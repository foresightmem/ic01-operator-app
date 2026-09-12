import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type OutboxRow = {
  id: string;
  user_id: string;
  title: string;
  body: string;
  data: Record<string, unknown> | null;
  attempts: number;
};

type PushTokenRow = {
  id: string;
  token: string;
  platform: "android" | "ios" | "web";
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const cronSecret = Deno.env.get("NOTIFICATION_CRON_SECRET") ?? "";
const firebaseProjectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
const firebaseServiceAccountJson =
  Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

function jsonError(code: string, status = 500): Response {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

const FCM_ENDPOINT = (projectId: string) =>
  `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
const BATCH_LIMIT = 50;
const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

let cachedAccessToken = "";
let cachedAccessTokenExpiry = 0;

function isAuthorized(req: Request): boolean {
  const auth = req.headers.get("authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const cronHeader = req.headers.get("x-cron-secret") ?? "";

  if (cronSecret) {
    return bearer === cronSecret || cronHeader === cronSecret;
  }

  return bearer === serviceRoleKey;
}

function base64UrlEncode(input: Uint8Array): string {
  const binary = Array.from(input)
    .map((b) => String.fromCharCode(b))
    .join("");
  const base64 = btoa(binary);
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function signJwt(
  serviceAccount: {
    client_email: string;
    private_key: string;
    token_uri?: string;
  },
): Promise<string> {
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 3600;
  const tokenUri =
    serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token";

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: tokenUri,
    iat,
    exp,
    scope: FCM_SCOPE,
  };

  const encoder = new TextEncoder();
  const headerEncoded = base64UrlEncode(encoder.encode(JSON.stringify(header)));
  const payloadEncoded = base64UrlEncode(
    encoder.encode(JSON.stringify(payload)),
  );
  const signingInput = `${headerEncoded}.${payloadEncoded}`;

  const privateKeyPem = serviceAccount.private_key.replace(/\\n/g, "\n");
  const keyData = privateKeyPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");

  const keyBuffer = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBuffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(signingInput),
  );

  const signatureEncoded = base64UrlEncode(new Uint8Array(signature));
  return `${signingInput}.${signatureEncoded}`;
}

async function getAccessToken(): Promise<
  { ok: true; token: string } | { ok: false; error: string }
> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && now < cachedAccessTokenExpiry - 60) {
    return { ok: true, token: cachedAccessToken };
  }

  if (!firebaseServiceAccountJson) {
    return { ok: false, error: "missing_service_account_json" };
  }

  let serviceAccount: {
    client_email: string;
    private_key: string;
    token_uri?: string;
  };
  try {
    serviceAccount = JSON.parse(firebaseServiceAccountJson);
  } catch (err) {
    return { ok: false, error: `invalid_service_account_json:${err}` };
  }

  const assertion = await signJwt(serviceAccount);
  const tokenUri =
    serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token";
  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (!res.ok) {
    return { ok: false, error: `oauth_http_${res.status}` };
  }

  const json = await res.json() as {
    access_token?: string;
    expires_in?: number;
  };
  if (!json.access_token || !json.expires_in) {
    return { ok: false, error: "oauth_invalid_response" };
  }

  cachedAccessToken = json.access_token;
  cachedAccessTokenExpiry = now + json.expires_in;
  return { ok: true, token: json.access_token };
}

async function sendFcm(
  token: string,
  title: string,
  body: string,
  data: Record<string, unknown>,
): Promise<{ ok: boolean; error?: string; unregister?: boolean }> {
  if (!firebaseProjectId) {
    return { ok: false, error: "missing_firebase_project_id" };
  }

  const accessToken = await getAccessToken();
  if (!accessToken.ok) {
    return { ok: false, error: accessToken.error };
  }

  const payload = {
    message: {
      token,
      notification: { title, body },
      data,
    },
  };

  const res = await fetch(FCM_ENDPOINT(firebaseProjectId), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${accessToken.token}`,
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    return { ok: false, error: `http_${res.status}` };
  }

  const json = await res.json() as { error?: { status?: string } };
  if (json.error?.status) {
    const unregister =
      json.error.status === "NOT_FOUND" ||
      json.error.status === "UNREGISTERED";
    return { ok: false, error: json.error.status, unregister };
  }

  return { ok: true };
}

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    if (!isAuthorized(req)) {
      return new Response("Unauthorized", { status: 401 });
    }

    const nowIso = new Date().toISOString();
    const { data: outbox, error: outboxErr } = await supabase
      .from("notification_outbox")
      .select("id,user_id,title,body,data,attempts")
      .eq("status", "pending")
      .lte("scheduled_for", nowIso)
      .order("scheduled_for", { ascending: true })
      .limit(BATCH_LIMIT);

    if (outboxErr) {
      console.error("load_outbox", outboxErr);
      return jsonError("load_outbox");
    }

    const rows = (outbox ?? []) as OutboxRow[];
    const results: Array<{ id: string; status: string; error?: string }> = [];

    for (const row of rows) {
      const { data: tokens, error: tokenErr } = await supabase
        .from("push_tokens")
        .select("id,token,platform")
        .eq("user_id", row.user_id);

      if (tokenErr) {
        await supabase
          .from("notification_outbox")
          .update({
            status: "failed",
            attempts: row.attempts + 1,
            last_error: "load_tokens",
          })
          .eq("id", row.id);
        results.push({ id: row.id, status: "failed", error: "load_tokens" });
        continue;
      }

      const tokensList = (tokens ?? []) as PushTokenRow[];
      if (tokensList.length === 0) {
        await supabase
          .from("notification_outbox")
          .update({
            status: "failed",
            attempts: row.attempts + 1,
            last_error: "no_tokens",
          })
          .eq("id", row.id);
        results.push({ id: row.id, status: "failed", error: "no_tokens" });
        continue;
      }

      let anySuccess = false;
      let lastError = "";
      for (const tokenRow of tokensList) {
        const payloadData = {
          ...(row.data ?? {}),
          route: "/dashboard",
        };
        const sendResult = await sendFcm(
          tokenRow.token,
          row.title,
          row.body,
          payloadData,
        );

        if (sendResult.ok) {
          anySuccess = true;
        } else {
          lastError = sendResult.error ?? "send_failed";
          if (sendResult.unregister) {
            await supabase
              .from("push_tokens")
              .delete()
              .eq("id", tokenRow.id);
          }
        }
      }

      if (anySuccess) {
        await supabase
          .from("notification_outbox")
          .update({
            status: "sent",
            attempts: row.attempts + 1,
            sent_at: new Date().toISOString(),
            last_error: null,
          })
          .eq("id", row.id);
        results.push({ id: row.id, status: "sent" });
      } else {
        await supabase
          .from("notification_outbox")
          .update({
            status: "failed",
            attempts: row.attempts + 1,
            last_error: lastError || "send_failed",
          })
          .eq("id", row.id);
        results.push({
          id: row.id,
          status: "failed",
          error: lastError || "send_failed",
        });
      }
    }

    return new Response(JSON.stringify({ ok: true, processed: results }), {
      headers: { "content-type": "application/json" },
    });
  } catch (err) {
    console.error("unhandled", err);
    return jsonError("unhandled");
  }
});
