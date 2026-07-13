import SwiftUI

/// Code-drawn Gaurava brand mark: the ribbon "G" plus the warm terracotta crescent,
/// using the same artwork geometry as the app icon but drawn as vectors in code.
///
/// This is intentionally decoupled from `AppIcon`. Share cards use it for branding so
/// the attribution stays crisp at any size and never goes stale when the app icon is
/// reskinned (no bundled PNG to keep in sync).
struct GauravaBrandMark: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let scale = side / 1024.0

            // Mirror the source SVG group transform applied to the 1024 artboard:
            // translate(0,-23) * translate(512,512) * scale(0.81) * translate(-512,-512)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let tx = (x - 512) * 0.81 + 512
                let ty = (y - 512) * 0.81 + 512 - 23
                return CGPoint(x: tx * scale, y: ty * scale)
            }

            // Teal ribbon "G" (stroked centerline, round caps) — drawn first (back).
            var g = Path()
            g.move(to: point(784, 264))
            g.addCurve(to: point(294, 280), control1: point(660, 154), control2: point(444, 145))
            g.addCurve(to: point(333, 848), control1: point(112, 444), control2: point(126, 720))
            g.addCurve(to: point(854, 670), control1: point(524, 967), control2: point(778, 881))
            g.addCurve(to: point(724, 512), control1: point(885, 584), control2: point(829, 512))
            g.addLine(to: point(560, 512))
            context.stroke(
                g,
                with: .color(AppTheme.primary),
                style: StrokeStyle(lineWidth: 156 * 0.81 * scale, lineCap: .round, lineJoin: .round)
            )

            // Warm terracotta crescent (filled) — drawn on top (front).
            var crescent = Path()
            crescent.move(to: point(316, 554))
            crescent.addCurve(to: point(644, 738), control1: point(360, 682), control2: point(484, 762))
            crescent.addCurve(to: point(834, 606), control1: point(728, 725), control2: point(787, 674))
            crescent.addCurve(to: point(528, 801), control1: point(809, 749), control2: point(680, 825))
            crescent.addCurve(to: point(316, 554), control1: point(415, 783), control2: point(337, 696))
            crescent.closeSubpath()
            context.fill(crescent, with: .color(AppTheme.medication))
        }
        .accessibilityHidden(true)
    }
}
