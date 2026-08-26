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

type SearchBody = {
  queryText?: string;
  equipmentId?: string | null;
  manufacturerId?: string | null;
  modelId?: string | null;
  subsystem?: string | null;
  errorCode?: string | null;
  limit?: number;
};

type CaseCandidate = {
  service_case_id: string;
  error_code?: string | null;
  subsystem?: string | null;
  reported_failure?: string | null;
  observed_symptoms?: string | null;
  root_cause?: string | null;
  solution_details?: string | null;
  validation_result?: string | null;
  final_score?: number | null;
};

/**
 * Gera, em uma única chamada, uma explicação curta por caso candidato
 * usando a Claude Messages API. É uma etapa de enriquecimento best-effort
 * que roda depois da busca híbrida determinística (SQL) — nunca decide
 * quais casos aparecem nem em que ordem, só explica em linguagem natural
 * por que cada um foi recuperado. Qualquer falha aqui retorna um mapa
 * vazio e a busca segue normalmente sem explicações.
 */
async function explainMatches(
  anthropicKey: string,
  model: string,
  queryText: string,
  filters: { errorCode?: string | null; subsystem?: string | null },
  candidates: CaseCandidate[],
): Promise<Record<string, string>> {
  if (candidates.length === 0) return {};

  const prompt = {
    descricao_falha_atual: queryText,
    filtro_codigo_erro: filters.errorCode ?? null,
    filtro_subsistema: filters.subsystem ?? null,
    casos_candidatos: candidates.map((item) => ({
      id: item.service_case_id,
      codigo_erro: item.error_code ?? null,
      subsistema: item.subsystem ?? null,
      falha_relatada: item.reported_failure ?? null,
      sintomas_observados: item.observed_symptoms ?? null,
      causa_raiz: item.root_cause ?? null,
      solucao_aplicada: item.solution_details ?? null,
      validacao: item.validation_result ?? null,
      pontuacao_similaridade: item.final_score ?? null,
    })),
  };

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": anthropicKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: 1024,
      system:
        "Você é um assistente técnico de manutenção de equipamentos médicos " +
        "(hemodinâmica e ressonância magnética). Para cada caso em " +
        "casos_candidatos, escreva uma explicação curta e objetiva (no " +
        "máximo 2 frases, em português) de por que aquele caso histórico é " +
        "relevante para a falha atual, citando evidências concretas em " +
        "comum (código de erro, subsistema, sintomas ou causa-raiz). Não " +
        "invente informações que não estejam nos dados fornecidos e não dê " +
        "instruções de reparo novas — apenas explique a relevância do " +
        "caso histórico. Responda apenas com um JSON no formato " +
        '{"explanations":[{"service_case_id":"...","explanation":"..."}]}' +
        ", um item por caso candidato, sem texto antes ou depois, sem " +
        "markdown.",
      messages: [{ role: "user", content: JSON.stringify(prompt) }],
    }),
  });

  if (!response.ok) {
    console.error("Anthropic API error", response.status, await response.text());
    return {};
  }

  const payload = await response.json();
  const textBlock = Array.isArray(payload?.content)
    ? payload.content.find((block: { type?: string }) => block.type === "text")
    : undefined;
  const text = textBlock?.text;
  if (typeof text !== "string") return {};

  try {
    const cleaned = text.trim().replace(/^```(json)?/i, "").replace(/```$/i, "").trim();
    const parsed = JSON.parse(cleaned) as {
      explanations?: { service_case_id?: string; explanation?: string }[];
    };
    const result: Record<string, string> = {};
    for (const item of parsed.explanations ?? []) {
      if (item.service_case_id && item.explanation) {
        result[item.service_case_id] = item.explanation;
      }
    }
    return result;
  } catch (error) {
    console.error("Failed to parse Anthropic explanation response", error);
    return {};
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) return jsonResponse({ error: "Missing authorization" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const openAiKey = Deno.env.get("OPENAI_API_KEY");
    const embeddingModel = Deno.env.get("OPENAI_EMBEDDING_MODEL") ?? "text-embedding-3-small";
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    const explanationModel = Deno.env.get("ANTHROPIC_EXPLANATION_MODEL") ?? "claude-sonnet-5";

    if (!supabaseUrl || !anonKey || !openAiKey) {
      return jsonResponse({ error: "Server configuration is incomplete" }, 500);
    }

    const body = await request.json() as SearchBody;
    const queryText = body.queryText?.trim();
    if (!queryText || queryText.length < 5) {
      return jsonResponse({ error: "Describe the failure using at least 5 characters" }, 400);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    });

    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return jsonResponse({ error: "Invalid session" }, 401);

    const { data: profile, error: profileError } = await userClient
      .from("profiles")
      .select("organization_id")
      .eq("user_id", authData.user.id)
      .single();

    if (profileError || !profile) return jsonResponse({ error: "User profile not configured" }, 403);

    const embeddingResponse = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: embeddingModel,
        input: queryText,
        encoding_format: "float",
      }),
    });

    if (!embeddingResponse.ok) {
      console.error("Embedding API error", embeddingResponse.status, await embeddingResponse.text());
      return jsonResponse({ error: "Could not process search query" }, 502);
    }

    const embeddingPayload = await embeddingResponse.json();
    const queryEmbedding = embeddingPayload?.data?.[0]?.embedding;
    if (!Array.isArray(queryEmbedding) || queryEmbedding.length !== 1536) {
      return jsonResponse({ error: "Unexpected embedding dimensions" }, 502);
    }

    const resultLimit = Math.min(Math.max(body.limit ?? 10, 1), 20);
    const { data: cases, error: searchError } = await userClient.rpc("search_similar_cases", {
      query_embedding: queryEmbedding,
      query_text: queryText,
      filter_equipment_id: body.equipmentId ?? null,
      filter_manufacturer_id: body.manufacturerId ?? null,
      filter_model_id: body.modelId ?? null,
      filter_subsystem: body.subsystem?.trim() || null,
      filter_error_code: body.errorCode?.trim() || null,
      result_limit: resultLimit,
    });

    if (searchError) {
      console.error(searchError);
      return jsonResponse({ error: "Search failed" }, 500);
    }

    const retrievedCaseIds = (cases ?? []).map((item: { service_case_id: string }) => item.service_case_id);

    let explanations: Record<string, string> = {};
    if (anthropicKey && (cases ?? []).length > 0) {
      try {
        explanations = await explainMatches(
          anthropicKey,
          explanationModel,
          queryText,
          { errorCode: body.errorCode, subsystem: body.subsystem },
          cases as CaseCandidate[],
        );
      } catch (error) {
        console.error("Explanation generation failed", error);
      }
    }
    const casesWithExplanations = (cases ?? []).map(
      (item: Record<string, unknown>) => ({
        ...item,
        ai_explanation: explanations[item.service_case_id as string] ?? null,
      }),
    );

    const { data: queryLog } = await userClient
      .from("ai_queries")
      .insert({
        organization_id: profile.organization_id,
        user_id: authData.user.id,
        query_text: queryText,
        filters: {
          equipmentId: body.equipmentId ?? null,
          manufacturerId: body.manufacturerId ?? null,
          modelId: body.modelId ?? null,
          subsystem: body.subsystem ?? null,
          errorCode: body.errorCode ?? null,
        },
        retrieved_case_ids: retrievedCaseIds,
      })
      .select("id")
      .single();

    return jsonResponse({
      queryId: queryLog?.id ?? null,
      cases: casesWithExplanations,
      guidance: {
        nature: "historical_evidence",
        warning: "Results are prior cases, not an official manufacturer procedure or autonomous diagnosis.",
        noResults: (cases ?? []).length === 0,
      },
    });
  } catch (error) {
    console.error(error);
    return jsonResponse({ error: "Unexpected server error" }, 500);
  }
});
