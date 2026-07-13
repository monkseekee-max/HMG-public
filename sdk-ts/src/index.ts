/**
 * HMG Agent Memory SDK — Community Edition.
 *
 * Wire-safe client types for the HMG agent memory protocol.
 * This module contains only the public DTO types needed to interact
 * with HMG Community Edition via HTTP or MCP.
 *
 * For the full SDK including observation, vault, and advanced features,
 * see the Developer/Enterprise Edition.
 */

declare const require: (name: string) => any;
declare const __dirname: string;
declare const process: {
  cwd(): string;
  env: Record<string, string | undefined>;
  platform: string;
};

// ---------------------------------------------------------------------------
// Context types
// ---------------------------------------------------------------------------

export type ActorKind = "User" | "Agent" | "Service";
export type AccessLevel = "Public" | "Internal" | "Restricted";
export type CorrectAction = "negate" | "confirm_actual" | "confirm_necessary" | "demote" | "replace";
export type GovernanceAction = "quarantine" | "seal" | "tombstone" | "derive_lesson";
export type RecallViewMode = "normal" | "governance" | "audit";
export type Modality = "text" | "code" | "dialogue" | "observation";
export type OutputFormat = "compact_yaml" | "json" | "markdown" | "summary";

export interface ScopeSegment {
  kind: string;
  id: string;
}

export interface ScopeRef {
  tenant_id: string;
  path: ScopeSegment[];
}

export function codingAgentScope(
  tenantId: string,
  workspace: string,
  repository: string,
  branch: string,
): ScopeRef {
  return {
    tenant_id: tenantId,
    path: [
      { kind: "workspace", id: workspace },
      { kind: "repository", id: repository },
      { kind: "branch", id: branch },
    ],
  };
}

export interface ActorPrincipal {
  kind: ActorKind;
  id: string;
}

export interface AuditContext {
  actor: ActorPrincipal;
  operation: string;
  trace_id?: string;
  reason?: string;
}

export interface ObjectRef {
  object_type: string;
  object_id: string;
}

export interface MemoryReferences {
  subjects?: ObjectRef[];
  artifacts?: ObjectRef[];
  work_items?: ObjectRef[];
  decisions?: ObjectRef[];
  commitments?: ObjectRef[];
  evidence?: ObjectRef[];
}

export interface MemoryGovernance {
  sensitivity?: string[];
  legal_basis?: string;
  break_glass_role?: string;
}

export interface MemoryContext {
  scope?: ScopeRef;
  access_level?: AccessLevel;
  policy_tags?: string[];
  audit?: AuditContext;
  references?: MemoryReferences;
  governance?: MemoryGovernance;
}

// ---------------------------------------------------------------------------
// Request types
// ---------------------------------------------------------------------------

export interface MemorizeRequest {
  content: string;
  source?: string;
  modality?: Modality;
  domain_pack_id?: string;
  context?: MemoryContext;
}

export interface RecallRequest {
  query: string;
  max_results?: number;
  include_negated?: boolean;
  domain_pack_id?: string;
  context?: MemoryContext;
}

export interface RecallViewRequest extends RecallRequest {
  mode?: RecallViewMode;
}

export interface CorrectRequest {
  target_atom: string;
  action: CorrectAction;
  reason: string;
  new_content?: string;
  domain_pack_id?: string;
  context?: MemoryContext;
}

export interface GovernanceRequest {
  target_atom: string;
  action: GovernanceAction;
  reason: string;
  actor?: string;
  lesson_content?: string;
  destroy_payload?: boolean;
}

export interface HandoffRequest {
  summary: string;
  source?: string;
  context?: MemoryContext;
}

export interface AgentBriefRequest {
  query?: string;
  max_results?: number;
  output_format?: OutputFormat;
  context?: MemoryContext;
}

export interface BulkMemorizeItem {
  content: string;
  source?: string;
  modality?: Modality;
}

export interface BulkMemorizeRequest {
  items: BulkMemorizeItem[];
  default_source?: string;
  default_modality?: Modality;
  domain_pack_id?: string;
  context?: MemoryContext;
  stop_on_error?: boolean;
}

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

export interface ApiError {
  code: string;
  message: string;
  details?: MutationErrorDetails | Record<string, unknown> | null;
}

export type MutationEffect = "applied" | "no_op" | "rejected";
export type MutationCommitOutcome =
  | "durable"
  | "degraded"
  | "not_committed"
  | "unknown_to_client";

export interface MutationErrorDetails {
  component?: string;
  source_error?: string;
  mutation_result?: {
    effect: MutationEffect;
    commit_outcome: MutationCommitOutcome;
    reconciliation_required: boolean;
    durability: MemorizeDurabilityState;
    [key: string]: unknown;
  };
  [key: string]: unknown;
}

export class HMGApiError extends Error {
  readonly code: string;
  readonly details?: MutationErrorDetails | Record<string, unknown> | null;
  readonly mutationResult?: MutationErrorDetails["mutation_result"];

  constructor(error?: ApiError | null) {
    const code = error?.code ?? "unknown";
    const message = error?.message ?? "no details";
    super(`HMG API error: ${code} — ${message}`);
    this.name = "HMGApiError";
    this.code = code;
    this.details = error?.details;
    this.mutationResult = (error?.details as MutationErrorDetails | undefined)?.mutation_result;
  }
}

export interface ApiEnvelope<T> {
  ok: boolean;
  data: T | null;
  error: ApiError | null;
}

export interface MemorizeDurabilityState {
  runtime_accepted: boolean;
  indexed: boolean;
  wal_committed: boolean;
  warm_store_committed: boolean;
  checkpointed: boolean;
  durability_error?: string | null;
  persisted_atom_count: number;
  persisted_edge_count: number;
}

export interface MemorizeResponse {
  added_atoms: string[];
  snapshot_version?: number;
  error?: string;
  /** Optional for compatibility with HMG servers predating durability receipts. */
  durability?: MemorizeDurabilityState | null;
  effect?: MutationEffect;
  commit_outcome?: MutationCommitOutcome;
  reconciliation_required?: boolean;
}

export interface RecalledAtom {
  id: string;
  text?: string;
  score?: number;
  epistemic_rank?: number;
  is_conditional?: boolean;
  exposure_state?: string;
}

export interface RecallResponse {
  narrative?: string;
  atoms: RecalledAtom[];
  knowledge_gaps: string[];
  candidates_considered?: number;
  error?: string;
}

export interface CorrectResponse {
  success: boolean;
  message: string;
  replacement_atom?: string;
  redaction_count?: number;
  snapshot_version?: number | null;
  durability?: MemorizeDurabilityState | null;
  effect?: MutationEffect;
  commit_outcome?: MutationCommitOutcome;
  reconciliation_required?: boolean;
}

export interface GovernanceResponse {
  success: boolean;
  message: string;
  target_atom: string;
  lesson_atom?: string;
  exposure?: string;
  snapshot_version?: number | null;
  payload_destroyed?: boolean;
  durability?: MemorizeDurabilityState | null;
  effect?: MutationEffect;
  commit_outcome?: MutationCommitOutcome;
  reconciliation_required?: boolean;
}

export interface AtomHistory {
  atom: Record<string, unknown>;
  current: Record<string, unknown>;
  polarity_history: unknown[];
  epistemic_history: unknown[];
  exposure_history: unknown[];
}

export interface StatsResponse {
  atom_count: number;
  edge_count: number;
  snapshot_version: number;
}

export interface HandoffResponse {
  summary: string;
  atoms_stored: number;
  scope?: string;
}

export interface AgentBriefResponse {
  content: string;
  memory_count: number;
  decisions: string[];
  risks: string[];
  next_steps: string[];
}

// ---------------------------------------------------------------------------
// Embedded in-process SDK
// ---------------------------------------------------------------------------

export interface EmbeddedMemoryOpenOptions {
  userId?: string;
  libraryPath?: string;
}

export interface EmbeddedMemoryCallOptions {
  userId?: string;
}

export interface EmbeddedMemorySearchOptions extends EmbeddedMemoryCallOptions {
  limit?: number;
}

export interface EmbeddedMemoryAddResult {
  atom_ids: string[];
  matched_atoms: [string, string][];
  snapshot_version?: number;
  durably_committed: boolean;
  warning?: string | null;
  execution_mode: "embedded";
  transport: "in_process";
}

export interface EmbeddedMemorySearchHit {
  id: string;
  text?: string;
  score: number;
  primary: boolean;
}

export interface EmbeddedMemorySearchResult {
  narrative: string;
  hits: EmbeddedMemorySearchHit[];
  knowledge_gaps: string[];
  candidates_considered: number;
  execution_mode: "embedded";
  transport: "in_process";
}

type EmbeddedNativeHandle = object;

interface EmbeddedNativeAddon {
  local(path: string, userId: string | null, libraryPath: string): EmbeddedNativeHandle;
  temporary(userId: string | null, libraryPath: string): EmbeddedNativeHandle;
  add(handle: EmbeddedNativeHandle, content: string, userId: string | null): string;
  search(handle: EmbeddedNativeHandle, query: string, userId: string | null, limit: number): string;
  close(handle: EmbeddedNativeHandle): void;
}

/**
 * In-process HMG memory for Node applications.
 *
 * This path loads the native `hmg-sdk` embedded library in the current Node
 * process. It does not start `hmg`, does not auto-start a daemon, and does not
 * use HTTP transport.
 */
export class EmbeddedMemory {
  private constructor(
    private native: EmbeddedNativeAddon,
    private handle: EmbeddedNativeHandle | null,
    readonly mode: "temporary" | "persistent",
    readonly userId?: string,
  ) {}

  static local(path: string, options: EmbeddedMemoryOpenOptions = {}): EmbeddedMemory {
    const native = loadEmbeddedNative();
    const libraryPath = resolveEmbeddedLibraryPath(options.libraryPath);
    return new EmbeddedMemory(
      native,
      native.local(path, options.userId ?? null, libraryPath),
      "persistent",
      options.userId,
    );
  }

  static temporary(options: EmbeddedMemoryOpenOptions = {}): EmbeddedMemory {
    const native = loadEmbeddedNative();
    const libraryPath = resolveEmbeddedLibraryPath(options.libraryPath);
    return new EmbeddedMemory(
      native,
      native.temporary(options.userId ?? null, libraryPath),
      "temporary",
      options.userId,
    );
  }

  add(content: string, options: EmbeddedMemoryCallOptions = {}): EmbeddedMemoryAddResult {
    return parseEmbeddedPayload<EmbeddedMemoryAddResult>(
      this.native.add(this.requireOpen(), content, options.userId ?? null),
    );
  }

  search(query: string, options: EmbeddedMemorySearchOptions = {}): EmbeddedMemorySearchResult {
    return parseEmbeddedPayload<EmbeddedMemorySearchResult>(
      this.native.search(this.requireOpen(), query, options.userId ?? null, options.limit ?? 10),
    );
  }

  close(): void {
    const handle = this.handle;
    this.handle = null;
    if (handle) {
      this.native.close(handle);
    }
  }

  private requireOpen(): EmbeddedNativeHandle {
    if (!this.handle) {
      throw new Error("embedded HMG memory is closed");
    }
    return this.handle;
  }
}

export const Memory = EmbeddedMemory;

let cachedEmbeddedNative: EmbeddedNativeAddon | undefined;

function loadEmbeddedNative(): EmbeddedNativeAddon {
  if (!cachedEmbeddedNative) {
    const path = require("node:path");
    const addonPath = path.resolve(__dirname, "../native/hmg_embedded.node");
    cachedEmbeddedNative = require(addonPath) as EmbeddedNativeAddon;
  }
  return cachedEmbeddedNative;
}

function resolveEmbeddedLibraryPath(libraryPath?: string): string {
  const fs = require("node:fs");
  const path = require("node:path");
  const libraryName =
    process.platform === "darwin"
      ? "libhmg_sdk.dylib"
      : process.platform === "win32"
        ? "hmg_sdk.dll"
        : "libhmg_sdk.so";
  const candidates = [
    libraryPath,
    process.env.HMG_EMBEDDED_LIBRARY,
    path.resolve(__dirname, "../../../target/debug", libraryName),
    path.resolve(__dirname, "../../../target/release", libraryName),
    path.resolve(process.cwd(), "target/debug", libraryName),
    path.resolve(process.cwd(), "target/release", libraryName),
  ].filter((item): item is string => Boolean(item));
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  throw new Error(`embedded HMG native library not found; tried ${candidates.join(", ")}`);
}

function parseEmbeddedPayload<T>(payload: string): T {
  const parsed = JSON.parse(payload) as {
    ok?: boolean;
    data?: T;
    error?: { message?: string };
  };
  if (!parsed.ok) {
    throw new Error(parsed.error?.message ?? "embedded HMG call failed");
  }
  return parsed.data as T;
}

/**
 * One streamed progress event from `bulkMemorize`. Variant tag is `event`.
 * Normal run order: `started` → (`item_done`, `progress`)* → `completed`.
 * With `stop_on_error`, a terminal `failed` precedes `completed`.
 */
export type BulkProgressEvent =
  | { event: "started"; total: number }
  | {
      event: "item_done";
      index: number;
      total: number;
      added_atoms: string[];
      error: string | null;
      /** Optional because older servers emitted item_done without a receipt. */
      durability?: MemorizeDurabilityState | null;
      effect?: MutationEffect;
      commit_outcome?: MutationCommitOutcome;
      reconciliation_required?: boolean;
    }
  | {
      event: "progress";
      done: number;
      total: number;
      elapsed_ms: number;
      eta_ms: number | null;
    }
  | {
      event: "completed";
      total: number;
      written_atoms: number;
      failed: number;
      applied?: number;
      no_op?: number;
      rejected?: number;
      degraded?: number;
      unknown?: number;
      elapsed_ms: number;
    }
  | {
      event: "failed";
      index: number;
      error: string;
      effect?: MutationEffect;
      commit_outcome?: MutationCommitOutcome;
      reconciliation_required?: boolean;
      durability?: MemorizeDurabilityState | null;
    }
  | { event: "error"; code: "bulk.worker_failure"; message: string; terminal: true };

export interface BulkMemorizeSummary {
  total: number;
  written_atoms: number;
  failed: number;
  applied?: number;
  no_op?: number;
  rejected?: number;
  degraded?: number;
  unknown?: number;
  elapsed_ms: number;
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/**
 * HTTP client for the HMG memory service.
 *
 * @example
 * ```typescript
 * import { HMGClient } from "@hmg_ai/sdk-ts";
 *
 * const client = new HMGClient({ baseUrl: "http://localhost:8080" });
 *
 * await client.memorize({
 *   content: "We chose PostgreSQL for the main database",
 *   context: { repository: "my-app", branch: "main" },
 * });
 *
 * const result = await client.recall({ query: "database choice" });
 * for (const atom of result.atoms) {
 *   console.log(atom.text);
 * }
 * ```
 */
export class HMGClient {
  private baseUrl: string;
  private apiKey: string | undefined;

  constructor(options: { baseUrl?: string; apiKey?: string } = {}) {
    this.baseUrl = (options.baseUrl ?? "http://localhost:8080").replace(/\/+$/, "");
    this.apiKey = options.apiKey;
  }

  private async request<T>(method: string, path: string, body?: unknown): Promise<ApiEnvelope<T>> {
    const url = `${this.baseUrl}${path}`;
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (this.apiKey) {
      headers["x-api-key"] = this.apiKey;
    }

    const response = await fetch(url, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });

    return response.json();
  }

  async memorize(req: MemorizeRequest): Promise<MemorizeResponse> {
    const envelope = await this.request<MemorizeResponse>("POST", "/api/memorize", req);
    if (envelope.data) return envelope.data;
    throw apiError(envelope);
  }

  async recall(req: RecallRequest): Promise<RecallResponse> {
    const envelope = await this.request<RecallResponse>("POST", "/api/recall", req);
    if (envelope.data) return envelope.data;
    throw apiError(envelope);
  }

  async recallView(req: RecallViewRequest): Promise<RecallResponse> {
    const envelope = await this.request<RecallResponse>("POST", "/api/recall_view", req);
    if (envelope.data) return envelope.data;
    throw apiError(envelope);
  }

  async correct(req: CorrectRequest): Promise<CorrectResponse> {
    const envelope = await this.request<CorrectResponse>("POST", "/api/correct", req);
    if (envelope.data) return envelope.data;
    throw apiError(envelope);
  }

  async govern(req: GovernanceRequest): Promise<GovernanceResponse> {
    const envelope = await this.request<GovernanceResponse>(
      "POST",
      `/api/governance/${req.action}`,
      req,
    );
    if (envelope.data) return envelope.data;
    throw apiError(envelope);
  }

  async history(atomId: string): Promise<AtomHistory> {
    const envelope = await this.request<AtomHistory>("GET", `/api/atom/${atomId}/history`);
    if (envelope.data) return envelope.data;
    throw apiError(envelope);
  }

  async stats(): Promise<StatsResponse> {
    const envelope = await this.request<StatsResponse>("GET", "/api/stats");
    if (envelope.data) return envelope.data;
    throw apiError(envelope);
  }

  async graphExport(): Promise<Record<string, unknown>> {
    const envelope = await this.request<Record<string, unknown>>("GET", "/api/graph/export");
    return envelope.data ?? {};
  }

  /**
   * Bulk-ingest many atoms with streamed progress (Server-Sent Events).
   *
   * Each item runs through the same admission / extraction / dedup /
   * governance / DLP path as a single `memorize`. `onEvent` is invoked for
   * every `started` / `item_done` / `progress` / `completed` / `failed`
   * event; the returned promise resolves with the terminal `completed`
   * summary once the stream ends.
   *
   * @example
   * ```typescript
   * const summary = await client.bulkMemorize(
   *   {
   *     items: docs.map((d) => ({ content: d.text, source: "corpus-seed" })),
   *     stop_on_error: false,
   *   },
   *   (e) => {
   *     if (e.event === "progress") {
   *       renderBar(e.done, e.total, e.eta_ms);
   *     }
   *   },
   * );
   * console.log(`wrote ${summary.written_atoms} atoms in ${summary.elapsed_ms}ms`);
   * ```
   */
  async bulkMemorize(
    req: BulkMemorizeRequest,
    onEvent?: (event: BulkProgressEvent) => void,
  ): Promise<BulkMemorizeSummary> {
    const url = `${this.baseUrl}/api/memorize/bulk`;
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      Accept: "text/event-stream",
    };
    if (this.apiKey) {
      headers["x-api-key"] = this.apiKey;
    }

    const response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(req),
    });
    if (!response.ok || !response.body) {
      const text = await response.text().catch(() => "");
      throw new Error(
        `HMG bulk memorize failed: HTTP ${response.status}${text ? ` — ${text}` : ""}`,
      );
    }
    return consumeBulkSse(response.body, onEvent);
  }
}

function apiError(envelope: ApiEnvelope<unknown>): HMGApiError {
  return new HMGApiError(envelope.error);
}

/**
 * Decode an SSE stream from `POST /api/memorize/bulk`, invoking `onEvent` for
 * each framed event. Resolves with the terminal `completed` summary.
 *
 * Implementation note: uses only the runtime `fetch` `ReadableStream` body
 * (Node 18+ and modern browsers) — no extra dependencies, matching the rest
 * of this SDK.
 */
async function consumeBulkSse(
  body: ReadableStream<Uint8Array>,
  onEvent?: (event: BulkProgressEvent) => void,
): Promise<BulkMemorizeSummary> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let summary: BulkMemorizeSummary = {
    total: 0,
    written_atoms: 0,
    failed: 0,
    elapsed_ms: 0,
  };

  for (;;) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    // SSE frames are separated by a blank line.
    let sep = buffer.indexOf("\n\n");
    while (sep !== -1) {
      const raw = buffer.slice(0, sep);
      buffer = buffer.slice(sep + 2);
      const evt = parseSseFrame(raw);
      if (evt) {
        onEvent?.(evt);
        if (evt.event === "error") {
          throw new Error(`HMG bulk memorize worker failed: ${evt.code} — ${evt.message}`);
        }
        if (evt.event === "completed") {
          summary = {
            total: evt.total,
            written_atoms: evt.written_atoms,
            failed: evt.failed,
            applied: evt.applied,
            no_op: evt.no_op,
            rejected: evt.rejected,
            degraded: evt.degraded,
            unknown: evt.unknown,
            elapsed_ms: evt.elapsed_ms,
          };
        }
      }
      sep = buffer.indexOf("\n\n");
    }
  }
  return summary;
}

function parseSseFrame(raw: string): BulkProgressEvent | null {
  let eventName = "message";
  const dataLines: string[] = [];
  for (const line of raw.split("\n")) {
    if (line.startsWith("event:")) {
      eventName = line.slice("event:".length).trim();
    } else if (line.startsWith("data:")) {
      dataLines.push(line.slice("data:".length).trim());
    }
  }
  if (dataLines.length === 0) {
    return null;
  }
  try {
    const payload = JSON.parse(dataLines.join("\n")) as Record<string, unknown>;
    return { event: eventName, ...payload } as BulkProgressEvent;
  } catch {
    return null;
  }
}
