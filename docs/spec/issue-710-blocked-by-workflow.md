# Issue #710: blocked-by Workflow Introduction

## Overview

Issue 起票・リファイン時に blocked-by relationships を GitHub native の `addBlockedBy` mutation で正式設定するワークフローを導入する。

現状:
- `/issue N` (既存リファイン) Step 10 は `gh-check-blocking.sh` を呼び出し済み
- `/issue "title"` (新規起票) は `gh-check-blocking.sh` を呼ばず、body テキストのみ
- `/triage` は `Blocked by #N` を検出するが relationship を設定しない
- `modules/retro-proposals.md` はそのまま `gh issue create` のみ
- `scripts/gh-graphql.sh` に `add-blocked-by` は既存だが `remove-blocked-by` は未実装
- `scripts/set-blocked-by.sh` ラッパースクリプト未存在

`docs/reports/loop-engineering-wholework-2026-06-18.md` で L0 = GitHub state を SSoT と宣言しており、blocked-by relationships は L0 surface の一部。body テキストのみで済ますと SSoT が二重化する。

## Consumed Comments

| Author | Trust | Intent |
|--------|-------|--------|
| saito (MEMBER) | first-class | Issue Retrospective: 5 件の自動解決済み曖昧ポイント (AC1 `remove-blocked-by` 対象変更、AC6 `addBlockedBy` 追加、status table 修正、provide §1 スコープ修正、AC7 注釈削除) — Issue body に反映済み |

## Changed Files

- `scripts/gh-graphql.sh`: `remove-blocked-by` named query を追加 (line 56の`add-blocked-by`ケースの直後に挿入) — bash 3.2+ compatible
- `scripts/set-blocked-by.sh`: 新規作成 — Issue 番号で渡せる `add-blocked-by` wrapper; `get-issue-id` で node ID 解決 → `add-blocked-by` 呼び出し; エラーハンドリング込み — bash 3.2+ compatible
- `tests/gh-graphql.bats`: `remove-blocked-by` named query 解決のテストを追加
- `tests/set-blocked-by.bats`: 新規作成 — `set-blocked-by.sh` のテストファイル
- `skills/issue/SKILL.md`: New Issue Creation の Step 7 (Apply Labels) 末尾に `gh-check-blocking.sh $NUMBER` 呼び出しを追加; `set-blocked-by.sh` を allowed-tools に追加
- `skills/triage/SKILL.md`: `set-blocked-by.sh` を allowed-tools に追加; Step 9 "Dependency blocked-by check" を拡張 — OPEN の blocker かつ relationship 未設定の場合、L1 では advisory print、L2/L3 では `set-blocked-by.sh $NUMBER $BLOCKER_NUM` 呼び出し; Step 2b "Dependency Analysis" も同様に拡張
- `modules/retro-proposals.md`: Step 11 (Create Issues) で `gh issue create` 成功後に `set-blocked-by.sh` による body `Blocked by #N` パターンの relationship 設定を追加
- `skills/verify/SKILL.md`: `${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh:*` を allowed-tools に追加 (retro-proposals.md から呼ばれるため)
- `skills/auto/SKILL.md`: `${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh:*` を allowed-tools に追加; line 614 の TODO (#710) コメントを削除 (本 Issue で実装されるため)
- `docs/workflow.md`: "## Blocked-by relationships" セクションを追加 — GitHub native relationships が SSoT、body テキストは人間向け補足と明記、`addBlockedBy` 呼び出し例を記載
- `docs/ja/workflow.md`: 同セクションの日本語訳を追加 (translation-workflow.md sync 対象)
- `modules/l0-surfaces.md`: L0 Surface SSoT table に `Issue blocked-by relationships` 行を追加
- `docs/structure.md`: Scripts > GitHub API utilities に `scripts/set-blocked-by.sh` を追加; scripts ファイル数コメントを 57 → 58 に更新

## Implementation Steps

1. `scripts/gh-graphql.sh` と `scripts/set-blocked-by.sh` を整備 (→ AC1, AC2)
   - `gh-graphql.sh` の `get_named_query()` case 文に `remove-blocked-by` ケースを追加 (after `add-blocked-by):`): `mutation($issueId:ID!,$blockingId:ID!){removeBlockedBy(input:{issueId:$issueId,blockingIssueId:$blockingId}){issue{number}}}`
   - `scripts/set-blocked-by.sh` 新規作成: Usage: `set-blocked-by.sh <issue-number> <blocking-issue-number>`. 内部処理: (1) 引数バリデーション, (2) `$SCRIPT_DIR/gh-graphql.sh --cache --query get-issue-id -F num="$ISSUE_NUM"` で node ID 取得, (3) 同様に `BLOCKING_ID` 取得, (4) `$SCRIPT_DIR/gh-graphql.sh --query add-blocked-by -F issueId="$ISSUE_ID" -F blockingId="$BLOCKING_ID"`. `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` パターン使用 (gh-check-blocking.sh と同じ)
   - `tests/gh-graphql.bats`: `--query remove-blocked-by` の named query 解決テストを追加 (pattern: `removeBlockedBy` が query 文字列に含まれること)
   - `tests/set-blocked-by.bats`: 新規作成。MOCK_DIR pattern で `gh-graphql.sh` をモック。`--help`, 引数不足エラー, 正常 (exit 0), `gh-graphql.sh` が `add-blocked-by` で呼ばれること をテスト

2. `skills/issue/SKILL.md` 改修 (→ AC3)
   - allowed-tools に `${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh:*` を追加
   - New Issue Creation Step 7 (Apply Labels) 末尾に追記: `After applying labels, set blocked-by relationships from "Blocked by #N" patterns in the issue body: ${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh $NUMBER` (exit code 2 は open blockers 検出で正常)

3. `skills/triage/SKILL.md` と `modules/retro-proposals.md` 改修 (→ AC4, AC5)
   - `skills/triage/SKILL.md`:
     - allowed-tools に `${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh:*` を追加
     - Step 9 "Dependency blocked-by check" の OPEN ブロッカー検出ステップを拡張: OPEN かつ GitHub blocked-by relationship 未設定 (`get-blocked-by` GraphQL で確認) の場合、`AUTONOMY_TIER` に応じて分岐: L1 → "Recommend: set blocked-by relationship: `scripts/set-blocked-by.sh $NUMBER $BLOCKER_NUM`" を出力, L2/L3 → `${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh $NUMBER $BLOCKER_NUM` 呼び出し
     - Step 2b "Dependency Analysis": 末尾の "No auto-correction" ポリシーを tier-aware に変更: L1 は従来通り advisory のみ、L2/L3 は `set-blocked-by.sh` で backfill
   - `modules/retro-proposals.md`:
     - Step 11 Create Issues 内: `gh issue create` 成功後に "If the created issue body contains `Blocked by #N` patterns, call `${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh $NEW_ISSUE_NUMBER $N` for each N to set the GitHub native blocked-by relationship." を追記

4. `skills/verify/SKILL.md` と `skills/auto/SKILL.md` の allowed-tools 更新 (→ AC5 補完)
   - `skills/verify/SKILL.md` allowed-tools: `${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh:*` を追加
   - `skills/auto/SKILL.md` allowed-tools: `${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh:*` を追加
   - `skills/auto/SKILL.md` line 614 の `<!-- TODO (#710): ... -->` コメントを削除

5. ドキュメント更新 (→ AC6, AC7)
   - `docs/workflow.md`: 既存セクション末尾に "## Blocked-by relationships" セクションを追加: GitHub native `addBlockedBy` mutation が SSoT、body テキストは人間向け補足、自動設定経路の表と `set-blocked-by.sh` 呼び出し例
   - `docs/ja/workflow.md`: 同セクションの日本語訳を追加
   - `modules/l0-surfaces.md`: L0 Surface SSoT table に行を追加 — `Issue blocked-by relationships | add, remove | set-blocked-by.sh, gh-check-blocking.sh, gh-graphql.sh add/remove-blocked-by | mutable | yes`
   - `docs/structure.md`: Scripts > GitHub API utilities に `scripts/set-blocked-by.sh` 説明行を追加; directory layout の `(57 files)` → `(58 files)` に更新

## Verification

### Pre-merge

- <!-- verify: grep "remove-blocked-by" "scripts/gh-graphql.sh" --> `scripts/gh-graphql.sh` に `remove-blocked-by` named query が追加されている
- <!-- verify: file_exists "scripts/set-blocked-by.sh" --> wrapper script `scripts/set-blocked-by.sh` が新規作成されている
- <!-- verify: section_contains "skills/issue/SKILL.md" "## New Issue Creation" "gh-check-blocking" --> `/issue` SKILL.md の新規起票フロー (New Issue Creation) に blocked-by 自動設定ステップが追記されている
- <!-- verify: file_contains "skills/triage/SKILL.md" "set-blocked-by" --> `/triage` SKILL.md に body-only 依存の backfill ステップが追記されている
- <!-- verify: file_contains "modules/retro-proposals.md" "set-blocked-by" --> retro-proposals が起票時に blocked-by を設定する経路を持つ
- <!-- verify: section_contains "docs/workflow.md" "Blocked-by relationships" "addBlockedBy" --> `docs/workflow.md` に blocked-by ハンドリングのセクションが追加されている
- <!-- verify: grep "blocked-by" "modules/l0-surfaces.md" --> `modules/l0-surfaces.md` に Issue blocked-by relationships が L0 surface として登録されている

### Post-merge

- body に `Blocked by #N` を含む試験 Issue を `/issue` で起票し、GraphQL `blockedByIssues` クエリで relationship が設定されていることを確認する <!-- verify-type: manual -->
- body-only `Blocked by #N` を持つ既存 Issue に対して `/triage N` を走らせ、relationship が backfill されることを確認する <!-- verify-type: manual -->

## Notes

- **autonomy tier gating (triage)**: `.wholework.yml` の `autonomy: L1` (デフォルト) では triage は advisory print のみ。L2/L3 で set-blocked-by.sh を自動呼び出し。これは `modules/autonomy-tier.md` の Tier × L0 Write Matrix (L1: advisory print only) に従う
- **Step 7 heading 変更なし**: `skills/issue/SKILL.md` Step 7 のヘッディング "Apply Labels" はそのままで末尾に blocked-by 呼び出しを追記する。step 番号のリナンバーは不要
- **set-blocked-by.sh がない bats モック**: `gh-check-blocking.bats` は `WHOLEWORK_SCRIPT_DIR` を使わないため新スクリプトのモック追加不要。新しく作成する `tests/set-blocked-by.bats` は MOCK_DIR パターンを使用
- **triage allowed-tools に gh-graphql.sh 既存**: triage SKILL.md の allowed-tools には `gh-graphql.sh` が含まれており、`get-blocked-by` query を呼ぶ Step 9 拡張はそのまま動作する
- **verify/auto allowed-tools**: retro-proposals.md が `set-blocked-by.sh` を呼ぶため、呼び出し元 skill の allowed-tools に追加が必要

## spec retrospective

### Minor observations
- `auto/SKILL.md` line 614 に本 Issue (#710) を参照する TODO コメントが存在。Spec 調査中に発見できた。Changed Files に含めて実装時に削除する方針とした
- `tests/set-blocked-by.bats` の MOCK_DIR パターンは `tests/gh-check-blocking.bats` と同じパターンを踏襲。コードベース既存の一貫したテストパターンを確認した

### Judgment rationale
- triage Step 9 で relationship 設定前に `get-blocked-by` で現状を確認する設計: 冪等性を保つため。既に設定済みなら `addBlockedBy` を呼ばない
- retro-proposals.md の blocked-by 設定方法: BLOCKED_BY_CANDIDATES パラメータの導入ではなく `gh-check-blocking.sh` 方式 (body テキスト検出) を採用。理由: improvement proposal の body に "Blocked by #N" を LLM が書いた場合に自動設定される最小侵入の方法。callers の引数変更が不要で backward compatible

### Uncertainty resolution
- Nothing to note (SPEC_DEPTH=light のため Step 8 は skip)

## Code Retrospective

### Deviations from Design

- `retro-proposals.md` の blocked-by 設定方法: Spec では `gh-check-blocking.sh` 方式を示唆していたが、実装では `set-blocked-by.sh` を直接呼び出す方式に変更した。`gh-check-blocking.sh` は Issue body を自分でフェッチするが、retro-proposals.md のコンテキストでは既に body が手元にあるため直接 `set-blocked-by.sh $NEW_ISSUE_NUMBER $N` を呼ぶほうが整合性が高い。AC5 の verify コマンド `file_contains "modules/retro-proposals.md" "set-blocked-by"` は両者で PASS するため影響なし。

### Design Gaps/Ambiguities

- `skills/issue/SKILL.md` の Step 7 heading "Apply Labels" の直後に blocked-by 呼び出しを追記したが、Spec では「Apply Labels の末尾に追記する」と指定されていた。実際には Labels 呼び出しの直後の新しいパラグラフとして追記した。意味は同一。
- `modules/retro-proposals.md` は `CLAUDE_PLUGIN_ROOT` を使う形式で記述したが、このモジュールの他の箇所も同じパターンを使用しているため一貫性がある。

### Rework

- N/A (1回の実装で全 AC PASS)

## review retrospective

### Spec vs. 実装の乖離パターン

- `docs/ja/structure.md` の同期漏れが SHOULD 指摘として検出された。`docs/structure.md` のスクリプト件数・エントリ更新は PR に含まれていたが、翻訳版の `docs/ja/structure.md` は更新されていなかった。`translation-workflow.md` に従うべきだが実装時に見落とされた。tests/ 件数 (78→79) も `docs/structure.md` と `docs/ja/structure.md` の双方で未更新だった。
- `set-blocked-by.sh` の exit code コメントが実装動作と不一致 (SHOULD): `(or already set)` はべき等性を示唆するが未実装。コメントと実装の一致は実装時に意識すべき点。

### 繰り返しの問題

- 翻訳版ドキュメント (`docs/ja/`) の同期漏れは過去の PR でも発生している。`docs/translation-workflow.md` を参照する習慣を code フェーズに組み込むべき。

### 受け入れ基準の検証難度

- 全 7 AC が `grep`/`file_exists`/`file_contains`/`section_contains` コマンドで機械的に PASS 判定できた。UNCERTAIN 件数: 0。verify コマンドは適切に設計されており、auto-verification の精度が高い。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #715 をスカッシュマージ (conflicts なし、CI success、review approved)
- BASE_BRANCH=main のため `closes #710` により Issue は自動クローズ済み
- review フェーズの SHOULD/CONSIDER 修正が全てマージコミットに含まれた状態でマージ完了

### Deferred Items
- Post-merge manual verification: `/issue` 起票テスト (body に `Blocked by #N` を含む Issue を起票し GraphQL で確認)
- Post-merge manual verification: `/triage N` backfill テスト (body-only `Blocked by #N` の既存 Issue に対して実行)
- `remove-blocked-by` mutation の呼び出し側実装は別 Issue で対応予定

### Notes for Next Phase
- 全 7 pre-merge AC が PASS 済み (`grep`/`file_exists`/`file_contains`/`section_contains` で機械的に確認可能)
- `set-blocked-by.sh` はべき等でないが、triage Step 9 は事前 `get-blocked-by` チェック付きで重複設定を回避
- verify フェーズは post-merge manual テストの 2 項目を除き自動検証可能

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 設計は 7 件すべて機械的検証コマンド (`grep`/`file_exists`/`file_contains`/`section_contains`) で構成され、verify 段階で UNCERTAIN がゼロ。Auto-Resolved Ambiguity Points で常時 PASS する `grep "add-blocked-by"` を `remove-blocked-by` に変更した判断が verify 精度に直結した。

#### code
- Spec とのわずかな逸脱 (retro-proposals.md で `set-blocked-by.sh` 直接呼び出し)は AC verify に影響なし。実装の整合性は code retrospective に既に明記されている。

#### review
- 翻訳版 `docs/ja/structure.md` の同期漏れが review で検出 (SHOULD)。review retrospective に「過去 PR でも繰り返し発生」と記録されており、recurring pattern として可視化されている。
- `set-blocked-by.sh` の `(or already set)` コメントと未実装べき等性の不一致も SHOULD で検出。merge コミットに修正が含まれた。

#### merge
- conflicts なし、CI green、squash-merge 通常完了。

#### verify
- pre-merge 7 件すべて PASS。post-merge AC8/AC9 は `verify-type: manual` で test issue 起票を伴うため SKIPPED とし、Verification Guide を出力。

### Improvement Proposals

- **docs/ja/ 翻訳版 sync の自動チェック**: `docs/structure.md` と `docs/ja/structure.md` の同期漏れが過去 PR でも繰り返し発生していると review retrospective に記録されている。`/code` または `/review` フェーズで `docs/structure.md` 変更検出時に `docs/ja/structure.md` の同期状態を自動確認するチェック (例: `scripts/check-translation-sync.sh` または `modules/translation-workflow.md` の verify command 化) を追加する価値がある。複数 skill (`/code`, `/review`) と複数 PR にまたがる再発性パターンのため Tier 1 候補。

