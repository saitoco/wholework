# Issue #878: context-budget: Sonnet 5 tokenizer 変更 (1.0-1.35×) の watchdog/context budget 影響測定

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (triage 判断根拠: Type=Task/Size=S/Value=3、Background 事実確認 (`WATCHDOG_TIMEOUT_ISSUE_DEFAULT` 実在確認、Step 番号ドリフト訂正)、Acceptance Criteria 新規追加の経緯、Auto-Resolved Ambiguity Points 要約、Dependency check #876 解消済み、Sub-issue splitting 非対象) / https://github.com/saitoco/wholework/issues/878#issuecomment-4882960653

## Overview

Sonnet 5 (2026-06-30 リリース) のトークナイザー変更 (同一入力が最大 1.35× のトークン数にマップされ得る) が、Wholework の watchdog timeout 校正値 (`scripts/watchdog-defaults.sh`) および context budget 前提に与える実務上の影響を実測し、`docs/reports/sonnet-5-tokenizer-impact.md` として報告する。判定基準 (p95 token 比 1.15× 超で有意) に基づき、watchdog 再校正 + prompt slimming の follow-up Issue 起票、または「対応不要」の結論のいずれかを導く。

本 Issue は `docs/reports/claude-sonnet-5-impact-strategy.md` §4.1/§4.4/§8 で「default parent (Sonnet 4.6 → Sonnet 5) 切替の2大ブロッカー」の一つとして位置づけられている (もう一方は #877 、`/verify` interactive 摩擦再測定は既に NO-GO 判定・follow-up #902 起票済み) 。

## Changed Files

- `docs/reports/sonnet-5-tokenizer-impact.md`: new file — Sonnet 4.6 vs Sonnet 5 の tokenizer 影響測定レポート

## Implementation Steps

1. 実測手法の実現可能性を確認する: (a) Sonnet 4.6 の日付固定 model ID が `claude -p --model <id> --output-format json` で直接呼び出し可能か試験する、(b) `docs/sessions/*/events.jsonl` の既存 `token_usage` イベント (`modules/event-emission.md` 定義) の実データを確認する。確認済みの制約: `token_usage` は `code`/`review`/`merge` phase の wrapper 単位でのみ発生し `spec`/`audit` は対象外 (`docs/reports/event-log-schema.md` に「spec phase is excluded as it is called directly」と明記、`/audit` は run-*.sh wrapper 自体を持たない) 。また実データ確認済みの制約として、`token_usage` イベントの `model` フィールドは全サンプルで `"unknown"` (`run-auto-sub.sh` の `jq -r '.model // empty'` 抽出が空値になっている) 。よってログ経由でコホート分離する場合は #877 と同様に 2026-06-30 の日時カットオーバーに拠る。結果をレポート Background に記録する (→ 受入条件 AC1, AC2)
2. 手順1(a)が可能な場合: 3種のコンテンツタイプ (`/spec` prompt = 実際の Issue 本文 + docs 抜粋、`/review` review-bug sub-agent input = 実際の PR の git diff + 変更ファイル内容、`/audit auto-session` prompt = 実際の `events.jsonl` 抜粋) それぞれについて代表サンプルを3〜5件収集し、Sonnet 4.6 / Sonnet 5 の両方で `claude -p --output-format json` を実行して `.usage.input_tokens` を比較する。手順1(a)が不可能な場合: `docs/sessions/*/events.jsonl` の `token_usage` イベント (`input_tokens` + `cache_read_tokens` 合算) を 2026-06-30 前後 (当日分は除外) でコホート分割し、ログ対象の `code`/`review`/`merge` phase についてのみ比較する。ログ対象外の `/spec`・`/audit auto-session` は「現行計装では実測不能」として明記する (→ 受入条件 AC2)
3. `docs/reports/sonnet-5-tokenizer-impact.md` を既存の `docs/reports/*.md` 構成 (Background / 測定シナリオ / 結果 / 判定 / Notes) で作成する。Background に手順1で判明した制約 (token_usage の phase 対象範囲、model フィールドの不備) を記載し、結果節に content-type 別の median/p95/max token 比 (または「実測不能」の明記) を記載する (→ 受入条件 AC1, AC2)
4. 判定節で Issue 本文 §B の基準 (p95 token 比が **1.15×** を超過 → 有意、watchdog 再校正 + prompt slimming の follow-up Issue 起票を推奨。1.15× 以下 → 対応不要) に基づき判定し、レポートに閾値 "1.15" を明記する。あわせて Workflow tool の `budget.total` はユーザ指定のハード上限であり、トークナイザー変化に対する自動的な余裕係数は組み込まれていない旨を Notes 節に記載する (→ 受入条件 AC3)
5. 判定結果に応じて `gh issue create` で watchdog 再校正 / prompt slimming の follow-up Issue を作成する、または判定が「対応不要」の場合はレポートにその結論を明記して完了する (→ 受入条件 AC4)

## Verification

### Pre-merge
- <!-- verify: file_exists "docs/reports/sonnet-5-tokenizer-impact.md" --> `docs/reports/sonnet-5-tokenizer-impact.md` が作成されている
- <!-- verify: rubric "docs/reports/sonnet-5-tokenizer-impact.md に、/spec prompt (Issue body + docs excerpts)・/review review-bug sub-agent input・/audit auto-session events.jsonl 集計 prompt の3種について、Sonnet 4.6 と Sonnet 5 の input token 比 (median, p95, max) の実測比較結果が content-type 別内訳とともに記載されている" --> レポートに測定シナリオ (§A) で定義された3種の prompt の Sonnet 4.6 vs Sonnet 5 token 比較結果が記録されている
- <!-- verify: rubric "docs/reports/sonnet-5-tokenizer-impact.md に watchdog timeout 再校正の要否について、p95 token 比 1.15× を有意閾値とした判定結果とその根拠が明記されている" --> <!-- verify: file_contains "docs/reports/sonnet-5-tokenizer-impact.md" "1.15" --> レポートに判定基準 (§B) に基づく watchdog 再校正要否の判定結果と根拠が明記されている
- <!-- verify: rubric "判定結果に応じて watchdog timeout 再校正または prompt slimming の follow-up Issue の作成、または「対応不要」の明記のいずれかが行われている" --> 判定結果に応じて follow-up Issue 作成、または対応不要の結論が記載されている

### Post-merge

なし

## Notes

- **Auto-Resolved Ambiguity Points (Issue 本文より継承、3件)**: (1) AC 全体が本文に存在しなかったため #877 の AC パターン (レポート作成 + rubric 判定 + follow-up 分岐) を踏襲して新規作成、(2) 「有意」閾値は本文で既に例示されていた p95 token 比 **1.15×** をそのまま確定値として採用、(3) Post-merge セクションは「なし」で確定 (watchdog 再校正の実施自体は判定結果次第の条件付き作業のため follow-up Issue のスコープとした) 。詳細な却下理由は Issue 本文末尾を参照
- **Issue body vs 既存実装の齟齬 (Step 6 で検出)**: Issue 本文 Proposal §A は `/spec` prompt・`/review` review-bug sub-agent input・`/audit auto-session` events.jsonl 集計 prompt の3種を測定対象として名指ししているが、既存の `token_usage` イベント計装 (`modules/event-emission.md`) は `code`/`review`/`merge` phase の wrapper 単位でのみ発生し、`spec` は明示的に対象外 (`docs/reports/event-log-schema.md` に "spec phase is excluded as it is called directly" と明記) 、`/audit` は run-*.sh wrapper を持たないため計装自体が存在しない。加えて実データ確認の結果、`token_usage` イベントの `model` フィールドは確認した全サンプルで `"unknown"` だった (`run-auto-sub.sh` の `.model` 抽出が空値になる既知の制約) 。したがって Implementation Steps は「日付固定 model ID による直接比較」を優先し、不可能な場合のみ既存ログ (日時カットオーバー方式、#877 precedent) にフォールバックする設計とした。SPEC_DEPTH=light のため本項目はユーザ確認を省略し Notes 記録のみとする
- **`docs/reports/` は ja mirror 対象外**: `docs/translation-workflow.md` 21行目 (`docs/reports/` — Audit and optimization reports (not translated)) で確認済み。ja 翻訳ファイルの追加作業は不要 (#877, #876 と同一の扱い)
- 関連: `docs/reports/claude-sonnet-5-impact-strategy.md` §4.1 (decision matrix) / §4.4 (tokenizer impact delegated to #878) / §8 (candidate issues) 、`docs/spec/issue-877-verify-sonnet-5-remeasurement.md` (同系列 precedent — コホート日時カットオーバー方式と代理指標限界明記パターンを継承) 、`scripts/watchdog-defaults.sh` (現行 timeout 定数) 、`modules/event-emission.md` / `docs/reports/event-log-schema.md` (token_usage イベント仕様)
