import Foundation

/// Cook Mode 步骤时长的展示格式化(纯函数):时长标签 + 倒计时 mm:ss。时长数据由
/// pipeline 从步骤文本预解析(见 `Recipe.stepDurations`),端上只负责呈现,不正则。
enum CookStepTimer {
    /// "30 秒" / "3 分钟" / "1 分 30 秒"——步骤时长的人类可读标签(负数夹到 0)。
    static func label(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s) 秒" }
        let minutes = s / 60
        let rem = s % 60
        if rem == 0 { return "\(minutes) 分钟" }
        return "\(minutes) 分 \(rem) 秒"
    }

    /// "02:05"——倒计时剩余的 mm:ss(负数夹到 0)。
    static func countdown(remaining: Int) -> String {
        let r = max(0, remaining)
        return String(format: "%02d:%02d", r / 60, r % 60)
    }
}
