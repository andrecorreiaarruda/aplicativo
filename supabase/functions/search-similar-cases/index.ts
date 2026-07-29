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
      cases: cases ?? [],
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
