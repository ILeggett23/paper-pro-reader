# Phase 5 — Book Writes Back

## Book Writes Back flow

```text
selected EPUB/PDF passage
  -> Ask AI -> Write
  -> temporary InkQuestionSession
  -> raw screen-space InkStroke tables (local)
  -> durable OfflineQueue request v2
  -> just-in-time tightly cropped PNG
  -> authenticated backend
  -> one multimodal provider request
  -> recognized question + contextual answer
  -> compact response over the book
  -> optional follow-up / Expand / Full Study
```

Typed Quick Ask remains available and uses the same request, queue, backend,
conversation, response, and history authorities.

## Handwritten question sessions

`InkQuestionSession` composes Phase 3 `InkService`, `InkCanvas`, `InkStroke`,
`InkRenderer`, and `Rasterizer` with a bounded canvas and an in-memory store.
It registers the existing stylus callback only while Write mode is active and
supports Undo, Clear, Cancel, and Submit. Touch controls remain on KOReader's
normal path.

Question ink uses `purpose = "ai_question"` and is not written to the document
InkStore. Session close unregisters its callback and detaches its canvas. The
existing global Ink Mode is not entered.

`Keep in book` is explicit. It imports retained screen strokes through the
document's existing InkService, converts them with the current EPUB/PDF anchor,
persists them in `paperpro-ink.json`, and associates them with the conversation
ID. History requires returning to the source passage before this action.

## Request schema and raster transport

Schema v2 accepts:

```text
question = { type = "text", text }
question = { type = "ink", local_ink = { strokes[] }, recognized_text? }
```

Schema v1 text requests already in OfflineQueue remain valid. Every v2 request
also carries a local conversation ID, turn ID, and bounded textual history.

Raw vectors are the durable local authority. Before sending an ink request,
`InkQuestionCodec` regenerates a cropped BB8 raster, writes a temporary local
PNG, reads it into memory, removes the temporary file immediately, and sends a
versioned JSON image object. Base64 JSON is justified here because the existing
zero-dependency authenticated transport is already bounded and schema-driven;
it is never stored in OfflineQueue or ResponseStore.

Image limits:

| Limit | Value |
| --- | ---: |
| MIME | `image/png` only |
| Encoded image bytes | 262,144 |
| Width | 1,200 px |
| Height | 512 px |
| Pixels | 600,000 |
| Raw session strokes | 32 |
| Raw session points | 5,000 |
| Total HTTP body | 400,000 bytes |

The backend validates canonical base64, PNG signature, IHDR, declared and
actual byte count, dimensions, and pixel count. It never fetches a client URL
or writes the image to disk.

## Multimodal AI and recognition

The provider-neutral backend accepts text and ink questions. Its OpenAI adapter
adds one `input_image` data URL beside application instructions and separately
labeled untrusted book context. It makes one Responses API call with
`store: false`, no tools, no function calling, and no web search.

The configured model must accept image plus text input and return text. A model
capability failure affects ink requests only; typed Quick Ask continues.

Ink responses include:

```text
recognized_question?
recognition_status = clear | uncertain | unreadable
clarification_required
answer
```

The provider is instructed not to invent illegible words. `uncertain` and
`unreadable` produce an intentional clarification panel with Rewrite, Edit as
text, Ask anyway, and Cancel. No second paid request occurs until the user
chooses one of those actions.

## Contextual answers

The initial bounded ReadingContext remains associated with the conversation.
Follow-ups send that source plus at most six recent textual question/answer
turns and 8,192 UTF-8 bytes. Oldest turns are removed first and truncation is
recorded. Raw prior images are not resent. Book text remains quoted untrusted
data, and answers distinguish passage-grounded inference from outside model
knowledge.

## Response presentation

Quick Ask remains the default. A completed answer replaces `Thinking…` in one
bounded update near the active passage. Long answers scroll inside the panel.

Response styles:

- **Text:** normal reader UI typography.
- **Handwriting:** local Noto Serif Italic rendering with KOReader fallback
  glyphs. This font is already distributed and licensed by KOReader.

The model always returns text. Handwriting style adds no provider request and
no generated image. Users can remember a default or toggle the current answer.

## Conversations, Expand, and Full Study

ResponseStore schema 2 is the local canonical conversation authority:

```text
conversation_id, document identity, anchor, source selection
created_at, updated_at, reading_context
turns = [{ turn_id, request_id, question_type, question_text?,
           recognized_question?, local question_ink?, answer, status,
           created_at, completed_at, kept_in_book }]
```

Follow-up supports Type or Write and reuses OfflineQueue. Expand opens a larger
conversation surface. Full Study is an intentional full-screen TextViewer with
book/chapter, source passage, all local turns, follow-up, passage navigation,
and return to reading. It has no unrelated chat, tools, or web-search features.

AI History groups one item per conversation. Queued/failed turns update the
conversation status. A subtle product-owned `AI` marker appears only when a
conversation anchor is visible; tapping it reopens that exchange. ReaderView
is unchanged.

## Storage migration

`paperpro-ai-responses.json` migrates from schema 1 to schema 2. Each valid
Phase 4 exchange becomes a one-turn `legacy-<request_id>` conversation while
the original response row remains readable. Migration is versioned,
repeat-safe, atomically saved, and does not purge malformed/future data.

Question PNGs are not retained. Ink turns retain bounded raw local strokes so
queued requests can regenerate the same transport raster after restart.

## Offline ink questions

Submit persists request ID, context, conversation metadata, and raw session
strokes before any network action. On restart, OfflineQueue validates v2 and
regenerates the PNG only when sending. Existing single-flight processing,
bounded retry, connectivity replay, and backend idempotency prevent duplicate
provider calls. Typed and ink questions coexist in one queue.

## Privacy and security

Local only:

- raw InkStroke vectors and pressure samples;
- book paths and document identities;
- EPUB XPointers and PDF native coordinates;
- notes, vocabulary, InkStore, response history, and conversation anchors;
- temporary transport PNG outside the duration of encoding.

Transmitted only when asking:

- bounded cropped handwritten PNG for an ink turn;
- bounded selected passage/nearby context;
- bounded recent textual turns;
- request/conversation metadata;
- optional title, author, and chapter.

The backend processes the image in memory and excludes it, book content,
questions, answers, bearer tokens, and provider keys from operational logs.
AI output remains text/data and is never executed. TLS, device authentication,
provider-key isolation, and local-anchor stripping from Phase 4 remain intact.

## E-ink strategy

```text
Marker segments -> bounded existing `fast` refreshes
Submit -> static Thinking…
Completion -> one complete answer update
```

There is no token streaming, character animation, spinner, fade, slide, or
continuous timer. The optional handwriting response is painted as complete
text. UIManager, framebuffer, QTFB, and waveform selection are unchanged.

## Verification status

- Device specs: request compatibility, session lifecycle, Undo/Clear, codec
  bounds, offline restart, Keep in book, migration, conversations, history,
  marker, response font/fallback, and typed regressions.
- Backend specs: text compatibility, image validation, one-pass provider input,
  clear/uncertain/unreadable recognition, capability failure, idempotency,
  privacy-safe logs, and timeouts.
- Packaged runtime: real ReaderUI selection, mocked Marker events, offline ink
  queue/restart, PNG regeneration, authenticated localhost multimodal response,
  and app-native framebuffer visuals.
- Live OpenAI multimodal: optional; not run without an explicit key.
- Physical Paper Pro: **UNVERIFIED — no device available.** No hardware claim
  is made for latency, eraser, touch concurrency, upload time, Gallery 3,
  ghosting, power, QTFB, or firmware compatibility.

## Known limitations

- Recognition quality is provider/model dependent; no separate OCR engine is
  included.
- Handwriting-style responses use an existing italic face, not generated human
  handwriting.
- Conversation context is bounded local text, not provider-hosted state.
- Backend idempotency remains process-local unless a deployment replaces its
  adapter with shared storage.
- Conversation markers are page/passage indicators, not semantic nearest-note
  inference.
- No automatic recognition of general document ink or nearest-paragraph
  activation is implemented.
