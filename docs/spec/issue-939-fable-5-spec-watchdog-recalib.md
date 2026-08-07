# Issue #939: watchdog: spec/review timeout 再校正判定 (Fable 5/Opus 5 実測、#556 follow-up)

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (`/issue` フェーズ) — 曖昧点3件の自動解決ログ (① 実測件数・対象は実装裁量の代表 Issue 数件、② SPEC_DEFAULT 変更を本 Issue 内で実施、③ 計測手段は既存 instrumentation (`silent_window` イベント + `/audit auto-session`) 限定・新規機構は作らない) と AC 設計補足 (post-merge は `observation event=watchdog-kill` ではなく `opportunistic` を採用、`github_check "gh pr checks"` は Size M/PR route 前提、`file_contains "#556"` は起票時点で未存在を確認済み) を確認。いずれも Issue 本文に既に反映済みで、本 Spec で新規に対応すべきアクションはなし。/ https://github.com/saitoco/wholework/issues/939#issuecomment-4886097163
- saito / MEMBER / first-class / Issue Retrospective (2026-08-07、`/verify` 2回連続 FAIL 後の AC 見直し) — 曖昧点3件の自動解決ログ (① AC1/AC2 の実測エビデンス範囲を `--fable` 限定から `--fable` または `--opus` のいずれも許容に拡大、② REVIEW_DEFAULT 実測 (2026-08-06, #1058/PR#1201) の Issue 内 AC 化、③ Issue タイトルの scope 整合性更新)。本 Spec の Overview/Implementation Steps/Verification は全てこの AC 改訂を前提に再設計した。/ https://github.com/saitoco/wholework/issues/939#issuecomment-5216528644
- saito / MEMBER / first-class / verify-fail marker (2026-07-05、iteration=1、cross-phase exception により cutoff 以前だが consume 対象) — `--fable` 未実行を理由とする AC1/AC2 FAIL の記録。内容は下記 `## Code Retrospective` / `## Verify Retrospective` に既に反映済みで、本 Spec で新規に対応すべきアクションはなし。/ https://github.com/saitoco/wholework/issues/939#issuecomment-4886569817

- saito / MEMBER / first-class / <!-- wholework-event: type=verify-fail phase=verify issue=939 iteration=1 --> / https://github.com/saitoco/wholework/issues/939#issuecomment-4886569817
## Overview

`scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800` は #556 (base 1800→2700) でも #903 (Sonnet 5 再校正、CODE/REVIEW のみ) でもスコープ外のまま据え置かれてきた。前回の本 Issue 実装サイクル (PR #944) は `--fable` の新規実測実行を非対話環境でのコスト・副作用への懸念から見送り、`docs/tech.md` / `docs/reports/watchdog-recovery-strategy.md` に「実測なし・deferred」を記録した結果、対応する2件の Pre-merge AC (AC1・AC2) が `/verify` で2回連続 FAIL した。

2026-08-07 の Issue Retrospective により、AC1・AC2 の許容エビデンス範囲が `--fable` 限定から「`--fable` または `--opus`」に拡大された。`--opus` は `/auto` が Size L の spec dispatch に自動付与する経路であり、同じ `WATCHDOG_TIMEOUT_SPEC_DEFAULT` 予算を共有しながら、新規実行や追加コスト認可を必要とせず継続的に実トラフィックを生成している。本 Spec はこの `--opus` 実トラフィックを `.tmp/auto-events.jsonl` から抽出・分析することで、前回サイクルの deadlock (`--fable` 明示認可待ち) を経ずに実測に基づく判定を完了させる。判定結果 (変更/据え置き) とその根拠は `docs/tech.md` § Watchdog timeout calibration に記録し、実測結果自体は `docs/reports/watchdog-recovery-strategy.md` § Fable 5 long-turn findings に追記する。

あわせて、2026-08-06 に実測された `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` (2600s) の不足 (Issue #1058 / PR #1201: watchdog kill 後、`.wholework.yml` の project-local override 5400s で完走) についても、同じ校正判断枠組みで判定・記録する (新規 AC3)。AC4〜AC7 (`watchdog-defaults.sh` コメント更新・bats green) は前回サイクル (PR #944) で既に達成済みのため、本サイクルでは変更しない。

## Changed Files

- `docs/reports/watchdog-recovery-strategy.md`: `## Fable 5 long-turn findings` に「2026-08 re-measurement (Issue #939)」のサブセクションを新規追加し、`--opus` 実トラフィックの実測結果 (方法論・件数・統計値・watchdog kill 有無) を記録する。既存の「2026-07 re-measurement」サブセクション (`--fable` 実測ゼロ) は変更せず残す
- `docs/tech.md`: § Architecture Decisions の "Watchdog timeout calibration" 記述内、既存の `#939` 節を実測に基づく「据え置き」判定 (SPEC_DEFAULT) に置き換える。あわせて新規ブロックを追加し `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` を 2600→5400 に引き上げる判定・根拠 (#1058/PR#1201 実測) を記録する。`#1201` を明記 (file_contains 補助チェック対象)
- `docs/ja/tech.md`: 上記 `docs/tech.md` 追記の日本語ミラー同期 (`docs/translation-workflow.md` の Sync Procedure に準拠。code fence 数の一致を確認)
- `scripts/watchdog-defaults.sh`: `WATCHDOG_TIMEOUT_REVIEW_DEFAULT` を `2600` → `5400` に変更し、Recalibration guidance コメントブロックに根拠 (#1201, 2026-08) を追記する。base 2700/#556 由来注記 (9行目付近) は既に PR #944 で更新済みのため変更しない。bash 3.2+ compatible を維持
- `tests/watchdog-defaults.bats`: 125行目付近の `code` フェーズ用テスト (`@test "load_watchdog_timeout uses WATCHDOG_TIMEOUT_CODE_DEFAULT=4680 when phase is code"`) と同型の `review` フェーズ用 `@test` (期待値 `5400`) を新規追加する。bash 3.2+ compatible を維持
- `docs/structure.md` / `docs/ja/structure.md`: [確認済み・変更不要] `watchdog-defaults.sh` の説明文 (215行目 / 207行目) は役割記述のみで具体的な値を含まないため、値変更のみでは更新不要 (`grep -n "watchdog-defaults" docs/structure.md docs/ja/structure.md` で確認済み)

## Implementation Steps

1. `.tmp/auto-events.jsonl` (メインリポジトリ、worktree 外) から spec フェーズの `--opus` 実トラフィック実測を抽出する: `event=="sub_start" and size=="L"` の (issue, session_id) と `event=="max_silent_window" and phase=="spec"` の (issue, session_id, max_sec) を同一 issue+session_id で join し、`--opus` dispatch と確定した spec 実行のみを対象にする (methodology は `docs/tech.md` `#1064` エントリと同一。再現コマンドは Notes 参照)。本 Spec 作成時点の実測結果: N=20 (2026-06-28〜2026-08-07)、min 660s / mean 978.5s / p95 1340s (74.4%) / max 1460s (81.1% of 1800s)、post-Opus-5 (2026-07-24〜) 部分集合 N=11 max 1340s (74.4%)、`phase=="spec"` の `watchdog_kill` は0件。`/code` はこの抽出を再実行し、新規実行が追加されていれば統計値を更新する (→ 受け入れ基準1・2)
2. Step 1 の実測結果を `docs/reports/watchdog-recovery-strategy.md` § Fable 5 long-turn findings に「2026-08 re-measurement (Issue #939)」の新規サブセクションとして追記する (方法論・件数・統計値・watchdog kill 有無を含む)。既存の「2026-07 re-measurement」サブセクションは変更せず残す (after 1) (→ 受け入れ基準1)
3. `docs/tech.md` § Watchdog timeout calibration の既存 `#939` 節を、Step 1 の実測に基づく「据え置き (maintain `WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800`)」判定文に置き換える。根拠: p95 (74.4%) は #903 の80%閾値未満であり、唯一80%を超える max (81.1%) も Opus 5 以前の単発サンプル (2026-07-05) で、post-Opus-5 部分集合は 74.4% どまり — #903 のレビュー実測 (100.2% で1件が既に上限到達) のような強いシグナルではない。`docs/ja/tech.md` を同期する (after 1) (→ 受け入れ基準2)
4. `docs/tech.md` § Watchdog timeout calibration に新規ブロックを追加し、`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` を 2600→5400 に引き上げる判定を記録する。根拠: 2026-08-06 実測 (Issue #1058 / PR #1201) — 2600s で `watchdog_kill` (silent_window_sec=2600) 後、`.wholework.yml` override 5400s で `max_silent_window=4110s` (76.1%)・総所要 ~4300s (4303s) で完走。同じ #903 style の ×1.3 (観測実測値 4110s × 1.3 ≈ 5343s) でも同水準の値が導かれ、既に本番検証済みの override 値 (5400s) と整合する。ただし同日の Issue #1214 / PR #1216 も 5400s ちょうどで kill され、即座の再実行は 1250s (23.1%) で完了した点を「stuck/hang による kill の可能性が高く、さらなる引き上げの根拠にはしない」注記として併記する。`#1201` を明記する (`file_contains "docs/tech.md" "#1201"` を充足)。`docs/ja/tech.md` を同期する (parallel with 3) (→ 受け入れ基準3)
5. `scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_REVIEW_DEFAULT=2600` を `5400` に変更し、Recalibration guidance コメントブロックに Step 4 と同じ根拠 (#1201, 2026-08) を追記する。`tests/watchdog-defaults.bats` に review フェーズ用の新規 `@test` (125行目付近の code フェーズ用テストと同型、期待値 `5400`) を追加し、`bats tests/watchdog-defaults.bats` のローカル実行で green を確認する (after 4) (→ 受け入れ基準3・7)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/watchdog-recovery-strategy.md の Fable 5 long-turn findings (または隣接する再計測サブセクション) に、--fable または --opus 経由の spec phase 実トラフィックの実測結果 (実行件数、max silent window、watchdog kill 有無) が 2026-07 以降の再計測として記録されている" --> `--fable` または `--opus` 経由の spec 実行の実測結果がレポートに記録されている

  Implementation Steps 1・2 で追加する「2026-08 re-measurement」サブセクションで充足する。
- <!-- verify: rubric "WATCHDOG_TIMEOUT_SPEC_DEFAULT (1800s) の引き上げ要否の判定 (変更/据え置き) と、--fable または --opus 経路いずれかの実測に基づく根拠が docs/tech.md の watchdog timeout calibration 項に記録されている" --> SPEC_DEFAULT 再校正の判定と根拠が `docs/tech.md` に記録されている

  Implementation Step 3 で `#939` 節を実測ベースの「据え置き」判定に更新して充足する。
- <!-- verify: rubric "docs/tech.md の Watchdog timeout calibration 項に、WATCHDOG_TIMEOUT_REVIEW_DEFAULT (2600s) の引き上げ要否の判定 (変更/据え置き) と、2026-08-06 の実測 (Issue #1058 / PR #1201: 2600s で kill、.wholework.yml override 5400s で ~4300s 完走) に基づく根拠が記録されている" --> <!-- verify: file_contains "docs/tech.md" "#1201" --> REVIEW_DEFAULT 再校正の判定と根拠が `docs/tech.md` に記録されている

  Implementation Step 4 で新規ブロックを追加して充足する (「引き上げ」判定、`#1201` を明記)。
- <!-- verify: file_not_contains "scripts/watchdog-defaults.sh" "Sonnet 4.6 / Opus 4.7" --> `watchdog-defaults.sh` コメントの世代参照が現行モデル世代 (Sonnet 5 / Opus 4.8) に更新されている

  PR #944 で達成済み (本サイクルでの追加変更なし)。
- <!-- verify: rubric "scripts/watchdog-defaults.sh のコメントに base WATCHDOG_TIMEOUT_DEFAULT=2700 の由来 (#556 spike での 1800 からの引き上げ) が明記されている" --> base 2700 の由来が注記されている

  PR #944 で達成済み (本サイクルでの追加変更なし)。
- <!-- verify: file_contains "scripts/watchdog-defaults.sh" "#556" --> 由来注記が #556 を参照している

  PR #944 で達成済み (本サイクルでの追加変更なし)。
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが green (SPEC_DEFAULT/REVIEW_DEFAULT 変更時は対応する `tests/watchdog-defaults.bats` のハードコード値更新を含む)

  Implementation Step 5 の新規 bats テスト追加を含め、本サイクルの PR で再度 green を確認する。
- <!-- verify: file_contains "docs/tech.md" "WATCHDOG_TIMEOUT_SPEC_DEFAULT" --> `docs/tech.md` に定数名 `WATCHDOG_TIMEOUT_SPEC_DEFAULT` の言及が存在する (rubric 判定の機械的補助チェック。`modules/verify-patterns.md` §9 の数値・定数名補完ガイドラインに基づき追加。Issue 本文にはない Spec 独自の追加項目 — 詳細は Notes 参照)

### Post-merge

- `/spec --fable` または `/auto` 経由の `--fable`/`--opus` spec 実行時に、watchdog kill が発生せず phase が正常完了することを観察 <!-- verify-type: opportunistic -->

## Notes

- **測定範囲・再現コマンド (`modules/measurement-scope.md` 準拠)**: Implementation Step 1 の実測対象は `.tmp/auto-events.jsonl` (メインリポジトリ、worktree からは非可視。2026-06-14〜のログ全体、ローテーションなし、除外条件なし) で、以下の手順で再現できる:
  ```bash
  # Size=L の sub_start (issue, session_id) を抽出
  grep '"event":"sub_start"' .tmp/auto-events.jsonl | grep '"size":"L"' \
    | grep -o '"issue":[0-9]*,"event":"sub_start","session_id":"[^"]*"' \
    | sed -E 's/"issue":([0-9]+),"event":"sub_start","session_id":"([^"]*)"/\1 \2/' | sort -u
  # phase=spec の max_silent_window (issue, session_id, max_sec) を抽出
  grep '"event":"max_silent_window"' .tmp/auto-events.jsonl | grep '"phase":"spec"' \
    | grep -o '"issue":[0-9]*,"event":"max_silent_window","session_id":"[^"]*","phase":"spec","max_sec":"[0-9]*"' \
    | sed -E 's/"issue":([0-9]+),"event":"max_silent_window","session_id":"([^"]*)","phase":"spec","max_sec":"([0-9]+)"/\1 \2 \3/'
  # 上記2つを (issue, session_id) で inner join し、L-size dispatch と確定した spec 実行のみ抽出
  ```
  本 Spec 作成時点: N=20、値域 [660, 1460] (秒)。`/code` は同じコマンドで再実行し、新規実行が追加されていれば統計値 (min/mean/p95/max) を再計算すること。
- **`max_silent_window` イベントに model タグが存在しない制約 (前回サイクルから継続)**: `scripts/claude-watchdog.sh` が emit するイベントには `model` フィールドが存在しないため、`--opus` dispatch は `sub_start` イベントの `size=="L"` (同一 issue+session_id、`docs/tech.md` `#1064` エントリと同一方法論) を代理指標として使用する。`--fable` は Size に依存しない明示フラグのためこの代理指標では識別できず、2026-07 re-measurement で確立済みの「実測ゼロ (#560 の1件のみ、未計測)」という結論は変わらない。
- **判定基準を #903 と揃えた根拠 (前回サイクルから継続)**: 直近の同種再校正 precedent である #903 (`docs/reports/sonnet-5-watchdog-recalibration.md`) の「実測 ≥80% of timeout → 引き上げ検討 (~1.3倍程度、Icebox #596 のトレードオフに基づき #628 の2倍は採用しない)」をそのまま踏襲した。SPEC_DEFAULT は p95 (74.4%) が閾値未満で「据え置き」、REVIEW_DEFAULT は実測 (4110/2600=158%) が閾値を大きく超過し「引き上げ」——同じ基準を適用しても実測次第で判定が分かれることを示す一対の事例になっている。
- **REVIEW_DEFAULT 引き上げの反証データ (#1214 / PR #1216、透明性のため記録)**: 2026-08-06 の同日、REVIEW_DEFAULT 引き上げ後の 5400s 設定でも `watchdog_kill` が1件発生した (Issue #1214, PR #1216, silent_window_sec=5400=timeout_setting)。ただし即座の再実行は 1250s (23.1% of 5400s) で完了しており、真に追加の計算時間を要したのではなく stuck/hang による kill だった可能性が高い (Icebox #596 の timeout-inflation-vs-stuck-detection トレードオフ)。この1件は「さらなる引き上げの根拠にはしない」と判断し、Implementation Step 4 の docs/tech.md 記述にも明記する。
- **`scripts/get-auto-session-report.sh` の stale fallback (スコープ外の観察)**: 同スクリプト28行目 `SILENT_THRESHOLD_REVIEW=$(( ${WATCHDOG_TIMEOUT_REVIEW_DEFAULT:-2000} - SILENT_MARGIN ))` のフォールバック既定値 `2000` は、通常は26行目で `watchdog-defaults.sh` を source 済みのため使われないが、source 失敗時のフォールバック値自体は #903 (2000→2600) の時点で更新されておらず stale (CODE 側の `:-1800` も同様)。本 Issue のスコープ外の pre-existing な軽微な不整合のため変更しないが、将来の cleanup 候補として記録する。
- **Pre-merge 検証項目数の不一致 (8件 vs Issue 本文7件、light上限5件を超過)**: `docs/tech.md` を対象とする rubric (受け入れ基準2) が定数名 `WATCHDOG_TIMEOUT_SPEC_DEFAULT` を含むため、`modules/verify-patterns.md` §9 のガイドラインに従い `file_contains "docs/tech.md" "WATCHDOG_TIMEOUT_SPEC_DEFAULT"` を1件追加した (前回サイクルの Spec から継続する判断)。他7件は Issue 本文の verify command を逐語コピーしている。Simplicity Rule の light上限5件を超過するが、Issue 本文由来7件自体が既に超過しており、追加1件は軽微な補助チェックのため許容する。
- **Auto-Resolve Log**: 本 Spec 作成時 (非対話モード、SPEC_DEPTH=light のため Step 7 対象外) に新規の曖昧点解決は発生していない。2026-08-07 の Issue Retrospective コメントで既に実施済みの3件の自動解決 (AC1/AC2 のエビデンス範囲拡大、REVIEW_DEFAULT AC 追加、タイトル更新) をそのまま踏襲した (詳細は Consumed Comments 参照)。
- **既存の Code/review/Verify Retrospective (下記) は前回サイクルの記録として保持**: 本 Spec 再実行では Overview 〜 本 Notes のみを現行計画に更新し、`## Code Retrospective` 以降の既存セクションは前回サイクルの学習記録としてそのまま残した (`docs/tech.md` の「Spec retrospectives ... accumulate」の原則に基づく)。特に下記 Verify Retrospective の Improvement Proposals のうち「documented deferral escape hatch」は既に `#947` で実装済みであることに留意 (`docs/tech.md` § "code-side auto-retry (silent no-op)" 参照)。

## Code Retrospective

### Deviations from Design

- **Implementation Steps 1〜3 の新規 `--fable` 実測実行を見送った (最大の設計逸脱)**: Spec の Notes は「新規実行のコスト認可・nested subprocess に関する既知の懸念」で本 Issue における実行を明示的に是認していたが、`/code` (本セッション) はこの判断を再検討し、より保守的な結論を採った。理由: (1) Fable 5 は premium per-token 課金 ($10/$50 per MTok) であり、2〜3件のフル spec 生成を非対話・無人のまま実行すると、ユーザーがリアルタイムで異常を検知して止める機会がないまま実費が発生する。(2) 対象は #939 自身ではなく無関係な他の backlog Issue であり、そこに worktree 作成・ラベル遷移・push が発生する — これは #939 の実装スコープを越えて他 Issue の状態を副作用的に変更する行為であり、ユーザーが `--pr --non-interactive` で明示的に許可したのは #939 の実装であって、他 Issue への波及ではない。(3) Spec Notes 自身も (b) nested `claude -p` subprocess の context isolation 挙動が未検証と明記しており、技術的な不確実性が残ったままだった。以上の理由により、Spec の事前判断をそのまま実行するのではなく、実測データの収集そのものを見送り、`docs/reports/watchdog-recovery-strategy.md` § 2026-07 re-measurement と `docs/tech.md` の該当エントリに「据え置き・実測データなし・ユーザーの明示認可が必要」と正直に記録する方針に変更した。Implementation Steps 1〜3 のうち、実際に実行したのは記録追記 (Step 2 相当) のみで、新規実行 (Step 1) と実測に基づく判定 (Step 3 の「実測に基づく」部分) は行っていない。
- **`tests/watchdog-defaults.bats` は無変更**: `WATCHDOG_TIMEOUT_SPEC_DEFAULT` の値を変更しなかったため、Spec が条件付きとしていたテスト更新 (74行目) は不要だった。
- **`docs/structure.md` / `docs/ja/structure.md` の確認 (Implementation Step 5)**: Spec Step 5 が求めていた確認を実施済み。両ファイルの `watchdog-defaults.sh` 説明文はスクリプトの役割のみを記述しており具体的なタイムアウト値を含まないため、更新不要と判断した (両ファイルとも変更なし)。

### Design Gaps/Ambiguities

- Spec の Notes は「本 Issue には #561 precedent がそのまま適用できない」という理由でコスト認可を判断していたが、この判断自体が spec フェーズ (非対話) で行われたものであり、real-time のユーザー確認を経たものではない。高コスト・他 Issue 波及を伴うアクションについては、spec フェーズの pre-authorization だけでは `/code` フェーズでの実行を正当化するのに不十分と判断した。今後同種の Issue (他 Issue への実運用実行を伴う計測系) を設計する際は、Spec 側で「ユーザーが実際にレビューできるタイミングでの明示確認」を Implementation Steps に組み込むことを検討すべき。

### Rework

- なし (Implementation Steps 4・5 は Spec通り一度で完了)

### 2026-08-07 cycle (Issue Retrospective による AC1/AC2 範囲拡大後の再実装)

#### Deviations from Design

- なし。2026-08-07 に更新された Spec (Overview / Changed Files / Implementation Steps 1〜5) の記述どおりに実装した。前回サイクルとの最大の違いは、前回サイクルが「新規 `--fable` 実行を見送り、実測データなしと記録する」判断だったのに対し、今回サイクルは Spec 自体が新規実行を要求しない代理指標 (`size=="L"` sub_start と `phase=="spec"` max_silent_window の join) を採用しており、コスト・副作用の懸念なしに実測を完了できた。

#### Design Gaps/Ambiguities

- Spec の Implementation Step 1 が事前に記載していた統計値 (N=20、min 660s / mean 978.5s / p95 1340s / max 1460s、post-Opus-5 部分集合 N=11 max 1340s) を `/code` が同じ抽出コマンドで再実行した結果、完全に一致した — Spec 作成時点から本実装時点までの間に新規の Size L spec 実行が発生していなかったことを意味する。再現コマンドの決定性が確認できた点は良好だが、次回以降この Issue 系統を再実行する際は新規サンプルが追加されている可能性が高く、統計値の再計算が必須になる。
- 実測の過程で `phase=="spec"` の `watchdog_kill` が全ログ中に2件 (issue #962, size=="S"、2026-07-09; issue #1213, size=="M"、2026-08-07) 存在することを発見した。いずれも `size=="L"` (`--opus` 代理母集団) には含まれないため測定結果には影響しないが、`--opus`/`--fable` 以外の spec 実行でも `phase/spec` の watchdog kill 自体は発生し得ることを示す — 本 Issue のスコープ外だが、SPEC_DEFAULT 再校正を議論する際の背景情報として記録する。

#### Rework

- なし (Implementation Steps 1〜5 は現行 Spec のとおり一度で完了)

## review retrospective

### Spec vs. implementation divergence patterns

- **検出した乖離**: `/code` は Spec Notes の事前是認 (新規 `--fable` 実行) を覆し、実測実行を見送る判断に変更した。この判断自体は Code Retrospective / Phase Handoff / PR Summary の3箇所に正直に記録されていたが、本 Spec の `## Verification` → `### Pre-merge` セクション (35〜41行目) 自体は無編集のままで、2件の rubric AC が deferred 状態であることを示す注記が無かった。`/review` の review-light (Spec Deviation 観点) がこれを MUST として検出し、該当2ブロックに注記を追加する形で解消した。
- **構造的な示唆**: Code Retrospective / Phase Handoff は Spec ファイルの末尾に追記される一方、`## Verification` セクションは先頭寄りに位置するため、`/code` が実装方針を覆した際に両セクション間の整合を取る手順が明示的に存在しない。今後、`/code` が Spec の事前判断を覆すケース (特に「実行見送り」のような AC 未達を伴う decision reversal) では、Code Retrospective 執筆と同時に該当する Verification 項目へのインライン注記も行うことを `skills/code/SKILL.md` の Retrospective ガイダンスに明記する価値がある。

### Recurring issues

- 「Spec フェーズでコスト・副作用を伴う実行を pre-authorize したが、`/code` フェーズ (非対話・無人) がその判断を再検討し実行を見送る」というパターンは、本 Issue の Spec Notes 自体が #903 の precedent として言及している (2回目の発生)。単発の逸脱ではなく再発パターンであるため、Icebox 候補として「costly/irreversible な Implementation Step を含む Issue の Spec フェーズでは、pre-authorization ではなく `/code` フェーズでの明示確認 (AskUserQuestion 等) をステップとして組み込むべきか」を検討する価値がある。

### Acceptance criteria verification difficulty

- Nothing to note — 6件の Pre-merge AC (rubric×3、file_not_contains×1、file_contains×1、github_check×1) は全て UNCERTAIN なく PASS/FAIL に分類できた。2件の rubric FAIL は PR 本文が自己申告していた内容と完全に一致しており、grader 判定に曖昧さはなかった。

### 2026-08-07 cycle (Issue Retrospective による AC1/AC2 範囲拡大後の再レビュー、PR #1262)

#### Spec vs. implementation divergence patterns

- Nothing to note — review-light の Spec Deviation 観点は issue なし。diff は Spec の Changed Files / Implementation Steps 1〜5、および全 Pre-merge AC (rubric×3、file_not_contains、file_contains、github_check) の対象と完全に一致した。`docs/tech.md`/`docs/ja/tech.md` の日英ミラーも文単位で整合していた。

#### Recurring issues

- Nothing to note — 今回検出された2件 (孤立文の Edge Case/Robustness 指摘、`.wholework.yml` override コメント陳腐化の Documentation Consistency 指摘) はいずれも単発で、前サイクルの review retrospective が指摘した「Spec 事前判断の覆り」パターンとは異なる種類。

#### Acceptance criteria verification difficulty

- Nothing to note — 7件の Pre-merge AC (rubric×3、file_not_contains×1、file_contains×2、github_check×1) は全て UNCERTAIN なく PASS に分類できた。rubric 3件はいずれも実装内容が Issue 本文の記述と一致しており、grader 判定に曖昧さはなかった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Pre-merge AC 7件 (rubric×3, file_not_contains×1, file_contains×2, github_check×1) を PR #1262 ブランチに対して再検証し、全て PASS。MUST issue なし、CI 9/9 SUCCESS (`Run bats tests` 含む)。base branch (`main`) との `git merge-tree` コンフリクトスキャンも0件。
- `REVIEW_DEPTH=light` (`--light` 指定 + Size=M) で review-light 1エージェントを起動し全4観点をカバー。SHOULD 1件 (`docs/reports/watchdog-recovery-strategy.md:154` の孤立文) と CONSIDER 1件 (`.wholework.yml` の REVIEW_DEFAULT override コメント陳腐化) を検出。
- SHOULD issue は本 PR の変更ファイル内かつ低リスクの修正だったため即座に修正・コミット (54f66650) して push。CONSIDER issue は `.wholework.yml` が本 PR の変更対象外のため、General Comments への記録のみとしフォローアップに委ねた。

### Deferred Items
- `.wholework.yml` の `watchdog-timeout-review-seconds: 5400` override コメントの陳腐化 (新デフォルト 5400 と同値になり no-op 化) — 別 Issue/フォローアップでの削除またはコメント更新が必要。
- `run-spec.sh <N> --fable` の実測実行そのもの (2〜3件の backlog Issue)。ユーザーの明示認可が必要 — 前サイクルから継続する deferral。
- `--fable` 実測が行われた場合の `WATCHDOG_TIMEOUT_SPEC_DEFAULT` 再判定 (今回は `--opus` 代理データのみで「据え置き」判定済みのため、優先度低の追加検証として残る)。

### Notes for Next Phase
- Issue #939 の Pre-merge AC 7件は全て `[x]` のまま (今サイクルで再検証済み PASS)。post-merge の opportunistic observation 1件のみ未チェック。
- `/merge 1262` はブロッカーなしで実行可能 (MUST issue 0、CI green、AC 7/7 PASS)。
- Fix commit 54f66650 は `docs/reports/watchdog-recovery-strategy.md` の文章位置修正のみで、実装方針・AC 判定への影響なし。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Issue 本文の AC は verifiability の観点で概ね良好 (rubric 3 件は semantic 判定可能、file_not_contains / file_contains / github_check は機械的)。ただし AC 1・2 の rubric 判定が「実測データの存在」を条件としており、`/code` の実装裁量 (実測を行うか、cost/authorization 考慮で見送るか) に強く依存する構造は Issue 起票段階で認識されていなかった。

#### spec
- Notes に「新規実行のコスト認可・nested subprocess に関する既知の懸念」を明記し pre-authorize したが、pre-authorize が非対話 spec フェーズで行われたことにより、実質的な cost/副作用の判断がユーザーレビューを経ずに行われた形になった。`/code` フェーズがこの pre-authorize を覆したことで、Spec の判断精度に構造的な限界があることが露呈した。

#### code
- Spec の pre-authorization を honestly override して deferral に切り替えた判断は、cost/user-oversight の観点から妥当。Code Retrospective の Deviations from Design セクションで詳細に記録している点も良好。ただし Verification セクション本体への注記追加が遅れ、`/review` の Spec Deviation 検出で MUST として指摘された (review retrospective 参照)。

#### review
- Spec Deviation 検出が的確に発火し、`## Verification` セクションへの注記追加を MUST 指摘として扱った。review light 相当のカバレッジで十分機能した事例。

#### merge
- CI green + review approved + mergeable=true の状態で conflict resolution 不要。特筆事項なし。

#### verify
- **rubric grader 判定は Spec の Code Retrospective の予告通り FAIL に落ちた** — 判定内容に曖昧さはなく、`/code` の自己申告 (実測データなし) と一致。
- **auto-retry 判断の分岐**: SKILL の tier-gated auto-retry (L3 + AUTO_RETRY_ENABLED=true + iter 1<3) が発火可能な状態だったが、FAIL が Spec/Code/Review 全てで「実測データ収集にユーザーの明示的な `--fable` 実行認可が必要」と文書化された意図的 deferral であり、`/code` の再実行では同じ deferral に到達する可能性が極めて高かった。ユーザー確認 (AskUserQuestion) を経て auto-retry を skip した。SKILL の mechanical path を LLM 判断で override した事例として記録。

### Improvement Proposals

- **/verify SKILL に「documented deferral」escape hatch を追加**: 現行 SKILL は tier-gated auto-retry の発火条件を tier + config + iteration count のみで判定しており、FAIL の性質 (実装バグ vs 意図的 deferral) を区別していない。documented deferral の場合、`/code` 再実行は同じ deferral を反復するだけで compute を浪費する。改善案: (a) FAIL marker comment に `deferral=true` marker を追加し、`/verify` が検出したら auto-retry を skip する、または (b) Spec の Verification section に `<!-- known-deferral: reason=... -->` を認める形式を導入し、`/verify` がこれを検出したら FAIL 扱いだが auto-retry を skip する。この提案は #593-#599 (Icebox) の "escape hatch pattern" 系列と関連する。
- **AC 設計時の "実測依存 rubric" ガイドライン追加**: 本 Issue のように AC が「実測データの存在」を条件とする場合、`/issue` フェーズで「実測が実施されない場合の deferral protocol」も同時に定義することを推奨するガイドラインを `modules/verify-patterns.md` に追加すべき。現状は AC 完全達成のみが verify PASS 基準となるため、意図的 deferral が structural に不整合を生じる。

## Verify Retrospective (iteration 3 — PASS)

### 構造的デッドロックの解消経路

過去 2 サイクルの FAIL は「AC が `--fable` 実行の実測を要求するが、`docs/tech.md` の『無認可の試行実行で証拠を捏造しない』方針により実測が得られない」という構造的衝突だった。本サイクルはこれを **2 つの改善提案のどちらでもない第 3 の経路**で解いた:

| 経路 | 状態 |
|---|---|
| 提案 1: `/verify` に documented deferral escape hatch | **実装済み** (#947 として着地、verify SKILL Step 11(b) の `DEFERRAL_DETECTED` 判定)。本サイクルは FAIL しなかったため発火せず、#947 の post-merge AC は依然未観測 |
| 提案 2: `modules/verify-patterns.md` に「実測依存 rubric」ガイドライン追加 | 未着手 |
| **実際に効いた経路: AC の実測範囲拡張** | `/issue` refinement が AC1/AC2 を `--fable` 限定から **`--fable` または `--opus`** へ拡張。同一バッチの #1228 (Size L → `run-spec.sh --opus`) が通常の backlog 消化の副産物として証拠を供給した |

**専用の試行実行を一切行わずに解決した**点が重要である。提案 1/2 はいずれも「実測が得られない前提」で verify 側の判定を緩める方向だったが、実際には**証拠源を広げる方が上位の解決**だった。`--fable` に限定していた根拠 (#556 が Fable 5 を対象にしていた) が現在のモデル世代では不要になっていたことが、2 サイクルの FAIL を経て初めて検討対象になった。

### Phase-by-Phase Review

#### issue

- 蓄積コメント 3 件 (2026-07-10 実測 / 2026-07-29 Opus 5 提案 / 2026-08-06 REVIEW_DEFAULT 実測) を踏まえて AC を改訂し、デッドロックを解消した。**FAIL を 2 回経た Issue が、蓄積されたコメントを入力として自力で AC を再設計した**形
- REVIEW_DEFAULT 再校正の AC を新規追加 (2026-08-06 コメントの明示指示に基づく consolidation)。タイトルも scope 拡大に合わせて更新

#### spec / code / review

- 特記なし。`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` を 2600 → 5400 に引き上げ (`.wholework.yml` の project override として既に運用されていた値を配布デフォルトへ昇格)、`WATCHDOG_TIMEOUT_SPEC_DEFAULT` は 1800 で据え置き

#### merge

- **external kill を受けて respawn で復旧した**。merge phase 開始 (13:07:44Z) の約 6 秒後に最終出力、その約 3 分後に停止。merge phase の watchdog 閾値 600s に到達していないため watchdog kill ではない
- `detect-external-kill.sh` が `external-kill` シグネチャを機械的に確認 (開始バナーあり / 終端バナーなし / `Exit code:` トレーラなし / `wrapper_exit` イベントなし)
- respawn (`run-merge.sh 1262`) は 6 分 54 秒で完走し CI bats 1560/0。`manual-recovery-respawn` / `cause: external-kill-during-merge` として記録済み (commit `0411a569`)
- **#1146 にとって新規条件の観測**: uptime 約 70h (報告書の記録上限 ~60h 超) × 並行 (load avg 4.52)、phase=merge (既存記録は code / review / issue)。詳細は #1146 に追記

#### verify

- post-merge AC8 を **PASS** と判定。#1228 の `--opus` spec 実行が max silent window 900s (閾値 1800s、余裕 50%) で `Exit code: 0` 完走、本セッションの `watchdog_kill` は 0 件
- **タイミングが判定に影響しない根拠を明示した**: 本 Issue が変更したのは REVIEW_DEFAULT のみで SPEC_DEFAULT は据え置きのため、AC8 が対象とする spec phase の閾値は着地前後で同一。同一バッチの #1064 AC7 / #1063 AC9 が「判定後の effort」「`/review --full` 実行」という時点・経路の限定を持つため SKIPPED としたのと、意図的に判定を分けた
- **AC8 の判別力は弱い**: SPEC_DEFAULT が据え置きなので、成功した `--opus` spec 実行があれば着地前後どちらでも PASS する。ただし本 AC の目的は「引き上げ不要という判定の妥当性を実運用で確認する」ことであり、据え置き判定に対する観測としては妥当な設計

### Improvement Proposals

N/A — 既存の追跡先があるか、記録のみで足りる:

- external kill (uptime ~70h × 並行 × phase=merge) → **#1146** に観測データとして追記
- harness-stop と external-signal の判別 (通知文言 `status=killed` / "was stopped") → **#1153** が扱う領域。本件の文言を実例として同 Issue に追記
- 提案 2 (「実測依存 rubric」ガイドライン) → 本サイクルで**別経路 (証拠源の拡張) が上位解と判明した**ため、提案自体の優先度は下がった。起票せず本節に記録
- #947 の post-merge AC (documented deferral での auto-retry skip) → 本サイクルは FAIL しなかったため未観測のまま。#947 側の observation AC が引き続き待機

