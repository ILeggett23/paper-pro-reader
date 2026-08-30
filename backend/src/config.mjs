import { AppError } from "./errors.mjs";

function positiveInteger(value, fallback) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function loadConfig(env = process.env) {
  const config = {
    port: positiveInteger(env.PORT, 8787),
    host: env.HOST || "127.0.0.1",
    deviceAccessToken: env.DEVICE_ACCESS_TOKEN ?? "",
    openaiApiKey: env.OPENAI_API_KEY ?? "",
    openaiModel: env.OPENAI_MODEL || "gpt-5.4-mini",
    providerTimeoutMs: positiveInteger(env.PROVIDER_TIMEOUT_MS, 30_000),
    idempotencyPath: env.IDEMPOTENCY_DB_PATH || "./data/idempotency.json",
    idempotencyTtlMs: positiveInteger(env.IDEMPOTENCY_TTL_SECONDS, 86_400) * 1_000,
  };
  if (!config.deviceAccessToken) {
    throw new AppError("configuration", 503, "DEVICE_ACCESS_TOKEN is not configured", false);
  }
  return config;
}
