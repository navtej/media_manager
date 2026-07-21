import Cocoa
import FlutterMacOS
import XCTest
@testable import Media_Manager

class RunnerTests: XCTestCase {

  func testMinimumContentSizeMatchesPER33Contract() {
    XCTAssertEqual(MainFlutterWindow.minimumContentSize.width, 800)
    XCTAssertEqual(MainFlutterWindow.minimumContentSize.height, 600)
  }

}
