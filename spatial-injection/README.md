# Project Overview

This iOS app leverages on-device LiDAR scanning and advanced image/object detection to enable rich spatial understanding. Using ARKit and RealityKit, it captures depth, point clouds, and scene meshes while running Vision and Core ML models for 2D object recognition. These results are fused in 3D space for enhanced spatial reasoning, enabling metric-aware insights and interactive experiences.

# Features

- LiDAR depth capture  
- Scene mesh generation  
- Point cloud sampling  
- Camera image capture  
- Object detection using Vision and Core ML  
- 2D–3D fusion of detections with depth and mesh  
- Optional cloud-based large language model (LLM) reasoning via API client  
- Recording and export of scans and spatial data  

# Architecture

- **AR Session & Sensors**  
  Utilizes ARKit/RealityKit with `ARWorldTrackingConfiguration` configured for `sceneDepth` and `sceneReconstruction` to acquire spatial data including depth maps, meshes, and feature points.

- **Perception**  
  Runs Vision requests such as `VNCoreMLRequest`, `VNDetectHumanRectanglesRequest`, and `VNRecognizeObjectsRequest`. Core ML models are used for detection with non-maximum suppression (NMS) and temporal tracking for stable object identification.

- **Fusion**  
  Projects 2D detections into 3D world space using camera intrinsics and depth maps. Associates detections with meshes and anchors for accurate spatial placement.

- **Reasoning**  
  An optional AI client consumes summarized spatial facts (object types, poses, distances) and answers queries to provide semantic or metric reasoning based on the observed environment.

- **UI**  
  SwiftUI-based interfaces including an overlay HUD, scanning controls, and an inspector panel to explore detected objects and spatial data.

# Data Flow

1. AR frame captured from device sensors  
2. Extract depth map and captured camera image  
3. Vision inference runs on the camera image producing 2D bounding boxes and masks  
4. Sample depth data and camera intrinsics for each detection  
5. Project 2D detections into 3D rays  
6. Intersect rays with scene mesh or point cloud to localize objects in world space  
7. Generate world-space object representations  
8. (Optional) Serialize spatial context and send to AI API for reasoning  
9. Receive AI response and update UI accordingly  

# LiDAR "Raw Output"

ARKit provides access to depth and mesh data as follows:

- `ARDepthData` / `sceneDepth` is a `CVPixelBuffer` containing per-pixel depth values in meters, along with a confidence map.  
- `ARMeshAnchor` provides triangle mesh geometry representing the scanned environment.  
- `ARPointCloud` exposes feature points detected by the sensor fusion pipeline.  

True raw Time-of-Flight (ToF) sensor data is not exposed by iOS; ARKit fuses sensor and camera data to produce a stabilized depth map.

```swift
// Access depth map
if let depth = frame.sceneDepth?.depthMap {
    let width = CVPixelBufferGetWidth(depth)
    let height = CVPixelBufferGetHeight(depth)
    // Lock and read float32 meters per pixel
}

// Access confidence
let confidence = frame.sceneDepth?.confidenceMap

// Access mesh anchors
let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }

// Access feature points
let points = frame.rawFeaturePoints
