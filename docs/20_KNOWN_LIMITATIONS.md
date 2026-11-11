# Limitações conhecidas

## Sincronização

1. **O download é integral.** Cada sincronização baixa a base inteira, em
   páginas, e substitui o espelho local. Não há sincronização incremental
   por data de alteração. Funciona bem na casa de alguns milhares de
   atendimentos; acima disso, o tempo e o tráfego crescem na mesma
   proporção.
2. **Um conflito não resolvido congela o download.** Enquanto houver
   operação parada na fila, as novidades do servidor não entram, para não
   sobrescrever a alteração local. A tela de conflitos resolve; não há
   comparação campo a campo entre as duas versões.
3. **Arquivar e restaurar direto na tabela não confere dependentes.** As
   regras de arquivamento vivem na RPC, que é o único caminho usado pelo
   aplicativo. Quem editar `deleted_at` direto pela API do banco contorna
   a verificação de histórico dependente. A exclusão direta, essa sim, foi
   restrita ao administrador.

## Dados locais

4. **O banco local não é criptografado.** A pasta de dados fica fechada
   para os outros usuários do sistema (modo 700 no Linux e no macOS), mas
   quem tem acesso à conta do sistema operacional lê o arquivo. Em
   notebook que sai da empresa, use criptografia de disco.
5. **Sair da conta não apaga os dados locais.** O espelho da organização
   continua no computador, para reabrir offline.
6. **O estado local é um instantâneo JSON**, não tabelas por entidade. É
   regravado a cada alteração — alguns megabytes numa base grande.
7. **Anexos não funcionam offline** e não têm tela.

## Ordem de serviço

8. **Um modelo só**, o da ORION. Os modelos por cliente
   (`service_order_templates`) existem apenas como tabela no banco.
9. **A OS emitida fica no computador que a emitiu.** O PDF vai para
   Documentos; o vínculo com o atendimento, os complementos e os dados do
   emitente ficam no banco local. Nada disso sobe para o servidor. Não há
   assinatura digital.
10. **Atendimento criado offline só gera OS depois de sincronizar**,
    porque o número dele é provisório até o servidor confirmar.

## Contas e acesso

11. **Não há gestão de usuários nem convites.** Um segundo usuário
    precisa ser ligado à organização direto no banco.
12. **A interface não esconde ações de quem só consulta.** Um perfil de
    Consulta vê os botões de edição; o servidor recusa a gravação.
13. **As funções de busca não têm limite de uso por usuário.** O tamanho
    da entrada é limitado, mas não a quantidade de consultas. Cada uma
    gera custo na OpenAI e na Anthropic.

## Busca no histórico

14. **Offline, a busca é por palavras**, não por significado: compara os
    termos da descrição com os atendimentos resolvidos no espelho local.

## Qualidade

15. **Não há teste de ponta a ponta** com duas instâncias, queda de rede
    e edição simultânea. A cobertura é de unidade, de tela e de banco
    (pgTAP).
16. **Não houve auditoria externa de segurança.** A revisão interna está
    em `50_REVISAO_GERAL.md`.
17. **Windows, macOS, Android, iOS e web compilam em tese**, mas só o
    Linux é usado e testado de fato.
