# 故障排查

## 安装失败 {#install-failure}
**症状**：`hmg --version` 无输出或命令找不到。

**排查**：
1. 确认安装器是否执行成功，检查 PATH 是否含 HMG 安装目录。
2. 重新运行官方安装命令。
3. 手动验证二进制可执行：
   ```bash
   /完整路径/hmg --version
   ```
4. 网络/权限问题导致下载失败，检查代理与磁盘权限。

## Agent 看不到 HMG 工具 {#agent-cant-see-hmg-tools}
**症状**：Agent 会话里没有 `memory_memorize` / `memory_recall` 等 `memory_*` 工具。

**排查**：
1. 确认 MCP 配置已生成：`hmg doctor --agent <id>`。
2. 先执行 `hmg init --agent <id> --dry-run`，确认当前版本会写哪些宿主文件。
3. 检查配置是否使用 `hmg-server <store-path>`。
4. 重启 Agent（MCP 配置通常需要重启生效）。
5. 验证本地运行时：`hmg doctor`、`hmg daemon status`。
6. 查 Agent 自身的 MCP / hooks 日志是否有连接错误。

```bash
hmg doctor --agent codex
hmg init --agent codex --dry-run
hmg daemon status
```

## 会话里没有自动注入记忆上下文

**症状**：新会话开始时没有记忆简报，或每轮对话没有预取结果。

**排查**：
1. 确认 hooks 已注册且包含三个事件（`SessionStart` / `UserPromptSubmit` / `PreToolUse`）：
   ```bash
   cat ~/.codex/hooks.json        # Codex
   cat .cursor/hooks.json         # Cursor
   ```
2. 确认适配脚本存在且可执行：`ls -l ~/.codex/hooks/hmg-lifecycle.sh`。
3. 手动验证 dispatch 链路（在项目目录里执行）：
   ```bash
   echo '{"hook_event_name":"SessionStart","cwd":"'"$PWD"'"}' | ~/.codex/hooks/hmg-lifecycle.sh
   ```
   正常会输出记忆简报文本；无输出或报错时看 `hmg doctor`。
4. hook 失败会静默跳过（不阻塞 Agent），所以「没报错但没有简报」时要按上面步骤主动排查。
5. 重新接入：`hmg init --agent <id>` 会重写 hooks 配置。

## HMG 服务没有启动

**症状**：命令报 daemon 不可用、模型未就绪，或持续 fallback direct。

**排查**：
1. 先执行 `hmg setup`，确保本地运行时已准备好。
2. `hmg model status` 看嵌入模型状态。
3. `hmg daemon status` 查 daemon 状态。
4. 启动失败时看错误信息；store 路径不对用 `--store` 指定。
5. 仍异常时：`hmg daemon restart`，或临时 `--direct` 绕过 daemon 直开 store。
6. 需要自启动可用 `hmg daemon install-service`。

```bash
hmg setup
hmg model status
hmg daemon status
```

## 登录失败 / 套餐未生效

**症状**：`hmg login` 报错，或官网已升级套餐但本地能力未解锁。

**排查**：
1. 登录必须联网：确认网络/代理可达 HMG 用户中心。
2. 确认已在官网完成套餐升级，且 `hmg login` 使用的账号与购买套餐的账号一致。
3. 签名校验失败时重试一次；仍失败联系支持并附上 `hmg doctor --verbose` 输出。
4. 登录只影响开发者版能力与容量上限，不影响基础记忆功能——未登录也可正常使用。

## 召回不到想要的信息 {#recall-cannot-find}
**可能原因与对策**：

| 原因 | 对策 |
|------|------|
| query 太宽或太口语化 | 用名词短语，`登录 500 根因` 优于 `我们之前怎么处理的` |
| 记忆没写过 | 先 `hmg memorize` 补上 |
| 作用域不对 | 当前仓库/分支与记忆时不一致，指定 `--scope`；注意临时会话的记忆在 `personal/chats/main`，项目会话里看不到 |
| 记忆被降级/墓碑化 | `hmg history <id>` 查状态 |
| 噪声干扰 | `hmg noise-feedback` 反馈噪声词 |
| 拼写/术语差异 | 换同义词，或用 `hmg suggest-query` 让 HMG 推荐 |

## 召回结果太多或太乱

**对策**：
1. 收窄 query。
2. 用 `--max-results <n>` 限制条数。
3. 用 `--profile compact` 精简输出。
4. 清理过期记忆：`hmg store hygiene`、纠正/降级旧信息。
5. 反馈噪声：`hmg noise-feedback "<噪声短语>"`。

## 记忆写错了怎么办

**不是删除，是纠正**：

```bash
# 内容错了 → 替换
hmg correct <atom-id> --action replace --reason "写错了" --new-content "正确内容"

# 不再需要 → 降级
hmg correct <atom-id> --action demote-possible --reason "已不适用"
```

replace 写错了就在那条 atom 上继续 replace。纠正保留历史，`hmg history <atom-id>` 可追溯。

## 误写敏感信息怎么办

**立即治理，不要只删**（保留审计）：

```bash
# 彻底清除（墓碑化 + 销毁 payload）
hmg govern <atom-id> --action tombstone --destroy-payload --reason "误写 API key"

# 仅隔离（保留内容但召回不出现）
hmg govern <atom-id> --action quarantine --reason "敏感信息暂隔离"

# 提炼脱敏教训
hmg govern <atom-id> --action derive-lesson --lesson "凭证应存 secret vault"
```

以后该用 `hmg secret store` 存凭证。详见 [删除或隔离敏感信息](daily-usage.md#sensitive-memory-governance)。

## 多项目记忆混在一起怎么办

**原因**：共用默认 store 且没区分作用域。

**对策**：
1. Agent 集成中 scope 由会话目录自动推断，一般不会出现；如在非项目目录启动了会话，记忆会落到该目录推断出的 scope。
2. 给项目独立 store：`hmg memorize "..." --store /proj/store`。
3. 或在默认 store 内显式 `--scope repository`/`branch`。
4. 跨项目通用偏好才放 `--scope tenant`。

作用域机制详见 [作用域](concepts.md#scope)。

## store lock 或 daemon 异常怎么办

**症状**：写入报锁错误，或 daemon 无响应。

**排查**：
1. `hmg daemon status` 确认是否卡死。
2. `hmg daemon restart` 重启。
3. 检查是否有多个进程争用同一 store（多 Agent + 直接 CLI 同时写）。建议统一走 daemon。
4. 索引损坏：`hmg store repair-edges --backup --apply`。
5. 仍不行：备份 store 后 `--direct` 模式操作排查。

## 如何备份或迁移本地数据 {#backup-or-migrate-local-data}
```bash
# 备份：复制目录
cp -r "<store目录>" ./hmg-backup-$(date +%F)

# 或导出
hmg export --format json --output ./hmg-export.json

# 迁移到新机器/新路径
hmg store migrate --from /old/store --to /new/store --backup --apply
```

> 默认 store 路径见 [Store 目录说明](settings.md#store-directory)，`hmg doctor --verbose` 可打印。

---

下一章：[FAQ](faq.md)
