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
    
    private let hudView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let centerDistanceLabel = UILabel()
    private let analyzeButton = UIButton(type: .system)
    private var detectionsPanel: UIView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create ARView programmatically
        arView = ARView(frame: view.bounds)
        view.addSubview(arView)
        
        // HUD setup for center distance
        hudView.layer.cornerRadius = 14
        hudView.layer.masksToBounds = true
        view.addSubview(hudView)
        
        centerDistanceLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        centerDistanceLabel.textColor = .label
        centerDistanceLabel.textAlignment = .center
        centerDistanceLabel.text = "Center: -- m"
        hudView.contentView.addSubview(centerDistanceLabel)
        
        // Add overlay view on top of arView
        overlayView.frame = arView.bounds
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        arView.addSubview(overlayView)
        
        // Start AR with depth
        let config = ARWorldTrackingConfiguration()
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        
        config.planeDetection = [.horizontal, .vertical]
        
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        // Initialize data collector
        dataCollector = ARDataCollector(arView: arView, detector: objectDetector)
        
        // Analyze button
        analyzeButton.setTitle("Analyze", for: .normal)
        analyzeButton.tintColor = .white
        analyzeButton.backgroundColor = .systemBlue
        analyzeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        analyzeButton.layer.cornerRadius = 22
        analyzeButton.layer.shadowColor = UIColor.black.cgColor
        analyzeButton.layer.shadowOpacity = 0.2
        analyzeButton.layer.shadowRadius = 6
        analyzeButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        analyzeButton.addTarget(self, action: #selector(captureAndAnalyze), for: .touchUpInside)
        view.addSubview(analyzeButton)
        view.bringSubviewToFront(analyzeButton)
        
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
        
        let safe = view.safeAreaInsets
        let hudWidth: CGFloat = 180
        let hudHeight: CGFloat = 44
        hudView.frame = CGRect(x: (view.bounds.width - hudWidth)/2, y: safe.top + 12, width: hudWidth, height: hudHeight)
        centerDistanceLabel.frame = hudView.bounds.insetBy(dx: 12, dy: 8)

        let buttonWidth: CGFloat = 160
        let buttonHeight: CGFloat = 44
        analyzeButton.frame = CGRect(x: (view.bounds.width - buttonWidth)/2, y: view.bounds.height - safe.bottom - buttonHeight - 20, width: buttonWidth, height: buttonHeight)
        view.bringSubviewToFront(analyzeButton)
    }
    
    @objc func captureAndAnalyze() {
        // If a previous panel is visible, dismiss it so the new one can appear properly
        dismissDetectionsPanel()
        
        // Get current spatial context
        let spatialData = dataCollector.currentSpatialContext
        
        // Convert to LLM prompt
        let contextPrompt = spatialData.toLLMPrompt()
        
        // Capture current image - FIXED this line
        arView.snapshot(saveToHDR: false) { image in
            guard let image = image else { return }
            
            // Send to LLM
            self.sendToLLM(image: image, spatialContext: contextPrompt)
            
            DispatchQueue.main.async {
                self.showDetectionsPanel()
            }
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
        
        if let d = dataCollector.currentSpatialContext.distances["center_point"], d.isFinite, d > 0 {
            centerDistanceLabel.text = String(format: "Center: %.2f m", d)
        } else {
            centerDistanceLabel.text = "Center: -- m"
        }
        
        // Get latest observations from objectDetector
        let observations = dataCollector.lastVisionObservations
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
                    let obj = DetectedObject(label: label, position: position, boundingBox: nil, confidence: 1.0, worldPosition: position)
                    self.dataCollector.addManualOverride(obj)
                    print("Manual override: marked \(label) at \(position)")
                }
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showDetectionsPanel() {
        // Remove existing panel if any
        detectionsPanel?.removeFromSuperview()

        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        panel.layer.cornerRadius = 18
        panel.layer.masksToBounds = true

        let grabber = UIView()
        grabber.backgroundColor = UIColor.label.withAlphaComponent(0.25)
        grabber.layer.cornerRadius = 2

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.addTarget(self, action: #selector(dismissDetectionsPanel), for: .touchUpInside)

        // Build content
        let titleLabel = UILabel()
        titleLabel.text = "Detections"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8

        let objs = dataCollector.currentSpatialContext.objects
        if objs.isEmpty {
            let empty = UILabel()
            empty.text = "No objects detected."
            empty.textColor = .secondaryLabel
            empty.textAlignment = .center
            empty.font = .systemFont(ofSize: 15)
            stack.addArrangedSubview(empty)
        } else {
            let cameraTransform = dataCollector.currentSpatialContext.cameraTransform
            let cameraPosition = simd_float3(cameraTransform.columns.3.x,
                                             cameraTransform.columns.3.y,
                                             cameraTransform.columns.3.z)
            for o in objs {
                let lbl = UILabel()
                let distance: Float
                if let world = o.worldPosition {
                    distance = simd_length(world - cameraPosition)
                } else {
                    distance = o.position.z
                }
                lbl.text = String(format: "%@ — %.2f m", o.label, distance)
                lbl.textColor = .label
                lbl.font = .systemFont(ofSize: 15)
                stack.addArrangedSubview(lbl)
            }
        }

        let content = UIStackView(arrangedSubviews: [titleLabel, stack])
        content.axis = .vertical
        content.spacing = 12
        content.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        content.isLayoutMarginsRelativeArrangement = true

        panel.contentView.addSubview(content)
        view.addSubview(panel)
        view.bringSubviewToFront(analyzeButton)

        // Layout
        let safe = view.safeAreaInsets
        let buttonBottom = analyzeButton.frame.minY
        let horizontalMargin: CGFloat = 12
        let width: CGFloat = view.bounds.width - horizontalMargin * 2
        let maxHeight: CGFloat = min(300, view.bounds.height * 0.4)
        let desiredBottomSpacing: CGFloat = 12
        let panelBottom = buttonBottom - desiredBottomSpacing
        let panelHeight = maxHeight
        panel.frame = CGRect(x: horizontalMargin, y: panelBottom - panelHeight, width: width, height: panelHeight)

        // Layout subviews inside panel
        let grabberWidth: CGFloat = 36
        let grabberHeight: CGFloat = 4
        grabber.frame = CGRect(x: (panel.bounds.width - grabberWidth)/2, y: 8, width: grabberWidth, height: grabberHeight)

        let closeSize = CGSize(width: 60, height: 28)
        closeButton.frame = CGRect(x: panel.bounds.width - closeSize.width - 8, y: 6, width: closeSize.width, height: closeSize.height)

        let contentTop: CGFloat = grabber.frame.maxY + 6
        content.frame = panel.bounds.inset(by: UIEdgeInsets(top: contentTop + 6, left: 0, bottom: 0, right: 0))

        panel.contentView.addSubview(grabber)
        panel.contentView.addSubview(closeButton)

        // Keep reference
        detectionsPanel = panel

        // Simple appear animation
        panel.alpha = 0
        UIView.animate(withDuration: 0.2) {
            panel.alpha = 1
        }
    }
    
    @objc private func dismissDetectionsPanel() {
        guard let panel = detectionsPanel else { return }
        UIView.animate(withDuration: 0.2, animations: {
            panel.alpha = 0
        }, completion: { _ in
            panel.removeFromSuperview()
            self.detectionsPanel = nil
        })
    }
}
