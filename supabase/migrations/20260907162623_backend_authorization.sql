-- ORION 0.5.0: primeira entrega de autorização do backend.
-- Gerada por supabase db pull após validação em PostgreSQL local.
-- Não expor orion_private na configuração da Data API.
-- Ao final, os grants são declarados explicitamente para não depender
-- dos privilégios padrão do projeto onde esta migration for aplicada.

SET local check_function_bodies = off;

REVOKE ALL ON TABLE "public"."ai_feedback" FROM "anon";

REVOKE ALL ON TABLE "public"."ai_queries" FROM "anon";

REVOKE ALL ON TABLE "public"."audit_logs" FROM "anon";

REVOKE ALL ON TABLE "public"."case_attachments" FROM "anon";

REVOKE ALL ON TABLE "public"."case_embeddings" FROM "anon";

REVOKE ALL ON TABLE "public"."customers" FROM "anon";

REVOKE ALL ON TABLE "public"."diagnostic_steps" FROM "anon";

REVOKE ALL ON TABLE "public"."equipment_models" FROM "anon";

REVOKE ALL ON TABLE "public"."equipments" FROM "anon";

REVOKE ALL ON TABLE "public"."manufacturers" FROM "anon";

REVOKE ALL ON TABLE "public"."organizations" FROM "anon";

REVOKE ALL ON TABLE "public"."profiles" FROM "anon";

REVOKE ALL ON TABLE "public"."service_cases" FROM "anon";

REVOKE ALL ON TABLE "public"."service_order_templates" FROM "anon";

REVOKE ALL ON TABLE "public"."service_progress_entries" FROM "anon";

REVOKE ALL ON TABLE "public"."sites" FROM "anon";

REVOKE ALL ON TABLE "public"."sync_conflicts" FROM "anon";

REVOKE ALL ON TABLE "public"."sync_operation_receipts" FROM "anon";

DROP POLICY "ai_feedback_tenant_access" ON "public"."ai_feedback";

DROP POLICY "ai_queries_tenant_access" ON "public"."ai_queries";

DROP POLICY "attachments_tenant_access" ON "public"."case_attachments";

DROP POLICY "customers_tenant_access" ON "public"."customers";

DROP POLICY "diagnostic_steps_tenant_access" ON "public"."diagnostic_steps";

DROP POLICY "equipment_models_insert_own" ON "public"."equipment_models";

DROP POLICY "equipment_models_visible" ON "public"."equipment_models";

DROP POLICY "equipments_tenant_access" ON "public"."equipments";

DROP POLICY "manufacturers_insert_own" ON "public"."manufacturers";

DROP POLICY "manufacturers_visible" ON "public"."manufacturers";

DROP POLICY "service_cases_tenant_access" ON "public"."service_cases";

DROP POLICY "service_order_templates_insert_own" ON "public"."service_order_templates";

DROP POLICY "service_progress_entries_tenant_access" ON "public"."service_progress_entries";

DROP POLICY "sites_tenant_access" ON "public"."sites";

DROP POLICY "service_attachments_delete_own_org" ON "storage"."objects";

DROP POLICY "service_attachments_insert_own_org" ON "storage"."objects";

DROP POLICY "service_attachments_update_own_org" ON "storage"."objects";

DROP FUNCTION "public"."apply_offline_operation"(uuid, text, uuid, text, jsonb, bigint);

CREATE SCHEMA "orion_private";

CREATE OR REPLACE FUNCTION orion_private.apply_offline_operation (
  p_operation_id      uuid,
  p_entity_type       text,
  p_entity_id         uuid,
  p_operation         text,
  p_payload           jsonb,
  p_expected_revision bigint DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_org uuid := public.current_organization_id();
  v_user uuid := auth.uid();
  v_role public.user_role := public.current_user_role();
  v_current_revision bigint;
  v_result jsonb;
  v_service_minutes integer;
  v_downtime_minutes integer;
  v_existing_service_minutes integer;
  v_existing_downtime_minutes integer;
  v_payload_entry_count integer;
  v_opened_at timestamptz;
  v_closed_at timestamptz;
  v_impact public.operational_impact;
  v_server_payload jsonb;
  v_conflict_id uuid;
  v_manufacturer_id uuid;
  v_entry jsonb;
begin
  if v_user is null or v_org is null then
    raise exception 'Authenticated organization context is required' using errcode = '42501';
  end if;

  if v_role is null or v_role not in ('admin', 'engineer', 'technician', 'manager') then
    raise exception 'Write permission is required' using errcode = '42501';
  end if;

  if p_operation <> 'upsert' then
    raise exception 'Unsupported offline operation: %', p_operation;
  end if;

  select result into v_result
  from public.sync_operation_receipts
  where operation_id = p_operation_id
    and organization_id = v_org;

  if found then
    return v_result || jsonb_build_object('status', 'duplicate');
  end if;

  if p_entity_type = 'customer' then
    select sync_revision, to_jsonb(c)
      into v_current_revision, v_server_payload
    from public.customers c
    where c.id = p_entity_id and c.organization_id = v_org;

    if found and coalesce(p_expected_revision, 0) > 0
       and v_current_revision <> p_expected_revision then
      insert into public.sync_conflicts (
        organization_id, operation_id, entity_type, entity_id,
        expected_revision, server_revision, client_payload,
        server_payload, created_by
      ) values (
        v_org, p_operation_id, p_entity_type, p_entity_id,
        p_expected_revision, v_current_revision, p_payload,
        v_server_payload, v_user
      )
      on conflict (organization_id, operation_id) do update
        set client_payload = excluded.client_payload,
            server_payload = excluded.server_payload,
            server_revision = excluded.server_revision
      returning id into v_conflict_id;

      return jsonb_build_object(
        'status', 'conflict',
        'conflict_id', v_conflict_id,
        'revision', v_current_revision,
        'message', 'O cliente foi alterado em outro dispositivo.'
      );
    end if;

    insert into public.customers (
      id, organization_id, name, tax_id, contact_name, email, phone,
      address_line, city, state, notes, client_updated_at, deleted_at
    ) values (
      p_entity_id, v_org, trim(p_payload->>'name'),
      nullif(trim(p_payload->>'tax_id'), ''),
      nullif(trim(p_payload->>'contact_name'), ''),
      nullif(trim(p_payload->>'email'), ''),
      nullif(trim(p_payload->>'phone'), ''),
      nullif(trim(p_payload->>'address_line'), ''),
      nullif(trim(p_payload->>'city'), ''),
      nullif(trim(p_payload->>'state'), ''),
      nullif(trim(p_payload->>'notes'), ''),
      coalesce((p_payload->>'_client_updated_at')::timestamptz, now()),
      null
    )
    on conflict (id) do update set
      name = excluded.name,
      tax_id = excluded.tax_id,
      contact_name = excluded.contact_name,
      email = excluded.email,
      phone = excluded.phone,
      address_line = excluded.address_line,
      city = excluded.city,
      state = excluded.state,
      notes = excluded.notes,
      client_updated_at = excluded.client_updated_at,
      deleted_at = null
    where customers.organization_id = v_org;

    if not found then
      raise exception 'Record is not writable in this organization' using errcode = '42501';
    end if;

    select sync_revision into v_current_revision
    from public.customers where id = p_entity_id;

  elsif p_entity_type = 'site' then
    select sync_revision, to_jsonb(s)
      into v_current_revision, v_server_payload
    from public.sites s
    where s.id = p_entity_id and s.organization_id = v_org;

    if found and coalesce(p_expected_revision, 0) > 0
       and v_current_revision <> p_expected_revision then
      insert into public.sync_conflicts (
        organization_id, operation_id, entity_type, entity_id,
        expected_revision, server_revision, client_payload,
        server_payload, created_by
      ) values (
        v_org, p_operation_id, p_entity_type, p_entity_id,
        p_expected_revision, v_current_revision, p_payload,
        v_server_payload, v_user
      )
      on conflict (organization_id, operation_id) do update
        set client_payload = excluded.client_payload,
            server_payload = excluded.server_payload,
            server_revision = excluded.server_revision
      returning id into v_conflict_id;
      return jsonb_build_object(
        'status', 'conflict', 'conflict_id', v_conflict_id,
        'revision', v_current_revision,
        'message', 'O local foi alterado em outro dispositivo.'
      );
    end if;

    insert into public.sites (
      id, organization_id, customer_id, name, city, state, notes,
      client_updated_at, deleted_at
    ) values (
      p_entity_id, v_org, (p_payload->>'customer_id')::uuid,
      trim(p_payload->>'name'), nullif(trim(p_payload->>'city'), ''),
      nullif(trim(p_payload->>'state'), ''),
      nullif(trim(p_payload->>'notes'), ''),
      coalesce((p_payload->>'_client_updated_at')::timestamptz, now()), null
    )
    on conflict (id) do update set
      customer_id = excluded.customer_id,
      name = excluded.name,
      city = excluded.city,
      state = excluded.state,
      notes = excluded.notes,
      client_updated_at = excluded.client_updated_at,
      deleted_at = null
    where sites.organization_id = v_org;

    if not found then
      raise exception 'Record is not writable in this organization' using errcode = '42501';
    end if;

    select sync_revision into v_current_revision
    from public.sites where id = p_entity_id;

  elsif p_entity_type = 'equipment_model' then
    select id into v_manufacturer_id
    from public.manufacturers
    where lower(name) = lower(trim(p_payload->>'manufacturer'))
      and (organization_id is null or organization_id = v_org)
      and deleted_at is null
    order by (organization_id = v_org) desc nulls last
    limit 1;

    if v_manufacturer_id is null then
      insert into public.manufacturers (
        organization_id, name, client_updated_at
      ) values (
        v_org, trim(p_payload->>'manufacturer'),
        coalesce((p_payload->>'_client_updated_at')::timestamptz, now())
      ) returning id into v_manufacturer_id;
    end if;

    select sync_revision, to_jsonb(em)
      into v_current_revision, v_server_payload
    from public.equipment_models em
    where em.id = p_entity_id
      and (em.organization_id is null or em.organization_id = v_org);

    if found and coalesce(p_expected_revision, 0) > 0
       and v_current_revision <> p_expected_revision then
      insert into public.sync_conflicts (
        organization_id, operation_id, entity_type, entity_id,
        expected_revision, server_revision, client_payload,
        server_payload, created_by
      ) values (
        v_org, p_operation_id, p_entity_type, p_entity_id,
        p_expected_revision, v_current_revision, p_payload,
        v_server_payload, v_user
      )
      on conflict (organization_id, operation_id) do update
        set client_payload = excluded.client_payload,
            server_payload = excluded.server_payload,
            server_revision = excluded.server_revision
      returning id into v_conflict_id;
      return jsonb_build_object(
        'status', 'conflict', 'conflict_id', v_conflict_id,
        'revision', v_current_revision,
        'message', 'O modelo foi alterado em outro dispositivo.'
      );
    end if;

    insert into public.equipment_models (
      id, organization_id, manufacturer_id, family, model, modality,
      description, client_updated_at, deleted_at
    ) values (
      p_entity_id, v_org, v_manufacturer_id,
      nullif(trim(p_payload->>'family'), ''), trim(p_payload->>'model'),
      coalesce(nullif(trim(p_payload->>'modality'), ''), 'Não informada'),
      nullif(trim(p_payload->>'description'), ''),
      coalesce((p_payload->>'_client_updated_at')::timestamptz, now()), null
    )
    on conflict (id) do update set
      manufacturer_id = excluded.manufacturer_id,
      family = excluded.family,
      model = excluded.model,
      modality = excluded.modality,
      description = excluded.description,
      client_updated_at = excluded.client_updated_at,
      deleted_at = null
    where equipment_models.organization_id = v_org and v_role in ('admin', 'engineer');

    if not found then
      raise exception 'Record is not writable in this organization' using errcode = '42501';
    end if;

    select sync_revision into v_current_revision
    from public.equipment_models where id = p_entity_id;

  elsif p_entity_type = 'equipment' then
    select sync_revision, to_jsonb(e)
      into v_current_revision, v_server_payload
    from public.equipments e
    where e.id = p_entity_id and e.organization_id = v_org;

    if found and coalesce(p_expected_revision, 0) > 0
       and v_current_revision <> p_expected_revision then
      insert into public.sync_conflicts (
        organization_id, operation_id, entity_type, entity_id,
        expected_revision, server_revision, client_payload,
        server_payload, created_by
      ) values (
        v_org, p_operation_id, p_entity_type, p_entity_id,
        p_expected_revision, v_current_revision, p_payload,
        v_server_payload, v_user
      )
      on conflict (organization_id, operation_id) do update
        set client_payload = excluded.client_payload,
            server_payload = excluded.server_payload,
            server_revision = excluded.server_revision
      returning id into v_conflict_id;
      return jsonb_build_object(
        'status', 'conflict', 'conflict_id', v_conflict_id,
        'revision', v_current_revision,
        'message', 'O equipamento foi alterado em outro dispositivo.'
      );
    end if;

    insert into public.equipments (
      id, organization_id, equipment_model_id, site_id, serial_number,
      software_version, hardware_version, status, notes, created_by,
      client_updated_at, deleted_at
    ) values (
      p_entity_id, v_org, (p_payload->>'equipment_model_id')::uuid,
      nullif(p_payload->>'site_id', '')::uuid,
      trim(p_payload->>'serial_number'),
      nullif(trim(p_payload->>'software_version'), ''),
      nullif(trim(p_payload->>'hardware_version'), ''),
      coalesce(nullif(p_payload->>'status', ''), 'operational')::public.equipment_status,
      nullif(trim(p_payload->>'notes'), ''), v_user,
      coalesce((p_payload->>'_client_updated_at')::timestamptz, now()), null
    )
    on conflict (id) do update set
      equipment_model_id = excluded.equipment_model_id,
      site_id = excluded.site_id,
      serial_number = excluded.serial_number,
      software_version = excluded.software_version,
      hardware_version = excluded.hardware_version,
      status = excluded.status,
      notes = excluded.notes,
      client_updated_at = excluded.client_updated_at,
      deleted_at = null
    where equipments.organization_id = v_org;

    if not found then
      raise exception 'Record is not writable in this organization' using errcode = '42501';
    end if;

    select sync_revision into v_current_revision
    from public.equipments where id = p_entity_id;

  elsif p_entity_type = 'service_case' then
    select sync_revision, to_jsonb(sc), sc.service_minutes, sc.downtime_minutes
      into v_current_revision, v_server_payload,
           v_existing_service_minutes, v_existing_downtime_minutes
    from public.service_cases sc
    where sc.id = p_entity_id and sc.organization_id = v_org;

    if found and coalesce(p_expected_revision, 0) > 0
       and v_current_revision <> p_expected_revision then
      insert into public.sync_conflicts (
        organization_id, operation_id, entity_type, entity_id,
        expected_revision, server_revision, client_payload,
        server_payload, created_by
      ) values (
        v_org, p_operation_id, p_entity_type, p_entity_id,
        p_expected_revision, v_current_revision, p_payload,
        v_server_payload, v_user
      )
      on conflict (organization_id, operation_id) do update
        set client_payload = excluded.client_payload,
            server_payload = excluded.server_payload,
            server_revision = excluded.server_revision
      returning id into v_conflict_id;
      return jsonb_build_object(
        'status', 'conflict', 'conflict_id', v_conflict_id,
        'revision', v_current_revision,
        'message', 'O atendimento foi alterado em outro dispositivo.'
      );
    end if;

    -- Defesa em profundidade: a UI já impede concluir um atendimento
    -- com uma sessão de diário em aberto, mas como o tempo técnico
    -- calculado a partir dessas sessões alimenta as métricas de
    -- qualidade do serviço, recusamos aqui também.
    if coalesce(nullif(p_payload->>'status', ''), 'open') = 'resolved'
       and exists (
         select 1
         from jsonb_array_elements(
           coalesce(p_payload->'progress_entries', '[]'::jsonb)
         ) as entry
         where nullif(trim(entry->>'description'), '') is not null
           and nullif(entry->>'ended_at', '') is null
       )
    then
      raise exception
        'Não é possível concluir um atendimento com sessão de trabalho em aberto no diário.';
    end if;

    -- Tempos derivados no SERVIDOR. Os valores de downtime_minutes /
    -- service_minutes que venham no payload são ignorados de propósito:
    -- este recálculo é a fonte da verdade. A ponderação por impacto
    -- abaixo não existe em nenhum outro lugar do projeto.
    v_opened_at := coalesce((p_payload->>'opened_at')::timestamptz, now());
    v_closed_at := nullif(p_payload->>'closed_at', '')::timestamptz;
    v_impact := coalesce(
      nullif(p_payload->>'operational_impact', ''), 'degraded'
    )::public.operational_impact;

    -- Quantas sessões o payload traz. Um payload SEM nenhuma sessão não
    -- significa "zero minutos trabalhados": significa que este cliente não
    -- tem diário para enviar — caso de atendimentos antigos, criados
    -- quando o tempo era digitado à mão. Recalcular para 0 nessa situação
    -- apagaria o histórico na primeira edição, então preserva-se o valor
    -- já gravado.
    select count(*)
    into v_payload_entry_count
    from jsonb_array_elements(
      coalesce(p_payload->'progress_entries', '[]'::jsonb)
    ) as entry
    where nullif(trim(entry->>'description'), '') is not null;

    if v_payload_entry_count = 0 then
      v_service_minutes := v_existing_service_minutes;
    else
      select coalesce(sum(
        floor(
          extract(epoch from (
            (entry->>'ended_at')::timestamptz
            - (entry->>'occurred_at')::timestamptz
          )) / 60
        )
      ), 0)::integer
      into v_service_minutes
      from jsonb_array_elements(
        coalesce(p_payload->'progress_entries', '[]'::jsonb)
      ) as entry
      where nullif(trim(entry->>'description'), '') is not null
        and nullif(entry->>'ended_at', '') is not null;
    end if;

    -- Enquanto o atendimento não estiver encerrado não há duração para
    -- ponderar. Preserva-se o que já estava gravado em vez de zerar: um
    -- atendimento reaberto para ajuste não deve perder a indisponibilidade
    -- que já havia sido apurada.
    if v_closed_at is null then
      v_downtime_minutes := v_existing_downtime_minutes;
    else
      v_downtime_minutes := greatest(
        round(
          greatest(
            extract(epoch from (v_closed_at - v_opened_at)) / 60,
            0
          )
          * case v_impact
              when 'none' then 0.0
              when 'degraded' then 0.30
              when 'partial_stop' then 0.65
              when 'total_stop' then 1.0
            end
        ),
        0
      )::integer;
    end if;

    insert into public.service_cases (
      id, organization_id, equipment_id, status, activity_type, opened_at,
      closed_at, reported_failure, observed_symptoms, error_code,
      error_message, subsystem, operational_impact, measurements,
      root_cause, solution_details, validation_result,
      final_equipment_status, solution_confidence, downtime_minutes,
      service_minutes, requires_follow_up, follow_up_notes, safety_notes,
      created_by, updated_by, client_updated_at, deleted_at
    ) values (
      p_entity_id, v_org, (p_payload->>'equipment_id')::uuid,
      coalesce(nullif(p_payload->>'status', ''), 'open')::public.case_status,
      coalesce(nullif(p_payload->>'activity_type', ''), 'maintenance'),
      v_opened_at,
      v_closed_at,
      trim(p_payload->>'reported_failure'),
      nullif(trim(p_payload->>'observed_symptoms'), ''),
      nullif(trim(p_payload->>'error_code'), ''),
      nullif(trim(p_payload->>'error_message'), ''),
      nullif(trim(p_payload->>'subsystem'), ''),
      coalesce(nullif(p_payload->>'operational_impact', ''), 'degraded')::public.operational_impact,
      nullif(trim(p_payload->>'measurements'), ''),
      nullif(trim(p_payload->>'root_cause'), ''),
      nullif(trim(p_payload->>'solution_details'), ''),
      nullif(trim(p_payload->>'validation_result'), ''),
      nullif(p_payload->>'final_equipment_status', '')::public.equipment_status,
      coalesce(nullif(p_payload->>'solution_confidence', ''), 'unconfirmed')::public.solution_confidence,
      v_downtime_minutes,
      v_service_minutes,
      coalesce((p_payload->>'requires_follow_up')::boolean, false),
      nullif(trim(p_payload->>'follow_up_notes'), ''),
      nullif(trim(p_payload->>'safety_notes'), ''),
      v_user, v_user,
      coalesce((p_payload->>'_client_updated_at')::timestamptz, now()), null
    )
    on conflict (id) do update set
      equipment_id = excluded.equipment_id,
      status = excluded.status,
      activity_type = excluded.activity_type,
      opened_at = excluded.opened_at,
      closed_at = excluded.closed_at,
      reported_failure = excluded.reported_failure,
      observed_symptoms = excluded.observed_symptoms,
      error_code = excluded.error_code,
      error_message = excluded.error_message,
      subsystem = excluded.subsystem,
      operational_impact = excluded.operational_impact,
      measurements = excluded.measurements,
      root_cause = excluded.root_cause,
      solution_details = excluded.solution_details,
      validation_result = excluded.validation_result,
      final_equipment_status = excluded.final_equipment_status,
      solution_confidence = excluded.solution_confidence,
      downtime_minutes = excluded.downtime_minutes,
      service_minutes = excluded.service_minutes,
      requires_follow_up = excluded.requires_follow_up,
      follow_up_notes = excluded.follow_up_notes,
      safety_notes = excluded.safety_notes,
      updated_by = v_user,
      client_updated_at = excluded.client_updated_at,
      deleted_at = null
    where service_cases.organization_id = v_org;

    if not found then
      raise exception 'Record is not writable in this organization' using errcode = '42501';
    end if;

    delete from public.service_progress_entries
    where service_case_id = p_entity_id and organization_id = v_org;

    for v_entry in
      select value from jsonb_array_elements(
        coalesce(p_payload->'progress_entries', '[]'::jsonb)
      )
    loop
      if nullif(trim(v_entry->>'description'), '') is not null then
        insert into public.service_progress_entries (
          id, organization_id, service_case_id, occurred_at, ended_at,
          description, created_by, client_updated_at
        ) values (
          (v_entry->>'id')::uuid, v_org, p_entity_id,
          coalesce((v_entry->>'occurred_at')::timestamptz, now()),
          nullif(v_entry->>'ended_at', '')::timestamptz,
          trim(v_entry->>'description'), v_user,
          coalesce((p_payload->>'_client_updated_at')::timestamptz, now())
        );
      end if;
    end loop;

    select sync_revision into v_current_revision
    from public.service_cases where id = p_entity_id;

  else
    raise exception 'Unsupported offline entity type: %', p_entity_type;
  end if;

  v_result := jsonb_build_object(
    'status', 'applied',
    'revision', v_current_revision,
    'entity_type', p_entity_type,
    'entity_id', p_entity_id
  );

  insert into public.sync_operation_receipts (
    operation_id, organization_id, entity_type, entity_id,
    result, applied_by
  ) values (
    p_operation_id, v_org, p_entity_type, p_entity_id,
    v_result, v_user
  );

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION orion_private.enforce_parent_scope()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_table_name = 'equipments' then
    if not exists (
      select 1 from public.equipment_models m
      where m.id = new.equipment_model_id
        and (m.organization_id is null or m.organization_id = new.organization_id)
    ) then
      raise exception 'Equipment model is not available in this organization' using errcode = '42501';
    end if;
  elsif tg_table_name = 'case_attachments' then
    if new.service_case_id is not null and not exists (
      select 1 from public.service_cases c
      where c.id = new.service_case_id and c.organization_id = new.organization_id
    ) then
      raise exception 'Service case is not available in this organization' using errcode = '42501';
    end if;
    if new.equipment_id is not null and not exists (
      select 1 from public.equipments e
      where e.id = new.equipment_id and e.organization_id = new.organization_id
    ) then
      raise exception 'Equipment is not available in this organization' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_offline_operation (
  p_operation_id      uuid,
  p_entity_type       text,
  p_entity_id         uuid,
  p_operation         text,
  p_payload           jsonb,
  p_expected_revision bigint DEFAULT 0
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select orion_private.apply_offline_operation(
    p_operation_id, p_entity_type, p_entity_id,
    p_operation, p_payload, p_expected_revision
  );
$function$;

CREATE OR REPLACE FUNCTION public.enforce_same_organization()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare parent_org uuid;
begin
  case tg_table_name
    when 'sites' then
      select organization_id into parent_org from public.customers where id = new.customer_id;
    when 'equipments' then
      if new.site_id is null then return new; end if;
      select organization_id into parent_org from public.sites where id = new.site_id;
    when 'service_cases' then
      select organization_id into parent_org from public.equipments where id = new.equipment_id;
    when 'diagnostic_steps' then
      select organization_id into parent_org from public.service_cases where id = new.service_case_id;
    when 'case_attachments' then
      if new.service_case_id is not null then
        select organization_id into parent_org from public.service_cases where id = new.service_case_id;
      else
        select organization_id into parent_org from public.equipments where id = new.equipment_id;
      end if;
    when 'case_embeddings' then
      select organization_id into parent_org from public.service_cases where id = new.service_case_id;
    when 'ai_feedback' then
      select organization_id into parent_org from public.ai_queries where id = new.ai_query_id;
    else return new;
  end case;
  if parent_org is null or parent_org is distinct from new.organization_id then
    raise exception 'Cross-organization relationship is not permitted' using errcode = '42501';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_case_updated_by()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  new.updated_by = auth.uid();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE TRIGGER attachments_parent_scope
  BEFORE INSERT OR UPDATE ON public.case_attachments
  FOR EACH ROW
  EXECUTE FUNCTION orion_private.enforce_parent_scope();

CREATE TRIGGER equipments_parent_scope
  BEFORE INSERT OR UPDATE ON public.equipments
  FOR EACH ROW
  EXECUTE FUNCTION orion_private.enforce_parent_scope();

CREATE POLICY "ai_feedback_delete" ON "public"."ai_feedback"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "ai_feedback_insert" ON "public"."ai_feedback"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "ai_feedback_read" ON "public"."ai_feedback"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "ai_feedback_update" ON "public"."ai_feedback"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "ai_queries_delete" ON "public"."ai_queries"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "ai_queries_insert" ON "public"."ai_queries"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "ai_queries_read" ON "public"."ai_queries"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "ai_queries_update" ON "public"."ai_queries"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "case_attachments_delete" ON "public"."case_attachments"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "case_attachments_insert" ON "public"."case_attachments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "case_attachments_read" ON "public"."case_attachments"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "case_attachments_update" ON "public"."case_attachments"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "customers_delete" ON "public"."customers"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "customers_insert" ON "public"."customers"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "customers_read" ON "public"."customers"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "customers_update" ON "public"."customers"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "diagnostic_steps_delete" ON "public"."diagnostic_steps"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "diagnostic_steps_insert" ON "public"."diagnostic_steps"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "diagnostic_steps_read" ON "public"."diagnostic_steps"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "diagnostic_steps_update" ON "public"."diagnostic_steps"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "equipment_models_insert_own" ON "public"."equipment_models"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "equipment_models_visible" ON "public"."equipment_models"
  FOR SELECT
  TO "authenticated"
  USING (((public.current_organization_id() IS NOT NULL) AND ((organization_id IS NULL) OR (organization_id = public.current_organization_id()))));

CREATE POLICY "equipments_delete" ON "public"."equipments"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "equipments_insert" ON "public"."equipments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "equipments_read" ON "public"."equipments"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "equipments_update" ON "public"."equipments"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "manufacturers_insert_own" ON "public"."manufacturers"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "manufacturers_visible" ON "public"."manufacturers"
  FOR SELECT
  TO "authenticated"
  USING (((public.current_organization_id() IS NOT NULL) AND ((organization_id IS NULL) OR (organization_id = public.current_organization_id()))));

CREATE POLICY "service_cases_delete" ON "public"."service_cases"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_cases_insert" ON "public"."service_cases"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_cases_read" ON "public"."service_cases"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "service_cases_update" ON "public"."service_cases"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_order_templates_insert_own" ON "public"."service_order_templates"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_progress_entries_delete" ON "public"."service_progress_entries"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_progress_entries_insert" ON "public"."service_progress_entries"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_progress_entries_read" ON "public"."service_progress_entries"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "service_progress_entries_update" ON "public"."service_progress_entries"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "sites_delete" ON "public"."sites"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "sites_insert" ON "public"."sites"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "sites_read" ON "public"."sites"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id = public.current_organization_id()));

CREATE POLICY "sites_update" ON "public"."sites"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((organization_id = public.current_organization_id()) AND (public.current_user_role() = ANY (ARRAY['admin'::public.user_role, 'engineer'::public.user_role,
    'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_attachments_delete_own_org" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'service-attachments'::text) AND ((storage.foldername(name))[1] = (public.current_organization_id())::text) AND (public.current_user_role() = ANY
    (ARRAY['admin'::public.user_role, 'engineer'::public.user_role, 'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_attachments_insert_own_org" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'service-attachments'::text) AND ((storage.foldername(name))[1] = (public.current_organization_id())::text) AND (public.current_user_role() = ANY
    (ARRAY['admin'::public.user_role, 'engineer'::public.user_role, 'technician'::public.user_role, 'manager'::public.user_role]))));

CREATE POLICY "service_attachments_update_own_org" ON "storage"."objects"
  FOR UPDATE
  TO "authenticated"
  USING
    (((bucket_id = 'service-attachments'::text) AND ((storage.foldername(name))[1] = (public.current_organization_id())::text) AND (public.current_user_role() = ANY
    (ARRAY['admin'::public.user_role, 'engineer'::public.user_role, 'technician'::public.user_role, 'manager'::public.user_role]))))
  WITH
    CHECK
    (((bucket_id = 'service-attachments'::text) AND ((storage.foldername(name))[1] = (public.current_organization_id())::text) AND (public.current_user_role() = ANY
    (ARRAY['admin'::public.user_role, 'engineer'::public.user_role, 'technician'::public.user_role, 'manager'::public.user_role]))));

REVOKE ALL ON FUNCTION "orion_private"."apply_offline_operation"(uuid, text, uuid, text, jsonb, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "orion_private"."apply_offline_operation"(uuid, text, uuid, text, jsonb, bigint) TO "authenticated", "postgres";

REVOKE ALL ON FUNCTION "orion_private"."enforce_parent_scope"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "orion_private"."enforce_parent_scope"() TO "postgres";

REVOKE ALL ON FUNCTION "public"."apply_offline_operation"(uuid, text, uuid, text, jsonb, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "public"."apply_offline_operation"(uuid, text, uuid, text, jsonb, bigint) TO "authenticated", "postgres", "service_role";

GRANT USAGE ON SCHEMA "orion_private" TO "authenticated";

GRANT CREATE, USAGE ON SCHEMA "orion_private" TO "postgres";

REVOKE ALL ON TABLE "public"."ai_feedback" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."ai_feedback" TO "authenticated";

REVOKE ALL ON TABLE "public"."ai_queries" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."ai_queries" TO "authenticated";

REVOKE ALL ON TABLE "public"."audit_logs" FROM "authenticated";

GRANT SELECT ON TABLE "public"."audit_logs" TO "authenticated";

REVOKE ALL ON TABLE "public"."case_attachments" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."case_attachments" TO "authenticated";

REVOKE ALL ON TABLE "public"."customers" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."customers" TO "authenticated";

REVOKE ALL ON TABLE "public"."diagnostic_steps" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."diagnostic_steps" TO "authenticated";

REVOKE ALL ON TABLE "public"."equipment_models" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."equipment_models" TO "authenticated";

REVOKE ALL ON TABLE "public"."equipments" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."equipments" TO "authenticated";

REVOKE ALL ON TABLE "public"."manufacturers" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."manufacturers" TO "authenticated";

REVOKE ALL ON TABLE "public"."organizations" FROM "authenticated";

GRANT SELECT, UPDATE ON TABLE "public"."organizations" TO "authenticated";

REVOKE ALL ON TABLE "public"."profiles" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."profiles" TO "authenticated";

REVOKE ALL ON TABLE "public"."service_cases" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."service_cases" TO "authenticated";

REVOKE ALL ON TABLE "public"."service_order_templates" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."service_order_templates" TO "authenticated";

REVOKE ALL ON TABLE "public"."service_progress_entries" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."service_progress_entries" TO "authenticated";

REVOKE ALL ON TABLE "public"."sites" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."sites" TO "authenticated";

REVOKE ALL ON TABLE "public"."sync_conflicts" FROM "authenticated";

GRANT SELECT, UPDATE ON TABLE "public"."sync_conflicts" TO "authenticated";

REVOKE ALL ON TABLE "public"."sync_operation_receipts" FROM "authenticated";

GRANT SELECT ON TABLE "public"."sync_operation_receipts" TO "authenticated";


-- Grants explícitos também em projetos sem exposição automática de tabelas.
-- TRUNCATE não é protegido por RLS; não deve ser concedido ao cliente.
revoke all on table public.customers, public.sites, public.equipments, public.service_cases, public.diagnostic_steps, public.case_attachments, public.service_progress_entries, public.ai_queries, public.ai_feedback, public.organizations, public.profiles, public.manufacturers, public.equipment_models, public.service_order_templates, public.case_embeddings, public.audit_logs, public.sync_operation_receipts, public.sync_conflicts from public, anon, authenticated;
grant select on table public.customers, public.sites, public.equipments, public.service_cases, public.diagnostic_steps, public.case_attachments, public.service_progress_entries, public.ai_queries, public.ai_feedback, public.organizations, public.profiles, public.manufacturers, public.equipment_models, public.service_order_templates, public.case_embeddings, public.audit_logs, public.sync_operation_receipts, public.sync_conflicts to authenticated;
grant insert, update, delete on table public.customers, public.sites, public.equipments, public.service_cases, public.diagnostic_steps, public.case_attachments, public.service_progress_entries, public.ai_queries, public.ai_feedback, public.profiles, public.manufacturers, public.equipment_models, public.service_order_templates to authenticated;
grant update on public.organizations, public.sync_conflicts to authenticated;
grant usage on sequence public.service_cases_case_number_seq to authenticated;
-- O replay escreve recibos e a indexação usa service_role, nunca o cliente.
grant all on table public.customers, public.sites, public.equipments, public.service_cases, public.diagnostic_steps, public.case_attachments, public.service_progress_entries, public.ai_queries, public.ai_feedback, public.organizations, public.profiles, public.manufacturers, public.equipment_models, public.service_order_templates, public.case_embeddings, public.audit_logs, public.sync_operation_receipts, public.sync_conflicts to service_role;
grant usage, select on sequence public.service_cases_case_number_seq, public.audit_logs_id_seq to service_role;


-- Privilégios explícitos nas fronteiras da RPC, inclusive quando defaults variam.
revoke all on schema orion_private from public, anon, authenticated;
grant usage on schema orion_private to authenticated;
revoke all on function public.apply_offline_operation(uuid, text, uuid, text, jsonb, bigint) from public, anon;
grant execute on function public.apply_offline_operation(uuid, text, uuid, text, jsonb, bigint) to authenticated;
revoke all on function orion_private.apply_offline_operation(uuid, text, uuid, text, jsonb, bigint) from public, anon;
grant execute on function orion_private.apply_offline_operation(uuid, text, uuid, text, jsonb, bigint) to authenticated;
revoke all on function orion_private.enforce_parent_scope() from public, anon, authenticated;
