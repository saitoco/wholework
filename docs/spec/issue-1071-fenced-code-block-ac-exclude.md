# Issue #1071: issue: fenced code block 内の checkbox を AC 列挙から除外

## Overview

Issue 本文のチェックボックス列挙 (1-based AC enumeration convention: `gh-issue-edit.sh --checkbox` の index、`check-pre-merge-ac.sh` の `unchecked_indices`、各種 `ac=` marker 属性が共有する規約) が、fenced code block (` ``` ` で囲まれた領域) 内の `- [ ]`/`- [x]` 行を実 AC として数えてしまう。記法サンプルを含む Issue (例: #1059) で発生し、以降の実 AC の index が全てずれる。

この規約を実装する 3 スクリプト (`gh-issue-edit.sh`, `check-pre-merge-ac.sh`, `scan-pending-ac.sh`) と、同じ規約を prose で参照する 3 Skill (`verify`, `auto`, `audit`) に、fenced code block 除外ロジックを追加する。除外ルールは `modules/l0-surfaces.md` に SSoT として定義する。

## Reproduction Steps

1. `- [ ]` を含む fenced code block (記法サンプル等) を Pre-merge セクションより前、または セクション内に含む Issue 本文を用意する (例: #1059 の「対応方針 (案)」節のコードフェンス)。
2. `scripts/check-pre-merge-ac.sh <N>` または `scripts/gh-issue-edit.sh <N> --checkbox <idx> --check` を実行する。
3. 返却される/更新される index が、フェンス内のサンプル行を index 1 として数え、以降の実 AC の index が実際のセクション内の位置より 1 つ (フェンス内の `- [ ]` 行数分) ずれていることを確認する。
4. `--checkbox <ずれた index>` で更新すると、意図した行ではなく隣接する別の行の checkbox が更新される。

## Root Cause

`gh-issue-edit.sh` の `CB_COUNT`/checkbox 更新 awk、`check-pre-merge-ac.sh` の `RECORDS` 抽出 awk は、いずれも `^- \[[ xX]\]` にマッチする行を単純にインクリメントしており、その行が fenced code block 内かどうかを一切追跡していない。`skills/verify/SKILL.md`・`skills/auto/SKILL.md`・`skills/audit/SKILL.md` の LLM 駆動の prose 記述も同様に「本文全体の `- [ ]` 行」を素朴に数える記述になっている。

この規約の SSoT は従来存在せず、`modules/l0-surfaces.md` を含む全参照箇所は "same convention as `gh-issue-edit.sh --checkbox`" という相互参照のみで、実際の列挙アルゴリズム (1-based, 全文横断, fenced code block 除外なし) を明文化した一次定義はどこにもなかった (`scripts/check-pre-merge-ac.sh` のヘッダコメントが最も近いが、これも「参照」であり定義ではない)。

調査の結果、`scripts/scan-pending-ac.sh` (Post-merge 側の同種列挙) も同じ未対策のバグを持つことが判明した。一方 `scripts/rank-verify-backlog.sh` (#1349 で追加、#709 の regression guard) は、自身の Post-merge auto/manual カウントに対してのみ、`in_fence` フラグによる fenced code block 除外を既に正しく実装済みだった。この既存の正しい実装が、同じ「`gh-issue-edit.sh --checkbox` と同じ規約」を謳う他のスクリプトへ伝播していなかったことが、今回の再発の直接的な構造要因である。

## Changed Files

- `modules/l0-surfaces.md`: 新規 `## AC Enumeration Convention` セクションを追加 (1-based 列挙規約の初の一次定義 + fenced code block 除外ルールを SSoT として明文化。`scripts/rank-verify-backlog.sh` を参照実装として明記)
- `scripts/gh-issue-edit.sh`: `CB_COUNT` 算出 awk と checkbox 更新 awk (`UPDATED_BODY`) の両方に `in_fence` トラッキングを追加 (bash 3.2+ 互換、変更なし)
- `scripts/check-pre-merge-ac.sh`: `RECORDS` 抽出 awk に `in_fence` トラッキングを追加。ヘッダコメントを `modules/l0-surfaces.md` § AC Enumeration Convention への参照に更新 (bash 3.2+ 互換、変更なし)
- `scripts/scan-pending-ac.sh`: `AWK_PROGRAM` に `in_fence` トラッキングを追加。ヘッダコメントを同 SSoT への参照に更新 (Spec 調査で判明した対象追加。理由は Notes 参照) (bash 3.2+ 互換、変更なし)
- `scripts/rank-verify-backlog.sh`: ヘッダコメントの fenced code block 除外の説明を、ロジックを再掲する形から `modules/l0-surfaces.md` § AC Enumeration Convention への参照に変更 (ロジック自体は変更なし。Spec 調査で判明した対象追加。理由は Notes 参照)
- `skills/verify/SKILL.md`: Step 4 (`Parse acceptance condition checkboxes` 付近)・Step 6 (`Identify the checkbox indices (1-based) of pre-merge conditions that PASSed`)・Step 8b (`ac_index uses the same 1-based index convention...` の一文) の 3 箇所に、fenced code block 除外ルールへの参照を追記
- `skills/auto/SKILL.md`: Batch Completion Report の Pending manual confirmation 集計 (`MANUAL_N`/`OBS_N`/`OPP_N` を数える箇所、L1268-1271 付近) に、fenced code block 除外ルールへの参照を追記
- `skills/audit/SKILL.md`: Observation Waiting Count / Opportunistic Remaining Count / Manual Waiting Count の 3 セクション (L357/361/365 付近) に、fenced code block 除外ルールへの参照を追記
- `tests/gh-issue-edit.bats`: fenced code block 内のサンプル checkbox が `--checkbox` の index 解決から除外されるケース (フェンス前後に実 AC がある場合) の新規 `@test` を追加
- `tests/check-pre-merge-ac.bats`: Pre-merge セクション内外に fenced code block 内サンプル checkbox を含む本文で、global index が正しく解決されるケースの新規 `@test` を追加 (Issue 本文が明示的に要求)
- `tests/run-fact-matching.bats`: `scan-pending-ac.sh` の候補列挙が fenced code block 内サンプルを除外するケースの新規 `@test` を追加 (`tests/rank-verify-backlog.bats` の既存 fence テストと同じ body 構造を流用。Spec 調査で判明した対象追加)

## Implementation Steps

1. `modules/l0-surfaces.md` に `## AC Enumeration Convention` セクションを新設する。挿入位置は `## L0 Surface SSoT` の直後、`## Trust Boundary` の直前。内容: (a) 1-based 列挙規約そのものの定義 (`^- \[[ xX]\]` にマッチする行を文書順に 1-based で数える、セクションをまたいだ単一のフラットカウント)、(b) fenced code block 除外ルール (` ``` ` で始まる行 — 3 個以上のバッククォート、言語タグの有無を問わない — でトグルする `in_fence` フラグ管理下にある行は除外)、(c) 参照実装として `scripts/rank-verify-backlog.sh` (Issue #709 の regression guard として先行実装) を明記し、この Issue で `gh-issue-edit.sh`/`check-pre-merge-ac.sh`/`scan-pending-ac.sh` に同じパターンを適用する旨を記載する。(→ acceptance criteria 1)

2. (after 1) `scripts/gh-issue-edit.sh` の `CB_COUNT` 算出 awk と `UPDATED_BODY` 生成 awk の両方に、`rank-verify-backlog.sh` と同じ `in_fence` トラッキングパターンを適用する:
   ```awk
   BEGIN { in_fence = 0 }
   /^```/ { in_fence = !in_fence }
   !in_fence && /^- \[[ xX]\]/ { count++ }
   END { print count+0 }
   ```
   (checkbox 更新側も同様に `!in_fence &&` ガードを追加し、末尾の catch-all `{ print }` で全行を出力する既存構造は変更しない。)
   `tests/gh-issue-edit.bats` に、フェンス内サンプル checkbox (チェック済み/未チェック双方) を含む本文で `--checkbox` の index 解決が正しく動作すること — 除外されるケース (フェンス内) と除外されないケース (フェンス外の通常の AC 行) の両方 — を検証する新規 `@test` を追加する (既存の `make_gh_mock_body`/`MOCK_BODY_FILE` ヘルパーパターンを踏襲)。(→ acceptance criteria 2)

3. (after 1) `scripts/check-pre-merge-ac.sh` の `RECORDS` 抽出 awk に、同じ `in_fence` トラッキングを適用する (この awk は既存で `next` を多用するスタイルのため、そのスタイルを踏襲: `/^```/ { in_fence = !in_fence; next }` → `in_fence { next }` を `BEGIN` の直後、`### Pre-merge` 判定の前に挿入)。ヘッダコメントの "Global index definition" 節に、`modules/l0-surfaces.md` § AC Enumeration Convention への参照を追記する。`tests/check-pre-merge-ac.bats` に、Pre-merge セクション内に fenced code block 内サンプル checkbox を含む本文で `unchecked_indices` が正しく (フェンス内サンプルを飛ばして) 解決されることを検証する新規 `@test` を追加する (Issue 本文の Background で明示的に要求されている回帰防止テスト)。(→ acceptance criteria 3)

4. (after 1) `scripts/scan-pending-ac.sh` の `AWK_PROGRAM` に同じ `in_fence` トラッキングを適用する (`check-pre-merge-ac.sh` と同じ `next` 多用スタイルを踏襲。`Post-merge` 判定の前に fence 判定を挿入)。ヘッダコメントの "Global 1-based checkbox index" 節に SSoT 参照を追記する。あわせて `scripts/rank-verify-backlog.sh` のヘッダコメント (`# Code fence exclusion: ...` 節) を、ロジックの再掲ではなく `modules/l0-surfaces.md` § AC Enumeration Convention への参照 1 文に置き換える (ロジック自体はコード変更なし)。`tests/run-fact-matching.bats` の `scan-pending-ac:` セクションに、`tests/rank-verify-backlog.bats` の `#709 regression` テストと同じ body 構造 (fenced code block 内サンプル checkbox を含む Post-merge セクション) を用いた新規 `@test` を追加する。(このステップは Issue 本文に明記された対象範囲を超える Spec 調査時点の発見であり、Notes に理由を記録する。既存の `command "bats tests/*.bats"` (acceptance criteria 6) で検証される。)

5. (after 1) `skills/verify/SKILL.md`・`skills/auto/SKILL.md`・`skills/audit/SKILL.md` の checkbox/index 列挙箇所に、`modules/l0-surfaces.md` § AC Enumeration Convention への参照を追記する:
   - `skills/verify/SKILL.md` Step 4 (`Parse acceptance condition checkboxes:` の直後)、Step 6 (`Identify the checkbox indices (1-based) of pre-merge conditions that PASSed:` の文)、Step 8b (`ac_index uses the same 1-based index convention as gh-issue-edit.sh --checkbox...` の文) の 3 箇所。
   - `skills/auto/SKILL.md` の Batch Completion Report、`Pending manual confirmation` 手順 3 (`MANUAL_N`/`OBS_N`/`OPP_N` を数える記述) に 1 箇所。
   - `skills/audit/SKILL.md` の `Observation Waiting Count` / `Opportunistic Remaining Count` / `Manual Waiting Count` の 3 セクションそれぞれに 1 箇所ずつ。
   (→ acceptance criteria 4, 5)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/l0-surfaces.md に、Issue 本文のチェックボックス列挙時に fenced code block 内の - [ ] 行を除外するルールが SSoT として定義されている" --> fenced code block 除外ルールが `modules/l0-surfaces.md` に定義されている
- <!-- verify: rubric "scripts/gh-issue-edit.sh の --checkbox index 解決処理が fenced code block 内の - [ ] 行を列挙対象から除外している。除外されるケース (コードフェンス内) と除外されないケース (通常の AC 行) の両方がテストで確認されている" --> `gh-issue-edit.sh` の index 解決が code fence を除外する
- <!-- verify: rubric "scripts/check-pre-merge-ac.sh の index 解決処理が fenced code block 内の - [ ] 行を列挙対象から除外しており、gh-issue-edit.sh と同じ index を返す。tests/check-pre-merge-ac.bats に code fence 内 checkbox を含む本文のケースが追加されている" --> `check-pre-merge-ac.sh` の index 解決が code fence を除外する
- <!-- verify: rubric "skills/verify/SKILL.md の checkbox/index 列挙処理 (Step 3 の Parse acceptance condition checkboxes 付近) が、fenced code block 内の行を除外する新しい除外ルールを参照する記述に更新されている" --> `skills/verify/SKILL.md` の index 解決が除外ルールを参照する
- <!-- verify: rubric "skills/auto/SKILL.md の Pending manual confirmation 集計と skills/audit/SKILL.md の Manual Waiting Count / Opportunistic Remaining Count が、新しい除外ルールを参照する記述に更新されている" --> `/auto` と `/audit` の集計が除外ルールを参照している
- <!-- verify: command "bats tests/*.bats" --> 既存の bats テストがすべて PASS する

### Post-merge

- 記法サンプルを fenced code block で含む Issue に対して `/verify` を実行し、checkbox が正しい index で更新されることを確認する <!-- verify-type: manual -->

## Notes

### Pre-merge 検証項目数について (Simplicity rule との関係)

Issue 本文の Pre-merge acceptance criteria は 6 件 (light 深度の目安 5 件をわずかに超過)。これは `/issue` フェーズの Autonomous Auto-Resolve Log で 4 件 → 6 件へ意図的に拡張された結果であり (`## Consumed Comments` 参照)、Verify command sync rule (Issue 本文の Pre-merge を Spec へ verbatim コピーし、独自に書き換えない) を優先し、6 件のまま維持した。件数削減のための統合・省略は行っていない。

### Scope expansion beyond Issue body (`scan-pending-ac.sh` / `rank-verify-backlog.sh`)

Step 6 の Multi-file change grep coverage check で、`scripts/scan-pending-ac.sh` が Issue 本文に記載のない同型バグ (ヘッダコメントで "same convention as scripts/gh-issue-edit.sh --checkbox and scripts/check-pre-merge-ac.sh" と明記しながら、実装は fenced code block 除外を欠く) を持つことを発見した。一方 `scripts/rank-verify-backlog.sh` (#1349 で追加、#709 の regression guard) は自身の Post-merge auto/manual カウント用に `in_fence` パターンを既に正しく実装済みであり、これを他スクリプトへ適用する際の参照実装として採用した。

両スクリプトを Changed Files/Implementation Steps に含めたが、Issue 本文の Pre-merge AC (6 件) には追加していない — Verify command sync rule (Issue 本文の `## Acceptance Criteria > Pre-merge` を Spec の `## Verification > Pre-merge` へ verbatim にコピーし、独自に書き換えない) を優先し、Issue 本文と Spec の Verification 項目数の整合を保つため。この 2 ファイルの修正は、既存の acceptance criteria 6 (`command "bats tests/*.bats"`) が新規追加する `tests/run-fact-matching.bats` の `@test` を含めて検証する。

### Step 番号の表記ゆれ (Issue 本文 vs 実装)

Issue 本文の acceptance criteria 4 は「`skills/verify/SKILL.md` Step 3 の Parse acceptance condition checkboxes 付近」と記載しているが、現在の `skills/verify/SKILL.md` では該当記述は Step 4 (`Fetch Issue Acceptance Conditions`) にある (Step 3 は `Worktree Entry`)。Issue 起票以降にステップが挿入され番号がずれたとみられる。SPEC_DEPTH=light のため自動解決 (ユーザー確認なし): Implementation Steps は実際のファイル内容 (Step 4/Step 6/Step 8b) を対象とする。

### `modules/l0-surfaces.md` を「既存の定義箇所」とする Issue 本文の記述について

Issue 本文 Purpose は `modules/l0-surfaces.md` を「既存の『1-based AC enumeration』convention の定義箇所」と表現しているが、実際には同ファイルは "same convention as `gh-issue-edit.sh --checkbox`" という相互参照を複数箇所に持つのみで、列挙アルゴリズムそのものを明文化した一次定義はリポジトリ全体に存在しなかった (`scripts/check-pre-merge-ac.sh` のヘッダコメントが最も詳細だが、これも「参照」)。本 Spec は Implementation Step 1 で `modules/l0-surfaces.md` に**新規に**一次定義を追加することで、Issue 本文の意図 (l0-surfaces.md を SSoT とする) を実現する。

### Fenced code block の対象範囲

除外対象は Issue 本文 Background が明示するバッククォート 3 個以上のフェンス (` ``` `) のみ。`~~~` 形式のフェンスおよびインデント (4 スペース) 形式のコードブロックは対象外 (このリポジトリの Issue 本文/ドキュメントで実際に使われているのはバッククォートフェンスのみと確認済み)。

### 不正なフェンス (奇数個の ``` ) の挙動

本文中の ` ``` ` 出現回数が奇数の場合 (閉じフェンスが無い等)、`in_fence` はそれ以降の行に対して true のまま残り、以降のすべての `- [ ]`/`- [x]` 行が列挙から除外される (アンダーカウント)。この挙動は明示的なフェイルセーフ実装ではないが、影響方向は安全側 (誤った行を書き換える一次バグより、対象行が「未検出」として素通しされる方が実害が小さい) であり、各スクリプトの既存の `gh` 失敗時 fail-open 契約 (`check-pre-merge-ac.sh` の `fail_open()`、`scan-pending-ac.sh`/`rank-verify-backlog.sh` の "Fails open" 契約) には触れない。このエッジケースへの明示的な対策 (フェンス不整合の検出・警告) は本 Issue のスコープ外とする。

### allowed-tools 影響チェーンチェック

`modules/l0-surfaces.md` の変更を受けて、全 8 読者 SKILL.md (`audit`/`code`/`auto`/`spec`/`merge`/`issue`/`review`/`verify`) を列挙した。今回の変更は既存スクリプト (`gh-issue-edit.sh` 等) への新規呼び出しを追加するものではなく (これらは既に各スキルの通常フローで呼ばれている)、prose 参照の追記のみのため、`allowed-tools` の追加は不要と判断した (`skills/verify/SKILL.md` の allowed-tools に `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*` が既に含まれていることを確認済み)。

### bats テスト入力フォーマット

- `tests/gh-issue-edit.bats`: 既存の `MOCK_BODY_FILE`/`CAPTURED_BODY_FILE` パターン (heredoc で body を書き込み、`--checkbox` 実行後の `CAPTURED_BODY_FILE` を検証) を踏襲する。
- `tests/check-pre-merge-ac.bats`: 既存の `make_gh_mock_body <<'BODY' ... BODY` ヘルパーを踏襲する。
- `tests/run-fact-matching.bats`: 既存の `scan-pending-ac:` セクションの `gh issue list` JSON mock (body は `\n` エスケープの JSON 文字列) パターンを踏襲する。`tests/rank-verify-backlog.bats` の `"rank-verify-backlog: code fence sample checkbox lines are excluded from both counts (#709 regression)"` テストの body 文字列 (`"### Post-merge\n\n- [ ] <!-- verify: rubric \"real\" --> real auto condition\n\n\`\`\`\n- [ ] <!-- verify: rubric \"fake\" --> fenced sample checkbox\n- [ ] fenced manual sample\n\`\`\`\n\n- [ ] manual after fence\n"`) と同型の構造を再利用できる。

### 新規テストケース要件のまとめ (SPEC_DEPTH=light — Step 13 retrospective 省略のため本欄に記録)

新規分岐ロジック (fenced code block 除外) を追加する 4 スクリプトそれぞれに対応する新規 `@test` を追加する: `tests/gh-issue-edit.bats` (フェンス内除外/フェンス外非除外の双方)、`tests/check-pre-merge-ac.bats` (Issue 本文が明示要求)、`tests/run-fact-matching.bats` の `scan-pending-ac:` 節 (Spec 発見分)。`scripts/rank-verify-backlog.sh` はロジック変更なし (コメントのみ) のため新規テスト不要 — 既存の `tests/rank-verify-backlog.bats` の fence テストがそのまま回帰確認として機能する。

### Issue retrospective / spec retrospective の扱い

SPEC_DEPTH=light のため Step 13 (Spec Retrospective、issue retrospective 転記を含む) は skip する。`/issue` フェーズの Autonomous Auto-Resolve Log 全文は Issue #1071 のコメント (`## Consumed Comments` セクション参照) に記録済みであり、要点は本 Notes の各節 (Scope expansion / Step 番号の表記ゆれ / SSoT の扱い) に反映済みのため、本 Spec 内での重複転記はしない。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / intent: `/issue` フェーズの Issue Retrospective コメント (Autonomous Auto-Resolve Log)。3 件の曖昧点 (SSoT 定義先を `modules/l0-surfaces.md` に決定、`check-pre-merge-ac.sh` を Pre-merge AC に追加、`skills/verify/SKILL.md` の checkbox 列挙処理を Pre-merge AC に追加) を自動解決し、既に Issue 本文へ反映済み。本 Spec はこの反映済み本文をそのまま設計のベースラインとして使用した (追加のアクションなし) / url: https://github.com/saitoco/wholework/issues/1071#issuecomment-5366096314

### code phase (cutoff: 2026-08-21T06:58:56Z, most recent `phase/ready` label assignment)

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- N/A — all 5 Implementation Steps executed as designed, in order, with no reordering, omission, or approach change.

### Design Gaps/Ambiguities

- N/A — no new ambiguity surfaced during implementation. The Spec's own Notes (Step 番号の表記ゆれ, Scope expansion beyond Issue body) already anticipated and resolved the two points that could otherwise have caused rework (Step 4/6/8b vs. the Issue body's "Step 3" reference; `scan-pending-ac.sh`/`rank-verify-backlog.sh` inclusion despite not being named in the Issue's Pre-merge AC).

### Rework

- N/A — no rework occurred. Each of the 4 target scripts' `in_fence` tracking pattern was implemented directly from `scripts/rank-verify-backlog.sh`'s existing reference implementation with no trial-and-error.

### Test Verification (Step 9 pre-implementation FAIL check)

- Confirmed pre-implementation FAIL for 3 new test(s): `tests/gh-issue-edit.bats` "checkbox: fenced sample checkbox is excluded from index counting", `tests/check-pre-merge-ac.bats` "(g) fenced code block sample checkbox is excluded from index (issue #1071)", and `tests/run-fact-matching.bats` "scan-pending-ac: fenced sample checkbox lines are excluded from candidates (#709 pattern, issue #1071)" — each stashed the target script's change, ran the test to confirm FAIL, then restored and confirmed PASS.
- Full bats suite (`bats --jobs 18 tests/`) run in parallel per the Behavioral Change Detection rule: `scripts/scan-pending-ac.sh` is referenced by two test files (`tests/scan-pending-ac.bats`, `tests/run-fact-matching.bats`) beyond a single direct counterpart, and the three modified SKILL.md files are each referenced by several test files (auto/audit/verify's own step-content assertion suites) — 1908/1908 PASS.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Followed `scripts/rank-verify-backlog.sh`'s existing `in_fence` toggle pattern verbatim for the other 3 scripts, rather than devising a new implementation — it was already a proven regression guard for the same class of bug (#709), so reusing it minimized review risk.
- Reused `tests/rank-verify-backlog.bats`'s exact `#709`-regression body string for the new `scan-pending-ac:` test in `tests/run-fact-matching.bats`, per the Spec's own guidance, to keep the two scripts' fence-handling test fixtures directly comparable.
- All 6 Pre-merge acceptance conditions were verified PASS via self-review against the diff (rubric-style adversarial check) plus an actual full bats run, and checked off on the Issue before PR creation.

### Deferred Items
- The Post-merge AC ("run `/verify` against an Issue containing a fenced notation sample and confirm checkboxes update at the correct index") is `verify-type: manual` and left unchecked — it requires an actual post-merge `/verify` run against a live Issue with this exact shape, which cannot be exercised pre-merge.
- None else — no `spec-approval-needed` deferrals, no scope-out remediations identified during implementation.

### Notes for Next Phase
- No refactor occurred, so no Issue/Spec verify command sync was needed in Step 10 — all 6 Pre-merge conditions matched the implementation as designed.
- `scripts/rank-verify-backlog.sh` itself has no logic change (comment-only), so its own existing `tests/rank-verify-backlog.bats` fence tests continue to serve as the reference-implementation regression guard; no new test was added for it.
- Full bats suite (1908/1908) already confirms no regression across the wider `verify`/`auto`/`audit` SKILL.md test coverage that the Behavioral Change Detection rule flagged — `/review` does not need to re-run the full suite from scratch on this basis alone.
