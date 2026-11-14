import { cliIpcCall } from "../assistant/src/ipc/cli-client.js";

const [command, port, option] = process.argv.slice(2);

async function run() {
  if (command === "begin") {
    if (option && option !== "--new-account") {
      throw new Error("Expected --new-account.");
    }
    const result = await call<{ url: string }>("begin", {
      port: Number(port),
      newAccount: option === "--new-account",
    });
    console.log(result.url);
  } else if (command === "finish") {
    const callback = (await Bun.stdin.text()).trim();
    const result = await call<{ models: number }>("finish", { callback });
    console.log(`Linked ChatGPT and loaded ${result.models} models.`);
  } else if (command === "refresh") {
    const result = await call<{ models: number }>("refresh");
    console.log(`Loaded ${result.models} ChatGPT models.`);
  } else if (command === "disconnect") {
    const result = await call<{ revoked: boolean }>("disconnect");
    if (result.revoked) {
      console.log("Disconnected ChatGPT plan usage.");
    } else {
      console.log("Cleared local ChatGPT plan credentials. To confirm revocation, disconnect Vellum AIO in ChatGPT Settings.");
    }
  } else {
    throw new Error("Use scripts/chatgpt-sign-in.py to connect, or run vellum-aio chatgpt refresh or disconnect.");
  }
}

async function call<T>(action: string, body?: Record<string, unknown>): Promise<T> {
  const result = await cliIpcCall<T>(`aio_chatgpt_plan_${action}`, { body });
  if (!result.ok || !result.result) {
    throw new Error(result.error ?? "The assistant could not complete the ChatGPT request.");
  }
  return result.result;
}

try {
  await run();
} catch (error) {
  console.error(error instanceof Error ? error.message : "ChatGPT command failed.");
  process.exitCode = 1;
}
