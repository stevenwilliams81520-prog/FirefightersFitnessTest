import Foundation

/// Step heights supported by the Chester Step Test.
enum StepHeight: Int, CaseIterable, Identifiable {
    case cm15 = 15, cm20 = 20, cm25 = 25, cm30 = 30

    var id: Int { rawValue }

    /// Oxygen cost (ml/kg/min) of stages 1–5 at this step height.
    var costs: [Double] {
        switch self {
        case .cm15: return [11, 14, 18, 21, 25]
        case .cm20: return [12, 17, 21, 25, 29]
        case .cm25: return [14, 19, 24, 28, 33]
        case .cm30: return [16, 21, 27, 32, 37]
        }
    }
}

enum Chester {
    static let stepRates = [15, 20, 25, 30, 35]   // steps per minute, stages 1–5
    static let stageSeconds: Double = 120
    static let standard = 42.3                    // UK firefighter fitness standard, ml/kg/min

    static func maxHR(age: Int) -> Int { 220 - age }
    static func stopHR(age: Int) -> Int { Int((Double(maxHR(age: age)) * 0.8).rounded()) }

    struct Result: Equatable {
        var vo2max: Double
        var slope: Double
        var intercept: Double
        var pointsUsed: Int
        var r2: Double
    }

    /// Line of best fit through (oxygen cost, heart rate), extended to age-predicted max heart rate.
    static func estimate(age: Int, height: StepHeight, stageHR: [Int?]) -> Result? {
        let costs = height.costs
        var pts: [(x: Double, y: Double)] = []
        for i in 0..<min(5, stageHR.count) {
            if let hr = stageHR[i], hr > 0 { pts.append((costs[i], Double(hr))) }
        }
        guard pts.count >= 2 else { return nil }
        let n = Double(pts.count)
        let mx = pts.reduce(0) { $0 + $1.x } / n
        let my = pts.reduce(0) { $0 + $1.y } / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for p in pts {
            sxy += (p.x - mx) * (p.y - my)
            sxx += (p.x - mx) * (p.x - mx)
            syy += (p.y - my) * (p.y - my)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        guard slope > 0 else { return nil }
        let intercept = my - slope * mx
        let vo2 = (Double(maxHR(age: age)) - intercept) / slope
        let r2 = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1
        return Result(vo2max: vo2, slope: slope, intercept: intercept, pointsUsed: pts.count, r2: r2)
    }
}
