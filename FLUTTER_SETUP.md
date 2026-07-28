# ORION ServiceLog AI — execução Flutter

Esta pasta contém o código-fonte do MVP Flutter. Como o pacote foi produzido em um ambiente sem Flutter SDK, os diretórios nativos (`android`, `ios`, `web`, `windows`, `macos` e `linux`) são gerados localmente pelo script de bootstrap.

## 1. Pré-requisitos

- Flutter estável instalado e disponível no `PATH`;
- Android Studio ou Visual Studio Code com extensões Flutter/Dart;
- para Windows desktop: Visual Studio com **Desktop development with C++**;
- para iOS/macOS: macOS com Xcode.

Confirme o ambiente:

```bash
flutter doctor
```

## 2. Gerar as plataformas e validar

### Windows PowerShell

```powershell
cd flutter_app
.\scripts\bootstrap.ps1
```

### macOS ou Linux

```bash
cd flutter_app
./scripts/bootstrap.sh
```

O script:

1. preserva o código ORION;
2. executa `flutter create` para gerar as plataformas;
3. instala dependências;
4. formata o Dart;
5. executa `flutter analyze`;
6. executa os testes.

## 3. Rodar em modo demonstração

Sem qualquer credencial, o aplicativo inicia com dados locais:

```bash
flutter run -d chrome
```

Outros exemplos:

```bash
flutter run -d windows
flutter run -d android
```

## 4. Rodar conectado ao Supabase

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICAVEL
```

Também é possível copiar `.env.example` para `.env` e executar:

```bash
flutter run -d chrome --dart-define-from-file=.env
```

Nunca inclua `SUPABASE_SERVICE_ROLE_KEY` ou `OPENAI_API_KEY` no aplicativo Flutter. Esses segredos pertencem exclusivamente às Edge Functions.

## 5. Fluxos implementados

- login e criação de conta;
- bootstrap da primeira organização;
- navegação responsiva para celular, web e desktop;
- dashboard operacional;
- cadastro dinâmico de fabricante/modelo;
- cadastro de cliente e múltiplos locais;
- cadastro de equipamento;
- abertura, diagnóstico e conclusão do atendimento;
- pesquisa de casos semelhantes;
- modo demonstração local;
- conexão real com as tabelas e Edge Functions Supabase.

## 6. Limites desta entrega

Ainda não foram implementados:

- sincronização offline completa em SQLite (o modo demo já persiste localmente);
- anexos e fotografias;
- etapas cronológicas individuais de diagnóstico;
- gestão de usuários e revisão por engenheiro;
- notificações;
- relatórios PDF;
- distribuição nas lojas.

Esses itens entram depois da validação do fluxo principal em campo.


## 7. Migrations para cadastros dinâmicos e clientes

No ambiente Supabase, aplique a migration incluída no pacote completo:

```bash
npx supabase db push
```

Ou execute, em ordem, os arquivos `supabase/migrations/0004_dynamic_master_data.sql` e `supabase/migrations/0005_customers_and_service_orders.sql` no SQL Editor. A primeira permite fabricantes e modelos próprios por organização. A segunda adiciona os campos opcionais de cliente e a fundação para modelos de ordem de serviço.
