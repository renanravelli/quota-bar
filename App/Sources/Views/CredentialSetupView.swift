import QuotaBarCore
import SwiftUI

struct CredentialSetupView: View {
    let model: CredentialSetupModel
    let keyboard: KeyboardReach
    let shouldAnimateEntry: Bool

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.controlActiveState) private var activeState
    @FocusState private var focusedField: CredentialField?
    @State private var pasted = ""
    @State private var authorizationCode = ""
    @State private var hasEntered = false

    private var content: CredentialSetupContent {
        model.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.title)
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

            if let precondition = content.precondition {
                Text(precondition)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(Palette.warning))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let notice = content.configuredNotice {
                bodyText(notice)
            }

            assistance

            if content.showsField {
                instructions
                credentialField
                if let reason = content.saveAvailability.reason {
                    bodyText(reason).foregroundStyle(secondaryStyle)
                }
            }

            if let cost = content.costNotice {
                bodyText(cost).foregroundStyle(secondaryStyle)
            }

            if let message = content.message {
                bodyText(message.text)
                    .foregroundStyle(Color(Palette.text))
            }

            actions
        }
        .padding(16)
        .frame(minWidth: 380, maxWidth: 460, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(PanelSurface.background))
        .opacity(hasEntered ? 1 : 0)
        .onChange(of: activeState, initial: true) { _, state in
            keyboard.observed(keyWindow: state == .key)
        }
        .onChange(of: content.focusableFields, initial: true) { _, fields in
            keyboard.offers(fields)
        }
        .onChange(of: keyboard.focusedField, initial: true) { _, field in
            focusedField = field
        }
        .onChange(of: focusedField) { _, field in
            keyboard.personFocused(field)
        }
        .task {
            await model.refresh()
            guard shouldAnimateEntry else {
                hasEntered = true
                return
            }
            withAnimation(.easeOut(duration: PanelAnimation.entryDuration.seconds)) {
                hasEntered = true
            }
        }
        .onDisappear {
            model.cancel()
            keyboard.surfaceClosed()
            pasted = ""
            authorizationCode = ""
        }
    }

    private var assistance: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let assistTitle = content.assistTitle {
                ActionButton(action: .startAssistedSetup, title: assistTitle, availability: .available) {
                    Task { await model.assist() }
                }
                .buttonStyle(.borderedProminent)
            }

            if let reason = content.assistUnavailableReason {
                bodyText(reason).foregroundStyle(secondaryStyle)
            }

            if let waitingNotice = content.waitingNotice {
                bodyText(waitingNotice)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if let codeFieldLabel = content.codeFieldLabel {
                codeEntry(labelled: codeFieldLabel)
            }
        }
    }

    private func codeEntry(labelled label: String) -> some View {
        let submit = model.submitAvailability(codeTyped: !authorizationCode.isEmpty)

        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(secondaryStyle)
            HStack(spacing: 8) {
                TextField(label, text: $authorizationCode)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .accessibilityLabel(Text(label))
                    .focused($focusedField, equals: .authorizationCode)
                ActionButton(
                    action: .submitAuthorizationCode,
                    title: CredentialSetupText.send,
                    availability: submit
                ) {
                    sendCode()
                }
            }
            if let reason = submit.reason {
                bodyText(reason).foregroundStyle(secondaryStyle)
            }
        }
    }

    private func sendCode() {
        let value = authorizationCode
        authorizationCode = ""
        Task { await model.submitCode(value) }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            bodyText(content.commandStep)

            HStack(spacing: 8) {
                Text(content.command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(PanelSurface.card))
                ActionButton(action: .copyCommand, title: content.copyCommandTitle, availability: .available) {
                    model.copyCommand()
                }
            }

            ForEach(content.steps, id: \.self) { step in
                bodyText(step)
            }
        }
    }

    private var credentialField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.fieldLabel)
                .font(.footnote)
                .foregroundStyle(secondaryStyle)
            SecureField(content.fieldLabel, text: $pasted)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityLabel(Text(content.fieldLabel))
                .focused($focusedField, equals: .credential)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if content.showsField {
                ActionButton(
                    action: .saveCredential,
                    title: content.saveTitle,
                    availability: content.saveAvailability
                ) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            if let cancelTitle = content.cancelTitle {
                ActionButton(action: .cancelConduction, title: cancelTitle, availability: .available) {
                    model.cancel()
                }
            }
            if let replaceTitle = content.replaceTitle {
                ActionButton(action: .replaceCredential, title: replaceTitle, availability: .available) {
                    model.beginReplacement()
                }
            }
            if let removeTitle = content.removeTitle {
                ActionButton(action: .removeCredential, title: removeTitle, availability: .available) {
                    Task { await model.remove() }
                }
            }
        }
    }

    private func save() {
        let value = pasted
        pasted = ""
        Task { await model.save(value) }
    }

    private var secondaryStyle: HierarchicalShapeStyle {
        contrast == .increased ? .primary : .secondary
    }

    private func bodyText(_ value: String) -> some View {
        Text(value)
            .font(.callout)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
