# Issue #1546: run-*.sh: claude -p に渡す Skill 本文の ${CLAUDE_PLUGIN_ROOT} が解決されず、手順が飛ばされる

## Overview

`run-spec.sh`・`run-code.sh`・`run-review.sh`・`run-merge.sh`・`run-issue.sh` は、Skill の本文 (`skills/<name>/SKILL.md` の frontmatter を除いた部分) を生のプロンプトとして `claude -p` に渡す (#284)。この経路では本文中の `${CLAUDE_PLUGIN_ROOT}` が解決されず、Bash のコマンドも Read のパスも壊れる。これまではモデルが wholework の場所を探して補っていたため目立たなかったが、keio の #347・#352 では探索が数分〜十数分かかったり、見つからずに手順が飛ばされたりした。

方針は、wrapper が `claude -p` を起動する前に、次の 3 つを同じ 1 つの値 (`--plugin-dir` に渡すパスと同一の `PLUGIN_ROOT`) で行うことである。

1. **本文の置換 (A)**: `SKILL_BODY` の `${CLAUDE_PLUGIN_ROOT}` を `PLUGIN_ROOT` の実パスに置き換える。Claude Code が Skill の内容を読み込むときに行うインライン置換と同じことを wrapper が代行する。Bash のコマンドにも Read のパスにも効く
2. **環境変数の export (B)**: `CLAUDE_PLUGIN_ROOT` を `PLUGIN_ROOT` として export する。実行時に Read されるモジュール内の Bash コマンド (`${CLAUDE_PLUGIN_ROOT}/scripts/...`) が、シェルの展開で解決される
3. **プロンプトへの 1 段落の注記 (C)**: `Plugin root: <PLUGIN_ROOT>` と、変数名の意味、Read ツールに渡すパスはこの値に置き換えるべきことを書く。モジュール内の Read のパスは A でも B でも機械的には解決できないため、探索させないための情報として渡す

共通処理は新規の sourceable ヘルパー `scripts/plugin-root.sh` に置き、5 本の wrapper から `guard-prefix.sh` と同じ形で `source` する。各 wrapper の bats に、claude を stub して受け取ったプロンプトと環境を検証するテストを足す。

## Reproduction Steps

1. `run-spec.sh <N>` (他の 4 本も同じ構造) が、frontmatter を除いた `SKILL.md` の本文を `claude -p "$PROMPT" ... --plugin-dir "$(dirname "$SCRIPT_DIR")"` に渡す。`run-*.sh` に `CLAUDE_PLUGIN_ROOT` への参照は無い
2. 起動したセッションの Bash ツールで `printenv CLAUDE_PLUGIN_ROOT` を実行すると、何も出力されず終了コード 1 になる。同じセッションで wrapper が渡した `ANTHROPIC_MODEL`・`WATCHDOG_TIMEOUT`・`OUTPUT_FORMAT_JSON`・`EMIT_PHASE_NAME` などは見える (本 Spec を作成したセッション自体が `run-spec.sh 1546` の起動で、この状態を実測した)
3. 手順どおりの `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh ...` は `/scripts/gh-label-transition.sh ...` に展開されて失敗し、`Read ${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` は `File does not exist` になる (Read ツールを同じ文字列で呼んで実測)
4. 最小の再現 (Claude Code 2.1.310): `env -u CLAUDECODE claude -p 'Run this exact bash command and print its raw output only: printf "[%s]\n" "${CLAUDE_PLUGIN_ROOT:-UNSET}"' --model haiku --plugin-dir <checkout> --allowedTools 'Bash(printf:*)'` の出力は `[UNSET]`

## Root Cause

公式ドキュメント (plugins-reference § "Where each variable resolves") によると、Claude Code は **Skill・command・agent の内容を読み込むときに**、本文中の `${CLAUDE_PLUGIN_ROOT}` をその場でパスに置換する。一方、この変数を Bash ツールの環境には**出さない** ("The variables aren't present in the environment of commands Claude runs through the Bash tool")。`run-*.sh` は context: fork の問題 (#284) を避けて本文を生のプロンプトとして渡すので、置換の経路を通らず、環境変数もどこからも供給されない。

実測 (Claude Code 2.1.310、2026-10-25) で、修正方式の前提を確かめた。

| 確認した内容 | 結果 |
|---|---|
| `--plugin-dir` のみで起動した Bash ツールの `${CLAUDE_PLUGIN_ROOT:-UNSET}` | `[UNSET]` |
| `CLAUDE_PLUGIN_ROOT=/opt/probe-plugin-root` を渡して `--plugin-dir` 付きで起動した Bash ツールの値 | `[/opt/probe-plugin-root]` (渡した値が届き、`--plugin-dir` に上書きされない) |
| `-p` のプロンプトに書いた `[${CLAUDE_PLUGIN_ROOT}/modules/a.md]` (環境変数あり・なしの両方) | そのまま返る (プロンプト本文は置換されない) |
| Read ツールに `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` を渡した結果 | `File does not exist` (展開されない) |

したがって、A だけでは実行時に Read されるモジュール内の Bash コマンドが、B だけでは本文の Read パスが、解決されない。A と B の併用が必要で、モジュール内の Read パスだけは機械的に解決できないため C で補う。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: Skill 本文から Read されるモジュール内の参照の扱いを `/spec` の調査項目にした、observation の `event=auto-run session=next` の付与、受入条件の追加、triage 結果 (Size M。5 本が個別に膨らめば `/spec` で見直す余地あり) / https://github.com/saitoco/wholework/issues/1546#issuecomment-6391910619

## Changed Files

測定範囲: リポジトリ内で変更するファイル (本 Spec 自身を除く)。既存ファイルの変更 16 件、新規 2 件の計 18 件で、翻訳ミラー (`docs/ja/`) 2 件を含む。同期候補の掃引は `grep -rl -- "<keyword>" docs/ tests/ scripts/ modules/` (件数は `docs/spec/` などの履歴を含む全体)。

- `scripts/plugin-root.sh`: 新規。sourceable ヘルパー (`expand_plugin_root_placeholder`・`plugin_root_note`)。`chmod +x` してから `git add` する。bash 3.2+ 互換 (`mapfile`・連想配列・`${var,,}`・`${var//pat/rep}` を使わない。macOS の CI は `bash -n` を全 `scripts/*.sh` に掛ける)
- `scripts/run-spec.sh`・`scripts/run-code.sh`・`scripts/run-review.sh`・`scripts/run-merge.sh`・`scripts/run-issue.sh`: ヘルパーの `source`、`PLUGIN_ROOT` の定義と `CLAUDE_PLUGIN_ROOT` の export、`SKILL_BODY` の置換、`PROMPT` への注記の挿入、`--plugin-dir` を `PLUGIN_ROOT` に統一 (計 `PROMPT=` 6 か所、`--plugin-dir` 10 か所。詳細は Implementation Step 2)。bash 3.2+ 互換
- `tests/plugin-root.bats`: 新規。ヘルパー単体のテスト
- `tests/run-spec.bats`・`tests/run-code.bats`・`tests/run-review.bats`・`tests/run-merge.bats`・`tests/run-issue.bats`: `setup()` にヘルパーのコピーを足し、解決を検証する新規テストを足す (AC2)
- `tests/run-code-mergeability.bats`: `setup()` にヘルパーのコピーを足すだけ (新規テストは足さない。`run-code.sh` を `WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` で実行するので、コピーが無いと `source` で全テストが落ちる)
- `modules/execution-context.md`: 「Fork Context」の制約表に `${CLAUDE_PLUGIN_ROOT}` の行を足し、末尾の Callers に `scripts/plugin-root.sh` の項を足す
- `docs/structure.md`: Key Files の「Skill runners」に `scripts/plugin-root.sh` の項を足す [Steering Docs sync candidate]
- `docs/tech.md`: Architecture Decisions の「Plugin directory distribution」に、wrapper 起動の headless セッションでは wrapper が解決する旨を 1〜2 文足す [Steering Docs sync candidate]
- `docs/ja/structure.md`・`docs/ja/tech.md`: 上の 2 件を日本語で反映する (`docs/translation-workflow.md` の同期手順。コードフェンス数の一致も確認する) [Steering Docs sync candidate]

合計 18 ファイル (スクリプト 6、テスト 7、モジュール 1、ドキュメント 4)。

**同期候補の掃引と「変更不要」の裏取り**:

- [Steering Docs sync candidate] keyword "run-spec.sh" skipped: matched 161 files (no discriminating power)。同様に "run-code.sh" 289、"run-review.sh" 207、"run-merge.sh" 171、"run-issue.sh" 121、"guard-prefix.sh" 27、"execution-context.md" 34 件でいずれも 8 件を超えるため掃引しない
- `plugin-root.sh`・`expand_plugin_root_placeholder`・`plugin_root_note` (この Issue が導入する名前): 一致 0 件。衝突しない。`PLUGIN_ROOT`・`PLUGIN_ROOT_NOTE` も `scripts/*.sh` に既存の同名変数が無い
- [Listing-side sub-check] 発火する (新規ファイルを足すため)。候補は `ssot_for: directory-layout` を宣言する `docs/structure.md` と、ルートの `README.md`。`docs/structure.md` は Scripts の項を足す (Directory Layout の木は `scripts/` を総称で書き、ファイル数のコメントも無いので木は変更しない)。`README.md` は `grep -nE 'guard-prefix|run-spec|run-code|scripts/' README.md` が 0 件でスクリプトを列挙していないため変更しない
- [Outbound pointer sync candidate] 各 wrapper の冒頭コメントは `modules/orchestration-fallbacks.md#wrapper-retry-on-kill` などを指すが、指す先の内容はこの変更で変わらない。`docs/structure.md` の `guard-prefix.sh` の項が指す `modules/execution-context.md` § "Wrapper-Level Constraint Injection" は、新しい行の置き場所 (同じモジュールの Fork Context 表) と矛盾しない
- 既存テストの影響: `scripts/run-*.sh` を `WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` で実行するテストは上の 6 ファイルだけ (`grep -nE 'cp .*scripts/run-(spec|code|review|merge|issue)\.sh|bash .*run-...'` で他に無いことを確認。`tests/run-auto-sub.bats` は wrapper を mock し、`tests/ci-failure-classifier.bats`・`tests/assignee-check.bats` は `run-*.sh` の文字列を grep するだけ)。`run-review.bats`・`run-merge.bats` の worktree-recovery テストは `cp "$MOCK_DIR"/*.sh scripts/` で MOCK_DIR 全体を複製するため、`setup()` でヘルパーを MOCK_DIR に置けば追加の対応は要らない
- `docs/guide/troubleshooting.md` L65 (と `docs/ja` の対応行): 「`${CLAUDE_PLUGIN_ROOT}` は Claude Code が自動設定する」と書かれている。公式ドキュメントによると Bash ツールの環境には出ないので、もともと不正確な記述だが、対話セッションの導入手順の話でこの Issue の範囲外のため変更しない (Notes に既存の不正確さとして記録)
- 履歴 (`docs/spec/`・`docs/reports/`・`docs/sessions/`): 変更しない。`docs/migration-notes.md`: 既存スクリプトの CLI・フラグ・引数順の変更が無いので対象外

## Implementation Steps

1. **`scripts/plugin-root.sh` と `tests/plugin-root.bats` を新規作成する** (→ AC1, AC2, AC3)
   - ヘッダは `scripts/retry-on-kill.sh` と同じ形にする (`# sourceable helper — do not execute directly`、`# bash 3.2+ compatible: no associative arrays, no mapfile`)。理由 (`claude -p` に本文を生で渡すと置換されない、Issue #1546)・関数の契約・fail-open の方針を英語のコメントで書く
   - `expand_plugin_root_placeholder TEXT ROOT`: TEXT の `${CLAUDE_PLUGIN_ROOT}` を**リテラルとして**すべて ROOT に置き換えて stdout に出す。完全一致の `${CLAUDE_PLUGIN_ROOT}` だけが対象で、`$CLAUDE_PLUGIN_ROOT` (波括弧なし) や `${CLAUDE_PLUGIN_ROOT:-}` は変えない。常に終了コード 0
   - 実装の核は awk の `index`/`substr` ループにする (正規表現を使わない)。ROOT は `-v` ではなく `ENVIRON` で渡す (`-v` はバックスラッシュを解釈する)。`${var//pat/rep}` は使わない: bash 5.2 の `patsub_replacement` で ROOT 中の `&` が一致文字列に置換され、bash 3.2 では置換側の引用符が残る不具合があり、どちらの版でも安全な書き方が無い

     ```bash
     expand_plugin_root_placeholder() {
       local text="$1" root="$2" out
       if out="$(printf '%s\n' "$text" | PLUGIN_ROOT_VALUE="$root" awk '
           BEGIN { pat = "${CLAUDE_PLUGIN_ROOT}"; plen = length(pat); root = ENVIRON["PLUGIN_ROOT_VALUE"] }
           {
             rest = $0; res = ""
             while ((i = index(rest, pat)) > 0) { res = res substr(rest, 1, i - 1) root; rest = substr(rest, i + plen) }
             print res rest
           }')"; then
         printf '%s' "$out"
       else
         echo "Warning: could not expand the plugin root placeholder; leaving the prompt text unchanged" >&2
         printf '%s' "$text"
       fi
     }
     ```
   - `plugin_root_note ROOT`: 2 行を出す。1 行目 `Plugin root: <ROOT>`。2 行目は「環境変数 CLAUDE_PLUGIN_ROOT がこのディレクトリに設定されている (Bash 用)。読んだファイル (モジュール、Skill 文書) がこのディレクトリをその変数名で参照していたら、Read ツールに渡すパスはファイルシステムを探さず上の値に置き換える」という趣旨の英文。**`${`...`}` の形でプレースホルダーを書かない** (プロンプトに未解決のプレースホルダーが残って見えるのを避ける)。バッククォート・`$`・二重引用符を含めず、単一引用符の `printf '%s\n'` で出す (#1213 の `GUARD_PREFIX` の注意と同じ)
   - **エッジケースの契約** (fail-safe に該当するため明記): 空文字列 → 空を出して 0。プレースホルダーが無い → 内容を変えない。行頭・行末・同じ行に複数・隣接 (`${CLAUDE_PLUGIN_ROOT}${CLAUDE_PLUGIN_ROOT}`) → すべて置換。ROOT に `&`・`\`・`|`・`$`・`"`・`'`・空白を含む → そのまま挿入 (特殊扱いしない)。日本語など多バイト文字と CRLF (`\r`) → 変えない。約 100 KB・数千行の入力 → 線形時間で終わる。awk が失敗した → stderr に警告を出し、元の TEXT を変えずに出して終了コード 0 (**fail-open**: ヘルパーが無かった修正前と同じ状態でフェーズを続ける。便宜的な補助処理の失敗でフェーズ全体を止めない)
   - `tests/plugin-root.bats` に次を入れる。ヘルパーは `bash -c 'source "$1"; ...' _ "$HELPER" ...` で隔離して呼ぶ: (a) 複数・隣接・行頭行末の置換 (b) 対象外の形 (`$CLAUDE_PLUGIN_ROOT`・`${CLAUDE_PLUGIN_ROOT:-}`) を変えない (c) ROOT の特殊文字 (d) 多バイト文字と CRLF の保持 (e) 空入力・プレースホルダー無し (f) **実際の** `skills/{spec,code,review,merge,issue}/SKILL.md` の本文 (frontmatter 除去後、wrapper と同じ `awk 'NR>1 && /^---$/{print NR; exit}'` で境界を決める) に特殊文字入りの ROOT で適用して、`${CLAUDE_PLUGIN_ROOT}` が残らない・置換後の ROOT の出現数が元のプレースホルダー数と一致する・行数が変わらない (g) fail-open: `$BATS_TEST_TMPDIR` に `exit 1` する偽の `awk` を置いて PATH の先頭に入れ、警告が stderr に出て元の TEXT が stdout に出て終了コード 0 になる (h) `plugin_root_note` の出力に ROOT が含まれ、`${CLAUDE_PLUGIN_ROOT}` のリテラルを含まない

2. **5 本の wrapper に組み込む** (after 1) (→ AC1)。各スクリプトで同じ形の変更をする。`source "$SCRIPT_DIR/guard-prefix.sh"` の直後 (`retry-on-kill.sh` を `source` するスクリプトではその直後) に次を置く。**挿入位置は `PROMPT=` の直前**で、`SCRIPT_DIR` のフォールバック (`run-code.sh`・`run-review.sh`・`run-merge.sh` の冒頭にある、削除済み worktree を指す `SCRIPT_DIR` を `$MAIN_REPO_ROOT/scripts` に差し替える処理) より後になるようにする

   ```bash
   source "$SCRIPT_DIR/plugin-root.sh"
   # Resolve ${CLAUDE_PLUGIN_ROOT} for this headless session (Issue #1546). The SKILL.md body is
   # passed as a raw prompt, so Claude Code's inline substitution never runs and it does not export
   # the variable to the Bash tool. PLUGIN_ROOT is also the --plugin-dir value below.
   PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
   export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
   SKILL_BODY="$(expand_plugin_root_placeholder "$SKILL_BODY" "$PLUGIN_ROOT")"
   PLUGIN_ROOT_NOTE="$(plugin_root_note "$PLUGIN_ROOT")"
   ```

   変更する箇所 (網羅):

   | スクリプト | `PROMPT=` | `--plugin-dir "$(dirname "$SCRIPT_DIR")"` → `--plugin-dir "$PLUGIN_ROOT"` |
   |---|---|---|
   | `run-spec.sh` | 1 か所 | 2 か所 (`AUTO_EVENTS_LOG` ありの JSON 分岐・なしの分岐) |
   | `run-code.sh` | 2 か所 (`EXTRA_FLAGS` あり・なし) | 2 か所 (同上) |
   | `run-review.sh` | 1 か所 | 2 か所 (`_run_claude_review_session` 内。関数は 2 回呼ばれうるが `PROMPT` と `PLUGIN_ROOT` は共有) |
   | `run-merge.sh` | 1 か所 | 2 か所 |
   | `run-issue.sh` | 1 か所 | 2 か所 |

   各 `PROMPT=` は `${GUARD_PREFIX}` と `${SKILL_BODY}` の間に空行を挟んで `${PLUGIN_ROOT_NOTE}` を入れる (`ARGUMENTS:` 行が最後に来る構造は変えない)。`CLAUDE_PLUGIN_ROOT` の export は 1 回で、`env -u CLAUDECODE ...` の行には足さない (JSON 分岐とそうでない分岐で食い違わない)。`PROMPT` 以外の処理 (リトライ、`reconcile-phase-state.sh`、イベント送出) は変えない

3. **bats を更新する** (after 1, 2) (→ AC2, AC3)
   - `tests/run-spec.bats`・`run-code.bats`・`run-review.bats`・`run-merge.bats`・`run-issue.bats`・`run-code-mergeability.bats` の `setup()` で、`guard-prefix.sh` をコピーする行の直後に `cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/plugin-root.sh" "$MOCK_DIR/plugin-root.sh"` を足す (**WHOLEWORK_SCRIPT_DIR mock addition**: コピーが無いと `source` の失敗で、これらのスクリプトを走らせる既存の全テストが落ちる)
   - AC の 5 ファイル (mergeability を除く) に、解決を検証する新規テストを足す。**既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケースを追加したうえでスイートが PASS すること**。テスト名に `$` とバッククォートを入れない (例: `plugin-root: CLAUDE_PLUGIN_ROOT placeholders in the prompt are resolved and exported to claude (Issue #1546)`)
     - (i) 本文に `${CLAUDE_PLUGIN_ROOT}` を含む SKILL.md フィクスチャ (frontmatter にも 1 つ入れて、除去されても問題ないこと、本文に Read のパス・Bash のコマンド・1 行に複数、を入れる) を `$BATS_TEST_TMPDIR/skills/<name>/SKILL.md` に書く。claude の stub を、そのテスト内で `$MOCK_DIR/claude` として書き直す: `-p` の次の引数 (プロンプト) と `--plugin-dir` の次の引数を、`export` したファイルパスへ書き出し、環境の `CLAUDE_PLUGIN_ROOT` を `${CLAUDE_PLUGIN_ROOT-__UNSET__}` の形で別ファイルに書く。テストの冒頭で `unset CLAUDE_PLUGIN_ROOT` する (開発者や CI の環境に依存させない)
     - (ii) 期待値は `EXPECTED_ROOT="$BATS_TEST_TMPDIR"` (`WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` の親)。検証: プロンプトに `${CLAUDE_PLUGIN_ROOT}` が残らない (`[[ "$prompt" != *'${CLAUDE_PLUGIN_ROOT}'* ]] || false`)・`Read \`$EXPECTED_ROOT/modules/...\`` と `$EXPECTED_ROOT/scripts/... 123` が含まれる・`Plugin root: $EXPECTED_ROOT` が含まれる・`--plugin-dir` の値と環境の `CLAUDE_PLUGIN_ROOT` がどちらも `EXPECTED_ROOT` と等しい
     - (iii) 継承された別の値の上書き: `export CLAUDE_PLUGIN_ROOT=/inherited/elsewhere` で起動しても、stub が見る値は `EXPECTED_ROOT` になる
     - (iv) `run-code.bats` だけ、上の (ii) を `--pr` 付きでも検証する (`EXTRA_FLAGS` がある側の `PROMPT=` を通すため)
   - この入力は修正前の wrapper では必ず FAIL する: 本文の `${CLAUDE_PLUGIN_ROOT}` がそのまま `claude` に渡り、`CLAUDE_PLUGIN_ROOT` も `__UNSET__` のままになる (AC2 の「修正前の状態では FAIL」)
   - 実行確認: `bats tests/plugin-root.bats tests/run-spec.bats tests/run-code.bats tests/run-code-mergeability.bats tests/run-review.bats tests/run-merge.bats tests/run-issue.bats` を実行し、続けて全スイートを並列で (`bats --jobs "$(nproc)" tests/`)。直列で長く走らせない (`modules/execution-context.md` の背景実行の規則)

4. **ドキュメントを同期する** (parallel with 3) (→ SHOULD の文書同期)
   - `modules/execution-context.md`: 「Fork Context」の表に行を足す。内容: wrapper 起動のセッションでは Claude Code が `${CLAUDE_PLUGIN_ROOT}` を解決しない (本文を生のプロンプトで渡すため置換が走らず、Bash ツールの環境にも出ない)。wrapper が `scripts/plugin-root.sh` で、本文の置換・`CLAUDE_PLUGIN_ROOT` の export・プロンプトへの注記を行う。実行時に Read されるモジュール内の Bash コマンドは export で解決し、Read のパスはモデルが注記を使って置き換える (機械的な解決ではない)。末尾の Callers に `scripts/plugin-root.sh` の項を足す (`scripts/guard-prefix.sh` の項と同じ書き方: このモジュールの読み手ではなく、Fork Context の行を実装する側)
   - `docs/structure.md`: Key Files の「Skill runners」に `scripts/plugin-root.sh` を足す (`scripts/guard-prefix.sh` の次)。1 行で、2 つの関数・5 wrapper が `source` すること・`modules/execution-context.md` § Fork Context への参照を書く
   - `docs/tech.md`: Architecture Decisions の「Plugin directory distribution」の末尾に 1〜2 文足す: `run-*.sh` が起動する headless セッションは本文を生のプロンプトで渡すので Claude Code の置換が走らず、wrapper が自分で解決する (`scripts/plugin-root.sh`、`modules/execution-context.md` § Fork Context)
   - `docs/ja/structure.md`・`docs/ja/tech.md`: 上の 2 件を日本語で反映し、コードフェンス数を英語版と一致させる

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-spec.sh・run-code.sh・run-review.sh・run-merge.sh・run-issue.sh のすべてで、claude -p に渡すプロンプトの中の ${CLAUDE_PLUGIN_ROOT} が wholework の場所 (--plugin-dir に渡すパスと同じ) に解決される。方法は、プロンプト本文の文字列を置き換える、CLAUDE_PLUGIN_ROOT を環境変数として渡す、またはその両方のいずれでもよいが、Bash ツールで実行するコマンドと Read ツールで読むパスの両方で解決される" --> `run-*.sh` から起動したセッションで、Skill 本文の `${CLAUDE_PLUGIN_ROOT}` が Bash のコマンドと Read のパスの両方で wholework の場所に解決される
- <!-- verify: rubric "tests/run-spec.bats・run-code.bats・run-review.bats・run-merge.bats・run-issue.bats のそれぞれに、claude を stub して受け取ったプロンプトと環境から ${CLAUDE_PLUGIN_ROOT} の解決結果を検証するテストが追加されている。テストは、未解決の ${CLAUDE_PLUGIN_ROOT} がプロンプトに残り、かつ環境変数も渡していない状態 (修正前の run-*.sh) では FAIL する入力を含む" --> `run-*.sh` 5 本それぞれについて、`${CLAUDE_PLUGIN_ROOT}` の解決を検証する bats テストが追加されており、修正前の状態では FAIL する
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Run bats tests\") | .state'" "SUCCESS" --> CI の bats テスト (Run bats tests) が通る

### Post-merge

- 次に `/auto` が `run-code.sh` または `run-review.sh` を経由するフェーズを含んで完了したとき、その実行の記録 (`docs/sessions/*/session.md` の該当 Issue の節、または wrapper のログ) に、モデルが wholework の場所を探す動き (ファイル検索、「`CLAUDE_PLUGIN_ROOT` が空」の報告) がなく、`review_incomplete_fallback: true` にもならずに、Skill の手順どおりスクリプトを実行して完了している <!-- verify-type: observation event=auto-run session=next -->
  - 観測する event: 次の `/auto` の完了 (`run-code.sh` または `run-review.sh` を経由するフェーズを含む)
  - 期待する出力の構造:
    - `docs/sessions/*/session.md` の該当 Issue の節、または wrapper のログに、wholework の場所を探す動き (ファイル検索、「`CLAUDE_PLUGIN_ROOT` が空」の報告) が無い
    - `review_incomplete_fallback: true` になっていない
    - Skill の手順どおりスクリプトが実行されて完了している

## Notes

### 方式の選択 (Issue が `/spec` の調査項目とした点の結論)

Issue の「Skill 本文から Read されるモジュール内の `${CLAUDE_PLUGIN_ROOT}` も同じく解決されるかを確かめる」に対する結論は次のとおり。出所: 公式ドキュメント https://code.claude.com/docs/en/plugins-reference § "Where each variable resolves" (取得日 2026-10-25)。実測は Claude Code 2.1.310 (`/home/saito/.local/share/claude/versions/2.1.310`、headless の `sdk-cli`) で 2026-10-25 に実施し、上の Root Cause の表に載せた。

| 参照の種類 | A (本文の置換) | B (環境変数の export) | C (注記) |
|---|---|---|---|
| SKILL.md 本文の Bash コマンド | 解決する | 解決する | — |
| SKILL.md 本文の Read のパス | 解決する | 解決しない | — |
| 実行時に Read されるモジュール内の Bash コマンド | 解決しない (本文ではない) | **解決する** | — |
| 実行時に Read されるモジュール内の Read のパス | 解決しない | 解決しない | モデルが値を知っている状態にする (機械的な解決ではない) |

採用しなかった案:

- **B だけ**: 本文の Read のパスが解決されず、Issue の AC1 (Bash と Read の両方で解決) を満たさない
- **A だけ**: モジュール内の Bash コマンドが空の変数に展開される。モデルが補う余地は残るが、それが今回の事象の原因
- **`--settings '{"env":{...}}'` で渡す**: AC2 が「stub した claude が受け取る環境」を検証する前提と合わず、JSON のエスケープ・設定のマージが増える
- **`claude-watchdog.sh env CLAUDE_PLUGIN_ROOT=... claude -p ...` で claude だけに渡す**: 次の副作用 (a) を避けられるが、全 wrapper の呼び出しの形が変わる。避けたい副作用は設計どおりの挙動の回復なので、払うコストに見合わないと判断した

### 副作用と注意点

- **(a) `claude-watchdog.sh` の休眠分岐が有効になる**: `scripts/claude-watchdog.sh` L139-141 は `CLAUDE_PLUGIN_ROOT` が設定されていて `scripts/observation-trigger.sh` が実行可能なら、watchdog が kill したときに `observation-trigger.sh --event watchdog-kill` を呼ぶ。wrapper の環境には今まで `CLAUDE_PLUGIN_ROOT` が無く、この分岐は事実上死んでいた (`modules/verify-classifier.md` の event 語彙表は `watchdog-kill` の発火元として `claude-watchdog.sh` を挙げている)。wrapper が export することで、設計どおりに動くようになる。影響は watchdog が kill した場合だけで、`2>/dev/null || true` で失敗は握りつぶされ、`observation-trigger.sh` 側にも 24 時間の冪等ガードがある。意図した範囲の挙動回復として受け入れ、この Issue では分岐のテストは足さない
- **(b) 説明用に `${CLAUDE_PLUGIN_ROOT}` を書いた行も置換される**: `skills/spec/SKILL.md` の本文 L765・L766・L775・L776 (Step 10 の「allowed-tools impact chain check」で、frontmatter の `allowed-tools` に書かれるリテラルの項を説明する行) は、置換後は絶対パスで読める。公式の置換は「Anywhere in the Markdown body」で同じ見え方になるため、対話セッションの `/spec` と同じであり、wrapper だけの新しい退行ではない。影響はこのチェックが助言の Notes を出す範囲に限られる。測定範囲: wrapper が渡す 5 本の本文 (frontmatter 除く) で、プレースホルダーを含み `allowed-tools`・「literal entry」・`<script-name>` のいずれかに触れる行。データとしての言及は spec の上記 4 行だけで、`code` の L303 は `check-allowed-tools.sh` の実行コマンド (解決されるべきパス) であり、`review`・`merge`・`issue` は 0 行。気になる場合の対処 (該当 4 行の書き換え) は別 Issue 候補で、`skills/spec/SKILL.md` の変更は本 Issue の範囲外
- **(c) プロンプトの大きさ (Linux の引数 1 個の上限)**: `claude -p "$PROMPT"` は単一引数で、Linux は 1 引数 131072 バイト (`MAX_ARG_STRLEN`) を超えると起動できない (`getconf ARG_MAX` は全体で 2097152)。測定範囲: 5 本の `SKILL.md` で frontmatter を除いた本文のバイト数 (`awk` で本文を取り出して `wc -c`)。本文 spec 88675、code 81416、review 92866、merge 29070、issue 70619。`GUARD_PREFIX` は約 2033 バイト。プレースホルダーの出現数 (本文のみ) は spec 48、code 55、review 46、merge 23、issue 48。置換で増えるのは出現数 × (ルートの長さ − 22)。例: 長さ 70 のルートで review は約 2.2 KB、長さ 200 で約 8.2 KB、長さ 400 でも約 17.4 KB 増える。これに注記の約 0.4 KB を足しても、最大の review の合計は長さ 70 で約 98 KB、長さ 200 で約 104 KB、長さ 400 で約 113 KB で、上限までの余裕は 18 KB 以上ある。ただし review の本文が今後大きく育つと余裕は減る (上限を超えると `claude` の起動時に引数が長すぎるエラーになる)。本 Issue では対策を足さず、この測定値を残すにとどめる
- **(d) `${CLAUDE_PLUGIN_ROOT}` を伴わない相対参照は範囲外**: 本文には `skills/<name>/<file>.md` を相対パスで指す行がある (測定範囲: 5 本の本文で `${CLAUDE_PLUGIN_ROOT}/skills/` を伴わずに `skills/<name>/<file>.md` を書く行。spec 8、code 2、review 9、merge 0、issue 8 行。説明や例を含む)。例は `skills/spec/SKILL.md` L156 の `read \`skills/spec/codebase-search.md\``。これは CWD 基準で解決されるため、wholework 自身のリポジトリでは動くが、ダウンストリームのリポジトリでは見つからず、同じ「場所を探す」事象を起こしうる。AC の対象 (`${CLAUDE_PLUGIN_ROOT}`) ではなく、注記は変数の意味だけを述べる (相対パスの基準をプラグインルートと言い切ると、wholework 自身を開発するときに worktree 側の編集対象を取り違えるおそれがある)。別 Issue の候補
- **(e) `spawn-recovery-subagent.sh` は対象外**: `agents/orchestration-recovery.md` のプレースホルダーは frontmatter の `tools:` 行だけ (本文には無い) で、スクリプトは frontmatter を除いて本文を渡すので影響を受けない
- **(f) premise マーカー**: Issue 本文の `<!-- premise: grep_count "CLAUDE_PLUGIN_ROOT" "scripts/run-spec.sh ..." -eq 0 -->` は、この修正で設計上偽になる。Issue の triage の記録のとおり、`/audit premise` は `phase/verify` 以降を評価しない
- **(g) 既存の不正確さ**: `docs/guide/troubleshooting.md` L65・`docs/structure.md` L320・`docs/tech.md` L35 は「Claude Code が実行時に `${CLAUDE_PLUGIN_ROOT}` を設定する」と書く。公式ドキュメントでは、Skill 等の内容へのインライン置換と、hook・MCP・LSP のプロセスへの export であり、Bash ツールの環境には出ない。`docs/tech.md` だけは本変更で wrapper の補足を足す。他の 2 つは対象外

### 数値の測定範囲 (Issue 本文との差)

Issue の「各 Skill が参照する回数 (code 54、spec 48、issue 48、review 45、merge 24)」は行数で、本 Spec の出現数 (code 55、spec 48、issue 48、review 46、merge 23) とは、frontmatter を含めるか・行数か出現数かが違うだけで、事実の食い違いではない。本 Spec は frontmatter を除いた本文の出現数を使った (wrapper が frontmatter を除いて渡すため)。

### fail-safe 判定と新規テスト

- 新規の `plugin-root.sh` は、失敗時に安全側 (元のテキストのまま) に倒れる設計 (fail-safe の基準 (c)) なので、Implementation Step 1 にエッジケースの契約を書いた。5 本の wrapper に新しい分岐は足さない (直線的な追加)
- 新規ロジックに対する新規テストケース: `tests/plugin-root.bats` の fail-open テストと実 SKILL.md への適用テスト、5 本の wrapper の解決テスト、継承された値の上書きテスト。既存スイートの PASS だけでは受け入れない

### bats のテスト入力の形式

- SKILL.md フィクスチャ: 先頭に `---` で囲む frontmatter (そこにも `allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/frontmatter-only.sh:*)` のように 1 つ入れる)、本文に `Read \`${CLAUDE_PLUGIN_ROOT}/modules/example.md\` and follow it.`、単独行の `${CLAUDE_PLUGIN_ROOT}/scripts/example.sh 123`、1 行に 2 つ含む行を入れる。単一引用符のヒアドキュメント (`<<'SKILL'`) で書き、シェルに展開させない
- claude の stub が書き出すもの: プロンプトの全文 (`-p` の次の引数をそのまま、末尾の改行を足さない)、`--plugin-dir` の値、環境の `CLAUDE_PLUGIN_ROOT` (未設定は `__UNSET__`)。書き出し先のパスは `export` した変数で stub に渡す (既存の stub が `CLAUDE_CALL_LOG` を渡す方式と同じ)
- `[[ ... ]]` の途中の検証には `|| false` を付ける (bash 3.2 でエラーにならない場合があるため。`scripts/check-bare-bracket-assertions.sh` の趣旨)

### allowed-tools impact chain check

`modules/execution-context.md` を変更するため Case 2 のゲートを実行した。追記内容は `scripts/plugin-root.sh` というパスを含むので、読み手を列挙した (`grep -rl 'modules/execution-context.md' skills/*/SKILL.md` → `skills/code/SKILL.md`, `skills/review/SKILL.md`)。どちらも `plugin-root.sh` を実行しない (wrapper が `source` するだけで、`skills/`・`modules/` に呼び出しが無いことを `grep -rl 'plugin-root.sh' skills modules` が 0 件で確認済み) ので、`allowed-tools` の追加は不要。新規の `scripts/*.sh` は 1 本だが、SKILL.md から呼ばれないため Case 1 も該当しない。

### Size の再評価

Changed Files は 18 件で、軸 1 の暫定は XL (11 件以上)。軸 2 は「原因が明確なバグ修正」と「既存パターンの横展開 (5 本の wrapper が同じ形)」で 1 段階下げ、「スクリプトのロジック変更」で上げる方向があるが、実質は機械的な横展開なので 1 段階下げて **L**。同型の先行例 #1213 (`guard-prefix.sh` を 5 本の wrapper に展開) も `/spec` で M から L に再評価された。triage の M は「5 本が個別に膨らめば `/spec` で見直す」前提だったので、Step 18 で Size を L に更新する (pr 経路、`/review --full`)。

### 外部仕様の確認と実測の手順

- 外部仕様: 公式ドキュメント (上記) を WebFetch で確認した。Context7 は使えなかった
- 実測: ネストした `claude -p` (haiku) を 4 回実行した。worktree の隔離ガードが `claude`・`env` を含むコマンドを拒否するため、`modules/worktree-lifecycle.md` の「Main-repo-only Steps inside a worktree session」の手順 (`ExitWorktree(keep)` → 実行 → `EnterWorktree(path)`) で main 側から実行した。リポジトリのファイルは変更していない
- 実測の入力は最小の文字列で、再取得に必要なものはこの Spec のコマンド列 (Reproduction Steps の 4) で足りる

### 受入条件の補足

- Pre-merge の 3 件は Issue 本文の `## Acceptance Criteria > Pre-merge` から verify command を含めて原文のまま写した (件数は 3 と 3 で一致)
- Post-merge の observation (`event=auto-run`) は、`modules/verify-classifier.md` の event 語彙表に `auto-run` があることを確認した。Issue の 1 文が (a) 観測する event と (b) 期待する出力を既に含むので、Issue 本文は書き換えず、Spec 側にだけ 2 部構成 (Option A) の副項目を足した。`session=next` は宣言のみで挙動を変えない (この Issue は `skills/*/SKILL.md` を変更しないが、wrapper は呼び出しのたびに読み込まれるので、次の `/auto` で評価できる)

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1・2・3・4 を Spec のとおりに実装した (ヘルパー、5 本の wrapper、bats、ドキュメント同期)。`tests/run-review.bats`・`run-merge.bats`・`run-issue.bats`・`run-spec.bats` に足したテストは Spec の (i)〜(iii) の形で、`run-code.bats` だけ (iv) の `--pr` 側を足した

### Design Gaps/Ambiguities
- 実装開始時、この `/code` セッション自身が `CLAUDE_PLUGIN_ROOT` 未設定で起動していた (Issue が直す症状そのもの)。モジュールや script のパスはリポジトリのパスを自分で補って進めた。修正が入るまで、wrapper 起動のセッションでは同じ補いが毎回必要になる
- Step 4 (`gh-label-transition.sh 1546 code --assign`) をうっかり Step 11 のあとまで実行し損ね、PR 作成後に実行した。ラベルは `phase/code` になり最終状態は正しいが、遷移の順序は Spec 手順とずれた
- Step 3 の precondition 確認 (`reconcile-phase-state.sh code-pr 1546 --check-precondition`) は実行せず、Issue のラベルが `phase/ready` で Spec が存在することを直接確認して進めた (`OBSERVED_LABELS` は `["triaged","phase/ready"]`)

### Rework
- worktree の隔離ガードが、`cd`・ヒアドキュメント・`git diff` を連結した一括編集コマンドを拒否した。5 本の wrapper の編集は Edit ツールの個別呼び出しに切り替えた。以降、複数ファイルの機械的な編集は最初から Edit ツールで行う
- Confirmed pre-implementation FAIL for 11 new wrapper test(s): wrapper 5 本を `git stash push` で修正前に戻して新規の解決テストを実行し、すべて FAIL することを確認した (その後 `git stash apply` で復元し、自分のエントリだけ `drop` した)

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note。Spec の Changed Files 18 件と PR の変更ファイルが一致し、`PROMPT=` 6 か所・`--plugin-dir "$PLUGIN_ROOT"` 10 か所の網羅も Spec どおりだった。

### Recurring issues

Nothing to note。review-bug x2 は指摘 0 件で、sub-agent の結果はすべて起動呼び出しの戻りとは別に結果ファイルとメッセージで届いた (結果の取りこぼしや degradation なし)。

### Acceptance criteria verification difficulty

Nothing to note。Pre-merge の 3 件は PASS (rubric 2 件は /code で確認済み、CI は `Run bats tests` が SUCCESS)。UNCERTAIN なし。Post-merge の observation は `/verify` に任せる。

- 補足: `capabilities.workflow: true` の repo でも、非対話の headless 実行では Workflow の完了通知を受け取れないため static Task fan-out を使った。CONSIDER 2 件 (`docs/tech.md:35` の記述の食い違い、`plugin-root.sh` の 1 行内プレースホルダー数に対する 2 乗時間) は対応せず、`/verify` で必要なら Issue 化する。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC は 3 件すべて `[x]`、review-incomplete-fallback も無しで、ゲートを通過した
- マージ方式は `resolve-merge-strategy.sh` の結果どおり `--squash` を使った (競合なし、CI 成功)

### Deferred Items
- Post-merge の observation (次の `/auto` で `run-code.sh`・`run-review.sh` 経由のフェーズが探索なしで完了すること) は `/verify` で評価する
- `docs/tech.md` と `docs/structure.md` の「Claude Code sets `${CLAUDE_PLUGIN_ROOT}` at runtime」の限定表現への書き換えは別 Issue 候補

### Notes for Next Phase
- `/verify 1546` では Post-merge の observation (`event=auto-run`) を扱う
- `claude-watchdog.sh` の `watchdog-kill` 分岐が有効になる副作用は、テスト未追加のまま
