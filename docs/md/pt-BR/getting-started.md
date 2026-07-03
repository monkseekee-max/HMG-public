# Início rápido com HMG

## Pré-requisitos

- Linux (x86_64 ou ARM64) ou macOS (Intel ou Apple Silicon)
- Um agente de IA ou ferramenta de código que suporte MCP (Model Context Protocol)

## Instalação

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


Ou baixe diretamente do [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases)：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## Verificar

```bash
hmg --version
# hmg 1.7.1-community
```

## Iniciar o serviço de memória

```bash
hmg daemon start
```

O daemon inicia um servidor MCP local em `~/.local/share/hmg/stores/default` por padrão.
Nenhum dado sai da sua máquina.

## Conectar seu agente

### Cursor

```bash
hmg init --agent cursor
# Reinicie o Cursor. As ferramentas HMG aparecem nas configurações MCP.
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

O HMG expõe um servidor MCP padrão via stdio. Configure seu cliente：

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

## Primeira memória

Use qualquer ferramenta MCP para armazenar e recuperar memórias：

```json
// Armazenar uma decisão
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "Decisão：Usar PostgreSQL para dados de usuário. Razão：Conformidade ACID e ferramentas maduras.",
    "source": "architecture-review",
    "modality": "text"
  }
}

// Recuperar depois
{
  "tool": "memory_recall",
  "arguments": {
    "query": "Qual banco de dados escolhemos？"
  }
}
```

## Recursos da Community Edition

| Recurso | Disponível |
|---|---|
| Armazenamento (memorize) | ✅ |
| Recuperação (recall) | ✅ One-Shot Recall (P1-P9) |
| Ciclo de correção | ✅ Completo |
| Ciclo de governança | ✅ Completo |
| Protocolo MCP | ✅ Completo |
| API HTTP | ✅ Completo |
| Integração de agentes | ✅ Todos os adaptadores |
| One-Shot Recall | ✅ Full (P1-P9) |
| Consolidação automatizada | ❌ Developer/Enterprise |
| Pacotes de domínio | ❌ Developer/Enterprise |
| Busca semântica (vetorial) | ❌ Developer/Enterprise |

## Próximos passos

- [Conceitos](concepts.md) — entender átomos de memória, correção, governança, escopo
- [Arquitetura](architecture.md) — como o HMG funciona em alto nível
- [Referência API](api-reference.md) — todas as ferramentas MCP e endpoints HTTP
- [Correção e Governança](correction-governance.md)
- [FAQ](faq.md)
- [Atualizar para Developer](upgrade.md)
