import Foundation

/// 公众号开放接口返回的业务错误。
///
/// 微信的错误码相当隐晦，常见的几个如果只把 errmsg 抛给用户基本没法排查，
/// 这里统一补上「去哪儿改」。
struct WeChatAPIError: LocalizedError {

    let code: Int
    let message: String

    var errorDescription: String? {
        switch code {
        case 40001, 40125:
            return "AppSecret 不正确（errcode \(code)）"
        case 40164:
            return "当前网络 IP 不在公众号白名单内"
        case 41001:
            return "缺少 access_token"
        case 42001:
            return "access_token 已过期"
        case 40007:
            return "素材 ID 不合法（errcode 40007）"
        case 45009:
            return "接口调用超过当日限额"
        case 48001:
            return "该账号没有草稿箱接口权限"
        case 53500, 45007:
            return "草稿数量已达上限，先去后台删几篇"
        case -1:
            return "微信服务端系统繁忙，稍后重试"
        default:
            return "微信接口返回错误（errcode \(code)）"
        }
    }

    var recoverySuggestion: String? {
        switch code {
        case 40001, 40125:
            return "去「公众号后台 → 设置与开发 → 基本配置」重新复制 AppSecret。"
                + "注意 AppSecret 只在生成时显示一次，忘了就重置。"
        case 40164:
            // 微信会在 errmsg 里带上具体 IP，直接透传给用户最好用
            let ip = message.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
                .filter { $0.filter({ $0 == "." }).count == 3 }
                .first
            return "去「公众号后台 → 设置与开发 → 基本配置 → IP 白名单」把 "
                + (ip.map { "\($0) " } ?? "你的公网 IP ")
                + "加进去。动态 IP 每次变更都要重新添加；用服务器发布的话填服务器的固定 IP。"
        case 48001:
            return "草稿箱接口需要已认证的公众号。未认证的订阅号没有这个权限，"
                + "只能走「复制到剪贴板 → 手动粘贴到编辑器」。"
        default:
            return nil
        }
    }

    /// 拼成一行完整提示，供界面直接展示
    var fullText: String {
        if let hint = recoverySuggestion {
            return "\(errorDescription ?? message)\n\(hint)"
        }
        return message.isEmpty ? "未知错误（errcode \(code)）" : message
    }
}

/// 一篇草稿
struct DraftArticle {
    var title: String
    var author: String
    var digest: String
    var content: String
    var sourceURL: String
    var thumbMediaID: String

    var jsonObject: [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "content": content,
            "thumb_media_id": thumbMediaID,
            "need_open_comment": 0,
            "only_fans_can_comment": 0,
        ]
        // 空字段不传，让微信用自己的默认行为
        if !author.isEmpty { dict["author"] = author }
        if !digest.isEmpty { dict["digest"] = digest }
        if !sourceURL.isEmpty { dict["content_source_url"] = sourceURL }
        return dict
    }
}

/// 公众号开放接口客户端。
///
/// 用 actor 保证 access_token 缓存不会被并发读写搅乱 —— 微信对 token 的获取有频率限制，
/// 反复刷新会把当日额度烧掉。
actor WeChatClient {

    private let appID: String
    private let secret: String

    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    private let base = "https://api.weixin.qq.com"
    private let session: URLSession

    init(appID: String, secret: String) {
        self.appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - access_token

    /// 拿 access_token。微信给的有效期是 7200 秒，这里提前 5 分钟过期以便自动续期。
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let token = cachedToken, Date() < tokenExpiry {
            return token
        }

        guard !appID.isEmpty, !secret.isEmpty else {
            throw WeChatAPIError(code: 40001, message: "AppID 或 AppSecret 为空")
        }

        var components = URLComponents(string: "\(base)/cgi-bin/token")!
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credential"),
            URLQueryItem(name: "appid", value: appID),
            URLQueryItem(name: "secret", value: secret),
        ]

        let json = try await getJSON(components.url!)
        let token = try extract(json, key: "access_token")

        cachedToken = token
        let expires = (json["expires_in"] as? Double) ?? 7200
        tokenExpiry = Date().addingTimeInterval(max(60, expires - 300))
        return token
    }

    /// 清掉缓存，下次强制重新获取
    func invalidateToken() {
        cachedToken = nil
        tokenExpiry = .distantPast
    }

    // MARK: - 图片

    /// 上传正文里的图片，返回可直接用在文章里的 mmbiz 地址。
    /// 微信要求 jpg/png、单张不超过 1MB。
    func uploadContentImage(data: Data, filename: String) async throws -> String {
        let token = try await accessToken()
        let url = URL(string: "\(base)/cgi-bin/media/uploadimg?access_token=\(token)")!

        let json = try await postMultipart(url: url, fileField: "media", data: data, filename: filename)
        return try extract(json, key: "url")
    }

    /// 上传封面图，返回永久素材 media_id。draft/add 要求封面必须是永久素材。
    func uploadCoverImage(data: Data, filename: String) async throws -> String {
        let token = try await accessToken()
        let url = URL(string: "\(base)/cgi-bin/material/add_material?access_token=\(token)&type=image")!

        let json = try await postMultipart(url: url, fileField: "media", data: data, filename: filename)
        return try extract(json, key: "media_id")
    }

    // MARK: - 草稿

    @discardableResult
    func addDraft(_ article: DraftArticle) async throws -> String {
        let token = try await accessToken()
        let url = URL(string: "\(base)/cgi-bin/draft/add?access_token=\(token)")!

        let body = try JSONSerialization.data(withJSONObject: ["articles": [article.jsonObject]])
        let json = try await postJSON(url: url, body: body)
        return try extract(json, key: "media_id")
    }

    // MARK: - HTTP

    private func getJSON(_ url: URL) async throws -> [String: Any] {
        let (data, response) = try await session.data(from: url)
        return try decode(data: data, response: response)
    }

    private func postJSON(url: URL, body: Data) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        return try decode(data: data, response: response)
    }

    private func postMultipart(url: URL, fileField: String, data: Data, filename: String) async throws -> [String: Any] {
        let boundary = "----MPStyle\(UUID().uuidString)"
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(Self.mimeType(for: filename))\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        return try decode(data: responseData, response: response)
    }

    private func decode(data: Data, response: URLResponse) throws -> [String: Any] {
        guard let http = response as? HTTPURLResponse else {
            throw WeChatAPIError(code: -1, message: "没有收到 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeChatAPIError(code: http.statusCode,
                                 message: "HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw WeChatAPIError(code: -1, message: "响应不是合法 JSON：\(text.prefix(200))")
        }
        // 微信成功时也可能带 errcode: 0
        if let code = json["errcode"] as? Int, code != 0 {
            // token 失效时顺手清缓存，下一次调用会自动重新获取
            if code == 40001 || code == 42001 { invalidateToken() }
            throw WeChatAPIError(code: code, message: (json["errmsg"] as? String) ?? "")
        }
        return json
    }

    private func extract(_ json: [String: Any], key: String) throws -> String {
        guard let value = json[key] as? String, !value.isEmpty else {
            throw WeChatAPIError(code: -1, message: "响应里没有 \(key) 字段")
        }
        return value
    }

    private static func mimeType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "png":  return "image/png"
        case "gif":  return "image/gif"
        case "webp": return "image/webp"
        default:     return "image/jpeg"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
