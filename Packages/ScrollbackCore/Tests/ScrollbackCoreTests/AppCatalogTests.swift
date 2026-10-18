import Testing
@testable import ScrollbackCore

@Suite struct AppCatalogTests {
    @Test(arguments: ["com.example.scrollback", "com.example.scrollback.mac", "org.someone.scrollback.macos"])
    func namesScrollbackWhateverThePrefix(_ bundleID: String) {
        #expect(AppCatalog.name(for: bundleID) == "Scrollback")
    }

    @Test func fallsBackToTheLastPartOfTheBundleID() {
        #expect(AppCatalog.name(for: "com.example.weather") == "Weather")
        #expect(AppCatalog.category(for: "com.example.weather") == .other)
    }
}
