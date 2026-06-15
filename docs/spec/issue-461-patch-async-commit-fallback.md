# Issue #461: reconcile-phase-state code-patch async external commit fallback

## Overview

`reconcile-phase-state.sh code-patch <issue> --check-completion` で、外部ツール（Obsidian Git 等）が `<タイムスタンプ>` 形式の自動コミットを行うパスのみを成果物とする patch タスクで、`matches_expected:false` を返す構造的 false-negative を修正する。

一次チェック（`closes #N` git log）を維持しつつ、コミットが見つからない場合のフォールバックとして phase ラベル（`phase/verify` / `phase/done`）または Issue の CLOSED 状態を確認する二段階判定を `_completion_code_patch` に追加する（方針 C）。

## Reproduction Steps

1. patch ルートの Issue で、成果物が外部ツール自動コミット領域のみ（例: Obsidian vault のノート）
2. 外部ツールが `vault backup: 2024-01-01T00:00:00Z` 形式でコミット（`closes #N` なし）
3. `/review` が完了し `phase/verify` ラベルが付与された状態
4. `reconcile-phase-state.sh code-patch <issue> --check-completion` を実行
5. `"matches_expected":false` が返り Tier 3 サブエージェントが起動する

## Root Cause

`_completion_code_patch()` は `origin/main` の git log を `--grep="closes #${ISSUE_NUMBER}"` で検索するだけで、phase ラベルや Issue 状態を確認しない。外部ツールのコミットには `closes #N` が含まれないため、成果物が存在しても false-negative になる。

`_completion_spec()` は「spec ファイル存在 + ready-or-later ラベル」の二段階確認で同様の問題を回避しており、同パターンを `_completion_code_patch` に適用するのが最小リスクの修正方針。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_completion_code_patch` を二段階判定に変更（`closes #N` 未検出時に phase/verify・phase/done ラベルまたは CLOSED 状態をフォールバック確認）— bash 3.2+ 互換
- `tests/reconcile-phase-state.bats`: 既存の「no matching commit → mismatch」テスト 2 件に `gh` モック追加（フォールバックが予期せず起動するのを防ぐ）; async fallback テストケース 1 件追加

- `modules/orchestration-fallbacks.md`: `async-external-commit` エントリ追加

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` の `_completion_code_patch` を修正（→ AC1, AC2, AC6）:
   - `found=true` の場合は即座に `_emit_result "true"` で `return`（早期リターンに変更）
   - `mismatch_diag` 変数に mismatch 時のメッセージを格納
   - 関数末尾にフォールバック処理を追加: `# See modules/orchestration-fallbacks.md#async-external-commit` コメント付きで `gh issue view "$ISSUE_NUMBER" --json labels` / `--json state` を `|| true` で呼び出し（非致命的）、`phase/(verify|done)` ラベルまたは `CLOSED` 状態であれば `_emit_result "true"` with "async" を含む diagnosis を出力

2. `tests/reconcile-phase-state.bats` を修正（→ AC3, AC4）:
   - 「no matching commit → mismatch」テスト（issue 55 使用）に `gh` モック追加（`--json labels` → `triaged`、`--json state` → `OPEN` を返す）
   - 「fix-cycle false positive - pre-reopen commit only → matches_expected false」テスト（issue 55 使用）に `gh` モック追加（同上）
   - 新テスト追加: `@test "code-patch completion: async external commit - no closes #N + phase/verify label -> matches_expected true"` — git log が空、gh モックが `phase/verify` + `OPEN` を返す場合に `matches_expected:true` かつ出力に `async` を含むことを検証（`gh-graphql.sh` モックは `null` を返す）

3. `modules/orchestration-fallbacks.md` に `## async-external-commit` エントリ追加（→ AC5）:
   - Symptom: 外部ツールが `closes #N` なしでコミット、phase ラベルは `phase/verify` 以降に進んでいる
   - Applicable Phases: code (patch route — `_completion_code_patch`)
   - Fallback Steps: `_completion_code_patch` の組み込み二段階チェックが自動処理（手動介入不要）
   - Rationale: `_completion_spec` の二段階確認パターンと一貫性、Issue #461 での導入経緯

## Verification

### Pre-merge

- <!-- verify: grep "async" "scripts/reconcile-phase-state.sh" --> `scripts/reconcile-phase-state.sh` の `_completion_code_patch` 関数に外部ツール非同期コミットを考慮したフォールバック判定（コメントまたは診断メッセージに "async" を含む）が追加されている
- <!-- verify: rubric "scripts/reconcile-phase-state.sh の _completion_code_patch 関数が closes #N コミット未検出時に phase/verify または phase/done ラベルをフォールバック判定として確認し matches_expected:true を返す二段階実装になっている" --> フォールバック判定（phase ラベル確認）が `_completion_code_patch` に実装されている
- <!-- verify: grep "async" "tests/reconcile-phase-state.bats" --> `tests/reconcile-phase-state.bats` に外部 async commit フォールバック（`closes #N` コミットなし + `phase/verify` ラベルあり → `matches_expected:true`）を検証するテストケースが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) 全ジョブが成功する（patch ルート）
- <!-- verify: grep "async" "modules/orchestration-fallbacks.md" --> `modules/orchestration-fallbacks.md` に外部ツール非同期コミットパターンのエントリが追加されている
- <!-- verify: file_contains "scripts/reconcile-phase-state.sh" "closes #${ISSUE_NUMBER}" --> 既存の `closes #N` git log 一次チェックが削除されずに維持されている

### Post-merge

- 外部ツール（Obsidian Git 等）が `vault backup: <timestamp>` 形式の自動コミットのみを成果物とする patch Issue で、オーケストレーター再実行時に `reconcile-phase-state.sh code-patch <issue> --check-completion` が `matches_expected:true` を返す（Tier 3 サブエージェントが不要になる）

## Notes

- 既存テストの `gh` モック追加が必要な理由: issue #55 と #42 が実際の repo で CLOSED + phase/verify ラベルを持つため、モックなしでは fallback が予期せず起動し既存テストが失敗する（`grep -qE '^phase/(verify|done)$'` が実際の gh 呼び出し結果にマッチする）
- フォールバックの `gh issue view` 呼び出しは `|| true` で非致命的 — `gh` が失敗した場合（モックなし等）でも `labels=""` / `state=""` となりフォールバック条件を満たさないため、既存の mismatch パスへフォールスルーする
- Pre-merge 検証項目が 6 件で light テンプレートの上限 5 件を超えるが、Issue body の AC をそのまま転記したため全件維持
