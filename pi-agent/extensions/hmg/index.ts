// HMG Pi Package extension.
// This extension exposes HMG memory tools to pi as native custom tools.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

function defaultHmgDataDir(): string {
  if (process.platform === "win32") {
    const localAppData = process.env.LOCALAPPDATA;
    if (localAppData) return path.join(localAppData, "HMG", "stores", "default");
  }
  const xdgDataHome = process.env.XDG_DATA_HOME;
  if (xdgDataHome) return path.join(xdgDataHome, "hmg", "stores", "default");
  return path.join(os.homedir(), ".local", "share", "hmg", "stores", "default");
}

function piAgentHome(): string {
  return process.env.PI_AGENT_HOME ?? path.join(os.homedir(), ".pi", "agent");
}

function legacyHmgExtensionPath(): string {
  return path.join(piAgentHome(), "extensions", "hmg", "index.ts");
}

function hasLegacyHmgExtension(): boolean {
  return fs.existsSync(legacyHmgExtensionPath());
}

const HMG_CLI = process.env.HMG_CLI ?? "hmg";
const HMG_SERVER = process.env.HMG_SERVER ?? "hmg-server";
const HMG_DATA_DIR = process.env.HMG_PI_DATA_DIR ?? process.env.HMG_DATA_DIR ?? defaultHmgDataDir();
// The Rust CLI compiles this file as the canonical legacy-extension template.
// It flips this flag to false so the generated extension does not mistake
// itself for a conflicting package/legacy dual installation.
const HMG_PACKAGED_EXTENSION = true;
const HMG_TIMEOUT_MS = Number(process.env.HMG_PI_MCP_TIMEOUT_MS ?? "30000");
const HMG_TASK_QUERY_MAX_CHARS = Number(process.env.HMG_PI_TASK_QUERY_MAX_CHARS ?? "4096");
const LIFECYCLE_TIMEOUT_MS = Number(process.env.HMG_PI_LIFECYCLE_TIMEOUT_MS ?? "NaN");
const TOOL_EVENT_TIMEOUT_MS = Number(process.env.HMG_PI_TOOL_EVENT_TIMEOUT_MS ?? "250");
const HMG_HOST_INSTANCE_ID = process.env.HMG_HOST_INSTANCE_ID ?? `${process.pid}:${Date.now()}`;
// Dual-site update-manifest fallback (ADR 2026-06-13 §D4/D5):
//   GitHub (primary, always available) → hmg1ai.com (CDN, international) → hmg2ai.com (domestic mirror)
// Each URL is tried in order; the first valid JSON manifest wins.
// hmg1ai.com is currently a Cloudflare SPA that returns text/html (index.html)
// for unknown paths, so a content-type guard skips it rather than failing.
const HMG_UPDATE_MANIFEST_URLS: readonly string[] = (() => {
  const override = process.env.HMG_UPDATE_MANIFEST_URL;
  if (override) return [override];
  return [
    "https://github.com/HMG-AI/HMG-public/releases/latest/download/version.json",
    "https://hmg1ai.com/releases/latest/download/version.json",
    "https://hmg2ai.com/releases/latest/download/version.json",
  ];
})();
const HMG_UPDATE_CHECK_TIMEOUT_MS = Number(process.env.HMG_UPDATE_CHECK_TIMEOUT_MS ?? "2000");

let updateNoticeShown = false;
let activeSessionId: string | undefined;
let pendingTaskContext: string | undefined;
let pendingCompactionContext: string | undefined;
let pendingHostAcknowledgement: PendingHostAcknowledgement | undefined;
let pendingCompactionCheckpoint: PendingCompactionCheckpoint | undefined;
let compactionGeneration = 0;

const HMG_DELIVERY_MARKER_PREFIX = "HMG_CONTEXT_DELIVERY_V1 ";

type PendingHostAcknowledgement = {
  marker: string;
  deliveryBlock: string;
  sessionId: string;
  contentHash: string;
  deliveryNonce: string;
  hostInstanceId: string;
};

type PendingCompactionCheckpoint = {
  checkpointId: string;
  generation: number;
  evidence: Record<string, string>;
};

type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };

type HmgFormattedResult = {
  text: string;
  details?: Record<string, unknown>;
};

type McpResponse = {
  jsonrpc: "2.0";
  id?: number;
  result?: {
    content?: Array<{ type: string; text?: string }>;
    isError?: boolean;
  };
  error?: { code: number; message: string };
};

type UpdateManifest = {
  version?: unknown;
  title?: unknown;
  message?: unknown;
  update_command?: unknown;
};

function parseJsonObject(text: string): Record<string, unknown> | undefined {
  try {
    const value = JSON.parse(text) as unknown;
    if (typeof value === "object" && value !== null && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
  } catch {
    return undefined;
  }
  return undefined;
}

function formatAgentBriefResult(text: string): HmgFormattedResult {
  const payload = parseJsonObject(text);
  if (!payload || typeof payload.brief !== "string") return { text };

  return {
    text: payload.brief,
    details: {
      success: payload.success,
      domainPackId: payload.domain_pack_id,
      scope: payload.scope,
      query: payload.query,
      briefFormat: payload.brief_format,
      language: payload.language,
      selectedCount: payload.selected_count,
      candidatesConsidered: payload.candidates_considered,
    },
  };
}

function compactRecallArgs(params: Record<string, unknown>): Record<string, unknown> {
  const args = { ...params };
  if (args.response_profile === undefined) {
    args.response_profile = "compact";
  }
  if (args.output_format === undefined) {
    args.output_format = args.response_profile === "summary" ? "markdown" : "yaml";
  }
  if (args.include_debug === undefined) {
    args.include_debug = false;
  }
  return args;
}

function compactAgentBriefArgs(params: Record<string, unknown>): Record<string, unknown> {
  const args = { ...params };
  if (args.brief_format === undefined && args.format === undefined) {
    args.brief_format = "compact_yaml";
  }
  if (args.include_debug === undefined) {
    args.include_debug = false;
  }
  return args;
}

function boundedTaskQuery(prompt: unknown): string {
  if (typeof prompt !== "string") return "";
  const limit = Number.isFinite(HMG_TASK_QUERY_MAX_CHARS)
    ? Math.min(16_384, Math.max(256, Math.trunc(HMG_TASK_QUERY_MAX_CHARS)))
    : 4096;
  return Array.from(prompt).slice(0, limit).join("");
}

async function taskBriefFromPrompt(prompt: unknown): Promise<string | undefined> {
  const query = boundedTaskQuery(prompt).trim();
  if (!query) return undefined;
  try {
    const text = await callHmgTool("memory_agent_brief", compactAgentBriefArgs({
      query,
      domain_pack_id: "software-engineering",
      tenant_id: process.env.HMG_TENANT_ID ?? process.env.HMG_MEMORY_TENANT ?? "tenant-acme",
      workspace: process.env.HMG_WORKSPACE ?? process.env.HMG_MEMORY_WORKSPACE ?? "platform",
      actor_id: "pi-hmg-extension",
      token_budget: 900,
    }));
    const brief = formatAgentBriefResult(text).text.trim();
    return brief || undefined;
  } catch {
    // Task-specific recall is best-effort; the lifecycle brief remains available.
    return undefined;
  }
}

function parseVersionParts(version: string): number[] {
  const parts: number[] = [];
  for (const part of version.trim().replace(/^v/, "").split(/[.+-]/)) {
    if (!/^\d+$/.test(part)) break;
    parts.push(Number(part));
  }
  return parts;
}

function isNewerVersion(candidate: string, current: string): boolean {
  const candidateParts = parseVersionParts(candidate);
  const currentParts = parseVersionParts(current);
  if (candidateParts.length === 0 || currentParts.length === 0) return false;
  const width = Math.max(candidateParts.length, currentParts.length);
  for (let index = 0; index < width; index += 1) {
    const candidatePart = candidateParts[index] ?? 0;
    const currentPart = currentParts[index] ?? 0;
    if (candidatePart !== currentPart) return candidatePart > currentPart;
  }
  return false;
}

function readLocalHmgVersion(): Promise<string | undefined> {
  return new Promise((resolve) => {
    const child = spawn(HMG_CLI, ["--version"], { stdio: ["ignore", "pipe", "ignore"] });
    let stdout = "";
    const timeout = setTimeout(() => {
      if (!child.killed) child.kill("SIGTERM");
      resolve(undefined);
    }, HMG_UPDATE_CHECK_TIMEOUT_MS);

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.on("error", () => {
      clearTimeout(timeout);
      resolve(undefined);
    });
    child.on("close", () => {
      clearTimeout(timeout);
      const match = stdout.match(/\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b/);
      resolve(match?.[1]);
    });
  });
}

async function fetchUpdateManifest(): Promise<UpdateManifest | undefined> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), HMG_UPDATE_CHECK_TIMEOUT_MS);
  try {
    for (const url of HMG_UPDATE_MANIFEST_URLS) {
      try {
        const response = await fetch(url, {
          headers: { accept: "application/json" },
          signal: controller.signal,
        });
        if (!response.ok) continue;
        // Skip SPA catch-all responses that return text/html for every path
        // (e.g. hmg1ai.com until its download service is live).
        const contentType = response.headers.get("content-type") ?? "";
        if (contentType.includes("text/html")) continue;
        const manifest = (await response.json()) as UpdateManifest;
        if (typeof manifest?.version === "string") return manifest;
      } catch {
        // Network error or JSON parse failure — try the next mirror.
      }
    }
    return undefined;
  } finally {
    clearTimeout(timeout);
  }
}

async function maybeNotifyHmgUpdate(ctx: { ui: { notify(message: string, level?: string): void } }) {
  if (updateNoticeShown || process.env.HMG_NO_UPDATE_CHECK) return;
  updateNoticeShown = true;

  const [currentVersion, manifest] = await Promise.all([readLocalHmgVersion(), fetchUpdateManifest()]);
  const latestVersion = typeof manifest?.version === "string" ? manifest.version : undefined;
  if (!currentVersion || !latestVersion || !isNewerVersion(latestVersion, currentVersion)) return;

  const title = typeof manifest?.title === "string" ? manifest.title : `HMG ${latestVersion} is available`;
  const message = typeof manifest?.message === "string" ? `\n${manifest.message}` : "";
  const updateCommand = typeof manifest?.update_command === "string" ? manifest.update_command : "hmg update";
  ctx.ui.notify(`${title}${message}\nCurrent: ${currentVersion}\nRun: ${updateCommand}`, "info");
}

async function callHmgTool(toolName: string, args: Record<string, unknown>, signal?: AbortSignal): Promise<string> {
  return await new Promise<string>((resolve, reject) => {
    const child = spawn(HMG_SERVER, [HMG_DATA_DIR], {
      env: {
        ...process.env,
        HMG_PROVIDER_BACKEND: process.env.HMG_PROVIDER_BACKEND ?? "local",
        HMG_DATA_DIR: HMG_DATA_DIR,
        // Force daemon mode: pi spawns a short-lived hmg-server per tool call,
        // so direct (non-daemon) mode would acquire the store lock on every call
        // and collide under parallel invocations. Daemon mode serializes writes
        // through one shared daemon and lets concurrent tool calls coexist.
        // (A user can still force direct mode via HMG_DIRECT_STORE_OPEN=1, which
        // the server's should_proxy_to_local_daemon gate honors.)
        HMG_USE_LOCAL_DAEMON: "1",
        HMG_CONSOLIDATION_SCHEDULER: process.env.HMG_CONSOLIDATION_SCHEDULER ?? "embedded",
      },
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stdoutBuffer = "";
    let stderr = "";
    let settled = false;
    let initializeAccepted = false;
    let toolRequestSent = false;
    let timeout: ReturnType<typeof setTimeout> | undefined;
    let onAbort: (() => void) | undefined;

    const terminate = () => {
      if (child.exitCode !== null || child.signalCode !== null) return;
      child.kill("SIGTERM");
      const killDeadline = setTimeout(() => {
        if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
      }, 100);
      killDeadline.unref?.();
    };

    const settle = (run: () => void) => {
      if (settled) return;
      settled = true;
      if (timeout !== undefined) clearTimeout(timeout);
      if (onAbort) signal?.removeEventListener("abort", onAbort);
      run();
    };

    const writeJsonLine = (value: Record<string, unknown>) => {
      if (settled || child.stdin.destroyed) return;
      child.stdin.write(`${JSON.stringify(value)}\n`);
    };

    const sendToolRequest = () => {
      if (toolRequestSent || settled) return;
      toolRequestSent = true;
      writeJsonLine({
        jsonrpc: "2.0",
        method: "notifications/initialized",
        params: {},
      });
      writeJsonLine({
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: { name: toolName, arguments: args as JsonValue },
      });
      child.stdin.end();
    };

    const handleResponse = (response: McpResponse) => {
      if (response.id === 1) {
        if (response.error) {
          settle(() => {
            terminate();
            reject(new Error(`HMG MCP initialize failed: ${response.error?.message ?? "unknown error"}`));
          });
          return;
        }
        initializeAccepted = true;
        sendToolRequest();
        return;
      }
      if (response.id !== 2) return;
      if (!initializeAccepted || !toolRequestSent) {
        settle(() => {
          terminate();
          reject(new Error(`HMG MCP protocol violation: ${toolName} responded before initialize completed`));
        });
        return;
      }
      if (response.error) {
        settle(() => {
          terminate();
          reject(new Error(response.error?.message ?? "HMG MCP error"));
        });
        return;
      }
      if (response.result?.isError) {
        const text = response.result.content?.map((item) => item.text ?? "").join("\n") ?? "HMG MCP error";
        settle(() => {
          terminate();
          reject(new Error(text));
        });
        return;
      }

      const text = response.result?.content?.map((item) => item.text ?? "").join("\n") ?? JSON.stringify(response.result ?? {}, null, 2);
      settle(() => {
        terminate();
        resolve(text);
      });
    };

    const parseLine = (line: string) => {
      const trimmed = line.trim();
      if (!trimmed || settled) return;
      try {
        handleResponse(JSON.parse(trimmed) as McpResponse);
      } catch (error) {
        settle(() => {
          terminate();
          reject(new Error(`Invalid HMG MCP JSON response for ${toolName}: ${trimmed}`));
        });
      }
    };

    const onStdout = (chunk: string) => {
      stdout += chunk;
      stdoutBuffer += chunk;
      const lines = stdoutBuffer.split(/\r?\n/);
      stdoutBuffer = lines.pop() ?? "";
      for (const line of lines) parseLine(line);
    };

    timeout = setTimeout(() => {
      settle(() => {
        terminate();
        reject(new Error(`HMG MCP tool ${toolName} timed out after ${HMG_TIMEOUT_MS}ms`));
      });
    }, HMG_TIMEOUT_MS);

    onAbort = () => {
      settle(() => {
        terminate();
        reject(new Error(`HMG MCP tool ${toolName} was cancelled`));
      });
    };
    if (signal?.aborted) {
      onAbort();
      return;
    }
    signal?.addEventListener("abort", onAbort, { once: true });

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", onStdout);
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.stdin.on("error", (error) => {
      settle(() => {
        terminate();
        reject(error);
      });
    });
    child.on("error", (error) => {
      settle(() => {
        terminate();
        reject(error);
      });
    });
    child.on("close", (code, termSignal) => {
      if (settled) return;
      if (stdoutBuffer.trim()) parseLine(stdoutBuffer);
      if (settled) return;
      settle(() => {
        const exit = code === null ? `signal ${termSignal ?? "unknown"}` : `code ${code}`;
        const details = stderr.trim() || stdout.trim();
        reject(new Error(`hmg-server exited with ${exit} before ${toolName} response: ${details}`));
      });
    });

    writeJsonLine({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "pi-hmg-extension", version: "0.1.0" },
      },
    });
  });
}

function lifecycleTimeoutMs(lifecycle: string): number {
  const configured = lifecycle === "PostToolUse" ? TOOL_EVENT_TIMEOUT_MS : LIFECYCLE_TIMEOUT_MS;
  if (Number.isFinite(configured)) return Math.min(5000, Math.max(50, configured));
  if (lifecycle === "SessionStart") return 1200;
  if (lifecycle === "UserPromptSubmit") return 750;
  if (lifecycle === "SessionEnd" || lifecycle === "PreCompact" || lifecycle === "PostCompact") return 500;
  return 250;
}

function additionalContextFromStdout(stdout: string): string | undefined {
  for (const line of stdout.trim().split(/\r?\n/).reverse()) {
    if (!line) continue;
    try {
      const parsed = JSON.parse(line) as Record<string, unknown>;
      const hookOutput = parsed.hookSpecificOutput;
      if (typeof hookOutput !== "object" || hookOutput === null) continue;
      const context = (hookOutput as Record<string, unknown>).additionalContext;
      if (typeof context === "string" && context.trim()) return context.trim();
    } catch {
      // Diagnostics are intentionally ignored; only the typed hook output is trusted.
    }
  }
  return undefined;
}

function acknowledgementFromContext(context: string): PendingHostAcknowledgement | undefined {
  // The trusted renderer appends its marker after the brief. Read from the end
  // so a marker-like line inside recalled content can only fail closed.
  const lines = context.split(/\r?\n/);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const rawLine = lines[index];
    const marker = rawLine.trim();
    if (!marker.startsWith(HMG_DELIVERY_MARKER_PREFIX)) continue;
    try {
      const payload = JSON.parse(marker.slice(HMG_DELIVERY_MARKER_PREFIX.length)) as Record<string, unknown>;
      const host = payload.host;
      const schemaVersion = payload.schema_version;
      const sessionId = payload.session_id;
      const contentHash = payload.content_hash;
      const briefVersion = payload.brief_version;
      const store = payload.store;
      const deliveryId = payload.delivery_id;
      const deliveryNonce = payload.delivery_nonce;
      const hostInstanceId = payload.host_instance_id;
      const expiresAtMs = payload.expires_at_ms;
      const contextBody = lines.slice(0, index).join("\n").trim();
      const recomputedHash = `sha256:${createHash("sha256").update(contextBody).digest("hex")}`;
      if (
        host === "pi"
        && schemaVersion === "hmg-host-context-delivery/v2"
        && typeof sessionId === "string"
        && sessionId === activeSessionId
        && typeof contentHash === "string"
        && /^sha256:[0-9a-f]{64}$/.test(contentHash)
        && recomputedHash === contentHash
        && typeof briefVersion === "number"
        && Number.isSafeInteger(briefVersion)
        && briefVersion >= 0
        && typeof store === "string"
        && store === HMG_DATA_DIR
        && typeof deliveryId === "string"
        && /^sha256:[0-9a-f]{64}$/.test(deliveryId)
        && typeof deliveryNonce === "string"
        && /^dc1_[0-9A-HJKMNP-TV-Z]{26}$/.test(deliveryNonce)
        && typeof hostInstanceId === "string"
        && hostInstanceId === HMG_HOST_INSTANCE_ID
        && typeof expiresAtMs === "number"
        && Number.isSafeInteger(expiresAtMs)
        && expiresAtMs > Date.now()
      ) {
        return {
          marker,
          deliveryBlock: `${contextBody}\n\n${marker}`,
          sessionId,
          contentHash,
          deliveryNonce,
          hostInstanceId,
        };
      }
    } catch {
      // A malformed marker is untrusted context, never acknowledgement evidence.
    }
  }
  return undefined;
}

async function acknowledgeHostDelivery(acknowledgement: PendingHostAcknowledgement): Promise<boolean> {
  return await new Promise<boolean>((resolve) => {
    const child = spawn(
      HMG_CLI,
      [
        "hook", "acknowledge",
        "--host", "pi",
        "--session-id", acknowledgement.sessionId,
        "--content-hash", acknowledgement.contentHash,
        "--source", "pi_agent_start_system_prompt",
        "--delivery-nonce", acknowledgement.deliveryNonce,
        "--host-instance-id", acknowledgement.hostInstanceId,
        "--store", HMG_DATA_DIR,
      ],
      {
        cwd: process.cwd(),
        env: { ...process.env, HMG_DATA_DIR, HMG_HOST_INSTANCE_ID },
        stdio: "ignore",
      },
    );
    let settled = false;
    const finish = (acknowledged: boolean) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      resolve(acknowledged);
    };
    const deadline = setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGTERM");
        const killDeadline = setTimeout(() => {
          if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
        }, 100);
        killDeadline.unref?.();
      }
      finish(false);
    }, 500);
    child.on("error", () => finish(false));
    child.on("close", (code) => finish(code === 0));
  });
}

async function dispatchHostEvent(
  lifecycle: "SessionStart" | "UserPromptSubmit" | "PostToolUse" | "PreCompact" | "PostCompact" | "SessionEnd",
  payload: Record<string, unknown>,
): Promise<string | undefined> {
  const hardTimeoutMs = lifecycleTimeoutMs(lifecycle);
  const dispatchTimeoutMs = Math.max(50, hardTimeoutMs - 50);
  return await new Promise<string | undefined>((resolve) => {
    const child = spawn(
      HMG_CLI,
      [
        "hook", "dispatch",
        "--host", "pi",
        "--event", lifecycle,
        "--store", HMG_DATA_DIR,
        "--payload", JSON.stringify(payload),
        "--timeout-ms", String(dispatchTimeoutMs),
      ],
      {
        cwd: process.cwd(),
        env: {
          ...process.env,
          HMG_DATA_DIR,
          HMG_HOST_INSTANCE_ID,
          HMG_USE_LOCAL_DAEMON: process.env.HMG_USE_LOCAL_DAEMON ?? "1",
          HMG_CAPTURE_MODE: process.env.HMG_CAPTURE_MODE ?? "raw-with-retention",
          HMG_PROMOTION_MODE: process.env.HMG_PROMOTION_MODE ?? "execute",
          HMG_AUTOMATION_TIER: process.env.HMG_AUTOMATION_TIER ?? "remember-first-govern-later",
          HMG_CONSOLIDATION_SCHEDULER: process.env.HMG_CONSOLIDATION_SCHEDULER ?? "embedded",
        },
        stdio: ["ignore", "pipe", "ignore"],
      },
    );
    let stdout = "";
    let settled = false;
    const finish = (context?: string) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      resolve(context);
    };
    const terminate = () => {
      if (child.exitCode !== null || child.signalCode !== null) return;
      child.kill("SIGTERM");
      const killDeadline = setTimeout(() => {
        if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
      }, 100);
      killDeadline.unref?.();
    };
    const deadline = setTimeout(() => {
      terminate();
      // The Rust dispatcher writes a metadata-only timeout/spool receipt whenever it starts.
      finish(undefined);
    }, hardTimeoutMs);
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      if (stdout.length < 1024 * 1024) stdout += chunk;
    });
    child.on("error", () => finish(undefined));
    child.on("close", (code) => {
      finish(code === 0 ? additionalContextFromStdout(stdout) : undefined);
    });
  });
}

function prepareCompactionCheckpoint(event: {
  preparation: { firstKeptEntryId: string };
  branchEntries: Array<{ type: string }>;
}): PendingCompactionCheckpoint {
  const nativeGeneration = event.branchEntries.reduce(
    (count, entry) => count + (entry.type === "compaction" ? 1 : 0),
    0,
  ) + 1;
  const generation = Math.max(compactionGeneration + 1, nativeGeneration);
  const checkpointDigest = createHash("sha256")
    .update(`${activeSessionId ?? "unknown"}\n${generation}\n${event.preparation.firstKeptEntryId}`)
    .digest("hex");
  const checkpointId = `pi-compaction:${checkpointDigest}`;
  const evidence = {
    objective_evidence_ref: `${checkpointId}:objective`,
    decision_evidence_ref: `${checkpointId}:decision`,
    verification_evidence_ref: `${checkpointId}:verification`,
    risk_evidence_ref: `${checkpointId}:risk`,
    next_action_evidence_ref: `${checkpointId}:next_action`,
  };
  return { checkpointId, generation, evidence };
}

function compactionPayload(
  checkpoint: PendingCompactionCheckpoint,
  source: string,
  reason: string,
  willRetry: boolean,
): Record<string, unknown> {
  return {
    session_id: activeSessionId,
    source,
    checkpoint_id: checkpoint.checkpointId,
    artifact_ref: checkpoint.checkpointId,
    compaction_generation: checkpoint.generation,
    compaction_reason: reason,
    will_retry: willRetry,
    ...checkpoint.evidence,
  };
}

async function recordToolOutcome(
  hostTool: string,
  hostCallId: string,
  outcome: "success" | "failure",
) {
  await dispatchHostEvent("PostToolUse", {
    session_id: activeSessionId,
    call_id: hostCallId,
    tool: hostTool,
    exit_code: outcome === "success" ? 0 : 1,
    source: "pi-extension",
  });
}

const ScopeFields = {
  tenant_id: Type.Optional(Type.String({ description: "HMG tenant id" })),
  workspace: Type.Optional(Type.String({ description: "HMG workspace id" })),
  repository: Type.Optional(Type.String({ description: "Repository id" })),
  branch: Type.Optional(Type.String({ description: "Branch id" })),
  task_id: Type.Optional(Type.String({ description: "Optional task id" })),
  decision_id: Type.Optional(Type.String({ description: "Optional decision id" })),
  actor_id: Type.Optional(Type.String({ description: "Agent actor id" })),
  domain_pack_id: Type.Optional(Type.String({ description: "Domain pack id" })),
  context: Type.Optional(Type.Any({ description: "Explicit HMG MemoryContext" })),
};

function registerHmgTool(pi: ExtensionAPI, definition: {
  name: string;
  label: string;
  mcpTool: string;
  description: string;
  promptSnippet: string;
  promptGuidelines: string[];
  parameters: ReturnType<typeof Type.Object>;
  prepareArgs?: (params: Record<string, unknown>) => Record<string, unknown>;
  formatResult?: (text: string) => HmgFormattedResult;
}) {
  pi.registerTool({
    name: definition.name,
    label: definition.label,
    description: definition.description,
    promptSnippet: definition.promptSnippet,
    promptGuidelines: definition.promptGuidelines,
    parameters: definition.parameters,
    async execute(toolCallId, params, signal, onUpdate) {
      onUpdate?.({
        content: [{ type: "text", text: `Calling HMG ${definition.mcpTool}...` }],
        details: { hmgTool: definition.mcpTool },
      });
      const inputParams = params && typeof params === "object" ? (params as Record<string, unknown>) : {};
      const toolArgs = definition.prepareArgs ? definition.prepareArgs(inputParams) : inputParams;
      try {
        const text = await callHmgTool(definition.mcpTool, toolArgs, signal);
        await recordToolOutcome(definition.mcpTool, toolCallId, "success");
        const formatted = definition.formatResult?.(text) ?? { text };
        return {
          content: [{ type: "text", text: formatted.text }],
          details: { hmgTool: definition.mcpTool, dataDir: HMG_DATA_DIR, ...formatted.details },
        };
      } catch (error) {
        // Failure receipts contain only the tool/call identifiers and outcome, never raw error text.
        await recordToolOutcome(definition.mcpTool, toolCallId, "failure");
        throw error;
      }
    },
  });
}

/// Resolve a credential `name` (label) to its `secret_id` (ULID) by calling
/// `secret_lookup`. The HMG vault's use/reveal/rotate/revoke MCP tools key on
/// `secret_id`, but pi exposes a simpler `name` (label) surface — so the pi
/// tools transparently resolve the label first, mirroring the CLI's behavior.
async function resolveSecretId(name: string, signal?: AbortSignal): Promise<string> {
  const text = await callHmgTool("secret_lookup", { query: name }, signal);
  const payload = parseJsonObject(text);
  const secrets = Array.isArray(payload?.secrets)
    ? (payload.secrets as Array<Record<string, unknown>>)
    : [];
  const match = secrets.find((s) => s?.label === name) ?? secrets[0];
  const id = match?.secret_id;
  if (typeof id !== "string") {
    throw new Error(`no secret named '${name}' found in vault`);
  }
  return id;
}

/// Register a secret tool that resolves `name` → `secret_id` before calling
/// the target MCP tool. Used by secret_use/reveal/rotate/revoke, which all
/// require `secret_id` on the server side.
function registerSecretIdTool(pi: ExtensionAPI, def: {
  name: string;
  label: string;
  mcpTool: string;
  description: string;
  promptSnippet: string;
  promptGuidelines: string[];
  extraParams?: Record<string, ReturnType<typeof Type.String>>;
  buildArgs: (params: Record<string, unknown>) => Record<string, unknown>;
}) {
  const extraParams = def.extraParams ?? {};
  pi.registerTool({
    name: def.name,
    label: def.label,
    description: def.description,
    promptSnippet: def.promptSnippet,
    promptGuidelines: def.promptGuidelines,
    parameters: Type.Object({
      name: Type.String({ description: "Credential name (label) to resolve to a secret_id" }),
      ...extraParams,
      ...ScopeFields,
    }),
    async execute(toolCallId, params, signal, onUpdate) {
      onUpdate?.({
        content: [{ type: "text", text: `Calling HMG ${def.mcpTool}...` }],
        details: { hmgTool: def.mcpTool },
      });
      const inputParams = params && typeof params === "object" ? (params as Record<string, unknown>) : {};
      const name = typeof inputParams.name === "string" ? inputParams.name : "";
      if (!name) throw new Error(`${def.name} requires a 'name'`);
      onUpdate?.({
        content: [{ type: "text", text: `Resolving secret '${name}' to secret_id...` }],
        details: { hmgTool: "secret_lookup" },
      });
      try {
        const secretId = await resolveSecretId(name, signal);
        const args = { secret_id: secretId, ...def.buildArgs(inputParams) };
        const text = await callHmgTool(def.mcpTool, args, signal);
        await recordToolOutcome(def.mcpTool, toolCallId, "success");
        return {
          content: [{ type: "text", text }],
          details: { hmgTool: def.mcpTool, secretId, dataDir: HMG_DATA_DIR },
        };
      } catch (error) {
        await recordToolOutcome(def.mcpTool, toolCallId, "failure");
        throw error;
      }
    },
  });
}

export default function hmgPiExtension(pi: ExtensionAPI) {
  const legacyExtensionPath = legacyHmgExtensionPath();
  if (HMG_PACKAGED_EXTENSION && hasLegacyHmgExtension() && process.env.HMG_PI_ALLOW_DUPLICATE_EXTENSIONS !== "1") {
    pi.on("session_start", async (_event, ctx) => {
      ctx.ui.setStatus("hmg", "HMG legacy extension conflict");
      ctx.ui.notify(`HMG pi package skipped because legacy extension exists at ${legacyExtensionPath}. Move or remove that directory, then restart pi.`, "warning");
    });
    return;
  }

  pi.on("session_start", async (_event, ctx) => {
    activeSessionId = ctx.sessionManager.getSessionId();
    compactionGeneration = 0;
    pendingCompactionCheckpoint = undefined;
    pendingCompactionContext = undefined;
    ctx.ui.setStatus("hmg", "HMG memory adapter active");
    void maybeNotifyHmgUpdate(ctx);
    const resumedSession = ctx.sessionManager.getBranch().some((entry) => entry.type === "message");
    pendingTaskContext = resumedSession
      ? undefined
      : await dispatchHostEvent("SessionStart", {
          session_id: activeSessionId,
          source: "pi-session-start",
        });
  });

  pi.on("session_before_compact", async (event) => {
    const checkpoint = prepareCompactionCheckpoint(event);
    pendingCompactionCheckpoint = checkpoint;
    await dispatchHostEvent(
      "PreCompact",
      compactionPayload(
        checkpoint,
        "pi-session-before-compact",
        event.reason,
        event.willRetry,
      ),
    );
  });

  pi.on("session_compact", async (event) => {
    const checkpoint = pendingCompactionCheckpoint;
    pendingCompactionCheckpoint = undefined;
    if (!checkpoint) return;
    compactionGeneration = checkpoint.generation;
    pendingCompactionContext = await dispatchHostEvent(
      "PostCompact",
      compactionPayload(
        checkpoint,
        "pi-session-compact",
        event.reason,
        event.willRetry,
      ),
    );
  });

  // Pi names its mechanical session_end surface `session_shutdown`.
  pi.on("session_shutdown", async (_event, _ctx) => {
    await dispatchHostEvent("SessionEnd", {
      session_id: activeSessionId,
      source: "pi-session-shutdown",
    });
    activeSessionId = undefined;
    pendingTaskContext = undefined;
    pendingCompactionContext = undefined;
    pendingHostAcknowledgement = undefined;
    pendingCompactionCheckpoint = undefined;
    compactionGeneration = 0;
  });

  pi.on("before_agent_start", async (event, ctx) => {
    // Derive the turn number from persisted native session entries so it stays
    // monotonic across `pi --print` process restarts. A process-local counter
    // would reset to one and collapse distinct rapid prompts in HMG's ledger.
    const eventSequence = ctx.sessionManager.getBranch().filter(
      (entry) => entry.type === "message" && entry.message.role === "user",
    ).length + 1;
    const promptContext = await dispatchHostEvent("UserPromptSubmit", {
      session_id: activeSessionId,
      event_sequence: eventSequence,
      source: "pi-before-agent-start",
    });
    // SessionStart and UserPromptSubmit are distinct native lifecycle facts.
    // The startup brief may satisfy this turn's injection, but it must never
    // suppress the prompt event itself.
    // A later prompt nonce supersedes the startup nonce, so acknowledge the
    // prompt delivery. Still expose both bounded briefs on the first turn: the
    // startup brief may carry broad recovery context that a task delta omits.
    const lifecycleContexts = [pendingTaskContext, pendingCompactionContext, promptContext]
      .filter((context): context is string => typeof context === "string" && context.length > 0);
    const lifecycleContext = lifecycleContexts.length > 0
      ? lifecycleContexts.join("\n\n")
      : undefined;
    // Prefer the newest challenge-bearing delivery, but do not let a later
    // capture-only/skip result hide an emitted PostCompact recovery block.
    const acknowledgement = [promptContext, pendingCompactionContext, pendingTaskContext]
      .filter((context): context is string => typeof context === "string" && context.length > 0)
      .map(acknowledgementFromContext)
      .find((candidate): candidate is PendingHostAcknowledgement => candidate !== undefined);
    pendingTaskContext = undefined;
    pendingCompactionContext = undefined;
    pendingHostAcknowledgement = acknowledgement;
    // The raw host prompt never enters lifecycle receipts, spool files, or durable
    // memory. It is used transiently as the MCP recall query, then discarded.
    const taskBrief = await taskBriefFromPrompt(event.prompt);
    const policy = "HMG memory policy for pi: remember first, govern later. Use the retrieved branch-aware brief below before meaningful work, hmg_recall before risky edits, hmg_handoff at milestones/end with decisions, validation, risks, and next steps, and hmg_memorize for durable product/design decisions, support learnings, operational learnings, user preferences, constraints, and root causes. Do not store secrets, tokens, raw tool output, or ephemeral command output.";
    const lifecycleBrief = lifecycleContext
      ? `\n\nHMG branch-aware lifecycle brief (retrieved and emitted by the adapter; host acknowledgement remains pending until Pi starts the agent with this exact prompt):\n${lifecycleContext}`
      : "";
    const targetedBrief = taskBrief
      ? `\n\nHMG task-targeted brief (transiently retrieved from the current user request; the request itself was not persisted by the adapter):\n${taskBrief}`
      : "";
    const context = lifecycleBrief || targetedBrief
      ? `${lifecycleBrief}${targetedBrief}`
      : "\n\nHMG did not retrieve a fresh task brief within the bounded host budget. Treat memory context as unavailable rather than claiming it was loaded.";
    return { systemPrompt: `${event.systemPrompt}\n\n${policy}${context}` };
  });

  pi.on("agent_start", async (_event, ctx) => {
    const acknowledgement = pendingHostAcknowledgement;
    pendingHostAcknowledgement = undefined;
    if (!acknowledgement) return;
    // Read the effective host prompt, but never persist or send it to HMG.
    if (!ctx.getSystemPrompt().includes(acknowledgement.deliveryBlock)) return;
    await acknowledgeHostDelivery(acknowledgement);
  });

  pi.registerCommand("hmg-doctor", {
    description: "Check the generated HMG pi extension settings",
    handler: async (_args, ctx) => {
      try {
        await callHmgTool("memory_stats", {});
        await recordToolOutcome("memory_stats", `pi-command:hmg-doctor:${Date.now()}`, "success");
        ctx.ui.notify(`HMG backend: reachable\nHMG CLI: ${HMG_CLI}\nHMG server: ${HMG_SERVER}\nHMG data: ${HMG_DATA_DIR}`, "info");
      } catch (error) {
        await recordToolOutcome("memory_stats", `pi-command:hmg-doctor:${Date.now()}`, "failure");
        ctx.ui.notify(`HMG backend check failed: ${error instanceof Error ? error.message : String(error)}`, "warning");
      }
      void maybeNotifyHmgUpdate(ctx);
    },
  });

  registerHmgTool(pi, {
    name: "hmg_agent_brief",
    label: "HMG Agent Brief",
    mcpTool: "memory_agent_brief",
    description: "Get branch-aware HMG memory at task start as compact brief text, not raw JSON.",
    promptSnippet: "Retrieve a compact HMG branch-aware agent brief before starting coding work",
    promptGuidelines: ["Use hmg_agent_brief at task start or context switch when HMG memory may contain relevant context."],
    prepareArgs: compactAgentBriefArgs,
    formatResult: formatAgentBriefResult,
    parameters: Type.Object({
      query: Type.Optional(Type.String({ description: "Task or question shaping the brief" })),
      max_results: Type.Optional(Type.Number({ description: "Maximum memories to include" })),
      brief_format: Type.Optional(StringEnum(["full", "compact_yaml", "yaml"] as const)),
      language: Type.Optional(Type.String({ description: "Preferred brief language or locale, for example auto, en, or zh-CN" })),
      token_budget: Type.Optional(Type.Number({ description: "Approximate maximum brief tokens" })),
      max_text_chars_per_atom: Type.Optional(Type.Number({ description: "Maximum text characters per recalled memory" })),
      include_debug: Type.Optional(Type.Boolean({ description: "Include raw debug payload in the HMG server response" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_handoff",
    label: "HMG Handoff",
    mcpTool: "memory_handoff",
    description: "Write a durable branch-aware handoff summary for future pi/Codex sessions.",
    promptSnippet: "Write a durable HMG handoff summary at task end",
    promptGuidelines: ["Use hmg_handoff at task end or a meaningful milestone to persist decisions, validation, risks, and next steps."],
    parameters: Type.Object({
      summary: Type.String({ description: "What changed, why, validation, risks, and next steps" }),
      source: Type.Optional(Type.String({ description: "Optional source attribution" })),
      response_profile: Type.Optional(StringEnum(["ack", "summary", "full", "debug"] as const)),
      include_content: Type.Optional(Type.Boolean({ description: "Echo generated handoff content in the response" })),
      include_debug: Type.Optional(Type.Boolean({ description: "Include verbose debug payloads" })),
      max_response_chars: Type.Optional(Type.Number({ description: "Maximum characters for optional echoed content" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_connection_status",
    label: "HMG Connection Status",
    mcpTool: "memory_connection_status",
    description: "Inspect non-sensitive host session, context-delivery, and spool evidence.",
    promptSnippet: "Inspect HMG host connection status without exposing prompts or tool output",
    promptGuidelines: ["Use hmg_connection_status to diagnose host continuity and context delivery without requesting raw hook payloads."],
    parameters: Type.Object({
      host: Type.Optional(Type.String({ description: "Exact host adapter id, for example codex or pi" })),
      session_id: Type.Optional(Type.String({ description: "Exact resolved HMG session id" })),
      session_limit: Type.Optional(Type.Number({ description: "Maximum recent unexpired sessions (1-100)" })),
      receipt_limit: Type.Optional(Type.Number({ description: "Maximum recent connection receipts (1-400)" })),
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_recall",
    label: "HMG Recall",
    mcpTool: "memory_recall",
    description: "Recall relevant HMG memories for a query as compact agent-readable YAML by default; use summary/markdown for humans or full/debug JSON explicitly.",
    promptSnippet: "Recall HMG memories for prior decisions, root causes, risks, and handoffs",
    promptGuidelines: ["Use hmg_recall before risky edits when prior HMG decisions or handoffs may affect the change."],
    prepareArgs: compactRecallArgs,
    parameters: Type.Object({
      query: Type.String({ description: "Query or question" }),
      max_results: Type.Optional(Type.Number({ description: "Maximum memories to return" })),
      mode: Type.Optional(StringEnum(["normal", "governance", "audit"] as const)),
      response_profile: Type.Optional(StringEnum(["compact", "summary", "full", "debug"] as const)),
      output_format: Type.Optional(StringEnum(["yaml", "markdown", "json"] as const)),
      token_budget: Type.Optional(Type.Number({ description: "Approximate maximum compact output tokens" })),
      max_text_chars_per_atom: Type.Optional(Type.Number({ description: "Maximum text characters per recalled memory" })),
      include_debug: Type.Optional(Type.Boolean({ description: "Include debug details when supported" })),
      include_recall_trace: Type.Optional(Type.Boolean({ description: "Include retrieval diagnostics" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_memorize",
    label: "HMG Memorize",
    mcpTool: "memory_memorize",
    description: "Store durable information into HMG.",
    promptSnippet: "Store durable decisions, root causes, constraints, validation outcomes, and risks in HMG",
    promptGuidelines: ["Use hmg_memorize only for durable facts; do not store secrets, tokens, or noisy intermediate output."],
    parameters: Type.Object({
      content: Type.String({ description: "Text content to memorize" }),
      source: Type.Optional(Type.String({ description: "Optional source attribution" })),
      modality: Type.Optional(StringEnum(["text", "code", "dialogue", "observation"] as const)),
      response_profile: Type.Optional(StringEnum(["ack", "summary", "full", "debug"] as const)),
      include_content: Type.Optional(Type.Boolean({ description: "Echo stored input content in the response" })),
      include_debug: Type.Optional(Type.Boolean({ description: "Include verbose debug payloads" })),
      max_response_chars: Type.Optional(Type.Number({ description: "Maximum characters for optional echoed content" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_correct",
    label: "HMG Correct",
    mcpTool: "memory_correct",
    description: "Correct, demote, negate, confirm, or replace an existing HMG memory atom.",
    promptSnippet: "Correct stale or wrong HMG memory instead of writing conflicting facts",
    promptGuidelines: ["Use hmg_correct when a recalled HMG memory is stale, wrong, or superseded."],
    parameters: Type.Object({
      target_atom: Type.String({ description: "Target atom ULID" }),
      action: StringEnum(["negate", "confirm_actual", "confirm_necessary", "demote", "replace"] as const),
      reason: Type.String({ description: "Correction reason" }),
      new_content: Type.Optional(Type.String({ description: "Replacement text for replace action" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_govern",
    label: "HMG Govern",
    mcpTool: "memory_govern",
    description: "Apply governance actions to sensitive, unsafe, or stale memory.",
    promptSnippet: "Govern sensitive or unsafe HMG memory via quarantine, seal, tombstone, or lesson derivation",
    promptGuidelines: ["Use hmg_govern for sensitive, unsafe, or audit-only HMG memories."],
    parameters: Type.Object({
      target_atom: Type.String({ description: "Target atom ULID" }),
      action: StringEnum(["quarantine", "seal", "tombstone", "derive_lesson"] as const),
      reason: Type.String({ description: "Governance reason" }),
      actor: Type.Optional(Type.String({ description: "Actor label" })),
      lesson_content: Type.Optional(Type.String({ description: "Optional safe lesson" })),
      destroy_payload: Type.Optional(Type.Boolean({ description: "Destroy tombstoned payload" })),
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_history",
    label: "HMG History",
    mcpTool: "memory_history",
    description: "Inspect correction, governance, and relationship history for an HMG atom.",
    promptSnippet: "Inspect HMG atom correction and governance history",
    promptGuidelines: ["Use hmg_history when you need audit trail, supersession, or governance lineage for a memory atom."],
    parameters: Type.Object({
      atom_id: Type.String({ description: "Atom ULID" }),
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_review_list",
    label: "HMG Review Queue",
    mcpTool: "memory_review_list",
    description: "List quarantined atoms pending review (deferred imports awaiting approve/discard).",
    promptSnippet: "List HMG quarantined atoms pending review (approve/discard)",
    promptGuidelines: ["Use hmg_review_list to list quarantined atoms pending review (deferred imports awaiting approve/discard)."],
    parameters: Type.Object({}),
  });

  registerHmgTool(pi, {
    name: "hmg_report_outcome",
    label: "HMG Report Outcome",
    mcpTool: "memory_report_outcome",
    description: "Report whether a recalled atom actually helped a real task.",
    promptSnippet: "Report HMG recall outcome feedback for real-task memory quality metrics",
    promptGuidelines: ["Use hmg_report_outcome after relying on or rejecting a recalled atom so HMG can measure real-task memory quality."],
    parameters: Type.Object({
      recall_id: Type.String({ description: "Recall request or trace id that returned the atom" }),
      atom_id: Type.String({ description: "Recalled atom ULID" }),
      used: Type.Optional(Type.Boolean({ description: "Whether the agent used this atom" })),
      task_correct: Type.Optional(Type.Boolean({ description: "Whether the task completed correctly" })),
      user_accepted: Type.Optional(Type.Boolean({ description: "Whether the user accepted the outcome" })),
      note: Type.Optional(Type.String({ description: "Optional note explaining the outcome" })),
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_stats",
    label: "HMG Stats",
    mcpTool: "memory_stats",
    description: "Get HMG graph and index statistics.",
    promptSnippet: "Inspect HMG memory graph statistics",
    promptGuidelines: ["Use hmg_stats to check whether the HMG memory graph has stored data."],
    parameters: Type.Object({}),
  });

  registerHmgTool(pi, {
    name: "hmg_verify",
    label: "HMG Verify",
    mcpTool: "memory_verify",
    description: "Run a read-only graph consistency check and return structural anomalies plus knowledge-health diagnostics.",
    promptSnippet: "Verify HMG graph consistency before trusting suspicious memory state",
    promptGuidelines: ["Use hmg_verify when memory state looks inconsistent, stale, or structurally suspicious."],
    parameters: Type.Object({
      response_profile: Type.Optional(StringEnum(["compact", "summary", "full", "debug"] as const)),
      output_format: Type.Optional(StringEnum(["yaml", "markdown", "json"] as const)),
      include_debug: Type.Optional(Type.Boolean({ description: "Include debug details when supported" })),
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_capture",
    label: "HMG Capture",
    mcpTool: "observation_capture",
    description: "Capture a governed observation summary or explicit remember instruction into the Observation Store.",
    promptSnippet: "Capture lifecycle summaries, test outcomes, git events, or explicit remember instructions into HMG observations",
    promptGuidelines: ["Use hmg_capture for lifecycle summaries, command/test summaries, git events, or explicit remember instructions."],
    parameters: Type.Object({
      summary: Type.Optional(Type.String({ description: "Concise summary to capture" })),
      content: Type.Optional(Type.String({ description: "Raw or explicit remember text" })),
      source: Type.Optional(StringEnum(["session-lifecycle", "command-summary", "test-result-summary", "git-event", "explicit-memory-instruction", "assistant-summary", "tool-call-summary"] as const)),
      session_id: Type.Optional(Type.String({ description: "Session id for lifecycle capture" })),
      promote: Type.Optional(Type.Boolean({ description: "Execute promotion when HMG_PROMOTION_MODE=execute" })),
      ...ScopeFields,
    }),
  });

  // ── Standard-tier tools (16 new registrations) ─────────────────────────

  registerHmgTool(pi, {
    name: "hmg_query_intent",
    label: "HMG Query Intent",
    mcpTool: "memory_query_intent",
    description: "Structured intent-driven query: DecisionTrace, CorrectionLineage, UnresolvedRisks, etc.",
    promptSnippet: "Run structured HMG query with intent routing (DecisionTrace, CorrectionLineage, UnresolvedRisks, PanoramaQuery, PanoramaImpact)",
    promptGuidelines: ["Use hmg_query_intent when you need structured knowledge retrieval with specific intent routing."],
    parameters: Type.Object({
      query: Type.String({ description: "Query or question" }),
      intent: Type.Optional(Type.String({ description: "Query intent" })),
      max_results: Type.Optional(Type.Number({ description: "Maximum memories to return" })),
      mode: Type.Optional(StringEnum(["normal", "governance", "audit"] as const)),
      output_format: Type.Optional(StringEnum(["yaml", "markdown", "json"] as const)),
      token_budget: Type.Optional(Type.Number({ description: "Approximate maximum compact output tokens" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_suggest_query",
    label: "HMG Suggest Query",
    mcpTool: "memory_suggest_query",
    description: "Suggest queries the user might want to ask based on graph analysis.",
    promptSnippet: "Suggest HMG queries based on graph analysis",
    promptGuidelines: ["Use hmg_suggest_query to explore what questions could be asked about the memory graph."],
    parameters: Type.Object({
      query: Type.String({ description: "Query or question" }),
      max_results: Type.Optional(Type.Number({ description: "Maximum suggestions to return" })),
      output_format: Type.Optional(StringEnum(["yaml", "markdown", "json"] as const)),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_query",
    label: "HMG Query",
    mcpTool: "memory_query",
    description: "Advanced read-only MemoryQL SELECT query. Prefer query_intent for agents.",
    promptSnippet: "Execute advanced HMG MemoryQL query",
    promptGuidelines: ["Use hmg_query for advanced MemoryQL queries; prefer hmg_query_intent for agent use."],
    parameters: Type.Object({
      query: Type.String({ description: "Query or question" }),
      mode: Type.Optional(StringEnum(["normal", "governance", "audit"] as const)),
      limit: Type.Optional(Type.Number({ description: "Maximum results" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_explain_query",
    label: "HMG Explain Query",
    mcpTool: "memory_explain_query",
    description: "Explain how a query would be executed, including plan and estimated results.",
    promptSnippet: "Explain HMG query execution plan",
    promptGuidelines: ["Use hmg_explain_query to understand query execution before running it."],
    parameters: Type.Object({
      query: Type.String({ description: "Query to explain" }),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_schema",
    label: "HMG Schema",
    mcpTool: "memory_schema",
    description: "Inspect the governed MemoryQL logical schema.",
    promptSnippet: "Inspect HMG MemoryQL schema and query modes",
    promptGuidelines: ["Use hmg_schema to understand available query modes and schema structure."],
    parameters: Type.Object({
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_query_templates",
    label: "HMG Query Templates",
    mcpTool: "memory_query_templates",
    description: "List safe MemoryQL intent templates for common coding-agent tasks.",
    promptSnippet: "List HMG query intent templates for common memory tasks",
    promptGuidelines: ["Use hmg_query_templates to discover available query intent templates."],
    parameters: Type.Object({
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_panorama",
    label: "HMG Panorama",
    mcpTool: "panorama_query",
    description: "Run unified panorama query: God Nodes, Surprising Connections, Suggested Questions.",
    promptSnippet: "Explore HMG knowledge graph via panorama analysis",
    promptGuidelines: ["Use hmg_panorama to explore the knowledge graph via panorama analysis."],
    parameters: Type.Object({
      query: Type.String({ description: "Query or question" }),
      mode: Type.Optional(StringEnum(["normal", "governance", "audit"] as const)),
      max_results: Type.Optional(Type.Number({ description: "Maximum results" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_panorama_impact",
    label: "HMG Panorama Impact",
    mcpTool: "panorama_impact",
    description: "Assess blast radius of a change from recalled graph context.",
    promptSnippet: "Assess blast radius of a change via HMG panorama impact analysis",
    promptGuidelines: ["Use hmg_panorama_impact to assess the blast radius of a proposed change."],
    parameters: Type.Object({
      target: Type.String({ description: "Target symbol or concept" }),
      direction: Type.Optional(StringEnum(["upstream", "downstream"] as const)),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_observation_promote",
    label: "HMG Observation Promote",
    mcpTool: "observation_promote",
    description: "Execute an approved promotion plan through existing HMG memory APIs.",
    promptSnippet: "Promote observation to durable HMG memory",
    promptGuidelines: ["Use hmg_observation_promote to promote observations to durable memory."],
    parameters: Type.Object({
      summary: Type.String({ description: "Concise summary to capture" }),
      content: Type.Optional(Type.String({ description: "Raw or explicit remember text" })),
      source: Type.Optional(Type.String({ description: "Source attribution" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_observation_promote_dry_run",
    label: "HMG Observation Promote (Dry Run)",
    mcpTool: "observation_promote_dry_run",
    description: "Dry-run promotion report for active observations without creating durable memory.",
    promptSnippet: "Preview observation promotion without creating durable memory",
    promptGuidelines: ["Use hmg_observation_promote_dry_run to preview promotion before committing."],
    parameters: Type.Object({
      summary: Type.String({ description: "Concise summary to capture" }),
      content: Type.Optional(Type.String({ description: "Raw or explicit remember text" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_observation_forget",
    label: "HMG Observation Forget",
    mcpTool: "observation_forget",
    description: "Tombstone scoped raw observations on user request.",
    promptSnippet: "Remove HMG observations on user request",
    promptGuidelines: ["Use hmg_observation_forget to remove observations on user request."],
    parameters: Type.Object({
      query: Type.Optional(Type.String({ description: "Query to match observations" })),
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_observation_config",
    label: "HMG Observation Config",
    mcpTool: "observation_config",
    description: "Return current observation capture and promotion mode configuration.",
    promptSnippet: "Check HMG observation configuration",
    promptGuidelines: ["Use hmg_observation_config to check current observation settings."],
    parameters: Type.Object({
      ...ScopeFields,
    }),
  });

  registerHmgTool(pi, {
    name: "hmg_noise_feedback",
    label: "HMG Noise Feedback",
    mcpTool: "memory_noise_feedback",
    description: "Register a phrase as an embedding noise prototype for retrieval gating.",
    promptSnippet: "Register noise-like query phrase for HMG retrieval improvement",
    promptGuidelines: ["Use hmg_noise_feedback to register noise phrases for retrieval improvement."],
    parameters: Type.Object({
      phrase: Type.String({ description: "Noise-like phrase to register" }),
      ...ScopeFields,
    }),
  });

  // Plaintext-bearing secret_store and secret_reveal are intentionally not
  // projected into Pi's autonomous tool surface. Secret enrollment belongs to
  // a trusted CLI/host-confirmation flow, and reveal remains available only
  // through the server's governed approval boundary.
  registerHmgTool(pi, {
    name: "hmg_secret_lookup",
    label: "HMG Secret Lookup",
    mcpTool: "secret_lookup",
    description: "Lookup credential metadata from the encrypted vault.",
    promptSnippet: "Lookup HMG credential metadata",
    promptGuidelines: ["Use hmg_secret_lookup to check credential metadata."],
    // Server's secret_lookup searches by `query`, not `name`/`label`.
    prepareArgs: (params) => {
      const { name, ...rest } = params;
      return { ...rest, query: name };
    },
    parameters: Type.Object({
      name: Type.String({ description: "Credential name" }),
      ...ScopeFields,
    }),
  });

  // secret_use/reveal/rotate/revoke key on `secret_id` (ULID) server-side,
  // but pi exposes a `name` (label) surface. Each resolves name→secret_id via
  // secret_lookup before calling the target tool (mirrors the CLI).
  registerSecretIdTool(pi, {
    name: "hmg_secret_use",
    label: "HMG Secret Use",
    mcpTool: "secret_use",
    description: "Authorize server-side use of a credential without revealing the payload.",
    promptSnippet: "Authorize HMG credential use without revealing payload",
    promptGuidelines: ["Use hmg_secret_use to authorize credential use server-side without revealing it."],
    buildArgs: () => ({
      purpose: "pi-secret-use",
      tool: "hmg-pi",
      actor_id: "hmg-pi",
    }),
  });

  registerSecretIdTool(pi, {
    name: "hmg_secret_rotate",
    label: "HMG Secret Rotate",
    mcpTool: "secret_rotate",
    description: "Rotate a credential: replace the payload while preserving metadata.",
    promptSnippet: "Rotate HMG credential payload",
    promptGuidelines: ["Use hmg_secret_rotate to update a credential value while keeping its metadata."],
    extraParams: { payload: Type.String({ description: "New credential value" }) },
    buildArgs: (params) => ({
      secret: params.payload,
      actor_id: "hmg-pi",
    }),
  });

  registerSecretIdTool(pi, {
    name: "hmg_secret_revoke",
    label: "HMG Secret Revoke",
    mcpTool: "secret_revoke",
    description: "Revoke a stored credential while retaining encrypted audit history.",
    promptSnippet: "Revoke HMG credential",
    promptGuidelines: ["Use hmg_secret_revoke to deny future use while retaining the audit record."],
    buildArgs: () => ({
      actor_id: "hmg-pi",
    }),
  });
}
