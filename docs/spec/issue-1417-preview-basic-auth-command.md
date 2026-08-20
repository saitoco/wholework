# Issue #1417: run-review: PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS を project-side スクリプトで自動解決する preview-basic-auth-command 設定キーを追加

## Overview

`#1410` で `preview-url-command` により `PREVIEW_URL` の自動解決が実現したが、同じく `run-review.sh` 経由の実行では export 主体が存在しない `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` (Basic 認証保護された preview 環境向け、`#1051`/`#1074` で消費側は実装済み) には同種の自動解決がない。`.wholework.yml` に `preview-basic-auth-command` キーを追加し、`scripts/run-review.sh` が `preview-url-command` と同じタイミング・同じ仕組みで両変数を自動解決・export できるようにする。

コードベース調査により Background の記述 (`modules/verify-executor.md` / `modules/browser-adapter.md` / `modules/lighthouse-adapter.md` / `modules/visual-diff-adapter.md` での消費実装、`run-review.sh` の `preview-url-command` fast path 実装、masking 方針) を grep で再確認済み。`run-review.sh` に `PREVIEW_BASIC` への参照は現状ゼロで、Issue の前提通り解決側の欠落が存在する。

## Changed Files

- `modules/detect-config-markers.md`: `preview-basic-auth-command` キーを Marker Definition Table / YAML Parsing Rules / Output Format に追加
- `scripts/run-review.sh`: `_resolve_preview_basic_auth_command()` fast path を追加 (`_resolve_preview_url_command()` と同型) — bash 3.2+ compatible
- `tests/run-review.bats`: 新規 fast path を検証するテストケースを追加
- `docs/guide/customization.md`: config-reference table に行追加 + "Automating Basic Auth credential resolution with `preview-basic-auth-command`" 節を新設
- `docs/guide/adapter-guide.md`: Steering Docs sync candidate — 既存の `preview-url-command` 段落に隣接する形で `preview-basic-auth-command` の段落を追加
- `docs/tech.md`: Steering Docs sync candidate — `HAS_PR_PREVIEW_CAPABILITY` 行の説明文末に 1 文追加
- `docs/ja/guide/customization.md`: `docs/translation-workflow.md` に基づく ja ミラー同期
- `docs/ja/guide/adapter-guide.md`: 同上
- `docs/ja/tech.md`: 同上

## Implementation Steps

1. `modules/detect-config-markers.md` に `preview-basic-auth-command` キーを追加する (→ Pre-merge AC1)

   **Marker Definition Table** — `preview-url-command` の行 (42行目付近) の直後に追加:
   ```
   | `preview-basic-auth-command` | `PREVIEW_BASIC_AUTH_COMMAND` | Command string (extract value as-is) | `""` |
   ```

   **YAML Parsing Rules** — `preview-url-command` の説明箇条書き (90行目付近) の直後に追加:
   ```
   - `preview-basic-auth-command` is treated as a shell command string with quotes removed (same handling as `production-url`). Same inline-comment-stripping caveat as `preview-url-command` (a space followed by `#` is stripped by `scripts/get-config-value.sh`). Currently consumed only by `scripts/run-review.sh` (bash wrapper) via `get-config-value.sh`; no skill reads `PREVIEW_BASIC_AUTH_COMMAND` directly — see `docs/guide/customization.md` § "Automating Basic Auth credential resolution with `preview-basic-auth-command`" for coverage scope
   ```

   **Output Format section** — `PREVIEW_URL_COMMAND` の行 (123行目付近) の直後に追加:
   ```
   PREVIEW_BASIC_AUTH_COMMAND: shell command string extracted from preview-basic-auth-command (default: "")
   ```

2. (after 1) `scripts/run-review.sh` に `_resolve_preview_basic_auth_command()` を追加し、既存の `capabilities.pr-preview: true` gate 内で呼び出す (→ Pre-merge AC2, AC3, AC4, AC5)

   `_resolve_preview_url_command()` 関数 (138-202行目) の直後に、同型の関数を追加する。`get-config-value.sh` 呼び出し・`{pr}` 置換・timeout/gtimeout/手動 watchdog の 3 段フォールバック・非ゼロ終了時/空出力時/2048 文字超過時のフォールバックガードは `_resolve_preview_url_command` と同一パターンを踏襲する。相違点は次の 2 点のみ:
   - URL 形式チェックの代わりに、出力 (trim 済み・1 行目のみ) に `:` が含まれるかを検証する (`username:password` 形式チェック)
   - timeout/gtimeout 不在時のフォールバック分岐で使う一時ファイルは、認証情報を含むため `.tmp/preview-url-command-output.$$` (PID サフィックスの平文ファイル、非機密の URL 向け) ではなく `mktemp .tmp/preview-basic-auth-command-output-XXXXXX` (600 権限で作成) を使う — `modules/verify-executor.md` の `curl-auth-XXXXXX.cfg` / `modules/lighthouse-adapter.md` の `lighthouse-headers-XXXXXX.json` と同じ、認証情報を扱う一時ファイルの既存規約に合わせる

   ```bash
   # Resolve PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS from a project-declared
   # preview-basic-auth-command (Issue #1417), when neither is already
   # exported. Same 30s bounded execution and non-zero-exit/empty-output/
   # 2048-char-length guards as _resolve_preview_url_command above;
   # additionally requires the (trimmed, first-line) output to contain a
   # `:` separating username from password. Any failure mode leaves both
   # variables unset and preserves the existing unauthenticated fallback
   # unchanged (deliberate fail-open, matching the Issue's explicit design
   # — not a new introduction of fail-open behavior).
   _resolve_preview_basic_auth_command() {
     local _cmd
     _cmd=$("$SCRIPT_DIR/get-config-value.sh" preview-basic-auth-command "" 2>/dev/null || echo "")
     [[ -z "$_cmd" ]] && return 0

     _cmd="${_cmd//\{pr\}/$PR_NUMBER}"

     local _resolved _resolved_status
     if command -v timeout >/dev/null 2>&1; then
       _resolved=$(timeout --kill-after=10 30 bash -c "$_cmd" 2>/dev/null)
       _resolved_status=$?
     elif command -v gtimeout >/dev/null 2>&1; then
       _resolved=$(gtimeout 30 bash -c "$_cmd" 2>/dev/null)
       _resolved_status=$?
     else
       mkdir -p .tmp 2>/dev/null || true
       local _tmpout
       _tmpout="$(mktemp .tmp/preview-basic-auth-command-output-XXXXXX)"
       bash -c "$_cmd" >"$_tmpout" 2>/dev/null &
       local _cmd_pid=$!
       ( sleep 30; kill -0 "$_cmd_pid" 2>/dev/null && kill -9 "$_cmd_pid" 2>/dev/null ) &
       local _watchdog_pid=$!
       wait "$_cmd_pid" 2>/dev/null
       _resolved_status=$?
       kill "$_watchdog_pid" 2>/dev/null
       wait "$_watchdog_pid" 2>/dev/null
       _resolved=$(cat "$_tmpout" 2>/dev/null)
       rm -f "$_tmpout"
     fi

     if [[ "$_resolved_status" -ne 0 ]]; then
       echo "Warning: preview-basic-auth-command exited non-zero (status=${_resolved_status}); leaving Basic Auth unset" >&2
       return 0
     fi

     _resolved=$(printf '%s' "$_resolved" | head -n 1 | tr -d '\r')
     local _resolved_trimmed
     _resolved_trimmed="${_resolved#"${_resolved%%[![:space:]]*}"}"
     _resolved_trimmed="${_resolved_trimmed%"${_resolved_trimmed##*[![:space:]]}"}"

     if [[ -z "$_resolved_trimmed" ]]; then
       echo "Warning: preview-basic-auth-command produced empty output; leaving Basic Auth unset" >&2
       return 0
     fi
     if [[ "${#_resolved_trimmed}" -gt 2048 ]]; then
       echo "Warning: preview-basic-auth-command output exceeds 2048 chars; leaving Basic Auth unset" >&2
       return 0
     fi
     if [[ "$_resolved_trimmed" != *:* ]]; then
       echo "Warning: preview-basic-auth-command output is not in username:password format; leaving Basic Auth unset" >&2
       return 0
     fi

     PREVIEW_BASIC_USER="${_resolved_trimmed%%:*}"
     PREVIEW_BASIC_PASS="${_resolved_trimmed#*:}"
     export PREVIEW_BASIC_USER PREVIEW_BASIC_PASS
     echo "Resolved PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS via preview-basic-auth-command for PR #${PR_NUMBER}" >&2
   }
   ```

   `${_resolved_trimmed%%:*}` は最初の `:` より前 (username)、`${_resolved_trimmed#*:}` は最初の `:` より後の残り全て (password) を取り出す — password に `:` が含まれても最初の 1 個で分割することで保持される。

   呼び出し箇所は既存の `if [[ -z "$_pending_reason" ]] && ... pr-preview: true; then` ブロック (204行目付近) 内、`_resolve_preview_url_command` 呼び出しの直後に追加する:
   ```bash
     [[ -z "${PREVIEW_URL:-}" ]] && _resolve_preview_url_command || true
     [[ -z "${PREVIEW_BASIC_USER:-}" && -z "${PREVIEW_BASIC_PASS:-}" ]] && _resolve_preview_basic_auth_command || true
   ```
   両変数が「共に未設定」の場合のみ解決を試みる (どちらか一方だけ手動 export 済みの場合は上書きも補完もせず、その状態を尊重してスキップする)。この呼び出しは `PREVIEW_URL` 解決の成否と独立して常に実行される。`_pending_reason` が非空の場合はブロック全体がスキップされ、後続の `claude` 起動 (259-268行目) 自体が実行されないため、Basic 認証解決も無駄なく併せてスキップされる。

3. (after 2) `tests/run-review.bats` に新規テストケースを追加する (→ Pre-merge AC3, AC4, AC5 の実証、AC7 の前提)

   既存の `preview-url-command` テストブロック (518-761行目、`get-config-value.sh` を `case` 文でモックするパターン) と同じモックハーネスを用いて、少なくとも次のテストケースを追加する:
   - `success: preview-basic-auth-command resolves PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS when both are unset`
   - `success: exported PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS take precedence over preview-basic-auth-command`
   - `success: preview-basic-auth-command {pr} placeholder is substituted with the PR number`
   - `fallback: preview-basic-auth-command failure (non-zero exit) leaves Basic Auth unset`
   - `fallback: preview-basic-auth-command empty output leaves Basic Auth unset`
   - `fallback: preview-basic-auth-command output without ':' leaves Basic Auth unset`
   - `masking: resolved username/password values never appear in output`

   最後のテストは、モックコマンドが `echo "secretuser:secretpass123"` を返すようにした上で `[[ "$output" != *"secretuser"* ]]` および `[[ "$output" != *"secretpass123"* ]]` を assert し、マスキング方針 (Pre-merge AC5) を機械的に検証する。既存スイートが PASS することだけでなく、上記の新規テストケースを追加したうえでスイート全体が PASS すること。

4. (after 2) ドキュメントを更新する (→ Pre-merge AC6)

   **`docs/guide/customization.md`** — config-reference table (134行目付近、`preview-url-command` 行の直後) に追加:
   ```
   | `preview-basic-auth-command` | string | `""` | Shell command that resolves `PREVIEW_BASIC_USER`/`PREVIEW_BASIC_PASS` for a project-side script, the same way `preview-url-command` resolves `PREVIEW_URL`. Requires `capabilities.pr-preview: true`; without it this key is ignored (same gate as `preview-url-command`). Supports a `{pr}` placeholder substituted with the PR number. Only consulted by `scripts/run-review.sh`'s preview-wait gate. The command's stdout first line must be in `username:password` format (split at the first `:`); any other outcome (non-zero exit, empty output, output over 2048 characters, or no `:` in the first line) leaves both variables unset and preserves the existing unauthenticated fallback. The value is executed verbatim via `bash -c`, so `.wholework.yml` must be treated as trusted on the checked-out branch, the same trust level as `preview-url-command`/`permission-mode`. |
   ```

   同ファイルの「`## .wholework/domains/`」見出し (228行目) の直前、"Automating `PREVIEW_URL` resolution with `preview-url-command`" 節の直後に新設:
   ```markdown
   **Automating Basic Auth credential resolution with `preview-basic-auth-command`:**

   Preview environments protected by Basic authentication (a common hosting-provider option for auto-created branch previews) require `PREVIEW_BASIC_USER`/`PREVIEW_BASIC_PASS` to be exported before invoking `/review`, the same way `PREVIEW_URL` does — see `modules/verify-executor.md` / `modules/browser-adapter.md` / `modules/lighthouse-adapter.md` for how these are consumed once set. Declare `preview-basic-auth-command` in `.wholework.yml` to let `scripts/run-review.sh` resolve and export both automatically, mirroring `preview-url-command`:

   \`\`\`yaml
   preview-basic-auth-command: ".wholework/adapters/resolve-preview-basic-auth.sh {pr}"
   \`\`\`

   The command's stdout first line must be in `username:password` format (split at the first `:`, so a password containing `:` is preserved intact). The `{pr}` placeholder is substituted with the PR number before the command runs, the same as `preview-url-command`. Resolution only runs when neither `PREVIEW_BASIC_USER` nor `PREVIEW_BASIC_PASS` is already exported — an existing manual export always takes precedence. Requires `capabilities.pr-preview: true` — without it this key is ignored, the same gate as `preview-url-command`. If the command exits non-zero, produces empty output, produces output longer than 2048 characters, or its first line contains no `:`, both variables are left unset and the existing unauthenticated fallback is preserved unchanged (no new fail-open or fail-closed behavior is introduced). The resolved command's raw output, and the split username/password values, are never written to logs or verification output (masked as `****`), following the same masking policy as `modules/browser-adapter.md` § Step 3.

   Coverage: this key is only consulted by `scripts/run-review.sh`'s preview-wait gate — i.e. `/auto`, scheduled runs, and direct `run-review.sh` invocation. It is not consulted when `/review` is invoked directly as a skill; that path still requires manually exporting `PREVIEW_BASIC_USER`/`PREVIEW_BASIC_PASS` as described in `modules/browser-adapter.md`.
   ```

   **`docs/guide/adapter-guide.md`** — 既存の `preview-url-command` 段落 (54-64行目) の直後に追加:
   ```markdown
   **`preview-basic-auth-command`** — the same mechanism as `preview-url-command` above, for
   resolving `PREVIEW_BASIC_USER`/`PREVIEW_BASIC_PASS` instead of `PREVIEW_URL`. Place the script
   under `.wholework/adapters/` alongside your other adapters and declare it with
   `preview-basic-auth-command: ".wholework/adapters/resolve-preview-basic-auth.sh {pr}"` in
   `.wholework.yml`. Like `preview-url-command`, this does **not** go through the 3-layer Adapter
   Resolution below — it is a plain script path declared directly in the config key, invoked by
   `scripts/run-review.sh` via `bash -c`. See [`docs/guide/customization.md`](customization.md) §
   "Automating Basic Auth credential resolution with `preview-basic-auth-command`" for the full
   contract.
   ```

   **`docs/tech.md`** — `HAS_PR_PREVIEW_CAPABILITY` 行 (276行目) の説明文末尾に 1 文追加:
   ```
    The same gated block additionally resolves `PREVIEW_BASIC_USER`/`PREVIEW_BASIC_PASS` from a declared `preview-basic-auth-command` when neither is already exported, mirroring `preview-url-command`'s resolution contract (30s bounded, `{pr}` substituted, `username:password`-format output split at the first `:`, any other outcome leaves both unset) — see `docs/guide/customization.md` § "Automating Basic Auth credential resolution with `preview-basic-auth-command`" (#1417).
   ```

5. (after 4) `docs/translation-workflow.md` の Sync Procedure に従い、Step 4 で変更した 3 ファイルの ja ミラーを同期する: `docs/ja/guide/customization.md` / `docs/ja/guide/adapter-guide.md` / `docs/ja/tech.md`。コードブロック数 (` ``` ` の出現数) が英語版と一致することを確認する。

## Verification

### Pre-merge

- <!-- verify: rubric "modules/detect-config-markers.md のマーカー定義表に preview-basic-auth-command キーと対応変数が追加されている" --> `.wholework.yml` で `preview-basic-auth-command` を宣言できるよう `detect-config-markers.md` が拡張されている
- <!-- verify: grep "preview-basic-auth-command" "scripts/run-review.sh" --> `scripts/run-review.sh` が `preview-basic-auth-command` を参照する fast path を持つ
- <!-- verify: rubric "scripts/run-review.sh の fast path が、PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS 未設定かつ preview-basic-auth-command が宣言されている場合に該当コマンドを実行し両変数を解決する" --> fast path は両変数未設定時に `preview-basic-auth-command` を実行して解決する
- <!-- verify: rubric "scripts/run-review.sh の fast path は preview-basic-auth-command の実行が失敗・空出力・不正形式の場合、両変数を未設定のまま維持し既存の非認証フォールバック挙動を変えない" --> コマンド失敗・空出力・不正形式時は既存の非認証フォールバックを維持する (後方互換)
- <!-- verify: rubric "scripts/run-review.sh の fast path は解決した認証情報の生出力・username・password をログに出力しない (マスキング方針を遵守する)" --> 解決した認証情報がログに出力されない (マスキング方針を遵守)
- <!-- verify: file_contains "docs/guide/customization.md" "preview-basic-auth-command" --> `docs/guide/customization.md` に `preview-basic-auth-command` の説明とサンプル設定が追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 関連する bats テストが全て pass する (PR route)

**Note**: Pre-merge 検証項目数は 7 件で、SPEC_DEPTH=light の名目上限 (5件) を超えている。これは Issue 本文の `## Acceptance Criteria > Pre-merge` が既に 7 件で確定しており、Verify command sync rule (Issue 本文から verbatim コピーし独立改変しない) と Count Alignment Check を優先したため。Implementation Steps 側は 5 ステップに収めている。

### Post-merge

- preview-basic-auth-command を宣言した実プロジェクトで `/auto` を実行し、`PREVIEW_BASIC_USER`/`PREVIEW_BASIC_PASS` が自動解決され Basic 認証保護下の preview 層 AC が 401 で false FAIL せず実行されることを観察 <!-- verify-type: manual -->

## Notes

### 設計判断 (Issue Background の「設計上の open question」3件への回答)

Issue 本文 Background 末尾の 3 件の open question は、Issue Retrospective (`/issue` フェーズ) で「AC 文言に影響しないため Auto-resolution 条件を満たす」と判定され、「Spec フェーズで確定」のまま残されていた。SPEC_DEPTH=light のため Step 7 (Ambiguity Resolution) は形式的には skip されるが、Implementation Steps を具体化する上で以下の通り確定させた:

1. **出力形式**: `username:password` 単一行、最初の `:` で分割 (password 内の `:` を保持)。curl `--config` の `user = "user:pass"` 形式や `preview-url-command` の「1行目のみ使用」規約と親和的なため。
2. **`preview-url-command` との複合レスポンス可否**: 常に別コマンド・別キーとして分離する (複合レスポンスは採用しない)。理由: (a) 既存の `preview-url-command` の単一行 URL 契約を変更せずに済む、(b) 各コマンドが単一責務を持つ方が解析ロジックがシンプルになる、(c) Issue の Out of Scope が「誰が export するかという解決・配線の欠落のみ」に限定しており複合化は範囲外。
3. **`{pr}` プレースホルダの要否**: `preview-url-command` と同様にサポートする。Basic 認証情報は通常 PR 非依存の静的値だが、プレースホルダ対応はコストがほぼゼロで、provider によっては PR ごとに一時的な Basic 認証情報を発行するケースもあり得るため、先例踏襲を優先した。

### Fail-safe critical script 該当性 (`_resolve_preview_basic_auth_command`)

本関数は `2>/dev/null` と早期 `return 0` によりあらゆる失敗経路で「両変数を未設定のまま維持し処理を継続する」設計であり、`modules/costly-step-protocol.md` 文脈とは別に、Spec Step 6 の「Fail-safe critical script identification」チェック (c) 「failure 時に safe-side default を返す」に該当すると判定した。エッジケースの扱いを明示する:
- **空/過大入力**: 空出力・2048文字超過はいずれも既存 `preview-url-command` と同じガードで警告付きスキップ
- **特殊文字 (CRLF・複数行)**: `head -n 1 | tr -d '\r'` により 1 行目のみ採用し CR を除去 — `preview-url-command` と同じ規約
- **`"` を含む認証情報**: 本 Issue のスコープ外 (`#1074` で実装済みの curl `--config` 生成側の既存挙動であり、手動 export でも同じ制約が既に存在するため新規リスクではない)
- **依存コマンド失敗時の fail-open/fail-closed**: 意図的な fail-open — Issue 本文で明示的に指定された設計 (「既存の非認証フォールバック挙動を変えない」) であり、本 Issue が新規導入するものではない。認証情報が解決されない場合でも、実際の verify command 実行時に 401/403 として可視化されるため、サイレントに失敗が握り潰されるわけではない。

### allowed-tools impact chain check (`modules/detect-config-markers.md` 変更)

`modules/detect-config-markers.md` を Read する SKILL.md は 10 件 (`skills/{audit,doc,code,auto,issue,spec,merge,review,triage,verify}/SKILL.md`)。追加する行・箇条書きに `scripts/run-review.sh` / `scripts/get-config-value.sh` への言及が含まれる (lightweight gate 該当) が、これは「どのスクリプトがこの config 値を消費するか」を示す説明文であり、`detect-config-markers.md` を読む Skill 自身に `scripts/run-review.sh` の呼び出しを指示するものではない (`run-review.sh` は Skill を起動する側のラッパースクリプトであり、Skill から呼ばれる側ではない)。既存の `preview-url-command` 行も同型の言及を含み allowed-tools 追加は発生していない。10 readers を個別確認した結果、いずれも新規 `allowed-tools` 追加は不要と判定した。

## Consumed Comments

| Author | Association | Trust tier | Summary | URL |
|--------|-------------|------------|---------|-----|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective。Background 事実確認 (grep 裏付け済み)、Post-merge AC の `verify-type` タグ修正 (`opportunistic event=review-run` → `manual`、`event=` は `observation` 専用のため)、Background 末尾の曖昧点 3 件は AC 文言に非影響のため Auto-resolution 条件を満たすと判定・現状維持、blocked-by オープンなし、Size M (sub-issue 分割対象外) を記録。 | https://github.com/saitoco/wholework/issues/1417#issuecomment-5353381634 |

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜5 を記載順どおりに実装した。`_resolve_preview_basic_auth_command()` の実装・呼び出し箇所・一時ファイル規約 (`mktemp .tmp/preview-basic-auth-command-output-XXXXXX`) はいずれも Spec の擬似コードと一致する。

### Design Gaps/Ambiguities

N/A — Spec の Notes 節(設計判断・Fail-safe critical script 該当性・allowed-tools impact chain check)が実装時の疑問をあらかじめ解消済みだった。

### Rework

N/A — 手戻りなし。

### Test Verification Note

新規追加した 7 bats テストのうち 6 件について、実装前コミット (`ff96a0c0~1`) の `scripts/run-review.sh` に対して FAIL することを確認した (`git checkout ff96a0c0~1 -- scripts/run-review.sh` で一時的に実装前状態へ戻し再実行 → 復元)。残り 1 件 (「exported PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS take precedence over preview-basic-auth-command」) は「新機能が呼ばれないこと」を検証するテストのため、実装前状態でも意味的に PASS するのが正しい挙動であり、FAIL しないことを確認した。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — `review-light` エージェントによる Perspective 1 (Spec Deviation) 確認の結果、Implementation Steps 1〜5 は記載順どおりに実装されており、構造的な乖離は検出されなかった。

### Recurring issues

Nothing to note — 同種の指摘が複数発生した形跡はない。今回の唯一の指摘 (Edge Case Execution によるバリデーション漏れ) は `_resolve_preview_url_command()` を模倣する形で実装された新規関数固有のものであり、他ファイルへの波及はなかった。

### Acceptance criteria verification difficulty

Nothing to note — Pre-merge AC 7件はすべて grep / file_contains / rubric / github_check のいずれかで機械的に PASS 判定でき、UNCERTAIN は発生しなかった。`preview-url-command` (#1410) と同型の設計だったため、verify command も流用しやすく検証コストは低かった。

### Additional observation (Parser/Validator Edge Case Pre-check)

`_resolve_preview_basic_auth_command()` に対する Edge Case Execution (実行ベースの検証、19 フィクスチャ) で、`:` は含むが username/password の一方または両方が空文字列というケース (`:password` 等) がバリデーションを素通りし、空文字列の資格情報を「解決済み」としてログ・export してしまう CONSIDER 相当の指摘が見つかった。`_resolve_preview_url_command()` 側は正規表現 (`^https?://[^[:space:]/]+`) で非空値を暗黙に要求する形になっていたのに対し、今回の新規関数は「`:` の有無」のみをチェックしており非空性を見落としていた — 同型実装を模倣する際に、模倣元が持つ暗黙の制約 (今回は正規表現による非空性保証) まで含めて引き継げていない典型例。Step 12 でその場で修正 (空オペランドチェック追加 + bats フィクスチャ追加) し、全 58 bats テスト PASS を確認済み。Spec の Implementation Steps に「模倣元の暗黙の入力制約も列挙する」チェック項目があれば、実装フェーズで拾えていた可能性がある。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Step 10 は `.wholework.yml` の `always-pr`/Size (M) に基づき `REVIEW_DEPTH=light` (1エージェント統合レビュー) で実行した
- Parser/Validator Edge Case Pre-check の発火条件 (新規関数が外部コマンド出力を解釈・検証する) に該当したため、`_resolve_preview_basic_auth_command()` を対象に実行ベースの Edge Case 検証 (19 フィクスチャ) を実施した
- 検出した CONSIDER 指摘 (空 username/password が `:` チェックを素通りする) はその場で修正し、bats フィクスチャを追加した (MUST/SHOULD ではなく CONSIDER だが、1行の安全な修正かつ実行ベースで裏付けが取れていたため即時対応を選択)

### Deferred Items
- Post-merge AC (`preview-basic-auth-command` を宣言した実プロジェクトでの `/auto` 実行観察) は `verify-type: manual` のため引き続き未チェック — `/verify` フェーズで human follow-up として扱われる

### Notes for Next Phase
- Pre-merge AC 7件は全て PASS (grep/file_contains/rubric/github_check)。AC7 (bats テスト CI) は `/review` 実行時点で CI 全11ジョブ SUCCESS を確認済み
- `/review` の Step 12 で 1 件の CONSIDER 修正コミット (`6e4f6a75`) を追加済み — `/merge` 時点で PR の最新コミットに含まれていることを前提としてよい
