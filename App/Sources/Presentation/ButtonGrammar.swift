import QuotaBarCore

enum ButtonForm: Equatable {
    case pictogramOnly
    case pictogramWithText
}

struct ActionConditions: Equatable {
    let hasEstablishedConvention: Bool
    let destroysNothing: Bool
    let mistakeUndoneInOneGesture: Bool

    var requiredForm: ButtonForm {
        hasEstablishedConvention && destroysNothing && mistakeUndoneInOneGesture
            ? .pictogramOnly
            : .pictogramWithText
    }
}

enum ButtonSurface: Equatable {
    case built
    case planned
}

enum PictogramRole: Equatable {
    case ordinary
    case emphasis
    case destructive

    var color: RGBColor {
        switch self {
        case .ordinary: Palette.text
        case .emphasis: Palette.accent
        case .destructive: Palette.bad
        }
    }
}

enum ButtonRendering: Equatable {
    case pictogram(symbol: String, name: String)
    case pictogramWithText(symbol: String, title: String)
    case textOnly(title: String)

    var name: String {
        switch self {
        case let .pictogram(_, name): name
        case let .pictogramWithText(_, title): title
        case let .textOnly(title): title
        }
    }
}

enum ButtonAction: CaseIterable {
    case quit
    case openUsageScreen
    case returnToPreviousSurface
    case copyCommand
    case configureCredential
    case startAssistedSetup
    case submitAuthorizationCode
    case saveCredential
    case replaceCredential
    case removeCredential
    case cancelConduction

    var symbolName: String {
        switch self {
        case .quit: "power"
        case .openUsageScreen: "chart.xyaxis.line"
        case .returnToPreviousSurface: "chevron.backward"
        case .copyCommand: "doc.on.doc"
        case .configureCredential: "key"
        case .startAssistedSetup: "wand.and.stars"
        case .submitAuthorizationCode: "arrow.right.circle"
        case .saveCredential: "checkmark.shield"
        case .replaceCredential: "arrow.triangle.2.circlepath"
        case .removeCredential: "trash"
        case .cancelConduction: "xmark.circle"
        }
    }

    var conditions: ActionConditions {
        switch self {
        case .quit, .openUsageScreen, .returnToPreviousSurface, .copyCommand:
            ActionConditions(
                hasEstablishedConvention: true,
                destroysNothing: true,
                mistakeUndoneInOneGesture: true
            )
        case .configureCredential, .startAssistedSetup, .submitAuthorizationCode:
            ActionConditions(
                hasEstablishedConvention: false,
                destroysNothing: true,
                mistakeUndoneInOneGesture: true
            )
        case .saveCredential:
            ActionConditions(
                hasEstablishedConvention: false,
                destroysNothing: true,
                mistakeUndoneInOneGesture: false
            )
        case .replaceCredential, .removeCredential:
            ActionConditions(
                hasEstablishedConvention: true,
                destroysNothing: false,
                mistakeUndoneInOneGesture: false
            )
        case .cancelConduction:
            ActionConditions(
                hasEstablishedConvention: true,
                destroysNothing: false,
                mistakeUndoneInOneGesture: true
            )
        }
    }

    var form: ButtonForm {
        conditions.requiredForm
    }

    var surface: ButtonSurface {
        switch self {
        case .openUsageScreen, .returnToPreviousSurface: .planned
        case .quit, .copyCommand, .configureCredential, .startAssistedSetup, .submitAuthorizationCode,
             .saveCredential, .replaceCredential, .removeCredential, .cancelConduction: .built
        }
    }

    var role: PictogramRole {
        switch self {
        case .removeCredential: .destructive
        case .startAssistedSetup: .emphasis
        case .quit, .openUsageScreen, .returnToPreviousSurface, .copyCommand, .configureCredential,
             .submitAuthorizationCode, .saveCredential, .replaceCredential, .cancelConduction: .ordinary
        }
    }

    func rendering(titled title: String, symbolIsRenderable: Bool) -> ButtonRendering {
        guard symbolIsRenderable else { return .textOnly(title: title) }

        return switch form {
        case .pictogramOnly: .pictogram(symbol: symbolName, name: title)
        case .pictogramWithText: .pictogramWithText(symbol: symbolName, title: title)
        }
    }
}
