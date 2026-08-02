#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = 9333;
const userDataDir = join(tmpdir(), `tixcraft-time-probe-${Date.now()}`);
const targets = process.argv.slice(2);

if (targets.length === 0) {
  targets.push(
    "https://tixcraft.com/activity",
    "https://tixcraft.com/activity/detail/26_joji",
    "https://tixcraft.com/activity/game/26_joji",
  );
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForJson(url, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url);
      if (response.ok) return await response.json();
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await sleep(150);
  }
  throw lastError ?? new Error(`Timed out waiting for ${url}`);
}

function createCdpClient(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let nextId = 1;
  const pending = new Map();
  const handlers = new Map();

  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);
      return;
    }
    if (message.method && handlers.has(message.method)) {
      for (const handler of handlers.get(message.method)) handler(message.params);
    }
  });

  const ready = new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", reject, { once: true });
  });

  return {
    ready,
    on(method, handler) {
      if (!handlers.has(method)) handlers.set(method, []);
      handlers.get(method).push(handler);
    },
    send(method, params = {}) {
      const id = nextId++;
      ws.send(JSON.stringify({ id, method, params }));
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
      });
    },
    close() {
      ws.close();
    },
  };
}

function interestingHeaders(headers = {}) {
  const wanted = new Set([
    "date",
    "x-timer",
    "server",
    "via",
    "x-served-by",
    "x-cache",
    "x-cache-hits",
    "cache-control",
    "expires",
    "content-type",
  ]);
  const out = {};
  for (const [key, value] of Object.entries(headers)) {
    if (wanted.has(key.toLowerCase())) out[key] = value;
  }
  return out;
}

function isMainTixcraftUrl(value) {
  try {
    const url = new URL(value);
    return url.hostname === "tixcraft.com";
  } catch {
    return false;
  }
}

function parseXTimer(value) {
  if (!value) return null;
  const match = String(value).match(/(?:^|,)S([0-9]+(?:\.[0-9]+)?)/);
  return match ? Number(match[1]) : null;
}

async function probeUrl(url) {
  const tab = await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent("about:blank")}`, {
    method: "PUT",
  }).then((r) => r.json());

  const cdp = createCdpClient(tab.webSocketDebuggerUrl);
  await cdp.ready;

  const rows = [];
  const byRequestId = new Map();

  cdp.on("Network.responseReceived", (params) => {
    const response = params.response || {};
    if (!response.url || !isMainTixcraftUrl(response.url)) return;
    const row = {
      url: response.url,
      status: response.status,
      mimeType: response.mimeType,
      headers: interestingHeaders(response.headers),
      timing: response.timing || null,
      wallTime: params.wallTime || null,
    };
    byRequestId.set(params.requestId, row);
    rows.push(row);
  });

  cdp.on("Network.responseReceivedExtraInfo", (params) => {
    const row = byRequestId.get(params.requestId);
    if (!row) return;
    row.extraHeaders = interestingHeaders(params.headers);
  });

  await cdp.send("Network.enable");
  await cdp.send("Page.enable");
  await cdp.send("Page.navigate", { url });
  await sleep(4500);

  cdp.close();
  await fetch(`http://127.0.0.1:${port}/json/close/${tab.id}`).catch(() => {});
  return rows;
}

async function main() {
  await mkdir(userDataDir, { recursive: true });
  const chrome = spawn(chromePath, [
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    "--window-size=1280,900",
    "about:blank",
  ], {
    stdio: ["ignore", "pipe", "pipe"],
  });

  chrome.stderr.on("data", (chunk) => {
    const text = chunk.toString();
    if (!text.includes("DevTools listening")) return;
    process.stderr.write(text);
  });

  try {
    await waitForJson(`http://127.0.0.1:${port}/json/version`);
    for (const target of targets) {
      console.log(`\n## ${target}`);
      const rows = await probeUrl(target);
      if (rows.length === 0) {
        console.log("No tixcraft.com responses captured.");
        continue;
      }
      for (const row of rows) {
        const headers = { ...row.headers, ...row.extraHeaders };
        const xTimer = headers["x-timer"] || headers["X-Timer"];
        const xTimerEpoch = parseXTimer(xTimer);
        console.log(JSON.stringify({
          url: row.url,
          status: row.status,
          mimeType: row.mimeType,
          date: headers.date || headers.Date || null,
          xTimer: xTimer || null,
          xTimerEpoch,
          server: headers.server || headers.Server || null,
          via: headers.via || headers.Via || null,
          servedBy: headers["x-served-by"] || headers["X-Served-By"] || null,
          cache: headers["x-cache"] || headers["X-Cache"] || null,
          wallTime: row.wallTime,
          timingReceiveHeadersEnd: row.timing?.receiveHeadersEnd ?? null,
        }, null, 2));
      }
    }
  } finally {
    chrome.kill("SIGTERM");
    await sleep(700);
    await rm(userDataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 250 });
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
