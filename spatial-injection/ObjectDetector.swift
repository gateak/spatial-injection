//
//  ObjectDetector.swift
//  spatial-injection
//
//  Created by Akbar Khamidov on 11/12/25.
//

import Vision
import CoreML
import ARKit

class ObjectDetector {
    private lazy var objectDetectionRequest: VNRecognizeObjectsRequest = {
        VNRecognizeObjectsRequest(completionHandler: { [weak self] request, error in
            guard let self = self else { return }
            if let results = request.results as? [VNRecognizedObjectObservation] {
                self.handleDetections(results)
            } else {
                self.handleDetections([])
            }
        })
    }()
    
    private var completionHandler: (([DetectedObject]) -> Void)?
    
    func detectObjects(in frame: ARFrame, completion: @escaping ([DetectedObject]) -> Void) {
        let pixelBuffer = frame.capturedImage
        let depthMap = frame.sceneDepth?.depthMap
        
        self.completionHandler = completion
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try handler.perform([self?.objectDetectionRequest].compactMap { $0 })
            } catch {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    private func handleDetections(_ observations: [VNRecognizedObjectObservation]) {
        guard let completion = completionHandler else { return }
        
        // We do this on a background queue to avoid blocking Vision
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var detectedObjects: [DetectedObject] = []
            
            for observation in observations where observation.confidence > 0.7 {
                let boundingBox = observation.boundingBox
                let xNorm = boundingBox.midX
                let yNorm = boundingBox.midY
                
                var zMeters: Float = 0
                
                if let depthMap = self.latestDepthMap {
                    // Convert normalized coordinates to pixel coordinates in depth map space
                    let width = CVPixelBufferGetWidth(depthMap)
                    let height = CVPixelBufferGetHeight(depthMap)
                    let pixelX = Int(self.clamp(Int(round(xNorm * Float(width))), 0, width - 1))
                    let pixelY = Int(self.clamp(Int(round((1 - yNorm) * Float(height))), 0, height - 1))
                    zMeters = self.sampleDepth(atX: pixelX, y: pixelY, from: depthMap)
                }
                
                let label = observation.labels.first?.identifier ?? "unknown"
                
                detectedObjects.append(
                    DetectedObject(
                        label: label,
                        position: simd_float3(xNorm, yNorm, zMeters),
                        boundingBox: nil,
                        confidence: observation.confidence
                    )
                )
            }
            
            DispatchQueue.main.async {
                completion(detectedObjects)
            }
        }
    }
    
    // Store latest depth map for sampling during detection
    private var latestDepthMap: CVPixelBuffer?
    
    private func sampleDepth(atX x: Int, y: Int, from depthMap: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return 0 }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        
        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
            let index = y * (rowBytes / MemoryLayout<Float32>.size) + x
            if index >= 0 && index < width * height {
                let depthValue = floatBuffer[index]
                return max(0, depthValue)
            }
        }
        
        return 0
    }
    
    private func clamp<T: Comparable>(_ value: T, _ min: T, _ max: T) -> T {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}

