//
//  GeometryView.swift
//  Mactenna
//
//  Standalone SceneKit view that renders just the geometry segments and
//  handles click-to-select behaviour.  This used to live inside PatternView
//  but selection is now confined to its own tab (Phase 5‑1 progress).
//

import SwiftUI
import SceneKit

// note: GeometrySegment is defined globally in PatternView.swift so it can be
// shared across multiple views.

// reuse the same vector helper functions as PatternView
fileprivate func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}
fileprivate func *(lhs: SCNVector3, rhs: CGFloat) -> SCNVector3 {
    let g = CGFloat(rhs)
    return SCNVector3(lhs.x * g, lhs.y * g, lhs.z * g)
}
fileprivate func *(lhs: SCNVector3, rhs: Float) -> SCNVector3 {
    return lhs * CGFloat(rhs)
}

/// SCNView subclass providing wheel‑zoom behaviour identical to PatternView.
fileprivate final class ZoomableSCNView: SCNView {
    override func scrollWheel(with event: NSEvent) {
        if let cam = scene?.rootNode.childNodes.first(where: { $0.camera != nil }) {
            let dir = cam.worldFront
            let delta = Float(event.scrollingDeltaY) * 0.1
            cam.position = cam.position + dir * delta
        } else {
            super.scrollWheel(with: event)
        }
    }
}

struct GeometryView: NSViewRepresentable {
    /// Geometry segments to render.
    let geometry: [GeometrySegment]
    /// Currently selected card index (or nil).
    @Binding var selectedCard: Int?
    
    // observe preferences so changes trigger SwiftUI updates
    @AppStorage("geometryRadiusScale") private var radiusScale: Double = Preferences.shared.geometryRadiusScale
    @AppStorage("geometryExaggerateSmallDiameters") private var exaggerateDiameters: Bool = Preferences.shared.geometryExaggerateSmallDiameters
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = ZoomableSCNView()
        scnView.scene = makeScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = NSColor.windowBackgroundColor
        // install click recognizer
        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(click)
        return scnView
    }
    
    func updateNSView(_ scnView: SCNView, context: Context) {
        scnView.scene = makeScene()
    }
    
    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        // camera orientation same as PatternView
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: -5, y: 0, z: 0)
        cameraNode.look(at: SCNVector3Zero,
                        up: SCNVector3(0,0,1),
                        localFront: SCNVector3(0,0,-1))
        scene.rootNode.addChildNode(cameraNode)
        
        // placeholder for axis; will build after bounding box computed
        func buildAxes(length: CGFloat) {
            let axis = SCNNode()
            axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(length,0,0), color: .red))
            axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(0,length,0), color: .green))
            axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(0,0,length), color: .blue))
            
            func labelNode(_ text: String, color: NSColor, position: SCNVector3, axisLength: CGFloat) -> SCNNode {
                let txt = SCNText(string: text, extrusionDepth: 0.1)
                // font size roughly matches the old hard-coded scale; we
                // will also scale the resulting node based on the axis length
                // so that labels grow/shrink with the axes.
                txt.font = NSFont.systemFont(ofSize: 0.4)
                txt.firstMaterial?.diffuse.contents = color
                let node = SCNNode(geometry: txt)
                let (min, max) = txt.boundingBox
                let dx = (max.x + min.x) / 2
                let dy = (max.y + min.y) / 2
                node.pivot = SCNMatrix4MakeTranslation(dx, dy, 0)
                // base scale roughly 0.4 previously; shrink by 25% to make
                // text a bit smaller relative to axes.
                let labelScale = axisLength * 0.3
                node.scale = SCNVector3(labelScale, labelScale, labelScale)
                node.position = position
                return node
            }
            axis.addChildNode(labelNode("X", color: .red,
                                        position: SCNVector3(length,0,0),
                                        axisLength: length))
            axis.addChildNode(labelNode("Y", color: .green,
                                        position: SCNVector3(0,length,0),
                                        axisLength: length))
            axis.addChildNode(labelNode("Z", color: .blue,
                                        position: SCNVector3(0,0,length),
                                        axisLength: length))
            scene.rootNode.addChildNode(axis)
        }
        
        // compute bounding box first so we know how to scale
        let container = SCNNode()
        var minB = SCNVector3(CGFloat.infinity, CGFloat.infinity, CGFloat.infinity)
        var maxB = SCNVector3(-CGFloat.infinity, -CGFloat.infinity, -CGFloat.infinity)
        for seg in geometry {
            let p1 = SCNVector3(CGFloat(seg.start.x), CGFloat(seg.start.y), CGFloat(seg.start.z))
            let p2 = SCNVector3(CGFloat(seg.end.x),   CGFloat(seg.end.y),   CGFloat(seg.end.z))
            minB.x = min(minB.x, p1.x, p2.x)
            minB.y = min(minB.y, p1.y, p2.y)
            minB.z = min(minB.z, p1.z, p2.z)
            maxB.x = max(maxB.x, p1.x, p2.x)
            maxB.y = max(maxB.y, p1.y, p2.y)
            maxB.z = max(maxB.z, p1.z, p2.z)
        }
        // compute axis length based on largest box dimension
        let dx = maxB.x - minB.x
        let dy = maxB.y - minB.y
        let dz = maxB.z - minB.z
        // halve the previous scale so axes are about 50% shorter
        let axisLen = max(dx, max(dy, dz)) * 0.6
        buildAxes(length: axisLen)
        
        // center container
        let cx = (minB.x + maxB.x) / 2
        let cy = (minB.y + maxB.y) / 2
        let cz = (minB.z + maxB.z) / 2
        container.position = SCNVector3(-cx, -cy, -cz)
        
        // compute bounding-sphere radius and move camera so entire box is visible
        func radius(from minB: SCNVector3, to maxB: SCNVector3, center: SCNVector3) -> CGFloat {
            let corners = [minB, maxB]
            return corners.map { v in
                let dx = v.x - center.x
                let dy = v.y - center.y
                let dz = v.z - center.z
                return sqrt(dx*dx + dy*dy + dz*dz)
            }.max() ?? 0
        }
        let geoCenter = SCNVector3(cx, cy, cz)
        let geoRadius = radius(from: minB, to: maxB, center: geoCenter)
        if geoRadius > 0 {
            let dist = max(geoRadius * 3, CGFloat(5))
            cameraNode.position = SCNVector3(x: -CGFloat(dist), y: 0, z: 0)
        }
        for seg in geometry {
            let p1 = SCNVector3(CGFloat(seg.start.x), CGFloat(seg.start.y), CGFloat(seg.start.z))
            let p2 = SCNVector3(CGFloat(seg.end.x),   CGFloat(seg.end.y),   CGFloat(seg.end.z))

            let isSel = (seg.cardIndex == selectedCard)
            let color: NSColor = isSel ? .systemYellow : .darkGray

            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let dz = p2.z - p1.z
            let length = sqrt(dx*dx + dy*dy + dz*dz)

            // compute radius solely from segment length; ignore scale
            // base multiplier configurable via preferences (observed via @AppStorage)
            let globalScale: CGFloat = CGFloat(radiusScale)
            var radius = max(CGFloat(length) * 0.002 * globalScale, 0.002 * globalScale)
            if exaggerateDiameters {
                let threshold = CGFloat(length) * 0.02 * globalScale
                if radius < threshold {
                    radius *= 5
                }
            }

            let cyl = SCNCylinder(radius: radius, height: CGFloat(length))
            cyl.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: cyl)
            node.name = "card_\(seg.cardIndex)"
            node.categoryBitMask = 2
            node.position = SCNVector3((p1.x+p2.x)/2,
                                       (p1.y+p2.y)/2,
                                       (p1.z+p2.z)/2)
            node.eulerAngles = SCNVector3(Float(-Double.pi/2), 0, 0)
            node.look(at: p2, up: SCNVector3(0,1,0), localFront: SCNVector3(0,1,0))

            container.addChildNode(node)
        }
    
    scene.rootNode.addChildNode(container)
    
    return scene
}

private func lineNode(from: SCNVector3, to: SCNVector3, color: NSColor) -> SCNNode {
    let src = SCNGeometrySource(vertices: [from, to])
    let indices: [UInt8] = [0, 1]
    let elem = SCNGeometryElement(data: Data(indices),
                                  primitiveType: .line,
                                  primitiveCount: 1,
                                  bytesPerIndex: MemoryLayout<UInt8>.size)
    let geom = SCNGeometry(sources: [src], elements: [elem])
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    geom.firstMaterial = mat
    return SCNNode(geometry: geom)
}

// MARK: – Coordinator
class Coordinator: NSObject {
    var parent: GeometryView
    init(_ parent: GeometryView) {
        self.parent = parent
    }
    
    @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard let scnView = gesture.view as? SCNView else { return }
        let loc = gesture.location(in: scnView)
        let hits = scnView.hitTest(loc, options: [SCNHitTestOption.categoryBitMask: 2])
        for hit in hits {
            if let name = hit.node.name, name.hasPrefix("card_") {
                let suffix = name.dropFirst("card_".count)
                if let idx = Int(suffix) {
                    DispatchQueue.main.async {
                        self.parent.selectedCard = idx
                    }
                }
                return
            }
        }
        DispatchQueue.main.async {
            self.parent.selectedCard = nil
        }
    }
}
}

#if DEBUG
extension GeometryView {
    struct Preview: PreviewProvider {
        static let sampleGeom: [GeometrySegment] = [
            GeometrySegment(start: SIMD3(-1,0,0), end: SIMD3(1,0,0), cardIndex: 0),
            GeometrySegment(start: SIMD3(0,-1,0), end: SIMD3(0,1,0), cardIndex: 1)
        ]
        static var previews: some View {
            GeometryView(geometry: sampleGeom, selectedCard: .constant(nil))
                .frame(width: 300, height: 300)
        }
    }
}
#endif
