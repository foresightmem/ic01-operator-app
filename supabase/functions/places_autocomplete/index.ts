import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type AutocompletePayload = {
  action?: "autocomplete";
  input?: unknown;
  sessionToken?: unknown;
};

type DetailsPayload = {
  action?: "details";
  placeId?: unknown;
  sessionToken?: unknown;
};

type ResolvePayload = {
  action?: "resolve";
  input?: unknown;
  sessionToken?: unknown;
};

type GoogleAddressComponent = {
  longText?: string;
  shortText?: string;
  types?: string[];
};

const googleApiKey = Deno.env.get("GOOGLE_MAPS_API_KEY") ?? "";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function logDiagnostic(message: string, fields: Record<string, unknown> = {}) {
  console.log(`[AddressAutocomplete] ${message}`, fields);
}

async function googleErrorResponse(
  response: Response,
  logKey: string,
  userMessage: string,
): Promise<Response> {
  const text = await response.text();
  let googleStatus: string | null = null;
  let googleMessage: string | null = null;

  try {
    const payload = JSON.parse(text) as Record<string, unknown>;
    const error = payload.error as Record<string, unknown> | undefined;
    googleStatus = readText(error?.status) || null;
    googleMessage = readText(error?.message) || null;
  } catch (_) {
    googleMessage = text.slice(0, 240);
  }

  console.error(`[AddressAutocomplete] ${logKey}`, {
    http_status: response.status,
    google_status: googleStatus,
    google_message: googleMessage,
  });

  return jsonResponse(
    {
      message: userMessage,
      google_status: googleStatus,
    },
    502,
  );
}

function readText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function decodeBase64Url(value: string): string {
  const padded = value.padEnd(value.length + ((4 - value.length % 4) % 4), "=");
  return atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
}

function jwtRole(req: Request): string | null {
  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.toLowerCase().startsWith("bearer ")
    ? authorization.slice(7)
    : "";
  const payload = token.split(".")[1];
  if (!payload) return null;

  try {
    const claims = JSON.parse(decodeBase64Url(payload)) as Record<
      string,
      unknown
    >;
    return readText(claims.role);
  } catch (_) {
    return null;
  }
}

function findComponent(
  components: GoogleAddressComponent[] | undefined,
  types: string[],
): string | null {
  if (!Array.isArray(components)) return null;

  for (const type of types) {
    const match = components.find((component) =>
      component.types?.includes(type)
    );
    const value = match?.longText?.trim() || match?.shortText?.trim();
    if (value) return value;
  }

  return null;
}

function titleCaseCity(value: string): string {
  return value
    .toLocaleLowerCase("it-IT")
    .split(/\s+/)
    .map((word) => word.charAt(0).toLocaleUpperCase("it-IT") + word.slice(1))
    .join(" ");
}

function fallbackCityFromText(value: string): string | null {
  const text = readText(value);
  if (!text) return null;

  const knownCities: Record<string, string> = {
    roma: "Roma",
    milano: "Milano",
    napoli: "Napoli",
    torino: "Torino",
    palermo: "Palermo",
    genova: "Genova",
    bologna: "Bologna",
    firenze: "Firenze",
    bari: "Bari",
    catania: "Catania",
    venezia: "Venezia",
    verona: "Verona",
    padova: "Padova",
  };

  const normalized = text
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("it-IT");
  for (const [needle, city] of Object.entries(knownCities)) {
    if (new RegExp(`\\b${needle}\\b`, "i").test(normalized)) {
      return city;
    }
  }

  const streetWords = new Set([
    "via",
    "viale",
    "piazza",
    "corso",
    "largo",
    "strada",
    "vicolo",
    "contrada",
    "localita",
    "località",
  ]);

  const candidates = text
    .split(",")
    .map((part) =>
      part
        .replace(/\b\d{5}\b/g, "")
        .replace(/\b[A-Z]{2}\b/g, "")
        .replace(/\b(italia|italy)\b/ig, "")
        .replace(/\s+/g, " ")
        .trim()
    )
    .filter(Boolean)
    .reverse();

  for (const candidate of candidates) {
    const firstWord = candidate
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLocaleLowerCase("it-IT")
      .split(/\s+/)[0];
    if (!streetWords.has(firstWord) && /[A-Za-zÀ-ÿ]/.test(candidate)) {
      return titleCaseCity(candidate);
    }
  }

  const words = text.match(/[A-Za-zÀ-ÿ']+/g) ?? [];
  for (const word of words.reverse()) {
    const normalizedWord = word
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLocaleLowerCase("it-IT");
    if (word.length > 2 && !streetWords.has(normalizedWord)) {
      return titleCaseCity(word);
    }
  }

  return null;
}

function predictionsFromGoogle(data: Record<string, unknown>) {
  const suggestions = Array.isArray(data.suggestions) ? data.suggestions : [];
  return suggestions
    .map((suggestion: Record<string, unknown>) => {
      const placePrediction = suggestion.placePrediction as
        | Record<string, unknown>
        | undefined;
      const text = placePrediction?.text as Record<string, unknown> | undefined;
      return {
        place_id: readText(placePrediction?.placeId),
        description: readText(text?.text),
      };
    })
    .filter((prediction: { place_id: string; description: string }) =>
      prediction.place_id && prediction.description
    );
}

async function autocomplete(payload: AutocompletePayload): Promise<Response> {
  const input = readText(payload.input);
  const sessionToken = readText(payload.sessionToken);
  logDiagnostic("query", { input_length: input.length });

  if (input.length < 3) {
    logDiagnostic("query too short");
    return jsonResponse({ predictions: [] });
  }

  logDiagnostic("request started", { action: "autocomplete" });
  const response = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-goog-api-key": googleApiKey,
      "x-goog-fieldmask":
        "suggestions.placePrediction.placeId,suggestions.placePrediction.text",
    },
    body: JSON.stringify({
      input,
      sessionToken: sessionToken || undefined,
      languageCode: "it",
      regionCode: "IT",
      includedRegionCodes: ["it"],
    }),
  });
  logDiagnostic("HTTP", { status: response.status, action: "autocomplete" });

  if (!response.ok) {
    return await googleErrorResponse(
      response,
      "google_places_autocomplete_failed",
      "Ricerca indirizzi temporaneamente non disponibile.",
    );
  }

  const data = await response.json();
  const predictions = predictionsFromGoogle(data).slice(0, 6);
  logDiagnostic("suggestions", { count: predictions.length });

  return jsonResponse({ predictions });
}

async function detailsForPlace(
  placeId: string,
  sessionToken: string,
  fallbackInput = "",
): Promise<Response> {
  if (!placeId) {
    return jsonResponse({ message: "Indirizzo non valido." }, 400);
  }

  const url = new URL(`https://places.googleapis.com/v1/places/${placeId}`);
  if (sessionToken) {
    url.searchParams.set("sessionToken", sessionToken);
  }
  url.searchParams.set("languageCode", "it");

  logDiagnostic("request started", { action: "details" });
  const response = await fetch(url, {
    headers: {
      "x-goog-api-key": googleApiKey,
      "x-goog-fieldmask": "id,formattedAddress,addressComponents,location",
    },
  });
  logDiagnostic("HTTP", { status: response.status, action: "details" });

  if (!response.ok) {
    return await googleErrorResponse(
      response,
      "google_place_details_failed",
      "Indirizzo temporaneamente non disponibile.",
    );
  }

  const data = await response.json();
  const components = data.addressComponents as
    | GoogleAddressComponent[]
    | undefined;
  const location = data.location as Record<string, unknown> | undefined;
  const formattedAddress = readText(data.formattedAddress);
  const city = findComponent(components, [
    "locality",
    "postal_town",
    "administrative_area_level_3",
    "administrative_area_level_2",
  ]) ?? fallbackCityFromText(formattedAddress) ??
    fallbackCityFromText(fallbackInput);

  return jsonResponse({
    place_id: readText(data.id),
    address: formattedAddress,
    city,
    postal_code: findComponent(components, ["postal_code"]),
    province: findComponent(components, ["administrative_area_level_2"]),
    region: findComponent(components, ["administrative_area_level_1"]),
    country: findComponent(components, ["country"]),
    latitude: typeof location?.latitude === "number"
      ? location.latitude
      : null,
    longitude: typeof location?.longitude === "number"
      ? location.longitude
      : null,
  });
}

async function details(payload: DetailsPayload): Promise<Response> {
  return await detailsForPlace(
    readText(payload.placeId),
    readText(payload.sessionToken),
  );
}

async function resolveInput(payload: ResolvePayload): Promise<Response> {
  const input = readText(payload.input);
  const sessionToken = readText(payload.sessionToken);
  logDiagnostic("query", { action: "resolve", input_length: input.length });

  if (input.length < 3) {
    return jsonResponse({ address: input, city: null });
  }

  logDiagnostic("request started", { action: "resolve_autocomplete" });
  const response = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-goog-api-key": googleApiKey,
      "x-goog-fieldmask":
        "suggestions.placePrediction.placeId,suggestions.placePrediction.text",
    },
    body: JSON.stringify({
      input,
      sessionToken: sessionToken || undefined,
      languageCode: "it",
      regionCode: "IT",
      includedRegionCodes: ["it"],
    }),
  });
  logDiagnostic("HTTP", { status: response.status, action: "resolve_autocomplete" });

  if (!response.ok) {
    await googleErrorResponse(
      response,
      "google_places_resolve_autocomplete_failed",
      "Indirizzo temporaneamente non disponibile.",
    );
    return jsonResponse({ address: input, city: null });
  }

  const data = await response.json();
  const first = predictionsFromGoogle(data)[0];
  if (!first?.place_id) {
    return jsonResponse({ address: input, city: null });
  }

  return await detailsForPlace(first.place_id, sessionToken, input);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ message: "Metodo non consentito." }, 405);
  }

  if (!googleApiKey) {
    console.error("[AddressAutocomplete] API key missing");
    return jsonResponse(
      { message: "Ricerca indirizzi non configurata." },
      500,
    );
  }

  if (jwtRole(req) !== "authenticated") {
    console.error("[AddressAutocomplete] unauthorized request");
    return jsonResponse({ message: "Accesso non autorizzato." }, 401);
  }

  try {
    const payload = await req.json() as AutocompletePayload | DetailsPayload;

    if (payload.action === "autocomplete") {
      return await autocomplete(payload);
    }

    if (payload.action === "details") {
      return await details(payload);
    }

    if (payload.action === "resolve") {
      return await resolveInput(payload);
    }

    return jsonResponse({ message: "Azione non valida." }, 400);
  } catch (err) {
    console.error("places_autocomplete_unhandled", err);
    return jsonResponse(
      { message: "Ricerca indirizzi temporaneamente non disponibile." },
      500,
    );
  }
});
