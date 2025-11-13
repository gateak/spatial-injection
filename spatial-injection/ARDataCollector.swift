//
//  ARDataCollector.swift
//  spatial-injection
//
//  Created by Akbar Khamidov on 11/12/25.
//
import ARKit
import RealityKit
import Vision

class ARDataCollector: NSObject, ARSessionDelegate {
    var currentSpatialContext = SpatialContext()
    var arView: ARView
    private let detector: ObjectDetector
    private var lastDetections: [DetectedObject] = []
    private var manualOverrides: [DetectedObject] = []
    
    var lastVisionObservations: [VNRecognizedObjectObservation] {
        detector.lastObservations
    }
    
    init(arView: ARView, detector: ObjectDetector) {
        self.arView = arView
        self.detector = detector
        super.init()
        arView.session.delegate = self
    }
    
    // This gets called every frame
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        currentSpatialContext.cameraTransform = frame.camera.transform
        
        // Extract depth distance at center of screen
        if let depth = frame.sceneDepth {
            let centerDistance = getCenterDistance(from: depth.depthMap)
            currentSpatialContext.distances["center_point"] = centerDistance
        }
        
        // Get detected planes (walls, floors, etc)
        updateDetectedPlanes(from: frame.anchors)
        
        detector.detectObjects(in: frame) { [weak self] objects in
            guard let self = self else { return }
            self.lastDetections = objects
            
            var context = self.currentSpatialContext
            context.objects = objects
            if !self.manualOverrides.isEmpty {
                context.objects.append(contentsOf: self.manualOverrides)
            }
            self.currentSpatialContext = context
        }
    }
    
    func addManualOverride(_ object: DetectedObject) {
        manualOverrides.append(object)
        var context = currentSpatialContext
        context.objects.append(object)
        currentSpatialContext = context
    }
    
    func clearManualOverrides() {
        manualOverrides.removeAll()
        
        var context = currentSpatialContext
        context.objects = lastDetections
        currentSpatialContext = context
    }
    
    func getCenterDistance(from depthMap: CVPixelBuffer) -> Float {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        if let baseAddress = CVPixelBufferGetBaseAddress(depthMap) {
            let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
            let centerIndex = (height/2) * width + (width/2)
            return buffer[centerIndex]
        }
        return 0
    }
    
    func updateDetectedPlanes(from anchors: [ARAnchor]) {
        currentSpatialContext.planes.removeAll()
        
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let plane = DetectedPlane(
                    classification: classificationString(planeAnchor.classification),
                    width: planeAnchor.planeExtent.width,
                    height: planeAnchor.planeExtent.height,
                    center: planeAnchor.center
                )
                currentSpatialContext.planes.append(plane)
            }
        }
    }
    
    func classificationString(_ classification: ARPlaneAnchor.Classification) -> String {
        switch classification {
        case .wall: return "wall"
        case .floor: return "floor"
        case .ceiling: return "ceiling"
        case .table: return "table"
        case .seat: return "seat"
        case .door: return "door"
        case .window: return "window"
        default: return "surface"
        }
    }
}
