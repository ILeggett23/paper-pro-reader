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
