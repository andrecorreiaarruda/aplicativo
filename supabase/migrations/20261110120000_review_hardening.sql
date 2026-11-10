-- ORION: endurecimento após revisão geral de segurança.
--
-- Cinco correções, todas de menor privilégio ou de coerência entre regras
-- que já existiam. Nenhuma muda o contrato usado pelo aplicativo, que só
-- grava pela RPC `apply_offline_operation`.
--
--   1. A RPC pública devolvia o recibo de uma operação já aplicada ANTES
--      de conferir o papel de quem chama. Um usuário de Consulta que
--      reenviasse o identificador de uma operação alheia recebia o
--      resultado gravado em vez da recusa. A conferência de papel passa a
--      vir primeiro. (Regressão da migration de exclusão definitiva, que
--      trouxe a idempotência para o wrapper; o teste 191 de
--      backend_authorization.test.sql a acusava.)
--
--   2. Exclusão direta nas tabelas operacionais passa a ser só do
--      administrador. A exclusão definitiva pela RPC já era só dele, e só
--      de registro arquivado e sem dependentes; a política de DELETE das
--      tabelas deixava técnico, gestor e engenheiro apagar a linha direto
--      pela API, contornando as três travas.
--
--   3. A busca por casos semelhantes devolvia atendimentos arquivados.
--
--   4. `bootstrap_organization`, `search_similar_cases` e os dois
--      auxiliares de contexto deixam de ser executáveis por `anon` e
--      `public`. Todos já recusavam ou devolviam vazio sem sessão; o
--      privilégio sobrava.
--
--   5. Funções SECURITY DEFINER passam a ter `pg_temp` no fim do
--      search_path, para que um objeto temporário nunca seja resolvido
--      antes do schema `public`.

-- ---------------------------------------------------------------------
-- 1. Papel antes do recibo
-- ---------------------------------------------------------------------

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
set search_path = public, pg_temp
as $$
declare
  v_org uuid := public.current_organization_id();
  v_role public.user_role := public.current_user_role();
  v_constraint text;
  v_result jsonb;
begin
  -- As mesmas condições, com as mesmas mensagens, das implementações
  -- internas. Repetidas aqui porque a consulta ao recibo, logo abaixo,
  -- responde antes de qualquer uma delas ser alcançada.
  if auth.uid() is null or v_org is null then
    raise exception 'Authenticated organization context is required'
      using errcode = '42501';
  end if;

  if v_role is null
     or v_role not in ('admin', 'engineer', 'technician', 'manager') then
    raise exception 'Write permission is required' using errcode = '42501';
  end if;

  -- Idempotência vale para todas as operações, inclusive arquivamento e
  -- exclusão definitiva.
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

  if p_operation = 'purge' then
    return public.apply_purge_operation(
      p_operation_id, p_entity_type, p_entity_id
    );
  end if;

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
) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2. Exclusão direta só do administrador
-- ---------------------------------------------------------------------
-- Locais entram porque saem em cascata do cliente e levam os
-- equipamentos a ficar sem local. O diário, os passos de diagnóstico e
-- os anexos continuam como estavam: são partes de um atendimento, e
-- editá-lo inclui removê-las.

drop policy if exists customers_delete on public.customers;
create policy customers_delete on public.customers
for delete to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() = 'admin'
);

drop policy if exists sites_delete on public.sites;
create policy sites_delete on public.sites
for delete to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() = 'admin'
);

drop policy if exists equipments_delete on public.equipments;
create policy equipments_delete on public.equipments
for delete to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() = 'admin'
);

drop policy if exists service_cases_delete on public.service_cases;
create policy service_cases_delete on public.service_cases
for delete to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() = 'admin'
);

-- ---------------------------------------------------------------------
-- 3. Busca sem arquivados
-- ---------------------------------------------------------------------

create or replace function public.search_similar_cases(query_embedding vector, query_text text, filter_equipment_id uuid DEFAULT NULL::uuid, filter_manufacturer_id uuid DEFAULT NULL::uuid, filter_model_id uuid DEFAULT NULL::uuid, filter_subsystem text DEFAULT NULL::text, filter_error_code text DEFAULT NULL::text, result_limit integer DEFAULT 10)
 RETURNS TABLE(service_case_id uuid, case_number bigint, equipment_id uuid, activity_type text, manufacturer text, equipment_model text, serial_number text, opened_at timestamp with time zone, error_code text, subsystem text, reported_failure text, observed_symptoms text, root_cause text, solution_details text, validation_result text, solution_confidence solution_confidence, vector_similarity double precision, lexical_score real, exact_code_match boolean, final_score double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $$
  with candidates as (
    select
      sc.id as service_case_id,
      sc.case_number,
      sc.equipment_id,
      sc.activity_type,
      m.name as manufacturer,
      em.model as equipment_model,
      e.serial_number,
      sc.opened_at,
      sc.error_code,
      sc.subsystem,
      sc.reported_failure,
      sc.observed_symptoms,
      sc.root_cause,
      sc.solution_details,
      sc.validation_result,
      sc.solution_confidence,
      (1 - (ce.embedding <=> query_embedding))::double precision as vector_similarity,
      ts_rank_cd(
        sc.search_document ||
          to_tsvector('portuguese', coalesce(progress.progress_text, '')),
        websearch_to_tsquery('portuguese', coalesce(query_text, ''))
      ) as lexical_score,
      (
        filter_error_code is not null
        and nullif(trim(filter_error_code), '') is not null
        and lower(coalesce(sc.error_code, '')) = lower(trim(filter_error_code))
      ) as exact_code_match,
      case sc.solution_confidence
        when 'reviewed' then 1.00
        when 'recurring' then 0.95
        when 'confirmed' then 0.90
        when 'probable' then 0.70
        when 'unconfirmed' then 0.45
        when 'obsolete' then 0.00
      end as confidence_weight
    from public.service_cases sc
    join public.case_embeddings ce on ce.service_case_id = sc.id
    join public.equipments e on e.id = sc.equipment_id
    join public.equipment_models em on em.id = e.equipment_model_id
    join public.manufacturers m on m.id = em.manufacturer_id
    left join lateral (
      select string_agg(spe.description, ' ' order by spe.occurred_at) as progress_text
      from public.service_progress_entries spe
      where spe.service_case_id = sc.id
    ) progress on true
    where sc.organization_id = public.current_organization_id()
      and sc.status = 'resolved'
      -- Atendimento arquivado sai das telas; não pode voltar pela busca.
      and sc.deleted_at is null
      and sc.solution_confidence <> 'obsolete'
      and (filter_equipment_id is null or sc.equipment_id = filter_equipment_id)
      and (filter_manufacturer_id is null or m.id = filter_manufacturer_id)
      and (filter_model_id is null or em.id = filter_model_id)
      and (filter_subsystem is null or lower(coalesce(sc.subsystem, '')) = lower(filter_subsystem))
  )
  select
    c.service_case_id,
    c.case_number,
    c.equipment_id,
    c.activity_type,
    c.manufacturer,
    c.equipment_model,
    c.serial_number,
    c.opened_at,
    c.error_code,
    c.subsystem,
    c.reported_failure,
    c.observed_symptoms,
    c.root_cause,
    c.solution_details,
    c.validation_result,
    c.solution_confidence,
    c.vector_similarity,
    c.lexical_score,
    c.exact_code_match,
    (
      (greatest(c.vector_similarity, 0) * 0.62)
      + (least(c.lexical_score::double precision, 1.0) * 0.18)
      + (case when c.exact_code_match then 0.15 else 0 end)
      + (c.confidence_weight * 0.05)
    ) as final_score
  from candidates c
  order by final_score desc, c.opened_at desc
  limit least(greatest(result_limit, 1), 50);
$$;

-- ---------------------------------------------------------------------
-- 4. Privilégios de execução
-- ---------------------------------------------------------------------

revoke all on function public.bootstrap_organization(text, text, text)
  from public, anon;
grant execute on function public.bootstrap_organization(text, text, text)
  to authenticated;

revoke all on function public.search_similar_cases(
  vector, text, uuid, uuid, uuid, text, text, integer
) from public, anon;
grant execute on function public.search_similar_cases(
  vector, text, uuid, uuid, uuid, text, text, integer
) to authenticated, service_role;

-- As políticas de RLS chamam estas duas com o papel de quem consulta;
-- `authenticated` precisa continuar podendo executá-las.
revoke all on function public.current_organization_id() from public, anon;
grant execute on function public.current_organization_id()
  to authenticated, service_role;

revoke all on function public.current_user_role() from public, anon;
grant execute on function public.current_user_role()
  to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5. search_path das funções privilegiadas
-- ---------------------------------------------------------------------

alter function public.apply_archive_operation(uuid, text, uuid, text)
  set search_path = public, pg_temp;
alter function public.apply_purge_operation(uuid, text, uuid)
  set search_path = public, pg_temp;
alter function public.count_archive_blockers(text, uuid)
  set search_path = public, pg_temp;
alter function public.count_purge_blockers(text, uuid)
  set search_path = public, pg_temp;
alter function public.record_offline_unique_conflict(
  uuid, text, uuid, jsonb, text
) set search_path = public, pg_temp;
alter function public.bootstrap_organization(text, text, text)
  set search_path = public, pg_temp;
alter function public.current_organization_id()
  set search_path = public, pg_temp;
alter function public.current_user_role()
  set search_path = public, pg_temp;
alter function public.audit_row_change()
  set search_path = public, pg_temp;
alter function public.enforce_equipment_model_catalog_scope()
  set search_path = public, pg_temp;
alter function public.enforce_service_order_template_scope()
  set search_path = public, pg_temp;
alter function public.enforce_service_progress_entry_scope()
  set search_path = public, pg_temp;
