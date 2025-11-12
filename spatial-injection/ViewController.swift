//
//  ViewController.swift
//  spatial-injection
//
//  Created by Akbar Khamidov on 11/12/25.

import UIKit
import RealityKit
import ARKit
import Vision

class ViewController: UIViewController {
    var arView: ARView!  // Changed: removed @IBOutlet since we're creating it programmatically
    var overlayView = DetectionOverlayView()
    
    var dataCollector: ARDataCollector!
    var objectDetector = ObjectDetector()
    let llm = LLMConnector()
    var displayLink: CADisplayLink?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create ARView programmatically
        arView = ARView(frame: view.bounds)
        view.addSubview(arView)
        
        // Add overlay view on top of arView
        overlayView.frame = arView.bounds
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        arView.addSubview(overlayView)
        
        // Start AR with depth
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.frameSemantics = .sceneDepth
        
        arView.session.run(config)
        
        // Initialize data collector
        dataCollector = ARDataCollector(arView: arView)
        
        // Add capture button
        let captureButton = UIButton(frame: CGRect(x: 50, y: 100, width: 200, height: 50))
        captureButton.setTitle("Analyze Scene", for: .normal)
        captureButton.backgroundColor = .systemBlue
        captureButton.layer.cornerRadius = 10  // Added: make it look nice
        captureButton.addTarget(self, action: #selector(captureAndAnalyze), for: .touchUpInside)
        view.addSubview(captureButton)
        
        // Add tap gesture recognizer for manual override
        let tap = UITapGestureRecognizer(target: self, action: #selector(manualMarkObject(_:)))
        arView.addGestureRecognizer(tap)
        
        // Setup CADisplayLink to refresh overlay each frame
        displayLink = CADisplayLink(target: self, selector: #selector(updateOverlay))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        arView.frame = view.bounds
        overlayView.frame = arView.bounds
    }
    
    @objc func captureAndAnalyze() {
        // Get current spatial context
        let spatialData = dataCollector.currentSpatialContext
        
        // Convert to LLM prompt
        let contextPrompt = spatialData.toLLMPrompt()
        
        // Capture current image - FIXED this line
        arView.snapshot(saveToHDR: false) { image in
            guard let image = image else { return }
            
            // Send to LLM
            self.sendToLLM(image: image, spatialContext: contextPrompt)
        }
    }
    
    func sendToLLM(image: UIImage, spatialContext: String) {
        llm.send(image: image, spatialContext: spatialContext) { response in
            print("=== LLM RESPONSE ===")
            print(response)
            print("=== END RESPONSE ===")
        }
    }
    
    @objc func updateOverlay() {
        guard let frame = arView.session.currentFrame else { return }
        // Get latest observations from objectDetector
        let observations = objectDetector.lastObservations
        // Map normalized Vision boxes to view-space rects
        let size = overlayView.bounds.size
        let rects: [CGRect] = observations.map { obs in
            let bb = obs.boundingBox // normalized in Vision space (origin bottom-left)
            let x = bb.origin.x * size.width
            let y = (1 - bb.origin.y - bb.height) * size.height
            let w = bb.width * size.width
            let h = bb.height * size.height
            return CGRect(x: x, y: y, width: w, height: h)
        }
        overlayView.observations = rects
    }
    
    @objc func manualMarkObject(_ sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: "Mark Object", message: "Choose a label for the tapped point", preferredStyle: .actionSheet)
        let labels = ["person", "door", "shelf", "ladder", "vehicle"]
        for label in labels {
            alert.addAction(UIAlertAction(title: label, style: .default, handler: { _ in
                let location = sender.location(in: self.arView)
                if let result = self.arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                    let position = simd_float3(result.worldTransform.columns.3.x,
                                               result.worldTransform.columns.3.y,
                                               result.worldTransform.columns.3.z)
                    var context = self.dataCollector.currentSpatialContext
                    let obj = DetectedObject(label: label, position: position, boundingBox: nil, confidence: 1.0)
                    context.objects.append(obj)
                    self.dataCollector.currentSpatialContext = context
                    print("Manual override: marked \(label) at \(position)")
                }
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}
