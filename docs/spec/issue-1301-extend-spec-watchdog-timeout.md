# Issue #1301: auto: spec フェーズの watchdog timeout を実測に見合う値へ延長

## Overview

`/spec` フェーズの watchdog timeout 既定値 (1800s) が、実測の silent window に対して余裕を失っている。2 セッション連続 (2026-08-08, 2026-08-09) の `/auto --batch` 実行で、spec フェーズの閾値超過 5 回・watchdog kill 1 回・最小余裕 10 秒を記録し、前セッションの L3 retrospective が設定した「再発時に判断」という保留条件を満たした。`.wholework.yml` に project override (`watchdog-timeout-spec-seconds: 2340`) を追加し、閾値到達によるリトライ発生 (実行時間・トークンの二重消費) を抑える。

## Changed Files

- `.wholework.yml`: `watchdog-timeout-spec-seconds: 2340` を追加 (実測根拠と override 判断理由をコメントに記載)
- `docs/tech.md`: 既存の `#939 (WATCHDOG_TIMEOUT_SPEC_DEFAULT re-check...)` 段落末尾に、本 Issue の project override 判断への短いフォローアップ注記を追記

## Implementation Steps

1. `.wholework.yml` に `watchdog-timeout-spec-seconds: 2340` を追加する。コメントには (a) 実測レンジ (1690–1790s、既定 1800s に対する余裕 10–110s、kill 1 回)、(b) 採用値の根拠 (既定 1800s に #903 と同じ ×1.3 係数を適用し 2340s)、(c) project override に留める判断とその理由、の 3 点を記載する — 既存の `watchdog-timeout-code-seconds` / `watchdog-timeout-review-seconds` エントリと同じ形式・同じ場所に揃える (→ 受入条件 1, 2)
2. `docs/tech.md` の `#939 (WATCHDOG_TIMEOUT_SPEC_DEFAULT re-check...)` 段落末尾に、本 Issue の project override 判断への短いフォローアップ注記を追記する。既存の「Verdict: maintain」文はその時点の実測に基づく正しい記録のため変更しない (parallel with 1)

## Verification

### Pre-merge

- <!-- verify: grep "watchdog-timeout-spec-seconds" ".wholework.yml" --> `.wholework.yml` に `watchdog-timeout-spec-seconds` が設定されている
- <!-- verify: rubric ".wholework.yml の watchdog-timeout-spec-seconds に、既存の code / review エントリと同様、実測に基づく延長理由のコメントが付与されており、かつ project override に留めるかグローバル既定値も変更するかの判断とその理由が同コメント内に記載されている" --> 設定値の根拠 (実測レンジと採用値の関係)、および project override に留めるか `scripts/watchdog-defaults.sh` の既定値も変更するかの判断と理由が `.wholework.yml` のコメントに記載されている

### Post-merge

- 次回以降の `/auto` セッションで、spec フェーズの silent window が watchdog limit に対して十分な余裕を持つ (`within 600s of watchdog limit` の警告が spec 行に出ない) ことを観察する

## Notes

### 採用値 2340s の根拠

既定値 1800s に、`docs/tech.md` の watchdog 再較正で確立済みの ×1.3 係数 (#903: `WATCHDOG_TIMEOUT_CODE_DEFAULT` 3600→4680、`WATCHDOG_TIMEOUT_REVIEW_DEFAULT` 2000→2600 の初回パスと同じ係数) を適用し、1800 × 1.3 = 2340 とした。直近セッションの実測クリーンサンプル (kill を含まない) は 1690s / 1790s で、2340s に対する使用率は最大 76.5% (1790/2340) — このリポジトリの再較正トリガー閾値 (実測が既定値の 80% 以上に達したら引き上げる) を下回る水準に収まる。前セッションの 4070s (kill 後のリトライを含む可能性がある、と Issue 本文が明記) は根拠として採用しなかった。

### project override 対 global default

`scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_SPEC_DEFAULT` (global default) ではなく、`.wholework.yml` の project override に留めた。理由:

1. 実測データが本 repo (wholework 自身の dogfooding) の 2 セッション分に限られ、#903 の再較正パス (code: n=10, review: n=9) と比べてサンプル数が少ない
2. review フェーズの先例と同じ段階を踏む — PR #1201 でまず `.wholework.yml` override として即時対応し、後続の別 Issue (#939) でより多くの実測を経てから global default へ昇格した。本 Issue はこの「即時 override」の段階に相当する
3. 再発が続く場合は、#939 と同様の別 Issue で global default への昇格を検討する (`docs/tech.md` に revisit trigger を明記した)

### Issue 本文 Acceptance Criteria の修正 (`/spec` Comment Consumption)

`/issue` Step 15 の AC audit ([コメント](https://github.com/saitoco/wholework/issues/1301#issuecomment-5229911809)) が、Pre-merge の元 bullet 3・4 の verify command に問題を指摘した:

- 元 bullet 3 (rubric: 「project override か global default 変更かの判断が Spec に記載されている」) — `modules/verify-executor.md` § Rubric Command Semantics により rubric grader には Spec ファイルが渡らない (Issue=WHAT / Spec=HOW 分離のため) ため、Spec にしか記載がなければ grader が恒久的に証拠へ到達できない
- 元 bullet 4 (rubric: 「resolve 関数が watchdog-timeout-spec-seconds を解決することが確認されている」) — `scripts/watchdog-defaults.sh` の `load_watchdog_timeout()` は既に `get-config-value.sh "watchdog-timeout-${phase}-seconds"` という phase 非依存の汎用形で解決しており、元 bullet 1 (値の設定) が満たされた時点で自動的に真になる。独立した検証シグナルを持たない

本 Spec ではこの指摘に従い、元 bullet 3 の要求 (override 対 global default の判断理由) を bullet 2 に統合し `.wholework.yml` のコメント (grader が `git diff` から到達できる範囲) に記載する形へ変更し、元 bullet 4 は削除した。Issue 本文は本 `/spec` フェーズの Comment Consumption Procedure 内で既に更新済み。

### resolve 関数の動作確認 (追加のコード変更が不要であることの確認)

上記の元 bullet 4 削除に伴い、「設定値が実際に読まれるか」の確認を Notes に記録する。`scripts/watchdog-defaults.sh:45` の `load_watchdog_timeout()` は `$phase` 変数を使った汎用形 (`get-config-value.sh "watchdog-timeout-${phase}-seconds"`) で解決しており、`watchdog-timeout-spec-seconds` は追加のコード変更なしに解決可能であることをコード読解で確認した。さらに、`.wholework.yml` へ実際に `watchdog-timeout-spec-seconds: 2340` を設定した状態で `load_watchdog_timeout "scripts" "spec"` を実行し、`WATCHDOG_TIMEOUT=2340` が返ることを実測で確認した (`watchdog-timeout-review-seconds: 5400` の既存解決結果が変わらないことも合わせて確認)。`tests/watchdog-defaults.bats` の既存 `@test "load_watchdog_timeout uses phase-specific default when phase is spec"` はグローバル既定値 1800 を検証する内容であり、本 Issue はグローバル既定値を変更しないため、この既存テストへの変更は不要。

### `docs/tech.md` 追記の位置づけ

`docs/tech.md` の Watchdog timeout calibration 節は、#903 / #939 など過去の全ての再較正・再評価が追記形式で履歴を積み上げている (SSoT ではないが、再較正判断の一次記録)。本 Issue も同節の既存 spec 段落 (#939) にフォローアップ注記を追記し、この蓄積パターンに揃えた。Issue 本文には正式な Pre-merge 受入条件として追加していない (SHOULD レベルの一貫性改善であり、Issue の Purpose の中心ではないため) — Implementation Step 2 として記録し、`/code` での実施を期待する。

## Consumed Comments

- saito / MEMBER / first-class / ⚠️ `/issue` AC audit (Step 15): verify command に問題があります / https://github.com/saitoco/wholework/issues/1301#issuecomment-5229911809
