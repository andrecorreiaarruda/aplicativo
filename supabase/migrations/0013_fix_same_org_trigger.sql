-- 0013_fix_same_org_trigger.sql
--
-- Corrige `enforce_same_organization`, que impedia qualquer gravação em
-- service_cases, diagnostic_steps, case_attachments, case_embeddings e
-- ai_feedback com:
--
--   record "new" has no field "site_id"  (SQLSTATE 42703)
--
-- A causa está na estrutura das condições, não na lógica:
--
--   elsif tg_table_name = 'equipments' and new.site_id is not null then
--
-- O PL/pgSQL avalia a condição inteira como uma expressão SQL, e não
-- garante curto-circuito no `and`. Para um gatilho em service_cases, a
-- primeira condição falha, a segunda é avaliada, e `new.site_id` é
-- resolvido contra um registro que não tem esse campo. O erro ocorre na
-- preparação da expressão, antes de qualquer comparação — por isso
-- `tg_table_name = 'equipments'` ser falso não protege.
--
-- Só `sites` e `equipments` escapavam: a primeira casa no ramo anterior,
-- a segunda tem a coluna. O defeito existe desde a 0001 e permaneceu
-- latente porque nenhum atendimento havia sido gravado num banco real.
--
-- A correção move as referências a campos para dentro dos ramos, onde o
-- PL/pgSQL só as prepara se o ramo for alcançado. A lógica de validação
-- permanece idêntica.

create or replace function public.enforce_same_organization()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  parent_org uuid;
begin
  if tg_table_name = 'sites' then
    select organization_id into parent_org
    from public.customers where id = new.customer_id;

  elsif tg_table_name = 'equipments' then
    -- Equipamento sem local não tem pai a validar.
    if new.site_id is null then
      return new;
    end if;
    select organization_id into parent_org
    from public.sites where id = new.site_id;

  elsif tg_table_name = 'service_cases' then
    select organization_id into parent_org
    from public.equipments where id = new.equipment_id;

  elsif tg_table_name = 'diagnostic_steps' then
    select organization_id into parent_org
    from public.service_cases where id = new.service_case_id;

  elsif tg_table_name = 'case_attachments' then
    -- O anexo pende de um atendimento ou de um equipamento; a restrição
    -- attachment_parent_required garante que ao menos um exista.
    if new.service_case_id is not null then
      select organization_id into parent_org
      from public.service_cases where id = new.service_case_id;
    elsif new.equipment_id is not null then
      select organization_id into parent_org
      from public.equipments where id = new.equipment_id;
    else
      return new;
    end if;

  elsif tg_table_name = 'case_embeddings' then
    select organization_id into parent_org
    from public.service_cases where id = new.service_case_id;

  elsif tg_table_name = 'ai_feedback' then
    select organization_id into parent_org
    from public.ai_queries where id = new.ai_query_id;

  else
    return new;
  end if;

  if parent_org is null or parent_org <> new.organization_id then
    raise exception 'Cross-organization relationship is not permitted';
  end if;

  return new;
end;
$$;
