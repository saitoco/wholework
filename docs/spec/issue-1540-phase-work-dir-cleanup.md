# Issue #1540: skills: 検証用の作業ファイルの置き場所と停止後の後片付けを全フェーズ共通で規定

## Overview

フェーズが検証のために作る大きな作業ファイル (リポジトリのコピー、`node_modules`、ビルド成果物、ブラウザ自動操作のプロファイル) について、置き場所・後片付けのタイミング・前回の残骸の扱いを、全フェーズ共通のルールとして `modules/` 配下の新規モジュールに定め、`/spec`・`/code`・`/verify` から参照させる。

ルールは文書だけにせず、削除を伴う操作を新規スクリプト `scripts/phase-work-dir.sh` に閉じ込める。LLM が `rm -rf` を直接実行する形では、前回の実行が残したファイルの削除が auto モードの分類器にブロックされうること、パスの組み立てミスが破壊的になりうることの 2 点が、ルールの実効性を損なうため (Notes「スクリプト化の判断」)。

採用する設計 (詳細は Notes「採用方針の判断」):

- 置き場所: `${XDG_CACHE_HOME:-$HOME/.cache}/wholework/work/<repo-key>/issue-<N>-<phase>/` (ディスク上、作業対象リポジトリの外、名前に Issue 番号とフェーズを含む)
- 後片付け: フェーズ終了時 (成功・失敗とも) に自分の分を消す。強制終了で残った分は次の実行が開始時に片付ける
- 前回の残骸: 開始時に探し、同じリポジトリの同じ Issue の同じフェーズの分は消してから始める。別の Issue・別のフェーズ・別のリポジトリの分は消さず、場所と大きさを警告する
- 専用の環境変数は追加しない (`XDG_CACHE_HOME` で場所を変えられる)

## Reproduction Steps

1. `/tmp` が tmpfs でメモリが限られる環境 (Proxmox の LXC コンテナ、メモリ 16GB) で、大きな検証を伴う Issue (keio #347、Size L、Next.js 16 系への更新) の `/spec` を `/auto` から走らせる
2. spec が検証のために、Next.js の版ごとにリポジトリのコピー (`node_modules` とビルドを含み各 1GB 前後) と Chrome のプロファイルを `/tmp` の下に作る
3. spec が途中で止まる (1 回目は watchdog 停止の exit 143、2・3 回目は親の Claude Code ごとの停止で、cgroup の記録から OOM killer によるものと見られる。コンテナの中からはカーネルのログが見えず、止められたプロセスの特定までは Issue 時点でできていない)
4. 作業ファイルは誰も片付けずに残る。再実行すると同様に作るため `/tmp` の使用が回ごとに増え、3 回目の時点で `/tmp` 14GB (89%)・メモリの空き約 3GB・スワップ満杯になり、cgroup の `memory.events` に `oom_kill 4` が記録される
5. 前提条件は本リポジトリの実行ホストでも再現する (測定: 2026-10-23、`stat -f -c %T /tmp` → `tmpfs`、`df -P /tmp` → 4194304 KiB 中 2488644 KiB 使用 (60%)。ホーム配下は `stat -f -c %T /home/saito` → `zfs` でディスク上)

## Root Cause

- **共通ルールが無い**: `modules/filesystem-scope.md` § Temporary Files は、Skill・module の手順が作る小さな一時ファイル (`.tmp/`) と、同梱スクリプト自身の private scratch (`$TMPDIR`) だけを扱う。大きな作業ディレクトリをどこに置くか、いつ消すか、止まったあとに残ったものを誰が片付けるかは定めていない。同 module は強制終了 (SIGKILL) で後片付けが走らないことを注記するだけである
- **Skill 側の参照が無い**: `modules/filesystem-scope.md` を参照している Skill は `skills/spec/SKILL.md` の rename 時の grep の 1 箇所だけで (Issue の premise `grep_count "filesystem-scope" "skills/" -eq 1` を実測で確認済み)、検証用の作業ディレクトリを作る場面からは参照されていない
- **既存の `.tmp/` 原則をそのまま当てはめられない**: 作業対象リポジトリの `.tmp/` にリポジトリのコピーを置くと、TypeScript の `include` やテストランナーの探索、lint のグロブがコピー側まで拾うおそれがある。一方 `docs/product.md` の Non-Goals は `/tmp/` を禁じており、代替の置き場所が定義されていないため、LLM は `/tmp` を選びやすい
- **修正方針の妥当性**: 置き場所を「ディスク上・リポジトリの外・名前から Issue 番号とフェーズが分かる」と定め、前回の残骸の掃除と自分の分の削除を、`allowed-tools` で事前許可されたスクリプトに閉じ込める。これで (a) 止まった次の実行が確実に片付ける、(b) 別の Issue・フェーズの分を誤って消さない、(c) 掃除の削除が分類器にブロックされない (Notes の Uncertainties 参照)、の 3 点が揃う

## Changed Files

- `modules/phase-work-dir.md`: 新規。置き場所・後片付けのタイミング・フェーズ開始時の掃除手順・失敗時の扱いを定める共通ルールの SSoT (英語。Pre-merge AC1〜AC3 の対象)
- `scripts/phase-work-dir.sh`: 新規。サブコマンド `path` / `create` / `sweep` / `clean`。置き場所の解決、入力検証、tmpfs ガード、前回の残骸の掃除、自分の分の削除を担う — bash 3.2+ 互換 (`mapfile`・連想配列・`${var,,}` を使わない)
- `tests/phase-work-dir.bats`: 新規。上記スクリプトの bats テスト (Implementation Step 2 に必要なテストケースを列挙)
- `skills/spec/SKILL.md`: Step 2 末尾に開始時の掃除段落、Step 6 の External spec dependency check の直後に使用場面の段落、Step 14 の先頭に終了時の削除段落を追加。frontmatter の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/phase-work-dir.sh:*` を追加
- `skills/code/SKILL.md`: Step 2 末尾に開始時の掃除段落、Step 6 末尾に使用場面の段落、Step 14 の先頭に終了時の削除段落を追加。`allowed-tools` に同エントリを追加 (frontmatter は 1 行のまま維持する。`tests/code.bats` が `head -6` で検査している)
- `skills/verify/SKILL.md`: Step 3 末尾に開始時の掃除段落 (使用場面の案内を含む)、Step 13 の先頭に終了時の削除段落を追加。`allowed-tools` に同エントリを追加。**本文マーカー `<!-- skill-body-lines: N -->` と `<!-- skill-body-sha: H -->` を最後の編集後に再計算して更新する** (`tests/verify.bats` と CI の `check-skill-body-hash` が検査する)
- `modules/filesystem-scope.md`: `### Allowed Base Paths` 表に 1 行、`### Temporary Files` 表に 1 行、`## Implementation Reference` に bullet 2 件を追加 (SSoT の整合: 現状の「Skill・module の手順が作る一時ファイルは `.tmp/`」と矛盾させない)
- `docs/product.md`: `## Non-Goals` の `/tmp/` 項目の `Scope:` 入れ子 bullet の直下に、大きな作業ファイルの例外を示す入れ子 bullet を 1 件追加
- `docs/ja/product.md`: 上記の日本語ミラー (`docs/product.md` と同一コミットで更新する)
- `SECURITY.md`: `### Local File Writes` に、新しい書き込み先 (キャッシュ配下の作業ディレクトリ) の bullet を 1 件追加 (翻訳ミラーなし)
- `docs/structure.md`: `### Modules` の Key modules に `modules/phase-work-dir.md`、`### Scripts` の `**Process management:**` に `scripts/phase-work-dir.sh` を追加 (Directory Layout の木は変更なし)
- `docs/ja/structure.md`: 上記の日本語ミラー (`docs/structure.md` と同一コミットで更新する)
- [Steering Docs sync candidate] keyword "Temporary Files" (4 件、判別力あり) の hit を全件確認済み: `docs/product.md`・`docs/ja/product.md`・`modules/filesystem-scope.md` は上記に含めた。残りは `docs/spec/issue-1492-*.md` (disposable) のみ — 測定: `grep -rl "Temporary Files" docs/ tests/ scripts/ modules/`
- [Steering Docs sync candidate] keyword "node_modules" skipped: matched 12 files (no discriminating power) — 測定: `grep -rl "node_modules" docs/ tests/ scripts/ modules/`
- [Steering Docs sync candidate] keyword "filesystem-scope.md" skipped: matched 11 files (no discriminating power、Spec #1492 の測定と同じ) — 新規名 `phase-work-dir` / `XDG_CACHE_HOME` は現状 0 件
- [Listing-side sub-check] 新規ファイルを追加するため発火。候補は `docs/structure.md` (`ssot_for: directory-layout`) と root `README.md`。`docs/structure.md` は上記に含めた。`README.md` は `modules/`・`scripts/` を列挙していない (`grep -n -E 'modules/|scripts/' README.md` が 0 件) ため変更不要
- [Outbound pointer sync candidate] `modules/filesystem-scope.md` が指す `docs/product.md` (Non-Goal) と、`docs/product.md` が指す `modules/filesystem-scope.md` はいずれも上記に含めた。`SECURITY.md` が指す `docs/guide/auto-mode-template.json` は本変更で内容が変わらないため対象外 (Notes の Uncertainties 参照)

## Implementation Steps

1. 新規モジュール `modules/phase-work-dir.md` を作成する (→ Pre-merge AC1, AC2, AC3)
   - 構成は `## Purpose` / `## Input` / `## Processing Steps` / `## Output` の 4 節 (Skill 開発の SHOULD 制約) に、`## Notes` と `## Callers (auto-maintained)` を加える。英語で書く (`scripts/check-language-convention.py` が `modules/` への CJK 混入を検出する)
   - `## Purpose`: 対象となる「大きな作業ファイル」を **repository copy, `node_modules`, build output, browser-automation profile** と例示付きで定義し、`/tmp` が tmpfs の環境ではファイルがメモリを使うこと、フェーズが途中で止まると残骸が累積して次の実行がメモリ不足で止まる連鎖 (keio #347) を述べる。ルールは `/spec`・`/code`・`/verify` に限らず全フェーズ共通であること (どのフェーズでも、検証のために大きな作業ファイルを作るなら同じ規則に従う) を明記する。小さな一時ファイル (`.tmp/`) と同梱スクリプトの private scratch は `modules/filesystem-scope.md` § Temporary Files が扱い、本モジュールの対象外と明記する
   - `## Input`: `ISSUE_NUMBER`、`PHASE_NAME` (例: `spec` / `code` / `verify`)
   - `## Processing Steps` に次の 4 小節を置く。**ルール 3 点 (配置)・2 点 (後片付け)・開始時の掃除の区別は、AC の rubric がそのまま照合できるよう、番号付きで明示的に書く**:
     - `### 1. Placement`: (1) **tmpfs など、メモリを使う場所 (`/tmp`、`$TMPDIR`、`/dev/shm`、`/run`) を使わず、ディスク上に置く** (2) **作業対象リポジトリのビルド・テスト・lint の走査対象に入らない場所に置く** — リポジトリのツリーの中 (メインのチェックアウトも worktree も、gitignore 済みの `.tmp/` も) は不可。理由: TypeScript の `include`、テストランナーの探索、lint / formatter のグロブは、ツールと設定によってはコピー側まで拾いうる (3) **作業ディレクトリの名前から Issue 番号とフェーズが分かる**: `issue-<N>-<phase>`。具体的な場所は `scripts/phase-work-dir.sh` だけが解決する (`<base>/<repo-key>/issue-<N>-<phase>`、`<base>` は `${XDG_CACHE_HOME:-$HOME/.cache}/wholework/work`、`<repo-key>` はメインのチェックアウトのパスから作る `<name>-<cksum>`)。サブディレクトリ (例: `repo-copy`、`browser-profile`) はフェーズが自由に切ってよい。自前の scratch を `$TMPDIR` に作るツール (Lighthouse の Chrome 起動など) は、そのコマンドだけ `TMPDIR=<作業ディレクトリ>/tmp` を付けて走らせる。大きな作業ファイルを作らずに worktree 内で検証できるなら、作らない
     - `### 2. Cleanup timing`: (1) **フェーズが終わるとき (成功・失敗のどちらで終わる場合も) に、そのフェーズが作った作業ファイルを消す**。使い終わった時点で早めに消してもよい。エラーで途中停止する経路でも消す (2) **強制終了 (watchdog 停止、OOM killer、クラッシュ) などで消せずに残った分は、次の実行が開始時に片付ける**。強制終了では終了時の削除が走らないため、これが保証になる
     - `### 3. Phase-start sweep`: 手順は `scripts/phase-work-dir.sh sweep <N> <phase>` の実行。(1) **同じリポジトリの同じ Issue の同じフェーズの分は、消してから始める** (同じ Issue の同じフェーズは並行して走らないので安全) (2) **別の Issue・別のフェーズ・別のリポジトリの分は消さず、場所と大きさを警告する** (並行して動いている別のセッションのものかもしれない)。警告は件数の上限 (20 件) を超えたら「ほか N 件」にまとめる。警告された場所は、LLM が自分の判断で削除しない。ユーザーに伝えるだけにする
     - `### 4. When the directory cannot be used`: スクリプトが 0 以外で終了した (場所を解決できない、tmpfs と判定された、権限・サンドボックスの制限、ディスクフル) 場合は、`/tmp`・`$TMPDIR`・`.tmp/` のどれにも逃がさない。コピーを要する検証は、worktree 内で行えるものはそこで行い、行えないものは UNCERTAIN (未検証) として Spec の Notes や retrospective に残す
   - `## Output`: `create` が表示する絶対パス、`sweep` の警告行、終了コード (0 成功 / 1 使い方の誤りまたは安全でない環境で何も触っていない / 2 削除の一部が失敗)
   - `## Notes`: (a) 置き場所の根拠 (リポジトリ内 `.tmp/` を使わない理由、XDG キャッシュを選んだ理由) (b) 強制終了では終了時の削除が走らず、次の実行の掃除が唯一の回収経路であること (c) 同じ Issue の同じフェーズへの排他は設けない (並行して走らない前提) (d) `.env` など秘匿情報をコピーしうるため、ディレクトリは所有者のみ (mode 700) で作る (e) スクリプトを経由する理由 (削除のブロック回避・検証・テスト) (f) `/spec`・`/code`・`/verify` 以外のフェーズ (`/review` など) も、大きな作業ファイルを作るなら同じ規則に従う。それらのフェーズへの `sweep` / `clean` 呼び出しの組み込みは別の変更で行う (本 Issue の AC は 3 つの Skill)
   - `## Callers (auto-maintained)`: 表に `spec` / `code` / `verify` の 3 行 (Direct Callers)。本モジュール内で `${CLAUDE_PLUGIN_ROOT}/scripts/phase-work-dir.sh` を示す場合は、`validate-skill-syntax.py` の `validate_modules_scripts_in_allowed_tools` が、本モジュールを参照する全 SKILL.md に `allowed-tools` の同エントリを要求する (Step 3 で満たす)
   - 「exhaustive」「すべて」と読める断定を表に付けない。付ける場合は Step 5 の機械的な照合を行う
2. (parallel with 1) 新規スクリプト `scripts/phase-work-dir.sh` と `tests/phase-work-dir.bats` を作成する (→ Pre-merge AC3 の掃除手順の実体、AC5)
   - インターフェース: `phase-work-dir.sh <subcommand> <issue-number> <phase>`、`-h` / `--help` は使い方を stdout に出して終了 0。ヘッダーコメントに Usage・環境変数・終了コード・bash 3.2+ 互換を書く。`set -euo pipefail`、`export LC_ALL=C`
   - **入力検証 (fail-safe critical: 削除対象を決める検証器)**。検証に通らない入力では何も作らず何も消さず、終了 1:
     - Issue 番号: `case "$1" in ''|*[!0123456789]*|0*) reject;; esac` かつ `${#1}` が 9 以下。空・0・先頭 0・負数・空白・改行・CR・全角数字・`../`・`;`・`>`・`"`・`$`・`*` を拒否する (`.tmp` 内のプローブで全件を実測済み)
     - フェーズ: 英小文字で始まり、英小文字・数字・ハイフンのみ、32 文字以内。`case "$1" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*|[!abcdefghijklmnopqrstuvwxyz]*) reject;; esac`。空・大文字・先頭ハイフン・先頭数字・`/`・`.`・`..`・空白・改行・CR・マルチバイト (全角英字を含む)・33 文字以上を拒否する (同上、実測済み)
     - エラーメッセージに入力を含める場合は `tr -c 'A-Za-z0-9._-' '?'` と `cut -c1-40` で無害化する (呼び出し元が LLM であり、制御文字やプロンプト注入をそのまま返さないため)
   - **場所の解決**: `<base>` は `$XDG_CACHE_HOME` が絶対パスならそれ、そうでなければ (空・未設定・相対パスは XDG 仕様に従い無効として無視) 絶対パスの `$HOME/.cache`、いずれも使えなければ終了 1 (`/tmp` へは決して逃がさない)。`<base>/wholework/work`。末尾の `/` は除去し、`/` そのもの、改行・CR を含む値、`..` の要素を含む値は終了 1
   - **`<repo-key>`**: `git rev-parse --git-common-dir` の指すディレクトリへ移動して `pwd -P` を取り、その親ディレクトリをメインのチェックアウトのルートとする (worktree からもメインのチェックアウトからも同じ値になる)。`git` が失敗したら `pwd -P` で代替。名前は `basename` を `tr -c 'A-Za-z0-9._-' '_'` で無害化し、`printf '%s' "$root" | cksum | cut -d' ' -f1` の値を `-` でつなぐ (例: `wholework-2600413697`)。`cksum` が空を返したら終了 1 (名前空間を保証できないため fail-closed)
   - **サブコマンド** (正常終了条件・error path を分岐ごとに規定する。タイマー・シグナルは使わない。`rm -rf` は完了まで待つ):
     - `path`: 対象 `<base>/<repo-key>/issue-<N>-<phase>` を stdout に出して終了 0。ファイルシステムは変更しない
     - `create`: (1) `<base>` の最も近い既存の祖先で `stat -f -c %T` を実行し、`tmpfs` または `ramfs` なら終了 1 (何も作らない)。`stat` が使えない環境 (macOS / BSD) は空文字になり、メモリ上ではないとみなす (best-effort) (2) 対象がシンボリックリンクなら終了 1 (3) `(umask 077; mkdir -p "$dir")` で作成し、失敗したら終了 1 (4) パスを stdout に出して終了 0。既に存在するディレクトリの内容は変更しない (冪等)
     - `sweep`: `<base>` が存在しなければ何も出さず終了 0。(1) 対象が存在すれば (シンボリックリンクはリンクだけ) 削除し、stderr に「前回の残骸を削除した」旨をパスと大きさ付きで 1 行出す。削除に失敗したら警告し、最後に終了 2 にする (2) `"$base"/*/issue-*` のうちディレクトリであり、対象でないものを列挙し、各行 stderr に「削除していない」「別の Issue・フェーズ・リポジトリのもので、並行して動いているセッションのものかもしれない」「パスと大きさ」を出す。20 件を超えたら残りは「ほか N 件」の 1 行にまとめる。決して削除しない (3) 終了 0 (1 の削除失敗のときは 2)
     - `clean`: 対象が存在しなければ何も出さず終了 0。存在すれば削除し (シンボリックリンクはリンクだけ。`chmod -R u+rwX` を先に試みる — 読み取り専用のツリーは素の `rm -rf` では残ることを実測済み)、失敗したら stderr に警告して終了 2 (再試行も別経路への逃がしもしない。次の実行の掃除が回収する)。兄弟のディレクトリには触れない
     - 未知のサブコマンド・引数の個数違反: 使い方を stderr に出して終了 1
   - **削除の安全不変条件**: 削除対象は検証済みの Issue 番号・フェーズと `<repo-key>` から再構築したパスだけで、削除前に `case "$target" in "$base"/*/issue-*) ;; *) 終了 1 ;; esac` で形を再確認する。`<base>`・`<repo-key>` ディレクトリ自体や、名前が一致しないものは決して消さない。シンボリックリンクは辿らない
   - **依存コマンド失敗時の方針** (fail-closed と fail-open の線引き): `git rev-parse` 失敗 → fail-open (`pwd -P` で代替。キーは名前空間にすぎない)。`cksum` 失敗 → fail-closed (終了 1)。`du` 失敗 → fail-open (大きさは `size unknown`)。`stat -f -c %T` 不可 → fail-open (ガード無効)。`rm` 失敗 → 終了 2 と警告のみで、再試行・権限昇格はしない。`chmod` 失敗 → 無視
   - 大きさの表示は `du -sk -- "$dir"` の KiB を `awk` で `NNN KiB` / `NNN MiB` / `N.N GiB` に整形する (1024 KiB 以上で MiB、1048576 KiB 以上で GiB)
   - **新規テストケース `tests/phase-work-dir.bats`** (名前は ASCII の英語のみ。`@test` に多バイト文字を入れるとテストが 0 件になる — #226。既存の流儀どおり `PROJECT_ROOT` を先頭で定義し、`setup()` で `XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"` と `HOME="$BATS_TEST_TMPDIR/home"` を設定、モックの `stat` (`$MOCK_DIR/stat`) を `PATH` の先頭に置いて `-f -c %T` に `${MOCK_FS_TYPE:-ext4}` を返し、tmpfs 判定を決定的にする。ホストの `/tmp` が tmpfs でも結果が変わらないようにするため):
     - `path` が `issue-<N>-<phase>` 形式のパスを出す (番号とフェーズが名前に含まれる) / `XDG_CACHE_HOME` が絶対パスならその配下 (`.../wholework/work/`) / 未設定・空・相対パスなら `$HOME/.cache/wholework/work/` / `HOME` も使えないときは終了 1 でファイルを作らない
     - `path` が worktree とメインのチェックアウトで同じ値になる (テスト内で `git init` と `git worktree add` を使う)。同名の別リポジトリでは別の `<repo-key>` になる
     - `create` がモード 700 のディレクトリを作りパスを出す / 再実行しても内容を壊さない / モック `stat` が `tmpfs` を返すと終了 1 でディレクトリを作らない / 対象がシンボリックリンクなら終了 1
     - `sweep`: 同じ Issue・同じフェーズの残骸を削除する / 別フェーズ・別 Issue のディレクトリは残し、パスと大きさ (`KiB` / `MiB` / `GiB` / `size unknown` のいずれかの書式) を警告する / 同名の Issue・フェーズでも別の `<repo-key>` のものは削除せず警告する / 残骸が無ければ無出力で終了 0 / 21 件以上の残骸で警告が 20 件に切られ「ほか N 件」の行が出る / `<base>` が無くても終了 0 / `issue-*` に一致しない名前のディレクトリとファイルには触れない
     - `clean`: 対象を削除する / 無くても終了 0 (冪等) / 兄弟ディレクトリを残す / 読み取り専用のツリーも消える / シンボリックリンクはリンクだけを消して指す先は無傷 / モック `rm` が失敗すると終了 2 で警告し対象が残る
     - 入力検証: Issue 番号が空・`0`・`01`・`-5`・`1 2`・改行付き・CR 付き・`../1`・`1;rm`・全角数字・10 桁のとき終了 1 で何も消さない / フェーズが空・大文字・先頭ハイフン・`a/b`・`..`・改行付き・多バイト・33 文字のとき終了 1 で何も消さない / 未知のサブコマンドと引数の個数違反は終了 1 / `--help` は終了 0
     - 無害化: 不正な入力を含むエラーメッセージに制御文字や元の長い入力がそのまま出ない
   - 既存スイートの PASS だけでなく、上記の新規テストケースを追加したうえでスイートが PASS すること (CI の `Run bats tests` が `tests/` 全体を実行する)
3. (after 1, 2) `/spec`・`/code`・`/verify` の `SKILL.md` を更新する (→ Pre-merge AC4, AC6)
   - 3 ファイル共通: frontmatter の `allowed-tools` に、既存の `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh:*` の直後へ `, ${CLAUDE_PLUGIN_ROOT}/scripts/phase-work-dir.sh:*` を追加する (3 ファイルとも当該エントリが存在することを確認済み)。frontmatter は 1 行のまま保つ
   - 挿入するのは既存 Step 内の段落だけで、見出しは追加しない (Step 番号の振り直しを避ける。`Step 2.5` のような小数も禁止)。半角の `!` を本文 (コードフェンスとインラインコードの外) に書かない。`$(...)` と `&&` を使わない単純なコマンドで書く (`/verify` は Step 冒頭で複合コマンドを禁じている)
   - 段落には、置き場所 (`create` が表示するディレクトリの下にだけ作る。`/tmp` に作らない)・後片付け (使い終わったら、終了時にも `clean`)・前回の残骸の扱い (`sweep` の警告をユーザーに伝え、別の分は削除しない) の 3 点と、`${CLAUDE_PLUGIN_ROOT}/modules/phase-work-dir.md` を読んで従う旨を含める。英語で書く
   - `skills/spec/SKILL.md`: (a) Step 2 の最後の段落 (`**Consume comments since the last phase ...**`) の直後、`### Step 3:` の直前に **Phase work directory sweep (start of phase)** の段落と `phase-work-dir.sh sweep $NUMBER spec` のコードブロック (b) Step 6 の `**External spec dependency check ...**` ブロックの直後 (`**Issue body vs. existing implementation conflict detection ...**` の直前) に、外部仕様や不確実性の検証でコピー・`node_modules`・ビルド・ブラウザのプロファイルが必要になったときの段落 (`create $NUMBER spec`) (c) Step 14 の見出し直後、既存の「Read ... worktree-lifecycle.md」の前に **Phase work directory cleanup (end of phase)** の段落と `clean $NUMBER spec`
   - `skills/code/SKILL.md`: (a) Step 2 の最後の段落 (`**Consume comments since the last phase ...**`) の直後、`### Step 3:` の直前に開始時の掃除 (`sweep $NUMBER code`) (b) Step 6 の最後の項目 (「4. If implementation approach is problematic ...」) の直後に使用場面の段落 (`create $NUMBER code`) (c) Step 14 の見出し直後、既存の「Read ... worktree-lifecycle.md」の前に終了時の削除 (`clean $NUMBER code`)。`tests/code.bats` の Step 14 テストは部分文字列と相対順序の検査なので影響しない
   - `skills/verify/SKILL.md`: (a) Step 3 の最後の段落 (`Record the ENTERED_WORKTREE variable ...`) の直後、`### Step 4:` の直前に開始時の掃除 (`sweep $NUMBER verify`)。verify command の実行やブラウザ検証で大きな作業領域が要るときの使い方 (`create $NUMBER verify`) もここに書く (b) Step 13 の見出し直後、既存の「Read ... worktree-lifecycle.md」の前に終了時の削除 (`clean $NUMBER verify`)
   - **`skills/verify/SKILL.md` の最後の編集のあとに**、マーカーを再計算して更新する: `wc -l < skills/verify/SKILL.md` の値を `<!-- skill-body-lines: N -->` に、`grep -v '<!-- skill-body-' skills/verify/SKILL.md | shasum -a 256 | cut -c1-8` の値を `<!-- skill-body-sha: H -->` に書く (どちらのマーカー行も行数は変わらず、ハッシュの入力からマーカー行は除かれるので、1 回の更新で収束する)
4. (parallel with 1, 2) 周辺文書を同期する (→ Pre-merge AC1 の「全フェーズ共通のルール」としての一貫性)
   - `modules/filesystem-scope.md`: (a) `### Allowed Base Paths` 表の末尾に `| Phase work directory | `${XDG_CACHE_HOME:-$HOME/.cache}/wholework/work/<repo-key>/issue-<N>-<phase>/`, resolved only by `scripts/phase-work-dir.sh` — see `modules/phase-work-dir.md` |` を追加 (b) `### Temporary Files` 表に、作成者「Skill / module procedure — large verification work files (repository copy, `node_modules`, build output, browser-automation profile)」、配置「the phase work directory (on disk, outside the repository)」、規則「Never `/tmp/` and not `.tmp/` ... see `modules/phase-work-dir.md`」の行を追加 (c) `## Implementation Reference` に `modules/phase-work-dir.md` と `scripts/phase-work-dir.sh` の bullet を 2 件追加。本ファイル内ではスクリプトを `scripts/phase-work-dir.sh` と書き、`${CLAUDE_PLUGIN_ROOT}` を付けない (付けると `skills/spec/SKILL.md` などに追加のチェックが波及するため。`skills/spec/SKILL.md` は本変更で `allowed-tools` を追加するので、付けても検証は通る)
   - `docs/product.md`: `## Non-Goals` の `/tmp/` 項目配下の `Scope:` bullet の直下に、入れ子 bullet を追加する: `  - Exception for large verification work files: repository copies, dependency installs (`node_modules`), build output, and browser-automation profiles that a phase creates go to the phase work directory (on disk, outside the repository, named by Issue number and phase), never `/tmp/`. Details: `modules/phase-work-dir.md``
   - `docs/ja/product.md`: 対応する入れ子 bullet を日本語で追加 (括弧は半角 + 前後に半角スペース): `  - 大きな検証用作業ファイルの例外: フェーズが検証のために作るリポジトリのコピー・依存関係のインストール (`node_modules`)・ビルド成果物・ブラウザ自動操作のプロファイルは、`/tmp/` ではなく、フェーズ作業ディレクトリ (ディスク上、リポジトリの外、名前に Issue 番号とフェーズを含む) に置く。詳細は `modules/phase-work-dir.md` を参照`
   - `SECURITY.md`: `### Local File Writes` の `$TMPDIR` bullet の直後に追加する: `- **`${XDG_CACHE_HOME:-~/.cache}/wholework/work/`** — large verification work files that phases create only when they need them (repository copies, `node_modules`, build output, browser-automation profiles), in one `issue-<N>-<phase>` directory per repository, Issue, and phase (owner-only permissions). A phase removes its own directory when it ends; the next run of the same Issue and phase removes what an interrupted run left behind, and reports (never deletes) directories left by other Issues, phases, or repositories`
   - `docs/structure.md`: Key modules の `modules/filesystem-scope.md` の直後に `- `modules/phase-work-dir.md` — SSoT for where phases place large verification work files (repository copies, `node_modules`, build output, browser-automation profiles), when they are removed, and how leftovers of an interrupted run are found and handled at phase start`、`**Process management:**` の `scripts/reclaim-stale-worktrees.sh` の直後に `- `scripts/phase-work-dir.sh` — resolve (`path`), create (`create`), sweep at phase start (`sweep`: removes the same repository / Issue / phase leftover, warns with path and size about every other directory and never removes it) and clean up (`clean`) the phase work directory `<base>/<repo-key>/issue-<N>-<phase>`; fail-closed input validation, owner-only permissions, refuses a tmpfs base`
   - `docs/ja/structure.md`: 上記 2 件の日本語ミラー (`modules/filesystem-scope.md` の行 (144 行付近) の直後と、`scripts/reclaim-stale-worktrees.sh` の行 (237 行付近) の直後)。`docs/translation-workflow.md` に従い、英語版と同一コミットで更新し、コードフェンス数の一致を確認する
5. (after 1, 2, 3, 4) 検証する (→ Pre-merge AC5, AC6 と全 AC の事前確認)
   - (a) 引用した識別子の実在を再確認する: `grep -n 'Temporary Files' modules/filesystem-scope.md`、`grep -n 'Local File Writes' SECURITY.md`、`grep -n 'reclaim-stale-worktrees' docs/structure.md docs/ja/structure.md`、`grep -n 'detect-foreign-worktree.sh' skills/spec/SKILL.md skills/code/SKILL.md skills/verify/SKILL.md`
   - (b) `bats tests/phase-work-dir.bats tests/verify.bats tests/code.bats tests/spec.bats tests/check-skill-body-hash.bats tests/validate-skill-syntax.bats` を実行する (この環境には bats 1.11.1 がある)。最後にスイート全体 `bats tests/` も実行する
   - (c) `python3 scripts/validate-skill-syntax.py skills/` と `bash scripts/check-allowed-tools.sh` で `allowed-tools` と本文の整合 (`validate_body_scripts_in_allowed_tools`、`validate_modules_scripts_in_allowed_tools`) を確認する
   - (d) `bash scripts/check-skill-body-hash.sh` で `verify/SKILL.md` のマーカーを確認する
   - (e) `bash scripts/check-translation-sync.sh` で `docs/product.md`・`docs/structure.md` が `IN_SYNC` であることを確認する
   - (f) `bash scripts/check-forbidden-expressions.sh` と、`git diff` を渡した `python3 scripts/check-language-convention.py` で、新規テキストに旧称と CJK の混入が無いことを確認する
   - (g) Callers 表の照合: `grep -rl 'modules/phase-work-dir.md' skills/*/SKILL.md` の結果が `spec` / `code` / `verify` の 3 件であり、モジュールの Callers 表と一致すること
   - (h) モジュールの本文に、AC1〜AC3 の rubric が求める記述 (大きな作業ファイルの 4 種、配置の 3 点、後片付けの 2 点、開始時の掃除の区別) が漏れなくあることを、rubric の文言と突き合わせて目視する

## Verification

### Pre-merge

- <!-- verify: rubric "wholework の共通モジュール (modules/ 配下) に、フェーズが検証のために作る大きな作業ファイル (リポジトリのコピー、node_modules、ビルド成果物、ブラウザ自動操作のプロファイルを含む) の置き場所のルールが書かれている。ルールは (1) /tmp のようにメモリを使う場所 (tmpfs) を避けてディスク上に置くこと、(2) 作業対象リポジトリのビルド・テスト・lint の走査対象に入らない場所に置くこと、(3) 作業ディレクトリの名前から Issue 番号とフェーズが分かること、の 3 点をすべて含む" --> 検証用の大きな作業ファイル (リポジトリのコピー、`node_modules`、ビルド成果物、ブラウザ自動操作のプロファイルなど) の置き場所のルールが、全フェーズ共通のルールとして書かれている。置き場所は、メモリを使わないディスク上で、作業対象リポジトリのビルドやテストの走査対象に入らない場所であり、名前から Issue 番号とフェーズが分かる
- <!-- verify: rubric "上記の共通ルールに、後片付けのタイミングとして (1) フェーズが終わるとき (成功・失敗のどちらで終わる場合も) に、そのフェーズが作った作業ファイルを消すこと、(2) 強制終了などで消せずに残った分は、次の実行が開始時に片付けること、の 2 点が書かれている" --> 後片付けのタイミングが書かれている。フェーズが終わるとき (成功でも失敗でも) は自分で作った作業ファイルを消し、強制終了などで残った分は次の実行が開始時に片付ける
- <!-- verify: rubric "上記の共通ルールに、フェーズの開始時に前の実行が残した作業ディレクトリを探す手順が書かれている。同じ Issue の同じフェーズの分は消してから始め、別の Issue や別のフェーズの分は消さずに場所と大きさを警告する、という区別が明記されている" --> フェーズの開始時に、前の実行が残した作業ディレクトリを探す。同じ Issue の同じフェーズの分は消してから始め、別の Issue や別のフェーズの分は (並行して動いている別のセッションのものかもしれないので) 消さずに場所と大きさを警告する
- <!-- verify: rubric "skills/spec/SKILL.md、skills/code/SKILL.md、skills/verify/SKILL.md の 3 つすべてが、フェーズの開始時、または検証用の作業ファイルを作る場面から、上記の共通ルール (置き場所・後片付け・前回の残骸の扱い) を参照している" --> `/spec`・`/code`・`/verify` のすべてが、フェーズの開始時、または検証用の作業ファイルを作る場面から、共通ルールを参照している
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Run bats tests\") | .state'" "SUCCESS" --> CI の bats テスト (Run bats tests) が通る
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Validate skill syntax\") | .state'" "SUCCESS" --> CI の Skill 構文チェック (Validate skill syntax) が通る

### Post-merge

- `/tmp` が tmpfs の環境で、リポジトリのコピーやビルドのような大きな検証用ファイルを作るフェーズが次に走ったとき、作業ファイルが `/tmp` ではなくルールで決めた場所に置かれ、フェーズが終わったあとに残っていない <!-- verify-type: manual -->
- そのようなフェーズが途中で止まったあと、同じ Issue の同じフェーズを再実行すると、前回の作業ファイルが開始時に片付けられ、メモリ不足で止まらずに完了する <!-- verify-type: manual -->

## Notes

### 採用方針の判断 (non-interactive auto-resolve)

Issue 本文は具体的な場所を `/spec` に委ねている (Issue Retrospective の「置き場所の条件」)。条件は 3 点: メモリを使わないディスク上、作業対象リポジトリのビルド・テスト・lint の走査対象に入らない、名前から Issue 番号とフェーズが分かる。ユーザー確認で決まった「全フェーズ共通」「同じ Issue の同じフェーズは消す、別の分は警告」「OOM の再現試験はしない」は変更しない。

| 候補 | 判断 | 理由 |
|------|------|------|
| 作業対象リポジトリ内の `.tmp/` | 不採用 | gitignore 済みでも、TypeScript の `include`、テストランナーの探索、lint / formatter のグロブは、ツールと設定によってはコピー側まで拾いうる (Issue 本文の指摘どおり。個々のツールの挙動は本 Spec では検証していない)。コピーを含むリポジトリのツリーの中に置く限り、条件 (2) を保証できない。リポジトリの外に出せば、ツールごとの設定に依存せず保証できる |
| リポジトリの兄弟ディレクトリ | 不採用 | 親ディレクトリの書き込み権限が環境依存。worktree からメインのチェックアウトの兄弟を指す解決も複雑 |
| `~/.wholework/work/` | 不採用 | `~/.wholework/` はユーザー設定 (`config.yml`、アダプタ) 用で、dotfiles として同期される可能性がある。数 GB の作業ファイルを混ぜるべきではない |
| **`${XDG_CACHE_HOME:-$HOME/.cache}/wholework/work/` (採用)** | 採用 | XDG Base Directory 仕様の「ユーザー固有の不可欠でないデータ」の置き場所で、再生成できる作業ファイルの意味と一致する。ディスク上、どのリポジトリの外でもある。複数リポジトリが同居しても `<repo-key>` で分かれる |

- **`<repo-key>`**: キャッシュはユーザー全体で共有されるため、リポジトリごとに名前空間を分ける。これが無いと、別リポジトリの同じ番号・同じフェーズ (keio #347 と wholework #347) を「同じ Issue の同じフェーズ」と誤認して消してしまう。メインのチェックアウトのパスから作るので、worktree からも同じ値になる
- **専用の環境変数 (`WHOLEWORK_WORK_DIR` など) は追加しない**: テストは `XDG_CACHE_HOME` で隔離でき、利用者も `XDG_CACHE_HOME` かシンボリックリンクで場所を変えられる。追加すると `docs/tech.md` § Environment Variables と `docs/ja/tech.md` の更新が波及する。必要になれば後続の Issue で追加する
- **`.wholework.yml` のキーも追加しない**: `modules/detect-config-markers.md` の表、`scripts/check-config-schema.sh`、`docs/guide/customization.md` の更新が波及し、Issue の範囲を超える
- **スクリプト化の判断** (Issue は「共通モジュールにルールを書く」としており、スクリプトは求めていない。追加する理由は次の 3 点):
  1. 公式 Docs (permission-modes、2026-10-23 取得) は、評価順を「allow / deny ルール → 作業ディレクトリ内の編集と読み取りの自動承認 → 分類器」とし、分類器の既定のブロックに「セッション以前から存在したファイルの不可逆な破壊」と「`/tmp` などの共有 scratch のワイルドカード・glob・経過時間による削除」を挙げる。前回の実行が残したディレクトリの削除はまさに「セッション以前から存在したファイル」の削除にあたり、LLM が `rm -rf` を直接実行すると `-p` 実行では分類器にブロックされうる (ブロックされた操作は実行されず、Claude は処理を続ける)。削除をスクリプトの中に閉じ込め、スクリプトの呼び出しを `allowed-tools` で事前許可すれば、この経路を避けられる (Docs は Skill の `allowed-tools` が allow ルールとして扱われるかを明記していないため、Uncertainties に残す)
  2. 削除の対象パスを検証済みの部品だけから再構築でき、`rm -rf "$VAR"` の変数が空になる類の事故を構造的に防げる
  3. bats で決定的にテストできる。文書だけのルールは、強制終了後の回収という最も重要な経路を検証できない
- **`run-*.sh` ラッパーへの掃除の組み込みは行わない** (範囲外): `/verify` にはラッパーが無い、`run-spec.bats` / `run-code.bats` が `WHOLEWORK_SCRIPT_DIR` のモックを使うため新スクリプト用のモック追加が波及する、Issue の AC は Skill からの参照を求めている、の 3 点。ラッパーで watchdog 停止 (exit 143) の直後に `clean` を呼ぶ案は、将来のフォローアップ候補

### Issue 本文と既存実装の整合

Background の事実主張を実装と照合し、一致した。乖離なし。

- 「`modules/filesystem-scope.md` を参照しているのは `/spec` の rename 時の grep の 1 箇所だけ」: `git grep -c 'filesystem-scope' -- skills/` → `skills/spec/SKILL.md:1` (premise `grep_count "filesystem-scope" "skills/" -eq 1` は成立)。本変更は 3 つの Skill から `modules/phase-work-dir.md` を参照するが、`filesystem-scope` の参照は増やさないので premise は変化しない
- 「`docs/product.md` の Non-Goals と `modules/filesystem-scope.md` § Temporary Files が `.tmp/` を定めている」: 両方に存在することを確認した (`docs/product.md` Non-Goals の `/tmp/` 項目と `Scope:` bullet、`modules/filesystem-scope.md` の `### Temporary Files` 表)
- 「強制終了 (SIGKILL) では後片付けが走らず、`.tmp/` に置いたものは残り続けると注記しているだけ」: `modules/filesystem-scope.md` の `Why private scratch is out of scope` 段落に同趣旨の記述があることを確認した

### 外部仕様の確認 (出所つき)

- XDG Base Directory Specification (出所: http://specifications.freedesktop.org/basedir/latest/ — `https://specifications.freedesktop.org/basedir-spec/latest/` から 301 で遷移。取得日時: 2026-10-23): 「`$XDG_CACHE_HOME` defines the base directory relative to which user-specific non-essential data files should be stored.」「If `$XDG_CACHE_HOME` is either not set or empty, a default equal to `$HOME`/.cache should be used.」「All paths set in these environment variables must be absolute.」「If an implementation encounters a relative path in any of these variables it should consider the path invalid and ignore it.」 → スクリプトは相対パスの `XDG_CACHE_HOME` を無視して `$HOME/.cache` に落とす
- Claude Code 公式 Docs (出所: https://code.claude.com/docs/en/permission-modes、取得日時: 2026-10-23。ページ末尾の約 1300 文字は未読): 評価順は「allow / ask / deny ルールが先、次に作業ディレクトリ内の読み取りと編集、それ以外は分類器」。`-p` 実行でブロックが閾値に達すると「the action doesn't run and Claude keeps working」(実行は止まらない)。Skill の `allowed-tools` の扱いと `soft_deny` という語はこのページの範囲では確認できなかった
- 実測 (この実行ホスト、2026-10-23): `stat -f -c %T /tmp` → `tmpfs`、`stat -f -c %T /home/saito` → `zfs`、`git rev-parse --git-common-dir` (worktree 内) → `/home/saito/src/wholework/.git` (絶対パス)。`df -P` の Filesystem 列は `/tmp` が `tmpfs`、`/` が ZFS のデータセット名。`du -sk -- docs` → `17928`。使い捨てのプローブで `case` による入力検証 (Issue 番号 19 件・フェーズ 21 件)、`umask 077` と `mkdir -p` の権限、シンボリックリンクの削除、読み取り専用ツリー、空グロブ、最も近い既存の祖先の探索を確認した (プローブは削除済み)
- 既存の GNU / BSD 判別は `uname` が `Darwin` かどうかで分岐する形 (`scripts/emit-event.sh`、`scripts/gh-graphql.sh`) だが、本スクリプトは `stat -f -c %T` の出力が `tmpfs` / `ramfs` かどうかだけを見る。BSD / macOS では `-c` が別の意味になり出力が `tmpfs` にならないため、`uname` の分岐なしで安全側 (メモリ上とはみなさない) に倒れる。既存パターンと検出方法が異なる理由はこの点 (検出対象が値ではなく特定の文字列だけ)

### fail-safe critical / 識別子検証

- fail-safe critical: **yes** (基準 (b): 入力検証で削除対象を受理 / 拒否する検証器を含み、基準 (c): 失敗時に安全側へ倒れる設計)。空 / 過大な入力、特殊文字 (`>`・`"`・改行・CRLF・マルチバイト)、依存コマンド失敗時の fail-open / fail-closed の線引きは Implementation Step 2 に規定した
- audit/investigation-type: **no** — 目的は新しい規則と実装の追加で、項目ごとの分類を後続プロセスが判断根拠として読む成果物ではない。ただし引用した既存の識別子 (`modules/filesystem-scope.md` § Temporary Files と `Why private scratch is out of scope`、`docs/product.md` Non-Goals の `Scope:`、`SECURITY.md` § Local File Writes、`scripts/emit-event.sh` と `scripts/gh-graphql.sh` の `stat` 分岐、`scripts/pre-merge-check.sh` の `mktemp -d`、`validate-skill-syntax.py` の関数名、`tests/verify.bats` と `tests/code.bats` の該当テスト) は、本 Spec の作成中に Read または grep で実在を確認済み。Step 5 (a) で再確認する

### allowed-tools impact chain

- Case 1 (新規 `scripts/*.sh`): `phase-work-dir.sh` を本文に書く `skills/spec/SKILL.md`・`skills/code/SKILL.md`・`skills/verify/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/phase-work-dir.sh:*` が必要 (Changed Files と Step 3 に反映済み)。ワイルドカードでの代替はしない
- Case 2 (`modules/*.md` 変更): 新規モジュール `phase-work-dir.md` がスクリプトを `${CLAUDE_PLUGIN_ROOT}` 付きで示す場合、reader (`grep -rl 'modules/phase-work-dir\.md' skills/*/SKILL.md` で列挙される `spec` / `code` / `verify`) の `allowed-tools` に同エントリが必要。上と同じ 3 ファイルで満たす。`modules/filesystem-scope.md` はスクリプトを `${CLAUDE_PLUGIN_ROOT}` なしで書くため、新たな波及はない
- `.claude/settings.json.template` の `permissions.allow` は `Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` と `Bash(${HOME}/.claude/plugins/cache/saitoco-wholework/wholework/*/scripts/*.sh *)` のワイルドカードを持つため、新スクリプトは追加なしで許可対象になる (変更不要を確認済み)。`.claude/` 配下の Changed Files は無く、`git add -f` は不要

### Uncertainties (実装前に確認する事項)

- **auto モードの分類器が、LLM による作業ディレクトリへのコピー・インストールをブロックする可能性**: 公式 Docs の評価順では、作業ディレクトリ外への書き込みは分類器に回る。Skill の指示で明示された操作は意図に沿うため通る可能性が高いが、保証はない。`-p` 実行ではブロックが続いても処理は止まらないため、Implementation Step 1 の `### 4. When the directory cannot be used` (コピー検証を諦め、worktree 内で行うか UNCERTAIN にする) が受け皿になる。Post-merge の manual 条件 (大きな検証用ファイルが規定の場所に置かれること) で実環境の挙動を観察する。ブロックが観測されたら `docs/guide/auto-mode-template.json` に許可ルールを足す後続 Issue を起票する (本 Issue では、least-privilege を保つテンプレートを根拠なく広げない)
- **Skill の `allowed-tools` が allow ルールとして分類器より先に評価されるか**: 公式 Docs の当該ページに明記がない。本リポジトリの全 Skill がスクリプトをこの方式で呼んでおり (例: `worktree-merge-push.sh`)、同じ前提に乗る。外れた場合も、スクリプトの中の `rm -rf` は分類器から見えない (見えるのはスクリプト呼び出しのコマンドラインだけ) ので、削除そのものはブロックされにくい
- **`stat -f -c %T` は GNU coreutils 専用のベストエフォート**: macOS / BSD ではガードが働かない (メモリ上とみなさない側に倒れる)。インシデントの環境は Linux。macOS の `/tmp` はディスク上であり、ガードが無くても同じ問題は起きない

### テスト

- bats 新規テストの入力形式: `setup()` で `XDG_CACHE_HOME` / `HOME` / `PATH` (モック `stat`) を設定する。`sweep` / `clean` の検証には、`path` サブコマンドで対象パスを取得し、その兄弟ディレクトリ (`.../issue-<M>-<phase>`、別の `<repo-key>`) を `mkdir -p` で作る。大きさの表示は ZFS などの圧縮 / スパース環境で `du` が実サイズより小さく出るため、具体的な数値ではなく書式 (`KiB` / `MiB` / `GiB` / `size unknown` のいずれか) だけを検査する
- 回帰ガードとして `tests/verify.bats` (マーカー 2 件)、`tests/code.bats` (frontmatter の `head -6`、Step 14)、`tests/check-skill-body-hash.bats`、`tests/validate-skill-syntax.bats` を実行する
- 既存のスクリプトにも bats にも `WHOLEWORK_SCRIPT_DIR` のモックを使って `phase-work-dir.sh` を呼ぶものは無い (呼び出し元は SKILL.md のみ) ため、モックの追加は不要
- 新規ロジックは新規スクリプトにあり、既存のスクリプト・モジュール・Skill に分岐を足すものではない (SKILL.md の追記は単純なスクリプト呼び出しの段落)。したがって "New test case requirement for new branch logic" の対象は新規テストファイル自体で、Step 2 に列挙した

### 範囲外の観察

- `scripts/pre-merge-check.sh` は `mktemp -d` (`$TMPDIR`) の下に ephemeral な detached worktree を作る。#1492 で同梱スクリプトの private scratch として Non-Goal の対象外とされており、本 Issue でも変更しない。チェックが依存関係をインストールする場合は大きくなりうるので、必要ならフォローアップ Issue で扱う
- `modules/lighthouse-adapter.md` の `lighthouse ... --chrome-flags="--headless --no-sandbox"` は、Chrome のプロファイルを既定で `$TMPDIR` に作る。本モジュールは「そのコマンドだけ `TMPDIR=<作業ディレクトリ>/tmp` を付ける」手順を示すが、アダプタ側の改修は範囲外
- 作業ディレクトリは別の Issue の完了後も、そのフェーズが再実行されない限り残る。開始時の警告で場所と大きさは見えるが、年齢による自動回収 (`scripts/reclaim-stale-worktrees.sh` のような) は本 Issue の範囲外

### verify-type タグの確認

Post-merge の 2 条件はどちらも `verify-type: manual` で、Issue Retrospective が「OOM の再現試験はしない。次に大きな検証を伴うフェーズが走ったときに観察する」と決めたもの。`modules/verify-patterns.md` §11 の決定手順で置換の可否を確認した結果、manual のまま維持する。

- 実行手段: 重い検証 (リポジトリのコピーとビルド) を要するフェーズを tmpfs の環境で実際に走らせ、途中で止め、再実行することは、MCP ツール・CLI・API では代替できない (環境と Issue の都合に依存する)
- 機械的な結果確認: `file_exists` / `file_contains` / `http_status` / `rubric` は、実行後のホストの状態 (作業ディレクトリの有無、メモリ不足の有無) を見るもので、ホスト外から確認できない。ルールの文書と、スクリプトの `path` / `create` / `sweep` / `clean` の挙動は Pre-merge の AC1〜AC3 と bats で確認済みになるため、残るのは実環境での end-to-end の観察だけである
- `observation` への振り替え: `modules/verify-classifier.md` の event 語彙に該当する名前付きイベントが無く (「次に大きな検証を伴うフェーズが走る」は語彙の外)、無理に振ると発火しない条件になる。`opportunistic` ("verify X when `/skill-name` is run" の形) にも当たらない

### Size 再評価と Simplicity rule

- Changed Files は実質 10 件 (新規 3 件、変更 7 件) に、翻訳ミラー 2 件 (`docs/ja/product.md`・`docs/ja/structure.md`) が付く。ミラーは機械的な追随で実質件数に数えない前例に従う (#1516、#1530)。軸 1 は L (6-10)。軸 2 は、スクリプトロジックの追加と複数 Skill にまたがる変更で +1、3 つの SKILL.md への同形の追記と既存パターン (`reclaim-stale-worktrees.sh`・`append-consumed-comments-section.sh` の形、#1492 の文書同期) の横展開で -1 となり相殺して **L**。triage 時点の M から変わるため、Step 18 で Size を更新する (route は M と同じ pr)
- Simplicity rule: Implementation Steps は 5 件で light の上限内。Pre-merge の検証項目は 6 件で上限 (5) を 1 件超えるが、Issue 本文の受け入れ条件を原文のまま転記する規則 (Verify command sync rule) により統合できない。Issue 本文との件数は一致している (6 件 = 6 件)

### `/code` へのメモ

- 追記文の言語: `modules/phase-work-dir.md`・`modules/filesystem-scope.md`・`skills/*/SKILL.md`・`scripts/phase-work-dir.sh`・`SECURITY.md`・`docs/product.md`・`docs/structure.md` は英語。`docs/ja/*` は日本語 (括弧は半角 + 前後に半角スペース)。`tests/phase-work-dir.bats` の `@test` 名は ASCII の英語
- 禁止表現チェック (`scripts/check-forbidden-expressions.sh`) は `skills/ modules/ agents/ tests/ docs/ scripts/` を走査する。旧称 (例: 大文字始まりの `Dispatch`) を新規テキストに書かない
- `skills/verify/SKILL.md` の編集は、Step 1 の自己整合性チェック (キャッシュされた本文とディスク上の本文の突き合わせ) が前提とするマーカーを必ず再計算する。順序を誤ると `tests/verify.bats` の 2 件と CI の `check-skill-body-hash` が落ちる
- フェーズ作業ディレクトリは `.tmp/` ではない。`/code` 自身がこのモジュールの実装中に大きな作業コピーを作る場面は想定しないが、作る場合は新モジュールのルールに従う

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (対象範囲を全フェーズ共通にした、前回の残骸は同じ Issue の同じフェーズだけ開始時に消し別の分は警告、OOM の再現試験はしない、置き場所の条件は /spec に委ねる、の確認と受け入れ条件の書き直し) / https://github.com/saitoco/wholework/issues/1540#issuecomment-6367144432
