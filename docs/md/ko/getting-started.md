# HMG 빠른 시작

## 전제 조건

- Linux (x86_64 또는 ARM64) 또는 macOS (Intel 또는 Apple Silicon)
- MCP (Model Context Protocol)를 지원하는 AI 에이전트 또는 코딩 도구

## 설치

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


또는 [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases)에서 직접 다운로드：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## 확인

```bash
hmg --version
# hmg 1.7.1-community
```

## 메모리 서비스 시작

```bash
hmg daemon start
```

데몬은 기본적으로 `~/.local/share/hmg/stores/default`에서 로컬 MCP 서버를 시작합니다.
데이터는 로컬을 벗어나지 않습니다.

## 에이전트 연결

### Cursor

```bash
hmg init --agent cursor
# Cursor 재시작. HMG 도구가 MCP 설정에 나타납니다.
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```

### Pi

```bash
hmg init --agent pi
```

### 범용 MCP 클라이언트

HMG는 표준 입출력으로 표준 MCP 서버를 노출합니다. 클라이언트 설정:

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

## 첫 번째 메모리

MCP 도구를 사용하여 메모리를 저장하고 검색：

```json
// 의사결정 저장
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "결정：사용자 데이터에 PostgreSQL 사용. 이유：ACID 준수 및 성숙한 도구.",
    "source": "architecture-review",
    "modality": "text"
  }
}

// 나중에 검색
{
  "tool": "memory_recall",
  "arguments": {
    "query": "어떤 데이터베이스를 선택했나요？"
  }
}
```

## Community Edition 사용 가능 기능

| 기능 | 사용 가능 |
|---|---|
| 메모리 저장 (memorize) | ✅ |
| 메모리 검색 (recall) | ✅ One-Shot Recall (P1-P9) |
| 수정 라이프사이클 | ✅ 전체 |
| 거버넌스 라이프사이클 | ✅ 전체 |
| MCP 프로토콜 | ✅ 전체 |
| HTTP API | ✅ 전체 |
| 에이전트 통합 | ✅ 모든 어댑터 |
| One-Shot Recall | ✅ Full (P1-P9) |
| 자동 통합 | ❌ Developer/Enterprise |
| 도메인 팩 | ❌ Developer/Enterprise |
| 시맨틱 (벡터) 검색 | ❌ Developer/Enterprise |

## 다음 단계

- [개념](concepts.md) — 메모리 원자, 수정, 거버넌스, 범위
- [아키텍처](architecture.md) — HMG 작동 원리
- [API 참조](api-reference.md) — 모든 MCP 도구와 HTTP 엔드포인트
- [수정과 거버넌스](correction-governance.md)
- [FAQ](faq.md)
- [Developer로 업그레이드](upgrade.md)
