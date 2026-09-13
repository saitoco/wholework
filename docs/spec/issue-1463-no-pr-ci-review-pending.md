# Issue #1463: review: PR トリガ CI が存在しないリポジトリで run-review.sh が常に PENDING 終了しレビュー本体をスキップする

## Overview

PR トリガの CI workflow を持たないリポジトリ (例: `saito/ops`。`on: schedule` + `workflow_dispatch` のみ) では、`wait-ci-checks.sh` が 120 秒の猶予後に `zero_checks=true` を返し、`scripts/run-review.sh` がそれを PENDING (exit 2) と扱ってレビュー本体を一度も起動しない。`skills/auto/SKILL.md` pr route item 8 は `modules/ci-failure-classifier.md` の verdict `undetermined` に従い 300 秒 × 最大 2 回リトライするが、状況は構造的に変わらないため最大 10 分を無駄に消費する。

本 Issue では次の 3 点を行う。

1. PR トリガ CI の構造的不在を判定する共有スクリプト `scripts/detect-pr-ci-workflows.sh` を新設する
2. `ci-failure-classifier.md` に新 verdict `no-ci-configured` を追加し、消費側応答表に反映する
3. `run-review.sh` の CI 待ちゲート (主) と `skills/auto/SKILL.md` pr route item 8 (安全網) で、この判定のときはリトライ / PENDING を行わない

## Changed Files

- `scripts/detect-pr-ci-workflows.sh`: new file — `.github/workflows/*.yml|*.yaml` (直下のみ) に `pull_request` / `pull_request_target` トリガがあるかを静的 grep で判定し、`present` / `absent` / `unknown` を stdout に 1 行で出力する — bash 3.2+ compatible (`mapfile` 不使用、`shopt -s nullglob` にも依存しない)
- `tests/detect-pr-ci-workflows.bats`: new file — 上記スクリプトの全分岐のテスト
- `scripts/run-review.sh`: CI 待ちゲートの `_pending_reason` 判定を `pending>0` と `zero_checks=true` に分割し、`zero_checks=true` のときだけ `detect-pr-ci-workflows.sh` を呼ぶ。`absent` なら PENDING にしない。ヘッダの exit code contract コメントも更新 — bash 3.2+ compatible
- `tests/run-review.bats`: `setup()` に `detect-pr-ci-workflows.sh` のデフォルト mock (`present`) を追加し、新規テストケース 4 件を追加
- `modules/ci-failure-classifier.md`: Structural CI Absence Check (h3) の追加、4 値 verdict (`no-ci-configured`) 化、Per-Consumer Response 表に `no-ci-configured` 列と `scripts/run-review.sh` 行を追加、Purpose / Input を更新
- `tests/ci-failure-classifier.bats`: 新規テストケース 3 件を追加 (新 verdict の定義、auto SKILL の item 8 対応、run-review.sh での共有検出の利用)
- `skills/auto/SKILL.md`: pr route item 8 に `no-ci-configured` 分岐を追加。Step 6 CI platform failure pre-check の「do nothing」行と Tier 3 入力 `ci_failure_verdict` の列挙に `no-ci-configured` を追加。`allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-pr-ci-workflows.sh:*` を追加
- `skills/verify/SKILL.md`: `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-pr-ci-workflows.sh:*` を追加 (classifier の直接の読み手のため。Notes 参照)
- `agents/orchestration-recovery.md`: `## Input` の `ci_failure_verdict` 列挙に `no-ci-configured` を追加し、Anomaly Pattern 表「CI platform outage」行に「`no-ci-configured` は outage ではないため該当しない」旨を明記
- `modules/orchestration-fallbacks.md`: `## review-pending-not-failure` の `### Structural PENDING (retry does not help)` に、PR トリガ CI 不在は `run-review.sh` が自動で PENDING を回避する旨の bullet を追加
- `docs/workflow.md`: 「Review PENDING retry」段落に、CI 構造的不在時は `run-review.sh` が exit 2 を返さないこと、item 8 は `no-ci-configured` でリトライを行わないことを追記
- `docs/ja/workflow.md`: 上記の日本語ミラー同期 (`docs/translation-workflow.md` 準拠)
- `docs/structure.md`: `modules/ci-failure-classifier.md` 行の「3-value verdict」→「4-value verdict」、`scripts/wait-ci-checks.sh` 行の直後に `scripts/detect-pr-ci-workflows.sh` の説明行を追加、Directory Layout の `scripts/` / `tests/` 件数コメントを実測値に更新
- `docs/ja/structure.md`: 上記の日本語ミラー同期
- [Steering Docs sync candidate] keyword "run-review.sh" skipped: matched 195 files (no discriminating power)
- [Steering Docs sync candidate] keyword "orchestration-fallbacks.md" skipped: matched 142 files (no discriminating power)
- [Steering Docs sync candidate] keyword "ci-failure-classifier.md" skipped: matched 16 files (no discriminating power) — ただし Tag/enum 消費側スイープ (Notes) で `docs/spec/`・`docs/sessions/` 以外の参照元はすべて評価済み
- [Steering Docs sync candidate] keyword "zero_checks" skipped: matched 9 files (no discriminating power) — 評価済み: `tests/wait-ci-checks.bats` / `scripts/wait-ci-checks.sh` は出力契約を変えないため変更不要
- [Steering Docs sync candidate] keyword "no-ci-configured" / "detect-pr-ci-workflows.sh": 0 files (新規導入の識別子)

## Implementation Steps

1. **`scripts/detect-pr-ci-workflows.sh` と `tests/detect-pr-ci-workflows.bats` を新規作成する** (→ acceptance criteria 5)
   - Usage: `detect-pr-ci-workflows.sh [<repo-root>]` (省略時はカレントディレクトリ)。ヘッダコメントに出力契約・フェイルセーフ方針・呼び出し元 (`scripts/run-review.sh`, `modules/ci-failure-classifier.md`) を記載する
   - 判定対象: `<repo-root>/.github/workflows/` 直下の `*.yml` / `*.yaml`。非再帰。`for f in "$dir"/*.yml "$dir"/*.yaml; do [[ -e "$f" ]] || continue; ...` の形で、glob が展開されない場合も安全に扱う
   - ファイルごとの判定: `LC_ALL=C grep -qE '^[^#]*pull_request' "$f"`。`pull_request_target` にも部分一致する。`#` より後ろに現れる出現 (コメント) は除外する。`set -e` は使わず、grep の終了コードを明示的に分岐する (0=一致 / 1=不一致 / 2 以上=エラー)
   - 分岐 (exhaustive):
     - 引数が 2 個以上: stderr に `Usage: detect-pr-ci-workflows.sh [<repo-root>]`、stdout なし、exit 1
     - `<repo-root>` がディレクトリでない: stdout `unknown`、exit 0
     - `.github/workflows` が存在しない: stdout `absent`、exit 0
     - `.github/workflows` は存在するがディレクトリでない、または読み取り・探索できない (`! -r` / `! -x`): stdout `unknown`、exit 0
     - いずれかのファイルで grep が 0 を返した: その時点で stdout `present`、exit 0
     - 一致なし、かつ grep が 2 以上を返したファイルがある (読み取り不能など): stdout `unknown`、exit 0
     - 一致なし、エラーもなし (対象ファイル 0 件を含む): stdout `absent`、exit 0
   - エッジケースの期待挙動:
     - 空ファイル: 一致なし
     - 巨大ファイル: grep がストリーム処理するのでサイズ上限を設けない
     - ファイル名に空白・引用符・マルチバイト文字: 変数は常にクォートして展開する
     - CRLF 改行: 行末の `\r` は一致に影響しない
     - マルチバイト本文: `LC_ALL=C` でバイト一致にし、invalid multibyte による grep エラーを避ける
     - 偽陽性 (例: schedule 専用 workflow 内の `github.event.pull_request` 参照) は `present` になり、既存の PENDING 挙動が残る安全側
   - フェイルセーフ方針: fail-closed。挙動を変えるのは `absent` だけで、`unknown` とスクリプト自体の失敗は呼び出し側で既存挙動 (PENDING / リトライ) に倒す。根拠: `absent` の誤判定は CI 確認なしのレビュー進行を招くため
   - bats テストケース (新規、`BATS_TEST_TMPDIR` にフィクスチャを生成する)。`@test` 名は `detect-pr-ci-workflows:` で始める:
     - `.github/workflows` なし → `absent`
     - 空の workflows ディレクトリ → `absent`
     - `on:` + `schedule` + `workflow_dispatch` のみ (saito/ops 形状) → `absent`
     - `on: pull_request` (文字列形) → `present`
     - `on: [push, pull_request]` (配列形) → `present`
     - `on:` の下にインデントした `pull_request:` (マッピング形) → `present`
     - `pull_request_target` のみ → `present`
     - `.yaml` 拡張子 → `present`
     - `# on: pull_request` のようにコメントアウトされたトリガのみ → `absent`
     - `.yml` 以外のファイル (例: `README.md`) にだけ `pull_request` → `absent`
     - CRLF 改行のマッピング形 → `present`
     - 読み取り不能な workflow ファイル (`chmod 000`。root 実行時は `skip`) → `unknown`
     - 存在しない `<repo-root>` → `unknown`
     - 引数 2 個 → exit 1 + Usage
2. **`scripts/run-review.sh` の CI 待ちゲートを分割し、`tests/run-review.bats` を更新する** (after 1) (→ acceptance criteria 6)
   - 対象: `_ci_zero_checks=$(...)` 直後の `_pending_reason=""` から、それに続く `if [[ "${_ci_pending:-0}" -gt 0 || "${_ci_zero_checks:-false}" == "true" ]]; then ... fi` ブロックまで。次の分岐 (exhaustive) に置き換える:
     - `_ci_pending > 0`: 既存の `_pending_reason` (文言は変えない) を設定する。検出スクリプトは呼ばない
     - `_ci_zero_checks == true`: `_pr_ci_workflows=$("$SCRIPT_DIR/detect-pr-ci-workflows.sh" 2>/dev/null) || _pr_ci_workflows="unknown"` で判定する
       - 結果が完全一致で `absent`: `_pending_reason` を空のまま、stderr に `No PR-triggered CI workflow (pull_request / pull_request_target) found under .github/workflows/; zero registered checks is structural (ci-failure-classifier verdict: no-ci-configured). Proceeding to review without CI confirmation.` を出力し、後続 (preview 待ちゲート → claude 起動) へ進む
       - それ以外 (`present` / `unknown` / 空 / スクリプト不在・失敗): 既存と同じ `_pending_reason` を設定する
     - いずれにも当たらない: `_pending_reason` は空のまま (既存どおり)
   - 呼び出し時の CWD は、スクリプト冒頭で `cd "$MAIN_REPO_ROOT"` 済みのメインリポジトリルート。引数は渡さない
   - ヘッダの exit code contract の `2 = PENDING` 行に、zero registered checks でも PR トリガ CI workflow が存在しない (`detect-pr-ci-workflows.sh` → `absent`) 場合は PENDING にならない旨を 1〜2 行で追記する
   - `tests/run-review.bats`:
     - `setup()` の `wait-ci-checks.sh` mock の直後に、`$MOCK_DIR/detect-pr-ci-workflows.sh` のデフォルト mock (`echo present; exit 0`) を追加する (WHOLEWORK_SCRIPT_DIR mock 追加。既存の `PENDING: ci_result zero_checks=true skips claude and exits 2` の意味を保つ)。先頭のコメント `# Mocks:` 行にも `detect-pr-ci-workflows.sh` を追記する
     - 新規テストケース (既存 `PENDING: ci_result zero_checks=true skips claude and exits 2` の直後に追加):
       - `success: ci_result zero_checks=true with no PR-triggered CI workflow runs claude` — mock が `absent` → status 0、claude 呼び出しログあり、出力に `No PR-triggered CI workflow` を含み、`PENDING:` を含まない
       - `PENDING: ci_result zero_checks=true with unknown PR-trigger workflow detection exits 2` — mock が `unknown` → status 2、claude 未起動
       - `PENDING: ci_result zero_checks=true when PR-trigger workflow detection fails exits 2` — mock が出力なしで exit 1 → status 2、claude 未起動
       - `PENDING: ci_result pending>0 exits 2 even when no PR-triggered CI workflow is detected` — `pending=1` かつ mock が `absent` → status 2
3. **`modules/ci-failure-classifier.md` に新 verdict を追加する** (after 1) (→ acceptance criteria 1, 2)
   - `## Purpose`: CI platform infrastructure failure と implementation failure に加え、PR トリガ CI の構造的不在 (リトライしても解消しない zero checks) も区別する旨を 1 文追記する
   - `## Input`: `CI_RESULT_LINE` (optional) を追加する — `run-review.sh` 出力の `ci_result:` 行と `PENDING:` 理由行 (取得できる場合)
   - `## Processing Steps` の冒頭段落を「まず Structural CI Absence Check を評価し、該当しなければ Signature Table を評価する」順序に書き換える
   - `## Processing Steps` 直下、`### Signature Table` の前に h3 `### Structural CI Absence Check (evaluated before the Signature Table)` を新設し、次を記述する:
     - 適用条件: 分類対象が PR の zero registered checks に由来する場合のみ。具体的には `ci_result: ... zero_checks=true` かつ `PENDING: CI check wait did not reach a confirmed state` 理由、または `gh pr checks <PR>` が checks なしを報告する場合。`PENDING: PR preview ...` 理由 (preview 待ち) には適用しない
     - 観測: リポジトリルートで `${CLAUDE_PLUGIN_ROOT}/scripts/detect-pr-ci-workflows.sh` を実行する
     - 出力が `absent` (`.github/workflows/` のどの workflow も `pull_request` / `pull_request_target` をトリガにしていない): verdict `no-ci-configured`。Signature Table は評価しない
     - 出力が `present` / `unknown`: Signature Table の評価へ進む (既存どおり)
     - signature 5 (run が dispatch されない) との違い: signature 5 は PR トリガ workflow の存在を前提とする
   - `## Output`: 「Return a 3-value verdict (exhaustive)」を 4 値に改め、`no-ci-configured` を定義する — PR トリガ CI が構造的に存在せず、待機・再実行・CI 再実行のいずれでも checks は登録されない。これは CI の障害ではない
   - `### Per-Consumer Response (exhaustive)` 表に列 `Response when \`no-ci-configured\`` を追加し、各行を埋める:
     - `skills/verify/SKILL.md` Step 5 Step 1: 既存の PASS / FAIL / UNCERTAIN 判定を継続する (`undetermined` と同じ。失敗 job の参照が前提なので実質到達しない)
     - `skills/auto/SKILL.md` Step 6 pre-check: 通常どおり Tier 1 へ進む (待機・再判定は行わない)
     - `skills/auto/SKILL.md` pr route item 8: PENDING リトライループ (#1115) を実行せず (sleep も再実行もしない)、即座に completion check へフォールスルーする
     - `agents/orchestration-recovery.md` (Tier 3): 既存の anomaly pattern 表に従う。`CI platform outage` 行には該当しない
     - `modules/verify-executor.md` § 3a: UNCERTAIN (非インフラと同じ。FAILURE job 前提なので実質到達しない)
     - `modules/orchestration-fallbacks.md#ci-wait-silence-timeout`: CI 再実行は無意味なので、エントリ自身の Escalation に従う
   - 同表に行 `scripts/run-review.sh` (CI wait gate, bash) を追加する — `no-ci-configured` 列: 同じ `detect-pr-ci-workflows.sh` を直接使い、`zero_checks=true` かつ `absent` なら exit 2 (PENDING) を返さずレビュー本体へ進む。他の列: 分類しない (既存の PENDING 判定のまま)
   - 表の (exhaustive) 主張は機械的に検証する: `grep -rn "ci-failure-classifier.md" skills modules agents scripts` の参照元と表の行を突合し、漏れがないことを確認する
4. **`tests/ci-failure-classifier.bats` に新規テストケースを追加する** (after 2, 3, 5) (→ acceptance criteria 4)
   - `@test "ci-failure-classifier: no-ci-configured verdict is defined with pull_request trigger detection"` — `$CLASSIFIER` に `no-ci-configured`、`pull_request_target`、`detect-pr-ci-workflows.sh` が含まれる
   - `@test "ci-failure-classifier: auto SKILL.md pr route item 8 handles no-ci-configured"` — `skills/auto/SKILL.md` に `no-ci-configured` が含まれる
   - `@test "ci-failure-classifier: run-review.sh uses the shared PR-trigger workflow detection"` — `scripts/run-review.sh` に `detect-pr-ci-workflows.sh` が含まれる
   - 既存 4 テストは変更しない
5. **`skills/auto/SKILL.md` を更新する** (after 3) (→ acceptance criteria 3)
   - pr route item 8: 既存の `- **verdict = \`ci-infra\`**: ...` bullet の直後、`- **verdict = \`implementation\` or \`undetermined\`**: ...` bullet の直前に次を追加する: `- **verdict = \`no-ci-configured\`**: PR-triggered CI does not structurally exist in this repository, so no check will ever register — do not sleep and retry (skip the #1115 retry loop below entirely), and fall through immediately to the completion check below.`
   - 同 item のフォールスルー文 (`If the exit code is anything other than 2, or exit code 2 persists after the retry limit ... is reached, fall through to the completion check ...`) の条件に `or the verdict is \`no-ci-configured\`` を追加する
   - `#### CI platform failure pre-check (before Tier 1)` の `- **When verdict = \`implementation\` or \`undetermined\`**: do nothing — proceed to Tier 1 ...` を `implementation`, `undetermined`, or `no-ci-configured` に改める
   - Tier 3 spawn 入力の `ci_failure_verdict` 列挙 (`(\`ci-infra\`/\`implementation\`/\`undetermined\`)`) に `no-ci-configured` を追加する
   - frontmatter `allowed-tools` の `Bash(...)` 内に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-pr-ci-workflows.sh:*` を追加する (単一行を維持)
   - SKILL.md 制約: 半角 `!`・3 連バッククォートを本文に入れない
6. **`skills/verify/SKILL.md` と `agents/orchestration-recovery.md` を同期する** (parallel with 5) (→ acceptance criteria 1)
   - `skills/verify/SKILL.md`: frontmatter `allowed-tools` の `Bash(...)` 内に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-pr-ci-workflows.sh:*` を追加する
   - `agents/orchestration-recovery.md`: `## Input` の `ci_failure_verdict` 列挙 `(\`ci-infra\` / \`implementation\` / \`undetermined\`)` に `no-ci-configured` を追加する。`### 3. Identify Anomaly Pattern` 表の `CI platform outage` 行の Indicators に、`no-ci-configured` はこの行に該当しない (CI が確定状態に達しないのは構造的な不在であり outage ではない) 旨を追記する
7. **`modules/orchestration-fallbacks.md` を更新する** (parallel with 5, 6) (→ acceptance criteria 1)
   - `## review-pending-not-failure` → `### Structural PENDING (retry does not help)` の末尾に次の bullet を追加する: **No PR-triggered CI workflow** — `ci_result: ... zero_checks=true` は、`.github/workflows/` のどの workflow も `pull_request` / `pull_request_target` をトリガにしていないリポジトリでは構造的に解消しない。`run-review.sh` は `scripts/detect-pr-ci-workflows.sh` が `absent` を返した場合に PENDING を返さずレビューへ進み、classifier は同状況を verdict `no-ci-configured` と判定する (#1463)
8. **ドキュメントを同期する** (after 1〜7) (→ acceptance criteria 1)
   - `docs/workflow.md` の「**Review PENDING retry**」段落末尾に 1〜2 文を追加する: zero registered checks かつ PR トリガ CI workflow が存在しない場合、`run-review.sh` は exit 2 を返さずレビューへ進む。exit 2 が残った場合でも classifier verdict が `no-ci-configured` なら sleep+retry は適用されない
   - `docs/ja/workflow.md` の対応段落 (「**review PENDING 時の再試行**」) に同内容を日本語で追加する
   - `docs/structure.md`:
     - `modules/ci-failure-classifier.md` 行の `3-value verdict` → `4-value verdict`
     - `scripts/wait-ci-checks.sh` 行の直後に `- \`scripts/detect-pr-ci-workflows.sh\` — static check for PR-triggered CI workflows (\`pull_request\` / \`pull_request_target\`) under \`.github/workflows/\`; outputs \`present\`/\`absent\`/\`unknown\` (fail-closed: only \`absent\` changes behavior); called by \`scripts/run-review.sh\`'s CI wait gate and \`modules/ci-failure-classifier.md\`'s Structural CI Absence Check` を追加する
     - Directory Layout の `scripts/` / `tests/` 件数コメントを、追加後の実測値 (`find scripts -maxdepth 1 -type f | wc -l` / `find tests -maxdepth 1 -type f | wc -l`) に更新する
   - `docs/ja/structure.md`: 上記 3 点を日本語ミラーに同期する (件数表記が存在する場合のみ件数も更新)
   - ja ミラーは `docs/translation-workflow.md` Sync Procedure 手順 5 のコードフェンス数突合を行う
9. **検証を実行する** (after 1〜8) (→ acceptance criteria 4, 5, 6, 7, 8)
   - `bats tests/detect-pr-ci-workflows.bats tests/run-review.bats tests/ci-failure-classifier.bats tests/auto-recovery.bats`
   - `python3 scripts/validate-skill-syntax.py skills/` (allowed-tools に追加したスクリプトの実在チェックと本文制約)
   - `bash scripts/check-forbidden-expressions.sh` が存在すれば実行する

## Alternatives Considered

| 案 | 内容 | 判断 |
|----|------|------|
| A | `.wholework.yml` の設定キー (例: `ci-wait: false`) で明示的に無効化する | 不採用 (Issue 本文)。設定漏れで再発しうる |
| C | verdict は `undetermined` のまま、リトライだけ抑止する | 不採用 (Issue 本文)。他の消費側に再利用できない |
| item 8 のみ | classifier verdict + item 8 のフォールスルーだけを実装する | 不採用。フォールスルー先の `reconcile-phase-state.sh review --check-completion` はレビュー未実行のため `matches_expected: false` → Step 6 に進むだけで、レビュー本体が起動せず目的を満たさない |
| item 8 から即時再実行 | `no-ci-configured` のとき `run-review.sh --skip-ci-wait` で即時再実行する | 不採用。猶予期間と classifier 判定が二重になり、XL route (`scripts/run-auto-sub.sh` の `run_phase_with_recovery()`) は 10 分待機のまま残り、新しい CLI フラグの表面も増える |
| `wait-ci-checks.sh` で短絡 | workflow 不在時は猶予期間 (120s) も省略して即時返す | 不採用。`/merge`・`/code`・`/review` Step 9 の呼び出し元と `ci_result:` 出力契約に影響する。猶予期間には `.github/workflows` を持たない外部 CI (GitHub App) の checks 登録を待つ意味もある |
| リモート判定 | `gh api repos/:owner/:repo/actions/workflows` で workflow を列挙する | 不採用。一覧にトリガ情報がなく、ファイルごとの内容取得とネットワーク依存が増える |
| **採用** | 共有スクリプトによるローカル静的 grep + `run-review.sh` ゲート (主) + classifier verdict + item 8 (安全網) | 発生源で PENDING を回避するため、pr route・XL route・ラッパー直接実行のすべてに効く。bats で決定的に検証できる |

## Verification

### Pre-merge

- <!-- verify: rubric "modules/ci-failure-classifier.md に、PR トリガの CI が構造的に存在しない (workflow が一つも pull_request/pull_request_target をトリガにしていない) ケースを、既存の ci-infra/implementation/undetermined の 3 verdict とは区別して判定する新しい verdict が追加されており、Output の消費側応答表にも反映されている" --> `ci-failure-classifier.md` に CI 構造的不在を判定する新しい verdict が追加されている
- <!-- verify: file_contains "modules/ci-failure-classifier.md" "pull_request" --> 判定ロジックが workflow のトリガ種別 (`pull_request` 系) を参照している
- <!-- verify: rubric "skills/auto/SKILL.md の pr route item 8 (run-review.sh が exit 2 で返した場合の分岐) に、CI が構造的に存在しないと判定された場合は既存の sleep + 最大 2 回リトライ (#1115) を実行せず、即座に次の判断 (レビュー完了チェックへのフォールスルー) に進む経路が追加されている" --> pr route item 8 が CI 構造的不在時にリトライを行わない
- <!-- verify: command "bats tests/ci-failure-classifier.bats" --> `tests/ci-failure-classifier.bats` が PASS する (新 verdict を検証する新規テストケースを含む)
- <!-- verify: command "bats tests/detect-pr-ci-workflows.bats" --> `tests/detect-pr-ci-workflows.bats` (新規) が PASS する (`present` / `absent` / `unknown` の各分岐を検証する新規テストケースを含む)
- <!-- verify: command "bats tests/run-review.bats" --> `tests/run-review.bats` が PASS する (`zero_checks=true` かつ PR トリガ CI 不在時に PENDING にならずレビュー本体へ進む新規テストケースを含む)
- <!-- verify: command "bats tests/auto-recovery.bats" --> `tests/auto-recovery.bats` が PASS する (回帰ガード)
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) が PASS する

### Post-merge

- 次に PR トリガ CI が構造的に存在しないリポジトリで `/auto` の pr route を実行した際、`run-review.sh` の PENDING リトライが無駄に消費されず、レビュー本体が実行されることを確認する <!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - `run-review.sh` のログに PR トリガ CI workflow 不在を示す行 (`No PR-triggered CI workflow`) が出力され、`PENDING:` 行と `Exit code: 2` が出力されない
    - `/review` 本体 (claude セッション) が起動し、PR にレビュー結果が投稿される

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/detect-pr-ci-workflows.sh:*`: classifier の Structural CI Absence Check の実行用。`skills/auto/SKILL.md` と `skills/verify/SKILL.md` の allowed-tools に追加する。どちらも未登録であることを grep で確認済み (新規スクリプトのため)

### Built-in Tools

- none

### MCP Tools

- none

## Uncertainty

- **`.github/workflows/` のサブディレクトリ**: 公式ドキュメントは「`.github/workflows` directory に `.yml` / `.yaml` で置く」と記載するが、サブディレクトリの扱いは明記していない
  - **Verification method**: 公式ドキュメントを確認済み (出所: https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions 、取得日時: 2026-09-13)。設計は直下のみの非再帰とする
  - **Impact scope**: Implementation Step 1。仮にサブディレクトリの workflow が実行される場合でも、checks が登録されるので `zero_checks=false` となり、本判定は呼ばれない。どちらでも安全側に倒れる
- **`.github/workflows` を持たない外部 CI (CircleCI / Buildkite / Vercel などの GitHub App)**: それらが 120 秒の猶予期間内に checks を登録しなかった場合、`absent` 判定でレビューが CI 確認なしに進む
  - **Verification method**: 未解決 (受容)。`/review` Step 9 が改めて `wait-ci-checks.sh` と `statusCheckRollup` を確認し、`/merge` 側にも CI 確認がある
  - **Impact scope**: Implementation Step 2。挙動の変化は「猶予期間後も checks ゼロ、かつ PR トリガ workflow ファイルもない」場合に限る
- **`on` キーの表記揺れ (`"on":` / YAML 1.1 の `true:` 解釈 / flow mapping)**: 解決済み。キー名ではなく、コメント外の行に `pull_request` という値の文字列があるかで判定するため、表記に依存しない (出所は上記公式ドキュメント。`on` は文字列・配列・マッピングの 3 形式)

## Notes

- **Conflict with implementation (SPEC_DEPTH=full, non-interactive auto-resolve)**:
  - Issue 本文の主張: `skills/auto/SKILL.md` pr route item 8 を「即座に次の判断 (レビュー完了チェックへのフォールスルー) に進む」ようにすれば、目的の「無駄な待機なくレビューへ進める」と Post-merge AC の「レビュー本体が実行される」を満たす、という前提になっている
  - 実装: item 8 のフォールスルー先は `reconcile-phase-state.sh review $NUMBER --pr $PR_NUMBER --check-completion` (`skills/auto/SKILL.md` item 8 末尾)。レビューが一度も実行されていなければ `matches_expected: false` → Step 6 (失敗処理) に進むだけで、レビュー本体は起動しない。XL route の `scripts/run-auto-sub.sh` `run_phase_with_recovery()` (`# PENDING pre-check (review phase only)` ブロック) には classifier 判定自体がない
  - 解決: 発生源の `scripts/run-review.sh` 自身が同じ検出を使って PENDING を回避する (主)。item 8 の `no-ci-configured` 分岐は、ゲート側の判定が `unknown` だった場合などの安全網として AC どおり実装する
- **Auto-resolved ambiguity (非対話モード)**: 詳細は Issue コメントの Auto-Resolve Log。要点は次のとおり
  - 検出方法: ローカル静的 grep の共有スクリプト
  - verdict 名: `no-ci-configured`
  - フェイルセーフ: `absent` のみ挙動を変更
  - 120 秒猶予期間: 維持
  - Issue 本文への AC 2 件追加と observation AC の期待出力構造 (Option A) 追加
- **Fail-safe critical script: yes** (criterion (c): `unknown` を安全側の既定値として返す判定スクリプト、および (a) PENDING ゲート)。エッジケースと fail-closed の根拠は Implementation Steps 1, 2 に記載
- **Audit/investigation-type: no** (新機能の追加であり、既存項目の分類監査ではない)
- **Tag/enum semantic extension consumer sweep**: verdict 値の追加に伴い、既存 3 値を分岐・列挙する消費側を洗い出した。パターン `grep -rn "ci-infra" skills modules scripts agents` (`modules/ci-failure-classifier.md` 自身を除く)。消費側一覧 (exhaustive) と対応は次のとおり
  - `skills/auto/SKILL.md` item 8 (451-452 行付近): Step 5 で変更
  - `skills/auto/SKILL.md` Step 6 pre-check (969-981 行付近): Step 5 で変更
  - `skills/auto/SKILL.md` Tier 3 入力の列挙 (1036 行付近): Step 5 で変更
  - `agents/orchestration-recovery.md` 28 行・57 行: Step 6 で変更
  - `skills/verify/SKILL.md` 258 行: `ci-infra` 時のみ分岐するため変更不要。表の行で応答を明記する
  - `modules/verify-executor.md` 432 行: 同上
  - `skills/auto/SKILL.md` 978 行・`agents/orchestration-recovery.md` 107 行の `ci-infra-outage-during-ci-wait`: cause slug であり verdict 分岐ではないため対象外
  - `scripts/run-auto-sub.sh` 797 行: ポインタコメントのみ。変更不要 (本件で exit 2 自体が発生しなくなる)
- **allowed-tools impact chain**:
  - Case 1 (新規 `scripts/*.sh`): `detect-pr-ci-workflows.sh` を LLM が実行しうるのは classifier 経由のみ
  - Case 2 (`modules/ci-failure-classifier.md` に `scripts/*.sh` 参照を追加): `grep -rl "modules/ci-failure-classifier\.md" skills/*/SKILL.md` の結果は `skills/auto/SKILL.md` と `skills/verify/SKILL.md` の 2 件で、どちらも未登録 → 両方に追加する (Step 5, 6)。`/verify` は失敗 job 前提の消費側なので Structural Check の適用条件に実質当たらないが、#1227 review retrospective の教訓 (消費者ごとに独立して allowed-tools を確認・登録する) に従って登録する
  - `modules/verify-executor.md` を経由する推移的な読み手 (`/review` 等) は § 3a が FAILURE job 前提で適用条件に当たらないため対象外
  - `validate-skill-syntax.py` の `validate_allowed_tools_scripts` は allowed-tools に列挙したスクリプトの実在のみを検査し、本文で未参照のエントリは検査しない (grep で確認済み)
- **WHOLEWORK_SCRIPT_DIR mock**:
  - `tests/run-review.bats` は `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を使うため、Step 2 で `detect-pr-ci-workflows.sh` のデフォルト mock を追加する
  - `tests/run-auto-sub.bats` / `tests/run-merge.bats` も `WHOLEWORK_SCRIPT_DIR` を使うが、テスト対象が新スクリプトを呼ばないため mock 不要
- **bats テストの入力形式**:
  - `run-review.sh` が読む `wait-ci-checks.sh` の出力は 1 行の `ci_result: total=N passed=N failed=N pending=N cancelled=N zero_checks=true|false` (`scripts/wait-ci-checks.sh` 末尾の echo)
  - `detect-pr-ci-workflows.sh` の出力は `present` / `absent` / `unknown` のいずれか 1 行
  - `detect-pr-ci-workflows.bats` のフィクスチャは `$BATS_TEST_TMPDIR/repo/.github/workflows/*.yml` に heredoc で生成する GitHub Actions workflow YAML。CRLF ケースは `printf 'on:\r\n  pull_request:\r\n'` で生成する
- **New test case requirement for new branch logic**: 新しい分岐を追加する Step は 1 (`detect-pr-ci-workflows.sh` の全分岐)、2 (`run-review.sh` の zero_checks 分割)、3/5 (classifier verdict と item 8 の分岐)。それぞれに対応する新規テストケースを Implementation Steps 1, 2, 4 と Issue 本文の AC 4〜6 に明記した (spec retrospective にも要約する)
- **`docs/structure.md` の件数コメントの既存ドリフト**: 現状の記載は `scripts/` 95 files / `tests/` 130 files。実測は `find scripts -maxdepth 1 -type f | wc -l` = 97、`find tests -maxdepth 1 -type f | wc -l` = 132 (いずれも直下のファイルのみ、2026-09-13 の worktree 時点)。本 Issue 着手前から各 +2 のドリフトがある。Step 8 では追加後の実測値に揃える。件数は verify command に固定しない (`docs/structure.md` の注記に従う)
- **Exclusions (変更不要と確認済み)**:
  - `scripts/wait-ci-checks.sh`: 出力契約と猶予期間を維持
  - `scripts/run-merge.sh` / `skills/merge/SKILL.md`: Issue 補足の merge ゲート・Handoff 誤記はスコープ外
  - `skills/review/SKILL.md` Step 9: zero checks 時も既に「proceed」
  - `skills/code/SKILL.md` 790 行: `zero_checks=true` は既に警告のうえ続行
  - `docs/tech.md`: 新しい環境変数なし
  - `README.md`: 関連記述なし (grep で確認)
  - `docs/guide/customization.md`: preview 待ちの PENDING のみ記述
  - `docs/migration-notes.md`: CLI シグネチャ変更なし
  - `modules/detect-config-markers.md`: 案 A 不採用
- **Size 再評価**: Changed Files はリポジトリファイル 15 件 (Axis 1 では XL 相当)。うち `skills/verify/SKILL.md` の allowed-tools 1 行、`agents/orchestration-recovery.md` の列挙追記、`modules/orchestration-fallbacks.md` の bullet、`docs/ja/*` ミラー 2 件、`docs/workflow.md`・`docs/structure.md` の数行追記の計 7 件は同期編集。実質は 8 件 (L) と判断し、L を維持する (Auto-Resolve Log 参照)

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: 方向性 B (自動検出による新 verdict) の採用、具体的な検出方法は `/spec` に委任、補足の merge Phase Handoff 誤記はスコープ外、AC を新規追加 / https://github.com/saitoco/wholework/issues/1463#issuecomment-5650843672
- saito / MEMBER / first-class / ## Spec Phase: Autonomous Auto-Resolve Log / https://github.com/saitoco/wholework/issues/1463#issuecomment-5651004555

## issue retrospective

(Issue コメント https://github.com/saitoco/wholework/issues/1463#issuecomment-5650843672 から転記)

### Autonomous Auto-Resolve Log

- **採用した方向性: B (自動検出)** — reason: Issue 本文が挙げていた A (`.wholework.yml` 設定キーによる明示無効化) / B (自動検出により新しい verdict を追加) / C (verdict は `undetermined` のままリトライのみ抑止) のうち、B を採用した。`modules/ci-failure-classifier.md` (#1227) が既に「CI 起因の PENDING を判定ロジックで分類し、消費側の応答を変える」という同種の構造を持っており、その拡張として最も自然で、workflow ファイルの静的内容から機械的に判定できるため設定漏れのリスクもない。`skills/auto/SKILL.md` pr route item 8 は、新しい verdict を受け取った場合に既存の sleep + 最大 2 回リトライ (#1115) を行わず即座に次の判断へ進む
  - Other candidates: A (設定キー明示) — 利用者の設定漏れで同じ問題が再発しうるため却下。C (リトライ抑止のみ) — verdict を `undetermined` のままにすると `skills/auto/SKILL.md` Step 6 の CI platform failure pre-check など他の消費側に恩恵が及ばないため却下
- **具体的な検出方法の設計は `/spec` に委ねる** — reason: `.github/workflows/` の静的 grep か、他の観測手段かは実装手段 (How) の判断であり、`/issue` (What) の責務を超えるため

### 主要なポリシー決定

- 補足の「`/merge` Phase Handoff の `### Key Decisions` が実態と食い違う」問題は、本 Issue のスコープ外として明示的に除外した (Issue filing restraint の方針に従い、必要になった時点で別途起票する判断とし、今回は新規 Issue を追加起票しない)
- Acceptance Criteria が本 Issue には存在しなかったため、新規に Pre-merge / Post-merge セクションを追加した。Pre-merge は `modules/ci-failure-classifier.md` の新 verdict 追加と `skills/auto/SKILL.md` pr route item 8 の分岐追加を rubric + 補助的な `file_contains` で検証し、既存の回帰テスト (`tests/ci-failure-classifier.bats` / `tests/auto-recovery.bats`) を command 検証に含めた。Post-merge は `skills/auto/SKILL.md` の変更を含むため `verify-type: observation event=auto-run session=next` とした (skill 変更は次回セッションでのみ観測可能)

(issue phase の消費コメント記録: No new comments since last phase.)

## spec retrospective

### Minor observations

- Issue 本文は「item 8 がレビュー完了チェックへフォールスルーすればレビューへ進める」という前提に立っていたが、フォールスルー先の `reconcile-phase-state.sh review --check-completion` はレビュー未実行だと `matches_expected: false` を返し、Step 6 に進むだけだった。`/issue` の段階で「フォールスルー後に何が起きるか」まで辿っていれば、発生源 (`run-review.sh`) の変更が必要だと What の段階で見えていた
- `docs/structure.md` の Directory Layout 件数コメントに、本 Issue 着手前から `scripts/` と `tests/` とも +2 のドリフトがあった (#1227 retrospective で指摘された modules 件数ドリフトと同種)。ファイル追加のたびに更新が必要な設計上、再発しやすい
- #1227 review retrospective の教訓を 2 点適用した。(1) classifier の読み手ごとに allowed-tools を独立して grep で確認し、`skills/auto/SKILL.md` と `skills/verify/SKILL.md` の両方に登録する。(2) verdict 列挙を持つ契約側 (`agents/orchestration-recovery.md` の `## Input` と anomaly 表) も Changed Files に含める
- Consumed Comments safety net (`append-consumed-comments-section.sh`) は、この spec phase 自身が cutoff 後に投稿した Auto-Resolve Log コメントも消費コメントとして 1 行追記した。実害はないが、自フェーズ由来のコメントが「消費した入力」として記録されるノイズになる
- worktree 分離ガードは `git add ... && git commit ... && ...` のような複合コマンドを拒否した。単純なコマンドに分割すれば問題なく実行できた

### Judgment rationale

- 主な修正箇所を classifier / item 8 (AC の対象) ではなく `run-review.sh` のゲートに置いた。発生源で PENDING を回避すれば pr route・XL route (`run-auto-sub.sh`)・ラッパー直接実行のすべてに効く。一方、item 8 のみの変更では目的 (レビュー本体の実行) を満たせない。item 8 の分岐は AC どおり安全網として残す
- 検出スクリプトの出力を 3 値 (`present` / `absent` / `unknown`) にし、挙動を変えるのは `absent` のときだけにした (fail-closed)。「挙動を変えるのは確証があるときだけ」という既存フェイルセーフ設計 (#1060 の fail-open バグの教訓) に合わせた
- 新規分岐に対して必須とした新規テストケースは次のとおり
  - `tests/detect-pr-ci-workflows.bats`: 14 件 (`on` の 3 形式、`pull_request_target`、`.yaml`、コメントアウト、CRLF、読み取り不能、存在しない root、引数過多)
  - `tests/run-review.bats`: 4 件 (`absent` → レビュー実行 / `unknown` → PENDING / 検出スクリプト失敗 → PENDING / `pending>0` は検出結果にかかわらず PENDING)
  - `tests/ci-failure-classifier.bats`: 3 件 (新 verdict の定義、item 8 の対応、run-review.sh での共有検出の利用)
  - Issue 本文の AC 4〜6 に対応付けた
- Changed Files は名目上 15 件だが、同期編集が 7 件あるため Size L を維持した (XL 化は sub-issue 分割を伴う High-Stakes Decision)

### Uncertainty resolution

- `on` キーの 3 形式 (文字列 / 配列 / マッピング) と、配置場所が `.github/workflows` の `.yml` / `.yaml` であることを公式ドキュメントで確認した (出所: https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions 、取得日時: 2026-09-13)。キー名ではなく `pull_request` という値の文字列で判定するので、`"on":` などの表記揺れには依存しない
- サブディレクトリの扱いはドキュメントに記載がなく未確認。ただし「checks がゼロ」という前提条件と組み合わせるため、どちらの仕様でも安全側に倒れることを確認し、非再帰と決めた
- `.github/workflows` を持たない外部 CI (GitHub App) が猶予期間内に checks を登録しない場合は受容リスクとした。`/review` Step 9 と `/merge` の CI 確認が後段に残る

## Code Retrospective

### Deviations from Design

- なし。Implementation Steps 1〜9 を Spec の記載順どおりに実装した

### Design Gaps/Ambiguities

- `scripts/detect-pr-ci-workflows.sh` の grep 呼び出しでパーミッションエラー (chmod 000 ケース) が stderr に漏れ、bats の `run` が stdout/stderr を結合する `$output` の等価比較を壊した。`grep ... 2>/dev/null` で抑制して解決。Spec のエッジケース記述には現れていなかった実装レベルの詳細

### Rework

- なし。Pre-implementation FAIL 確認は新規 3 テストファイル (`ci-failure-classifier.bats` の新規 3 ケース、`run-review.bats` の新規 4 ケースのうち成功ケース 1 件) で実施し、いずれも一発で意図通りに FAIL/PASS した
- 新規 bats テストの `$output`/`$status` に対する bare `[[ ... ]]` アサーションは、`skills/code/skill-dev-validation.md` の bash 3.2 非伝播ガイダンスに従って `grep -q` / 否定形の grep 形式に書き直した (既存の類似アサーションは対象外、新規分のみ)

## review retrospective

### Spec vs. implementation divergence patterns

- Spec / Code の設計自体からの構造的逸脱はなかったが、Spec の Uncertainty 節に記載されなかった実装レベルの前提 (`detect-pr-ci-workflows.sh` が呼び出し元の CWD / repo-root 引数省略に依存する) が review-bug ×2 の両エージェントに独立して検出された。Spec の Implementation Steps は「何を検出するか」を記述していたが「どの root を対象に検出するか」という呼び出し契約を明記していなかったため、実装時にも review 時にも見落とされやすい形になっていた

### Recurring issues

- 「repo-root / CWD 依存の判定スクリプトが、呼び出し元によって異なる対象を評価しうる」という指摘は、review-bug の bug-diff エージェントと security-scan エージェントの双方から独立に (角度は異なるが) 提起された。パーサ / バリデータ系の新規スクリプトでは、権限エラー・欠損ディレクトリ・CWD 依存性の 3 点セットが再発しやすいエッジケース群であることを確認 (Parser/Validator Edge Case Pre-check の実行 sub-agent 自身は fixture ベースの機能検証では発見できず、review-bug の diff 読解で発見された — 実行検証と diff レビューが相補的であることの実例)
- Fail-closed を明記した新規スクリプトでも、「読み取り不能」を「不在」に落とし込む分岐が 1 箇所残っているだけでポリシーに反する。ヘッダコメントで宣言した不変条件は、実装の全分岐を機械的に突合しないと保証されない

### Acceptance criteria verification difficulty

- Pre-merge AC 8 件はすべて verify command (`rubric` / `file_contains` / `command` / `github_check`) 付きで、CI reference fallback (`Run bats tests` ジョブが `bats tests/` フルスイートを実行) により `command` 系 4 件も safe mode のまま PASS 判定できた。verify command 品質に起因する UNCERTAIN は 0 件
- `github_check "gh pr checks" "Run bats tests"` の 1 件は `/code` フェーズでは意図的に未チェックのまま残されており (Phase Handoff の Notes for Next Phase に明記)、`/review` が実際の CI 結果で検証してチェック済みに更新する運用が想定どおり機能した

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC ゲートは 8/8 チェック済み、review completion も review-incomplete-fallback 起源ではなかったため、AskUserQuestion を経由せずそのまま `gh pr merge --squash --delete-branch` を実行した
- `merge-strategy` は `.wholework.yml` 未設定のためデフォルトの `squash` に解決された

### Deferred Items
- Post-merge observation AC (`/auto` の pr route を PR トリガ CI 不在リポジトリで実行して確認) は引き続き次回セッションでのみ観測可能 (spec/review フェーズからの deferred item を継続)
- `docs/guide/xl-decomposition.md` の ja ミラードリフトは本 PR のスコープ外のまま未着手

### Notes for Next Phase
- `/verify` は Post-merge observation AC (`session=next`) を、次に PR トリガ CI が構造的に存在しないリポジトリで `/auto` pr route を実行するセッションで確認すること
