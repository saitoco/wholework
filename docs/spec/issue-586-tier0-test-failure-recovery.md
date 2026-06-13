# Issue #586: code-skill: Tier 0 リカバリ（test 失敗の mock/snapshot/fixture 自動修復、max 1 回）

## Overview

`/code` の実装直後ローカルテスト失敗のうち、ロジック誤りではなく「モック・スナップショット・期待値（fixture）ずれ」のクラスを、構造化された Tier 0 リカバリで最大 1 回だけ自動修復する。修復可能クラスでないもの（ロジック誤り・テストインフラ誤り）は Tier 0 をスキップし、即座に既存の Step 9 FAIL ハンドリング（汎用 1-repair → route 別 abort/continue）へフォールスルーする。

実現要素は 3 つ:

1. 新スクリプト `scripts/test-failure-classify.sh` — テスト出力を分類し、カテゴリを stdout に出力（`apply-fallback.sh` / `detect-wrapper-anomaly.sh` と同じ `--log <file>` + stdout カテゴリ + exit 0/1 パターン）。
2. `skills/code/SKILL.md` Step 9 へ Tier 0 リカバリブロックを追加。
3. `tests/test-failure-classify.bats` — 5 分類パターン + 引数/エラーハンドリングの bats テスト。

## Changed Files

- `scripts/test-failure-classify.sh`: 新規。テスト失敗分類スクリプト（入力 `--log <test-output-file>`、出力 stdout カテゴリ、exit 0=修復可 / 1=修復不可）。bash 3.2+ 互換。
- `tests/test-failure-classify.bats`: 新規。5 分類カテゴリ（snapshot / mock / fixture / logic / infra）+ 引数欠落 / 不在ファイルのエラーハンドリングを検証する bats テスト。
- `skills/code/SKILL.md`: Step 9（Run Tests）に「#### Tier 0: Structured Test-Failure Recovery」ブロックを既存 FAIL ハンドリングの**前**に追加。あわせて allowed-tools の Bash() リストへ `${CLAUDE_PLUGIN_ROOT}/scripts/test-failure-classify.sh:*` を追加。
- `docs/structure.md`: scripts カウント `(49 files)` → `(50 files)`、tests カウント `(59 files)` → `(60 files)`、Scripts > Process management リストへ `test-failure-classify.sh` の項目を追加。

## Implementation Steps

1. **`scripts/test-failure-classify.sh` を新設**（→ 受入条件 1, 2, 3）

   - インターフェース: `test-failure-classify.sh --log <test-output-file>`（`apply-fallback.sh` / `detect-wrapper-anomaly.sh` と同じ引数パーサ・エラー処理パターン）。`--log` 欠落・ファイル不在は stderr メッセージ + 非ゼロ exit。
   - 入力ファイルの内容を grep でキーワード照合し、カテゴリ 1 個を stdout に出力。検出優先順（先勝ち、上から評価）:

     | 評価順 | カテゴリ | 検出キーワード（`grep -iE`） | exit |
     |---|---|---|---|
     | 1 | `infra` | `command not found`, `permission denied`, `No such file or directory`, `ModuleNotFoundError` | 1 |
     | 2 | `snapshot` | `snapshot doesn't match`, `expected snapshot to be`, `--update-snapshot` | 0 |
     | 3 | `mock` | `expected calls`, `not called with expected arguments`, `mock returned` | 0 |
     | 4 | `fixture` | `expected <X>, got <Y>` で X/Y が両方リテラル文字列（ヒューリスティック。例: `expected .* got .*` のリテラル比較行） | 0 |
     | 5 | `logic` | 上記いずれにも該当しない（既定） | 1 |

   - exit code: 修復可（snapshot/mock/fixture）= 0、修復不可（infra/logic）= 1。
   - `infra` を最優先にする理由: `command not found` 等は他パターンと共起しうるため、先に確定させる。
   - 先頭に shebang `#!/bin/bash`、`set -uo pipefail`（`-e` は grep 不一致での即終了を避けるため付けない／`apply-fallback.sh` は `-e` 付きだが本スクリプトは grep 評価ロジックのため挙動を合わせて検証）。bash 3.2+ 互換（`mapfile` 等 bash4 機能を使わない）。

2. **`tests/test-failure-classify.bats` を新設**（1 の後）（→ 受入条件 8）

   - 入力フォーマット: 分類対象はテストランナー（bats/pytest/vitest）の生 stdout テキストを `--log` ファイルに渡す。各カテゴリの代表的な失敗スニペットを平文で fixture として与える。
   - `@test` ケース（最低限、exhaustive ではない例）:
     - snapshot 出力 → stdout `snapshot`、status 0
     - mock 出力 → stdout `mock`、status 0
     - fixture 出力 → stdout `fixture`、status 0
     - logic 出力（汎用 assertion 失敗・null reference 等） → stdout `logic`、status 1
     - infra 出力（`command not found`） → stdout `infra`、status 1
     - `--log` 欠落 → 非ゼロ exit
     - `--log` 不在ファイル → 非ゼロ exit
   - `WHOLEWORK_SCRIPT_DIR` モックは不要（本スクリプトは兄弟スクリプトを呼ばない。Notes 参照）。

3. **`skills/code/SKILL.md` Step 9 に Tier 0 ブロックを追加**（1, 2 と並行可）（→ 受入条件 4, 5, 6, 7）

   `### Step 9: Run Tests` 内、`**Test FAIL handling (when test-runner.md reports FAIL):**` の直前（または直後の最初のアクション）に、以下の `#### Tier 0` サブブロックを挿入する。テキストは半角 `!` を含めない。Tier 0 は test FAIL 時の最初のアクションで、修復不可クラスや Tier 0 修復失敗時は既存の FAIL ハンドリングへフォールスルーする。

   挿入する本文（実装者はこの内容をそのまま反映する。`$NUMBER` は既存変数）:

   ```
   #### Tier 0: Structured Test-Failure Recovery

   On test FAIL, before the generic 1-repair-attempt flow below, run structured recovery:

   1. Write the failing test output to `.tmp/test-failure-recovery-$NUMBER.log`.
   2. Classify the failure before acting: run
      `${CLAUDE_PLUGIN_ROOT}/scripts/test-failure-classify.sh --log .tmp/test-failure-recovery-$NUMBER.log`
      and read the category from stdout.
   3. Route by category:
      - `snapshot` / `mock` / `fixture` (repairable): perform at most one targeted auto-fix attempt for
        that class (regenerate snapshot / rebuild mock expectations / update fixture literal). No loop.
      - `logic` / `infra` (not repairable): skip Tier 0 and escalate immediately to Tier 3 — fall through
        to the existing Step 9 FAIL handling below (in `/auto` this path reaches orchestration Tier 3 recovery).
   4. Safety guard — limit changes to the `tests/` directory: after the auto-fix, run `git status --porcelain`
      and confirm only `tests/` paths changed. If any non-`tests/` file changed, revert the Tier 0 changes
      (`git checkout -- <files>`) and fall through to the existing FAIL handling.
   5. Re-run tests once: PASS → continue to commit; still FAIL → fall through to the existing Step 9 FAIL
      handling (generic 1-repair-attempt / route-specific abort/continue).
   6. Record the Tier 0 attempt (classification, files changed, outcome) in the Spec Code Retrospective (Step 12),
      and append attempt details to `.tmp/test-failure-recovery-$NUMBER.log` for Tier 3 sub-agent reference.
   ```

   この本文は rubric の 5 要件を満たす: (1) acting 前に classify（手順 2）、(2) `tests/` 配下のみへ変更を限定（手順 4）、(3) 最大 1 回リトライ（手順 3, 5）、(4) Code Retrospective に記録（手順 6）、(5) logic error を即 Tier 3 へエスカレート（手順 3）。`Tier 0` リテラルと `test-failure-classify` 文字列が Step 9 内に出現する。

4. **`skills/code/SKILL.md` の allowed-tools に新スクリプトを追加**（3 の後）

   frontmatter の `Bash(...)` リスト内（既存の `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh:*` の近く）に `${CLAUDE_PLUGIN_ROOT}/scripts/test-failure-classify.sh:*` を追加。`validate-skill-syntax.py` は本文で参照されるスクリプトが allowed-tools に含まれることを強制するため必須（含めないと「Validate skill syntax」CI が失敗し AC8 にも波及）。

5. **`docs/structure.md` を更新**（1〜4 と並行可）（→ 受入条件 9, 10）

   - Directory Layout の `scripts/ ... (49 files)` を `(50 files)` に変更。
   - Directory Layout の `tests/ ... (59 files)` を `(60 files)` に変更。
   - Key Files > Scripts > Process management セクション（`apply-fallback.sh` / `detect-wrapper-anomaly.sh` の近く）へ `test-failure-classify.sh` の 1 行説明を追加。

## Alternatives Considered

- **Tier 0 を orchestration 層（`run-auto-sub.sh` / `apply-fallback.sh`）に実装する案**: 却下。テスト失敗は code フェーズのローカルテスト実行中、orchestration へのハンドオフより前に発生する。orchestration 側で分類するにはテストを再実行する必要があり、失敗の生コンテキストも失われる。`/code` Step 9 に置けば発生源で完全なコンテキストのまま捕捉できる（Issue 自動解決 #2 の方針と整合）。
- **分類せず汎用リトライのみ行う案**: 却下。既存の 1-repair-attempt が既に汎用修復を行っている。Tier 0 の価値は「構造化分類 + `tests/` 限定セーフガード」で高インパクトな mock/snapshot クラスを決定論的に扱う点にあり、無分類リトライでは差別化されない。

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/test-failure-classify.sh" --> 分類スクリプトが存在する
- <!-- verify: command "bash -n scripts/test-failure-classify.sh" --> 構文エラーなし
- <!-- verify: grep "[Ss]napshot|mock|fixture" "scripts/test-failure-classify.sh" --> 主要 3 パターンの検出ロジックがある
- <!-- verify: grep "Tier 0" "skills/code/SKILL.md" --> `/code` SKILL.md に Tier 0 リカバリステップが追加されている
- <!-- verify: file_contains "skills/code/SKILL.md" "test-failure-classify.sh" --> `/code` SKILL.md から `test-failure-classify.sh` が参照されている
- <!-- verify: rubric "skills/code/SKILL.md Tier 0 specifies that auto-fix attempts (1) classify the failure before acting, (2) limit changes to tests/ directory, (3) retry at most once, (4) record the attempt in Spec Code Retrospective, and (5) escalate logic errors to Tier 3 immediately" --> Tier 0 仕様（5 つの要件）が明記されている
- <!-- verify: section_contains "skills/code/SKILL.md" "### Step 9" "test-failure-classify" --> Step 9 内に Tier 0 分類ステップへの参照がある
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが green（5 パターンの分類テスト含む）
- <!-- verify: grep "(50 files)" "docs/structure.md" --> structure.md の scripts カウントが 50 に更新されている
- <!-- verify: grep "(60 files)" "docs/structure.md" --> structure.md の tests カウントが 60 に更新されている

### Post-merge

- 次回 fix-cycle で発生したテスト失敗が「mock/snapshot」クラスだった場合、Tier 0 で自動修復されることを観察 <!-- verify-type: observation event=fix-cycle -->

## Tool Dependencies

### Bash Command Patterns
- `${CLAUDE_PLUGIN_ROOT}/scripts/test-failure-classify.sh:*` — `skills/code/SKILL.md` の allowed-tools へ新規追加（本文参照スクリプトの allowed-tools 整合制約のため）。本 spec フェーズ自体には新規ツール追加なし。

### Built-in Tools
- `Read` — ファイル読み取り / `Write` — 新規スクリプト・bats 作成 / `Edit` — SKILL.md・structure.md 編集 / `Bash` — bats 実行・分類スクリプト検証

### MCP Tools
- none

## Uncertainty

- **フレームワーク失敗出力キーワードの精度**: 検出キーワード（snapshot/mock/fixture/infra）は Issue 本文由来のヒューリスティック。bats/pytest/vitest/jest で実際の失敗出力文字列は異なる。
  - **検証方法**: 各カテゴリの代表的な実出力サンプルで `tests/test-failure-classify.bats` を作成し、分類結果を検証する。
  - **影響範囲**: Implementation Steps 1, 2。誤分類は Tier 0 の発火可否に影響するが、セーフガード（`tests/` 限定・最大 1 回）により誤修復のリスクは低い。
- **fixture 検出（`expected <X>, got <Y>` 両方リテラル）の信頼性**: リテラル比較の fixture ずれと、ロジック誤りの assertion 失敗を区別するのはヒューリスティックで誤分類しうる。
  - **検証方法**: bats fixture で代表ケースを検証。
  - **影響範囲**: Implementation Step 1。logic を fixture と誤分類しても、修復は `tests/` 限定・最大 1 回で、失敗時は既存フローへフォールスルーするため影響は限定的。

## Smoke Test

**(非該当 — 本 Issue は実外部/MCP ツール呼び出しを含まない。Tier 0 分類スクリプトはローカル grep のみ。省略)**

## Notes

### 自動解決した曖昧ポイント（spec フェーズ、非対話モード）

| # | 曖昧ポイント | 解決内容 | 根拠 |
|---|---|---|---|
| A | `test-failure-classify.sh` の入力インターフェース | `--log <file>` 方式 | `apply-fallback.sh` / `detect-wrapper-anomaly.sh` が確立した既存パターン |
| B | 出力カテゴリの正確な文字列 | `snapshot` / `mock` / `fixture` / `logic` / `infra` の 5 トークン（小文字） | Issue 本文の分類表から導出 |
| C | Step 9 内の Tier 0 挿入位置 | test FAIL 時の最初のアクション（既存の汎用 1-repair-attempt フローの前）。修復不可・失敗時は既存フローへフォールスルー | AC7（Step 9 内に参照）+ 最小変更・低リスク |

### 「Tier 3 escalation」の意味（Issue 自動解決 #2 を踏襲）

Tier 0 コンテキストでの「escalate to Tier 3」は、既存 Step 9 FAIL ハンドリング（汎用 1-repair / route 別 abort/continue）へのフォールスルーを指す。`/auto` 実行時はこのフォールスルー経路が最終的に orchestration Tier 3 recovery（`run-auto-sub.sh` → `spawn-recovery-subagent.sh`）に到達する。Tier 0 が直接 `spawn-recovery-subagent.sh` を起動するわけではない。

### コンフリクト検出（Issue 本文 vs 既存実装）

コンフリクトなし。Issue 本文「既存 3-tier recovery の前段にテスト失敗構造化ハンドリングのレイヤーがない」は実装と一致する（既存 Step 9 は汎用 1-repair-attempt のみで、Tier 0 分類層は存在しない）。

### verify command の解釈に関する注意

- 受入条件 3 の `grep "[Ss]napshot|mock|fixture"` は verify-executor では ripgrep 正規表現（`|` = alternation）として解釈されるため、スクリプト内の任意行にいずれかのキーワードが出現すれば PASS する。
- 受入条件 7 の `section_contains "### Step 9"` は見出しの**部分一致**（`#` 除去後 `Step 9` が `Step 9: Run Tests` に一致）で機能する。
- 受入条件 9/10 のカウント verify は structure.md の既存慣例（`grep "(N files)"`）に合わせた。

### bats / スクリプト固有の注意

- **自己参照除外（#272）不要**: `test-failure-classify.sh` は明示渡しの `--log` ファイルのみを grep し、リポジトリや自身の bats テストファイルをスキャンしない。よって `grep -v 'tests/...'` の自己参照除外は不要。
- **`WHOLEWORK_SCRIPT_DIR` モック不要**: 本スクリプトは `skills/code/SKILL.md`（LLM 実行）から直接呼ばれ、テスト対象のシェルスクリプトからは呼ばれない。かつ兄弟スクリプトを呼ばないため、他の bats テストへのモック追加は不要。
- **bats テスト入力フォーマット**: 分類対象はテストランナーの生 stdout テキスト（bats/pytest/vitest の失敗出力）を `--log` ファイルに渡す。fixture は各カテゴリの代表的失敗スニペットを平文で与える。
- **allowed-tools 追加が必須**: `validate-skill-syntax.py` は本文参照スクリプトが allowed-tools に含まれることを強制するため、Implementation Step 4 を省略すると「Validate skill syntax」CI が失敗する。
- **settings.json.template の変更は不要**: 新規スキル追加ではない（既存 code スキルの修正）。`test-failure-classify.sh` は `.claude/settings.json.template` の `scripts/*.sh` ワイルドカード許可エントリでカバーされ、code スキルが呼ぶ既存スクリプト（`run-code.sh` 等）と同じ許可機構で動作する。`KNOWN_TOOLS`（base tool 名）への追加も不要（追加するのは `Bash(...)` 内のスクリプトパスであり base tool 名ではないため）。
