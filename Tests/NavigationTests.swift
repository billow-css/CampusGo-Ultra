import XCTest
@testable import CampusScheduleCore

final class NavigationTests: XCTestCase {
    func testAllTabsAreVisibleByDefault() {
        let preferences = NavigationPreferences()
        for id in ["home", "schedule", "work", "discover", "nav.campus.gosci"] { XCTAssertTrue(preferences.isVisible(id)) }
    }
    func testSummaryAndScheduleCannotBeHidden() {
        var preferences = NavigationPreferences()
        preferences.setVisible("home", false); preferences.setVisible("schedule", false)
        XCTAssertTrue(preferences.isVisible("home")); XCTAssertTrue(preferences.isVisible("schedule"))
        XCTAssertTrue(preferences.hiddenTabs.isEmpty)
    }
    func testSavedFixedHiddenIDsCannotRemoveCoreTabs() throws {
        let preferences = try JSONDecoder().decode(NavigationPreferences.self, from: Data(#"{"hiddenTabs":["home","schedule","work"]}"#.utf8))
        XCTAssertTrue(preferences.isVisible("home")); XCTAssertTrue(preferences.isVisible("schedule"))
        XCTAssertFalse(preferences.isVisible("work"))
    }
    func testOptionalVisibilityRoundTripAndRestore() throws {
        var preferences = NavigationPreferences()
        for id in ["work", "discover", "nav.campus.gosci"] { preferences.setVisible(id, false) }
        var restored = try JSONDecoder().decode(NavigationPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored, preferences)
        restored.setVisible("work", true)
        XCTAssertTrue(restored.isVisible("work")); XCTAssertFalse(restored.isVisible("discover"))
    }
    func testHidingCurrentTabReturnsToScheduleWithoutAffectingOtherPages() {
        var preferences = NavigationPreferences()
        preferences.setVisible("work", false); preferences.setVisible("nav.campus.gosci", false)
        XCTAssertEqual(preferences.resolvedPage("work"), "schedule")
        XCTAssertEqual(preferences.resolvedPage("nav.campus.gosci"), "schedule")
        XCTAssertEqual(preferences.resolvedPage("home"), "home")
        XCTAssertEqual(preferences.resolvedPage("discover"), "discover")
    }
    func testModuleOpenedFromSummaryRemainsUsableWhenItsTabIsHidden() {
        var preferences = NavigationPreferences()
        preferences.setVisible("discover", false); preferences.setVisible("nav.campus.gosci", false)
        XCTAssertEqual(preferences.resolvedPage("module", moduleOrigin: "home"), "module")
        XCTAssertEqual(preferences.resolvedPage("module", moduleOrigin: "discover"), "schedule")
        XCTAssertEqual(preferences.resolvedPage("module", moduleOrigin: "nav.campus.gosci"), "schedule")
    }
}
