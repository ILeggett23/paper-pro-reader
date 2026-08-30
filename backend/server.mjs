import { createServer } from "node:http";
import { createApp } from "./src/app.mjs";
import { loadConfig } from "./src/config.mjs";
import { OpenAIProvider } from "./src/providers/openai.mjs";

const config = loadConfig();
const provider = new OpenAIProvider({
  apiKey: config.openaiApiKey,
  model: config.openaiModel,
  timeoutMs: config.providerTimeoutMs,
});
const server = createServer(createApp({ config, provider }));
server.listen(config.port, config.host, () => {
  console.info(JSON.stringify({ event: "backend_started", host: config.host, port: config.port }));
});
