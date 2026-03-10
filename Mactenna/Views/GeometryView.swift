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
}

/// SCNView subclass providing wheel‑zoom behaviour identical to PatternView,
/// plus forwarding of mouse events to a delegate.
fileprivate final class ZoomableSCNView: SCNView {
    weak var dragDelegate: GeometryViewDragDelegate?

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
}

struct GeometryView: NSViewRepresentable {
    /// Geometry segments to render.
    let geometry: [GeometrySegment]
    /// Currently selected card index (or nil).
    var selectedCard: Int?
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
        case dragging(handle: HandleID, node: SCNNode, startWorld: SCNVector3, preSnapshot: String)
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
        // always rebuild the scene and reapply the current selection colour.
        // the camera transform is preserved so the view doesn't jump.
        guard scnView.scene != nil else {
            scnView.scene = makeScene(coordinator: context.coordinator)
            context.coordinator.lastGeometry = geometry
            return
        }
        // prefer the view's pointOfView as that's what user interaction
        // actually manipulates.
        let previousCameraTransform = scnView.pointOfView?.transform
        scnView.scene = makeScene(coordinator: context.coordinator)
        if let camTransform = previousCameraTransform {
            scnView.pointOfView?.transform = camTransform
        }
        context.coordinator.lastGeometry = geometry
    }

    private func makeScene(coordinator: Coordinator) -> SCNScene {
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

        // compute camera distance
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
class Coordinator: NSObject, GeometryViewDragDelegate {
    var parent: GeometryView
    /// Cached geometry from the last scene build.
    var lastGeometry: [GeometrySegment]?
    /// Last selected card index; used to implement cheap recolor path.
    var lastSelectedCard: Int? = nil
    /// Number of triangle faces contributed by each segment; used for hit testing
    var segmentFaceCount: [Int] = []
    /// Map from vertex ranges to card indices, for color updates.
    var segmentIndexMap: [(startIndex: UInt32, vertexCount: UInt32, cardIndex: Int)] = []

    // current drag/interaction state (Phase B)
    var dragState: GeometryView.DragState = .idle

    init(_ parent: GeometryView) {
        self.parent = parent
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
        for hit in allHits {
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

    /// Given a finished drag, compute deck-space start/end coordinates.
    /// Returns (cardIndex, newStart?, newEnd?) where only one of the two
    /// coordinate triples is non‑nil depending on which handle was moved.
    private func deckCoords(afterDrag hid: HandleID, worldPos: SCNVector3) -> (Int, SIMD3<Float>?, SIMD3<Float>?)? {
        switch hid {
        case .mid:
            return nil
        case .start(let card):
            // convert world back to container-local
            if let node = dragStateNode(for: hid) {
                guard let cont = node.parent else { break }
                let local = cont.convertPosition(worldPos, from: nil)
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
        for hit in hits {
            if let name = hit.node.name, name.hasPrefix("handle_") {
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
    func mouseDown(at point: NSPoint, in view: SCNView) {
        // only turn off camera control if the user actually grabbed a handle
        if let (hid, node, world) = hitHandle(at: point, in: view) {
            view.allowsCameraControl = false
            // begin drag state; snapshot placeholder
            dragState = .dragging(handle: hid, node: node, startWorld: world, preSnapshot: "")
            print("begin drag \(hid) at \(world)")
        }
    }
    func mouseDragged(at point: NSPoint, in view: SCNView) {
        guard case .dragging(let hid, let node, let start, _) = dragState else { return }
        guard let world = worldPoint(from: point, in: view) else { return }
        // apply simple axial constraint when dragging start/end of GW
        let constrained: SCNVector3
        switch hid {
        case .mid:
            // free translation: unproject the screen point back onto the same
            // camera-view plane as the handle's original position.  This keeps
            // the handle tied to the view's depth and prevents it from drifting
            // in world‑z when the container orientation changes.
            let local = view.convert(point, from: nil)
            var proj = view.projectPoint(node.worldPosition)
            proj.x = CGFloat(Float(local.x)); proj.y = CGFloat(Float(local.y))
            constrained = view.unprojectPoint(proj)
        case .start(let card), .end(let card):
            if let (origin, dir) = axisFor(card: card, relativeTo: node) {
                // project world point onto the world-space axis
                let v = world - origin
                let t = dot(v, dir)
                constrained = origin + dir * t
            } else {
                constrained = world
            }
        }
        node.worldPosition = constrained
        print("dragging \(hid) -> \(constrained)")
    }
    func mouseUp(at point: NSPoint, in view: SCNView) {
        // restore camera control after any drag attempt
        view.allowsCameraControl = true
        switch dragState {
        case .idle: break
        case .dragging(let hid, let node, _, let snap):
            if let world = worldPoint(from: point, in: view) {
                print("end drag \(hid) at \(world) snapshot=\(snap)")
                // compute deck coordinate and notify parent
                if let (card,newStart,newEnd) = deckCoords(afterDrag: hid, worldPos: node.worldPosition) {
                    parent.onDragCommit(card, newStart, newEnd)
                }
            }
            dragState = .idle
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
            GeometryView(geometry: sampleGeom, selectedCard: nil, onSelect: { _ in }, onDragCommit: { _,_,_ in })
                .frame(width: 300, height: 300)
        }
    }
}
#endif
