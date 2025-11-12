import simd

/// Hackathon utility for simple measurement calculations
struct MeasurementCalculator {
    static func estimatePersonReach(heightMeters: Float) -> Float {
        return heightMeters + 0.65
    }
    
    static func doorStandardWidthMeters() -> Float {
        return 0.91 // 36 inches
    }
    
    static func canReach(targetHeight: Float, personHeight: Float) -> Bool {
        estimatePersonReach(heightMeters: personHeight) >= targetHeight
    }
}
