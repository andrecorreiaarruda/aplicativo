-- Regressões da migration 20261110120000_review_hardening.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(14);
create function pg_temp.id(label text) returns uuid language sql immutable
as $$ select md5('orion-review-hardening:' || label)::uuid $$;
create function pg_temp.actor(label text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', pg_temp.id(label), 'role', 'authenticated')::text, true);
$$;

insert into auth.users(id)
select pg_temp.id(x) from unnest(array['admin','technician','viewer']) x;
insert into public.organizations(id,name,slug)
values (pg_temp.id('org'),'Hardening','review-hardening');
insert into public.profiles(user_id,organization_id,full_name,role)
select pg_temp.id(x), pg_temp.id('org'), x, x::public.user_role
from unnest(array['admin','technician','viewer']) x;
insert into public.manufacturers(id,organization_id,name)
values (pg_temp.id('maker'),pg_temp.id('org'),'Maker H');
insert into public.equipment_models(id,organization_id,manufacturer_id,model,modality)
values (pg_temp.id('model'),pg_temp.id('org'),pg_temp.id('maker'),'Model H','Test');
insert into public.customers(id,organization_id,name)
values (pg_temp.id('customer'),pg_temp.id('org'),'Customer H');
insert into public.sites(id,organization_id,customer_id,name)
values (pg_temp.id('site'),pg_temp.id('org'),pg_temp.id('customer'),'Site H');
insert into public.equipments(id,organization_id,equipment_model_id,site_id,serial_number)
values (pg_temp.id('equipment'),pg_temp.id('org'),pg_temp.id('model'),pg_temp.id('site'),'SERIAL-H');
insert into public.service_cases(
  id,organization_id,equipment_id,status,reported_failure,
  solution_details,validation_result,final_equipment_status,closed_at,
  solution_confidence,created_by,deleted_at)
values
  (pg_temp.id('case-active'),pg_temp.id('org'),pg_temp.id('equipment'),'resolved',
   'Falha ativa','Solução','Validação','operational',now(),'confirmed',
   pg_temp.id('admin'),null),
  (pg_temp.id('case-archived'),pg_temp.id('org'),pg_temp.id('equipment'),'resolved',
   'Falha arquivada','Solução','Validação','operational',now(),'confirmed',
   pg_temp.id('admin'),now());
insert into public.case_embeddings(
  service_case_id,organization_id,embedding_model,source_hash,source_text,embedding)
select c, pg_temp.id('org'), 'test', 'hash', 'text',
       array_fill(0.1::real, array[1536])::vector
from unnest(array[pg_temp.id('case-active'), pg_temp.id('case-archived')]) c;

-- 1. Papel antes do recibo -------------------------------------------------
set local role authenticated;
select pg_temp.actor('admin');
select lives_ok($q$
  select public.apply_offline_operation(
    pg_temp.id('op'),'customer',pg_temp.id('customer'),
    'upsert','{"name":"Customer H2"}'::jsonb,0)
$q$,'administrador aplica a operação');
select is(
  (select public.apply_offline_operation(
     pg_temp.id('op'),'customer',pg_temp.id('customer'),
     'upsert','{"name":"Customer H2"}'::jsonb,0) ->> 'status'),
  'duplicate','quem pode gravar recebe o recibo ao reenviar');

select pg_temp.actor('viewer');
select throws_ok($q$
  select public.apply_offline_operation(
    pg_temp.id('op'),'customer',pg_temp.id('customer'),
    'upsert','{"name":"Customer H2"}'::jsonb,0)
$q$,'42501',null,'Consulta não recebe o recibo de operação já aplicada');

-- 2. Exclusão direta só do administrador ----------------------------------
select pg_temp.actor('technician');
with changed as (delete from public.service_cases
  where id=pg_temp.id('case-archived') returning 1)
select is((select count(*) from changed),0::bigint,'técnico não exclui atendimento direto');
with changed as (delete from public.equipments
  where id=pg_temp.id('equipment') returning 1)
select is((select count(*) from changed),0::bigint,'técnico não exclui equipamento direto');
with changed as (delete from public.sites
  where id=pg_temp.id('site') returning 1)
select is((select count(*) from changed),0::bigint,'técnico não exclui local direto');
with changed as (delete from public.customers
  where id=pg_temp.id('customer') returning 1)
select is((select count(*) from changed),0::bigint,'técnico não exclui cliente direto');
with changed as (update public.customers set notes='ok'
  where id=pg_temp.id('customer') returning 1)
select is((select count(*) from changed),1::bigint,'técnico continua podendo editar');

-- 3. Busca sem arquivados ---------------------------------------------------
select pg_temp.actor('admin');
select is(
  (select array_agg(service_case_id order by service_case_id)
   from public.search_similar_cases(
     array_fill(0.1::real, array[1536])::vector, 'falha')),
  array[pg_temp.id('case-active')],
  'busca devolve só o atendimento ativo');

select pg_temp.actor('admin');
with changed as (delete from public.service_cases
  where id=pg_temp.id('case-archived') returning 1)
select is((select count(*) from changed),1::bigint,'administrador exclui direto');

-- 4. Privilégios de execução -----------------------------------------------
reset role;
select ok(not has_function_privilege('anon',
  'public.bootstrap_organization(text,text,text)','EXECUTE'),
  'anon não executa bootstrap_organization');
select ok(not has_function_privilege('anon',
  'public.current_organization_id()','EXECUTE'),
  'anon não executa current_organization_id');
select ok(has_function_privilege('authenticated',
  'public.current_organization_id()','EXECUTE'),
  'authenticated executa current_organization_id, usada nas políticas');
select ok(has_function_privilege('authenticated',
  'public.bootstrap_organization(text,text,text)','EXECUTE'),
  'authenticated executa bootstrap_organization, usada no cadastro');
select * from finish();
rollback;
