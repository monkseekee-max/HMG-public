# HMG Docs — Community Translations / HMG 文档社区翻译

Markdown source of the HMG documentation, organized by locale.
HMG 文档的 Markdown 源文件，按语言并列存放。

## Layout / 目录结构

| Folder    | Language           |
|-----------|--------------------|
| `zh-CN/`  | 简体中文（source of truth / 源语言） |
| `zh-TW/`  | 繁體中文 |
| `en/`     | English |
| `ja/`     | 日本語 |
| `ko/`     | 한국어 |
| `ar/`     | العربية |
| `de/`     | Deutsch |
| `es/`     | Español |
| `fr/`     | Français |
| `hi/`     | हिन्दी |
| `id/`     | Bahasa Indonesia |
| `pt-BR/`  | Português (Brasil) |
| `ru/`     | Русский |
| `tr/`     | Türkçe |
| `vi/`     | Tiếng Việt |

All 15 locales contain the same 13 files with identical file names.
每个语言都包含相同的 13 个文件，文件名一一对应。

## Contribution rules / 参与规则

1. Content changes start from `zh-CN/` (the source language), then propagate to translations.
   内容改动先改 `zh-CN/`（源语言），再同步到各语言翻译。
2. When translating, keep the same file name and preserve the front matter (`sidebar_position`).
   翻译时保持文件名一致，并保留 front matter（`sidebar_position`）。
3. Site UI strings (e.g. "Previous/Next", "On this page") are NOT maintained here —
   they come from Docusaurus' official `@docusaurus/theme-translations` automatically.
   站点界面文案（如"上一页/下一页"）不在这里维护，由 Docusaurus 官方翻译包自动提供。

## Mapping into the Docusaurus site repo / 与站点仓库的对应关系

- `zh-CN/*`  → `docs/`
- `<locale>/*` → `i18n/<locale>/docusaurus-plugin-content-docs/current/`
