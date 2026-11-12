import Foundation

struct PetFrame: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct PetPlacement: Codable, Equatable {
    var x = 1.0
    var y = 1.0
    var size = 136.0
    static let aspect = 963.0 / 930.0
    var normalized: PetPlacement {
        .init(x: x.isFinite ? min(1, max(0, x)) : 1,
              y: y.isFinite ? min(1, max(0, y)) : 1,
              size: size.isFinite ? min(240, max(72, size)) : 136)
    }
    func frame(inWidth width: Double, height: Double, aspect: Double = Self.aspect) -> PetFrame {
        let aspect = aspect.isFinite && aspect > 0 ? aspect : Self.aspect
        let areaWidth = width.isFinite ? max(1, width) : 1
        let areaHeight = height.isFinite ? max(1, height) : 1
        let margin = min(24, areaWidth / 4, areaHeight / 4)
        let top = min(64, max(0, areaHeight - margin * 2 - 1))
        let placement = normalized
        let petWidth = min(placement.size, max(0.001, areaWidth - margin * 2), max(0.001, areaHeight - top - margin * 2) * aspect)
        let petHeight = petWidth / aspect
        let travelX = max(0, areaWidth - margin * 2 - petWidth)
        let travelY = max(0, areaHeight - top - margin * 2 - petHeight)
        return .init(x: margin + travelX * placement.x, y: top + margin + travelY * placement.y,
                     width: petWidth, height: petHeight)
    }
    func moved(toX x: Double, y: Double, inWidth width: Double, height: Double, aspect: Double = Self.aspect) -> PetPlacement {
        var first = normalized; first.x = 0; first.y = 0
        var last = first; last.x = 1; last.y = 1
        let a = first.frame(inWidth: width, height: height, aspect: aspect)
        let b = last.frame(inWidth: width, height: height, aspect: aspect)
        return PetPlacement(x: b.x > a.x ? (x - a.x) / (b.x - a.x) : normalized.x,
                            y: b.y > a.y ? (y - a.y) / (b.y - a.y) : normalized.y, size: normalized.size).normalized
    }
}
