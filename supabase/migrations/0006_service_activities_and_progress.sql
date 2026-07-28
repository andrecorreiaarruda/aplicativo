-- ORION ServiceLog 0.3.3
-- Classificação de atendimentos e diário contínuo de execução.

alter table public.service_cases
  add column if not exists activity_type text not null default 'maintenance';

alter table public.service_cases
  drop constraint if exists service_cases_activity_type_check;

alter table public.service_cases
  add constraint service_cases_activity_type_check
  check (activity_type in ('maintenance', 'installation', 'deinstallation'));

create index if not exists service_cases_activity_idx
  on public.service_cases (organization_id, activity_type, opened_at desc);

create table if not exists public.service_progress_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  service_case_id uuid not null references public.service_cases(id) on delete cascade,
  occurred_at timestamptz not null default now(),
  description text not null check (nullif(trim(description), '') is not null),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists service_progress_entries_case_idx
  on public.service_progress_entries (service_case_id, occurred_at desc);

create index if not exists service_progress_entries_org_idx
  on public.service_progress_entries (organization_id, occurred_at desc);

create or replace function public.enforce_service_progress_entry_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_org uuid;
begin
  select organization_id
    into parent_org
  from public.service_cases
  where id = new.service_case_id;

  if not found then
    raise exception 'Service case does not exist';
  end if;

  if parent_org is distinct from new.organization_id then
    raise exception 'Service case and progress entry must belong to the same organization';
  end if;

  return new;
end;
$$;

drop trigger if exists service_progress_entries_scope_guard
  on public.service_progress_entries;

create trigger service_progress_entries_scope_guard
before insert or update on public.service_progress_entries
for each row execute function public.enforce_service_progress_entry_scope();

alter table public.service_progress_entries enable row level security;

drop policy if exists service_progress_entries_tenant_access
  on public.service_progress_entries;

create policy service_progress_entries_tenant_access
on public.service_progress_entries
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

grant select, insert, update, delete
on public.service_progress_entries to authenticated;

-- Atualiza a busca híbrida para preservar a classificação da atividade e
-- considerar o diário de andamento na similaridade textual.
drop function if exists public.search_similar_cases(
  vector, text, uuid, uuid, uuid, text, text, integer
);

create function public.search_similar_cases(
  query_embedding vector(1536),
  query_text text,
  filter_equipment_id uuid default null,
  filter_manufacturer_id uuid default null,
  filter_model_id uuid default null,
  filter_subsystem text default null,
  filter_error_code text default null,
  result_limit integer default 10
)
returns table (
  service_case_id uuid,
  case_number bigint,
  equipment_id uuid,
  activity_type text,
  manufacturer text,
  equipment_model text,
  serial_number text,
  opened_at timestamptz,
  error_code text,
  subsystem text,
  reported_failure text,
  observed_symptoms text,
  root_cause text,
  solution_details text,
  validation_result text,
  solution_confidence public.solution_confidence,
  vector_similarity double precision,
  lexical_score real,
  exact_code_match boolean,
  final_score double precision
)
language sql
stable
security invoker
set search_path = public
as $$
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

grant execute on function public.search_similar_cases(
  vector, text, uuid, uuid, uuid, text, text, integer
) to authenticated;
