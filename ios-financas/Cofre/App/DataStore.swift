import Foundation
import SwiftData

/// Dono do banco local e do conteúdo inicial.
///
/// O armazenamento é um arquivo SQLite dentro do contêiner do app, protegido
/// pela criptografia do iOS. Não há servidor: se o aparelho não for
/// desbloqueado, ninguém lê nada.
enum DataStore {

    static let schema = Schema([
        Institution.self,
        Account.self,
        CreditCard.self,
        Category.self,
        Txn.self,
        MerchantRule.self,
        ImportBatch.self,
        EnvelopeAllocation.self,
        EnvelopeAdjustment.self,
        Goal.self,
        GoalContribution.self,
        AllocationPlan.self,
        AllocationBucket.self,
        RecurringBill.self
    ])

    /// Contêiner de produção. `cloudKitDatabase: .none` é deliberado: por padrão
    /// os dados ficam só neste aparelho.
    static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Se o arquivo estiver corrompido, é melhor abrir em memória do que
            // travar na inicialização — o usuário consegue reimportar.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [fallback]) else {
                fatalError("Não foi possível iniciar o armazenamento local: \(error)")
            }
            return container
        }
    }

    /// Contêiner temporário usado pelos previews do Xcode.
    static func makePreviewContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        SeedData.installIfNeeded(in: ModelContext(container))
        SeedData.installSampleLedger(in: ModelContext(container))
        return container
    }
}

/// Categorias, plano de alocação e demais dados que o app já traz prontos.
enum SeedData {

    /// Roda uma vez, na primeira abertura. Sem isso não haveria categorias para
    /// a importação classificar.
    static func installIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard existing == 0 else { return }

        for category in defaultCategories() {
            context.insert(category)
        }
        context.insert(defaultAllocationPlan())
        try? context.save()
    }

    // MARK: - Categorias

    static func defaultCategories() -> [Category] {
        var index = 0
        func next() -> Int { index += 1; return index }

        return [
            // Essencial
            Category(name: "Moradia", symbol: "house", colorHex: "#2F6FED", group: .essencial,
                     keywords: ["aluguel", "condominio", "iptu", "imobiliaria"], isSystem: true, sortIndex: next()),
            Category(name: "Mercado", symbol: "cart", colorHex: "#1D9A6C", group: .essencial,
                     keywords: ["supermercado", "mercado", "atacadao", "assai", "carrefour", "pao de acucar", "extra", "hortifruti", "sacolao"], isSystem: true, sortIndex: next()),
            Category(name: "Contas de casa", symbol: "bolt", colorHex: "#36618E", group: .essencial,
                     keywords: ["energia", "eletrica", "enel", "cemig", "light", "copel", "sabesp", "agua", "gas", "comgas"], isSystem: true, sortIndex: next()),
            Category(name: "Internet e telefone", symbol: "wifi", colorHex: "#5E5CE6", group: .essencial,
                     keywords: ["vivo", "claro", "tim", "oi ", "net ", "internet", "telefonia"], isSystem: true, sortIndex: next()),
            Category(name: "Transporte", symbol: "car", colorHex: "#F2994A", group: .essencial,
                     keywords: ["uber", "99", "posto", "combustivel", "gasolina", "ipiranga", "shell", "petrobras", "estacionamento", "pedagio", "metro", "bilhete unico"], isSystem: true, sortIndex: next()),
            Category(name: "Saúde", symbol: "cross.case", colorHex: "#E5484D", group: .essencial,
                     keywords: ["farmacia", "drogaria", "droga raia", "drogasil", "pacheco", "hospital", "clinica", "laboratorio", "unimed", "amil", "bradesco saude", "dentista"], isSystem: true, sortIndex: next()),
            Category(name: "Educação", symbol: "book", colorHex: "#00A6A6", group: .essencial,
                     keywords: ["escola", "faculdade", "universidade", "curso", "mensalidade", "udemy", "alura"], isSystem: true, sortIndex: next()),
            Category(name: "Seguros", symbol: "shield", colorHex: "#5B6472", group: .essencial,
                     keywords: ["seguro", "porto seguro", "azul seguros", "previdencia"], isSystem: true, sortIndex: next()),

            // Estilo de vida
            Category(name: "Restaurantes", symbol: "fork.knife", colorHex: "#F2994A", group: .estiloDeVida,
                     keywords: ["ifood", "restaurante", "lanchonete", "padaria", "pizzaria", "hamburgue", "bar ", "cafe", "starbucks", "mcdonalds", "burger king", "subway", "rappi"], isSystem: true, sortIndex: next(), rollover: .surplusOnly),
            Category(name: "Compras", symbol: "bag", colorHex: "#C0399F", group: .estiloDeVida,
                     keywords: ["amazon", "mercado livre", "mercadolivre", "shopee", "magalu", "magazine luiza", "americanas", "renner", "riachuelo", "zara", "centauro", "shopping"], isSystem: true, sortIndex: next()),
            Category(name: "Assinaturas", symbol: "repeat", colorHex: "#8E44AD", group: .estiloDeVida,
                     keywords: ["netflix", "spotify", "disney", "hbo", "max ", "prime video", "youtube premium", "apple com bill", "icloud", "globoplay", "deezer"], isSystem: true, sortIndex: next()),
            Category(name: "Lazer", symbol: "ticket", colorHex: "#E8B931", group: .estiloDeVida,
                     keywords: ["cinema", "ingresso", "teatro", "show", "parque", "steam", "playstation", "xbox", "nintendo"], isSystem: true, sortIndex: next(), rollover: .surplusOnly),
            Category(name: "Cuidados pessoais", symbol: "scissors", colorHex: "#C0399F", group: .estiloDeVida,
                     keywords: ["barbearia", "salao", "cabelereiro", "manicure", "estetica", "academia", "smartfit", "gympass"], isSystem: true, sortIndex: next()),
            Category(name: "Viagem", symbol: "airplane", colorHex: "#00A6A6", group: .estiloDeVida,
                     keywords: ["latam", "gol ", "azul linhas", "airbnb", "booking", "hotel", "passagem", "decolar"], isSystem: true, sortIndex: next()),
            Category(name: "Presentes e doações", symbol: "gift", colorHex: "#E5484D", group: .estiloDeVida,
                     keywords: ["doacao", "presente", "vakinha"], isSystem: true, sortIndex: next()),
            Category(name: "Taxas e juros", symbol: "percent", colorHex: "#5B6472", group: .estiloDeVida,
                     keywords: ["tarifa", "juros", "anuidade", "iof", "multa", "encargos"], isSystem: true, sortIndex: next()),
            Category(name: "Outros", symbol: "ellipsis.circle", colorHex: "#8E8E93", group: .estiloDeVida,
                     keywords: [], isSystem: true, sortIndex: next(), rollover: .reset),

            // Investir e guardar
            Category(name: "Investimentos", symbol: "chart.line.uptrend.xyaxis", colorHex: "#1D9A6C", group: .investimento,
                     keywords: ["aplicacao", "cdb", "tesouro", "fundo", "lci", "lca", "corretora", "xp investimentos", "rico", "clear", "nuinvest"], isSystem: true, sortIndex: next()),
            Category(name: "Reserva", symbol: "shield.lefthalf.filled", colorHex: "#1D9A6C", group: .investimento,
                     keywords: ["poupanca", "reserva"], isSystem: true, sortIndex: next()),

            // Receita
            Category(name: "Salário", symbol: "banknote", colorHex: "#1D9A6C", group: .receita,
                     keywords: ["salario", "provento", "remuneracao", "folha", "pagamento empresa"], isSystem: true, sortIndex: next()),
            Category(name: "Renda extra", symbol: "plus.circle", colorHex: "#00A6A6", group: .receita,
                     keywords: ["freelance", "servico prestado", "comissao", "bonus"], isSystem: true, sortIndex: next()),
            Category(name: "Rendimentos", symbol: "arrow.up.forward", colorHex: "#1D9A6C", group: .receita,
                     keywords: ["rendimento", "dividendo", "juros recebidos", "resgate"], isSystem: true, sortIndex: next()),

            // Neutro
            Category(name: "Transferências", symbol: "arrow.left.arrow.right", colorHex: "#8E8E93", group: .neutro,
                     keywords: ["transferencia entre contas", "aplicacao automatica"], isSystem: true, sortIndex: next()),
            Category(name: "Pagamento de fatura", symbol: "creditcard", colorHex: "#8E8E93", group: .neutro,
                     keywords: ["pagamento de fatura", "pagto fatura"], isSystem: true, sortIndex: next())
        ]
    }

    // MARK: - Plano de alocação

    /// 50/30/20: metade para o essencial, 30% para o que você escolhe gastar,
    /// 20% para guardar e investir. É um ponto de partida conhecido, não um
    /// dogma — as fatias são editáveis na tela de planejamento.
    static func defaultAllocationPlan() -> AllocationPlan {
        let plan = AllocationPlan(name: "50 / 30 / 20")
        plan.buckets = [
            AllocationBucket(name: "Essencial", percentage: 50, group: .essencial,
                             symbol: "house", colorHex: CategoryGroup.essencial.hex, sortIndex: 0),
            AllocationBucket(name: "Estilo de vida", percentage: 30, group: .estiloDeVida,
                             symbol: "sparkles", colorHex: CategoryGroup.estiloDeVida.hex, sortIndex: 1),
            AllocationBucket(name: "Investir e guardar", percentage: 20, group: .investimento,
                             symbol: "chart.pie", colorHex: CategoryGroup.investimento.hex, sortIndex: 2)
        ]
        return plan
    }

    // MARK: - Dados de demonstração

    /// Conta, cartão e alguns meses de lançamentos para você ver as telas cheias
    /// antes de importar o primeiro extrato. Fica atrás de um botão em Ajustes.
    static func installSampleLedger(in context: ModelContext) {
        let bank = Institution(name: "Banco Exemplo", colorHex: "#5E5CE6")
        context.insert(bank)

        let checking = Account(name: "Conta corrente", type: .corrente, openingBalance: 2_400,
                               openingDate: Date().adding(months: -6).startOfDay,
                               colorHex: "#2F6FED", institution: bank)
        let savings = Account(name: "Reserva", type: .poupanca, openingBalance: 8_000,
                              openingDate: Date().adding(months: -6).startOfDay,
                              colorHex: "#1D9A6C", institution: bank)
        context.insert(checking)
        context.insert(savings)

        let card = CreditCard(name: "Cartão principal", brand: .mastercard, lastFourDigits: "4417",
                              creditLimit: 9_000, closingDay: 25, dueDay: 5,
                              colorHex: "#5E5CE6", institution: bank, paymentAccount: checking)
        context.insert(card)

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        func category(_ name: String) -> Category? { categories.first { $0.name == name } }

        let samples: [(String, Decimal, String, TxKind, Bool)] = [
            ("Salário", 7_800, "Salário", .income, false),
            ("Aluguel", -1_850, "Moradia", .expense, false),
            ("Supermercado Bom Preço", -742.30, "Mercado", .expense, true),
            ("Enel distribuição", -168.44, "Contas de casa", .expense, false),
            ("Vivo fibra", -119.90, "Internet e telefone", .expense, false),
            ("Posto Ipiranga", -240, "Transporte", .expense, true),
            ("iFood", -86.70, "Restaurantes", .expense, true),
            ("Netflix", -44.90, "Assinaturas", .expense, true),
            ("Spotify", -21.90, "Assinaturas", .expense, true),
            ("Drogasil", -97.15, "Saúde", .expense, true),
            ("Amazon", -213.80, "Compras", .expense, true),
            ("Academia SmartFit", -109.90, "Cuidados pessoais", .expense, true),
            ("Aplicação CDB", -900, "Investimentos", .investment, false)
        ]

        for offset in 0..<5 {
            let month = MonthKey.current.adding(months: -offset)
            for (index, sample) in samples.enumerated() {
                let day = min(2 + index * 2, month.numberOfDays)
                let date = InvoiceCalculator.date(year: month.year, month: month.month, day: day)
                guard date <= Date() else { continue }

                // Um pouco de variação para os gráficos não ficarem chapados.
                let jitter = Decimal((index * 7 + offset * 13) % 11) - 5
                let amount = sample.1 == 7_800 ? sample.1 : Money.rounded(sample.1 + jitter)

                let txn = Txn(
                    date: date,
                    displayName: sample.0,
                    amount: amount,
                    kind: sample.3,
                    source: .manual,
                    rawDescription: sample.0.uppercased()
                )
                txn.category = category(sample.2)
                if sample.4 {
                    txn.card = card
                    txn.invoiceKey = InvoiceCalculator.cycle(for: card, containing: date).monthKey.key
                } else {
                    txn.account = checking
                }
                txn.fingerprint = ImportService.fingerprint(
                    destination: sample.4 ? card.id.uuidString : checking.id.uuidString,
                    date: date, amount: amount, description: sample.0
                )
                context.insert(txn)
            }
        }

        let goal = Goal(name: "Reserva de emergência", kind: .reserva, targetAmount: 30_000,
                        targetDate: Date().adding(months: 14), colorHex: "#1D9A6C",
                        linkedAccount: savings)
        context.insert(goal)
        let contribution = GoalContribution(date: Date().adding(months: -1), amount: 8_000, note: "Saldo inicial")
        contribution.goal = goal
        context.insert(contribution)

        let trip = Goal(name: "Viagem em julho", kind: .viagem, targetAmount: 9_000,
                        targetDate: Date().adding(months: 9), colorHex: "#00A6A6")
        context.insert(trip)

        for (name, amount) in [("Mercado", Decimal(900)), ("Restaurantes", 450), ("Compras", 400), ("Transporte", 500)] {
            guard let cat = category(name) else { continue }
            context.insert(EnvelopeAllocation(category: cat, amount: amount))
        }

        context.insert(RecurringBill(name: "Aluguel", expectedAmount: 1_850, dueDay: 5,
                                     category: category("Moradia"), account: checking))
        context.insert(RecurringBill(name: "Vivo fibra", expectedAmount: 119.90, dueDay: 12,
                                     category: category("Internet e telefone"), account: checking))
        context.insert(RecurringBill(name: "Enel", expectedAmount: 170, dueDay: 18, isVariableAmount: true,
                                     category: category("Contas de casa"), account: checking))

        try? context.save()
    }

    /// Apaga tudo, inclusive as categorias, e reinstala o conteúdo inicial.
    static func eraseEverything(in context: ModelContext) {
        try? context.delete(model: Txn.self)
        try? context.delete(model: GoalContribution.self)
        try? context.delete(model: Goal.self)
        try? context.delete(model: EnvelopeAllocation.self)
        try? context.delete(model: EnvelopeAdjustment.self)
        try? context.delete(model: RecurringBill.self)
        try? context.delete(model: MerchantRule.self)
        try? context.delete(model: ImportBatch.self)
        try? context.delete(model: CreditCard.self)
        try? context.delete(model: Account.self)
        try? context.delete(model: Institution.self)
        try? context.delete(model: AllocationBucket.self)
        try? context.delete(model: AllocationPlan.self)
        try? context.delete(model: Category.self)
        try? context.save()
        installIfNeeded(in: context)
    }
}
