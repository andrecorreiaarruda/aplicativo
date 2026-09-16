import Foundation
import SwiftUI

/// Preferências do app. São poucas de propósito.
///
/// Usa `@Published` sobre o `UserDefaults` em vez de `@AppStorage`: dentro de um
/// `ObservableObject`, o `@AppStorage` grava mas não avisa as telas, e o botão de
/// esconder valores não atualizaria nada.
@MainActor
final class AppSettings: ObservableObject {

    @Published var requireBiometrics: Bool {
        didSet { defaults.set(requireBiometrics, forKey: Keys.requireBiometrics) }
    }

    @Published var hideAmounts: Bool {
        didSet { defaults.set(hideAmounts, forKey: Keys.hideAmounts) }
    }

    @Published var startTab: Int {
        didSet { defaults.set(startTab, forKey: Keys.startTab) }
    }

    /// Mês em que você começou a usar envelopes. Antes dele não há saldo
    /// acumulado: todo envelope nasce zerado aqui. Sem essa âncora, o cálculo
    /// do acúmulo não teria onde parar de voltar no tempo.
    @Published var envelopeStartMonth: MonthKey {
        didSet { defaults.set(envelopeStartMonth.key, forKey: Keys.envelopeStart) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let requireBiometrics = "requireBiometrics"
        static let hideAmounts = "hideAmounts"
        static let startTab = "startTab"
        static let envelopeStart = "envelopeStartMonth"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A trava biométrica vem ligada: o padrão seguro é o que protege quem
        // nunca abre os ajustes.
        self.requireBiometrics = defaults.object(forKey: Keys.requireBiometrics) as? Bool ?? true
        self.hideAmounts = defaults.bool(forKey: Keys.hideAmounts)
        self.startTab = defaults.integer(forKey: Keys.startTab)
        // Na primeira abertura, os envelopes começam no mês corrente — e o
        // valor é gravado na hora. Se ficasse só em memória, todo mês novo
        // viraria o "início" e o acúmulo se perderia sozinho na virada.
        if let stored = defaults.string(forKey: Keys.envelopeStart).flatMap(MonthKey.init(key:)) {
            self.envelopeStartMonth = stored
        } else {
            let first = MonthKey.current
            self.envelopeStartMonth = first
            defaults.set(first.key, forKey: Keys.envelopeStart)
        }
    }

    /// Esconde os valores na tela (útil em lugar público). Os dados continuam
    /// lá; só a exibição muda.
    func display(_ value: Decimal, signed: Bool = false) -> String {
        guard !hideAmounts else { return "R$ ••••" }
        return signed ? Money.signed(value) : Money.string(value)
    }

    func displayAbs(_ value: Decimal) -> String {
        guard !hideAmounts else { return "R$ ••••" }
        return Money.abs(value)
    }
}
