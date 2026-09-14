import SwiftUI
import SwiftData

/// Categorias e as palavras-chave que alimentam a classificação automática.
struct CategoriesView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \MerchantRule.hits, order: .reverse) private var rules: [MerchantRule]

    @State private var creating = false
    @State private var editing: Category?

    var body: some View {
        List {
            ForEach(CategoryGroup.allCases) { group in
                let items = categories.filter { $0.group == group }
                if !items.isEmpty {
                    Section(group.label) {
                        ForEach(items) { category in
                            Button { editing = category } label: {
                                HStack(spacing: 12) {
                                    IconBadge(symbol: category.symbol, hex: category.colorHex, size: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(category.name)
                                        if !category.keywords.isEmpty {
                                            Text(category.keywords.prefix(4).joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text("\((category.transactions ?? []).count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                if !category.isSystem {
                                    Button(role: .destructive) {
                                        context.delete(category)
                                        try? context.save()
                                    } label: {
                                        Label("Apagar", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !rules.isEmpty {
                Section {
                    ForEach(rules.prefix(20)) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.displayName ?? rule.pattern)
                                    .font(.subheadline)
                                Text(rule.pattern)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let category = rule.category {
                                Label(category.name, systemImage: category.symbol)
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: category.colorHex))
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let list = Array(rules.prefix(20))
                        for index in offsets { context.delete(list[index]) }
                        try? context.save()
                    }
                } header: {
                    Text("Regras aprendidas")
                } footer: {
                    Text("Criadas quando você corrige a categoria de um lançamento. Apague uma regra se ela estiver classificando algo errado.")
                }
            }
        }
        .navigationTitle("Categorias")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nova categoria")
            }
        }
        .sheet(isPresented: $creating) { NavigationStack { CategoryEditor(category: nil) } }
        .sheet(item: $editing) { category in NavigationStack { CategoryEditor(category: category) } }
    }
}

/// Cadastro e edição de categoria.
struct CategoryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let category: Category?

    @State private var name = ""
    @State private var group: CategoryGroup = .estiloDeVida
    @State private var symbol = "tag"
    @State private var colorHex = Palette.picks[0]
    @State private var keywordsText = ""

    private var isNew: Bool { category == nil }

    private let symbols = [
        "tag", "house", "cart", "fork.knife", "car", "bolt", "wifi", "cross.case",
        "book", "bag", "repeat", "ticket", "scissors", "airplane", "gift", "percent",
        "chart.line.uptrend.xyaxis", "shield.lefthalf.filled", "banknote", "plus.circle",
        "pawprint", "figure.run", "gamecontroller", "cup.and.saucer", "wrench.and.screwdriver"
    ]

    var body: some View {
        Form {
            Section {
                TextField("Nome", text: $name)
                    .textInputAutocapitalization(.words)

                Picker("Grupo", selection: $group) {
                    ForEach(CategoryGroup.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } footer: {
                Text("O grupo define em qual fatia da sua renda esta categoria entra no plano de alocação.")
            }

            Section("Ícone") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 10)], spacing: 10) {
                    ForEach(symbols, id: \.self) { option in
                        Image(systemName: option)
                            .font(.system(size: 18))
                            .frame(width: 42, height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(symbol == option ? Color(hex: colorHex).opacity(0.25) : Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(symbol == option ? Color(hex: colorHex) : .primary)
                            .onTapGesture { symbol = option }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Cor") {
                ColorPickerGrid(hex: $colorHex)
            }

            Section {
                TextField("mercado, supermercado, atacadão", text: $keywordsText, axis: .vertical)
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Palavras-chave")
            } footer: {
                Text("Separadas por vírgula. Quando uma delas aparecer na descrição do extrato, o lançamento cai nesta categoria. Acentos e maiúsculas não importam.")
            }

            if let category, !isNew, !category.isSystem {
                Section {
                    Button(role: .destructive) {
                        context.delete(category)
                        try? context.save()
                        dismiss()
                    } label: {
                        Label("Apagar categoria", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Nova categoria" : "Editar categoria")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let category else { return }
        name = category.name
        group = category.group
        symbol = category.symbol
        colorHex = category.colorHex
        keywordsText = category.keywords.joined(separator: ", ")
    }

    private func save() {
        let target = category ?? Category(name: name)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.group = group
        target.symbol = symbol
        target.colorHex = colorHex
        target.keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if category == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
