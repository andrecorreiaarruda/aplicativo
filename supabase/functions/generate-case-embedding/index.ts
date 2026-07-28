import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sha256(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) return jsonResponse({ error: "Missing authorization" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const openAiKey = Deno.env.get("OPENAI_API_KEY");
    const embeddingModel = Deno.env.get("OPENAI_EMBEDDING_MODEL") ?? "text-embedding-3-small";

    if (!supabaseUrl || !anonKey || !serviceRoleKey || !openAiKey) {
      return jsonResponse({ error: "Server configuration is incomplete" }, 500);
    }

    const { serviceCaseId } = await request.json() as { serviceCaseId?: string };
    if (!serviceCaseId) return jsonResponse({ error: "serviceCaseId is required" }, 400);

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    });

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return jsonResponse({ error: "Invalid session" }, 401);

    const { data: serviceCase, error: caseError } = await userClient
      .from("service_cases")
      .select(`
        id,
        organization_id,
        status,
        activity_type,
        reported_failure,
        observed_symptoms,
        error_code,
        error_message,
        subsystem,
        measurements,
        root_cause,
        solution_details,
        validation_result,
        solution_confidence,
        service_progress_entries(
          occurred_at,
          description
        ),
        equipments!inner(
          serial_number,
          software_version,
          hardware_version,
          equipment_models!inner(
            family,
            model,
            modality,
            manufacturers!inner(name)
          )
        )
      `)
      .eq("id", serviceCaseId)
      .single();

    if (caseError || !serviceCase) {
      return jsonResponse({ error: "Service case not found or not permitted" }, 404);
    }

    if (serviceCase.status !== "resolved") {
      return jsonResponse({ error: "Only resolved cases can be indexed" }, 409);
    }

    const equipment = Array.isArray(serviceCase.equipments)
      ? serviceCase.equipments[0]
      : serviceCase.equipments;
    const model = Array.isArray(equipment?.equipment_models)
      ? equipment.equipment_models[0]
      : equipment?.equipment_models;
    const manufacturer = Array.isArray(model?.manufacturers)
      ? model.manufacturers[0]
      : model?.manufacturers;
    const progressEntries = Array.isArray(serviceCase.service_progress_entries)
      ? serviceCase.service_progress_entries
      : [];
    const progressText = progressEntries
      .map((entry: { occurred_at?: string; description?: string }) =>
        `${entry.occurred_at ?? "data não informada"}: ${entry.description ?? ""}`
      )
      .filter((value: string) => value.trim().length > 0)
      .join(" | ");

    const sourceText = [
      `Fabricante: ${manufacturer?.name ?? "não informado"}`,
      `Família: ${model?.family ?? "não informada"}`,
      `Modelo: ${model?.model ?? "não informado"}`,
      `Modalidade: ${model?.modality ?? "não informada"}`,
      `Número de série: ${equipment?.serial_number ?? "não informado"}`,
      `Versão de software: ${equipment?.software_version ?? "não informada"}`,
      `Versão de hardware: ${equipment?.hardware_version ?? "não informada"}`,
      `Tipo de atividade: ${serviceCase.activity_type ?? "maintenance"}`,
      `Subsistema: ${serviceCase.subsystem ?? "não informado"}`,
      `Código de erro: ${serviceCase.error_code ?? "não informado"}`,
      `Mensagem de erro: ${serviceCase.error_message ?? "não informada"}`,
      `Falha relatada: ${serviceCase.reported_failure}`,
      `Sintomas observados: ${serviceCase.observed_symptoms ?? "não informados"}`,
      `Medições: ${serviceCase.measurements ?? "não informadas"}`,
      `Causa-raiz: ${serviceCase.root_cause ?? "não confirmada"}`,
      `Solução: ${serviceCase.solution_details ?? "não informada"}`,
      `Validação: ${serviceCase.validation_result ?? "não informada"}`,
      `Diário de andamento: ${progressText || "sem registros adicionais"}`,
      `Confiabilidade: ${serviceCase.solution_confidence}`,
    ].join("\n");

    const sourceHash = await sha256(sourceText);
    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: existing } = await serviceClient
      .from("case_embeddings")
      .select("source_hash")
      .eq("service_case_id", serviceCaseId)
      .maybeSingle();

    if (existing?.source_hash === sourceHash) {
      return jsonResponse({ indexed: false, reason: "unchanged", serviceCaseId });
    }

    const embeddingResponse = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: embeddingModel,
        input: sourceText,
        encoding_format: "float",
      }),
    });

    if (!embeddingResponse.ok) {
      const details = await embeddingResponse.text();
      console.error("Embedding API error", embeddingResponse.status, details);
      return jsonResponse({ error: "Embedding generation failed" }, 502);
    }

    const embeddingPayload = await embeddingResponse.json();
    const embedding = embeddingPayload?.data?.[0]?.embedding;

    if (!Array.isArray(embedding) || embedding.length !== 1536) {
      return jsonResponse({ error: "Unexpected embedding dimensions" }, 502);
    }

    const { error: upsertError } = await serviceClient
      .from("case_embeddings")
      .upsert({
        service_case_id: serviceCaseId,
        organization_id: serviceCase.organization_id,
        embedding_model: embeddingModel,
        source_hash: sourceHash,
        source_text: sourceText,
        embedding,
        updated_at: new Date().toISOString(),
      }, { onConflict: "service_case_id" });

    if (upsertError) {
      console.error(upsertError);
      return jsonResponse({ error: "Could not store embedding" }, 500);
    }

    return jsonResponse({ indexed: true, serviceCaseId, model: embeddingModel });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: "Unexpected server error" }, 500);
  }
});
