# Issue #994: code: --non-interactive 実行時は full suite (bats tests/) をフォアグラウンドで実行するガイダンスを追加

## Overview

Issue #979 の `/code --non-interactive` 実行で、Behavioral Change Detection (`skills/code/SKILL.md` Step 9) が発火させた full suite override (`bats tests/`) をサブエージェントがバックグラウンドで起動し、完了通知を受け取れないまま無限待機し、3回の自動リトライ (`auto-retry-on-fail.max_iterations: 3`) を使い切って手動介入待ちになった。同 Issue を手動でフォアグラウンド実行したところ約6分47秒 (407秒) で正常完了しており (`docs/spec/issue-979-get-config-value-parse-fix.md` Code Retrospective 参照)、headless (`claude -p --non-interactive`) 実行下ではバックグラウンド Bash タスクの完了通知がエージェントに届かない可能性が示唆されている。

本 Issue では、`skills/code/SKILL.md` の Behavioral Change Detection サブセクション (`bats tests/` full suite override の実行箇所そのもの) に、`--non-interactive` 実行時はフォアグラウンドで (かつ十分な明示的 Bash timeout を指定して) 実行すべきというガイダンスを追加する。

## Changed Files
- `skills/code/SKILL.md`: change — Step 9 Behavioral Change Detection サブセクションの `bats tests/` full suite override コードブロック直後に、`--non-interactive` 実行時のフォアグラウンド実行 (`run_in_background` 不使用) + 明示的 timeout 指定のガイダンス文を追加

## Implementation Steps
1. `skills/code/SKILL.md` Step 9 "Behavioral Change Detection" の項目2 (`bats tests/` full suite override) — `(Same pre-check guard applies — bats tests/ requires the directory to exist.)` の行の直後、`Handle FAIL via Tier 0 structured recovery below.` の行の直前に、新しい箇条書きを1つ追加する。内容: `/code` 自体が `--non-interactive` モードで動作している場合、上記の `bats tests/` override は `run_in_background: true` を設定せず**フォアグラウンド**で実行し、かつフルスイートの実測所要時間 (約407秒) をカバーする明示的な Bash `timeout` (例: `timeout: 600000` = ツールの上限10分。デフォルトの120秒上限では短すぎる) を指定する。headless `claude -p` プロセスにはバックグラウンド Bash タスクの完了通知を受け取る後続ターンが保証されないため、バックグラウンド化すると `auto-retry-on-fail.max_iterations` を無為に消費する無限待機のリスクがある (Issue #994)。対話モードでの挙動 (バックグラウンド化 + 通知待ち) は変更しない。 (→ Acceptance Criteria 1)

## Verification
### Pre-merge
- <!-- verify: rubric "skills/code/SKILL.md の Behavioral Change Detection セクション (または test-runner.md) が、--non-interactive / headless 実行時はフルスイート (bats tests/) をバックグラウンド化せずフォアグラウンドで実行すべきというガイダンスを含んでいる" --> ガイダンスが追記されている

### Post-merge
なし

## Notes

- **追記先の判断根拠**: Issue 本文の Auto-Resolved Ambiguity Points で「`skills/code/SKILL.md` の Behavioral Change Detection サブセクションを第一候補とし、`modules/test-runner.md` への追記可否は実装フェーズの裁量に委ねる」との事前決定があった。`modules/test-runner.md` を確認したところ、`bats tests/` full suite override は Step 9 内 (355行目の `Read test-runner.md` 呼び出しより前) で直接実行される処理であり、`test-runner.md` 自体は auto-detection による narrow scope 実行のみを担当する。したがって本 Spec では `skills/code/SKILL.md` の該当箇所のみを追記対象とし、`modules/test-runner.md` への重複追記は行わない。
- **明示的 timeout 指定を追加した理由**: Issue 本文の AC (rubric) はフォアグラウンド/バックグラウンドの区別のみを求めているが、Bash ツールは明示的な `timeout` を指定しない場合デフォルト120秒でタイムアウトする。Issue #979 の Code Retrospective によれば、フォアグラウンド実行での実測所要時間は約6分47秒 (407秒) であり、120秒のデフォルト上限を大きく超える。フォアグラウンド化のみでは新たなタイムアウト失敗を招く (無限待機がタイムアウト失敗に置き換わるだけで根本課題が解決しない) ため、本 Spec では十分な明示的 timeout (例: 600000ms) の指定もあわせてガイダンスに含める。
- **Steering Docs sync candidate 確認**: `skills/code/SKILL.md` を変更対象に含むため `grep -l "code" docs/*.md docs/ja/*.md` を実行したが、"code" は "Claude Code" 等を含む一般的な語であり17ファイルがヒットして識別に有用でなかった。より的を絞った `grep -l "Behavioral Change Detection\|bats tests/" docs/*.md docs/ja/*.md` では `docs/migration-notes.md` (と ja 版) のみがヒットしたが、内容は無関係な一般的移行チェックリストのテンプレート行であり、本 Issue の変更に起因する同期対象ではないと判断した。
- 本 Issue はドキュメント文言追加のみで `docs/translation-workflow.md` の対象である `docs/*.md` トップレベルファイルを変更しないため、`docs/ja/` 同期は不要と判断した。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 「`/issue 994 --non-interactive` のリファインメント実施記録。Type=Task, Size=XS, Value=2 の triage 根拠、Background記載事実の確認 (skills/code/SKILL.md Step 9 の実在確認、test-runner.md に既存の background/foreground 記述がないことの確認)、Auto-Resolved Ambiguity Points 2件の判断根拠を記録した Issue Retrospective」/ https://github.com/saitoco/wholework/issues/994#issuecomment-4979349164

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps の箇条書き1件を記載どおりに追加した

### Design Gaps/Ambiguities
- Behavioral Change Detection の `grep -rl "SKILL.md" tests/` は (ファイル名ベースの一致のため) `skills/code/SKILL.md` 専用の対応テストファイル以外にも汎用的にヒットし、本Issue自身の実装時にも full suite override が発火した。結果として、本Issueが追加したばかりのガイダンス (`--non-interactive` 実行時はフォアグラウンド + 明示的timeout) をその場で実運用検証する機会になり、`bats tests/` (1202件) をフォアグラウンド・timeout 600000ms 指定で実行して正常完了 (無限待機なし) を確認できた

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps に記載された1箇所 (Step 9 `bats tests/` override直後) にのみガイダンスを追加し、`modules/test-runner.md` への重複追記は行わなかった (Spec Notes の判断を踏襲)

### Deferred Items
- None

### Notes for Next Phase
- 本Issue実装自体が Behavioral Change Detection を誘発し、追加直後のガイダンスをフォアグラウンド実行で dogfood 検証済み (上記 Design Gaps/Ambiguities 参照) — review/verify フェーズでの追加検証は不要
