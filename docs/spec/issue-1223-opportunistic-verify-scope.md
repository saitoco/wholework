# Issue #1223: opportunistic-verify: セッション単独で観測できない条件の PASS 誤判定を防ぐ

## Overview

`modules/opportunistic-verify.md` の Step 2 (AI retrospective による PASS/FAIL/SKIP 判定) は、「this execution で確認できた」を PASS の基準としているが、条件がそもそも単一セッションの観測範囲に収まっているかを事前に評価するステップを持たない。そのため、リポジトリ全体の集計や複数セッションにまたがる状態を問う条件に対して、自セッションの局所的な成功 (例: 自分の worktree を作成・削除できた) を条件全体の成立と読み替えて PASS 誤判定する構造的リスクがある。実測 (#129: `/review 1218` が「残留 worktree が蓄積せず、再試行時に競合しない」を PASS 判定し `phase/done` へ遷移させたが、実際には 47 件残留していた) により実害が確認済み。

本 Issue は `modules/opportunistic-verify.md` の判定基準に、(1) 条件がこの実行の観測範囲内かを PASS/FAIL 判定の前に評価し、範囲外なら SKIP に倒すステップ、(2) 単一セッション内の部分的な成功を条件全体の PASS と読み替えてはならない旨の明記、の 2 点を追加する。この module は `/issue` `/spec` `/code` `/review` `/verify` の 5 skill から "Read and follow" パターンで参照されており (grep で実際に 5 ファイルのヒットを確認済み)、1 箇所の修正が全呼び出し元に伝播する。

## Reproduction Steps

1. Issue の post-merge 条件が、リポジトリ全体の集計や複数セッションにまたがる状態を記述している (例: 「残留 worktree が蓄積せず、再試行時に競合しない」)
2. 何らかの skill (例: `/review`) の実行が完了し、`modules/opportunistic-verify.md` に従って Opportunistic Verification が走る
3. AI が自分自身の実行メモリを retrospect する際、その実行が行った局所的な作業 (例: 自分の worktree を 1 つ作成し、Exit 時に 1 つ削除した) が成功していることを根拠に、条件全体を PASS と判定する — リポジトリ全体の残留数は一度も数えていない
4. チェックボックスが checked になり、post-merge 条件がすべて checked になった場合は `phase/done` へ遷移する — 実際には検証されていない条件が検証済みとして Issue が完了扱いになる

## Root Cause

`modules/opportunistic-verify.md` の "### 2. Cross-Reference with Current Execution Results (AI Retrospective)" は、PASS の基準を「Confirmed during this execution that the condition is met」とのみ定義しており、その手前に「この条件はそもそも単一実行の観測範囲内で確認可能か」を問う評価ステップが存在しない。単一セッションの実行では、リポジトリ全体の集計や複数セッションにまたがる累積状態を直接観測することはできない。にもかかわらず判定基準は「この実行で確認できたか」という基準のみを提示しているため、AI が「自分のスコープ内で行った作業は成功した」という部分的事実を「条件全体が成立した」という全体命題にすり替えて PASS を返す余地が残っている。#129 で実際に発生したのはこのすり替えである。

## Changed Files

- `modules/opportunistic-verify.md`: "### 2. Cross-Reference with Current Execution Results (AI Retrospective)" セクションに、(a) PASS/FAIL 判定前の観測スコープ評価ステップ (範囲外なら SKIP へ)、(b) PASS 定義への部分的成功の読み替え禁止の明記、を追加

## Implementation Steps

1. `modules/opportunistic-verify.md` の "### 2. Cross-Reference with Current Execution Results (AI Retrospective)" セクション冒頭に、PASS/FAIL/SKIP 判定に先立つ観測スコープ評価の説明を追加する。「条件の真偽がこの実行自身が行った・観測した範囲だけで確定できるか」を問い、リポジトリ全体の集計 (repository-wide aggregation) や複数セッションにまたがる状態を範囲外の例として明示し、範囲外なら PASS/FAIL を試みず SKIP と判定する旨を書く (→ acceptance criteria AC1)
2. 同セクションの **PASS** 箇条書き定義に、単一セッション内の局所的な成功 (例: 自セッションが自分の worktree を作成・削除できた) を条件全体の PASS の根拠にしてはならない旨を追記する (after 1) (→ acceptance criteria AC2)

具体的な追加後の全文 (既存の "No additional log retention mechanism..." 段落までを含む "### 2." セクション全体の置き換え):

```markdown
### 2. Cross-Reference with Current Execution Results (AI Retrospective)

For each extracted condition, first check whether it is observable within this execution's own scope, then judge by PASS/FAIL/SKIP criteria.

**Observation scope check (before PASS/FAIL judgment)**: a condition is in scope only when its truth value is fully determined by what this skill execution itself performed or observed. Conditions that require repository-wide aggregation (e.g., "no stale worktrees accumulate repository-wide", "N occurrences across the repository") or state spanning multiple sessions are out of scope for a single execution — judge these **SKIP**, not PASS/FAIL, regardless of how this execution's own local work went.

For in-scope conditions, reflect on this skill's execution memory (output results, operations performed, observed facts) and judge:

- **PASS**: Confirmed during this execution that the condition is met. This execution's own local success (e.g., this session created and removed its own worktree) is not by itself evidence that a broader or repository-wide condition holds — do not read a partial, local success as PASS for the condition as a whole.
- **FAIL**: Confirmed during this execution that the condition is not met
- **SKIP**: Insufficient information for judgment (not the specific pattern of input, out of this execution's observable scope per the check above, etc.)

No additional log retention mechanism is needed. The AI retrospects on its memory of skill execution to make judgments.
```

## Verification

### Pre-merge

- <!-- verify: rubric "modules/opportunistic-verify.md の判定基準に、条件がそのセッションの実行範囲で観測可能かを評価し、範囲外の場合は PASS ではなく SKIP に倒す旨が明記されている。リポジトリ全体の集計や複数セッションにまたがる状態を問う条件が範囲外の例として示されていること" --> セッション観測範囲外の条件を SKIP に倒す判定基準が追加されている
- <!-- verify: rubric "追加された判定基準が、単一セッション内の部分的な成功 (自セッションの後始末が成功した等) を条件全体の PASS と読み替えてはならない旨に言及している" --> 部分的成功の読み替えを禁じる記述がある

### Post-merge

- 次回 opportunistic verification 実行時 (`event=auto-run`)、リポジトリ全体の状態を問う条件が PASS ではなく SKIP と判定されることを観察する

## Consumed Comments

Cutoff: `2026-08-07T02:40:06Z` (最新の `phase/*` ラベル付与イベント = `phase/issue`)

| Login | Association | Trust tier | Intent summary | URL |
|-------|-------------|-----------|-----------------|-----|
| saito | MEMBER | first-class | Issue Retrospective。Pre-merge AC3 (`grep "SKIP" modules/opportunistic-verify.md`) を削除した経緯を記録: 直前の triage AC audit コメントが「常時 PASS な verify command」パターン該当を指摘 (`grep -c "SKIP"` が現行 main で既に 3 件ヒットし実装内容に関わらず常に PASS する)。`modules/verify-patterns.md` §9 の「実装先セクション見出しが未定/実装依存の場合は補完チェックを適用しない」指針に基づき AC3 を削除。検討候補 A/B/C のどちらを採用するかは spec フェーズの調査に委ねる設計判断であることも明記 | https://github.com/saitoco/wholework/issues/1223#issuecomment-5211504295 |

## Notes

**検討候補 A/B/C の採否判断 (spec フェーズ)**: Issue 本文の検討候補表 (A: 観測スコープの明示的判定を追加 / B: PASS 時の根拠列挙必須化 / C: 条件側にスコープ属性を付与) のうち、**A と B を併用し、C は採用しない**。

- 根拠: Issue 本文自身が「案 A と B は併用可能」「案 C は `modules/verify-classifier.md` との整合も要る」と明記している。C は `verify-type: opportunistic scope=session|repo` のような属性を既存の opportunistic 条件すべてに付与し直す移行作業を伴い、`modules/verify-classifier.md` (Issue 起票時の分類基準 SSoT) 側の変更も要る — Size S / Bug 種別の本 Issue のスコープに対して過大である
- A と B は `modules/opportunistic-verify.md` 単体の Processing Steps 記述変更のみで実現でき、Pre-merge AC1・AC2 の rubric 文言 (観測スコープ評価 → SKIP へのフォールバック / 部分的成功の読み替え禁止) をそのまま満たす
- `modules/verify-classifier.md` は Issue 起票時点の条件テキストを `auto`/`opportunistic`/`observation`/`manual` に分類する基準 (別の関心事) であり、本 Issue が扱う「判定側 (retrospect 時) の基準」とは独立している。Related #1209 (常時 PASS な verify command の検出パターン追加) とも役割が異なる — 実害のクラスは同じだが、#1209 は verify command の記述側、本 Issue は判定側の基準を扱う

**AC3 (常時 PASS 検出) の削除は Issue 側で既に解決済み**: Issue Retrospective コメント (Consumed Comments 参照) の通り、起票時点の Pre-merge AC3 (`<!-- verify: grep "SKIP" "modules/opportunistic-verify.md" -->`) は `/spec` 着手前に既に削除されている。`grep -c "SKIP" modules/opportunistic-verify.md` は本 Spec 作成時点の現行 main で 3 件ヒットしており (Background の PASS/FAIL/SKIP 定義に由来)、実装内容に関わらず常に PASS するため、`modules/verify-patterns.md` §9 の補完チェック運用ガイドに沿って正しく除外されている。本 Spec で追加の対応は不要。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 起票時点の Pre-merge AC3 (`grep "SKIP" modules/opportunistic-verify.md`) を `/issue` refinement が削除した判断は妥当。現行 main で既に 3 件ヒットするため実装内容に関わらず常時 PASS する verify command であり、`modules/verify-patterns.md` §9 の運用ガイドに合致する。残った AC1/AC2 の rubric は意味的条件を過不足なく記述しており、verify 時に PASS/FAIL の境界で迷う余地がなかった
- 検討候補 A/B/C の採否を Issue 側で確定させず spec フェーズに委ねた設計は、Size S に対して適切な粒度だった

#### spec
- 採用案 (A+B)・不採用案 (C) の判断根拠が Notes に明記され、C の除外理由 (`modules/verify-classifier.md` との整合コストが Size S に対して過大) も Issue 本文の記述に根拠づけられている
- Spec の Implementation Steps が置換後の全文をコードブロックで提示していたため、実装差分が Spec の提案ブロックと逐語一致した。設計と実装の乖離ゼロ

#### code
- `run-code.sh` の auto-retry 3 回すべてが silent no-op で終了。3 回とも「バックグラウンドで実行中の `bats tests/` の完了を待ちます (完了時に通知されます)」という文でターンを終了しており、`claude -p` には再呼び出し保証がないためそこでプロセスが終了した (`background-notification-wait`)
- **ただしこれは #1213 の修正 (`38663cb3`, 13:00:19 着地) の退行ではない**。4 回の試行開始時刻は 11:59 / 12:24 / 12:38 / 12:52 で、いずれも修正着地前。全試行が修正前の `skills/code/SKILL.md` を読んで走っている。修正の有効性は次回以降の code フェーズで初めて観測可能
- retry 3 は実装を完了し `worktree-code+issue-1223` に `75bbb950` として commit まで到達していた。`reconcile-phase-state.sh` も `worktree_commits_found: true` を返しており、「実装は存在するが main へ伝播していない」状態を検知できていた

#### review
- patch route のため未実行 (N/A)

#### merge
- patch route のため未実行 (N/A)

#### verify
- Pre-merge 2 条件とも初回で PASS。rubric の文言が実装差分と 1:1 対応していたため判定に曖昧さがなかった
- Post-merge AC3 は `event=auto-run` 未発火のため SKIPPED。`session=next` 付きのため、発火しても skill 自己更新の伝播が確認できるまでは SKIPPED に倒れる想定

### Improvement Proposals

- **Tier 2/Tier 3 の patch route 復旧経路が `worktree_commits_found` を活用していない**: `reconcile-phase-state.sh code-patch --check-completion` は「worktree に commit はあるが origin/main には無い」状態を `worktree_commits_found: true` として正しく報告するが、この信号を消費する復旧経路が存在しない。(1) `modules/orchestration-fallbacks.md#code-patch-silent-no-op` の Fallback Steps は「`run-code.sh` を 1 回リトライ → 駄目なら Tier 3」のみで、worktree commit の main への伝播を試みない。(2) `agents/orchestration-recovery.md` は Step 3a (L61) で `code-pr` 専用に「commit はあるが push 未了」プローブを持ち `git push origin <branch>` を提案できるが、`code-patch` には同等のプローブがない。さらに L100 が main への直 push を禁止し、`scripts/validate-recovery-plan.sh` の `forbidden_cmd_patterns` (`push\s.*origin\s.*(main|master)`) がそれを機械的に強制するため、sub-agent は素の `git push origin main` を提案して棄却される — 実際に #1223 でこの経路をたどった。lock 経由の sanctioned な伝播手段である `scripts/worktree-merge-push.sh --from <branch>` は validator の禁止パターンに一致しないため復旧案として有効だが、agent prompt にその存在が記載されていない。対策として、`code-patch` 用の Step 3a 相当プローブを追加し、`worktree_commits_found: true` の場合は `worktree-merge-push.sh --from <branch>` を提案するよう agent prompt に明記する。あわせて `code-patch-silent-no-op` の Fallback Steps にも同経路を Tier 2 の段階で追加することを検討する
