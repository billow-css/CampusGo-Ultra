import Foundation

enum ModuleSurface: String, Codable, Hashable { case summary, detail, settings, overlay }
enum ModulePermission: String, Codable, Hashable { case readCourses, readHomework, readTodos, createTodo, writeHomework }
struct ModuleDescriptor: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    var version = "1.0.0"
    var interfaceVersion = 1
    var surfaces: Set<ModuleSurface>
    var permissions: Set<ModulePermission> = []
}
enum ModuleError: LocalizedError {
    case invalidIdentifier, duplicateIdentifier, unsupportedInterface, noSurface, unavailable, missingPermission
    var errorDescription: String? {
        switch self {
        case .invalidIdentifier: return "模块标识格式无效。"
        case .duplicateIdentifier: return "模块标识重复。"
        case .unsupportedInterface: return "模块接口版本不受支持。"
        case .noSurface: return "模块未提供展示入口。"
        case .unavailable: return "模块当前不可用。"
        case .missingPermission: return "模块未声明所需的数据能力。"
        }
    }
}
struct ModuleRegistry {
    static let interfaceVersion = 1
    let descriptors: [ModuleDescriptor]
    static func validID(_ id: String) -> Bool {
        guard let match = id.range(of: "^[a-z][a-z0-9._-]{2,79}$", options: .regularExpression) else { return false }
        return match == (id.startIndex..<id.endIndex)
    }
    init(_ descriptors: [ModuleDescriptor]) throws {
        var ids = Set<String>()
        for descriptor in descriptors {
            guard Self.validID(descriptor.id) else { throw ModuleError.invalidIdentifier }
            guard ids.insert(descriptor.id).inserted else { throw ModuleError.duplicateIdentifier }
            guard descriptor.interfaceVersion == Self.interfaceVersion else { throw ModuleError.unsupportedInterface }
            guard !descriptor.surfaces.isEmpty else { throw ModuleError.noSurface }
        }
        self.descriptors = descriptors
    }
    func descriptor(_ id: String) -> ModuleDescriptor? { descriptors.first { $0.id == id } }
}
struct ModuleLayout: Codable, Equatable {
    var enabled: [String: Bool] = [:]
    var summaryOrder: [String] = []
    mutating func normalize(registry: ModuleRegistry, defaults: [String: Bool], initialPins: [String]) {
        let valid = Set(registry.descriptors.map(\.id))
        enabled = enabled.filter { valid.contains($0.key) }
        for descriptor in registry.descriptors where enabled[descriptor.id] == nil {
            enabled[descriptor.id] = defaults[descriptor.id] ?? true
        }
        var seen = Set<String>()
        summaryOrder = summaryOrder.filter {
            registry.descriptor($0)?.surfaces.contains(.summary) == true && seen.insert($0).inserted
        }
        // Initial pins are supplied only for a first-time layout, never on every restart.
        for id in initialPins where registry.descriptor(id)?.surfaces.contains(.summary) == true && !summaryOrder.contains(id) {
            summaryOrder.append(id)
        }
    }
    var visibleSummaryIDs: [String] { summaryOrder.filter { enabled[$0] == true } }
    mutating func pin(_ id: String, registry: ModuleRegistry) {
        guard registry.descriptor(id)?.surfaces.contains(.summary) == true else { return }
        enabled[id] = true
        if !summaryOrder.contains(id) { summaryOrder.append(id) }
    }
    mutating func unpin(_ id: String) { summaryOrder.removeAll { $0 == id } }
    @discardableResult
    mutating func move(_ id: String, to target: String) -> Bool {
        guard id != target, let from = summaryOrder.firstIndex(of: id), let to = summaryOrder.firstIndex(of: target) else { return false }
        summaryOrder.remove(at: from)
        summaryOrder.insert(id, at: min(to, summaryOrder.count))
        return true
    }
}
struct ModuleStorage {
    private let defaults: UserDefaults
    private let prefix: String
    init(moduleID: String, defaults: UserDefaults = .standard) throws {
        guard ModuleRegistry.validID(moduleID) else { throw ModuleError.invalidIdentifier }
        self.defaults = defaults
        // Brackets make nested IDs and dotted keys unambiguous across modules.
        prefix = "campus.module-data[" + moduleID + "]."
    }
    func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        guard let data = defaults.data(forKey: prefix + key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
    func save<T: Encodable>(_ value: T, key: String) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: prefix + key)
    }
    func remove(key: String) { defaults.removeObject(forKey: prefix + key) }
}
