# Issue #903: context-budget: watchdog timeout 再校正 / prompt slimming 検討 (Sonnet 5 tokenizer 実測 1.3-1.4× を受けて、#878 follow-up)

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — 非対話モード自動解決ログ3件 (再校正対象定数のスコープ限定、wall-clock サンプル数 n=3、据え置き判定基準80%マージン) を確認。いずれも Issue 本文に既に反映済みで新規アクションなし。Size=M のため sub-issue 分割は不要と判断済み / https://github.com/saitoco/wholework/issues/903#issuecomment-4884094272

## Overview

#878 (`docs/reports/sonnet-5-tokenizer-impact.md`) の実測により、Sonnet 4.6 → Sonnet 5 移行に伴うトークナイザー変更の影響 (raw total-token 比 p95=1.413、判定基準 1.15× を明確に超過) が確認された。本 Issue はその follow-up として、(A) `scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_CODE_DEFAULT` (3600) / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` (2000) の再校正要否を実測に基づき判断し、(B) `/audit auto-session` の events.jsonl 集計 prompt と `/issue`/`/review` の L/XL parallel investigation sub-agent input という2件の prompt slimming 候補について検討結果を記録する。

再校正対象は `WATCHDOG_TIMEOUT_CODE_DEFAULT` / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` の2定数に限定する (`WATCHDOG_TIMEOUT_SPEC_DEFAULT` / `WATCHDOG_TIMEOUT_ISSUE_DEFAULT` / `WATCHDOG_TIMEOUT_MERGE_DEFAULT` はスコープ外。Issue本文の Auto-Resolve Log で確定済み)。

## Changed Files

- `docs/reports/sonnet-5-watchdog-recalibration.md`: new file — `/code`・`/review` の wall-clock 実測データ (各 n≥3) と、prompt slimming 候補2件の検討結果を記録するレポート (`docs/reports/sonnet-5-tokenizer-impact.md` と同様の構成: Background/測定手順/結果表/判断)
- `docs/tech.md`: § Architecture Decisions の "Watchdog timeout calibration" 記述近傍に、再校正判断 (実施/据え置き + 変更値または根拠) と prompt slimming 検討結果の要約を追記。上記レポートへのリンクと `#903` の明記、`prompt slimming` という語の明記を含める
- `docs/ja/tech.md`: 上記 `docs/tech.md` 追記の日本語ミラー同期 (`docs/translation-workflow.md` の Sync Procedure に準拠)
- `scripts/watchdog-defaults.sh`: [条件付き — 実測でマージン20%未満と判明した場合のみ] `WATCHDOG_TIMEOUT_CODE_DEFAULT` / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` を比例的 (~1.3-1.4×) に引き上げ。据え置き判断の場合は変更なし
- `tests/watchdog-defaults.bats`: [条件付き — `WATCHDOG_TIMEOUT_CODE_DEFAULT` の値を変更した場合のみ] 125行目 `@test "load_watchdog_timeout uses WATCHDOG_TIMEOUT_CODE_DEFAULT=3600 when phase is code"` のテスト名と assertion (`[ "$output" = "3600" ]`) を新しい値に更新。bash 3.2+ compatible を維持

## Implementation Steps

1. `/code` と `/review` の wall-clock を Sonnet 5 で実測する (各フェーズ最低3件、n=3)。[実装時に変更: 新規のダミー実行はコスト・副作用の観点で不適切と判断し、GitHub Issue/PR タイムライン (`phase/*` label 適用タイムスタンプ、`/review` の自動レビューサマリコメント timestamp) から Sonnet 5 リリース (2026-06-30) 以降の実際の本番実行 wall-clock を再構成する方式に変更 (#877 のログベース手法と同じ精神)。結果 code n=10・review n=9 を確保。詳細は Code Retrospective 参照] 実測データを新規レポート `docs/reports/sonnet-5-watchdog-recalibration.md` に記録する (→ 受け入れ基準1・2の根拠データ)
2. Step 1 の実測値に、Issue 本文で確定済みの判定基準 (実測 wall-clock がタイムアウト値の80%未満 → 据え置き、80%以上 → ~1.3-1.4× の比例引き上げを検討) を `WATCHDOG_TIMEOUT_CODE_DEFAULT` / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` それぞれに適用して判断する。引き上げが必要な場合は `scripts/watchdog-defaults.sh` の該当定数を更新し、`WATCHDOG_TIMEOUT_CODE_DEFAULT` を変更した場合は `tests/watchdog-defaults.bats` 125行目の期待値も同時に更新する (after 1) (→ 受け入れ基準1・2)
3. prompt slimming 候補2件 (`/audit auto-session` の events.jsonl 集計 prompt — `skills/audit/SKILL.md` auto-session Subcommand、`/issue`/`/review` の L/XL・full mode parallel investigation sub-agent input — `skills/issue/SKILL.md` Step 12a-12c と `skills/review/SKILL.md` の review-spec/review-bug 起動箇所) について現行実装を確認し、抜粋・要約方式の採用可否を判断する。判断結果 (採用する場合はアプローチ概要、不要と判断した場合はその根拠) を Step 1 のレポートに記録する (parallel with 1, 2) (→ 受け入れ基準3・4)
4. Step 2 (再校正判断) と Step 3 (prompt slimming 判断) の結論を `docs/tech.md` § Architecture Decisions の "Watchdog timeout calibration" 記述近傍に追記する。`#903` の明記、`prompt slimming` という語の明記、Step 1 のレポートへのリンクを含める (after 2, 3) (→ 受け入れ基準1-4)
5. `docs/translation-workflow.md` の Sync Procedure に従い、`docs/ja/tech.md` を Step 4 の追記内容で同期する (after 4)

## Verification

### Pre-merge

- <!-- verify: rubric "watchdog timeout 定数の再校正を実施した場合はその変更値と根拠、据え置いた場合はその判断根拠が docs/tech.md § Watchdog timeout calibration に明記されている" --> watchdog timeout 再校正の判断 (実施/据え置き) とその根拠が `docs/tech.md` に記録されている
- <!-- verify: file_contains "docs/tech.md" "#903" --> `docs/tech.md` に本 Issue (#903) を根拠とした追記が存在する (rubric 判定の機械的補助チェック)
- <!-- verify: rubric "prompt slimming の候補 (audit auto-session と L/XL parallel investigation) について検討結果 (実施方針または対応不要の結論) が明記されている" --> prompt slimming 候補2件について検討結果が記録されている
- <!-- verify: file_contains "docs/tech.md" "prompt slimming" --> `docs/tech.md` に prompt slimming の検討結果記述が存在する (rubric 判定の機械的補助チェック)

### Post-merge

なし

## Notes

- 再校正対象は `WATCHDOG_TIMEOUT_CODE_DEFAULT` / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` の2定数に限定 (Issue本文 Auto-Resolve Log で確定済み。`SPEC`/`ISSUE`/`MERGE` 定数はスコープ外、必要になれば別 Issue で扱う)
- wall-clock 再測定のサンプル数は各フェーズ最低3件 (n=3) (Issue本文 Auto-Resolve Log で確定済み。#878 の n=9 実測と同一粒度)
- 「現行値で十分な余裕がある」の定量判定基準: 実測 wall-clock がタイムアウト値の80%未満 (マージン20%以上) に収まること (Issue本文 Auto-Resolve Log で確定済み)
- `scripts/get-auto-session-report.sh` は `watchdog-defaults.sh` を直接 source しているため (24行目)、`WATCHDOG_TIMEOUT_CODE_DEFAULT` / `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` の値変更は同ファイル経由で自動反映される。同ファイル自体の直接編集は不要 (grep で確認済み — 27-28行目の `${VAR:-1800}` 等のフォールバック値は source 成功時は評価されない dead path であり、本 Issue のスコープ外の既存差異)
- `docs/structure.md` / `docs/ja/structure.md` の `watchdog-defaults.sh` 説明文は定数の役割記述のみで具体的な値を含まないため、値変更のみでは更新不要 (grep で確認済み)
- Issue body の記載 (#878 実測値、#628 precedent、現行定数値) はすべて実装 (`scripts/watchdog-defaults.sh`、`docs/tech.md`) と整合しており、齟齬は検出されなかった

## Code Retrospective

### Deviations from Design

- Spec の Implementation Steps は「Sonnet 5 で `/code`・`/review` を実際に3件以上ずつ新規実行して wall-clock を測る」ことを前提としていたが、実装では新規の使い捨て実行（本物のブランチ/PR/CI を伴う）を意図的に行うのはコスト・副作用の観点で不適切と判断し、GitHub Issue/PR タイムライン (`phase/*` label 適用タイムスタンプ、`/review` が投稿する自動レビューサマリコメントのタイムスタンプ) から Sonnet 5 リリース (2026-06-30) 以降の実際の本番実行の wall-clock を再構成する方式に変更した。これは #877 (`docs/reports/verify-sonnet-5-remeasurement.md`) が `/verify` の直接起動不可のために採用したログベース手法と同じ精神。結果的に code n=10・review n=9 と、Spec が要求した n≥3 を上回るサンプル数を確保できた。
- review フェーズの計測手法は当初の想定（`events.jsonl` の `phase_start`/`phase_complete` を直接使う）から、実際には過去セッションログが Sonnet 5 リリース後の1セッションにしか存在しなかったため、PR の `createdAt` → 自動投稿される "Review Response Summary" コメントの timestamp を review 期間の近似値として用いる方式に切り替えた。唯一利用可能な clean な `events.jsonl` サンプル (Issue #882 / PR #889: 真値1160秒) でこの近似手法を検証したところ誤差3.6%（近似値1120秒）と十分な精度を確認できたため、残り8件についてもこの近似手法を採用した。

### Design Gaps/Ambiguities

- Issue #882 の code フェーズ label 区間 (`phase/code`→`phase/review`) は、`events.jsonl` を確認すると内部の silent-no-op auto-retry が2回発生しており、単一の watchdog window に対応する時間ではなかった（3回分の試行が積み重なっていた）。この1件は code フェーズの実測データセットから除外し、Notes に理由を明記した。同種の除外判断が必要になるケースが今後も起こりうるため、`docs/reports/sonnet-5-watchdog-recalibration.md` の Notes セクションに判断根拠を明記した。
- `docs/guide/customization.md` の `watchdog-timeout-code-seconds` フォールバック値の記載 (`1800`) が、実装済みの実際の `WATCHDOG_TIMEOUT_CODE_DEFAULT` (変更前 `3600`) と既に不整合であることを発見した。この既存の drift は本 Issue のスコープ外だが、同じ行を本 Issue の変更で更新する必要があったため、ついでに正しい新値 (`4680`) に修正した（据え置きではなく、修正後の正しい値で記載）。

### Rework

- なし（実装手順の逸脱は上記2件のみで、手戻りは発生しなかった）

## review retrospective

### Spec vs. implementation divergence patterns

- Spec の Changed Files 列挙外だった `docs/guide/customization.md` / `docs/ja/guide/customization.md` の変更は、Code Retrospective に理由が明記されており実質的な乖離ではなかった。ただし、その修正自体が同一ファイル内の**参照テーブル行のみ**を対象とし、同じ値を記載した別の箇所 (コメントアウト済みサンプル設定ブロック、52-53行目 / 46-47行目) が更新対象から漏れていた。「1つの設定値が同一ドキュメント内に複数箇所存在し、片方だけ更新される」というパターンは今後も再発しうる (SHOULD で指摘・修正済み)。

### Recurring issues

- 今回検出した issue は上記1件 (根本原因は共通) のみで、workflow 改善が必要となるような重複パターンは見られなかった。

### Acceptance criteria verification difficulty

- 4条件すべて `rubric` / `file_contains` の verify command で明確に PASS 判定でき、UNCERTAIN は0件だった。verify command の記述自体も実装 (`docs/tech.md` の `#903` / `prompt slimming` という語の明記) と過不足なく対応しており、改善提案なし。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST issueは無し。SHOULD 1件 (`docs/guide/customization.md` / `docs/ja/guide/customization.md` のコメントアウト済みサンプル設定ブロックが旧値のまま) を検出し、`4680`/`2600` に修正・push済み。
- 当該指摘はこのPRのdiffが触れていない行のため `gh-pr-review.sh` のインライン行コメントが `Line could not be resolved` で失敗し、General Comments (レビュー本文) に振り替えて投稿した。
- Spec Changed Files 列挙外の2ファイル変更 (既存drift修正) は CONSIDER として記録のみで対応不要と判断。

### Deferred Items
- `/auto` L3 auto-retrospective "notable judgment" ステップの events.jsonl 生読み込みを jq 集計サマリに置き換える改善は、引き続き follow-up Issue として別途起票が必要 (本 Issue のスコープ外、code フェーズからの引き継ぎ事項)。

### Notes for Next Phase
- `/merge 912` 実行時、追加コミット (f5b989da, ドキュメントのサンプル値同期) が含まれることを確認。CIは全ジョブSUCCESS、再チェック (bats 11/11、validate-skill-syntax 0 errors、forbidden-expressions) もPASS済み。
