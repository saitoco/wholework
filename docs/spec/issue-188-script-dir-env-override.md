# Issue #188: scripts: SCRIPT_DIR ベースの絶対パスを環境変数オーバーライド可能にして BATS モック戦略を統一

## Overview

Wholework の 17 個の scripts/*.sh が `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` で初期化され、`"$SCRIPT_DIR/helper.sh"` 形式で sibling scripts を呼び出している。この絶対パス解決が BATS テストの PATH ベースモック (`PATH="$MOCK_DIR:$PATH"`) を回避してしまうため、Issue #183 の `setup-labels.bats` では `gh-graphql.sh` のモック戦略を全面書き直し (`gh api graphql` レベルでのモック) する rework が発生した。

本 Issue では `SCRIPT_DIR` 初期化を `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` パターンに統一し、BATS テスト側が `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` するだけで sibling scripts を直接モックできるようにする。加えて `setup-labels.bats` を新しいモック戦略に書き直し、`docs/tech.md` の Testing Strategy セクションに規約として記録する。

## Changed Files

### scripts 系 (17 ファイル、全て同一パターンの変更)

各ファイルの `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` を `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` に変更する。

- `scripts/setup-labels.sh`: SCRIPT_DIR 行を env var override 対応
- `scripts/gh-label-transition.sh`: 同上
- `scripts/run-merge.sh`: 同上
- `scripts/gh-check-blocking.sh`: 同上
- `scripts/validate-permissions.sh`: 同上 (PROJECT_ROOT="$SCRIPT_DIR/.." も override 経由で解決されるため追加変更不要)
- `scripts/run-auto-sub.sh`: 同上
- `scripts/get-sub-issue-graph.sh`: 同上
- `scripts/run-verify.sh`: 同上
- `scripts/run-spec.sh`: 同上
- `scripts/get-issue-type.sh`: 同上
- `scripts/get-issue-priority.sh`: 同上
- `scripts/check-file-overlap.sh`: 同上 (REPO_ROOT も同様)
- `scripts/get-issue-size.sh`: 同上
- `scripts/test-skills.sh`: 同上 (PROJECT_ROOT も同様)
- `scripts/run-review.sh`: 同上
- `scripts/run-code.sh`: 同上
- `scripts/run-issue.sh`: 同上

### tests 系 (1 ファイル、モック戦略書き直し)

- `tests/setup-labels.bats`: `setup()` で `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を export し、`$MOCK_DIR/gh-graphql.sh` にモックを配置。`gh` モックから `api graphql` 特殊処理を削除しラベル操作のみに簡素化。22 個の既存テストケースは全てそのまま通ることを確認

### docs 系 (1 ファイル、規約追記)

- `docs/tech.md`: `## Testing Strategy` セクションに `WHOLEWORK_SCRIPT_DIR` を用いた BATS モック規約の段落を追加 (既存テーブルの直後、`## Forbidden Expressions` の前)
- `docs/ja/tech.md`: 翻訳出力ファイルのため本 PR 内では更新しない (`/doc translate ja` で事後同期)

### Issue body 側の調整

- Issue #188 body の `## Acceptance Criteria > Pre-merge` から、count 集約型 `command` hint (`test $(grep -l ... | wc -l) -eq 0`) を削除し post-merge opportunistic に移動 (`modules/verify-patterns.md` #32 学習: count 集約は `/review` safe mode で UNCERTAIN になり CI ジョブと相関しづらいため post-merge へ)

## Implementation Steps

**Step recording rules**: integer step numbers only; acceptance criteria mapping per step.

1. 17 個の scripts/*.sh の `SCRIPT_DIR` 行を `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` に一斉変更する。各ファイルで該当行は 1 箇所のみ (Grep で事前確認済み)。`set -euo pipefail` 配下でも `${VAR:-default}` は nounset エラーにならないため安全 (→ AC #1, #2, #3, #4)

2. `tests/setup-labels.bats` の `setup()` を書き直し (→ AC #5, #6):
   - `MOCK_DIR="$BATS_TEST_TMPDIR/mocks"` は維持
   - `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を追加
   - `$MOCK_DIR/gh-graphql.sh` に直接 count を返す shell script モックを配置 (`echo "1"` / `echo "0"` のパターン)
   - 既存の `gh` モックから `api graphql` ハンドリング分岐を削除し、label 系処理のみに簡素化
   - 各テストケース (`env=full`, `env=none`, `idempotent`, `--force`, `--no-fallback`, `env-detect-fail`, `error`, `colors`, `output`) の 22 件全てが引き続き PASS することを確認する。count 比較値 (11 always, 28 total, etc.) は変更しない

3. `docs/tech.md` の `## Testing Strategy` セクションに、既存テーブルの直後かつ `## Forbidden Expressions` の前に以下の段落を追加する (→ AC #7):

   ```markdown
   ### BATS Mocking Convention

   Scripts under `scripts/` resolve sibling helpers through `SCRIPT_DIR`, which is
   overridable via the `WHOLEWORK_SCRIPT_DIR` environment variable. BATS tests set
   `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` and place mock helpers (e.g.
   `$MOCK_DIR/gh-graphql.sh`) under the mock directory. This allows per-test
   substitution of arbitrary sibling scripts without falling back to mocking
   lower-level tools such as `gh api graphql`.
   ```

   テキストには `WHOLEWORK_SCRIPT_DIR` と `MOCK_DIR` を明示的に含め、`section_contains` verify command が PASS するようにする

4. ローカルで `bats tests/setup-labels.bats` を実行し、22 件全てが PASS することを確認する。失敗する場合は step 2 のモック実装を見直す (→ AC #8 への間接担保)

5. Issue #188 の body を更新: `## Acceptance Criteria > Pre-merge` から count 集約 `command` hint の 1 項目を削除 (pre-merge 9→8)、`## Acceptance Criteria > Post-merge` に `verify-type: opportunistic` として「$SCRIPT_DIR/ を sibling 参照する全 scripts/*.sh が WHOLEWORK_SCRIPT_DIR に対応していることを確認」を追加 (post-merge 1→2)

6. 変更を commit & push し、CI (`test.yml` の bats ジョブ) が PASS することを確認する (→ AC #8)

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/setup-labels.sh" "WHOLEWORK_SCRIPT_DIR" --> `scripts/setup-labels.sh` が `WHOLEWORK_SCRIPT_DIR` 環境変数によるオーバーライドに対応している
- <!-- verify: file_contains "scripts/gh-label-transition.sh" "WHOLEWORK_SCRIPT_DIR" --> `scripts/gh-label-transition.sh` が同じパターンに対応している
- <!-- verify: file_contains "scripts/run-auto-sub.sh" "WHOLEWORK_SCRIPT_DIR" --> `scripts/run-auto-sub.sh` が同じパターンに対応している (代表的な大型 orchestrator script)
- <!-- verify: file_contains "scripts/gh-check-blocking.sh" "WHOLEWORK_SCRIPT_DIR" --> `scripts/gh-check-blocking.sh` が同じパターンに対応している (sibling script を inline 呼び出しする script の代表)
- <!-- verify: file_contains "tests/setup-labels.bats" "WHOLEWORK_SCRIPT_DIR" --> `tests/setup-labels.bats` が `WHOLEWORK_SCRIPT_DIR` を利用した PATH ベースのモック戦略 (`gh-graphql.sh` を `MOCK_DIR` に配置してスタブ) で書き直されている
- <!-- verify: file_contains "tests/setup-labels.bats" "MOCK_DIR" --> `tests/setup-labels.bats` が `MOCK_DIR` を用いたモックディレクトリを設定している
- <!-- verify: section_contains "docs/tech.md" "Testing Strategy" "WHOLEWORK_SCRIPT_DIR" --> `docs/tech.md` の Testing Strategy セクションに `WHOLEWORK_SCRIPT_DIR` を用いた BATS モック規約が記載されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テスト CI が PASS する

### Post-merge

- 新しく BATS テストを追加する際に `WHOLEWORK_SCRIPT_DIR` を利用したモック戦略が機能することを opportunistic に確認する
- `$SCRIPT_DIR/` で sibling script を参照している `scripts/*.sh` が全て `WHOLEWORK_SCRIPT_DIR` オーバーライドに対応していることを、次回の関連 PR レビュー時に opportunistic に確認する

## Notes

### env var override パターンの後方互換性

`${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}` は env var が未設定/空のとき従来のパス解決にフォールバックする。`set -u` (nounset) 環境でも `:-` 形式は安全。本番環境では `WHOLEWORK_SCRIPT_DIR` が設定されることはないため、動作は完全に従来通り。

### 子プロセスへの env var 伝播

BATS テストが `export WHOLEWORK_SCRIPT_DIR=...` で export した場合、`run-*.sh` が起動する `env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p ...` のような子プロセスにも環境変数が伝播する。`env -u CLAUDECODE` は `CLAUDECODE` のみを除去するため `WHOLEWORK_SCRIPT_DIR` は残る。

同様に `run-auto-sub.sh` が `$SCRIPT_DIR/run-verify.sh` 等を呼び出すとき、子スクリプトも親の `WHOLEWORK_SCRIPT_DIR` を参照するため、テスト側で 1 回 export するだけで全段のスクリプトが MOCK_DIR を参照できる。

### scripts 系 17 ファイルの一斉適用根拠

`grep -l '\$SCRIPT_DIR=' scripts/*.sh` の結果が 17 ファイル、`grep -l '\$SCRIPT_DIR/' scripts/*.sh` の結果と完全一致。すなわち `SCRIPT_DIR` を定義しているファイルは全て sibling 参照を行っており、全ファイルが本規約の対象となる。部分適用 (代表 2 件のみ) にする場合、未対応スクリプトに BATS テストを追加する際に同一の rework が再発するため、CI-sensitive Size M 以上ルール (PR route で systematic 規約導入) に従って全 17 ファイルを一斉更新する。

### verify command の count 集約パターン除外

Issue body の初版には `command "test $(grep -lF '$SCRIPT_DIR/' scripts/*.sh | xargs grep -LF 'WHOLEWORK_SCRIPT_DIR' | wc -l) -eq 0"` という count 集約型の comprehensive check が含まれていた。これは `modules/verify-patterns.md` #32 学習 (#364 由来) に該当する anti-pattern (count 集約は `/review` safe mode で UNCERTAIN、CI ジョブ相関困難) のため Spec では pre-merge から除外し、post-merge opportunistic に移動した。comprehensive な対応状況確認は次回の関連 PR レビュー時に grep で目視確認する運用とする。

また、初版で使用されていた `'\\$SCRIPT_DIR/'` は bash の single quote 内で literal `\\$SCRIPT_DIR/` として grep に渡り、BRE の `\\` が literal backslash にマッチしてしまうため `$SCRIPT_DIR/` を含む行を正しく検出できない (always 0 matches) という false positive も内包していた。post-merge opportunistic で目視検査する際は `grep -lF '$SCRIPT_DIR/'` (fixed string) を使用する。

### docs/ja/tech.md の翻訳同期

`/issue` スキルの翻訳除外ルールに従い、`docs/ja/tech.md` は本 PR では更新しない。`docs/tech.md` のマージ後に `/doc translate ja` で同期する前提 (Issue のスコープ外)。

### Tool Dependencies

すべての実装は既存の bash / grep / bats / gh でカバーでき、allowed-tools の追加は不要。

## issue retrospective

### 曖昧点解消の判断根拠

- **方式選定 (env var override vs PATH 解決化)**: env var override を採用。Issue #183 retrospective (`Recurring Issues` セクション) が明示的に推奨しており、既存 `$SCRIPT_DIR/helper.sh` 呼び出しを書き換えずに済むため差分最小。PATH 解決化は他スクリプトへの副作用 (PATH 先頭の内容に依存) を受けやすく、リスク高
- **スコープ (全 17 scripts 一斉 vs 最小限)**: 全 scripts 一斉適用を採用。CI-sensitive Size M 以上ルールと、将来の BATS テスト追加時に同じ問題が再発する構造的リスクの排除を優先。規約として定着させる
- **BATS テスト検証 (setup-labels.bats 書き直し vs 既存維持)**: 書き直し採用。PATH ベースのモックに統一することで今後の BATS テスト追加時のテンプレートとして機能させる

### Key Policy Decisions

- `WHOLEWORK_SCRIPT_DIR` 変数名は `WHOLEWORK_CI_TIMEOUT_SEC` (`docs/tech.md` Environment Variables) と整合
- `${WHOLEWORK_SCRIPT_DIR:-$(...)}` フォールバック形式により本番動作は完全後方互換
- `docs/tech.md` Testing Strategy セクションに BATS モック規約を記載し、未来の BATS テスト追加時に参照できるようにする

### Size 判定

Size L: 17 scripts の一斉適用 (6-10 files を超える) + CI-sensitive (+1) + 新規規約導入 (+1) = L 相当 (XL への昇格は single-purpose refactor のため不要)

## Code Retrospective

### Deviations from Design

- `docs/tech.md` の Environment Variables テーブルへの `WHOLEWORK_SCRIPT_DIR` 追加は Spec に明示されていなかったが、`WHOLEWORK_CI_TIMEOUT_SEC` との整合性と Notes の記述（「`WHOLEWORK_CI_TIMEOUT_SEC` と整合」）から追加が適切と判断した

### Design Gaps/Ambiguities

- macOS の BSD sed は複雑なシェル展開パターンを含む文字列の置換に非対応（`-i` の区切り文字エスケープ問題）。Spec は実装手法を明示していなかったため Python で代替した。Linux 環境の GNU sed では問題ないが、macOS での開発時は Python スクリプトが確実

### Rework

- N/A（設計通りに実装完了）

## review retrospective

### Spec vs. implementation divergence patterns

- `docs/tech.md` の Environment Variables テーブルへの `WHOLEWORK_SCRIPT_DIR` 追加はSpecに明示されていなかったが、Code Retrospectiveで「`WHOLEWORK_CI_TIMEOUT_SEC` との整合性から追加が適切と判断」と記録されており、適切なドキュメント整備として評価。Spec段階でEnvironment Variablesテーブルへの追記を明示しておくと、レビュー時の確認漏れを防げた。

### Recurring issues

- 特記なし。17スクリプトへの同一パターン適用という性質上、個別の問題は発生しなかった。

### Acceptance criteria verification difficulty

- 条件1〜7はすべてfile_contains/section_containsでPASSと判定できた。条件8（CI PASS）のみIN_PROGRESSでUNCERTAIN。`github_check "gh run list ..."` はsafeモードのallowlistに含まれないため、CIの完了まで待機する必要があった。今後、batsテストのCI PASSを事前条件とするIssueでは、CIが完了したタイミングで`/review`を実行するか、`gh pr checks`のallowlist内コマンドを活用するverify commandにすることで、より確実な自動判定が可能。

## spec retrospective

### Minor observations

- 初版 Issue body に含まれていた count 集約型 `command` verify command (`test $(grep -l ... | wc -l) -eq 0`) は、`modules/verify-patterns.md` #32 学習 (#364 由来) の anti-pattern に該当していた。加えて `'\\$SCRIPT_DIR/'` のエスケープが bash + grep BRE で literal `\\` 扱いになり実際には `$SCRIPT_DIR/` を検出できない false positive も内包していた。Spec 段階で発見し、`-F` (fixed string) 形式 + post-merge opportunistic への移動で整理した
- `/issue` 実行時に verify-patterns.md の count 集約回避ガイドラインが照会されていれば Issue 段階で anti-pattern の投入を防げた可能性がある。`/issue` での verify command 設計時に verify-patterns.md の関連セクションを明示的に照会する運用強化を検討する余地あり

### Judgment rationale

- **comprehensive check の pre-merge 除外**: 4 代表 scripts の `file_contains` + CI PASS + 将来のレビュー時 opportunistic 確認で本 Issue の価値 (rework 防止) は担保されると判断。network 集約 command は PR-level の自動化価値に対して `/review` safe mode での UNCERTAIN コストが上回る
- **docs/ja/tech.md を本 PR のスコープ外に**: `/doc translate {lang}` による post-merge 同期前提の翻訳除外ルールに従い、本 PR では `docs/tech.md` のみ更新。変更のレビュー範囲を英語版に集中させる

### Uncertainty resolution

- 子プロセスへの `WHOLEWORK_SCRIPT_DIR` 伝播: `env -u CLAUDECODE` は `CLAUDECODE` のみ削除のため env var は保持される。BATS テストで 1 回 `export` すれば `run-auto-sub.sh` → `run-verify.sh` 等のチェーン全段で override が効く。Notes セクションに明文化
- `set -u` 下での `${VAR:-default}` 安全性: `:-` は unset/empty 両方で default に fallback するため nounset エラーにならない。`set -euo pipefail` を使用する setup-labels.sh 等でも問題なし

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- count 集約型 verify command の anti-pattern (`test $(... | wc -l) -eq 0`) を Spec 段階で発見・除外できた。`modules/verify-patterns.md` を `/issue` 実行時に照会していれば Issue 段階で防げた可能性あり（spec retrospective に記録済み）
- `/issue` での verify command 設計時に verify-patterns.md の関連セクションを明示的に参照する運用強化は改善余地あり

#### design
- 4 代表スクリプトの `file_contains` verify + CI PASS + post-merge opportunistic という検証構造は適切。全 17 スクリプトへの包括的検証を pre-merge に含めず、代表件のみに絞った判断は verify 実行効率の観点からも妥当

#### code
- 17 スクリプトへの同一パターン一斉適用で rework なし。macOS BSD sed の制約により Python で代替したが（code retrospective 記録済み）、実装品質への影響なし
- `docs/tech.md` の Environment Variables テーブルへの `WHOLEWORK_SCRIPT_DIR` 追記は Spec 未明示だったが、文書整備として適切な追加（review retrospective 記録済み）

#### review
- review retrospective で「条件8の CI in_progress → UNCERTAIN」パターンに言及あり。今回の再実行（CI 完了後）で条件8が PASS となり、パターンの記録が正確であることを確認

#### merge
- 1 コミット（`chore: unify SCRIPT_DIR env var override and BATS mock strategy`）でクリーンにマージ。コンフリクトなし

#### verify
- 初回 verify: 条件 1〜7 PASS、条件 8 UNCERTAIN（マージ直後で CI が `in_progress`）
- 再実行（今回）: 全 8 条件すべて PASS（CI 完了後に実行したため条件8も `success` 確認）
- `github_check "gh run list --limit=1 ..."` はマージ直後（CI 実行中）に呼ぶと `in_progress` を返して UNCERTAIN になる。CI 完了を待って再実行する運用が必要

### Improvement Proposals
- `/verify` がマージ直後に実行される場合、`github_check` の CI PASS 条件は `in_progress` のまま UNCERTAIN になりやすい。`gh run list` で in_progress を除外する `--status completed` フィルタを verify command 側に追加するか、`gh pr checks` 形式（allowlist 内）を採用するパターンを `modules/verify-patterns.md` に追記することを検討する

