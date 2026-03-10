//
//  PatternView.swift
//  Mactenna
//
//  SceneKit-based viewer for 3D radiation patterns (Phase 4).
//  Renders a continuous triangular mesh derived from the NEC output data;
//  falls back to scattered points when the pattern is incomplete.
//

import SwiftUI
import SceneKit

// helpers for vector math
fileprivate func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}
// multiply by a scalar which may be Float or CGFloat (convert to Float)
fileprivate func *(lhs: SCNVector3, rhs: CGFloat) -> SCNVector3 {
    // convert rhs to Float for uniformity, then back to CGFloat for component
    let g = CGFloat(rhs)
    return SCNVector3(lhs.x * g, lhs.y * g, lhs.z * g)
}

// overload taking Float directly, forwards to CGFloat version
fileprivate func *(lhs: SCNVector3, rhs: Float) -> SCNVector3 {
    return lhs * CGFloat(rhs)
}

/// SCNView subclass that interprets scroll-wheel as zoom along the camera's
/// look direction.  Default SceneKit behaviour may not respect custom camera
/// orientations (e.g. when looking along +X), so we implement our own.
fileprivate final class ZoomableSCNView: SCNView {
    override func scrollWheel(with event: NSEvent) {
        if let cam = scene?.rootNode.childNodes.first(where: { $0.camera != nil }) {
            let dir = cam.worldFront // unit vector pointing in view direction
            let delta = Float(event.scrollingDeltaY) * 0.1
            cam.position = cam.position + dir * delta
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// simple segment representation shared by view and deck model
struct GeometrySegment: Equatable, Hashable {
    let start: SIMD3<Float>
    let end:   SIMD3<Float>
    let cardIndex: Int
}


struct PatternView: NSViewRepresentable {
    /// Radiation pattern points to display.  Coordinates are in degrees and
    /// gain is in dBi.  All values are provided by SimulationResult.
    let points: [SimulationResult.RadiationPoint]
    let maxGain: Double  // used to normalise radius

    // NOTE: selection and interaction moved to GeometryView; this view is
    // now strictly for rendering the pattern mesh (with overlaid geometry).

    // MARK: – colour helpers

    /// Returns the colour used for a normalized gain value (0…1) when rendering
    /// the mesh in SceneKit.
    static func nsColor(forNorm norm: Double) -> NSColor {
        let hue = CGFloat(0.66 - 0.66 * norm) // blue->red
        return NSColor(calibratedHue: hue, saturation: 1, brightness: 1, alpha: 1)
    }

    /// SwiftUI equivalent of `nsColor(forNorm:)`.  Used for the legend view.
    static func swiftUIColor(forNorm norm: Double) -> Color {
        Color(nsColor(forNorm: norm))
    }

    func makeNSView(context: Context) -> SCNView {
        let scnView = ZoomableSCNView()
        scnView.scene = makeScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = NSColor.windowBackgroundColor
        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        // rebuild geometry whenever points change
        scnView.scene = makeScene()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // camera – sit a bit along negative X and look toward origin so the
        // view direction is +X.  Use +Z as up so the Y axis appears to the left.
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: -5, y: 0, z: 0)
        cameraNode.look(at: SCNVector3Zero,
                        up: SCNVector3(0,0,1),
                        localFront: SCNVector3(0,0,-1))
        scene.rootNode.addChildNode(cameraNode)

        // axes helper – extend by 50% (1 → 1.5) and add labels
        let axis = SCNNode()
        let axisLength: CGFloat = 1.5
        axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(axisLength,0,0), color: .red))
        axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(0,axisLength,0), color: .green))
        axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(0,0,axisLength), color: .blue))

        func labelNode(_ text: String, color: NSColor, position: SCNVector3) -> SCNNode {
            let txt = SCNText(string: text, extrusionDepth: 0.1)
            txt.font = NSFont.systemFont(ofSize: 0.4)  // twice as large
            txt.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: txt)
            // centre the text around its origin
            let (min, max) = txt.boundingBox
            let dx = (max.x + min.x) / 2
            let dy = (max.y + min.y) / 2
            node.pivot = SCNMatrix4MakeTranslation(dx, dy, 0)
            node.scale = SCNVector3(0.4, 0.4, 0.4)     // match the font size increase
            node.position = position
            return node
        }
        axis.addChildNode(labelNode("X", color: .red,   position: SCNVector3(axisLength,0,0)))
        axis.addChildNode(labelNode("Y", color: .green, position: SCNVector3(0,axisLength,0)))
        axis.addChildNode(labelNode("Z", color: .blue,  position: SCNVector3(0,0,axisLength)))
        scene.rootNode.addChildNode(axis)

        // build a continuous mesh from the pattern points
        // determine unique ordered theta/phi values so we can index the grid
        let thetas = Array(Set(points.map { $0.theta })).sorted()
        let phis   = Array(Set(points.map { $0.phi })).sorted()
        if !thetas.isEmpty && !phis.isEmpty {
            let nTheta = thetas.count
            let nPhi   = phis.count
            // require full grid; otherwise fall back to scatter
            guard points.count == nTheta * nPhi, nTheta >= 2, nPhi >= 1 else {
                // incomplete grid; draw points individually
                let parent = SCNNode()
                for pt in points {
                    let theta = pt.theta * .pi / 180.0
                    let phi   = pt.phi   * .pi / 180.0
                    let norm = maxGain > 0 ? max(0.0, pt.gain) / maxGain : 0.0
                    let r = Float(1.0 + norm * 2.0)
                    let x = r * sin(Float(theta)) * cos(Float(phi))
                    let y = r * sin(Float(theta)) * sin(Float(phi))
                    let z = r * cos(Float(theta))
                    let sphere = SCNSphere(radius: 0.02)
                    sphere.firstMaterial?.diffuse.contents = NSColor.systemOrange
                    let node = SCNNode(geometry: sphere)
                    node.position = SCNVector3(x,y,z)
                    parent.addChildNode(node)
                }
                scene.rootNode.addChildNode(parent)
                return scene
            }
            // map from (i,j) to point
            var grid = Array(repeating: Array(repeating: points[0], count: nPhi), count: nTheta)
            for pt in points {
                if let i = thetas.firstIndex(of: pt.theta),
                   let j = phis.firstIndex(of: pt.phi) {
                    grid[i][j] = pt
                }
            }

            // vertex positions & colors
            var vertices: [SCNVector3] = []
            var colors: [Float] = [] // RGBA floats
            vertices.reserveCapacity(nTheta * nPhi)
            colors.reserveCapacity(nTheta * nPhi * 4)

            for i in 0..<nTheta {
                for j in 0..<nPhi {
                    let pt = grid[i][j]
                    let theta = pt.theta * .pi / 180.0
                    let phi   = pt.phi   * .pi / 180.0
                    let norm = maxGain > 0 ? max(0.0, pt.gain) / maxGain : 0.0
                    let r = Float(1.0 + norm * 2.0)
                    let x = CGFloat(r * sin(Float(theta)) * cos(Float(phi)))
                    let y = CGFloat(r * sin(Float(theta)) * sin(Float(phi)))
                    let z = CGFloat(r * cos(Float(theta)))
                    vertices.append(SCNVector3(x,y,z))
                    // colour by gain: hue from 0 (blue) to 0.33 (green) to 0 (red)
                    let hue = CGFloat(0.66 - 0.66 * norm) // blue->red
                    let col = NSColor(calibratedHue: hue, saturation: 1, brightness: 1, alpha: 1)
                    var red: CGFloat=0, gr: CGFloat=0, bl: CGFloat=0, al: CGFloat=0
                    col.getRed(&red, green: &gr, blue: &bl, alpha: &al)
                    colors.append(Float(red))
                    colors.append(Float(gr))
                    colors.append(Float(bl))
                    colors.append(Float(al))
                }
            }

            let vertexSource = SCNGeometrySource(vertices: vertices)

            // normals are no longer required when using constant lighting,
            // but keep the calculation in case we revert to a lit model later.
            var normals: [SCNVector3] = []
            normals.reserveCapacity(vertices.count)
            for v in vertices {
                let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
                if len > 0 {
                    normals.append(SCNVector3(v.x/len, v.y/len, v.z/len))
                } else {
                    normals.append(SCNVector3Zero)
                }
            }
            let normalSource = SCNGeometrySource(normals: normals)

            let colorData: Data = colors.withUnsafeBufferPointer { buf in
                Data(buffer: buf)
            }
            let colorSource = SCNGeometrySource(data: colorData,
                                               semantic: .color,
                                               vectorCount: vertices.count,
                                               usesFloatComponents: true,
                                               componentsPerVector: 4,
                                               bytesPerComponent: MemoryLayout<Float>.size,
                                               dataOffset: 0,
                                               dataStride: MemoryLayout<Float>.size * 4)

            // build triangle indices
            var indices: [Int32] = []
            for i in 0..<(nTheta - 1) {
                for j in 0..<nPhi {
                    let j2 = (j + 1) % nPhi
                    let v00: Int32 = Int32(i * nPhi + j)
                    let v10: Int32 = Int32((i + 1) * nPhi + j)
                    let v11: Int32 = Int32((i + 1) * nPhi + j2)
                    let v01: Int32 = Int32(i * nPhi + j2)
                    // two triangles per quad
                    indices.append(contentsOf: [v00, v10, v11, v00, v11, v01])
                }
            }
            let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
            let elem = SCNGeometryElement(data: indexData,
                                         primitiveType: .triangles,
                                         primitiveCount: indices.count / 3,
                                         bytesPerIndex: MemoryLayout<Int32>.size)
            let geom = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [elem])
            let mat = SCNMaterial()
            mat.lightingModel = .constant   // unlit: display vertex colors exactly
            mat.isDoubleSided = true
            mat.transparency = 1.0          // opaque pattern mesh
            // ensure we blend using alpha so overlapping parts are visible
            mat.transparencyMode = .aOne
            geom.firstMaterial = mat
            let meshNode = SCNNode(geometry: geom)
        // avoid interfering with hit-testing; pattern mesh belongs to mask 1
        meshNode.categoryBitMask = 1

            // compute bounding box of the pattern mesh itself so we can
            // centre it in the scene.  We do not scale to any external
            // geometry – that responsibility now lies with the separate
            // GeometryView.
            let (patternMin, patternMax) = geom.boundingBox
            let patCenter = SCNVector3((patternMin.x+patternMax.x)/2,
                                       (patternMin.y+patternMax.y)/2,
                                       (patternMin.z+patternMax.z)/2)
            func radius(from minB: SCNVector3, to maxB: SCNVector3, center: SCNVector3) -> CGFloat {
                let corners = [minB, maxB]
                return corners.map { v in
                    let dx = v.x - center.x
                    let dy = v.y - center.y
                    let dz = v.z - center.z
                    return sqrt(dx*dx + dy*dy + dz*dz)
                }.max() ?? 0
            }
            let patRadius = radius(from: patternMin, to: patternMax, center: patCenter)
            // no external scaling for now

            // create container and position children relative to its centre
            let container = SCNNode()
            container.addChildNode(meshNode)
            let cx = (patternMin.x + patternMax.x) / 2
            let cy = (patternMin.y + patternMax.y) / 2
            let cz = (patternMin.z + patternMax.z) / 2
            container.position = SCNVector3(-cx, -cy, -cz)
            scene.rootNode.addChildNode(container)
        }

        // Note: camera has been oriented so Z is up and +Y is on the left, no
        // additional scene rotation required.
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
}

#if DEBUG

// helper for previews that need a @State binding
// from https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-state-binding-for-a-preview
// (simplified generic implementation)
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: value)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

extension PatternView {
    struct PreviewData {
        static let sample: [SimulationResult.RadiationPoint] = (0..<36).flatMap { ti in
            (0..<72).map { pj in
                let theta = Double(ti) * 5.0
                let phi   = Double(pj) * 5.0
                let gain  = 1.0 + sin(theta * .pi/180) * cos(phi * .pi/180)
                return SimulationResult.RadiationPoint(theta: theta, phi: phi, gain: gain)
            }
        }
    }

    struct Preview: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 8) {
                // PatternView no longer needs a selection binding; the
                // geometry view handles interaction now.  Keep the preview
                // simple without the helper wrapper.
                PatternView(points: PreviewData.sample,
                            maxGain: 2.0)
                    .frame(width: 300, height: 300)
            }
                // simple legend for preview
                HStack {
                    Text("0.0 dBi")
                        .font(.caption2)
                    Rectangle()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [
                                PatternView.swiftUIColor(forNorm: 0),
                                PatternView.swiftUIColor(forNorm: 1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing))
                        .frame(height: 8)
                        .cornerRadius(4)
                    Text("2.0 dBi")
                        .font(.caption2)
                }
                .padding(.horizontal)
            }
        }
    }
#endif
