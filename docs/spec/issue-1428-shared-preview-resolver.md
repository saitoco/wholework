# Issue #1428: review: 共有 preview 解決スクリプト基盤 + preview-url-command を /review 直接実行で解決

## Overview

`preview-url-command` は現在 `scripts/run-review.sh` の `pr-preview` ゲート内でのみ解決され、`/review` を `--auto` なしで直接実行する経路では一切参照されない。本 Issue は解決ロジックを共有スクリプト `scripts/resolve-preview-env.sh` に切り出し、`skills/review/SKILL.md` Step 8.0 の Fast path からも呼べるようにすることで、直接実行時も `preview-url-command` を自動解決できるようにする。この共有スクリプトは兄弟 Sub-issue #1429 (`preview-basic-auth-command` 解決) が拡張する基盤となる。

## Changed Files

- `scripts/resolve-preview-env.sh` (新規): `run-review.sh` の `_resolve_preview_url_command()` (L137-196) を切り出した共有スクリプト。`url` サブコマンドのみを実装 (Basic Auth モードは #1429 が追加)。bash 3.2+ 互換
- `scripts/run-review.sh`: `_resolve_preview_url_command()` を共有スクリプト呼び出しへの薄いラッパーに置き換え。既存コメント文言 (`preview-url-command` を含む) は保持し、`#1410` の既存 verify command `grep "preview-url-command" "scripts/run-review.sh"` の生存を維持する。呼び出し箇所 (L271)・メッセージ文言・exit code契約 (常に0のfail-open) は変更しない
- `skills/review/SKILL.md`:
  - frontmatter `allowed-tools` (L5) に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-env.sh:*` を追加 (#1053 の bundled script 追加先例と同型)
  - L113 の `detect-config-markers.md` 読み込みの retain リストに `HAS_PR_PREVIEW_CAPABILITY` を追加 (既存の1回の読み込みで取得可能、追加の読み込み不要)
  - Step 8.0 (L227付近) の Fast path を拡張: `PREVIEW_URL` 未 export かつ `HAS_PR_PREVIEW_CAPABILITY=true` かつ `preview-url-command` が宣言されている場合の解決ステップを、既存の「Fast path (env 既存)」と「Deployments API (steps 1-4)」の間に追加
- `modules/detect-config-markers.md` (L91): 「Currently consumed only by `scripts/run-review.sh`; no skill reads `PREVIEW_URL_COMMAND` directly」の記述を撤去し、`skills/review/SKILL.md` も消費する旨に更新 — [Steering Docs sync candidate] この記述は #1428 着地後に事実と矛盾するため MUST UPDATE (単なる相互参照ではなく事実の正確性の問題)
- `docs/guide/customization.md`:
  - L129 (Available Keys 表, `preview-url-command` 行): "not by `/review` invoked directly as a skill" を撤去
  - L219 (Resolution order の説明段落): 直接実行でも同じ優先順位 (export済み > command解決 > Deployments API) が適用される旨を追記
- `docs/ja/guide/customization.md`: 上記2箇所の ja ミラー更新 ([Steering Docs sync candidate], `docs/translation-workflow.md` の同期手順に従う)
- `docs/guide/adapter-guide.md` (L54-64): 「`scripts/run-review.sh` invokes directly via `bash -c`」の記述を、共有スクリプト経由で `run-review.sh` と `/review` 直接実行の両方から呼ばれる旨に更新 — [Steering Docs sync candidate] 事実の正確性の問題 (呼び出し元が1つから2つに増える)
- `docs/ja/guide/adapter-guide.md`: 上記の ja ミラー更新 ([Steering Docs sync candidate])
- `docs/structure.md` (L32): `(92 files)` → `(93 files)`
- `docs/ja/structure.md` (L25): `92 ファイル` → `93 ファイル`
- `tests/resolve-preview-env.bats` (新規): 共有スクリプトの単体テスト (guards: timeout・空出力・非ゼロ終了・2048文字超・URL形式検証・MAIN_REPO_ROOT解決)
- `tests/run-review.bats`: `setup()` に `cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/resolve-preview-env.sh" "$MOCK_DIR/resolve-preview-env.sh"` を追加 (`guard-prefix.sh` と同じ実体コピー方式、L111 付近)。既存13テスト (preview-url-command関連) が薄いラッパー化後も同じメッセージ文言・exit code で PASS することを維持
- `tests/review.bats`: Step 8.0 の新しい Fast path 拡張に対応するテストケースを追加 (`preview-url-command` 宣言時に共有スクリプトが呼ばれ `{{base_url}}` が解決されることの検証)

**Not in scope (deliberately excluded, reviewed — no change needed):**
- `modules/orchestration-fallbacks.md` L636: `run-review.sh` 自身の PENDING ゲート (Deployments API 未到達時のフォールバック案内) についての記述であり、`/review` 直接実行時の Step 8.0 解決とは別の仕組みを指すため対象外。実際に読み確認済み
- `scripts/detect-wrapper-anomaly.sh` L147: 同上、`run-review.sh` 自身の wrapper 異常検知ヒントであり対象外。実際に読み確認済み

## Implementation Steps

1. `scripts/resolve-preview-env.sh` を新規作成する (→ 受入条件 AC3, AC4)
   - Usage: `resolve-preview-env.sh url <pr-number>`
   - `run-review.sh` の `_resolve_preview_url_command()` (L137-196) と同一の処理を実装: `get-config-value.sh preview-url-command` で設定値取得 → 空なら exit 0 (何も出力しない) → `{pr}` プレースホルダ置換 → 30秒 timeout (timeout/gtimeout/手動 watchdog の3段フォールバック、既存と同一) → 非ゼロ終了・空出力・2048文字超・`^https?://[^[:space:]/]+` 不一致の4ガード
   - `.wholework.yml` の読み取りは呼び出し元の CWD に依存せず、`git worktree list --porcelain` で MAIN_REPO_ROOT を解決してから行う (run-review.sh L28 と同一パターン。worktree 内 (`/review` 直接実行時) から呼ばれても main repo root 基準で読むことで、`run-review.sh` (既に main repo root で動作) との信頼境界を揃える)
   - `SCRIPT_DIR` は `WHOLEWORK_SCRIPT_DIR` 環境変数を尊重する (`docs/tech.md` § BATS Mocking Convention 準拠、bats でのモック差し替えを可能にする)
   - 成功時: 解決した URL を stdout に1行で出力し exit 0。警告メッセージは既存と同一文言で stderr に出力 (`Resolved PREVIEW_URL via preview-url-command for PR #${PR_NUMBER}` 等)
   - 失敗時 (いずれのガードに引っかかった場合も): stdout は空、exit 0 (fail-open — 既存の `run-review.sh` 関数の契約を完全に保持。呼び出し元は空 stdout を「Deployments API にフォールバック」のシグナルとして扱う)
   - 引数不正 (mode不明、PR番号非数値) のみ exit 1
   - **Fail-safe critical script該当**: 本スクリプトは失敗時に安全側 (Deployments API フォールバック) へ倒れる fail-open 設計。エッジケースの扱い: 空/巨大入力 (PR番号は数値のみ許可、設定コマンド空なら即 exit 0)、特殊文字 (CRLF は既存同様 `tr -d '\r'` で除去、URL正規表現マッチによる形式検証は既存 #1410 実装をそのまま踏襲し新規に拡張しない)、依存コマンド失敗時は fail-open (空 stdout, exit 0) — 新規に fail-closed 化しない
   - bash 3.2+ 互換 (`mapfile`/連想配列不使用)

2. `scripts/run-review.sh` の `_resolve_preview_url_command()` (L137-196) を薄いラッパーに置き換える (after 1) (→ 受入条件 AC4, AC5)
   ```bash
   # Resolve PREVIEW_URL from a project-declared preview-url-command (Issue #1410),
   # delegating guard logic to the shared resolver (scripts/resolve-preview-env.sh, Issue #1428).
   _resolve_preview_url_command() {
     local _resolved
     _resolved=$("$SCRIPT_DIR/resolve-preview-env.sh" url "$PR_NUMBER") || return 0
     [[ -n "$_resolved" ]] && { PREVIEW_URL="$_resolved"; export PREVIEW_URL; }
   }
   ```
   コメント文言に `preview-url-command` の文字列を保持することで、既存 verify command `grep "preview-url-command" "scripts/run-review.sh"` (#1410) の生存を確認する。呼び出し箇所 L271 (`[[ -z "${PREVIEW_URL:-}" ]] && _resolve_preview_url_command || true`) は変更しない

3. `skills/review/SKILL.md` の frontmatter/config 読み込みを更新する (after 1) (→ 受入条件 AC1)
   - frontmatter `allowed-tools` (L5) に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-env.sh:*` を追加
   - L113 の `detect-config-markers.md` 読み込みステップの retain リストに `HAS_PR_PREVIEW_CAPABILITY` を追加: "Retain `ALWAYS_PR` for use in the Size mapping below." → "Retain `ALWAYS_PR` and `HAS_PR_PREVIEW_CAPABILITY` for use below."

4. `skills/review/SKILL.md` Step 8.0 (L227付近) の Fast path を拡張する (after 3) (→ 受入条件 AC1, AC2)
   - 既存の「Fast path — `PREVIEW_URL` env variable already set」の直後、「1. Get the PR branch name」の直前に新セクションを挿入:
     ```markdown
     **preview-url-command resolution — `PREVIEW_URL` unset but declared via config:**

     If `PREVIEW_URL` is not exported, `HAS_PR_PREVIEW_CAPABILITY` is `true`, and `.wholework.yml` declares `preview-url-command`, resolve it in a single Bash tool call:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-env.sh url "$NUMBER"
     ```
     If the command produces non-empty stdout, treat it as the resolved preview URL: replace `{{base_url}}` with this **literal value** (not a `$PREVIEW_URL` shell reference — Bash tool calls do not persist exported env vars across invocations) and proceed to step 5, skipping the Deployments API lookup below — mirroring how the Deployments API path itself substitutes its resolved `environment_url` literally. If stdout is empty, fall through to the Deployments API path below unchanged.
     ```
   - 挿入位置の判断基準: 既存の優先順位 (export済み > command解決 > Deployments API) をそのまま反映する順序

5. `modules/detect-config-markers.md` (L91) を更新する (parallel with 1-4)
   - "Currently consumed only by `scripts/run-review.sh` (bash wrapper) via `get-config-value.sh`; no skill reads `PREVIEW_URL_COMMAND` directly" → "Consumed by `scripts/run-review.sh` (bash wrapper) directly via `get-config-value.sh`, and by `skills/review/SKILL.md` Step 8.0 (via the shared `scripts/resolve-preview-env.sh`, Issue #1428) for direct `/review` execution" のように更新

6. `docs/guide/customization.md` と `docs/ja/guide/customization.md` を更新する (after 1-4) (→ 受入条件 AC6)
   - en L129: "Only consulted by `scripts/run-review.sh`'s preview-wait gate (covers `/auto`, scheduled runs, and direct wrapper invocation) — not by `/review` invoked directly as a skill." を削除し、"Consulted by both `scripts/run-review.sh`'s preview-wait gate and `/review`'s own Step 8.0 when invoked directly as a skill (via the shared `scripts/resolve-preview-env.sh`, Issue #1428)." に置き換える
   - en L219: Resolution order の説明文に、直接実行時も同じ優先順位が適用される旨を追記
   - ja ミラーを同内容で更新 (`docs/translation-workflow.md` の同期手順に従う)

7. `docs/guide/adapter-guide.md` と `docs/ja/guide/adapter-guide.md` を更新する (parallel with 6)
   - L54-64: "a project-local *script* ... that `scripts/run-review.sh` invokes directly via `bash -c`" を、共有スクリプト経由で `run-review.sh` と `/review` 直接実行の両方から呼ばれる旨に更新。ja ミラーを同内容で更新

8. `docs/structure.md` (L32) と `docs/ja/structure.md` (L25) のスクリプト件数を更新する (after 1)
   - en: `(92 files)` → `(93 files)` / ja: `92 ファイル` → `93 ファイル`

9. `tests/resolve-preview-env.bats` を新規作成する (after 1) (→ 受入条件 AC7)
   - 新規ロジック (ガード5種 + MAIN_REPO_ROOT解決) を検証する新規テストケースを追加したうえでスイートが PASS すること。既存 `tests/resolve-preview-ac-fallback.bats` の構造 (usage/exit code のテストパターン) を参考にする
   - テストケース: 正常解決、`{pr}` 置換、timeout、非ゼロ終了、空出力、2048文字超、非URL出力、mode不明時のexit 1、PR番号非数値時のexit 1

10. `tests/run-review.bats` と `tests/review.bats` にテストを追加する (after 1-4) (→ 受入条件 AC7, AC1)
    - `tests/run-review.bats` の `setup()` に実体コピーを追加: `cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/resolve-preview-env.sh" "$MOCK_DIR/resolve-preview-env.sh"` (L111 の `guard-prefix.sh` コピー行の近くに追加)。既存13テスト (`success: preview-url-command resolves...` 等、L511-741付近) が薄いラッパー化後も同じ出力文言・exit code で PASS することを確認する (新規ロジック固有のテストケースは9で追加済み)
    - `tests/review.bats` に、`preview-url-command` 宣言時に Fast path が共有スクリプトを呼び `{{base_url}}` を解決することを検証する新規テストケースを追加したうえでスイートが PASS すること

## Alternatives Considered

**採用: 共有スクリプト化 (`scripts/resolve-preview-env.sh`)**

Precedent 調査 (`/issue` Step 12a) が発見した `#1053` の先例 (`skills/verify/SKILL.md` への `reconcile-phase-state.sh:*` bundled script 追加) と同型。固定パスのスクリプト1本を `allowed-tools` に列挙するだけで済み、プロジェクト宣言コマンド自体はスクリプト内部の `bash -c` 実行に閉じ込められる。

**不採用案1: `modules/detect-config-markers.md` の既存マーカー定義のみで対応 (共有スクリプトなし)**

`preview-url-command` の値自体は既に `detect-config-markers.md` の Marker Definition Table に定義済みで、`skills/review/SKILL.md` は既存の1回の読み込みで値を取得できる (Implementation Step 3)。しかし「読んだコマンド文字列を実行する」部分を SKILL.md 本文に直接書くと、30秒 timeout・4ガード・`{pr}` 置換のロジックが `run-review.sh` と重複し、AC3 (重複実装でない) に反する。Precedent 調査もこの代替案を検討した上で「共有スクリプト案のほうが優位」と判定している

**不採用案2: `run-review.sh` を SKILL.md から呼び出す**

`run-review.sh` は `claude -p` を起動する側であり、`/review` の Step 8.0 から `run-review.sh` を呼び出すと循環参照になる。不成立

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md Step 8.0 の Fast path に、PREVIEW_URL 未 export かつ preview-url-command が宣言されている場合の解決ステップが追加されている" --> Step 8.0 に解決ステップが追加されている
- <!-- verify: rubric "解決ステップは capabilities.pr-preview: true をゲートとして踏襲している" --> capabilities.pr-preview ゲートが踏襲されている
- <!-- verify: file_exists "scripts/resolve-preview-env.sh" --> 共有解決スクリプトが新規作成されている
- <!-- verify: rubric "scripts/run-review.sh の _resolve_preview_url_command は scripts/resolve-preview-env.sh の呼び出しに置き換えられており、run-review.sh 自身に30秒timeout・空出力/非ゼロ終了/2048文字超のガード・URL形式検証ロジックが重複実装されていない" --> 重複実装でないことの確認
- <!-- verify: grep "preview-url-command" "scripts/run-review.sh" --> run-review.sh からキー名の参照が失われていない
- <!-- verify: file_not_contains "docs/guide/customization.md" "not by \`/review\` invoked directly as a skill" --> ドキュメントが直接実行時の挙動変更を反映して更新されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テスト全PASS

### Post-merge

- `preview-url-command` を宣言した実プロジェクトで `--auto` なしの `/review <PR番号>` を直接実行し、事前の手動 export なしで preview 層 AC が UNCERTAIN にならず実行されることを観察 <!-- verify-type: manual -->

## Uncertainty

- **`--when="test -n \"$PREVIEW_URL\""` ガードとリテラル代入方式の相互作用**: `/issue` が `ac-tier: preview` の auto subcase AC に自動付与する `--when="test -n \"$PREVIEW_URL\""` は、`modules/verify-executor.md` により実際の Bash サブプロセスで評価される shell condition である。一方、Step 8.0 の Deployments API 経路 (既存) と本 Issue が追加する preview-url-command 経路はいずれも `{{base_url}}` への**リテラル値代入**であり、`PREVIEW_URL` を実際に export するわけではない。そのため、これら2経路で解決された場合、`--when` ガード付きの AC は (Fast path=env既存の場合を除き) SKIP される可能性がある
  - **検証方法**: `/code` 実装後、実際に `ac-tier: preview` + `--when` ガード付き AC を Deployments API 経路 / preview-url-command 経路それぞれで動作確認し、SKIP されるかどうかを Code Retrospective に記録する
  - **影響範囲**: この挙動は Deployments API 経路について既に (#1428 以前から) 存在する特性であり、本 Issue が新規に導入するものではない。本 Issue のスコープでは「修正」しない — 修正が必要と判断された場合は別 Issue とする
  - **Out of Scope 扱いの根拠**: 親 Issue #1423 の Out of Scope に明記された「run-review.sh 経由の既存解決ロジック自体の挙動変更」とは異なる論点 (SKILL.md 側の `--when` 評価契約) だが、Deployments API 経路という既存機構への言及であり、preview-url-command 経路固有の新規欠陥ではないため、本 Issue の Pre-merge AC には含めない

## Notes

### Auto-Resolved Ambiguity Points (`/spec` Step 7)

- **共有スクリプトのインターフェース簡略化**: `/issue` 起票時点の Proposal 例示 (`resolve-preview-env.sh url --key preview-url-command`) から `--key` フラグを削除し、`url` サブコマンドが `preview-url-command` を固定的に読む設計に簡略化した。理由: Basic Auth 解決は `#1429` で別サブコマンド (`basic-auth`) として追加される設計のため、`url` サブコマンドが複数のキーを読み分ける汎用性は不要 (`docs/tech.md` Spec Simplicity Rules に整合)。AC 本文 (「解決ステップが追加されている」) は変更を要しないため自動解決
- **Fast path 拡張の挿入位置**: 既存の「Fast path (env既存)」→ 新規「preview-url-command 解決」→ 既存「Deployments API (steps 1-4)」の順序で確定。Issue 本文 Proposal item 4 が「既存優先順位ガード (export済み > command解決 > Deployments API) をそのまま複写する」と明記しており一意に推論可能

### Steering Docs Sync Candidates (要確認、`/code` が最終判断)

- `modules/detect-config-markers.md` L91 — MUST UPDATE (事実の正確性、Implementation Step 5)
- `docs/guide/adapter-guide.md` L54-64 + ja ミラー — 更新推奨 (Implementation Step 7)
- `modules/orchestration-fallbacks.md` L636、`scripts/detect-wrapper-anomaly.sh` L147 — 確認済み、対象外 (run-review.sh 自身の PENDING ゲートについての記述であり、Step 8.0 とは別の仕組み)

### Sub-issue 分割の背景

本 Issue は `#1423` (親) の Sub-issue。Basic Auth (`preview-basic-auth-command`) の解決は兄弟 Sub-issue `#1429` (blocked by 本 Issue) が担当する。`#1429` は本 Issue が作成する `scripts/resolve-preview-env.sh` を拡張する前提のため、本 Issue の完了 (マージ) が `#1429` の着手前提となる。

## Consumed Comments

No new comments since last phase.

## spec retrospective

### Minor observations

- `/issue` 起票時点の Proposal 例示 (`resolve-preview-env.sh url --key preview-url-command`) は「How」レベルの実装詳細を含んでいたが、Basic Auth モード (`#1429`) が別サブコマンドとして拡張する設計を踏まえると `--key` フラグは不要と判明した。`/issue` の Proposal 記述はあくまで「共有スクリプト化」という方向性の例示であり、正確なインターフェースは `/spec` が決めるべき — `/issue` (What) vs `/spec` (How) の責任境界どおりに機能した一例

### Judgment rationale

- インターフェース簡略化 (`--key` フラグ削除) は自動解決。Basic Auth 用の別サブコマンドが `#1429` で追加される設計のため `url` サブコマンドの汎用性は不要、かつ AC 本文への影響もないため
- Fast path 拡張の挿入順序 (env既存 → preview-url-command → Deployments API) は Issue 本文の Proposal item 4 が明記する優先順位から一意に確定できた

### Uncertainty resolution

- `--when="test -n \"$PREVIEW_URL\""` ガードとリテラル値代入方式 (Deployments API 経路・preview-url-command 経路の両方) の相互作用は、コードベース調査で新たに発見した未解決の疑問点。既存 (Deployments API) 経路にも同じ特性があり #1428 固有の新規欠陥ではないと判断し、Pre-merge AC には含めず Uncertainty として記録した。`/code` 実装後に実地確認し Code Retrospective に記録する運用とした

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1-10 は Spec の記述どおりに実装した (インターフェース・挿入位置・ゲート条件を含め設計からの逸脱なし)

### Design Gaps/Ambiguities
- なし。Spec の Alternatives Considered / Notes が事前に判断根拠を記録済みだったため、実装中に新たな曖昧点は発生しなかった

### Rework
- `tests/resolve-preview-env.bats` の 2048 文字超テストで、`mock_config_value()` ヘルパーが未クオートの heredoc (`<<MOCK`) 内で `echo "$1"` の形にコマンド文字列を直接展開していたため、`$1` に二重引用符 (`python3 -c "print(...)"`) が含まれるケースで生成されるモックスクリプトのクオートが壊れて構文的に破綻した。値を別ファイルへ `printf '%s' "$1" > file` で書き出し、heredoc 側は `<<'MOCK'` (クオート済み) にして `cat` で読み込む方式に変更して解消した — bats のモック生成で「呼び出し元の任意文字列をそのまま heredoc に埋め込む」パターンは、値に `"` を含むケースで一般に壊れる点に注意

### Uncertainty resolution (`--when="test -n \"$PREVIEW_URL\""` との相互作用)
- Spec Uncertainty 節の疑問点をコードベース調査で確認した (実プロジェクトでの実地確認ではなく、静的な契約の突き合わせによる確認 — 本 Issue の non-interactive 実行では `capabilities.pr-preview: true` を宣言した実プロジェクトが手元になく、実地確認は実施できなかったため best-effort で代替した)
- `modules/verify-executor.md` は `--when` 条件を実際の Bash サブプロセスで評価する。Step 8.0 の Deployments API 経路 (既存) と本 Issue が追加した preview-url-command 経路は、いずれも解決した URL を `{{base_url}}` へ**リテラル文字列として代入**するのみで、実際に `PREVIEW_URL` を shell に `export` するわけではない
- そのため `--when` 評価用のサブプロセスには `$PREVIEW_URL` は存在せず、`test -n "$PREVIEW_URL"` は偽と評価され、`--when` ガード付き AC は「Fast path (env 既存)」以外の2経路 (Deployments API・preview-url-command) では SKIP される
- Spec の想定どおり、これは Deployments API 経路に既に (#1428 以前から) 存在していた特性であり、preview-url-command 経路固有の新規欠陥ではない。本 Issue のスコープでは修正しない (Spec の Uncertainty 節・Out of Scope の判断を踏襲)
- 修正が必要と判断された場合は別 Issue とする (Spec の判断をそのまま維持)

## review retrospective

### Spec vs. implementation divergence patterns

- Parser/Validator Edge Case Pre-check の実測実行で、`scripts/resolve-preview-env.sh` に Spec の Implementation Steps には現れなかった実装レベルの逸脱が複数見つかった: (a) `printf | head -n 1 | tr -d` のパイプが `set -euo pipefail` 配下の独立スクリプト化で SIGPIPE 経由の異常終了を起こしうる (移行元は errexit 無効化された関数本体だったため顕在化していなかった)、(b) URL 検証正規表現が末尾アンカーを持たず同一行の末尾ゴミを許容してしまう、(c) PR 番号検証が `grep` の行単位マッチで複数行入力に対して移行元の bash 正規表現 (全体マッチ) より緩い。いずれも Spec の Implementation Step 1 が「既存 #1410 実装をそのまま踏襲」と記述していた箇所で、"そのまま移植" が独立スクリプト化という文脈変化 (関数 → 独立 `set -e` スクリプト) と組み合わさることで新規リグレッションを生んだ。実コード実行によるエッジケース検証 (静的読解だけでは見つからない) が有効だった事例
- Steering Documents (`docs/tech.md`・`docs/structure.md`) の同期漏れが 2 件重複して発生した: Spec の Changed Files / Pre-merge AC はいずれも `docs/tech.md` の `HAS_PR_PREVIEW_CAPABILITY` ゲート一覧行、および `docs/structure.md` の Key Files 一覧 (件数コメントのみ更新、一覧本体は未更新) を対象に含めていなかった。`docs/guide/customization.md` / `docs/guide/adapter-guide.md` は Spec 対象に含まれ実際に更新されたが、同種の SSoT である `docs/tech.md`/`docs/structure.md` Key Files が漏れた — 「同じ変更内容を複数の SSoT に反映する」タスクで対象ドキュメントの列挙が不完全になりやすいパターン

### Recurring issues

- 本 PR のレビューで検出した SHOULD/CONSIDER 12 件のうち 5 件 (SIGPIPE 回帰・regex 末尾アンカー・PR 番号検証・`cat` ガード欠落・wrapper の暗黙 return 1) は共通して「`set -e`/`pipefail` 環境下でのエラーハンドリングの契約が、コードを移動 (関数 → 独立スクリプト) する際に暗黙のうちに変化する」という同一クラスの問題だった。今後同様の「既存ロジックを共有スクリプト化して切り出す」設計の Issue では、Spec の Implementation Steps に "移行前後で `set -e`/errexit の有効/無効コンテキストが変わらないか" を明示的なチェック項目として含めることが有効と考えられる

### Acceptance criteria verification difficulty

- 特になし。Pre-merge AC 7 件はいずれも `rubric` / `file_exists` / `grep` / `file_not_contains` / `github_check` の verify command が過不足なく整備されており、UNCERTAIN や verify command の不備は発生しなかった

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC ゲート (7 件) は全て checked 済みで review-incomplete-fallback も検出されなかったため、override マーカーなしで通常経路のまま squash merge を実行した
- `gh-pr-merge-status.sh` が `mergeable=true, reason=clean` を返したため、コンフリクト解消 (Step 3) はスキップし直接 Step 4 (squash merge) に進んだ

### Deferred Items
- `--when="test -n \"$PREVIEW_URL\""` ガード付き auto-subcase の preview AC が `preview-url-command` 経路でも `export PREVIEW_URL` されないため実質 SKIP され続ける件は、review フェーズに続き本フェーズでも据え置き。修正する場合は別 Issue で `/review` 側に `export PREVIEW_URL` を追加する設計を検討する必要がある

### Notes for Next Phase
- Post-merge AC (「`preview-url-command` を宣言した実プロジェクトで `--auto` なしの `/review` を直接実行し観察」) は `verify-type: manual` のため、`/verify` は自動確認できない。人手による観察結果の記録が必要
- 全 bats テストスイートは merge フェーズ実行時点で CI 上 SUCCESS 済みであることを `gh-pr-merge-status.sh` の `ci_status: success` で確認済み
