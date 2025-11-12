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
