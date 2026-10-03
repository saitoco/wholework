# Issue #1478: review: 起動したサブエージェントを TaskStop で確実に停止する

## Overview

`/review` の Step 10 が `Task(...)` で起動するサブエージェントには、名前も停止の手順も無い。結果が返らずに Sub-agent Result Fallback (#1481) へ進んだ場合、起動したエージェントがセッションに取り残される (downstream の実例では 34 分間 `ListAgents` に残り、手動の `TaskStop` まで消えなかった)。

この Issue では、`/issue` Step 12a (#1031) と同じ 2 点を `/review` Step 10 に入れる。

1. 各 `Task(...)` に明示的な `name:` を付け、`TaskStop` で個別に指定できるようにする
2. 結果を受け取った直後にそのエージェントだけを `TaskStop(task_id: ...)` で停止する。結果が返らずフォールバックした場合も停止する

あわせて、#1481 が Sub-agent Result Fallback の項目 4 (Cleanup) に入れた「停止は #1478 の範囲」という先送りの注記を、実際の停止手順に置き換える。停止はベストエフォートで、失敗 (fork 側からの拒否を含む) してもフォールバックや後続の処理を止めない。

変更するファイルは `skills/review/SKILL.md` の 1 つだけ (frontmatter の `allowed-tools` は変更しない。理由は Notes を参照)。Workflow 経路 (`skills/review/workflow-guidance.md`) は Issue の対象外。

## Reproduction Steps

1. 任意の PR に対して `/review <PR>` を実行する (light でも full でもよい)。Step 10 が `Task(...)` でサブエージェントを起動する。SKILL.md の `Task(...)` には `name` が無い
2. サブエージェントが時間内に結果を返さない (background の teammate / task として返る)。`/review` は Sub-agent Result Fallback に従って同じ観点を自分で実施し、Review を投稿して完了する
3. 起動したサブエージェント (例: `review-light-<N>`) は完了せず `ListAgents` に残り続ける。SKILL.md に停止の手順が無く、`TaskStop` を呼ぶ契機が無いので、手動で停止するまで消えない

## Root Cause

- **停止の手順が無い**: Step 10 は `Task(...)` で起動して結果を消費するだけで、`TaskStop(task_id: ...)` の呼び出しが 0 件 (`grep -c "TaskStop(task_id:" skills/review/SKILL.md` が 0)。#1481 が入れた Sub-agent Result Fallback 項目 4 は「停止は #1478 の範囲」という先送りの注記で、手順ではない
- **名前が無く、停止対象を指せない**: Step 10 内の `Task(...)` 起動箇所 6 件 (計測は Notes の「計測値」を参照) のいずれにも `name` が無い。`TaskStop` は名前付きのバックグラウンドエージェントを名前で指定できる
- **結果を使わなかったエージェントほど取り残される**: 結果が戻り値として返ればエージェントは完了して消える。フォールバックに進んだ経路は結果を待たないので、停止されないまま残る

対処の妥当性:

- `/issue` Step 12a (#1031) が同じ 2 点 (`name:` と結果受領直後の `TaskStop`) で対処済み。同じ形を `/review` Step 10 に移す
- `TaskStop` は権限が不要なので、`allowed-tools` への追加は要らない (Notes 参照)
- fork から起動した teammate は main session の所有になり、fork 側からの `TaskStop` は拒否されうる (#1481 観測 2)。そのため停止はベストエフォートにする (Issue の方針どおり)

## Changed Files

- `skills/review/SKILL.md`: Step 10 だけを変更する (frontmatter の `allowed-tools` は変更しない)
  - Step 10 に小節 `### Sub-agent Names and Stop` を新設する (位置: `**Foreground dispatch reminder ...**` 段落の直後、`### Sub-agent Result Fallback` の直前)。命名規則、結果受領直後の個別の `TaskStop`、ベストエフォートの規定を書く
  - `### Sub-agent Result Fallback`: 項目 4 `Cleanup` (「停止は #1478 の範囲」の先送りの注記) を削除し、停止の手順を項目 2 として新設する。Substitution と Record in the Review body は項目 3 と 4 に繰り下げる
  - `### Parser/Validator Edge Case Pre-check` の手順 3: 測定用のサブエージェントに `name="edge-case-$NUMBER-{n}"` を付け、結果が返った直後の停止を書き足す
  - `### 10.0.`: `Task(...)` ブロックに `name="review-light-$NUMBER"` を付け、手順 5 に停止の項目を足す
  - `### 10.2.`: 3 つの `Task(...)` ブロックに `name=` を付け、手順 4 に停止の項目を足す
  - `### 10.3.`: `Task(...)` ブロックに `name="bug-verify-$NUMBER-{n}"` を付け、手順 3 に停止の項目を足す
- [Steering Docs sync candidate] キーワード `TaskStop(task_id:` (この Issue が導入する形): `docs/ tests/ scripts/ modules/` 内の該当は 0 件。同期対象なし (測定コマンド: `grep -rl "TaskStop(task_id:" docs/ tests/ scripts/ modules/`)
- [Steering Docs sync candidate] キーワード `TaskStop`: 4 件 (`docs/spec/issue-1031-parallel-subagent-cleanup.md`、`docs/spec/issue-1142-spawn-detach-experiment.md`、`docs/spec/issue-1481-review-step10-fallback.md`、`docs/sessions/91609-1784609460-2026-07-21/session.md`)。いずれも過去の Spec / セッション記録で、変更不要 (測定コマンド: `grep -rl "TaskStop" docs/ tests/ scripts/ modules/`)
- [Steering Docs sync candidate] キーワード `Sub-agent Result Fallback`: 2 件 (`docs/ tests/ scripts/ modules/` 内の測定)。`modules/execution-context.md` は L97 (Precedents) と L192 (Callers) のどちらも小節名による参照で、Cleanup 項目の内容に依存しないため変更不要 (grep で確認済み)。もう 1 件は過去の Spec (`docs/spec/issue-1481-review-step10-fallback.md`) で変更不要
- [Outbound pointer sync candidate] Step 10 が指す `skills/review/workflow-guidance.md` (Workflow 経路)、`agents/review-*.md`、`modules/execution-context.md`: いずれも今回の変更の影響を受けない。`workflow-guidance.md` の手順 5 は `"Sub-agent Result Fallback"` を小節名で指しており、項目の繰り下げで壊れない。Workflow 経路は Issue の対象外
- [tests sync candidate] `tests/edge-case-execution-context.bats`: Edge Case Pre-check 手順 3 を編集するので、この bats が見る 2 つの文字列 (`Execution context axis`、`CWD other than the repository root`) を残すこと。`tests/review.bats` に Step 10 を対象にした assertion は無い

## Implementation Steps

1. `skills/review/SKILL.md` の Step 10 に小節 `### Sub-agent Names and Stop` を新設する。位置は `**Foreground dispatch reminder ...**` 段落の直後、`### Sub-agent Result Fallback` の直前。見出しは必ず `###` にする (Notes の「section 系 AC の走査範囲」参照)。本文は次のとおり (→ AC1, AC4, AC5, AC6)

   ````markdown
   ### Sub-agent Names and Stop

   Every `Task(...)` launched in Step 10 — the Parser/Validator Edge Case Pre-check measurement sub-agents, 10.0, 10.2, and 10.3 — carries an explicit `name:`, so that each agent can be addressed individually by `TaskStop` (Issue #1478). Without a name the agent has no stable identifier to stop by, and a sub-agent that returned no result can stay in the session long after `/review` has finished. `$NUMBER` is the PR number; `{n}` is the 1-based index of the file (Edge Case Pre-check) or of the issue (10.3).

   As soon as a given sub-agent's result is in hand, immediately stop that agent alone — do not wait for the others, and do not defer the stops to the end of `/review`:

   ```text
   TaskStop(task_id: "review-light-$NUMBER")         # right after the review-light result is in hand (10.0)
   TaskStop(task_id: "review-spec-$NUMBER")          # right after the review-spec result is in hand (10.2)
   TaskStop(task_id: "review-bug-diff-$NUMBER")      # right after the diff bug scan result is in hand (10.2)
   TaskStop(task_id: "review-bug-security-$NUMBER")  # right after the security scan result is in hand (10.2)
   TaskStop(task_id: "bug-verify-$NUMBER-{n}")       # right after that verification verdict is in hand (10.3)
   TaskStop(task_id: "edge-case-$NUMBER-{n}")        # right after that measurement result is in hand (Edge Case Pre-check)
   ```

   A sub-agent whose result was not obtained is stopped too, not only the ones whose result was used — it is the agent most likely to be left behind. For the review sub-agents that stop is step 2 of "Sub-agent Result Fallback" below.

   **The stop is best-effort and never gates anything.** `TaskStop` can fail for reasons outside this step's control: no running task matches the name because the agent already ended, or `/review` is running as a fork and the agent is owned by the main session, which refuses the stop. Ignore any such failure — do not retry, do not wait, and do not let it delay the fallback, the Review posting, or any later Step.
   ````

2. (after 1) `### Sub-agent Result Fallback` の項目を差し替える。項目 1 (Trigger) は変更しない。項目 4 `Cleanup` (`stopping the already-launched sub-agent is out of scope here (see #1478); ...` の行) を削除し、次の停止手順を項目 2 として挿入する。旧項目 2 (Substitution) と旧項目 3 (Record in the Review body) は本文を変えずに項目 3 と 4 に繰り下げる。この小節に `see #1478` という文字列を残さないこと (→ AC2, AC3, AC4)

   ````markdown
   2. **Stop the sub-agent**: for each sub-agent whose result was not obtained, first call `TaskStop(task_id: "<its name>")` (names per "Sub-agent Names and Stop" above) — an agent that returned nothing may still be running, and it is the one most likely to be left in the session after `/review` finishes. This step covers sub-agents launched with `Task(...)`; the Workflow path is a separate launch mechanism and is not covered here. The stop is best-effort: if `TaskStop` fails (no running task matches the name, or `/review` runs as a fork and the main session that owns the agent refuses the stop), ignore the failure and go straight on to item 3 — the stop's outcome never blocks the substitution, the Review body line in item 4, or the Review posting.
   ````

3. (after 1) 各起動箇所に `name=` を付け、結果が手元に入った直後の停止を書き足す。挿入する文面は英語、既存の文との整合のため小節名 `"Sub-agent Names and Stop"` を参照させる (→ AC1, AC6)
   - **Parser/Validator Edge Case Pre-check の手順 3**: `launch a `subagent_type="general-purpose"` Task sub-agent in parallel.` を `launch a `subagent_type="general-purpose"` Task sub-agent in parallel, each with an explicit `name="edge-case-$NUMBER-{n}"` (`{n}` = 1 or 2, the file's rank by diff hunk size; see "Sub-agent Names and Stop").` に変える。手順 3 の末尾 (`noting both CWD values used.` の後) に ` As soon as each measurement sub-agent has returned (with findings, or without a usable result), stop it with `TaskStop(task_id: "edge-case-$NUMBER-{n}")` (best-effort, see "Sub-agent Names and Stop").` を足す。(7) の文言は触らない
   - **10.0**: `Task(...)` ブロックの `description=...,` と `prompt=...` の間に `name="review-light-$NUMBER",` を足す。手順 5 の最初の箇条書きとして `Stop `review-light-$NUMBER` as soon as its result is in hand: `TaskStop(task_id: "review-light-$NUMBER")` (best-effort, see "Sub-agent Names and Stop"; when the result was not obtained, step 2 of "Sub-agent Result Fallback" stops it instead)` を足す
   - **10.2**: 3 つの `Task(...)` ブロックの `description=...,` の後に、それぞれ `name="review-spec-$NUMBER",`、`name="review-bug-diff-$NUMBER",`、`name="review-bug-security-$NUMBER",` を足す。手順 4 の `Collect outputs from each group` の直後に、箇条書きとして `Stop each launched sub-agent as soon as its result is in hand, one call per agent and without waiting for the others: `TaskStop(task_id: "review-spec-$NUMBER")`, `TaskStop(task_id: "review-bug-diff-$NUMBER")`, `TaskStop(task_id: "review-bug-security-$NUMBER")` (best-effort, see "Sub-agent Names and Stop"; a sub-agent whose result was not obtained is stopped by step 2 of "Sub-agent Result Fallback")` を足す
   - **10.3**: `Task(...)` ブロックの `description="Bug issue verification #{n}",` の後に `name="bug-verify-$NUMBER-{n}",` を足す。手順 3 `Process verification results` の最初の箇条書きとして `Stop each verification sub-agent as soon as its verdict is in hand: `TaskStop(task_id: "bug-verify-$NUMBER-{n}")` (best-effort, see "Sub-agent Names and Stop"). This includes a verification sub-agent whose result was not obtained: the issue passes through unverified, but its sub-agent is still stopped` を足す

4. (after 2, 3) 検証する。`skills/review/SKILL.md` の `allowed-tools` は変更しないこと。次を確認する (→ AC1-AC6 全体)
   - `python3 scripts/validate-skill-syntax.py skills/` が成功する (半角 `!` を本文に入れていないこと)
   - `bash scripts/check-forbidden-expressions.sh` が成功する
   - `/code` の言語規約チェック (`skills/code/language-convention-check.md`) で、追加した行に仮名・漢字が無いこと。L39 の `前景` を含む行には触れない
   - Step 10 の `Task(` 起動箇所 6 件すべてに `name=` が付いていること。Fallback 小節に `see #1478` が残っていないこと。Step 10 に `TaskStop(task_id:` があること
   - `tests/edge-case-execution-context.bats` が見る 2 つの文字列 (`Execution context axis`、`CWD other than the repository root`) が `skills/review/SKILL.md` に残っていること (実行環境に `bats` が無いので grep で確認する)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md の Step 10 (10.0 の review-light、10.2 の review-spec / review-bug、10.3 の検証サブエージェントを含む) が、起動したサブエージェントの結果を受け取った直後に、そのサブエージェントを TaskStop で個別に停止する手順を含んでいる" --> 結果受領後に停止する手順がある
- <!-- verify: rubric "skills/review/SKILL.md の Sub-agent Result Fallback (サブエージェントが時間内に結果を返さず /review 側で代替実施する経路) が、起動済みのサブエージェントに対して TaskStop を呼ぶことを手順として明記している。『停止は out of scope』と先送りする記述ではなく、実際に停止を呼ぶ手順である" --> フォールバック時も停止することが書かれている
- <!-- verify: section_not_contains "skills/review/SKILL.md" "Sub-agent Result Fallback" "see #1478" --> #1481 が入れた「停止は #1478 の範囲」という先送りの注記が、Sub-agent Result Fallback から取り除かれている
- <!-- verify: rubric "skills/review/SKILL.md の Step 10 に TaskStop を呼ぶ停止手順があり、その手順について、停止の成否 (fork 実行からの TaskStop が拒否される場合を含む) によって、フォールバックや後続の review 処理が止まらない (停止はベストエフォートである) ことが明記されている。『停止は out of scope』と先送りする既存の注記だけでは満たさない" --> 停止に失敗してもレビューの進行を妨げないことが書かれている
- <!-- verify: section_contains "skills/review/SKILL.md" "Step 10" "TaskStop(task_id:" --> Step 10 に `TaskStop(task_id: ...)` による停止手順が記載されている
- <!-- verify: rubric "skills/review/SKILL.md の Step 10 の全ての Task(...) 呼び出し (10.0 の review-light、10.2 の review-spec と review-bug 2 件、10.3 の検証サブエージェント) が、TaskStop で個別に指定できる name: を持っている" --> エージェントに名前が付いている

### Post-merge

- `/review` を実行したあと `ListAgents` にレビュー用サブエージェントが残っていないことを確認する <!-- verify-type: manual -->

## Notes

**計測値** (スコープ: `skills/review/SKILL.md` の Step 10 = L463-L702、変更前の状態)

- `Task(...)` の起動箇所は 6 件: Edge Case Pre-check の手順 3 (L524、散文での起動指示、最大 2 件) / 10.0 (L559) / 10.2 (L618, L624, L630) / 10.3 (L667、最大 10 件のテンプレート)。コマンド: `awk 'NR>=463 && NR<=702 && (/Task\(/ || /subagent_type/)' skills/review/SKILL.md`。Step 10 の外に `Task(...)` の起動箇所は無い (`grep -n "Task(\|subagent_type" skills/review/SKILL.md` で確認)
- `name` を持つ起動箇所は 0 件。`TaskStop(task_id:` は `skills/review/SKILL.md` 全体で 0 件、`TaskStop` という語は L483 の先送りの注記 1 件のみ

**Issue 本文との相違**

- Issue の「対象範囲」は 10.0 / 10.2 / 10.3 の 3 系統 (4 種) を列挙しているが、Step 10 には Parser/Validator Edge Case Pre-check の手順 3 が `subagent_type="general-purpose"` のサブエージェントを起動する箇所もある (上の計測値の L524)。AC の rubric は「Step 10 の全ての Task(...) 呼び出し」と書いているので、この起動箇所も対象に含める。除くと、このエージェントだけが取り残される経路が残る (自動解決)

**自動解決した判断 (非対話モード)**

- **`allowed-tools` に `TaskStop` を足さない** (Issue が `/spec` に委ねた論点)。根拠は 3 つ。(a) 公式の tools-reference で `TaskStop` は Permission required: No。(b) #1481 の観測 2 では、`allowed-tools` に無いまま呼ばれた `TaskStop` が、権限エラーではなく所有者エラー (main session の所有) で拒否された。(c) `/issue` Step 12a も `allowed-tools` に載せずに使っている。足す場合は `scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` にも `TaskStop` が要り (無いと未知のツール名として検査に落ちる)、変更が 1 ファイルでは収まらなくなる。検査の本文チェック (`validate_body_tools_in_allowed_tools`) は `KNOWN_TOOLS` にあるツール名しか見ないので、本文に `TaskStop` を書いても検査は通る。権限で拒否される場合は Post-merge の manual 条件 (`ListAgents` で残留が無いこと) で顕在化する
- **AC4 の rubric を絞った** (Issue 本文を更新)。triage の監査コメントのとおり、変更前の main でも #1481 の注記 (`Whether the stop succeeds must not block the fallback.`) だけで PASS しうる (検出力が無い) ため、Issue Retrospective の「`/spec` で文言を絞る」に従って、「Step 10 に TaskStop を呼ぶ停止手順があり、その手順について、停止の成否が止まらないことが明記されている。『停止は out of scope』と先送りする既存の注記だけでは満たさない」に変えた。要件 (停止はベストエフォート) は変えず、検出力だけを上げた。verify command の SSoT は Issue 本文なので、先に Issue 本文を更新し、Spec の Verification には原文のまま写した。編集は AC4 の 1 行だけ (更新前の本文との行単位の比較で、差分がこの 1 行だけであることを確認し、更新後の本文と下書きが一致することも確認した)
- **名前の付け方**: `/issue` Step 12a の `scope-$NUMBER` の形を踏襲し、役割ごとの固定名にする。`review-light-$NUMBER` / `review-spec-$NUMBER` / `review-bug-diff-$NUMBER` / `review-bug-security-$NUMBER` / `bug-verify-$NUMBER-{n}` / `edge-case-$NUMBER-{n}`。`$NUMBER` は PR 番号で、downstream で観測された `review-light-141` / `review-light-175` と同じ規則
- **Fallback で停止を項目 2 (代行の前) に置いた**: 結果が手元に無いエージェントはまだ動いている可能性がある。代行レビューは数分かかるので、その間も動かし続けないこと、代行を終えてターンを閉じる時点で停止を忘れないことを優先した。項目番号を参照する文書は無い (SKILL.md 内は小節名で参照、`modules/execution-context.md` も小節名のみ。grep で確認済み)
- **Workflow 経路は対象外のまま** (Issue の方針): Fallback の停止項目は `Task(...)` で起動したサブエージェントに限ると本文に書く。「停止は out of scope」という先送りの文言にならないよう、対象の宣言に留める
- **拒否を親セッションへ知らせる仕組みは入れない**: fork 側の拒否を最終応答で親に伝える案もあるが、Completion Report が「変更しない固定形式」であること、Issue の AC の範囲を超えることから採用しない。fork 実行で拒否が常態なら別 Issue で扱う
- **新規テストは不要**: 変更は SKILL.md の文書のみで、スクリプトに分岐を追加しない (#1481 と同じ扱い)。実行環境に `bats` が無い (`command -v bats` が失敗) ので、既存の bats は実行できない。Implementation Step 4 で、`tests/edge-case-execution-context.bats` が見る文字列の残存を grep で確認する
- **Pre-merge の検証項目は 6 件**: Issue の AC と 1:1 で、light の上限 5 件を超える。Issue 本文を SSoT として原文のまま写す同期ルールと件数一致のチェックを優先した
- **Size は S のまま**: Changed Files は 1 件。軸 2 は文書のみの変更・原因が明確なバグ修正で縮小方向だが、起動箇所 6 件と Fallback の書き換えがあり、1 箇所の追加だった `/issue` Step 12a (#1031、XS) より広い。XS と S はどちらも patch 経路なので、経路は変わらない

**section 系 AC の走査範囲** (`modules/verify-patterns.md` §29)

- AC5 は `section_contains "Step 10"` で、`## Step 10` から次の `##` 見出しの直前 (配下の `###` を含む) を走査する。AC3 は `### Sub-agent Result Fallback` から次の `###` 見出しの直前までを走査する。新設する小節は `###` で Step 10 配下に置き、Fallback 小節の外側 (直前) にする。見出しレベルを変えると走査範囲が変わり、AC が意図と違う範囲を見ることになるので、変えない
- AC3 の `see #1478` は変更前の Fallback 小節 (L483) に存在する。実装後は無くなることが期待される状態。新設する小節の `(Issue #1478)` は Fallback 小節の外側なので AC3 に掛からない
- AC5 の `TaskStop(task_id:` は変更前の `skills/review/SKILL.md` に存在しない (0 件)。実装が導入する文字列で、Implementation Step 1 の文面に含まれる

**CI の制約** (`/code` で守る)

- 追加する文言は英語のみ。`scripts/check-language-convention.py` は `skills/` の差分の `+` 行から仮名と漢字を検出する。Step 10 の既存行に仮名・漢字は無いので、Step 10 の行を編集しても検出されない。一方、L39 の `前景` の行は編集しない
- 半角 `!` を本文に入れない (`scripts/validate-skill-syntax.py`)。非推奨用語 (`scripts/check-forbidden-expressions.sh`) を使わない

**外部仕様の確認** (出所と取得日)

- `TaskStop` のスキーマ: `task_id` は「名前付きのバックグラウンドエージェントや agent-team の teammate を、agent ID または名前で指定できる」。`shell_id` は非推奨。出所: ToolSearch `select:TaskStop` が返したスキーマ (取得日 2026-10-03)
- `TaskStop` の権限: Permission required は No。名前付きエージェントを名前で停止でき、対象が無いときのエラーは実行中のバックグラウンドエージェントを列挙する。出所: https://code.claude.com/docs/en/tools-reference (取得日 2026-10-03)
- agent teams: `name` 付きの Agent 呼び出しは、agent teams が有効な対話セッションでは teammate として起動され、結果を戻り値ではなくチームのメッセージで返す。非対話 (`-p`) では名前付きでも通常のサブエージェントとして動く。出所: https://code.claude.com/docs/en/agent-teams (取得日 2026-10-03)
- サブエージェントはバックグラウンドが既定で、結果は完了通知として後のターンに届く。非対話では起動元が待たないため、起動元の終了後に完了したバックグラウンドのサブエージェントは親の会話に報告する。出所: https://code.claude.com/docs/en/sub-agents (取得日 2026-10-03)

**Uncertainty** (light のためここに記録)

- **`name:` を明示すると teammate として起動されうる**: agent teams が有効な対話セッションでは、名前付きの呼び出しは teammate になり、結果がチームのメッセージで返る (公式ドキュメント)。ただし #1481 の観測では、SKILL.md に名前が無くてもモデルが `review-light-<PR 番号>` と名付けて teammate になっていたので、差は小さいと見ている。結果が返らない場合は Sub-agent Result Fallback が受ける。検証方法: Post-merge の manual 条件に加え、次回の対話セッションからの fork 実行 `/review` で、Review 本文の `Sub-agent fallback` 行の有無と `ListAgents` を見る。影響範囲: Implementation Steps 1-3
- **fork 実行ではこの手順が効かない可能性が高い**: 対話セッションからの fork 実行では、teammate は main session の所有になり、fork 側の `TaskStop` は拒否される (#1481 観測 2)。ベストエフォートとして受け入れ、Post-merge の manual 条件で実効性を確認する。拒否が常態なら、名前を付けずに停止する、サブエージェントの `maxTurns` で上限を設ける、といった案を別 Issue で検討する。影響範囲: Implementation Steps 1-3
- **同名のエージェントが残っているときの挙動は未検証**: 同一セッションに前回の `/review` のエージェントが残った状態で同じ PR を再度 `/review` すると、名前が重複する。エラーになるか、サフィックスが付くかは分からない。エラーなら Task 呼び出しが結果なしとなり、Sub-agent Result Fallback が受ける。影響範囲: Implementation Steps 1-3

**Consumed Comments**: 末尾の `## Consumed Comments` を参照

## Consumed Comments

- saito / MEMBER / first-class / `/issue` の Issue Retrospective (自動解決ログ、受け入れ条件の変更理由、監査で残った点: AC4 の rubric を `/spec` で絞る) / https://github.com/saitoco/wholework/issues/1478#issuecomment-5964340803
- saito / MEMBER / first-class / triage の AC 監査 (AC4 の rubric が変更前の main でも PASS しうる Pattern 2。停止手順の存在を前提にした文言への絞り込みを提案) / https://github.com/saitoco/wholework/issues/1478#issuecomment-5964340973
- 参考: cutoff (`phase/issue` の付与、2026-10-03T01:52:13Z) より前の triage の AC 監査コメント (`file_contains "TaskStop"` が #1481 の注記で常時 PASS) は `/issue` で消費済みで、Issue 本文の AC に反映されている
