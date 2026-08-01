import QuotaBarCore
import SwiftUI

@main
struct QuotaBarApp: App {
    @State private var presenter: IndicatorPresenter
    @State private var render: PanelRenderClock
    @State private var preferences = AccessibilityPreferences()
    @State private var setup: CredentialSetupModel

    init() {
        let provider = ProviderFactory.make()
        let render = PanelRenderClock()
        _render = State(initialValue: render)
        _presenter = State(initialValue: IndicatorPresenter(provider: provider, requestRender: render.mark))
        _setup = State(
            initialValue: CredentialSetupFactory.make(credentialDidChange: { await provider.refreshNow() })
        )
    }

    var body: some Scene {
        MenuBarExtra {
            PanelHost(presenter: presenter, render: render, preferences: preferences)
        } label: {
            Label {
                Text(presenter.indicatorText)
            } icon: {
                BarSymbolView(
                    appearance: presenter.symbolAppearance,
                    fallbackSystemName: presenter.symbolName
                )
            }
            .accessibilityLabel(Text(presenter.accessibilityLabel))
            .task { await presenter.observeStates() }
        }
        .menuBarExtraStyle(.window)

        Window(CredentialSetupText.title, id: CredentialSetupWindow.id) {
            CredentialSetupView(
                model: setup,
                shouldAnimateEntry: AnimationPolicy.shouldAnimate(preferences.reduceMotion)
            )
        }
        .windowResizability(.contentSize)
    }
}

private struct PanelHost: View {
    let presenter: IndicatorPresenter
    let render: PanelRenderClock
    let preferences: AccessibilityPreferences

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        QuotaPanelView(
            content: presenter.panelContent(at: render.instant),
            shouldAnimateEntry: AnimationPolicy.shouldAnimate(preferences.reduceMotion),
            configureCredential: {
                NSApp.activate()
                openWindow(id: CredentialSetupWindow.id)
            },
            quit: {
                NSApplication.shared.terminate(nil)
            }
        )
        .onAppear { presenter.panelDidOpen() }
        .onDisappear { presenter.panelDidClose() }
    }
}
