-- 0014_nullable_conflict_revisions.sql
--
-- Corrige a gravação de conflitos que não são de revisão.
--
-- `sync_conflicts` nasceu na 0008 para um único caso: divergência de
-- revisão otimista. Ali `expected_revision` e `server_revision` são
-- sempre conhecidos, e por isso foram declarados `not null`.
--
-- A 0011 passou a registrar também violação de chave natural, e a 0012
-- arquivamento recusado por dependência. Nesses dois não existe revisão
-- envolvida: a operação não colide com outra versão do mesmo registro,
-- colide com um registro diferente ou com o histórico. As funções
-- gravavam `null` nessas colunas e esbarravam na restrição:
--
--   null value in column "expected_revision" violates not-null constraint
--
-- O efeito era pior do que perder o conflito: o erro subia como falha de
-- sincronização, a operação permanecia na fila, e o pull seguinte
-- substituía o estado local pelo remoto — que não tinha o registro
-- recusado. Para quem usa, o cadastro simplesmente desaparecia.
--
-- Em vez de inventar zeros, as colunas passam a aceitar nulo, que é o
-- que "não se aplica" significa aqui. Relaxar uma restrição não invalida
-- linha existente alguma.

alter table public.sync_conflicts
  alter column expected_revision drop not null;

alter table public.sync_conflicts
  alter column server_revision drop not null;

comment on column public.sync_conflicts.expected_revision is
  'Revisão que o cliente esperava. Nulo em conflitos sem revisão '
  'envolvida, como violação de chave natural e arquivamento recusado.';

comment on column public.sync_conflicts.server_revision is
  'Revisão vigente no servidor. Nulo pelo mesmo motivo acima.';
