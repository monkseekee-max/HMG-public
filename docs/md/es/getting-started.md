# Inicio rápido con HMG

## Requisitos previos

- Linux (x86_64 o ARM64) o macOS (Intel o Apple Silicon)
- Un agente de IA o herramienta de codificación compatible con MCP (Model Context Protocol)

## Instalación

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


O descarga directamente desde [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases)：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.6-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.6-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## Verificar

```bash
hmg --version
# hmg 1.7.6-community
```

## Iniciar el servicio de memoria

```bash
hmg daemon start
```

El demonio inicia un servidor MCP local en `~/.local/share/hmg/stores/default` por defecto.
Ningún dato sale de tu máquina.

## Conectar tu agente

### Cursor

```bash
hmg init --agent cursor
# Reinicia Cursor. Las herramientas HMG aparecen en la configuración MCP.
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```

### Pi

```bash
hmg init --agent pi
```

### Cliente MCP genérico

HMG expone un servidor MCP estándar sobre stdio. Configura tu cliente：

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

## Primer recuerdo

Usa cualquier herramienta MCP para almacenar y recuperar memorias：

```json
// Almacenar una decisión
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "Decisión：Usar PostgreSQL para datos de usuario. Razón：Conformidad ACID y herramientas maduras.",
    "source": "architecture-review",
    "modality": "text"
  }
}

// Recuperar después
{
  "tool": "memory_recall",
  "arguments": {
    "query": "¿Qué base de datos elegimos？"
  }
}
```

## Funciones de Community Edition

| Función | Disponible |
|---|---|
| Almacenamiento (memorize) | ✅ |
| Recuperación (recall) | ✅ One-Shot Recall (P1-P9) |
| Ciclo de corrección | ✅ Completo |
| Ciclo de gobernanza | ✅ Completo |
| Protocolo MCP | ✅ Completo |
| API HTTP | ✅ Completo |
| Integración de agentes | ✅ Todos los adaptadores |
| One-Shot Recall | ✅ Full (P1-P9) |
| Consolidación automatizada | ❌ Developer/Enterprise |
| Paquetes de dominio | ❌ Developer/Enterprise |
| Búsqueda semántica (vectorial) | ❌ Developer/Enterprise |

## Siguientes pasos

- [Conceptos](concepts.md) — entender átomos de memoria, corrección, gobernanza, alcance
- [Arquitectura](architecture.md) — cómo funciona HMG a alto nivel
- [Referencia API](api-reference.md) — todas las herramientas MCP y endpoints HTTP
- [Corrección y Gobernanza](correction-governance.md)
- [FAQ](faq.md)
- [Actualizar a Developer](upgrade.md)
