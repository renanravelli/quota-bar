import AppKit
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

@Suite("Símbolo do indicador")
struct IndicatorSymbolTests {
    private static let bands: [ConsumptionBand] = [.normal, .attention, .critical, .exhausted]
    private static let sources: [QuotaSource] = [.primaryProbe, .contingencyStatusLine]

    private static func displayValue(_ band: ConsumptionBand) -> DisplayValue {
        let percent = switch band {
        case .normal: 5_000
        case .attention: 8_000
        case .critical: 9_500
        case .exhausted: 10_000
        }
        let utilization = Utilization(basisPoints: percent)!
        return DisplayValue(selection: .reportedByOrigin(.fiveHour), utilization: utilization, band: band)
    }

    @Test("as quatro faixas têm símbolos distintos, além de qualquer diferença de cor")
    func bandsHaveDistinctSymbols() {
        for source in Self.sources {
            let names = Set(Self.bands.map { IndicatorSymbol.name(for: $0, source: source) })
            #expect(names.count == 4, "faixas colapsaram em \(names.count) símbolos na fonte \(source)")
        }
    }

    @Test("para a mesma faixa, contingência e fonte primária têm símbolos distintos")
    func sourceModeChangesTheSymbolForTheSameBand() {
        for band in Self.bands {
            let primary = IndicatorSymbol.name(for: band, source: .primaryProbe)
            let contingency = IndicatorSymbol.name(for: band, source: .contingencyStatusLine)
            #expect(primary != contingency, "faixa \(band) não distingue a fonte")
        }
    }

    @Test("os dois eixos juntos produzem oito símbolos distintos")
    func bandAndSourceTogetherAreInjective() {
        var names: Set<String> = []
        for band in Self.bands {
            for source in Self.sources {
                names.insert(IndicatorSymbol.name(for: band, source: source))
            }
        }

        #expect(names.count == 8)
    }

    @Test("os três estados sem valor têm símbolo próprio e distinto")
    func statesWithoutValueHaveOwnSymbols() {
        let notConfigured = IndicatorSymbol.name(for: .notConfigured, source: .primaryProbe)
        let loading = IndicatorSymbol.name(for: .loading, source: .primaryProbe)
        let failed = IndicatorSymbol.name(for: .failed(.communicationFailure), source: .primaryProbe)

        #expect(Set([notConfigured, loading, failed]).count == 3)
    }

    @Test("nenhum símbolo de estado sem valor colide com símbolo de faixa")
    func valuelessSymbolsNeverCollideWithBands() {
        var bandNames: Set<String> = []
        for band in Self.bands {
            for source in Self.sources {
                bandNames.insert(IndicatorSymbol.name(for: band, source: source))
            }
        }

        for state in [IndicatorState.notConfigured, .loading, .failed(.credentialExpired)] {
            let name = IndicatorSymbol.name(for: state, source: .primaryProbe)
            #expect(!bandNames.contains(name))
        }
    }

    @Test("o símbolo dos estados com valor acompanha a faixa do valor exibido")
    func statesWithValueUseTheBandSymbol() {
        for band in Self.bands {
            let value = Self.displayValue(band)
            for state in [IndicatorState.ready(value), .stale(value), .exhausted(value)] {
                #expect(
                    IndicatorSymbol.name(for: state, source: .primaryProbe)
                        == IndicatorSymbol.name(for: band, source: .primaryProbe)
                )
            }
        }
    }

    @Test("todo símbolo usado existe no sistema, senão o item da barra fica vazio")
    func everySymbolResolvesOnThisSystem() {
        var names: Set<String> = []
        for band in Self.bands {
            for source in Self.sources {
                names.insert(IndicatorSymbol.name(for: band, source: source))
            }
        }
        for state in [IndicatorState.notConfigured, .loading, .failed(.blockedByPolicy)] {
            names.insert(IndicatorSymbol.name(for: state, source: .primaryProbe))
        }

        for name in names {
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "símbolo inexistente: \(name)"
            )
        }
    }
}
