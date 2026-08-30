export function assertProvider(provider) {
  if (!provider || typeof provider.answer !== "function") {
    throw new TypeError("A provider with answer(request) is required");
  }
  return provider;
}
