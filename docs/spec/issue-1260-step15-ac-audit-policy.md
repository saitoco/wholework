# Issue #1260: issue/triage: Step 15 AC 監査が自己生成 AC を自動修正してよいかを定義

## Overview

`/issue` Existing Issue Refinement の Step 15 (AC Verify Command Integrity Audit) が、**自分自身が同一実行内で書いた AC** (Step 7 の分類・Step 9 の Issue body 反映、または Step 12 の再配分に由来する自己生成 AC) の不備を検出した場合の扱いが未定義であり、実測で挙動が分かれていた (#1220: 規定通り非破壊のコメント報告のみ、#1221: Issue body を即座に自動修正 — 規定からの逸脱)。

本 Issue では `skills/triage/skill-dev-verify-audit.md` § Non-Destructive Audit Behavior と `skills/issue/SKILL.md` Step 15 の両方を更新し、自己生成 AC も外部由来 AC と同じ非破壊 (コメントのみ、Issue body 自動編集なし) の扱いに統一する (Issue 本文の検討候補 B を採用。A/C を不採用とした理由は Notes を参照)。Size XS (spec スキップ経路) での引き取り手不在という B 案の既知の穴は、既存の Comment Consumption Procedure (`modules/l0-surfaces.md`) が `/code` にも同じコメント一級コンテキスト注入を提供している事実を明文化することで、新規メカニズムなしに解消する。

## Changed Files

- `skills/triage/skill-dev-verify-audit.md`: `## Non-Destructive Audit Behavior` セクションに自己生成 AC の扱い (非破壊を維持、根拠) と repair handoff (次フェーズへのコメント引き継ぎ経路) の説明を追加
- `skills/issue/SKILL.md`: Step 15 に自己生成 AC への言及を追加し、`skill-dev-verify-audit.md` の方針との整合を明記
- [Steering Docs sync candidate、確認済み・変更不要] `docs/environment-adaptation.md` / `docs/ja/environment-adaptation.md`: Domain file 一覧表の `skill-dev-verify-audit.md` 行 (読み込み条件「常時 (無条件)」・目的「AC verify command integrity audit」) — 本 Issue はセクション内の追記のみで読み込み条件・目的を変えないため、表の記述は現状のまま正確 (grep 確認済み)
- [Steering Docs sync candidate、確認済み・変更不要] `modules/size-workflow-table.md`: `skill-dev-verify-audit.md` への参照は Pattern 4 (Size/`ALWAYS_PR` sourcing) に関するもので、本 Issue が変更する Non-Destructive Audit Behavior セクションとは無関係 (grep 確認済み)
- [Steering Docs sync candidate、確認済み・変更不要] `tests/issue.bats`: line 42 が `skills/issue/SKILL.md` 内の "AC Verify Command Integrity Audit" 見出し文字列の存在を確認するテスト — 本 Issue は見出しを変更しないため影響なし (grep 確認済み)

## Implementation Steps

1. `skills/triage/skill-dev-verify-audit.md` の `## Non-Destructive Audit Behavior` セクションを変更する。冒頭の非破壊原則の直後に、自己生成 AC (Step 7 の分類・Step 9 の Issue body 反映、または Step 12 の再配分によって同一 `/issue` 実行内で書かれた AC) も非破壊の対象に含まれることを明記し、その根拠 (判定の決定性維持、`/triage` Step 2 auto-chain 経由での起源追跡境界の曖昧さ回避) を記述する。#1220 (規定通り非破壊) と #1221 (逸脱して自動編集) の実測差を根拠として引用する。続けて「Repair handoff for self-generated AC」段落を追加し、`modules/l0-surfaces.md` の Comment Consumption Procedure により、次に実行されるフェーズ (Size M/L/XL は `/spec`、Size XS は `/spec` をスキップするため `/code` が直接) がコメントを一級コンテキストとして受け取り、示唆された修正を適用することを明記する。新規メカニズムは導入しない。(→ 受入条件 1, 2, 4)
2. `skills/issue/SKILL.md` Step 15 の "Pattern 4 Size/`ALWAYS_PR` sourcing in this context" 段落の直後、既存の "Note: if Step 2's triage auto-chain..." 段落の直前に新規段落を挿入する。Step 15 が監査する AC の大半は同一実行の Step 9/Step 12 に由来する自己生成 AC であり、`skill-dev-verify-audit.md` § Non-Destructive Audit Behavior と同じ非破壊方針 (小さな不備でも Issue body を自動編集しない) に従うことを明記する。(after 1) (→ 受入条件 3)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/triage/skill-dev-verify-audit.md の Non-Destructive Audit Behavior セクションに、監査対象 AC が同一実行内で自己生成されたものである場合の扱いが明示されている (自動修正可・不可のいずれかと、その根拠)" --> 自己生成 AC に対する扱いが `skill-dev-verify-audit.md` に明示されている
- <!-- verify: section_contains "skills/triage/skill-dev-verify-audit.md" "Non-Destructive Audit Behavior" "自己生成" --> `Non-Destructive Audit Behavior` セクションに「自己生成」への言及がある
- <!-- verify: rubric "skills/issue/SKILL.md Step 15 の記述が、skill-dev-verify-audit.md 側で定めた自己生成 AC の扱いと矛盾しない形に更新されている。両者が異なる方針を述べていないこと" --> `skills/issue/SKILL.md` Step 15 の記述が上記と整合している
- <!-- verify: rubric "採用案 (A/B/C のいずれか、または組み合わせ) と不採用案の理由が Spec に記録されている。案 B を採る場合は Size XS (spec スキップ) 経路で引き取り手がいない問題への対応も含まれていること" --> 案の採否と XS 経路の扱いが記録されている

### Post-merge

- 次回 `/issue` Step 15 が自己生成 AC の不備を検出した際、定めた方針どおりの挙動になることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### Design Decision (Adopted Approach)

Issue 本文の検討候補 3 案から **B (一律非破壊を維持し `/spec` 引き継ぎを正式化)** を採用した。

- **採用: B** — 変更対象が Issue 本文の AC が既に指定する 2 ファイル (`skill-dev-verify-audit.md` § Non-Destructive Audit Behavior, `skills/issue/SKILL.md` Step 15) に収まり、新規メカニズムを要しない。既存の Comment Consumption Procedure (`modules/l0-surfaces.md`) が全フェーズ共通で「コメントは一級コンテキスト」という契約を既に持っているため、「次フェーズが拾って直す」という B の前提は追加実装なしで成立する
- **不採用: A (自己生成 AC のみ自動修正を許可)** — 「同一実行内で自己生成された」の判定基準を新設する必要があり、Issue 本文の trade-off 列が指摘する通り `/triage` Step 2 auto-chain 経由で `/issue` が呼ばれた場合の「同一実行」境界が曖昧 (`/triage` の Step 2 と `/issue` 自身の Step 7/9/12 は別スキル呼び出しだが、ユーザ視点では連続した 1 回の操作)。この境界を明確に定義しないまま実装すると、Step 15 の判定自体が非決定的になり、本 Issue が解消しようとしている「挙動が分かれる」問題を判定ロジック内に再導入することになる
- **不採用: C (検出時に AC を保留状態にする)** — 新しいマーカー語彙 (例: `verify-type: pending-audit`) の新設と、`/verify` の分類器 (`modules/verify-classifier.md`) との整合が必要になり、3 案中もっとも変更範囲が大きい。SPEC_DEPTH=light (Size M) の対象規模に見合わない

### Size XS (spec スキップ) 経路への対応

B 案の既知の穴 (Issue 本文): 「Size XS の patch route では `/spec` がスキップされるため、非破壊コメントの引き取り手がいない」。

調査の結果、**新規メカニズムは不要**と判断した。`skills/code/SKILL.md` (Worktree Entry 内) は既に `modules/l0-surfaces.md` の Comment Consumption Procedure を `COMMENT_SCOPE=issue` で呼び出しており (`/spec` と同じ契約)、`/issue` が投稿する監査コメントは `authorAssociation: MEMBER` (first-class) として次フェーズに一級コンテキスト注入される。この注入は Size に関わらず「次に実行されるフェーズ」であれば `/spec` でも `/code` でも同じ経路で機能する。したがって「引き取り手がいない」わけではなく、`/spec` 前提で書かれていた既存の文言 (`skill-dev-verify-audit.md` 側) を「次フェーズ (`/spec` または Size XS の場合は `/code`)」に一般化するだけで、XS 経路の穴は解消する。新しいコード・スクリプト変更は不要 (Implementation Step 1 の Repair handoff 段落がこれを明文化する)。

### Steering Docs sync candidate 確認結果

`grep -rn "skill-dev-verify-audit" docs/ tests/ scripts/` で確認した参照先のうち、`docs/environment-adaptation.md` / `docs/ja/environment-adaptation.md` (Domain file 一覧表)、`modules/size-workflow-table.md` (Pattern 4 関連)、`tests/issue.bats` (見出し文字列確認) はいずれも本 Issue の変更内容 (セクション内の追記、既存見出し文字列は不変) と無関係であることを確認した。`docs/spec/issue-{584,1102,1181,1185,1220,1221}-*.md` は過去 Issue の disposable な Spec 記録であり、更新対象外 (履歴として現状のまま)。

### 文字列存在確認

`section_contains` の見出し引数 `"Non-Destructive Audit Behavior"` は `skills/triage/skill-dev-verify-audit.md` の実見出し `## Non-Destructive Audit Behavior` と完全一致することを確認済み。検索文字列 `"自己生成"` は現状の main には未出現であることを確認済み (grep 実行、ヒット 0 件) — 常時 PASS ではなく、Implementation Step 1 の変更後にのみ出現する

## Consumed Comments

- saito / MEMBER / first-class / `/issue` Existing Issue Refinement の Issue Retrospective — AC1 への補助チェック追加理由、Ambiguity Detection の結果 (該当なし、案 A/B/C の決定は `/spec` に意図的に委譲)、事実確認結果、Title drift なし、Blocked-by なしを記録 / https://github.com/saitoco/wholework/issues/1260#issuecomment-5225317179

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1・2 をそのまま実施した (段落の挿入位置・内容とも Spec の指定通り)。

### Design Gaps/Ambiguities

- N/A

### Rework

- 実装のやり直しは発生していない。参考記録として: `skills/issue/SKILL.md` が複数テストファイル (`tests/verify-executor.bats` 等、直接対応する `tests/issue.bats` 以外) から参照されているため Behavioral Change Detection が発火し、`bats --jobs 18 tests/` のフルスイート実行が必要になった。実行結果、`tests/post_merge_check.bats` の `fail: gh issue reopen called when FAIL input given` が 1 件 FAIL したが、同ファイル単体実行では PASS することを確認済み。`test-failure-classify.sh` の分類は `infra` (並列実行時のリソース競合によるフレークで、テストコード側の修復対象ではない)。本 Issue の変更 (`skills/issue/SKILL.md` Step 15, `skills/triage/skill-dev-verify-audit.md`) とは無関係と判断し、pr route の既定方針通り CI 側の検知に委ねて未修正のまま継続した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps 1・2 をそのまま実施し、`skill-dev-verify-audit.md` § Non-Destructive Audit Behavior に自己生成 AC の扱い (非破壊を維持) と根拠、「Repair handoff for self-generated AC」段落を追加。`skills/issue/SKILL.md` Step 15 に整合段落を挿入した。
- Pre-merge AC 4件 (rubric x3, section_contains x1) はいずれも実装内容そのままで PASS と判定し、Issue body のチェックボックスを更新した。

### Deferred Items
- Post-merge AC (`次回 /issue Step 15 が自己生成 AC の不備を検出した際、定めた方針どおりの挙動になることを観察する`, observation type) は次回発火まで未検証のまま。
- `tests/post_merge_check.bats` の並列実行時フレーク (`fail: gh issue reopen called when FAIL input given`) は本 Issue の変更と無関係と判断し未修正。継続的に発生する場合は別途調査 Issue が必要。

### Notes for Next Phase
- `/review` は Pre-merge AC 4件が既に `[x]` 済みであることを踏まえ、rubric 判定の妥当性を独立に再確認すること。
- `/merge` は上記の `tests/post_merge_check.bats` フレークが CI 上でも再現するかを確認し、再現する場合は無関係な既存問題として扱ってよい (本 Issue の diff は `skills/issue/SKILL.md` と `skills/triage/skill-dev-verify-audit.md` のみ)。
