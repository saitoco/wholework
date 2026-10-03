# Issue #1486: auto: セッション自動リネームのタイトルに環境変数で prefix を付けられるようにする

## Overview

`session-auto-rename: true` のとき、`scripts/hook-rename-on-auto.sh` (UserPromptSubmit hook) は `/auto` 実行時にセッションタイトルを `auto #N: <Issue タイトル>` / `auto #N (resume): <Issue タイトル>` / `auto batch #N1,N2,...` / `auto batch (N issues)` に置き換える。複数マシンのセッションを Remote Control 一覧などで見分けられるよう、環境変数 `WHOLEWORK_SESSION_TITLE_PREFIX` が空でないとき、生成したタイトルの先頭にその値をそのまま付ける。

- 区切り文字は自動で入れない (必要なら利用者が値に含める。例: `"mac "`)
- 50 文字の truncate は prefix を付ける前の本体タイトルに適用し、prefix は切らない
- 未設定・空文字のときは現在の出力を一切変えない
- `.wholework.yml` にキーは追加しない (マシン間で共有されるため。Issue の Non-Goals)

実装の要点: 3 経路 (`--batch` / `--resume` / 通常の `/auto N`) はすべて変数 `TITLE` に集約され、末尾で truncate → `jq -n --arg` で出力される。prefix の付与を truncate ブロックの直後・`jq` 出力の直前の 1 箇所に置けば、3 経路すべてに効き、かつ truncate の後になる。

## Changed Files

- `scripts/hook-rename-on-auto.sh`: truncate ブロック (`[ ${#TITLE} -gt 50 ]` / `TITLE="${TITLE:0:49}…"`) の直後、`jq -n --arg title "$TITLE"` の直前に、`WHOLEWORK_SESSION_TITLE_PREFIX` が空でないときだけ `TITLE` の先頭へ付与する分岐を追加。ファイル冒頭コメントにも 1 行追記 — bash 3.2+ 互換 (`${VAR:-}` と `[ -n ]` のみ使用)
- `tests/hook-rename-on-auto.bats`: `setup()` に `unset WHOLEWORK_SESSION_TITLE_PREFIX` を追加し、prefix の新規テストを追加
- `docs/guide/customization.md`: `### Available Keys` 表の `session-auto-rename` 行の Description に環境変数の説明を併記
- `docs/ja/guide/customization.md`: 同上 (日本語版)
- `docs/tech.md`: `## Environment Variables` 表に `WHOLEWORK_SESSION_TITLE_PREFIX` 行を追加 (`WHOLEWORK_YML` 行の直後) — [Steering Docs sync candidate]
- `docs/ja/tech.md`: 同上 (日本語版。`docs/translation-workflow.md` の同期義務) — [Steering Docs sync candidate]
- `modules/worktree-lifecycle.md`: Entry section step 2 の self-reference フィルタ (`ListAgents` の行の表示名を `/auto` のセッションタイトル規約と照合する箇所) に、prefix が先頭に付く場合は先頭一致ではなく部分一致で照合する旨を 1 文追記 — [Steering Docs sync candidate]

Steering Docs sync candidate check の結果 (スコープ: `docs/ tests/ scripts/ modules/` の全ファイル。`docs/spec/` の過去 Spec を含む):

- [Steering Docs sync candidate] keyword "hook-rename-on-auto.sh" skipped: matched 12 files (no discriminating power)
- keyword "WHOLEWORK_SESSION_TITLE_PREFIX": 0 files (新規識別子。既存の参照なし)
- keyword "session-auto-rename": 8 files。`docs/guide/customization.md` / `docs/ja/guide/customization.md` / `tests/hook-rename-on-auto.bats` は変更対象に含め済み。`docs/structure.md:23,213` と `docs/ja/structure.md:16,206` は hook の 1 行説明で prefix 追加後も正確なため変更不要。`modules/detect-config-markers.md:40,124` は `.wholework.yml` キー (`HAS_SESSION_AUTO_RENAME`) の行で、今回の環境変数は設定キーではない (Issue の Non-Goals) ため変更不要。`docs/spec/issue-549-*.md` / `docs/spec/issue-552-*.md` は使い捨ての過去 Spec のため対象外
- `docs/tech.md` / `docs/ja/tech.md` を候補に含める根拠: `WHOLEWORK_*` 環境変数の一覧は `docs/tech.md` の `## Environment Variables` 表に集約する運用で (先例: #748 が `WHOLEWORK_YML` を含む 4 変数の欠落を `/audit drift` の指摘で追記した)、追記しないと同じ drift が再発する

consumer sweep (セッションタイトル形式の消費者の列挙):

- コマンド: `grep -rn -e "auto batch" -e "(resume)" -e "auto #N" modules skills scripts agents hooks docs/workflow.md docs/guide docs/tech.md docs/structure.md docs/product.md` (スコープ: 列挙したディレクトリ・ファイルの全ファイル)
- 結果: `/auto` のセッションタイトル規約を消費するのは `modules/worktree-lifecycle.md:27` のみ。`skills/auto/SKILL.md:707,747,767,1101` の `/auto #N ...` は端末出力メッセージでセッションタイトルとは無関係
- 追加検索 `grep -rn -i -e "custom-title" -e "customTitle" -e "session_title" -e "session-title" -e "session title" -e "ListAgents" scripts modules skills agents hooks`: `modules/worktree-lifecycle.md:25-27` 以外に消費者なし

## Implementation Steps

1. `scripts/hook-rename-on-auto.sh` に prefix 付与を追加する (→ 受け入れ条件 1, 2, 3, 4)
   - 既存の truncate ブロックは変更しない (`[ ${#TITLE} -gt 50 ]` / `TITLE="${TITLE:0:49}…"` をそのまま残す)
   - truncate ブロックの直後、`jq -n --arg title "$TITLE"` の直前に次を追加する (コメントは英語で、既存コメントの密度に合わせる):
     ```bash
     # Prepend operator-supplied prefix (per-machine marker). Applied after truncation so the prefix
     # is never cut; no separator is inserted. Unset or empty: no-op (output unchanged).
     if [ -n "${WHOLEWORK_SESSION_TITLE_PREFIX:-}" ]; then
       TITLE="${WHOLEWORK_SESSION_TITLE_PREFIX}${TITLE}"
     fi
     ```
   - 値の trim・サニタイズ・区切り文字の補完はしない (末尾スペース付きの `"mac "` が意味を持つため)。`exit 0` の早期終了経路と `jq -n --arg` の出力は変更しない
   - ファイル冒頭コメントに、`WHOLEWORK_SESSION_TITLE_PREFIX` が設定されていればタイトルの先頭に付く旨を 1 行追記する
   - fail-safe critical (この hook は gh 失敗・不一致時に空出力で終了して既存のセッション名を保つ設計) のため、エッジケースの期待動作を以下に固定する:
     - 未設定・空文字: 分岐に入らず、出力は変更前とバイト単位で同一
     - 過大な prefix: 切り詰めずそのまま付ける (Issue の「prefix が切られない」)。新たな失敗経路はない
     - `"` / `\` / `>` / 多バイト文字 (例: 🐧): `jq -n --arg` が JSON エスケープするため出力は有効な JSON のまま。prefix は byte 依存の `${#TITLE}` / `${TITLE:0:49}` の対象外なので多バイト文字も壊れない
     - 改行・CR を含む値: 特別扱いしない (利用者入力。`jq --arg` が `\n` / `\r` にエンコードするため出力は有効な JSON のまま)
     - 依存コマンドの失敗: 新規分岐は外部コマンドを呼ばないので新たな失敗経路はない。既存の gh 失敗 → `exit 0` (空出力・既存タイトル維持) と jq 失敗時の挙動は不変。分岐は早期 `exit 0` のすべてより後ろにあるため、prefix だけのタイトルが出力されることはない
2. `tests/hook-rename-on-auto.bats` を更新する (after 1) (→ 受け入れ条件 7, 8)
   - `setup()` に `unset WHOLEWORK_SESSION_TITLE_PREFIX` を追加する。利用者のシェルにこの変数が export されていても (本機能の想定用途そのもの)、既存テストの完全一致アサーションが影響を受けないようにするため (先例: `tests/worktree-merge-push.bats` の `unset WHOLEWORK_PATCH_LOCK_TIMEOUT`)
   - 既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケースを追加したうえでスイートが PASS すること。テスト名には `WHOLEWORK_SESSION_TITLE_PREFIX` を含める。追加するケース:
     - (a) 未設定: 出力 JSON が変更前と完全一致 (`jq -c .` で正規化して `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","sessionTitle":"auto #123: Add auto-rename of session title"}}`)
     - (b) 空文字 (`WHOLEWORK_SESSION_TITLE_PREFIX=""`): (a) と同一の出力
     - (c) `/auto 123` + `🐧`: `🐧auto #123: Add auto-rename of session title`
     - (d) `/auto --resume 456` + `🐧`: `🐧auto #456 (resume): Short title`
     - (e) `/auto --batch 123 124 125` + `🐧`: `🐧auto batch #123,124,125`、`/auto --batch 5` + `🐧`: `🐧auto batch (5 issues)`
     - (f) 区切り文字を自動挿入しない: `"mac "` → `mac auto #123: ...`、`mac` → `macauto #123: ...`
     - (g) 長いタイトル: 既存の「50 文字超」テストと同じ gh モック入力で、prefix 付き出力が「prefix + prefix なし出力」と一致し (prefix が先頭に残る)、prefix なし出力が `…` で終わる (本体だけが truncate される)
     - (h) JSON 特殊文字: prefix `a"b\c ` で出力が有効な JSON のまま、`sessionTitle` が `a"b\c auto #123: ...` になる
     - (i) 無出力経路が prefix の影響を受けない: prefix 設定下で gh 失敗 (`/auto 999`)・非 `/auto` プロンプト (`/code 123`)・`--help`・`session-auto-rename: false` のいずれも空出力
   - テスト入力形式: 標準入力に `{"prompt":"/auto 123"}` 形式の JSON を渡し、`echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="..." bash "$SCRIPT"` で実行、`jq -r '.hookSpecificOutput.sessionTitle'` で取り出す。gh は `setup()` の `$MOCK_DIR/gh` を使う (issue 123 → `auto: Add auto-rename of session title`、456 → `Short title`、999 → exit 1)
3. `docs/guide/customization.md` と `docs/ja/guide/customization.md` を更新する (parallel with 1, 2) (→ 受け入れ条件 5, 6)
   - `### Available Keys` 表の `session-auto-rename` 行の Description に、`patch-lock-timeout` 行の `WHOLEWORK_PATCH_LOCK_TIMEOUT` の書き方に倣って次の内容を併記する: `claude` プロセスの環境に環境変数 `WHOLEWORK_SESSION_TITLE_PREFIX` が設定されているとき、その値が `/auto N` / `--resume` / `--batch` のいずれのタイトルにも先頭へそのまま付く (例: `🐧` → `🐧auto #123: ...`)、区切り文字は自動挿入されない (必要なら値に含める。例: `"mac "`)、50 文字の truncate は本体タイトルに適用され prefix は切られない、未設定・空文字ならタイトルは変わらない、キーではなく環境変数なのは `.wholework.yml` がコミットされてマシン間で共有されるため
   - 日本語版は同じ内容を日本語で書く (括弧は半角で前後に半角スペース。既存の表の文体に合わせる)
   - 追記位置 (Issue の自動解決で `/spec`・`/code` に委ねられた事項) はこの行の Description で確定。YAML 例のコメント行は変更しない
4. `docs/tech.md` と `docs/ja/tech.md` の `## Environment Variables` 表に行を追加する (parallel with 1, 2, 3)
   - `WHOLEWORK_YML` 行の直後に `WHOLEWORK_SESSION_TITLE_PREFIX` 行を追加する (Default は `*(unset)*` / `*(未設定)*`)。内容: `scripts/hook-rename-on-auto.sh` が生成する `/auto` のセッションタイトルの先頭にそのまま付ける prefix (`session-auto-rename: true` のときのみ効く)、区切り文字は自動挿入しない、50 文字 truncate の後に付けるので切られない、未設定・空文字ならタイトルは変わらない、環境変数のみで `.wholework.yml` キーは意図的に設けない (マシン間で共有されるため)、詳細は `docs/guide/customization.md` を参照
5. `modules/worktree-lifecycle.md` を更新する (parallel with 1, 2, 3, 4)
   - Entry section step 2 の self-reference フィルタの 3 つ目の箇条書き (`If AUTO_SESSION_ID is set, call ListAgents and compare each row's displayed name ...` で始まり、`auto #N (resume): <title>` で終わる箇条書き) の末尾に 1 文追記する: オペレーターが `WHOLEWORK_SESSION_TITLE_PREFIX` を設定している場合、hook はその値を区切り文字なしでこれらのタイトルの先頭に付けるため (例: `🐧auto #N: <title>`)、各パターンは表示名の先頭一致ではなく部分一致で照合すること
   - 追記内容に `scripts/*.sh` のパスを含めない (スクリプト名は同じ箇条書きの既存部分に既にある)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/hook-rename-on-auto.sh は環境変数 WHOLEWORK_SESSION_TITLE_PREFIX を参照する実装を持ち、かつ、それが未設定または空文字のときは prefix 関連の処理を行わず、変更前と同じ sessionTitle を出力する" --> `WHOLEWORK_SESSION_TITLE_PREFIX` が未設定または空文字のとき、hook の出力が変更前と同じ
- <!-- verify: file_contains "scripts/hook-rename-on-auto.sh" "WHOLEWORK_SESSION_TITLE_PREFIX" --> hook が環境変数 `WHOLEWORK_SESSION_TITLE_PREFIX` を読んでいる
- <!-- verify: rubric "scripts/hook-rename-on-auto.sh は、WHOLEWORK_SESSION_TITLE_PREFIX が設定されているとき、/auto N・--resume・--batch のいずれの経路で生成したタイトルでも、先頭に prefix を付けて出力する (区切り文字は自動で挿入しない)" --> 設定したとき、`/auto N` / `--resume` / `--batch` のいずれのタイトルにも prefix が先頭に付く
- <!-- verify: rubric "scripts/hook-rename-on-auto.sh は、50 文字の truncate を prefix を付ける前の本体タイトルに適用し、本体タイトルが長いときも prefix は切られずに残る" --> 本体タイトルが長いとき、prefix は残り、本体だけが truncate される
- <!-- verify: file_contains "docs/guide/customization.md" "WHOLEWORK_SESSION_TITLE_PREFIX" --> customization ガイド (英語版) に環境変数 `WHOLEWORK_SESSION_TITLE_PREFIX` の説明がある
- customization ガイド (日本語版 `docs/ja/guide/customization.md`) に環境変数 `WHOLEWORK_SESSION_TITLE_PREFIX` の説明がある
- <!-- verify: file_contains "tests/hook-rename-on-auto.bats" "WHOLEWORK_SESSION_TITLE_PREFIX" --> `tests/hook-rename-on-auto.bats` に `WHOLEWORK_SESSION_TITLE_PREFIX` を扱うテスト (prefix 未設定 / 設定時の各経路 / 長いタイトルの truncate) が追加されている
- <!-- verify: command "bats tests/hook-rename-on-auto.bats" --> `tests/hook-rename-on-auto.bats` が通る (既存テストを含む回帰保護)
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが通る (PR route)

### Post-merge

なし

## Notes

**Size 再評価 (Step 18 の根拠)**: 変更ファイルは 7 件で、Axis 1 は L (6-10)。Axis 2 は「スクリプトロジック変更 (新規分岐)」で +1、「既存パターンの単純な横展開 (docs 表行の追記、既存テストの流儀の踏襲)」で -1、差し引き 0 のため最終 Size は L。triage 時点の Size M (想定 4 ファイル) から、調査で `docs/tech.md` / `docs/ja/tech.md` / `modules/worktree-lifecycle.md` の 3 件が増えたことによる。本 Spec は `/spec` 開始時の Size M に基づき light で作成している (深さは再判定しない)。

**受け入れ条件に対応しない Step (4, 5)**: Step 4 (tech.md の環境変数表) と Step 5 (worktree-lifecycle.md) は Issue の受け入れ条件に含まれない。light では Issue 本文の受け入れ条件を書き換えず、Changed Files と Implementation Steps で実装範囲を固定する (`/review` の spec 逸脱レビューが差分を Spec と突き合わせる)。実装後のセルフチェックとして、`/code` は `grep -c WHOLEWORK_SESSION_TITLE_PREFIX docs/tech.md docs/ja/tech.md modules/worktree-lifecycle.md` が各ファイルで 1 以上であることを確認する。

**自動解決した曖昧点 (non-interactive)**:

- docs の追記位置: Issue の自動解決を引き継ぎ、`session-auto-rename` 行の Description に確定 (`patch-lock-timeout` 行の `WHOLEWORK_PATCH_LOCK_TIMEOUT` の書き方に倣う)
- 範囲の追加 (`docs/tech.md` 系 2 件と `modules/worktree-lifecycle.md`): 上記 Changed Files の根拠による。Issue の提案 1-4 を狭めるものではなく、整合のための追加同期のみ

**外部仕様の確認 (Claude Code hooks)**:

- 出所: https://code.claude.com/docs/en/hooks (取得日 2026-10-03)
- 環境変数の継承: "A hook process inherits the parent environment, apart from the `OTEL_*` exporter variables that Claude Code removes from every subprocess it spawns and, when `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is set to `1`, the variables it strips." — `claude` を起動したシェルで export した `WHOLEWORK_SESSION_TITLE_PREFIX` は hook から見える。`settings.json` の `env` キー経由の設定も、Claude Code がプロセス環境へ書き込むため hook に届く (出所: https://code.claude.com/docs/en/env-vars の `env` の説明 "Claude Code writes each `env` entry into the process environment, replacing the value inherited from the shell")
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` が落とすのは資格情報系 (`*KEY*` / `*TOKEN*` / `*SECRET*` / `*PASSWORD*` / `*CREDENTIAL*` / `*AUTHORIZATION*` など) で、`WHOLEWORK_SESSION_TITLE_PREFIX` は該当しない。ただしこの点は一次情報で確認できていない (出所: 2026-10-03 の WebSearch 結果の要約。公式 env-vars ページは取得時に当該エントリの手前で途中打ち切りだった)。影響範囲はこの opt-in 設定を使う環境のみ
- `sessionTitle` の記載: 公式ドキュメントの hooks ページでは `sessionTitle` が「SessionStart decision control」にのみ記載され、UserPromptSubmit の節には記載がない。一方、既存の UserPromptSubmit hook (#549, #552) は `hookSpecificOutput.sessionTitle` を使っており、Issue #1486 の背景も「`/auto` のリネームが `claude --name` の印を上書きする」と実動作を述べている。本 Issue はタイトル文字列の値だけを変え、hook のイベント種別と JSON 形状は変えないため、設計への影響はない。upstream の挙動が変われば影響するのは prefix だけでなく `session-auto-rename` 機能全体であり、本 Issue の範囲外
- hook の JSON 出力 (変更なし): `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","sessionTitle":"<title>"}}`。必須は `hookEventName` (値は `"UserPromptSubmit"`)。出力を省略 (空出力で `exit 0`) した場合は既存タイトルが維持される。本 Issue で追加するフィールドはない

**fail-safe critical の判定**: yes。根拠: スクリプト冒頭コメント (`Silent exit (empty output) on no match or gh failure to preserve existing session name`) と、`grep -nF -e 'fail_open' -e '|| true' -e '2>/dev/null' scripts/hook-rename-on-auto.sh` が 53, 64 行目 (`2>/dev/null` と `|| exit 0`) にヒットすること。判定基準 (c) に該当する。エッジケースの期待動作は Implementation Step 1 に記載。

**監査・調査型 Issue の判定**: no (機能追加であり、既存項目の分類・監査ではない)。

**新規テストケース要件 (light のため Step 13 の代わりにここへ記録)**: 新規分岐 (`if [ -n "${WHOLEWORK_SESSION_TITLE_PREFIX:-}" ]`) に対し、Step 2 の (a)〜(i) を新規テストケースとして `tests/hook-rename-on-auto.bats` に追加したうえでスイートが PASS すること。受け入れ条件 8 は既存テストの回帰保護、受け入れ条件 7 は新規テストの存在確認、受け入れ条件 9 は CI での全体実行。

**allowed-tools impact chain check**: 新規 `scripts/*.sh` はない (Case 1 非該当)。`modules/worktree-lifecycle.md` への追記内容に `scripts/*.sh` のパスを含めないため Case 2 の軽量ゲートに該当せず、reader の列挙は不要。

**String-matching verify command の存在確認**: `file_contains` の 3 件 (`scripts/hook-rename-on-auto.sh` / `docs/guide/customization.md` / `tests/hook-rename-on-auto.bats`) はいずれも `WHOLEWORK_SESSION_TITLE_PREFIX` を検索する。現時点で `docs/ tests/ scripts/ modules/ skills/ agents/ hooks/` に 0 件であることを `grep -rl` で確認済みで、実装が導入する文字列である。

**受け入れ条件 4 の rubric と数値リテラル**: rubric は 50 文字に言及するが、50 は既存の truncate 閾値 (`-gt 50` / `0:49`) で、本 Issue は変更しない (Step 1 で既存ブロックをそのまま残す)。受け入れ条件の要点は truncate → prefix の順序であり、文字列一致では検証できないため `file_contains` の補助 verify command は追加していない。順序の決定的な検証は新規テスト (g) が担う (受け入れ条件 7, 8 経由)。

**受け入れ条件 6 (日本語版ガイド)**: Issue の方針 (`docs/ja/` は verify command を付けない) に従って転記した。`/review` の「verify command なし」の分岐で AI 判断により確認される。決定的にしたい場合は `file_contains "docs/ja/guide/customization.md" "WHOLEWORK_SESSION_TITLE_PREFIX"` を追加できる (環境変数名は言語に依存しないため、日本語版の文体には影響しない)。

**Verification の項目数**: Pre-merge は 9 件で light の目安 (5 件) を超えるが、Issue 本文の受け入れ条件を 1:1 で転記した結果である (Issue 本文が verify command の SSoT であり、件数一致チェックを優先した)。Implementation Steps は 5 件で目安内。

**`.claude/` 配下**: `.claude/settings.json.template:21` は hook をパスで参照するだけで変更対象ではない (`git add -f` は不要)。`hooks/hooks.json` も登録のみで変更不要。

**日本語 docs の文体**: `docs/ja/*` の追記は既存の表の文体に合わせ、括弧は半角で前後に半角スペースを入れる。

## Code Retrospective

### Deviations from Design
- 設計からの逸脱なし。Implementation Steps 1-5 をそのまま実装した

### Design Gaps/Ambiguities
- この環境には `bats` が PATH になく、GNU `parallel` も無かった。`npx --yes bats` で代替し、`--jobs` は使えないため `ls tests/*.bats | xargs -P 4 -n 20 npx --yes bats` のシャード並列でフルスイートを実行した (FAIL 0 件)。`modules/test-runner.md` の `--jobs` fallback 節に沿った扱い
- 新規テストは出力を検証する振る舞いテストで、文字列一致型 (`grep` / `file_contains`) ではないため、Pre-implementation FAIL Check の対象外とした

### Rework
- なし (テスト中の `[[ ... ]]` に `|| false` を付け足した軽微な修正のみ)

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (docs 追記位置の確定を spec・code フェーズへ委任) / https://github.com/saitoco/wholework/issues/1486#issuecomment-5963663315

## review retrospective

### Spec vs. implementation divergence patterns
- 構造的な乖離なし。変更ファイル 8 件は Spec の Changed Files と一致し、prefix 付与の位置・テストケース (a)〜(i) も Spec の通りだった

### Recurring issues
- 繰り返しの指摘なし。指摘は CONSIDER 1 件 (`docs/ja/tech.md` の「env var」と「環境変数」の表記揺れ) のみで、修正は見送った。review-bug の 1 件 (`modules/worktree-lifecycle.md` の部分一致照合) は検証 sub-agent が REJECT した
- `capabilities.workflow: true` でも、完了通知を受け取れない実行面では Workflow パスを使わず、静的な Task fan-out をフォアグラウンドで実行した。通知待ちにならず、3 sub-agent の結果をすべて同一ターンで回収できた

### Acceptance criteria verification difficulty
- UNCERTAIN なし。`command "bats ..."` は safe mode のため直接実行せず、CI の `Run bats tests` ジョブ (全 bats を実行) の SUCCESS で代替判定した。日本語版ガイドの条件は verify command なしのため diff から AI 判断で PASS とした (Spec の注記通り `file_contains` を足せば決定的にできる)

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- pre-merge AC ゲートは未チェック 0 件・review-incomplete-fallback なしで通過し、競合もなかったため、`--squash` (base の `.wholework.yml` から解決) でそのままマージした

### Deferred Items
- `docs/ja/tech.md:271` の「env var のみで」を「環境変数のみで」に揃える (任意。必要なら別 Issue)

### Notes for Next Phase
- Post-merge の確認項目はなし。`/verify` は Pre-merge AC がマージ後も成立していることの確認のみでよい

