import { timingSafeEqual } from "node:crypto";
import { AppError, errorBody } from "./errors.mjs";
import { IdempotencyStore } from "./idempotency.mjs";
import { assertProvider } from "./providers/provider.mjs";
import { LIMITS, validateReadingRequest } from "./validation.mjs";

const MAX_ANSWER_BYTES = 32_768;

function json(response, status, body) {
  const encoded = JSON.stringify(body);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(encoded),
    "Cache-Control": "no-store",
  });
  response.end(encoded);
}

function authorized(request, token) {
  const value = request.headers.authorization ?? "";
  const expected = `Bearer ${token}`;
  const a = Buffer.from(value);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

async function readJSON(request) {
  const declared = Number.parseInt(request.headers["content-length"] ?? "0", 10);
  if (declared > LIMITS.bodyBytes) {
    throw new AppError("payload_too_large", 413, "Request body is too large", false);
  }
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > LIMITS.bodyBytes) {
      throw new AppError("payload_too_large", 413, "Request body is too large", false);
    }
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new AppError("invalid_json", 400, "Request body must be valid JSON", false); }
}

export function createApp({ config, provider, idempotency = new IdempotencyStore(), logger = console }) {
  assertProvider(provider);
  return async function app(request, response) {
    const started = Date.now();
    let requestId;
    try {
      const url = new URL(request.url, "http://backend.local");
      if (request.method === "GET" && url.pathname === "/health") {
        json(response, 200, { status: "ok", protocol_version: 1 });
        return;
      }
      if (!authorized(request, config.deviceAccessToken)) {
        throw new AppError("authentication", 401, "Device token was rejected", false);
      }
      if (request.method === "GET" && url.pathname === "/v1/config") {
        json(response, 200, { status: "ok", protocol_version: 1, question_types: ["text"] });
        return;
      }
      if (request.method !== "POST" || url.pathname !== "/v1/reading/answer") {
        throw new AppError("not_found", 404, "Endpoint not found", false);
      }
      const payload = validateReadingRequest(await readJSON(request));
      requestId = payload.request_id;
      const result = await idempotency.run(requestId, async () => {
        const providerResult = await provider.answer(payload);
        if (!providerResult || typeof providerResult.responseId !== "string"
            || typeof providerResult.answer !== "string" || !providerResult.answer.trim()
            || Buffer.byteLength(providerResult.answer, "utf8") > MAX_ANSWER_BYTES) {
          throw new AppError("malformed_provider_response", 502,
            "Provider returned an invalid answer", false);
        }
        return {
          schema_version: 1,
          request_id: requestId,
          response_id: providerResult.responseId,
          status: "completed",
          answer: providerResult.answer,
          created_at: payload.created_at,
          completed_at: Math.floor(Date.now() / 1000),
          metadata: { provider: "configured", model: providerResult.model },
        };
      });
      json(response, 200, result);
      logger.info?.({ event: "reading_answer", request_id: requestId, status: "completed", duration_ms: Date.now() - started });
    } catch (error) {
      const safe = error instanceof AppError ? error
        : new AppError("internal_error", 500, "The backend could not complete the request", true);
      json(response, safe.status, errorBody(safe));
      logger.warn?.({ event: "reading_answer", request_id: requestId, status: safe.category, duration_ms: Date.now() - started });
    }
  };
}
