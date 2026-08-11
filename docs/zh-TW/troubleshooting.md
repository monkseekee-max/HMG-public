# 故障排查

## 安裝失敗 {#install-failure}
**症狀**：`hmg --version` 無輸出或命令找不到。

**排查**：
1. 確認安裝器是否執行成功，檢查 PATH 是否含 HMG 安裝目錄。
2. 重新執行官方安裝命令。
3. 手動驗證二進位制可執行：
   ```bash
   /完整路徑/hmg --version
   ```
4. 網路/許可權問題導致下載失敗，檢查代理與磁碟許可權。

## Agent 看不到 HMG 工具 {#agent-cant-see-hmg-tools}
**症狀**：Agent 會話裡沒有 `memory_memorize` / `memory_recall` 等 `memory_*` 工具。

**排查**：
1. 確認 MCP 配置已生成：`hmg doctor --agent <id>`。
2. 先執行 `hmg init --agent <id> --dry-run`，確認當前版本會寫哪些宿主檔案。
3. 檢查配置是否使用 `hmg-server <store-path>`。
4. 重啟 Agent（MCP 配置通常需要重啟生效）。
5. 驗證本地執行時：`hmg doctor`、`hmg daemon status`。
6. 查 Agent 自身的 MCP / hooks 日誌是否有連線錯誤。

```bash
hmg doctor --agent codex
hmg init --agent codex --dry-run
hmg daemon status
```

## 會話裡沒有自動注入記憶上下文

**症狀**：新會話開始時沒有記憶簡報，或每輪對話沒有預取結果。

**排查**：
1. 確認 hooks 已註冊且包含三個事件（`SessionStart` / `UserPromptSubmit` / `PreToolUse`）：
   ```bash
   cat ~/.codex/hooks.json        # Codex
   cat .cursor/hooks.json         # Cursor
   ```
2. 確認適配指令碼存在且可執行：`ls -l ~/.codex/hooks/hmg-lifecycle.sh`。
3. 手動驗證 dispatch 鏈路（在專案目錄裡執行）：
   ```bash
   echo '{"hook_event_name":"SessionStart","cwd":"'"$PWD"'"}' | ~/.codex/hooks/hmg-lifecycle.sh
   ```
   正常會輸出記憶簡報文字；無輸出或報錯時看 `hmg doctor`。
4. hook 失敗會靜默跳過（不阻塞 Agent），所以「沒報錯但沒有簡報」時要按上面步驟主動排查。
5. 重新接入：`hmg init --agent <id>` 會重寫 hooks 配置。

## HMG 服務沒有啟動

**症狀**：命令報 daemon 不可用、模型未就緒，或持續 fallback direct。

**排查**：
1. 先執行 `hmg setup`，確保本地執行時已準備好。
2. `hmg model status` 看嵌入模型狀態。
3. `hmg daemon status` 查 daemon 狀態。
4. 啟動失敗時看錯誤資訊；store 路徑不對用 `--store` 指定。
5. 仍異常時：`hmg daemon restart`，或臨時 `--direct` 繞過 daemon 直開 store。
6. 需要自啟動可用 `hmg daemon install-service`。

```bash
hmg setup
hmg model status
hmg daemon status
```

## 登入失敗 / 套餐未生效

**症狀**：`hmg login` 報錯，或官網已升級套餐但本地能力未解鎖。

**排查**：
1. 登入必須聯網：確認網路/代理可達 HMG 使用者中心。
2. 確認已在官網完成套餐升級，且 `hmg login` 使用的賬號與購買套餐的賬號一致。
3. 簽名校驗失敗時重試一次；仍失敗聯絡支援並附上 `hmg doctor --verbose` 輸出。
4. 登入隻影響開發者版能力與容量上限，不影響基礎記憶功能——未登入也可正常使用。

## 召回不到想要的資訊 {#recall-cannot-find}
**可能原因與對策**：

| 原因 | 對策 |
|------|------|
| query 太寬或太口語化 | 用名詞短語，`登入 500 根因` 優於 `我們之前怎麼處理的` |
| 記憶沒寫過 | 先 `hmg memorize` 補上 |
| 作用域不對 | 當前倉庫/分支與記憶時不一致，指定 `--scope`；注意臨時會話的記憶在 `personal/chats/main`，專案會話裡看不到 |
| 記憶被降級/墓碑化 | `hmg history <id>` 查狀態 |
| 噪聲干擾 | `hmg noise-feedback` 反饋噪聲詞 |
| 拼寫/術語差異 | 換同義詞，或用 `hmg suggest-query` 讓 HMG 推薦 |

## 召回結果太多或太亂

**對策**：
1. 收窄 query。
2. 用 `--max-results <n>` 限制條數。
3. 用 `--profile compact` 精簡輸出。
4. 清理過期記憶：`hmg store hygiene`、糾正/降級舊資訊。
5. 反饋噪聲：`hmg noise-feedback "<噪聲短語>"`。

## 記憶寫錯了怎麼辦

**不是刪除，是糾正**：

```bash
# 內容錯了 → 替換
hmg correct <atom-id> --action replace --reason "寫錯了" --new-content "正確內容"

# 不再需要 → 降級
hmg correct <atom-id> --action demote-possible --reason "已不適用"
```

replace 寫錯了就在那條 atom 上繼續 replace。糾正保留歷史，`hmg history <atom-id>` 可追溯。

## 誤寫敏感資訊怎麼辦

**立即治理，不要只刪**（保留審計）：

```bash
# 徹底清除（墓碑化 + 銷燬 payload）
hmg govern <atom-id> --action tombstone --destroy-payload --reason "誤寫 API key"

# 僅隔離（保留內容但召回不出現）
hmg govern <atom-id> --action quarantine --reason "敏感資訊暫隔離"

# 提煉脫敏教訓
hmg govern <atom-id> --action derive-lesson --lesson "憑證應存 secret vault"
```

以後該用 `hmg secret store` 存憑證。詳見 [刪除或隔離敏感資訊](daily-usage.md#sensitive-memory-governance)。

## 多專案記憶混在一起怎麼辦

**原因**：共用預設 store 且沒區分作用域。

**對策**：
1. Agent 整合中 scope 由會話目錄自動推斷，一般不會出現；如在非專案目錄啟動了會話，記憶會落到該目錄推斷出的 scope。
2. 給專案獨立 store：`hmg memorize "..." --store /proj/store`。
3. 或在預設 store 內顯式 `--scope repository`/`branch`。
4. 跨專案通用偏好才放 `--scope tenant`。

作用域機制詳見 [作用域](concepts.md#scope)。

## store lock 或 daemon 異常怎麼辦

**症狀**：寫入報鎖錯誤，或 daemon 無響應。

**排查**：
1. `hmg daemon status` 確認是否卡死。
2. `hmg daemon restart` 重啟。
3. 檢查是否有多個程序爭用同一 store（多 Agent + 直接 CLI 同時寫）。建議統一走 daemon。
4. 索引損壞：`hmg store repair-edges --backup --apply`。
5. 仍不行：備份 store 後 `--direct` 模式操作排查。

## 如何備份或遷移本地資料 {#backup-or-migrate-local-data}
```bash
# 備份：複製目錄
cp -r "<store目錄>" ./hmg-backup-$(date +%F)

# 或匯出
hmg export --format json --output ./hmg-export.json

# 遷移到新機器/新路徑
hmg store migrate --from /old/store --to /new/store --backup --apply
```

> 預設 store 路徑見 [Store 目錄說明](settings.md#store-directory)，`hmg doctor --verbose` 可列印。

---

下一章：[FAQ](faq.md)
