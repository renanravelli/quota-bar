import AppKit
import Foundation
import Observation
import QuotaBarCore

@MainActor
@Observable
final class IndicatorPresenter {
    struct RenderKey: Equatable {
        let appearance: SymbolAppearance
        let text: String
    }

    private(set) var state: QuotaState
    private(set) var indicator: IndicatorState
    private(set) var isInEpisode = false
    private(set) var panelWasOpened = false

    @ObservationIgnored private(set) var symbolRebuildCount = 0
    @ObservationIgnored private var lastRenderKey: RenderKey?

    @ObservationIgnored private var staleLatch = StaleLatch()
    @ObservationIgnored private var deferralLatch = DeferralLatch()
    @ObservationIgnored private(set) var armedDeferralThreshold: Date?
    @ObservationIgnored private(set) var armedAgeThreshold: Date?
    private var lastSeenSourceOnOpen: QuotaSource?
    private var panelIsObserved = false
    private var scheduledReevaluation: Task<Void, Never>?
    private var deferralWatch: Task<Void, Never>?
    private var ageWatch: Task<Void, Never>?
    private var episode: Task<Void, Never>?
    private var viewerSignal: Task<Void, Never>?

    private let provider: any QuotaStateProviding
    private let clock: @Sendable () -> Date
    private let reduceMotion: @MainActor () -> ReduceMotionPreference
    private let episodeDuration: Duration
    private let requestRender: @MainActor () -> Void
    private let countdown: CountdownTicker
    private let cadenceFill: CadenceFillTicker

    init(
        provider: any QuotaStateProviding,
        clock: @escaping @Sendable () -> Date = Date.init,
        reduceMotion: @escaping @MainActor () -> ReduceMotionPreference = SystemAccessibility.reduceMotion,
        episodeDuration: Duration = EpisodePolicy.maxDuration,
        requestRender: @escaping @MainActor () -> Void = {}
    ) {
        self.provider = provider
        self.clock = clock
        self.reduceMotion = reduceMotion
        self.episodeDuration = episodeDuration
        self.requestRender = requestRender
        countdown = CountdownTicker(clock: clock, requestRender: requestRender)
        cadenceFill = CadenceFillTicker(requestRender: requestRender)
        state = .unconfigured
        indicator = .notConfigured
        updateIndicator()
        scheduleNextReevaluation()
        lastRenderKey = RenderKey(appearance: symbolAppearance, text: indicatorText)
    }

    var indicatorText: String {
        IndicatorTextFormatter.text(for: indicator)
    }

    var symbolName: String {
        IndicatorSymbol.name(for: indicator, source: effectiveSource)
    }

    var symbolAppearance: SymbolAppearance {
        SymbolResolver.appearance(for: indicator, source: state.source, inEpisode: isInEpisode)
    }

    var accessibilityLabel: String {
        IndicatorAccessibilityLabel.text(for: indicator, source: effectiveSource)
    }

    private var effectiveSource: QuotaSource {
        state.source ?? state.snapshot?.source ?? .primaryProbe
    }

    func observeStates() async {
        for await newState in provider.states {
            receive(newState)
        }
    }

    func receive(_ newState: QuotaState) {
        let previousIndicator = indicator
        let previousSource = state.source
        state = newState
        reevaluate(previousIndicator: previousIndicator, previousSource: previousSource)
    }

    var nearestReset: Date? {
        guard let snapshot = state.snapshot else { return nil }
        return [snapshot.fiveHour.resetsAt, snapshot.sevenDay.resetsAt].compactMap { $0 }.min()
    }

    var countdownIsArmed: Bool {
        countdown.isRunning
    }

    var cadenceFillIsArmed: Bool {
        cadenceFill.isRunning
    }

    func panelContent(at now: Date) -> PanelContent {
        PanelContentBuilder.build(
            state: state,
            indicator: IndicatorStateResolver.resolve(state: state, latch: &staleLatch, now: now),
            at: now,
            deferralLatch: &deferralLatch,
            previouslySeenSource: lastSeenSourceOnOpen,
            fixtureFed: ProviderFactory.isFixtureFed
        )
    }

    func panelDidOpen() {
        panelWasOpened = true
        panelIsObserved = true
        lastSeenSourceOnOpen = state.source
        schedulePanelCadences()
        signalViewer(observing: true)
    }

    func panelDidClose() {
        panelIsObserved = false
        schedulePanelCadences()
        signalViewer(observing: false)
    }

    private func signalViewer(observing: Bool) {
        let previous = viewerSignal
        viewerSignal = Task { [provider] in
            await previous?.value
            await provider.setViewerObserving(observing)
        }
    }

    private func reevaluate(previousIndicator: IndicatorState, previousSource: QuotaSource?) {
        updateIndicator()

        let trigger = EpisodePolicy.trigger(
            from: previousIndicator,
            to: indicator,
            previousSource: previousSource,
            currentSource: state.source
        )
        if trigger != nil, AnimationPolicy.shouldAnimate(reduceMotion()) {
            beginEpisode()
        }

        scheduleNextReevaluation()
        schedulePanelCadences()
        recordRender()
    }

    private func updateIndicator() {
        let resolved = IndicatorStateResolver.resolve(state: state, latch: &staleLatch, now: clock())
        guard resolved != indicator else { return }
        indicator = resolved
    }

    private func beginEpisode() {
        episode?.cancel()
        isInEpisode = true
        recordRender()

        episode = Task { [weak self, episodeDuration] in
            try? await Task.sleep(for: episodeDuration)
            guard !Task.isCancelled else { return }
            self?.endEpisode()
        }
    }

    private func endEpisode() {
        guard isInEpisode else { return }
        isInEpisode = false
        recordRender()
    }

    private func recordRender() {
        let key = RenderKey(appearance: symbolAppearance, text: indicatorText)
        guard key != lastRenderKey else { return }
        lastRenderKey = key
        symbolRebuildCount += 1
    }

    private func schedulePanelCadences() {
        scheduleDeferralThreshold()
        scheduleAgeThreshold()

        guard panelIsObserved else {
            countdown.stop()
            cadenceFill.stop()
            return
        }

        countdown.start(nextDeadline: nearestReset)
        cadenceFill.start(cadence: state.cycle?.cadence)
    }

    private func scheduleAgeThreshold() {
        ageWatch?.cancel()
        armedAgeThreshold = panelIsObserved ? AgeSchedule.nextThreshold(for: state, now: clock()) : nil
        ageWatch = watch(until: armedAgeThreshold) { [weak self] in self?.ageThresholdReached() }
    }

    private func ageThresholdReached() {
        requestRender()
        scheduleAgeThreshold()
    }

    private func scheduleDeferralThreshold() {
        deferralWatch?.cancel()
        armedDeferralThreshold = panelIsObserved ? DeferralSchedule.nextThreshold(for: state, now: clock()) : nil
        deferralWatch = watch(until: armedDeferralThreshold) { [weak self] in self?.deferralThresholdReached() }
    }

    private func watch(until threshold: Date?, reached: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard let threshold else { return nil }

        let delay = threshold.timeIntervalSince(clock())

        return Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            reached()
        }
    }

    private func deferralThresholdReached() {
        armedDeferralThreshold = nil
        requestRender()
    }

    private func scheduleNextReevaluation() {
        scheduledReevaluation?.cancel()
        scheduledReevaluation = nil

        guard let threshold = StalenessSchedule.nextThreshold(for: state, now: clock()) else { return }

        let delay = threshold.timeIntervalSince(clock())
        guard delay > 0 else { return }

        scheduledReevaluation = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.reevaluate(previousIndicator: self.indicator, previousSource: self.state.source)
        }
    }
}
