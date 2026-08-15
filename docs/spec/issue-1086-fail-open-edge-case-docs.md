# Issue #1086: spec: fail-open が実害となるスクリプトに edge case の期待動作を明記させる

## Overview

`/spec` は、fail-open が実害となるスクリプト (merge ゲート・validator など) を実装対象として識別する仕組みを持たず、Implementation Steps に edge case (空入力・特殊文字・依存コマンド失敗時など) の期待動作を明記させる仕組みもない。そのため fail-open バグが Pre-merge AC 検証をすり抜け、`/review` の bug-detection finder に到達するまで検出されない (実例: #1060 で `scripts/check-pre-merge-ac.sh` の fail-open バグ 2 件が、AC 検証 (ゲートのステップが追加されているかという記述の存在の確認) をすり抜けた)。

本 Issue では `skills/spec/SKILL.md` の Step 6 (Codebase Investigation) に、fail-safe critical スクリプトの識別基準と、該当時に Implementation Steps へ記載すべき edge case の期待動作を明記する新規サブセクションを追加する。

## Changed Files
- `skills/spec/SKILL.md`: Step 6 (Codebase Investigation) に "Fail-safe critical script identification" サブセクションを新規追加 (識別基準 3 点 + edge case 記載義務 + Issue #1060 の実例引用)

## Implementation Steps

1. `skills/spec/SKILL.md` の Step 6 内、"Adapter pattern survey" サブセクション末尾 (`**Skip** if all Issue body verify commands use built-in command types.`) の直後、`### Step 7: Ambiguity Resolution (clarify)` の直前に、以下の内容で "Fail-safe critical script identification (regardless of SPEC_DEPTH; only when applicable)" サブセクションを追加する (→ acceptance criteria AC1, AC2):
   - **識別基準**: 実装対象が次のいずれかに該当する場合 "fail-safe critical" として扱う — (a) 何らかの操作をブロック/許可するゲート (merge ゲート、precondition check など)、(b) 入力を検証して受理/拒否を決める validator (`validate-recovery-plan.sh` など)、(c) 失敗時に "安全側" の既定値を返す設計を持つスクリプト (`fail_open()` / `|| true` / `2>/dev/null` またはこれに準ずるパターンを含む)
   - **判定手順**: Issue 本文と Implementation Steps の記述から役割を判断する。既存スクリプトを変更する場合は `grep -nF -e 'fail_open' -e '|| true' -e '2>/dev/null' <file>` で裏付けを取る
   - **記載義務**: fail-safe critical と判定した場合、Implementation Steps に次の edge case の期待動作を明記する — 空入力 / 巨大入力、特殊文字 (`>`, `"`, 改行, CRLF, マルチバイト) を含む入力、依存コマンドが失敗した場合の挙動 (fail-open するか fail-closed するか、その根拠)
   - **実例引用**: Issue #1060 (`scripts/check-pre-merge-ac.sh` の `fail_open()` 設計に対し、`/review 1079` の bug-detection finder が `pipefail` 起因の意図しない fail-open 経路と `>` を含む AC テキストでの HTML コメント除去失敗の 2 件を検出した実例。いずれも Pre-merge AC 4 件 (ゲートのステップ存在の確認のみ) では捕捉できなかった)
   - **Skip 条件**: 実装対象が上記 3 基準のいずれにも該当しない場合

## Verification
### Pre-merge
- <!-- verify: rubric "skills/spec/SKILL.md に、fail-open が実害となるスクリプト (ゲート・validator 等) を識別する基準が追加されている" --> fail-safe critical の識別基準が追加されている
- <!-- verify: rubric "識別された場合に Implementation Steps へ記載すべき edge case の期待動作 (空入力・巨大入力・特殊文字を含む入力・依存コマンド失敗時の fail-open/fail-closed 方針) が具体的に列挙されている" --> edge case の記載義務が具体的に列挙されている
- <!-- verify: command "bats tests/spec.bats" --> `tests/spec.bats` が PASS する

### Post-merge
- ゲートまたは validator を新規追加する Issue を `/spec` に通し、Implementation Steps に edge case の期待動作が記載されることを確認する (verify-type: opportunistic)

## Notes

- **挿入位置の判断**: Step 6 内の既存サブセクション (Credential/security policy alignment check、Tool detection pattern consistency check、Adapter pattern survey など) と同じ「regardless of SPEC_DEPTH; only when applicable」スタイルに合わせ、"Adapter pattern survey" の直後・"### Step 7" の直前に配置する。この識別基準 (ゲート/validator/fail-open 既定値設計) は既存コードの内容 (`fail_open()` の有無など) を根拠に判断するため、Credential/security policy alignment check のような「codebase investigation 前」の早期ゲートとは異なり、investigation 後の位置が適切と判断した。
- **既存実装との整合確認 (Issue body vs. existing implementation conflict detection)**: Issue 本文が言及する `scripts/check-pre-merge-ac.sh` の `fail_open()`、`scripts/validate-recovery-plan.sh` の実在をそれぞれ `grep`/`ls` で独立に再確認した。矛盾なし (`/issue` フェーズの Issue Retrospective でも同様の確認が行われており、結果は一致)。
- **Steering Docs sync candidate check**: `grep -rn "fail-safe critical" docs/ tests/ scripts/ modules/` は 0 件、`docs/workflow.md` の `/spec` 記述 (48行目付近) も Step 6 内の個別サブセクション一覧までは踏み込んでいないため同期対象外と判断した。既存の類似 Step 6 サブセクション追加の前例 (Credential/security policy alignment check、コミット `ecad3488`, closes #502) も `skills/spec/SKILL.md` 単体の変更のみで完結しており、同じ判断を踏襲した。
- **allowed-tools impact chain check**: Changed Files に新規 `scripts/*.sh` も `modules/*.md` も含まれないため対象外。
- **`docs/ja/` translation sync check**: Changed Files が `skills/spec/SKILL.md` のみであり、`docs/translation-workflow.md` の同期対象 (top-level `docs/*.md`) 外のため対象外。
- **tests/spec.bats への新規テスト追加は見送り**: 既存の類似 Step 6 サブセクション (Credential/security policy alignment check、Tool detection pattern consistency check、Adapter pattern survey) はいずれも `tests/spec.bats` に専用テストを持たず、rubric verify command による検証のみで運用されている前例を確認した。本 Issue の AC 構成 (rubric 2件 + 既存スイート回帰確認 1件) もこの前例と一致するため、新規 bats テストは追加しない。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Step 1 was applied as written; no reordering, omission, or approach change occurred.

### Design Gaps/Ambiguities
- N/A — the insertion point and subsection content specified in the Spec (Notes: "挿入位置の判断") matched the actual `skills/spec/SKILL.md` Step 6 structure exactly.

### Rework
- N/A

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective (post-merge AC の verify-type を manual → opportunistic に自動解決。判断根拠は `modules/verify-classifier.md` の Tag Assignment Example との文言一致。Background 記載事実 (`check-pre-merge-ac.sh`/`fail_open()`/`validate-recovery-plan.sh`) はコードベース実在確認済み) / https://github.com/saitoco/wholework/issues/1086#issuecomment-5303694902
- No new comments since last phase.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Inserted the new "Fail-safe critical script identification" subsection immediately after "Adapter pattern survey" and before "### Step 7", matching the Spec's Notes rationale (the identification criteria depend on inspecting existing code for `fail_open()`/validator patterns, so it belongs after codebase investigation, not before it like the Credential/security policy alignment check).
- Wrote the new subsection content in English to match `skills/spec/SKILL.md`'s existing language (source code convention per project `CLAUDE.md`).
- Followed the Spec's Implementation Step 1 verbatim (3-criteria identification + edge case enumeration + #1060 example citation) without adding scope beyond it.

### Deferred Items
- None — the Post-merge AC (`verify-type: opportunistic`) is left unchecked by design; it observes a future gate/validator Issue passing through `/spec`, not something deferrable within this phase.

### Notes for Next Phase
- No dedicated `tests/spec.bats` case was added, per the Spec's Notes — matches the precedent of the three sibling Step 6 subsections (Credential/security policy alignment check, Tool detection pattern consistency check, Adapter pattern survey), which are verified by rubric + existing suite regression only.
- All 3 Pre-merge AC (2 `rubric` + 1 `command "bats tests/spec.bats"`) verified PASS in this phase; Issue checkboxes already updated via `gh-issue-edit.sh`.
- The Post-merge opportunistic AC remains open — `/audit` or a future `/spec` run on a gate/validator Issue is expected to surface it.

## Issue Retrospective

### Auto-Resolve Log

- **Post-merge AC の `verify-type` を `manual` → `opportunistic` に変更** — 理由: `modules/verify-classifier.md` の Tag Assignment Example が「`/spec` 実行時に X を確認する」という文言パターンを `opportunistic` の具体例として明示している。本 Issue の post-merge AC (「ゲートまたは validator を新規追加する Issue を `/spec` に通し、Implementation Steps に edge case の期待動作が記載されることを確認する」) は同じ文言形状に一致するため、Classification Criteria の優先順位 (`auto > opportunistic > observation > manual`) に従い `opportunistic` を採用した。
  - 他の候補: `manual` のまま維持 (元の設定) — `opportunistic` の方が `/auto` 実行時の自動消費対象になり将来の該当 Issue を取りこぼしにくいため不採用。

### Background Factual Claim Verification (advisory)

`scripts/check-pre-merge-ac.sh` / `fail_open()` / `scripts/validate-recovery-plan.sh` への言及はいずれもコードベースに実在を確認済み (advisory チェック PASS、本文修正なし)。

### AC Verify Command Integrity Audit

`scripts/check-skill-change-observation-ac.sh` / `scripts/check-ac-checkbox-format.sh` はいずれも exit 0 (指摘なし)。

### Consumed Comments (at /issue time)

No new comments since last phase.
