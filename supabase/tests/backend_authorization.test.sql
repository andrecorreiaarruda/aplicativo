-- Integração PostgreSQL/pgTAP. Isolado por transação; não usa contas reais.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();
create function pg_temp.id(label text) returns uuid language sql immutable as $$ select md5('orion-auth-test:' || label)::uuid $$;
create function pg_temp.actor(label text) returns void language sql as $$
 select set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(label), 'role', 'authenticated')::text, true);
$$;
insert into auth.users(id) select pg_temp.id(x) from unnest(array['admin-a','engineer-a','technician-a','manager-a','viewer-a','inactive-a','admin-b']) x;
insert into public.organizations(id,name,slug) values (pg_temp.id('org-a'),'Test A','auth-test-a'),(pg_temp.id('org-b'),'Test B','auth-test-b');
insert into public.profiles(user_id,organization_id,full_name,role,active)
select pg_temp.id(x),pg_temp.id('org-a'),x,split_part(x,'-',1)::public.user_role,true
from unnest(array['admin-a','engineer-a','technician-a','manager-a','viewer-a']) x;
insert into public.profiles(user_id,organization_id,full_name,role,active) values
(pg_temp.id('inactive-a'),pg_temp.id('org-a'),'Inactive','admin',false),
(pg_temp.id('admin-b'),pg_temp.id('org-b'),'Admin B','admin',true);
insert into public.manufacturers(id,organization_id,name) values
(pg_temp.id('maker-a'),pg_temp.id('org-a'),'Maker A'),(pg_temp.id('maker-b'),pg_temp.id('org-b'),'Maker B'),(pg_temp.id('maker-global'),null,'Maker Global');
insert into public.equipment_models(id,organization_id,manufacturer_id,model,modality) values
(pg_temp.id('model-a'),pg_temp.id('org-a'),pg_temp.id('maker-a'),'Model A','Test'),
(pg_temp.id('model-b'),pg_temp.id('org-b'),pg_temp.id('maker-b'),'Model B','Test'),
(pg_temp.id('model-global'),null,pg_temp.id('maker-global'),'Model Global','Test');
insert into public.customers(id,organization_id,name) values (pg_temp.id('customer-a'),pg_temp.id('org-a'),'Customer A'),(pg_temp.id('customer-b'),pg_temp.id('org-b'),'Customer B');
insert into public.sites(id,organization_id,customer_id,name) values
(pg_temp.id('site-a'),pg_temp.id('org-a'),pg_temp.id('customer-a'),'Site A'),
(pg_temp.id('site-b'),pg_temp.id('org-b'),pg_temp.id('customer-b'),'Site B');
insert into public.equipments(id,organization_id,equipment_model_id,site_id,serial_number) values
(pg_temp.id('equipment-a'),pg_temp.id('org-a'),pg_temp.id('model-a'),pg_temp.id('site-a'),'SERIAL-A'),
(pg_temp.id('equipment-b'),pg_temp.id('org-b'),pg_temp.id('model-b'),pg_temp.id('site-b'),'SERIAL-B');
insert into public.service_cases(id,organization_id,equipment_id,reported_failure,created_by) values
(pg_temp.id('case-a'),pg_temp.id('org-a'),pg_temp.id('equipment-a'),'Failure A',pg_temp.id('admin-a')),
(pg_temp.id('case-b'),pg_temp.id('org-b'),pg_temp.id('equipment-b'),'Failure B',pg_temp.id('admin-b'));
insert into public.diagnostic_steps(id,organization_id,service_case_id,sequence_number,action,result,created_by)
values (pg_temp.id('step-a'),pg_temp.id('org-a'),pg_temp.id('case-a'),1,'Test','Test',pg_temp.id('admin-a'));
insert into public.service_progress_entries(id,organization_id,service_case_id,description,created_by)
values (pg_temp.id('progress-a'),pg_temp.id('org-a'),pg_temp.id('case-a'),'Test',pg_temp.id('admin-a'));
insert into public.case_attachments(id,organization_id,service_case_id,equipment_id,storage_path,file_name,mime_type,size_bytes,uploaded_by)
values (pg_temp.id('attachment-a'),pg_temp.id('org-a'),pg_temp.id('case-a'),pg_temp.id('equipment-a'),'test','test','text/plain',1,pg_temp.id('admin-a'));
insert into public.ai_queries(id,organization_id,user_id,query_text)
values (pg_temp.id('query-a'),pg_temp.id('org-a'),pg_temp.id('admin-a'),'Test query');
insert into public.ai_feedback(id,organization_id,ai_query_id,user_id)
values (pg_temp.id('feedback-a'),pg_temp.id('org-a'),pg_temp.id('query-a'),pg_temp.id('admin-a'));
insert into public.service_order_templates(id,organization_id,customer_id,name)
values (pg_temp.id('template-a'),pg_temp.id('org-a'),pg_temp.id('customer-a'),'Test template');
insert into storage.objects(id,bucket_id,name) values
(pg_temp.id('object-a'),'service-attachments',pg_temp.id('org-a')::text || '/test.txt');

-- Reutiliza o contrato público real. Os payloads têm relações válidas de A.
create function pg_temp.replay(kind text, label text, operation_label text default null)
returns jsonb language plpgsql as $$
declare payload jsonb;
begin
 payload := case kind
 when 'customer' then jsonb_build_object('name',label)
 when 'site' then jsonb_build_object('name',label,'customer_id',pg_temp.id('customer-a'))
 when 'equipment_model' then jsonb_build_object('manufacturer','Maker Global','model',label,'modality','Test')
 when 'equipment' then jsonb_build_object('equipment_model_id',pg_temp.id('model-global'),'serial_number',label)
 when 'service_case' then jsonb_build_object('equipment_id',pg_temp.id('equipment-a'),'reported_failure',label,'status','open')
 end;
 return public.apply_offline_operation(pg_temp.id(coalesce(operation_label,'op-'||label)),kind,pg_temp.id(label),'upsert',payload,0);
end;
$$;
set local role authenticated;
select pg_temp.actor('viewer-a');
select is((select count(*) from public.customers where id=pg_temp.id('customer-a')),1::bigint,'viewer can read customers');
with changed as (update public.customers set id=id where id=pg_temp.id('customer-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update customers');
with changed as (delete from public.customers where id=pg_temp.id('customer-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete customers');
select is((select count(*) from public.sites where id=pg_temp.id('site-a')),1::bigint,'viewer can read sites');
with changed as (update public.sites set id=id where id=pg_temp.id('site-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update sites');
with changed as (delete from public.sites where id=pg_temp.id('site-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete sites');
select is((select count(*) from public.equipments where id=pg_temp.id('equipment-a')),1::bigint,'viewer can read equipments');
with changed as (update public.equipments set id=id where id=pg_temp.id('equipment-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update equipments');
with changed as (delete from public.equipments where id=pg_temp.id('equipment-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete equipments');
select is((select count(*) from public.service_cases where id=pg_temp.id('case-a')),1::bigint,'viewer can read service_cases');
with changed as (update public.service_cases set id=id where id=pg_temp.id('case-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update service_cases');
with changed as (delete from public.service_cases where id=pg_temp.id('case-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete service_cases');
select is((select count(*) from public.diagnostic_steps where id=pg_temp.id('step-a')),1::bigint,'viewer can read diagnostic_steps');
with changed as (update public.diagnostic_steps set id=id where id=pg_temp.id('step-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update diagnostic_steps');
with changed as (delete from public.diagnostic_steps where id=pg_temp.id('step-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete diagnostic_steps');
select is((select count(*) from public.service_progress_entries where id=pg_temp.id('progress-a')),1::bigint,'viewer can read service_progress_entries');
with changed as (update public.service_progress_entries set id=id where id=pg_temp.id('progress-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update service_progress_entries');
with changed as (delete from public.service_progress_entries where id=pg_temp.id('progress-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete service_progress_entries');
select is((select count(*) from public.case_attachments where id=pg_temp.id('attachment-a')),1::bigint,'viewer can read case_attachments');
with changed as (update public.case_attachments set id=id where id=pg_temp.id('attachment-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update case_attachments');
with changed as (delete from public.case_attachments where id=pg_temp.id('attachment-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete case_attachments');
select is((select count(*) from public.ai_queries where id=pg_temp.id('query-a')),1::bigint,'viewer can read ai_queries');
with changed as (update public.ai_queries set id=id where id=pg_temp.id('query-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update ai_queries');
with changed as (delete from public.ai_queries where id=pg_temp.id('query-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete ai_queries');
select is((select count(*) from public.ai_feedback where id=pg_temp.id('feedback-a')),1::bigint,'viewer can read ai_feedback');
with changed as (update public.ai_feedback set id=id where id=pg_temp.id('feedback-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update ai_feedback');
with changed as (delete from public.ai_feedback where id=pg_temp.id('feedback-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete ai_feedback');
select is((select count(*) from public.manufacturers where id=pg_temp.id('maker-a')),1::bigint,'viewer can read manufacturers');
with changed as (update public.manufacturers set id=id where id=pg_temp.id('maker-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update manufacturers');
with changed as (delete from public.manufacturers where id=pg_temp.id('maker-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete manufacturers');
select is((select count(*) from public.equipment_models where id=pg_temp.id('model-a')),1::bigint,'viewer can read equipment_models');
with changed as (update public.equipment_models set id=id where id=pg_temp.id('model-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update equipment_models');
with changed as (delete from public.equipment_models where id=pg_temp.id('model-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete equipment_models');
select is((select count(*) from public.service_order_templates where id=pg_temp.id('template-a')),1::bigint,'viewer can read service_order_templates');
with changed as (update public.service_order_templates set id=id where id=pg_temp.id('template-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot update service_order_templates');
with changed as (delete from public.service_order_templates where id=pg_temp.id('template-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer cannot delete service_order_templates');
select throws_ok($q$insert into public.customers (id,organization_id,name) values (gen_random_uuid(),pg_temp.id('org-a'),'Viewer customer')$q$, '42501', null, 'viewer cannot insert customers');
select throws_ok($q$insert into public.sites (organization_id,customer_id,name) values (pg_temp.id('org-a'),pg_temp.id('customer-a'),'Viewer site')$q$, '42501', null, 'viewer cannot insert sites');
select throws_ok($q$insert into public.equipments (organization_id,equipment_model_id,serial_number) values (pg_temp.id('org-a'),pg_temp.id('model-global'),'VIEWER')$q$, '42501', null, 'viewer cannot insert equipments');
select throws_ok($q$insert into public.service_cases (organization_id,equipment_id,reported_failure) values (pg_temp.id('org-a'),pg_temp.id('equipment-a'),'Viewer failure')$q$, '42501', null, 'viewer cannot insert service_cases');
select throws_ok($q$insert into public.diagnostic_steps (organization_id,service_case_id,sequence_number,action,result) values (pg_temp.id('org-a'),pg_temp.id('case-a'),2,'Viewer','Viewer')$q$, '42501', null, 'viewer cannot insert diagnostic_steps');
select throws_ok($q$insert into public.service_progress_entries (organization_id,service_case_id,description) values (pg_temp.id('org-a'),pg_temp.id('case-a'),'Viewer')$q$, '42501', null, 'viewer cannot insert service_progress_entries');
select throws_ok($q$insert into public.case_attachments (organization_id,service_case_id,storage_path,file_name,mime_type,size_bytes) values (pg_temp.id('org-a'),pg_temp.id('case-a'),'viewer','viewer','text/plain',1)$q$, '42501', null, 'viewer cannot insert case_attachments');
select throws_ok($q$insert into public.ai_queries (organization_id,query_text) values (pg_temp.id('org-a'),'Viewer query')$q$, '42501', null, 'viewer cannot insert ai_queries');
select throws_ok($q$insert into public.ai_feedback (organization_id,ai_query_id) values (pg_temp.id('org-a'),pg_temp.id('query-a'))$q$, '42501', null, 'viewer cannot insert ai_feedback');
select throws_ok($q$insert into public.manufacturers (organization_id,name) values (pg_temp.id('org-a'),'Viewer maker')$q$, '42501', null, 'viewer cannot insert manufacturers');
select throws_ok($q$insert into public.equipment_models (organization_id,manufacturer_id,model,modality) values (pg_temp.id('org-a'),pg_temp.id('maker-global'),'Viewer model','Test')$q$, '42501', null, 'viewer cannot insert equipment_models');
select throws_ok($q$insert into public.service_order_templates (organization_id,customer_id,name) values (pg_temp.id('org-a'),pg_temp.id('customer-a'),'Viewer template')$q$, '42501', null, 'viewer cannot insert service_order_templates');
select throws_ok($q$select pg_temp.replay('customer','viewer-customer')$q$, '42501', null, 'viewer RPC denied: customer');
select throws_ok($q$select pg_temp.replay('site','viewer-site')$q$, '42501', null, 'viewer RPC denied: site');
select throws_ok($q$select pg_temp.replay('equipment_model','viewer-equipment_model')$q$, '42501', null, 'viewer RPC denied: equipment_model');
select throws_ok($q$select pg_temp.replay('equipment','viewer-equipment')$q$, '42501', null, 'viewer RPC denied: equipment');
select throws_ok($q$select pg_temp.replay('service_case','viewer-service_case')$q$, '42501', null, 'viewer RPC denied: service_case');
select throws_ok($q$insert into storage.objects(bucket_id,name) values ('service-attachments',pg_temp.id('org-a')::text || '/viewer.txt')$q$, '42501', null, 'viewer storage insert denied');
with changed as (update storage.objects set name=name where id=pg_temp.id('object-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer storage update denied');
-- Emula a configuração interna da Storage API para testar RLS de DELETE.
set local storage.allow_delete_query = 'true';
with changed as (delete from storage.objects where id=pg_temp.id('object-a') returning 1) select is((select count(*) from changed), 0::bigint, 'viewer storage delete denied');
select ok(not has_table_privilege('authenticated','public.customers','TRUNCATE'),'client cannot bypass RLS with TRUNCATE');

select pg_temp.actor('technician-a');
select lives_ok($q$insert into public.customers(organization_id,name) values (pg_temp.id('org-a'),'technician-direct')$q$, 'technician direct create allowed');
with changed as (update public.customers set notes='edited' where name='technician-direct' returning 1) select is((select count(*) from changed),1::bigint,'technician direct update allowed');
with changed as (delete from public.customers where name='technician-direct' returning 1) select is((select count(*) from changed),1::bigint,'technician direct delete allowed');
select lives_ok($q$select pg_temp.replay('customer','technician-customer')$q$, 'technician RPC can create customer');
select lives_ok($q$select pg_temp.replay('customer','technician-customer','edit-technician-customer')$q$, 'technician RPC can update customer');
select lives_ok($q$select pg_temp.replay('site','technician-site')$q$, 'technician RPC can create site');
select lives_ok($q$select pg_temp.replay('site','technician-site','edit-technician-site')$q$, 'technician RPC can update site');
select lives_ok($q$select pg_temp.replay('equipment_model','technician-equipment_model')$q$, 'technician RPC can create equipment_model');
select throws_ok($q$select pg_temp.replay('equipment_model','technician-equipment_model','edit-technician-equipment_model')$q$, '42501', null, 'technician cannot edit catalog via RPC');
select lives_ok($q$select pg_temp.replay('equipment','technician-equipment')$q$, 'technician RPC can create equipment');
select lives_ok($q$select pg_temp.replay('equipment','technician-equipment','edit-technician-equipment')$q$, 'technician RPC can update equipment');
select lives_ok($q$select pg_temp.replay('service_case','technician-service_case')$q$, 'technician RPC can create service_case');
select lives_ok($q$select pg_temp.replay('service_case','technician-service_case','edit-technician-service_case')$q$, 'technician RPC can update service_case');
select is((select count(*) from public.customers where id=pg_temp.id('customer-b')),0::bigint,'technician cannot read B customers');
with changed as (update public.customers set id=id where id=pg_temp.id('customer-b') returning 1) select is((select count(*) from changed), 0::bigint, 'technician cannot update B customers directly');
select throws_ok($q$select pg_temp.replay('customer','customer-b','attack-technician-customer')$q$, '42501', null, 'technician cannot overwrite B customer via RPC');
select is((select count(*) from public.sites where id=pg_temp.id('site-b')),0::bigint,'technician cannot read B sites');
with changed as (update public.sites set id=id where id=pg_temp.id('site-b') returning 1) select is((select count(*) from changed), 0::bigint, 'technician cannot update B sites directly');
select throws_ok($q$select pg_temp.replay('site','site-b','attack-technician-site')$q$, '42501', null, 'technician cannot overwrite B site via RPC');
select is((select count(*) from public.equipments where id=pg_temp.id('equipment-b')),0::bigint,'technician cannot read B equipments');
with changed as (update public.equipments set id=id where id=pg_temp.id('equipment-b') returning 1) select is((select count(*) from changed), 0::bigint, 'technician cannot update B equipments directly');
select throws_ok($q$select pg_temp.replay('equipment','equipment-b','attack-technician-equipment')$q$, '42501', null, 'technician cannot overwrite B equipment via RPC');
select is((select count(*) from public.service_cases where id=pg_temp.id('case-b')),0::bigint,'technician cannot read B service_cases');
with changed as (update public.service_cases set id=id where id=pg_temp.id('case-b') returning 1) select is((select count(*) from changed), 0::bigint, 'technician cannot update B service_cases directly');
select throws_ok($q$select pg_temp.replay('service_case','case-b','attack-technician-case')$q$, '42501', null, 'technician cannot overwrite B service_case via RPC');
select is((select count(*) from public.equipment_models where id=pg_temp.id('model-b')),0::bigint,'technician cannot read B equipment_models');
with changed as (update public.equipment_models set id=id where id=pg_temp.id('model-b') returning 1) select is((select count(*) from changed), 0::bigint, 'technician cannot update B equipment_models directly');
select throws_ok($q$select pg_temp.replay('equipment_model','model-b','attack-technician-model')$q$, '42501', null, 'technician cannot overwrite B equipment_model via RPC');
select throws_ok($q$select pg_temp.replay('equipment_model','model-global','global-technician')$q$, '42501', null, 'technician cannot overwrite global catalog');

select pg_temp.actor('manager-a');
select lives_ok($q$insert into public.customers(organization_id,name) values (pg_temp.id('org-a'),'manager-direct')$q$, 'manager direct create allowed');
with changed as (update public.customers set notes='edited' where name='manager-direct' returning 1) select is((select count(*) from changed),1::bigint,'manager direct update allowed');
with changed as (delete from public.customers where name='manager-direct' returning 1) select is((select count(*) from changed),1::bigint,'manager direct delete allowed');
select lives_ok($q$select pg_temp.replay('customer','manager-customer')$q$, 'manager RPC can create customer');
select lives_ok($q$select pg_temp.replay('customer','manager-customer','edit-manager-customer')$q$, 'manager RPC can update customer');
select lives_ok($q$select pg_temp.replay('site','manager-site')$q$, 'manager RPC can create site');
select lives_ok($q$select pg_temp.replay('site','manager-site','edit-manager-site')$q$, 'manager RPC can update site');
select lives_ok($q$select pg_temp.replay('equipment_model','manager-equipment_model')$q$, 'manager RPC can create equipment_model');
select throws_ok($q$select pg_temp.replay('equipment_model','manager-equipment_model','edit-manager-equipment_model')$q$, '42501', null, 'manager cannot edit catalog via RPC');
select lives_ok($q$select pg_temp.replay('equipment','manager-equipment')$q$, 'manager RPC can create equipment');
select lives_ok($q$select pg_temp.replay('equipment','manager-equipment','edit-manager-equipment')$q$, 'manager RPC can update equipment');
select lives_ok($q$select pg_temp.replay('service_case','manager-service_case')$q$, 'manager RPC can create service_case');
select lives_ok($q$select pg_temp.replay('service_case','manager-service_case','edit-manager-service_case')$q$, 'manager RPC can update service_case');
select is((select count(*) from public.customers where id=pg_temp.id('customer-b')),0::bigint,'manager cannot read B customers');
with changed as (update public.customers set id=id where id=pg_temp.id('customer-b') returning 1) select is((select count(*) from changed), 0::bigint, 'manager cannot update B customers directly');
select throws_ok($q$select pg_temp.replay('customer','customer-b','attack-manager-customer')$q$, '42501', null, 'manager cannot overwrite B customer via RPC');
select is((select count(*) from public.sites where id=pg_temp.id('site-b')),0::bigint,'manager cannot read B sites');
with changed as (update public.sites set id=id where id=pg_temp.id('site-b') returning 1) select is((select count(*) from changed), 0::bigint, 'manager cannot update B sites directly');
select throws_ok($q$select pg_temp.replay('site','site-b','attack-manager-site')$q$, '42501', null, 'manager cannot overwrite B site via RPC');
select is((select count(*) from public.equipments where id=pg_temp.id('equipment-b')),0::bigint,'manager cannot read B equipments');
with changed as (update public.equipments set id=id where id=pg_temp.id('equipment-b') returning 1) select is((select count(*) from changed), 0::bigint, 'manager cannot update B equipments directly');
select throws_ok($q$select pg_temp.replay('equipment','equipment-b','attack-manager-equipment')$q$, '42501', null, 'manager cannot overwrite B equipment via RPC');
select is((select count(*) from public.service_cases where id=pg_temp.id('case-b')),0::bigint,'manager cannot read B service_cases');
with changed as (update public.service_cases set id=id where id=pg_temp.id('case-b') returning 1) select is((select count(*) from changed), 0::bigint, 'manager cannot update B service_cases directly');
select throws_ok($q$select pg_temp.replay('service_case','case-b','attack-manager-case')$q$, '42501', null, 'manager cannot overwrite B service_case via RPC');
select is((select count(*) from public.equipment_models where id=pg_temp.id('model-b')),0::bigint,'manager cannot read B equipment_models');
with changed as (update public.equipment_models set id=id where id=pg_temp.id('model-b') returning 1) select is((select count(*) from changed), 0::bigint, 'manager cannot update B equipment_models directly');
select throws_ok($q$select pg_temp.replay('equipment_model','model-b','attack-manager-model')$q$, '42501', null, 'manager cannot overwrite B equipment_model via RPC');
select throws_ok($q$select pg_temp.replay('equipment_model','model-global','global-manager')$q$, '42501', null, 'manager cannot overwrite global catalog');

select pg_temp.actor('engineer-a');
select lives_ok($q$insert into public.customers(organization_id,name) values (pg_temp.id('org-a'),'engineer-direct')$q$, 'engineer direct create allowed');
with changed as (update public.customers set notes='edited' where name='engineer-direct' returning 1) select is((select count(*) from changed),1::bigint,'engineer direct update allowed');
with changed as (delete from public.customers where name='engineer-direct' returning 1) select is((select count(*) from changed),1::bigint,'engineer direct delete allowed');
select lives_ok($q$select pg_temp.replay('customer','engineer-customer')$q$, 'engineer RPC can create customer');
select lives_ok($q$select pg_temp.replay('customer','engineer-customer','edit-engineer-customer')$q$, 'engineer RPC can update customer');
select lives_ok($q$select pg_temp.replay('site','engineer-site')$q$, 'engineer RPC can create site');
select lives_ok($q$select pg_temp.replay('site','engineer-site','edit-engineer-site')$q$, 'engineer RPC can update site');
select lives_ok($q$select pg_temp.replay('equipment_model','engineer-equipment_model')$q$, 'engineer RPC can create equipment_model');
select lives_ok($q$select pg_temp.replay('equipment_model','engineer-equipment_model','edit-engineer-equipment_model')$q$, 'engineer RPC can update equipment_model');
select lives_ok($q$select pg_temp.replay('equipment','engineer-equipment')$q$, 'engineer RPC can create equipment');
select lives_ok($q$select pg_temp.replay('equipment','engineer-equipment','edit-engineer-equipment')$q$, 'engineer RPC can update equipment');
select lives_ok($q$select pg_temp.replay('service_case','engineer-service_case')$q$, 'engineer RPC can create service_case');
select lives_ok($q$select pg_temp.replay('service_case','engineer-service_case','edit-engineer-service_case')$q$, 'engineer RPC can update service_case');
select is((select count(*) from public.customers where id=pg_temp.id('customer-b')),0::bigint,'engineer cannot read B customers');
with changed as (update public.customers set id=id where id=pg_temp.id('customer-b') returning 1) select is((select count(*) from changed), 0::bigint, 'engineer cannot update B customers directly');
select throws_ok($q$select pg_temp.replay('customer','customer-b','attack-engineer-customer')$q$, '42501', null, 'engineer cannot overwrite B customer via RPC');
select is((select count(*) from public.sites where id=pg_temp.id('site-b')),0::bigint,'engineer cannot read B sites');
with changed as (update public.sites set id=id where id=pg_temp.id('site-b') returning 1) select is((select count(*) from changed), 0::bigint, 'engineer cannot update B sites directly');
select throws_ok($q$select pg_temp.replay('site','site-b','attack-engineer-site')$q$, '42501', null, 'engineer cannot overwrite B site via RPC');
select is((select count(*) from public.equipments where id=pg_temp.id('equipment-b')),0::bigint,'engineer cannot read B equipments');
with changed as (update public.equipments set id=id where id=pg_temp.id('equipment-b') returning 1) select is((select count(*) from changed), 0::bigint, 'engineer cannot update B equipments directly');
select throws_ok($q$select pg_temp.replay('equipment','equipment-b','attack-engineer-equipment')$q$, '42501', null, 'engineer cannot overwrite B equipment via RPC');
select is((select count(*) from public.service_cases where id=pg_temp.id('case-b')),0::bigint,'engineer cannot read B service_cases');
with changed as (update public.service_cases set id=id where id=pg_temp.id('case-b') returning 1) select is((select count(*) from changed), 0::bigint, 'engineer cannot update B service_cases directly');
select throws_ok($q$select pg_temp.replay('service_case','case-b','attack-engineer-case')$q$, '42501', null, 'engineer cannot overwrite B service_case via RPC');
select is((select count(*) from public.equipment_models where id=pg_temp.id('model-b')),0::bigint,'engineer cannot read B equipment_models');
with changed as (update public.equipment_models set id=id where id=pg_temp.id('model-b') returning 1) select is((select count(*) from changed), 0::bigint, 'engineer cannot update B equipment_models directly');
select throws_ok($q$select pg_temp.replay('equipment_model','model-b','attack-engineer-model')$q$, '42501', null, 'engineer cannot overwrite B equipment_model via RPC');
select throws_ok($q$select pg_temp.replay('equipment_model','model-global','global-engineer')$q$, '42501', null, 'engineer cannot overwrite global catalog');

select pg_temp.actor('admin-a');
select lives_ok($q$insert into public.customers(organization_id,name) values (pg_temp.id('org-a'),'admin-direct')$q$, 'admin direct create allowed');
with changed as (update public.customers set notes='edited' where name='admin-direct' returning 1) select is((select count(*) from changed),1::bigint,'admin direct update allowed');
with changed as (delete from public.customers where name='admin-direct' returning 1) select is((select count(*) from changed),1::bigint,'admin direct delete allowed');
select lives_ok($q$select pg_temp.replay('customer','admin-customer')$q$, 'admin RPC can create customer');
select lives_ok($q$select pg_temp.replay('customer','admin-customer','edit-admin-customer')$q$, 'admin RPC can update customer');
select lives_ok($q$select pg_temp.replay('site','admin-site')$q$, 'admin RPC can create site');
select lives_ok($q$select pg_temp.replay('site','admin-site','edit-admin-site')$q$, 'admin RPC can update site');
select lives_ok($q$select pg_temp.replay('equipment_model','admin-equipment_model')$q$, 'admin RPC can create equipment_model');
select lives_ok($q$select pg_temp.replay('equipment_model','admin-equipment_model','edit-admin-equipment_model')$q$, 'admin RPC can update equipment_model');
select lives_ok($q$select pg_temp.replay('equipment','admin-equipment')$q$, 'admin RPC can create equipment');
select lives_ok($q$select pg_temp.replay('equipment','admin-equipment','edit-admin-equipment')$q$, 'admin RPC can update equipment');
select lives_ok($q$select pg_temp.replay('service_case','admin-service_case')$q$, 'admin RPC can create service_case');
select lives_ok($q$select pg_temp.replay('service_case','admin-service_case','edit-admin-service_case')$q$, 'admin RPC can update service_case');
select is((select count(*) from public.customers where id=pg_temp.id('customer-b')),0::bigint,'admin cannot read B customers');
with changed as (update public.customers set id=id where id=pg_temp.id('customer-b') returning 1) select is((select count(*) from changed), 0::bigint, 'admin cannot update B customers directly');
select throws_ok($q$select pg_temp.replay('customer','customer-b','attack-admin-customer')$q$, '42501', null, 'admin cannot overwrite B customer via RPC');
select is((select count(*) from public.sites where id=pg_temp.id('site-b')),0::bigint,'admin cannot read B sites');
with changed as (update public.sites set id=id where id=pg_temp.id('site-b') returning 1) select is((select count(*) from changed), 0::bigint, 'admin cannot update B sites directly');
select throws_ok($q$select pg_temp.replay('site','site-b','attack-admin-site')$q$, '42501', null, 'admin cannot overwrite B site via RPC');
select is((select count(*) from public.equipments where id=pg_temp.id('equipment-b')),0::bigint,'admin cannot read B equipments');
with changed as (update public.equipments set id=id where id=pg_temp.id('equipment-b') returning 1) select is((select count(*) from changed), 0::bigint, 'admin cannot update B equipments directly');
select throws_ok($q$select pg_temp.replay('equipment','equipment-b','attack-admin-equipment')$q$, '42501', null, 'admin cannot overwrite B equipment via RPC');
select is((select count(*) from public.service_cases where id=pg_temp.id('case-b')),0::bigint,'admin cannot read B service_cases');
with changed as (update public.service_cases set id=id where id=pg_temp.id('case-b') returning 1) select is((select count(*) from changed), 0::bigint, 'admin cannot update B service_cases directly');
select throws_ok($q$select pg_temp.replay('service_case','case-b','attack-admin-case')$q$, '42501', null, 'admin cannot overwrite B service_case via RPC');
select is((select count(*) from public.equipment_models where id=pg_temp.id('model-b')),0::bigint,'admin cannot read B equipment_models');
with changed as (update public.equipment_models set id=id where id=pg_temp.id('model-b') returning 1) select is((select count(*) from changed), 0::bigint, 'admin cannot update B equipment_models directly');
select throws_ok($q$select pg_temp.replay('equipment_model','model-b','attack-admin-model')$q$, '42501', null, 'admin cannot overwrite B equipment_model via RPC');
select throws_ok($q$select pg_temp.replay('equipment_model','model-global','global-admin')$q$, '42501', null, 'admin cannot overwrite global catalog');

select pg_temp.actor('admin-a');
select lives_ok($q$select pg_temp.replay('customer','admin-customer')$q$, 'duplicate replay remains valid');
select is((pg_temp.replay('customer','admin-customer')->>'status'),'duplicate','receipt returns duplicate');
select throws_ok($q$insert into public.equipments(organization_id,equipment_model_id,serial_number) values (pg_temp.id('org-a'),pg_temp.id('model-b'),'FOREIGN-MODEL')$q$, '42501', null, 'direct insert cannot reference B model');
select throws_ok($q$select public.apply_offline_operation(gen_random_uuid(),'equipment',gen_random_uuid(),'upsert',jsonb_build_object('equipment_model_id',pg_temp.id('model-b'),'serial_number','FOREIGN-MODEL-RPC'),0)$q$, '42501', null, 'RPC cannot reference B model');
select throws_ok($q$insert into public.case_attachments(organization_id,service_case_id,equipment_id,storage_path,file_name,mime_type,size_bytes) values (pg_temp.id('org-a'),pg_temp.id('case-a'),pg_temp.id('equipment-b'),'mixed','mixed','text/plain',1)$q$, '42501', null, 'both attachment parents must belong to A');
select ok(not has_table_privilege('authenticated','public.sync_operation_receipts','INSERT'),'client cannot forge sync_operation_receipts');
select ok(not has_table_privilege('authenticated','public.audit_logs','INSERT'),'client cannot forge audit_logs');
select ok(not has_table_privilege('authenticated','public.case_embeddings','INSERT'),'client cannot forge case_embeddings');
select throws_ok($q$update public.customers set organization_id=pg_temp.id('org-b') where id=pg_temp.id('customer-a')$q$, '42501', null, 'direct update cannot move a customer into B');
select throws_ok($q$insert into public.sites(organization_id,customer_id,name) values (pg_temp.id('org-a'),pg_temp.id('customer-b'),'Foreign parent')$q$, '42501', null, 'site cannot reference foreign customer');
select throws_ok($q$insert into public.service_cases(organization_id,equipment_id,reported_failure) values (pg_temp.id('org-a'),pg_temp.id('equipment-b'),'Foreign equipment')$q$, '42501', null, 'case cannot reference foreign equipment');

select is((public.apply_offline_operation(
  pg_temp.id('stale-op'),'customer',pg_temp.id('admin-customer'),'upsert',
  '{"name":"stale change"}'::jsonb,999)->>'status'),'conflict','stale revision still records conflict');
select lives_ok($q$
  select public.apply_offline_operation(
    pg_temp.id('resolved-op'),'service_case',pg_temp.id('resolved-case'),'upsert',
    jsonb_build_object(
      'equipment_id',pg_temp.id('equipment-a'),'reported_failure','Resolved test',
      'status','resolved','opened_at','2026-09-07T10:00:00Z','closed_at','2026-09-07T10:10:00Z',
      'operational_impact','total_stop','solution_details','Fixed','validation_result','Validated',
      'final_equipment_status','operational','service_minutes',999,
      'progress_entries',jsonb_build_array(jsonb_build_object(
        'id',pg_temp.id('resolved-entry'),'occurred_at','2026-09-07T10:00:00Z',
        'ended_at','2026-09-07T10:10:00Z','description','Work session'
      ))
    ),0
  )
$q$,'resolved case and work session still save');
select is((select service_minutes from public.service_cases where id=pg_temp.id('resolved-case')),10,'server still derives service minutes');
select is((select downtime_minutes from public.service_cases where id=pg_temp.id('resolved-case')),10,'server still derives downtime');
select pg_temp.actor('inactive-a');
select throws_ok($q$select pg_temp.replay('customer','inactive-customer')$q$, '42501', null, 'inactive user cannot replay');
select is((select count(*) from public.customers),0::bigint,'inactive user has no tenant rows');
select pg_temp.actor('viewer-a');
select throws_ok($q$select pg_temp.replay('customer','admin-customer')$q$, '42501', null, 'viewer cannot replay an existing receipt');
set local role anon;
select throws_ok($q$select pg_temp.replay('customer','anonymous-customer')$q$, '42501', null, 'anonymous RPC denied');
select throws_ok($q$select * from public.customers$q$, '42501', null, 'anonymous table access denied');
reset role;
select is((select name from public.customers where id=pg_temp.id('customer-b')),'Customer B','B customer unchanged after all attacks');
select is((select model from public.equipment_models where id=pg_temp.id('model-global')),'Model Global','global model unchanged');
select * from finish();
rollback;
