# Démarrage rapide avec HMG

## Prérequis

- Linux (x86_64 ou ARM64) ou macOS (Intel ou Apple Silicon)
- Un agent IA ou outil de codage supportant MCP (Model Context Protocol)

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


Ou téléchargez directement depuis [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases)：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## Vérification

```bash
hmg --version
# hmg 1.7.1-community
```

## Démarrer le service de mémoire

```bash
hmg daemon start
```

Le démon démarre un serveur MCP local dans `~/.local/share/hmg/stores/default` par défaut.
Aucune donnée ne quitte votre machine.

## Connecter votre agent

### Cursor

```bash
hmg init --agent cursor
# Redémarrez Cursor. Les outils HMG apparaissent dans les paramètres MCP.
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```

### Pi

```bash
hmg init --agent pi
```

### Client MCP générique

HMG expose un serveur MCP standard via stdio. Configurez votre client：

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

## Premier souvenir

Utilisez n'importe quel outil MCP pour stocker et récupérer des mémoires：

```json
// Stocker une décision
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "Décision：Utiliser PostgreSQL pour les données utilisateur. Raison：Conformité ACID et outillage mature.",
    "source": "architecture-review",
    "modality": "text"
  }
}

// Récupérer plus tard
{
  "tool": "memory_recall",
  "arguments": {
    "query": "Quelle base de données avons-nous choisie？"
  }
}
```

## Fonctionnalités de Community Edition

| Fonctionnalité | Disponible |
|---|---|
| Stockage mémoire (memorize) | ✅ |
| Récupération mémoire (recall) | ✅ Recherche par mots-clés basique |
| Cycle de correction | ✅ Complet |
| Cycle de gouvernance | ✅ Complet |
| Protocole MCP | ✅ Complet |
| API HTTP | ✅ Complet |
| Intégration agent | ✅ Tous les adaptateurs |
| One-Shot Recall | ✅ Full (P1-P9) |
| Consolidation automatique | ❌ Developer/Enterprise |
| Packs de domaine | ❌ Developer/Enterprise |
| Recherche sémantique (vectorielle) | ❌ Developer/Enterprise |

## Prochaines étapes

- [Concepts](concepts.md) — comprendre les atomes mémoire, correction, gouvernance, portée
- [Architecture](architecture.md) — fonctionnement de HMG à haut niveau
- [Référence API](api-reference.md) — tous les outils MCP et endpoints HTTP
- [Correction et Gouvernance](correction-governance.md)
- [FAQ](faq.md)
- [Passer à Developer](upgrade.md)
