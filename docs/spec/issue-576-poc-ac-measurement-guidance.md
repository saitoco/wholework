# Issue #576: AC Design Guidance for PoC/Measurement Issues

## Overview

`skills/issue/spec-test-guidelines.md` の AC 生成ガイダンスに、spike / PoC / 計測系 Issue における「実測か試算か」の区別を明示するセクションを追加する。

Issue #565 の verify retrospective で検出された問題：Spec は Spike 2 を「代表 PR に対し実行し、検出数・false-positive 率を突き合わせる」と定義したが、code フェーズで「アーキテクチャ分析 + 試算ベースの PoC」へスコープ縮小された。AC の verify command がキーワード grep のみだったため、この縮小を機械検証で検出できなかった。

対応：実測要求の場合は計測成果物（ログ・結果ファイル等）の `file_exists` 検証を AC に含める規約を追加し、暗黙的なスコープ縮小を検出可能にする。

## Changed Files

- `skills/issue/spec-test-guidelines.md`: add `## AC Design Guidelines for PoC and Measurement Issues` section (実測/試算区別ガイダンス)

## Implementation Steps

1. `skills/issue/spec-test-guidelines.md` の末尾（`## Specifying individual changed skills...` セクションの後）に `## AC Design Guidelines for PoC and Measurement Issues` セクションを追加する (→ AC1, AC2)
   - **実測 (actual measurement)** と **試算 (estimation)** の定義と区別を明文化
   - 実測要求時: 計測成果物の `file_exists` verify command を AC に含めることを必須とするパターンを記載
   - 試算許容時: AC 文面に "estimation allowed" を明記し、code フェーズへスコープ判断を明示委任するパターンを記載
   - キーワード grep のみに依存しないよう注記

## Verification

### Pre-merge

- <!-- verify: grep "実測|試算" "skills/issue/spec-test-guidelines.md" --> AC 生成ガイダンスに実測/試算の区別が明文化されている
- <!-- verify: grep "file_exists" "skills/issue/spec-test-guidelines.md" --> 実測要求時の計測成果物検証（file_exists 等）パターンが記載されている

### Post-merge

- 次回の spike 型 Issue 作成時、生成 AC に実測/試算の区別が反映されることを確認

## Notes

- `grep "実測|試算"` パターンは実装によって導入される（現時点でファイルに存在しない）
- `grep "file_exists"` は現行ファイル 28 行目に既存（`file_exists` と `file_exists_any` が含まれる）。新セクションでも計測成果物の検証パターンとして `file_exists` を使用するため、実装後も確実にマッチする
- 対象ファイル `skills/issue/spec-test-guidelines.md` は `docs/*.md` ではないため翻訳同期（docs/ja/）対象外
- このガイダンスは `/issue` スキルが `/issue` 実行時にのみ読み込む domain file（`file_exists_any: [scripts/validate-skill-syntax.py]` ゲート）であるため、distributable-first 原則を満たす（他の Wholework ユーザーが validate-skill-syntax.py を持つ skill-dev リポジトリで自動適用される）

## Code Retrospective

### Deviations from Design

- None. Implementation followed the Spec exactly — new section added at the end of `skills/issue/spec-test-guidelines.md` with 実測/試算 terminology and `file_exists` pattern examples as specified.

### Design Gaps/Ambiguities

- The Spec noted that "estimation allowed" should appear in AC text, but did not specify whether English or Japanese was preferred. Since the domain file uses English for section headings and pattern descriptions (consistent with the existing file style), and the Japanese terms 実測/試算 are preserved as grep targets, this was implemented with English-primary prose and Japanese key terms inline.

### Rework

- None.

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec | patch | SUCCESS | — |
| code | patch | SUCCESS (after silent-no-op detection) | detect-wrapper-anomaly が初回 code 実行を silent-no-op として検出。run-auto-sub.sh の Tier 2 リトライで 2 回目に成功（commit c6a6170） |
| verify | - | SUCCESS | pre-merge 2/2 PASS |

### Orchestration Anomalies
- code phase の 1 回目実行で wrapper exit 0 だがコミットなし（silent no-op、#365 pattern）。`detect-wrapper-anomaly.sh` が検出し、改善提案として "Re-run run-code.sh 576" を出力。`run-auto-sub.sh` がリトライ実行、2 回目で正常コミット（c6a6170）。**本セッション 2 件目の silent-no-op 自動リカバリ**（#580 と連続）

### Improvement Proposals
- silent-no-op の発生頻度が #580 → #576 と連続している点は要観察。本セッション内では Tier 2 が正しく機能しているが、根本原因（claude の応答内容と実 commit の乖離）の追跡は #365 で継続中。発生頻度が高い場合は予防策（spec phase 末尾のサニティチェックなど）を検討する Issue 起票を検討

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- retro/verify 起票時点で AC が grep × 2 で揃い、triage 補正不要

#### spec
- 英日表記の選択（実測/試算は日本語のまま grep 対象、説明文は英語）の判断が Code Retrospective に明示記録された

#### code
- 1 回目 silent no-op → Tier 2 リトライで 2 回目成功。#580 と連続で同パターンが発生したが、いずれも自動リカバリで完結

#### verify
- pre-merge 2/2 PASS。post-merge opportunistic は spike 型 Issue 作成時の `/issue` 実行が観測機会で SKIP

### Improvement Proposals
- 本セッションで silent-no-op が #580/#576 で連続 2 回発生。Tier 2 自動リカバリで完結したが、頻度が上がる場合は予防策（事前ハートビート、code phase 開始確認 echo 等）の検討が必要。観察期間として次の数 Issue で頻度を測定し、3 件目以降が発生したら起票を検討

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added the new section at the end of the file (after `## Specifying individual changed skills...`) as specified in the Spec — no structural changes to existing sections.
- Used English-primary prose with inline Japanese terms (実測/試算) to match the existing file style while satisfying the grep-based AC verify commands.
- Included both a positive pattern (実測 required → `file_exists` AC) and a negative pattern (anti-pattern: keyword grep only) for clarity.

### Deferred Items
- None — this is a self-contained documentation-only change with no follow-up needed.

### Notes for Next Phase
- The post-merge AC is opportunistic (spike 型 Issue 作成時に観察); no automated verification possible until a new spike-type Issue is created.
- Both pre-merge verify commands PASS as confirmed during Step 10.
