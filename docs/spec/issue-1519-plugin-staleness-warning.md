# Issue #1519: phase-banner: plugin-dir の読み込み元が upstream より遅れている場合に警告

## Overview

`claude --plugin-dir <wholework の checkout>` で Wholework を読み込むと、その checkout を誰も pull しない限り、Skill・モジュール・スクリプトは古い版のまま動く。修正の Issue を閉じても手元では効いておらず、それに気づく手段が無い (下流での実例: #1478 の修正が入っていない checkout が origin/main より 208 コミット遅れていた)。

この Issue では、全 Skill が通るバナー手順 (`modules/phase-banner.md`) に、読み込み元 (`${CLAUDE_PLUGIN_ROOT}`) が git の checkout で upstream より遅れていれば、遅れのコミット数を含む警告を 1 行出す手順を足す。遅れの数え方は新規スクリプト `scripts/check-plugin-staleness.sh` に切り出す (読み取り専用・ネットワークなし・常に exit 0)。git の checkout でない場合と数えるのに失敗した場合は何も出さずに続け、自動では pull しない。

Issue 本文が Spec に委ねた 2 点は次のとおり決めた (理由と却下案は Notes)。

1. 実装位置: `modules/phase-banner.md` の LLM 手順 + 新規ヘルパースクリプト。`scripts/phase-banner.sh` (`run-*.sh` 用) は変更しない
2. fetch: しない。最後に fetch した `@{u}` と比べる。fetch していない checkout は遅れが見えない盲点があり、Notes と `docs/guide/troubleshooting.md` に明記する

変更ファイルは 15 件 (新規 2、既存 13)。うち 8 件は `skills/*/SKILL.md` の frontmatter `allowed-tools` への 1 エントリ追加で、`scripts/validate-skill-syntax.py` の CI 検査 (`validate_modules_scripts_in_allowed_tools`) が要求する機械的な変更である。

## Changed Files

測定範囲: リポジトリ内で作成・変更するファイルの数 (本 Spec 自身は除く)。新規 2 + 既存 13 = 15 件。

- `scripts/check-plugin-staleness.sh`: 新規。実行権限を付ける (`chmod +x`。`git ls-files -s scripts/check-plugin-staleness.sh` が `100755` を示すこと。Skill は `${CLAUDE_PLUGIN_ROOT}/scripts/NAME.sh` を直接実行する形で呼ぶ)。bash 3.2+ 互換 (`mapfile`・連想配列を使わない。`printf '%q'`・`case`・`[ ]` だけを使う)
- `tests/check-plugin-staleness.bats`: 新規。実 git で組んだフィクスチャを使う (git のモックは、git 失敗を模す 2 ケースだけ)
- `modules/phase-banner.md`: Purpose / Processing Steps (新 Step 4) / Output / Notes を変更
- `skills/auto/SKILL.md`, `skills/code/SKILL.md`, `skills/issue/SKILL.md`, `skills/merge/SKILL.md`, `skills/review/SKILL.md`, `skills/spec/SKILL.md`, `skills/triage/SKILL.md`, `skills/verify/SKILL.md`: frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-staleness.sh:*` を 1 エントリ追加する (本文は変更しない)。この 8 件は `modules/phase-banner.md` を本文で読む Skill の全件 (測定コマンド: `grep -rl 'modules/phase-banner.md' skills/`、範囲は `skills/` 配下の全ファイル、除外なし、結果 8 件)。`skills/verify/SKILL.md` だけは `skill-body-sha` マーカーの再計算が要る (Implementation Steps 4)
- `docs/structure.md`: [Steering Docs sync candidate] Key Files の 2 箇所 (L144 の `modules/phase-banner.md` の説明、Scripts の `**Phase banner:**` 群に新スクリプトの 1 項目)。Directory Layout は説明が役割ベースで件数コメントを持たないので変更しない
- `docs/ja/structure.md`: `docs/translation-workflow.md` の同期手順に従い、上記の 2 箇所を日本語で反映する (L137 と、L167-L168 の `**Phase banner:**` 群)
- `docs/guide/troubleshooting.md`: 新セクション "Plugin Directory Is Behind Upstream" を `## Skill Updates Not Reflected Mid-Session` の直後、`## Further Help` の直前に足す (警告の意味・直し方・盲点・抑止方法)
- `docs/ja/guide/troubleshooting.md`: 同じセクションの日本語版を `## スキル更新がセッション中に反映されない` の直後、`## さらに助けが必要なとき` の直前に足す

**同期候補の機械的スイープ** (測定コマンド: `grep -rl "<keyword>" docs/ tests/ scripts/ modules/ | grep -v -e '^docs/spec/' -e '^docs/sessions/' | wc -l`、つまり `docs/spec/` と `docs/sessions/` を除く。閾値 8 超で skip):

- `check-plugin-staleness` (この Issue が導入する名前): 0 件 (既存参照なし)
- `phase-banner.md`: 3 件 (閾値内)。`docs/structure.md`、`docs/ja/structure.md`、`docs/reports/progress-scaffolding-audit.md`。最後は過去の監査レポート (翻訳対象外・履歴) なので変更しない。前 2 件は上記 Changed Files に採用
- `phase-banner.sh`: 22 件。この Issue は `scripts/phase-banner.sh` を変更しない (判断は Notes) ので同期対象なし。`tests/run-*.bats` などが `$MOCK_DIR/phase-banner.sh` をモックしている件も影響を受けない
- [Listing-side sub-check] 新規ファイルを足すため発火。候補は `docs/structure.md` (frontmatter `ssot_for` に `directory-layout` があることを確認済み) と `README.md`。`README.md` は `scripts/` / `modules/` を列挙しておらず (`grep -n "scripts/\|modules/" README.md` が 0 件)、変更しない
- [Outbound pointer sync candidate] `modules/phase-banner.md` には他ファイルを指す "See also" / "SSoT:" 型の pointer が無い。追加する新セクションも他ファイルを指さない。他の変更ファイルの pointer も本変更に影響されない
- `docs/migration-notes.md`: 本 Issue は既存スクリプトの CLI シグネチャ・フラグ・引数順を変えない (新規スクリプト) ので対象外
- `modules/doc-checker.md` の Change Types (skill-dev 補足を含む): 「共有モジュールの変更」→ `docs/workflow.md` のモジュール/エージェント一覧表: 該当する表は無い (`docs/workflow.md` の `modules/` 言及はすべて個別モジュールへの文中参照で、`phase-banner` を含むものは 0 件)。「スクリプトの追加」→ `README.md` のスクリプト説明: 該当記述なし。いずれも変更しない
- `SECURITY.md`: "Git Operations" は状態を変える操作 (commit / branch / push / rebase) だけを列挙しており、本ヘルパーは読み取り専用なので変更しない (L21-L28 を読んで確認)

**テストの同期**:

- `tests/phase-banner.bats` は `scripts/phase-banner.sh` のテストで、`.sh` を変更しないので不変
- `tests/code.bats` L206 / L250 は `head -6 "$SKILL_FILE" | grep -qF '<entry>'` の存在確認で、`allowed-tools` 行へのエントリ追加の影響を受けない (行数も変わらない)
- `tests/verify.bats` L194 (`skill-body-lines`) と L201 (`skill-body-sha`)、`tests/check-skill-body-hash.bats` は `skills/verify/SKILL.md` のマーカー整合を検査する。frontmatter を編集するので sha の再計算が必須 (行数は変わらないので `skill-body-lines` は 997 のまま)
- `$MOCK_DIR` へのモック追加 (`WHOLEWORK_SCRIPT_DIR` 型) は不要: 新スクリプトを呼ぶ `scripts/` 側のスクリプトは無く、この Issue も足さない (`grep -rn "check-plugin-staleness" scripts/ tests/` が 0 件)

## Implementation Steps

1. `scripts/check-plugin-staleness.sh` を新規作成する (→ AC1, AC2)
   - シバンは `#!/usr/bin/env bash`。ヘッダーコメント (英語) に書く内容は、用途、出力契約、fail-open の方針、「読み取り専用でネットワークに出ない (fetch / pull / merge をしない)」こと、そして Usage `check-plugin-staleness.sh [plugin-root]` (省略時はスクリプト自身の親ディレクトリ = `${CLAUDE_PLUGIN_ROOT}`) である。`set -e` / `set -u` は付けず、その理由 (全ての失敗経路が黙って exit 0 に着地する契約) をコメントに残す
   - 出力契約 (stdout): 何も出さない、または upstream が HEAD より進んでいるときだけ 1 行 `behind=<N> upstream=<追跡 ref 例: origin/main> root=<シェルクォート済みの絶対パス>`。終了コードは常に 0
   - 参照実装 (プロトタイプで検証済み。Notes の実測を参照)。ヘッダーコメントの後ろに置く

     ```bash
     unset CDPATH

     root="${1:-}"
     if [ -z "$root" ]; then
       root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)" || exit 0
     else
       root="$(cd -- "$root" 2>/dev/null && pwd -P)" || exit 0
     fi

     command -v git >/dev/null 2>&1 || exit 0

     top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || exit 0
     top="$(cd -- "$top" 2>/dev/null && pwd -P)" || exit 0
     [ "$top" = "$root" ] || exit 0

     behind="$(git -C "$root" rev-list --count 'HEAD..@{u}' 2>/dev/null)" || exit 0
     case "$behind" in
       ''|*[!0-9]*) exit 0 ;;
     esac
     [ "$behind" -gt 0 ] || exit 0

     upstream="$(git -C "$root" rev-parse --abbrev-ref '@{u}' 2>/dev/null)" || upstream="upstream"
     [ -n "$upstream" ] || upstream="upstream"

     printf 'behind=%s upstream=%s root=%q\n' "$behind" "$upstream" "$root"
     exit 0
     ```

   - このスクリプトは fail-safe critical (失敗時に安全側の既定 = 無出力を返す設計、`|| exit 0` と `2>/dev/null` を持つ) と判定した。各エッジケースの期待挙動を次のとおり固定する。ネットワークに出る・書き込む処理 (`git fetch` / `pull` / `merge` / `checkout` / `update-index` など、リポジトリを変えるもの) は一切足さない

     | 入力・状態 | 期待される挙動 | 理由 |
     |---|---|---|
     | 引数なし / 空文字列 | スクリプト自身の親ディレクトリを root とする | `${CLAUDE_PLUGIN_ROOT}/scripts/` から実行されるので、親ディレクトリが `${CLAUDE_PLUGIN_ROOT}` に一致する |
     | 存在しない path / 5000 文字の path | 無出力・exit 0 | `cd` の失敗は fail-open |
     | 空白・`"`・`$`・`>`・改行・CR・多バイト文字を含む path | `root=` は `printf '%q'` で 1 行かつシェル再入力可能に出す (`eval` で元の path に戻る) | 出力 1 行の契約。改行入りの path が行を増やすと、LLM が偽の警告行を中継しうる |
     | シンボリックリンクの root | 物理パス (`pwd -P`) で報告 | `git rev-parse --show-toplevel` も物理パスを返すので、一致判定が成り立つ |
     | git が無い / git が非 0 で終わる / 件数が空・負・非数 | 無出力・exit 0 | 警告は助言。Skill を止める・誤警告を出すより沈黙のほうが安全 |
     | toplevel が root と異なる (別リポジトリの中に入れ子になった普通のディレクトリ) | 無出力・exit 0 | 外側のリポジトリの遅れを誤って報告しない (`$HOME` が dotfiles リポジトリのとき、その配下のキャッシュに起きる) |
     | detached HEAD / upstream 未設定 / ahead のみ / 同期済み | 無出力・exit 0 | 遅れが無い、または数えられない |
     | diverged (ローカルに未 push のコミットもある) | upstream 側だけにあるコミット数を出す | `git pull --ff-only` は失敗しうるが、遅れを知らせる助言としては有益。判断はユーザーに任せる |

2. `tests/check-plugin-staleness.bats` を新規作成する (after 1) (→ AC1)
   - ファイル冒頭に `bats_require_minimum_version 1.5.0` を置き、無出力ケースでは `run --separate-stderr` で stdout と stderr の両方が空であることを確認する。`[[ ... ]]` を使うときは `|| false` を付ける (`scripts/check-bare-bracket-assertions.sh` の規約)
   - `setup()` は `tests/reclaim-stale-worktrees.bats` の流儀に合わせる (`git init -q -b main`、`git init -q --bare -b main`)。フィクスチャは bare の upstream、5 コミットを積んで push した seed、upstream を追跡する work クローン。リポジトリローカルの `user.email` / `user.name` / `commit.gpgsign=false` を設定し、`$BATS_TEST_TMPDIR` だけを使う (並列実行 `bats --jobs` で衝突しない)。遅れの作り方は `git reset --hard HEAD~N` (追跡 ref は動かない)
   - 新規ロジックを検証するテストケース (すべて新規)

     | `@test` 名 | 確認すること |
     |---|---|
     | `behind upstream: prints one behind=N line with upstream and root` | 3 コミット遅れで `behind=3 upstream=origin/main root=<work>` の 1 行、exit 0 |
     | `in sync with upstream: prints nothing` | 無出力・exit 0 |
     | `ahead of upstream only: prints nothing` | 無出力 |
     | `diverged: counts only the upstream-side commits` | ローカル +1・upstream +2 で `behind=2` |
     | `does not fetch: a stale remote-tracking ref hides new upstream commits until an explicit fetch` | 別クローンから upstream に 2 コミット足しても work では件数が変わらず、`git fetch` 後に増える (「fetch しない」契約を固定する) |
     | `read-only: HEAD, remote-tracking ref and worktree state are unchanged` | 実行前後で `rev-parse HEAD`・`rev-parse refs/remotes/origin/main`・`status --porcelain` が同じ |
     | `detached HEAD: prints nothing` / `branch without upstream: prints nothing` | 無出力 |
     | `plain directory outside any repository: prints nothing` | 無出力 |
     | `directory nested inside a behind repository: prints nothing` | 遅れた外側リポジトリの中の普通のディレクトリで無出力 (toplevel 不一致) |
     | `nonexistent, empty-string and oversized path arguments print nothing and exit 0` | 存在しない path・`""`・5000 文字の path。`""` は既定の root (この Issue のリポジトリ) になるので、exit 0 と出力が 0 または 1 行であることだけを確認する |
     | `root with space, quote, dollar, newline and multibyte characters: one shell-quoted line that round-trips` | 各 path で出力が 1 行、`root=` の値を `eval` すると元の物理パスに戻る |
     | `symlinked plugin root: reports the physical path` | リンク経由で渡しても物理パスで出る |
     | `default root is the parent directory of the script itself` | work の `scripts/` にスクリプトをコピーして引数なしで実行し、`root=` が work になる |
     | `git failure: a fake git that exits 1 prints nothing` / `non-numeric or negative count from git prints nothing` | `$BATS_TEST_TMPDIR/bin` に偽 git を置いて `PATH` の先頭へ。後者の偽 git は `git -C <dir> rev-parse --show-toplevel` に `<dir>` を返し、`rev-list` に `abc` / `-3` / 空を返す |
     | `no git on PATH: prints nothing and exits 0` | 空のディレクトリだけを `PATH` にし、`"$BASH" "$SCRIPT" "$REPO"` で実行 |

3. `modules/phase-banner.md` を変更する (parallel with 1, 2) (→ AC1, AC2)
   - 挿入する文面はすべて英語 (日本語は警告テンプレートの code fence 内だけ。`scripts/check-language-convention.py` が code fence 内を除外する)。半角 `!` を入れない
   - モジュール本文で `${CLAUDE_PLUGIN_ROOT}/scripts/` を前置した形で書くスクリプトは `check-plugin-staleness.sh` だけにする。`validate_modules_scripts_in_allowed_tools` は本文全体から `${CLAUDE_PLUGIN_ROOT}/scripts/NAME.sh` を拾うので、他のスクリプトをその形で書くと全 8 SKILL.md の `allowed-tools` への追加要求が波及する (Notes では `scripts/phase-banner.sh` と、前置なしで書く)
   - **Purpose**: 既存の 1 文の後ろに足す

     ```text
     Right after the banner, also warn when the plugin directory the Skill was loaded from (`${CLAUDE_PLUGIN_ROOT}`) is a git checkout that is behind its upstream, because a stale checkout silently runs old Skills, modules, and scripts.
     ```

   - **Processing Steps**: 既存の 3 の後ろに Step 4 を足す (既存の 1-3 は変えない)

     ````markdown
     4. Warn when the plugin directory is behind its upstream, right after the banner. Skip this step when the same warning was already shown earlier in this conversation (for example when this Skill runs inside another Skill's flow). Run the helper as a single command; it never changes the checkout and always exits 0:
        ```bash
        ${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-staleness.sh
        ```
        - **No output**: the plugin directory is not a git checkout (for example a marketplace install), HEAD is detached, no upstream is configured, it is not behind, or counting the lag failed. Output nothing and continue with the calling Skill.
        - **One line `behind=N upstream=U root=R`**: the upstream is N commits ahead of HEAD. Output this warning as one line, with {N}, {U}, and {R} substituted ({R} is already shell-quoted; use it as is):
          ```
          wholework の読み込み元が最後に fetch した {U} より {N} コミット遅れています。`git -C {R} pull --ff-only` を検討してください
          ```
        - **The command itself cannot run** (script missing, not executable, non-zero exit): treat it as no output. Never stop the Skill, retry, or report an error because of this step.
        - Never run `git pull`, `git fetch`, `git merge`, or any other command that changes the checkout, including the suggested one. Whether and when to update is the user's decision (see Notes).
     ````

   - **Output**: `Phase identification banner displayed to terminal.` を `Phase identification banner displayed to terminal, followed by a one-line staleness warning only when the plugin directory is behind its upstream.` に変える
   - **Notes**: 既存の段落の後ろに、次の小節を足す

     ````markdown
     ### Plugin directory staleness warning (Issue #1519)

     - **Scope**: `${CLAUDE_PLUGIN_ROOT}` is checked only when it is itself the top level of a git work tree whose current branch has an upstream, which is the `claude --plugin-dir <checkout>` setup. A marketplace install (not a git checkout), a plain directory (including one nested inside an unrelated repository), a detached HEAD, a branch without an upstream, or any failure while counting produces no output, so the Skill continues without a warning.
     - **Measurement**: `git rev-list --count HEAD..@{u}`, the number of upstream commits that HEAD does not contain. The helper makes no network access, so the count is relative to the remote-tracking ref as of the last fetch: a checkout that nobody has fetched can look up to date. Keeping that ref fresh (for example a scheduled `git fetch` in the checkout) is left to the user; see `docs/guide/troubleshooting.md`.
     - **Never updates the checkout**: this step only reports. It never runs `git pull`, `git fetch`, or `git merge`, because another session may be executing scripts from the same checkout and a pull would change them mid-run. The suggested `git -C <root> pull --ff-only` is for the user to run.
     - **Why `scripts/phase-banner.sh` does not call the helper**: it serves the `run-*.sh` wrappers, which run headless and repeat for every phase (in `--output-format json` runs the wrapper keeps only the final `.result`, so a line the session prints mid-run does not reach the wrapper log anyway). An interactive `/auto` shows this warning once at its own banner; calling the helper from `print_start_banner` too would repeat the line for every phase of every Issue.
     - **Not covered**: Skills that show no start banner (`/audit`, `/doc`) and runs that are headless from the start.
     ````

4. 8 件の `skills/*/SKILL.md` の `allowed-tools` を更新し、`skills/verify/SKILL.md` のマーカーを再計算する (after 1, 3) (→ AC1)
   - 対象 8 件: `auto`、`code`、`issue`、`merge`、`review`、`spec`、`triage`、`verify`。各ファイルの frontmatter で `allowed-tools: Bash(` (各ファイルに 1 か所だけあることを確認済み) の直後に `${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-staleness.sh:*, ` を挿入する。本文は変更しない。`/audit` と `/doc` は `modules/phase-banner.md` を読まないので変更しない
   - `skills/verify/SKILL.md`: 編集後に `grep -v '<!-- skill-body-' skills/verify/SKILL.md | shasum -a 256 | cut -c1-8` で新しいハッシュを求め、`<!-- skill-body-sha: ... -->` の値を置き換える。`wc -l < skills/verify/SKILL.md` が 997 のままで `skill-body-lines` マーカーを変えなくてよいことも確認する
   - 確認: `python3 scripts/validate-skill-syntax.py skills/` (モジュール経由のスクリプト参照と存在確認が通る)、`bash scripts/check-skill-body-hash.sh`、`bats tests/verify.bats tests/check-skill-body-hash.bats tests/code.bats`

5. ドキュメントを更新する (after 3) (→ SHOULD: ドキュメント同期)
   - `docs/structure.md`: L144 の `modules/phase-banner.md` の項目を次の 1 行に置き換える。続けて、Scripts の `**Phase banner:**` 群で `scripts/phase-banner.sh` の次の行に、`scripts/check-plugin-staleness.sh` の項目を足す

     ````text
     - `modules/phase-banner.md` — phase identification banner display for skills, followed by a warning when the plugin directory (`${CLAUDE_PLUGIN_ROOT}`) is a git checkout behind its upstream
     - `scripts/check-plugin-staleness.sh` — read-only, offline helper called by `modules/phase-banner.md` Step 4: prints nothing, or one line `behind=<N> upstream=<ref> root=<path>` when the plugin directory (a git checkout loaded with `--plugin-dir`) is behind its upstream as of the last fetch; always exits 0 (not a git checkout, detached HEAD, no upstream, or any git failure prints nothing); never fetches or pulls
     ````

   - `docs/ja/structure.md`: 同じ 2 箇所を日本語で反映する。新規テキストの括弧は半角 `()` の前後に半角スペースを入れる
   - `docs/guide/troubleshooting.md` に次のセクションを足す (見出しは `##`、`type: project` frontmatter はそのまま)

     ````markdown
     ## Plugin Directory Is Behind Upstream

     **Symptom**: At the start of a Skill, a warning says that the wholework plugin directory is N commits behind its upstream (for example `origin/main`).

     **Cause**: With `claude --plugin-dir <checkout>`, the Skills, modules, and scripts that run are the ones in that checkout, and nothing updates it. A checkout that nobody pulls keeps running an old version, so a fix merged upstream does not take effect locally. At the start of a Skill (`modules/phase-banner.md`), Wholework compares the checkout's `HEAD` with its upstream branch and warns when the upstream is ahead.

     **Fix**: Update the checkout when no other Claude Code session is using it (running scripts change under such a session), then start a new session so the updated `SKILL.md` content is loaded (see "Skill Updates Not Reflected Mid-Session"):

     ```bash
     git -C /path/to/wholework pull --ff-only
     ```

     Wholework never pulls for you.

     **Notes**:

     - The comparison uses the upstream branch as of the last `git fetch` and makes no network access, so a checkout that has not been fetched for a long time can look up to date. Run `git -C /path/to/wholework fetch` now and then (for example from a scheduled job) to keep the warning accurate.
     - No warning appears for a marketplace install (not a git checkout), a detached HEAD, a branch without an upstream, or when the check cannot run. To silence it for a deliberately pinned checkout, run `git -C /path/to/wholework branch --unset-upstream`.
     ````

   - `docs/ja/guide/troubleshooting.md`: 上のセクションを日本語で足す (見出し `## Plugin ディレクトリが upstream より遅れている`、ラベルは既存に合わせて `**症状**` / `**原因**` / `**修正**` / `**補足**`、コード例は同一)。直し方の「スキル更新がセッション中に反映されない」への参照は日本語の見出しに合わせる
   - コミット前の自己検証 (Step 1-5 を終えた後): `bash -n scripts/check-plugin-staleness.sh`、`bats tests/check-plugin-staleness.bats tests/phase-banner.bats`、`bash scripts/check-forbidden-expressions.sh`、`git diff -U100000 origin/main...HEAD -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py` (スクリプト・モジュールに仮名・漢字が code fence と引用符の外に残っていないこと)、`grep -n "!" modules/phase-banner.md` (追加した行に半角 `!` が無いこと)

## Verification

### Pre-merge

- <!-- verify: rubric "wholework の Skill の開始時 (phase-banner など全 Skill が通る箇所) に、CLAUDE_PLUGIN_ROOT が git の checkout で upstream より遅れていれば、遅れのコミット数を含む警告を出す手順が書かれている。git の checkout でない場合と、数えるのに失敗した場合は、警告を出さずに続ける" --> 読み込み元の遅れを開始時に警告する手順がある
- <!-- verify: rubric "読み込み元の遅れを検出しても、自動で pull しないことが明記されている" --> 自動で pull しないことが書かれている

### Post-merge

- upstream より遅れた checkout を `--plugin-dir` で渡して Skill を実行すると、開始時に遅れのコミット数を含む警告が出る <!-- verify-type: manual -->

## Notes

### 設計判断 (Issue が Spec に委ねた 2 点) — Auto-Resolve Log

- **実装位置**: `modules/phase-banner.md` の LLM 手順 + 新規ヘルパー `scripts/check-plugin-staleness.sh`。`scripts/phase-banner.sh` は変更しない。理由: (a) Issue の実例は対話セッションの `/review` で、`/auto` の親セッションも自分のバナーで 1 回出す。(b) `run-*.sh` はヘッドレスで phase ごとに繰り返す。`--output-format json` の実行はラッパーのログに最終の `.result` だけを残す (`scripts/run-spec.sh` の `jq -r '.result // empty'`) ので、子セッションが途中で出した行はそこに届かない。`print_start_banner` に足すと全 Issue の全 phase に同じ 1 行が出る。(c) `print_start_banner` は 6 本の `run-*.sh` が source し (測定コマンド: `grep -ln "phase-banner.sh" scripts/run-*.sh`)、8 本の bats がモックしている (`grep -ln "phase-banner.sh" tests/*.bats` は 9 件で、`phase-banner.sh` 自身をテストする `tests/phase-banner.bats` を除いた 8 件) ので、足すと影響が広い。「共通モジュール化」は不要 (`modules/phase-banner.md` が既に Skill 共通の読み込み先)
- **fetch**: しない。ヘルパーは `git rev-parse` / `git rev-list` だけを使う読み取り専用・オフラインとし、最後に fetch した `@{u}` と比べる。理由: Issue が「ネットワークに出ない形」を既定と定めている。Skill の開始ごと (`/auto` は phase ごとに新しいセッション) のネットワーク往復・認証プロンプト・ハングの危険を避ける。fetch は `.git` (FETCH_HEAD と追跡 ref) に書くので、同じ checkout を共有する並行セッションとの競合を新たに持ち込む
- **盲点 (受け入れた制約)**: 誰も fetch していない checkout は、upstream が進んでいても `HEAD..@{u}` が 0 を返し、警告が出ない (実測: upstream が 3 進んだ状態で、fetch 前は 0、fetch 後は 3)。緩和はユーザー側の定期的な `git fetch` とし、`docs/guide/troubleshooting.md` に書く。盲点が実害になる場合の後続案は、環境変数などで有効にする opt-in の fetch (`timeout` / `gtimeout` の検出で有界化する。`scripts/resolve-preview-env.sh` に前例がある)。この Issue では足さない
- **出力契約**: ヘルパーは完成した文ではなく `behind=N upstream=U root=R` を出し、日本語の警告文はモジュールの code fence 内のテンプレートにする。理由: `scripts/` は英語、Skill の端末出力は日本語という言語規約 (`CLAUDE.md`) に合わせる。テストが文面でなく値を検証できる。`modules/steering-hint.md` の出力テンプレートと同じ形
- **1 会話 1 回の抑止**: `/auto` が `/triage` や `/verify` を同じセッションで呼ぶと、同じバナー手順を複数回通る。同じ警告を会話中に既に出していれば出さない、と書く (LLM 記憶に依存する緩い規則で、守られなくても害は 1 行の重複だけ)

### 却下した代替案

- **SessionStart hook (`hooks/hooks.json`)**: LLM 非依存で 1 セッション 1 回確実に出せ、`allowed-tools` の追加も要らない。却下: (a) AC1 は「Skill の開始時 (phase-banner など全 Skill が通る箇所) に警告を出す手順が書かれている」ことを求めており、phase-banner 側に手順が無い hook は rubric で PASS しにくい。(b) Wholework の Skill を使わないセッションでも、プラグインが有効なら発火する。(c) Issue の範囲 (Skill の開始時) を超える
- **モジュールに git コマンドを直書き**: ヘルパーを作らない案。却下: 8 件の `allowed-tools` に汎用の `git -C:*` / `git rev-list:*` を足すことになり、許可範囲が広がる (ヘルパー方式なら `check-plugin-staleness.sh` の 1 本に限られる)。toplevel 一致・整数検査・クォートを LLM が毎回正しく組み立てる保証が無く、bats で検証できない
- **HEAD のコミット日時 (経過日数) で代用**: ネットワーク不要で、未 fetch の checkout にも効く。却下: AC が求める「遅れのコミット数」と異なり、更新の少ない期間は誤警告になる
- **`.wholework.yml` のキー (off / local / fetch) で制御**: 抑止と fetch を 1 キーで解決できる。却下: 設定面の拡張 (`modules/detect-config-markers.md`・`scripts/check-config-schema.sh`・`docs/guide/customization.md`) が加わり、Issue の範囲を超える。抑止は `git branch --unset-upstream` (upstream 無し → 無出力) で足りる

### Issue 本文との相違 (light: 記録のみ)

- Issue は phase-banner を「全 Skill が通る箇所」と書くが、`modules/phase-banner.md` を読むのは 10 Skill 中 8 (`auto`・`code`・`issue`・`merge`・`review`・`spec`・`triage`・`verify`)。`/audit` と `/doc` は開始バナーを出さず、警告も出ない。AC の括弧書き (「phase-banner など」) の範囲として許容し、この 2 Skill にバナーを足すことは範囲外 (別 Issue)
- Issue は「marketplace から入れた場合は git の checkout でない」と前提する。この環境では `~/.claude/plugins/marketplaces/claude-plugins-official` が `.git` を持たず、前提と一致した。Wholework 自身の marketplace キャッシュ (`~/.claude/plugins/cache/saitoco-wholework/`) はこの環境に無く、未確認。もし `.git` と upstream を持っていても「checkout として扱う」だけで無害 (upstream が無ければ無出力)

### 実測と出所 (Uncertainty の解消記録)

- 環境: git 2.47.3、bash 5.2.37、Linux。実行日 2026-10-12。使い捨てリポジトリでの実測 (プローブは `.tmp/` に置いた未コミットのスクリプトで、再現はこの表の条件と、bats の各ケースで足りる)
- 公式ドキュメント (取得 2026-10-12): `https://git-scm.com/docs/gitrevisions` (`@{upstream}` / `@{u}` は `refs/remotes/R/X` の追跡ブランチを指す。upstream 未設定時の挙動は記載なし)、`https://git-scm.com/docs/git-rev-parse` (`--show-toplevel` は作業ツリーが無いとエラー)

  | 条件 | `git rev-list --count HEAD..@{u}` | 備考 |
  |---|---|---|
  | 同期済み | `0` (exit 0) | |
  | upstream が 3 進んだが未 fetch | `0` | 追跡 ref が古いので見えない (盲点) |
  | 上の状態で `git fetch` | `3` | |
  | ローカルだけ進んでいる | `0` | |
  | detached HEAD | exit 128 `fatal: HEAD does not point to a branch` | 無出力にする |
  | upstream 未設定 | exit 128 `fatal: no upstream configured for branch '...'` | 無出力にする |
  | リポジトリの中に入れ子になった普通のディレクトリ | 外側のリポジトリを照会する (`--show-toplevel` が外側を返す) | toplevel 一致の検査で弾く |
  | `--depth 1` の浅いクローンで upstream が 3 進んだ | `1` | 浅いクローンは下限値 (警告は出る) |

- プロトタイプ (`.tmp/` の未コミットのスクリプト) の検証結果: 上の参照実装で、同期済み・遅れ・diverged・ahead のみ・detached・upstream なし・非リポジトリ・入れ子・存在しない path・5000 文字の path・シンボリックリンク・空白/`"`/`$`/改行/多バイト文字を含む path (往復一致)、`CDPATH` 設定、偽 git (失敗・非数・空・負の件数)、git 不在、読み取り専用 (HEAD / 追跡 ref / status が不変)、スクリプト位置からの既定 root、の全ケースが期待どおり。実リポジトリでの所要時間は平均 8 ms (20 回、git 3 回呼び出しを含む)

### その他の判断

- **Size 再評価 (Step 18 の入力)**: 変更ファイル 15 件 (測定範囲は上の Changed Files と同じ) は軸 1 で XL (11 件以上)。ただし 10 件は copy-and-adapt の機械的な変更 (8 件の 1 行 `allowed-tools` 追加、2 件の翻訳ミラー) で、機能は 1 つ、新ロジックは小さな読み取り専用ヘルパー 1 本なので、軸 2 で 1 段階下げて L とする。前例: #1461 (モジュール変更に伴う 6 件の `allowed-tools` 更新を含む変更、Size L)
- **既存ファイルへの新規分岐ロジックの追加は無い** (新規スクリプトと、それを検証する新規 bats だけ)。そのため「既存スイートが PASS すること」に加える新規テストケースの要件は、上の `tests/check-plugin-staleness.bats` の一覧がそのまま満たす
- **コストが高い・取り消せない Step は無い** (`spec-approval-needed` の対象なし)。外部サービスへのログインを要する Step も無い
- **verify-type の確認**: Post-merge の manual AC は、`modules/verify-patterns.md` §11 の手順で置き換えを検討した。目的は実 Claude Code セッションで LLM 手順 (Step 4) が実際に走り、警告が出ること。`rubric` は手順が書かれていることを見るだけで、実行されることを見られず、`command` で実 LLM セッションを回すと非決定的で費用もかかる。`manual` を維持する
- **Post-merge の手動確認の手順 (ネットワーク不要)**: この Issue のマージ後の main を元にする。upstream 用のローカル bare とその checkout を作り、別クローンから upstream に 2 コミット足して、checkout 側で `git fetch` する (checkout が 2 コミット遅れで、`@{u}` が進んだ状態になる)。その checkout を `claude --plugin-dir` で読み込み、バナーを出す Skill (`/triage <N>` など) を実行して、バナーの直後に N=2 の警告 1 行が出ることを確認する

  ```bash
  git clone --bare <wholework の checkout> .tmp/stale-up.git
  git clone .tmp/stale-up.git .tmp/stale-plugin
  git clone .tmp/stale-up.git .tmp/stale-pusher
  git -C .tmp/stale-pusher commit --allow-empty -m "ahead 1"
  git -C .tmp/stale-pusher commit --allow-empty -m "ahead 2"
  git -C .tmp/stale-pusher push origin HEAD
  git -C .tmp/stale-plugin fetch
  claude --plugin-dir "$PWD/.tmp/stale-plugin"
  ```

- **言語規約**: `modules/phase-banner.md` の日本語は警告テンプレートの code fence 内だけ。`scripts/check-plugin-staleness.sh` は英語のみ。`docs/` の英語版は英語、`docs/ja/` は日本語 (`scripts/check-language-convention.py` の対象外)
- **worktree 内での呼び出し**: Skill が `${CLAUDE_PLUGIN_ROOT}` を展開した固定パスの単一コマンドとして実行するので、worktree isolation guard に拒否されない。`${VAR:-default}` のようなコマンド名の実行時計算は拒否される (本 Spec 作成中に確認済み) ので、モジュールにそういう形を書かない

## Code Retrospective

### Deviations from Design
- Implementation Steps 1-5 を Spec どおりに実装した。順序・内容の変更なし (Spec の Implementation Steps の更新は不要)
- 例外として、`bats` の `no git on PATH` テストは Spec の記述 (`PATH` に空ディレクトリだけを置いて `"$BASH" "$SCRIPT" "$REPO"` を実行) どおりでは動かなかった。`run` 自体が `mktemp` を PATH から探すため、127 で落ちる。`run --separate-stderr env PATH="$empty" "$BASH" "$SCRIPT" "$WORK"` に変えて、PATH を絞る範囲をスクリプトだけにした

### Design Gaps/Ambiguities
- Spec の bats 手順は、`run --separate-stderr` と `PATH=... run` を組み合わせると bats-core 内部の外部コマンド (`mktemp`) が PATH から消えることを想定していなかった。PATH を絞るテストは `env PATH=... cmd` の形でコマンド側に渡すのが確実
- この環境では `CLAUDE_PLUGIN_ROOT` が未設定だった。リポジトリ自体がプラグインのルートなので、スクリプトは worktree 内の相対パスで実行した
- この環境には `bats` と GNU `parallel` が無かった。`bats` はリポジトリ外の `/tmp/bats-tool-1519` に npm で入れて実行し、全スイートは `xargs -P 4 -n 15` で分割して実行した (136 ファイル、失敗 0)
- worktree isolation guard は、`for` ループ内の `sed -i` (変数でファイル名を渡す形) と `$(...)` を含む git 付きの複合コマンドを拒否した。ファイル名を直接並べた単一の `sed -i`、コマンドを分けた実行で回避できた

### Rework
- bats の `no git on PATH` テストを 1 回修正した (上記)。ほかに手戻りなし

### Verification Notes
- 新規テスト (`tests/check-plugin-staleness.bats`) はスクリプトの出力・終了コードを検証するもので、ファイル内容の文字列一致ではないため、「New Verification-Test Pre-implementation FAIL Check」の対象外 (該当なし)
- pre-merge の rubric 2 件は、名前付きの採点サブエージェント (`rubric-grader-1519-1` / `rubric-grader-1519-2`) で評価し、どちらも PASS。採点は返却済みで、停止対象は残らなかった

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective: 警告の実装位置と fetch の要否は Spec で決める旨の Auto-Resolve Log と、Background の事実確認の結果 / https://github.com/saitoco/wholework/issues/1519#issuecomment-6116710481
- 上記以外の新規コメントなし (`/code` 開始時点。`phase/ready` 付与 (2026-10-12T02:59:41Z) より後のコメントは 0 件)

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC は 2 件とも `[x]`、review 完了は organic (fallback ではない)、mergeable=clean・CI 成功のため、ゲートを通過して `--squash` でマージした (strategy は `resolve-merge-strategy.sh` で解決)
- 競合なし。リベースとテスト再実行は不要

### Deferred Items
- `GIT_DIR` 等の git 環境変数の無効化と bats 回帰ケースの追加は未対応 (review からの持ち越し)。必要なら別 Issue にする
- Post-merge の manual AC (遅れた checkout を `--plugin-dir` で渡して Skill を実行し、開始時に警告が出ること) は未確認

### Notes for Next Phase
- `/verify`: LLM 手順 (Step 4) が実セッションで走るかは manual AC の手順 (bare リポジトリ 1 つ + クローン 2 つ) で確認する
- `/verify`: `GIT_DIR` の件を改善提案として拾うかどうかを判断する

## review retrospective

### Spec vs. Implementation Divergence Patterns
実装は Spec の参照実装と 1 文字単位で一致し、変更ファイルの 15 件も Spec の Changed Files と一致した。唯一の乖離は、Spec のエッジケース表に「git の環境変数を継承するケース」が無かったこと (設計段階の漏れ)。Spec の入力軸は引数・パス・git の状態を網羅していたが、実行環境側 (継承される環境変数) の軸が抜けていた。

### Recurring Issues
同じ指摘が Parser/Validator Edge Case Pre-check の測定サブエージェントと、review-spec / review-bug x2 の計 4 体から重複して出た (測定結果をレビューサブエージェントに渡す設計のため、重複自体は想定どおり)。同種の指摘は他に無い。

### Acceptance Criteria Verification Difficulty
UNCERTAIN は無かった。rubric 2 件は文面で判定できた。manual の post-merge AC は、実セッションで LLM 手順が走るかを確かめる必要があり、マージ後の `/verify` に委ねる。
