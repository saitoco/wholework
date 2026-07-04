# Issue #877: verify: Sonnet 5 での /verify interactive 摩擦 (#485) 再測定と設計簡素化判定

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (triage 内容の記録: Type=Task/Size=M/Value=3 の判定根拠、Priority 未検出のため据え置き、Blocked-by #876 は既存の GitHub native 関係を確認済み、Auto-Resolved Ambiguity Points の要約) / https://github.com/saitoco/wholework/issues/877#issuecomment-4882415667

## Overview

Sonnet 5 (2026-06-30 リリース) 環境下で `/verify` の interactive モード摩擦を再測定し、以下を判定する:

1. 既知の摩擦点 (#485) が Sonnet 5 の autonomous verification 特性により消滅・軽減するか
2. #485 で計画された対策の scope を縮小できるか
3. `/verify` skill の SKILL.md prompt を Sonnet 5 前提に de-prescription できる箇所があるか

本 Issue は `docs/reports/claude-sonnet-5-impact-strategy.md` §4.1/§4.5/§8 で「default parent (Sonnet 4.6 → Sonnet 5) 切替の2大ブロッカー」の一つとして位置づけられている (もう一方は #878) 。

**重要な事実確認 (Issue 本文との齟齬)**: Issue 本文 Background は「#485 で対策設計が進行中」と記述しているが、実際には #485 は 2026-05-26 に全 6 件の Acceptance Criteria を達成しクローズ済み (fork 廃止・parent context 実行・`AskUserQuestion` による manual AC 確認・checkbox flip・phase/done 遷移・`scripts/run-verify.sh` 削除、いずれも実装完了) 。したがって本 Issue の実質は「#485 の対策が Sonnet 5 下でも持続しているか、および Sonnet 5 の agentic 性能向上が残存摩擦をさらに軽減するか」の再測定であり、「進行中の設計を縮小するか」ではない。以下はこの訂正済み前提で設計する。

**Sonnet 5 カットオーバー時点の確認**: 本 `/spec` 実行自体が Sonnet 5 (`claude-sonnet-5`) で動作している (システムコンテキストで確認済み) 。`model: sonnet` エイリアスは現行 Sonnet に自動解決される仕様であり、かつ本リポジトリの `run-*.sh` / skill frontmatter は全て bare alias `sonnet` を使用し、ダウングレード用の日付固定モデル ID は存在しない (`grep -rn "claude-sonnet-4" scripts/ skills/*/SKILL.md` で 0 件を確認済み) 。よって 2026-06-30 (Sonnet 5 リリース日) 以降に実行された `/verify` は全て Sonnet 5、それ以前は Sonnet 4.6 とみなせる。過去 2 週間 (2026-06-20〜2026-07-04) のサンプル母集団はこの境界を自然にまたぐため (実測: 2026-06-29 以前に verify 済みの Issue が #862〜#869 など7件、2026-07-02 以降に verify 済みの Issue が #875〜#886 など8件、いずれも `## Acceptance Test Results` コメントの存在で確認済み) 、明示的な re-run なしで両コホートを構成できる。

## Changed Files

- `docs/reports/verify-sonnet-5-remeasurement.md`: new file — Sonnet 4.6 vs Sonnet 5 の `/verify` 摩擦比較レポート

## Implementation Steps

1. 過去 2 週間 (2026-06-20〜2026-07-04) に `phase/verify` label を経由した Issue から、Sonnet 4.6 コホート (2026-06-30 より前に `/verify` 実行) と Sonnet 5 コホート (2026-06-30 以降に `/verify` 実行) をそれぞれ 3〜5 件サンプリングする。判定方法: `gh issue list --state closed` で直近の候補を列挙し、各 Issue のコメントに `## Acceptance Test Results` を含むものを「verify 実行済み」として抽出、最初の該当コメントの `createdAt` で 2026-06-30 前後に振り分ける (→ 受入条件: 測定シナリオの前提データセット構築、AC2)
2. 各サンプル Issue について、既存の GitHub 上のアーティファクトから4指標を導出する (`/verify` には wall-clock やユーザ介入回数を記録する既存の計装が無いため、以下の代理指標を用いる):
   - **wall clock**: `gh api repos/{owner}/{repo}/issues/{n}/timeline` で `phase/verify` が付与された `labeled` イベントの時刻と、最初の `## Acceptance Test Results` コメントの `createdAt` との差分
   - **ユーザ介入回数**: 同コメント内の「Items Requiring User Verification」に列挙された項目数 (`post_merge_check.sh` が P/F/S を都度確認する対象数に対応する代理指標)
   - **reopen → 修正 → re-verify サイクル発生率**: 最初の verify コメント以降に発生した `reopened` timeline イベント数 ÷ サンプル数
   - **verify command 実行成功率と誤検知率**: 「### Auto Verification」テーブルの PASS/FAIL/UNCERTAIN 集計。FAIL のうち直後に修正コミットを伴わず再 verify で PASS した項目は誤検知 (false positive) とみなす
   (→ 受入条件 AC2)
3. `docs/reports/verify-sonnet-5-remeasurement.md` を既存の `docs/reports/*.md` 構成 (Background / 測定シナリオ / 結果 / 判定 / Notes) に沿って作成する。Background には本 Spec の「重要な事実確認」節の内容 (#485 クローズ済みの訂正) を含める。測定シナリオ節に手順1〜2の方法論と代理指標の限界を明記し、4指標 × 2コホートの比較表を記載する。判定節で Issue 本文 §B の基準 (摩擦の60%以上が消滅かつ精度低下なし→GO、一部シナリオのみ改善→部分適用、改善確認できず→NO-GO) に基づき GO/部分適用/NO-GO を判定し根拠を明記する (→ 受入条件 AC1, AC2, AC3)
4. 手順3の判定結果に応じて次のいずれかを実行する: GO または部分適用の場合は `scripts/gh-issue-comment.sh` で (クローズ済みの) Issue #485 に測定結果と持続性/改善の要旨、および残スコープ (もしあれば) を追記するコメントを投稿する。NO-GO の場合、または #485 の当初スコープに含まれない新規の残存摩擦パターンが見つかった場合は、`gh issue create` で follow-up Issue を新規作成する (#485 は全 Acceptance Criteria 達成済みのため reopen はしない) (→ 受入条件 AC4)

## Verification

### Pre-merge
- <!-- verify: file_exists "docs/reports/verify-sonnet-5-remeasurement.md" --> `docs/reports/verify-sonnet-5-remeasurement.md` が作成されている
- <!-- verify: rubric "docs/reports/verify-sonnet-5-remeasurement.md に、/verify 実行時間 (wall clock)・ユーザ介入回数・reopen→修正→re-verify サイクル発生率・verify command の実行成功率と誤検知率について、Sonnet 4.6 と Sonnet 5 の比較結果が記載されている" --> レポートに測定シナリオ (§A) で定義された4指標の Sonnet 4.6 vs Sonnet 5 比較結果が記録されている
- <!-- verify: rubric "docs/reports/verify-sonnet-5-remeasurement.md に GO/部分適用/NO-GOのいずれかの判定結果と、その根拠が明記されている" --> レポートに判定基準 (§B: GO / 部分適用 / NO-GO) に基づく判定結果と根拠が明記されている
- <!-- verify: rubric "判定結果に応じて Issue #485 への更新コメント、または follow-up Issue の作成のいずれかが行われている" --> 判定結果に応じて #485 への更新コメントまたは follow-up Issue が作成されている

### Post-merge

なし

## Notes

- **#485 は既にクローズ済み**: Issue 本文 Background の「#485 で対策設計が進行中」という記述は現状 (2026-07-04 時点) と齟齬がある。#485 は 2026-05-26 に全 6 件の Acceptance Criteria を達成しクローズ済み。本 Spec はこの訂正済み前提で設計している (`/spec` Step 6「Issue 本文 vs 実装齟齬検出」による検出、SPEC_DEPTH=light のため Notes 記録のみ、ユーザ確認は省略)
- **サンプル件数の解釈**: Issue 本文の「3〜5件サンプリング」を Sonnet 4.6 / Sonnet 5 各コホート 3〜5件 (合計 6〜10件) と解釈した。両コホート比較が目的のため、母集団を分割せず合算 3〜5件では一方のコホートが0件になるリスクがある
- **代理指標の限界**: 4指標のいずれも `/verify` 専用の計装 (wall-clock やユーザ介入回数の記録) は存在しない (`docs/sessions/*/events.jsonl` の `phase_start`/`phase_complete` イベントは `spec`/`code`/`review`/`merge` のみが対象で `verify` は対象外 — `run-verify.sh` が #485 で削除され in-session 実行に変わったため) 。レポートの数値は GitHub Issue タイムライン・コメントからの近似値であり、真の wall-clock や interactive プロンプト回数の正確な計測ではない。この限界をレポートの測定シナリオ節に明記すること
- **カットオーバー日時の精度**: 2026-06-30 前後数時間以内に verify コメントが投稿された Issue は、実行時刻の Sonnet 4.6/5 判定が曖昧なため、コホートから除外するか個別に注記することを推奨する
- 関連: `docs/reports/claude-sonnet-5-impact-strategy.md` §4.1 (decision matrix) / §4.5 (delegated to #877) / §8 (candidate issues) 、`docs/reports/claude-fable-5-impact-strategy.md` §4.3 (de-prescription audit 先例) 、`docs/translation-workflow.md` § Exclusions により `docs/reports/` は ja mirror 対象外 (追加作業不要)
