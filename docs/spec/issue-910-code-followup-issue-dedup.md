# Issue #910: code: フェーズ内 follow-up Issue 作成に open-issue 重複チェックを追加 (#898/#899/#902 三重重複の根本原因)

## Overview

`/code` フェーズ (`skills/code/SKILL.md` Step 8 の「Follow-up Issue Creation」サブステップ、`gh issue create` 実行経路) には、起票前の既存 open Issue との重複チェックが無い。このため #877 の code フェーズが #902 を起票した際、既に同趣旨の #898・#899 が存在するにもかかわらず重複が検知できず、三重重複 (#898/#899/#902) が発生した。

`modules/retro-proposals.md` step 9 は同種の dedup ロジック (`gh issue list` で open Issue 一覧を取得し、タイトル/内容を semantic 比較して重複ならスキップ) を既に持つ。本 Issue はこの照合基準を `skills/code/SKILL.md` の Follow-up Issue Creation サブステップにインラインで適用し、`gh issue create` 前に同等の重複チェックを行わせる。

スコープは `skills/code/SKILL.md` の Follow-up Issue Creation 経路のみに限定する。Issue 本文の Auto-Resolved Ambiguity Points 記載の通り、`skills/verify/SKILL.md` の recoveries-auto-fire 経路 (`scripts/collect-recovery-candidates.sh --issues-json`) と `modules/retro-proposals.md` step 9 は既に重複チェックを実装済みのため対象外。

## Changed Files

- `skills/code/SKILL.md`: Step 8「Follow-up Issue Creation」サブステップに、`gh issue create` 実行前の open-issue 重複チェック手順を追加 (bash 3.2+ 互換 — 追加はプレーンテキストのみでシェルスクリプトの変更なし)
- `tests/code.bats`: 「Follow-up Issue Creation」セクション抽出ヘルパーと、重複チェック手順 (`gh issue list` キーワード) の存在を確認する `@test` を追加 (bash 3.2+ 互換 — 既存の `step0_section()` と同じ awk パターンを使用し、`mapfile` 等の bash 4+ 機能は使用しない)

## Implementation Steps

1. `skills/code/SKILL.md` の `#### Follow-up Issue Creation` サブステップ (Step 8 内、現行の `gh issue create` コマンドブロックの直前) に、重複チェックの手順を追加する。手順内容: `gh issue list --state open --limit 200 --json number,title` で open Issue 一覧を取得し、起票候補タイトルを既存 open Issue タイトルと semantic 比較する (`modules/retro-proposals.md` step 9 と同一の照合基準: タイトルまたは内容が同一・実質的に同一、または既存 Issue の背景/目的が同じ改善を対象としている場合は重複と判定)。重複が見つかった場合は `gh issue create` をスキップし、"Skipping follow-up Issue creation due to duplicate: {title} (existing: #{number})" 相当のメッセージを出力する。 (→ acceptance criteria AC1, AC2)
2. `tests/code.bats` に、`#### Follow-up Issue Creation` セクションを抽出する awk ヘルパー関数 (既存の `step0_section()` と同パターン) と、そのセクションが `gh issue list` を含むことを確認する `@test` を追加する。(after 1) (→ acceptance criteria AC1)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md の follow-up Issue 作成 (gh issue create) 経路に、起票前の open-issue 重複チェック手順が追加されている" --> <!-- verify: section_contains "skills/code/SKILL.md" "#### Follow-up Issue Creation" "gh issue list" --> code フェーズの follow-up Issue 作成前に既存 open Issue との重複チェックが行われる
- <!-- verify: rubric "重複チェックのロジックが retro-proposals の dedup と整合している (共用ヘルパーまたは同等の照合基準)" --> 重複判定基準が retro-proposals dedup と整合している

### Post-merge

なし

## Notes

- **実装方式の判断**: 「共用ヘルパー化」ではなく「`modules/retro-proposals.md` step 9 と同等の照合基準をインライン実装」を採用した。理由: (1) Size S / SPEC_DEPTH=light のシンプルさ制約 (実装ステップ・検証項目とも上限5件) との整合、(2) Issue Purpose 文言が「共用ヘルパー化して再利用する、または...インラインで実装することが望ましい」と両方式を許容していると明記、(3) Issue Retrospective コメント (2026-07-04T23:28:09Z, saito) が「共用ヘルパー化を必須要件ではなく推奨として扱う」と確認済み、(4) `modules/retro-proposals.md` は `/verify` と `/auto` から参照される共有モジュールであり、リファクタリングは本 Issue のスコープに対して変更のブラスト半径を不必要に広げる。
- **ドキュメント同期の判断**: `docs/tech.md` / `docs/ja/tech.md` に `retro/code` ラベルの言及があるが、ラベル一覧表 (Wholework Label Management) のみでラベル自体は変更しないため対象外と判断した (`doc-checker.md` Impact Determination Criteria の「Workflow phase changes」「Project structure changes」いずれにも該当しない)。
- **Issue 本文との整合性確認**: Issue 本文 Background の「`skills/code/SKILL.md:277` 付近に重複チェックが無い」という記述は、コードベース調査 (`skills/code/SKILL.md` Step 8 Follow-up Issue Creation サブステップ、272-286行目) で実装と一致することを確認した。矛盾なし。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / summary: Issue Retrospective — スコープを `skills/code/SKILL.md` に限定する判断の根拠 (`scripts/collect-recovery-candidates.sh` と `modules/retro-proposals.md` step 9 は実装済みと確認済み) と、AC1 への `section_contains "gh issue list"` 補助チェック追加の決定を記録。AC2 には補助チェックを追加しない判断 (実装自由度を AC 文言が既に許容) も記載。 / url: https://github.com/saitoco/wholework/issues/910#issuecomment-4884131799
