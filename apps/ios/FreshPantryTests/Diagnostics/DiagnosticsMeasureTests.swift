import Foundation
import Testing
@testable import FreshPantry

/// `Diagnostics.measure` 默认实现的行为:成功/失败两路各发什么、是否透传错误。
struct DiagnosticsMeasureTests {
    private struct Boom: Error {}

    @Test func measureSuccessEmitsStartAndOkBreadcrumbs() async throws {
        let spy = SpyDiagnostics()
        let value = try await spy.measure("scan.lookup", ["source": "off"]) { 42 }

        #expect(value == 42)
        #expect(spy.breadcrumbNames == ["scan.lookup.start", "scan.lookup"])
        #expect(spy.failures.isEmpty)
        let ok = spy.breadcrumbs.last!
        #expect(ok.tags["outcome"] == "ok")
        #expect(ok.tags["source"] == "off")
        #expect(ok.tags["durationMs"] != nil)
    }

    @Test func measureFailureRethrowsAndRecordsFailure() async {
        let spy = SpyDiagnostics()
        await #expect(throws: Boom.self) {
            try await spy.measure("scan.lookup", ["source": "off"]) { throw Boom() }
        }

        // 失败路径:start + 一条带 outcome=fail 的 breadcrumb,外加一条 failure。
        #expect(spy.breadcrumbNames == ["scan.lookup.start", "scan.lookup"])
        #expect(spy.failureNames == ["scan.lookup"])
        let f = spy.failures.first!
        #expect(f.tags["outcome"] == "fail")
        #expect(f.tags["errorClass"] == "Boom")
        #expect(f.errorClass == "Boom")
    }
}
