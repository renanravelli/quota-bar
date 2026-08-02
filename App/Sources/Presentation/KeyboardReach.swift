import AppKit
import Observation

enum CredentialField: Hashable {
    case authorizationCode
    case credential
}

extension CredentialSetupContent {
    var focusableFields: [CredentialField] {
        var fields: [CredentialField] = []
        if codeFieldLabel != nil { fields.append(.authorizationCode) }
        if showsField { fields.append(.credential) }
        return fields
    }
}

@MainActor
protocol ApplicationActivating {
    func requestActivation()
}

struct SystemApplication: ApplicationActivating {
    func requestActivation() {
        NSApp.activate()
    }
}

@MainActor
@Observable
final class KeyboardReach {
    private(set) var focusedField: CredentialField?

    @ObservationIgnored private var receivesTyping = false
    @ObservationIgnored private var offered: [CredentialField] = []
    @ObservationIgnored private var held: CredentialField?
    @ObservationIgnored private let application: any ApplicationActivating

    init(application: any ApplicationActivating = SystemApplication()) {
        self.application = application
    }

    func observed(keyWindow: Bool) {
        receivesTyping = keyWindow
        drawFocus()
    }

    func offers(_ fields: [CredentialField]) {
        offered = fields
        held = held.flatMap { fields.contains($0) ? $0 : nil } ?? fields.first
        drawFocus()
    }

    func personFocused(_ field: CredentialField?) {
        guard let field, offered.contains(field) else { return }
        held = field
        drawFocus()
    }

    func surfaceClosed() {
        receivesTyping = false
        offered = []
        held = nil
        drawFocus()
    }

    func requestForeground() {
        application.requestActivation()
    }

    private func drawFocus() {
        focusedField = receivesTyping ? held : nil
    }
}
