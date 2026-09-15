import Foundation
import XCTest

/// Loads a JSON fixture from the test bundle.
///
/// Fixtures are copied into this repository rather than read from a sibling checkout,
/// so the suite never depends on `gameball-flutter` being present.
enum IAMFixture {
    static func data(_ name: String) -> Data {
        // `Package.swift` declares `.copy("Fixtures")`, which preserves the directory
        // inside the resource bundle, so the file is at `Fixtures/<name>.json` and a
        // root-level lookup finds nothing. `.copy` is the right declaration — a captured
        // payload must land byte-identical rather than be processed — so the subdirectory
        // is named here. The root is still tried, so switching to `.process` later, which
        // flattens, would not break this.
        let url = Bundle.module.url(forResource: name,
                                    withExtension: "json",
                                    subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")

        guard let resolved = url, let data = try? Data(contentsOf: resolved) else {
            XCTFail("fixture \(name).json not found in the test bundle")
            return Data()
        }
        return data
    }
}
