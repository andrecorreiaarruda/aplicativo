-- ORION ServiceLog 0.4.0-alpha.2
-- Diário de andamento passa a registrar sessões de trabalho (início e
-- fim), não só um ponto no tempo. Isso permite calcular tempo técnico
-- automaticamente a partir de sessões reais, em vez de um número
-- digitado à mão na conclusão do atendimento.

alter table public.service_progress_entries
  add column if not exists ended_at timestamptz null;

-- Entradas anteriores a esta migration eram apenas um ponto no tempo, não
-- uma sessão com duração. Sem backfill, todas passariam a contar como
-- "sessão sem horário de fim" e bloqueariam a conclusão de qualquer
-- atendimento antigo que fosse reaberto. Fecha-se cada uma com duração
-- zero: não inventa tempo técnico que ninguém registrou, e o histórico de
-- tempo desses atendimentos continua sendo o que já está em
-- service_cases.service_minutes.
update public.service_progress_entries
  set ended_at = occurred_at
  where ended_at is null;

alter table public.service_progress_entries
  drop constraint if exists service_progress_entries_time_range_check;

alter table public.service_progress_entries
  add constraint service_progress_entries_time_range_check
  check (ended_at is null or ended_at >= occurred_at);

-- Substitui apply_offline_operation para: (1) gravar ended_at nas
-- entradas do diário e (2) recusar concluir um atendimento
-- (status = 'resolved') enquanto houver sessão em aberto no diário
-- (defesa em profundidade — a UI já bloqueia isso antes de chegar aqui,
-- mas a gravação de dados de tempo é a base das métricas de qualidade
-- do serviço, então vale garantir também no servidor).
create or replace function public.apply_offline_operation(
  p_operation_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_operation text,
  p_payload jsonb,
  p_expected_revision bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
  v_user uuid := auth.uid();
  v_current_revision bigint;
  v_result jsonb;
  v_server_payload jsonb;
  v_conflict_id uuid;
  v_manufacturer_id uuid;
  v_entry jsonb;
begin
  if v_user is null or v_org is null then
    raise exception 'Authenticated organization context is required';
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
      deleted_at = null;

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
      deleted_at = null;

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
      deleted_at = null;

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
      deleted_at = null;

    select sync_revision into v_current_revision
    from public.equipments where id = p_entity_id;

  elsif p_entity_type = 'service_case' then
    select sync_revision, to_jsonb(sc)
      into v_current_revision, v_server_payload
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
      coalesce((p_payload->>'opened_at')::timestamptz, now()),
      nullif(p_payload->>'closed_at', '')::timestamptz,
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
      nullif(p_payload->>'downtime_minutes', '')::integer,
      nullif(p_payload->>'service_minutes', '')::integer,
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
      deleted_at = null;

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
$$;

grant execute on function public.apply_offline_operation(
  uuid, text, uuid, text, jsonb, bigint
) to authenticated;
