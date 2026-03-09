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

struct PatternView: NSViewRepresentable {
    /// Radiation pattern points to display.  Coordinates are in degrees and
    /// gain is in dBi.  All values are provided by SimulationResult.
    let points: [SimulationResult.RadiationPoint]
    let maxGain: Double  // used to normalise radius
    /// Geometry segments to overlay on the pattern.
    let geometry: [GeometrySegment]

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
            mat.transparency = 0.5          // render the pattern half‑transparent
            // ensure we blend using alpha so overlapping parts are visible
            mat.transparencyMode = .aOne
            geom.firstMaterial = mat
            let meshNode = SCNNode(geometry: geom)

            // compute bounding boxes for geometry and pattern separately
            let (patternMin, patternMax) = geom.boundingBox
            // compute geometry bounds from segment list
            var geoMin = SCNVector3(CGFloat.infinity, CGFloat.infinity, CGFloat.infinity)
            var geoMax = SCNVector3(-CGFloat.infinity, -CGFloat.infinity, -CGFloat.infinity)
            for seg in geometry {
                let pts = [seg.start, seg.end]
                for p in pts {
                    let gx = CGFloat(p.x), gy = CGFloat(p.y), gz = CGFloat(p.z)
                    geoMin.x = min(geoMin.x, gx); geoMin.y = min(geoMin.y, gy); geoMin.z = min(geoMin.z, gz)
                    geoMax.x = max(geoMax.x, gx); geoMax.y = max(geoMax.y, gy); geoMax.z = max(geoMax.z, gz)
                }
            }
            // compute radii relative to respective centers
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
            var geoRadius: CGFloat = 0
            if geoMin.x < geoMax.x { // means we actually have geometry
                let geoCenter = SCNVector3((geoMin.x+geoMax.x)/2,
                                           (geoMin.y+geoMax.y)/2,
                                           (geoMin.z+geoMax.z)/2)
                geoRadius = radius(from: geoMin, to: geoMax, center: geoCenter)
            }
            // scale pattern so geometry sits inside it
            if patRadius > 0 && geoRadius > 0 {
                let scale = (geoRadius * 1.1) / patRadius
                meshNode.scale = SCNVector3(scale, scale, scale)
            }

            // recompute combined bounds after scaling pattern
            var minB = SCNVector3(patternMin.x * meshNode.scale.x,
                                   patternMin.y * meshNode.scale.y,
                                   patternMin.z * meshNode.scale.z)
            var maxB = SCNVector3(patternMax.x * meshNode.scale.x,
                                   patternMax.y * meshNode.scale.y,
                                   patternMax.z * meshNode.scale.z)
            for seg in geometry {
                let sx1 = CGFloat(seg.start.x)
                let sy1 = CGFloat(seg.start.y)
                let sz1 = CGFloat(seg.start.z)
                let sx2 = CGFloat(seg.end.x)
                let sy2 = CGFloat(seg.end.y)
                let sz2 = CGFloat(seg.end.z)
                minB.x = min(minB.x, sx1, sx2)
                minB.y = min(minB.y, sy1, sy2)
                minB.z = min(minB.z, sz1, sz2)
                maxB.x = max(maxB.x, sx1, sx2)
                maxB.y = max(maxB.y, sy1, sy2)
                maxB.z = max(maxB.z, sz1, sz2)
            }
            // create container and position children relative to its center
            let container = SCNNode()
            container.addChildNode(meshNode)
            for seg in geometry {
                let p1 = SCNVector3(CGFloat(seg.start.x), CGFloat(seg.start.y), CGFloat(seg.start.z))
                let p2 = SCNVector3(CGFloat(seg.end.x),   CGFloat(seg.end.y),   CGFloat(seg.end.z))
                let geoLine = lineNode(from: p1,
                                       to: p2,
                                       color: NSColor.darkGray)
                container.addChildNode(geoLine)
            }
            let cx = (minB.x + maxB.x) / 2
            let cy = (minB.y + maxB.y) / 2
            let cz = (minB.z + maxB.z) / 2
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
extension PatternView {
    struct GeometrySegment {
        let start: SIMD3<Float>
        let end:   SIMD3<Float>
    }

    struct PreviewData {
        static let sample: [SimulationResult.RadiationPoint] = (0..<36).flatMap { ti in
            (0..<72).map { pj in
                let theta = Double(ti) * 5.0
                let phi   = Double(pj) * 5.0
                let gain  = 1.0 + sin(theta * .pi/180) * cos(phi * .pi/180)
                return SimulationResult.RadiationPoint(theta: theta, phi: phi, gain: gain)
            }
        }
        static let geom: [GeometrySegment] = [
            GeometrySegment(start: SIMD3(-1,0,0), end: SIMD3(1,0,0)),
            GeometrySegment(start: SIMD3(0,-1,0), end: SIMD3(0,1,0))
        ]
    }

    struct Preview: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 8) {
                PatternView(points: PreviewData.sample, maxGain: 2.0, geometry: PreviewData.geom)
                    .frame(width: 300, height: 300)
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
}
#endif
