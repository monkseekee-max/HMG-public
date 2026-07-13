# Быстрый старт с HMG

## Предварительные требования

- Linux (x86_64 или ARM64) или macOS (Intel или Apple Silicon)
- ИИ-агент или инструмент кодирования с поддержкой MCP (Model Context Protocol)

## Установка

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


Или скачайте напрямую с [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases)：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.6-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.6-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## Проверка

```bash
hmg --version
# hmg 1.7.6-community
```

## Запуск сервиса памяти

```bash
hmg daemon start
```

Демон запускает локальный MCP-сервер в `~/.local/share/hmg/stores/default` по умолчанию.
Данные не покидают ваш компьютер.

## Подключение агента

### Cursor

```bash
hmg init --agent cursor
# Перезапустите Cursor. Инструменты HMG появятся в настройках MCP.
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```

### Pi

```bash
hmg init --agent pi
```

### Универсальный MCP-клиент

HMG предоставляет стандартный MCP-сервер через stdio. Настройте клиент：

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

## Первое воспоминание

Используйте любой MCP-инструмент для хранения и извлечения воспоминаний：

```json
// Сохранить решение
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "Решение：Использовать PostgreSQL для пользовательских данных. Причина：ACID-совместимость и зрелые инструменты.",
    "source": "architecture-review",
    "modality": "text"
  }
}

// Извлечь позже
{
  "tool": "memory_recall",
  "arguments": {
    "query": "Какую базу данных мы выбрали？"
  }
}
```

## Функции Community Edition

| Функция | Доступна |
|---|---|
| Хранение (memorize) | ✅ |
| Извлечение (recall) | ✅ One-Shot Recall (P1-P9) |
| Жизненный цикл исправлений | ✅ Полный |
| Жизненный цикл управления | ✅ Полный |
| Протокол MCP | ✅ Полный |
| HTTP API | ✅ Полный |
| Интеграция агентов | ✅ Все адаптеры |
| One-Shot Recall | ✅ Full (P1-P9) |
| Автоматическая консолидация | ❌ Developer/Enterprise |
| Доменные пакеты | ❌ Developer/Enterprise |
| Семантический (векторный) поиск | ❌ Developer/Enterprise |

## Следующие шаги

- [Концепции](concepts.md) — понять атомы памяти, исправления, управление, область видимости
- [Архитектура](architecture.md) — как работает HMG
- [Справочник API](api-reference.md) — все MCP-инструменты и HTTP-эндпоинты
- [Исправление и Управление](correction-governance.md)
- [FAQ](faq.md)
- [Обновление до Developer](upgrade.md)
