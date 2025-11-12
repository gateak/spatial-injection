//
//  SpatialDataExtractor.swift
//  spatial-injection
//
//  Created by Akbar Khamidov on 11/12/25.
//

import ARKit
import RealityKit
import Vision

struct SpatialContext {
    var objects: [DetectedObject] = []
    var distances: [String: Float] = [:]
    var planes: [DetectedPlane] = []
    
    // Convert to LLM-friendly format
    func toLLMPrompt() -> String {
        var prompt = "SPATIAL_CONTEXT:\n"
        
        // Add distances
        prompt += "DISTANCES:\n"
        for (key, value) in distances {
            prompt += "- \(key): \(String(format: "%.2f", value))m\n"
        }
        
        // Add detected objects
        prompt += "\nOBJECTS:\n"
        for obj in objects {
            prompt += "- \(obj.label) at position (\(String(format: "%.2f", obj.position.x)), \(String(format: "%.2f", obj.position.y)), \(String(format: "%.2f", obj.position.z)))m\n"
            if let size = obj.boundingBox {
                prompt += "  size: \(String(format: "%.2f", size.x))m x \(String(format: "%.2f", size.y))m x \(String(format: "%.2f", size.z))m\n"
            }
        }
        
        // Add planes (walls, floors, tables)
        prompt += "\nSURFACES:\n"
        for plane in planes {
            prompt += "- \(plane.classification): \(String(format: "%.2f", plane.width))m x \(String(format: "%.2f", plane.height))m\n"
        }
        
        return prompt
    }
    
    func toSummary() -> String {
        var lines: [String] = []
        // Basic distances
        if let center = distances["center_point"] {
            lines.append(String(format: "Center distance: %.2fm", center))
        }
        // Simple heuristics for reachability and clearance
        let personHeights: [Float] = objects.filter { $0.label == "person" }.map { _ in 1.7 }
        let maxReach = personHeights.map { MeasurementCalculator.estimatePersonReach(heightMeters: $0) }.max() ?? 0
        // Infer a shelf height from any object labeled 'shelf' using its z as distance; we don't have height, so treat z as distance and make a conservative guess
        // For demo: if we have a plane classified as 'table' or 'ceiling', create simple statements
        if maxReach > 0 {
            lines.append(String(format: "Max human reach (est.): %.2fm", maxReach))
        }
        // List detected objects with approximate distance (z)
        for obj in objects {
            lines.append(String(format: "%@ at ~%.2fm away (conf: %.0f%%)", obj.label, obj.position.z, obj.confidence * 100))
        }
        // Surfaces summary
        for plane in planes {
            lines.append(String(format: "Surface: %@ (%.2fm x %.2fm)", plane.classification, plane.width, plane.height))
        }
        // Opinionated conclusion examples
        if maxReach > 0 {
            // If any object named 'shelf' exists, assume shelf height 2.4m for demo
            let hasShelf = objects.contains { $0.label == "shelf" }
            if hasShelf {
                let shelfHeight: Float = 2.4
                let canReach = MeasurementCalculator.canReach(targetHeight: shelfHeight, personHeight: 1.7)
                lines.append(canReach ? "A person can likely reach the shelf (2.4m)." : "A person likely cannot reach the 2.4m shelf without a ladder.")
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct DetectedObject {
    let label: String
    let position: simd_float3
    let boundingBox: simd_float3?
    let confidence: Float
}

struct DetectedPlane {
    let classification: String
    let width: Float
    let height: Float
    let center: simd_float3
}
