-- Hybrid search: exact error code + PostgreSQL full text + vector similarity + confidence weighting.

create or replace function public.search_similar_cases(
  query_embedding vector(1536),
  query_text text,
  filter_equipment_id uuid default null,
  filter_manufacturer_id uuid default null,
  filter_model_id uuid default null,
  filter_subsystem text default null,
  filter_error_code text default null,
  result_limit integer default 10
)
returns table (
  service_case_id uuid,
  case_number bigint,
  equipment_id uuid,
  manufacturer text,
  equipment_model text,
  serial_number text,
  opened_at timestamptz,
  error_code text,
  subsystem text,
  reported_failure text,
  observed_symptoms text,
  root_cause text,
  solution_details text,
  validation_result text,
  solution_confidence public.solution_confidence,
  vector_similarity double precision,
  lexical_score real,
  exact_code_match boolean,
  final_score double precision
)
language sql
stable
security invoker
set search_path = public
as $$
  with candidates as (
    select
      sc.id as service_case_id,
      sc.case_number,
      sc.equipment_id,
      m.name as manufacturer,
      em.model as equipment_model,
      e.serial_number,
      sc.opened_at,
      sc.error_code,
      sc.subsystem,
      sc.reported_failure,
      sc.observed_symptoms,
      sc.root_cause,
      sc.solution_details,
      sc.validation_result,
      sc.solution_confidence,
      (1 - (ce.embedding <=> query_embedding))::double precision as vector_similarity,
      ts_rank_cd(sc.search_document, websearch_to_tsquery('portuguese', coalesce(query_text, ''))) as lexical_score,
      (
        filter_error_code is not null
        and nullif(trim(filter_error_code), '') is not null
        and lower(coalesce(sc.error_code, '')) = lower(trim(filter_error_code))
      ) as exact_code_match,
      case sc.solution_confidence
        when 'reviewed' then 1.00
        when 'recurring' then 0.95
        when 'confirmed' then 0.90
        when 'probable' then 0.70
        when 'unconfirmed' then 0.45
        when 'obsolete' then 0.00
      end as confidence_weight
    from public.service_cases sc
    join public.case_embeddings ce on ce.service_case_id = sc.id
    join public.equipments e on e.id = sc.equipment_id
    join public.equipment_models em on em.id = e.equipment_model_id
    join public.manufacturers m on m.id = em.manufacturer_id
    where sc.organization_id = public.current_organization_id()
      and sc.status = 'resolved'
      and sc.solution_confidence <> 'obsolete'
      and (filter_equipment_id is null or sc.equipment_id = filter_equipment_id)
      and (filter_manufacturer_id is null or m.id = filter_manufacturer_id)
      and (filter_model_id is null or em.id = filter_model_id)
      and (filter_subsystem is null or lower(coalesce(sc.subsystem, '')) = lower(filter_subsystem))
  )
  select
    c.service_case_id,
    c.case_number,
    c.equipment_id,
    c.manufacturer,
    c.equipment_model,
    c.serial_number,
    c.opened_at,
    c.error_code,
    c.subsystem,
    c.reported_failure,
    c.observed_symptoms,
    c.root_cause,
    c.solution_details,
    c.validation_result,
    c.solution_confidence,
    c.vector_similarity,
    c.lexical_score,
    c.exact_code_match,
    (
      (greatest(c.vector_similarity, 0) * 0.62)
      + (least(c.lexical_score::double precision, 1.0) * 0.18)
      + (case when c.exact_code_match then 0.15 else 0 end)
      + (c.confidence_weight * 0.05)
    ) as final_score
  from candidates c
  order by final_score desc, c.opened_at desc
  limit least(greatest(result_limit, 1), 50);
$$;

grant execute on function public.search_similar_cases(
  vector, text, uuid, uuid, uuid, text, text, integer
) to authenticated;
