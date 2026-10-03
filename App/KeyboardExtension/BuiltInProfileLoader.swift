import Foundation

enum BuiltInProfileLoader {
    static func loadJSON() throws -> String {
        guard let url = Bundle.main.url(forResource: "default-ja", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
