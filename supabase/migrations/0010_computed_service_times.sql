-- ORION ServiceLog — Tempos de atendimento calculados no servidor
--
-- `service_minutes` e `downtime_minutes` deixaram de ser digitados pelo
-- técnico e passaram a ser derivados:
--
--   service_minutes  = soma das sessões ENCERRADAS do diário
--   downtime_minutes = (closed_at - opened_at) * peso do impacto operacional
--
-- Pesos: none 0% · degraded 30% · partial_stop 65% · total_stop 100%.
-- São valores de calibração, não constantes técnicas, e ESTE É O ÚNICO
-- LUGAR onde vivem. O cliente não os reimplementa: reajustar aqui basta.
--
-- Divisão de responsabilidade:
--   service_minutes  — o cliente também sabe calcular (soma pura das
--                      sessões, sem calibração), para exibir offline; o
--                      servidor recalcula e prevalece.
--   downtime_minutes — só o servidor calcula. Enquanto o atendimento não
--                      for sincronizado, o campo fica nulo e a interface
--                      indica que o valor será calculado no envio.
--
-- Em ambos os casos os valores recebidos no payload são ignorados: o
-- servidor é a fonte da verdade, para que dois dispositivos não gravem
-- números divergentes para o mesmo atendimento.
--
-- Atendimentos anteriores a esta migration mantêm os valores digitados
-- manualmente: nada é reescrito retroativamente. Eles só serão
-- recalculados se forem editados e sincronizados novamente.

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
