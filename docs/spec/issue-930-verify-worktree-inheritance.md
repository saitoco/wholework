# Issue #930: verify: opportunistic dispatch 経由の nested /verify が親 worktree/CWD を継承する構造的問題

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (`/issue 930 --non-interactive` の実行結果。AC 適用範囲を `/review` 単独から `/review` + `/auto` の両エミッターに拡大したこと、Post-merge AC の `verify-type` を `opportunistic` から `observation event=<name>` へ修正したことを記録。いずれも Issue body に既に反映済みで、本 Spec 作成時点で追加のアクションは不要) / https://github.com/saitoco/wholework/issues/930#issuecomment-4885654899

## Overview

`/review`・`/auto` が Opportunistic Verification / Event-based observation scan の完了時に `Skill(skill="wholework:verify", args="$N")` を dispatch する際 (`/auto` は同フローに加え、通常フロー内の verify phase 実行でも同じ `Skill()` 呼び出しを行う)、その `Skill()` 呼び出しは呼び出し元セッションと同一コンテキストで実行されるため、CWD が呼び出し元の worktree に残ったままだと nested `/verify` の commit がその worktree の branch (呼び出し元 Issue のブランチ) に混入してしまう。

根本原因は `modules/worktree-lifecycle.md` Entry section の `test -f .git` 判定にある。この判定は「worktree の中にいるか否か」しか区別できず、「今いる worktree が **自分自身の** worktree か、**他フェーズ由来の foreign worktree** か」を区別できない。foreign worktree 内で `test -f .git` が true になると `ENTERED_WORKTREE=false` と誤判定され、`EnterWorktree` がスキップされたまま以降の commit がその foreign worktree の branch に対して実行される。Exit 時も `ENTERED_WORKTREE=false` の分岐 (`ExitWorktree` を呼ばずそのまま `git push origin main`/`git push origin <base>` を実行、または `/review`・`/merge` の push-and-remove 分岐では Exit 自体がスキップされる) を通るため、foreign worktree から一度も抜け出せない。

この構造的ギャップは `/verify` だけでなく、`worktree-lifecycle.md` の Entry section を参照する `/spec`・`/code`・`/review`・`/merge` の全 5 skill に共通して存在する (`## Callers` テーブル参照)。実際に Session 68567-1783235854 (2026-07-05) で観測された事象は、`/code 902` (pr route) の worktree (`worktree-code+issue-902` branch) が正常に Exit されないまま残存し、後続の `/review 928 --full` がその CWD を引き継いで自分の Worktree Entry で foreign worktree を「自分の worktree」と誤認、そのまま Opportunistic Verification → Event-based observation scan で nested `Skill(wholework:verify, args="794")` を dispatch、`/verify` 自身の Worktree Entry (Step 3) も同じ誤判定を繰り返し、Verify Retrospective の commit が `worktree-code+issue-902` branch に混入した (詳細: `docs/reports/orchestration-recoveries.md` 「2026-07-05 08:37 UTC: nested-verify-committed-to-review-worktree」、および隣接する「2026-07-05 07:35 UTC: code-pr-silent-no-op」)。

本 Spec では、`modules/worktree-lifecycle.md` の Entry section に「今いる worktree が自分の worktree か foreign worktree かを判定し、foreign であれば一旦メインリポジトリ root に戻ってから通常の `EnterWorktree` フローに合流する」という判定ロジックを追加する。5 skill 共通の shared module 一箇所を修正することで、`/verify` 単体・`/review`/`/auto` からの nested dispatch・将来の呼び出し元のいずれに対しても同一の安全策が適用される。

## Changed Files

- `scripts/detect-foreign-worktree.sh`: new file — CWD が「worktree 外」「自分の worktree 内」「foreign worktree 内」のいずれかを判定し、foreign の場合はメインリポジトリ root のパスを返すスクリプト
- `tests/detect-foreign-worktree.bats`: new file — 上記スクリプトの3状態 + 引数欠如エラーを検証する bats テスト
- `modules/worktree-lifecycle.md`: change — Entry section Step 1 の `test -f .git` のみに基づく判定を、`detect-foreign-worktree.sh` を呼び出す3分岐判定に置き換え
- `skills/spec/SKILL.md`: change — allowed-tools frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh:*` を追加
- `skills/code/SKILL.md`: change — 同上
- `skills/review/SKILL.md`: change — 同上
- `skills/merge/SKILL.md`: change — 同上
- `skills/verify/SKILL.md`: change — 同上
- `docs/structure.md`: change — Directory Layout の `scripts/` ファイル数コメントを `(64 files)` → `(65 files)` に更新し、Key Files > Scripts > Process management リストに `detect-foreign-worktree.sh` の説明を追加
- `docs/ja/structure.md`: change — 上記2点の日本語ミラーを同期 (`docs/translation-workflow.md` Sync Procedure 準拠。`docs/spec/` 配下ではないため sync 対象)

## Implementation Steps

1. `scripts/detect-foreign-worktree.sh` を新規作成する (→ acceptance criteria 1)。仕様:
   - Usage: `detect-foreign-worktree.sh <worktree-name>` (`<worktree-name>` は呼び出し元が `EnterWorktree` の `name` に渡すのと同じ値。例: `verify/issue-794`)
   - `set -euo pipefail` を先頭に置く
   - **引数欠如**: `$#` が1未満の場合、`Usage: $0 <worktree-name>` を stderr に出力し exit 1 (以降の分岐には進まない)
   - **worktree 外**: `test -f .git` が false (通常ディレクトリ) の場合、stdout に `none` の1行を出力し exit 0
   - **自分の worktree 内 (own)**: `test -f .git` が true、かつ `EXPECTED_BRANCH="worktree-${1//\//+}"` (`/` を `+` に置換) が `git rev-parse --abbrev-ref HEAD` の出力と一致する場合、stdout に `own` の1行を出力し exit 0
   - **foreign worktree 内**: `test -f .git` が true、かつ現在のブランチが `EXPECTED_BRANCH` と不一致の場合、`git worktree list --porcelain` を実行し最初の `worktree ` 行 (git の仕様上、常にメインリポジトリ root) のパスを `awk '/^worktree /{print $2; exit}'` で抽出し、stdout に `foreign <path>` (スペース区切り2トークン) を出力し exit 0
   - **git コマンド失敗時**: `set -euo pipefail` によりスクリプト自体が git のエラーメッセージを stderr に出力して非ゼロ終了する。追加のフォールバック処理は行わない (`.git` ファイルが存在するにも関わらず `git rev-parse`/`git worktree list` が失敗するのは環境異常であり、正常系として扱わない)
   - **監視継続**: なし (1回の判定で exit する一回性スクリプト)
2. `tests/detect-foreign-worktree.bats` を新規作成する (after 1) (→ acceptance criteria 2)。`tests/pre-merge-check.bats` に倣い実際の `git init`/`git worktree add` を用いる (git バイナリのモック化はしない)。最低限のケース:
   - "not in a worktree -> none": 通常の git リポジトリ直下で `detect-foreign-worktree.sh verify/issue-794` を実行し、stdout が `none`、exit code が0であることを検証
   - "in own matching worktree -> own": `git worktree add -b worktree-verify+issue-794 <path>` で作成した worktree 内で同スクリプトを実行し、stdout が `own` であることを検証
   - "in a foreign worktree -> foreign + main repo root": `git worktree add -b worktree-code+issue-902 <path>` で作成した (別 Issue 相当の) worktree 内で `detect-foreign-worktree.sh verify/issue-794` を実行し、stdout の1トークン目が `foreign`、2トークン目がメインリポジトリの絶対パスと一致することを検証
   - "missing argument -> usage error": 引数なしで実行し、exit code が1、stderr に `Usage` を含むことを検証
3. `modules/worktree-lifecycle.md` の Entry section Step 1 を書き換える (after 1) (→ acceptance criteria 1)。現行の

   ```
   1. **Determine if already in a worktree**: Run `test -f .git`
      - **If file (inside worktree)**: Already running inside a worktree. Record `ENTERED_WORKTREE=false` and skip EnterWorktree, proceeding to the next step
      - **If directory (normal repository)**: Record `ENTERED_WORKTREE=true` and proceed to the next step
   ```

   を、次の3分岐判定に置き換える:

   ```
   1. **Determine worktree context**: Run `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh "$WORKTREE_NAME"` (pass the same value used for `EnterWorktree`'s `name` parameter in step 2):
      - **Output `none`** (not inside any worktree): Record `ENTERED_WORKTREE=true` and proceed to the next step
      - **Output `own`** (already inside the worktree matching `WORKTREE_NAME`): Record `ENTERED_WORKTREE=false` and skip EnterWorktree, proceeding to the next step
      - **Output `foreign <path>`** (inside a *different* worktree — e.g. inherited via a nested `Skill()` dispatch from a parent phase's Opportunistic Verification / Event-based observation scan, or a leftover worktree from a prior phase that was never exited): run `cd <path>` to return to the main repository root, then record `ENTERED_WORKTREE=true` and proceed to the next step exactly as in the `none` case (this creates the skill's own properly isolated worktree instead of silently operating — and potentially committing — inside the foreign one)
   ```

   Step 2 (`Only when ENTERED_WORKTREE=true: Call EnterWorktree(name: WORKTREE_NAME)`) 以降は変更しない。`WORKTREE_NAME` は Entry section の既存 Input として各 skill から渡されており、新規入力は不要。
4. `skills/spec/SKILL.md`・`skills/code/SKILL.md`・`skills/review/SKILL.md`・`skills/merge/SKILL.md`・`skills/verify/SKILL.md` の frontmatter `allowed-tools` の `Bash(...)` グループ内、既存の `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh:*` の直前または直後に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh:*` を追加する (parallel with 2, 3) (→ acceptance criteria 1)。5ファイルとも機械的に同一パターンの追加のみ。
5. `docs/structure.md` の Directory Layout コメント `scripts/ ... (64 files)` を `(65 files)` に更新し、Key Files > Scripts > **Process management** リストの `scripts/worktree-merge-push.sh` エントリの直後に `scripts/detect-foreign-worktree.sh` — detect whether CWD is inside a foreign (different-owner) git worktree; used by `modules/worktree-lifecycle.md` Entry section を追加する。`docs/ja/structure.md` にも同じ2点の日本語ミラーを同期する (after 1) (SHOULD レベル。`docs/translation-workflow.md` Sync Procedure 準拠)

## Verification

### Pre-merge

- <!-- verify: rubric "対応する skill/script/module に、opportunistic dispatch 経由の /verify が親コンテキストの worktree に誤コミットしない構造が実装されている" --> `Skill()` 経由で opportunistic dispatch された `/verify` が、呼び出し元が worktree 内であっても Verify Retrospective 追記を親リポジトリ (origin/main 直コミットではなく worktree branch 経由 → merge-push、または main worktree からの直接 commit) に安全にコミットする仕組みが実装されている
- <!-- verify: rubric "追加された分離機構について、テストコード (bats/pytest 等) が存在する" --> 上記構造について bats テスト等の自動検証が追加されている

### Post-merge

- 次回 `/review --full` 完了時に `pr-review-full` イベントで opportunistic verify が dispatch されたセッションで、nested `/verify` のコミット先が期待通り (親 worktree に混入せず、正規フロー内で main に到達) であることを観察 <!-- verify-type: observation event=pr-review-full -->
- 次回 `/auto` 完了時に `auto-run` イベントで opportunistic verify が dispatch されたセッションで、nested `/verify` のコミット先が期待通り (worktree 内での実行であっても main に安全に到達) であることを観察 <!-- verify-type: observation event=auto-run -->

## Tool Dependencies

### Bash Command Patterns
- `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh:*`: 新規スクリプトの実行許可 (5 skill の allowed-tools に追加。内部で呼ぶ `git rev-parse`/`git worktree list` は本コマンドパターンの承認に包含され個別追加は不要— 既存の `worktree-merge-push.sh` 等と同型)

### Built-in Tools
- none (追加なし)

### MCP Tools
- none

## Uncertainty

- **`EnterWorktree` の CWD 解決タイミング**: Bash tool による `cd <path>` 実行直後に `EnterWorktree(name: WORKTREE_NAME)` を呼んだ場合、ツールが post-cd の CWD を正しく解決してそこを起点に新規 worktree を作成することを前提とした設計になっている。この挙動はツールの公開ドキュメント上に明記された保証ではなく、既存コードベースの慣習 (`modules/worktree-lifecycle.md` 自身の node_modules symlink snippet における `git worktree list` 起点パスの扱いや、Bash tool の CWD 永続性への既存の依存パターン) からの類推に基づく。
  - **検証方法**: Post-merge の observation AC (次回の実 `/review --full`・`/auto` 実行) で直接確認される。想定外の挙動 (EnterWorktree が拒否する、誤ったリポジトリを起点にする等) が発生した場合はそこで顕在化する。
  - **影響範囲**: Implementation Step 3 (`modules/worktree-lifecycle.md` Entry section)。
- **Session 68567-1783235854 における foreign CWD 発生経路の完全な再現**: `docs/reports/orchestration-recoveries.md` の隣接する2エントリ (`code-pr-silent-no-op`と`nested-verify-committed-to-review-worktree`) から、`/code 902` の worktree が Exit されずに残存したこと、および `/auto` 親セッションが手動リカバリのため `EnterWorktree(path=...)` で該当 worktree に入った可能性があることまでは追跡できたが、`/review`・nested `/verify` 双方が具体的にどの経路で foreign CWD を引き継いだか (nested `Skill()` の直接継承か、`run-review.sh` サブプロセスが親シェルの dangling CWD を継承したものか) は完全には再現できていない。
  - **検証方法**: 本 Spec の修正は経路に依存せず「現在のブランチ名が期待値と一致するか」のみで foreign 判定を行うため、この不確実性は実装設計そのものには影響しない。
  - **影響範囲**: Overview の root cause 記述のみ (実装ステップには影響なし)。

## Notes

### Ambiguity Resolution (Auto-Resolve Log — non-interactive mode)

- **論点**: Issue body の "Options (outline)" (Option A: `/verify` 自身が opportunistic dispatch 経由かを判定し親 worktree に戻ってから commit / Option B: `observation-trigger.sh` 等のディスパッチャ側が worktree 内からの呼び出し検出時に同期 dispatch せず deferred queue に積む / Option C: `/review`・`/auto` が Opportunistic Verification Step 実行前に main worktree に戻る) のうち、どれを採用するか。
- **自動解決 (非対話モードのため AskUserQuestion 不使用)**: Option A を一般化し、`/verify` 個別ではなく `modules/worktree-lifecycle.md` の Entry section (spec/code/review/merge/verify 全5 skill が共有) に実装する。
- **判断根拠**:
  - Option C (dispatch 直前に main へ戻る) は手遅れであることが判明した: `/review` 自身の Worktree Entry (Step 2) の時点で、既に同じ `test -f .git` の曖昧性により foreign worktree (`/code` の残存 worktree) を「自分の worktree」と誤認しており、Opportunistic Verification に到達する前に CWD が汚染されている。dispatch 直前のガードでは間に合わない。
  - `/auto` は Event-based observation scan による dispatch に加え、pr route Step 15・patch route Step 8 で通常フローの一部として直接 `Skill(skill="wholework:verify", args="$NUMBER")` を呼んでおり、Option C を採用する場合は `auto/SKILL.md` 内の複数の呼び出し箇所すべてに個別のガードを追加する必要がある。shared module 一箇所の修正で全呼び出し箇所を一律にカバーする方が単純かつ再発防止力が高い。
  - Option B (deferred queue 化) は `modules/observation-trigger.md` の Trigger Interface (同期的な JSON 配列返却契約) を非同期契約に変更する必要があり、実際の根本原因 (Entry 時点での CWD 誤判定) に対して不釣り合いに大きい変更になる。
  - `docs/tech.md` の "Shared module pattern" および "Distributable-first improvement principle" に照らし、5 skill 共通の SSoT である `worktree-lifecycle.md` を1箇所直すことで将来の呼び出し元にも同じ安全策が及ぶ。
- **不採用とした候補**: Option C 単独 (上記の通り時点が遅い)、Option B (スコープが不釣り合いに大きい)。

### Steering Docs sync candidate 調査について

`docs/structure.md`/`docs/ja/structure.md` 以外の `docs/*.md` を、変更対象の skill 名 (`spec`/`code`/`review`/`merge`/`verify`) をキーワードに `grep` する手法は、これらが Wholework の中核 skill 名でありほぼ全 doc に出現するため誤検知が支配的と判断し、代わりに新規アーティファクト名 (`detect-foreign-worktree`) と変更対象モジュール名 (`worktree-lifecycle`、旧ロジック文字列 `test -f .git`) で `docs/*.md` `docs/ja/*.md` を検索した。結果、`docs/structure.md`/`docs/ja/structure.md` のスクリプト一覧・ファイル数以外に同期が必要な箇所は見つからなかった (`docs/guide/*.md` はこの内部メカニズムに言及していない)。

### Verify command sync 確認

本 Spec の `## Verification > Pre-merge` は Issue 本文 `## Acceptance Criteria > Pre-merge` の2項目と verify コマンドを含め完全一致 (件数一致: Issue側2件 / Spec側2件)。Post-merge も Issue 本文の2件と一致 (`verify-type: observation event=pr-review-full` / `event=auto-run` を含め verbatim コピー)。

### 影響を受けない箇所の確認

`modules/worktree-lifecycle.md` の Exit section (merge-to-main / push-and-remove いずれも) は `ENTERED_WORKTREE` の値のみで分岐しており、本修正後も foreign worktree 検出時は `ENTERED_WORKTREE=true` に正規化されるため、Exit section 自体への変更は不要 (既存の `ENTERED_WORKTREE=true` 分岐がそのまま正しく機能する)。`modules/observation-trigger.md`・`modules/opportunistic-verify.md` の dispatch contract もこの修正により変更不要 (dispatch は同期のまま、dispatch **先**の `/verify` 自身が安全になる)。
