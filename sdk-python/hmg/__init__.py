"""HMG Agent Memory SDK — Community Edition.

Wire-safe client types for the HMG agent memory protocol.
This module contains only the public DTO types needed to interact
with HMG Community Edition via HTTP or MCP.

For the full SDK including observation, vault, and advanced features,
see the Developer/Enterprise Edition.
"""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any, Literal, TypeAlias
from urllib import error as urllib_error
from urllib import request
import json

ActorKind = Literal["User", "Agent", "Service"]
AccessLevel = Literal["Public", "Internal", "Restricted"]
CorrectAction = Literal["negate", "confirm_actual", "confirm_necessary", "demote", "replace"]
GovernanceAction = Literal["quarantine", "seal", "tombstone", "derive_lesson"]
RecallViewMode = Literal["normal", "governance", "audit"]
Modality = Literal["text", "code", "dialogue", "observation"]
OutputFormat = Literal["compact_yaml", "json", "markdown", "summary"]
MutationEffect = Literal["applied", "no_op", "rejected"]
MutationCommitOutcome = Literal[
    "durable", "degraded", "not_committed", "unknown_to_client"
]


# ---------------------------------------------------------------------------
# Context types
# ---------------------------------------------------------------------------

@dataclass
class ScopeSegment:
    """One segment in a hierarchical scope path."""
    kind: str
    id: str


@dataclass
class ScopeRef:
    """A hierarchical scope reference."""
    tenant_id: str
    path: list[ScopeSegment] = field(default_factory=list)

    @staticmethod
    def coding_agent(tenant_id: str, workspace: str, repository: str, branch: str) -> "ScopeRef":
        """Create a software-engineering style scope."""
        return ScopeRef(
            tenant_id=tenant_id,
            path=[
                ScopeSegment(kind="workspace", id=workspace),
                ScopeSegment(kind="repository", id=repository),
                ScopeSegment(kind="branch", id=branch),
            ],
        )


@dataclass
class ActorPrincipal:
    kind: ActorKind
    id: str


@dataclass
class AuditContext:
    actor: ActorPrincipal
    operation: str
    trace_id: str | None = None
    reason: str | None = None


@dataclass
class EffectiveTimeWindow:
    starts_at: str | None = None
    ends_at: str | None = None


@dataclass
class ObjectRef:
    object_type: str
    object_id: str


@dataclass
class MemoryReferences:
    subjects: list[ObjectRef] = field(default_factory=list)
    artifacts: list[ObjectRef] = field(default_factory=list)
    work_items: list[ObjectRef] = field(default_factory=list)
    decisions: list[ObjectRef] = field(default_factory=list)
    commitments: list[ObjectRef] = field(default_factory=list)
    evidence: list[ObjectRef] = field(default_factory=list)


@dataclass
class RetentionPolicy:
    kind: Literal["keep_indefinitely", "retain_until"] = "keep_indefinitely"
    until: str | None = None


@dataclass
class MemoryGovernance:
    sensitivity: list[str] = field(default_factory=list)
    legal_basis: str | None = None
    retention_policy: RetentionPolicy | None = None
    break_glass_role: str | None = None


@dataclass
class MemoryContext:
    """Unified context attached to memory operations."""
    scope: ScopeRef | None = None
    access_level: AccessLevel | None = None
    policy_tags: list[str] = field(default_factory=list)
    effective_time: EffectiveTimeWindow | None = None
    audit: AuditContext | None = None
    references: MemoryReferences | None = None
    governance: MemoryGovernance | None = None


# ---------------------------------------------------------------------------
# Request types
# ---------------------------------------------------------------------------

@dataclass
class MemorizeRequest:
    content: str
    source: str | None = None
    modality: Modality | None = None
    domain_pack_id: str | None = None
    context: MemoryContext | None = None


@dataclass
class RecallRequest:
    query: str
    max_results: int | None = None
    include_negated: bool | None = None
    domain_pack_id: str | None = None
    context: MemoryContext | None = None


@dataclass
class RecallViewRequest(RecallRequest):
    mode: RecallViewMode | None = None


@dataclass
class CorrectRequest:
    target_atom: str
    action: CorrectAction
    reason: str
    new_content: str | None = None
    domain_pack_id: str | None = None
    context: MemoryContext | None = None


@dataclass
class GovernanceRequest:
    target_atom: str
    action: GovernanceAction
    reason: str
    actor: str | None = None
    lesson_content: str | None = None
    destroy_payload: bool | None = None


@dataclass
class HandoffRequest:
    summary: str
    source: str | None = None
    context: MemoryContext | None = None


@dataclass
class AgentBriefRequest:
    query: str | None = None
    max_results: int | None = None
    output_format: OutputFormat | None = None
    context: MemoryContext | None = None


# ---------------------------------------------------------------------------
# Response types
# ---------------------------------------------------------------------------

@dataclass
class ApiError:
    code: str
    message: str
    details: dict | None = None


class HMGApiError(Exception):
    """Typed API error that preserves mutation receipts from non-2xx responses."""

    def __init__(self, code: str, message: str, details: dict | None = None):
        super().__init__(f"HMG API error: {code} — {message}")
        self.code = code
        self.message = message
        self.details = details
        self.mutation_result = (
            details.get("mutation_result") if isinstance(details, dict) else None
        )


@dataclass
class MemorizeDurabilityState:
    runtime_accepted: bool = False
    indexed: bool = False
    wal_committed: bool = False
    warm_store_committed: bool = False
    checkpointed: bool = False
    durability_error: str | None = None
    persisted_atom_count: int = 0
    persisted_edge_count: int = 0


@dataclass
class MemorizeResponse:
    added_atoms: list[str] = field(default_factory=list)
    snapshot_version: int | None = None
    error: str | None = None
    durability: MemorizeDurabilityState | None = None
    effect: MutationEffect | None = None
    commit_outcome: MutationCommitOutcome | None = None
    reconciliation_required: bool | None = None


@dataclass
class RecalledAtom:
    id: str
    text: str | None = None
    score: float | None = None
    epistemic_rank: int | None = None
    is_conditional: bool | None = None
    exposure_state: str | None = None


@dataclass
class RecallResponse:
    narrative: str | None = None
    atoms: list[RecalledAtom] = field(default_factory=list)
    knowledge_gaps: list[str] = field(default_factory=list)
    candidates_considered: int | None = None
    error: str | None = None


@dataclass
class CorrectResponse:
    success: bool
    message: str
    replacement_atom: str | None = None
    redaction_count: int = 0
    snapshot_version: int | None = None
    durability: MemorizeDurabilityState | None = None
    effect: MutationEffect | None = None
    commit_outcome: MutationCommitOutcome | None = None
    reconciliation_required: bool | None = None


@dataclass
class GovernanceResponse:
    success: bool
    message: str
    target_atom: str
    lesson_atom: str | None = None
    exposure: str | None = None
    snapshot_version: int | None = None
    payload_destroyed: bool = False
    durability: MemorizeDurabilityState | None = None
    effect: MutationEffect | None = None
    commit_outcome: MutationCommitOutcome | None = None
    reconciliation_required: bool | None = None


@dataclass
class AtomHistory:
    atom: dict
    current: dict
    polarity_history: list = field(default_factory=list)
    epistemic_history: list = field(default_factory=list)
    exposure_history: list = field(default_factory=list)


@dataclass
class StatsResponse:
    atom_count: int
    edge_count: int
    snapshot_version: int


@dataclass
class HandoffResponse:
    summary: str
    atoms_stored: int
    scope: str | None = None


@dataclass
class AgentBriefResponse:
    content: str
    memory_count: int
    decisions: list[str] = field(default_factory=list)
    risks: list[str] = field(default_factory=list)
    next_steps: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

@dataclass
class ApiEnvelope:
    ok: bool
    data: dict | None = None
    error: ApiError | None = None


ApiEnvelopeDict: TypeAlias = dict[str, Any]


def api_envelope_data(envelope: ApiEnvelopeDict) -> Any | None:
    return envelope.get("data")


def api_envelope_error(envelope: ApiEnvelopeDict) -> dict[str, Any] | None:
    error = envelope.get("error")
    return error if isinstance(error, dict) else None


def _decode_uint(value: Any) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else 0


def _decode_memorize_durability(value: Any) -> MemorizeDurabilityState | None:
    if not isinstance(value, dict):
        return None
    return MemorizeDurabilityState(
        runtime_accepted=bool(value.get("runtime_accepted", False)),
        indexed=bool(value.get("indexed", False)),
        wal_committed=bool(value.get("wal_committed", False)),
        warm_store_committed=bool(value.get("warm_store_committed", False)),
        checkpointed=bool(value.get("checkpointed", False)),
        durability_error=(
            value.get("durability_error")
            if isinstance(value.get("durability_error"), str)
            else None
        ),
        persisted_atom_count=_decode_uint(value.get("persisted_atom_count")),
        persisted_edge_count=_decode_uint(value.get("persisted_edge_count")),
    )


def _decode_memorize_response(value: Any) -> MemorizeResponse:
    if not isinstance(value, dict):
        return MemorizeResponse()
    added_atoms = value.get("added_atoms")
    return MemorizeResponse(
        added_atoms=(
            [str(atom_id) for atom_id in added_atoms]
            if isinstance(added_atoms, list)
            else []
        ),
        snapshot_version=(
            value.get("snapshot_version")
            if isinstance(value.get("snapshot_version"), int)
            and not isinstance(value.get("snapshot_version"), bool)
            and value.get("snapshot_version") >= 0
            else None
        ),
        error=value.get("error") if isinstance(value.get("error"), str) else None,
        durability=_decode_memorize_durability(value.get("durability")),
        effect=(
            value.get("effect")
            if value.get("effect") in {"applied", "no_op", "rejected"}
            else None
        ),
        commit_outcome=(
            value.get("commit_outcome")
            if value.get("commit_outcome")
            in {"durable", "degraded", "not_committed", "unknown_to_client"}
            else None
        ),
        reconciliation_required=(
            value.get("reconciliation_required")
            if isinstance(value.get("reconciliation_required"), bool)
            else None
        ),
    )


class HMGClient:
    """HTTP client for the HMG memory service.

    Usage:
        client = HMGClient(base_url="http://localhost:8080")
        client.memorize(content="We chose PostgreSQL for the main database")
        result = client.recall(query="database choice")
        for atom in result.atoms:
            print(atom.content)
    """

    def __init__(self, base_url: str = "http://localhost:8080", api_key: str | None = None):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

    def _request(self, method: str, path: str, body: dict | None = None) -> dict:
        url = f"{self.base_url}{path}"
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["x-api-key"] = self.api_key

        data = json.dumps(body).encode() if body else None
        req = request.Request(url, data=data, headers=headers, method=method)
        try:
            with request.urlopen(req) as resp:
                return json.loads(resp.read())
        except urllib_error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            try:
                decoded = json.loads(body)
            except json.JSONDecodeError as decode_error:
                raise exc from decode_error
            if isinstance(decoded, dict):
                return decoded
            raise exc

    def memorize(self, content: str, **kwargs) -> MemorizeResponse:
        """Store a new memory atom."""
        req = MemorizeRequest(content=content, **kwargs)
        envelope = self._request("POST", "/api/memorize", _to_dict(req))
        if isinstance(envelope.get("data"), dict):
            return _decode_memorize_response(envelope["data"])
        raise _api_error(envelope)

    def recall(self, query: str, **kwargs) -> RecallResponse:
        """Recall relevant memories."""
        req = RecallRequest(query=query, **kwargs)
        envelope = self._request("POST", "/api/recall", _to_dict(req))
        if envelope.get("data"):
            data = envelope["data"]
            data["atoms"] = [RecalledAtom(**a) for a in data.get("atoms", [])]
            return RecallResponse(**data)
        raise _api_error(envelope)

    def recall_view(self, query: str, mode: RecallViewMode = "normal", **kwargs) -> RecallResponse:
        """Recall memories through a governance-aware view."""
        req = RecallViewRequest(query=query, mode=mode, **kwargs)
        envelope = self._request("POST", "/api/recall_view", _to_dict(req))
        if envelope.get("data"):
            data = envelope["data"]
            data["atoms"] = [RecalledAtom(**a) for a in data.get("atoms", [])]
            return RecallResponse(**data)
        raise _api_error(envelope)

    def correct(self, target_atom: str, action: CorrectAction, reason: str, **kwargs) -> CorrectResponse:
        """Correct an existing memory atom."""
        req = CorrectRequest(target_atom=target_atom, action=action, reason=reason, **kwargs)
        envelope = self._request("POST", "/api/correct", _to_dict(req))
        if envelope.get("data"):
            return CorrectResponse(**envelope["data"])
        raise _api_error(envelope)

    def govern(self, target_atom: str, action: GovernanceAction, reason: str, **kwargs) -> GovernanceResponse:
        """Apply a governance action to a memory atom."""
        req = GovernanceRequest(target_atom=target_atom, action=action, reason=reason, **kwargs)
        envelope = self._request("POST", f"/api/governance/{action}", _to_dict(req))
        if envelope.get("data"):
            return GovernanceResponse(**envelope["data"])
        raise _api_error(envelope)

    def history(self, atom_id: str) -> AtomHistory:
        """Inspect atom correction and governance history."""
        envelope = self._request("GET", f"/api/atom/{atom_id}/history")
        if envelope.get("data"):
            return AtomHistory(**envelope["data"])
        raise _api_error(envelope)

    def stats(self) -> StatsResponse:
        """Get memory graph statistics."""
        envelope = self._request("GET", "/api/stats")
        if envelope.get("data"):
            return StatsResponse(**envelope["data"])
        raise _api_error(envelope)

    def graph_export(self) -> dict:
        """Export the memory graph as visualization-friendly JSON."""
        envelope = self._request("GET", "/api/graph/export")
        return envelope.get("data", {})


def _to_dict(obj: Any) -> dict:
    """Convert a dataclass to a dict, filtering None values."""
    d = asdict(obj)
    return {k: v for k, v in d.items() if v is not None}


def _api_error(envelope: dict) -> Exception:
    error = envelope.get("error", {})
    return HMGApiError(
        str(error.get("code", "unknown")),
        str(error.get("message", "no details")),
        error.get("details") if isinstance(error.get("details"), dict) else None,
    )
