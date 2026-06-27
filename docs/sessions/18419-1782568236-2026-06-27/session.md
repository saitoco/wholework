---
type: report
description: L3 batch session retrospective — /auto --batch 781 783
date: 2026-06-27
session_id: 18419-1782568236
---

# L3 Session Retrospective: 18419-1782568236

## Context

`/auto --batch 781 783` — 2 Issues 連続処理 (website 系プロジェクト対応 feature の 2 つ):

- **#781** (L): AC 三層分類 + PR preview URL pre-merge 検証 (3-tier classification: local/preview/production)
- **#783** (M): `always-pr` + `auto-stop-at` (enum) project-level config

両者は website 系プロジェクトを `/auto` で扱える状態にするための補完関係。`#781` の preview URL tier と `#783` の `auto-stop-at=review` が組み合わさることで、PR 上で preview URL 検証 + AI review → 人間 merge gate のワークフローが成立する。

## What worked

- **Sequential 直列 batch 処理**: List mode (`--batch 781 783`) で 2 Issue を順次処理し、各 Issue ごとに run-auto-sub.sh で spec→code→review→merge を独立完走、parent session で verify を実行する分業が機能。
- **#781 完走**: L size + Opus spec → 18分で PR 作成、review、merge まで自動完走。Pre-merge AC 8 件すべて initial PASS (auto-retry 不要)。
- **#783 完走 (再実行後)**: M size で spec → code → review (light) → merge を完走。Pre-merge AC 10 件すべて initial PASS。
- **Retrospective から的確な改善 Issue 抽出**: #781 から 3 件、#783 から 5 件の Tier 1 改善 Issue を起票 (#788-#790, #794-#798)。review/spec/code phase で検出された繰り返し課題を構造化された Issue に落とせた。
- **Adversarial review の効果**: #783 review phase で `auto-stop-at: spec` 値の実装漏れ・`$PR_NUMBER` 未取得状態でのジャンプの 2 件を detect・修正。enum coverage check と実行順序依存変数の参照タイミングは review pattern として価値が確認できた (#794 に起票)。

## Limits and gaps

- **#783 first attempt の external kill**: spec phase 開始直後 (約 1 分後) に background task が killed status で停止。原因不明 (watchdog ではない、user 介入の可能性)。clean re-run で問題なく完走したが、kill の root cause は未調査。
- **Loop-state heartbeat dirty state friction が再発**: #781 と #783 の verify 前に `docs/sessions/_daily/loop-state-{DATE}.md` が dirty として検出され、毎回手動 commit + pull rebase が必要だった。`append-loop-state-heartbeat.sh` が best-effort 設計で commit/push しないため、下流 phase が clean state で立ち上がらない構造的問題。#798 に起票済。
- **CI DCO 失敗の再発リスク**: #783 で 2 commits に Signed-off-by 欠落 → CI DCO 失敗が発生し review phase で手動修復された。`/code` skill が `-s` を enforce する仕組みが不在で、Spec 側に「全 commit に `-s`」と都度書く運用は脆弱。#795 に起票。
- **docs/code consistency gap**: #783 で `docs/guide/customization.md` の説明文と skills 実装が不一致 ("silently ignored" vs 警告出力) → review で検出。issue/spec 段階で mechanical 照合する AC pattern がない。#796 に起票。
- **enum coverage check pattern の不在**: #783 で `auto-stop-at` の enum `spec/code/review/merge/verify` のうち `spec` 値の実装漏れを review で検出。Spec で enum 定義した機能の全 enum 値網羅を review で系統的にチェックする pattern がない。#794 に起票。
- **`/auto` Step 3a route demotion 後の ALWAYS_PR 再チェック未実装**: #783 で `ALWAYS_PR` 機構を導入したが Step 3a の demotion ロジックに再チェック未追加で SHOULD として handoff から繰り越し。#797 に起票。

## Improvement candidates

(以下は本 session で起票済の改善 Issue 群。`## Auto Retrospective > ### Improvement Proposals` セクションでも参照される)

- **#788** `/issue` skill が test 関連 AC で参照する test file の存在を確認する Step 4 ガイダンス追加
- **#789** 新規 bats test 用 `PROJECT_ROOT` anchoring pattern の template/ガイダンス導入
- **#790** `/doc translate` workflow に source/target code block fidelity check を追加
- **#794** `/review` skill に enum 定義機能の coverage check pattern を導入
- **#795** `/code` skill が生成する全 commit に Signed-off-by (`-s`) を自動付与
- **#796** Issue/Spec template に docs/code consistency を mechanical 照合する AC pattern を guideline 化
- **#797** `/auto` Step 3a route demotion 時に `ALWAYS_PR=true` なら demotion 抑止
- **#798** Loop-state heartbeat の dirty state による `/verify` block を解消 (案 A: append 後 commit/push, 案 B: verify dirty check 特例)

## Auto Retrospective
### Improvement Proposals

(上記 `## Improvement candidates` と同一内容。`modules/retro-proposals.md` 互換のため複製)

- `/issue` skill が test 関連 AC で参照する test file の存在を確認する Step 4 ガイダンス追加
- 新規 bats test 用 `PROJECT_ROOT` anchoring pattern の template/ガイダンス導入
- `/doc translate` workflow に source/target code block fidelity check を追加
- `/review` skill に enum 定義機能の coverage check pattern を導入
- `/code` skill が生成する全 commit に Signed-off-by (`-s`) を自動付与
- Issue/Spec template に docs/code consistency を mechanical 照合する AC pattern を guideline 化
- `/auto` Step 3a route demotion 時に `ALWAYS_PR=true` なら demotion 抑止
- Loop-state heartbeat の dirty state による `/verify` block を解消

## Filed Issues

- #788, #789, #790 (from #781 verify retrospective)
- #794, #795, #796, #797, #798 (from #783 verify retrospective)
