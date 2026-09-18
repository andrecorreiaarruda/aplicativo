-- 20260918120000_purge_operations.sql
--
-- Exclusão definitiva a partir de Arquivados.
--
-- Arquivar tira o registro das listagens e preserva o histórico técnico.
-- É o comportamento certo para quase tudo. Falta a saída para o que nunca
-- deveria ter sido criado: um cadastro de teste, um cliente digitado em
-- duplicidade, um equipamento lançado no cliente errado. Esses não têm
-- histórico a preservar, e mantê-los arquivados para sempre transforma a
-- lista de arquivados num depósito.
--
-- Três travas, porque a operação não tem volta:
--
--   1. Só registros já arquivados podem ser excluídos. Quem quiser apagar
--      precisa antes arquivar, o que dá um passo de arrependimento e faz
--      o registro sumir das listagens antes de sumir do banco.
--   2. Só papel 'admin'. Arquivar é do dia a dia e vale para técnico e
--      engenheiro; apagar em definitivo, não.
--   3. Nada é excluído com dependentes — e aqui, ao contrário do
--      arquivamento, os dependentes arquivados também contam. Apagar um
--      cliente cujo equipamento está apenas arquivado deixaria o
--      equipamento órfão, já que `sites` sai em cascata com o cliente.
--
-- Anexos contam como impedimento por um motivo diferente: a linha sairia
-- em cascata, mas o arquivo correspondente continuaria no bucket privado,
-- sem nada que o referencie. Enquanto não houver rotina que limpe o
-- armazenamento, recusar é melhor do que deixar lixo inacessível. Hoje o
-- aplicativo não grava anexos, então a contagem é sempre zero; a trava
-- existe para o dia em que passar a gravar.

-- ---------------------------------------------------------------------------
-- 1. Contagem de impedimentos, incluindo os arquivados.
-- ---------------------------------------------------------------------------

create or replace function public.count_purge_blockers(
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
  v_anexos integer := 0;
begin
  if p_entity_type = 'customer' then
    select count(*) into v_equipamentos
    from public.equipments e
    join public.sites s on s.id = e.site_id
    where s.customer_id = p_entity_id
      and e.organization_id = v_org;

    select count(*) into v_atendimentos
    from public.service_cases c
    join public.equipments e on e.id = c.equipment_id
    join public.sites s on s.id = e.site_id
    where s.customer_id = p_entity_id
      and c.organization_id = v_org;

  elsif p_entity_type = 'equipment' then
    select count(*) into v_atendimentos
    from public.service_cases c
    where c.equipment_id = p_entity_id
      and c.organization_id = v_org;

    select count(*) into v_anexos
    from public.case_attachments a
    where a.equipment_id = p_entity_id
      and a.organization_id = v_org;

  elsif p_entity_type = 'service_case' then
    select count(*) into v_anexos
    from public.case_attachments a
    where a.service_case_id = p_entity_id
      and a.organization_id = v_org;

  end if;

  return jsonb_build_object(
    'equipment', v_equipamentos,
    'cases', v_atendimentos,
    'attachments', v_anexos,
    'total', v_equipamentos + v_atendimentos + v_anexos
  );
end;
$$;

revoke execute on function public.count_purge_blockers(text, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Aplicação da exclusão definitiva.
-- ---------------------------------------------------------------------------

create or replace function public.apply_purge_operation(
  p_operation_id uuid,
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
  v_user uuid := auth.uid();
  v_role public.user_role := public.current_user_role();
  v_table text;
  v_blockers jsonb;
  v_conflict_id uuid;
  v_arquivado timestamptz;
  v_revision bigint;
  v_existe boolean;
  v_result jsonb;
  v_partes text[];
begin
  if v_user is null or v_org is null then
    raise exception 'Authenticated organization context is required'
      using errcode = '42501';
  end if;

  -- Mais restrito que o arquivamento de propósito: a operação não tem
  -- volta e não deve estar ao alcance de quem apenas registra atendimento.
  if v_role is distinct from 'admin' then
    raise exception 'Only an administrator can permanently delete records'
      using errcode = '42501';
  end if;

  v_table := case p_entity_type
    when 'customer' then 'customers'
    when 'equipment' then 'equipments'
    when 'service_case' then 'service_cases'
    else null
  end;

  if v_table is null then
    raise exception 'Exclusão definitiva não suportada para: %', p_entity_type;
  end if;

  execute format(
    'select deleted_at, sync_revision, true
       from public.%I where id = $1 and organization_id = $2',
    v_table
  )
  into v_arquivado, v_revision, v_existe
  using p_entity_id, v_org;

  if v_existe is not true then
    -- Já não existe. A intenção da operação está cumprida, e recusá-la
    -- prenderia a fila para sempre num registro que ninguém mais vê.
    v_result := jsonb_build_object(
      'status', 'applied',
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'message', 'O registro já não existia.'
    );

    insert into public.sync_operation_receipts (
      operation_id, organization_id, entity_type, entity_id,
      result, applied_by
    ) values (
      p_operation_id, v_org, p_entity_type, p_entity_id, v_result, v_user
    );

    return v_result;
  end if;

  if v_arquivado is null then
    return jsonb_build_object(
      'status', 'conflict',
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'message',
        'Só registros arquivados podem ser excluídos em definitivo. '
        'Arquive o registro primeiro.'
    );
  end if;

  v_blockers := public.count_purge_blockers(p_entity_type, p_entity_id);

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
    if (v_blockers->>'attachments')::integer > 0 then
      v_partes := array_append(
        v_partes, (v_blockers->>'attachments') || ' anexo(s)'
      );
    end if;

    insert into public.sync_conflicts (
      organization_id, operation_id, entity_type, entity_id,
      expected_revision, server_revision, client_payload,
      server_payload, created_by
    ) values (
      v_org, p_operation_id, p_entity_type, p_entity_id,
      null, v_revision, jsonb_build_object('operation', 'purge'),
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
        'Não é possível excluir: ' || array_to_string(v_partes, ' e ')
        || ' ainda dependem deste registro, inclusive arquivados. '
        || 'Exclua-os primeiro.'
    );
  end if;

  execute format(
    'delete from public.%I where id = $1 and organization_id = $2',
    v_table
  )
  using p_entity_id, v_org;

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

revoke all on function public.apply_purge_operation(uuid, text, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Invólucro público: roteia 'purge' junto de 'archive' e 'restore'.
-- ---------------------------------------------------------------------------
--
-- Recriado por inteiro a partir de 20260912120000, trocando apenas o
-- desvio. Redefinir só o desvio não é possível, e deixar o invólucro
-- antigo faria 'purge' cair no corpo privado, que a recusaria como
-- operação desconhecida.

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
  -- Idempotência vale para todas as operações, inclusive arquivamento e
  -- exclusão definitiva.
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

  if p_operation = 'purge' then
    return public.apply_purge_operation(
      p_operation_id, p_entity_type, p_entity_id
    );
  end if;

  begin
    return orion_private.apply_offline_operation(
      p_operation_id, p_entity_type, p_entity_id,
      p_operation, p_payload, p_expected_revision
    );
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      -- Corrida na criação implícita de fabricante: o vencedor gravou o
      -- que o perdedor queria. Uma segunda tentativa reaproveita a linha.
      if v_constraint not in (
        'manufacturers_global_name_uq', 'manufacturers_tenant_name_uq'
      ) then
        return public.record_offline_unique_conflict(
          p_operation_id, p_entity_type, p_entity_id, p_payload, v_constraint
        );
      end if;
  end;

  begin
    return orion_private.apply_offline_operation(
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

revoke all on function public.apply_offline_operation(
  uuid, text, uuid, text, jsonb, bigint
) from public, anon;

grant execute on function public.apply_offline_operation(
  uuid, text, uuid, text, jsonb, bigint
) to authenticated;
