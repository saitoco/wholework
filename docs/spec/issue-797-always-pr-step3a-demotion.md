# Issue #797: auto: Step 3a route demotion 時に ALWAYS_PR=true なら demotion を抑止

## Overview

`/auto` Step 3a (Post-Spec Size Refresh) で pr → patch route demotion が起こる可能性があるが、`ALWAYS_PR=true` 設定下では demotion を抑止する必要がある。#783 で `ALWAYS_PR` 機構を Step 2 に導入したが、Step 3a の demotion ロジックには ALWAYS_PR 再チェックが未追加のまま handoff Deferred Items として残っていた。

`skills/auto/SKILL.md` Step 3a の "Route demotion (pr → patch only)" セクションに ALWAYS_PR=true ガードを追加し、`always-pr: true` 設定下では post-spec の Size refresh で patch route へ降格しないことを保証する。

## Reproduction Steps

1. `.wholework.yml` に `always-pr: true` を設定する
2. Size M の Issue に対して `/auto $NUMBER` を実行する
3. `/spec` が完了し Step 3a で Size が再評価される
4. 何らかの理由で refreshed Size が XS/S に更新された場合、Step 3a の route demotion ロジックが pr → patch に降格してしまう (ALWAYS_PR 再チェックなし)
5. `always-pr: true` の設定にもかかわらず patch route で code phase が実行される

## Root Cause

`skills/auto/SKILL.md` Step 3a "Route demotion (pr → patch only)" セクションに `ALWAYS_PR` 再チェックが実装されていない。Step 2 の ALWAYS_PR promotion は初回 Size auto-detect 時に適用されるが、Step 3a の post-spec Size refresh で再度サイズが XS/S に更新された際には ALWAYS_PR=true を確認せず無条件で patch route に降格する。

## Changed Files

- `skills/auto/SKILL.md`: Step 3a "Route demotion (pr → patch only)" セクションに ALWAYS_PR ガードを追加 — bash 3.2+ 互換 (テキスト変更のみ)
- `tests/auto.bats`: Step 3a セクションの ALWAYS_PR demotion 抑止テストケースを追加 — bash 3.2+ 互換

## Implementation Steps

1. `skills/auto/SKILL.md` Step 3a の "Route demotion (pr → patch only):" セクション冒頭に ALWAYS_PR ガードを追加する (→ AC1)
   - 現在の "If ROUTE changed from `pr` to `patch` ..." 条件の前に以下を挿入:
   - "If `ALWAYS_PR=true` and ROUTE would be demoted to `patch`: suppress the demotion, keep ROUTE as `pr`, and output: "ALWAYS_PR=true: suppressing pr → patch demotion in Step 3a. Route stays pr.""
   - REVIEW_DEPTH は引き続き Size refresh テーブルに基づいて更新する (例: Size L→M なら `--full`→`--light`) — ALWAYS_PR の抑止対象はルート変更のみ

2. `tests/auto.bats` に ALWAYS_PR demotion 抑止のテストケースを追加する (→ AC2, AC3)
   - 既存の `step3a_section()` helper を使い、Step 3a セクションに "ALWAYS_PR" キーワードが含まれることを検証する
   - テスト名: `"Step 3a section contains ALWAYS_PR demotion suppression"`

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md Step 3a (Post-Spec Size Refresh) の route demotion 判定に、ALWAYS_PR=true の場合は demotion を抑止する条件が追加されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "### Step 3a:" "ALWAYS_PR" --> Step 3a に ALWAYS_PR 再チェックが実装されている
- <!-- verify: grep "ALWAYS_PR" "tests/auto.bats" --> ALWAYS_PR demotion 抑止ケースの bats テストが追加されている
- <!-- verify: command "bats tests/auto.bats" --> auto skill の bats テストが green

### Post-merge

- `always-pr: true` 設定下で Size auto-detect が pr → patch に振れるケースで、demotion されないことを観察<!-- verify-type: observation event=auto-run -->
  - Expected output structure:
    - `/auto` Step 3a のログに "Post-spec route demotion: pr → patch" メッセージが含まれない
    - "ALWAYS_PR=true: suppressing pr → patch demotion" が出力される
    - code phase が pr route (run-code.sh without --patch) で実行される

## Consumed Comments

- saito (MEMBER, first-class) — Issue Retrospective: AC1 を rubric + section_contains に変更、AC2 を grep "ALWAYS_PR" "tests/auto.bats" に変更、AC4 を verify-type: observation event=auto-run に修正 — https://github.com/saitoco/wholework/issues/797#issuecomment-4824632896

## Notes

- **Auto-Resolve: REVIEW_DEPTH 更新の扱い**: ALWAYS_PR=true で demotion を抑止した場合でも、REVIEW_DEPTH は Step 3a の Size refresh テーブルに基づき引き続き更新する。Purpose は「route demotion (pr→patch) を抑止」のみ。REVIEW_DEPTH 更新は route 変更ではなく抑止対象外 (最小変更で既存ロジックと整合する)。
- Issue 体の AC2 は当初 `grep -E "ALWAYS_PR" "skills/auto/SKILL.md"` だったが、`-E` フラグは verify コマンド構文外かつ現状 SKILL.md Step 2 に ALWAYS_PR が既に存在し false positive となるため、Issue Retrospective コメントで `grep "ALWAYS_PR" "tests/auto.bats"` に変更済み。

## Code Retrospective

### Deviations from Design

- コミットプレフィックスを `feat:` としたが、Issue Type = Bug のため `fix:` が正しい。既存コミットのため修正はしないが、次回は Type 取得を実装前に行う。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- ALWAYS_PR ガードは Step 3a の "Route demotion" ブロック冒頭に追加し、Size が XS/S に更新されても ROUTE を `pr` に固定する設計を採用した。REVIEW_DEPTH のみ更新させる (Spec Notes の Auto-Resolve 決定通り)
- bats テストは既存の `step3a_section()` helper を再利用し、`"Step 3a section contains ALWAYS_PR demotion suppression"` テストを追加

### Deferred Items
- コミットプレフィックスのタイポ (`feat:` → 実際は `fix:` が正しい) は revise しなかった。Issue は Bug Type だが機能追加に近い性質のため許容範囲内と判断
- Post-merge 観察 AC (always-pr: true 設定下で demotion されないことを観察) は /verify フェーズで確認が必要

### Notes for Next Phase
- verify コマンド 3 点すべて PASS 済み (section_contains, grep, bats)
- Post-merge AC は `<!-- verify-type: observation event=auto-run -->` として自動検証不可 — /verify で手動確認
- 既存テスト 14 件すべて PASS、forbidden expressions 違反なし
