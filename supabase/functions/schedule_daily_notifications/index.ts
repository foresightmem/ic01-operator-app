import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

type NotificationSetting = {
  user_id: string;
  enabled: boolean;
  hour: number;
  minute: number;
  timezone: string;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const cronSecret = Deno.env.get("NOTIFICATION_CRON_SECRET") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

function jsonError(code: string, status = 500): Response {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function isAuthorized(req: Request): boolean {
  const auth = req.headers.get("authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const cronHeader = req.headers.get("x-cron-secret") ?? "";

  if (cronSecret) {
    return bearer === cronSecret || cronHeader === cronSecret;
  }

  return bearer === serviceRoleKey;
}

function pad2(value: number): string {
  return value.toString().padStart(2, "0");
}

function getDatePartsInTimeZone(
  timeZone: string,
  date: Date,
): { year: number; month: number; day: number } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);

  const map: Record<string, string> = {};
  for (const part of parts) {
    if (part.type !== "literal") map[part.type] = part.value;
  }

  return {
    year: Number(map.year),
    month: Number(map.month),
    day: Number(map.day),
  };
}

function getTimeZoneOffsetMinutes(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).formatToParts(date);

  const map: Record<string, string> = {};
  for (const part of parts) {
    if (part.type !== "literal") map[part.type] = part.value;
  }

  const asUtc = Date.UTC(
    Number(map.year),
    Number(map.month) - 1,
    Number(map.day),
    Number(map.hour),
    Number(map.minute),
    Number(map.second),
  );

  return (date.getTime() - asUtc) / 60000;
}

function scheduledForTodayUtc(setting: NotificationSetting): string {
  const tz = setting.timezone || "Europe/Rome";
  const now = new Date();
  const { year, month, day } = getDatePartsInTimeZone(tz, now);
  const localTargetUtc = Date.UTC(
    year,
    month - 1,
    day,
    setting.hour,
    setting.minute,
    0,
  );

  const offsetMinutes = getTimeZoneOffsetMinutes(
    new Date(localTargetUtc),
    tz,
  );
  const scheduledUtc = localTargetUtc - offsetMinutes * 60000;
  return new Date(scheduledUtc).toISOString();
}

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    if (!isAuthorized(req)) {
      return new Response("Unauthorized", { status: 401 });
    }

    const { data: settings, error: settingsErr } = await supabase
      .from("notification_settings")
      .select("user_id,enabled,hour,minute,timezone")
      .eq("enabled", true);

    if (settingsErr) {
      console.error("load_settings", settingsErr);
      return jsonError("load_settings");
    }

    const items = (settings ?? []) as NotificationSetting[];
    const results: Array<{ user_id: string; scheduled_for: string }> = [];

    for (const setting of items) {
      const scheduledFor = scheduledForTodayUtc(setting);

      const { data: existing } = await supabase
        .from("notification_outbox")
        .select("id")
        .eq("user_id", setting.user_id)
        .eq("scheduled_for", scheduledFor)
        .limit(1);

      if (existing && existing.length > 0) {
        continue;
      }

      const { error: insertErr } = await supabase
        .from("notification_outbox")
        .insert({
          user_id: setting.user_id,
          title: "Nuovo giro di ricariche",
          body: "Apri la dashboard per vedere il piano di oggi.",
          data: { route: "/dashboard" },
          scheduled_for: scheduledFor,
        });

      if (!insertErr) {
        results.push({ user_id: setting.user_id, scheduled_for: scheduledFor });
      }
    }

    return new Response(JSON.stringify({ ok: true, created: results }), {
      headers: { "content-type": "application/json" },
    });
  } catch (err) {
    console.error("unhandled", err);
    return jsonError("unhandled");
  }
});
