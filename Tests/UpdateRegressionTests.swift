import Foundation

@main
struct UpdateRegressionTests {
    static func main() throws {
        precondition(ReleaseVersion("v0.1.10")! > ReleaseVersion("0.1.9")!)
        precondition(ReleaseVersion("1.0") == ReleaseVersion("1.0.0"))
        for invalid in ["", "v", "1..0", "1.0.0-beta", "-1.0.0", "1.2.3.4"] {
            precondition(ReleaseVersion(invalid) == nil)
        }
        func expect(_ condition: Bool) { precondition(condition) }
        func release(_ tag: String = "v0.2.0", draft: Bool = false, prerelease: Bool = false, asset: String = "Plupo-arm64.dmg") throws -> PublishedRelease {
            let data = try JSONSerialization.data(withJSONObject: [
                "tag_name": tag, "draft": draft, "prerelease": prerelease, "assets": [["name": asset]]
            ])
            return try JSONDecoder().decode(PublishedRelease.self, from: data)
        }
        try expect(release().newerVersion(than: "0.1.9") != nil)
        try expect(release().newerVersion(than: "0.2.0") == nil)
        try expect(release().newerVersion(than: "1.0") == nil)
        try expect(release(draft: true).newerVersion(than: "0.1.0") == nil)
        try expect(release(prerelease: true).newerVersion(than: "0.1.0") == nil)
        try expect(release(asset: "source.zip").newerVersion(than: "0.1.0") == nil)
        try expect(release("v0.2.0-beta").newerVersion(than: "0.1.0") == nil)
        print("Passed update version and release eligibility checks")
    }
}
