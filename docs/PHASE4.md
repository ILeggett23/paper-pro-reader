# Phase 4 — Context-aware AI, secure backend, and offline queue

## Implemented flow

Phase 4 adds one typed contextual question and one completed text answer while
the book remains open:

```text
selection
  -> QuickAskOverlay
  -> ContextResolver
  -> AIReadingRequest
  -> OfflineQueue (persist first)
  -> AIProvider / subprocess HTTPTransport
  -> authenticated reading backend
  -> provider adapter
  -> completed answer
  -> ResponseStore
  -> QuickAskOverlay or AI History
```

The user can close Quick Ask immediately. A completion does not reopen a modal;
it is saved and appears in Study > AI Questions. Reader position is never
changed by compose, queue, sending, answer, error, or dismissal.

Phase 4 accepts `question.type = "text"` only. The request contract can add an
`ink` type later without replacing context, request IDs, queueing,
authentication, saved responses, history, or passage navigation.

## ContextResolver

`frontend/apps/paperpro/services/contextresolver.lua` converts the immutable
Phase 1 SelectionSnapshot into a detached schema-versioned ReadingContext. The
result contains no document, ReaderUI, ReaderHighlight, or mutable selection
object.

EPUB/CREngine context may contain:

- selected passage and optional selected word;
- sentence segment from `extendXPointersToSentenceSegment()`;
- rendered-final-node paragraph text when the existing public HTML seam
  returns a node containing the selection;
- nearest words before and after from `getSelectedWordContext()`;
- title, author, chapter, and an XPointer range kept for local navigation.

PDF/fixed-layout context contains selected text, page/native-position anchor,
title/author/chapter where available, and bounded nearby text from the existing
text-box context seam. It does not claim sentence or paragraph semantics. A
scanned PDF selection with no usable neighboring text retains the selected
OCR/text result and reports the missing capabilities.

Two policies exist:

- `nearby` (default): selection plus reliable sentence/paragraph and nearest
  before/after text.
- `minimal`: selection and book/chapter metadata only.

## Context limits

Limits are measured as UTF-8 bytes on the device and repeated by backend
validation:

| Field | Maximum |
| --- | ---: |
| Question | 1,024 bytes |
| Selected passage | 8,192 bytes |
| Sentence | 4,096 bytes |
| Paragraph | 6,144 bytes |
| Before context | 4,096 bytes |
| After context | 4,096 bytes |
| All transmitted source fields combined | 16,384 bytes |
| Entire backend request body | 65,536 bytes |

Selection has first claim on the source budget. Sentence and paragraph follow;
remaining space is split between the suffix of `before` and prefix of `after`,
so context closest to the selection survives. The selected passage is retained
up to its hard 8,192-byte safety limit. Trimming uses KOReader's UTF-8 repair
helper and records per-field plus aggregate truncation flags.

No full chapter, full PDF page, or unbounded book section is transmitted.

## Device request and privacy boundary

The durable device request is:

```text
schema_version
request_id
created_at
question = { type = "text", text }
reading_context
preferences = { response_length, context_mode }
```

A UUID is created before queueing and remains unchanged across retries,
timeouts, connectivity events, and restarts. The durable local request retains
the document ID and DocumentAnchor so History can return to the source.

Immediately before serialization, AIProvider removes:

- local document/file identity;
- EPUB XPointer or PDF page/native-coordinate anchor.

The backend may receive only:

- request ID and creation time;
- typed question;
- selected passage;
- bounded sentence, paragraph, and before/after fields allowed by context
  mode;
- optional title, author, and chapter;
- non-identifying capability/truncation flags;
- response-length and context-mode preferences.

It does not automatically receive notes, annotations, vocabulary history,
other books, InkStroke data, handwriting rasters, reader settings, file paths,
navigation anchors, or OpenAI conversation history.

## Quick Ask

The existing contextual Ask AI action is enabled when the product AI setting
is enabled and the selection has a valid anchor. It uses ReaderOverlay and
KOReader's existing keyboard widgets.

States:

- **Compose:** selected-passage excerpt, default context mode, multiline typed
  input, Ask, and Cancel.
- **Queued:** static confirmation that the request was saved for later; Close
  and Cancel question remain available.
- **Sending:** static `Thinking…`; no spinner or incremental text.
- **Success:** one completed answer update in a bounded scrollable panel.
- **Error:** stable user-facing message driven by a machine error category,
  with Retry or Edit question as appropriate.
- **Cancelled:** durable cancellation and safe dismissal.

Closing a queued or sending overlay leaves the request alive. Completion while
reading updates storage quietly instead of opening UI. Long answers scroll
inside the compact panel; Phase 4 does not automatically enter a full-screen
conversation.

## Device AI architecture

`AIProvider` knows only the backend URL, a revocable device bearer token, and
the versioned request/response schema. It does not contain OpenAI-specific
model, SDK, organization, project, or provider-key logic.

`HTTPTransport` uses KOReader's LuaSocket/LuaSec and timeout facilities inside
a child process. The main UI checks the result pipe through UIManager
scheduling, so DNS, TLS, request, and response waits do not block reader input.
Responses are capped at 49,152 bytes. Cancellation terminates the owned child
process. Remote URLs must be HTTPS; plain HTTP is accepted only for localhost
development. Certificate verification is never disabled.
HTTPS uses the packaged CA bundle with peer-chain verification plus explicit
subject-alternative-name/common-name hostname matching; wildcard certificates
may match exactly one DNS label.

Network callbacks return durable request IDs and response/error tables.
OfflineQueue owns persistence and response settlement. PaperProReader registers
a removable listener only for visible updates; document close removes that
listener, so an in-flight completion cannot dereference a closed document.

Stable error categories include disabled, not configured, offline, DNS,
timeout, TLS, authentication, rate limit, backend unavailable, request
rejected, malformed response, unsupported schema, cancellation, and local
storage failure. UI code does not parse transport error strings.

## Backend architecture

The isolated `backend/` service uses Node.js 20+ built-ins and no runtime
framework:

```text
Paper Pro
  -> authenticated HTTPS
  -> POST /v1/reading/answer
  -> validation and idempotency
  -> provider interface
  -> OpenAI adapter
  -> OpenAI Responses API
```

Additional endpoints:

- `GET /health`: public liveness and protocol version, no secrets.
- `GET /v1/config`: authenticated client protocol diagnostic.

The concrete adapter uses `POST https://api.openai.com/v1/responses`,
`store: false`, no tools, no web search, no streaming, and a bounded completed
text response. `OPENAI_MODEL` selects the backend model; the development
default is `gpt-5.4-mini`. Provider choice and model remain invisible to device
business logic.

The backend separates developer instructions, the user's question, and a
JSON-encoded block explicitly labeled as untrusted quoted book context. Text
such as “ignore previous instructions” inside a book remains quoted data.

## Authentication and secrets

Secrets are separated:

| Secret | Location | Reaches reader? |
| --- | --- | --- |
| `OPENAI_API_KEY` | backend environment/secret manager | No |
| `DEVICE_ACCESS_TOKEN` server copy | backend environment/secret manager | N/A |
| revocable device token | KOReader settings on the reader | Yes |

The backend compares the bearer token in constant time and prevents an open
public AI relay. `.env` and `.env.*` are ignored; `.env.example` contains
placeholder names only. Production documentation requires HTTPS.

KOReader's normal settings file is the safest already-available device
mechanism used in this phase, but it is not an OS keychain or hardware enclave.
The device token is stored locally in recoverable settings and may be readable
to someone with filesystem/root access. It must therefore be independently
revocable and must never be a provider credential.

Backend logs contain request ID, stable status, and duration. They omit full
questions, excerpts, answers, bearer tokens, and provider keys by default.
AI output is text/data only and is never evaluated as Lua, JavaScript, shell,
or server-returned code.

## OfflineQueue

`paperpro-ai-queue.json` is a versioned global product store in KOReader's
settings directory. It is separate from ReaderAnnotation, Vocabulary Builder,
InkStore, and DocSettings because queued AI work has a different authority and
lifecycle.

Every item retains request, state, attempts, next retry, last machine error,
response reference, and timestamps. States are `queued`, `sending`,
`completed`, `failed`, and `cancelled`.

Persistence writes and fsyncs a temporary file, rotates the prior primary to
`.old`, atomically replaces the primary, and recovers a valid backup after a
malformed primary. Unsupported future schemas fail closed. A `sending` item
found after restart returns to `queued` with the same request ID and an
`interrupted` category.

Only one request is in flight per queue instance. Duplicate connectivity or
Retry events cannot send a second concurrent copy. Network recovery processes
at most three eligible requests sequentially. Retryable errors use 30-second
exponential backoff capped at one hour. Authentication, schema, malformed
request, and configuration failures require user action and stop retrying.

The backend deduplicates pending and completed request IDs for 24 hours, up to
1,000 entries. This in-memory Phase 4 adapter covers one backend process; a
multi-instance/restart-resistant deployment must replace it with a shared
durable adapter behind the same interface.

## Saved responses and AI History

`paperpro-ai-responses.json` atomically stores up to 500 completed exchanges:

```text
request_id, response_id, question, answer
document identity, title, author, chapter
DocumentAnchor, selected/source text
created_at, completed_at, context_mode, status
```

It does not duplicate the full nearby-context payload. Answers remain readable
without network access and are not cloud-synced.

Study > AI Questions lists completed, queued, sending, failed, and cancelled
items for the current book. Detail shows source passage, question, full answer,
status, and Go to passage. Navigation validates current-book EPUB/PDF anchors,
adds the current location to ReaderLink's back stack, and delegates to existing
ReaderRolling or ReaderPaging operations. Stale, malformed, or cross-book
anchors remain readable but cannot navigate.

## E-ink behavior

There are no animations, fades, slides, token streaming, continuously updating
timers, or character-by-character answers. Quick Ask uses:

```text
Compose -> static Thinking… -> one completed answer update
```

ReaderOverlay and normal KOReader widgets retain responsibility for bounded
dirty regions. Product code does not touch UIManager internals, framebuffer,
QTFB, waveforms, or document rendering.

## Verification status

- **Automated device:** focused specs cover EPUB/PDF context and degradation,
  UTF-8 budgets, request schema, provider serialization/errors, durable queue
  recovery/retry/cancel/deduplication, atomic recovery, saved responses,
  navigation, settings, Quick Ask states, History, and composition regressions.
- **Backend:** Node tests use mocked providers for health, authentication,
  validation, budgets, untrusted context, success, rate limits, timeout,
  malformed results, idempotency, secret exclusion, and privacy-safe logging.
- **Packaged-runtime smoke:** Phase 3's verified macOS artifact loads Phase 4
  modules, builds a real EPUB context and Quick Ask over ReaderUI, preserves
  position, and completes the real Lua HTTP/subprocess path against an
  authenticated local mocked backend.
- **Display-fitted framebuffer visual:** at 600 x 800, compose leaves the EPUB
  visible around a compact keyboard-ready panel, and a completed long answer
  appears once in a bounded scrollable panel. This is not Gallery 3 evidence.
- **Live OpenAI:** optional and not run unless an explicit developer
  `OPENAI_API_KEY` is available. No CI test requires it.
- **Physical Paper Pro:** **NOT RUN — no device available.** Network behavior,
  keyboard ergonomics, refresh/ghosting, Marker concurrency, power use, QTFB,
  and firmware compatibility remain unverified.

## Known limitations

- Typed questions and text answers only; no handwriting recognition, InkStroke
  upload, OCR of Marker questions, or handwriting-styled rendering.
- One question produces one answer; no expanded multi-turn conversation,
  tools, web search, or full Book Assistant UI.
- PDF semantics depend on existing extracted/OCR text and remain weaker than
  EPUB.
- The device token is settings-file protected, not hardware-backed.
- Backend idempotency is process-local in Phase 4.
- There is no account system, cloud note sync, response sync, or OS-level
  notification.
- Physical Paper Pro behavior and Phase 3 hardware claims remain unverified.
