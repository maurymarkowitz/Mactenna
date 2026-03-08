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

struct PatternView: NSViewRepresentable {
    /// Radiation pattern points to display.  Coordinates are in degrees and
    /// gain is in dBi.  All values are provided by SimulationResult.
    let points: [SimulationResult.RadiationPoint]
    let maxGain: Double  // used to normalise radius

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
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

        // camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 5)
        scene.rootNode.addChildNode(cameraNode)

        // axes helper
        let axis = SCNNode()
        axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(1,0,0), color: .red))
        axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(0,1,0), color: .green))
        axis.addChildNode(lineNode(from: SCNVector3Zero, to: SCNVector3(0,0,1), color: .blue))
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
                    let x = r * sin(Float(theta)) * cos(Float(phi))
                    let y = r * sin(Float(theta)) * sin(Float(phi))
                    let z = r * cos(Float(theta))
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
            geom.firstMaterial = mat
            let meshNode = SCNNode(geometry: geom)
            scene.rootNode.addChildNode(meshNode)
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
}

#if DEBUG
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
            PatternView(points: PreviewData.sample, maxGain: 2.0)
                .frame(width: 300, height: 300)
        }
    }
}
#endif
