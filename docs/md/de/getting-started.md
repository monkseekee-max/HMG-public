# Schnellstart mit HMG

## Voraussetzungen

- Linux (x86_64 oder ARM64) oder macOS (Intel oder Apple Silicon)
- Ein KI-Agent oder Codierungstool, das MCP (Model Context Protocol) unterstützt

## Installation

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

### Windows (PowerShell)

```powershell
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex
```

### WSL (Windows Subsystem for Linux)

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```


Oder direkt von [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases) herunterladen：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.6-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.6-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## Überprüfung

```bash
hmg --version
# hmg 1.7.6-community
```

## Speicherdienst starten

```bash
hmg daemon start
```

Der Daemon startet standardmäßig einen lokalen MCP-Server unter `~/.local/share/hmg/stores/default`.
Keine Daten verlassen Ihren Rechner.

## Agent verbinden

### Cursor

```bash
hmg init --agent cursor
# Cursor neu starten. HMG-Tools erscheinen in den MCP-Einstellungen.
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```

### Pi

```bash
hmg init --agent pi
```

### Generischer MCP-Client

HMG stellt einen Standard-MCP-Server über stdio bereit. Client konfigurieren：

```json
{
  "mcpServers": {
    "hmg": {
      "command": "hmg-server",
      "args": ["~/.local/share/hmg/stores/default"]
    }
  }
}
```

## Erste Erinnerung

Verwenden Sie ein beliebiges MCP-Tool zum Speichern und Abrufen：

```json
// Entscheidung speichern
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "Entscheidung：PostgreSQL für Benutzerdaten. Begründung：ACID-Konformität und ausgereifte Werkzeuge.",
    "source": "architecture-review",
    "modality": "text"
  }
}

// Später abrufen
{
  "tool": "memory_recall",
  "arguments": {
    "query": "Welche Datenbank haben wir gewählt？"
  }
}
```

## Community Edition Funktionen

| Funktion | Verfügbar |
|---|---|
| Speicher (memorize) | ✅ |
| Abruf (recall) | ✅ One-Shot Recall (P1-P9) |
| Korrektur-Lebenszyklus | ✅ Vollständig |
| Governance-Lebenszyklus | ✅ Vollständig |
| MCP-Protokoll | ✅ Vollständig |
| HTTP-API | ✅ Vollständig |
| Agenten-Integration | ✅ Alle Adapter |
| One-Shot Recall | ✅ Full (P1-P9) |
| Automatische Konsolidierung | ❌ Developer/Enterprise |
| Domain-Packs | ❌ Developer/Enterprise |
| Semantische (Vektor-)Suche | ❌ Developer/Enterprise |

## Nächste Schritte

- [Konzepte](concepts.md) — Speicheratome, Korrektur, Governance, Scope
- [Architektur](architecture.md) — Wie HMG funktioniert
- [API-Referenz](api-reference.md) — Alle MCP-Tools und HTTP-Endpunkte
- [Korrektur & Governance](correction-governance.md)
- [FAQ](faq.md)
- [Upgrade zu Developer](upgrade.md)
