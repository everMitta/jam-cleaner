import AppKit
import MacSweepCore
import SwiftUI

// MARK: - Innotec Labs Brand Identity (https://innoteclabs.com) — White Liquid Glass & Purple-Green Lines

public enum InnotecTheme {
    // Primary Brand Colors from innoteclabs.com CSS & Logo
    /// #512977 — Deep Royal Purple ("Labs" Wordmark & Primary Brand Anchor)
    public static let royalPurple = Color(red: 81.0 / 255.0, green: 41.0 / 255.0, blue: 119.0 / 255.0)
    /// #6B498B — Mid Brand Violet
    public static let midViolet = Color(red: 107.0 / 255.0, green: 73.0 / 255.0, blue: 139.0 / 255.0)
    /// #6C3EC6 — Electric Violet Accent
    public static let electricViolet = Color(red: 108.0 / 255.0, green: 62.0 / 255.0, blue: 198.0 / 255.0)
    /// #7E52D6 — Vibrant Violet for badges & lines on white
    public static let luminousViolet = Color(red: 112.0 / 255.0, green: 64.0 / 255.0, blue: 205.0 / 255.0)
    /// #EFEAFF — Soft Lavender Surface Wash (from innoteclabs.com)
    public static let lavenderTint = Color(red: 239.0 / 255.0, green: 234.0 / 255.0, blue: 255.0 / 255.0)

    /// #43B3A5 — Innotec Primary Mint-Green ("Innotec" Wordmark)
    public static let mintTeal = Color(red: 67.0 / 255.0, green: 179.0 / 255.0, blue: 165.0 / 255.0)
    /// #2DB3A5 — Vibrant Mint-Green
    public static let vibrantTeal = Color(red: 45.0 / 255.0, green: 179.0 / 255.0, blue: 165.0 / 255.0)
    /// #0F8779 — Rich Emerald-Mint for crisp AA/AAA metric legibility on white glass
    public static let luminousMint = Color(red: 15.0 / 255.0, green: 135.0 / 255.0, blue: 121.0 / 255.0)
    /// #1E8A7E — Deep Teal
    public static let deepTeal = Color(red: 30.0 / 255.0, green: 138.0 / 255.0, blue: 126.0 / 255.0)
    /// #187E91 — Cyan-Teal Bridge for heuristic badges on white
    public static let cyanBridge = Color(red: 24.0 / 255.0, green: 126.0 / 255.0, blue: 145.0 / 255.0)
    /// #E0F4F2 — Soft Mint Surface Wash (from innoteclabs.com)
    public static let mintSurfaceTint = Color(red: 224.0 / 255.0, green: 244.0 / 255.0, blue: 242.0 / 255.0)

    /// Semantic Status Accents (High-contrast on White Glass)
    public static let amberReview = Color(red: 196.0 / 255.0, green: 112.0 / 255.0, blue: 6.0 / 255.0)
    public static let coralAlert = Color(red: 197.0 / 255.0, green: 52.0 / 255.0, blue: 52.0 / 255.0)

    /// Light-Mode White Canvas & Typography Ink Tokens
    public static let canvasWhite = Color.white
    public static let pearlSurface = Color(red: 246.0 / 255.0, green: 248.0 / 255.0, blue: 252.0 / 255.0)
    public static let codePillSurface = Color(red: 242.0 / 255.0, green: 240.0 / 255.0, blue: 250.0 / 255.0)

    /// #171226 — Primary Deep Slate-Indigo Ink
    public static let inkPrimary = Color(red: 23.0 / 255.0, green: 18.0 / 255.0, blue: 38.0 / 255.0)
    /// #4A4260 — Secondary Slate-Violet Ink
    public static let inkSecondary = Color(red: 74.0 / 255.0, green: 66.0 / 255.0, blue: 96.0 / 255.0)
    /// #6E6685 — Muted Monospace & Caption Ink
    public static let inkMuted = Color(red: 110.0 / 255.0, green: 102.0 / 255.0, blue: 133.0 / 255.0)

    /// Legacy compatibility aliases
    public static let obsidianBase = inkPrimary
    public static let midnightIndigo = pearlSurface
    public static let slateSurface = Color(red: 248.0 / 255.0, green: 249.0 / 255.0, blue: 253.0 / 255.0)

    /// Signature Innotec Labs Purple-to-Green Gradients
    public static let purpleGreenLine = LinearGradient(
        colors: [royalPurple, electricViolet, mintTeal, vibrantTeal],
        startPoint: .leading,
        endPoint: .trailing
    )

    public static let purpleGreenDiagonal = LinearGradient(
        colors: [royalPurple, electricViolet, mintTeal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Critically Damped Default Spring (damping = 1.0, response = 0.32)
    public static let fluidSpring = Animation.spring(response: 0.32, dampingFraction: 1.0, blendDuration: 0.08)
    /// Press Feedback Spring (instant response on pointer-down)
    public static let pressSpring = Animation.spring(response: 0.22, dampingFraction: 1.0, blendDuration: 0.0)
}

// MARK: - Reusable Purple-Green Gradient Hairline Divider

public struct InnotecPurpleGreenLine: View {
    public var height: CGFloat = 2.0
    public var opacity: Double = 0.85

    public init(height: CGFloat = 2.0, opacity: Double = 0.85) {
        self.height = height
        self.opacity = opacity
    }

    public var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        InnotecTheme.royalPurple.opacity(opacity),
                        InnotecTheme.electricViolet.opacity(opacity),
                        InnotecTheme.mintTeal.opacity(opacity),
                        InnotecTheme.vibrantTeal.opacity(opacity),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: height)
    }
}

// MARK: - JAM Cleaner Brand Icon Badge & Header Lockup (Light Mode)

public struct JAMCleanerIconBadge: View {
    public var size: CGFloat = 44

    public init(size: CGFloat = 44) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.11, blue: 0.56),
                            InnotecTheme.royalPurple,
                            Color(red: 0.26, green: 0.22, blue: 0.72),
                            InnotecTheme.mintTeal,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.60),
                                    InnotecTheme.electricViolet.opacity(0.35),
                                    InnotecTheme.mintTeal.opacity(0.65),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                )
                .shadow(color: InnotecTheme.royalPurple.opacity(0.24), radius: 8, x: 0, y: 3)

            // Sweep instrument track & glowing arc
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: size * 0.085)
                .frame(width: size * 0.68, height: size * 0.68)

            Circle()
                .trim(from: 0.08, to: 0.80)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.52, green: 0.45, blue: 1.0),
                            Color(red: 0.22, green: 0.82, blue: 0.98),
                            Color(red: 0.14, green: 0.96, blue: 0.76),
                            Color(red: 0.52, green: 0.45, blue: 1.0),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round)
                )
                .rotationEffect(.degrees(115))
                .frame(width: size * 0.68, height: size * 0.68)

            // Crisp pearl center medallion with sparkle emblem
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.93, green: 0.95, blue: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.44, height: size * 0.44)
                .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.23, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            InnotecTheme.royalPurple,
                            InnotecTheme.mintTeal,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: size, height: size)
    }
}

public struct InnotecBrandLockup: View {
    public let language: AppLanguage

    public init(language: AppLanguage = .english) {
        self.language = language
    }

    public var body: some View {
        HStack(spacing: 12) {
            JAMCleanerIconBadge(size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("JAM Cleaner")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(InnotecTheme.inkPrimary)

                Text("Just another MacOS Cleaner")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .tracking(-0.1)
                    .foregroundStyle(InnotecTheme.inkSecondary)
            }
        }
    }
}

// MARK: - Crisp White Canvas with Signature Innotec Purple-Green Flowing Lines

public struct InnotecAmbientCanvas: View {
    public init() {}

    public var body: some View {
        ZStack {
            // 1. Pure Luminous White & Pearl Base
            LinearGradient(
                colors: [
                    Color.white,
                    InnotecTheme.pearlSurface,
                    Color.white,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 2. Soft Pastel Lavender & Mint Corner Washes (from innoteclabs.com)
            RadialGradient(
                colors: [
                    InnotecTheme.lavenderTint.opacity(0.85),
                    InnotecTheme.lavenderTint.opacity(0.25),
                    Color.clear,
                ],
                center: .init(x: 0.12, y: 0.14),
                startRadius: 10,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    InnotecTheme.mintSurfaceTint.opacity(0.90),
                    InnotecTheme.mintSurfaceTint.opacity(0.28),
                    Color.clear,
                ],
                center: .init(x: 0.88, y: 0.84),
                startRadius: 20,
                endRadius: 540
            )

            // 3. Signature Flowing Purple-to-Green Vector Lines across the White Canvas
            Canvas { context, size in
                let w = size.width
                let h = size.height

                let primaryLineGrad = Gradient(colors: [
                    InnotecTheme.royalPurple.opacity(0.32),
                    InnotecTheme.electricViolet.opacity(0.36),
                    InnotecTheme.mintTeal.opacity(0.38),
                    InnotecTheme.vibrantTeal.opacity(0.30),
                ])

                let secondaryLineGrad = Gradient(colors: [
                    InnotecTheme.mintTeal.opacity(0.28),
                    InnotecTheme.electricViolet.opacity(0.26),
                    InnotecTheme.royalPurple.opacity(0.30),
                ])

                // Top flowing purple-green ribbon wave
                var wave1 = Path()
                wave1.move(to: CGPoint(x: 0, y: h * 0.11))
                wave1.addCurve(
                    to: CGPoint(x: w, y: h * 0.08),
                    control1: CGPoint(x: w * 0.32, y: h * 0.02),
                    control2: CGPoint(x: w * 0.68, y: h * 0.18)
                )
                context.stroke(
                    wave1,
                    with: .linearGradient(primaryLineGrad, startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                )

                // Parallel fine harmonic wave
                var wave2 = Path()
                wave2.move(to: CGPoint(x: 0, y: h * 0.135))
                wave2.addCurve(
                    to: CGPoint(x: w, y: h * 0.105),
                    control1: CGPoint(x: w * 0.35, y: h * 0.045),
                    control2: CGPoint(x: w * 0.65, y: h * 0.205)
                )
                context.stroke(
                    wave2,
                    with: .linearGradient(secondaryLineGrad, startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                )

                // Mid-canvas diagonal purple-green contour line (refracted behind the 3 glass islands)
                var wave3 = Path()
                wave3.move(to: CGPoint(x: -20, y: h * 0.62))
                wave3.addCurve(
                    to: CGPoint(x: w + 20, y: h * 0.38),
                    control1: CGPoint(x: w * 0.28, y: h * 0.34),
                    control2: CGPoint(x: w * 0.72, y: h * 0.68)
                )
                context.stroke(
                    wave3,
                    with: .linearGradient(
                        primaryLineGrad, startPoint: CGPoint(x: 0, y: h * 0.62), endPoint: CGPoint(x: w, y: h * 0.38)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )

                // Bottom flowing purple-green accent line behind the command dock
                var wave4 = Path()
                wave4.move(to: CGPoint(x: 0, y: h * 0.91))
                wave4.addCurve(
                    to: CGPoint(x: w, y: h * 0.93),
                    control1: CGPoint(x: w * 0.36, y: h * 0.97),
                    control2: CGPoint(x: w * 0.66, y: h * 0.86)
                )
                context.stroke(
                    wave4,
                    with: .linearGradient(
                        primaryLineGrad, startPoint: CGPoint(x: 0, y: h), endPoint: CGPoint(x: w, y: h)),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Fluid Press Button Style (Instant Pointer-Down Response)

public struct AppleFluidPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public var scaleAmount: CGFloat

    public init(scaleAmount: CGFloat = 0.975) {
        self.scaleAmount = scaleAmount
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scaleAmount : 1.0)
            .brightness(configuration.isPressed ? -0.02 : 0.0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : InnotecTheme.pressSpring,
                value: configuration.isPressed
            )
    }
}

// MARK: - White Liquid Glass Surface Modifier with Purple-Green Gradient Lines

public struct InnotecLiquidGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    public let cornerRadius: CGFloat
    public let tint: Color
    public let tintOpacity: Double
    public let isInteractive: Bool
    public let isStaticSnapshot: Bool
    public let isElevated: Bool

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isHighlighted = (tintOpacity >= 0.24)

        let baseStyled =
            content
            .background(
                ZStack {
                    if reduceTransparency {
                        shape.fill(Color.white)
                    } else {
                        // Pure frosted White Liquid Glass substrate with delicate purple-green pastel sheen
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isElevated ? 0.95 : 0.88),
                                    Color.white.opacity(isElevated ? 0.88 : 0.80),
                                    tint.opacity(min(0.14, tintOpacity * 0.42)),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
            )
            .overlay(
                // Signature Innotec Labs Purple-to-Green Gradient Border Line
                shape.strokeBorder(
                    LinearGradient(
                        colors: isHighlighted
                            ? [
                                InnotecTheme.royalPurple.opacity(0.90),
                                InnotecTheme.electricViolet.opacity(0.85),
                                InnotecTheme.mintTeal.opacity(0.95),
                                InnotecTheme.vibrantTeal.opacity(0.90),
                            ]
                            : [
                                InnotecTheme.royalPurple.opacity(isElevated ? 0.45 : 0.28),
                                InnotecTheme.electricViolet.opacity(isElevated ? 0.38 : 0.22),
                                InnotecTheme.mintTeal.opacity(isElevated ? 0.50 : 0.32),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isHighlighted ? 1.8 : (isElevated ? 1.25 : 1.0)
                )
            )
            .shadow(
                color: InnotecTheme.royalPurple.opacity(isHighlighted ? 0.14 : (isElevated ? 0.08 : 0.04)),
                radius: isHighlighted ? 14 : (isElevated ? 16 : 8),
                x: 0,
                y: isElevated ? 6 : 3
            )

        if isStaticSnapshot || reduceTransparency {
            baseStyled
        } else {
            // Native Swift 6.4 / macOS 26+ Liquid Glass shader & lensing over white canvas
            baseStyled
                .glassEffect(
                    isInteractive
                        ? .regular.tint(Color.white.opacity(0.35)).interactive()
                        : .regular.tint(Color.white.opacity(0.25)),
                    in: shape
                )
        }
    }
}

extension View {
    public func innotecLiquidGlass(
        cornerRadius: CGFloat = 16,
        tint: Color = InnotecTheme.royalPurple,
        tintOpacity: Double = 0.14,
        isInteractive: Bool = false,
        isStaticSnapshot: Bool = false,
        isElevated: Bool = false
    ) -> some View {
        modifier(
            InnotecLiquidGlassModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                tintOpacity: tintOpacity,
                isInteractive: isInteractive,
                isStaticSnapshot: isStaticSnapshot,
                isElevated: isElevated
            )
        )
    }
}
