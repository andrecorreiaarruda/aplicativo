-- 0011_offline_unique_conflicts.sql
--
-- Duas correções no replay offline, ambas sobre o mesmo sintoma: a fila
-- travada.
--
-- 1. `apply_offline_operation` não tratava `unique_violation`. Quando dois
--    dispositivos criavam offline a mesma entidade natural — o mesmo cliente,
--    o mesmo número de série — cada um gerava um UUID próprio. O `on conflict
--    (id)` do corpo da função só resolve colisão de chave primária, então a
--    segunda gravação estourava a restrição de chave natural e subia como
--    exceção. O cliente não sabia distinguir isso de uma falha de rede e
--    retentava indefinidamente, sem nunca progredir.
--
-- 2. A função vinha sendo reescrita por inteiro a cada migration
--    (0008 -> 0010), com cerca de 460 linhas copiadas. Além do custo de
--    revisão, era fácil editar a cópia errada.
--
-- Esta migration resolve as duas de uma vez: o corpo da 0010 é renomeado
-- para `apply_offline_operation_impl` e permanece a única definição da
-- lógica. `apply_offline_operation` passa a ser um invólucro fino que
-- delega ao corpo e traduz `unique_violation` em conflito registrado.
-- Mudanças futuras na lógica alteram o corpo; mudanças no tratamento de
-- erro alteram o invólucro. Nenhuma das duas exige copiar a outra.

-- ---------------------------------------------------------------------------
-- 1. Renomeia o corpo vigente, preservando security definer e search_path.
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'apply_offline_operation_impl'
  ) then
    alter function public.apply_offline_operation(
      uuid, text, uuid, text, jsonb, bigint
    ) rename to apply_offline_operation_impl;
  end if;
end;
$$;

-- O corpo deixa de ser chamável diretamente: todo acesso passa pelo
-- invólucro, que é quem trata a violação de chave natural.
revoke execute on function public.apply_offline_operation_impl(
  uuid, text, uuid, text, jsonb, bigint
) from public, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Registro de conflito por chave natural.
-- ---------------------------------------------------------------------------
-- Reaproveita a tabela `sync_conflicts` já usada pelos conflitos de revisão,
-- porque o cliente só precisa saber que a operação exige decisão humana — a
-- origem do conflito muda a mensagem, não o tratamento.

create or replace function public.record_offline_unique_conflict(
  p_operation_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb,
  p_constraint text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := public.current_organization_id();
  v_user uuid := auth.uid();
  v_conflict_id uuid;
  v_message text;
begin
  v_message := case p_entity_type
    when 'customer' then
      'Já existe um cliente com este nome. O registro foi criado em outro '
      || 'dispositivo e precisa ser reaproveitado em vez de duplicado.'
    when 'site' then
      'Já existe um local com este nome para o cliente. O registro foi '
      || 'criado em outro dispositivo.'
    when 'equipment_model' then
      'Já existe um modelo com esta descrição para o fabricante. O registro '
      || 'foi criado em outro dispositivo.'
    when 'equipment' then
      'Já existe um equipamento com este número de série. O registro foi '
      || 'criado em outro dispositivo.'
    else
      'Já existe um registro equivalente criado em outro dispositivo.'
  end;

  insert into public.sync_conflicts (
    organization_id, operation_id, entity_type, entity_id,
    expected_revision, server_revision, client_payload,
    server_payload, created_by
  ) values (
    v_org, p_operation_id, p_entity_type, p_entity_id,
    null, null, p_payload,
    jsonb_build_object('constraint', p_constraint), v_user
  )
  on conflict (organization_id, operation_id) do update
    set client_payload = excluded.client_payload,
        server_payload = excluded.server_payload
  returning id into v_conflict_id;

  return jsonb_build_object(
    'status', 'conflict',
    'conflict_id', v_conflict_id,
    'entity_type', p_entity_type,
    'entity_id', p_entity_id,
    'message', v_message
  );
end;
$$;

revoke execute on function public.record_offline_unique_conflict(
  uuid, text, uuid, jsonb, text
) from public, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Invólucro público.
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
  v_constraint text;
begin
  -- Primeira tentativa.
  begin
    return public.apply_offline_operation_impl(
      p_operation_id, p_entity_type, p_entity_id,
      p_operation, p_payload, p_expected_revision
    );
  exception
    when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;

      -- O corpo cria o fabricante implicitamente quando ele ainda não
      -- existe, num "select, e se nulo insere" que não é atômico. Numa
      -- corrida entre dispositivos os dois veem nulo e os dois inserem.
      -- Isso não é conflito de dados: o vencedor gravou exatamente o que o
      -- perdedor queria gravar. Uma segunda tentativa encontra o registro
      -- já commitado e segue adiante.
      if v_constraint not in (
        'manufacturers_global_name_uq', 'manufacturers_tenant_name_uq'
      ) then
        return public.record_offline_unique_conflict(
          p_operation_id, p_entity_type, p_entity_id, p_payload, v_constraint
        );
      end if;
  end;

  -- Segunda e última tentativa, exclusiva da corrida de fabricante acima.
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
