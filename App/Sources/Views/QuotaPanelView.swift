import QuotaBarCore
import SwiftUI

struct QuotaPanelView: View {
    let content: PanelContent
    let shouldAnimateEntry: Bool
    let configureCredential: () -> Void
    let quit: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hasEntered = false

    private var secondaryStyle: HierarchicalShapeStyle {
        contrast == .increased ? .primary : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = content.fixtureNotice {
                noticeText(notice)
                    .foregroundStyle(.orange)
                    .accessibilityAddTraits(.isHeader)
            }
            if let notice = content.sourceChangeNotice {
                noticeText(notice)
                Divider()
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    windowRow(content.fiveHour)
                    windowRow(content.sevenDay)
                }
                Spacer(minLength: 0)
                MascotView(expression: content.mascot)
            }

            Divider()

            if let selection = content.selection {
                bodyText(selection)
            }
            bodyText(content.situation)
            if let cadenceLine = content.cadenceLine {
                bodyText(cadenceLine)
            }
            if let cadence = content.cadence {
                CadenceBarView(display: cadence)
            }
            if let source = content.source {
                bodyText(source)
            }
            ForEach(content.contingencyLosses, id: \.self) { loss in
                detailText(loss)
            }
            if let credentialNotice = content.credentialNotice {
                detailText(credentialNotice)
            }
            ForEach(content.pendencies, id: \.self) { pendency in
                bodyText(pendency)
            }

            Divider()

            HStack(spacing: 8) {
                if let configureTitle = content.configureCredentialTitle {
                    ActionButton(action: .configureCredential, title: configureTitle, perform: configureCredential)
                }
                ActionButton(action: .quit, title: content.quitTitle, perform: quit)
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(minWidth: 320, maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(PanelSurface.background))
        .opacity(hasEntered ? 1 : 0)
        .onAppear {
            guard shouldAnimateEntry else {
                hasEntered = true
                return
            }
            withAnimation(.easeOut(duration: PanelAnimation.entryDuration.seconds)) {
                hasEntered = true
            }
        }
    }

    private func bodyText(_ value: String) -> some View {
        Text(value)
            .font(.callout)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailText(_ value: String) -> some View {
        bodyText(value)
            .font(.footnote)
            .foregroundStyle(secondaryStyle)
    }

    private func noticeText(_ value: String) -> some View {
        bodyText(value)
            .fontWeight(.semibold)
    }

    @ViewBuilder
    private func windowRow(_ row: WindowRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if let utilization = row.utilization {
                    Text(utilization)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(row.tint.map { Color($0) } ?? Color(Palette.text))
                }
            }
            .accessibilityElement(children: .combine)

            MeterView(litSegments: row.litSegments, tint: row.tint)

            if let countdown = row.countdown {
                Text(countdown)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(row.tint.map { Color($0) } ?? Color(Palette.textMuted))
            }
            if let reset = row.reset {
                detailText("Reseta às \(reset)")
            }
            ForEach(row.absences, id: \.self) { absence in
                detailText(absence)
            }
        }
    }
}
