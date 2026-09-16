import Foundation

/// 十六进制颜色工具。纯 Foundation，无 UI 框架依赖。
enum HexColor {

    /// 归一化为 `#RRGGBB` / `#RRGGBBAA` 形式；非法输入回退为 `#000000`
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 || s.count == 8,
              s.allSatisfy({ $0.isHexDigit })
        else { return "#000000" }
        return "#" + s
    }

    /// 解析为 0...1 的 RGB 分量。忽略 alpha。
    static func components(_ raw: String) -> (r: Double, g: Double, b: Double) {
        let s = normalize(raw).dropFirst()
        guard s.count >= 6 else { return (0, 0, 0) }
        let chars = Array(s)
        func byte(_ i: Int) -> Double {
            let hi = chars[i], lo = chars[i + 1]
            let v = Int(String(hi), radix: 16).map { $0 * 16 } ?? 0
            let w = Int(String(lo), radix: 16) ?? 0
            return Double(v + w) / 255.0
        }
        return (byte(0), byte(2), byte(4))
    }

    /// 两个颜色按比例混合。`ratio` 为 0 时返回 `a`，为 1 时返回 `b`。
    static func mix(_ a: String, _ b: String, ratio: Double) -> String {
        let t = min(max(ratio, 0), 1)
        let ca = components(a), cb = components(b)
        let r = ca.r + (cb.r - ca.r) * t
        let g = ca.g + (cb.g - ca.g) * t
        let bl = ca.b + (cb.b - ca.b) * t
        return hex(r, g, bl)
    }

    /// 淡化到白色：`amount` 为混入的白色比例，0 保持原色，1 变为纯白。
    static func fade(_ hex: String, to amount: Double) -> String {
        mix(hex, "#FFFFFF", ratio: amount)
    }

    /// 输出 rgba()，用于阴影等需要透明度的场景
    static func rgba(_ hex: String, alpha: Double) -> String {
        let c = components(hex)
        let a = min(max(alpha, 0), 1)
        return "rgba(\(Int((c.r * 255).rounded())), \(Int((c.g * 255).rounded())), \(Int((c.b * 255).rounded())), \(trim(a)))"
    }

    static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    private static func trim(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return "\(Int(r))" }
        return "\(r)"
    }
}
