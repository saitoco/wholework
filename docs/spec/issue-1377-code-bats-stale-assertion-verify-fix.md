# Issue #1377: tests/code.bats: stale assertion in Step 10 branch-scoped CI AC exclusion test

## Overview

Issue Background の通り、`tests/code.bats` line 164 のアサーション文字列 (`"For patch or operate route, Step 10 runs before"`) と `skills/code/SKILL.md` の実装テキストの drift は、本 Issue 起票前に #1375 (Issue #1095, `2026-08-16T02:40:50Z` merge) で既に解消済みだった。Issue 本文の AC verify command も `/issue` Step 7 調査 (2026-08-17) で `command "bats --filter-status failed tests/code.bats"` (前提条件エラーで常時停止) から `bats --filter '<test name>' tests/code.bats` 形式に修正済みであることを Issue 本文自身が記録している。本 Issue には `/spec` フェーズが実行されておらず、Issue 本文自体を要件源として使用する。

## Changed Files

なし — repository file への変更は不要。対象アサーションは #1375 で既に修正済みであることを確認するのみ。

## Implementation Steps

1. `bats --filter 'Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route' tests/code.bats` を実行し、Issue 本文の主張通り現在の `main` で PASS することを確認する

## Verification

### Pre-merge

- <!-- verify: command "bats --filter 'Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route' tests/code.bats" --> 対象テストが PASS する

### Post-merge

- N/A (Issue 本文記載の通り)

## Notes

- 本 Issue には `/spec` フェーズが実行された形跡がなく (`docs/spec/issue-1377-*.md` が存在しない状態で `phase/ready` label が付与されていた)、Size は XS のため `/code` Step 3 の Spec precondition check は該当なくスキップされる。Step 12 (Code Retrospective) および Phase Handoff の書き込み先として Spec が必要なため、このセッションで本ファイルを新規作成して補った。
- Step 0 の operate route 判定は既存 Spec の存在を前提とする診断のため、Spec 不在の時点では判定対象外だった。`--patch` フラグの明示により patch route が確定している。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- N/A — 実装対象ファイルなし。Issue 本文が既に正しい verify command を含んでいたため、コード変更は不要だった。

### Design Gaps/Ambiguities

- Issue に `phase/ready` label が付与されているにもかかわらず対応する Spec ファイルが存在しなかった。XS Size のため `/code` Step 3 の Spec precondition check は該当なくスキップされたが、Step 12 (Code Retrospective) や Phase Handoff の書き込み先には Spec が必要なため、このセッションで Spec を新規作成して補った。

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 対象テストが既に PASS することを確認した上で、リポジトリファイルへの変更は一切行わなかった (drift は #1375 で解消済み、AC の verify command も起票時点で既に修正済み)。
- Spec 不在のまま `phase/ready` だった状態を補うため、retrospective 専用の Spec ファイルをこのフェーズで新規作成した。

### Deferred Items
- None

### Notes for Next Phase
- Pre-merge AC 1件は `/code` 内で PASS 判定済みで Issue 本文のチェックボックスも更新予定。Post-merge AC は Issue 本文記載の通り N/A。
- `/verify` は同じ verify command を再実行するだけで良く、追加の実装確認は不要。

## Issue Retrospective

### 調査結果と判断根拠

- 起票時点で報告された `tests/code.bats` line 164 と `skills/code/SKILL.md` line 459 の drift は、本 Issue 起票 (`2026-08-16T03:20:13Z`) の約 40 分前に merge された無関係な PR #1375 (Issue #1095, `2026-08-16T02:40:50Z` merge) によって既に解消されていた。現状の `main` で `bats --filter 'Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route' tests/code.bats` を実行すると `ok 1` (PASS) を確認した。
- ただし AC 自身の verify command `command "bats --filter-status failed tests/code.bats"` は `tests/.bats/run-logs/` ディレクトリの不在により常時前提条件エラーで停止する欠陥があり、これは Issue コメント (@saito, MEMBER, first-class) で指摘済みだった。コメントの修復案 (`bats --filter '<test name>' tests/code.bats` への変更) をそのまま採用した。
- Background に上記調査結果を追記し、Purpose を「verify command の修正が残作業の中心であり、テキスト側の追加変更は不要な可能性が高い」旨に更新した。AC 本文・verify command はコメントの修復案に沿って更新済み。

### Auto-Resolve Log (non-interactive)

- **verify command を `bats --filter-status failed` から `bats --filter '<test name>'` へ変更** — reason: Issue コメントで既に修復案が提示されており (first-class, MEMBER)、現状の `main` に対して空撃ちして動作を確認済み (exit 0)。他候補 (`bats tests/code.bats` 全体実行) は対象テストへの絞り込みが弱く、コメントの推奨とも一致しないため不採用。
- **AC/Purpose の記述をそのまま残し追記のみで対応** — reason: 既存の英語記述を全面的に日本語へ翻訳するスコープ拡大は今回のタスク (verify command 修正) の範囲外と判断。追記部分のみ本リポジトリの Issue body 言語規約 (日本語) に従った。

### Consumed Comments

- saito / MEMBER / first-class / `bats --filter-status failed` は `tests/.bats/run-logs/` 不在により常時前提条件エラーになると指摘し、`bats --filter '<test name>'` への変更を提案 / https://github.com/saitoco/wholework/issues/1377#issuecomment-5306048277
