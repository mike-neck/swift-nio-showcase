import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(swift_nio_showcaseTests.allTests),
    ]
}
#endif