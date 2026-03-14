//
//  PatternBaseView.swift
//  Mactenna
//
//  Base class for polar pattern displays (Elevation and Azimuth).
//  Generates grid, transforms coordinates, and renders radiation patterns.
//

import SwiftUI

struct PatternBaseView: View {
    let radiationPoints: [SimulationResult.RadiationPoint]
    let frequency: Float
    let isElevation: Bool  // true for elevation, false for azimuth

    private let chartRadius: CGFloat = 200
    private let margin: CGFloat = 40

    // Scaling parameters
    @State private var rho: Float = 1.059998  // ~0.89 dB per circle
    @State private var gainPolarization: GainPolarization = .total

    // Grid parameters
    private let majorCircles: [Int] = [-2, -4, -8, -10, -20, -30, -40]
    private let minorMin: Int = -30
    private let majorMin: Int = -40

    enum GainPolarization {
        case total, vertical, horizontal, leftCircular, rightCircular
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(isElevation ? "Elevation Pattern" : "Azimuth Pattern")
                .font(.headline)
                .padding()

            Canvas { context, size in
                let centerX = chartRadius + margin
                let centerY = chartRadius + margin
                let center = CGPoint(x: centerX, y: centerY)

                // Draw background
                drawBackground(&context, center: center)

                // Draw grid
                drawGrid(&context, center: center)

                // Draw pattern
                drawPattern(&context, center: center)
            }
            .frame(height: chartRadius * 2 + margin * 2)
            .background(Color(nsColor: .controlBackgroundColor))

            // Info display
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(format: "Frequency: %.3f MHz", frequency))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    if !radiationPoints.isEmpty {
                        let maxGain = radiationPoints.map { $0.gain }.max() ?? 0
                        Text(String(format: "Max Gain: %.2f dBi", maxGain))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Text("Gain Scale:")
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)

                    Picker("", selection: $rho) {
                        Text("Fine (1.05)").tag(1.05 as Float)
                        Text("Standard (1.060)").tag(1.059998 as Float)
                        Text("Coarse (1.08)").tag(1.08 as Float)
                    }
                    .font(.caption)
                }

                HStack(spacing: 12) {
                    Text("Polarization:")
                        .font(.caption)
                        .frame(width: 80, alignment: .leading)

                    Picker("", selection: $gainPolarization) {
                        Text("Total").tag(GainPolarization.total)
                        Text("Vertical").tag(GainPolarization.vertical)
                        Text("Horizontal").tag(GainPolarization.horizontal)
                        Text("L-Circular").tag(GainPolarization.leftCircular)
                        Text("R-Circular").tag(GainPolarization.rightCircular)
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func drawBackground(_ context: inout GraphicsContext, center: CGPoint) {
        var bgPath = Path()
        bgPath.addEllipse(in: CGRect(
            x: center.x - chartRadius,
            y: center.y - chartRadius,
            width: chartRadius * 2,
            height: chartRadius * 2
        ))
        context.fill(bgPath, with: .color(.white))
        context.stroke(bgPath, with: .color(.black), lineWidth: 1.5)
    }

    private func drawGrid(_ context: inout GraphicsContext, center: CGPoint) {
        // Draw concentric circles for dB levels
        for dB in majorCircles {
            let radius = CGFloat(powf(rho, Float(dB))) * chartRadius
            var circlePath = Path()
            circlePath.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))

            let lineWidth: CGFloat = (dB % 10 == 0) ? 0.9 : 0.4
            let color: Color = (dB % 10 == 0) ? .gray : .gray.opacity(0.5)
            context.stroke(circlePath, with: .color(color), lineWidth: lineWidth)
        }

        // Draw radial lines (10° steps = 36 total)
        for i in 0..<36 {
            let angle = Float(i) * (Float.pi / 18.0)  // π/18 = 10°

            let majorRadius = CGFloat(powf(rho, Float(majorMin))) * chartRadius
            let minorRadius = CGFloat(powf(rho, Float(minorMin))) * chartRadius
            let radius = ((i % 3) == 0) ? majorRadius : minorRadius

            let x = cos(Double(angle))
            let y = sin(Double(angle))

            var linePath = Path()
            linePath.move(to: CGPoint(
                x: center.x + CGFloat(x) * radius,
                y: center.y - CGFloat(y) * radius
            ))
            linePath.addLine(to: CGPoint(
                x: center.x + CGFloat(x) * chartRadius,
                y: center.y - CGFloat(y) * chartRadius
            ))

            let lineWidth: CGFloat = ((i % 3) == 0) ? 0.45 : 0.2
            let color: Color = ((i % 3) == 0) ? .blue : .blue.opacity(0.5)
            context.stroke(linePath, with: .color(color), lineWidth: lineWidth)
        }

        // Draw axis labels
        drawAxisLabels(&context, center: center)

        // Draw dB labels on circles
        drawDBLabels(&context, center: center)
    }

    private func drawAxisLabels(_ context: inout GraphicsContext, center: CGPoint) {
        let labels = [
            ("0°", 0.0),
            ("90°", Float.pi / 2),
            ("180°", Float.pi),
            ("270°", 3 * Float.pi / 2)
        ]

        let labelRadius = chartRadius * 1.08
        for (label, angle) in labels {
            let x = center.x + labelRadius * CGFloat(cos(Double(angle)))
            let y = center.y - labelRadius * CGFloat(sin(Double(angle)))

            var resolvedImage = context.resolve(
                Text(label)
                    .font(.system(size: 9, weight: .regular, design: .default))
                    .foregroundColor(.black)
            )
            context.draw(resolvedImage, at: CGPoint(x: x - 10, y: y - 10))
        }
    }

    private func drawDBLabels(_ context: inout GraphicsContext, center: CGPoint) {
        // Draw dB value labels on circles at 0° position (right side)
        for dB in majorCircles {
            let radius = CGFloat(powf(rho, Float(dB))) * chartRadius
            let x = center.x + radius + 5
            let y = center.y

            let label = String(dB)
            var resolvedImage = context.resolve(
                Text(label)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundColor(.gray)
            )
            context.draw(resolvedImage, at: CGPoint(x: x, y: y - 6))
        }
    }

    private func drawPattern(_ context: inout GraphicsContext, center: CGPoint) {
        guard !radiationPoints.isEmpty else { return }

        let maxGain = radiationPoints.map { $0.gain }.max() ?? 0
        var pathPoints: [CGPoint] = []

        // Convert radiation points to polar coordinates
        for point in radiationPoints {
            let angle: Float
            if isElevation {
                // Elevation: angle = (90 - theta) in degrees
                angle = (90.0 - Float(point.theta)) * (Float.pi / 180.0)
            } else {
                // Azimuth: angle = phi in degrees
                angle = Float(point.phi) * (Float.pi / 180.0)
            }

            // Gain mapping: r = ρ^(gain - maxGain)
            let gainDiff = Float(point.gain) - Float(maxGain)
            let r = powf(rho, gainDiff)

            let x = center.x + CGFloat(r) * chartRadius * CGFloat(cos(Double(angle)))
            let y = center.y - CGFloat(r) * chartRadius * CGFloat(sin(Double(angle)))

            pathPoints.append(CGPoint(x: x, y: y))
        }

        // Draw pattern line
        if pathPoints.count > 1 {
            var patternPath = Path()
            patternPath.move(to: pathPoints[0])
            for i in 1..<pathPoints.count {
                patternPath.addLine(to: pathPoints[i])
            }
            context.stroke(patternPath, with: .color(.green), lineWidth: 1.2)
        }

        // Draw data points
        for (index, point) in pathPoints.enumerated() {
            let radius: CGFloat = 3
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(.green)
            )
        }
    }
}

#Preview {
    let samplePoints = [
        SimulationResult.RadiationPoint(theta: 0, phi: 0, gain: 10),
        SimulationResult.RadiationPoint(theta: 15, phi: 0, gain: 9),
        SimulationResult.RadiationPoint(theta: 30, phi: 0, gain: 6),
        SimulationResult.RadiationPoint(theta: 45, phi: 0, gain: 2),
        SimulationResult.RadiationPoint(theta: 60, phi: 0, gain: -5),
        SimulationResult.RadiationPoint(theta: 90, phi: 0, gain: -20),
    ]

    PatternBaseView(
        radiationPoints: samplePoints,
        frequency: 146.5,
        isElevation: true
    )
}
