# Issue #317: auto: --resume で batch 残リストと verify counter を復元

## Overview

`/auto` 実行中の中断（Ctrl+C、ターミナル切断、OS 再起動等）後の再開コスト低減を目的として、checkpoint ファイルによる2種類の情報永続化を追加する。

- **単一 Issue**: verify iteration counter を `.tmp/auto-state-$NUMBER.json` に保存し、`/auto --resume N` で復元
- **Batch List mode**: 残 Issue リストを `.tmp/auto-batch-state.json` に保存し、`/auto --batch --resume` (引数なし) で自動継続

**設計方針 (reconciler-first / checkpoint-as-hint)**:
現在 phase の権威ソースは GitHub labels + `reconcile-phase-state.sh`。checkpoint は verify カウンタ (単一 Issue) と batch 残リストのみを保持する。checkpoint と labels が矛盾する場合は labels を優先し、checkpoint を破棄 (stale 判定)。

XL route (sub-issue 並列実行) は本 Issue のスコープ外。

## Changed Files

- `skills/auto/SKILL.md`: `--resume N` / `--batch --resume` フラグ解析追加、VERIFY_ITERATION_COUNT 追跡、checkpoint 読み書き・stale 判定・cleanup ロジック追加、allowed-tools 更新
- `scripts/auto-checkpoint.sh`: 新規ファイル — checkpoint 操作ヘルパースクリプト (bash 3.2+ 互換)
- `tests/auto-checkpoint.bats`: 新規ファイル — `auto-checkpoint.sh` のテストケース
- `docs/tech.md`: `/auto` Architecture Decision に `--resume` / checkpoint 記述追加
- `docs/workflow.md`: `/auto` セクションに `--resume` / `--batch --resume` 追加
- `docs/structure.md`: Scripts セクションに `auto-checkpoint.sh` 追加
- `docs/ja/tech.md`: translation sync
- `docs/ja/workflow.md`: translation sync
- `docs/ja/structure.md`: translation sync

## Implementation Steps

1. **Create `scripts/auto-checkpoint.sh`** (new, bash 3.2+): subcommands `read_single <NUMBER>`, `write_single <NUMBER> <COUNT>`, `delete_single <NUMBER>`, `read_batch`, `write_batch <REMAINING> <COMPLETED> <FAILED>`, `update_batch <NUMBER> complete|fail`, `delete_batch`; atomic write via `*.json.tmp → mv`; `read_single` performs stale detection (issue_number mismatch → echo 0 and exit 0); uses `jq` for JSON manipulation; `.tmp/` directory created if absent (→ acceptance criteria: bats test file exists, CI passes)

2. **Update `skills/auto/SKILL.md` — flag parsing and allowed-tools**: in Step 1, add `--resume N` detection (sets RESUME_MODE=true, extracts NUMBER); add `--batch --resume` detection (no numeric tokens after `--batch` AND `--resume` present → RESUME_BATCH=true → branch to new `### Resume mode (--batch --resume)` section); add `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh:*` to `allowed-tools` Bash entry (→ acceptance criteria: all 3 rubric items)

3. **Update `skills/auto/SKILL.md` — checkpoint lifecycle**: (a) initialize VERIFY_ITERATION_COUNT: on RESUME_MODE=true call `read_single $NUMBER` and restore count; on normal mode start at 0; (b) in Step 4 before each verify run call `write_single $NUMBER $VERIFY_ITERATION_COUNT`; after verify success or MAX_ITERATIONS_REACHED call `delete_single $NUMBER`; (c) in Batch List mode: call `write_batch` with full list at start; call `update_batch $NUMBER complete|fail` after each Issue; call `delete_batch` on batch completion; (d) add `### Resume mode (--batch --resume)` section: call `read_batch`, if remaining empty output "No resume target found" and exit, otherwise process `remaining` as List mode; (e) document JSON v1 schemas, atomic write pattern, stale detection (issue_number mismatch → discard; label conflict → labels win), cleanup triggers (phase/done, Issue CLOSED, batch completion) in SKILL.md (→ acceptance criteria: all 3 rubric items)

4. **Create `tests/auto-checkpoint.bats`** (new): 5 test cases — (a) `single checkpoint write and read: schema integrity`, (b) `stale detection: mismatched issue_number is discarded`, (c) `batch checkpoint: remaining/completed/failed transitions`, (d) `atomic write: partial write leaves original file intact`, (e) `cleanup: delete_single removes checkpoint file` (→ acceptance criteria: file_exists)

5. **Update docs and translation sync**: `docs/tech.md` — append `--resume N` / `--batch --resume` to `/auto` Architecture Decision (`--batch N1 N2 ...` 行の直後に追記); `docs/workflow.md` — add `**--resume N**` / `**--batch --resume**` paragraph under the existing `--batch` paragraph; `docs/structure.md` — add `scripts/auto-checkpoint.sh` entry under Skill runners or Process management section; sync `docs/ja/tech.md`, `docs/ja/workflow.md`, `docs/ja/structure.md` with the same additions in Japanese (→ documentation consistency)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md documents a `--resume` option for both single-issue (`/auto --resume N`) and batch (`/auto --batch --resume`) invocations, and clearly states that `reconcile-phase-state.sh` plus GitHub labels are the authority for current phase while the checkpoint file carries only verify iteration counter (single) or remaining list (batch)." --> `--resume` option と reconciler-first / checkpoint-as-hint の責務分離が SKILL.md に記載されている
- <!-- verify: rubric "skills/auto/SKILL.md defines a JSON v1 schema for `.tmp/auto-state-$NUMBER.json` (single) and `.tmp/auto-batch-state.json` (batch) with atomic write via `*.json.tmp` → `mv`, and specifies cleanup on `phase/done` / Issue CLOSED / batch completion." --> checkpoint schema、atomic write、cleanup 仕様が記載されている
- <!-- verify: rubric "skills/auto/SKILL.md states that stale checkpoints (mismatched issue_number, or conflicting with live labels) are discarded in favor of the label + reconciler state." --> stale 判定ルールが記載されている
- <!-- verify: file_exists "tests/auto-checkpoint.bats" --> bats テストファイルが存在する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが CI で PASS する

### Post-merge

- L size の `/auto` を verify loop 中に意図的に中断し、`/auto --resume N` で verify iteration_count が復元され、ラベル状態から正しい phase で再開できることを確認
- `/auto --batch 5 件` 実行中に 2 件目処理中で中断し、`/auto --batch --resume` (引数なし) で残 3 件が自動継続されることを確認
- Checkpoint と現状ラベルが矛盾する状況 (例: 手動で phase/done に遷移) を作り、`/auto --resume N` が checkpoint を破棄してラベル優先で動作することを確認

## Notes

**`auto-checkpoint.sh` コマンドインタフェース (bats test 入力フォーマット)**:
- `read_single <NUMBER>` → stdout に verify_iteration_count の整数値 (stale/absent → 0)
- `write_single <NUMBER> <COUNT>` → `.tmp/auto-state-<NUMBER>.json` を atomic write
- `delete_single <NUMBER>` → `.tmp/auto-state-<NUMBER>.json` を削除 (absent は noop, exit 0)
- `read_batch` → stdout に remaining list (スペース区切り数値列; absent/empty → "")
- `write_batch <REMAINING> <COMPLETED> <FAILED>` → `.tmp/auto-batch-state.json` を atomic write (各引数はスペース区切り数値列; 空は "")
- `update_batch <NUMBER> complete|fail` → remaining から completed/failed へ移動 (atomic write)
- `delete_batch` → `.tmp/auto-batch-state.json` を削除 (absent は noop, exit 0)

**JSON スキーマ**:
```json
// .tmp/auto-state-$NUMBER.json
{
  "schema_version": "v1",
  "issue_number": 317,
  "verify_iteration_count": 2,
  "last_update": "2026-04-22T16:10:05Z"
}

// .tmp/auto-batch-state.json
{
  "schema_version": "v1",
  "mode": "list",
  "remaining": [104, 105],
  "completed": [101, 102],
  "failed": [103],
  "last_update": "2026-04-22T16:10:05Z"
}
```

**stale 判定の責務分担**:
- `auto-checkpoint.sh read_single`: `issue_number` 不一致のみ処理 (→ return 0)
- label conflict check: SKILL.md レベルで `gh issue view --json labels` と照合; 矛盾が検出されたら `delete_single` を呼び出してから処理継続

**スコープ外**: XL route 向け checkpoint 拡張 (sub-issue 依存グラフ + worktree 並列状態) は follow-up Issue で対応。

**`--batch --resume` と Count mode**: `--batch N` (Count mode) では `.tmp/auto-batch-state.json` は生成しない。`--batch --resume` 実行時にファイルが存在しない場合は "No resume target found" で即終了。

## Spec Retrospective

N/A

## Code Retrospective

### Deviations from Design

- Spec では `docs/structure.md` のスクリプトカウント更新は明示されていなかったが、実装中に 41→42 (scripts) および 46→50 (tests) のカウント不整合を発見し追加修正した。docs/ja/structure.md も同様に更新。これはdoc-checkerが検出した追加修正で、Spec の範囲外の副次的な修正。

### Design Gaps/Ambiguities

- Spec の `## Implementation Steps` Step 2 に `VERIFY_ITERATION_COUNT` のカウントアップ（+1）について明示がなかった。verify run 後にカウントを更新するロジックが SKILL.md に必要だが、Spec では書き込みタイミング（`write_single $NUMBER $VERIFY_ITERATION_COUNT`）のみ指定されており、カウントアップ自体が誰の責務かが曖昧。今回は `/auto` 自身がカウントアップ責務を持つとして SKILL.md に記述した。

### Rework

- なし

## review retrospective

### Spec vs. Implementation Divergence Patterns

- **VERIFY_ITERATION_COUNT インクリメント未記述**: Code Retrospective に「`/auto` 自身がカウントアップ責務を持つとして SKILL.md に記述した」と明記されていたが、実際には SKILL.md にインクリメントステップが存在しなかった。Spec の `Implementation Steps` に increment のタイミングを明示していなかったことが根因。今後の Spec では「カウント変更を行う操作」について変更前後の値と変更タイミングを具体的に記述する。

### Recurring Issues

- `cmd_update_batch` の jq 失敗時ガード漏れは、atomic write のパターン（write → mv）は実装されているが read-then-write パスのエラーハンドリングが漏れていた。Spec に「既存ファイルを入力とする書き込み操作は jq 失敗時のガードも明記する」旨を今後追加する。
- `delete_batch` テストの欠落: Spec Step 4 で列挙した 5 件のテストケースが `delete_single` を含むが `delete_batch` を含んでいなかった。checkpoint の対称性から `write_batch` と `delete_batch` はペアでテストを定義する。

### Acceptance Criteria Verification Difficulty

- verify コマンドはすべて rubric / file_exists / github_check の3種類で構成されており、UNCERTAIN は発生しなかった。github_check による CI 結果確認が verify 条件に含まれていたため、CI 完了後のレビューでは迷わずに判定できた。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec Retrospective は N/A。設計方針（reconciler-first）の責務分担や stale 判定の2パターンはこの Spec で明確に定義されており、受け入れ条件も rubric による semantic 判定で適切に設定されていた。

#### design
- VERIFY_ITERATION_COUNT のインクリメントタイミングが Spec の `Implementation Steps` に明示されておらず、Code 実装で「`/auto` 自身がカウントアップ」と解釈したが初期実装でそのステップが欠落していた。今後の Spec では「カウント変更操作」のタイミングと責務担当者を明記する。
- `docs/structure.md` のスクリプトカウント更新は Spec 対象外だったが、doc-checker が不整合を検出して追加修正が必要になった。ドキュメント整合性チェックを Spec の verification に含めるか検討の余地あり。

#### code
- PR #343 のコミット履歴に "Address review feedback: add VERIFY_ITERATION_COUNT increment and robustness" という rework コミットが1件存在。レビュー指摘を受けた修正であり、Spec の曖昧さが起因。
- Spec 未記載の副次修正（structure.md カウント修正）が1コミット追加された。

#### review
- レビューが効果的に機能し、VERIFY_ITERATION_COUNT のインクリメント欠落、`cmd_update_batch` の jq エラーガード漏れ、`delete_batch` テスト欠落を検出・修正させた。
- Review Retrospective で指摘された問題はすべて rework コミットで対応されており、マージ前に品質が担保された。

#### merge
- squash merge（PR #343）で競合なし。マージコミット `8c402c7` のみ。

#### verify
- Pre-merge 5条件すべて PASS（rubric ×3、file_exists ×1、github_check ×1）。UNCERTAIN/FAIL なし。
- `github_check "gh pr checks" "Run bats tests"` が2つの CI run でいずれも pass（3分46秒、3分55秒）を確認。
- Post-merge manual 条件3件（verify loop 中断→resume、batch 中断→resume、stale 判定実機確認）は手動検証待ち。

### Improvement Proposals
- Spec の `Implementation Steps` でカウント変更操作（increment/decrement/reset）を記述する際は変更前後の値と変更タイミング（どの操作の前 or 後）を必ず明記する。
- `write_batch` のようにファイルを読み込んで書き戻す操作は、jq 失敗時のガード（`|| die "..."` 等）を Spec 段階で明示する。
