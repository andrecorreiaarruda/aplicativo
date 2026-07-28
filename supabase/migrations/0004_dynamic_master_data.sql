-- ORION ServiceLog 0.3.0
-- Permite que cada organização cadastre fabricantes e modelos próprios,
-- mantendo o catálogo inicial global visível para todos os usuários autenticados.

alter table public.manufacturers
  add column if not exists organization_id uuid
  references public.organizations(id) on delete cascade;

alter table public.equipment_models
  add column if not exists organization_id uuid
  references public.organizations(id) on delete cascade;

alter table public.manufacturers
  drop constraint if exists manufacturers_name_key;

alter table public.equipment_models
  drop constraint if exists equipment_models_manufacturer_id_model_key;

create unique index if not exists manufacturers_global_name_uq
  on public.manufacturers (lower(name))
  where organization_id is null;

create unique index if not exists manufacturers_tenant_name_uq
  on public.manufacturers (organization_id, lower(name))
  where organization_id is not null;

create unique index if not exists equipment_models_global_name_uq
  on public.equipment_models (manufacturer_id, lower(model))
  where organization_id is null;

create unique index if not exists equipment_models_tenant_name_uq
  on public.equipment_models (organization_id, manufacturer_id, lower(model))
  where organization_id is not null;

create or replace function public.enforce_equipment_model_catalog_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  manufacturer_org uuid;
begin
  select organization_id
    into manufacturer_org
  from public.manufacturers
  where id = new.manufacturer_id;

  if not found then
    raise exception 'Manufacturer does not exist';
  end if;

  if manufacturer_org is not null
     and manufacturer_org is distinct from new.organization_id then
    raise exception 'Manufacturer and model must belong to the same organization';
  end if;

  if new.organization_id is null and manufacturer_org is not null then
    raise exception 'A global model cannot reference an organization-specific manufacturer';
  end if;

  return new;
end;
$$;

drop trigger if exists equipment_models_scope_guard
  on public.equipment_models;

create trigger equipment_models_scope_guard
before insert or update on public.equipment_models
for each row execute function public.enforce_equipment_model_catalog_scope();

drop policy if exists manufacturers_read on public.manufacturers;
drop policy if exists equipment_models_read on public.equipment_models;
drop policy if exists manufacturers_visible on public.manufacturers;
drop policy if exists manufacturers_insert_own on public.manufacturers;
drop policy if exists manufacturers_manage_own on public.manufacturers;
drop policy if exists manufacturers_delete_own on public.manufacturers;
drop policy if exists equipment_models_visible on public.equipment_models;
drop policy if exists equipment_models_insert_own on public.equipment_models;
drop policy if exists equipment_models_manage_own on public.equipment_models;
drop policy if exists equipment_models_delete_own on public.equipment_models;

create policy manufacturers_visible on public.manufacturers
for select to authenticated
using (
  organization_id is null
  or organization_id = public.current_organization_id()
);

create policy manufacturers_insert_own on public.manufacturers
for insert to authenticated
with check (organization_id = public.current_organization_id());

create policy manufacturers_manage_own on public.manufacturers
for update to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() in ('admin', 'engineer')
)
with check (organization_id = public.current_organization_id());

create policy manufacturers_delete_own on public.manufacturers
for delete to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() in ('admin', 'engineer')
);

create policy equipment_models_visible on public.equipment_models
for select to authenticated
using (
  organization_id is null
  or organization_id = public.current_organization_id()
);

create policy equipment_models_insert_own on public.equipment_models
for insert to authenticated
with check (organization_id = public.current_organization_id());

create policy equipment_models_manage_own on public.equipment_models
for update to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() in ('admin', 'engineer')
)
with check (organization_id = public.current_organization_id());

create policy equipment_models_delete_own on public.equipment_models
for delete to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() in ('admin', 'engineer')
);

grant select, insert, update, delete on public.manufacturers to authenticated;
grant select, insert, update, delete on public.equipment_models to authenticated;
