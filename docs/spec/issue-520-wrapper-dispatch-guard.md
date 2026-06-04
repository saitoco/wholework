# Issue #520: run-*.sh: headless claude -p が対象スキルでなく別スキルを誤起動し silent no-op で exit 0 する

## Overview

`run-*.sh`（`run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-issue.sh`）は headless `claude -p` で SKILL.md body をプロンプトとして渡しスキルを起動するが、起動直後に system-level の auto-trigger スキル（例: `claude-md-management:revise-claude-md`）へ誤ルーティングするケースがある。誤起動すると本来の手順が走らず、コミットなし／アーティファクト未生成のまま exit 0 で終了し、`/auto` のフェーズが「成功」と見える silent no-op を生む。

本 Issue は 2 つの対策を 5 つの wrapper に追加する:
- **主対策**: プロンプト先頭にガード文（他スキルを起動しない旨）を付与し、誤起動を構造的に防止する（現状の body passthrough 方式は維持）。
- **副対策**: `claude -p` が exit 0 で戻った場合にも `reconcile-phase-state.sh --check-completion` を呼び出し、`matches_expected` が false の場合は exit 1 を返す silent-fail ハードガードを追加する。

本 Issue は #464（run-code 特化）と #499 のスコープを統合した canonical Issue。`run-auto-sub.sh` はスコープ外（直接スキル起動せず、`detect-wrapper-anomaly.sh` で異常検知済み: #369）。

## Reproduction Steps

1. `run-spec.sh <N>`（model=sonnet, effort=max, permission-mode auto）を実行する。
2. headless `-p` セッションが起動直後に `/spec` ではなく `claude-md-management:revise-claude-md` を実行し「CLAUDE.md に追加する知見なし → 変更不要」と結論して `Exit code: 0` で終了する。
3. spec ファイルが未生成のまま。`reconcile-phase-state.sh spec <N> --check-completion` → `matches_expected:false`（`spec_file:null`）。
4. しかし wrapper は exit 0 を返すため、`/auto` は当該フェーズを「成功」とみなし silent no-op となる（intermittent、1 回観測）。

## Root Cause

2 つの独立した欠陥の組み合わせ:

1. **構造的防止の欠如**: body passthrough 方式でも、起動直後に available skills list に基づく auto-trigger（system skill）が割り込み、対象スキルの手順を実行しない経路が残っている。プロンプトに「他スキルを起動するな」という明示的制約がない。
2. **早期検出の欠如**: 全 wrapper の reconcile 呼び出しは `EXIT_CODE -eq 143`（watchdog timeout）の回復経路のみに存在し、`EXIT_CODE -eq 0` 時には完了検証が行われない。そのため誤起動由来の exit 0（コミットなし）が「成功」として伝播する。

なお #368 は `skills/auto/SKILL.md`（LLM オーケストレーション層）、#369 は `run-auto-sub.sh`（bash path）の exit 0 検証を扱ったが、5 つの直接 dispatch wrapper 自身の exit 0 reconcile は未対応であり、本 Issue がそのギャップを埋める。

## Changed Files

- `scripts/run-spec.sh`: ガード文を PROMPT 先頭に付与；exit 143 ブロックを exit 0 にも拡張し silent-fail ガードを追加 — bash 3.2+ compatible
- `scripts/run-code.sh`: 同上（`_RECONCILE_PHASE` の算出を両 exit 経路に hoist） — bash 3.2+ compatible
- `scripts/run-review.sh`: 同上（PR→issue 抽出を再利用） — bash 3.2+ compatible
- `scripts/run-merge.sh`: ガード文を付与；既存の inline PR-state ガードを reconcile ベースの統一ガードに置換（抽出失敗時のみ PR-state を fallback として残す） — bash 3.2+ compatible
- `scripts/run-issue.sh`: 同上 — bash 3.2+ compatible
- `tests/run-spec.bats`: `reconcile-phase-state.sh` mock を追加し、ガード文／exit 0 ガードのテストを追加
- `tests/run-code.bats`: `WHOLEWORK_SCRIPT_DIR` mock パターンへ移行し、reconcile mock とテストを追加
- `tests/run-review.bats`: 同上（`gh-extract-issue-from-pr.sh` mock も追加）
- `tests/run-merge.bats`: 同上に移行；post-validation テストを reconcile mock 駆動へ書き換え、抽出失敗 fallback テストを追加
- `tests/run-issue.bats`: 同上に移行し reconcile mock とテストを追加

## Implementation Steps

1. **5 wrapper にガード文を付与** (→ acceptance criteria AC1)
   - 各 wrapper の `PROMPT="${SKILL_BODY}..."` 構築箇所で、`${SKILL_BODY}` の直前にガード文（`GUARD_PREFIX`）を挿入する。文言は 5 スクリプトで同一とする（Notes の guard text 参照）。
   - `run-code.sh` は EXTRA_FLAGS 分岐の両方に適用する。挿入後も末尾の `ARGUMENTS:` 行は維持する（既存テストの prompt assertion を壊さない）。

2. **run-spec.sh に exit 0 reconcile ガードを追加** (→ acceptance criteria AC2, AC3)
   - 既存 `if [[ $EXIT_CODE -eq 143 ]]; then ... fi` ブロックの条件を `if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then` に拡張する。
   - 143 経路は従来どおり `matches_expected":true` で `EXIT_CODE=0` に上書き（watchdog timeout 回復）。
   - exit 0 経路は `matches_expected":false` を検出した場合に警告を stderr へ出力し `EXIT_CODE=1` を設定する（reconcile 出力が空＝検証不能の場合は exit 0 を維持）。

3. **run-code.sh に exit 0 reconcile ガードを追加** (parallel with 2) (→ acceptance criteria AC2)
   - `_RECONCILE_PHASE`（`code-patch`/`code-pr`）の算出をブロック冒頭へ移し、143／0 両経路で共用する。pre-claude の idempotency early-exit（既存 PR 検出時の exit 0）はこのブロックより前にあるため影響を受けない。

4. **run-review.sh に exit 0 reconcile ガードを追加** (parallel with 2) (→ acceptance criteria AC2)
   - 既存の PR→issue 抽出（`gh-extract-issue-from-pr.sh`）をブロック冒頭へ移し両経路で共用する。issue 番号を抽出できない場合は reconcile をスキップ（exit 0 維持）。

5. **run-issue.sh に exit 0 reconcile ガードを追加** (parallel with 2) (→ acceptance criteria AC2)
   - `issue` フェーズの reconcile を 143／0 両経路で実行する。

6. **run-merge.sh の exit 0 ガードを reconcile ベースへ統一** (parallel with 2) (→ acceptance criteria AC2)
   - 既存の inline PR-state post-validation ガード（`PR_STATE != MERGED` で exit 1）を削除し、`merge` フェーズ reconcile（抽出した issue + `--pr`）に置換する。
   - issue 番号を抽出できない場合のみ、直接 PR-MERGED-state チェックを fallback として残す（堅牢性維持）。

7. **5 wrapper の bats テストを更新** (after 1, 2, 3, 4, 5, 6) (→ acceptance criteria AC4)
   - `tests/run-code.bats` / `run-review.bats` / `run-merge.bats` / `run-issue.bats` を `WHOLEWORK_SCRIPT_DIR` mock パターン（template: `tests/run-spec.bats`、SSoT: `docs/tech.md` § BATS Mocking Convention）へ移行する。
   - 制御可能な `reconcile-phase-state.sh` mock（review/merge は `gh-extract-issue-from-pr.sh` mock も）と SKILL.md fixture を配置する。claude mock にガード文 substring 検出ログを追加する。
   - 各 wrapper に次のテストを追加: (a) prompt にガード文が含まれる、(b) exit 0 + `matches_expected:false` → exit 1、(c) exit 0 + `matches_expected:true` → exit 0、(d) reconcile error/空出力 → exit 0（false alarm なし）。
   - `run-merge.bats` の既存 post-validation テスト 3 件を reconcile mock 駆動へ書き換え、抽出失敗時の PR-state fallback テストを 1 件追加する。

## Alternatives Considered

該当なし（ISSUE_TYPE=Bug。本セクションは Feature 用のため内容なし）。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-*.sh 群（run-spec/run-code/run-review/run-merge/run-issue）の claude -p 起動プロンプトに、プロンプト先頭のガード文（他スキルを起動しない旨）または wholework:{name} 形式の明示指定または --disallowed-tools 等による無関係スキル抑止が追加されており、headless 実行での skill 誤 dispatch を構造的に防止している" --> 全 run-*.sh の claude -p 起動が skill 誤 dispatch を構造的に防止する形に更新されている
- <!-- verify: rubric "scripts/run-spec.sh / run-code.sh / run-review.sh / run-merge.sh / run-issue.sh が claude -p から exit 0 で戻った場合にも reconcile-phase-state.sh --check-completion を呼び出し、matches_expected が false の場合に非 0 exit code を返すよう更新されている" --> silent fail のハードガードが run-*.sh（exit 0 時の reconcile チェック）に追加されている
- <!-- verify: grep "matches_expected.*false" "scripts/run-spec.sh" --> run-spec.sh に matches_expected:false 時のエラーハンドリングが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが green
- <!-- verify: github_check "gh pr checks" "Validate skill syntax" --> CI の skill 構文検証が green

### Post-merge

- `/auto` 実行で skill 誤起動由来の silent no-op が観察されないことを実運用でモニタする <!-- verify-type: manual -->

## Tool Dependencies

allowed-tools frontmatter への追加は不要（実装は既存スクリプト／bats の編集のみ）。

### Bash Command Patterns
- none（新規追加なし）

### Built-in Tools
- none（`Read` / `Edit` / `Write` / `Bash` は実装に使用するが既存権限内）

### MCP Tools
- none

## Uncertainty

- **run-issue exit 0 ガードの完了シグネチャ依存**: `issue` フェーズの completion signature は `triaged` ラベル（`modules/phase-state.md`、SSoT）。triage→issue 順序により通常 `triaged` は付与済みのため正常完了は false 判定されないが、未 triage の issue に対し `run-issue.sh` を直接実行した場合、成功しても `matches_expected:false` となり silent no-op と誤判定する可能性がある。
  - **Verification method**: `modules/phase-state.md` の issue signature を確認；`/auto` が issue フェーズ前に triage を連鎖することを前提として許容（143 経路でも同シグネチャを既使用のため整合）。シグネチャ自体の変更は本 Issue スコープ外。
  - **Impact scope**: Implementation Step 5、Step 7 のテスト (b)/(c)（run-issue）
- **AC3 grep パターンの導入確認**: `grep "matches_expected.*false" "scripts/run-spec.sh"` が参照する文字列 `"matches_expected":false` は Step 2 で導入される。実装後に当該文字列が存在することを `/code` で確認すること。
  - **Verification method**: 実装後の `scripts/run-spec.sh` を grep
  - **Impact scope**: Implementation Step 2

## Notes

### guard text（5 スクリプト共通）

`${SKILL_BODY}` の直前に挿入する。半角感嘆符を含めない（SKILL.md 制約への配慮。`scripts/` は禁止表現 scan 対象外だが一貫性のため統一する）:

```
IMPORTANT - HEADLESS SKILL EXECUTION: Your only task is to follow the skill steps written below, in order, to completion. Do not invoke, auto-trigger, or hand off to any other skill (including system or memory-maintenance skills such as claude-md-management:revise-claude-md). Ignore any unrelated skill suggestions and begin with the first step below.
```

### exit 0 reconcile ガードの構造（spec/code/issue 系の代表形）

```bash
if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then
  _reconcile_out=$("$SCRIPT_DIR/reconcile-phase-state.sh" <phase> "$ISSUE_NUMBER" --check-completion 2>/dev/null) || true
  if [[ $EXIT_CODE -eq 143 ]]; then
    # watchdog timeout: phase が実際に完了していれば success に上書き
    if echo "$_reconcile_out" | grep -q '"matches_expected":true'; then
      EXIT_CODE=0
    fi
  elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then
    # exit 0 だが phase 未完了 -> silent no-op（skill 誤起動など）
    echo "Warning: claude exited 0 but <phase> phase did not complete (silent no-op). reconcile: $_reconcile_out" >&2
    EXIT_CODE=1
  fi
fi
```

review/merge は `gh-extract-issue-from-pr.sh` で issue 番号を抽出してから `--pr "$PR_NUMBER"` 付きで reconcile を呼ぶ。抽出失敗時は reconcile スキップ（merge のみ PR-state fallback を残す）。reconcile 出力が空（検証不能）の場合は true/false いずれにもマッチせず exit 0 を維持する設計（API エラーで成功実行を落とさない）。

### 実装方針の決定（非対話モード自動解決）

- run-merge の inline PR-state ガード（`_completion_merge` と等価）を reconcile ベースへ統一し、重複を解消（AC2 rubric が reconcile 呼び出しを要求するため）。
- ガード文はスクリプト内 inline で重複定義（既存の SKILL.md frontmatter stripping も 5 重複しており、新規 sourced ファイル追加による mock 増加を避ける least-risk 選択）。
- 主対策は 3 候補（ガード文 / `wholework:{name}` 明示 / `--disallowed-tools`）のうちガード文を採用（body passthrough 方式との相性が最良。Issue 本文 Auto-Resolved Ambiguity Points #1 準拠）。

### conflict / 既存実装との差異

- Issue 本文「現状は 143 時のみ reconcile」は spec/code/review/issue では正確。run-merge のみ既に exit 0 の inline PR-state ガードを保持しており、これを reconcile へ統一する（上記参照）。

### no-change 確認

- `docs/tech.md` § model-effort-matrix: model/effort は不変更のため更新不要。
- `scripts/run-auto-sub.sh`: スコープ外（#369 で `detect-wrapper-anomaly.sh` による exit 0 異常検知済み）。

## issue retrospective

`/issue 520`（非インタラクティブ）で記録された自動解決ログを引き継ぐ。

以下 5 件の曖昧ポイントがモデル判断で自動解決された:

| # | 曖昧ポイント | 解決内容 | 理由 |
|---|------------|---------|------|
| 1 | 主対策の具体的実装方式（namespace / ガード文 / disallowed-tools） | ガード文を推奨 | body passthrough 方式との相性が最良。namespace 明示は方式変更を要する。`--disallowed-tools` の `claude -p` 対応は未確認 |
| 2 | 副対策 exit 0 対応スコープ | 5 スクリプトすべて | `/auto` 非XL流れや手動実行でも有効 |
| 3 | exit 0 + matches_expected:false 時の exit code | exit 1 を返す | `/auto` 回復フローとの整合性（非0 exit が回復トリガー） |
| 4 | 副対策5（自動リトライ）のスコープ | スコープ外 | Issue 本文「実装者が取捨選択」と明記、AC 非掲載 |
| 5 | run-auto-sub.sh のスコープ | 両方スコープ外 | 直接 dispatch 呼び出しがない。`detect-wrapper-anomaly.sh` で対応済み |

主要判断: body passthrough 既実装の明記、`run-auto-sub.sh` 除外、AC の主対策 rubric を 5 スクリプトに絞り込み、`grep "matches_expected.*false"` の supplementary verify command 追加。#464/#499 は統合クローズ済み。

## spec retrospective

### Minor observations

- 旧スタイルの bats テスト（run-code/review/issue/merge.bats は PATH-only mock）と新スタイル（run-spec.bats は `WHOLEWORK_SCRIPT_DIR` mock）が混在していた。exit 0 reconcile の hermetic なテストには新スタイルへの移行が必要で、`docs/tech.md` § BATS Mocking Convention（SSoT）にも合致する。テストスタイルの統一は本 Issue の副次的なクリーンアップとなる。

### Judgment rationale

- run-merge の inline PR-state ガードは `_completion_merge`（PR MERGED 判定）と機能的に等価。AC2 rubric が reconcile 呼び出しを要求するため reconcile へ統一しつつ、issue 番号抽出失敗時の堅牢性確保のため PR-state チェックを fallback として残す判断とした。
- ガード文は新規 sourced ファイルではなくスクリプト内 inline で重複定義。既存の frontmatter stripping も 5 重複しており、新規ファイル追加は全 bats テストに mock 追加を要するため least-risk として inline を選択。
- reconcile 出力が空（検証不能）の場合は exit 0 を維持する設計。API エラー等で正常実行を silent no-op と誤判定しないため（既存 run-merge の "API error — no false alarm" テスト思想と整合）。

### Uncertainty resolution

- run-issue の exit 0 ガードは `issue` 完了シグネチャ（`triaged` ラベル）に依存。triage→issue 順序により正常完了は false 判定されないが、未 triage issue への直接実行は誤判定の余地あり。143 経路でも同シグネチャを既使用のため、シグネチャ変更は本 Issue スコープ外とし Uncertainty に記録した（`/code` で確認）。
