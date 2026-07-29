-- ORION ServiceLog 0.4.0-alpha.1
-- Fundação para sincronização offline e resolução futura de conflitos.

-- As entidades sincronizáveis recebem um contador monotônico, a data informada
-- pelo cliente e exclusão lógica. A exclusão lógica evita que um dispositivo
-- offline recrie um registro que já foi removido em outro dispositivo.

alter table public.customers
  add column if not exists client_updated_at timestamptz,
  add column if not exists sync_revision bigint not null default 1,
  add column if not exists deleted_at timestamptz;

alter table public.sites
  add column if not exists client_updated_at timestamptz,
  add column if not exists sync_revision bigint not null default 1,
  add column if not exists deleted_at timestamptz;

alter table public.manufacturers
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists client_updated_at timestamptz,
  add column if not exists sync_revision bigint not null default 1,
  add column if not exists deleted_at timestamptz;

alter table public.equipment_models
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists client_updated_at timestamptz,
  add column if not exists sync_revision bigint not null default 1,
  add column if not exists deleted_at timestamptz;

alter table public.equipments
  add column if not exists client_updated_at timestamptz,
  add column if not exists sync_revision bigint not null default 1,
  add column if not exists deleted_at timestamptz;

alter table public.service_cases
  add column if not exists client_updated_at timestamptz,
  add column if not exists sync_revision bigint not null default 1,
  add column if not exists deleted_at timestamptz;

alter table public.service_progress_entries
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists client_updated_at timestamptz,
  add column if not exists sync_revision bigint not null default 1,
  add column if not exists deleted_at timestamptz;

create or replace function public.bump_sync_revision()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.sync_revision = coalesce(old.sync_revision, 0) + 1;
  new.updated_at = now();
  return new;
end;
$$;

-- Um trigger separado por tabela mantém a migration idempotente.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'customers',
    'sites',
    'manufacturers',
    'equipment_models',
    'equipments',
    'service_cases',
    'service_progress_entries'
  ]
  loop
    execute format(
      'drop trigger if exists %I on public.%I',
      table_name || '_bump_sync_revision',
      table_name
    );
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.bump_sync_revision()',
      table_name || '_bump_sync_revision',
      table_name
    );
  end loop;
end;
$$;

create index if not exists customers_sync_cursor_idx
  on public.customers (organization_id, updated_at, sync_revision);
create index if not exists sites_sync_cursor_idx
  on public.sites (organization_id, updated_at, sync_revision);
create index if not exists equipments_sync_cursor_idx
  on public.equipments (organization_id, updated_at, sync_revision);
create index if not exists service_cases_sync_cursor_idx
  on public.service_cases (organization_id, updated_at, sync_revision);
create index if not exists service_progress_sync_cursor_idx
  on public.service_progress_entries (organization_id, updated_at, sync_revision);

comment on column public.service_cases.client_updated_at is
  'Data da alteração no dispositivo, usada apenas como evidência de conflito; o servidor continua autoritativo.';
comment on column public.service_cases.sync_revision is
  'Contador monotônico incrementado no servidor a cada atualização.';
comment on column public.service_cases.deleted_at is
  'Exclusão lógica para propagação segura a dispositivos offline.';
