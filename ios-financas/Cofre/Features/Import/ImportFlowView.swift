import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Importação de extrato em quatro passos: escolher o destino, escolher o
/// arquivo, conferir as colunas (só CSV) e revisar antes de gravar.
///
/// Nada é gravado até você tocar em "Importar" na revisão.
struct ImportFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.name) private var accounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.name) private var cards: [CreditCard]
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query private var rules: [MerchantRule]

    /// Quando a importação é aberta a partir de uma conta ou cartão, o destino
    /// já vem escolhido.
    var preselected: ImportDestination?

    private enum Step { case destination, file, mapping, review, done }

    @State private var step: Step = .destination
    @State private var destinationID: UUID?
    @State private var showingFilePicker = false

    @State private var fileData: Data?
    @State private var fileName = ""
    @State private var table: CSVTable?
    @State private var mapping = CSVMapping()
    @State private var presetID = "generico"

    @State private var statement: StatementFile?
    @State private var items: [ImportPreviewItem] = []
    @State private var errorMessage: String?
    @State private var result: ImportBatch?

    private var destination: ImportDestination? {
        if let preselected { return preselected }
        if let account = accounts.first(where: { $0.id == destinationID }) { return .account(account) }
        if let card = cards.first(where: { $0.id == destinationID }) { return .card(card) }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .destination: destinationStep
                case .file: fileStep
                case .mapping: mappingStep
                case .review: reviewStep
                case .done: doneStep
                }
            }
            .navigationTitle("Importar extrato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .done ? "Fechar" : "Cancelar") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.data, .plainText, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { outcome in
                handleFileSelection(outcome)
            }
            .alert("Não deu para importar", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Entendi", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if preselected != nil { step = .file }
            }
        }
    }

    // MARK: - 1. Destino

    private var destinationStep: some View {
        List {
            Section {
                InlineNote(
                    symbol: "lock.shield",
                    text: "O arquivo é lido dentro do aparelho. Nenhuma senha de banco é pedida e nada é enviado para a internet."
                )
            }

            if accounts.isEmpty && cards.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "building.columns",
                        title: "Cadastre uma conta antes",
                        message: "O extrato precisa de um destino. Crie a conta ou o cartão e volte aqui."
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if !accounts.isEmpty {
                Section("Contas") {
                    ForEach(accounts) { account in
                        selectionRow(
                            symbol: account.type.symbol,
                            hex: account.colorHex,
                            title: account.name,
                            subtitle: account.type.label,
                            isSelected: destinationID == account.id
                        ) { destinationID = account.id }
                    }
                }
            }

            if !cards.isEmpty {
                Section("Cartões") {
                    ForEach(cards) { card in
                        selectionRow(
                            symbol: "creditcard",
                            hex: card.colorHex,
                            title: card.name,
                            subtitle: "fecha dia \(card.closingDay)",
                            isSelected: destinationID == card.id
                        ) { destinationID = card.id }
                    }
                }
            }

            Section {
                Button {
                    step = .file
                } label: {
                    Text("Continuar").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(destination == nil)
                .listRowBackground(Color.clear)
            }
        }
    }

    private func selectionRow(
        symbol: String,
        hex: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, hex: hex, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Arquivo

    private var fileStep: some View {
        List {
            Section {
                if let destination {
                    HStack(spacing: 12) {
                        IconBadge(symbol: destination.isCard ? "creditcard" : "building.columns", hex: "#2F6FED", size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Importando para").font(.caption).foregroundStyle(.secondary)
                            Text(destination.name).font(.headline)
                        }
                        Spacer()
                        if preselected == nil {
                            Button("Trocar") { step = .destination }
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Escolher arquivo", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
            }

            Section("Como conseguir o arquivo") {
                instruction(1, "Abra o app ou o site do seu banco.")
                instruction(2, "Procure «Extrato» ou «Fatura» e a opção de exportar.")
                instruction(3, "Escolha o formato OFX se existir — ele é o mais completo. Senão, CSV.")
                instruction(4, "Salve em Arquivos e escolha aqui.")
            }

            Section {
                InlineNote(symbol: "doc.text", text: "Formatos aceitos: OFX, QFX, CSV, TSV e TXT.")
                InlineNote(symbol: "arrow.triangle.2.circlepath", text: "Pode importar o mesmo período de novo: o que já existe é reconhecido e não duplica.")
            }
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                .foregroundStyle(Color.accentColor)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 3. Colunas do CSV

    @ViewBuilder
    private var mappingStep: some View {
        if let table {
            List {
                Section {
                    Picker("Modelo do banco", selection: $presetID) {
                        ForEach(CSVPreset.all) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .onChange(of: presetID) { _, newValue in
                        if let preset = CSVPreset.all.first(where: { $0.id == newValue }), preset.id != "generico" {
                            mapping = preset.mapping
                        }
                    }
                } footer: {
                    Text(CSVPreset.all.first { $0.id == presetID }?.detail ?? "")
                }

                Section("Colunas") {
                    columnPicker("Data", selection: Binding(
                        get: { mapping.dateColumn },
                        set: { mapping.dateColumn = $0 }
                    ), table: table)

                    columnPicker("Descrição", selection: Binding(
                        get: { mapping.descriptionColumn },
                        set: { mapping.descriptionColumn = $0 }
                    ), table: table)

                    columnPicker("Valor", selection: Binding(
                        get: { mapping.amountColumn ?? 0 },
                        set: { mapping.amountColumn = $0 }
                    ), table: table)
                }

                Section {
                    Toggle("Inverter o sinal dos valores", isOn: $mapping.invertSign)
                } footer: {
                    Text("Ligue quando a planilha lista compras como valores positivos — é o caso da maioria das faturas de cartão.")
                }

                Section("Prévia das colunas") {
                    ForEach(0..<table.columnCount, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(table.columnLabel(index))
                                .font(.caption.weight(.semibold))
                            Text(table.samples(index).joined(separator: "  •  "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Section {
                    Button {
                        buildPreview()
                    } label: {
                        Text("Ver os lançamentos").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
            }
        } else {
            ProgressView()
        }
    }

    private func columnPicker(_ title: String, selection: Binding<Int>, table: CSVTable) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<table.columnCount, id: \.self) { index in
                Text(table.columnLabel(index)).tag(index)
            }
        }
    }

    // MARK: - 4. Revisão

    @ViewBuilder
    private var reviewStep: some View {
        if let statement {
            let selected = items.filter(\.include)
            let duplicates = items.filter(\.isDuplicate)

            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            StatTile(title: "Encontrados", value: "\(items.count)")
                            StatTile(title: "Novos", value: "\(selected.count)", tint: Palette.positive)
                            StatTile(title: "Já existiam", value: "\(duplicates.count)", tint: .secondary)
                        }
                        Divider()
                        HStack(alignment: .top) {
                            StatTile(title: "Entradas", value: Money.string(statement.totalIn), tint: Palette.positive)
                            StatTile(title: "Saídas", value: Money.string(statement.totalOut))
                        }
                        if let start = statement.periodStart, let end = statement.periodEnd {
                            InlineNote(
                                symbol: "calendar",
                                text: "Período de \(DateFormatters.short.string(from: start)) a \(DateFormatters.short.string(from: end))."
                            )
                        }
                        ForEach(statement.warnings, id: \.self) { warning in
                            InlineNote(symbol: "exclamationmark.triangle", text: warning, tint: Palette.warning)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let reported = statement.reportedBalance {
                    Section {
                        LabeledContent("Saldo informado no arquivo", value: Money.string(reported))
                        if case .account(let account) = destination {
                            let calculated = FinanceEngine.balance(of: account)
                            LabeledContent("Saldo calculado aqui", value: Money.string(calculated))
                        }
                    } footer: {
                        Text("Depois de importar, confira se os dois batem. Se não baterem, falta algum período de extrato.")
                    }
                }

                if !duplicates.isEmpty {
                    Section {
                        Button("Marcar todos os repetidos como novos") {
                            for index in items.indices where items[index].isDuplicate {
                                items[index].include = true
                            }
                        }
                        .font(.subheadline)
                    } footer: {
                        Text("\(duplicates.count) lançamento(s) já existem e ficam desmarcados. Só marque se tiver certeza de que são compras diferentes com o mesmo valor no mesmo dia.")
                    }
                }

                Section("Lançamentos") {
                    ForEach($items) { $item in
                        previewRow($item)
                    }
                }

                Section {
                    Button {
                        commit()
                    } label: {
                        Text("Importar \(selected.count) lançamento\(selected.count == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
                    .listRowBackground(Color.clear)
                }
            }
        } else {
            ProgressView()
        }
    }

    private func previewRow(_ item: Binding<ImportPreviewItem>) -> some View {
        HStack(spacing: 12) {
            Button {
                item.wrappedValue.include.toggle()
            } label: {
                Image(systemName: item.wrappedValue.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.wrappedValue.include ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.wrappedValue.suggestion.displayName)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(DateFormatters.short.string(from: item.wrappedValue.row.date))
                    if let category = item.wrappedValue.suggestion.category {
                        Text("•")
                        Text(category.name)
                    }
                    if item.wrappedValue.suggestion.fromLearnedRule {
                        Image(systemName: "brain")
                    }
                    if item.wrappedValue.isDuplicate {
                        Text("• já existe")
                            .foregroundStyle(Palette.warning)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(Money.signed(item.wrappedValue.row.amount))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.amount(item.wrappedValue.row.amount))
        }
        .opacity(item.wrappedValue.include ? 1 : 0.45)
        .padding(.vertical, 2)
    }

    // MARK: - 5. Concluído

    @ViewBuilder
    private var doneStep: some View {
        if let result {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.positive)

                Text("\(result.inserted) lançamento\(result.inserted == 1 ? "" : "s") importado\(result.inserted == 1 ? "" : "s")")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                if result.duplicatesSkipped > 0 {
                    Text("\(result.duplicatesSkipped) já estavam aqui e foram ignorados.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Para \(result.destinationName), a partir de \(fileName).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Pronto").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        undo(result)
                    } label: {
                        Text("Desfazer esta importação").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding()
        }
    }

    // MARK: - Ações

    private func handleFileSelection(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case .failure(let error):
            errorMessage = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }

            // Arquivo vindo de fora do app precisa de permissão explícita.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                fileData = data
                fileName = url.lastPathComponent

                let ext = url.pathExtension.lowercased()
                if ext == "ofx" || ext == "qfx" {
                    statement = try OFXParser.parse(data: data, fileName: fileName)
                    buildPreview()
                } else {
                    let parsed = try CSVReader.read(data: data)
                    let suggestion = CSVImporter.suggestMapping(for: parsed)
                    table = parsed
                    mapping = suggestion.mapping
                    presetID = suggestion.preset.id
                    step = .mapping
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func buildPreview() {
        guard let destination else { return }

        do {
            let file: StatementFile
            if let statement, statement.source == .ofx {
                file = statement
            } else if let table {
                file = try CSVImporter.rows(from: table, mapping: mapping, fileName: fileName)
            } else if let fileData {
                file = try ImportService.read(data: fileData, fileName: fileName, mapping: mapping)
            } else {
                throw ImportError.unreadableFile
            }

            statement = file
            items = ImportService(context: context).preview(
                file: file,
                destination: destination,
                categories: categories,
                rules: rules
            )
            step = .review
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func commit() {
        guard let destination, let statement else { return }
        do {
            result = try ImportService(context: context).commit(
                items: items,
                file: statement,
                destination: destination
            )
            step = .done
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ batch: ImportBatch) {
        try? ImportService(context: context).undo(batch: batch)
        dismiss()
    }
}
