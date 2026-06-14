# Issue #627: auto: Namespace auto-checkpoint State File by BATCH_ID for Parallel --batch Sessions

## Overview

`scripts/auto-checkpoint.sh` の batch state file (`.tmp/auto-batch-state.json`) が single-file 設計のため、並列 `/auto --batch` セッションが state を奪い合う問題を修正する。

各 batch session に一意の BATCH_ID (例: `${PPID}-$(date +%s)`) を割り当て、per-session ファイル (`.tmp/auto-batch-state-${BATCH_ID}.json`) に書き込む。また active batch の一覧を管理する index ファイル (`.tmp/auto-batch-active.json`) を新設し、`list_active_batches` サブコマンドで列挙できるようにする。

後方互換: BATCH_ID 未指定または "default" の場合は既存パス `.tmp/auto-batch-state.json` を使用し、単独運用ユーザーは無変更で動く。

## Changed Files

- `scripts/auto-checkpoint.sh`: BATCH_ID パラメータ追加 (`write_batch`, `read_batch`, `update_batch`, `delete_batch` の引数変更)、`list_active_batches` サブコマンド追加、`.tmp/auto-batch-active.json` active index 管理、backward compat 実装 — bash 3.2+ 互換
- `skills/auto/SKILL.md`: List mode に BATCH_ID 生成・伝播、Resume mode に `list_active_batches` 使用、Checkpoint Design セクション更新、frontmatter description 更新
- `tests/auto-checkpoint-batch.bats`: 新規ファイル — 並列 write 競合・resume 復元・後方互換の最小 3 テストケース
- `docs/structure.md`: `auto-checkpoint.sh` 説明更新（新サブコマンド + BATCH_ID）、テスト数 `(70 files)` → `(71 files)`
- `docs/ja/structure.md`: Japanese mirror 同期

## Implementation Steps

1. Update `scripts/auto-checkpoint.sh` — `_batch_file_path <batch_id>` ヘルパーを追加し、空/"default" → `.tmp/auto-batch-state.json`、それ以外 → `.tmp/auto-batch-state-${batch_id}.json` にマップ。`write_batch` を `write_batch <batch_id> <remaining> <completed> <failed>` に変更し、BATCH_ID が "default" 以外の場合は `.tmp/auto-batch-active.json` に batch_id を追加。`read_batch` を `read_batch <batch_id>` に変更。`update_batch` を `update_batch <batch_id> <issue> <result>` に変更。`delete_batch` を `delete_batch <batch_id>` に変更し active index から除去。`list_active_batches` サブコマンドを追加し active index の batch_id を1行ずつ出力。Usage コメント更新。(→ AC1, AC2, AC3, AC5, AC7)

2. Update `skills/auto/SKILL.md` — List mode 冒頭で BATCH_ID を生成 (`BATCH_ID="${PPID}-$(date +%s)"`); `write_batch`, `update_batch`, `delete_batch` のすべての呼び出しに BATCH_ID を第1引数として追加。Resume mode の Step 1 を `list_active_batches` 呼び出しから候補一覧取得 → 非対話モードでは最新 (最後の) エントリを BATCH_ID として使用 → `read_batch <BATCH_ID>` で remaining 取得に変更。`## Checkpoint Design` セクションの schema 例に BATCH_ID ファイル命名規則と active index スキーマを追記。frontmatter の description の `.tmp/auto-batch-state.json` 参照を BATCH_ID メカニズムの説明に更新。(→ AC4)

3. Create `tests/auto-checkpoint-batch.bats` — テストケース: (a) 並列 write 競合なし: 2つの異なる BATCH_ID で write_batch 後、各ファイルが独立して保持されること; (b) resume 復元: write_batch + update_batch 後に read_batch <batch_id> が正しい remaining を返すこと; (c) 後方互換: BATCH_ID 省略時 (または "default") が既存パス `.tmp/auto-batch-state.json` を使用すること。(→ AC6)

4. Update `docs/structure.md` and `docs/ja/structure.md` — `auto-checkpoint.sh` の説明を BATCH_ID パラメータと `list_active_batches` を含む内容に更新; Directory Layout の `tests/` コメントを `(71 files)` に変更; `docs/ja/structure.md` も同様に更新。(→ doc consistency)

## Verification

### Pre-merge

- <!-- verify: grep "BATCH_ID|batch_id" "scripts/auto-checkpoint.sh" --> `auto-checkpoint.sh` が BATCH_ID 引数を受け付ける
- <!-- verify: grep "list_active_batches" "scripts/auto-checkpoint.sh" --> `list_active_batches` メソッドが実装されている
- <!-- verify: file_contains "scripts/auto-checkpoint.sh" "auto-batch-active.json" --> active batch index ファイル管理が実装されている
- <!-- verify: grep "BATCH_ID" "skills/auto/SKILL.md" --> `/auto` skill が BATCH_ID を生成・伝播する
- <!-- verify: rubric "auto-checkpoint.sh maintains backward compatibility: when BATCH_ID is omitted, it defaults to 'default' and maps to the existing .tmp/auto-batch-state.json file path. Existing single-session --resume continues to work without changes" --> 後方互換性が rubric 基準で確認できる
- <!-- verify: command "bats tests/auto-checkpoint-batch.bats" --> bats テストが green（並列 write 競合・resume 復元・後方互換の最小 3 ケース）
- <!-- verify: command "bash -n scripts/auto-checkpoint.sh" --> 構文エラーなし

### Post-merge

- 2 つの並列 `/auto --batch` 実行で互いの state を上書きしないことを観察 <!-- verify-type: observation event=concurrent-batch -->
- 中断後の `/auto --resume --batch --batch-id <id>` で正しい batch が復元できることを確認 <!-- verify-type: observation event=batch-resume -->

## Notes

- **BATCH_ID 生成形式**: `${PPID}-$(date +%s)` を採用。親プロセス PID + Unix タイムスタンプで実用的な一意性を確保。bash 3.2 互換。
- **`_batch_file_path` ヘルパー設計**: `[[ -z "$batch_id" || "$batch_id" == "default" ]]` で backward compat 判定。既存の `cmd_read_batch` / `cmd_write_batch` などが内部でこのヘルパーを呼ぶように変更する。
- **active index `.tmp/auto-batch-active.json` スキーマ**:
  ```json
  {"schema_version":"v1","active_batch_ids":["12345-1718336400","67890-1718336500"],"last_update":"..."}
  ```
  write_batch 時に batch_id を追加（"default" は追加しない）、delete_batch 時に除去。atomic write (*.tmp → mv)。
- **`list_active_batches` 出力**: active_batch_ids の各エントリを1行ずつ stdout に出力。absent/empty → 空文字。
- **Resume mode の non-interactive 選択**: `list_active_batches` の出力が複数行の場合、最後の行 (最新) を BATCH_ID として使用する。
- **verify-executor ripgrep**: `grep "BATCH_ID|batch_id"` は `|` が alternation として機能するため、実装コードに "BATCH_ID" が含まれれば PASS する。
- **Pre-merge verify 数**: 7 項目 (light limit=5 を超過)。Issue body が 7 項目定義済みのため verbatim コピーとし、削減しない。

## Code Retrospective

### Deviations from Design

- `tests/auto-checkpoint.bats`（既存）の更新は Spec の "Changed Files" に未記載だったが、`write_batch` / `update_batch` の API 変更（引数追加）後も既存テストが通るよう arg count 検出で旧 API を吸収した。既存テストの改変は不要だった。

### Design Gaps/Ambiguities

- 後方互換の実現方法について Spec は「BATCH_ID 未指定時は default」と定義するが、スクリプトレベルで 3-arg `write_batch` と 4-arg `write_batch` をどう区別するかが未定義だった。arg count 検出（`$# == 3` → old API、`$# >= 4` → new API）で解決し、既存テストを無変更で通過させた。

### Rework

- N/A

## review retrospective

### Spec vs. implementation divergence patterns

- Spec定義と実装の整合性は良好。`_batch_file_path`、`list_active_batches`、BATCH_ID生成・伝播すべてSpec通りに実装されていた。
- `_add_to_active_index` の戻り値チェック漏れを発見・修正。Specには記載のないエラー処理の詳細だったが、resume機能の信頼性に影響するSHOULD指摘として適切だった。

### Recurring issues

- なし（同種の問題の繰り返しは見られない）。
- エラー処理の非対称パターン（既存ファイル更新分岐は`if ! jq ...`でチェックするが、新規作成分岐はチェックしない）が1件見られたが、CONSIDERレベルで留置。今後のshell scriptレビューでは非対称なエラーチェックパターンに注意する。

### Acceptance criteria verification difficulty

- 7件のpre-merge ACすべてがgrep/file_contains/rubric/commandで自動検証可能だった。UNCERTAINなし。
- `command`型2件（bats/bash -n）はsafe modeでCI参照フォールバックを使用→SUCCESS確認。verify commandの品質は高い。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #634 を `--squash --delete-branch` でマージ。`mergeable=true, ci_status=success, review_status=approved` のため競合解消・テスト実行不要
- BASE_BRANCH=main のため `closes #627` が自動でIssueをクローズする
- review フェーズから引き継いだ SHOULD指摘（`_add_to_active_index` 戻り値チェック）は実装済みでマージ済み

### Deferred Items
- Post-merge AC 2件（observation: concurrent-batch / batch-resume）は /verify フェーズで実施
- `_add_to_active_index` else分岐のエラーチェック非対称（CONSIDER）は留置

### Notes for Next Phase
- Spec の Post-merge verification（並列 `/auto --batch` での state 非衝突、`/auto --resume --batch --batch-id <id>` での正しい batch 復元）が verify の主要確認事項
- verify-type: observation の2件は自動実行不可のため手動またはSKIP扱いになる可能性あり
