import Foundation

/// 发布到公众号草稿箱所需的配置。
///
/// 只有 AppSecret 走钥匙串，其余字段（AppID、标题、作者等）不敏感，放 UserDefaults。
struct PublishConfig: Codable, Equatable {

    /// 公众号 AppID，形如 wx1234567890abcdef
    var appID: String = ""
    /// 文章标题。留空则从正文里第一个一级标题自动推断
    var title: String = ""
    /// 作者，显示在标题下方
    var author: String = ""
    /// 摘要。留空则由微信自动截取正文前 54 字
    var digest: String = ""
    /// 「阅读原文」跳转地址
    var sourceURL: String = ""
    /// 封面图路径（本地文件）。draft/add 接口要求必须有封面
    var coverPath: String = ""
    /// 是否把正文里的外链图片上传到公众号再替换地址
    var localizeImages: Bool = true
    /// 是否在发布成功后自动打开公众号后台草稿箱
    var openDraftBoxAfterPublish: Bool = true

    /// 是否填了必填项
    var isReadyToPublish: Bool {
        !appID.trimmingCharacters(in: .whitespaces).isEmpty && !coverPath.isEmpty
    }
}

/// 发布过程的实时状态，供界面展示进度流水
struct PublishProgress {

    enum Level {
        case info, success, failure, warning

        var symbol: String {
            switch self {
            case .info:    return "·"
            case .success: return "✓"
            case .failure: return "✗"
            case .warning: return "!"
            }
        }
    }

    struct Line: Identifiable {
        let id = UUID()
        let level: Level
        let text: String
    }

    var lines: [Line] = []
    var isRunning = false
    /// 成功后的草稿 media_id
    var draftMediaID: String?

    mutating func log(_ text: String, level: Level = .info) {
        lines.append(Line(level: level, text: text))
    }

    mutating func reset() {
        lines = []
        draftMediaID = nil
    }
}

enum PublishConfigStore {

    private static let key = "publish.config.v1"

    static func load() -> PublishConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(PublishConfig.self, from: data)
        else { return PublishConfig() }
        return config
    }

    static func save(_ config: PublishConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
