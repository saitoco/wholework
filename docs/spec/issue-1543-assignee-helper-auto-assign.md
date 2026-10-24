# Issue #1543: scripts: Issue の担当状況の判定・assignee の付与と付け替えを行う共通処理と auto-assign 設定を追加

## Overview

#1542 (XL 親) の sub-issue ① (基盤)。Issue の担当状況の判定 (読み取りのみ)・未アサイン時の付与・実行ユーザーへの付け替えを、SKILL.md (#1544・#1545) からもスクリプトからも同じ形で呼べる共通処理として用意し、無効化の設定 `auto-assign` と、GitHub 状態に関するドキュメント (L0 surface・autonomy tier) を整える。各スキルへの組み込みは #1544 (`/issue`・`/spec`・`/code`) と #1545 (`/auto`) で行うため、この Issue ではスキルの手順 (SKILL.md) を変更しない。

要点:

- 新規スクリプト `scripts/gh-issue-assignee.sh` を追加する。サブコマンドは `status` (読み取りのみ)・`assign` (未アサインのときだけ付ける)・`reassign` (実行ユーザー以外を外して実行ユーザーに付け替える) の 3 つ。assignee の更新は REST の追加 API と置換 API で行い、`gh issue edit` は使わない (理由は Notes)
- `scripts/gh-label-transition.sh` に opt-in の `--assign` を追加する。ラベル更新が成功した後で、別の呼び出しとして `assign` を実行する。assignee の更新が失敗しても警告だけで遷移は成功とする。オプションなしの既存の呼び出しは挙動が変わらない
- `.wholework.yml` の `auto-assign` (既定 true) を追加する。false にすると `assign` / `reassign` の書き込みだけが止まり、`status` の判定は止まらない。autonomy tier には依存しない
- 後続の #1544・#1545 が使う呼び出し規約 (標準出力の語彙・終了コード・実行ユーザーを特定できないときの判定結果) を、スクリプトのヘッダーコメントで定義する

## Consumed Comments

No new comments since last phase.

## Changed Files

- `scripts/gh-issue-assignee.sh`: 新規ファイル。`status` / `assign` / `reassign` の 3 サブコマンドと、ヘッダーコメントの呼び出し規約 — bash 3.2+ 互換 (連想配列・`mapfile` を使わない)。作成後に `chmod +x` を実行する (隣接スクリプトは git mode 100755)。追記する文字列は英語のみ (`scripts/check-language-convention.py` が `scripts/` への CJK 混入を検出する)
- `scripts/gh-label-transition.sh`: opt-in の `--assign` を追加 (ラベル更新の成功後に `gh-issue-assignee.sh assign` を別の呼び出しで実行し、失敗しても警告のみ)。Usage 表記・`--help`・ヘッダーコメントを更新 — bash 3.2+ 互換 (配列を使わない)。追記する文字列は英語のみ
- `tests/gh-issue-assignee.bats`: 新規ファイル。判定・付与・付け替えの各ケースと、ドキュメント側の構造テスト
- `tests/gh-label-transition.bats`: `--assign` の @test を追加 (既存の @test と mock は変更しない)
- `tests/check-config-schema.bats`: `auto-assign` が既知キーとして受理される @test を追加 (Marker Definition Table への行の追加漏れの回帰ガード)
- `modules/detect-config-markers.md`: Marker Definition Table・YAML Parsing Rules・Output Format の 3 か所に `auto-assign` (`HAS_AUTO_ASSIGN`) を追加。あわせて Processing Steps 1 の「`.wholework.yml` が無いときは boolean 変数を `false` にする」記述を、既定 true の変数を除く形に直す。追記する文字列は英語のみ
- `modules/l0-surfaces.md`: L0 Surface SSoT 表に `Assignees` 行を追加し、表の直後の Note に書き込みが autonomy tier の対象外である旨と、判定結果の語彙の定義先を追記。追記する文字列は英語のみ
- `modules/autonomy-tier.md`: Tier × L0 Write Matrix の直後に、assignee の付与は tier で制御しない例外である旨と理由を書いたサブセクションを追加 (先例: operate route の独立した表)。追記する文字列は英語のみ
- `docs/guide/customization.md`: `.wholework.yml` のサンプルと Available Keys 表 (キーの SSoT) に `auto-assign` を追加
- `docs/ja/guide/customization.md`: [translation sync] 上記 2 箇所の日本語ミラーを同期 (`docs/translation-workflow.md` の Sync Procedure に従う。コードフェンス数の一致を確認する)
- `docs/structure.md`: [Steering Docs sync candidate: listing-side sub-check] Key Files の「GitHub API utilities」に `scripts/gh-issue-assignee.sh` を追加し、`scripts/gh-label-transition.sh` の行に `--assign` を追記 (`ssot_for: directory-layout` を frontmatter で確認済み。Directory Layout の木構造には個別スクリプトもファイル数も載っていないため、木構造は変更不要)
- `docs/ja/structure.md`: [translation sync] 上記の日本語ミラーを同期
- `docs/tech.md`: Architecture Decisions の「Autonomy tier (L0 write governance)」の項に、assignee の付与が tier の対象外の例外である旨を 1 文追記 (`skills/spec/skill-dev-constraints.md` の #250 制約: 新規 `.wholework.yml` キーの追加時は `docs/tech.md` の Architecture Decisions を確認して Changed Files に含める)
- `docs/ja/tech.md`: [translation sync] 上記の日本語ミラーを同期
- `docs/guide/autonomy.md`: [Outbound pointer sync candidate] `docs/guide/customization.md` の `autonomy` 行が参照するユーザー向けガイド。L1 の説明 (「No automatic writes to GitHub state」) に対し、assignee の付与は tier の対象外で `auto-assign: false` で止められる旨を 1 文足すかどうかを `/code` が読んで判断する (推奨: 追加。追加する場合は `docs/ja/guide/autonomy.md` も同期)

**変更不要 (grep・Read で確認済み):**

- `README.md`: スクリプト・サブコマンドの列挙がない (全 68 行を確認)。`SECURITY.md`: 13 行目の GitHub 操作の一覧が「edit (title, body, labels, assignees)」を既に含む
- `docs/migration-notes.md` と `docs/ja/migration-notes.md`: private から public への移行時のインターフェース変更記録 (`gh-label-transition.sh` の項は「Interface changes: None」とエラーメッセージの翻訳のみ)。今回追加するのは末尾の任意フラグ 1 つで、既存の呼び出し形・引数順を変えないため対象外
- `docs/workflow.md`: Label Management への追記は #1544 の AC (`section_contains "docs/workflow.md" "Label Management" "assignee"`)、`/auto` の説明への追記は #1545 の AC が持つ (両 Issue の本文で確認済み)
- `.claude/settings.json.template`: `Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` などのワイルドカードが全スクリプトを覆い、`set-blocked-by.sh`・`resolve-merge-strategy.sh` のような近い例も個別登録されていない
- `scripts/check-config-schema.sh` と `scripts/get-config-value.sh`: `auto-assign` はフラットな boolean キーで、Marker Definition Table の行から自動で登録・読み取りできる (`get-config-value.sh` の Supported 表の行 1 に該当)。コードの変更は不要
- `skills/*/SKILL.md` の `allowed-tools`: この Issue では SKILL.md から新スクリプトを呼ばない (`grep -rl "gh-issue-assignee" skills/` が空)。追加は #1544・#1545 側 (Notes の申し送り)
- `gh-label-transition.sh` を mock する既存テスト (`tests/run-issue.bats`・`tests/run-merge.bats`・`tests/post_merge_check.bats`・`tests/audit-retention.bats`): 既存の呼び出し元は `--assign` を渡さないので `gh-issue-assignee.sh` は呼ばれず、`$MOCK_DIR` への mock 追加は不要

**同期候補の探索結果** (測定範囲: `grep -rl "<keyword>" docs/ tests/ scripts/ modules/`、`docs/spec/`・`docs/reports/`・`docs/sessions/` を含む全ファイル。main の f3ce53f6 時点):

- キーワード `auto-assign`・`HAS_AUTO_ASSIGN`・`gh-issue-assignee`: 既存ファイルへの一致は 0 件 (新規の識別子のため、既存ドキュメントに同期漏れの候補はない)
- [Steering Docs sync candidate] keyword "gh-label-transition.sh" skipped: matched 74 files (no discriminating power)
- [Steering Docs sync candidate] keyword "detect-config-markers.md" skipped: matched 122 files (no discriminating power)
- [Steering Docs sync candidate] keyword "l0-surfaces.md" skipped: matched 83 files (no discriminating power)
- [Steering Docs sync candidate] keyword "autonomy-tier.md" skipped: matched 31 files (no discriminating power)
- 既存の `assignee` への言及は `/triage --assignee` (読み取りのみ: `skills/triage/SKILL.md`・`scripts/triage-backlog-filter.sh`・`tests/triage-backlog-filter.bats`) だけで、今回の変更と矛盾しない

## Implementation Steps

1. `scripts/gh-issue-assignee.sh` を新規作成する (→ acceptance criteria 1, 2, 3, 4)

   **呼び出し規約** (スクリプトのヘッダーコメントと `--help` に英語で書く。AC4 の定義場所はこのヘッダーコメント):

   ```
   scripts/gh-issue-assignee.sh status   <issue-number>   # read-only
   scripts/gh-issue-assignee.sh assign   <issue-number>   # add the executing user, only when unassigned
   scripts/gh-issue-assignee.sh reassign <issue-number>   # replace the other assignees with the executing user
   ```

   | サブコマンド | 標準出力 (1 語 + 改行) | 意味 |
   |---|---|---|
   | `status` | `unassigned` | assignee がいない |
   | `status` | `self` | assignee は実行ユーザーだけ |
   | `status` | `other` | 実行ユーザー以外を含む (bot・Copilot も `other`) |
   | `status` | `unknown` | assignee を読み取れなかった |
   | `assign`・`reassign` | `assigned` | 書き込みを行い、実行ユーザーが assignee になった (読み直しで確認できなかった場合を含む) |
   | `assign`・`reassign` | `unchanged` | 何も変更しなかった (`assign`: すでに誰かがアサイン済み、`reassign`: すでに実行ユーザーだけ) |
   | `assign`・`reassign` | `disabled` | `auto-assign: false` のため何もしなかった |
   | `assign`・`reassign` | `failed` | 失敗した (警告は標準エラー出力) |

   - 終了コード: 使い方の誤り (サブコマンドが不正、Issue 番号が `^[1-9][0-9]*$` でない、引数不足) だけ 1。実行時の失敗はすべて語彙 (`unknown` / `failed`) を出力して 0 で終了する (呼び出し側のフェーズを止めないため)。`--help` は 0
   - 標準エラー出力は人間向けのメッセージ (`Warning:` / `Info:` で始まる) だけにし、機械処理は標準出力の 1 語だけを見る
   - 判定の基準は実行ユーザー (`gh api user` の login) との比較で、大文字小文字は区別しない。同じユーザーが別のセッションで動かしている場合は区別できない (assignee はロックではないため。この制約もヘッダーコメントに書く)

   **実行ユーザーを特定できないとき** (AC4。`gh api user --jq '.login'` が失敗・空・形式不正のとき。GitHub App のトークンや CI の `GITHUB_TOKEN` など):

   - `status`: assignee がいなければ `unassigned`、1 人でもいれば `other` (実行ユーザー本人かを確かめられないので、本人とは見なさない)
   - `assign`: assignee がいれば `unchanged` (実行ユーザーが不要な経路)、いなければ警告して `failed` (書き込まない)
   - `reassign`: 警告して `failed` (書き込まない)

   **API 呼び出し** (この形に固定する。`gh issue edit` は使わない):

   | 用途 | 呼び出し |
   |---|---|
   | 実行ユーザー | `gh api user --jq '.login'`。1 行目だけ採用し、CR を除去し、`^[A-Za-z0-9][A-Za-z0-9_-]*$` に一致して 100 文字以下のときだけ採用 |
   | assignee の読み取り | `gh issue view "$N" --json assignees` の出力を `jq -r '.assignees[]?.login // empty'` で login 一覧にする。出力が空文字、または `jq` が失敗したら読み取り失敗 |
   | 追加 | `gh api "repos/{owner}/{repo}/issues/$N/assignees" -X POST -f "assignees[]=$ME"` (標準出力は捨てる) |
   | 置換 | `gh api "repos/{owner}/{repo}/issues/$N" -X PATCH -f "assignees[]=$ME"` (標準出力は捨てる) |

   login 一覧は `while IFS= read -r` で 1 行ずつ処理する (`dependabot[bot]` のように `[` `]` を含む login を glob 展開させないため、引用なしの `for` では回さない)。`set -euo pipefail` 下で `local x=$(cmd)` は使わず、宣言と代入を分ける。`auto-assign` の読み取りは `"$SCRIPT_DIR/get-config-value.sh" auto-assign true` の結果を小文字にして、`false` のときだけ無効とする (`SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` の慣用句に従う)。

   **挙動の全列挙** (このスクリプトは fail-open の補助処理であり、fail-safe critical に当たる。入力・依存コマンドの失敗の各ケースの期待挙動を次の表で固定する):

   | 条件 | `status` | `assign` | `reassign` |
   |---|---|---|---|
   | `auto-assign` が `false` (大文字小文字不問) | 影響を受けない (通常どおり判定する) | `disabled`。`gh` を一切呼ばない | `disabled`。`gh` を一切呼ばない |
   | `auto-assign` が未設定・空・`false` 以外の値、または `get-config-value.sh` が失敗 | 影響を受けない | 有効 (既定 true) として扱う。`run-auto-sub.sh` の `always-pr` 読み取りなど他の bash 側リーダーと同じ、失敗時に既定値へ倒す慣用句 | 同左 |
   | assignee を読み取れない (`gh issue view` の失敗・空出力・不正な JSON・Issue が存在しない) | `unknown` + 警告 | 警告 + `failed` (書き込まない) | 同左 |
   | assignee が 0 人 | `unassigned` | 実行ユーザーを特定 → 追加 API → 書き込み後の確認 | 追加 API → 書き込み後の確認 (実行ユーザーの特定が前提) |
   | assignee が実行ユーザーだけ | `self` | `unchanged` | `unchanged` |
   | 実行ユーザー以外を含む (複数人・bot を含む) | `other` + `Info:` で login 一覧 | `unchanged` (警告は出さない。確認・警告は `status` を先に呼ぶ側の責務) | 置換 API → 書き込み後の確認 |
   | 実行ユーザーを特定できない | 上記 (AC4) | 上記 (AC4) | 上記 (AC4) |
   | 追加・置換 API が失敗 (終了コード非 0: 権限なし・404・5xx・ネットワーク) | — | 警告 + `failed`。終了コードは 0 | 同左 |
   | API は成功したが、読み直しに実行ユーザーが含まれない (権限のない呼び出しの変更は黙って捨てられる、割り当てできないユーザー) | — | 警告 + `failed` | 同左 |
   | 読み直しに実行ユーザー以外も含まれる (ほぼ同時の着手。AC3) | — | 警告 + `assigned` | 警告 + `assigned` |
   | 読み直しそのものが失敗 | — | 警告 (確認できなかった) + `assigned` (書き込み自体は成功しているため) | 同左 |
   | `gh` の出力に CR・前後の空白が混じる | 除去して扱う | 同左 | 同左 |
   | login の大文字小文字が実行ユーザーと異なる | 区別せず比較する | 同左 | 同左 |

   各サブコマンドの流れ (関数に分けて実装する): `status` = 読み取り → (0 人なら `unassigned`) → 実行ユーザーの特定 → 分類。`assign` = 設定確認 → 読み取り → (1 人以上なら `unchanged`) → 実行ユーザーの特定 → 追加 → 書き込み後の確認。`reassign` = 設定確認 → 読み取り → 実行ユーザーの特定 → 分類 → (実行ユーザーだけなら `unchanged`、0 人なら追加、他のメンバーがいれば置換) → 書き込み後の確認。書き込み後の確認 (AC3) は assignee を読み直し、実行ユーザーが含まれなければ警告して `failed`、含まれて他にもいれば警告して `assigned`、含まれて他にいなければ警告なしで `assigned`。

   **メッセージ文言** (英語。テストの assert と一致させるため固定する。`N` は Issue 番号):

   - 実行ユーザー不明: `Warning: could not identify the executing user (gh api user failed); skipping the assignee update for issue #N`
   - 読み取り失敗: `Warning: could not read the assignees of issue #N; ...` (`status` は `... status is unknown`、`assign` / `reassign` は `... skipping the assignee update`)
   - 書き込み失敗: `Warning: failed to update the assignee of issue #N (no permission or API error); continuing`
   - 反映されていない: `Warning: @<login> is not an assignee of issue #N after the update (the change may have been silently dropped, e.g. no push access); continuing`
   - 同時着手 (AC3): `Warning: issue #N is also assigned to: <logins>. Another member may have started this Issue at about the same time; check with them to avoid duplicate work`
   - 読み直し失敗: `Warning: could not re-read the assignees of issue #N to verify the update; continuing`
   - `status` の `other`: `Info: issue #N is assigned to: <logins>` (実行ユーザー不明のときは末尾に ` (the executing user could not be identified, so these cannot be compared with you)`)

   **検出力の確認** (AC10): 実装とテストを書いた後、`assign` の「すでに assignee がいれば何もしない」分岐を一時的に外して `bats tests/gh-issue-assignee.bats` が FAIL すること、`assign` の API 失敗時に 0 で終了する処理を一時的に外して FAIL することを確認してから元に戻す (コミットしない)。

2. `scripts/gh-label-transition.sh` に opt-in の `--assign` を追加する (after 1) (→ acceptance criteria 2, 5)

   - Usage 表記を `<issue-number> [target-phase] [--assign]` にし、ヘッダーコメントと `--help` に `--assign` の説明を足す: ラベル更新が成功した後で `gh-issue-assignee.sh assign` を別の呼び出しとして実行する。assignee の更新に失敗しても警告だけで、遷移は成功 (exit 0) のまま。`auto-assign: false` のときは何もしない。呼び出し側が明示したときだけ働く (遷移先のフェーズから自動では付与しない)
   - 引数の解析: 既存の `ISSUE_NUMBER="$1"` / `TARGET_PHASE="${2:-}"` を `for ARG in "$@"` のループに置き換える。`--assign` だけをフラグとして扱い、それ以外は位置引数として 1 番目を Issue 番号、2 番目を target-phase に入れる (3 番目以降は従来どおり無視する)。引数不足の判定は `[ $# -lt 1 ]` から「位置引数が 0 個」に変える (`--assign` だけを渡したときも `Error: issue number is required`)。配列は使わない (bash 3.2 の `set -u` で空配列が未定義エラーになるため)。`--help` / `-h` の判定 (`${1:-}`) と、既存のエラーメッセージ・終了コードは変えない
   - `--assign` には target-phase が必要: `ASSIGN=true` で `TARGET_PHASE` が空なら `Error: --assign requires a target phase` を標準エラー出力に出して exit 1 (target-phase の検証ブロックの直後)
   - ラベル更新のブロック (`if ... else ... fi`) の直後 (スクリプトの末尾) に次を追加する: `if [ "$ASSIGN" = "true" ]; then if ! "$SCRIPT_DIR/gh-issue-assignee.sh" assign "$ISSUE_NUMBER" >/dev/null; then echo "Warning: ..." >&2; fi; fi` (実際は複数行で書く)。ラベル更新が失敗したときは、その手前で exit 1 になるので assignee の更新には到達しない。標準出力 (`gh issue edit` が出す Issue URL) は従来から変えないため、`assign` の結果語は捨てる。標準エラー出力 (警告) は残す。`if !` で受けるので、ヘルパーが無い・実行権限が無い場合も遷移は成功のまま
   - 既存の `gh issue view --json labels` と `gh issue edit` の呼び出しには手を入れない (既存の冪等性テストの mock と、同じラベルの remove+add の競合回避に影響するため)

3. テストを追加する (after 1, 2, 4) (→ acceptance criteria 9, 10, 11)。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/gh-issue-assignee.bats` の各 @test、`tests/gh-label-transition.bats` の `--assign` 系、`tests/check-config-schema.bats` の `auto-assign`) を追加したうえでスイートが PASS すること

   **`tests/gh-issue-assignee.bats`** (新規): 先頭に `bats_require_minimum_version 1.5.0` を置き、`run --separate-stderr` で標準出力 (1 語) と標準エラー出力 (警告) を分けて assert する (先例: `tests/check-plugin-staleness.bats`)。`PROJECT_ROOT` を先頭で 1 回定義する。`auto-assign` は `WHOLEWORK_CONFIG_PATH` で制御する (未設定のケースは `/dev/null`、無効化のケースは一時ファイルに `auto-assign: false`)。`WHOLEWORK_SCRIPT_DIR` は設定せず、実物の `get-config-value.sh` を使う。`gh` は PATH 先頭の stub に差し替える (形式は Notes)。@test 名は `status:` / `assign:` / `reassign:` / `usage:` / `docs:` で始める。括弧内は AC9 の (1)〜(7) との対応:

   - `status:` 未アサイン (1) / 実行ユーザーだけ→`self` (2) / 他のメンバー→`other` かつ標準エラー出力に login (3) / bot (`Copilot`) だけ→`other` / login の大文字小文字を区別しない / `auto-assign: false` でも判定は変わらない (4) / 実行ユーザー不明かつ未アサイン→`unassigned` (7) / 実行ユーザー不明かつアサイン済み→`other` (7) / 読み取り失敗→`unknown` で exit 0 / 書き込み系の `gh` 呼び出しが一度も記録されない
   - `assign:` 未アサイン→追加 API を `assignees[]=<実行ユーザー>` 付きで 1 回呼ぶ (1) / 実行ユーザーだけ→書き込みなし (2) / 他のメンバーがアサイン済み→追加 API も置換 API も呼ばれない (3) / `auto-assign: false`→`gh` が一度も呼ばれず `disabled` (4) / 追加 API が失敗→`failed`・警告・exit 0 (5) / 書き込み後の読み直しに他のメンバーがいる→同時着手の警告 (6) / 書き込み後の読み直しに実行ユーザーがいない→警告と `failed` / 実行ユーザー不明→書き込みなし・警告・`failed` (7) / 読み取り失敗→書き込みなし
   - `reassign:` 他のメンバーがアサイン済み→置換 API を実行ユーザーだけで呼ぶ (3) / 実行ユーザーだけ→`unchanged` (2) / 未アサイン→追加 API (1) / `auto-assign: false`→`disabled` (4) / 置換 API が失敗→`failed`・exit 0 (5) / 置換後の読み直しにまだ他のメンバーがいる→警告 (6) / 実行ユーザー不明→書き込みなし (7)
   - `usage:` 引数なし・不正なサブコマンド・Issue 番号が非数字/0/先頭ゼロ→exit 1、`--help`→exit 0 で語彙を表示
   - `docs:` ドキュメント側の構造テスト 4 本。`detect-config-markers.md` の Marker Definition Table の行・YAML Parsing Rules の箇条書き・Output Format の 3 か所に `auto-assign` / `HAS_AUTO_ASSIGN` がある、`docs/guide/customization.md` のサンプルと表に `auto-assign` がある、`modules/l0-surfaces.md` の L0 Surface SSoT の節 (`md_section` で取り出す) に `Assignees` がある、`modules/autonomy-tier.md` に assignee の例外がある

   **`tests/gh-label-transition.bats`** (追記。既存の @test と `setup()` は変更せず、新しい @test の中で `gh` の stub を書く。名前は `assign:` で始める。`WHOLEWORK_SCRIPT_DIR` の差し替えを使う @test では `$MOCK_DIR` に `gh-issue-assignee.sh` の mock を置く):

   - `assign: no --assign flag never touches assignees` (既存の呼び出し形で `gh api` と `assignees` が記録されない。回帰ガード)
   - `assign: --assign updates the assignee after the label update` (呼び出しログでラベル更新が追加 API より先)
   - `assign: --assign is accepted before the positional arguments`
   - `assign: assignee API failure does not fail the label transition` (実物の `gh-issue-assignee.sh` と、追加 API だけ失敗する stub で exit 0・警告・ラベル更新は記録される。AC9 の (5))
   - `assign: a crashing assignee helper does not fail the label transition` (mock が exit 1)
   - `assign: label update failure skips the assignee update` (exit 1 かつ追加 API が呼ばれない)
   - `assign: --assign without a target phase is a usage error`
   - `help: --help documents --assign`

   **`tests/check-config-schema.bats`** (追記): `auto-assign: false` だけの `.wholework.yml` が exit 0 で `Unknown key` を出さない。

4. 設定キーと SSoT ドキュメントを更新する (parallel with 1, 2) (→ acceptance criteria 6, 7, 8)。`modules/` に追記する文字列は英語のみ

   - `modules/detect-config-markers.md`:
     - (a) Marker Definition Table の `steering-hint` 行の直後に `` | `auto-assign` | `HAS_AUTO_ASSIGN` | `true` | `true` (default true; `false` when `auto-assign: false`) | `` を追加する
     - (b) YAML Parsing Rules の `steering-hint` の逆マッピングの箇条書きの直後に `auto-assign` の箇条書きを追加する。次の 5 点を書く: 既定は true で `auto-assign: false` のときだけ `HAS_AUTO_ASSIGN=false` / false にすると `scripts/gh-issue-assignee.sh` の `assign` と `reassign` (および `gh-label-transition.sh --assign`) が書き込みを行わなくなる / 担当状況の判定 (`status`: 他のメンバーの担当の確認・警告と `/auto` の候補除外に使う) は値に関係なく動く / autonomy tier に依存せず L1 でも付与する / 書き込みの可否は `gh-issue-assignee.sh` が自分で判定するので、呼び出し側で再判定しない
     - (c) Output Format の `HAS_STEERING_HINT` の行の直後に `HAS_AUTO_ASSIGN: false if auto-assign: false is set (default: true)` を追加する
     - (d) Processing Steps 1 の「`.wholework.yml` が存在しない場合は boolean 変数を `false` にする」記述を、既定 true の変数 (`HAS_STEERING_HINT`・`HAS_AUTO_ASSIGN`) は `true` にする、と読めるように直す (直さないと、設定ファイルを置かない下流リポジトリで `auto-assign` が無効と読まれる)
   - `modules/l0-surfaces.md`: L0 Surface SSoT 表の `Labels` 行の直後に `` | Assignees | read (`status`), add (`assign`), replace (`reassign`) | `gh-issue-assignee.sh`; `gh-label-transition.sh --assign` (opt-in `assign`) | mutable | yes | `` を追加する (Operations 列の語は `modules/` の他の行と同じ小文字)。表の直後の Note に 1〜2 文を足す: Assignees の書き込みは autonomy tier で制御しない例外であること (`modules/autonomy-tier.md` への参照)、判定結果の語彙と実行ユーザーを特定できないときの扱いの定義先は `scripts/gh-issue-assignee.sh` のヘッダーコメントであること
   - `modules/autonomy-tier.md`: `### Tier-independent L0 write: assignee assignment` というサブセクションを、Tier × L0 Write Matrix の表の直後 (`### Tier × External System Write (operate route)` の前) に追加する (heading level は `###`)。内容は 3 点: (i) assignee の付与 (`gh-issue-assignee.sh` の `assign` / `reassign` と `gh-label-transition.sh --assign`) は L0 write だが、上の表の例外で、tier では制御せず L1 でも行う / (ii) 理由: `phase/*` ラベルの遷移と同じくフェーズ進行の一部で、他のメンバーに担当を見せることが目的。tier で止めると `autonomy:` を設定しない (既定 L1 の) 下流リポジトリで効果が出ない / (iii) 止めたいときは tier ではなく `auto-assign: false` を使う。読み取り (`status`) は L0 read でゲートしない。operate route の表と同じく tier ごとの表 (3 行すべて ○) を添える
   - `docs/guide/customization.md`: (a) サンプルの `steering-hint` ブロックの直後に `auto-assign` のコメント付きの行を追加する (既定 true の opt-out なので `auto-assign: false` の形)。(b) Available Keys 表の `steering-hint` 行の直後に行を追加する (型 boolean、既定 `true`)。説明に 4 点を書く: 既定は有効で、フェーズが Issue に着手するときに実行ユーザーを assignee に設定する (すでに assignee がいるときは上書きも追加もしない) / `false` にすると付与と付け替えだけを止める / 他のメンバーの担当の確認・警告と `/auto` の候補除外は、人が手で付けた assignee を尊重するためのものなので、値に関係なく動く / `autonomy:` tier に依存せず L1 でも付与する (フェーズラベルの遷移と同じくフェーズ進行の一部)。付与に失敗 (実行ユーザーを特定できない・権限がない・API エラー) したときは警告だけで、フェーズは続く旨も添える
   - `docs/tech.md`: Architecture Decisions の「Autonomy tier (L0 write governance)」の項の、`modules/autonomy-tier.md` と `modules/l0-surfaces.md` を SSoT として挙げている文の直後に 1 文足す: assignee の付与 (`scripts/gh-issue-assignee.sh`、`auto-assign: false` で止められる) は、`phase/*` ラベルの遷移と同じくフェーズ進行の一部なので、tier の対象外の例外として `modules/autonomy-tier.md` に定義している

5. 構造ドキュメントと翻訳ミラーを更新する (after 1, 2, 4) (→ acceptance criteria 6 の周辺整合)

   - `docs/structure.md`: Key Files の「GitHub API utilities」で、`scripts/gh-label-transition.sh` の行の直後に `scripts/gh-issue-assignee.sh` の行を追加し (`status` の 4 つの結果、`assign` は未アサインのときだけ、`reassign` は実行ユーザー以外を外して付け替え、失敗しても呼び出し側を止めない、書き込みは `auto-assign` の対象で autonomy tier の対象外、を 1 行にまとめる)、`gh-label-transition.sh` の行には opt-in の `--assign` を追記する
   - `docs/ja/structure.md`: 177〜181 行付近の「GitHub API ユーティリティ」の同じ位置に日本語で同期する
   - `docs/ja/guide/customization.md`: サンプル (30 行付近の `steering-hint`) と Available Keys 表 (119 行付近) に `auto-assign` を日本語で同期する
   - `docs/ja/tech.md`: 72 行付近の「Autonomy tier (L0 write ガバナンス)」の項に、`docs/tech.md` の追記を日本語で同期する
   - いずれもコードフェンスの数が英語版と一致していることを確認する (`docs/translation-workflow.md` の手順 5)。日本語の括弧は半角 `()` の前後に半角スペースを入れる
   - 最後に `docs/guide/autonomy.md` (Changed Files の候補) を読み、追加する場合は `docs/ja/guide/autonomy.md` も同期する

## Verification

### Pre-merge

- <!-- verify: rubric "Issue の assignee について、(a) 担当状況を読み取りだけで判定する (未アサイン / 実行ユーザーだけがアサイン済み / 実行ユーザー以外を含む、の区別を返す)、(b) 未アサインのときだけ実行ユーザーを付ける (既存の assignee は上書きも追加もしない)、(c) 実行ユーザー以外を外して実行ユーザーに付け替える、の 3 つの操作を、SKILL.md とスクリプトの両方から呼べる形で提供するスクリプトが追加または拡張されている" --> Issue の担当状況の判定 (読み取りのみ)、未アサイン時の付与、実行ユーザーへの付け替え、の 3 つの操作がスクリプトとして用意されている
- <!-- verify: rubric "assignee の付与・付け替えに失敗した場合 (実行ユーザーを特定できない、割り当て権限がない、API エラーなど) は警告を出力して処理を続行し、フェーズラベルの遷移を失敗させない。assignee の更新はラベルを更新する gh issue edit とは別の呼び出しで行われている" --> assignee の付与・付け替えに失敗しても警告を出して続行し、フェーズラベルの遷移は失敗しない
- <!-- verify: rubric "assignee を付与した後に assignees を読み直し、実行ユーザー以外も含まれていた場合 (ほぼ同時に別のメンバーが着手した場合) は警告を出力することが実装されている" --> 付与した後に読み直し、実行ユーザー以外も付いていた場合 (ほぼ同時の着手) は警告する
- <!-- verify: rubric "実行ユーザーの login を特定できない場合に、担当状況の判定がどの結果を返すか (未アサインの場合と、誰かがアサイン済みの場合のそれぞれ) が、スクリプトのヘッダーコメントまたは関連ドキュメントに定義されている" --> 実行ユーザーを特定できない場合の判定結果が定義されている
- <!-- verify: rubric "gh-label-transition.sh の既存の呼び出し (オプションなしの位置引数 2 つ) の挙動は変わらず、assignee の付与は呼び出し側が明示的に指定したときだけ行われる (遷移先のフェーズから自動で付与しない)" --> 既存の `gh-label-transition.sh` の呼び出しは挙動が変わらない。assignee の付与は、呼び出し側が明示したときだけ行われる
- <!-- verify: grep "auto-assign" "modules/detect-config-markers.md" --> <!-- verify: grep "auto-assign" "docs/guide/customization.md" --> <!-- verify: rubric "auto-assign の既定値が true (有効) で、false にすると assignee の付与と付け替えを行わなくなること、担当状況の判定 (他のメンバーの担当の確認・警告、/auto の候補除外に使うもの) は auto-assign の値に関係なく動くこと、assignee の付与が autonomy tier (L1 を含む) に依存しないことが、modules/detect-config-markers.md と docs/guide/customization.md に書かれている" --> `.wholework.yml` の `auto-assign` (既定は有効) で付与・付け替えを無効にできる。担当状況の判定は無効にならない。autonomy tier には依存しない
- <!-- verify: section_contains "modules/l0-surfaces.md" "L0 Surface SSoT" "Assignees" --> `modules/l0-surfaces.md` の L0 Surface SSoT 表に、assignee の行が追加されている
- <!-- verify: grep "assignee" "modules/autonomy-tier.md" --> <!-- verify: rubric "modules/autonomy-tier.md に、assignee の付与は autonomy tier で制御しない (L1 でも行う) 例外であることが、フェーズラベル遷移と同じくフェーズ進行の一部であるという理由とともに書かれている" --> `modules/autonomy-tier.md` に、assignee の付与は autonomy tier で制御しない例外であることが理由とともに書かれている
- <!-- verify: rubric "assignee の判定・付与・付け替えについて、bats テストが (1) 未アサイン、(2) 実行ユーザーのみがアサイン済み、(3) 実行ユーザー以外がアサイン済み、(4) auto-assign: false、(5) assignee の付与に失敗 (フェーズラベル遷移は成功し exit 0)、(6) 付与後の読み直しで実行ユーザー以外も含まれていた、(7) 実行ユーザーの login を特定できない、の各ケースを検証している" --> 判定・付与・付け替えについて、未アサイン・自分だけ・他のメンバー・無効化・付与失敗・同時着手・実行ユーザー不明の各ケースを bats テストで確認している
- <!-- verify: rubric "assignee の判定・付与・付け替えの新規 bats テストが、他ユーザーがアサイン済みのケースや付与失敗のケースを再現する gh スタブを使用しており、修正前の実装に対して FAIL する形になっている (未アサインなど既知の安全側の値だけで PASS する形ではない)" --> 新規の bats テストが、他のメンバーがアサイン済みのケースや付与失敗のケースを再現する入力を使っており、修正前の実装では FAIL する
- <!-- verify: github_check "gh pr checks --json name,state --jq '.[] | select(.name==\"Run bats tests\") | .state'" "SUCCESS" --> CI の bats テスト (Run bats tests) が通る

### Post-merge

- なし (各スキルからの呼び出しは sub-issue ② (#1544) と ③ (#1545) の Post-merge で確認する)

## Smoke Test

- <!-- verify: command "bash scripts/gh-issue-assignee.sh status 1543 2>/dev/null | grep -E '^(unassigned|self|other|unknown)'" --> 実 GitHub に対する読み取りのみの疎通確認 (`gh issue view --json assignees` の実出力が `jq` のフィルタで処理でき、語彙のいずれかが返る)。`assign` / `reassign` は実 Issue の assignee を変更し通知を発生させるため、ここには含めない

## Notes

### 外部仕様の確認結果 (取得日はすべて 2026-10-24)

| 項目 | 結果 | 根拠 |
|---|---|---|
| `gh issue edit --add-assignee` は追加型か置換型か | 実質的に置換型。実行時に取得した assignee の一覧 (スナップショット) に Add を足し Remove を除いた全体をクライアントで計算し、集合全体を送る (github.com は `ReplaceActorsForAssignable`、GHES は `updateIssue` の `assigneeIds`)。取得から更新までの間に他のメンバーが付けた assignee は消える。ラベルは個別の mutation で更新する設計との対比がコードのコメントにある | `cli/cli` trunk の `pkg/cmd/pr/shared/editable_http.go` と `editable.go` (WebFetch) |
| REST の追加 API (`POST /repos/{owner}/{repo}/issues/{n}/assignees`) | サーバー側で追加型 ("Users already assigned to an issue are not replaced")。1 回に最大 10 人。応答は 201。push 権限のない呼び出しの assignee は黙って無視される ("Assignees are silently ignored otherwise") | GitHub REST docs "Add assignees to an issue" (https://docs.github.com/en/rest/issues/assignees) |
| REST の更新 API (`PATCH /repos/{owner}/{repo}/issues/{n}`) の `assignees` | 渡した login で assignee の集合を置換する。空配列で全解除。push 権限がないと変更は黙って捨てられる ("silently dropped") | GitHub REST docs "Update an issue" (https://docs.github.com/en/rest/issues/issues#update-an-issue) |
| `gh api` で配列を渡す形 | `-f 'key[]=value'` を並べる | `gh api --help` (gh 2.101.0) の "declare multiple fields with the syntax `key[]=value1`" |
| 追加 API の呼び出し形が正しいか | 存在しない Issue (99999999) に同じ形で呼ぶと、終了コード 1 と `gh: Not Found (HTTP 404)` で、応答の `documentation_url` が `rest/issues/assignees#add-assignees-to-an-issue`。パスは公式の追加 API に解決され、`{owner}/{repo}` の展開も worktree 内で動く。`gh issue view 99999999 --json assignees` も終了コード 1。書き込み系の失敗が必ず非 0 で返ることを確認 (対象が存在しないので状態は変わらない) | 実機 (`gh api "repos/{owner}/{repo}/issues/99999999/assignees" -X POST -f "assignees[]=saito"`) |
| bot・Copilot の `assignees` での見え方 | `login: "Copilot"` として、他のユーザーと同じ配列に並ぶ。REST は `type: "Bot"`、`gh ... --json assignees` は `id` が `BOT_` で始まり `name` が空。login はどちらも `Copilot`。実行ユーザー以外として扱うので `status` は `other` になる (特別扱いしない) | 公開リポジトリの実データを読み取りのみで確認 (`gh api repos/microsoft/vscode/pulls/343430`、`gh pr view 343430 --repo microsoft/vscode --json assignees`) |
| 未アサインの JSON の形 | `{"assignees":[]}` | 実機 (`gh issue view 1543 --json assignees`) |
| 実行ユーザー | `gh api user --jq '.login'` で取得でき、`type=User` | 実機。取得に失敗する条件 (GitHub App のトークン・CI の `GITHUB_TOKEN`) は #1542 の調査による。実機では再現していない |

**実機で確認しなかったこと**: 書き込みを伴う実機確認 (追加 API が割り当てできないユーザーを黙って無視するか、置換 API の実挙動) は行っていない。実 Issue の assignee を変更し、通知を発生させるためで、`/spec` の範囲を超える。公式ドキュメントに明記があるのは「push 権限のない呼び出し」の場合だけで、割り当て対象のユーザー側が割り当て不可の場合はドキュメントに記載がない。設計は、どちらの場合も書き込み後の読み直しで検出できる (実行ユーザーが assignee に含まれなければ警告して `failed`) ので、この挙動には依存しない。書き込み系の実機での初回確認は、#1544 の Post-merge (`opportunistic`: 未アサインの Issue でスキルを実行したときに assignee が設定される) で行われる。

**fixture の出所と形** (bats の `gh` stub が出す JSON の形。実在のユーザー名・id は使わずダミー値にする): `gh ... --json assignees` の出力は `{"assignees":[{"id":"...","login":"...","name":"...","databaseId":N}, ...]}` (4 フィールド)。形の取得元は上記の 2 つの実機コマンド (取得日 2026-10-24)。

### 設計判断 (非対話モードでの自動解決)

- **`gh-label-transition.sh` への opt-in `--assign` を採用**: AC5 の「呼び出し側が明示したときだけ」と、AC2・AC9 の (5) の「フェーズラベル遷移は成功し exit 0」を満たす最小の形。別案は「SKILL.md が `assign` を別コマンドで呼ぶだけ」だが、#1544 の各スキルが 2 つのコマンドを順序依存で呼ぶことになり、「Comment Consumption → ラベル遷移」の順序 (#1316・#1507) を崩しやすい。`--assign` なら 1 つのコマンドで「ラベル遷移 → 付与」を保証できる。`gh-label-transition.sh` の既存の呼び出し元は多数 (scripts 4 本と各 SKILL.md。Issue 本文は 25 か所以上と記載) あり、遷移先のフェーズから自動で付与する案は、新規 Issue 作成・`run-issue.sh` のラベル補完・XL 親の集約にも波及するため採らない
- **assignee の更新は REST の追加 API と置換 API にした**: `gh issue edit --add-assignee` はクライアントで計算した集合全体を送る (上表) ので、同時着手のとき他のメンバーの assignee を消し得る。この機能は同時着手を事後の警告で検出する設計 (#1542 の方針 7) なので、追加が追加型であることが前提になる。追加 API ならサーバー側で追加型。置換が必要な `reassign` だけ、置換 API で集合ごと置き換える (「付け替え」の意味そのもの)
- **`reassign` は assignee が 0 人のとき追加 API を使う**: 判定から書き込みまでの間に他のメンバーが付けた assignee を、見ていないのに消さないため。置換 API を使うのは、他のメンバーがいると確認できたときだけ
- **標準出力は 1 語、詳細は標準エラー出力**: スクリプトの呼び出し側 (`case` で分岐) と SKILL.md (LLM が結果を読む) の両方で扱いやすい。標準エラー出力の `Info:` / `Warning:` は人間向けで、`status` の `other` の login 一覧もここに出す
- **`status` に `unknown` を加えた**: AC が求める 3 つの区別に加えて、読み取りそのものが失敗したときの第 4 の結果。未アサインや他のメンバーと誤って扱うと、不要な書き込みや不要な確認が起きる。終了コードは 0 にして、`set -e` の呼び出し側を止めない
- **`assign` は他のメンバーがアサイン済みでも警告を出さない**: 確認・警告は `status` を先に呼ぶ側 (#1544・#1545 の手順) の責務にした。`auto-assign: false` でも警告が動く (`status` は無効化の影響を受けない) ようにするため、そして二重の警告を避けるため
- **`auto-assign` の読み取り失敗は既定 (true) に倒す**: 他の bash 側リーダーと同じ慣用句。`get-config-value.sh` は同じディレクトリのスクリプトで、通常は失敗しない
- **`detect-config-markers.md` の Processing Steps 1 の記述も直す**: 「設定ファイルが無いときは boolean を `false`」のままだと、`.wholework.yml` を置かない下流リポジトリ (この機能が効くべき対象) で、読み取る側のスキルが `HAS_AUTO_ASSIGN` を無効と解釈する。`HAS_STEERING_HINT` にも同じ潜在的な誤読があるので、あわせて直す
- **Issue 本文と既存実装の矛盾は検出されなかった**: 背景に書かれた事実 (`gh-label-transition.sh` の `gh issue edit` 失敗が exit 1 になる構造、既存テストの mock の形、`/auto` の `allowed-tools` に `gh issue edit` と `gh api` がない、`check-config-schema.sh` が Marker Definition Table から自動登録、など) をすべてコードで確認した
- 実行ユーザーの特定は既存の先例 (`scripts/post-fallback-review-summary.sh` の `gh api user -q '.login'`、`skills/triage/SKILL.md` の `--assignee me`) と同じ `gh api user` を使う
- 監査・調査型の Issue ではない (新機能の実装であり、複数の既存項目を分類する成果物はない)

### bats の `gh` stub の入力形式

`tests/gh-issue-assignee.bats` の `setup()` で `$MOCK_DIR/gh` を書き、`export PATH="$MOCK_DIR:$PATH"` で差し替える (環境変数で挙動を切り替える。ヒアドキュメントは引用付きにして実行時に変数を読む):

- すべての呼び出しを `$GH_CALL_LOG` に `echo "$*"` で追記する
- `gh api user ...` → `$MOCK_ME` を出力する。空文字なら何も出力せず終了コード 1 (実行ユーザー不明)
- `gh issue view N --json assignees` → 1 回目は `$MOCK_VIEW_1`、2 回目以降は `$MOCK_VIEW_2` (未定義なら `$MOCK_VIEW_1`) の JSON を出力する。呼び出し回数は `$BATS_TEST_TMPDIR/view_count` に記録する。`MOCK_VIEW_FAIL=1` で終了コード 1
- `gh api ... -X POST` と `gh api ... -X PATCH` → `MOCK_WRITE_FAIL=1` なら終了コード 1、そうでなければ `{}` を出力して 0
- JSON の例: 未アサイン `{"assignees":[]}`、他のメンバーと bot `{"assignees":[{"id":"U_dummy","login":"alice","name":"Alice","databaseId":1},{"id":"BOT_dummy","login":"Copilot","name":"","databaseId":2}]}`
- 書き込みの有無は `$GH_CALL_LOG` で assert する (例: `grep -q -- "-X POST"`、`! grep -q -- "-X PATCH"`)。「何も呼ばれない」ケースは、ログに `issues/N/assignees` も `-X PATCH` も無いことを assert する
- `tests/gh-label-transition.bats` の `--assign` 系は、既存の `setup()` の `gh` mock が `issue view` に空文字を返すため、実物の `gh-issue-assignee.sh` を通す @test では `issue view` / `api user` / 書き込み系を分岐する mock を @test 内で書き直す (既存の mock と同じく、ヒアドキュメントで `$MOCK_DIR/gh` を上書きする)

### 後続 Issue への申し送り

- `skills/issue`・`skills/spec`・`skills/code` (#1544) と `skills/auto` (#1545) の SKILL.md が `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh` を直接呼ぶ場合は、各 SKILL.md の frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh:*` を追加する必要がある。`gh-label-transition.sh --assign` だけで済む箇所は、既存の `gh-label-transition.sh:*` で足りる。現時点で `skills/` に `gh-issue-assignee` を参照するものはない (grep 確認済み)
- 3 択の確認で「自分に付け替えて続ける」を選んでも、`auto-assign: false` だと `reassign` は `disabled` を返して何も起きない。#1544・#1545 の手順で `disabled` を検出してその旨を伝えるか、`HAS_AUTO_ASSIGN` が false のときは「付け替え」の選択肢を出さない
- #1545 の候補除外の設計材料: `status` は、実行ユーザーを特定できず assignee がいる Issue を `other` にする。除外を `resolve-batch-query.sh` の `jq` で直接判定する場合は、この規約に合わせる (誰かがアサイン済みなら除外 = fail-closed) か、別の方針にするかを #1545 の `/spec` で決める
- `modules/l0-surfaces.md` の Assignees 行の Primary callers 列には、現時点でスクリプトだけを書いている。スキル名 (`/issue`・`/spec`・`/code`・`/auto`) を足すのは #1544・#1545 の側
- `docs/workflow.md` の Label Management と `/auto` の説明は #1544・#1545 の AC が持つので、この Issue では触らない

### 規模の見積もり (Step 18 の再評価に使う)

Changed Files は 14 件 (候補の `docs/guide/autonomy.md` を除く)。内訳はスクリプトのロジック変更 2 (新規 1)、テスト 3 (新規 1)、`modules/` 3、`docs/` 6 (うち翻訳ミラー 3)。ファイル数の軸では XL 相当。複雑さの補正は、加算要因が「分岐の多い新規スクリプトのロジック」、減算要因が「大半がドキュメント・翻訳ミラーの追記で、`steering-hint`・`set-blocked-by.sh` など既存パターンの横展開」で、差し引き 1 段階下げて L。triage 時点の M より大きい (親 #1542 は「① には外部サービスの挙動の確認が含まれるので、`/spec` で規模を見直してよい」としていた)。

### その他

- **Pre-merge 項目数**: この Spec の Pre-merge は 11 件で、SPEC_DEPTH=light の目安 (5 件) を超える。Issue 本文の `## Acceptance Criteria > Pre-merge` を verify command ごと転記する規則 (件数の一致検査を含む) を優先した。Implementation Steps は目安内の 5 件にまとめた
- **英語のみにするファイル**: `scripts/`・`modules/` に追記する文字列に CJK 文字を入れない (`scripts/check-language-convention.py` が CI と `/code` のコミット前に検出する)。`docs/`・`tests/` は対象外だが、`tests/` のコード・コメントは英語にする
- **コミット前の確認**: 新規スクリプトは `chmod +x` してから `git add` する (git mode 100755)。`.claude/` 配下のファイルは変更しないので `git add -f` は不要
- **実行する確認コマンド**: `bats tests/gh-issue-assignee.bats tests/gh-label-transition.bats tests/check-config-schema.bats`、`bats tests/` 全体、`bash scripts/check-config-schema.sh`、`bash scripts/check-forbidden-expressions.sh`、`bash scripts/check-translation-sync.sh`
