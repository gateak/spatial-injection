//
//  ObjectDetector.swift
//  spatial-injection
//
//  Created by Akbar Khamidov on 11/12/25.
//

import Vision
import CoreML
import ARKit
import UIKit

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
    public private(set) var lastDetections: [DetectedObject] = []
    
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
    private var latestCameraIntrinsics = simd_float3x3()
    private var latestCameraTransform = matrix_identity_float4x4
    
    private var isProcessing = false
    private var lastRequestTimestamp: TimeInterval = 0
    private let minimumRequestInterval: TimeInterval = 0.12
    private let processingQueue = DispatchQueue(label: "com.spatialinjection.objectdetector", qos: .userInitiated)
    
    func detectObjects(in frame: ARFrame, completion: @escaping ([DetectedObject]) -> Void) {
        let timestamp = frame.timestamp
        
        if isProcessing || (timestamp - lastRequestTimestamp) < minimumRequestInterval {
            let cachedDetections = lastDetections
            DispatchQueue.main.async {
                completion(cachedDetections)
            }
            return
        }
        
        completionHandler = completion
        isProcessing = true
        lastRequestTimestamp = timestamp
        
        latestDepthMap = frame.sceneDepth?.depthMap
        let pixelBuffer = frame.capturedImage
        latestImageSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                                 height: CVPixelBufferGetHeight(pixelBuffer))
        latestCameraIntrinsics = frame.camera.intrinsics
        latestCameraTransform = frame.camera.transform
        
        var intrinsics = frame.camera.intrinsics
        let intrinsicsData = NSData(bytes: &intrinsics, length: MemoryLayout.size(ofValue: intrinsics))
        let orientation = currentImageOrientation()
        
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [.cameraIntrinsics: intrinsicsData]
        )
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try handler.perform([self.request])
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.lastDetections = []
                    self.completionHandler?([])
                    self.completionHandler = nil
                }
            }
        }
    }
    
    private func handleDetections(_ observations: [VNRecognizedObjectObservation]) {
        lastObservations = observations
        
        var detectedObjects: [DetectedObject] = []
        
        for observation in observations where observation.confidence > 0.7 {
            let boundingBox = observation.boundingBox
            let midX = boundingBox.midX
            let midY = boundingBox.midY
            let midXFloat = Float(midX)
            let midYFloat = Float(midY)
            
            var zMeters: Float = 0
            var worldPosition: simd_float3?
            
            if let depthMap = latestDepthMap {
                let width = CVPixelBufferGetWidth(depthMap)
                let height = CVPixelBufferGetHeight(depthMap)
                let pixelXFloat = midXFloat * Float(width)
                let pixelYFloat = (1 - midYFloat) * Float(height)
                let pixelX = Int(clamp(Int(round(pixelXFloat)), 0, width - 1))
                let pixelY = Int(clamp(Int(round(pixelYFloat)), 0, height - 1))
                zMeters = sampleDepth(atX: pixelX, y: pixelY, from: depthMap, kernelRadius: 1)
                worldPosition = worldPositionForPixel(x: pixelXFloat, y: pixelYFloat, depth: zMeters)
            }
            
            let label = observation.labels.first?.identifier ?? "unknown"
            
            detectedObjects.append(
                DetectedObject(
                    label: label,
                    position: simd_float3(midXFloat, midYFloat, zMeters),
                    boundingBox: nil,
                    confidence: observation.confidence,
                    worldPosition: worldPosition
                )
            )
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastDetections = detectedObjects
            self.completionHandler?(detectedObjects)
            self.completionHandler = nil
            self.isProcessing = false
        }
    }
    
    private func sampleDepth(atX x: Int, y: Int, from depthMap: CVPixelBuffer, kernelRadius: Int = 0) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return 0 }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        
        if pixelFormat == kCVPixelFormatType_DepthFloat32 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
            let stride = rowBytes / MemoryLayout<Float32>.size
            var total: Float = 0
            var samples: Float = 0
            let radius = max(0, kernelRadius)
            
            let minY = max(0, y - radius)
            let maxY = min(height - 1, y + radius)
            let minX = max(0, x - radius)
            let maxX = min(width - 1, x + radius)
            
            for yy in minY...maxY {
                for xx in minX...maxX {
                    let index = yy * stride + xx
                    if index >= 0 && index < stride * height {
                        let depthValue = floatBuffer[index]
                        if depthValue.isFinite && depthValue > 0 {
                            total += depthValue
                            samples += 1
                        }
                    }
                }
            }
            
            if samples > 0 {
                return total / samples
            }
        }
        
        return 0
    }
    
    private func clamp<T: Comparable>(_ value: T, _ min: T, _ max: T) -> T {
        if value < min { return min }
        if value > max { return max }
        return value
    }
    
    private func worldPositionForPixel(x: Float, y: Float, depth: Float) -> simd_float3? {
        guard depth.isFinite, depth > 0 else { return nil }
        
        let fx = latestCameraIntrinsics.columns.0.x
        let fy = latestCameraIntrinsics.columns.1.y
        let cx = latestCameraIntrinsics.columns.2.x
        let cy = latestCameraIntrinsics.columns.2.y
        
        guard fx != 0, fy != 0 else { return nil }
        
        let normalizedX = (x - cx) / fx
        let normalizedY = (y - cy) / fy
        
        let cameraSpacePoint = simd_float4(normalizedX * depth,
                                           normalizedY * depth,
                                           depth,
                                           1)
        let worldPoint = latestCameraTransform * cameraSpacePoint
        return simd_float3(worldPoint.x, worldPoint.y, worldPoint.z)
    }
    
    private func currentImageOrientation() -> CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portraitUpsideDown:
            return .left
        default:
            return .right
        }
    }
}
