import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

const MAX_SKEW_S = 600;

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const deviceId = req.headers.get("x-device-id") ?? "";
  const tsHeader = req.headers.get("x-timestamp") ?? "";
  const signature = req.headers.get("x-signature") ?? "";

  if (!deviceId || !tsHeader || !signature) {
    return new Response("Missing auth headers", { status: 401 });
  }

  const ts = Number(tsHeader);
  if (!Number.isFinite(ts)) {
    return new Response("Invalid timestamp", { status: 401 });
  }

  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - ts) > MAX_SKEW_S) {
    return new Response("Timestamp out of range", { status: 401 });
  }

  const rawBody = await req.text();
  if (!rawBody) {
    return new Response("Empty body", { status: 400 });
  }

  const { data: device, error: deviceErr } = await supabase
    .from("devices")
    .select("id, device_secret, device_secret_next")
    .eq("device_id", deviceId)
    .maybeSingle();

  if (deviceErr || !device) {
    return new Response("Unknown device", { status: 401 });
  }

  const toSign = `${ts}.${rawBody}`;
  const sigPrimary = await hmacHex(device.device_secret, toSign);
  const sigNext = device.device_secret_next
    ? await hmacHex(device.device_secret_next, toSign)
    : "";
  const valid =
    timingSafeEqual(signature, sigPrimary) ||
    (sigNext && timingSafeEqual(signature, sigNext));

  if (!valid) {
    return new Response("Invalid signature", { status: 401 });
  }

  let payload: any;
  try {
    payload = JSON.parse(rawBody);
  } catch (_err) {
    return new Response("Invalid JSON", { status: 400 });
  }

  const intervalS = Number(payload.interval_s) || 30;
  const bucketStartMs =
    Math.floor(Date.now() / 1000 / intervalS) * intervalS * 1000;
  const tsBucket = new Date(bucketStartMs).toISOString();
  const counts = payload.counts ?? {};

  const upsertCounters = {
    device_id: device.id,
    ts_bucket: tsBucket,
    interval_s: intervalS,
    idle_count: Number(counts.idle) || 0,
    coffee_count: Number(counts.coffee) || 0,
    cappuccino_count: Number(counts.cappuccino) || 0,
    powders_count: Number(counts.powders) || 0,
    unknown_count: Number(counts.unknown) || 0,
  };

  const { error: countersErr } = await supabase
    .from("device_counters_bucket")
    .upsert(upsertCounters, { onConflict: "device_id,ts_bucket" });

  if (countersErr) {
    return new Response("Failed to write counters", { status: 500 });
  }

  const { error: statusErr } = await supabase
    .from("device_status")
    .upsert(
      {
        device_id: device.id,
        last_seen_at: new Date().toISOString(),
        fw_version: typeof payload.fw_version === "string"
          ? payload.fw_version
          : null,
      },
      { onConflict: "device_id" },
    );

  if (statusErr) {
    return new Response("Failed to write status", { status: 500 });
  }

  return new Response(
    JSON.stringify({ ok: true, ts_bucket: tsBucket }),
    { headers: { "content-type": "application/json" } },
  );
});
