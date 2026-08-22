# Issue #1429: review: preview-basic-auth-command を /review 直接実行で解決 (Basic Auth)

## Overview

`#1423` の子 Issue、`#1428` (共有スクリプト基盤 `scripts/resolve-preview-env.sh` + `url` モード) の後続。`preview-basic-auth-command` は現在 `scripts/run-review.sh` の `pr-preview` ゲート内 (`_resolve_preview_basic_auth_command()`) でのみ解決され、`/review` を `--auto` なしで直接実行する経路では一切参照されない。本 Issue は解決ロジックを `scripts/resolve-preview-env.sh` の `basic-auth` モードへ切り出し、`modules/verify-executor.md` (curl 実行直前) と `modules/browser-adapter.md` (Step 3) の双方から呼べるようにする。

資格情報は URL より機微度が高いため、**値ではなく一時ファイルパス**で伝搬する (`#1074`/`#1051`/`#1417` の先例と整合)。Bash tool call 間で export した環境変数は保持されない (`skills/review/SKILL.md` Step 8.0 が `preview-url-command` で明記している制約) ため、「解決した値をテンプレート値として後続 Bash tool call に渡す」設計は資格情報が会話 transcript・`docs/sessions/*/events.jsonl` (public repo) に残る。ファイルパスのみを渡せばこの露出を回避できる。

## Changed Files

- `scripts/resolve-preview-env.sh`: 変更 — `basic-auth` サブコマンド追加 (`basic-auth <pr-number> [--format curl-config|user-pass]`)。`url` サブコマンドは 2 引数固定のまま維持。bash 3.2+ 互換 (mapfile/連想配列/`${var^^}` を使わない)
- `scripts/run-review.sh`: 変更 — `_resolve_preview_basic_auth_command()` (L150-209) の本体を共有スクリプト呼び出し (`--format user-pass`) の薄いラッパーへ置換。bash 3.2+ 互換
- `modules/verify-executor.md`: 変更 — `### Basic Authentication Support` 節の curl config 構築ブロック直前に解決ステップを追加。あわせて同節の `mktemp .tmp/curl-auth-XXXXXX.cfg` を末尾 X 形式へ修正 (下記 Notes「実装との矛盾 (2)」)
- `modules/browser-adapter.md`: 変更 — `### Step 3: Basic Authentication Setup` の CDP attach フォールバック説明の直前に解決ステップを追加。優先順位「明示 env > command 解決 > CDP attach (`#1025`) > 非認証」を exhaustive 明示
- `modules/detect-config-markers.md`: 変更 — L92 の `preview-basic-auth-command` 解説から "Currently consumed only by `scripts/run-review.sh` (bash wrapper) via `get-config-value.sh`; no skill reads `PREVIEW_BASIC_AUTH_COMMAND` directly" を、`preview-url-command` (L91) と同型の「両経路が共有 `scripts/resolve-preview-env.sh` 経由で参照する」表現へ更新
- `docs/guide/customization.md`: 変更 — (a) L130 の `preview-basic-auth-command` 表行「Only consulted by `scripts/run-review.sh`'s preview-wait gate.」を両経路参照へ更新、(b) L233 の Coverage 段落から "It is not consulted when `/review` is invoked directly as a skill; that path still requires manually exporting ..." を撤去し `preview-url-command` の Coverage 段落 (L221) と同型に書き換え、(c) L231 の解決失敗時の説明に「ファイルパスで伝搬する」旨を追記 (→ 受入条件 AC6)
- `docs/ja/guide/customization.md`: 変更 — 上記 (a)(b)(c) の日本語ミラー (L118 表行 / L230 Coverage 段落 / L228 解決契約段落)
- `docs/tech.md`: [Steering Docs sync candidate] 変更 — L286 `HAS_PR_PREVIEW_CAPABILITY` 行末尾の `preview-basic-auth-command` 記述 ("The same gated block additionally resolves ... (#1417)") に、`/review` 直接実行経路のカバーと共有リゾルバ委譲を追記
- `docs/ja/tech.md`: [Steering Docs sync candidate] 変更 — L277 の日本語ミラー
- `docs/structure.md`: [Steering Docs sync candidate] 変更 — L208 の `scripts/resolve-preview-env.sh` 説明を `url` / `basic-auth` の 2 サブコマンド構成へ更新
- `docs/ja/structure.md`: [Steering Docs sync candidate] 変更 — L201 の日本語ミラー
- `docs/guide/adapter-guide.md`: [Outbound pointer sync candidate] 変更 — L71 付近 `preview-basic-auth-command` 段落の "invoked by `scripts/run-review.sh` via `bash -c`" を、共有リゾルバ `scripts/resolve-preview-env.sh` 経由で両呼び出し箇所が参照する旨へ更新 (`preview-url-command` 段落 L57 と同型)
- `docs/ja/guide/adapter-guide.md`: [Outbound pointer sync candidate] 変更 — L50 付近の日本語ミラー
- `tests/resolve-preview-env.bats`: 変更 — `basic-auth` モードの新規テストケースを追加 (guard 移送 8 件 + `--format` 2 種 + マスキング + 特殊文字エスケープ)
- `tests/run-review.bats`: 変更 — 既存 8 テスト (L756-1055 の `preview-basic-auth-command` 系 7 件 + `masking:` 1 件) が薄いラッパー化後も同じ文言・exit code で PASS することを維持 (`setup()` の `resolve-preview-env.sh` 実体コピーは `#1428` で追加済みのため追加変更不要)
- `skills/review/SKILL.md`: 変更不要 — frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-env.sh:*` が `#1428` で追加済みであることを grep で確認済み (L5)。下記 Notes「allowed-tools impact chain」参照
- `modules/lighthouse-adapter.md` / `modules/visual-diff-adapter.md`: 変更なし — Issue 本文 `## Known Gap` によりスコープ外 (grep で `PREVIEW_BASIC_USER` 参照を確認済み。両モジュールは env 変数が設定済みである前提のまま残置)

## Implementation Steps

1. `scripts/resolve-preview-env.sh` の引数パースを拡張する (→ 受入条件 AC3, AC4)
   - `url` モード: 現行どおり引数 2 個固定 (`url <pr-number>`)。`if [ $# -ne 2 ]` の一律チェックを、モード判定後のモード別チェックへ分解する
   - `basic-auth` モード: `basic-auth <pr-number> [--format curl-config|user-pass]` (引数 2 個または 4 個)。`--format` 省略時の既定は `curl-config` (LLM から呼ばれる既定経路が資格情報を stdout に出さない側になるよう、安全側を既定にする)
   - `--format` の値が `curl-config` / `user-pass` のいずれでもない場合は exit 1 (引数エラー。fail-open ではなく fail-closed — 呼び出し側のタイポを黙って非認証へ落とさない)
   - ヘッダコメントの Usage / Output 節を 2 モード分に更新する。bash 3.2+ 互換 (`mapfile` / 連想配列 / `${var^^}` を使わない)
2. `basic-auth` モードのガードを `_resolve_preview_basic_auth_command()` から漏れなく移送する (after 1) (→ 受入条件 AC4)
   - 移送対象 (exhaustive、8 件): (a) `preview-basic-auth-command` 未宣言なら no-op、(b) `{pr}` プレースホルダ置換、(c) 30 秒上限実行 (`timeout` → `gtimeout` → 手動 watchdog の 3 段フォールバック)、(d) 非 0 終了、(e) 1 行目抽出 + CR 除去 + 前後空白トリム、(f) 空出力、(g) 2048 文字超、(h) `username:password` 形式 — 「`:` を含む」「`:` 前が非空」「`:` 後が非空」の 3 条件すべて
   - (h) は `#1417` 実装時に「模倣元の非空性ガードを引き継がず `:password` が素通りした」不具合が発生した箇所。現行 `run-review.sh` L198-200 の 3 条件 (`!= *:*` / `-z "${_resolved_trimmed%%:*}"` / `-z "${_resolved_trimmed#*:}"`) を 1 つも落とさずに移送したことを、実装ステップ完了時に当該 3 行を並べて突合確認する
   - (e) は `run-review.sh` L184 で `printf '%s' "$_resolved" | head -n 1 | tr -d '\r'` (パイプ) だが、独立スクリプトは `set -euo pipefail` 配下のため SIGPIPE 経由で異常終了しうる。`url` モード L97-98 と同じ純 bash パラメータ展開 (`${_resolved%%$'\n'*}` / `${_resolved//$'\r'/}`) へ置き換える (`#1428` retrospective で実測された既知の落とし穴)
   - stderr の警告文言は現行と逐語一致させる (`tests/run-review.bats` の 8 テストが文字列一致で検証している): `Warning: preview-basic-auth-command exited non-zero (status=N); leaving Basic Auth unset` / `... produced empty output; ...` / `... output exceeds 2048 chars; ...` / `... output is not in username:password format; ...`。成功時は `url` モードと同型に `Resolved PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS via preview-basic-auth-command for PR #<N>` を stderr へ出す
   - 手動 watchdog 分岐の一時出力ファイルは、資格情報を保持するため `mktemp .tmp/preview-basic-auth-command-output-XXXXXX` (末尾 X、600 権限) を使い、読み出し後は成功・失敗を問わず `rm -f` する (`url` モードの固定名 `.tmp/preview-url-command-output.$$` を流用しない)
3. `basic-auth` モードの資格情報ファイル書き出しを実装する (after 2) (→ 受入条件 AC3, AC5)
   - 出力ファイルは `mktemp` で作成する。**テンプレートの `X` は必ず末尾に置く** — macOS の BSD `mktemp` は末尾以外の `XXXXXX` を置換せず、`mktemp .tmp/curl-auth-XXXXXX.cfg` は literal 名 `curl-auth-XXXXXX.cfg` を作る (本 repo 上で実測確認済み)。`mktemp .tmp/curl-auth-XXXXXX` / `mktemp .tmp/preview-basic-auth-XXXXXX` を使う
   - `--format curl-config`: `user = "<escaped>"` の 1 行を書く。`<escaped>` は `username:password` 全体に対し `\` → `\\`、`"` → `\"` の順で置換した文字列 (curl 公式 man page: 二重引用符内で使えるエスケープは `\\ \" \t \n \r \v`、それ以外の文字の前の `\` は無視される)。curl の `--libcurl` 出力で往復を実測確認済み
   - `--format user-pass`: 1 行目に username、2 行目に password の 2 行を書く。**シェルエスケープを一切行わない**形式にすることで、消費側は `{ IFS= read -r U; IFS= read -r P; } < "$file"` だけで復元でき、クオート起因の破損経路を作らない (sourceable な `KEY='value'` 形式は `'` を含む password でエスケープが破綻しうるため不採用)
   - stdout に出すのは**ファイルパス 1 行のみ**。資格情報そのもの・コマンド生出力は stdout にも stderr にも決して出さない
   - fail-open: いずれかのガードに引っかかった場合は stdout 空 + exit 0 (ファイルも作らない)。呼び出し側は「非認証で続行」へ落ちる
4. **Fail-safe critical エッジケースの明示** (after 3) (→ 受入条件 AC3, AC4)
   - 本スクリプトは「失敗時に安全側の既定へ倒す」設計 (fail-open) に該当するため、以下の期待挙動を実装とテストの双方で確定させる
   - 空入力 / 2048 文字超: fail-open (stdout 空 + exit 0)。ファイルは作らない
   - 特殊文字を含む入力: `"` / `\` を含む password → `curl-config` で正しくエスケープされ curl が原値を復元できること。`:` を複数含む password → 最初の `:` のみで分割され残りは password 側に保持されること。CRLF → CR 除去後に評価されること。改行を含む複数行出力 → 1 行目のみ評価されること。多バイト文字 → 文字数ではなくバイト長で 2048 を判定する現行挙動 (`${#var}` の bash 挙動) を維持し、テストで固定すること
   - 依存コマンド失敗 (`preview-basic-auth-command` が非 0 終了 / timeout): **fail-open**。理由 — 資格情報が取れないことは「認証なしでアクセスして 401 を観測する」という既存フォールバックへ戻るだけであり、`/review` 全体を止める価値がない。`#1417` が明示的に採用した設計をそのまま維持する (新規の fail-open 導入ではない)
   - 引数エラー (未知のモード / 未知の `--format` / 非数値 PR 番号): **fail-closed** (exit 1)。呼び出し側のバグを黙って握り潰さない
5. `scripts/run-review.sh` の `_resolve_preview_basic_auth_command()` を薄いラッパーへ置換する (after 3) (→ 受入条件 AC4)
   - 本体を `_f=$("$SCRIPT_DIR/resolve-preview-env.sh" basic-auth "$PR_NUMBER" --format user-pass) || return 0` → 空なら `return 0` → `{ IFS= read -r PREVIEW_BASIC_USER; IFS= read -r PREVIEW_BASIC_PASS; } < "$_f"` → `export` → `rm -f "$_f"` に置換する
   - `rm -f` は成功・失敗を問わず実行する (読み出し失敗時も残さない)
   - 呼び出し元 L215 の外側ゲート (`[[ -z "${PREVIEW_BASIC_USER:-}" && -z "${PREVIEW_BASIC_PASS:-}" ]]` と `capabilities.pr-preview` grep) は変更しない — 既存 export 優先と capability ゲートの挙動を維持する
   - 関数コメント (L141-149) を「ガードは共有リゾルバへ委譲」へ書き換える (`_resolve_preview_url_command` の L132-133 と同型)
6. `modules/verify-executor.md` の `### Basic Authentication Support` 節に解決ステップを追加する (after 3) (→ 受入条件 AC1, AC3, AC5)
   - 挿入位置: 「For the curl-based URL commands (`http_status` / ...) ... build a temporary `--config` file ...」の段落の直前 (curl config 構築コードフェンスより前)
   - 内容: `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` の双方が未 export かつ、呼び出し skill が `HAS_PR_PREVIEW_CAPABILITY` をロード済みでその値が `true` かつ `.wholework.yml` が `preview-basic-auth-command` を宣言している場合に、`${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-env.sh basic-auth "<caller-supplied PR number>" 2>/dev/null` を 1 回の Bash tool call で実行する。`2>/dev/null` は必須 (Step 8.0 の `preview-url-command` と同じ理由 — stderr の情報/警告メッセージが stdout と混ざると解決値と区別できなくなる)
   - stdout 非空ならそれは curl config ファイルのパス。**内容を読まず・表示せず**そのまま `curl --config "<path>"` に渡し、コマンド完了後 (成功・失敗を問わず) `rm -f "<path>"` する。stdout 空なら `--config` 注入をスキップして非認証で実行する (既存挙動、fail-open)
   - **Caller scope (exhaustive)** として、`HAS_PR_PREVIEW_CAPABILITY` をロードするのは現状 `skills/review/SKILL.md` Step 8 のみであり、`/code` / `/verify` / `/auto` は同変数をロードしないため `false` 扱いで本解決をスキップする旨を明記する (下記 Notes「allowed-tools impact chain」の根拠となる記述)
   - あわせて既存の `mktemp .tmp/curl-auth-XXXXXX.cfg` を `mktemp .tmp/curl-auth-XXXXXX` へ修正する (Step 3 と同じ BSD `mktemp` 制約。同一段落内に誤った例と正しい例が並ぶ状態を作らない)
7. `modules/browser-adapter.md` の `### Step 3: Basic Authentication Setup` に解決ステップを追加する (after 3) (parallel with 6) (→ 受入条件 AC2, AC5)
   - 挿入位置: 「**When environment variables are not set — authenticated local browser (CDP attach) fallback:**」見出しの直前
   - 内容: Step 6 と同じ前提条件で `... resolve-preview-env.sh basic-auth "<PR number>" --format user-pass 2>/dev/null` を実行する。stdout 非空なら 2 行ファイル (1 行目 username / 2 行目 password) のパスであり、**ブラウザツールを起動するのと同じ Bash 呼び出しの中で** `{ IFS= read -r PREVIEW_BASIC_USER; IFS= read -r PREVIEW_BASIC_PASS; } < "<path>"` により環境変数へ読み込み、直後に `rm -f "<path>"` する。ファイル内容・username・password をログや検証結果に出力しない (Step 3 冒頭のマスキング方針をそのまま適用)
   - 解決に失敗した場合 (stdout 空) は必ず既存の CDP attach フォールバックへ落ちる。FAIL にはしない
   - 優先順位を **(exhaustive)** マーカー付きで明記する: 明示 export された env 変数 > `preview-basic-auth-command` 解決 > CDP attach フォールバック (browser-use CLI 限定、`#1025`) > 非認証
   - Playwright MCP 経路の既知の制約を注記する: `extraHTTPHeaders` は MCP tool 引数として `Authorization: Basic <base64>` のリテラル値を要求するため、この経路では値が会話に現れることを避けられない。Step 2 の検出優先順位で browser-use CLI が優先 (priority 1) であり同 CLI は環境変数参照で完結するため、既定経路ではこの露出は発生しない。既存挙動 (env 変数が export 済みの場合) と同一であり、本 Issue が新たに導入する露出ではない
8. `modules/detect-config-markers.md` の consumption note を更新する (after 6, 7) (→ 受入条件 AC1, AC2)
   - L92 の "Currently consumed only by `scripts/run-review.sh` (bash wrapper) via `get-config-value.sh`; no skill reads `PREVIEW_BASIC_AUTH_COMMAND` directly" を、L91 (`preview-url-command`) と同型の「`scripts/run-review.sh` と、`modules/verify-executor.md` / `modules/browser-adapter.md` (いずれも共有 `scripts/resolve-preview-env.sh` 経由、Issue #1429) が参照する」表現へ置き換える
9. ドキュメント同期 (after 6, 7) (parallel with 8) (→ 受入条件 AC6)
   - `docs/guide/customization.md`: 表行 (L130) / Coverage 段落 (L233) / 解決契約段落 (L231) を更新。Coverage 段落は `preview-url-command` 側 (L221) と同型の「両経路が参照する」文へ書き換え、`It is not consulted when \`/review\` is invoked directly as a skill` の文字列を残さない
   - `docs/ja/guide/customization.md`: 上記の日本語ミラー。`docs/translation-workflow.md` の Sync Procedure に従い、コードフェンス数の一致も確認する。日本語ミラー側は日本語表現でパターンを扱う (英語パターンをそのまま持ち込まない)
   - `docs/tech.md` L286 / `docs/ja/tech.md` L277 (`HAS_PR_PREVIEW_CAPABILITY` 行)、`docs/structure.md` L208 / `docs/ja/structure.md` L201 (`resolve-preview-env.sh` 説明)、`docs/guide/adapter-guide.md` L71 付近 / `docs/ja/guide/adapter-guide.md` L50 付近 (`preview-basic-auth-command` 段落) を、`/review` 直接実行経路のカバーと共有リゾルバ委譲を反映して更新する
10. テストを追加・確認する (after 5) (→ 受入条件 AC4, AC5, AC7)
   - `tests/resolve-preview-env.bats` に `basic-auth` モードの**新規テストケース**を追加する (既存スイートの PASS だけでは不十分 — 本 Issue は既存スクリプトへ新規分岐ロジックを追加するため、新規分岐を検証する新規ケースの追加が必須): (a) `--format curl-config` 既定で 600 権限ファイルパスを stdout へ出す、(b) `--format user-pass` で 2 行ファイルを出す、(c) 未知の `--format` は exit 1、(d) ガード 8 件それぞれの fail-open (stdout 空 + exit 0 + 期待する stderr 文言)、(e) `:password` / `username:` の非空性ガード (`#1417` 再発防止の回帰テスト)、(f) `"` / `\` / 複数 `:` / CRLF / 多バイトを含む password のエスケープ・分割、(g) マスキング — `run` の `$output` に username / password / コマンド生出力が一切現れない (`tests/run-review.bats` L1030 の `masking: resolved username/password values never appear in output` と同型)
   - `tests/run-review.bats` の既存 8 テスト (L756-1055) を無改修で実行し、薄いラッパー化後も同じ stderr 文言・同じ exit code で PASS することを確認する。`setup()` の `resolve-preview-env.sh` 実体コピー (L118) は `#1428` で追加済みのため追加変更は不要
   - bats のモック生成で「呼び出し元の任意文字列をそのまま非クオート heredoc へ埋め込む」パターンは、値に `"` を含むケースで壊れる (`#1428` retrospective の実測)。`"` を含む password のテストでは値を別ファイルへ `printf '%s' "$1" > file` で書き出し、heredoc 側はクオート済み (`<<'MOCK'`) にして `cat` で読み込む方式を使う

## Alternatives Considered

| 案 | 内容 | 判断 |
|----|------|------|
| **採用: ファイルパス伝搬 (2 フォーマット)** | `curl-config` / `user-pass` の 2 形式を用意し、消費側はパースなしで使う | **採用**。`#1074`/`#1051`/`#1417` の 3 先例すべてと整合し、消費側 (prose モジュール) に文字列処理を持ち込まない |
| 単一フォーマット (`curl-config` のみ) | すべての消費者が curl config を読み戻して分解する | 不採用。`run-review.sh` と browser-adapter は生の username/password が必要で、curl のエスケープ規則を逆変換する処理が 2 箇所に増える |
| 単一フォーマット (`user-pass` のみ) | verify-executor 側で curl config を組み立てる | 不採用。curl のエスケープ規則を prose モジュール内に書くことになり、`"` / `\` を含む password で壊れやすい (エスケープはスクリプト 1 箇所に閉じるべき) |
| 値を stdout へ出す (テキスト伝搬) | `basic-auth` が `username:password` を stdout に出す | 不採用。Issue 本文が明示的に否定。会話 transcript / `docs/sessions/*/events.jsonl` (public repo) への残存リスク |
| `capabilities.pr-preview` ゲートをスクリプト内に置く | `basic-auth` モード自身が capability を確認 | 不採用。`tests/run-review.bats` の `get-config-value.sh` モックは未知キーに既定値を返すため、既存 8 テストが一斉に落ちる。`#1428` (`url` モード) と同じく消費側ゲートで揃える |
| `skills/code` / `/verify` / `/auto` の `allowed-tools` に `resolve-preview-env.sh` を追加 | verify-executor の全読者へ権限を付与 | 不採用。3 skill は `HAS_PR_PREVIEW_CAPABILITY` をロードせず解決ステップに到達しない。不要な権限面の拡大を避ける (下記 Notes に前提崩壊時の影響を記録) |

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-executor.md の curl 実行直前に、PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS 未 export かつ preview-basic-auth-command が宣言されている場合の解決ステップが追加されている" --> modules/verify-executor.md の curl 実行直前に PREVIEW_BASIC_USER/PREVIEW_BASIC_PASS 解決ステップが追加されている
- <!-- verify: rubric "modules/browser-adapter.md の browser 認証セットアップ直前に、同様の解決ステップが追加されている" --> modules/browser-adapter.md の browser 認証セットアップ直前に同様の解決ステップが追加されている
- <!-- verify: rubric "資格情報の伝搬はテキスト値ではなく一時ファイルパス (600権限、mktemp) で行われている" --> 資格情報の伝搬がテキスト値ではなく一時ファイルパス (600権限) で行われている
- <!-- verify: rubric "scripts/resolve-preview-env.sh の Basic Auth 解決モードは、run-review.sh の既存正規表現・長さ・非空性ガードを漏れなく移送している (#1417 の暗黙制約引き継ぎ漏れを再発させない)" --> scripts/resolve-preview-env.sh の Basic Auth 解決モードが既存ガードを漏れなく移送している (#1417 の暗黙制約引き継ぎ漏れの再発防止)
- <!-- verify: rubric "解決した認証情報の生出力・username・password が対話実行時もログ・verification result に出力されない (マスキング方針を遵守する)" --> 解決した認証情報がログ・verification result に出力されない (マスキング方針の遵守)
- <!-- verify: file_not_contains "docs/guide/customization.md" "It is not consulted when \`/review\` is invoked directly as a skill" --> preview-basic-auth-command セクションの Coverage 記述が更新されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが全PASSしている

### Post-merge

- `preview-basic-auth-command` を宣言した実プロジェクトで `--auto` なしの `/review <PR番号>` を直接実行し、事前の手動 export なしで preview 層 AC が 401 / UNCERTAIN にならず実行されることを観察

## Tool Dependencies

### Bash Command Patterns
- `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-env.sh:*` — `modules/verify-executor.md` / `modules/browser-adapter.md` から `basic-auth` モードを呼ぶ。**追加不要** — 唯一の到達経路である `skills/review/SKILL.md` の `allowed-tools` (L5) に `#1428` で登録済み

### Built-in Tools
- なし (`Read` / `Edit` / `Bash` はすべて既存の `allowed-tools` に含まれる)

### MCP Tools
- なし

## Uncertainty

- **curl config ファイルのエスケープ規則**: 解決済み。curl 公式 man page (`https://curl.se/docs/manpage.html`) の `-K, --config` 節 — 二重引用符内で有効なエスケープは `\\` `\"` `\t` `\n` `\r` `\v` のみで、それ以外の文字の前の `\` は無視される。`\` → `\\`、`"` → `\"` の順で置換すれば往復が成立することを、`curl --config <file> --libcurl` の `CURLOPT_USERPWD` 出力で実測確認済み (Implementation Step 3 に反映)
- **BSD `mktemp` の suffix 挙動**: 解決済み。macOS (Darwin 25.6.0) 実測で `mktemp .tmp/curl-auth-XXXXXX.cfg` は `X` を置換せず literal 名のファイルを作る (権限は 600)。末尾 `X` 形式 `mktemp .tmp/preview-basic-auth-XXXXXX` は正しくランダム化される。Implementation Step 3 (新規ファイル) と Step 6 (既存記述の修正) の双方に反映済み
- **`skills/review/SKILL.md` 以外の verify-executor 読者が解決ステップに到達しないという前提**: 未検証 (prose モジュールの LLM 実行挙動に依存するため機械的に固定できない)。**影響範囲**: Implementation Step 6 の Caller scope 記述と、`allowed-tools` を 3 skill に追加しないという判断。**前提が崩れた場合の挙動**: `/code` / `/verify` / `/auto` が誤って `resolve-preview-env.sh` を呼ぶと権限がなく失敗するが、解決ステップ自体が fail-open のため非認証フォールバックへ落ちるだけで、AC が FAIL になったり実行が止まったりはしない (安全側に劣化する)。**検証方法**: マージ後の `/review` 以外のフェーズで `resolve-preview-env.sh basic-auth` の permission denied が観測されるかを監視する

## Notes

### 実装との矛盾 (Issue 本文 vs 既存実装)

1. **AC6 の `file_not_contains` パターンが実在しない (自動解決済み)** — Issue 本文 (Proposal 7 / AC6) は `docs/guide/customization.md` から `not by \`/review\` invoked directly as a skill` を撤去せよと指定していたが、この文言は `preview-url-command` セクションの旧記述であり `#1428` で既に削除済み。`preview-basic-auth-command` セクションの実際の文言は `It is not consulted when \`/review\` is invoked directly as a skill` (L233)。撤去前から常に PASS する verify command になっていたため、`/spec` 実行時に Issue 本文の Proposal 7 と AC6 を実在する文言へ修正した (`gh-issue-edit.sh` 適用済み)。本 Spec の `## Verification > Pre-merge` は修正後の Issue 本文からの逐語コピー
2. **`mktemp .tmp/curl-auth-XXXXXX.cfg` は macOS でランダム化されない** — `modules/verify-executor.md` L279 の既存スニペットは `X` が末尾にないため BSD `mktemp` (macOS 既定) が置換せず、literal 名 `.tmp/curl-auth-XXXXXX.cfg` を作る (権限 600 は満たす)。並行実行時の衝突と予測可能な名前という 2 点の問題があり、本 Issue で同じ段落へ新規スニペットを追加する以上、誤った例を隣に残さないため同時に修正する (Implementation Step 6)。Issue 本文 Proposal 2 の「`mktemp .tmp/curl-auth-XXXXXX.cfg` (600 権限)」の意図 (600 権限の一時ファイル) は満たしたうえで、テンプレートのみ末尾 X 形式へ変更する
3. **行番号のずれ** — Issue 本文は `_resolve_preview_basic_auth_command()` を `scripts/run-review.sh` L207-266、`modules/verify-executor.md` の curl 実行直前を L275-285 と記載しているが、実際は前者が L150-209、後者が L269-285 節内の L275-283。実装は行番号ではなく周辺コンテキスト (関数名 / 見出し名) で位置を特定する

### allowed-tools impact chain (Case 2: `modules/*.md` 変更)

- 変更対象 `modules/verify-executor.md` の読者 (`grep -rl "modules/verify-executor\.md" skills/*/SKILL.md`, exhaustive 7 件): `skills/audit`, `skills/code`, `skills/auto`, `skills/review`, `skills/issue`, `skills/spec`, `skills/verify`
- このうち Processing Steps の translation table を実際に**実行**するのは `review` / `code` / `verify` / `auto` の 4 件 (`audit` / `issue` / `spec` はコマンド型の一覧を参照するだけで実行しない)
- `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-env.sh:*` を `allowed-tools` に literal で持つのは `skills/review/SKILL.md` のみ (`#1428` で追加)
- **判断**: 新規解決ステップは `HAS_PR_PREVIEW_CAPABILITY` を**ロード済みの呼び出し元**でのみ発火する設計とし、実際にロードするのは `skills/review/SKILL.md` (L113) のみ。したがって `code` / `verify` / `auto` は本スクリプトを呼ばず、`allowed-tools` 追加は不要。この前提を Implementation Step 6 の Caller scope 記述として モジュール本文に明記し、監査可能にする (前提崩壊時の影響は `## Uncertainty` に記録)
- `modules/browser-adapter.md` の読者は modules のみ (`browser-verify-security.md` / `lighthouse-adapter.md` / `verify-executor.md` / `visual-diff-adapter.md`)。SKILL.md からの直接読み込みはなく、到達経路は verify-executor 経由のため上記と同じ結論

### fail-safe critical 判定

`scripts/resolve-preview-env.sh` は「失敗時に安全側の既定へ倒す」設計 (fail-open: 空 stdout + exit 0) に該当するため fail-safe critical。エッジケースの期待挙動は Implementation Step 4 に明示した。判定根拠の grep: `grep -nF -e 'fail_open' -e '|| true' -e '2>/dev/null' scripts/resolve-preview-env.sh` で `|| true` / `2>/dev/null` を確認

### 監査/調査型 Issue 判定

**該当しない**。本 Issue の目的は既存項目の分類・実査ではなく、共有スクリプトへの機能追加と消費側モジュールの記述追加。判断根拠を持続的成果物 (レポート) に per-item で記録する構造もない

### クレデンシャル/セキュリティポリシー整合

`grep -rl "credential\|security" docs/ SECURITY.md` でヒットしたポリシー文書を確認した。`SECURITY.md` L73 「Wholework does not store or transmit credentials. All GitHub operations use the `gh` CLI's existing authenticated session.」は GitHub CLI 認証に関する記述で本件とは別スコープ (`#1051` Spec が同じ判断を先例として記録済み)。本 Issue が書き出す資格情報ファイルは gitignore 済みの `.tmp/` 配下、600 権限、使用直後に `rm -f` する一時ファイルであり、`modules/verify-executor.md` が既に行っている curl config 書き出しと同じ性質。新たなポリシー矛盾はない

### 新規分岐ロジックに対する新規テストケース要件

`scripts/resolve-preview-env.sh` へ `basic-auth` モードという新規分岐を追加するため、command 型 AC (AC7 = `github_check "gh pr checks" "Run bats tests"`) は「既存スイートが PASS すること」だけでなく「新規分岐を検証する新規テストケースを `tests/resolve-preview-env.bats` に追加したうえでスイートが PASS すること」を要求する。要求される新規ケースの内訳は Implementation Step 10 の (a)-(g) に列挙した

### Auto-Resolve Log

非対話モード (`--non-interactive`) のため、以下は模型判断で自動解決した (詳細は Issue に投稿する retrospective コメントの Auto-Resolve Log にも記録):

- **資格情報ファイルは 2 フォーマット (`curl-config` / `user-pass`)、既定は `curl-config`** — 理由: 消費側 (prose モジュール) にパース処理を持ち込まないため。既定を安全側 (資格情報が復元しづらい curl config) にすることで、`--format` を書き忘れた呼び出しが平文 2 行ファイルを作らない。Other candidates: 単一フォーマット案 2 種 (`## Alternatives Considered` 参照)
- **`capabilities.pr-preview` ゲートは消費側 (モジュール本文) に置く** — 理由: `#1428` の `url` モードと対称であり、スクリプト内ゲートは `tests/run-review.bats` の `get-config-value.sh` モックが未知キーに既定値を返す性質上、既存 8 テストを一斉に壊す。Other candidates: `basic-auth` モード内で `get-config-value.sh capabilities.pr-preview` を確認する案
- **`scripts/run-review.sh` の env 変数 export 契約は維持する** — 理由: `run-review.sh` は `claude` サブプロセスへ環境変数を継承させることが目的であり、`#1417` の契約を変えるとサブプロセス側 (`/review` セッション) の既存「export 済み」経路が壊れる。`--format user-pass` の 2 行ファイルを読み戻して export する形で契約を保つ。Other candidates: ファイルパス自体を環境変数として渡す案 (消費側モジュールを 2 経路対応にする必要があり複雑)
- **`modules/verify-executor.md` の既存 `mktemp` テンプレートも同時修正する** — 理由: 同一段落に新規スニペットを追加する以上、誤った例を隣に残すと `/code` 実装時と将来の読者の双方を誤らせる。Other candidates: 別 Issue へ切り出す案 (同じ段落を触るのに 2 回に分ける合理性がない)

### Uncertainty と Implementation Steps の整合 (self-check)

`## Uncertainty` の解決済み 2 項目は、いずれも Implementation Steps へ漏れなく転記した — curl エスケープ規則は Step 3、BSD `mktemp` 制約は Step 3 (新規ファイル) と Step 6 (既存記述の修正) の**両方**へ個別に列挙している (片方だけの転記にしない)。未解決 1 項目 (verify-executor 読者の到達前提) は Step 6 の Caller scope 記述と Notes の allowed-tools 節へ転記した。整合方向は (a)「不足項目を Implementation Steps へ追加する」を採用

## Consumed Comments
No new comments since last phase.

## spec retrospective

### Minor observations

- Issue 本文の引用文字列 (`not by /review invoked directly as a skill`) が、兄弟 Sub-issue `#1428` のマージによって起票時点から実在しなくなっていた。親 Issue から分割された Sub-issue 群では「先行 Sub-issue のマージが後続 Sub-issue の Issue 本文を陳腐化させる」経路が構造的に存在する。`/spec` の String-matching verify command existence check がこれを捕捉したが、`file_not_contains` の「撤去対象が現在存在することを確認する」規則がなければ、常時 PASS の verify command のままマージまで到達していた
- Issue 本文の行番号参照 (`run-review.sh` L207-266、`verify-executor.md` L275-285) が実際とずれていた (実際は L150-209 / L269-285)。起票から `/spec` までの間に別 PR がファイルを変更したため。Implementation Steps 側は行番号ではなく周辺コンテキストで位置を指定する `/spec` の既存規則がそのまま機能した
- `modules/verify-executor.md` の既存 `mktemp .tmp/curl-auth-XXXXXX.cfg` が macOS の BSD `mktemp` で `X` を置換しないことは、静的読解では発見できず実測 (`mktemp` 実行 + `ls -l`) ではじめて判明した。`#1428` retrospective の「実コード実行によるエッジケース検証が有効だった」という記録が同じ形で再現した

### Judgment rationale

- **資格情報ファイルを 2 フォーマットにした理由**: 単一フォーマットに寄せると、消費側 (prose モジュール) のいずれかが必ず変換処理を持つことになる。curl のエスケープ規則を prose に書くのは `"` を含む password で壊れやすく、逆にシェルクオート規則を prose に書くのは `'` を含む password で壊れやすい。エスケープ知識をスクリプト 1 箇所に閉じ、消費側は「そのまま渡す」か「2 行読む」だけにするのが最も破損経路が少ない
- **`capabilities.pr-preview` ゲートをスクリプト内に置かなかった理由**: 一見スクリプト内ゲートのほうが堅牢だが、`tests/run-review.bats` の `get-config-value.sh` モックが未知キーに既定値を返す設計のため、既存 8 テストが一斉に落ちる。既存テストを大量改修してまで得られる堅牢性の増分は小さく、`#1428` (`url` モード) との対称性も失う
- **`skills/code` / `/verify` / `/auto` の `allowed-tools` を拡張しなかった理由**: `modules/verify-executor.md` の読者 7 skill のうち translation table を実行するのは 4 件だが、新規解決ステップは `HAS_PR_PREVIEW_CAPABILITY` をロード済みの呼び出し元でのみ発火する設計とした。前提が崩れても fail-open で非認証に落ちるだけで安全側に劣化するため、権限面の拡大より前提の明文化を選んだ

### Uncertainty resolution

- **curl config のエスケープ規則**: 公式 man page で 6 種のエスケープのみ有効と確認し、`curl --config <file> --libcurl` の `CURLOPT_USERPWD` 出力で往復を実測。設計時点で解決済み
- **BSD `mktemp` の suffix 挙動**: macOS 上で実測し、末尾以外の `XXXXXX` は置換されないことを確認。新規実装 (Step 3) と既存記述の修正 (Step 6) の両方に反映
- **verify-executor 読者の到達前提**: prose モジュールの LLM 実行挙動に依存するため機械的には固定できず、未解決のまま `## Uncertainty` に残した。前提崩壊時の影響 (fail-open で安全側に劣化) と検証方法 (マージ後の permission denied 監視) を併記している

### 新規分岐ロジックに対する新規テストケース要件 (要約)

`scripts/resolve-preview-env.sh` へ `basic-auth` という新規分岐を追加するため、AC7 (`github_check "gh pr checks" "Run bats tests"`) は既存スイートの PASS に加えて、`tests/resolve-preview-env.bats` への新規ケース追加を要求する。要求内訳は Implementation Step 10 の (a)-(g): `--format` 既定/明示/不正値、ガード 8 件の fail-open、`#1417` 非空性ガードの回帰テスト、特殊文字 (`"` / `\` / 複数 `:` / CRLF / 多バイト)、マスキング

## Code Retrospective

### Deviations from Design

- `tests/resolve-preview-env.bats` の既存テスト `@test "error: unknown mode"` は `basic-auth 123` を「未知モード」として exit 1 を期待していたが、本 Issue の実装により `basic-auth` は正規サポートモードになったため、このテストは実装後 FAIL する状態になっていた。Spec の Implementation Step 10 は新規テストケースの追加のみを指示しており、この既存テストの修正は明記されていなかったが、テスト対象を `bogus-mode` に差し替えて「本当に未知のモード」をテストする形に修正した (`git diff` で確認可能)。Implementation Steps 自体の変更は不要 (新規実装ロジックとは無関係な、既存テストの前提崩れの修正のため)

### Design Gaps/Ambiguities

- N/A — Spec が Implementation Steps・Notes・Uncertainty で実装判断のほぼ全てを事前に確定していたため、実装中に新たな設計判断や曖昧さの発見はなかった

### Rework

- N/A — 手戻りは発生しなかった。curl config のエスケープ順序 (`\` → `\\` の後に `"` → `\"`) と BSD `mktemp` の末尾 X 制約は Spec の Uncertainty 節で事前解決済みで、実装時に `curl --config --libcurl` による往復検証と `mktemp` の実測確認を行い、Spec の記載通りであることを再確認しただけだった

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- Spec の Implementation Steps・Notes を逐語通りに実装した。curl config エスケープ順序・BSD `mktemp` 末尾 X 制約・`#1417` 非空性ガード 3 条件・パイプ回避 (純 bash パラメータ展開) の 4 点は事前解決済みだったため、実装は Spec の記載を機械的に転記する作業だった
- `resolve-preview-env.sh` の `basic-auth` モード実装後、`curl --config --libcurl` で `CURLOPT_USERPWD` の実測往復検証を行い、`"` / `\` を含む password が正しく復元されることを確認した
- テストは Spec Step 10 の (a)-(g) を網羅する 20 件を新規追加し、既存 `tests/run-review.bats` の 8 件 (薄いラッパー化後) と合わせて計 28 件が本 Issue のガード移送を検証する

### Deferred Items

- `modules/lighthouse-adapter.md` / `modules/visual-diff-adapter.md` の Basic Auth 解決は Issue 本文 `## Known Gap` によりスコープ外のまま (変更なし)
- Playwright MCP 経路 (`extraHTTPHeaders`) の資格情報露出は既存挙動のまま、注記のみ追加 (Deferred のまま)
- verify-executor の読者のうち `skills/review/SKILL.md` 以外が解決ステップに到達しないという前提は未検証のまま — マージ後の permission denied 監視で確認する (Spec Uncertainty 節を参照)

### Notes for Next Phase

- Pre-merge AC 1-6 は本フェーズでチェック済み。AC7 (`github_check "gh pr checks" "Run bats tests"`) は CI verification AC exclusion によりチェック未実施のまま — `/review` で確認すること
- ローカルで全 1981 bats テストを実行し FAIL 0 件を確認済み (behavioral change detection によりフルスイート実行が要求された)
- Post-merge AC (`preview-basic-auth-command` を宣言した実プロジェクトでの直接 `/review` 実行の観察) は未検証のまま — `/verify` フェーズで対応すること
