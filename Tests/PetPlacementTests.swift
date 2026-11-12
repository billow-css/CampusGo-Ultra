import XCTest
@testable import CampusScheduleCore

final class PetPlacementTests: XCTestCase {
    func testDefaultIsBottomRightAndKeepsOriginalAspectRatio() {
        let frame = PetPlacement().frame(inWidth: 1240, height: 900)
        XCTAssertEqual(frame.x + frame.width, 1216, accuracy: 0.001)
        XCTAssertEqual(frame.y + frame.height, 876, accuracy: 0.001)
        XCTAssertEqual(frame.width / frame.height, 963.0 / 930.0, accuracy: 0.001)
    }
    func testCornerPresetsStayInsideWindowAndBelowNavigation() {
        for x in [0.0, 0.5, 1.0] {
            for y in [0.0, 0.5, 1.0] {
                let frame = PetPlacement(x: x, y: y, size: 240).frame(inWidth: 1080, height: 730)
                XCTAssertGreaterThanOrEqual(frame.x, 24)
                XCTAssertGreaterThanOrEqual(frame.y, 88)
                XCTAssertLessThanOrEqual(frame.x + frame.width, 1056.001)
                XCTAssertLessThanOrEqual(frame.y + frame.height, 706.001)
            }
        }
    }
    func testDragRoundTripsPositionWithoutJump() {
        let moved = PetPlacement().moved(toX: 300, y: 250, inWidth: 1240, height: 900)
        let frame = moved.frame(inWidth: 1240, height: 900)
        XCTAssertEqual(frame.x, 300, accuracy: 0.001)
        XCTAssertEqual(frame.y, 250, accuracy: 0.001)
    }
    func testDraggingOutsideClampsAtBothEdges() {
        let top = PetPlacement().moved(toX: -900, y: -1000, inWidth: 1240, height: 900)
        XCTAssertEqual(top.x, 0); XCTAssertEqual(top.y, 0)
        let bottom = PetPlacement().moved(toX: 9000, y: 9000, inWidth: 1240, height: 900)
        XCTAssertEqual(bottom.x, 1); XCTAssertEqual(bottom.y, 1)
    }
    func testWindowResizePreservesRelativePositionAndAvoidsClipping() {
        let placement = PetPlacement(x: 0.7, y: 0.8, size: 200)
        for area in [(1240.0,900.0),(1080.0,730.0),(400.0,300.0),(40.0,40.0),(1.0,1.0)] {
            let frame = placement.frame(inWidth: area.0, height: area.1)
            XCTAssertGreaterThanOrEqual(frame.x, 0)
            XCTAssertGreaterThanOrEqual(frame.y, 0)
            XCTAssertLessThanOrEqual(frame.x + frame.width, area.0 + 0.001)
            XCTAssertLessThanOrEqual(frame.y + frame.height, area.1 + 0.001)
        }
    }
    func testInvalidPreferencesAreNormalized() {
        let value = PetPlacement(x: .nan, y: -.infinity, size: .infinity).normalized
        XCTAssertEqual(value, PetPlacement())
        XCTAssertEqual(PetPlacement(x: -2, y: 5, size: 2).normalized, .init(x: 0, y: 1, size: 72))
        XCTAssertEqual(PetPlacement(size: 999).normalized.size, 240)
    }
    func testPlacementSerializationPreservesUserChoice() throws {
        let value = PetPlacement(x: 0.25, y: 0.75, size: 180)
        let restored = try JSONDecoder().decode(PetPlacement.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored, value)
    }
    func testCustomTallAndWideImagesFitAndDragWithoutJump() {
        for aspect in [0.2, 1.0, 5.0] {
            let placement = PetPlacement(x: 0.7, y: 0.6, size: 240)
            let frame = placement.frame(inWidth: 1080, height: 730, aspect: aspect)
            XCTAssertEqual(frame.width / frame.height, aspect, accuracy: 0.001)
            XCTAssertLessThanOrEqual(frame.x + frame.width, 1056.001)
            XCTAssertLessThanOrEqual(frame.y + frame.height, 706.001)
            let moved = placement.moved(toX: frame.x, y: frame.y, inWidth: 1080, height: 730, aspect: aspect)
            XCTAssertEqual(moved.x, placement.x, accuracy: 0.001)
            XCTAssertEqual(moved.y, placement.y, accuracy: 0.001)
        }
    }
    func testInvalidImageAspectFallsBackToDefault() {
        let fallback = PetPlacement().frame(inWidth: 1080, height: 730)
        for aspect in [0.0, -1, Double.nan, Double.infinity] {
            XCTAssertEqual(PetPlacement().frame(inWidth: 1080, height: 730, aspect: aspect), fallback)
        }
    }

}
