import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync, renameSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

import { saveAssistantEntry, setActiveAssistant } from "../cli/src/lib/assistant-config";
import { leaseGuardianToken } from "../cli/src/lib/guardian-token";
import { credentialKey } from "../assistant/src/security/credential-key";
import { generateLocalSigningKey } from "../cli/src/lib/local";
import {
  HATCH_PROVIDER_CHOICES, injectGatewayApiKey, promptLine,
  promptProviderChoice, promptSecret, readGatewayApiKey,
} from "../cli/src/lib/provider-secrets";

const home = "/data/home";
const pending = home + "/.aio-hatch";
const seal = home + "/.aio-identity.json";
const gatewayUrl = "http://127.0.0.1:7830";
const instanceDir = home + "/instance";

function writeJson(target: string, value: unknown) {
  const staged = target + ".tmp";
  writeFileSync(staged, JSON.stringify(value) + "\n", { mode: 0o600, flag: "wx" });
  renameSync(staged, target);
}

async function waitForBackend() {
  const deadline = Date.now() + 150_000;
  while (Date.now() < deadline) {
    try {
      if (readFileSync("/run/vellum/state", "utf8").trim() === "HATCHING_READY") return;
    } catch {}
    await Bun.sleep(500);
  }
  throw new Error("Service startup timed out. Check the container logs.");
}

async function api(token: string, path: string, body: object, method = "POST") {
  const response = await fetch(gatewayUrl + path, {
    method, headers: { "Content-Type": "application/json", Authorization: "Bearer " + token },
    body: JSON.stringify(body), signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`${path} returned HTTP ${response.status}`);
  return response.json();
}

async function setup() {
  if (existsSync(seal)) throw new Error("Setup is already complete. Use vellum-aio status.");
  if (process.argv.length !== 2 || !process.stdin.isTTY) {
    throw new Error("Open the Docker Console and run vellum-aio setup interactively.");
  }
  if (readdirSync(home).filter((name) => name !== ".cache").length !== 0) {
    throw new Error("Existing or interrupted setup detected. See the repair procedure.");
  }
  const name = (await promptLine("Assistant name (letters, numbers, spaces, - or _): ")).trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9 _-]{0,62}$/.test(name)) throw new Error("Invalid assistant name.");
  const id = name.toLowerCase().replace(/[ _]+/g, "-");
  const custom = (await promptLine("Use a custom OpenAI-compatible endpoint? [y/N]: ")).trim().toLowerCase() === "y";
  const provider = custom ? null : await promptProviderChoice() ?? HATCH_PROVIDER_CHOICES[0];
  let baseUrl: string | undefined;
  if (custom) {
    const url = new URL((await promptLine("OpenAI-compatible base URL (include /v1 if required): ")).trim());
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
      throw new Error("Use an HTTP(S) base URL without embedded credentials, query, or fragment.");
    }
    baseUrl = url.href;
  }
  const model = (await promptLine("Model ID (Enter for provider default): ")).trim();
  const credential = (await promptSecret(custom ? "Provider API key (hidden, Enter for keyless): " : "Provider API key (hidden): ")).trim();
  if (custom && !model) throw new Error("A model ID is required for a custom endpoint.");
  if (provider && !credential) throw new Error("A provider key is required.");

  const signingKey = generateLocalSigningKey();
  const bootstrap = generateLocalSigningKey();
  const config = {
    llm: {
      default: { provider: provider ?? "anthropic" },
      ...(provider && model && {
        activeProfile: "initial-model",
        profiles: {
          "initial-model": {
            label: "Initial model", source: "user", provider, model,
            provider_connection: provider + "-personal",
          },
        },
      }),
    },
  };
  writeJson(pending, config);
  saveAssistantEntry({
    assistantId: id,
    name,
    assistantName: name,
    species: "vellum",
    cloud: "local",
    runtimeUrl: gatewayUrl,
    localUrl: gatewayUrl,
    hatchedAt: new Date().toISOString(),
    guardianBootstrapSecret: bootstrap,
    resources: { instanceDir, daemonPort: 7821, gatewayPort: 7830, qdrantPort: 6333, cesPort: 8090, signingKey },
  });
  setActiveAssistant(id);

  console.log("Starting services and registering the guardian…");
  await waitForBackend();
  const guardian = await leaseGuardianToken(gatewayUrl, id, bootstrap);
  try {
    if (provider) {
      let key = credential;
      for (;;) {
        try {
          await injectGatewayApiKey(gatewayUrl, provider, key, guardian.accessToken);
          const saved = await readGatewayApiKey(gatewayUrl, provider, guardian.accessToken);
          if (saved.found && !saved.unreachable) break;
        } catch {}
        key = (await promptSecret("Credential rejected or unavailable. Retry key, or Enter to stop: ")).trim();
        if (!key) throw new Error();
      }
    } else {
      const service = "aio-model-endpoint";
      const name = service + ":api_key";
      // Store no placeholder secret on a keyless install.
      if (credential) {
        await api(guardian.accessToken, "/v1/secrets", { type: "credential", name, value: credential });
      }
      await api(guardian.accessToken, "/v1/inference/provider-connections", {
        name: service, provider: "openai-compatible", label: "Custom endpoint",
        base_url: baseUrl, models: [{ id: model }],
        ...(credential ? { credential: credentialKey(service, "api_key") } : {}),
      });
      await api(guardian.accessToken, "/v1/inference/profiles", {
        name: "initial-model", provider: "openai-compatible", model, connection: service,
      });
      await api(guardian.accessToken, "/v1/inference/active-profile", { name: "initial-model" }, "PUT");
    }
  } catch (error) {
    const detail = provider ? "" : " " + String(error);
    throw new Error("Provider setup did not complete." + detail);
  }

  const keyPath = resolve(instanceDir, ".vellum/protected/store.key");
  const hash = (key: string | Buffer) => createHash("sha256").update(key).digest("hex");
  writeJson(seal, {
    id,
    guardian: guardian.guardianPrincipalId,
    signing: hash(signingKey),
    bootstrap: hash(bootstrap),
    vault: existsSync(keyPath) ? hash(readFileSync(keyPath)) : null,
  });
  console.log(`Hatched ${name} (${id}). Run vellum-aio status to check readiness.`);
}

try {
  await setup();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
