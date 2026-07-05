# Issue #939: watchdog: Fable 5 実トラフィックでの spec silent window 実測と SPEC_DEFAULT 再校正判定 (#556 follow-up)

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (`/issue` フェーズ) — 曖昧点3件の自動解決ログ (① 実測件数・対象は実装裁量の代表 Issue 数件、② SPEC_DEFAULT 変更を本 Issue 内で実施、③ 計測手段は既存 instrumentation (`silent_window` イベント + `/audit auto-session`) 限定・新規機構は作らない) と AC 設計補足 (post-merge は `observation event=watchdog-kill` ではなく `opportunistic` を採用、`github_check "gh pr checks"` は Size M/PR route 前提、`file_contains "#556"` は起票時点で未存在を確認済み) を確認。いずれも Issue 本文に既に反映済みで、本 Spec で新規に対応すべきアクションはなし。/ https://github.com/saitoco/wholework/issues/939#issuecomment-4886097163

## Overview

`scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800` は、base `WATCHDOG_TIMEOUT_DEFAULT` が #556 の spike (Fable 5 短期スパイク、2026-06-13) に基づき 1800→2700 に引き上げられた際も、また #903 (Sonnet 5 再校正) でもスコープ外のまま据え置かれてきた。Fable 5 は 2026-06-13〜2026-07-01 の一時停止を経て再デプロイされ、`run-spec.sh --fable` による実トラフィックでの計測が今回初めて可能になる。

本 Issue では、代表的な backlog Issue 数件に対して実際に `run-spec.sh <N> --fable` を実行し、spec フェーズの実測 silent window (max_silent_window イベント) と watchdog kill 有無を収集する。結果を `docs/reports/watchdog-recovery-strategy.md` § Fable 5 long-turn findings に 2026-07 再計測として追記し、#903 と同じ判定基準 (実測がタイムアウトの80%以上 → 引き上げ検討、未満 → 据え置き) を適用して `WATCHDOG_TIMEOUT_SPEC_DEFAULT` の再校正要否を判定する。判定結果 (変更/据え置き) とその根拠は `docs/tech.md` § Watchdog timeout calibration に記録する。あわせて `scripts/watchdog-defaults.sh` のコメントに残る世代参照 ("Sonnet 4.6 / Opus 4.7") を現行世代 (Sonnet 5 / Opus 4.8) に更新し、base `WATCHDOG_TIMEOUT_DEFAULT=2700` の由来 (#556 spike での 1800 からの引き上げ) を明記する。

## Changed Files

- `docs/reports/watchdog-recovery-strategy.md`: 既存の `## Fable 5 long-turn findings` セクションに、`--fable` spec 実行の実測結果 (実行件数、issue ごとの max silent window、watchdog kill 有無) を「2026-07 re-measurement」as a new subsection として追記。#556 の外挿 (600–2000s の推測レンジ) を実測値で更新する
- `docs/tech.md`: § Architecture Decisions の "Watchdog timeout calibration" 記述近傍 (既存の #903 エントリの並び) に、`WATCHDOG_TIMEOUT_SPEC_DEFAULT` 再校正の判定 (変更/据え置き) と実測に基づく根拠を追記。`#939` の明記、上記レポートへのリンクを含める
- `docs/ja/tech.md`: 上記 `docs/tech.md` 追記の日本語ミラー同期 (`docs/translation-workflow.md` の Sync Procedure に準拠。code fence 数の一致を確認)
- `scripts/watchdog-defaults.sh`: (a) 9行目のコメント "high-effort triage under Sonnet 4.6 / Opus 4.7 requires more headroom" を現行モデル世代 (Sonnet 5 / Opus 4.8) の表現に更新、(b) base `WATCHDOG_TIMEOUT_DEFAULT=2700` の由来 (#556 spike での 1800 からの引き上げ) をコメントに追記し `#556` を明記、(c) [条件付き — 実測でマージン20%未満 (使用率80%以上) と判明した場合のみ] `WATCHDOG_TIMEOUT_SPEC_DEFAULT` を比例的に引き上げ。据え置き判断の場合は値変更なし
- `tests/watchdog-defaults.bats`: [条件付き — `WATCHDOG_TIMEOUT_SPEC_DEFAULT` の値を変更した場合のみ] 74行目 `@test "load_watchdog_timeout uses phase-specific default when phase is spec"` の assertion (`[ "$output" = "1800" ]`) を新しい値に更新。bash 3.2+ compatible を維持
- `docs/structure.md`: [Steering Docs sync candidate] `watchdog-defaults.sh` の説明文 (Scripts カタログ) は役割記述のみで具体的な値を含まないため、値変更のみでは更新不要と見込まれるが `/code` で最終確認
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記と同様、`/code` で最終確認

## Implementation Steps

1. 代表的な backlog Issue 2〜3件 (未だ `/spec` を実行しておらず、Size XS/S/M 程度で他セッションが同時に処理していないもの。実装裁量 — #556 spike・#561 A/B の先例を踏襲) を選定し、`bash scripts/run-spec.sh <N> --fable` を各 Issue に対して実行する。各実行完了直後に `.tmp/auto-events.jsonl` から `event=="max_silent_window" and phase=="spec" and issue==<N>` に一致するイベント (と、もしあれば `event=="watchdog_kill"`) を抽出する (→ 受け入れ基準1)
2. Step 1 で収集した実測結果 (実行件数、issue ごとの max silent window 秒数、watchdog kill 有無) を `docs/reports/watchdog-recovery-strategy.md` § Fable 5 long-turn findings に「2026-07 re-measurement」の新規サブセクションとして追記する (after 1) (→ 受け入れ基準1)
3. Step 2 の実測値に、#903 と同じ判定基準 (実測 max silent window が `WATCHDOG_TIMEOUT_SPEC_DEFAULT` (1800s) の80%以上 [≥1440s] → 引き上げ検討、未満 → 据え置き) を適用して判定する。判定結果とその根拠 (実測データへの参照を含む) を `docs/tech.md` § Watchdog timeout calibration に追記する。引き上げが必要な場合は #903 と同じ conservative な比例引き上げ (Icebox #596 のトレードオフに基づき #628 の2倍ではなく控えめな倍率) を `scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_SPEC_DEFAULT` に適用し、`tests/watchdog-defaults.bats` 74行目の期待値も同時に更新する (after 2) (→ 受け入れ基準2・6)
4. `scripts/watchdog-defaults.sh` のコメントを更新する: 9行目の世代参照 "Sonnet 4.6 / Opus 4.7" を現行世代 (Sonnet 5 / Opus 4.8) に置き換え、base `WATCHDOG_TIMEOUT_DEFAULT=2700` の由来 (#556 spike での 1800 からの引き上げ) を明記するコメント行を追加し `#556` を含める (parallel with 1, 2, 3) (→ 受け入れ基準3・4・5)
5. `docs/translation-workflow.md` の Sync Procedure に従い `docs/ja/tech.md` を Step 3 の追記内容で同期する。あわせて `docs/structure.md` / `docs/ja/structure.md` の `watchdog-defaults.sh` 説明文を確認し、値変更のみで更新不要であることを確認する (after 3)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/watchdog-recovery-strategy.md の Fable 5 long-turn findings に、--fable spec 実行の実測結果 (実行件数、max silent window、watchdog kill 有無) が 2026-07 以降の再計測として記録されている" --> `--fable` spec 実行の実測結果がレポートに記録されている

  **[/review 時点で FAIL 確定・意図的]**: `/code` フェーズは新規 `--fable` 実行を見送り、「実測データなし・deferred」と正直に記録する方針に変更した (下記 Code Retrospective 参照)。この判定自体は本 Spec の事前是認を覆すものであり、実測データが存在しない以上この AC は満たせない。ユーザーの明示認可を得た追加実行が完了するまで、この AC は未達のまま維持される。
- <!-- verify: rubric "WATCHDOG_TIMEOUT_SPEC_DEFAULT (1800s) の引き上げ要否の判定 (変更/据え置き) と実測に基づく根拠が docs/tech.md の watchdog timeout calibration 項に記録されている" --> SPEC_DEFAULT 再校正の判定と根拠が `docs/tech.md` に記録されている

  **[/review 時点で FAIL 確定・意図的]**: `docs/tech.md` には「据え置き」の判定は記録済みだが、根拠は「新規実測なし」であり、本 AC が要求する実測に基づく根拠ではない。上記 AC と同じ理由 (Code Retrospective 参照) により未達。
- <!-- verify: file_contains "docs/tech.md" "WATCHDOG_TIMEOUT_SPEC_DEFAULT" --> `docs/tech.md` に定数名 `WATCHDOG_TIMEOUT_SPEC_DEFAULT` の言及が存在する (rubric 判定の機械的補助チェック。`modules/verify-patterns.md` §9 の数値・定数名補完ガイドラインに基づき追加。Issue 本文にはない Spec 独自の追加項目 — 詳細は Notes 参照)
- <!-- verify: file_not_contains "scripts/watchdog-defaults.sh" "Sonnet 4.6 / Opus 4.7" --> `watchdog-defaults.sh` コメントの世代参照が現行モデル世代 (Sonnet 5 / Opus 4.8) に更新されている
- <!-- verify: rubric "scripts/watchdog-defaults.sh のコメントに base WATCHDOG_TIMEOUT_DEFAULT=2700 の由来 (#556 spike での 1800 からの引き上げ) が明記されている" --> base 2700 の由来が注記されている
- <!-- verify: file_contains "scripts/watchdog-defaults.sh" "#556" --> 由来注記が #556 を参照している
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが green (SPEC_DEFAULT 変更時は `tests/watchdog-defaults.bats` のハードコード値更新を含む)

### Post-merge

- `/spec --fable` または `/auto` 経由の `--fable` spec 実行時に、watchdog kill が発生せず phase が正常完了することを観察 <!-- verify-type: opportunistic -->

## Notes

- **Pre-merge 検証項目数の不一致 (7件 vs Issue 本文6件)**: `docs/tech.md` を対象とする rubric (受け入れ基準2) が定数名 `WATCHDOG_TIMEOUT_SPEC_DEFAULT` という数値相当の識別子を含むため、`modules/verify-patterns.md` §9 の「rubric に数値リテラル・定数名が含まれる場合は file_contains を併記する」ガイドラインに従い `file_contains "docs/tech.md" "WATCHDOG_TIMEOUT_SPEC_DEFAULT"` を1件追加した。他5件は Issue 本文の verify command を逐語コピーしており、独自の書き換えは行っていない。Size/Route への影響なし (Simplicity Rule の light上限5件を超過するが、Issue 本文由来6件はそのまま超過しており、追加1件は軽微な補助チェックのため許容)。
- **`--fable` 実測の実行方針 (#903 retrospective と #561 precedent の両方を踏まえた判断)**: #903 の Verify Retrospective は「spec 段階では新規実行を計画したが、code フェーズで cost/副作用の観点から却下され、GitHub Issue/PR タイムラインからの log-based reconstruction に変更された。spec 段階でその方式を第一候補にできた余地がある」と指摘している。しかし本 Issue にはその教訓がそのまま適用できない: #903 (Sonnet 5) は 2026-06-30 以降の全ての `/code`/`/review` production 実行が対象母集団になり得たため log 再構成で十分だったが、Fable 5 の spec 実行は opt-in (`--fable` 明示指定) のため、Issue 本文が明記する通り実測は過去1回 (#560) のみで、再構成に足る production log の母集団が存在しない。したがって本 Issue では新規に `--fable` spec 実行を行うこと自体が必須であり、Implementation Steps 1 で明示した。
- **新規実行のコスト認可・nested subprocess に関する既知の懸念**: `docs/reports/de-prescription-audit.md` § A/B Test Methodology (#561) は、`--non-interactive` autonomous mode (`run-code.sh` 経由の `claude -p` subprocess) から `run-spec.sh --fable` (それ自体が `claude -p` を起動する) を呼び出すことについて、(a) Fable 5 の高コスト ($10/$50 per MTok) を明示的なユーザー認可なしに開始する高リスク判断、(b) `claude -p` の入れ子呼び出しの context isolation 挙動が未検証、の2点を理由に実行を見送った precedent がある。本 Issue はこの precedent と状況が異なる: 本 Issue 自体が「実トラフィックでの Fable 5 spec 実測」を明示目的として起票されており、実行対象も使い捨てのダミー呼び出しではなく実際に spec 化が必要な backlog Issue (実行が Issue 自体の進捗にも資する) を選ぶため、コスト発生への実質的な事前認可があると判断できる。ただし (b) の nested subprocess 挙動の未検証という技術的懸念は解消されていないため、`/code` は Step 1 実行時に異常 (context 混線、予期しない早期終了等) が見られた場合は Code Retrospective に記録すること。バックグラウンド実行 (`run_in_background`) での起動も選択肢として検討してよい。
- **`max_silent_window` イベントに model タグが存在しない制約**: `scripts/claude-watchdog.sh` が emit する `max_silent_window` / `phase_start` イベントには `model` フィールドが存在しない (`model` を持つのは `token_usage` イベントのみで、かつ現行 `.tmp/auto-events.jsonl` を確認した限り spec/issue フェーズでは `token_usage` 自体が記録されていない)。したがって過去ログを「Fable 5 で実行されたものだけ」機械的に抽出することはできない。Step 1 で「未だ spec 実行していない Issue番号」を選んで新規実行することで、実行直後に同じ issue番号でマッチする `max_silent_window` イベントを一意に自分の実行結果として識別できる (この方法であれば model フィールド不在は実務上問題にならない)。
- **判定基準を #903 と揃えた根拠**: Issue 本文は本 Issue 独自の閾値を明記していないため、直近の同種再校正 precedent である #903 (`docs/reports/sonnet-5-watchdog-recalibration.md`) の「実測 ≥80% of timeout → 引き上げ検討 (~1.3倍程度、Icebox #596 のトレードオフに基づき #628 の2倍は採用しない)」をそのまま踏襲した。Issue retrospective コメントにも異なる基準は示されていない。
- **Auto-Resolve Log**: 本 Spec 作成時 (非対話モード) に追加で自動解決したものはない。Issue 本文と issue retrospective コメントに記載済みの3件の自動解決 (計測対象・変更スコープ・計測手段) をそのまま踏襲した。

## Code Retrospective

### Deviations from Design

- **Implementation Steps 1〜3 の新規 `--fable` 実測実行を見送った (最大の設計逸脱)**: Spec の Notes は「新規実行のコスト認可・nested subprocess に関する既知の懸念」で本 Issue における実行を明示的に是認していたが、`/code` (本セッション) はこの判断を再検討し、より保守的な結論を採った。理由: (1) Fable 5 は premium per-token 課金 ($10/$50 per MTok) であり、2〜3件のフル spec 生成を非対話・無人のまま実行すると、ユーザーがリアルタイムで異常を検知して止める機会がないまま実費が発生する。(2) 対象は #939 自身ではなく無関係な他の backlog Issue であり、そこに worktree 作成・ラベル遷移・push が発生する — これは #939 の実装スコープを越えて他 Issue の状態を副作用的に変更する行為であり、ユーザーが `--pr --non-interactive` で明示的に許可したのは #939 の実装であって、他 Issue への波及ではない。(3) Spec Notes 自身も (b) nested `claude -p` subprocess の context isolation 挙動が未検証と明記しており、技術的な不確実性が残ったままだった。以上の理由により、Spec の事前判断をそのまま実行するのではなく、実測データの収集そのものを見送り、`docs/reports/watchdog-recovery-strategy.md` § 2026-07 re-measurement と `docs/tech.md` の該当エントリに「据え置き・実測データなし・ユーザーの明示認可が必要」と正直に記録する方針に変更した。Implementation Steps 1〜3 のうち、実際に実行したのは記録追記 (Step 2 相当) のみで、新規実行 (Step 1) と実測に基づく判定 (Step 3 の「実測に基づく」部分) は行っていない。
- **`tests/watchdog-defaults.bats` は無変更**: `WATCHDOG_TIMEOUT_SPEC_DEFAULT` の値を変更しなかったため、Spec が条件付きとしていたテスト更新 (74行目) は不要だった。
- **`docs/structure.md` / `docs/ja/structure.md` の確認 (Implementation Step 5)**: Spec Step 5 が求めていた確認を実施済み。両ファイルの `watchdog-defaults.sh` 説明文はスクリプトの役割のみを記述しており具体的なタイムアウト値を含まないため、更新不要と判断した (両ファイルとも変更なし)。

### Design Gaps/Ambiguities

- Spec の Notes は「本 Issue には #561 precedent がそのまま適用できない」という理由でコスト認可を判断していたが、この判断自体が spec フェーズ (非対話) で行われたものであり、real-time のユーザー確認を経たものではない。高コスト・他 Issue 波及を伴うアクションについては、spec フェーズの pre-authorization だけでは `/code` フェーズでの実行を正当化するのに不十分と判断した。今後同種の Issue (他 Issue への実運用実行を伴う計測系) を設計する際は、Spec 側で「ユーザーが実際にレビューできるタイミングでの明示確認」を Implementation Steps に組み込むことを検討すべき。

### Rework

- なし (Implementation Steps 4・5 は Spec通り一度で完了)

## review retrospective

### Spec vs. implementation divergence patterns

- **検出した乖離**: `/code` は Spec Notes の事前是認 (新規 `--fable` 実行) を覆し、実測実行を見送る判断に変更した。この判断自体は Code Retrospective / Phase Handoff / PR Summary の3箇所に正直に記録されていたが、本 Spec の `## Verification` → `### Pre-merge` セクション (35〜41行目) 自体は無編集のままで、2件の rubric AC が deferred 状態であることを示す注記が無かった。`/review` の review-light (Spec Deviation 観点) がこれを MUST として検出し、該当2ブロックに注記を追加する形で解消した。
- **構造的な示唆**: Code Retrospective / Phase Handoff は Spec ファイルの末尾に追記される一方、`## Verification` セクションは先頭寄りに位置するため、`/code` が実装方針を覆した際に両セクション間の整合を取る手順が明示的に存在しない。今後、`/code` が Spec の事前判断を覆すケース (特に「実行見送り」のような AC 未達を伴う decision reversal) では、Code Retrospective 執筆と同時に該当する Verification 項目へのインライン注記も行うことを `skills/code/SKILL.md` の Retrospective ガイダンスに明記する価値がある。

### Recurring issues

- 「Spec フェーズでコスト・副作用を伴う実行を pre-authorize したが、`/code` フェーズ (非対話・無人) がその判断を再検討し実行を見送る」というパターンは、本 Issue の Spec Notes 自体が #903 の precedent として言及している (2回目の発生)。単発の逸脱ではなく再発パターンであるため、Icebox 候補として「costly/irreversible な Implementation Step を含む Issue の Spec フェーズでは、pre-authorization ではなく `/code` フェーズでの明示確認 (AskUserQuestion 等) をステップとして組み込むべきか」を検討する価値がある。

### Acceptance criteria verification difficulty

- Nothing to note — 6件の Pre-merge AC (rubric×3、file_not_contains×1、file_contains×1、github_check×1) は全て UNCERTAIN なく PASS/FAIL に分類できた。2件の rubric FAIL は PR 本文が自己申告していた内容と完全に一致しており、grader 判定に曖昧さはなかった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Pre-merge AC 6件中 FAIL 2件 (実測結果記録、SPEC_DEFAULT 再校正の実測根拠) は `/code` の意図的な決定によるものであり、review 側では実測実行や authorization 取得を代行せず、Issue チェックボックスに FAIL として正直に反映するに留めた (該当2件は unchecked のまま)。
- Spec の Pre-merge Verification セクション (35〜36行目) に deferred 状態の注記を追加 (MUST fix)。`docs/structure.md` 確認結果を Code Retrospective に追記 (CONSIDER fix)。いずれも Spec ファイル内の記述整合性を取るための変更で、Issue 側の AC テキストや GitHub の検証結果には影響しない。
- レビューは GitHub 上で self-authored PR のため `REQUEST_CHANGES` を発行できず (422)、`COMMENT` イベントで投稿。MUST issue は本文と Step 14 のレスポンスサマリーで明示している。

### Deferred Items
- `run-spec.sh <N> --fable` の実測実行そのもの (2〜3件の backlog Issue)。ユーザーの明示認可が必要 — `/code` フェーズからの継続的な deferral。
- 実測データに基づく `WATCHDOG_TIMEOUT_SPEC_DEFAULT` の引き上げ要否判定。
- 上記実測が行われた場合の `tests/watchdog-defaults.bats` 74行目の期待値更新 (値変更時のみ)。

### Notes for Next Phase
- `/merge` 前にユーザーが本 PR の Summary (2件の未達 AC と判断根拠) を確認し、実測実行の要否を判断すること。
- Post-merge AC (opportunistic observation) は次回 `--fable` spec 実行時に自動検証される想定。
