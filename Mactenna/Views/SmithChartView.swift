//
//  NewSmithChartView.swift
//  Mactenna
//

import SwiftUI

struct SmithChartView: View {
    let impedances: [(zr: [Float], zi: [Float])]

    private let chartRadius: CGFloat = 225
    private let margin: CGFloat = 60

    // Grid region tables (from cocoaNEC)
    private let zRegions:  [Float] = [0, 0.2, 0.5, 1, 2, 5, 10, 20, 50]
    private let zMinorDiv: [Float] = [0.01, 0.02, 0.05, 0.1, 0.2, 1, 2, 10]
    private let zMajorDiv: [Int]   = [5, 5, 2, 2, 5, 5, 5, 5]

    // MARK: - Helper functions for Smith chart grid

    private func rxToUVf(r: Float, x: Float) -> (u: Float, v: Float) {
        let r2 = r * r, x2 = x * x
        let d  = r2 + x2 + 2 * r + 1
        return ((r2 + x2 - 1) / d, 2 * x / d)
    }

    private func angR(r: Float, x: Float) -> Double {
        let (u, v) = rxToUVf(r: r, x: x)
        return atan2(Double(v), Double(u) - Double(r / (r + 1)))
    }

    private func angX(r: Float, x: Float) -> Double {
        let (u, v) = rxToUVf(r: r, x: x)
        return atan2(Double(v) - Double(1 / x), Double(u) - 1)
    }

    private func drawRarc(_ context: inout GraphicsContext, center: CGPoint,
                          r: Float, x1: Float, x2: Float, lineWidth: CGFloat) {
        let u0 = CGFloat(r / (r + 1))
        let radius = CGFloat(1 / (r + 1)) * chartRadius
        let arcCenter = CGPoint(x: center.x + u0 * chartRadius, y: center.y)

        let t1 = angR(r: r, x: x1)
        let t2 = angR(r: r, x: x2)

        strokeArc(&context, center: arcCenter, radius: radius,
                  startAngle: -t1, endAngle: -t2, lineWidth: lineWidth)
    }

    private func drawXarc(_ context: inout GraphicsContext, center: CGPoint,
                          x: Float, r1: Float, r2: Float, lineWidth: CGFloat) {
        let u0: CGFloat = 1
        let v0 = 1 / x
        let radius = abs(CGFloat(1 / x)) * chartRadius
        let arcCenter = CGPoint(x: center.x + u0 * chartRadius,
                                y: center.y - CGFloat(v0) * chartRadius)

        let t1 = angX(r: r1, x: x)
        let t2 = angX(r: r2, x: x)

        strokeArc(&context, center: arcCenter, radius: radius,
                  startAngle: -t1, endAngle: -t2, lineWidth: lineWidth)
    }

    private func strokeArc(_ context: inout GraphicsContext,
                           center: CGPoint, radius: CGFloat,
                           startAngle: Double, endAngle: Double,
                           lineWidth: CGFloat) {
        var path = Path()
        path.addArc(center: center,
                    radius: radius,
                    startAngle: .radians(startAngle),
                    endAngle:   .radians(endAngle),
                    clockwise: false)
        context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: lineWidth)
    }

    private func drawBlock(_ context: inout GraphicsContext, center: CGPoint,
                           r1: Float, r2: Float, x1: Float, x2: Float,
                           minorinc: Float, majorinc: Int) {
        var rtics: Float = 0
        var r = r1 + minorinc
        while r <= r2 + minorinc / 2 {
            rtics += 1
            let lw: CGFloat = (Int(rtics + 0.001) % majorinc == 0) ? 0.9 : 0.4
            drawRarc(&context, center: center, r: r, x1:  x2, x2:  x1, lineWidth: lw)
            drawRarc(&context, center: center, r: r, x1: -x1, x2: -x2, lineWidth: lw)
            r += minorinc
        }
        var xtics: Float = 0
        var x = x1 + minorinc
        while x <= x2 + minorinc / 2 {
            xtics += 1
            let lw: CGFloat = (Int(xtics + 0.001) % majorinc == 0) ? 0.9 : 0.4
            drawXarc(&context, center: center, x:  x, r1: r1, r2: r2, lineWidth: lw)
            drawXarc(&context, center: center, x: -x, r1: r2, r2: r1, lineWidth: lw)
            x += minorinc
        }
    }

    // MARK: - Label drawing

    private func drawResistanceLabel(_ context: inout GraphicsContext, center: CGPoint,
                                     r: Float, label: String) {
        let (u, _) = rxToUVf(r: r, x: 0)
        let x = center.x + CGFloat(u) * chartRadius
        let y = center.y

        // Position label horizontally on the real axis
        var resolvedImage = context.resolve(
            Text(label)
                .font(.system(size: 8, weight: .regular, design: .default))
                .foregroundColor(.gray)
        )
        context.draw(resolvedImage, at: CGPoint(x: x, y: y - 8))
    }

    private func drawReactanceLabel(_ context: inout GraphicsContext, center: CGPoint,
                                    x: Float, label: String) {
        let (u, v) = rxToUVf(r: 0, x: x)
        let isNegative = x < 0
        let rad = isNegative ? 0.985 : 0.93
        let radiusScale = CGFloat(rad) * chartRadius

        let labelX = center.x + CGFloat(u) * radiusScale
        let labelY = center.y - CGFloat(v) * radiusScale

        var resolvedImage = context.resolve(
            Text(label)
                .font(.system(size: 8, weight: .regular, design: .default))
                .foregroundColor(.gray)
        )
        context.draw(resolvedImage, at: CGPoint(x: labelX, y: labelY))
    }

    private func drawSmithChartBackground(_ context: inout GraphicsContext, center: CGPoint) {
        // Create circular clipping path
        var clipPath = Path()
        clipPath.addEllipse(in: CGRect(
            x: center.x - chartRadius, y: center.y - chartRadius,
            width: chartRadius * 2,    height: chartRadius * 2
        ))

        // Outer circumference
        var outerPath = Path()
        outerPath.addEllipse(in: CGRect(
            x: center.x - chartRadius, y: center.y - chartRadius,
            width: chartRadius * 2,    height: chartRadius * 2
        ))
        context.stroke(outerPath, with: .color(.gray), lineWidth: 1.5)

        // Real axis
        var realAxis = Path()
        realAxis.move(to: CGPoint(x: center.x - chartRadius, y: center.y))
        realAxis.addLine(to: CGPoint(x: center.x + chartRadius, y: center.y))
        context.stroke(realAxis, with: .color(.gray.opacity(0.8)), lineWidth: 0.9)

        // Clip grid drawing to circle
        context.clip(to: clipPath)

        // Grid regions
        let n = zMinorDiv.count
        for index in 0..<n {
            let minorinc = zMinorDiv[index]
            let majorinc = zMajorDiv[index]

            // First sub-block: r in [regions[index], regions[index+1]], x in [regions[index], regions[index+1]]
            drawBlock(&context, center: center,
                      r1: zRegions[index], r2: zRegions[index + 1],
                      x1: zRegions[index], x2: zRegions[index + 1],
                      minorinc: minorinc, majorinc: majorinc)

            // Second sub-block: r in [regions[index], regions[index+1]], x in [0, regions[index]]
            let maj2 = (index == 7) ? 3 : majorinc
            drawBlock(&context, center: center,
                      r1: zRegions[index], r2: zRegions[index + 1],
                      x1: zMinorDiv[index], x2: zRegions[index],
                      minorinc: minorinc, majorinc: maj2)
        }

        // Draw grid labels
        drawResistanceLabel(&context, center: center, r: 0.2, label: "0.2")
        drawResistanceLabel(&context, center: center, r: 0.5, label: "0.5")
        drawResistanceLabel(&context, center: center, r: 1.0, label: "1.0")
        drawResistanceLabel(&context, center: center, r: 2.0, label: "2.0")
        drawResistanceLabel(&context, center: center, r: 5.0, label: "5.0")
        drawResistanceLabel(&context, center: center, r: 10.0, label: "10")

        drawReactanceLabel(&context, center: center, x: 0.2, label: "0.2")
        drawReactanceLabel(&context, center: center, x: 0.5, label: "0.5")
        drawReactanceLabel(&context, center: center, x: 1.0, label: "1.0")
        drawReactanceLabel(&context, center: center, x: 2.0, label: "2.0")
        drawReactanceLabel(&context, center: center, x: 5.0, label: "5.0")

        drawReactanceLabel(&context, center: center, x: -0.2, label: "-0.2")
        drawReactanceLabel(&context, center: center, x: -0.5, label: "-0.5")
        drawReactanceLabel(&context, center: center, x: -1.0, label: "-1.0")
        drawReactanceLabel(&context, center: center, x: -2.0, label: "-2.0")
        drawReactanceLabel(&context, center: center, x: -5.0, label: "-5.0")
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text("Smith Chart - Input Impedance")
                .font(.headline)
                .padding()

            Canvas { context, size in
                let centerX = chartRadius + margin
                let centerY = chartRadius + margin
                let center = CGPoint(x: centerX, y: centerY)

                // Draw Smith chart background with grid
                drawSmithChartBackground(&context, center: center)
            }
            .frame(height: chartRadius * 2 + margin * 2)
            .background(Color(nsColor: .controlBackgroundColor))

            Text("\(impedances.count) inputs")
                .font(.caption)
                .padding()
        }
    }
}

#Preview {
    SmithChartView(
        impedances: [
            (zr: [50], zi: [0])
        ]
    )
}
