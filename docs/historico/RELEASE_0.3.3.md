# ORION ServiceLog AI 0.3.3

## Fluxo de equipamentos

O campo **Cliente / local de instalação** agora funciona por autocomplete. A pesquisa considera cliente, unidade, sala, bunker, cidade e UF. Quando não existe correspondência, o usuário pode cadastrar o cliente e o local sem sair do formulário do equipamento.

## Tipos de atendimento

Cada atendimento passa a ser classificado como:

- manutenção;
- instalação;
- desinstalação.

Os títulos, orientações e campos do formulário mudam conforme a atividade. Os dados continuam armazenados em uma estrutura comum para permitir pesquisa, relatórios e futura geração de ordens de serviço.

## Diário de andamento

Um atendimento pode permanecer aberto por vários dias. Cada acesso permite acrescentar novos registros ao diário, mantendo o mesmo número de atendimento e o histórico cronológico completo.

## Supabase

Antes de utilizar esta versão com o backend, aplicar:

```bash
npx supabase db push
```

A migration `0006_service_activities_and_progress.sql` cria a classificação de atividade, a tabela do diário, as políticas RLS e atualiza a busca híbrida.
