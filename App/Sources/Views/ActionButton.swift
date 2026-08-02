import QuotaBarCore
import SwiftUI

enum ActionButtonMetrics {
    static let minimumTargetSide: CGFloat = 24
}

struct ActionButton: View {
    let action: ButtonAction
    let title: String
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            content
                .foregroundStyle(Color(action.role.color))
                .frame(
                    minWidth: ActionButtonMetrics.minimumTargetSide,
                    minHeight: ActionButtonMetrics.minimumTargetSide
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(title))
        .help(title)
    }

    @ViewBuilder
    private var content: some View {
        switch action.rendering(titled: title, symbolIsRenderable: SystemSymbol.isRenderable(action.symbolName)) {
        case let .pictogram(symbol, _):
            Image(systemName: symbol)
                .imageScale(.large)
        case let .pictogramWithText(symbol, title):
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .imageScale(.large)
            }
        case let .textOnly(title):
            Text(title)
        }
    }
}
