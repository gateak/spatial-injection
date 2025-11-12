//
//  ObjectDetector.swift
//  spatial-injection
//
//  Created by Akbar Khamidov on 11/12/25.
//

import Vision
import CoreML
import ARKit

#if canImport(CoreML)
private func makeYOLOModel() -> VNCoreMLModel? {
    try? VNCoreMLModel(for: YOLOv3().model)
}
#else
private func makeYOLOModel() -> VNCoreMLModel? {
    return nil
}
#endif

class ObjectDetector {
    public private(set) var lastObservations: [VNRecognizedObjectObservation] = []
    
    private lazy var request: VNRequest = {
        let completionHandler: VNRequestCompletionHandler = { [weak self] request, error in
            guard let self = self else { return }
            if let results = request.results as? [VNRecognizedObjectObservation] {
                self.handleDetections(results)
            } else {
                self.handleDetections([])
            }
        }
        
        if let yoloModel = makeYOLOModel() {
            return VNCoreMLRequest(model: yoloModel, completionHandler: completionHandler)
        } else {
            // Fallback: create a dummy VNRequest that immediately completes with no results
            let fallback = VNRequest { _, _ in
                completionHandler(VNRequest(), nil)
            }
            return fallback
        }
    }()
    
    private var completionHandler: (([DetectedObject]) -> Void)?
    
    // Store latest depth map for sampling during detection
    private var latestDepthMap: CVPixelBuffer?
    private var latestImageSize: CGSize?
    
    func detectObjects(in frame: ARFrame, completion: @escaping ([DetectedObject]) -> Void) {
        let pixelBuffer = frame.capturedImage
        let depthMap = frame.sceneDepth?.depthMap
        
        self.completionHandler = completion
        self.latestDepthMap = depthMap
        self.latestImageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                      height: CVPixelBufferGetHeight(pixelBuffer))
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try handler.perform([self?.request].compactMap { $0 })
            } catch {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }
    
    private func handleDetections(_ observations: [VNRecognizedObjectObservation]) {
        guard let completion = completionHandler else { return }
        
        self.lastObservations = observations
        
        // We do this on a background queue to avoid blocking Vision
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var detectedObjects: [DetectedObject] = []
            
            for observation in observations where observation.confidence > 0.7 {
                let boundingBox = observation.boundingBox
                let xNorm = boundingBox.midX
                let yNorm = boundingBox.midY
                let xNormF = Float(xNorm)
                let yNormF = Float(yNorm)
                
                var zMeters: Float = 0
                
                if let depthMap = self.latestDepthMap {
                    // Convert normalized coordinates to pixel coordinates in depth map space
                    let width = CVPixelBufferGetWidth(depthMap)
                    let height = CVPixelBufferGetHeight(depthMap)
                    let pixelXFloat = xNormF * Float(width)
                    let pixelYFloat = (1 - yNormF) * Float(height)
                    let pixelX = Int(self.clamp(Int(round(pixelXFloat)), 0, width - 1))
                    let pixelY = Int(self.clamp(Int(round(pixelYFloat)), 0, height - 1))
                    zMeters = self.sampleDepth(atX: pixelX, y: pixelY, from: depthMap)
                }
                
                let label = observation.labels.first?.identifier ?? "unknown"
                
                // boundingBox is left as nil here; actual VNRecognizedObjectObservation is exposed via lastObservations
                // Width/height in meters could be computed if needed in future
                detectedObjects.append(
                    DetectedObject(
                        label: label,
                        position: simd_float3(xNormF, yNormF, zMeters),
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
