# HMG API-Referenz — Community Edition

HTTP-Basis-URL: `http://localhost:7654` (Standard).

## MCP-Werkzeuge

HMG stellt 48 MCP-Werkzeuge für Core Memory, Governance, MemoryQL, Observation, Vault, Panorama und Graph-Health-Workflows bereit.

### `memory_memorize`
Speichert dauerhafte Informationen.

```json
{
  "content": "Zu speichernder Text",
  "source": "optionales-Quell-Label",
  "modality": "text",
  "context": { "tenant_id": "tenant-acme", "workspace": "platform", "repository": "my-repo", "branch": "main" }
}
```

### `memory_recall`
Ruft relevante Erinnerungen ab.

```json
{ "query": "Welche Datenbank haben wir gewählt?", "max_results": 10, "response_profile": "compact", "output_format": "yaml" }
```

Antwortprofile: `compact` (Standard), `summary`, `full`, `debug`. Ausgabeformate: `yaml` (Standard), `markdown`, `json`.

### `memory_correct`
Korrigiert, negiert, bestätigt, stuft herab oder ersetzt ein Atom.

```json
{ "target_atom": "01KSEF...", "action": "replace", "reason": "Vereinfachung: SQLite", "new_content": "Entscheidung: SQLite für Benutzerdaten." }
```

Aktionen: `negate`, `confirm_actual`, `confirm_necessary`, `demote`, `replace`.

### `memory_govern`
Wendet Governance an: Quarantäne, Versiegelung, Tombstone oder Lektion ableiten.

```json
{ "target_atom": "01KSEF...", "action": "tombstone", "reason": "Enthält sensiblen API-Schlüssel-Verweis" }
```

### `memory_history`
Inspekturiert Korrektur- und Governance-Historie eines Atoms.

### `memory_handoff`
Schreibt eine sitzungsübergreifende Übergabezusammenfassung.

### `memory_agent_brief`
Ruft ein kompaktes, zweigbewusstes Briefing zu Aufgabenbeginn ab.

### `memory_stats`
Liefert Graph- und Indexstatistiken.

## HTTP API

| Endpunkt | Beschreibung |
|---|---|
| `POST /api/memorize` | Gleiche Parameter wie memory_memorize |
| `POST /api/recall` | Gleiche Parameter wie memory_recall |
| `POST /api/correct` | Gleiche Parameter wie memory_correct |
| `POST /api/governance/{action}` | quarantine, seal, tombstone, derive_lesson |
| `GET /api/stats` | Atomzahl, Kantenzahl, Indexstatistiken |
| `GET /api/graph/export` | Vollständigen Speichergraph als JSON exportieren |
| `GET /api/snapshot/{atom_id}` | Snapshot-Historie eines Atoms |
| `GET /api/audit/{atom_id}` | Vollständige Audit-Spur |

## Scope (Zweigbewusster Speicher)

```
tenant_id → workspace → repository → branch → task_id / decision_id
```

## Antwortformat

```json
{ "success": true, "snapshot_version": 905, "..." }
```

Fehler: `{ "success": false, "error": "Fehlerbeschreibung" }`
