import QuotaBarCore
import SwiftUI

struct MeterView: View {
    let litSegments: Int
    let tint: QuotaBarCore.RGBColor?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<Meter.segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color(at: index))
                    .frame(height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(at index: Int) -> Color {
        guard index < litSegments, let tint else { return Color(Palette.track) }
        return Color(tint)
    }
}

struct CadenceBarView: View {
    let bar: CadenceBar

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(Palette.track))
                Capsule()
                    .fill(Color(Palette.accent))
                    .frame(width: geometry.size.width * bar.progress)
            }
            .overlay(alignment: .leading) { natureMark }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var natureMark: some View {
        switch bar.mark {
        case .none:
            EmptyView()
        case .idleDashes:
            Capsule()
                .stroke(Color(Palette.textMuted), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        case .failureRing:
            Capsule()
                .stroke(Color(Palette.bad), lineWidth: 1)
        case .deferralDashes:
            Capsule()
                .stroke(Color(Palette.structuralWeak), style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
        }
    }
}
