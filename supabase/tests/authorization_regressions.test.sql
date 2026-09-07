-- Regressões mínimas: estes testes falham no backend anterior à correção.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(6);
create function pg_temp.id(label text) returns uuid language sql immutable
as $$ select md5('orion-auth-regression:' || label)::uuid $$;
insert into auth.users(id) values (pg_temp.id('admin')), (pg_temp.id('viewer'));
insert into public.organizations(id,name,slug) values
  (pg_temp.id('a'),'Regression A','regression-a'),
  (pg_temp.id('b'),'Regression B','regression-b');
insert into public.profiles(user_id,organization_id,full_name,role) values
  (pg_temp.id('admin'),pg_temp.id('a'),'Admin','admin'),
  (pg_temp.id('viewer'),pg_temp.id('a'),'Viewer','viewer');
insert into public.customers(id,organization_id,name) values
  (pg_temp.id('customer-a'),pg_temp.id('a'),'Original A'),
  (pg_temp.id('customer-b'),pg_temp.id('b'),'Original B');

set local role authenticated;
select set_config('request.jwt.claims',json_build_object('sub',pg_temp.id('viewer'),'role','authenticated')::text,true);
with changed as (
  update public.customers set notes='unauthorized'
  where id=pg_temp.id('customer-a') returning 1
)
select is((select count(*) from changed),0::bigint,'viewer direct update is denied');
select throws_ok($q$
  select public.apply_offline_operation(
    pg_temp.id('viewer-op'),'customer',pg_temp.id('customer-a'),
    'upsert','{"name":"Changed by viewer"}'::jsonb,0
  )
$q$,'42501',null,'viewer RPC update is denied');

select set_config('request.jwt.claims',json_build_object('sub',pg_temp.id('admin'),'role','authenticated')::text,true);
select throws_ok($q$
  select public.apply_offline_operation(
    pg_temp.id('foreign-op'),'customer',pg_temp.id('customer-b'),
    'upsert','{"name":"Changed by other organization"}'::jsonb,0
  )
$q$,'42501',null,'RPC cannot overwrite a foreign customer UUID');
select lives_ok($q$
  select public.apply_offline_operation(
    pg_temp.id('valid-op'),'customer',pg_temp.id('customer-a'),
    'upsert','{"name":"Valid edit"}'::jsonb,0
  )
$q$,'own-organization admin update remains valid');

reset role;
select is((select name from public.customers where id=pg_temp.id('customer-b')),
  'Original B','foreign customer is unchanged');
select is((select count(*) from public.sync_operation_receipts
  where operation_id in (pg_temp.id('foreign-op'),pg_temp.id('viewer-op'))),
  0::bigint,'denied operations do not produce successful receipts');
select * from finish();
rollback;
