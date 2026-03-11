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
import SpriteKit

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

fileprivate func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    return SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
}

fileprivate func dot(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
    return a.x*b.x + a.y*b.y + a.z*b.z
}

fileprivate extension SCNVector3 {
    func length() -> CGFloat {
        return sqrt(x*x + y*y + z*z)
    }
    func normalized() -> SCNVector3 {
        let l = length()
        return l > 0 ? SCNVector3(x/l, y/l, z/l) : SCNVector3Zero
    }
}

/// Protocol implemented by the coordinator to receive mouse events.
fileprivate protocol GeometryViewDragDelegate: AnyObject {
    func mouseDown(at point: NSPoint, in view: SCNView)
    func mouseDragged(at point: NSPoint, in view: SCNView)
    func mouseUp(at point: NSPoint, in view: SCNView)
    func keyDown(_ event: NSEvent)
    func keyUp(_ event: NSEvent)
}

/// SCNView subclass providing wheel‑zoom behaviour identical to PatternView,
/// plus forwarding of mouse events to a delegate.
fileprivate final class ZoomableSCNView: SCNView {
    weak var dragDelegate: GeometryViewDragDelegate?
    private var overlayScene: SKScene?
    private var overlayLabels: [SKLabelNode] = []

    override func scrollWheel(with event: NSEvent) {
        if let cam = scene?.rootNode.childNodes.first(where: { $0.camera != nil }) {
            let dir = cam.worldFront
            let delta = Float(event.scrollingDeltaY) * 0.1
            cam.position = cam.position + dir * delta
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        dragDelegate?.mouseDown(at: event.locationInWindow, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        dragDelegate?.mouseDragged(at: event.locationInWindow, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        dragDelegate?.mouseUp(at: event.locationInWindow, in: self)
    }
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        dragDelegate?.keyDown(event)
    }

    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        dragDelegate?.keyUp(event)
    }

    // MARK: - Overlay SKScene
    private func ensureOverlay() {
        wantsLayer = true
        if overlayScene == nil {
            let size = bounds.size
            let sk = SKScene(size: size)
            sk.scaleMode = .resizeFill
            sk.backgroundColor = .clear
            overlayScene = sk
            overlaySKScene = sk
            print("[Overlay] created overlay SKScene of size \(size)")
        } else {
            overlayScene?.size = bounds.size
        }
        // assign to view even on resize
        if let sk = overlayScene {
            overlaySKScene = sk
        }
    }

    func showOverlay(text: String, at screenPoint: CGPoint) {
        ensureOverlay()
        guard let sk = overlayScene else {
            print("[Overlay] no overlayScene!")
            return
        }
        print("[Overlay] showOverlay text=\(text) at screen=\(screenPoint)")
        // remove all existing nodes to eradicate stray bg shapes
        sk.removeAllChildren()
        overlayLabels.removeAll()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // flip y for SK coordinates
        let skBase = CGPoint(x: screenPoint.x, y: bounds.height - screenPoint.y)
        var y = skBase.y
        for line in lines {
            let label = SKLabelNode(fontNamed: "Menlo")
            label.fontSize = 14
            label.fontColor = .black
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .top
            label.text = String(line)
            label.position = CGPoint(x: skBase.x, y: y)
            // add a light background rectangle behind the label
            let padding: CGFloat = 4
            let rect = CGRect(x: -padding,
                              y: -label.frame.height - padding,
                              width: label.frame.width + 2*padding,
                              height: label.frame.height + 2*padding)
            let bg = SKShapeNode(rect: rect, cornerRadius: 2)
            bg.fillColor = SKColor.white.withAlphaComponent(0.6)
            bg.strokeColor = .clear
            bg.position = label.position
            bg.zPosition = label.zPosition - 1
            sk.addChild(bg)
            sk.addChild(label)
            overlayLabels.append(label)
            y -= label.frame.height + 2
        }
    }

    func hideOverlay() {
        guard let sk = overlayScene else { return }
        sk.removeAllChildren()
        overlayLabels.removeAll()
    }
}

struct GeometryView: NSViewRepresentable {
    /// Geometry segments to render.
    let geometry: [GeometrySegment]
    /// Currently selected card index (or nil).
    var selectedCard: Int?
    /// Persisted camera transform supplied by parent.  This allows us to
    /// restore view state even if SwiftUI destroys and recreates the NSView
    /// (which happens when the parent list of geometry changes).
    @Binding var cameraTransform: SCNMatrix4?
    /// Called whenever the user selects a card in the 3‑D view.
    let onSelect: (Int?) -> Void
    /// Called when a drag finishes and the geometry has changed.
    /// Arguments are (cardIndex, newStart?, newEnd?).  Only one of the
    /// start/end tuples will be non-nil, depending on which handle was
    /// dragged; mid drags do not generate commits.
    let onDragCommit: (Int, SIMD3<Float>?, SIMD3<Float>?) -> Void

    // --- drag support types ------------------------------------------------
    /// identifies one of the three spherical handles attached to a wire
    enum HandleID: Equatable {
        case start(card: Int)
        case mid(card: Int)
        case end(card: Int)
    }

    /// current interaction state while editing geometry
    enum DragState {
        case idle
        case dragging(handle: HandleID,
                      node: SCNNode,
                      startWorld: SCNVector3,
                      preSnapshot: String)
    }

    /// World axes used for locks and plane constraints.
    enum Axis {
        case x, y, z
        var vector: SCNVector3 {
            switch self {
            case .x: return SCNVector3(1,0,0)
            case .y: return SCNVector3(0,1,0)
            case .z: return SCNVector3(0,0,1)
            }
        }
    }

    /// Constraint applied to a dragged handle.
    enum DragConstraint {
        case axial(origin: SCNVector3, direction: SCNVector3)
        case worldAxis(Axis)
        case worldPlane(Axis)
        case free
        case rotation(center: SCNVector3, axis: SCNVector3)
    }


    // observe preferences so changes trigger SwiftUI updates
    @AppStorage("geometryRadiusScale") private var radiusScale: Double = Preferences.shared.geometryRadiusScale
    @AppStorage("geometryExaggerateSmallDiameters") private var exaggerateDiameters: Bool = Preferences.shared.geometryExaggerateSmallDiameters

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: – Cylinder Mesh Generation

    /// Generate vertex/normal/index data for a single cylinder.
    /// Returns (vertices, normals, indices) for a cylinder with the given radius and height,
    /// centered at origin, extending along the Z axis.
    /// `sides` is the number of sides around the circumference (default 12).
    private func cylinderMesh(radius: Float, height: Float, sides: Int = 12)
        -> (vertices: [SCNVector3], normals: [SCNVector3], indices: [UInt32]) {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [UInt32] = []

        let halfHeight = height / 2
        let angleStep = Float(2 * Double.pi / Double(sides))

        // Generate vertices around the two circular ends
        for i in 0..<sides {
            let angle = Float(i) * angleStep
            let x = radius * cos(angle)
            let y = radius * sin(angle)

            // Bottom cap vertex
            vertices.append(SCNVector3(x: CGFloat(x), y: CGFloat(y), z: CGFloat(-halfHeight)))
            // Top cap vertex
            vertices.append(SCNVector3(x: CGFloat(x), y: CGFloat(y), z: CGFloat(halfHeight)))

            // Side normals (pointing outward)
            let nx = cos(angle)
            let ny = sin(angle)
            normals.append(SCNVector3(x: CGFloat(nx), y: CGFloat(ny), z: 0))
            normals.append(SCNVector3(x: CGFloat(nx), y: CGFloat(ny), z: 0))
        }

        // Center vertices for caps (to close the ends)
        let centerBottomIdx: UInt32 = UInt32(vertices.count)
        vertices.append(SCNVector3(x: 0, y: 0, z: CGFloat(-halfHeight)))
        normals.append(SCNVector3(x: 0, y: 0, z: -1))

        let centerTopIdx: UInt32 = UInt32(vertices.count)
        vertices.append(SCNVector3(x: 0, y: 0, z: CGFloat(halfHeight)))
        normals.append(SCNVector3(x: 0, y: 0, z: 1))

        // Side faces (quads, represented as two triangles)
        for i in 0..<sides {
            let i0 = UInt32(i * 2)
            let i1 = UInt32((i * 2) + 1)
            let i2 = UInt32(((i + 1) % sides) * 2)
            let i3 = UInt32((((i + 1) % sides) * 2) + 1)

            // First triangle
            indices.append(i0)
            indices.append(i1)
            indices.append(i2)

            // Second triangle
            indices.append(i1)
            indices.append(i3)
            indices.append(i2)
        }

        // Bottom cap triangles
        for i in 0..<sides {
            let i0 = UInt32(i * 2)
            let i1 = UInt32(((i + 1) % sides) * 2)
            indices.append(centerBottomIdx)
            indices.append(i1)
            indices.append(i0)
        }

        // Top cap triangles
        for i in 0..<sides {
            let i0 = UInt32((i * 2) + 1)
            let i1 = UInt32((((i + 1) % sides) * 2) + 1)
            indices.append(centerTopIdx)
            indices.append(i0)
            indices.append(i1)
        }

        return (vertices, normals, indices)
    }

    // MARK: – Helper for avoiding full scene rebuilds

    /// Returns true if the provided geometry array is equivalent to the one
    /// last used to build the scene.  Comparison is cheap thanks to
    /// `GeometrySegment: Equatable`.
    private func geometryIsUnchanged(_ geometry: [GeometrySegment], coordinator: Coordinator) -> Bool {
        // If we have never recorded any geometry yet, this is the first update
        // and we should rebuild the scene.  /nil/ is never equal to a real array.
        guard let last = coordinator.lastGeometry else { return false }
        return last == geometry
    }


    func makeNSView(context: Context) -> SCNView {
        let scnView = ZoomableSCNView()
        scnView.dragDelegate = context.coordinator
        scnView.scene = makeScene(coordinator: context.coordinator)
        // initial camera transform from binding
        if let cam = cameraTransform {
            scnView.pointOfView?.transform = cam
        }
        scnView.delegate = context.coordinator
        // immediately record the starting transform into the binding so
        // future rebuilds have a value to apply (prevents first-change snap).
        if let cam = scnView.pointOfView?.transform {
            cameraTransform = cam
        }
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = NSColor.windowBackgroundColor
        // keep click recognizer temporarily for testing; later we can remove
        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(click)
        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        // If nothing relevant has changed, leave the existing scene intact.
        // This prevents unnecessary camera/device resets when merely selecting
        // a different card or when no geometry edits occurred at all.
        if scnView.scene != nil,
           geometryIsUnchanged(geometry, coordinator: context.coordinator),
           selectedCard == context.coordinator.lastSelectedCard {
            return
        }

        // rebuild path.
        scnView.scene = makeScene(coordinator: context.coordinator)
        // makeScene updates coordinator.cameraNode; make sure the view uses it
        if let camNode = context.coordinator.cameraNode {
            scnView.pointOfView = camNode
        }
        // apply stored transform from parent if available
        if let cam = cameraTransform {
            scnView.pointOfView?.transform = cam
        }
        // start delegating frame updates
        scnView.delegate = context.coordinator
        // hook up ourselves as renderer delegate so we can save camera each
        // frame (must do this after scene creation so delegate is honoured)
        scnView.delegate = context.coordinator
        context.coordinator.lastGeometry = geometry
        context.coordinator.lastSelectedCard = selectedCard
    }

    private func makeScene(coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()
        // camera orientation same as PatternView.  reuse previously created
        // node if we have one; this keeps the transform (position/rotation)
        // across rebuilds.
        let cameraNode: SCNNode
        if let existing = coordinator.cameraNode {
            cameraNode = existing
            cameraNode.removeFromParentNode()
        } else {
            cameraNode = SCNNode()
            cameraNode.name = "mainCamera"
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(x: -5, y: 0, z: 0)
            cameraNode.look(at: SCNVector3Zero,
                            up: SCNVector3(0,0,1),
                            localFront: SCNVector3(0,0,-1))
            coordinator.cameraNode = cameraNode
        }
        scene.rootNode.addChildNode(cameraNode)

        // placeholder for axis; will build after bounding box computed
        func buildAxes(length: CGFloat) {
            let axis = SCNNode()
            axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(length,0,0), color: .red))
            axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(0,length,0), color: .green))
            axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(0,0,length), color: .blue))

            func labelNode(_ text: String, color: NSColor, position: SCNVector3, axisLength: CGFloat) -> SCNNode {
                let txt = SCNText(string: text, extrusionDepth: 0.1)
                txt.font = NSFont.systemFont(ofSize: 0.4)
                txt.firstMaterial?.diffuse.contents = color
                let node = SCNNode(geometry: txt)
                let (min, max) = txt.boundingBox
                let dx = (max.x + min.x) / 2
                let dy = (max.y + min.y) / 2
                node.pivot = SCNMatrix4MakeTranslation(dx, dy, 0)
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
        container.name = "geometryContainer" // so handles can be attached later
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
        let axisLen = max(dx, max(dy, dz)) * 0.6
        buildAxes(length: axisLen)

        // center container
        let cx = (minB.x + maxB.x) / 2
        let cy = (minB.y + maxB.y) / 2
        let cz = (minB.z + maxB.z) / 2
        container.position = SCNVector3(-cx, -cy, -cz)
        // store offset so snaps can convert deck coords to world coords
        coordinator.containerOffset = container.position

        // compute desired camera distance based on bounding radius.
        // If the camera already exists we may still need to push it back if
        // it has drifted too close to the new geometry.  This handles both
        // initial creation and subsequent geometry updates.
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
            // original framing math: choose at least 3× radius or 5 units,
            // whichever is larger.  this gives a consistent starting distance
            // without attempting to readjust on subsequent geometry updates.
            let dist = max(geoRadius * 3, CGFloat(5))
            cameraNode.position = SCNVector3(x: -CGFloat(dist), y: 0, z: 0)
        }

        // Build one batched geometry for all segments.  This scales far better
        // when thousands of segments are present.  We'll also keep invisible
        // proxy nodes for hit testing so the interaction remains easy.

        var batchVertices: [SCNVector3] = []
        var batchNormals: [SCNVector3] = []
        var batchIndices: [UInt32] = []
        var batchColors: [NSColor] = []
        var segmentFaceCount: [Int] = []
        var segmentIndexMap: [(startIndex: UInt32, vertexCount: UInt32, cardIndex: Int)] = []

        for seg in geometry {
            let p1 = SCNVector3(CGFloat(seg.start.x), CGFloat(seg.start.y), CGFloat(seg.start.z))
            let p2 = SCNVector3(CGFloat(seg.end.x),   CGFloat(seg.end.y),   CGFloat(seg.end.z))

            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let dz = p2.z - p1.z
            let length = sqrt(dx*dx + dy*dy + dz*dz)

            let globalScale: CGFloat = CGFloat(radiusScale)
            // if the segment provided an explicit radius (from F7) use it
            // verbatim; the scale slider only affects automatically-derived
            // values to avoid blowing up user-entered numbers.
            var radius: CGFloat
            if seg.radius > 0 {
                radius = CGFloat(seg.radius)
            } else {
                radius = max(CGFloat(length) * 0.002 * globalScale, 0.002 * globalScale)
            }
            if exaggerateDiameters {
                let threshold = CGFloat(length) * 0.02 * globalScale
                if radius < threshold {
                    radius *= 5
                }
            }

            let mesh = cylinderMesh(radius: Float(radius), height: Float(length), sides: 12)

            let direction = normalize(SIMD3<Float>(x: Float(dx), y: Float(dy), z: Float(dz)))
            let midpoint = SIMD3<Float>(x: Float((p1.x + p2.x) / 2),
                                        y: Float((p1.y + p2.y) / 2),
                                        z: Float((p1.z + p2.z) / 2))
            let zAxis = SIMD3<Float>(0,0,1)
            let dotProduct = dot(zAxis, direction)
            let quat: simd_quatf
            if abs(dotProduct - 1.0) < 0.001 {
                quat = simd_quatf()
            } else if abs(dotProduct + 1.0) < 0.001 {
                quat = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(1,0,0))
            } else {
                let rotAxis = normalize(cross(zAxis, direction))
                let rotAngle = acos(dotProduct)
                quat = simd_quatf(angle: rotAngle, axis: rotAxis)
            }

            let startVertexIdx = UInt32(batchVertices.count)
            // remember which vertices belong to this card
            segmentIndexMap.append((startIndex: startVertexIdx,
                                     vertexCount: UInt32(mesh.vertices.count),
                                     cardIndex: seg.cardIndex))
            for vertex in mesh.vertices {
                let v = SIMD3<Float>(x: Float(vertex.x), y: Float(vertex.y), z: Float(vertex.z))
                let rotated = quat.act(v)
                let transformed = rotated + midpoint
                batchVertices.append(SCNVector3(x: CGFloat(transformed.x),
                                               y: CGFloat(transformed.y),
                                               z: CGFloat(transformed.z)))
            }
            for normal in mesh.normals {
                let n = SIMD3<Float>(x: Float(normal.x), y: Float(normal.y), z: Float(normal.z))
                let rotated = quat.act(n)
                batchNormals.append(SCNVector3(x: CGFloat(rotated.x),
                                              y: CGFloat(rotated.y),
                                              z: CGFloat(rotated.z)))
            }
            for idx in mesh.indices {
                batchIndices.append(idx + startVertexIdx)
            }
            segmentFaceCount.append(mesh.indices.count / 3)

            let isSelectedSeg = (seg.cardIndex == selectedCard)
            // no debug coloring output
            let color = isSelectedSeg ? NSColor.systemYellow : NSColor.darkGray
            for _ in 0..<mesh.vertices.count {
                batchColors.append(color)
            }
            // selected segment color check (no logging)
        }

        if !batchVertices.isEmpty {
            let posSource = SCNGeometrySource(vertices: batchVertices)
            let normalSource = SCNGeometrySource(normals: batchNormals)
            var colorData: [UInt8] = []
            for color in batchColors {
                var r: CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=1
                if let rgb = color.usingColorSpace(.sRGB) {
                    rgb.getRed(&r, green:&g, blue:&b, alpha:&a)
                } else {
                    color.getRed(&r, green:&g, blue:&b, alpha:&a)
                }
                colorData.append(UInt8(r*255)); colorData.append(UInt8(g*255));
                colorData.append(UInt8(b*255)); colorData.append(UInt8(a*255))
            }
            // debug bytes removed
            let colorSource = SCNGeometrySource(data: Data(colorData),
                                                semantic: .color,
                                                vectorCount: batchVertices.count,
                                                usesFloatComponents: false,
                                                componentsPerVector: 4,
                                                bytesPerComponent: 1,
                                                dataOffset: 0,
                                                dataStride: 4)
            let indexData = Data(batchIndices.flatMap { index in
                withUnsafeBytes(of: index) { Array($0) }
            })
            let element = SCNGeometryElement(data: indexData,
                                             primitiveType: .triangles,
                                             primitiveCount: batchIndices.count/3,
                                             bytesPerIndex: MemoryLayout<UInt32>.size)
            let batchedGeometry = SCNGeometry(sources: [posSource, normalSource, colorSource],
                                             elements: [element])
            // no custom material: allow per-vertex colors to drive appearance
            batchedGeometry.firstMaterial?.lightingModel = .constant
            batchedGeometry.firstMaterial?.isDoubleSided = true
            let batchNode = SCNNode(geometry: batchedGeometry)
            batchNode.name = "geometryBatch"
            container.addChildNode(batchNode)

            // record metadata for coordinator so hit conversion & recolor work
            coordinator.segmentFaceCount = segmentFaceCount
            coordinator.segmentIndexMap = segmentIndexMap

            // (no proxies; selection via face index)
        }

        scene.rootNode.addChildNode(container)

        // Add handles for the currently selected card (if any)
        if let sel = selectedCard,
           !geometry.isEmpty {
            let cardSegs = geometry.filter { $0.cardIndex == sel }
            if !cardSegs.isEmpty {
                coordinator.addLineHandles(to: scene, cardSegments: cardSegs)
            }
        }

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
class Coordinator: NSObject, GeometryViewDragDelegate, SCNSceneRendererDelegate {
    var parent: GeometryView
    /// Cached geometry from the last scene build.
    var lastGeometry: [GeometrySegment]?
    /// Last selected card index; used for cheap recolor path.
    var lastSelectedCard: Int? = nil
    /// Number of triangle faces contributed by each segment; used for hit testing
    var segmentFaceCount: [Int] = []
    /// Map from vertex ranges to card indices, for color updates.
    var segmentIndexMap: [(startIndex: UInt32, vertexCount: UInt32, cardIndex: Int)] = []
    /// Camera node preserved between scene rebuilds so we retain orientation/zoom.
    var cameraNode: SCNNode? = nil

    // current drag/interaction state (Phase B)
    var dragState: GeometryView.DragState = .idle

    /// store the most recent camera transform so we can restore it even when
    /// camera control is temporarily turned off during a drag.  This avoids the
    /// view resetting to its default position after edits.
    var savedCameraTransform: SCNMatrix4? = nil
    /// true while we're in the middle of a handle drag and have disabled
    /// camera control; used to determine whether mouseUp should reapply the
    /// saved transform.
    var restoringCameraAfterDrag: Bool = false

    // snapping helpers (Phase D)
    enum SnapType { case endpoint, midpoint }
    struct SnapResult {
        let point: SCNVector3
        let type: SnapType
        let cardIndex: Int
    }
    var containerOffset: SCNVector3 = SCNVector3Zero
    var snapTargets: [SnapResult] = []
    var snapIndicator: SCNNode? = nil
    var activeSnap: SnapResult? = nil

    // modifier-key state (Phase C)
    var axisLock: GeometryView.Axis? = nil    // X/Y/Z letters
    var rotationLock: Bool = false           // ⌘ held
    var precisionLock: Bool = false          // ⇧ held

    // visual helper shown during drag to indicate the active constraint
    private var guideNode: SCNNode? = nil
    private var dimensionNode: SCNNode? = nil

    init(_ parent: GeometryView) {
        self.parent = parent
    }

    // MARK: – Keyboard handling for constraint modifiers

    func keyDown(_ event: NSEvent) {
        // allow Escape to cancel an active drag
        if event.keyCode == 53 { // ESC
            if case .dragging(_, let node, let start, _) = dragState {
                node.worldPosition = start
                dragState = .idle
                clearGuide()
                clearSnapIndicator()
                clearDimensionOverlay()
            }
            return
        }
        // track letter locks
        if let ch = event.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "x": axisLock = .x
            case "y": axisLock = .y
            case "z": axisLock = .z
            default: break
            }
        }
        // the modifier flags tell us about cmd/shift/option too
        let flags = event.modifierFlags
        rotationLock = flags.contains(.command)
        precisionLock = flags.contains(.shift)
    }

    func keyUp(_ event: NSEvent) {
        if let ch = event.charactersIgnoringModifiers?.lowercased() {
            switch ch {
            case "x" where axisLock == .x: axisLock = nil
            case "y" where axisLock == .y: axisLock = nil
            case "z" where axisLock == .z: axisLock = nil
            default: break
            }
        }
        let flags = event.modifierFlags
        rotationLock = flags.contains(.command)
        precisionLock = flags.contains(.shift)
    }

    /// Return the card index associated with a given vertex in the batched
    /// geometry.  Returns -1 if the vertex doesn’t belong to any segment.
    func cardIndexForVertex(_ vidx: Int) -> Int {
        for entry in segmentIndexMap {
            let start = Int(entry.startIndex)
            let end = start + Int(entry.vertexCount)
            if vidx >= start && vidx < end {
                return entry.cardIndex
            }
        }
        return -1
    }


    /// Add three spherical handles for a wire: green at the first end,
    /// cyan at the midpoint, and red at the far end.
    /// `cardSegments` must be all NEC sub-segments belonging to the same card,
    /// ordered so that `cardSegments.first` starts at the wire's first endpoint
    /// and `cardSegments.last` ends at its second endpoint.
    public func addLineHandles(to scene: SCNScene, cardSegments: [GeometrySegment]) {
        guard let first = cardSegments.first, let last = cardSegments.last else { return }
        let start = SCNVector3(first.start.x,
                               first.start.y,
                               first.start.z)
        let end   = SCNVector3(last.end.x,
                               last.end.y,
                               last.end.z)
        let mid = SCNVector3((start.x + end.x) / 2,
                             (start.y + end.y) / 2,
                             (start.z + end.z) / 2)

        // compute handle radius using the same base formula we used for
        // the cylinder geometry.  handles should be noticeably larger than
        // the wire itself, so apply a separate multiplier and clamp to a
        // sensible minimum.
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dz = end.z - start.z
        let segLen = CGFloat(sqrt(dx*dx + dy*dy + dz*dz))
        let globalScale = CGFloat(parent.radiusScale)
        var wireRadius: CGFloat
        // all segments on this card share the same radius; read from F7 if
        // specified, otherwise fall back to the heuristic.
        let explicitRadius = CGFloat(first.radius)
        if explicitRadius > 0 {
            wireRadius = explicitRadius
        } else {
            wireRadius = max(segLen * 0.002 * globalScale, 0.002 * globalScale)
            if parent.exaggerateDiameters {
                let threshold = segLen * 0.02 * globalScale
                if wireRadius < threshold { wireRadius *= 5 }
            }
        }
        // make the handle bigger than the wire so it’s easy to grab; also
        // enforce a minimum size based on the segment length so tiny wires still
        // produce a visible sphere.
        var radius = wireRadius * 1.5
        radius = max(radius, segLen * 0.05)
        radius = max(radius, 0.01)   // final safety clamp
        func sphere(color: NSColor, name: String) -> SCNNode {
            let sph = SCNSphere(radius: radius)
            if let mat = sph.firstMaterial {
                mat.diffuse.contents = color
                mat.lightingModel = .constant
            }
            let node = SCNNode(geometry: sph)
            // include card index in name so hitHandle can decode it reliably
            node.name = "handle_\(name)_card_\(first.cardIndex)"
            return node
        }

        let h1 = sphere(color: .systemGreen, name: "start")
        h1.position = start
        let h2 = sphere(color: .systemTeal, name: "mid")
        h2.position = mid
        let h3 = sphere(color: .systemRed, name: "end")
        h3.position = end

        // add handles to the same container that holds the segment geometry
        // so they inherit the centering/scale transform applied during scene
        // construction.
        if let container = scene.rootNode.childNode(withName: "geometryContainer", recursively: true) {
            container.addChildNode(h1)
            container.addChildNode(h2)
            container.addChildNode(h3)
        } else {
            // fallback – shouldn't happen, but avoid dropping handles entirely
            scene.rootNode.addChildNode(h1)
            scene.rootNode.addChildNode(h2)
            scene.rootNode.addChildNode(h3)
        }
    }

    @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard let scnView = gesture.view as? SCNView else { return }
        let loc = gesture.location(in: scnView)
        // hit the batched geometry and derive the card from face index
        let hits = scnView.hitTest(loc, options: nil)
        if let hit = hits.first {
            let face = Int(hit.faceIndex)
            var cum = 0
            if let geom = self.lastGeometry {
                for (segIdx, count) in self.segmentFaceCount.enumerated() {
                    if face < cum + count {
                        let card = geom[segIdx].cardIndex
                        DispatchQueue.main.async {
                            self.parent.onSelect(card)
                        }
                        return
                    }
                    cum += count
                }
            }
        }
        // try without mask to see if any geometry is hit at all
        let allHits = scnView.hitTest(loc, options: nil)
        for _ in allHits {
        }
        DispatchQueue.main.async {
            self.parent.onSelect(nil)
        }
        // no selection; scene update will reflect this
    }

    // MARK: - Drag helpers

    /// convert a window-space point to the first world coordinate hit by ray
    private func worldPoint(from windowPoint: NSPoint, in view: SCNView) -> SCNVector3? {
        let local = view.convert(windowPoint, from: nil)
        let hits = view.hitTest(local, options: nil)
        return hits.first?.worldCoordinates
    }

    /// compute the world-space axis (origin and unit direction) for the given card
    private func axisFor(card: Int, relativeTo node: SCNNode) -> (origin: SCNVector3, dir: SCNVector3)? {
        guard let seg = parent.geometry.first(where: { $0.cardIndex == card }),
              let cont = node.parent else { return nil }
        let p1 = SCNVector3(CGFloat(seg.start.x), CGFloat(seg.start.y), CGFloat(seg.start.z))
        let p2 = SCNVector3(CGFloat(seg.end.x),   CGFloat(seg.end.y),   CGFloat(seg.end.z))
        let w1 = cont.convertPosition(p1, to: nil)
        let w2 = cont.convertPosition(p2, to: nil)
        let dir = (w2 - w1).normalized()
        return (origin: w1, dir: dir)
    }

    /// world-space midpoint of the given card’s geometry, or nil if not found
    private func worldMidpointFor(card: Int, relativeTo node: SCNNode) -> SCNVector3? {
        guard let seg = parent.geometry.first(where: { $0.cardIndex == card }),
              let cont = node.parent else { return nil }
        let p1 = SCNVector3(CGFloat(seg.start.x), CGFloat(seg.start.y), CGFloat(seg.start.z))
        let p2 = SCNVector3(CGFloat(seg.end.x),   CGFloat(seg.end.y),   CGFloat(seg.end.z))
        let w1 = cont.convertPosition(p1, to: nil)
        let w2 = cont.convertPosition(p2, to: nil)
        return (w1 + w2) * CGFloat(0.5)
    }

    /// Given a finished drag, compute deck-space start/end coordinates.
    /// Returns (cardIndex, newStart?, newEnd?) where only one of the two
    /// coordinate triples is non‑nil depending on which handle was moved.
    /// Compute deck-space coordinates after a drag.  `startWorld` is the
    /// original world-space position of the dragged handle (extracted from
    /// `dragState` by the caller).  For mid drags we translate both endpoints.
    private func deckCoords(afterDrag hid: HandleID,
                            startWorld: SCNVector3,
                            worldPos: SCNVector3) -> (Int, SIMD3<Float>?, SIMD3<Float>?)? {
        switch hid {
        case .mid(let card):
            // compute translation delta in container space
            if let node = dragStateNode(for: hid), let cont = node.parent,
               let seg = parent.geometry.first(where: { $0.cardIndex == card }) {
                let startLocal = cont.convertPosition(startWorld, from: nil)
                let endLocal   = cont.convertPosition(worldPos, from: nil)
                print("[deckCoords] mid startLocal=\(startLocal) endLocal=\(endLocal)")
                let delta = SIMD3<Float>(Float(endLocal.x - startLocal.x),
                                         Float(endLocal.y - startLocal.y),
                                         Float(endLocal.z - startLocal.z))
                let origStart = SIMD3<Float>(Float(seg.start.x),
                                             Float(seg.start.y),
                                             Float(seg.start.z))
                let origEnd   = SIMD3<Float>(Float(seg.end.x),
                                             Float(seg.end.y),
                                             Float(seg.end.z))
                return (card, origStart + delta, origEnd + delta)
            }
            return nil
        case .start(let card):
            // convert world back to container-local
            if let node = dragStateNode(for: hid) {
                guard let cont = node.parent else { break }
                let local = cont.convertPosition(worldPos, from: nil)
                print("[deckCoords] startLocal=\(local) world=\(worldPos)")
                let v = SIMD3<Float>(Float(local.x), Float(local.y), Float(local.z))
                return (card, v, nil)
            }
        case .end(let card):
            if let node = dragStateNode(for: hid) {
                guard let cont = node.parent else { break }
                let local = cont.convertPosition(worldPos, from: nil)
                let v = SIMD3<Float>(Float(local.x), Float(local.y), Float(local.z))
                return (card, nil, v)
            }
        }
        return nil
    }

    /// helper to pull the current node from dragState for a given handle id
    private func dragStateNode(for hid: HandleID) -> SCNNode? {
        if case .dragging(let existing, let node, _, _) = dragState,
           existing == hid {
            return node
        }
        return nil
    }

    /// detect a drag handle under the pointer, returning its ID and world pos
    private func hitHandle(at windowPoint: NSPoint, in view: SCNView) -> (HandleID, SCNNode, SCNVector3)? {
        let local = view.convert(windowPoint, from: nil)
        let hits = view.hitTest(local, options: nil)
        print("[hitHandle] window=\(windowPoint) local=\(local) hits=\(hits.count)")
        for hit in hits {
            if let name = hit.node.name, name.hasPrefix("handle_") {
                print("[hitHandle] found handle node \(name)")
                // name format: handle_<kind>_card_<index>
                let parts = name.split(separator: "_")
                guard parts.count == 4,
                      parts[0] == "handle",
                      parts[2] == "card",
                      let cardIdx = Int(parts[3])
                else { continue }
                let kind = String(parts[1])
                let hid: HandleID
                switch kind {
                case "start": hid = .start(card: cardIdx)
                case "mid":   hid = .mid(card: cardIdx)
                case "end":   hid = .end(card: cardIdx)
                default: continue
                }
                return (hid, hit.node, hit.worldCoordinates)
            }
        }
        return nil
    }

    // MARK: - GeometryViewDragDelegate


    /// Compute which constraint should apply based on handle, current locks
    private func computeConstraint(hid: HandleID, node: SCNNode, worldPoint: SCNVector3) -> DragConstraint {
        // option key = free regardless of anything else
        if let flags = NSApp.currentEvent?.modifierFlags, flags.contains(.option) {
            return .free
        }
        // rotation mode has highest precedence
        if rotationLock {
            // compute center/axis for rotation based on handle's card
            switch hid {
            case .start(let card), .end(let card), .mid(let card):
                if let (origin, dir) = axisFor(card: card, relativeTo: node) {
                    // compute true midpoint in world space if possible
                    if let mid = worldMidpointFor(card: card, relativeTo: node) {
                        return .rotation(center: mid, axis: dir)
                    } else {
                        return .rotation(center: origin, axis: dir)
                    }
                }
                return .free
            }
        }
        // world axis/plane locks from letter keys
        if let ax = axisLock {
            if let flags = NSApp.currentEvent?.modifierFlags, flags.contains(.shift) {
                return .worldPlane(ax)
            } else {
                return .worldAxis(ax)
            }
        }
        // default shape-specific behaviour
        switch hid {
        case .mid:
            return .free
        case .start(let card), .end(let card):
            if let (origin, dir) = axisFor(card: card, relativeTo: node) {
                return .axial(origin: origin, direction: dir)
            } else {
                return .free
            }
        }
    }

    /// Update the on-screen guide element for the given constraint.
    private func updateGuide(_ constraint: DragConstraint, in scn: SCNScene?, relativeTo node: SCNNode) {
        // remove old guide if any
        guideNode?.removeFromParentNode()
        guard let scene = scn else { return }
        var g: SCNNode?
        switch constraint {
        case .axial(let origin, let dir):
            // draw a long line through origin along dir
            let len: CGFloat =  CGFloat( (scene.rootNode.boundingSphere.radius) * 2 )
            let end1 = origin - dir * len
            let end2 = origin + dir * len
            g = parent.lineNode(from: end1, to: end2, color: .yellow)
        case .worldAxis(let axis):
            let dir = axis.vector
            let len: CGFloat = CGFloat(scene.rootNode.boundingSphere.radius) * 2
            g = parent.lineNode(from: dir * (-len), to: dir * len, color: .systemBlue)
        case .worldPlane(let axis):
            // simple square plane
            let size: CGFloat = CGFloat(scene.rootNode.boundingSphere.radius)
            let plane = SCNPlane(width: size, height: size)
            plane.firstMaterial?.diffuse.contents = NSColor.systemGreen.withAlphaComponent(0.2)
            plane.firstMaterial?.isDoubleSided = true
            let pn = SCNNode(geometry: plane)
            // orient plane perpendicular to axis vector
            pn.look(at: pn.position + axis.vector)
            g = pn
        default:
            break
        }
        if let guide = g {
            guide.name = "constraintGuide"
            scene.rootNode.addChildNode(guide)
            guideNode = guide
        }
    }

    /// Remove any existing constraint guide.
    private func clearGuide() {
        guideNode?.removeFromParentNode()
        guideNode = nil
    }

    // MARK: – Live dimension overlay (Phase E)

    private func clearDimensionOverlay() {
        dimensionNode?.removeFromParentNode()
        dimensionNode = nil
    }

    private func formatMeters(_ value: CGFloat) -> String {
        String(format: "%.3f m", value)
    }

    private func cardIndex(from handle: HandleID) -> Int {
        switch handle {
        case .start(let card), .mid(let card), .end(let card):
            return card
        }
    }

    private func worldWireLength(forCard card: Int, in container: SCNNode) -> CGFloat? {
        guard let startNode = container.childNode(withName: "handle_start_card_\(card)", recursively: false),
              let endNode = container.childNode(withName: "handle_end_card_\(card)", recursively: false)
        else { return nil }
        return (endNode.worldPosition - startNode.worldPosition).length()
    }

    private func updateDimensionOverlay(handle: HandleID,
                                        start: SCNVector3,
                                        current: SCNVector3,
                                        constraint: DragConstraint,
                                        in view: SCNView) {
        let scene = view.scene
        let delta = (current - start).length()
        var lines: [String] = []
        lines.append("Δ: \(formatMeters(delta))")
        lines.append(String(format: "X: %.3f  Y: %.3f  Z: %.3f", current.x, current.y, current.z))

        if case .start = handle,
           let cont = scene?.rootNode.childNode(withName: "geometryContainer", recursively: true),
           let length = worldWireLength(forCard: cardIndex(from: handle), in: cont) {
            lines.append("L: \(formatMeters(length))")
        }
        if case .end = handle,
           let cont = scene?.rootNode.childNode(withName: "geometryContainer", recursively: true),
           let length = worldWireLength(forCard: cardIndex(from: handle), in: cont) {
            lines.append("L: \(formatMeters(length))")
        }

        if case .rotation(let center, let axis) = constraint {
            let ax = axis.normalized()
            let v0 = start - center
            let v1 = current - center
            let p0 = v0 - ax * dot(v0, ax)
            let p1 = v1 - ax * dot(v1, ax)
            let n0 = p0.normalized()
            let n1 = p1.normalized()
            let c = max(-1.0 as CGFloat, min(1.0 as CGFloat, dot(n0, n1)))
            let angleDeg = acos(c) * 180 / .pi
            lines.append(String(format: "θ: %.1f°", angleDeg))
        }

        if let snap = activeSnap {
            let kind = (snap.type == .endpoint) ? "Endpoint" : "Midpoint"
            lines.append("Snap: \(kind)")
        }

        // project point to screen and show overlay label
        if let zoomView = view as? ZoomableSCNView {
            let projected = zoomView.projectPoint(current)
            print("[Overlay] dims=\(lines) proj=\(projected)")
            guard projected.z > 0 else {
                zoomView.hideOverlay()
                return
            }
            let screenPt = CGPoint(x: CGFloat(projected.x),
                                   y: zoomView.bounds.height - CGFloat(projected.y))
            zoomView.showOverlay(text: lines.joined(separator: "\n"), at: screenPt)
        }
    }

    // MARK: – Snapping helpers (Phase D)

    /// Populate `snapTargets` from the parent geometry array, converting to world
    /// coordinates using the most recent container offset.
    private func buildSnapTargets() {
        snapTargets.removeAll()
        for seg in parent.geometry {
            let start = SCNVector3(CGFloat(seg.start.x), CGFloat(seg.start.y), CGFloat(seg.start.z)) + containerOffset
            let end   = SCNVector3(CGFloat(seg.end.x),   CGFloat(seg.end.y),   CGFloat(seg.end.z)) + containerOffset
            snapTargets.append(SnapResult(point: start, type: .endpoint, cardIndex: seg.cardIndex))
            snapTargets.append(SnapResult(point: end, type: .endpoint, cardIndex: seg.cardIndex))
            let mid = SCNVector3((start.x+end.x)/2, (start.y+end.y)/2, (start.z+end.z)/2)
            snapTargets.append(SnapResult(point: mid, type: .midpoint, cardIndex: seg.cardIndex))
        }
    }

    /// Check whether `pos` is within snap threshold for any target; if so,
    /// update `snapIndicator` and return the snapped coordinate.
    private func checkSnap(position pos: SCNVector3, in scene: SCNScene?) -> SCNVector3? {
        let thresh: CGFloat = 0.02  // metres; later convert from screen space
        var best: (SnapResult, CGFloat)? = nil
        for t in snapTargets {
            let d = (pos - t.point).length()
            if d < thresh {
                if best == nil || d < best!.1 {
                    best = (t, d)
                }
            }
        }
        if let (target, _) = best {
            activeSnap = target
            showSnapIndicator(at: target.point, type: target.type, scene: scene)
            return target.point
        } else {
            clearSnapIndicator()
            return nil
        }
    }

    private func showSnapIndicator(at pt: SCNVector3, type: SnapType, scene: SCNScene?) {
        snapIndicator?.removeFromParentNode()
        let color: NSColor = (type == .endpoint ? .cyan : .magenta)
        let sphere = SCNSphere(radius: 0.01)
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: sphere)
        node.position = pt
        node.name = "snapIndicator"
        if let s = scene {
            s.rootNode.addChildNode(node)
        }
        snapIndicator = node
    }

    private func clearSnapIndicator() {
        snapIndicator?.removeFromParentNode()
        snapIndicator = nil
        activeSnap = nil
    }

    func mouseDown(at point: NSPoint, in view: SCNView) {
        // ensure camera is being tracked continuously while interacting
        view.delegate = self
        // hide any previous overlay text
        if let zv = view as? ZoomableSCNView { zv.hideOverlay() }
        // only turn off camera control if the user actually grabbed a handle
        if let (hid, node, world) = hitHandle(at: point, in: view) {
            // save current camera transform before disabling camera control;
            // we'll restore it later in mouseUp or updateNSView so the view
            // doesn't jump back to origin after edits.
            savedCameraTransform = view.pointOfView?.transform
            restoringCameraAfterDrag = true
            view.allowsCameraControl = false
            // reset modifier locks
            axisLock = nil
            rotationLock = false
            precisionLock = false
            // build snap target list from current geometry
            buildSnapTargets()
            // begin drag state; snapshot placeholder
            dragState = .dragging(handle: hid, node: node, startWorld: world, preSnapshot: "")
        }
    }
    func mouseDragged(at point: NSPoint, in view: SCNView) {
        print("[mouseDragged] called point=\(point) state=\(dragState)")
        guard case .dragging(let hid, let node, let start, _) = dragState else { return }
        guard let world = worldPoint(from: point, in: view) else {
            print("[mouseDragged] worldPoint nil")
            return
        }
        print("[mouseDragged] world=\(world)\n")

        // update locks from current event flags (cmd, opt, shift)
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        rotationLock = flags.contains(.command)
        precisionLock = flags.contains(.shift)
        // option key simply switches to free; no state needed

        // determine constraint for this drag
        let constraint = computeConstraint(hid: hid, node: node, worldPoint: world)

        // apply the constraint projection
        let constrained: SCNVector3
        switch constraint {
        case .free:
            constrained = world
        case .axial(let origin, let dir):
            let v = world - origin
            let t = dot(v, dir)
            constrained = origin + dir * t
        case .worldAxis(let axis):
            let dir = axis.vector.normalized()
            let v = world
            let t = dot(v, dir)
            constrained = dir * t
        case .worldPlane(let axis):
            let normal = axis.vector.normalized()
            let v = world
            let d = dot(v, normal)
            constrained = v - normal * d
        case .rotation(let center, let axis):
            // project world onto circle around center, in plane perp to axis
            let v = world - center
            let ax = axis.normalized()
            let proj = v - ax * dot(v, ax)
            let r = proj.length()
            let u = proj.normalized()
            constrained = center + u * r
        }

        // allow snapping to override the computed position
        let finalPosition: SCNVector3
        if let snap = checkSnap(position: constrained, in: view.scene) {
            finalPosition = snap
        } else {
            finalPosition = constrained
        }
        node.worldPosition = finalPosition
        // TODO: use precisionLock to scale movement (later)
        updateGuide(constraint, in: view.scene, relativeTo: node)
        updateDimensionOverlay(handle: hid,
                               start: start,
                               current: finalPosition,
                               constraint: constraint,
                               in: view)
    }
    func mouseUp(at point: NSPoint, in view: SCNView) {
        // hide overlay when drag finishes
        if let zv = view as? ZoomableSCNView { zv.hideOverlay() }
        // stop tracking when drag ends; normal camera moves still tracked via delegate
        view.delegate = self
        // restore camera control after any drag attempt.  reapply saved
        // transform only if we previously disabled camera control for a
        // handle drag; otherwise the user may have freely moved the camera
        // and we don't want to snap it back.
        view.allowsCameraControl = true
        if restoringCameraAfterDrag, let cam = savedCameraTransform {
            view.pointOfView?.transform = cam
        }
        restoringCameraAfterDrag = false
        switch dragState {
        case .idle: break
        case .dragging(let hid, let node, let startWorld, _):
            let world = node.worldPosition
            // compute deck coordinate and notify parent; worldPoint may be nil
            let result = deckCoords(afterDrag: hid,
                                    startWorld: startWorld,
                                    worldPos: world)
            if let (card,newStart,newEnd) = result {
                parent.onDragCommit(card, newStart, newEnd)
            }
            dragState = .idle
            clearGuide()
            clearSnapIndicator()
            clearDimensionOverlay()
        }
    }

    // MARK: – SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let view = renderer as? SCNView,
              let cam = view.pointOfView?.transform else { return }
        DispatchQueue.main.async {
            self.parent.cameraTransform = cam
        }
    }
}

} // end struct GeometryView

#if DEBUG
extension GeometryView {
    struct Preview: PreviewProvider {
        static let sampleGeom: [GeometrySegment] = [
            GeometrySegment(start: SIMD3(-1,0,0), end: SIMD3(1,0,0), cardIndex: 0, radius: 0),
            GeometrySegment(start: SIMD3(0,-1,0), end: SIMD3(0,1,0), cardIndex: 1, radius: 0)
        ]
        static var previews: some View {
            GeometryView(geometry: sampleGeom, selectedCard: nil, cameraTransform: .constant(nil), onSelect: { _ in }, onDragCommit: { _,_,_ in })
                .frame(width: 300, height: 300)
        }
    }
}
#endif
