# Issue #827: issue: behavioral changes 時の verify command broader scope 推奨ロジックを追加

## Overview

`/issue` skill が verify command を生成する際、behavioral changes (既存スクリプト/関数の修正で直接指定外のテストにも影響するケース) を含む Issue では、局所的なファイル指定ではなくフルスイート (`bats tests/`、`pytest` 等) を推奨するロジックが存在しない。

この問題の発生例 (Issue #819):
- AC3 の verify command が `bats tests/run-code.bats tests/append-consumed-comments-section.bats` と局所指定されていたが、既存 `tests/run-verify.bats` の "spec absent" テストが旧挙動前提で FAIL することを verify-time にカバーできなかった (CI で初めて検出)。

本 Issue は、`modules/verify-patterns.md` に新セクション §24 を追加し、behavioral changes を含む Issue に対して verify command の scope 判定ガイドラインを提供する。

## Changed Files

- `modules/verify-patterns.md`: add §24 "Behavioral Changes — Prefer Full Test Suite for Verify Commands" (bash 3.2+ 不要 — markdown ファイルのみ)
- `tests/verify-heuristics.bats`: add test for §24 section existence — bash 3.2+ compatible

## Implementation Steps

1. `modules/verify-patterns.md` の末尾 (`## Output` セクション直前) に §24 を追加する (→ AC1)

   §24 の内容:
   - **タイトル**: `### 24. Behavioral Changes — Prefer Full Test Suite for Verify Commands`
   - **behavioral changes の定義**: 既存スクリプト/関数を修正し、直接指定外のテストからも参照されるケース。判定基準: 修正ファイルを参照する既存テストが局所指定以外にも存在するか。
   - **検出ヒューリスティック**: (a) 実装が既存ファイルを修正するか (新規ファイル追加のみなら非該当) ／ (b) 修正ファイルを参照する既存テストが局所指定外に存在するか
   - **推奨スコープ**: broader scope が原則 (`bats tests/` for bats、`pytest` for Python、`pnpm test` for Node.js)
   - **局所スコープとの trade-off テーブル**: 局所 (高速・新規テストのみ) vs. 広域 (低速・既存テストの regression 検知可能)
   - **決定手順** (3 ステップ)
   - **実例**: Issue #819 の `run-code.sh` 修正が `run-verify.bats` の "spec absent" テストに影響したケース

2. `tests/verify-heuristics.bats` に §24 存在確認テストを追加する (SHOULD)

   ```bash
   @test "verify-heuristics: behavioral changes section exists in verify-patterns.md" {
       grep -q "Behavioral Changes" "$VERIFY_PATTERNS"
   }
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md または modules/verify-patterns.md のいずれかに、behavioral changes を含む実装の verify command を局所ファイルではなく bats tests/ や pytest 等のフルスイートにする推奨ロジック・heuristic が記述されている" --> behavioral changes 時の broader scope 推奨ロジックが追加されている

### Post-merge

- 次回 `/issue` 実行時、behavioral changes を含む Issue の verify command が broader scope で生成されることを観察 <!-- verify-type: opportunistic -->

## Notes

### Auto-resolved Ambiguity Points

1. **behavioral changes の定義** (HIGH): 既存スクリプト/関数を修正し、直接指定外のテストからも参照されるケースを "behavioral changes" と定義する。#819 事例 (run-code.sh 修正が run-verify.bats の "spec absent" テストに影響) が典型例。判定基準: 修正ファイルを参照する既存テストが局所指定以外にも存在するか。
   - 採用: 上記定義 / 代替候補: より保守的な "すべての非 XS 変更にフルスイートを適用" (副作用が大きいため不採用)

2. **実装対象ファイル** (MEDIUM): `modules/verify-patterns.md` に新セクションを追加する方式。根拠: verify command ガイダンスはすべて同モジュールに集約 (§1-§23)、SKILL.md は "Read and follow" で委譲する設計。
   - 採用: `modules/verify-patterns.md` 新セクション / 代替候補: `skills/issue/SKILL.md` 直接追記

3. **post-merge verify-type** (LOW): `verify-type: opportunistic` を採用。条件テキスト「次回 `/issue` 実行時」は `/issue` スキル実行時の観察を指しており、`opportunistic` が正確。
   - 採用: `verify-type: opportunistic` / 代替候補: 旧称 `observation event=auto-run`

### 関連 Issue

- #826: `/code` phase の behavioral changes フルスイート実行ガイドライン (相補関係)

## Consumed Comments

- `saito (MEMBER / first-class)` — Issue Retrospective (Auto-Resolve Log): behavioral changes の定義・実装対象ファイル・post-merge verify-type の 3 点を自動解決した記録 — https://github.com/saitoco/wholework/issues/827#issuecomment-4827301727
