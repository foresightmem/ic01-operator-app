import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type TicketReason = "out_of_stock" | "malfunction";

type PublicTicketPayload = {
  machine_code?: unknown;
  reason?: unknown;
};

type RpcResult = {
  ok?: boolean;
  duplicate?: boolean;
  ticket_id?: string;
  code?: string;
  message?: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json",
};

const MAX_REQUESTS_PER_WINDOW = 12;
const RATE_WINDOW_MS = 10 * 60 * 1000;

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function normalizeMachineCode(value: string): string {
  return value.trim().toUpperCase().replace(/[\s-]+/g, "");
}

function isTicketReason(value: unknown): value is TicketReason {
  return value === "out_of_stock" || value === "malfunction";
}

function clientAddress(req: Request): string {
  const forwardedFor = req.headers.get("x-forwarded-for");
  if (forwardedFor) {
    return forwardedFor.split(",")[0]?.trim() ?? "unknown";
  }

  return req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    "unknown";
}

async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function isRateLimited(ipHash: string): Promise<boolean> {
  const since = new Date(Date.now() - RATE_WINDOW_MS).toISOString();
  const { count, error } = await supabase
    .from("public_ticket_request_log")
    .select("id", { count: "exact", head: true })
    .eq("ip_hash", ipHash)
    .gte("created_at", since);

  if (error) {
    console.error("rate_limit_lookup_failed", error);
    return false;
  }

  return (count ?? 0) >= MAX_REQUESTS_PER_WINDOW;
}

async function logRequest(
  ipHash: string,
  machineCodeHash: string | null,
  accepted: boolean,
): Promise<void> {
  const { error } = await supabase.from("public_ticket_request_log").insert({
    ip_hash: ipHash,
    machine_code_hash: machineCodeHash,
    accepted,
  });

  if (error) {
    console.error("request_log_insert_failed", error);
  }
}

function messageForCode(code?: string): string {
  switch (code) {
    case "machine_not_found":
      return "Codice macchina non trovato. Controlla il codice e riprova.";
    case "machine_inactive":
      return "Questa macchina non risulta disponibile per nuove segnalazioni.";
    case "invalid_reason":
      return "Seleziona un motivo valido.";
    case "missing_machine_code":
      return "Inserisci il codice macchina.";
    default:
      return "Non siamo riusciti a registrare la segnalazione. Riprova tra poco.";
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, message: "Metodo non consentito." }, 405);
  }

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("missing_supabase_edge_env");
    return jsonResponse(
      {
        ok: false,
        message: "Servizio temporaneamente non disponibile.",
      },
      500,
    );
  }

  const ipHash = await sha256Hex(
    `${clientAddress(req)}:${req.headers.get("user-agent") ?? ""}`,
  );

  try {
    if (await isRateLimited(ipHash)) {
      await logRequest(ipHash, null, false);
      return jsonResponse(
        {
          ok: false,
          message: "Troppi tentativi ravvicinati. Riprova tra qualche minuto.",
        },
        429,
      );
    }

    let payload: PublicTicketPayload;
    try {
      payload = await req.json() as PublicTicketPayload;
    } catch (_) {
      await logRequest(ipHash, null, false);
      return jsonResponse(
        { ok: false, message: "Controlla i dati inseriti e riprova." },
        400,
      );
    }

    const rawMachineCode = typeof payload.machine_code === "string"
      ? payload.machine_code
      : "";
    const normalizedMachineCode = normalizeMachineCode(rawMachineCode);
    const machineCodeHash = normalizedMachineCode
      ? await sha256Hex(normalizedMachineCode)
      : null;

    if (!normalizedMachineCode) {
      await logRequest(ipHash, machineCodeHash, false);
      return jsonResponse({ ok: false, message: "Inserisci il codice macchina." }, 400);
    }

    if (!isTicketReason(payload.reason)) {
      await logRequest(ipHash, machineCodeHash, false);
      return jsonResponse({ ok: false, message: "Seleziona un motivo valido." }, 400);
    }

    const { data, error } = await supabase.rpc(
      "create_public_maintenance_ticket",
      {
        p_machine_code: rawMachineCode,
        p_reason: payload.reason,
        p_reporter_hash: ipHash,
      },
    );

    if (error) {
      console.error("public_ticket_rpc_failed", error);
      await logRequest(ipHash, machineCodeHash, false);
      return jsonResponse(
        {
          ok: false,
          message:
            "Non siamo riusciti a registrare la segnalazione. Riprova tra poco.",
        },
        500,
      );
    }

    const result = (data ?? {}) as RpcResult;
    await logRequest(ipHash, machineCodeHash, result.ok === true);

    if (!result.ok) {
      return jsonResponse(
        { ok: false, message: messageForCode(result.code) },
        result.code === "machine_not_found" ? 404 : 400,
      );
    }

    return jsonResponse({
      ok: true,
      duplicate: result.duplicate === true,
      ticket_id: result.ticket_id,
      message: result.message ?? "Segnalazione inviata correttamente.",
    });
  } catch (err) {
    console.error("public_ticket_unhandled", err);
    return jsonResponse(
      {
        ok: false,
        message: "Servizio temporaneamente non disponibile.",
      },
      500,
    );
  }
});

