import XCTest
@testable import ZdramaCore

final class SmokeTests: XCTestCase {
    func testCoreModuleLoads() {
        XCTAssertEqual(ZdramaCore.moduleName, "ZdramaCore")
    }
}
