-- 0012_offline_archive_operations.sql
--
-- Arquivamento e restauração pela fila offline.
--
-- Até aqui `apply_offline_operation` recusava qualquer operação que não
-- fosse `upsert`, então o aplicativo não tinha como remover nada: as
-- colunas `deleted_at`, criadas na 0001 para exclusão lógica, nunca
-- chegaram a ser usadas.
--
-- O arquivamento é recusado enquanto houver histórico dependente. Num
-- registro de serviço técnico o histórico é o ativo principal, e um
-- clique em "arquivar cliente" não pode esconder os atendimentos que
-- documentam anos de manutenção. A checagem existe também no cliente,
-- para resposta imediata, mas a do servidor é a que vale: offline o
-- dispositivo não enxerga o que os outros criaram.
--
-- Esta migration não reescreve o corpo da RPC. Desde a 0011 a função
-- pública é um invólucro fino sobre `apply_offline_operation_impl`, e
-- as operações novas são tratadas antes da delegação.

-- ---------------------------------------------------------------------------
-- Contagem de dependentes ativos.
-- ---------------------------------------------------------------------------

create or replace function public.count_archive_blockers(
  p_entity_type text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
  v_equipamentos integer := 0;
  v_atendimentos integer := 0;
begin
  if p_entity_type = 'customer' then
    select count(*) into v_equipamentos
    from public.equipments e
    join public.sites s on s.id = e.site_id
    where s.customer_id = p_entity_id
      and e.organization_id = v_org
      and e.deleted_at is null;

    select count(*) into v_atendimentos
    from public.service_cases c
    join public.equipments e on e.id = c.equipment_id
    join public.sites s on s.id = e.site_id
    where s.customer_id = p_entity_id
      and c.organization_id = v_org
      and c.deleted_at is null;

  elsif p_entity_type = 'equipment' then
    select count(*) into v_atendimentos
    from public.service_cases c
    where c.equipment_id = p_entity_id
      and c.organization_id = v_org
      and c.deleted_at is null;

  end if;
  -- service_case é folha: nada depende dele, os contadores ficam zerados.

  return jsonb_build_object(
    'equipment', v_equipamentos,
    'cases', v_atendimentos,
    'total', v_equipamentos + v_atendimentos
  );
end;
$$;

revoke execute on function public.count_archive_blockers(text, uuid)
  from public, authenticated;

-- ---------------------------------------------------------------------------
-- Aplicação do arquivamento / restauração.
-- ---------------------------------------------------------------------------

create or replace function public.apply_archive_operation(
  p_operation_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_operation text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
  v_user uuid := auth.uid();
  v_table text;
  v_blockers jsonb;
  v_conflict_id uuid;
  v_revision bigint;
  v_result jsonb;
  v_partes text[];
begin
  v_table := case p_entity_type
    when 'customer' then 'customers'
    when 'equipment' then 'equipments'
    when 'service_case' then 'service_cases'
    else null
  end;

  if v_table is null then
    raise exception 'Arquivamento não suportado para: %', p_entity_type;
  end if;

  if p_operation = 'archive' then
    v_blockers := public.count_archive_blockers(p_entity_type, p_entity_id);

    if (v_blockers->>'total')::integer > 0 then
      if (v_blockers->>'equipment')::integer > 0 then
        v_partes := array_append(
          v_partes,
          (v_blockers->>'equipment') || ' equipamento(s)'
        );
      end if;
      if (v_blockers->>'cases')::integer > 0 then
        v_partes := array_append(
          v_partes,
          (v_blockers->>'cases') || ' atendimento(s)'
        );
      end if;

      insert into public.sync_conflicts (
        organization_id, operation_id, entity_type, entity_id,
        expected_revision, server_revision, client_payload,
        server_payload, created_by
      ) values (
        v_org, p_operation_id, p_entity_type, p_entity_id,
        null, null, jsonb_build_object('operation', p_operation),
        v_blockers, v_user
      )
      on conflict (organization_id, operation_id) do update
        set server_payload = excluded.server_payload
      returning id into v_conflict_id;

      return jsonb_build_object(
        'status', 'conflict',
        'conflict_id', v_conflict_id,
        'entity_type', p_entity_type,
        'entity_id', p_entity_id,
        'message',
          'Não é possível arquivar: ' || array_to_string(v_partes, ' e ')
          || ' ainda dependem deste registro. Arquive-os primeiro.'
      );
    end if;
  end if;

  execute format(
    'update public.%I
        set deleted_at = $1,
            sync_revision = sync_revision + 1
      where id = $2 and organization_id = $3
      returning sync_revision',
    v_table
  )
  into v_revision
  using
    case when p_operation = 'archive' then now() else null end,
    p_entity_id,
    v_org;

  if v_revision is null then
    raise exception 'Registro não encontrado para arquivamento: %', p_entity_id;
  end if;

  v_result := jsonb_build_object(
    'status', 'applied',
    'revision', v_revision,
    'entity_type', p_entity_type,
    'entity_id', p_entity_id
  );

  insert into public.sync_operation_receipts (
    operation_id, organization_id, entity_type, entity_id,
    result, applied_by
  ) values (
    p_operation_id, v_org, p_entity_type, p_entity_id, v_result, v_user
  );

  return v_result;
end;
$$;

revoke execute on function public.apply_archive_operation(
  uuid, text, uuid, text
) from public, authenticated;

-- ---------------------------------------------------------------------------
-- Invólucro público: trata archive/restore e delega o resto.
-- ---------------------------------------------------------------------------

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
  v_constraint text;
  v_result jsonb;
begin
  -- Idempotência vale para todas as operações, inclusive as novas.
  select result into v_result
  from public.sync_operation_receipts
  where operation_id = p_operation_id
    and organization_id = v_org;

  if found then
    return v_result || jsonb_build_object('status', 'duplicate');
  end if;

  if p_operation in ('archive', 'restore') then
    return public.apply_archive_operation(
      p_operation_id, p_entity_type, p_entity_id, p_operation
    );
  end if;

  -- Gravação: mesmo tratamento de chave natural introduzido na 0011.
  begin
    return public.apply_offline_operation_impl(
      p_operation_id, p_entity_type, p_entity_id,
      p_operation, p_payload, p_expected_revision
    );
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint not in (
        'manufacturers_global_name_uq', 'manufacturers_tenant_name_uq'
      ) then
        return public.record_offline_unique_conflict(
          p_operation_id, p_entity_type, p_entity_id, p_payload, v_constraint
        );
      end if;
  end;

  begin
    return public.apply_offline_operation_impl(
      p_operation_id, p_entity_type, p_entity_id,
      p_operation, p_payload, p_expected_revision
    );
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      return public.record_offline_unique_conflict(
        p_operation_id, p_entity_type, p_entity_id, p_payload, v_constraint
      );
  end;
end;
$$;

grant execute on function public.apply_offline_operation(
  uuid, text, uuid, text, jsonb, bigint
) to authenticated;
