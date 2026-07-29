# Limitações conhecidas — 0.4.0-alpha.2

1. O pull remoto substitui o snapshot local completo; ainda não usa paginação ou cursor incremental.
2. Conflitos são detectados e preservados, mas ainda não existe tela para comparar e resolver versões.
3. Exclusões e tombstones não estão expostos na interface.
4. Anexos não funcionam offline.
5. O SQLite local mantém o estado operacional em snapshot JSON, não em tabelas normalizadas por entidade.
6. O cache de perfil permite abrir o workspace offline após um primeiro acesso online, mas fluxos de expiração completa de sessão ainda precisam de homologação por plataforma.
7. Modelos de OS existem apenas como metadados no banco.
8. Não há geração PDF/DOCX ou assinatura.
9. Não há gestão completa de usuários e convites.
10. O assistente local não usa embeddings; é uma busca heurística de fallback.
11. Não há suíte E2E com duas instâncias, perda de rede, concorrência e base volumosa.
12. Não houve auditoria externa de segurança.
13. A compilação não foi executada no ambiente de empacotamento; deve ser validada com Flutter no computador de desenvolvimento.
14. A identidade visual ainda não constitui um manual de marca completo.
