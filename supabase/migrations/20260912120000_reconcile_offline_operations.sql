-- 20260912120000_reconcile_offline_operations.sql
--
-- Reconcilia duas linhas de trabalho que chegaram, de forma independente,
-- à mesma decisão arquitetural: manter o corpo da RPC de replay num
-- escopo interno e expor uma função pública fina.
--
-- A 0011 renomeou o corpo para `apply_offline_operation_impl`, e a 0012
-- fez do invólucro público o lugar onde `archive`/`restore` e violação de
-- chave natural são tratados. A migration de autorização (20260907162623)
-- moveu o corpo para `orion_private.apply_offline_operation`, com
-- isolamento por organização reforçado, e recriou a função pública como
-- uma delegação direta.
--
-- Como o nome dela ordena depois das 0011-0015, ela venceu — e, ao
-- vencer, devolveu ao servidor um corpo derivado da 0010, que recusa
-- qualquer operação diferente de 'upsert':
--
--     if p_operation <> 'upsert' then
--       raise exception 'Unsupported offline operation: %', p_operation;
--
-- O efeito visível seria o arquivamento parar de funcionar e a violação
-- de chave natural voltar a subir como exceção crua.
--
-- Esta migration mantém o corpo endurecido como única definição da
-- lógica e reconstrói sobre ele o invólucro da 0012. Nada do isolamento
-- por organização é revertido: `orion_private.apply_offline_operation`
-- não é tocada.

-- ---------------------------------------------------------------------------
-- 1. Invólucro público, agora delegando ao corpo em orion_private.
-- ---------------------------------------------------------------------------

create or replace function public.apply_offline_operation(
  p_operation_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_operation text,
  p_payload jsonb,
  p_expected_revision bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
  v_constraint text;
  v_result jsonb;
begin
  -- Idempotência vale para todas as operações, inclusive arquivamento.
  select result into v_result
  from public.sync_operation_receipts
  where operation_id = p_operation_id
    and organization_id = v_org;

  if found then
    return v_result || jsonb_build_object('status', 'duplicate');
  end if;

  if p_operation in ('archive', 'restore') then
    return public.apply_archive_operation(
      p_operation_id, p_entity_type, p_entity_id, p_operation
    );
  end if;

  -- Gravação: o corpo endurecido decide, e a violação de chave natural
  -- vira conflito registrado em vez de exceção crua.
  begin
    return orion_private.apply_offline_operation(
      p_operation_id, p_entity_type, p_entity_id,
      p_operation, p_payload, p_expected_revision
    );
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      -- Corrida na criação implícita de fabricante: o vencedor gravou o
      -- que o perdedor queria. Uma segunda tentativa reaproveita a linha.
      if v_constraint not in (
        'manufacturers_global_name_uq', 'manufacturers_tenant_name_uq'
      ) then
        return public.record_offline_unique_conflict(
          p_operation_id, p_entity_type, p_entity_id, p_payload, v_constraint
        );
      end if;
  end;

  begin
    return orion_private.apply_offline_operation(
      p_operation_id, p_entity_type, p_entity_id,
      p_operation, p_payload, p_expected_revision
    );
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      return public.record_offline_unique_conflict(
        p_operation_id, p_entity_type, p_entity_id, p_payload, v_constraint
      );
  end;
end;
$$;

revoke all on function public.apply_offline_operation(
  uuid, text, uuid, text, jsonb, bigint
) from public, anon;

grant execute on function public.apply_offline_operation(
  uuid, text, uuid, text, jsonb, bigint
) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Remove a cópia agora órfã do corpo.
-- ---------------------------------------------------------------------------
-- `apply_offline_operation_impl` era o corpo da 0010 renomeado pela 0011.
-- A versão de orion_private o substitui com vantagem. Manter as duas
-- reintroduziria exatamente o problema que a 0011 existia para resolver:
-- duas definições divergentes da mesma lógica, fáceis de editar na errada.

drop function if exists public.apply_offline_operation_impl(
  uuid, text, uuid, text, jsonb, bigint
);
