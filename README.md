# ORION ServiceLog AI — Flutter MVP 0.3.1

Aplicativo responsivo para registrar clientes, locais, fabricantes, modelos, equipamentos, atendimentos técnicos e soluções, com recuperação de casos semelhantes.

## Modos de execução

- **Demonstração local:** nenhuma configuração; cadastros e atendimentos são mantidos localmente no dispositivo para permitir testes entre reinicializações.
- **Supabase:** ativado quando `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` são fornecidos por `--dart-define`.

Consulte [FLUTTER_SETUP.md](FLUTTER_SETUP.md) para preparar e executar o projeto.

## Cadastros dinâmicos

Não é necessário recompilar o aplicativo para adicionar dados operacionais. Em tempo de execução, o usuário pode cadastrar:

- cliente usando apenas o nome;
- CNPJ, contato, telefone, e-mail e endereço como dados opcionais;
- vários locais para o mesmo cliente;
- fabricante e modelo usando apenas fabricante e modelo;
- família/linha e modalidade como informações opcionais;
- equipamento físico e número de série;
- atendimento e solução.

A navegação possui uma área exclusiva de **Clientes**. No formulário de equipamento permanecem os atalhos para criar rapidamente um modelo ou cliente/local que ainda não esteja listado.

## Fundação para ordens de serviço

A área de clientes organiza os dados que futuramente alimentarão modelos de ordem de serviço. A migration `0005_customers_and_service_orders.sql` acrescenta campos opcionais ao cliente e cria a estrutura inicial de modelos de OS por cliente.

O fluxo planejado é:

1. salvar um arquivo-modelo de OS para o cliente;
2. mapear campos do modelo;
3. finalizar um atendimento;
4. escolher **Preencher ordem de serviço**;
5. gerar uma cópia com cliente, equipamento, falha, diagnóstico, solução, tempos e validação.

A geração do documento ainda não está habilitada nesta versão; a estrutura de dados foi preparada para a próxima etapa.

## Organização do código

```text
lib/
├── core/               # configuração e tema ORION
├── data/
│   ├── models/         # modelos da aplicação
│   └── repositories/   # repositório local e Supabase
├── features/
│   ├── auth/
│   ├── dashboard/
│   ├── customers/
│   ├── equipment/
│   ├── cases/
│   ├── assistant/
│   └── shell/
└── shared/widgets/
```

A interface usa uma camada de repositório para que o modo local e o backend real mantenham os mesmos fluxos de tela.

## Supabase

Antes de usar a versão conectada, aplique, em ordem, as migrations:

```text
supabase/migrations/0004_dynamic_master_data.sql
supabase/migrations/0005_customers_and_service_orders.sql
```

A `0004` permite fabricantes e modelos próprios por organização. A `0005` acrescenta os campos opcionais do cliente e a fundação segura para modelos de ordem de serviço.

## Versão 0.3.2 — seleção inteligente de modelos

O cadastro de equipamentos agora usa pesquisa incremental em vez de uma lista suspensa fixa. Ao digitar fabricante, família, modelo ou modalidade, o sistema apresenta as correspondências existentes. Quando não existe correspondência exata, a própria lista oferece o cadastro rápido do novo modelo, preservando o restante do formulário.

## Atualização 0.3.3

- autocomplete de cliente e local diretamente no cadastro do equipamento;
- criação rápida de cliente/local sem abandonar o formulário;
- classificação do atendimento em manutenção, instalação ou desinstalação;
- textos e campos adaptados automaticamente ao tipo de atividade;
- diário cumulativo de andamento, com vários registros no mesmo atendimento;
- filtro por atividade na listagem de atendimentos;
- migration `0006_service_activities_and_progress.sql` para Supabase.
