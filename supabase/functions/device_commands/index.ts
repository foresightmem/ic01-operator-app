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

async function authenticate(req: Request, rawBody: string): Promise<
  { deviceId: string; devicePk: string } | Response
> {
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

  return { deviceId, devicePk: device.id };
}

serve(async (req) => {
  try {
    const url = new URL(req.url);
    if (req.method === "GET" && url.pathname.endsWith("/ack")) {
      return new Response("Method not allowed", { status: 405 });
    }

    if (req.method === "GET") {
      const auth = await authenticate(req, "");
      if (auth instanceof Response) {
        return auth;
      }

      const { data: cmd, error: cmdErr } = await supabase
        .from("device_commands")
        .select("id, command, payload")
        .eq("device_id", auth.devicePk)
        .eq("status", "pending")
        .order("created_at", { ascending: true })
        .limit(1)
        .maybeSingle();

      if (cmdErr) {
        return new Response(
          JSON.stringify({ error: "load_commands", detail: cmdErr }),
          { status: 500, headers: { "content-type": "application/json" } },
        );
      }
      if (!cmd) {
        return new Response(null, { status: 204 });
      }

      const { error: sentErr } = await supabase
        .from("device_commands")
        .update({ status: "sent", sent_at: new Date().toISOString() })
        .eq("id", cmd.id);

      if (sentErr) {
        return new Response(
          JSON.stringify({ error: "update_command_status", detail: sentErr }),
          { status: 500, headers: { "content-type": "application/json" } },
        );
      }

      return new Response(
        JSON.stringify({
          command: {
            id: cmd.id,
            command: cmd.command,
            payload: cmd.payload,
          },
        }),
        { headers: { "content-type": "application/json" } },
      );
    }

    if (req.method === "POST" && url.pathname.endsWith("/ack")) {
      const rawBody = await req.text();
      const auth = await authenticate(req, rawBody);
      if (auth instanceof Response) {
        return auth;
      }

      let payload: { command_id?: string; status?: string; message?: string } = {};
      try {
        payload = JSON.parse(rawBody);
      } catch (err) {
        return new Response(
          JSON.stringify({ error: "invalid_json", detail: String(err) }),
          { status: 400, headers: { "content-type": "application/json" } },
        );
      }

      const commandId = payload.command_id;
      const status = payload.status;
      if (!commandId || !status) {
        return new Response(
          JSON.stringify({ error: "missing_fields" }),
          { status: 400, headers: { "content-type": "application/json" } },
        );
      }

      const { error: ackErr } = await supabase
        .from("device_commands")
        .update({
          status,
          ack_at: new Date().toISOString(),
        })
        .eq("id", commandId)
        .eq("device_id", auth.devicePk);

      if (ackErr) {
        return new Response(
          JSON.stringify({ error: "ack_failed", detail: ackErr }),
          { status: 500, headers: { "content-type": "application/json" } },
        );
      }

      return new Response(JSON.stringify({ ok: true }), {
        headers: { "content-type": "application/json" },
      });
    }

    return new Response("Method not allowed", { status: 405 });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "unhandled", detail: String(err) }),
      { status: 500, headers: { "content-type": "application/json" } },
    );
  }
});
