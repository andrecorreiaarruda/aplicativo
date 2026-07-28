-- ORION ServiceLog 0.3.1
-- Dados opcionais de clientes e fundação para modelos de ordem de serviço.

alter table public.customers
  add column if not exists contact_name text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists address_line text,
  add column if not exists city text,
  add column if not exists state text;

create table if not exists public.service_order_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  name text not null,
  file_name text,
  storage_path text,
  field_mapping jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (customer_id, name)
);

create or replace function public.enforce_service_order_template_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  customer_org uuid;
begin
  select organization_id
    into customer_org
  from public.customers
  where id = new.customer_id;

  if not found then
    raise exception 'Customer does not exist';
  end if;

  if customer_org is distinct from new.organization_id then
    raise exception 'Customer and service order template must belong to the same organization';
  end if;

  return new;
end;
$$;

drop trigger if exists service_order_templates_scope_guard
  on public.service_order_templates;

create trigger service_order_templates_scope_guard
before insert or update on public.service_order_templates
for each row execute function public.enforce_service_order_template_scope();

drop trigger if exists service_order_templates_set_updated_at
  on public.service_order_templates;

create trigger service_order_templates_set_updated_at
before update on public.service_order_templates
for each row execute function public.set_updated_at();

alter table public.service_order_templates enable row level security;

drop policy if exists service_order_templates_read_own
  on public.service_order_templates;
drop policy if exists service_order_templates_insert_own
  on public.service_order_templates;
drop policy if exists service_order_templates_update_own
  on public.service_order_templates;
drop policy if exists service_order_templates_delete_own
  on public.service_order_templates;

create policy service_order_templates_read_own
on public.service_order_templates
for select to authenticated
using (organization_id = public.current_organization_id());

create policy service_order_templates_insert_own
on public.service_order_templates
for insert to authenticated
with check (organization_id = public.current_organization_id());

create policy service_order_templates_update_own
on public.service_order_templates
for update to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() in ('admin', 'engineer')
)
with check (organization_id = public.current_organization_id());

create policy service_order_templates_delete_own
on public.service_order_templates
for delete to authenticated
using (
  organization_id = public.current_organization_id()
  and public.current_user_role() in ('admin', 'engineer')
);

grant select, insert, update, delete
on public.service_order_templates to authenticated;
