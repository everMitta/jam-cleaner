#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CoreText
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate_app_icon.swift <output.iconset directory>\n", stderr)
    exit(1)
}

let iconsetPath = CommandLine.arguments[1]
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

struct IconSpec {
    let filename: String
    let pixelSize: Int
}

let specs: [IconSpec] = [
    IconSpec(filename: "icon_16x16.png", pixelSize: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixelSize: 32),
    IconSpec(filename: "icon_32x32.png", pixelSize: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixelSize: 64),
    IconSpec(filename: "icon_128x128.png", pixelSize: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixelSize: 256),
    IconSpec(filename: "icon_256x256.png", pixelSize: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixelSize: 512),
    IconSpec(filename: "icon_512x512.png", pixelSize: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixelSize: 1024)
]

func makeFourPointStarPath(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * (.pi / 4.0) - (.pi / 2.0)
        let r = (i % 2 == 0) ? outerRadius : innerRadius
        let pt = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        if i == 0 {
            path.move(to: pt)
        } else {
            let prevAngle = CGFloat(i - 1) * (.pi / 4.0) - (.pi / 2.0)
            let prevR = ((i - 1) % 2 == 0) ? outerRadius : innerRadius
            let prevPt = CGPoint(x: center.x + cos(prevAngle) * prevR, y: center.y + sin(prevAngle) * prevR)
            let ctrl = CGPoint(
                x: (prevPt.x + pt.x) * 0.5 + (center.x - (prevPt.x + pt.x) * 0.5) * 0.38,
                y: (prevPt.y + pt.y) * 0.5 + (center.y - (prevPt.y + pt.y) * 0.5) * 0.38
            )
            path.addQuadCurve(to: pt, control: ctrl)
        }
    }
    path.closeSubpath()
    return path
}

func drawFourPointStar(in cg: CGContext, center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat, color: CGColor) {
    let path = makeFourPointStarPath(center: center, outerRadius: outerRadius, innerRadius: innerRadius)
    cg.saveGState()
    cg.setFillColor(color)
    cg.addPath(path)
    cg.fillPath()
    cg.restoreGState()
}

func drawGradientFourPointStar(in cg: CGContext, colorSpace: CGColorSpace, center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) {
    let path = makeFourPointStarPath(center: center, outerRadius: outerRadius, innerRadius: innerRadius)
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -outerRadius * 0.08),
        blur: outerRadius * 0.22,
        color: CGColor(red: 0.32, green: 0.15, blue: 0.65, alpha: 0.28)
    )
    cg.setFillColor(CGColor(red: 0.32, green: 0.15, blue: 0.65, alpha: 1.0))
    cg.addPath(path)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let starColors: [CGFloat] = [
        0.31, 0.14, 0.62, 1.0,
        0.48, 0.24, 0.86, 1.0,
        0.10, 0.72, 0.64, 1.0
    ]
    if let grad = CGGradient(colorSpace: colorSpace, colorComponents: starColors, locations: [0.0, 0.55, 1.0], count: 3) {
        cg.drawLinearGradient(
            grad,
            start: CGPoint(x: center.x - outerRadius, y: center.y + outerRadius),
            end: CGPoint(x: center.x + outerRadius, y: center.y - outerRadius),
            options: []
        )
    }
    cg.restoreGState()
}

func renderIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    cg.interpolationQuality = .high

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // 1. Apple macOS Sequoia/Tahoe Squircle Geometry (9.5% margin -> 830x830 on 1024 canvas)
    let inset = size * 0.094
    let squircleRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = squircleRect.width * 0.228
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Soft ambient outer drop shadow under the squircle
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -size * 0.022),
        blur: size * 0.048,
        color: CGColor(red: 0.14, green: 0.06, blue: 0.32, alpha: 0.42)
    )
    cg.setFillColor(CGColor(red: 0.18, green: 0.09, blue: 0.38, alpha: 1.0))
    cg.addPath(squirclePath)
    cg.fillPath()
    cg.restoreGState()

    // Clip all interior layers to the squircle
    cg.saveGState()
    cg.addPath(squirclePath)
    cg.clip()

    // 2. Deep Rich Multi-Stop Background Gradient (Obsidian Violet -> Royal Purple -> Electric Indigo -> Deep Emerald Teal)
    let bgColors: [CGFloat] = [
        0.14, 0.07, 0.31, 1.0, // Deep Obsidian Violet (top-left)
        0.33, 0.15, 0.65, 1.0, // Royal Purple
        0.22, 0.18, 0.56, 1.0, // Electric Indigo
        0.05, 0.58, 0.54, 1.0  // Deep Emerald-Mint (bottom-right)
    ]
    let bgLocations: [CGFloat] = [0.0, 0.38, 0.70, 1.0]
    if let bgGrad = CGGradient(colorSpace: colorSpace, colorComponents: bgColors, locations: bgLocations, count: 4) {
        cg.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
            end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
            options: []
        )
    }

    // 3. Top-Left Violet-Magenta Ambient Glow & Bottom-Right Mint Caustic Glow
    let topGlowColors: [CGFloat] = [
        0.68, 0.42, 1.00, 0.52,
        0.52, 0.25, 0.92, 0.18,
        0.33, 0.15, 0.65, 0.0
    ]
    if let topRadial = CGGradient(colorSpace: colorSpace, colorComponents: topGlowColors, locations: [0.0, 0.45, 1.0], count: 3) {
        let glowCenter = CGPoint(x: squircleRect.minX + squircleRect.width * 0.24, y: squircleRect.maxY - squircleRect.height * 0.20)
        cg.drawRadialGradient(
            topRadial,
            startCenter: glowCenter,
            startRadius: 0,
            endCenter: glowCenter,
            endRadius: squircleRect.width * 0.68,
            options: []
        )
    }

    let bottomGlowColors: [CGFloat] = [
        0.22, 0.96, 0.84, 0.55,
        0.12, 0.78, 0.70, 0.20,
        0.05, 0.58, 0.54, 0.0
    ]
    if let bottomRadial = CGGradient(colorSpace: colorSpace, colorComponents: bottomGlowColors, locations: [0.0, 0.5, 1.0], count: 3) {
        let glowCenter = CGPoint(x: squircleRect.maxX - squircleRect.width * 0.20, y: squircleRect.minY + squircleRect.height * 0.18)
        cg.drawRadialGradient(
            bottomRadial,
            startCenter: glowCenter,
            startRadius: 0,
            endCenter: glowCenter,
            endRadius: squircleRect.width * 0.65,
            options: []
        )
    }

    // 4. Subtle Architectural Grid / Harmonic Wave Lines in Background (for large icons >= 64px)
    let center = CGPoint(x: size * 0.5, y: size * 0.51)
    if pixelSize >= 64 {
        cg.saveGState()
        cg.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.07))
        cg.setLineWidth(max(1.0, size * 0.003))
        for factor in [0.42, 0.48] {
            let r = squircleRect.width * CGFloat(factor)
            cg.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        cg.restoreGState()
    }

    // 5. Frosted Glass Outer Instrument Disc
    let outerDiscRadius = squircleRect.width * 0.365
    let outerDiscRect = CGRect(
        x: center.x - outerDiscRadius,
        y: center.y - outerDiscRadius,
        width: outerDiscRadius * 2,
        height: outerDiscRadius * 2
    )

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -size * 0.018),
        blur: size * 0.04,
        color: CGColor(red: 0.05, green: 0.02, blue: 0.15, alpha: 0.55)
    )
    cg.setFillColor(CGColor(red: 0.13, green: 0.09, blue: 0.28, alpha: 0.72))
    cg.fillEllipse(in: outerDiscRect)
    cg.restoreGState()

    // Glass disc subtle inner gradient
    cg.saveGState()
    cg.addEllipse(in: outerDiscRect)
    cg.clip()
    let discGlassColors: [CGFloat] = [
        1.0, 1.0, 1.0, 0.22,
        0.65, 0.52, 0.98, 0.10,
        0.16, 0.85, 0.76, 0.18
    ]
    if let discGrad = CGGradient(colorSpace: colorSpace, colorComponents: discGlassColors, locations: [0.0, 0.5, 1.0], count: 3) {
        cg.drawLinearGradient(
            discGrad,
            start: CGPoint(x: outerDiscRect.minX, y: outerDiscRect.maxY),
            end: CGPoint(x: outerDiscRect.maxX, y: outerDiscRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // Glass disc rim highlight
    cg.saveGState()
    cg.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.32))
    cg.setLineWidth(max(1.0, size * 0.008))
    cg.strokeEllipse(in: outerDiscRect)
    cg.restoreGState()

    // 6. Precision Gauge Tick Marks Around Track (for >= 64px)
    let sweepTrackRadius = squircleRect.width * 0.295
    if pixelSize >= 64 {
        cg.saveGState()
        let tickCount = 24
        for i in 0..<tickCount {
            let angle = CGFloat(i) * (2.0 * .pi / CGFloat(tickCount))
            let innerR = sweepTrackRadius * 1.11
            let outerR = sweepTrackRadius * (i % 3 == 0 ? 1.17 : 1.145)
            let p1 = CGPoint(x: center.x + cos(angle) * innerR, y: center.y + sin(angle) * innerR)
            let p2 = CGPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR)
            cg.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: i % 3 == 0 ? 0.36 : 0.16))
            cg.setLineWidth(max(1.0, size * (i % 3 == 0 ? 0.0045 : 0.003)))
            cg.setLineCap(.round)
            cg.move(to: p1)
            cg.addLine(to: p2)
            cg.strokePath()
        }
        cg.restoreGState()
    }

    // 7. Recessed Track & Luminous Sweeping Clean Arc (Mint-Cyan-Violet Gradient)
    let trackLineWidth = max(2.0, size * 0.052)
    cg.saveGState()
    cg.setStrokeColor(CGColor(red: 0.08, green: 0.05, blue: 0.18, alpha: 0.55))
    cg.setLineWidth(trackLineWidth)
    cg.strokeEllipse(
        in: CGRect(
            x: center.x - sweepTrackRadius,
            y: center.y - sweepTrackRadius,
            width: sweepTrackRadius * 2,
            height: sweepTrackRadius * 2
        )
    )
    cg.restoreGState()

    // Active Sweep Arc (from 135 deg counter-clockwise to -45 deg -> 255 deg sweep)
    let startAngle = CGFloat(140.0 * .pi / 180.0)
    let endAngle = CGFloat(-45.0 * .pi / 180.0)

    let arcMutable = CGMutablePath()
    arcMutable.addArc(center: center, radius: sweepTrackRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    let strokedArc = arcMutable.copy(
        strokingWithWidth: trackLineWidth,
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 10
    )

    // Glow under active sweep arc
    cg.saveGState()
    cg.setShadow(
        offset: .zero,
        blur: size * 0.028,
        color: CGColor(red: 0.18, green: 0.96, blue: 0.82, alpha: 0.65)
    )
    cg.setFillColor(CGColor(red: 0.22, green: 0.94, blue: 0.82, alpha: 0.35))
    cg.addPath(strokedArc)
    cg.fillPath()
    cg.restoreGState()

    // Gradient fill inside the active sweep arc
    cg.saveGState()
    cg.addPath(strokedArc)
    cg.clip()
    let sweepColors: [CGFloat] = [
        0.58, 0.34, 0.98, 1.0, // Electric Violet tail
        0.24, 0.82, 0.92, 1.0, // Cyan bridge
        0.18, 0.98, 0.78, 1.0, // Luminous Mint head
        0.82, 1.00, 0.95, 1.0  // Specular Mint-White tip
    ]
    if let sweepGrad = CGGradient(colorSpace: colorSpace, colorComponents: sweepColors, locations: [0.0, 0.45, 0.85, 1.0], count: 4) {
        cg.drawLinearGradient(
            sweepGrad,
            start: CGPoint(x: center.x - sweepTrackRadius, y: center.y + sweepTrackRadius),
            end: CGPoint(x: center.x + sweepTrackRadius, y: center.y - sweepTrackRadius),
            options: []
        )
    }
    cg.restoreGState()

    // 8. Center White Liquid Glass Core Medallion
    let coreRadius = squircleRect.width * 0.205
    let coreRect = CGRect(
        x: center.x - coreRadius,
        y: center.y - coreRadius,
        width: coreRadius * 2,
        height: coreRadius * 2
    )

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.028,
        color: CGColor(red: 0.12, green: 0.05, blue: 0.28, alpha: 0.48)
    )
    cg.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.97))
    cg.fillEllipse(in: coreRect)
    cg.restoreGState()

    // Core inner pearl sheen
    cg.saveGState()
    cg.addEllipse(in: coreRect)
    cg.clip()
    let coreColors: [CGFloat] = [
        1.00, 1.00, 1.00, 1.0,
        0.95, 0.94, 0.99, 1.0,
        0.88, 0.97, 0.96, 1.0
    ]
    if let coreGrad = CGGradient(colorSpace: colorSpace, colorComponents: coreColors, locations: [0.0, 0.62, 1.0], count: 3) {
        cg.drawLinearGradient(
            coreGrad,
            start: CGPoint(x: coreRect.minX, y: coreRect.maxY),
            end: CGPoint(x: coreRect.maxX, y: coreRect.minY),
            options: []
        )
    }

    // Subtle Mint-Violet sweeping wave across bottom of the white core medallion
    let wavePath = CGMutablePath()
    wavePath.move(to: CGPoint(x: coreRect.minX, y: center.y - coreRadius * 0.18))
    wavePath.addCurve(
        to: CGPoint(x: coreRect.maxX, y: center.y + coreRadius * 0.06),
        control1: CGPoint(x: center.x - coreRadius * 0.35, y: center.y + coreRadius * 0.20),
        control2: CGPoint(x: center.x + coreRadius * 0.35, y: center.y - coreRadius * 0.42)
    )
    wavePath.addLine(to: CGPoint(x: coreRect.maxX, y: coreRect.minY))
    wavePath.addLine(to: CGPoint(x: coreRect.minX, y: coreRect.minY))
    wavePath.closeSubpath()

    let waveColors: [CGFloat] = [
        0.32, 0.16, 0.65, 0.12,
        0.16, 0.80, 0.72, 0.22
    ]
    cg.saveGState()
    cg.addPath(wavePath)
    cg.clip()
    if let waveGrad = CGGradient(colorSpace: colorSpace, colorComponents: waveColors, locations: [0.0, 1.0], count: 2) {
        cg.drawLinearGradient(
            waveGrad,
            start: CGPoint(x: coreRect.minX, y: center.y),
            end: CGPoint(x: coreRect.maxX, y: coreRect.minY),
            options: []
        )
    }
    cg.restoreGState()
    cg.restoreGState() // end core clip

    // Core rim border (Royal Purple -> Mint Teal)
    cg.saveGState()
    cg.setStrokeColor(CGColor(red: 0.42, green: 0.24, blue: 0.78, alpha: 0.28))
    cg.setLineWidth(max(1.0, size * 0.006))
    cg.strokeEllipse(in: coreRect)
    cg.restoreGState()

    // 9. Central Emblem inside White Medallion:
    // Crisp 4-point Clean Sparkle + "JAM" Typography Pill (for >= 64px) or Bold Sparkle Cluster (for <= 32px)
    if pixelSize >= 64 {
        // Upper 4-point primary gradient sparkle with clean breathing room above the JAM pill
        let mainSparkleCenter = CGPoint(x: center.x - coreRadius * 0.08, y: center.y + coreRadius * 0.31)
        drawGradientFourPointStar(
            in: cg,
            colorSpace: colorSpace,
            center: mainSparkleCenter,
            outerRadius: coreRadius * 0.38,
            innerRadius: coreRadius * 0.115
        )

        // Secondary Mint-Teal sparkle (top-right of center)
        let secondSparkleCenter = CGPoint(x: center.x + coreRadius * 0.40, y: center.y + coreRadius * 0.46)
        drawFourPointStar(
            in: cg,
            center: secondSparkleCenter,
            outerRadius: coreRadius * 0.20,
            innerRadius: coreRadius * 0.062,
            color: CGColor(red: 0.08, green: 0.68, blue: 0.60, alpha: 1.0)
        )

        // Accent micro-sparkle (top-left of center)
        let thirdSparkleCenter = CGPoint(x: center.x - coreRadius * 0.46, y: center.y + coreRadius * 0.14)
        drawFourPointStar(
            in: cg,
            center: thirdSparkleCenter,
            outerRadius: coreRadius * 0.13,
            innerRadius: coreRadius * 0.042,
            color: CGColor(red: 0.46, green: 0.26, blue: 0.86, alpha: 0.85)
        )

        // Bottom "JAM" Rounded Badge inside the Medallion
        let badgeWidth = coreRadius * 1.26
        let badgeHeight = coreRadius * 0.46
        let badgeRect = CGRect(
            x: center.x - badgeWidth * 0.5,
            y: center.y - coreRadius * 0.66,
            width: badgeWidth,
            height: badgeHeight
        )
        let badgePath = CGPath(
            roundedRect: badgeRect,
            cornerWidth: badgeHeight * 0.5,
            cornerHeight: badgeHeight * 0.5,
            transform: nil
        )

        cg.saveGState()
        cg.setShadow(
            offset: CGSize(width: 0, height: -size * 0.006),
            blur: size * 0.014,
            color: CGColor(red: 0.25, green: 0.10, blue: 0.52, alpha: 0.28)
        )
        cg.setFillColor(CGColor(red: 0.31, green: 0.15, blue: 0.58, alpha: 1.0))
        cg.addPath(badgePath)
        cg.fillPath()
        cg.restoreGState()

        cg.saveGState()
        cg.addPath(badgePath)
        cg.clip()
        let pillColors: [CGFloat] = [
            0.31, 0.15, 0.58, 1.0, // Royal Purple
            0.42, 0.23, 0.78, 1.0, // Electric Violet
            0.10, 0.68, 0.61, 1.0  // Mint Teal
        ]
        if let pillGrad = CGGradient(colorSpace: colorSpace, colorComponents: pillColors, locations: [0.0, 0.55, 1.0], count: 3) {
            cg.drawLinearGradient(
                pillGrad,
                start: CGPoint(x: badgeRect.minX, y: badgeRect.midY),
                end: CGPoint(x: badgeRect.maxX, y: badgeRect.midY),
                options: []
            )
        }
        cg.restoreGState()

        // Crisp white rim around the JAM pill
        cg.saveGState()
        cg.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.65))
        cg.setLineWidth(max(1.0, size * 0.0035))
        cg.addPath(badgePath)
        cg.strokePath()
        cg.restoreGState()

        // Draw "JAM" text centered in the pill
        let fontSize = badgeHeight * 0.62
        let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: fontSize * 0.06,
            .paragraphStyle: paragraph
        ]
        let text = NSAttributedString(string: "JAM", attributes: attrs)
        let textSize = text.size()
        let textRect = CGRect(
            x: badgeRect.midX - textSize.width * 0.5,
            y: badgeRect.midY - textSize.height * 0.51,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect)
    } else {
        // High-contrast simplified sparkle emblem for 16x16 and 32x32 menu/Dock sizes
        drawFourPointStar(
            in: cg,
            center: center,
            outerRadius: coreRadius * 0.68,
            innerRadius: coreRadius * 0.20,
            color: CGColor(red: 0.32, green: 0.15, blue: 0.62, alpha: 1.0)
        )
    }

    // 10. Leading Sweep Head Glowing Orb + Sparkle on the Outer Ring
    let headPoint = CGPoint(
        x: center.x + cos(endAngle) * sweepTrackRadius,
        y: center.y + sin(endAngle) * sweepTrackRadius
    )
    let orbRadius = trackLineWidth * 0.62
    cg.saveGState()
    cg.setShadow(
        offset: .zero,
        blur: size * 0.022,
        color: CGColor(red: 0.55, green: 1.0, blue: 0.90, alpha: 0.95)
    )
    cg.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.98))
    cg.fillEllipse(
        in: CGRect(
            x: headPoint.x - orbRadius,
            y: headPoint.y - orbRadius,
            width: orbRadius * 2,
            height: orbRadius * 2
        )
    )
    cg.restoreGState()

    drawFourPointStar(
        in: cg,
        center: headPoint,
        outerRadius: orbRadius * 0.72,
        innerRadius: orbRadius * 0.22,
        color: CGColor(red: 0.08, green: 0.65, blue: 0.58, alpha: 1.0)
    )

    cg.restoreGState() // end squircle clip

    // 11. Specular Glass Squircle Rim Border
    cg.saveGState()
    let rimPath = squirclePath.copy(
        strokingWithWidth: max(1.2, size * 0.012),
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 10
    )
    cg.addPath(rimPath)
    cg.clip()
    let rimColors: [CGFloat] = [
        1.0, 1.0, 1.0, 0.72,
        0.72, 0.58, 1.0, 0.38,
        0.25, 0.96, 0.84, 0.62
    ]
    if let rimGrad = CGGradient(colorSpace: colorSpace, colorComponents: rimColors, locations: [0.0, 0.5, 1.0], count: 3) {
        cg.drawLinearGradient(
            rimGrad,
            start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
            end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for spec in specs {
    if let pngData = renderIcon(pixelSize: spec.pixelSize) {
        let outURL = URL(fileURLWithPath: iconsetPath).appendingPathComponent(spec.filename)
        try pngData.write(to: outURL)
    }
}
