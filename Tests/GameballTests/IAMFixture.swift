import Foundation
import XCTest

/// Loads a JSON fixture from the test bundle.
///
/// Fixtures are copied into this repository rather than read from a sibling checkout,
/// so the suite never depends on `gameball-flutter` being present.
enum IAMFixture {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            XCTFail("fixture \(name).json not found in the test bundle")
            return Data()
        }
        return data
    }
}
