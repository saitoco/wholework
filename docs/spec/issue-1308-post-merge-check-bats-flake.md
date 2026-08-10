# Issue #1308: tests/post_merge_check.bats: bats --jobs 並列実行時に FAIL するフレークを解消

## Overview

`tests/post_merge_check.bats` が `bats --jobs <N>` 並列実行時のみ非決定的に FAIL する。単体シリアル実行 (`bats tests/post_merge_check.bats`) では毎回 10/10 PASS するが、`--jobs 4` (このファイル単独の並列実行) でも再現する。`#1221` / `#1224` / `#1227` / `#953` / `#1278` / `#1157` など複数の先行 Issue で同一の flake が独立に観測され、いずれも「対象ファイルは自 Issue の変更対象外」として本 Issue #1308 へ調査・修正を委譲している。本 Spec では実機での再現実験により根本原因を特定し、`scripts/post_merge_check.sh` 側の修正方針を設計する。

## Reproduction Steps

1. `bats --jobs 4 tests/post_merge_check.bats` を実行する (本リポジトリの実行環境は macOS) — 10 件中 1〜2 件が非決定的に FAIL する。3 回連続実行した結果、いずれの回も `not ok 7 fail: gh issue reopen called when FAIL input given` (`tests/post_merge_check.bats:132`) が再現し、`--jobs 18` に上げた際には追加で `not ok 10 multiple issues: processed sequentially` (`tests/post_merge_check.bats:181`) も再現した。
2. `--print-output-on-failure` を付けて再実行すると、失敗時の `$output` 末尾に以下のいずれかが出現する:
   - `mktemp: mkstemp failed on /tmp/post-merge-comment-XXXXXX.md: File exists` (line 132 `fail:` テスト)
   - `scripts/post_merge_check.sh: line 90: /tmp/post-merge-acs-XXXXXX.txt: No such file or directory` (line 181 `multiple issues:` テスト)
3. 上記を切り分けるため、`tests/post_merge_check.bats` から独立した最小再現 (`.tmp/probe.bats`、4 並列で同一テンプレートに対し `mktemp` を呼ぶだけのテスト) を作成して実行したところ、4 並列のうち 1 件だけが成功しほかは同一の `File exists` で失敗した。成功した 1 件のログを確認すると、`mktemp /tmp/probe-shared-XXXXXX.txt` の返り値が `XXXXXX` を置換しない**リテラル文字列そのまま**であることを確認した (`ls -la /tmp/probe-shared-XXXXXX.txt` で実ファイルとして存在することも確認済み)。単独 (並列なし) で同じテンプレートを 1 回だけ実行した場合も同様に `XXXXXX` が置換されないことを確認した。

## Root Cause

`scripts/post_merge_check.sh` は 4 箇所 (2026-08-11 時点の行番号: 63, 80, 136, 154) で `mktemp /tmp/<prefix>-XXXXXX.<拡張子>` の形式を使ってテンポラリファイルを作成している。

```
63:        TMP_SRC=$(mktemp /tmp/post-merge-issue-body-XXXXXX.md)
80:    TMP_ACS=$(mktemp /tmp/post-merge-acs-XXXXXX.txt)
136:        TMP_COMMENT=$(mktemp /tmp/post-merge-comment-XXXXXX.md)
154:        TMP_COMMENT=$(mktemp /tmp/post-merge-comment-XXXXXX.md)
```

macOS (BSD) の `mktemp(1)` は man page に明記されている通り、**末尾 (trailing) の `X` の連続のみ**を置換対象とする。上記 4 テンプレートはいずれも `XXXXXX` の直後に `.md`/`.txt` という拡張子が続いており「末尾」ではないため、macOS の `mktemp` はこれをプレースホルダとして認識せず、**引数文字列をそのままリテラルなファイル名として使用する** (Reproduction Steps 3 で実機確認済み)。

このため:
- シリアル実行では、1 回の `post_merge_check.sh` 実行が「同じリテラルパスを作成 → 使用 → 削除」を完了してから次の実行が始まるため問題が顕在化しない。
- `bats --jobs <N>` 並列実行では、複数の `post_merge_check.sh` プロセス (bats 1.13 の `--jobs` はファイル内のテストケースもデフォルトで並列化する — `--no-parallelize-within-files` を指定しない限り) が**まったく同じリテラルパス**に対して同時に `mktemp` を呼び出す。最初の 1 プロセスは成功するが、他のプロセスは `mkstemp failed on ...: File exists` で失敗する。
- `scripts/post_merge_check.sh` は `set -euo pipefail` で実行されており (line 14)、`mktemp` の失敗をガードしていないため、`TMP_XXX=$(mktemp ...)` という代入コマンドの失敗がそのままスクリプト全体の非ゼロ終了を引き起こす (`VAR=$(cmd)` 形式の代入は `cmd` の終了コードを引き継ぐため `set -e` が正しく作動することを実機確認済み)。これが bats テストの `[ "$status" -eq 0 ]` を FAIL させる直接原因である。
- どの `mktemp` 呼び出しが競合に負けるかはプロセススケジューリング次第の非決定的事象であるため、Issue Background に記録された「FAIL 件数が実行毎に変動する (2 件 / 1 件)」非決定性とも整合する。`line 90` の `No such file or directory` は、`TMP_ACS` の `mktemp` 呼び出し自体が競合に負けて `set -e` により該当イテレーションより前で止まるケースと、他プロセスが同じリテラルパスを所有している間に `exec 3< "$TMP_ACS"` に到達し読み取り不能になるケースの両方で発生しうる、同一バグの別症状である。

**Issue Notes で調査対象として挙げられていた `WHOLEWORK_SCRIPT_DIR` / `PATH` 経由のモック解決経路については、切り分け実験 (`.tmp/probe.bats` で `$BATS_TEST_TMPDIR` を 4 並列出力してログ比較) により、`--jobs 4` 下でも `$BATS_TEST_TMPDIR` (ひいては `setup()` が生成する `$MOCK_DIR`) はテストごとに一意であることを確認し、原因ではないと判断した。**

**プラットフォーム依存性について**: GNU `mktemp` (coreutils) は `X` の連続が末尾でなくても正しく置換する拡張を持つため、CI の `bats` ジョブ (`.github/workflows/test.yml`、`ubuntu-latest`) では同じテンプレートでも真にランダムな 6 文字が生成され、偶然の衝突確率は無視できるほど低い。一方、本 Issue の Background に記録された再現、および本リポジトリの検証環境はいずれも macOS であり、macOS 上では上記メカニズムにより「低確率の偶発的衝突」ではなく「同一プロセス群が重なった時点でほぼ確実に衝突する」構造的バグとなっている。修正はこの非移植的なテンプレート形式そのものを排除するため、プラットフォームに依存せず両OSで有効である。

## Changed Files

- `scripts/post_merge_check.sh`: 4 箇所の leaf-level `mktemp /tmp/<prefix>-XXXXXX.<拡張子>` 呼び出し (`TMP_SRC`/`TMP_ACS`/`TMP_COMMENT`×2) を廃止し、スクリプト起動時に一度だけ作成する run-scoped な一時ディレクトリ (`mktemp -d`、既存の `scripts/pre-merge-check.sh:52` と同じ「テンプレート引数なしの bare `mktemp -d`」形式) 配下の固定ファイル名に置き換える。cleanup もループ内で `trap` を再登録する現行方式から、スクリプト冒頭で 1 回だけ登録する `trap 'rm -rf "$RUN_TMP_DIR"' EXIT` に統一する。bash 3.2+ compatible (新規に導入する構文は `mktemp -d` と `trap` のみで、いずれも同スクリプト/同リポジトリ内に既存の利用実績あり)。

## Implementation Steps

1. `scripts/post_merge_check.sh` の引数バリデーションブロック (line 33 の直後、`extract_manual_acs` 関数定義より前) に `RUN_TMP_DIR=$(mktemp -d)` と `trap 'rm -rf "$RUN_TMP_DIR"' EXIT` を追加する (→ AC1, AC2)
2. (after 1) line 63 の `TMP_SRC=$(mktemp /tmp/post-merge-issue-body-XXXXXX.md)` を `TMP_SRC="$RUN_TMP_DIR/issue-body-${NUMBER}.md"` に置き換える (単純なパス代入に変更、`mktemp` 呼び出し自体を削除)。既存の `TMP_SRC_CREATED` フラグと使用後の `rm -f "$TMP_SRC"` (line 70-72) はそのまま維持する (→ AC1, AC2)
3. (after 1) line 80 の `TMP_ACS=$(mktemp /tmp/post-merge-acs-XXXXXX.txt)` を `TMP_ACS="$RUN_TMP_DIR/acs-${NUMBER}.txt"` に置き換え、line 81 の per-loop `trap 'rm -f "$TMP_ACS"' EXIT` を削除する (Step 1 で登録した run-scoped trap が `$RUN_TMP_DIR` ごと cleanup するため不要になる)。AC 読み取りループ末尾の明示的な `rm -f "$TMP_ACS"` (line 126) はイテレーション間の即時クリーンアップとして維持する (→ AC1, AC2)
4. (after 1) line 136 と line 154 の 2 箇所の `TMP_COMMENT=$(mktemp /tmp/post-merge-comment-XXXXXX.md)` をいずれも `TMP_COMMENT="$RUN_TMP_DIR/comment-${NUMBER}.md"` に置き換える (→ AC1, AC2)
5. (after 2, 3, 4) コミット前に `bats --jobs 4 tests/post_merge_check.bats` と `bats --jobs 18 tests/post_merge_check.bats` をそれぞれ 5 回連続実行し、Pre-merge AC と同条件で全件 PASS することをローカルで確認する (→ AC1, AC2)

## Verification

### Pre-merge

- <!-- verify: command "for i in $(seq 1 5); do bats --jobs 4 tests/post_merge_check.bats || exit 1; done" --> `tests/post_merge_check.bats` が並列実行 (`--jobs 4`) で 5 回連続して全件 PASS する (非決定性が確認済みのため、単発 PASS では「安定して直った」ことの根拠として不十分)
- <!-- verify: command "for i in $(seq 1 5); do bats --jobs 18 tests/post_merge_check.bats || exit 1; done" --> より高い並列度 (`--jobs 18`) でも 5 回連続して全件 PASS する

### Post-merge

- 次回 `/auto` 実行 (event=auto-run) で CI (`bats --jobs $(nproc) tests/`) が走った際、`$GITHUB_STEP_SUMMARY` に `tests/post_merge_check.bats` 由来の Serial re-run セクション (docs/tech.md § CI bats Parallel/Serial Split 記載の切り分け機構) が出現しないことを確認する <!-- verify-type: observation event=auto-run -->

## Notes

- **Steering Docs sync candidate 確認済み・変更不要**: `docs/structure.md:210` および `docs/ja/structure.md:202` の `scripts/post_merge_check.sh` 説明行は「複数 Issue の post-merge 手動 AC をバンドル実行し P/F/S 入力を受け付け、phase/done 遷移 または reopen する」という外部から見た振る舞いを記述しており、本修正 (内部の一時ファイル配置のみの変更) では変わらないため更新不要と判断した (`grep -rn "post_merge_check.sh" docs/ tests/ scripts/` で全参照箇所を確認済み)。
- **同種アンチパターンの横展開確認**: `grep -rn 'mktemp [^-].*XXXXXX\.' scripts/` で `scripts/` 配下を確認したところ、非 trailing な `XXXXXX` + 拡張子サフィックスの `mktemp` テンプレートは `scripts/post_merge_check.sh` の 4 箇所のみであり、他スクリプトへの横展開は不要と判断した。
- **テスト側の変更は不要と判断**: `tests/post_merge_check.bats` の既存 10 ケースはいずれも一時ファイルの実パスやディレクトリ配置を直接アサートしておらず (`$GH_CALL_LOG` の内容や `$output` の文字列を検証するのみ)、`scripts/post_merge_check.sh` 側の内部実装変更のみで既存テストは無修正のまま安定 PASS するようになる想定。Issue の Pre-merge AC も新規ユニットテストの追加を要求していない (5 回連続 PASS という実行時検証のみ) ため、新規テストの追加は行わない。
- Issue 本文の `## Auto-Resolved Ambiguity Points` (5 回連続 PASS を要求する判定基準、根本原因ドキュメント化を追加 AC としない方針、`docs/tech.md` § CI bats Parallel/Serial Split 更新をスコープ外とする方針) はいずれも Issue body 側で解決済みであり、本 Spec で再検討すべき新たな曖昧性はない。

## Consumed Comments

- saito / MEMBER / first-class / `/issue 1308 --non-interactive` による refinement 完了後の Issue Retrospective コメント。Background への非決定性記録の明文化、Pre-merge AC のループ実行化、Post-merge observation AC 新設、Related Issues セクション新設などの反映内容の要約 (内容はすでに Issue 本文に反映済みで、本 Spec の設計に影響する新規情報はなし) / https://github.com/saitoco/wholework/issues/1308#issuecomment-5241844509
- code フェーズ (`phase/ready` ラベル付与以降): No new comments since last phase.

## Code Retrospective

### Deviations from Design

- N/A — Spec の Implementation Steps 1〜5 をそのままの順序・内容で実装した。

### Design Gaps/Ambiguities

- Step 8 (実装) の中で Spec Implementation Step 5 のローカル検証 (`--jobs 4`/`--jobs 18` を各 5 回連続実行) を先に済ませてから中間コミットしたため、Step 11 の「`git add <changed files>` → 規定フォーマットでコミット」に到達した時点で未コミットの差分が残っていなかった。規定フォーマット (`{prefix} <summary> (closes #N)`) は #996 の `concurrent_commit_detected` 誤検知防止と GitHub 自動クローズの両方にとって必須のため、既存コミットのメッセージのみを `git commit --amend` で訂正した (差分は変更せず、未 push のローカルコミットであることを確認した上で実施)。Step 8 で先にコミットする場合、その時点で規定フォーマットを直接使うほうが amend を避けられる。

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Root Cause / Changed Files / Implementation Steps をそのまま採用し、`scripts/post_merge_check.sh` の 4 箇所の `mktemp /tmp/<prefix>-XXXXXX.<拡張子>` を run-scoped な `mktemp -d` ディレクトリ配下の固定ファイル名に置換した。
- コミット前に Spec Implementation Step 5 が指定するローカル検証 (`bats --jobs 4`/`--jobs 18` を各 5 回連続実行) を実施し、Pre-merge AC の verify command そのものを事前実行して両方 PASS を確認した。

### Deferred Items
- Post-merge AC (次回 `/auto` 実行時の CI Serial re-run セクション非出現の確認) は `verify-type: observation` のため本フェーズでは未実施 — `/verify` フェーズに委譲。

### Notes for Next Phase
- `/verify` は Post-merge AC を CI 実行時の `$GITHUB_STEP_SUMMARY` 観測で判定する (`docs/tech.md` § CI bats Parallel/Serial Split の Serial re-run セクションが出現しないことを確認)。
- Pre-merge AC 2件は本フェーズで `[x]` 済み。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- triage が Pre-merge AC を単発実行から「5 回連続 PASS」のループ実行へ強化した判断は妥当だった。本 Issue のバグは非決定的レース (`--jobs` 実行時のみ、FAIL 件数が実行毎に変動) であり、単発 PASS では解消の根拠にならない。

#### spec
- Issue Notes が優先調査対象として挙げていた `WHOLEWORK_SCRIPT_DIR` / `PATH` 経由のモック解決経路は、切り分け実験 (`$BATS_TEST_TMPDIR` の 4 並列出力比較) により真因ではないと否定され、別方向 (macOS BSD `mktemp(1)` の trailing-X 制約) で真因に到達した。Notes の仮説に引きずられず実測で切り分けた点が有効に働いた。
- Changed Files が 1 ファイルのみと判明したため Size を M → XS へ再評価し、route を patch に確定した。事前見積り (M) と実態の乖離を spec フェーズで補正できている。

#### code
- Spec の Implementation Steps をそのままの順序で実装し、design deviation なし。
- Code Retrospective に記録された Design Gap (Step 8 の先行コミットにより Step 11 の規定フォーマット到達時に未コミット差分が残らず `git commit --amend` で訂正) は、既存 Issue #1134 (`code: Step 8 の粒度別コミットと Step 11 の closes-commit 要件の衝突を明文化`) がカバーする範囲であり、新規起票は不要。

#### review / merge
- patch route のため該当なし。

#### verify
- FAIL / UNCERTAIN は 0 件。Pre-merge 2 件は code フェーズで verify command 実行済みのため already-checked skip rule で SKIPPED。
- **横展開の確認**: 本 Issue が修正した非移植的テンプレート形式 (`mktemp <path>-XXXXXX.<ext>`) が他に残っていないことを `scripts/*.sh` 全体で確認した。現存する `mktemp` 呼び出しは 7 箇所 (`apply-run-fact-match.sh:158` / `claude-watchdog.sh:47` / `gh-issue-edit.sh:118` / `post_merge_check.sh:35` / `gh-pr-review.sh:84` / `pre-merge-check.sh:52` / `wait-ci-checks.sh:30`) で、いずれも引数なしの `mktemp` または `mktemp -d` であり、同種のバグは残存しない。横展開 Issue の起票は不要。

### Improvement Proposals
- N/A (code フェーズの Design Gap は既存 #1134 でカバー済み、横展開余地は上記の通り無し)
