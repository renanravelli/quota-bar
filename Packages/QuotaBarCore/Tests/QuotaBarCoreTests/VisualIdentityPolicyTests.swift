import Foundation
import Testing

@testable import QuotaBarCore

private func value(_ percent: String, window: QuotaWindow = .fiveHour) -> DisplayValue {
    let utilization = Utilization(originPercent: Decimal(string: percent)!)!
    return DisplayValue(
        selection: .reportedByOrigin(window),
        utilization: utilization,
        band: ConsumptionBand(utilization: utilization)
    )
}

@Suite("Política de animação")
struct AnimationPolicyTests {
    @Test("a política decide apenas a partir do argumento")
    func policyDependsOnlyOnItsArgument() {
        #expect(AnimationPolicy.shouldAnimate(.off))
        #expect(!AnimationPolicy.shouldAnimate(.on))
        #expect(AnimationPolicy.shouldAnimate(.off) == AnimationPolicy.shouldAnimate(.off))
    }

    @Test("preferência indeterminada falha para o lado seguro e não anima")
    func undeterminedDoesNotAnimate() {
        #expect(!AnimationPolicy.shouldAnimate(.undetermined))
    }

    @Test("os três casos são distintos e cobrem a preferência inteira")
    func thePreferenceHasThreeDistinctCases() {
        let all: Set<ReduceMotionPreference> = [.on, .off, .undetermined]

        #expect(all.count == 3)
        #expect(AnimationPolicy.shouldAnimate(.undetermined) == AnimationPolicy.shouldAnimate(.on))
    }
}

@Suite("Resolução do símbolo")
struct SymbolResolverTests {
    private static func appearance(
        _ state: IndicatorState,
        source: QuotaSource? = .primaryProbe,
        inEpisode: Bool = false
    ) -> SymbolAppearance {
        SymbolResolver.appearance(for: state, source: source, inEpisode: inEpisode)
    }

    @Test("em regime, ready e stale são template monocromático")
    func regimeIsMonochromeTemplate() {
        #expect(Self.appearance(.ready(value("50"))).tint == .template)
        #expect(Self.appearance(.stale(value("50"))).tint == .template)
        #expect(Self.appearance(.ready(value("95"))).tint == .template)
    }

    @Test("em exhausted o símbolo ganha cor própria")
    func exhaustedIsColoured() {
        guard case .colored = Self.appearance(.exhausted(value("100"))).tint else {
            Issue.record("exhausted deveria ter cor própria")
            return
        }
    }

    @Test("exhausted é a única situação de regime com cor")
    func exhaustedIsTheOnlyColouredRegimeState() {
        let regimeStates: [IndicatorState] = [
            .notConfigured, .loading, .failed(.communicationFailure),
            .ready(value("0")), .ready(value("50")), .ready(value("80")), .ready(value("95")),
            .stale(value("50")), .stale(value("99"))
        ]

        for state in regimeStates {
            #expect(Self.appearance(state).tint == .template, "\(state) não deveria ter cor em regime")
        }
    }

    @Test("o episódio colore e o regime devolve ao template")
    func episodeColoursAndReturns() {
        let state = IndicatorState.ready(value("50"))

        guard case .colored = Self.appearance(state, inEpisode: true).tint else {
            Issue.record("o episódio deveria colorir")
            return
        }
        #expect(Self.appearance(state, inEpisode: false).tint == .template)
    }

    @Test("os estados sem valor não têm forma derivada de faixa")
    func statesWithoutValueHaveNoBandShape() {
        #expect(Self.appearance(.notConfigured).shape == nil)
        #expect(Self.appearance(.loading).shape == nil)
        #expect(Self.appearance(.failed(.credentialExpired)).shape == nil)
    }

    @Test("mesmo sem forma, o tint dos estados sem valor continua significativo")
    func tintRemainsMeaningfulWithoutAShape() {
        #expect(Self.appearance(.notConfigured).tint == .template)
        #expect(Self.appearance(.loading).tint == .template)
        #expect(Self.appearance(.failed(.blockedByPolicy)).tint == .template)

        guard case .colored = Self.appearance(.loading, inEpisode: true).tint else {
            Issue.record("o episódio deveria colorir mesmo sem forma de faixa")
            return
        }
    }

    @Test("sem fonte declarada o preenchimento é o padrão, não contingência")
    func absentSourceIsStandardFill() {
        #expect(Self.appearance(.ready(value("50")), source: nil).fill == .standard)
        #expect(Self.appearance(.ready(value("50")), source: .primaryProbe).fill == .standard)
        #expect(Self.appearance(.ready(value("50")), source: .contingencyStatusLine).fill == .contingency)
    }

    @Test("as quatro faixas produzem quatro formas distintas")
    func fourBandsProduceFourShapes() {
        let shapes = [
            Self.appearance(.ready(value("50"))).shape,
            Self.appearance(.ready(value("80"))).shape,
            Self.appearance(.ready(value("95"))).shape,
            Self.appearance(.exhausted(value("100"))).shape
        ]

        #expect(Set(shapes).count == 4)
        #expect(shapes == [.normal, .attention, .critical, .exhausted])
    }

    @Test("a contingência muda o preenchimento e preserva a forma da faixa")
    func contingencyKeepsShapeAndChangesFill() {
        let primary = Self.appearance(.ready(value("80")), source: .primaryProbe)
        let contingency = Self.appearance(.ready(value("80")), source: .contingencyStatusLine)

        #expect(primary.shape == contingency.shape)
        #expect(primary.shape == .attention)
        #expect(primary.fill == .standard)
        #expect(contingency.fill == .contingency)
        #expect(primary != contingency)
    }

    @Test("a variante de preenchimento é independente da faixa")
    func fillIsIndependentOfBand() {
        for percent in ["50", "80", "95", "100"] {
            let contingency = Self.appearance(.ready(value(percent)), source: .contingencyStatusLine)
            #expect(contingency.fill == .contingency)
        }
    }

    @Test("forma e preenchimento juntos distinguem oito aparências sem depender de cor")
    func shapeAndFillTogetherAreInjective() {
        var combinations: Set<SymbolAppearance> = []

        for percent in ["50", "80", "95", "100"] {
            for source in [QuotaSource.primaryProbe, .contingencyStatusLine] {
                let state: IndicatorState = percent == "100"
                    ? .exhausted(value(percent))
                    : .ready(value(percent))
                let appearance = Self.appearance(state, source: source)
                combinations.insert(
                    SymbolAppearance(shape: appearance.shape, fill: appearance.fill, tint: .template)
                )
            }
        }

        #expect(combinations.count == 8)
    }
}

@Suite("Política de episódio")
struct EpisodePolicyTests {
    private static func trigger(
        from previous: IndicatorState,
        to current: IndicatorState,
        previousSource: QuotaSource? = .primaryProbe,
        currentSource: QuotaSource? = .primaryProbe
    ) -> EpisodeTrigger? {
        EpisodePolicy.trigger(
            from: previous, to: current,
            previousSource: previousSource, currentSource: currentSource
        )
    }

    @Test("a política devolve gatilho de mudança de estado")
    func stateChangeTriggers() {
        #expect(Self.trigger(from: .ready(value("50")), to: .stale(value("50"))) == .stateChanged)
        #expect(Self.trigger(from: .loading, to: .ready(value("50"))) == .stateChanged)
        #expect(Self.trigger(from: .notConfigured, to: .loading) == .stateChanged)
        #expect(Self.trigger(from: .failed(.communicationFailure), to: .failed(.credentialExpired)) == .stateChanged)
    }

    @Test("a política devolve gatilho de cruzamento de faixa")
    func bandCrossingTriggers() {
        #expect(Self.trigger(from: .ready(value("74")), to: .ready(value("75"))) == .bandCrossed)
        #expect(Self.trigger(from: .ready(value("89")), to: .ready(value("90"))) == .bandCrossed)
    }

    @Test("a política devolve gatilho de troca da janela exibida")
    func displayedWindowChangeTriggers() {
        let before = IndicatorState.ready(value("50", window: .fiveHour))
        let after = IndicatorState.ready(value("50", window: .sevenDay))

        #expect(Self.trigger(from: before, to: after) == .displayedWindowChanged)
    }

    @Test("a política devolve gatilho de mudança de modo de fonte")
    func sourceModeChangeTriggers() {
        let state = IndicatorState.ready(value("50"))

        #expect(
            Self.trigger(
                from: state, to: state,
                previousSource: .primaryProbe, currentSource: .contingencyStatusLine
            ) == .sourceModeChanged
        )
    }

    @Test("sem mudança nenhuma, não há gatilho")
    func nothingChangedProducesNoTrigger() {
        let state = IndicatorState.ready(value("50"))

        #expect(Self.trigger(from: state, to: state) == nil)
    }

    @Test("a passagem do tempo, sozinha, não dispara episódio")
    func timePassingAloneDoesNotTrigger() {
        let stale = IndicatorState.stale(value("30"))

        #expect(Self.trigger(from: stale, to: stale) == nil)
        #expect(Self.trigger(from: stale, to: stale) == nil)
        #expect(Self.trigger(from: stale, to: stale) == nil)
    }

    @Test("a política não devolve gatilho para variação de percentual dentro da mesma faixa")
    func percentChangeWithinTheSameBandDoesNotTrigger() {
        #expect(Self.trigger(from: .ready(value("50")), to: .ready(value("60"))) == nil)
        #expect(Self.trigger(from: .ready(value("75")), to: .ready(value("89"))) == nil)
    }

    @Test("a duração máxima do episódio é 600 ms")
    func episodeDurationIsBounded() {
        #expect(EpisodePolicy.maxDuration == .milliseconds(600))
    }

    @Test("o gatilho é um valor único, não uma coleção onde acumular")
    func triggerIsASingleValueWithoutQueue() {
        let first = Self.trigger(from: .ready(value("50")), to: .ready(value("80")))
        let second = Self.trigger(from: .ready(value("80")), to: .ready(value("95")))

        #expect(first == .bandCrossed)
        #expect(second == .bandCrossed)
        #expect(Mirror(reflecting: second as Any).displayStyle != .collection)
    }
}

@Suite("Contagem regressiva")
struct CountdownPolicyTests {
    @Test("abaixo de uma hora exibe segundos e atualiza a cada segundo")
    func belowOneHourUsesSeconds() {
        #expect(CountdownPolicy.format(remaining: .seconds(50 * 60)) == .withSeconds)
        #expect(CountdownPolicy.refreshInterval(for: .withSeconds) == .seconds(1))
    }

    @Test("acima de uma hora omite segundos e atualiza por minuto")
    func aboveOneHourUsesMinutes() {
        #expect(CountdownPolicy.format(remaining: .seconds(90 * 60)) == .minutesOnly)
        #expect(CountdownPolicy.refreshInterval(for: .minutesOnly) == .seconds(60))
    }

    @Test("a fronteira de uma hora não paga 1 Hz para exibir número que não muda")
    func theOneHourBoundaryDoesNotPayForSeconds() {
        #expect(CountdownPolicy.format(remaining: .seconds(3_600)) == .minutesOnly)
        #expect(CountdownPolicy.format(remaining: .seconds(3_599)) == .withSeconds)
        #expect(CountdownPolicy.secondsThreshold == .seconds(3_600))
    }

    @Test("reset já vencido continua no formato de segundos")
    func elapsedResetKeepsSeconds() {
        #expect(CountdownPolicy.format(remaining: .zero) == .withSeconds)
        #expect(CountdownPolicy.format(remaining: .seconds(-30)) == .withSeconds)
    }
}

@Suite("Expressão do mascote")
struct MascotResolverTests {
    @Test("uma expressão distinta para cada faixa")
    func oneExpressionPerBand() {
        let expressions = [
            MascotResolver.expression(for: .ready(value("50"))),
            MascotResolver.expression(for: .ready(value("80"))),
            MascotResolver.expression(for: .ready(value("95"))),
            MascotResolver.expression(for: .exhausted(value("100")))
        ]

        #expect(expressions == [.normal, .attention, .critical, .exhausted])
        #expect(Set(expressions).count == 4)
    }

    @Test("os estados sem valor têm expressão própria")
    func statesWithoutValueShareTheirOwnExpression() {
        #expect(MascotResolver.expression(for: .notConfigured) == .noValue)
        #expect(MascotResolver.expression(for: .loading) == .noValue)
        #expect(MascotResolver.expression(for: .failed(.blockedByPolicy)) == .noValue)
    }

    @Test("a expressão não muda enquanto faixa e estado não mudam")
    func expressionIsStableWithinABand() {
        #expect(
            MascotResolver.expression(for: .ready(value("50")))
                == MascotResolver.expression(for: .ready(value("70")))
        )
        #expect(
            MascotResolver.expression(for: .ready(value("50")))
                == MascotResolver.expression(for: .stale(value("50")))
        )
    }

    @Test("são cinco expressões ao todo")
    func thereAreFiveExpressions() {
        let all: Set<MascotExpression> = [.normal, .attention, .critical, .exhausted, .noValue]

        #expect(all.count == 5)
    }
}
