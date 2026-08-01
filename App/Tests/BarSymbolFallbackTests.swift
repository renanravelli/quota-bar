import AppKit
import Foundation
import Testing

@testable import QuotaBar
@testable import QuotaBarCore

private func value(_ percent: String) -> DisplayValue {
    let utilization = Utilization(originPercent: Decimal(string: percent)!)!
    return DisplayValue(
        selection: .reportedByOrigin(.fiveHour),
        utilization: utilization,
        band: ConsumptionBand(utilization: utilization)
    )
}

private final class TestBundleMarker {}

@Suite("Símbolo da barra com reserva")
struct BarSymbolFallbackTests {
    private static let bundleWithoutArt = Bundle(for: TestBundleMarker.self)

    private static let states: [IndicatorState] = [
        .notConfigured,
        .loading,
        .failed(.credentialExpired),
        .ready(value("50")),
        .ready(value("80")),
        .ready(value("95")),
        .stale(value("42")),
        .exhausted(value("100"))
    ]

    private static let sources: [QuotaSource?] = [nil, .primaryProbe, .contingencyStatusLine]

    @Test("QB-APP-002 AC-2: a arte própria existe e carrega para as oito combinações de faixa e preenchimento")
    func customArtLoadsForEveryBandAndFill() {
        for percent in ["50", "80", "95", "100"] {
            for source in [QuotaSource.primaryProbe, .contingencyStatusLine] {
                let state: IndicatorState = percent == "100"
                    ? .exhausted(value(percent))
                    : .ready(value(percent))
                let appearance = SymbolResolver.appearance(for: state, source: source, inEpisode: false)

                let image = BarSymbolAsset.image(for: appearance)
                #expect(image != nil, "sem arte para \(percent)% em \(source)")
                #expect(image?.isTemplate == true, "o símbolo precisa ser template para herdar a barra de menus")
            }
        }
    }

    @Test("QB-APP-002 AC-32: com a arte indisponível no bundle, nenhum símbolo customizado é carregado")
    func customArtIsAbsentInABundleWithoutIt() {
        for state in Self.states {
            for source in Self.sources {
                let appearance = SymbolResolver.appearance(for: state, source: source, inEpisode: false)
                #expect(BarSymbolAsset.image(for: appearance, in: Self.bundleWithoutArt) == nil)
            }
        }
    }

    @Test("QB-APP-002 AC-32: o símbolo de reserva existe e é carregável em todos os estados")
    func fallbackSymbolAlwaysResolves() {
        for state in Self.states {
            for source in Self.sources {
                let fallback = IndicatorSymbol.name(for: state, source: source ?? .primaryProbe)
                #expect(
                    NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil,
                    "símbolo de reserva não carregável para \(state)"
                )
            }
        }
    }

    @Test("QB-APP-002 AC-32: o item nunca fica sem símbolo — customizado ou reserva, sempre há um")
    func thereIsAlwaysASymbolToDraw() {
        for state in Self.states {
            for source in Self.sources {
                let appearance = SymbolResolver.appearance(for: state, source: source, inEpisode: false)
                let custom = BarSymbolAsset.image(for: appearance, in: Self.bundleWithoutArt)
                let fallback = NSImage(
                    systemSymbolName: IndicatorSymbol.name(for: state, source: source ?? .primaryProbe),
                    accessibilityDescription: nil
                )

                #expect(custom != nil || fallback != nil)
            }
        }
    }

    @Test("QB-APP-002 AC-4 e QB-APP-002 AC-7: o nome do recurso customizado codifica faixa e preenchimento")
    func customNameEncodesBandAndFill() {
        let primary = SymbolResolver.appearance(
            for: .ready(value("80")), source: .primaryProbe, inEpisode: false
        )
        let contingency = SymbolResolver.appearance(
            for: .ready(value("80")), source: .contingencyStatusLine, inEpisode: false
        )

        #expect(BarSymbolAsset.customName(for: primary) == "QuotaBarSymbolAttentionStandard")
        #expect(BarSymbolAsset.customName(for: contingency) == "QuotaBarSymbolAttentionContingency")
        #expect(BarSymbolAsset.customName(for: primary) != BarSymbolAsset.customName(for: contingency))
    }

    @Test("QB-APP-002 AC-4: os estados sem forma não pedem recurso customizado")
    func statesWithoutShapeAskForNoCustomResource() {
        for state in [IndicatorState.notConfigured, .loading, .failed(.blockedByPolicy)] {
            let appearance = SymbolResolver.appearance(for: state, source: .primaryProbe, inEpisode: false)
            #expect(BarSymbolAsset.customName(for: appearance) == nil)
        }
    }

    @Test("QB-APP-002 AC-6: as oito combinações de faixa e preenchimento pedem oito recursos distintos")
    func eightDistinctCustomResources() {
        var names: Set<String> = []

        for percent in ["50", "80", "95", "100"] {
            for source in [QuotaSource.primaryProbe, .contingencyStatusLine] {
                let state: IndicatorState = percent == "100"
                    ? .exhausted(value(percent))
                    : .ready(value(percent))
                let appearance = SymbolResolver.appearance(for: state, source: source, inEpisode: false)
                if let name = BarSymbolAsset.customName(for: appearance) {
                    names.insert(name)
                }
            }
        }

        #expect(names.count == 8)
    }
}
