export class IdempotencyStore {
  constructor({ ttlMs = 86_400_000, maxEntries = 1_000, clock = Date.now } = {}) {
    this.ttlMs = ttlMs;
    this.maxEntries = maxEntries;
    this.clock = clock;
    this.entries = new Map();
  }

  prune() {
    const now = this.clock();
    for (const [key, entry] of this.entries) {
      if (entry.expiresAt <= now) this.entries.delete(key);
    }
    while (this.entries.size > this.maxEntries) {
      this.entries.delete(this.entries.keys().next().value);
    }
  }

  run(requestId, task) {
    this.prune();
    const existing = this.entries.get(requestId);
    if (existing) return existing.promise;
    const promise = Promise.resolve().then(task).catch(error => {
      this.entries.delete(requestId);
      throw error;
    });
    this.entries.set(requestId, { promise, expiresAt: this.clock() + this.ttlMs });
    return promise;
  }
}

export class FileIdempotencyStore extends IdempotencyStore {
  constructor({ path, ...options } = {}) {
    super(options);
    if (!path) throw new TypeError("FileIdempotencyStore requires path");
    this.path = path;
    this.loaded = false;
  }

  async load() {
    if (this.loaded) return;
    this.loaded = true;
    const { readFile } = await import("node:fs/promises");
    for (const candidate of [this.path, `${this.path}.old`]) {
      try {
        const data = JSON.parse(await readFile(candidate, "utf8"));
        if (data?.schema_version !== 1 || !Array.isArray(data.entries)) continue;
        for (const entry of data.entries) {
          if (typeof entry.request_id === "string" && Number.isFinite(entry.expires_at)
              && entry.expires_at > this.clock() && entry.response != null) {
            this.entries.set(entry.request_id, {
              promise: Promise.resolve(entry.response),
              response: entry.response,
              createdAt: entry.created_at,
              expiresAt: entry.expires_at,
            });
          }
        }
        break;
      } catch { /* Missing or malformed files fail closed to an empty cache. */ }
    }
    this.prune();
  }

  async persist() {
    const { mkdir, rename, writeFile } = await import("node:fs/promises");
    const { dirname } = await import("node:path");
    await mkdir(dirname(this.path), { recursive: true, mode: 0o700 });
    const entries = [];
    for (const [requestId, entry] of this.entries) {
      if (entry.response != null) entries.push({
        request_id: requestId,
        status: "completed",
        response: entry.response,
        created_at: entry.createdAt,
        expires_at: entry.expiresAt,
      });
    }
    const temporary = `${this.path}.tmp`, backup = `${this.path}.old`;
    await writeFile(temporary, JSON.stringify({ schema_version: 1, entries }), { mode: 0o600 });
    try { await rename(this.path, backup); } catch { /* First write has no primary. */ }
    await rename(temporary, this.path);
  }

  async run(requestId, task) {
    await this.load();
    this.prune();
    const existing = this.entries.get(requestId);
    if (existing) return existing.promise;
    const createdAt = this.clock();
    const promise = Promise.resolve().then(task).then(async response => {
      const entry = this.entries.get(requestId);
      if (entry) {
        entry.response = response;
        entry.promise = Promise.resolve(response);
        await this.persist();
      }
      return response;
    }).catch(error => {
      this.entries.delete(requestId);
      throw error;
    });
    this.entries.set(requestId, {
      promise, createdAt, expiresAt: createdAt + this.ttlMs,
    });
    return promise;
  }
}
