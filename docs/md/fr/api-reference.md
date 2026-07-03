# Référence API HMG — Community Edition

URL de base HTTP : `http://localhost:7654` (par défaut).

## Outils MCP

HMG expose 48 outils MCP pour la mémoire principale, la gouvernance, MemoryQL, les observations, le coffre, panorama et les workflows de santé du graphe. Les outils principaux ci-dessous acceptent un objet `context` optionnel avec des champs de portée pour la mémoire sensible aux branches.

### `memory_memorize`

Stocker des informations durables.

```json
{
  "content": "Texte à mémoriser",
  "source": "étiquette-source-optionnelle",
  "modality": "text",
  "context": {
    "tenant_id": "tenant-acme",
    "workspace": "platform",
    "repository": "my-repo",
    "branch": "main"
  }
}
```

Réponse :

```json
{
  "success": true,
  "added_atom_count": 1,
  "added_atoms": ["01KSEFSC29QX8RQ78N3110ATC9"],
  "snapshot_version": 8
}
```


### `memory_recall`

Récupérer des mémoires pertinentes.

```json
{
  "query": "Quelle base de données avons-nous choisie ?",
  "max_results": 10,
  "response_profile": "compact",
  "output_format": "yaml"
}
```

Profils de réponse : `compact` (par défaut), `summary`, `full`, `debug`.

Formats de sortie : `yaml` (par défaut), `markdown`, `json`.


### `memory_correct`

Corriger, nier, confirmer, rétrograder ou remplacer un atome.

```json
{
  "target_atom": "01KSEFSC29QX8RQ78N3110ATC9",
  "action": "replace",
  "reason": "Base de données changée pour SQLite pour simplifier",
  "new_content": "Décision : Utiliser SQLite pour les données utilisateur."
}
```

Actions : `negate`, `confirm_actual`, `confirm_necessary`, `demote`, `replace`.


### `memory_govern`

Appliquer la gouvernance : quarantaine, scellement, tombstone ou dériver une leçon.

```json
{
  "target_atom": "01KSEFSC29QX8RQ78N3110ATC9",
  "action": "tombstone",
  "reason": "Contient une référence à une clé API sensible"
}
```

Actions : `quarantine`, `seal`, `tombstone`, `derive_lesson`.


### `memory_history`

Inspecter l'historique de correction et de gouvernance d'un atome.

```json
{
  "atom_id": "01KSEFSC29QX8RQ78N3110ATC9"
}
```

### `memory_handoff`

Écrire un résumé de transmission inter-session.

```json
{
  "summary": "Implémenté X, validé avec Y tests, risque restant : Z.",
  "source": "session-end"
}
```

### `memory_agent_brief`

Obtenir un briefing compact sensible aux branches au début d'une tâche.

```json
{
  "query": "contexte pour la tâche de codage actuelle",
  "brief_format": "compact_yaml"
}
```


### `memory_stats`

Obtenir les statistiques du graphe et des index.

```json
{}
```


## API HTTP

### `POST /api/memorize`

Mêmes paramètres que `memory_memorize`, en corps JSON.

### `POST /api/recall`

Mêmes paramètres que `memory_recall`, en corps JSON.

### `POST /api/correct`

Mêmes paramètres que `memory_correct`, en corps JSON.

### `POST /api/governance/{action}`

Actions : `quarantine`, `seal`, `tombstone`, `derive_lesson`.

### `GET /api/stats`

Retourne le nombre d'atomes, d'arêtes et les statistiques d'index.

### `GET /api/graph/export`

Exporte le graphe de mémoire complet en JSON.

### `GET /api/snapshot/{atom_id}`

Retourne l'historique des instantanés pour un atome spécifique.

### `GET /api/audit/{atom_id}`

Retourne la piste d'audit complète (correction + historique de gouvernance).

## Portée (mémoire sensible aux branches)

HMG prend en charge une portée hiérarchique pour les agents de codage :

```text
tenant_id → workspace → repository → branch
                                        ↳ task_id
                                        ↳ decision_id
```

Lorsque des champs de portée sont fournis, le rappel priorise automatiquement les mémoires spécifiques à la branche.

## Format de réponse

Toutes les réponses suivent une structure cohérente :

```json
{
  "success": true,
  "snapshot_version": 905,
  "..."
}
```

Réponses d'erreur :

```json
{
  "success": false,
  "error": "description de l'erreur"
}
```
