@testable import QuotaBar

enum ApprovedButtonTable {
    static let roleByAction: [ButtonAction: PictogramRole] = [
        .quit: .ordinary,
        .openUsageScreen: .ordinary,
        .returnToPreviousSurface: .ordinary,
        .copyCommand: .ordinary,
        .configureCredential: .ordinary,
        .startAssistedSetup: .emphasis,
        .submitAuthorizationCode: .ordinary,
        .saveCredential: .ordinary,
        .replaceCredential: .ordinary,
        .removeCredential: .destructive,
        .cancelConduction: .ordinary
    ]

    static var declaredActions: Int {
        roleByAction.count
    }

    static func title(of action: ButtonAction) -> String {
        ButtonGrammarTests.titlesInTheProduct[action] ?? "Ação prevista"
    }
}
