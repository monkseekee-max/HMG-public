// HMG Pi Package extension.
// This extension exposes HMG memory tools to pi as native custom tools.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { spawn } from "node:child_process";
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
const HMG_TIMEOUT_MS = Number(process.env.HMG_PI_MCP_TIMEOUT_MS ?? "30000");
const HMG_UPDATE_MANIFEST_URL = process.env.HMG_UPDATE_MANIFEST_URL ?? "https://hmg1ai.com/releases/latest/download/version.json";
const HMG_UPDATE_CHECK_TIMEOUT_MS = Number(process.env.HMG_UPDATE_CHECK_TIMEOUT_MS ?? "2000");

let updateNoticeShown = false;

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
    const response = await fetch(HMG_UPDATE_MANIFEST_URL, {
      headers: { accept: "application/json" },
      signal: controller.signal,
    });
    if (!response.ok) return undefined;
    return (await response.json()) as UpdateManifest;
  } catch {
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
        HMG_USE_LOCAL_DAEMON: process.env.HMG_USE_LOCAL_DAEMON ?? "1",
        HMG_CONSOLIDATION_SCHEDULER: process.env.HMG_CONSOLIDATION_SCHEDULER ?? "embedded",
      },
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stdoutBuffer = "";
    let stderr = "";
    let settled = false;
    let timeout: ReturnType<typeof setTimeout> | undefined;
    let onAbort: (() => void) | undefined;

    const terminate = () => {
      if (!child.killed) child.kill("SIGTERM");
    };

    const settle = (run: () => void) => {
      if (settled) return;
      settled = true;
      if (timeout !== undefined) clearTimeout(timeout);
      if (onAbort) signal?.removeEventListener("abort", onAbort);
      run();
    };

    const handleResponse = (response: McpResponse) => {
      if (response.id !== 2) return;
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
    signal?.addEventListener("abort", onAbort, { once: true });

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", onStdout);
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.stdin.on("error", (error) => {
      settle(() => reject(error));
    });
    child.on("error", (error) => {
      settle(() => reject(error));
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

    child.stdin.write(JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "pi-hmg-extension", version: "0.1.0" },
      },
    }) + "\n");
    child.stdin.write(JSON.stringify({
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: {},
    }) + "\n");
    child.stdin.write(JSON.stringify({
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: { name: toolName, arguments: args as JsonValue },
    }) + "\n");
    child.stdin.end();
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
    async execute(_toolCallId, params, signal, onUpdate) {
      onUpdate?.({ content: [{ type: "text", text: `Calling HMG ${definition.mcpTool}...` }] });
      const inputParams = params && typeof params === "object" ? (params as Record<string, unknown>) : {};
      const toolArgs = definition.prepareArgs ? definition.prepareArgs(inputParams) : inputParams;
      const text = await callHmgTool(definition.mcpTool, toolArgs, signal);
      const formatted = definition.formatResult?.(text) ?? { text };
      return {
        content: [{ type: "text", text: formatted.text }],
        details: { hmgTool: definition.mcpTool, dataDir: HMG_DATA_DIR, ...formatted.details },
      };
    },
  });
}

export default function hmgPiExtension(pi: ExtensionAPI) {
  const legacyExtensionPath = legacyHmgExtensionPath();
  if (hasLegacyHmgExtension() && process.env.HMG_PI_ALLOW_DUPLICATE_EXTENSIONS !== "1") {
    pi.on("session_start", async (_event, ctx) => {
      ctx.ui.setStatus("hmg", "HMG legacy extension conflict");
      ctx.ui.notify(`HMG pi package skipped because legacy extension exists at ${legacyExtensionPath}. Move or remove that directory, then restart pi.`, "warn");
    });
    return;
  }

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setStatus("hmg", "HMG memory ready");
    void maybeNotifyHmgUpdate(ctx);
  });

  pi.on("before_agent_start", async (event) => ({
    systemPrompt: `${event.systemPrompt}\n\nHMG memory policy for pi: when HMG tools are active, use hmg_agent_brief at task start for durable branch-aware context, hmg_recall before risky edits, and hmg_handoff at task end with decisions, validation, risks, and next steps. Do not store secrets or ephemeral command output.`,
  }));

  pi.registerCommand("hmg-doctor", {
    description: "Check the generated HMG pi extension settings",
    handler: async (_args, ctx) => {
      ctx.ui.notify(`HMG CLI: ${HMG_CLI}\nHMG server: ${HMG_SERVER}\nHMG data: ${HMG_DATA_DIR}`, "info");
      void maybeNotifyHmgUpdate(ctx);
    },
  });

  registerHmgTool(pi, {
    name: "hmg_agent_brief",
    label: "HMG Agent Brief",
    mcpTool: "memory_agent_brief",
    description: "Get branch-aware HMG memory at task start as compact brief text, not raw JSON.",
    promptSnippet: "Retrieve a compact HMG branch-aware agent brief before starting coding work",
    promptGuidelines: ["Use hmg_agent_brief at the start of coding tasks when HMG memory may contain relevant context."],
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
    promptGuidelines: ["Use hmg_handoff before ending substantial coding tasks to persist decisions, validation, risks, and next steps."],
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
    name: "hmg_stats",
    label: "HMG Stats",
    mcpTool: "memory_stats",
    description: "Get HMG graph and index statistics.",
    promptSnippet: "Inspect HMG memory graph statistics",
    promptGuidelines: ["Use hmg_stats to check whether the HMG memory graph has stored data."],
    parameters: Type.Object({}),
  });
}
