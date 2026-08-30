import { AppError } from "../errors.mjs";
import { buildProviderInput } from "../prompt.mjs";

function outputText(payload) {
  const pieces = [];
  for (const item of payload?.output ?? []) {
    if (item?.type !== "message") continue;
    for (const content of item.content ?? []) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        pieces.push(content.text);
      }
    }
  }
  return pieces.join("\n").trim();
}

function recognitionResult(text) {
  const cleaned = text.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  let value;
  try { value = JSON.parse(cleaned); } catch { return null; }
  if (!value || !["clear", "uncertain", "unreadable"].includes(value.recognition_status)
      || typeof value.clarification_required !== "boolean"
      || typeof value.answer !== "string" || !value.answer.trim()
      || (value.recognized_question != null && typeof value.recognized_question !== "string")) return null;
  return value;
}

export class OpenAIProvider {
  constructor({ apiKey, model, timeoutMs = 30_000, fetchImpl = globalThis.fetch }) {
    this.apiKey = apiKey;
    this.model = model;
    this.timeoutMs = timeoutMs;
    this.fetch = fetchImpl;
  }

  async answer(request) {
    if (!this.apiKey) {
      throw new AppError("provider_not_configured", 503, "AI provider is not configured", false);
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const prompt = buildProviderInput(request);
      const response = await this.fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: this.model,
          store: false,
          instructions: prompt.instructions,
          input: prompt.input,
          max_output_tokens: request.preferences.response_length === "standard" ? 1200 : 700,
        }),
        signal: controller.signal,
      });
      let payload;
      try { payload = await response.json(); } catch { payload = null; }
      if (!response.ok) {
        if (response.status === 429) {
          throw new AppError("rate_limited", 429, "Provider rate limit reached", true);
        }
        if (response.status >= 500) {
          throw new AppError("provider_unavailable", 503, "Provider is temporarily unavailable", true);
        }
        if (request.question.type === "ink" && response.status === 400) {
          throw new AppError("model_capability", 400,
            "Configured model does not accept handwriting images", false);
        }
        throw new AppError("provider_error", 502, "Provider rejected the request", false);
      }
      const answer = outputText(payload);
      if (!answer) throw new AppError("malformed_provider_response", 502, "Provider returned no text", true);
      if (request.question.type === "ink") {
        const recognition = recognitionResult(answer);
        if (!recognition) throw new AppError("malformed_provider_response", 502,
          "Provider returned invalid handwriting recognition", true);
        return { responseId: payload.id, answer: recognition.answer,
          recognizedQuestion: recognition.recognized_question,
          recognitionStatus: recognition.recognition_status,
          clarificationRequired: recognition.clarification_required,
          model: payload.model ?? this.model };
      }
      return { responseId: payload.id, answer, model: payload.model ?? this.model };
    } catch (error) {
      if (error instanceof AppError) throw error;
      if (error?.name === "AbortError") {
        throw new AppError("provider_timeout", 504, "Provider request timed out", true);
      }
      throw new AppError("provider_unavailable", 503, "Provider could not be reached", true);
    } finally {
      clearTimeout(timeout);
    }
  }
}

export { outputText, recognitionResult };
