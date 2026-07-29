-- ServiceLog AI - initial multi-tenant schema

create extension if not exists pgcrypto;
create extension if not exists vector;

create type public.user_role as enum ('admin', 'engineer', 'technician', 'viewer', 'manager');
create type public.equipment_status as enum ('operational', 'degraded', 'stopped', 'decommissioned');
create type public.case_status as enum ('open', 'diagnosing', 'waiting_parts', 'waiting_customer', 'resolved', 'cancelled');
create type public.operational_impact as enum ('none', 'degraded', 'partial_stop', 'total_stop');
create type public.solution_confidence as enum ('unconfirmed', 'probable', 'confirmed', 'recurring', 'reviewed', 'obsolete');
create type public.sync_state as enum ('synced', 'pending', 'conflict');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  full_name text not null,
  role public.user_role not null default 'technician',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  tax_id text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, name)
);

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  name text not null,
  city text,
  state text,
  country text not null default 'Brasil',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (customer_id, name)
);

create table public.manufacturers (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.equipment_models (
  id uuid primary key default gen_random_uuid(),
  manufacturer_id uuid not null references public.manufacturers(id),
  family text,
  model text not null,
  modality text not null,
  description text,
  created_at timestamptz not null default now(),
  unique (manufacturer_id, model)
);

create table public.equipments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  site_id uuid references public.sites(id) on delete set null,
  equipment_model_id uuid not null references public.equipment_models(id),
  serial_number text not null,
  asset_tag text,
  software_version text,
  hardware_version text,
  installation_date date,
  status public.equipment_status not null default 'operational',
  subsystems text[] not null default '{}',
  notes text,
  sync_status public.sync_state not null default 'synced',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, serial_number)
);

create table public.service_cases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  equipment_id uuid not null references public.equipments(id) on delete restrict,
  case_number bigint generated always as identity,
  status public.case_status not null default 'open',
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  reported_failure text not null,
  observed_symptoms text,
  error_code text,
  error_message text,
  subsystem text,
  operational_impact public.operational_impact not null default 'degraded',
  suspected_components text[],
  measurements text,
  root_cause text,
  solution_details text,
  validation_result text,
  final_equipment_status public.equipment_status,
  solution_confidence public.solution_confidence not null default 'unconfirmed',
  downtime_minutes integer check (downtime_minutes is null or downtime_minutes >= 0),
  service_minutes integer check (service_minutes is null or service_minutes >= 0),
  requires_follow_up boolean not null default false,
  follow_up_notes text,
  safety_notes text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid references auth.users(id),
  sync_status public.sync_state not null default 'synced',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  search_document tsvector generated always as (
    to_tsvector(
      'portuguese',
      coalesce(reported_failure, '') || ' ' ||
      coalesce(observed_symptoms, '') || ' ' ||
      coalesce(error_code, '') || ' ' ||
      coalesce(error_message, '') || ' ' ||
      coalesce(subsystem, '') || ' ' ||
      coalesce(measurements, '') || ' ' ||
      coalesce(root_cause, '') || ' ' ||
      coalesce(solution_details, '') || ' ' ||
      coalesce(validation_result, '')
    )
  ) stored,
  constraint closed_case_requires_solution check (
    status <> 'resolved'
    or (
      closed_at is not null
      and nullif(trim(solution_details), '') is not null
      and nullif(trim(validation_result), '') is not null
      and final_equipment_status is not null
    )
  )
);

create index service_cases_org_idx on public.service_cases (organization_id);
create index service_cases_equipment_idx on public.service_cases (equipment_id);
create index service_cases_error_code_idx on public.service_cases (organization_id, lower(error_code));
create index service_cases_search_idx on public.service_cases using gin (search_document);
create index service_cases_status_idx on public.service_cases (organization_id, status, opened_at desc);

create table public.diagnostic_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  service_case_id uuid not null references public.service_cases(id) on delete cascade,
  sequence_number integer not null check (sequence_number > 0),
  performed_at timestamptz not null default now(),
  action text not null,
  result text not null,
  measurement_value numeric,
  measurement_unit text,
  conclusion text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (service_case_id, sequence_number)
);

create table public.case_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  service_case_id uuid references public.service_cases(id) on delete cascade,
  equipment_id uuid references public.equipments(id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  category text not null default 'other',
  contains_patient_data boolean not null default false,
  ai_indexing_allowed boolean not null default false,
  copyright_basis text,
  uploaded_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  constraint attachment_parent_required check (service_case_id is not null or equipment_id is not null),
  constraint no_patient_data check (contains_patient_data = false)
);

create table public.case_embeddings (
  service_case_id uuid primary key references public.service_cases(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  embedding_model text not null,
  source_hash text not null,
  source_text text not null,
  embedding vector(1536) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index case_embeddings_org_idx on public.case_embeddings (organization_id);
create index case_embeddings_hnsw_idx on public.case_embeddings using hnsw (embedding vector_cosine_ops);

create table public.ai_queries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id),
  query_text text not null,
  filters jsonb not null default '{}'::jsonb,
  retrieved_case_ids uuid[] not null default '{}',
  generated_answer text,
  created_at timestamptz not null default now()
);

create table public.ai_feedback (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  ai_query_id uuid not null references public.ai_queries(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id),
  helpful boolean,
  rating smallint check (rating between 1 and 5),
  comments text,
  created_at timestamptz not null default now(),
  unique (ai_query_id, user_id)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid,
  actor_user_id uuid,
  table_name text not null,
  record_id uuid,
  operation text not null,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger organizations_set_updated_at before update on public.organizations
for each row execute function public.set_updated_at();
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger customers_set_updated_at before update on public.customers
for each row execute function public.set_updated_at();
create trigger sites_set_updated_at before update on public.sites
for each row execute function public.set_updated_at();
create trigger equipments_set_updated_at before update on public.equipments
for each row execute function public.set_updated_at();
create trigger service_cases_set_updated_at before update on public.service_cases
for each row execute function public.set_updated_at();
create trigger diagnostic_steps_set_updated_at before update on public.diagnostic_steps
for each row execute function public.set_updated_at();
create trigger case_embeddings_set_updated_at before update on public.case_embeddings
for each row execute function public.set_updated_at();

create or replace function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id
  from public.profiles
  where user_id = auth.uid() and active = true
  limit 1;
$$;

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.profiles
  where user_id = auth.uid() and active = true
  limit 1;
$$;

create or replace function public.bootstrap_organization(
  organization_name text,
  organization_slug text,
  owner_full_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_org_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if exists (select 1 from public.profiles where user_id = auth.uid()) then
    raise exception 'User already belongs to an organization';
  end if;

  insert into public.organizations(name, slug)
  values (trim(organization_name), lower(trim(organization_slug)))
  returning id into new_org_id;

  insert into public.profiles(user_id, organization_id, full_name, role)
  values (auth.uid(), new_org_id, trim(owner_full_name), 'admin');

  return new_org_id;
end;
$$;

grant execute on function public.bootstrap_organization(text, text, text) to authenticated;

create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  org_id uuid;
  row_id uuid;
begin
  org_id := coalesce((to_jsonb(new)->>'organization_id')::uuid, (to_jsonb(old)->>'organization_id')::uuid);
  row_id := coalesce((to_jsonb(new)->>'id')::uuid, (to_jsonb(old)->>'id')::uuid);

  insert into public.audit_logs(
    organization_id,
    actor_user_id,
    table_name,
    record_id,
    operation,
    old_data,
    new_data
  ) values (
    org_id,
    auth.uid(),
    tg_table_name,
    row_id,
    tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger equipments_audit after insert or update or delete on public.equipments
for each row execute function public.audit_row_change();
create trigger service_cases_audit after insert or update or delete on public.service_cases
for each row execute function public.audit_row_change();
create trigger diagnostic_steps_audit after insert or update or delete on public.diagnostic_steps
for each row execute function public.audit_row_change();

create or replace function public.enforce_same_organization()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  parent_org uuid;
begin
  if tg_table_name = 'sites' then
    select organization_id into parent_org from public.customers where id = new.customer_id;
  elsif tg_table_name = 'equipments' and new.site_id is not null then
    select organization_id into parent_org from public.sites where id = new.site_id;
  elsif tg_table_name = 'service_cases' then
    select organization_id into parent_org from public.equipments where id = new.equipment_id;
  elsif tg_table_name = 'diagnostic_steps' then
    select organization_id into parent_org from public.service_cases where id = new.service_case_id;
  elsif tg_table_name = 'case_attachments' and new.service_case_id is not null then
    select organization_id into parent_org from public.service_cases where id = new.service_case_id;
  elsif tg_table_name = 'case_attachments' and new.equipment_id is not null then
    select organization_id into parent_org from public.equipments where id = new.equipment_id;
  elsif tg_table_name = 'case_embeddings' then
    select organization_id into parent_org from public.service_cases where id = new.service_case_id;
  elsif tg_table_name = 'ai_feedback' then
    select organization_id into parent_org from public.ai_queries where id = new.ai_query_id;
  else
    return new;
  end if;

  if parent_org is null or parent_org <> new.organization_id then
    raise exception 'Cross-organization relationship is not permitted';
  end if;

  return new;
end;
$$;

create trigger sites_same_org before insert or update on public.sites
for each row execute function public.enforce_same_organization();
create trigger equipments_same_org before insert or update on public.equipments
for each row execute function public.enforce_same_organization();
create trigger service_cases_same_org before insert or update on public.service_cases
for each row execute function public.enforce_same_organization();
create trigger diagnostic_steps_same_org before insert or update on public.diagnostic_steps
for each row execute function public.enforce_same_organization();
create trigger case_attachments_same_org before insert or update on public.case_attachments
for each row execute function public.enforce_same_organization();
create trigger case_embeddings_same_org before insert or update on public.case_embeddings
for each row execute function public.enforce_same_organization();
create trigger ai_feedback_same_org before insert or update on public.ai_feedback
for each row execute function public.enforce_same_organization();

create or replace function public.set_case_updated_by()
returns trigger
language plpgsql
as $$
begin
  new.updated_by = auth.uid();
  return new;
end;
$$;

create trigger service_cases_set_updated_by before update on public.service_cases
for each row execute function public.set_case_updated_by();

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.sites enable row level security;
alter table public.manufacturers enable row level security;
alter table public.equipment_models enable row level security;
alter table public.equipments enable row level security;
alter table public.service_cases enable row level security;
alter table public.diagnostic_steps enable row level security;
alter table public.case_attachments enable row level security;
alter table public.case_embeddings enable row level security;
alter table public.ai_queries enable row level security;
alter table public.ai_feedback enable row level security;
alter table public.audit_logs enable row level security;

create policy organizations_select_own on public.organizations
for select to authenticated
using (id = public.current_organization_id());

create policy organizations_admin_update on public.organizations
for update to authenticated
using (id = public.current_organization_id() and public.current_user_role() = 'admin')
with check (id = public.current_organization_id());

create policy profiles_select_own_org on public.profiles
for select to authenticated
using (organization_id = public.current_organization_id());

create policy profiles_admin_insert on public.profiles
for insert to authenticated
with check (organization_id = public.current_organization_id() and public.current_user_role() = 'admin');

create policy profiles_admin_update on public.profiles
for update to authenticated
using (organization_id = public.current_organization_id() and public.current_user_role() = 'admin')
with check (organization_id = public.current_organization_id());

create policy profiles_admin_delete on public.profiles
for delete to authenticated
using (organization_id = public.current_organization_id() and public.current_user_role() = 'admin');

create policy manufacturers_read on public.manufacturers
for select to authenticated using (true);
create policy equipment_models_read on public.equipment_models
for select to authenticated using (true);

-- The manufacturer/model catalog is read-only to authenticated users.
-- Additions are made by controlled migrations or a service-role administration flow.

create policy customers_tenant_access on public.customers
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy sites_tenant_access on public.sites
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy equipments_tenant_access on public.equipments
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy service_cases_tenant_access on public.service_cases
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy diagnostic_steps_tenant_access on public.diagnostic_steps
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy attachments_tenant_access on public.case_attachments
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id() and contains_patient_data = false);

create policy embeddings_tenant_read on public.case_embeddings
for select to authenticated
using (organization_id = public.current_organization_id());

create policy ai_queries_tenant_access on public.ai_queries
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy ai_feedback_tenant_access on public.ai_feedback
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy audit_logs_read on public.audit_logs
for select to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() in ('admin', 'engineer', 'manager')
);

revoke all on public.case_embeddings from authenticated;
grant select on public.case_embeddings to authenticated;
revoke insert, update, delete on public.audit_logs from authenticated;
