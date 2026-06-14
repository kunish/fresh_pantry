import Foundation
import Testing
@testable import FreshPantry

/// Cook Mode 步骤时长的人类可读标签 + 倒计时 mm:ss 格式化(纯函数)。
struct CookStepTimerTests {
    @Test func labelUsesSecondsUnderAMinute() {
        #expect(CookStepTimer.label(seconds: 30) == "30 秒")
        #expect(CookStepTimer.label(seconds: 1) == "1 秒")
    }

    @Test func labelUsesWholeMinutes() {
        #expect(CookStepTimer.label(seconds: 180) == "3 分钟")
        #expect(CookStepTimer.label(seconds: 60) == "1 分钟")
    }

    @Test func labelMixesMinutesAndSeconds() {
        #expect(CookStepTimer.label(seconds: 90) == "1 分 30 秒")
        #expect(CookStepTimer.label(seconds: 125) == "2 分 5 秒")
    }

    @Test func countdownFormatsMinutesAndSeconds() {
        #expect(CookStepTimer.countdown(remaining: 125) == "02:05")
        #expect(CookStepTimer.countdown(remaining: 0) == "00:00")
        #expect(CookStepTimer.countdown(remaining: 600) == "10:00")
    }

    @Test func countdownClampsNegativeToZero() {
        #expect(CookStepTimer.countdown(remaining: -5) == "00:00")
    }
}
