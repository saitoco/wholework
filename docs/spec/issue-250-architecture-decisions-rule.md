# Issue #250: spec: 振る舞いを変える設定追加時に docs/tech.md を Changed Files に含めるルールを追加

## Issue Retrospective

### Triage Results

| Field | Value |
|-------|-------|
| Type | Feature |
| Priority | — (未検出) |
| Size | XS |
| Value | 2 (Impact=低、Alignment=中: tech.md SSoT ルールパターンに合致) |

### Ambiguity Auto-Resolution

Size=XS の曖昧性点 3 件を auto-resolve:

1. **「振る舞いを変える設定」の適用範囲** → `.wholework.yml` 新規キー または `claude -p` への新規 CLI フラグ。理由: #214（両方に該当）から派生した指摘で、他の設定変更形態（workflow 等）には既存 SHOULD ルールが別途存在するため。
2. **SHOULD 制約テーブル内の配置** → Step 10 「Constraint checklist (MUST/SHOULD)」配下の既存テーブルに 1 行追加。理由: 同形式の既存パターンに揃える。
3. **verify command の trivial PASS 問題** → 既存 AC の `grep "Architecture Decisions"` と `grep "tech.md"` は skills/spec/SKILL.md 内で変更前から既にマッチ（line 97 ほか多数）しており、実装されなくても PASS する欠陥があった。`"Architecture Decisions impact"` というユニーク句を rule 名に採用し、`section_contains` で Step 10 スコープに限定する verify に差し替え。

### Acceptance Criteria Changes

- 既存 2 件の壊れた `grep` verify を差し替え
  - `grep "Architecture Decisions"` → `grep "Architecture Decisions impact"`（ユニーク句に置換）
  - `grep "tech.md"` → 削除（過剰マッチ）。代わりに `section_contains "... Step 10 ..." "Architecture Decisions impact"` で配置検証を追加
- 適用範囲を明記する AC を新規追加（`grep ".wholework.yml.*tech.md\|permission-mode\|CLI flag"`）
- Post-merge opportunistic 条件の表現を更新（`.wholework.yml` キー追加または CLI フラグ追加を明示）

### Scope Assessment

Size=XS、単一ファイル（`skills/spec/SKILL.md`）への SHOULD 行 1 行追加のみ。サブ Issue 分割は不要。

### Title Drift

Title "spec: 振る舞いを変える設定追加時に docs/tech.md を Changed Files に含めるルールを追加" は更新後の body と整合しており drift なし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective で verify command の trivial PASS 問題が事前に検出・修正された。ユニーク句 `Architecture Decisions impact` の採用と `section_contains` による配置スコープ限定は効果的だった。

#### design
- N/A（Spec Retrospective セクションなし、Size=XS のため設計フェーズは省略）

#### code
- パッチルート（commit `45cc4cd`）で直接 main に実装。単一行追加のシンプルな変更であり、レビューサイクルなし。

#### review
- パッチルートのため PR/レビューなし。Size=XS の変更としては妥当。

#### merge
- パッチルートで main に直コミット。コンフリクトなし。

#### verify
- 3 件のプレマージ条件がすべて PASS。Post-merge opportunistic 条件（`verify-type: opportunistic`）が未チェックのため `phase/verify` を割り当て。
- PR_NUMBER が空のため Step 2 での PR ベースの BASE_BRANCH 検出はスキップされ main をデフォルト使用。

### Improvement Proposals
- N/A
