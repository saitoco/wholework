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

## Autonomous Auto-Resolve Log

- **[phase/ready ラベル欠如のまま実装続行]** — reason: Step 3 の `phase/ready` チェックで対象ラベルが存在しなかった (`triaged`, `phase/code` のみ) が、Spec ファイル (`docs/spec/issue-878-sonnet-5-tokenizer-impact.md`) は既に存在し設計内容も完備していたため、非対話モードの auto-resolve ポリシーに従い Spec に基づいて実装を継続した。`reconcile-phase-state.sh --check-precondition code-patch 878` も `matches_expected: false` を返したが、診断内容はラベル状態のみを指摘しており `spec_file` は検出済みだった。
  - Other candidates: 実装を中断し `/spec 878` の再実行を促す (却下: Spec は既に完成しており再実行の必要がないため、non-interactive モードでの中断はワークフロー完走率を不必要に下げる)

## Code Retrospective

### Deviations from Design

- なし。Implementation Steps 1〜5 の順序・方法論どおりに実施した (手順1(a) の日付固定 model ID 直接比較が可能だったため、手順1(b) のログベースコホート方式へのフォールバックは不要だった) 。

### Design Gaps/Ambiguities

- **`.usage.input_tokens` 単体では tokenizer 比較に不十分だった**: Spec Implementation Step 2 は「`.usage.input_tokens` を比較する」と指定していたが、実際には Anthropic API のプロンプトキャッシュにより `input_tokens` は「直前のキャッシュ済みプレフィックスとの差分 (marginal)」のみを表す小さな値になり、システムプロンプト/メモリ由来の大きな固定オーバーヘッドが `cache_creation_input_tokens` / `cache_read_input_tokens` に計上されることが判明した。そのため実装では3フィールドの合計 (`input_tokens + cache_creation_input_tokens + cache_read_input_tokens`) を「そのターンが処理した総トークン数」として採用し、raw total 比 (プロンプト全体) と baseline 差分による content-only 比の2指標を併記した。raw total 比のほうが Anthropic 公表値 (1.0-1.35×) に近く安定していたため主指標として採用し、content-only 比は小サンプルでノイズが大きいことを明記した。
- **CWD がシステムプロンプトの動的セクションに影響する未知の交絡要因だった**: measurement harness の baseline を異なる CWD (`/tmp`) から再測定したところ、同一モデル・同一空プロンプトでも異なるトークン総数が得られた (`claude --help` の `--exclude-dynamic-system-prompt-sections` の説明どおり、cwd/git status/memory paths がシステムプロンプトに動的挿入されるため) 。全計測を worktree の固定 CWD から実施することで対処し、baseline の再現性 (2回とも同一値) を確認した。この制約は Spec に事前記載がなかったため、実装中に発見し report の Notes に記録した。
- **無制限ツール実行が測定を汚染するリスクが判明した**: 初回の計測試行で `--disallowedTools` を指定しなかったところ、モデルがコンテンツ中のファイルパス言及に反応して agentic にツールを使用し、1サンプルのみ 557k トークンという明らかな外れ値を生じた。`--disallowedTools "*"` を追加して単一ターン応答に固定することで解消した。

### Rework

- 上記の無制限ツール実行による外れ値混入により、measurement harness (`.tmp/measure-tokens.sh`) を1回作り直して再実行した (`--disallowedTools "*"` 追加)
- macOS 標準 bash (3.2) が連想配列 (`declare -A`) を非サポートのため、`declare -A EVENT_FILES=(...)` を使った初回実装が `unbound variable` エラーで失敗し、並列配列 (`EVENT_LABELS` / `EVENT_PATHS`) 方式に書き換えた

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 手順1(a) (日付固定 model ID `claude-sonnet-4-6` / `claude-sonnet-5` の直接呼び出し) が feasible だったため、#877 が採用したログベースのコホート/カットオーバー方式ではなく、同日内での直接 side-by-side 比較を採用した。これにより日毎の活動内容差異という交絡要因を排除できた
- 指標は raw total-token 比 (プロンプト全体、Anthropic 公表値に最も近く安定) を主指標、baseline 差分による content-only 比を副指標として両方併記した
- 判定は raw p95=1.413、content-only p95=2.596 のいずれも閾値 1.15× を明確に超過したため「有意」とし、follow-up Issue #903 (watchdog 再校正 + prompt slimming 検討) を起票した

### Deferred Items
- watchdog timeout 定数の実際の再校正作業 (`scripts/watchdog-defaults.sh` の値変更) は判定結果次第の条件付き作業のため #903 のスコープとし、本 Issue では実施しない
- `/audit auto-session` と L/XL parallel investigation の prompt slimming 具体案の検討も同様に #903 に委譲

### Notes for Next Phase
- `/review` フェーズでは #903 起票が「判定結果に応じた follow-up Issue 作成」の AC を正しく満たしているか、および raw/content-only 2指標の使い分けの説明が rubric 上十分に明記されているかを重点確認してほしい
- measurement harness (`.tmp/measure-tokens.sh` 等) は `.tmp/` (gitignore 対象) にのみ存在し、コミットには含まれていない — レポート (`docs/reports/sonnet-5-tokenizer-impact.md`) 自体に再現手順を明記済み

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC を rubric + file_contains の多層構成 (AC3 は判定文言の rubric と "1.15" の literal 両方) にした設計は verify で機械的かつ堅牢に検証でき、条件品質は高かった
- spec が「日付固定 model ID の直接呼び出しが feasible」であることを事前確認し、Issue Proposal §A のログベース cohort 方式より強い直接 side-by-side 方式に設計変更した。これが交絡排除に直結し、#877 の小サンプルノイズ問題を回避できた

#### design
- Size S / light depth は妥当だった。調査過程で計装ギャップ (token_usage が code/review/merge のみ、`model` フィールドが常に "unknown") を検出し、実測手法を実現可能な形に調整できた

#### code
- 測定過程で 2 つの交絡要因 (CWD 依存の system-prompt セクション差、agentic tool-use による token 膨張) を検出・排除し、`--disallowedTools "*"` + CWD 固定で決定論的な測定を実現した。手戻り (fixup/amend) なし
- 測定 harness を `.tmp/` に留めコミットしない代わりにレポートへ再現手順を明記した判断は、gitignore 規約と再現性の両立として妥当

#### review
- patch route (Size S) のため /review はスキップ。verify が rubric で最終品質を担保

#### merge
- patch route の main 直コミット。conflict なし

#### verify
- 全 pre-merge AC が file_exists/rubric/file_contains で PASS。verify command の不整合なし。1st-attempt PASS (auto-retry 発火なし)

### Improvement Proposals
- **token_usage イベントの `model` フィールドが常に `"unknown"` になっている計装バグ**: #877・#878 の両測定 Issue で独立に確認された。`run-auto-sub.sh` の `.model` 抽出が非機能状態のため、`docs/sessions/*/events.jsonl` の全 token_usage イベントで実 model ID が記録されず、ログベースの model-cohort 分析 (Sonnet 4.6 vs 5 の実データ比較等) が不可能になっている。両 Issue はこのギャップを直接測定・日時カットオーバーで回避したが、計装が機能していれば将来の同種計測が大幅に簡略化される。`run-auto-sub.sh` の token_usage emit 経路で実 model ID を記録するよう修正することを提案する (複数 Issue で再発性が確認された構造的問題)
