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

type BeverageCounts = {
  coffee?: number;
  cappuccino?: number;
  powders?: number;
  idle?: number;
  unknown?: number;
};

type RecipeRow = {
  beverage: string;
  consumable: string;
  delta_units: number;
  require_water_tank: boolean;
};

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

    let payload: { counts?: BeverageCounts } = {};
    try {
      payload = JSON.parse(rawBody);
    } catch (_err) {
      return new Response("Invalid JSON", { status: 400 });
    }

    const counts = payload.counts ?? {};
    const beverageCounts: Record<string, number> = {
      coffee: Number(counts.coffee) || 0,
      cappuccino: Number(counts.cappuccino) || 0,
      powder_drink: Number(counts.powders) || 0,
    };

    const totalEvents =
      beverageCounts.coffee +
      beverageCounts.cappuccino +
      beverageCounts.powder_drink;
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
      .select("water_tank_enabled")
      .eq("id", device.machine_id)
      .maybeSingle();

    if (machineErr) {
      return new Response(
        JSON.stringify({ error: "load_machine", detail: machineErr }),
        { status: 500, headers: { "content-type": "application/json" } },
      );
    }

    const waterEnabled = machineRow?.water_tank_enabled === true;

    const { data: recipes, error: recipeErr } = await supabase
      .from("beverage_recipe_items")
      .select("beverage, consumable, delta_units, require_water_tank");

    if (recipeErr || !recipes) {
      return new Response(
        JSON.stringify({ error: "load_recipes", detail: recipeErr }),
        { status: 500, headers: { "content-type": "application/json" } },
      );
    }

    const recipeRows = (recipes as RecipeRow[]).filter((r) =>
      r.beverage in beverageCounts
    );

    const { data: consumables, error: consErr } = await supabase
      .from("machine_consumables")
      .select("id, type, capacity_units, current_units")
      .eq("machine_id", device.machine_id);

    if (consErr || !consumables) {
      return new Response(
        JSON.stringify({ error: "load_consumables", detail: consErr }),
        { status: 500, headers: { "content-type": "application/json" } },
      );
    }

    const currentByType = new Map<string, number>();
    const capacityByType = new Map<string, number>();
    const idByType = new Map<string, string>();
    for (const row of consumables as Array<{ id: string; type: string; capacity_units: number; current_units: number }>) {
      idByType.set(row.type, row.id);
      capacityByType.set(row.type, Number(row.capacity_units) || 0);
      currentByType.set(row.type, Number(row.current_units) || 0);
    }

    const warnings: string[] = [];

    for (const r of recipeRows) {
      const count = beverageCounts[r.beverage] || 0;
      if (count <= 0) continue;
      if (r.require_water_tank && !waterEnabled) {
        warnings.push(`skip ${r.beverage}:${r.consumable} water_tank_disabled`);
        continue;
      }
      if (!currentByType.has(r.consumable) || !capacityByType.has(r.consumable)) {
        warnings.push(`missing consumable ${r.consumable}`);
        continue;
      }

      const capacity = capacityByType.get(r.consumable) ?? 0;
      if (capacity <= 0) {
        warnings.push(`invalid capacity ${r.consumable}`);
        continue;
      }

      const cur = currentByType.get(r.consumable) ?? 0;
      const next = cur + r.delta_units * count;
      const clamped = Math.min(Math.max(next, 0), capacity); // TODO: investigate underflow/overflow
      currentByType.set(r.consumable, clamped);
    }

    const updates = Array.from(currentByType.entries())
      .map(([type, current_units]) => {
        const id = idByType.get(type);
        return id ? { id, current_units } : null;
      })
      .filter((u): u is { id: string; current_units: number } => u !== null);

    for (const u of updates) {
      const { error: updateErr } = await supabase
        .from("machine_consumables")
        .update({ current_units: u.current_units })
        .eq("id", u.id);
      if (updateErr) {
        return new Response(
          JSON.stringify({ error: "update_consumables", detail: updateErr }),
          { status: 500, headers: { "content-type": "application/json" } },
        );
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        applied: totalEvents,
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
