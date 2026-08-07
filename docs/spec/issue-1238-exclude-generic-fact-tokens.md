# Issue #1238: collect-run-facts: fact_tokens の汎用語を排除し絞り込み率を上げる

## Overview

`scripts/collect-run-facts.sh` が生成する `fact_tokens` には、phase 名由来の汎用語 (`issue` / `spec` / `code` / `code-pr` / `code-patch` / `review` / `merge` / `verify`) が bare な (namespace/prefix なしの) 単語としてそのまま含まれている。AC の condition text はほぼ必ずこれらの語を含むため、`scan-pending-ac.sh --facts` / `opportunistic-search.sh --facts` の絞り込みが実質的に無効化される。特に `opportunistic-search.sh` はスキル名 (`/verify` 等) で候補集合を事前に絞り込んだ後に同じ skill 名由来の bare token (`verify`) で照合するため、定義上 100% が通過する (実測 13→13, session `83694-1786088052`)。`scan-pending-ac.sh` 経路でも同様の理由で 418→186 (55.5% 除外) に留まっている (session `3340-1786079730`)。

本 Issue は `collect-run-facts.sh` の `fact_tokens` 生成から、この bare な phase 名 token を除外する (すでに `/auto` / `single` token が同じ理由で除外済み — 本変更はその延長)。`Size S` / `pr route` / `#1234` / `run-issue.sh` 等、既に十分に識別力のある token は変更しない。

## Changed Files

- `scripts/collect-run-facts.sh`: change — `JQ_PASS2` の `fact_tokens` 構築から bare な phase 名 (`$names` そのもの) を除外し、`wrapper_for()` でマッピングされる script 名 token (`run-issue.sh` 等) のみを残す。ヘッダーコメントの `fact_tokens` 説明に、既存の `/auto`/`single` 除外の記述と並べてこの新しい除外を追記する。純粋な jq 式の変更で bash 3.2+ 互換 (bash バージョン依存の構文は触れない)
- `modules/run-fact-matching.md`: change — `fact_tokens` の語彙 (route / size / phase-wrapper script 名 / PR 番号 / anomaly キー / recovery tier / batch mode) と、意図的に除外されているカテゴリ (bare phase 名, `/auto`, `single`) を記述するサブセクションを追加。マッチング規則 (大文字小文字を無視した部分文字列一致、本 Issue で変更なし) と、AC 執筆者向けの指針 (bare な phase 名に依存した表現では絞り込みが効かないため、Size/route/PR番号/anomaly 等のより具体的な事実を記述すること) を含める
- `tests/run-fact-matching.bats`: change — bare phase 名 token (例: `review`, `code-pr`) が `fact_tokens` から除外され、対応する wrapper script token (例: `run-review.sh`) は残ることを確認する新規 `@test` を追加

## Implementation Steps

1. `scripts/collect-run-facts.sh` の `JQ_PASS2` を変更し、`fact_tokens` の加算対象から bare な `$names` を外し、`wrapper_for()` マッピング後の値のみを残す。ヘッダーコメントの `fact_tokens` 説明に本除外 (Issue #1238) を追記する (→ acceptance criteria AC1)
2. `modules/run-fact-matching.md` に `fact_tokens` の語彙とマッチング規則、AC 執筆者向け指針を記述するサブセクションを追加する (parallel with 1) (→ acceptance criteria AC2)
3. `tests/run-fact-matching.bats` に、bare phase 名 token の除外と wrapper script token の保持を確認する新規テストを追加する (after 1) (→ acceptance criteria AC4)
4. `bats tests/run-fact-matching.bats tests/opportunistic-search.bats` を実行し全件 PASS することを確認する (after 1, 3) (→ acceptance criteria AC4, AC5)
5. 変更後の `collect-run-facts.sh` に対して両経路 (`scan-pending-ac.sh` / `opportunistic-search.sh`) の絞り込み効果を再測定し、本 Spec の `## Verification` セクションのベースライン行の直下に実装後の件数を追記する (after 1)。`.tmp/auto-events.jsonl` に session `3340-1786079730` / `83694-1786088052` の生イベントが現存しない場合は、Issue 本文 Background に引用されている fact_tokens 配列を新ロジックで手動再構成した代表 JSON を用いて `--facts` 経由で再測定する (→ acceptance criteria AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/collect-run-facts.sh の fact_tokens 生成が、汎用語による部分一致誤ヒットを排除する方式 (名前空間化 / stop-word 除外 / 重み付けのいずれか) に変更されている。採用した方式と既存 AC との互換方針が実装コメントまたは modules/run-fact-matching.md に記録されていること" --> fact_tokens の語彙が誤ヒットを排除する方式に変更されている
- <!-- verify: rubric "modules/run-fact-matching.md に、変更後の token 語彙とマッチング規則が記述されている。AC 側で token をどう書くべきかの指針を含むこと" --> `run-fact-matching.md` に語彙とマッチング規則が記述されている
- <!-- verify: rubric "変更前後の絞り込み件数の比較が Spec の Verification セクションに数値で記録されている。scan-pending-ac.sh 経路のベースラインは 418 件 → 186 件 (session 3340-1786079730)、opportunistic-search.sh 経路のベースラインは 13 件 → 13 件 (session 83694-1786088052)。両経路の変更後件数が記録されていること" --> 絞り込み効果が両経路について数値で記録されている
- <!-- verify: command "bats tests/run-fact-matching.bats tests/opportunistic-search.bats" --> `collect-run-facts.sh` の fact_tokens 生成をカバーする既存テスト (`tests/run-fact-matching.bats` / `tests/opportunistic-search.bats`) が PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) が PR で pass する

**Effect measurement (baseline)**: scan-pending-ac.sh 経路 418 件 → 186 件 (55.5% 除外, session `3340-1786079730`, 2026-08-07 計測, Issue #1238 本文記載)。opportunistic-search.sh 経路 13 件 → 13 件 (0% 除外, session `83694-1786088052`, 2026-08-07 計測, Issue #1238 本文記載)。Implementation Step 5 の実施後、`/code` はこの行の直下に実装後の件数・facts のソース (実セッション再実行 or 代表 JSON)・計測日を追記すること (AC3 の充足条件)。

**Effect measurement (after implementation, 2026-08-08)**: `.tmp/auto-events.jsonl` に session `3340-1786079730` / `83694-1786088052` の生イベントは現存しない (Notes 記載のとおりローテーション済み) ため、両経路とも Issue 本文引用の fact_tokens 配列を新ロジックで手動再構成した代表 JSON (`--facts` 経由) で再測定した。母集団は測定時点 (2026-08-08) の現在の Issue 集合を使用したため、ベースライン計測時点 (2026-08-07) との間に自然な件数のドリフトがある — そのため同一母集団に対して旧語彙 (bare phase 名を含む、変更前の実装を手動再現) と新語彙 (本実装後の `fact_tokens`) を両方適用し、同一母集団内での差分として効果を確認した。

- **scan-pending-ac.sh 経路**: 現在の母集団 422 件 (`--max-candidates 10000` で truncation なく計測。ベースライン計測時の 418 件から自然増)。session `3340-1786079730` の fact_tokens (`["Size S","issue","run-issue.sh","run-spec.sh","spec"]`) をそのまま (旧語彙として) 適用すると **185 件** (55.9% 除外) — ベースラインの 186 件とほぼ一致し、旧ロジックの再現性を確認。同じ token 配列から bare な `issue`/`spec` を除いた新語彙 (`["Size S","run-issue.sh","run-spec.sh"]`) を適用すると **2 件** (99.5% 除外) まで減少した。
- **opportunistic-search.sh 経路**: 現在の `/verify` 母集団 13 件 (ベースラインと同数)。session `83694-1786088052` を模した batch route・Size M・issue→spec→code(pr)→review→merge→verify を経た代表的 fact_tokens について、旧語彙 (`["pr route","Size M","issue","spec","code-pr","review","merge","verify","run-issue.sh","run-spec.sh","run-code.sh","run-review.sh","run-merge.sh","batch"]`、bare `verify` を含む) を適用すると **13 件** (0% 除外) — ベースラインの 13→13 を再現。同じ token 配列から bare な phase 名 (`issue`/`spec`/`code-pr`/`review`/`merge`/`verify`) を除いた新語彙 (`["pr route","Size M","run-issue.sh","run-spec.sh","run-code.sh","run-review.sh","run-merge.sh","batch"]`) を適用すると **0 件** (100% 除外) まで減少した。`verify` phase は `wrapper_for()` マッピングを持たないため、新語彙では一切のトークンを生成しない (意図した挙動、Notes 参照)。

両経路とも、同一母集団内の旧語彙比較で絞り込み効果の大幅な改善を確認した (scan-pending-ac.sh: 185→2、opportunistic-search.sh: 13→0)。facts のソース: 実行中の `/auto` セッションが存在しない単発実行環境のため、`collect-run-facts.sh` の出力形式に相当する代表的 JSON (`.tmp/facts-old-1238.json` / `.tmp/facts-new-1238.json` / `.tmp/facts-old-opp-1238.json` / `.tmp/facts-new-opp-1238.json`、いずれも `.tmp/` は gitignore 対象で本コミットには含まれない) を使用した。

### Post-merge

- 次回以降の `/auto` 完走後の Run-fact AC reconciliation で、絞り込み後の候補件数が変更前より減少していることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **設計方式の選定 (Auto-Resolved, non-interactive mode)**: Issue 本文は案 A-2 (token の名前空間化 + `scan-pending-ac.sh` 側で「`:` の右辺のみ」でも一致させるマッチング規則変更) を推奨していたが、本 Spec ではこれを採用せず、**bare な phase 名 token (`issue`/`spec`/`code`/`code-pr`/`code-patch`/`review`/`merge`/`verify`) を fact_tokens 生成から除外する** (案 B を、実測で判明した汎用語に対してのみ外科的に適用する) 方式を採用した。
  - **理由 1 (A-2 の回帰リスク)**: A-2 の「namespace 化した token は `:` の右辺のみでも一致させる」というマッチング規則をそのまま適用すると、`Size S` / `Size M` のような既に安全な token (namespace 化すると RHS が `S`/`M` の1文字になる) の一致精度が著しく悪化する。1文字の RHS 部分文字列一致は、現状の `issue`/`spec` 等の汎用語問題よりも遥かに強い誤ヒットを生むため、A-2 をそのまま全 token に適用するのは新たな回帰を生む
  - **理由 2 (Issue 本文自身の分析と整合)**: Background 記載の「スキル名フィルタが既に同じ選別を行っているため、除外しても情報損失が実質ゼロ」という opportunistic-search.sh 経路の分析、および「識別力のある token (`Size S`/`run-issue.sh`/`run-spec.sh`) は既に機能している」という scan-pending-ac.sh 経路の分析は、いずれも「bare な phase 名 token 自体に単独の価値がない」ことを示しており、新しい token 語彙体系を導入せずとも単純な除外で AC1 の「誤ヒットを排除する」という要求 (「維持」ではなく「排除」) を満たせる
  - **理由 3 (Simplicity)**: `scan-pending-ac.sh` / `opportunistic-search.sh` 側のマッチングロジックを一切変更せずに済み、両スクリプトの既存テストが無改修で PASS し続ける (回帰リスクが `collect-run-facts.sh` 単体に閉じる)
  - 他候補: 案 A-2 (不採用: 理由1)、案 A-3 全既存 AC 書き換え (不採用: 移行コスト大。Issue 本文も「最も効果が高いが移行コストが大きい」と明記)、案 A-1 新旧併記 (不採用: 誤ヒットがそのまま残り AC1 の「排除」要求を満たさない)
  - AC1 の「既存 AC との互換方針」: 本方式は AC 側の書き換えを一切必要としない。既存 AC は無変更のまま機能し続け、bare phase 名への偶発的な部分一致 (誤ヒットの原因そのもの) だけが失われる — これが意図した効果である
- **`.tmp/auto-events.jsonl` のログローテーション**: Issue 本文が引用する2セッション (`3340-1786079730` / `83694-1786088052`) の生イベントは、本 Spec 作成時点 (2026-08-08) で `.tmp/auto-events.jsonl` から既にローテーション済みで現存しない (現存するのは別セッションの `worktree-path-block` イベント1行のみ)。Implementation Step 5 は Issue 本文記載の fact_tokens 配列を手動再構成した代表 JSON で代替測定すること (`docs/spec/issue-1239-opportunistic-fact-filter.md` の代表 JSON パターンに準拠)
- **`verify` token の `wrapper_for()` 非対応**: `/verify` skill は `run-verify.sh` を持たない (in-session 実行、`docs/tech.md` Fork context 表参照)。したがって `wrapper_for("verify")` は変更前から `null` を返しており、本変更後は `verify` phase が fact_tokens に一切寄与しなくなる。opportunistic-search.sh 経路の 13→13 の主因は正にこの bare `verify` token であったため、これは意図した挙動である
- **Issue 本文との整合性確認**: Background の事実主張 (`collect-run-facts.sh` の `fact_tokens` 生成ロジック、`scan-pending-ac.sh`/`opportunistic-search.sh` の部分文字列マッチング方式、`/auto`/`single` の既存除外) はいずれもコードベース実測 (`scripts/collect-run-facts.sh` JQ_PASS2, `scripts/scan-pending-ac.sh`, `scripts/opportunistic-search.sh` の該当箇所) で確認済み。矛盾なし
- **patch route 検証**: `ALWAYS_PR=false` かつ Size=M → pr route (PR が存在する) のため `github_check "gh pr checks" "Run bats tests"` はそのまま正しい形。`.github/workflows/test.yml` のジョブ名が `Run bats tests` であることを確認済み。修正不要
- **BRE メタ文字チェック**: Issue 本文の verify command はいずれも `rubric`/`command`/`github_check` で `grep` 形式は含まれない。該当なし

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1238#issuecomment-5218544266
