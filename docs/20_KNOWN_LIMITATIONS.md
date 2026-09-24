# Limitações conhecidas — 0.4.0-alpha.2

1. O pull remoto substitui o snapshot local completo; ainda não usa paginação ou cursor incremental.
2. Conflitos são detectados e preservados, mas ainda não existe tela para comparar e resolver versões.
3. A exclusão é lógica (arquivamento), com tela de restauração. Não há
   exclusão definitiva pela interface, e arquivar é recusado enquanto
   houver histórico dependente.
4. Anexos não funcionam offline.
5. O SQLite local mantém o estado operacional em snapshot JSON, não em tabelas normalizadas por entidade.
6. O cache de perfil permite abrir o workspace offline após um primeiro acesso online, mas fluxos de expiração completa de sessão ainda precisam de homologação por plataforma.
7. A OS sai num modelo único, o da ORION. Os modelos por cliente
   (`service_order_templates`, com arquivo .docx e mapeamento de campos)
   continuam só como tabela no banco, sem tela.
8. A OS emitida fica só no computador que a emitiu: o PDF vai para
   Documentos/ORION ServiceLog/Ordens de serviço, e o vínculo com o
   atendimento, os complementos (solicitante, patrimônio, materiais,
   testes, situação final) e os dados do emitente ficam no banco local.
   Nada disso sobe para o servidor, e não há assinatura digital. A
   emissão é recusada enquanto o atendimento criado offline não
   sincroniza, porque o número dele ainda é provisório.
9. Não há gestão completa de usuários e convites.
10. O assistente local não usa embeddings; é uma busca heurística de fallback.
11. Não há suíte E2E com duas instâncias, perda de rede, concorrência e base volumosa.
12. Não houve auditoria externa de segurança.
13. A compilação não foi executada no ambiente de empacotamento; deve ser validada com Flutter no computador de desenvolvimento.
14. A identidade visual ainda não constitui um manual de marca completo.

15. O gatilho `enforce_same_organization` impedia gravação em
    atendimentos e tabelas derivadas até a migration `0013`. Bancos
    criados com a `0001` precisam dela antes do primeiro uso real.
