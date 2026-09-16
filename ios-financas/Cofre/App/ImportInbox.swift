import Foundation
import SwiftUI

/// Um arquivo que chegou de fora esperando para ser importado.
struct IncomingFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
}

/// Recebe os extratos que o iOS entrega ao app.
///
/// Quando você toca em Compartilhar no app do banco e escolhe o Cofre, o
/// sistema copia o arquivo para a pasta `Documents/Inbox` e abre o app. Esta
/// classe tira o arquivo de lá, guarda numa pasta nossa e enfileira para a tela
/// de importação — que continua sendo a mesma de sempre, com escolha de destino,
/// prévia e deduplicação.
///
/// Tirar da `Inbox` do sistema importa: ela é pública para quem compartilhou e
/// o iOS não a limpa sozinho.
@MainActor
final class ImportInbox: ObservableObject {

    /// Fila de arquivos aguardando importação. O primeiro é o que está na tela.
    @Published private(set) var queue: [IncomingFile] = []

    /// Pedido de abrir a importação sem arquivo (veio de `cofre://importar`).
    @Published var wantsEmptyImport = false

    var current: IncomingFile? { queue.first }

    private let fileManager = FileManager.default

    /// Pasta nossa, fora da `Inbox`, onde os arquivos ficam até serem lidos.
    private var storage: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExtratosRecebidos", isDirectory: true)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private var systemInbox: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    // MARK: - Entrada

    /// Trata uma URL entregue pelo sistema: arquivo compartilhado ou
    /// `cofre://importar`.
    func handle(_ url: URL) {
        if url.isFileURL {
            receive(url)
            return
        }
        if url.scheme?.lowercased() == "cofre", url.host?.lowercased() == "importar" {
            wantsEmptyImport = true
        }
    }

    /// Guarda uma cópia do arquivo e põe na fila.
    func receive(_ url: URL) {
        // Arquivo vindo de fora do contêiner precisa de permissão explícita.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }

        let destination = storage.appendingPathComponent(uniqueName(for: url.lastPathComponent))
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return }

        // Se o original estava na Inbox do sistema, a cópia já está segura.
        if url.path.hasPrefix(systemInbox.path) {
            try? fileManager.removeItem(at: url)
        }

        queue.append(IncomingFile(url: destination))
    }

    /// Recolhe o que o sistema deixou na `Inbox` — inclusive de uma abertura
    /// anterior que não chegou a ser importada.
    func scanSystemInbox() {
        guard let found = try? fileManager.contentsOfDirectory(
            at: systemInbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in found {
            receive(url)
        }
    }

    /// Reenfileira o que sobrou de sessões anteriores, para nada se perder se o
    /// app foi fechado no meio da importação.
    func restorePending() {
        guard let found = try? fileManager.contentsOfDirectory(
            at: storage,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let known = Set(queue.map(\.url))
        for url in found where !known.contains(url) {
            queue.append(IncomingFile(url: url))
        }
    }

    // MARK: - Saída

    /// Tira o arquivo da fila e apaga a cópia. Chamado tanto quando a
    /// importação termina quanto quando você fecha a tela sem importar — nos
    /// dois casos o arquivo já cumpriu seu papel.
    func finish(_ file: IncomingFile) {
        try? fileManager.removeItem(at: file.url)
        queue.removeAll { $0.id == file.id }
    }

    func finishCurrent() {
        guard let current else { return }
        finish(current)
    }

    // MARK: - Auxiliares

    /// Evita que dois extratos com o mesmo nome se sobreponham.
    private func uniqueName(for name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let stamp = Int(Date().timeIntervalSince1970)
        let safe = base.isEmpty ? "extrato" : base
        return ext.isEmpty ? "\(safe)-\(stamp)" : "\(safe)-\(stamp).\(ext)"
    }
}
