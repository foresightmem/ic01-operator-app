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

function monitoringFactorForMode(
  mode: string | null | undefined,
): "hot" | "cold" {
  return mode === "cold" ? "cold" : "hot";
}

serve(async (req) => {
  try {
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
      .select("id, device_secret, device_secret_next, machine_id")
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

    let payload: {
      counts?: Record<string, number>;
      fw_version?: unknown;
      app_version?: unknown;
    } = {};
    try {
      payload = JSON.parse(rawBody);
    } catch (_err) {
      return new Response("Invalid JSON", { status: 400 });
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
          app_version: typeof payload.app_version === "string"
            ? payload.app_version
            : null,
        },
        { onConflict: "device_id" },
      );

    if (statusErr) {
      return new Response(
        JSON.stringify({ error: "write_status", detail: statusErr }),
        { status: 500, headers: { "content-type": "application/json" } },
      );
    }

    const counts = payload.counts ?? {};
    const beverageCounts: Record<string, number> = {};
    for (const [key, value] of Object.entries(counts)) {
      beverageCounts[key] = Number(value) || 0;
    }
    // Backward compatibility: "powders" -> "powder_drink"
    if (beverageCounts.powders && !beverageCounts.powder_drink) {
      beverageCounts.powder_drink = beverageCounts.powders;
    }

    const totalEvents = Object.values(beverageCounts).reduce(
      (sum, v) => sum + v,
      0,
    );
    if (totalEvents <= 0) {
      return new Response(JSON.stringify({ ok: true, applied: 0 }), {
        headers: { "content-type": "application/json" },
      });
    }

    if (!device.machine_id) {
      return new Response("Device not linked to machine", { status: 400 });
    }

    const { data: machineRow, error: machineErr } = await supabase
      .from("machines")
      .select("temperature_mode")
      .eq("id", device.machine_id)
      .maybeSingle();

    if (machineErr) {
      return new Response(
        JSON.stringify({ error: "load_machine", detail: machineErr }),
        { status: 500, headers: { "content-type": "application/json" } },
      );
    }

    const factor = monitoringFactorForMode(machineRow?.temperature_mode);

    const { data: consumable, error: consErr } = await supabase
      .from("machine_consumables")
      .select("id, type, capacity_units, current_units, is_enabled")
      .eq("machine_id", device.machine_id)
      .eq("type", factor)
      .eq("is_enabled", true)
      .maybeSingle();

    if (consErr) {
      return new Response(
        JSON.stringify({ error: "load_consumables", detail: consErr }),
        { status: 500, headers: { "content-type": "application/json" } },
      );
    }

    const warnings: string[] = [];
    if (!consumable) {
      warnings.push(`missing active factor ${factor}`);
    } else {
      const row = consumable as {
        id: string;
        capacity_units: number;
        current_units: number;
      };
      const capacity = Number(row.capacity_units) || 0;
      if (capacity <= 0) {
        warnings.push(`invalid capacity ${factor}`);
      } else {
        const cur = Number(row.current_units) || 0;
        const next = cur - totalEvents;
        const currentUnits = Math.min(Math.max(next, 0), capacity);
        const { error: updateErr } = await supabase
          .from("machine_consumables")
          .update({ current_units: currentUnits })
          .eq("id", row.id);
        if (updateErr) {
          return new Response(
            JSON.stringify({ error: "update_consumables", detail: updateErr }),
            { status: 500, headers: { "content-type": "application/json" } },
          );
        }
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        applied: totalEvents,
        factor,
        warnings,
      }),
      { headers: { "content-type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "unhandled", detail: String(err) }),
      { status: 500, headers: { "content-type": "application/json" } },
    );
  }
});
