# Issue #165: refactor: /auto のエラー自動復旧機能を除去

## Overview

`/auto` が持つ 3 つのエラー自動復旧経路（watchdog の自動リトライ、verify の UNCERTAIN → 自動 reopen、`fix-cycle` ラベルによる patch route 強制ジャンプ）をすべて除去し、失敗時はユーザーが 1 回手動介入するシンプルなモデルに戻す。`fix-cycle` ラベル自体を廃止し、verify FAIL 時の reopen メッセージで `/code --patch N` を Size 非依存で推奨する guidance に置換する。fix-cycle 本来のユースケース（Size L の Issue が verify 後に patch route で修正される）は、既存の `--patch` フラグ（Size オーバーライド）で代替する。

## Changed Files

- `scripts/claude-watchdog.sh`: retry ブロック（行 81-90 相当）削除。kill 時メッセージを `retrying disabled; please re-run the skill manually` に変更
- `tests/claude-watchdog.bats`: `retry:` テスト削除、`no retry:` テストを「リトライなし」の期待に書き換え、`watchdog timeout:` の期待から `retry also killed` を削除
- `skills/verify/SKILL.md`: Issue CLOSED/OPEN 両 path で FAIL と UNCERTAIN を分離。FAIL 含む → reopen（CLOSED の場合のみ）+ phase/* 削除、UNCERTAIN のみ → reopen せず phase/verify 付与 + 通知。fix-cycle ラベル作成・付与コマンド削除。reopen 完了メッセージに `/code --patch N` / `/code --pr N` / `/spec N` の guidance 追加
- `scripts/setup-labels.sh`: `fix-cycle` ラベル行削除（11 → 10 ラベル）
- `tests/setup-labels.bats`: 期待ラベル数 11 → 10 に変更、`fix-cycle` label name/color テストケース削除
- `skills/auto/SKILL.md`: Step 3 の「Fix-cycle Pre-check」ブロック全体削除、Step 4 の「Defensive fix-cycle check before sub-issue graph expansion」段落削除
- `skills/code/SKILL.md`: Step 0 の「Fix-cycle Detection」ブロック全体削除、Step の「Post-verify fix append」ブロック全体削除
- `skills/spec/SKILL.md`: full template 内の `## Post-verify fix` section（`### Fix Cycle 1` サブセクション含む）削除
- `modules/next-action-guide.md`: verify fail 行の `<!-- fix-cycle label auto-applied ... -->` コメント削除（推奨コマンド `/code {ISSUE_NUMBER}` は維持）
- `modules/size-workflow-table.md`: 「Fix-cycle Override」section（見出し + 本文 + 3 行テーブル、行 54-62 相当）削除
- `docs/product.md`: Terms テーブルから `Fix cycle` 行削除
- `docs/workflow.md`: ラベル遷移テーブルから `fix-cycle` 行削除、「Post-verify Fix Cycle」section を「Verify Fail User Intervention」等に書き換え（fix-cycle ラベル/自動ジャンプ記述を排除し `/code --patch N` / `/code --pr N` / `/spec N` の手動選択フローを説明）
- `docs/guide/workflow.md`: 「Fix Cycle」section を書き換え（`/verify` FAIL 時に Issue が reopen される旨と `/code --patch N` を手動実行する案内、`fix-cycle` ラベルへの言及を削除）

## Implementation Steps

**Step 記録ルール:**
- ステップ番号は整数。受入条件マッピングは `(→ AC: <キーワード>)` で示す。

1. **A. watchdog リトライ除去**: `scripts/claude-watchdog.sh` の末尾リトライ分岐（`watchdog: retrying once...` を含む `if [[ "$_watchdog_killed" == "true" ]]; then ... fi` ブロック）を、kill 時のみ `watchdog: retrying disabled; please re-run the skill manually` を stderr に出力する分岐に置換する。`_run_with_watchdog` の 2 回目呼び出しを削除し、単一実行の exit code をそのまま `exit` に渡す。`_watchdog_killed` フラグは新メッセージの分岐条件として保持する。（→ AC: A1 retry メッセージ削除, A2 新メッセージ実装）

2. **A. watchdog テスト書き換え** (after 1): `tests/claude-watchdog.bats` の `@test "retry: second invocation occurs after watchdog kill"` を削除。`@test "no retry: watchdog fires only once on second hang"` を `@test "no retry: watchdog kills and does not retry"` に書き換え、期待値を `[ "$(cat "$COUNTER_FILE")" -eq 1 ]`（1 回呼び出しのみ）と `retrying disabled` 文字列の出力確認に変更。`@test "watchdog timeout: ..."` の期待コメントから `retry also killed` を削除。`@test "heartbeat: ..."` の期待は retry に依存しないため現状維持。（→ AC: CI bats）

3. **B. verify UNCERTAIN 分岐導入** (parallel with 1): `skills/verify/SKILL.md` の Step 9 内「When Issue is CLOSED (standard flow via `closes #N`)」セクションの判定ブロックを以下の 3 分岐に再構成する:
   - All PASS/SKIPPED（既存挙動を維持）
   - Auto-verification targets include **FAIL**（UNCERTAIN は含まない判定に変更）: reopen + phase/* 削除 + guidance 出力
   - Auto-verification targets are **UNCERTAIN only**（FAIL なし、UNCERTAIN ≥1）: reopen せず、phase/verify ラベル付与、ユーザーに手動再 verify を通知
   
   同様に「When Issue is OPEN (auto-close disabled)」セクションの FAIL/UNCERTAIN 分岐を以下に再構成:
   - Auto-verification targets include **FAIL**: phase/* 削除 + guidance 出力
   - **UNCERTAIN only**: phase/verify 付与、ユーザーに手動再 verify を通知
   （→ AC: B2 UNCERTAIN のみの reopen 回避）

4. **B+C. verify fix-cycle ラベル付与削除 + guidance 追加** (after 3): Step 3 で再構成した FAIL 分岐の実装から、`gh label list --search fix-cycle | grep -q '^fix-cycle' || gh label create fix-cycle ...` と `gh issue edit "$NUMBER" --add-label "fix-cycle"` の 2 行を削除し、reopen + `gh-label-transition.sh "$NUMBER"`（phase/* 全削除）のみ残す。FAIL 分岐の最後に以下の guidance を出力する指示を追記する:
   ```
   Issue #N を再オープンしました。以下のいずれかで修正してください:
   - `/code --patch N` — Size を変えずに main 直コミットで修正（小さな修正）
   - `/code --pr N` — 新規ブランチ + PR で修正（Size L の大きな修正）
   - `/spec N` — Spec から見直し（根本的な設計変更が必要な場合）
   ```
   （→ AC: B1 fix-cycle ラベル付与削除, C' guidance）

5. **C. setup-labels fix-cycle ラベル定義削除** (parallel with 1): `scripts/setup-labels.sh` の `LABELS=(...)` 配列から `"fix-cycle|#c5def5|Post-verify fix cycle marker — preserves original Size while routing through patch"` 行を削除（11 → 10 エントリ）。`tests/setup-labels.bats` の以下を更新: `@test "success: creates 11 labels"` を `creates 10 labels` に書き換え、`-eq 11` を `-eq 10` に、コメント `(6 phase/* + triaged + 3 type/* + fix-cycle)` を `(6 phase/* + triaged + 3 type/*)` に変更。`--force` の 11 回期待も 10 に変更。`grep -q 'label create fix-cycle' "$GH_CALL_LOG"` の assertion 行削除。`@test "success: completion message includes label count"` の `"$output" == *"11"*` を `"10"` に変更。（→ AC: C setup-labels.sh）

6. **C. auto fix-cycle 参照削除** (parallel with 1): `skills/auto/SKILL.md` の Step 3 冒頭「**Fix-cycle Pre-check (run before phase/* label evaluation):**」から「If ARGUMENTS contains `--patch` or `--pr`, skip fix-cycle detection (explicit user intent takes precedence).」までの 15 行相当を丸ごと削除し、Step 3 本体（phase/* 評価）を直接続ける。Step 4 の XL route 直下の段落「**Defensive fix-cycle check before sub-issue graph expansion**: ...」1 段落を削除。（→ AC: C auto Fix-cycle Pre-check, Defensive fix-cycle check）

7. **C. code fix-cycle 参照削除** (parallel with 1): `skills/code/SKILL.md` の Step 0（ルート決定）内「**Fix-cycle Detection (run before flag/size evaluation):**」から「If ARGUMENTS contains `--patch` or `--pr`, skip fix-cycle detection ...」までのブロック全体を削除。後段の「**Post-verify fix append (run only when fix-cycle was detected in Step 0):**」section（4 項目の記録仕様を含む）全体を削除し、直前の「Sync Spec implementation steps (when deviations exist)」と直後の `**Steps:**` を直接繋ぐ。（→ AC: C code fix-cycle）

8. **C. spec Post-verify fix template 削除** (parallel with 1): `skills/spec/SKILL.md` の full template 例（コードブロック内）から `## Post-verify fix` 見出しと `**(Appended by ...)**` 注記、`### Fix Cycle 1` サブセクションおよびその 4 行（対象 AC/修正内容/コミット/判断根拠）を削除する。直前の `## Notes` セクションの後にコードブロック終端（` ``` `）が直接来るようにする。（→ AC: C spec Post-verify fix）

9. **C. modules fix-cycle 記述削除** (parallel with 1): `modules/next-action-guide.md` の verify fail 行末のコメント `<!-- fix-cycle label auto-applied by /verify; /code and /auto detect it and force patch route -->` を削除（行本体と推奨コマンドは維持）。`modules/size-workflow-table.md` の `### Fix-cycle Override` 見出しと本文段落、および 3 行テーブル（`fix-cycle` label present / `--patch`/`--pr` / No `fix-cycle` の 3 行）を含む section 全体を削除し、直前の「Size-to-Workflow Mapping Table」と直後の「Phase-Level Light/Full Mapping」が隣接するように結合する。（→ AC: C next-action-guide.md, size-workflow-table.md）

10. **C. ドキュメント更新** (parallel with 1): `docs/product.md` Terms テーブルから `Fix cycle` 行（1 行）を削除。`docs/workflow.md` のラベル遷移テーブルから `fix-cycle` 行を削除し、`### Post-verify Fix Cycle` section（見出し + 本文段落 + Mermaid風フロー図ブロック + 後続の size/* 保持説明段落）を削除または書き換えて、「verify FAIL 時、Issue が reopen され phase/* が削除される。ユーザーは `/code --patch N`（Size 変更なし）/ `/code --pr N`（新規ブランチ）/ `/spec N`（設計見直し）のいずれかを選択して再実行する」旨のユーザー介入フロー説明に置き換える。`docs/guide/workflow.md` の `## Fix Cycle` section（2 行）を、fix-cycle ラベルへの言及を削除し `/code --patch N` を手動で実行する旨の案内に書き換える。（→ AC: C product.md, workflow.md, guide/workflow.md）

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/claude-watchdog.sh" "retrying once" --> watchdog の retry メッセージが削除されている
- <!-- verify: file_contains "scripts/claude-watchdog.sh" "retrying disabled" --> kill 時の新メッセージが実装されている
- <!-- verify: file_not_contains "skills/verify/SKILL.md" "add-label \"fix-cycle\"" --> verify SKILL.md で fix-cycle ラベル付与が削除されている
- <!-- verify: section_contains "skills/verify/SKILL.md" "When Issue is CLOSED" "UNCERTAIN のみ" --> UNCERTAIN のみの場合の reopen 回避ロジックが追加されている
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "Fix-cycle Pre-check" --> auto SKILL.md から fix-cycle pre-check セクションが削除されている
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "Defensive fix-cycle check" --> XL route の defensive check も削除されている
- <!-- verify: file_not_contains "skills/code/SKILL.md" "fix-cycle" --> code SKILL.md から fix-cycle 参照が削除されている
- <!-- verify: file_not_contains "skills/spec/SKILL.md" "Post-verify fix" --> spec SKILL.md の Spec template から Post-verify fix section が削除されている
- <!-- verify: file_not_contains "modules/next-action-guide.md" "fix-cycle" --> next-action-guide.md から fix-cycle 記述が削除されている
- <!-- verify: file_not_contains "modules/size-workflow-table.md" "fix-cycle" --> size-workflow-table.md から fix-cycle override が削除されている
- <!-- verify: file_not_contains "scripts/setup-labels.sh" "fix-cycle" --> setup-labels.sh から fix-cycle ラベル作成が削除されている
- <!-- verify: file_not_contains "docs/product.md" "Fix cycle" --> Terms から Fix cycle エントリが削除されている
- <!-- verify: file_not_contains "docs/workflow.md" "fix-cycle" --> docs/workflow.md から fix-cycle 記述が削除されている
- <!-- verify: file_not_contains "docs/guide/workflow.md" "fix-cycle" --> docs/guide/workflow.md から fix-cycle 記述が削除されている
- <!-- verify: section_contains "skills/verify/SKILL.md" "When Issue is CLOSED" "/code --patch" --> reopen 時の案内に `/code --patch` が含まれている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats tests CI が PASS する
- <!-- verify: github_check "gh pr checks" "Validate skill syntax" --> validate-skill-syntax CI が PASS する
- <!-- verify: github_check "gh pr checks" "Forbidden Expressions check" --> forbidden expressions CI が PASS する

### Post-merge

- watchdog kill 後に再実行を促すメッセージが出力され、自動 spawn が発生しないことを観測
- verify で UNCERTAIN のみ含む結果の場合、Issue が reopen されないことを観測
- verify で FAIL を含む場合、Issue が reopen されるが `fix-cycle` ラベルは付与されず、完了メッセージで `/code --patch` が案内されることを観測
- Size L の Issue で `/code --patch N` を実行し、Size を変えずに patch route で修正できることを確認
- 既存の fix-cycle ラベル付き Issue（#161 など）がクローズされても副作用なく動作する（legacy label は inert）

## Tool Dependencies

### Bash Command Patterns
- 既存の権限のみ使用（`gh label create`、`gh issue edit`、`gh issue reopen` は既に `allowed-tools` に含まれている）

### Built-in Tools
- `Read` / `Edit` / `Write`: ファイル編集
- `Grep` / `Glob`: 変更箇所確認

### MCP Tools
- none

## Notes

**Auto-Resolved Ambiguity Points（Issue 本文より転記）:**

1. **`## Post-verify fix` Spec section の扱い**: 完全削除。Spec は disposable（tech.md）で、verify FAIL 後の修正は通常の retrospective append で十分。特別 section は不要
2. **既存の fix-cycle ラベル付き Issue**: マイグレーション不要。ラベルは残るが `/auto` / `/code` が参照しないため inert 状態になる。ユーザーが必要に応じて手動削除可能
3. **`setup-labels.sh` の挙動**: 再実行時に既存 `fix-cycle` ラベルを削除するロジックは追加しない（GitHub label の削除は破壊的）。新規 repo では作成されない、既存 repo ではユーザーが手動削除する運用
4. **歴史的 Spec retrospective の fix-cycle 言及**: 削除不要。`docs/spec/issue-141-post-verify-fix-cycle.md` 等は disposable な履歴で、現実の運用を反映していない過去記録として保存
5. **Size L + `/code --patch` の明示指定**: 既存の `--patch` フラグが Size をオーバーライドする挙動を利用するだけで、新規実装不要。verify reopen メッセージで推奨コマンドとして案内する

**設計上の追加メモ:**

- `scripts/claude-watchdog.sh` の `_watchdog_killed` フラグは保持する（新メッセージ分岐条件として使用）。dead code にはしない
- `modules/verify-executor.md` の 4 値分類（PASS/FAIL/UNCERTAIN/SKIPPED）は維持。分類自体は変えず、`/verify` 側のアクションのみ変更
- `docs/ja/*` ファイル（product.md, workflow.md 等）は現時点で fix-cycle の言及を含まないため、本 Issue では変更対象外
- `docs/spec/issue-141-post-verify-fix-cycle.md` / `docs/spec/issue-161-*.md` / `docs/spec/issue-163-*.md` は履歴として保存（Auto-Resolved 項目 4 参照）
- Pre-merge verify 項目数は 18（18 > full template 推奨上限 10）。ただし Issue 本文の受入条件と逐語同期（verify command sync rule）のため、Spec 側で集約は行わない
- `tests/setup-labels.bats` の期待ラベル数（11→10）は `scripts/setup-labels.sh` の変更と同期して更新（CI bats が PASS 条件に含まれる）

**変更方針（watchdog kill 時メッセージ配置）:**

`scripts/claude-watchdog.sh` の kill 後メッセージ `retrying disabled; please re-run the skill manually` は、元の retry 分岐 `if [[ "$_watchdog_killed" == "true" ]]; then ... fi` の位置（末尾、`exit` 直前）に同じ条件で配置する。kill 自体のメッセージ（`watchdog: no output for ${WATCHDOG_TIMEOUT}s, killing process`）は内部ループ内に残し、重複出力を避ける。

**docs/workflow.md の section 書き換え方針:**

`### Post-verify Fix Cycle` 見出しは見出しごと置換。新見出しは `### Verify Fail Flow`（または同等の fix-cycle 非依存な名前）。本文は「verify FAIL → Issue reopen + phase/* 削除 → `/code --patch N`（同 Size patch）/ `/code --pr N`（新規ブランチ）/ `/spec N`（設計見直し）を手動で選択」の 3 択ガイドに書き換える。直後の「The original `size/*` label is preserved throughout...」段落は fix-cycle 非依存（Size 保持は reopen/close サイクルでも成り立つ事実）のため維持可能だが、`reopen/close cycles` という文脈のみ残して fix-cycle への言及部分だけ削除する。
