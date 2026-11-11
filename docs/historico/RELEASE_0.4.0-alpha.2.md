# Release 0.4.0-alpha.2+13 — replay offline

## Objetivo

Transformar a fila criada no alpha.1 em um fluxo local-first funcional com envio idempotente, reconciliação remota e detecção de conflitos.

## Entregas

- `OfflineFirstServiceLogRepository`;
- `SupabaseSyncGateway`;
- gravação imediata no SQLite;
- UUID para entidades criadas offline;
- compactação de operações da mesma entidade;
- replay automático após gravações e na inicialização;
- retry progressivo e ao retomar o aplicativo;
- sincronização manual;
- cache do perfil e organização;
- RPC idempotente `apply_offline_operation`;
- `sync_operation_receipts`;
- `sync_conflicts`;
- revisão otimista;
- snapshot remoto depois do push;
- testes com gateway remoto simulado.

## Migration

Aplicar, em ordem, até:

```text
0008_offline_operation_replay.sql
```

## Homologação mínima

1. validar `flutter analyze` e `flutter test`;
2. aplicar migrations em projeto Supabase de homologação;
3. entrar online ao menos uma vez;
4. desconectar a rede;
5. cadastrar cliente, local, equipamento e atendimento;
6. fechar e reabrir o aplicativo;
7. restabelecer a conexão;
8. acionar `Sincronizar agora`;
9. confirmar filas zeradas e registros no Supabase;
10. repetir o mesmo replay para confirmar ausência de duplicatas.

## Limites

O pull ainda é integral e conflitos não têm resolução visual. Consulte `10_OFFLINE_SYNC.md` e `20_KNOWN_LIMITATIONS.md`.
