# Issue #1255: tests: 並列 bats 実行下でのみ落ちる flaky を機械的に切り分ける

## Overview

並列 bats 実行 (`bats --jobs N`) でのみ FAIL し単独実行では PASS するテストが、CI (`.github/workflows/test.yml`) や `/auto --batch` セッションで継続的に観測されている (#1221, #1224, #1227 他。`docs/spec/` 横断で flaky への言及は 12 spec)。これを検知・分類する常設の仕組みが存在せず、`github_check` 系 AC の偽 FAIL や `/merge` の CI ゲート判断が毎回 LLM の裁量に委ねられている。

本 Spec は検討候補「B. CI に切り分け job を追加」を、bats-core が標準搭載するネイティブフラグ `--filter-status failed` (前回実行で FAIL したテストのみを再実行) を用いて実装する。新規スクリプトは追加せず、`.github/workflows/test.yml` の `bats` job 内に閉じる。検出粒度はテスト単位を採用する。採否の判断根拠・不採用案の理由は `## Notes` を参照。

## Changed Files

- `.github/workflows/test.yml`: change — `bats` job に、`--jobs` 並列実行後に FAIL したテストのみを単独 (非並列) で再実行し結果を `$GITHUB_STEP_SUMMARY` に出力するステップを追加する。並列実行時のみ FAIL し単独再実行で全件 PASS すれば job は成功として扱い、単独再実行でも FAIL するテストが1件でも残れば job は失敗のまま維持する
- `.gitignore`: change — `tests/.bats/` を追加 (bats の `--filter-status` が要求する実行履歴ディレクトリ。bats 自身がコミット対象外にするよう指示している)
- `docs/structure.md`: change — `## CI Workflows` の `.github/workflows/test.yml` の一行説明に、並列限定 flaky 切り分けステップの追加を反映
- `docs/ja/structure.md`: change — 上記の日本語訳を同期 (`docs/translation-workflow.md` の同期規則に従う)

## Implementation Steps

1. `.github/workflows/test.yml` の `bats` job を変更する。既存の "Run bats tests" ステップの直前 (同ステップの `run:` 内、またはその前段の独立ステップ) で `mkdir -p tests/.bats/run-logs` を実行し、当該ステップに `id: bats` と `continue-on-error: true` を付与する。続けて新規ステップ (`if: steps.bats.outcome == 'failure'`, `continue-on-error` は付与しない) を追加し、`bats --filter-status failed tests/` で前回 FAIL したテストのみを非並列で再実行して `$GITHUB_STEP_SUMMARY` に結果を書き出す。このステップ自身の exit code が job 全体の最終的な成否を決定する (→ acceptance criteria AC1)
2. `.gitignore` に `tests/.bats/` を追加する (parallel with 1) (→ acceptance criteria AC1 の実行基盤)
3. `docs/structure.md` の `## CI Workflows` にある `.github/workflows/test.yml` の説明行を更新し、並列限定 flaky 切り分けステップの追加を反映する (after 1)
4. `docs/ja/structure.md` の対応行を日本語で同期する (after 3)

## Verification

### Pre-merge

- <!-- verify: rubric "並列 bats 実行下でのみ FAIL するテストを、単独実行での PASS/FAIL と突き合わせて機械的に切り分ける経路が実装されている (scripts/ 配下のスクリプト、CI workflow の job、またはその両方)。切り分け結果が呼び出し元から参照可能な形で出力されること" --> 並列のみ FAIL するテストを機械的に切り分ける経路が実装されている
- <!-- verify: rubric "採用した案 (A/B/C のいずれか、または組み合わせ) と不採用案の理由が Spec に記録されており、CI 時間・実行副作用のトレードオフが明示的に判断されている" --> 案の採否とトレードオフ判断が記録されている

### Post-merge

- 次回 CI で並列実行由来の FAIL が発生した際、本物の失敗と区別されて報告されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **採用案**: 検討候補 B (CI に切り分け job/step を追加) を、bats-core 標準機能 `--filter-status failed` で実装する。
  - **B を採用した理由 (実害への直結)**: Issue 本文が挙げる 2 つの実害経路 (`github_check` 系 AC の偽 FAIL、`/merge` の CI ゲート) はいずれも CI run の結果 (`gh pr checks` / `gh run list`) を参照する。CI job 自体が「並列実行時のみの flaky」を切り分けて job の成否に反映すれば、両経路とも追加の下流変更なしに解消する。一方、案 A (`test-failure-classify.sh` 拡張) は現状 `/code` Step 9 の Tier 0 (ローカル、コミット前) からのみ呼ばれ CI run の成否には一切関与しないため、実害2経路を閉じるには結局 CI 側の変更が別途必要になり B を避けられない
  - **A を不採用とした理由 (責務混在)**: `test-failure-classify.sh` は `--log <file>` を受け取り純粋にテキストパターン分類するだけの副作用なしスクリプトである (`/code` Step 9 Tier 0 の唯一の呼び出し元)。これを「実行して再実行結果で分類する」機能に拡張すると、既存の「ログ分類」という単一責務に「テスト実行」という別責務が混在する。Tier 0 は既に自前の再実行ロジック (1回リトライ) を持っており、安易に統合すると Tier 0 の呼び出し契約を変える回帰リスクを負う
  - **C を不採用とした理由 (事後性、ただし将来の併用は妨げない)**: 案 C (`docs/reports/` への累積閾値検出、`collect-recovery-candidates.sh` 同型) は長期的なパターン可視化に価値があるが、単一の CI run 内でその場で切り分けることはできない (事後集計)。今回の実害は「その run 自体」の判定に関わるため即時性のある B が必須。C は Issue 本文も「A/B と直交し併用可能」と明記しており、本 Issue のスコープ外の follow-up 候補として残す
  - **検出粒度 (テスト単位を採用、ファイル単位は見送り)**: bats `--jobs` はファイル単位で並列化され、同一ファイル内のテストは元々シリアル実行される (`docs/spec/issue-177-ci-bats-speed.md` で確認済みの既存知見)。#1227 で観測された「同一ファイル内の複数テストが揃って FAIL」は、この事実と整合的に「同一ファイル内の真の並行実行」ではなく「複数ファイルワーカーが同時実行することによる CPU/IO 競合」由来と考えられる。ファイル単位の attribution を確実に行うには `--report-formatter junit` の XML 解析が必要になるが、本リポジトリの `@test` 命名規約はファイル名プレフィックス方式 (`tests/workflow-guidance.bats` の `"workflow-guidance: ..."` 等) とカテゴリプレフィックス方式 (`tests/get-issue-size.bats` の `"success: ..."` 等) が混在しており実測で確認済みのため、テスト名文字列からの file 逆引きは信頼できない。bats 標準機能 `--filter-status failed` はテスト単位で完結し、この不確実性を回避できるため、`/issue` が明示した「テスト単位を最低ラインとする」方針のままテスト単位を採用した。ファイル単位の attribution が必要になった場合は `--report-formatter junit` を使った拡張を follow-up として検討できる
- **技術検証 (bats バージョン)**: `--filter-status` は bats-core 1.8.0 (2022-09-15) で追加された機能であり (公式 CHANGELOG で確認)、ubuntu-latest の apt パッケージ (`docs/spec/issue-177-ci-bats-speed.md` で 1.10.0 系と確認済み) は要件を満たす。ローカル bats (Homebrew, 1.13.0) でも実機検証済み: ディレクトリに対し `bats <dir>` で 1 件 FAIL させた後、`bats --filter-status failed <dir>` が当該 1 件のみを再実行し正しく分類することを確認した。`tests/.bats/run-logs/` ディレクトリが事前に存在しないと明示的エラーで停止することも確認済みのため、Implementation Step 1 で `mkdir -p` を必須としている
- **`continue-on-error` の job 成否への影響 (GitHub 公式ドキュメント + Web 検索で確認)**: ステップレベルの `continue-on-error: true` は、そのステップが FAIL しても job 全体の結論には影響しない — job は当該ステップの失敗を無視して次のステップに進み、後続ステップが成功すれば job 全体は success になる。これにより「元の並列実行が FAIL → 単独再実行が全件 PASS → job は success」という設計が意図通り機能する。既存の多数の Spec が参照する `github_check "gh pr checks" "Run bats tests"` の job 名 `Run bats tests` (`.github/workflows/test.yml` 9行目、job 定義の `name:`) 自体は変更しないため、既存 AC との互換性に影響しない
- **Issue 本文との整合性確認**: Background の事実主張 (`.github/workflows/test.yml:29` が `bats --jobs $(nproc) tests/` であること、`scripts/test-failure-classify.sh` が現状パターン分類のみで再実行を行わないこと) はいずれもコードベース実測で確認済み。矛盾なし
- **patch route 検証**: 該当なし。Size=M・`ALWAYS_PR=false` のため pr route であり、本 Issue の Pre-merge AC は `rubric` のみで `github_check "gh pr checks"` を含まないため、patch route 向けの自動修正チェックは対象外
- **BRE メタ文字チェック**: 該当なし。verify command はいずれも `rubric` 形式で `grep` を含まない

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1255#issuecomment-5218891812
