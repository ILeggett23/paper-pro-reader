import { AppError } from "./errors.mjs";

export const LIMITS = Object.freeze({
  bodyBytes: 400_000,
  questionBytes: 1_024,
  selectionBytes: 8_192,
  sentenceBytes: 4_096,
  paragraphBytes: 6_144,
  sideBytes: 4_096,
  sourceBytes: 16_384,
  metadataBytes: 512,
  imageBytes: 256 * 1024,
  imageWidth: 1_200,
  imageHeight: 512,
  imagePixels: 600_000,
  historyTurns: 6,
  historyBytes: 8_192,
});

const byteLength = value => Buffer.byteLength(value ?? "", "utf8");

function requiredString(value, name, limit) {
  if (typeof value !== "string" || !value.trim()) {
    throw new AppError("invalid_payload", 400, `${name} is required`, false);
  }
  if (byteLength(value) > limit) throw new AppError("payload_too_large", 413, `${name} is too large`, false);
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
  if (!Array.isArray(author) || author.length > 8) throw new AppError("invalid_payload", 400, "book.author is invalid", false);
  return author.map((value, index) => requiredString(value, `book.author[${index}]`, LIMITS.metadataBytes));
}

function decodePNG(image) {
  if (!image || image.mime_type !== "image/png" || typeof image.data_base64 !== "string"
      || !Number.isInteger(image.bytes) || !Number.isInteger(image.width)
      || !Number.isInteger(image.height)) {
    throw new AppError("invalid_image", 400, "Handwriting image metadata is invalid", false);
  }
  if (image.bytes < 24) throw new AppError("invalid_image", 400, "Handwriting image is malformed", false);
  if (image.bytes > LIMITS.imageBytes) {
    throw new AppError("image_too_large", 413, "Handwriting image is too large", false);
  }
  let bytes;
  try { bytes = Buffer.from(image.data_base64, "base64"); }
  catch { throw new AppError("invalid_image", 400, "Handwriting image is malformed", false); }
  if (bytes.length !== image.bytes || bytes.toString("base64").replace(/=+$/, "")
      !== image.data_base64.replace(/\s+/g, "").replace(/=+$/, "")) {
    throw new AppError("invalid_image", 400, "Handwriting image encoding is invalid", false);
  }
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!bytes.subarray(0, 8).equals(signature) || bytes.toString("ascii", 12, 16) !== "IHDR") {
    throw new AppError("invalid_image", 400, "Handwriting image is not a PNG", false);
  }
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  if (width !== image.width || height !== image.height || width < 1 || height < 1
      || width > LIMITS.imageWidth || height > LIMITS.imageHeight
      || width * height > LIMITS.imagePixels) {
    throw new AppError("invalid_image_dimensions", 400, "Handwriting image dimensions are invalid", false);
  }
  return { mime_type: "image/png", data_base64: image.data_base64.replace(/\s+/g, ""),
    bytes: bytes.length, width, height };
}

function validateConversation(value, schemaVersion) {
  if (schemaVersion === 1) return undefined;
  const historySource = Array.isArray(value?.history) ? value.history
    : value?.history && typeof value.history === "object"
      && Object.keys(value.history).length === 0 ? [] : null;
  if (!value || typeof value.id !== "string" || typeof value.turn_id !== "string"
      || !historySource || historySource.length > LIMITS.historyTurns) {
    throw new AppError("invalid_conversation", 400, "Conversation metadata is invalid", false);
  }
  let bytes = 0;
  const history = historySource.map((turn, index) => {
    const question = requiredString(turn?.question, `history[${index}].question`, 2_048);
    const answer = requiredString(turn?.answer, `history[${index}].answer`, 8_192);
    bytes += byteLength(question) + byteLength(answer);
    return { question, answer };
  });
  if (bytes > LIMITS.historyBytes) throw new AppError("payload_too_large", 413, "Conversation history is too large", false);
  return { id: value.id, turn_id: value.turn_id, history,
    history_truncated: value.history_truncated === true };
}

export function validateReadingRequest(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)
      || ![1, 2].includes(payload.schema_version)) {
    throw new AppError("unsupported_schema", 400, "Unsupported request schema", false);
  }
  const requestId = requiredString(payload.request_id, "request_id", 128);
  let question;
  if (payload.question?.type === "text") {
    question = { type: "text", text: requiredString(payload.question.text, "question.text", LIMITS.questionBytes) };
  } else if (payload.schema_version === 2 && payload.question?.type === "ink") {
    question = { type: "ink", image: decodePNG(payload.question.image),
      recognized_text: optionalString(payload.question.recognized_text, "question.recognized_text", LIMITS.questionBytes) };
  } else {
    throw new AppError("unsupported_question_type", 400, "Question type is unsupported", false);
  }
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
  if (sourceBytes > LIMITS.sourceBytes) throw new AppError("payload_too_large", 413, "Book context exceeds the source budget", false);
  const mode = payload.preferences?.context_mode ?? reading.context_mode ?? "nearby";
  if (!['minimal', 'nearby'].includes(mode)) throw new AppError("invalid_payload", 400, "context_mode is invalid", false);
  const responseLength = payload.preferences?.response_length ?? "concise";
  if (!["concise", "standard"].includes(responseLength)) throw new AppError("invalid_payload", 400, "response_length is invalid", false);
  return {
    schema_version: payload.schema_version, request_id: requestId,
    created_at: Number.isFinite(payload.created_at) ? payload.created_at : Math.floor(Date.now() / 1000),
    question,
    conversation: validateConversation(payload.conversation, payload.schema_version),
    reading_context: {
      schema_version: 1,
      book: { title: optionalString(reading.book.title, "book.title", LIMITS.metadataBytes),
        author: authorValue(reading.book.author) },
      location: { chapter: optionalString(reading.location?.chapter, "location.chapter", LIMITS.metadataBytes) },
      selection: { text: selection,
        selected_word: optionalString(reading.selection.selected_word, "selection.selected_word", 256) },
      context: normalizedContext, context_mode: mode,
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

export { decodePNG };
