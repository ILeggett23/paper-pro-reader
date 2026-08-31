# Set up the AI backend for Paper Pro testing

The Paper Pro never receives `OPENAI_API_KEY`. It receives only a revocable
device token used to authenticate to this backend.

## Requirements

- Node.js 20 or newer.
- An OpenAI project API key stored only on the backend computer.
- A configured model supporting text and image input; RC5 defaults to
  `gpt-5.4-mini`.
- Paper Pro and backend network reachability.

## Configure

From `backend/`:

```sh
cp .env.example .env
openssl rand -hex 32
```

Put the generated value in `.env` as `DEVICE_ACCESS_TOKEN`, and set:

```text
HOST=127.0.0.1
PORT=8787
DEVICE_ACCESS_TOKEN=<generated-device-token>
OPENAI_API_KEY=<server-side-openai-key>
OPENAI_MODEL=gpt-5.4-mini
PROVIDER_TIMEOUT_MS=30000
IDEMPOTENCY_DB_PATH=./data/idempotency.json
IDEMPOTENCY_TTL_SECONDS=86400
```

`.env` is ignored and is not loaded automatically. Start in the same shell:

```sh
set -a
. ./.env
set +a
npm test
npm start
```

Test locally:

```sh
curl http://127.0.0.1:8787/health
curl -H "Authorization: Bearer $DEVICE_ACCESS_TOKEN" http://127.0.0.1:8787/v1/config
```

The second response should advertise protocol 2 and `text`/`ink`.

## Localhost is not the Paper Pro address

`127.0.0.1` on the Paper Pro means the Paper Pro itself. If the backend runs
on a Mac/PC, the device must use that computer's reachable address.

Preferred: put the backend behind a publicly trusted HTTPS reverse proxy or
tunnel and use its `https://` URL. Keep TLS verification enabled.

For a short test on a trusted private home/USB network only:

1. Change backend `.env` to `HOST=0.0.0.0` and restart.
2. Find the computer's private address. On macOS, try
   `ipconfig getifaddr en0`; on Linux use `hostname -I`. Confirm the address is
   in `10.0.0.0/8`, `192.168.0.0/16`, `172.16.0.0/12`, or link-local
   `169.254.0.0/16`.
3. Allow inbound TCP port 8787 only on the trusted/private firewall profile.
   Do not router-forward this port or expose it to the internet.
4. In Paper Pro Reader > Study > AI assistant, enable **Allow private-LAN HTTP
   for testing**.
5. Set Backend URL to `http://<COMPUTER_PRIVATE_IP>:8787`, enter the device
   token, save, and run **Test connection**.

Private-LAN HTTP is unencrypted: other parties on that network could observe
the token and transmitted excerpt/image. Use it only for controlled A/B tests,
rotate the device token afterward, and disable the setting. Public or untrusted
networks require HTTPS.

## Persistent idempotency

Completed responses are stored in `IDEMPOTENCY_DB_PATH` with request ID,
response, creation time, and expiry. Images, prompts, book context, and device
tokens are not stored. The file is mode 0600 in a mode 0700 directory. Preserve
this file across backend restarts to prevent a retried stable request from
creating another paid provider call. Back it up only if the completed answer
content is acceptable to retain.

## Live test sequence

1. Typed: select a sentence and ask `What does the author mean by this?`.
2. Clear handwriting: write `Why does this matter?`; confirm recognition and
   answer.
3. Messy handwriting: write roughly; confirm uncertain/unreadable handling.
4. Follow-up: ask `Can you give me an example?`; confirm it stays grouped.
5. Offline: disable Wi-Fi, queue a question, restart if desired, reconnect, and
   confirm exactly one completion.

Do not paste keys, tokens, full questions, book excerpts, answers, or PNG data
into diagnostic reports.
