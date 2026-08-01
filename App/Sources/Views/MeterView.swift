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
    let display: CadenceDisplay

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(Palette.track))
                Capsule()
                    .fill(Color(Palette.accent))
                    .frame(width: geometry.size.width * display.progress)
            }
            .overlay(alignment: .leading) { reinforcement }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var reinforcement: some View {
        switch display.reinforcement {
        case .none:
            EmptyView()
        case .idle:
            Capsule()
                .stroke(Color(Palette.textMuted), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        case .failure:
            Capsule()
                .stroke(Color(Palette.bad), lineWidth: 1)
        case .deferral:
            Capsule()
                .stroke(Color(Palette.structuralWeak), style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
        }
    }
}
