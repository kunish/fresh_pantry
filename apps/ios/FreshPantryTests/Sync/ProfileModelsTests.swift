import Foundation
import Testing
@testable import FreshPantry

struct ProfileModelsTests {
    @Test func decodesSnakeCaseRowWithDefaults() throws {
        let json = """
        {"id":"u1","email":"a@b.com","display_name":"小明","nickname":"明明","avatar_path":"u1/x.jpg"}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(p.id == "u1")
        #expect(p.displayName == "小明")
        #expect(p.nickname == "明明")
        #expect(p.avatarPath == "u1/x.jpg")
    }

    @Test func missingOptionalFieldsDefaultToEmpty() throws {
        let json = """
        {"id":"u2","email":"c@d.com","display_name":"阿花"}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(p.nickname == "")
        #expect(p.avatarPath == "")
    }
}
