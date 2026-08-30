import { AppError } from "./errors.mjs";

export const LIMITS = Object.freeze({
  bodyBytes: 65_536,
  questionBytes: 1_024,
  selectionBytes: 8_192,
  sentenceBytes: 4_096,
  paragraphBytes: 6_144,
  sideBytes: 4_096,
  sourceBytes: 16_384,
  metadataBytes: 512,
});

const byteLength = value => Buffer.byteLength(value ?? "", "utf8");

function requiredString(value, name, limit) {
  if (typeof value !== "string" || !value.trim()) {
    throw new AppError("invalid_payload", 400, `${name} is required`, false);
  }
  if (byteLength(value) > limit) {
    throw new AppError("payload_too_large", 413, `${name} is too large`, false);
  }
  return value.trim();
}

function optionalString(value, name, limit) {
  if (value == null || value === "") return undefined;
  if (typeof value !== "string" || byteLength(value) > limit) {
    throw new AppError("invalid_payload", 400, `${name} is invalid`, false);
  }
  return value.trim() || undefined;
}

function authorValue(author) {
  if (author == null) return undefined;
  if (typeof author === "string") return optionalString(author, "book.author", LIMITS.metadataBytes);
  if (!Array.isArray(author) || author.length > 8) {
    throw new AppError("invalid_payload", 400, "book.author is invalid", false);
  }
  return author.map((value, index) => requiredString(value, `book.author[${index}]`, LIMITS.metadataBytes));
}

export function validateReadingRequest(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)
      || payload.schema_version !== 1) {
    throw new AppError("unsupported_schema", 400, "Unsupported request schema", false);
  }
  const requestId = requiredString(payload.request_id, "request_id", 128);
  if (!payload.question || payload.question.type !== "text") {
    throw new AppError("unsupported_question_type", 400, "Only text questions are supported", false);
  }
  const question = requiredString(payload.question.text, "question.text", LIMITS.questionBytes);
  const reading = payload.reading_context;
  if (!reading || reading.schema_version !== 1 || !reading.book || !reading.selection) {
    throw new AppError("invalid_payload", 400, "reading_context is invalid", false);
  }
  if (reading.book.document_id != null || reading.location?.anchor != null) {
    throw new AppError("invalid_payload", 400, "Local navigation data must not be transmitted", false);
  }
  const selection = requiredString(reading.selection.text, "selection.text", LIMITS.selectionBytes);
  const context = reading.context ?? {};
  const normalizedContext = {
    before: optionalString(context.before, "context.before", LIMITS.sideBytes),
    after: optionalString(context.after, "context.after", LIMITS.sideBytes),
    sentence: optionalString(context.sentence, "context.sentence", LIMITS.sentenceBytes),
    paragraph: optionalString(context.paragraph, "context.paragraph", LIMITS.paragraphBytes),
  };
  const sourceBytes = byteLength(selection)
    + Object.values(normalizedContext).reduce((total, value) => total + byteLength(value), 0);
  if (sourceBytes > LIMITS.sourceBytes) {
    throw new AppError("payload_too_large", 413, "Book context exceeds the source budget", false);
  }
  const mode = payload.preferences?.context_mode ?? reading.context_mode ?? "nearby";
  if (mode !== "minimal" && mode !== "nearby") {
    throw new AppError("invalid_payload", 400, "context_mode is invalid", false);
  }
  const responseLength = payload.preferences?.response_length ?? "concise";
  if (!["concise", "standard"].includes(responseLength)) {
    throw new AppError("invalid_payload", 400, "response_length is invalid", false);
  }
  return {
    schema_version: 1,
    request_id: requestId,
    created_at: Number.isFinite(payload.created_at) ? payload.created_at : Math.floor(Date.now() / 1000),
    question: { type: "text", text: question },
    reading_context: {
      schema_version: 1,
      book: {
        title: optionalString(reading.book.title, "book.title", LIMITS.metadataBytes),
        author: authorValue(reading.book.author),
      },
      location: {
        chapter: optionalString(reading.location?.chapter, "location.chapter", LIMITS.metadataBytes),
      },
      selection: {
        text: selection,
        selected_word: optionalString(reading.selection.selected_word, "selection.selected_word", 256),
      },
      context: normalizedContext,
      context_mode: mode,
      truncation: reading.truncation?.any === true ? { any: true } : { any: false },
      capabilities: typeof reading.capabilities === "object" ? {
        sentence: reading.capabilities.sentence === true,
        paragraph: reading.capabilities.paragraph === true,
        semantic_context: reading.capabilities.semantic_context === true,
        fixed_layout: reading.capabilities.fixed_layout === true,
      } : {},
    },
    preferences: { response_length: responseLength, context_mode: mode },
  };
}
