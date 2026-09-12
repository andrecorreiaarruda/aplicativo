-- 20260912130000_archive_authorization.sql
--
-- Fecha uma brecha de autorização no caminho de arquivamento.
--
-- `orion_private.apply_offline_operation` exige usuário autenticado,
-- organização ativa e papel com permissão de escrita antes de gravar
-- qualquer coisa. Mas o invólucro público desvia `archive` e `restore`
-- para `apply_archive_operation`, que nunca passou por essas checagens:
-- ela lia `current_organization_id()` e `auth.uid()` apenas para compor a
-- linha, sem verificar se havia contexto e sem olhar o papel.
--
-- O efeito era um usuário de consulta poder arquivar e restaurar
-- registros — a única operação de escrita ao seu alcance. A restrição por
-- organização já existia na cláusula de atualização, então não havia
-- alcance entre inquilinos; o problema era de papel.
--
-- A brecha só se tornou visível ao alinhar o arquivamento com o modelo de
-- autorização introduzido em 20260907162623, que centralizou as checagens
-- no corpo privado. Quem não passa por ele precisa repeti-las.

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
  v_role public.user_role := public.current_user_role();
  v_table text;
  v_blockers jsonb;
  v_conflict_id uuid;
  v_revision bigint;
  v_result jsonb;
  v_partes text[];
begin
  -- Mesmas exigências do corpo privado de replay. Repetidas aqui porque
  -- este caminho não passa por ele.
  if v_user is null or v_org is null then
    raise exception 'Authenticated organization context is required'
      using errcode = '42501';
  end if;

  if v_role is null or v_role not in
     ('admin', 'engineer', 'technician', 'manager') then
    raise exception 'Write permission is required' using errcode = '42501';
  end if;

  if p_operation not in ('archive', 'restore') then
    raise exception 'Operação de arquivamento não suportada: %', p_operation;
  end if;

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
          v_partes, (v_blockers->>'equipment') || ' equipamento(s)'
        );
      end if;
      if (v_blockers->>'cases')::integer > 0 then
        v_partes := array_append(
          v_partes, (v_blockers->>'cases') || ' atendimento(s)'
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

  -- A restrição por organização já impedia alcance entre inquilinos.
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

revoke all on function public.apply_archive_operation(uuid, text, uuid, text)
  from public, anon, authenticated;
