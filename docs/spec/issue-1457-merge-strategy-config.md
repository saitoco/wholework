# Issue #1457: merge: マージ戦略を .wholework.yml で選択可能にする (squash 固定を解除)

## Overview

`/merge` は `gh pr merge "$NUMBER" --squash --delete-branch` (`skills/merge/SKILL.md` Step 4) で squash 固定になっており、マージ戦略を選択する設定キーが存在しない。チーム規約で merge commit を必須とし、リポジトリ側で squash merge を無効化しているプロジェクトでは、初回の `/merge` が GitHub API エラーで失敗し、Tier 1/2 の completion check も通らず、最終的に `/auto` が merge フェーズで停止する。

`.wholework.yml` に `merge-strategy` キー (`squash` / `merge` / `rebase`、既定 `squash`) を追加し、`/merge` が設定値に応じたフラグを発行できるようにする。既定値により既存挙動は完全に維持する。

戦略解決ロジックは `skills/merge/SKILL.md` の散文に直書きせず、新規スクリプト `scripts/resolve-merge-strategy.sh` に抽出する。理由は 2 つ: (a) `scripts/resolve-preview-env.sh` (#1428/#1429) が確立した「bash wrapper と SKILL.md の双方から呼べる共有リゾルバ」の先例に沿う、(b) 散文のままでは分岐が bats で検証できず、Issue の 3 件の `command` 型 AC が構造的に常時 PASS になる (Triage AC audit コメントの指摘そのもの)。

## Reproduction Steps

(参考。Bug ではなく Feature だが、Issue 本文の実害シナリオを再現手順として記録しておく)

1. `allow_squash_merge: false` / `allow_merge_commit: true` のリポジトリを用意する
2. Size M/L の Issue に対して `/auto <N>` を実行する
3. merge フェーズで `gh pr merge "$NUMBER" --squash --delete-branch` が GitHub API エラーで失敗し、exit 非ゼロになる
4. Tier 1 completion check (`gh pr view --json state == MERGED`) も false のため Tier 3 recovery sub-agent 送りとなり、stop-and-report で停止する

## Changed Files

- `scripts/resolve-merge-strategy.sh`: 新規作成。`.wholework.yml` の `merge-strategy` を解決し、strategy 名 (既定モード) または `gh pr merge` フラグ (`--flag` モード) を stdout に 1 行出力する — bash 3.2+ 互換 (連想配列 / `mapfile` / `readarray` を使わない)
- `tests/resolve-merge-strategy.bats`: 新規作成。11 ケース (下記 Implementation Steps の Step 2 に列挙)
- `modules/detect-config-markers.md`: Marker Definition Table に `merge-strategy` 行を追加 (SSoT)。`**YAML Parsing Rules:**` 箇条書きに `merge-strategy` の解釈規則を追加
- `skills/merge/SKILL.md`: Step 4 の `gh pr merge --squash --delete-branch` を戦略解決経由へ変更。`allowed-tools` frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-merge-strategy.sh:*` を追加。squash 断定表現 (frontmatter `description` / H1 `# Squash Merge` / 106 行目 `Step 4 (Execute Squash Merge)` / 239 行目見出し / 250・254・266 行目の Phase Handoff 散文 / 339 行目の Worktree Exit 散文) を戦略中立表現へ変更
- `docs/guide/customization.md`: § Available Keys に `merge-strategy` 行を追加 (EN)
- `docs/ja/guide/customization.md`: § Available Keys に `merge-strategy` 行を追加 (JA)
- `docs/workflow.md`: 99 行目「Executes squash merge and deletes the remote branch.」を `merge-strategy` 条件付き表現へ変更
- `docs/ja/workflow.md`: 92 行目「squash merge を実行してリモートブランチを削除します。」を同上
- `docs/tech.md`: 60 行目「Squash-merges a PR and deletes the remote branch after CI passes...」を同上
- `docs/ja/tech.md`: 51 行目「PR を squash-merge し、リモートブランチを削除する。」を同上
- `docs/guide/workflow.md`: 111 行目「Squash-merges the PR and deletes the remote branch.」を同上 (Issue 本文の Scope に未記載だが、同じ user-facing な squash 断定であり、放置すると設定キー追加直後にドリフトする)
- `docs/ja/guide/workflow.md`: 107 行目「PR を squash merge してリモートブランチを削除します。」を同上
- `docs/structure.md`: `scripts/resolve-merge-strategy.sh` の行を scripts インベントリに追加 (`scripts/resolve-preview-env.sh` 行の近傍)。100 行目 skills テーブルの merge 行「Squash merge and branch deletion」を戦略中立表現へ変更
- `docs/ja/structure.md`: 同上 (201 行目付近にスクリプト行追加、93 行目 skills テーブル行を変更)
- `scripts/reclaim-stale-worktrees.sh`: ヘッダーコメントの ancestry 前提記述 (17-21 行目 `safe branch deletion`、35-38 行目 `uncommitted-changes guard equivalent`、121-123 行目 `resolve_merged_pr_head_ref_oid`) に「merge commit / rebase 戦略では ancestry が保存されるため ancestor チェック側の経路が通る」旨を追記 — コメントのみ、挙動変更なし。bash 3.2+ 互換 (変更なし)
- `modules/worktree-lifecycle.md`: [Steering Docs sync candidate] 267 行目の base propagation table の `/merge` 行「fast-forwarded to `origin/main` after squash merge」を戦略中立表現へ (`git merge origin/main --ff-only` は 3 戦略すべてで成功する — Notes の設計前提を参照)
- `modules/l0-surfaces.md`: [Steering Docs sync candidate] 431 行目「after the PR branch has already been squash-merged and deleted (`gh pr merge --squash --delete-branch`, earlier in the same Step)」を戦略中立表現へ
- `modules/orchestration-fallbacks.md`: [Steering Docs sync candidate] 552 行目「`gh pr merge --squash --delete-branch` is an irreversible external side effect」を戦略中立表現へ
- `.claude/settings.json.template`: 変更不要 (確認済み — 56-57 行目に `Bash(${HOME}/.claude/plugins/cache/saitoco-wholework/wholework/*/scripts/*.sh *)` と `Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` のワイルドカードがあり、新規スクリプトは既に許可範囲内。`scripts/resolve-preview-env.sh` も個別登録されていない)
- `scripts/run-merge.sh` および `tests/run-merge.bats`: 変更不要 (確認済み — `grep -rn "resolve-merge-strategy\|squash" scripts/run-merge.sh` で該当なし。戦略解決は `skills/merge/SKILL.md` の散文からのみ呼ばれ、bash wrapper は関与しない。したがって `WHOLEWORK_SCRIPT_DIR` mock の追加も不要)
- `scripts/check-config-schema.sh`: 変更不要 (確認済み — 26-33 行目で `modules/detect-config-markers.md` の Marker Definition Table から `KNOWN_KEYS` を awk 導出しているため、表に行を足すだけで CI の schema validation に自動登録される)

**Steering Docs sync candidate 検索結果 (discriminating-power filter 適用後):**

- キーワード `merge-strategy`: `grep -rl "merge-strategy" docs/ tests/ scripts/ modules/` の一致 0 件 — 新規キーのため既存参照なし、sync candidate なし
- キーワード `resolve-merge-strategy.sh`: 一致 0 件 — 新規スクリプトのため sync candidate なし
- [Steering Docs sync candidate] keyword "detect-config-markers.md" skipped: matched 111 files (no discriminating power)
- [Steering Docs sync candidate] keyword "reclaim-stale-worktrees.sh" skipped: matched 10 files (no discriminating power)
- 上記フィルタで全キーワードが除外/0 件のため、`modules/worktree-lifecycle.md` / `modules/l0-surfaces.md` / `modules/orchestration-fallbacks.md` の 3 件は `grep -rn "squash" modules/` による本 Issue 固有の squash 断定表現スイープで別途特定したもの (キーワード検索由来ではない)

## Implementation Steps

1. `scripts/resolve-merge-strategy.sh` を新規作成する (→ acceptance criteria 1, 2, 3)。仕様:
   - 引数: なし (strategy 名を出力) / `--flag` (`gh pr merge` のフラグ `--squash` `--merge` `--rebase` を出力) / `--help` (usage を出力し exit 0)。それ以外の引数は usage を stderr に出して exit 1
   - `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` で sibling 解決 (既存の `scripts/check-allowed-tools.sh` と同じ形)
   - 値取得: `bash "$SCRIPT_DIR/get-config-value.sh" merge-strategy squash`
   - **fail-safe critical 指定** (下記の 3 分類は Notes の "fail-safe critical 判定" を参照):
     - **空 / 不正値**: 取得値から末尾の CR (`\r`) を 1 個だけ除去したうえで `squash` / `merge` / `rebase` に完全一致しない値 (空文字列を含む) は、stderr に `Warning: invalid merge-strategy '<value>' in .wholework.yml; falling back to 'squash'.` を出力して `squash` にフォールバックする。exit code は 0 (警告であってエラーではない)
     - **特殊文字 / 多バイト / 過大入力**: `>` `"` 改行 CRLF 多バイト文字などを含む値はいずれも上記の完全一致に失敗するため、同じ不正値経路で `squash` にフォールバックする。値をシェルに再解釈させる経路 (`eval` / 展開) を作らないこと
     - **依存コマンド失敗時**: `get-config-value.sh` が非ゼロ終了または不在の場合は **fail-closed で `squash`** にフォールバックする。理由: `squash` は本 Issue 以前の既存挙動そのものであり、解決失敗時に戦略が黙って切り替わるより現状維持へ縮退するほうが安全。`set -euo pipefail` 下でコマンド置換の失敗がスクリプト全体を中断しないよう、取得は `RAW=$(bash "$SCRIPT_DIR/get-config-value.sh" merge-strategy squash 2>/dev/null) || RAW=""` の形で受けること
   - 出力は常に 1 行 (`printf '%s\n'`)。警告は stderr、解決結果は stdout に分離する
   - bash 3.2+ 互換 (連想配列 / `mapfile` / `readarray` を使わない)
2. `tests/resolve-merge-strategy.bats` を新規作成する (after 1) (→ acceptance criteria 1, 2, 3)。`tests/get-config-value.bats` と同じ `PROJECT_ROOT` / `WORK_DIR` 構成を用い、`$WORK_DIR` に `.wholework.yml` を書いて実行する。`@test` 名は以下のとおり (grep 型 verify command が参照するため文言を変更しないこと):
   - `flag mode: merge-strategy merge resolves to --merge`
   - `flag mode: unset merge-strategy falls back to --squash`
   - `flag mode: merge-strategy rebase resolves to --rebase`
   - `invalid merge-strategy falls back to squash and warns on stderr`
   - `empty merge-strategy falls back to squash and warns on stderr`
   - `merge-strategy value with special characters falls back to squash`
   - `merge-strategy value with a trailing carriage return is accepted`
   - `get-config-value failure falls back to squash (fail-closed)` — `MOCK_DIR` + `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` に非ゼロ終了する `get-config-value.sh` モックを置いて検証する
   - `name mode: merge-strategy merge prints the bare strategy name`
   - `help: --help outputs usage`
   - `error: unknown argument`
3. `modules/detect-config-markers.md` を更新する (parallel with 1, 2) (→ acceptance criteria 4):
   - `### Marker Definition Table (fixed mappings)` の `auto-stop-at` 行の直後に `| `merge-strategy` | `MERGE_STRATEGY` | Enum string extracted as-is (`squash`/`merge`/`rebase`) | `squash` (used by `scripts/resolve-merge-strategy.sh`) |` を追加する
   - `**YAML Parsing Rules:**` 箇条書きの `auto-stop-at` の項目の直後に、`merge-strategy` は enum 文字列であること・`squash`/`merge`/`rebase` 以外 (空値を含む) は `squash` にフォールバックして警告をログ出力すること・解決は `scripts/resolve-merge-strategy.sh` が担うことを 1 項目として追加する
   - `## Output Format` ブロックにも既存キーと同じ形式で `MERGE_STRATEGY: ...` の 1 行を追加する (内部整合性のため。Code Retrospective 参照)
4. `skills/merge/SKILL.md` を更新する (after 1) (→ acceptance criteria 1, 7):
   - `allowed-tools` frontmatter の `Bash(...)` リストに `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-merge-strategy.sh:*` を追加する (`${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-merge-status.sh:*` の隣が自然な位置)
   - `### Step 4: Execute Squash Merge` の見出しを `### Step 4: Execute Merge` に変更し、`gh pr merge "$NUMBER" --squash --delete-branch` の直前に戦略解決の呼び出しを挿入する。挿入する内容: `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-merge-strategy.sh --flag` を実行し、出力 (`--squash` / `--merge` / `--rebase` のいずれか 1 行) を `MERGE_FLAG` として記録したうえで `gh pr merge "$NUMBER" $MERGE_FLAG --delete-branch` を発行する、と明記する。`--delete-branch` は 3 戦略すべてで有効なため無条件のまま維持する
   - squash 断定表現を戦略中立表現へ変更する (対象箇所は Changed Files に列挙。frontmatter `description` / H1 / 106 行目 / 239 行目 / 250・254・266 行目 / 339 行目)。266 行目の「なぜこの呼び出しが post-squash に置かれているか」の論理は戦略非依存 (PR ブランチ削除後であることが根拠) なので、論旨は変えず語のみ中立化する
5. `docs/guide/customization.md` と `docs/ja/guide/customization.md` の § Available Keys テーブルに `merge-strategy` 行を追加する (parallel with 1, 2) (→ acceptance criteria 5, 6)。`auto-stop-at` 行の直後、`themes` 行の直前に置く。Type=`string`、Default=`"squash"`、Description には有効値 3 種・不正値時は `squash` にフォールバックして警告をログ出力すること・リポジトリ側の許可設定 (`allow_squash_merge` 等) との不一致は自動検出せず GitHub API エラーとして表面化することを記載する
6. `docs/workflow.md` / `docs/ja/workflow.md` / `docs/tech.md` / `docs/ja/tech.md` の squash 断定表現を `merge-strategy` 条件付き表現へ変更する (parallel with 1, 2) (→ acceptance criteria 7)。EN 側には `merge-strategy` の literal を含めること (AC7 の補助 `file_contains` が `docs/workflow.md` を対象にしているため)。JA ミラーは `docs/translation-workflow.md` の Sync Procedure に従い EN と同時に更新する
7. `docs/guide/workflow.md` / `docs/ja/guide/workflow.md` の squash 断定表現を同様に条件付き表現へ変更する (parallel with 6) (→ acceptance criteria 7)
8. `docs/structure.md` / `docs/ja/structure.md` を更新する (after 1) (→ acceptance criteria 7 の補助):
   - scripts インベントリ (`scripts/resolve-preview-env.sh` 行の近傍) に `scripts/resolve-merge-strategy.sh` の行を追加する
   - skills テーブルの merge 行 (`docs/structure.md` 100 行目 / `docs/ja/structure.md` 93 行目) の「Squash merge and branch deletion」/「Squash merge とブランチ削除」を戦略中立表現へ変更する
9. `scripts/reclaim-stale-worktrees.sh` のヘッダーコメントの ancestry 前提記述に merge commit / rebase ケースを追記する (parallel with 1)。対象: 17-21 行目 (`safe branch deletion`)、35-38 行目 (`uncommitted-changes guard equivalent` の「squash merges do not preserve ancestry」)、121-123 行目 (`resolve_merged_pr_head_ref_oid`)。追記内容は「`merge-strategy` が `merge` / `rebase` の場合は ancestry が保存されるため、`git branch -d` および ancestor-of-`origin/<default-branch>` チェックがそのまま成立する。headRefOid 照合フォールバックは squash 戦略のための経路として残す」。コメントのみで挙動は変更しない
10. `modules/worktree-lifecycle.md` / `modules/l0-surfaces.md` / `modules/orchestration-fallbacks.md` の squash 断定表現を戦略中立表現へ変更する (parallel with 6)。いずれも Changed Files に [Steering Docs sync candidate] として列挙した 1 行程度の記述で、論旨は戦略非依存のため語のみ中立化する。`/code` が各ファイルを読んで最終的な include/exclude を判断する

## Alternatives Considered

| 案 | 内容 | 採否 | 理由 |
|----|------|------|------|
| A. `skills/merge/SKILL.md` の散文に直接分岐を書く | SKILL.md で `.wholework.yml` を Read し、値に応じて `--squash`/`--merge`/`--rebase` を選ぶ | 不採用 | 分岐が LLM 実行の散文にしか存在せず bats で検証不能。Issue の 3 件の `command` 型 AC が構造的に常時 PASS になる (Triage AC audit の指摘そのもの)。`modules/detect-config-markers.md` の LLM 解釈だけに依存する形は、不正値フォールバックの決定性も失う |
| B. `scripts/run-merge.sh` (bash wrapper) 側で解決して `claude -p` に渡す | wrapper が戦略を解決し ARGUMENTS 経由で SKILL.md へ渡す | 不採用 | `/merge` は wrapper 経由 (`--auto`) と skill 直接呼び出しの 2 経路があり、wrapper 側だけに置くと直接呼び出し経路が squash 固定のまま残る。`resolve-preview-env.sh` (#1428/#1429) が同じ理由で共有スクリプトへ抽出された先例がある |
| C. **共有リゾルバスクリプト `scripts/resolve-merge-strategy.sh` に抽出** | 両経路から呼べる決定的スクリプトに解決ロジックを置く | **採用** | (a) `resolve-preview-env.sh` の先例に一致、(b) bats で分岐・フォールバック・警告を決定的に検証でき AC の常時 PASS 問題が解消、(c) fail-safe な不正値フォールバックを 1 箇所に集約できる |
| D. リポジトリ側の許可設定 (`allow_squash_merge` 等) を検出して自動フォールバック | `gh api repos/{owner}/{repo}` を読んで許可されていない戦略を回避する | 不採用 | Issue 本文の Out of scope に明記。設定値と実リポジトリ許可の不一致は API エラーとして表面化させる方針 |
| E. `tests/run-merge.bats` に merge-strategy ケースを追加 | Issue 本文の AC が指定していた検証先 | 不採用 | `tests/run-merge.bats` の検証対象は `scripts/run-merge.sh` (wrapper) であり、戦略解決を含まない。リポジトリの慣習は 1 スクリプト 1 bats ファイル (`tests/resolve-*.bats` に 3 件の先例)。新規 `tests/resolve-merge-strategy.bats` は実装前に存在しないため常時 PASS にもならない |

## Verification

### Pre-merge

- <!-- verify: grep "flag mode: merge-strategy merge resolves" "tests/resolve-merge-strategy.bats" --> <!-- verify: file_contains "skills/merge/SKILL.md" "resolve-merge-strategy.sh" --> <!-- verify: command "bats tests/resolve-merge-strategy.bats" --> `.wholework.yml` に `merge-strategy: merge` を設定した状態で `/merge` が `--merge` フラグを発行する経路がテストで確認できる
- <!-- verify: grep "flag mode: unset merge-strategy falls back" "tests/resolve-merge-strategy.bats" --> <!-- verify: command "bats tests/resolve-merge-strategy.bats" --> `merge-strategy` キー未設定時は従来どおり `--squash` が発行される
- <!-- verify: grep "invalid merge-strategy falls back to squash and warns" "tests/resolve-merge-strategy.bats" --> <!-- verify: command "bats tests/resolve-merge-strategy.bats" --> 不正値 (`squash` / `merge` / `rebase` 以外) は `squash` にフォールバックし、警告がターミナル出力される (`watchdog-timeout-seconds` 等の既存の不正値フォールバック運用と同じ扱い。Issue コメント等への永続化は不要)
- <!-- verify: file_contains "modules/detect-config-markers.md" "merge-strategy" --> `modules/detect-config-markers.md` § Marker Definition Table に `merge-strategy` 行が追加されている (`scripts/check-config-schema.sh` の `KNOWN_KEYS` はこの表から awk 導出されるため、追加により自動登録される)
- <!-- verify: file_contains "docs/guide/customization.md" "merge-strategy" --> `docs/guide/customization.md` (EN) に `merge-strategy` の記載がある
- <!-- verify: file_contains "docs/ja/guide/customization.md" "merge-strategy" --> `docs/ja/guide/customization.md` (JA) に `merge-strategy` の記載がある
- <!-- verify: rubric "docs/workflow.md, docs/ja/workflow.md, docs/tech.md, docs/ja/tech.md, docs/guide/workflow.md, docs/ja/guide/workflow.md はいずれも squash merge を断定的に記述せず、merge-strategy 設定値に応じた条件付きの記述に更新されている" --> <!-- verify: file_contains "docs/workflow.md" "merge-strategy" --> squash 断定表現が条件付き表現に更新されている (EN/JA)

### Post-merge

- このリポジトリ (wholework 自身、`allow_merge_commit: true` / `allow_rebase_merge: true` が有効) で `merge-strategy: merge` (または `rebase`) を実際に設定した状態で `/auto` を実行し、merge フェーズを通過することを確認する <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-merge-strategy.sh:*`: `skills/merge/SKILL.md` Step 4 でマージ戦略を解決する (未登録 — Step 4 で `allowed-tools` frontmatter に追加が必要)

### Built-in Tools

- なし (`skills/merge/SKILL.md` の既存 `allowed-tools` に含まれる `Read` / `Edit` / `Write` / `Grep` / `Glob` で足りる)

### MCP Tools

- なし

## Uncertainty

- **`gh pr merge` の戦略フラグと `--delete-branch` の組み合わせ**: `--merge` / `--rebase` 指定時に `--delete-branch` が併用可能か
  - **検証方法**: `gh pr merge --help` の実行確認
  - **結果**: 解決済み。`-m/--merge`、`-r/--rebase`、`-s/--squash`、`-d/--delete-branch` がいずれも独立したフラグとして提供されており併用可能。→ Implementation Steps 4 に反映済み (`--delete-branch` を無条件のまま維持)
  - **影響範囲**: Implementation Steps 4
- **本リポジトリでの Post-merge AC 実施可否**: wholework 自身のリポジトリで `merge` / `rebase` 戦略が実際に選択できるか
  - **検証方法**: `gh api repos/{owner}/{repo} --jq '{allow_squash_merge, allow_merge_commit, allow_rebase_merge}'`
  - **結果**: 解決済み。`allow_merge_commit: true` / `allow_rebase_merge: true` / `allow_squash_merge: true` をいずれも確認。Post-merge AC を本リポジトリで実施可能。→ Post-merge AC の記述をそのまま維持
  - **影響範囲**: Verification > Post-merge
- **`skills/merge/SKILL.md` Step 4 substep 1 の `git merge origin/main --ff-only` が非 squash 戦略でも成立するか**: `/merge` の worktree ブランチは Worktree Entry 時点の `origin/main` から作られる (`worktree.baseRef: fresh`)。squash では新規コミット 1 個、merge commit では第 1 親が旧 main のマージコミット、rebase では旧 main の上に並ぶ再構成コミット列 — いずれの場合も worktree ブランチの tip は新しい `origin/main` の ancestor になるため、`--ff-only` は 3 戦略すべてで成功する
  - **検証方法**: 上記は git の ancestry 特性からの演繹。実機確認は Post-merge AC (`merge-strategy: merge` を設定して `/auto` を実走) が兼ねる
  - **影響範囲**: Implementation Steps 4, 10 (`modules/worktree-lifecycle.md` の base propagation table の記述)。既存の squash 経路は変更しないため、この前提が崩れても既定挙動には影響しない

## Notes

- **Consumed Comments 由来の AC 修正**: Triage AC audit コメント (2026-09-08T05:21:30Z) が Pre-merge AC 1〜3 の `command "bats tests/run-merge.bats"` を「常時 PASS」(`skills/triage/skill-dev-verify-audit.md` Pattern 2 サブパターン、#1279 と同型) と指摘していた。実測でも `bats tests/run-merge.bats` は実装前の main 時点で 36 ケース全 PASS する。本 Spec では audit コメントの当初案 (`bats --filter` への絞り込み) ではなく、#1103 が採用したより新しい precedent — `grep "<新規テスト名>" tests/xxx.bats` (新規テストの存在確認、実装前は不一致) + `command "bats tests/xxx.bats"` (スイート全体の PASS 確認) の 2 段構え — を採用した。理由: `bats --filter` は 0 件マッチでも exit 0 になる同型のギャップが #1334/#1363 の Spec investigation で指摘されている。加えて検証先自体を `tests/run-merge.bats` から新規 `tests/resolve-merge-strategy.bats` へ変更した (Alternatives Considered E 参照) — 新規ファイルのため実装前は必ず FAIL する。これらの修正は本 `/spec` セッション内で `gh-issue-edit.sh` により Issue #1457 本文にも適用済み
- **fail-safe critical 判定**: `scripts/resolve-merge-strategy.sh` は判定基準 (c)「失敗時に safe-side の既定値を返す設計のスクリプト」に該当する (不正値・依存コマンド失敗時に `squash` へフォールバックする)。したがって Implementation Steps 1 に、空 / 過大 / 特殊文字 (`>` `"` 改行 CRLF 多バイト) 入力時の期待挙動と、依存コマンド (`get-config-value.sh`) 失敗時が fail-open か fail-closed か (fail-closed) およびその根拠を明記した。判定基準 (a) gate / (b) validator には該当しない (マージ可否をブロックする門ではなく、フラグ値を決めるだけ)
- **監査・調査型 Issue 判定**: 該当しない (yes/no = no)。本 Issue の目的は既存項目の分類・実査ではなく機能追加であり、per-item の判定根拠を永続成果物に記録する要件もない。したがって「識別子の存在検証を必須化する Implementation Step」は追加していない
- **allowed-tools impact chain (Case 2, `modules/*.md` 変更)**: `modules/detect-config-markers.md` の追加内容が `scripts/resolve-merge-strategy.sh` を文字列として参照するため lightweight gate に一致する。reader を列挙したところ `grep -rl "modules/detect-config-markers\.md" skills/*/SKILL.md` は 10 件 (audit / code / doc / auto / issue / review / spec / merge / triage / verify) だが、モジュール本文は「このキーの解決は当該スクリプトが担う」という consumer 注記を書くだけで、reader に対してスクリプトの実行を指示しない (既存の `patch-lock-timeout` 行が `scripts/worktree-merge-push.sh` を同じ形で参照しているのと同一パターン)。実際の呼び出し箇所は `skills/merge/SKILL.md` Step 4 のみであり、`allowed-tools` 追加が必要な SKILL.md も `skills/merge/SKILL.md` 1 件に限られる (Implementation Steps 4 に含む)
- **`.wholework.yml` 本体は変更しない**: 本リポジトリの `.wholework.yml` に `merge-strategy` を追記すると、このリポジトリ自身の `/merge` 挙動が変わってしまう。Post-merge AC が要求する `merge-strategy: merge` の設定は、AC 実施時に人間が一時的に行う手動操作として扱う。実装コミットには含めない
- **`gh pr merge --merge` の対話プロンプト**: `gh pr merge` は戦略フラグを 1 つも渡さない場合にのみ対話プロンプトを出す。`/merge` は常に戦略フラグを明示して発行するため、非 TTY の headless 実行でもプロンプトは発生しない
- **新規分岐ロジックに対する新規テストケース要件**: Implementation Steps 1 (新規スクリプトの enum 分岐・フォールバック分岐) と Step 4 (SKILL.md 側の戦略解決経路) が新規分岐に該当する。対応する `command` 型 AC (`command "bats tests/resolve-merge-strategy.bats"`) は、既存スイートの PASS だけでなく Step 2 に列挙した 11 件の新規テストケースを追加したうえでの PASS を要求する。この対応関係は各 AC に併記した `grep "<新規テスト名>" tests/resolve-merge-strategy.bats` により機械的に担保される
- **`docs/ja/*` の verify command**: 本 Spec の verify command のうち `docs/ja/` を対象にするのは `file_contains "docs/ja/guide/customization.md" "merge-strategy"` のみで、パターンは言語非依存の設定キー名。日本語文の書式に影響しない
- **BRE メタ文字チェック**: `grep` 型 verify command 3 件のパターン (`flag mode: merge-strategy merge resolves` / `flag mode: unset merge-strategy falls back` / `invalid merge-strategy falls back to squash and warns`) はいずれも `\|` `\(` `\)` `\+` `\?` を含まず、先頭が `-` でもない (ripgrep がフラグと誤認しない)。ERE 書き換えの必要なし
- **patch route verify command チェック**: Size L (pr route) かつ Diff-less Axis の判定基準を満たさない (`## Changed Files` にリポジトリ内ファイル多数、`## Implementation Steps` はすべてファイル編集) ため、`github_check "gh pr checks"` 非互換のチェックは非該当。そもそも本 Spec に `github_check` 型の verify command はない
- **`docs/migration-notes.md`**: sync candidate から除外。本 Issue は既存スクリプトの CLI シグネチャ・フラグ・引数順を変更しないため (新規スクリプトの追加のみ)、scope rule に従い対象外

## issue retrospective

### 曖昧性解決の判断根拠

- **不正値時の警告出力先**: ターミナルログのみとし、Issue コメント等への永続化は不要と判断。`watchdog-timeout-seconds` / `verify-max-iterations` など `modules/detect-config-markers.md` 内の既存の不正値フォールバックがいずれも「デフォルトにフォールバックしてログ警告を出す」という同一パターンを踏襲しており、`merge-strategy` のみ別扱いにする理由がないため。
- **Post-merge AC の検証環境**: 外部の別プロジェクトではなく、wholework 自身のリポジトリで検証する方針に決定。`gh api repos/{owner}/{repo}` で確認したところ本リポジトリは `allow_merge_commit: true` / `allow_rebase_merge: true` が有効で squash 以外の戦略も実際に選択可能であり、外部プロジェクトを新設する必要がない。

### Acceptance Criteria の変更理由

元の Issue 本文は Pre-merge / Post-merge を見出しのみで区切ったプレーンな箇条書きだったため、以下を実施:

- 全条件を `- [ ]` チェックボックス形式に変換 (`/verify` 等のダウンストリーム処理が `^- \[[ xX]\]` パターンでパースするため)
- 機械検証可能な条件に `file_contains` / `command` / `rubric` の verify command を付与
  - `merge-strategy` 分岐のテスト確認は `tests/run-merge.bats` (既存ファイル、追加ケースで対応) への `command "bats tests/run-merge.bats"` を割り当て
  - SSoT テーブル追加・customization.md 追記は `file_contains` で機械検証
  - `docs/workflow.md` 等の squash 断定表現の条件付き化は具体的な文言が `/spec` で決まるため `rubric` を主軸とし、`file_contains "docs/workflow.md" "merge-strategy"` を補助チェックとして追加
- Post-merge の 1 件に `verify-type: manual` を付与 (実プロジェクトでの `/auto` 実走確認が必要なため)

## spec retrospective

### Minor observations

- Issue 本文の Scope が挙げていた squash 断定表現の対象は `docs/workflow.md` / `docs/tech.md` (JA ミラー含む) の 4 ファイルだったが、`grep -rn "squash" docs/` の実査で `docs/guide/workflow.md:111` / `docs/ja/guide/workflow.md:107` にも同種の user-facing な断定が存在した。`/issue` の Scope 起草時点で `docs/` 配下を再帰的に grep していれば拾えた漏れ。
- 同じ実査で `docs/structure.md:100` / `docs/ja/structure.md:93` の skills テーブル merge 行 (`Squash merge and branch deletion`) と `modules/` 配下 3 件 (`worktree-lifecycle.md` / `l0-surfaces.md` / `orchestration-fallbacks.md`) にも squash 断定が見つかった。合計すると Issue 本文が想定していた 4 ファイルに対し実際の対象は 11 ファイルで、約 2.75 倍。
- Steering Docs sync candidate の discriminating-power filter は本 Issue ではほぼ機能しなかった: `merge-strategy` / `resolve-merge-strategy.sh` は新規のため一致 0 件、`detect-config-markers.md` (111 件) と `reclaim-stale-worktrees.sh` (10 件) はいずれも閾値 8 を超えてスキップ。実際の sync candidate は本 Issue 固有の `grep -rn "squash"` スイープで特定した。新規シンボルを導入する Issue では、キーワード検索より「置き換え対象の旧概念語」でのスイープのほうが検出力が高い。

### Judgment rationale

- **Issue 本文の AC が指定した検証先 (`tests/run-merge.bats`) を採用しなかった**: `tests/run-merge.bats` の検証対象は `scripts/run-merge.sh` (bash wrapper) であり、戦略解決を含まない。Issue の AC は「テストで確認できる」という要求を書いていたが、実装対象を SKILL.md の散文に置いたままではその要求自体が満たせない。設計側 (`scripts/resolve-merge-strategy.sh` への抽出) と検証側 (新規 `tests/resolve-merge-strategy.bats`) を同時に変更することで初めて AC が意味を持つ、という構造だった。
- **`bats --filter` ではなく grep + フルスイートの 2 段構えを選んだ**: Triage AC audit コメントの当初案は `bats --filter` への絞り込み (#1279 が採用した修復パターン) だったが、`--filter` が 0 件マッチでも exit 0 になる同型のギャップが #1334/#1363 で既に指摘されている。#1103 がより新しい precedent として grep + フルスイートを採用しており、そちらに合わせた。audit コメントの提案をそのまま採らなかった判断であり、Notes に理由を明記した。
- **`.wholework.yml` 本体に `merge-strategy` を書かない**: 本リポジトリの設定ファイルにキーを追記すると、このリポジトリ自身の `/merge` 挙動が実装コミットの時点で変わってしまう。Post-merge AC が要求する設定は AC 実施時の一時的な手動操作として切り離した。self-hosting リポジトリ特有の、実装と検証環境が同一であることに起因する判断。

### Uncertainty resolution

- **`gh pr merge` の戦略フラグと `--delete-branch` の併用可否**: `gh pr merge --help` の実行で `-m/--merge` `-r/--rebase` `-s/--squash` `-d/--delete-branch` がいずれも独立フラグであることを確認し、設計時点で解決。散文推測に頼らず実機の help 出力を取ったのが有効だった。
- **本リポジトリでの Post-merge AC 実施可否**: `gh api repos/{owner}/{repo}` で `allow_merge_commit: true` / `allow_rebase_merge: true` を確認済み。Issue 本文の Auto-Resolve Log が同じ確認を既に済ませていたため、追認のみで済んだ。
- **`git merge origin/main --ff-only` の 3 戦略での成立性**: git の ancestry 特性からの演繹で解決 (squash = 新規コミット 1 個、merge commit = 第 1 親が旧 main、rebase = 旧 main の上に再構成 — いずれも worktree ブランチ tip が新 `origin/main` の ancestor になる)。実機確認は Post-merge AC が兼ねる形にした。既定の squash 経路は変更しないため、前提が崩れても既定挙動には影響しないという退避線を Uncertainty セクションに明記した。

## Code Retrospective

### Deviations from Design

- Implementation Step 3 は Marker Definition Table の行追加と YAML Parsing Rules の箇条書き追加のみを指示していたが、同じファイル内の `## Output Format` ブロック (30 件超の既存キーが `KEY: 説明 (default: ...)` 形式で列挙されている) にも `MERGE_STRATEGY` の 1 行を追加した。同一ファイル内の内部整合性を保つための追加で、他ファイルへの波及はない。

### Design Gaps/Ambiguities

- Implementation Step 2 が指定した bats テスト名「empty merge-strategy falls back to squash and warns on stderr」は、Implementation Step 1 が指示した呼び出し形 `get-config-value.sh merge-strategy squash` (デフォルト値 `squash` を渡す) の下では文字どおりの空値では再現できない — `get-config-value.sh` 自身の `[ -z "$VALUE" ]` チェックが、値が本当に空の場合は渡されたデフォルト `squash` に差し替えてしまうため、`merge-strategy: ""` は resolve-merge-strategy.sh に届く前に `squash` へ収束し、warning が発火しない (unset キーと区別がつかない)。`get-config-value.sh` の quote-strip ロジック (2 段の `sed` 適用) を辿ると、クォート付きの単一スペース値 (`merge-strategy: " "`) は長さ 1 の非空文字列として `[ -z ]` チェックを通過し、`squash`/`merge`/`rebase` いずれにも一致しない値として resolve-merge-strategy.sh に届く — このテストケースのみこの入力を採用して warning 経路を再現した。Spec 側にこの `get-config-value.sh` の挙動との相互作用は明記されていなかった。

### Rework

- Implementation Step 2 の「get-config-value failure falls back to squash (fail-closed)」テストは、当初 `run bash "$SCRIPT"` (bats の `--separate-stderr` なし) で書いたところ FAIL した。原因はスクリプトのフォールバック挙動の不具合ではなく、stderr の warning 文字列が `$output` に混入し `[ "$output" = "squash" ]` が一致しなくなったこと。同スイート内の他 3 テストは既に `run --separate-stderr` を使っていたが、このテストにだけ付け忘れていた。`run --separate-stderr` を追加して解決。

## review retrospective

### Spec と実装の乖離パターン

- **fail-safe critical の「全列挙」が、検証されない列挙になっていた**。Spec の Implementation Steps 1 は空値・特殊文字・CRLF・依存コマンド失敗を明示列挙し「fail-safe critical」と宣言していたが、そのうち 2 項目 (空値 → 警告あり / 依存失敗 → 無警告) が実装挙動と逆だった。列挙そのものは詳細だったが、列挙の各項目に対応する検証手段が担保されていなかったのが構造的な原因。**教訓: fail-safe critical 指定を付けた Spec では、列挙項目ごとに「その項目を落としたらどのテストが落ちるか」を Implementation Steps 側で明記する**。
- **Spec 由来の事実誤認がそのまま実装に転写された**。Implementation Steps 9 の「`merge-strategy` が `merge` / `rebase` の場合は ancestry が保存される」は rebase について誤り (GitHub の Rebase and merge は全コミットの SHA を書き換える)。`/code` は Spec を忠実に転写しただけで、欠陥の発生源は Spec 側。外部サービスの挙動に依存する前提を Spec に書く場合、`/spec` 段階での裏取りが必要だった。
- **セキュリティ境界の見落としは、Spec が「戦略非依存で影響しない箇所」を調査した裏返しで起きた**。Issue 本文は completion signature / Issue 自動クローズ / patch route を調査済みとして列挙したが、「`.wholework.yml` をどのブランチから読むか」という軸は列挙になかった。conflict path で `git checkout headRefName` が同一 worktree 内で走るため、PR 自身が自分のマージ戦略を選べる経路が残っていた。

### 繰り返し発生した問題

- **テスト名と検証内容の不一致が、両方の MUST の共通原因**。`empty merge-strategy falls back to squash and warns on stderr` はクォート付き単一スペースを使い、`get-config-value failure falls back to squash (fail-closed)` は `--separate-stderr` を要求しながら `$stderr` を一切見ていなかった。`/code` の Code Retrospective はこの制約を「発見して記録」していたが、**記録先が Spec の Design Gaps であって、実装かドキュメントの修正には至らなかった**。既知の制約を retrospective に書いて済ませると、レビューまで残る。
- **断定表現の一括置換で、grep 対象ディレクトリの選定漏れが起きた**。spec retrospective は `grep -rn "squash" docs/` と `modules/` を記録しているが `scripts/` を含めておらず、`scripts/run-auto-sub.sh` が漏れた。さらに `modules/orchestration-fallbacks.md` は同一ファイル内で 552 行目だけ中立化され 487 行目が残るという、ファイル内不整合まで生じた。**教訓: 表現の一括中立化 AC では、grep 対象を「リポジトリ全体マイナス除外リスト」で定義する (対象ディレクトリの列挙にしない)**。

### 受入基準の検証しやすさ

- AC 1〜3 の「新規テスト名の `grep` + フルスイート `command`」2 段構え (Triage AC audit → `/spec` の対応) は**設計意図どおり機能した**。新規テストファイルなので実装前は確実に FAIL し、`bats --filter` の 0 件マッチ問題も回避できている。この precedent (#1103) は今後も有効。
- 一方で、**この 2 段構えは「テストが存在し、かつ PASS する」ことしか保証しない**。テストが主張どおりの入力を使っているかは検証しない。本 PR の 2 件の MUST はいずれもこの隙間から抜けた。AC が `grep "<test name>"` でテスト名を固定する形式を採る場合、テスト名が実際の fixture と乖離してもゲートは通過する — この構造的ギャップは記録に値する (改善提案としては `/verify` で集約)。
- UNCERTAIN は 0 件。7 件の Pre-merge AC はすべて決定的に検証でき、verify command の品質自体は高かった。
- 検出の実効性という点では、**parser/validator edge case pre-check (実コード実行) が最大の貢献**をした。2 件の MUST はいずれも diff の静的読解では出ず、18 種の fixture で実際にスクリプトを走らせて初めて観測できたもの。firing condition (c)「外部由来の文字列を解釈・検証するスクリプト」に正しくマッチした事例。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- 本 PR (#1459) 自身のマージは `.wholework.yml` に `merge-strategy` を未設定のまま、従来どおり `--squash --delete-branch` で実行した。新しい戦略解決経路 (Step 2 末尾) は実装済みだが、このマージ自体は挙動確認の対象ではない。
- `gh pr merge "1459" --squash --delete-branch` は問題なく完了し、mergeable=true / CI success / review approved の状態から追加の conflict resolution は不要だった。

### Deferred Items

- Post-merge AC (`merge-strategy: merge` または `rebase` を実際に設定した状態で `/auto` を実行し、merge フェーズを通過することを確認する) は `verify-type: manual` のまま未実施。次フェーズ (`/verify`) または人手での実施が必要。
- `get-config-value.sh` のフラットキー検索が任意インデントにマッチする既知の非対称挙動、および「テスト名 grep だけでは入力内容の妥当性を保証しない」という構造的ギャップは、本 PR の scope 外のまま据え置き。

### Notes for Next Phase

- `/verify` は Post-merge AC (`merge-strategy: merge`/`rebase` 実走確認) が `verify-type: manual` である点に注意。自動検証では PASS/FAIL を確定できないため、人手確認の依頼または明示的な保留記録が必要。
- 今後 wholework 自身のリポジトリで `merge-strategy` を変更する場合、戦略解決は `skills/merge/SKILL.md` Step 2 末尾 (worktree Entry 直後) で行われる点を踏まえること。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (曖昧性解決の判断根拠 2 件 [不正値時の警告出力先はターミナルログのみ / Post-merge AC の検証環境は wholework 自身のリポジトリ] と AC のチェックボックス化・verify command 付与の理由を記録) / https://github.com/saitoco/wholework/issues/1457#issuecomment-5579668103
- saito / MEMBER / first-class / Triage AC audit (Pre-merge AC 1〜3 の `command "bats tests/run-merge.bats"` が実装前の main で既に 36 ケース全 PASS するため常時 PASS であると指摘し、新規テスト名への絞り込みを提案 — 本 Spec は Notes 記載のとおり検証先を新規 `tests/resolve-merge-strategy.bats` に変更したうえで grep + フルスイートの 2 段構えで対応) / https://github.com/saitoco/wholework/issues/1457#issuecomment-5579705356
