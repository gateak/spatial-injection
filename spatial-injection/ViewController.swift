//
//  ViewController.swift
//  spatial-injection
//
//  Created by Akbar Khamidov on 11/12/25.

import UIKit
import RealityKit
import ARKit

class ViewController: UIViewController {
    var arView: ARView!  // Changed: removed @IBOutlet since we're creating it programmatically
    
    var dataCollector: ARDataCollector!
    var objectDetector = ObjectDetector()
    let llm = LLMConnector()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create ARView programmatically
        arView = ARView(frame: view.bounds)
        view.addSubview(arView)
        
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
    
    @objc func manualMarkObject(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
        // Simple raycast into the scene
        if let result = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
            // For demo: mark a person at this location with approximate height
            let position = simd_float3(result.worldTransform.columns.3.x,
                                       result.worldTransform.columns.3.y,
                                       result.worldTransform.columns.3.z)
            var context = dataCollector.currentSpatialContext
            let person = DetectedObject(label: "person", position: position, boundingBox: nil, confidence: 1.0)
            context.objects.append(person)
            dataCollector.currentSpatialContext = context
            print("Manual override: marked person at \(position)")
        }
    }
}

