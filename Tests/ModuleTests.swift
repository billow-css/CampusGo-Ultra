import XCTest
@testable import CampusScheduleCore

final class ModuleTests: XCTestCase {
    func descriptor(_ id: String, surfaces: Set<ModuleSurface> = [.summary, .detail]) -> ModuleDescriptor {
        .init(id: id, name: id, description: "test", icon: "square", surfaces: surfaces)
    }
    func registry() throws -> ModuleRegistry { try ModuleRegistry([descriptor("mod.alpha"), descriptor("mod.beta")]) }
    func testRegistrationKeepsOrderAndMetadata() throws {
        let value = try registry()
        XCTAssertEqual(value.descriptors.map(\.id), ["mod.alpha", "mod.beta"])
        XCTAssertEqual(value.descriptor("mod.alpha")?.interfaceVersion, 1)
    }
    func testDuplicateIDsRejected() { XCTAssertThrowsError(try ModuleRegistry([descriptor("mod.alpha"), descriptor("mod.alpha")])) }
    func testInvalidIDsRejected() {
        for id in ["", "a", "../module", "mod/a", "mod]alpha", "mod.alpha\n", "MOD.alpha"] {
            XCTAssertThrowsError(try ModuleRegistry([descriptor(id)]), id)
        }
    }
    func testUnsupportedInterfaceRejected() {
        var value = descriptor("mod.alpha"); value.interfaceVersion = 99
        XCTAssertThrowsError(try ModuleRegistry([value]))
    }
    func testModuleNeedsPresentationSurface() { XCTAssertThrowsError(try ModuleRegistry([descriptor("mod.alpha", surfaces: [])])) }
    func testLayoutRemovesUnknownAndDuplicatePins() throws {
        let registry = try registry()
        var layout = ModuleLayout(enabled: ["mod.alpha": false, "gone": true], summaryOrder: ["mod.alpha", "gone", "mod.alpha", "mod.beta"])
        layout.normalize(registry: registry, defaults: ["mod.alpha": true, "mod.beta": true], initialPins: [])
        XCTAssertEqual(layout.summaryOrder, ["mod.alpha", "mod.beta"])
        XCTAssertEqual(layout.enabled, ["mod.alpha": false, "mod.beta": true])
    }
    func testInitialPinsAreNotReaddedOnRestore() throws {
        let registry = try registry()
        var layout = ModuleLayout()
        layout.normalize(registry: registry, defaults: [:], initialPins: ["mod.alpha"])
        layout.unpin("mod.alpha")
        var restored = try JSONDecoder().decode(ModuleLayout.self, from: JSONEncoder().encode(layout))
        restored.normalize(registry: registry, defaults: [:], initialPins: [])
        XCTAssertTrue(restored.summaryOrder.isEmpty)
    }
    func testDisabledModuleKeepsItsPinnedPositionButIsHidden() throws {
        let registry = try registry()
        var layout = ModuleLayout(); layout.pin("mod.alpha", registry: registry)
        layout.enabled["mod.alpha"] = false
        XCTAssertTrue(layout.visibleSummaryIDs.isEmpty)
        XCTAssertEqual(layout.summaryOrder, ["mod.alpha"])
        layout.enabled["mod.alpha"] = true
        XCTAssertEqual(layout.visibleSummaryIDs, ["mod.alpha"])
    }
    func testPinEnablesModuleAndDoesNotDuplicate() throws {
        let registry = try registry()
        var layout = ModuleLayout(enabled: ["mod.alpha": false])
        layout.pin("mod.alpha", registry: registry); layout.pin("mod.alpha", registry: registry)
        XCTAssertEqual(layout.visibleSummaryIDs, ["mod.alpha"])
    }
    func testUnpinDoesNotDisableFeature() throws {
        let registry = try registry(); var layout = ModuleLayout()
        layout.pin("mod.alpha", registry: registry); layout.unpin("mod.alpha")
        XCTAssertEqual(layout.enabled["mod.alpha"], true)
        XCTAssertTrue(layout.summaryOrder.isEmpty)
    }
    func testMoveForwardAndBackwardBothWork() throws {
        let registry = try registry(); var layout = ModuleLayout()
        layout.pin("mod.alpha", registry: registry); layout.pin("mod.beta", registry: registry)
        XCTAssertTrue(layout.move("mod.alpha", to: "mod.beta"))
        XCTAssertEqual(layout.summaryOrder, ["mod.beta", "mod.alpha"])
        XCTAssertTrue(layout.move("mod.alpha", to: "mod.beta"))
        XCTAssertEqual(layout.summaryOrder, ["mod.alpha", "mod.beta"])
    }
    func testUnknownAndSelfMovesAreNoOps() {
        var layout = ModuleLayout(summaryOrder: ["mod.alpha"]); let original = layout
        XCTAssertFalse(layout.move("mod.alpha", to: "mod.alpha"))
        XCTAssertFalse(layout.move("missing", to: "mod.alpha")); XCTAssertEqual(layout, original)
    }
    func testOverlayOnlyModuleCannotBePinned() throws {
        let registry = try ModuleRegistry([descriptor("mod.overlay", surfaces: [.overlay])]); var layout = ModuleLayout()
        layout.pin("mod.overlay", registry: registry)
        layout.normalize(registry: registry, defaults: [:], initialPins: ["mod.overlay"])
        XCTAssertTrue(layout.summaryOrder.isEmpty)
    }
    func testLayoutSerializationPreservesOrderAndEnableFlags() throws {
        let layout = ModuleLayout(enabled: ["mod.alpha": true, "mod.beta": false], summaryOrder: ["mod.beta", "mod.alpha"])
        XCTAssertEqual(try JSONDecoder().decode(ModuleLayout.self, from: JSONEncoder().encode(layout)), layout)
    }
    func withDefaults(_ action: (UserDefaults) throws -> Void) throws {
        let suite = "CampusGo.ModuleTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try action(defaults)
    }
    func testStorageIsIsolatedPerModule() throws {
        try withDefaults { defaults in
            let a = try ModuleStorage(moduleID: "mod.alpha", defaults: defaults)
            let b = try ModuleStorage(moduleID: "mod.beta", defaults: defaults)
            try a.save("alpha", key: "value"); try b.save("beta", key: "value")
            XCTAssertEqual(try a.load(String.self, key: "value"), "alpha")
            XCTAssertEqual(try b.load(String.self, key: "value"), "beta")
        }
    }
    func testNestedModuleIDsAndDottedKeysDoNotCollide() throws {
        try withDefaults { defaults in
            let a = try ModuleStorage(moduleID: "mod.alpha", defaults: defaults)
            let b = try ModuleStorage(moduleID: "mod.alpha.child", defaults: defaults)
            try a.save(1, key: "child.value"); try b.save(2, key: "value")
            XCTAssertEqual(try a.load(Int.self, key: "child.value"), 1)
            XCTAssertEqual(try b.load(Int.self, key: "value"), 2)
        }
    }
    func testStorageRemovalOnlyAffectsOwningModule() throws {
        try withDefaults { defaults in
            let a = try ModuleStorage(moduleID: "mod.alpha", defaults: defaults)
            let b = try ModuleStorage(moduleID: "mod.beta", defaults: defaults)
            try a.save([1,2], key: "values"); try b.save([3,4], key: "values")
            a.remove(key: "values")
            XCTAssertNil(try a.load([Int].self, key: "values"))
            XCTAssertEqual(try b.load([Int].self, key: "values"), [3,4])
        }
    }
    func testScopedStorageRejectsMalformedID() throws {
        try withDefaults { defaults in XCTAssertThrowsError(try ModuleStorage(moduleID: "bad]id", defaults: defaults)) }
    }
}
