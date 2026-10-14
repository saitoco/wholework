# Issue #1526: verify-executor: gh run list の判定で run の headSha が実装コミットを含むことを確認

## Overview

patch route の CI 確認の標準形 (`github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion,status --jq '...'" "success"`) は、main の最新 run が実装コミットより前のものでも PASS する。`/verify` が patch route の `github_check` で `gh run list` / `gh run view` を判定するとき、判定に使う run の `headSha` が Issue の実装コミット (`closes #N` のコミット) を含むことを確かめ、含まなければ PASS / FAIL にせず PENDING として扱う手順を `modules/verify-executor.md` に追加する。標準形のコマンド (既存 AC) は変えない。

## Reproduction Steps

1. patch route (Size XS/S、`always-pr: true` なし) の Issue に、標準形の CI AC を置く (例: #1525 の AC4)。
2. `/code` が実装コミット (`closes #N`) と retrospective コミットを 1 回の push で main に送る。
3. push 直後に `/verify` が始まる。この時点で、実装 push の run はまだ登録されていないか、`in_progress` である。
4. run が未登録のとき: `--branch=main --limit=1` の最新 run は直前コミットの run で、すでに `completed` / `success` になっている。コマンドの出力は `success` で、`expected_value` と一致して PASS する (結果は実装前のもの)。run が `in_progress` のとき: 既存の `in_progress` 検出 (§ In-Progress Detection Constraint) が PENDING にするので、この経路は塞がれている。

実例は #1525 の verify (2026-10-13)。verify 開始時点の最新 run `b9ca9ff6` (実装コミット `98b5633c` を含む) は `in_progress` で、1 つ前の run `31643ad3` (spec のコミット) は `success` だった。triage の AC 監査と Spec の Notes を人手で引き継いで回避できたが、同種の人手の照合は #1265 (`headSha` `28a99f28` が実装コミット `ecb49dc2` を含むことを確認)、#1339、#1353 の verify でも続いており、手順として固定されていない (出所: Issue #1526 本文の Background、`docs/spec/issue-1525-subagent-unnamed-launch-test.md` の Notes と Verify Retrospective、`docs/sessions/83307-1786372673-2026-08-10/session.md` の 85 行目、`docs/sessions/18115-1786457312-2026-08-11/session.md` の 80 行目)。

## Root Cause

`modules/verify-executor.md` の `github_check` は、コマンドの出力を `expected_value` と比べるだけで、出力のもとになった run が Issue の実装コミットを含むかを確かめない。§ "github_check: `gh run list` In-Progress Detection Constraint" が扱うのは run の `status` (完了したか) だけで、run とコミットの対応は対象外である (`modules/verify-executor.md` 内の `headSha` は 0 件。測定: `grep -c 'headSha' modules/verify-executor.md`、2026-10-14 時点の main `bf86d3fd`)。標準形の `--branch=main --limit=1` が選ぶのは「main の最新 run」であって「この Issue の実装を含む run」ではない。`modules/verify-classifier.md` § Patch Route CI Verification Note の "Residual risk" も、この点を「自動チェックではなくガイダンス」と明記しており、executor が自力で気づくことに頼っていた。

修正方針の妥当性: run の `headSha` と実装コミットの祖先関係を見れば、(i) push 直後で run が未登録、(ii) 実装前の run しかない、のどちらも検出できる。判定はコマンドの外 (executor の手順) で行うので、既存 AC の verify command は書き換えなくてよい。等価ではなく包含で見るのは、patch route の push が `[実装コミット, retrospective コミット]` を 1 回で送り、run を持つのは push の先頭 (retrospective コミット) だけだから (`modules/verify-classifier.md` の "Why `--commit` is not used")。

## Changed Files

- `modules/verify-executor.md`: 次の 4 か所を変更する (英語で記述。文面は Notes の「追加する文面」に従う)
  - `## Input`: `Issue number` (optional) を追加する
  - 翻訳表の `github_check` 行: 行末の `Same \`in_progress\` detection and display name fallback apply in full mode` の後に、Run/commit correspondence check への参照句を追加する (セル内に `|` を入れない)
  - `### github_check: \`gh run list\` In-Progress Detection Constraint`: 節の末尾 (`**Constraint scope:**` の段落の後、次の `### grep Verify Command: ERE vs BRE Reference` の前) に、`**Run/commit correspondence check ...**` の段落、手順 1〜3、`**Scope:**` の段落を追加する。見出しは変更しない
  - `6. Classify each condition's verification result` の `**PENDING**` の定義: `gh run list` / `gh run view` が読む run が実装コミットをまだ含まない場合を追加する
- `modules/verify-classifier.md`: § "Patch Route CI Verification Note" の 2 か所を変更する
  - `When \`/verify\` detects \`github_check "gh pr checks"\` ...` の段落の後に、`/verify` が `headSha` を確かめて PENDING にする旨の段落を追加する
  - `**Residual risk (defect A is not fully eliminated):**` の段落を、古い run を読む側は自動チェック済みで、残るのは別セッションの後続 push の run を読む側だけ、という内容に書き換える
- `tests/verify-executor.bats`: `load 'helpers/markdown-section'` の追加、ヘッダコメントの更新、新規テスト 4 件 (Implementation Steps の 3)
- [Steering Docs sync candidate] 検索範囲は `docs/` `tests/` `scripts/` `modules/` の全ファイル (測定: `grep -rl -- "<keyword>" docs/ tests/ scripts/ modules/ | wc -l`、2026-10-14 時点の main `bf86d3fd`)
  - keyword "headSha" skipped: matched 12 files (no discriminating power)
  - keyword "Patch Route CI Verification Note" skipped: matched 22 files (no discriminating power)
  - keyword "verify-classifier.md" skipped: matched 145 files (no discriminating power)
  - keyword "verify-executor.md" skipped: matched 194 files (no discriminating power)
  - keyword "In-Progress Detection Constraint" (3 files): 該当は `modules/verify-executor.md` と `modules/verify-classifier.md` (どちらも変更対象) と、過去の Spec `docs/spec/issue-1449-gh-run-list-inprogress.md` (対象外) のみ。見出しを変えないので参照側の更新は不要
- 変更不要と確認したファイルは Notes の「他ファイルの扱い」に根拠を記録した

## Implementation Steps

1. `modules/verify-executor.md` を編集する (→ AC 1, 2)
   - 編集箇所は Changed Files の 4 か所。英語の文面は Notes の「追加する文面」の A〜D に従う
   - 分岐の期待動作 (fail-closed を基本とし、実装コミットを特定できない場合だけ「対象外」) は Notes の「edge case の期待動作」の表に従う
   - 最小の実例 (2026-10-14 に取得、`origin/main` = `bf86d3fd`): `git log origin/main --extended-regexp --grep='closes #1525([^0-9]|$)' --format=%H -n 1` → `98b5633c6215fe34695607d5c5371762938dc442`、`gh run list --workflow=test.yml --branch=main --limit=1 --json headSha --jq '.[0].headSha'` → `bf86d3fd82113ae7a7d7b41e0482120de44c544c`、`gh api "repos/{owner}/{repo}/compare/98b5633c6215fe34695607d5c5371762938dc442...bf86d3fd82113ae7a7d7b41e0482120de44c544c" --jq '.status'` → `ahead` (引数の順を逆にすると `behind`、同一 SHA だと `identical`)
   - 見出し `### github_check: \`gh run list\` In-Progress Detection Constraint` は変えない。`gh run list` を含む見出しを新設しない (AC 1 の `section_contains` は見出しを部分一致で探すため、2 節に当たると対象が不定になる)。節内に `###` 以上の見出しや、`#` で始まる行を含むコードフェンスを置かない (走査範囲が途中で切れる。`modules/verify-patterns.md` §29)
2. `modules/verify-classifier.md` を更新する (after 1) (→ AC 2 の整合)
   - Changed Files の 2 か所。文面は Notes の「追加する文面」の E, F に従う。"Residual risk" の後半 (別セッションの後続 push の run を読む側) は残す
3. `tests/verify-executor.bats` にテストを追加する (after 1, 2) (→ AC 1, 2 の回帰ガード)
   - 既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/verify-executor.bats` に `verify-executor: gh run list section documents the headSha run/commit correspondence check` ほか 3 件) を追加したうえでスイートが PASS すること
   - 4 件の内容は Notes の「bats テストの入力形式」に従う。`/code` が commit 前に回す既存チェック (forbidden expressions、language convention など) も通すこと

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/verify-executor.md" "gh run list" "headSha" --> `modules/verify-executor.md` の `github_check` (`gh run list`) の判定手順に、run の `headSha` を確かめる手順がある
- <!-- verify: rubric "modules/verify-executor.md の github_check で gh run list / gh run view を判定する手順が、判定に使う run の headSha が Issue の実装コミット (closes #N のコミット) を含むかを確かめ、含まない場合 (実装コミットより前の run しかない場合) は PASS とせず PENDING として扱う、と定めている" --> 実装コミットを含まない run しかない場合は PASS ではなく PENDING になる

### Post-merge

- patch route の Issue で、`/verify` の開始時に実装コミットの CI run がまだ始まっていない (または `in_progress`) とき、`github_check "gh run list ..."` の AC が PASS ではなく PENDING として扱われる <!-- verify-type: opportunistic -->

## Notes

### 追加する文面 (英語。`modules/` と `tests/` には英語だけを入れる)

**A. `modules/verify-executor.md` の `## Input`** (`PR_BRANCH` の項目の次に追加。他の項目に合わせて文末にピリオドは付けない)

```markdown
- **Issue number** (optional): The Issue whose acceptance conditions are being verified (`/verify` supplies its `NUMBER`). Used only by the run/commit correspondence check of `github_check` (see "github_check: `gh run list` In-Progress Detection Constraint") to find the Issue's implementation commit
```

**B. 翻訳表の `github_check` 行の末尾** (`Same \`in_progress\` detection and display name fallback apply in full mode | \`always_ask\` |` の部分を次に置き換える)

```markdown
Same `in_progress` detection and display name fallback apply in full mode. **Run/commit correspondence check** (full mode, patch route, `gh_command` starting with `gh run list` or `gh run view`): before evaluating the output, confirm that the `headSha` of the run the command reads contains the Issue's implementation commit; a run that does not contain it is **PENDING**, never PASS or FAIL. See "github_check: `gh run list` In-Progress Detection Constraint" below | `always_ask` |
```

**C. `### github_check: \`gh run list\` In-Progress Detection Constraint` の末尾** (`**Constraint scope:**` の段落の後に、空行を挟んで追加)

```markdown
**Run/commit correspondence check (full mode, patch route; `gh_command` starting with `gh run list` or `gh run view`):** the status synthesis above only tells whether the run has finished, not whether it was produced by the Issue under verification. Right after the implementation push, the newest run on the branch can still be an earlier commit's run that is already `completed` with `success`, so the output alone can PASS on a result that predates the implementation. Before evaluating the output, confirm that the `headSha` of the run the command reads contains the Issue's implementation commit (the commit carrying `closes #N`). Use containment, not equality: a patch-route push carries the implementation commit and the retrospective commit together, and only the push head gets a run (`modules/verify-classifier.md` § "Patch Route CI Verification Note", "Why `--commit` is not used"). Run each command below on its own, as a plain single command with literal arguments, and copy each resolved SHA into the next command by hand (the worktree isolation guard refuses `$(...)`, and it also refuses an unquoted `{owner}/{repo}/compare/<base>...<head>` endpoint, so keep the `gh api` endpoint in double quotes; observed 2026-10-14).

1. **Implementation commit (`IMPL_SHA`).** `ISSUE_NUMBER` is the Issue under verification (see Input). Run `git fetch origin <branch>`, then `git log origin/<branch> --extended-regexp --grep='closes #<ISSUE_NUMBER>([^0-9]|$)' --format=%H -n 1`, where `<branch>` is the `--branch` value of `gh_command` if it is a plain ref name, otherwise `BASE_BRANCH` (default `main`). The newest match wins, and the `([^0-9]|$)` tail keeps `closes #15` from matching `closes #152`. A non-zero exit → **UNCERTAIN**. Exit 0 with no output, or no `ISSUE_NUMBER` → the check does not apply: evaluate `gh_command` as usual and add "run/commit correspondence not checked: implementation commit not identified" to Details (operate route, a non-`main` base branch where `/code` adds no `closes #N`, and an XL parent have no such commit by design, so their results do not change).
2. **Run head (`RUN_HEAD_SHA`).** For `gh run list`, run it again with the same filter flags, `--limit=1`, and `--json headSha --jq '.[0].headSha'` in place of the command's own `--json`/`--jq`; for `gh run view <run-id>`, run `gh run view <run-id> --json headSha --jq '.headSha'`. A non-zero exit → **UNCERTAIN**. Empty output (no run matched) → **PENDING** (detail: "no CI run found yet").
3. **Containment.** `gh api "repos/{owner}/{repo}/compare/<IMPL_SHA>...<RUN_HEAD_SHA>" --jq '.status'` with both SHAs in full. Check the exit status first: on failure (HTTP 404/422/403/5xx, network) the error body goes to stdout and is not a status.
   - `identical` or `ahead` (the run head is the implementation commit or its descendant): evaluate `gh_command`'s output as usual (the `in_progress` rule and the `expected_value` comparison above). On PASS, put both short SHAs in Details.
   - `behind` or `diverged` (only runs older than the push exist, or the push has not produced a run yet): **PENDING** whatever the run's conclusion (detail: "run head {RUN_HEAD_SHA short} does not contain implementation commit {IMPL_SHA short}; re-verify after CI for the implementation push completes"). A stale `success` is no evidence for this Issue, and a stale `failure` is no verdict against it.
   - Anything else, or a non-zero exit: **UNCERTAIN** (no retry; the caller re-runs `/verify`).

**Scope:** the check applies only in `full` mode when `PR_NUMBER` is empty (patch route). It is skipped in `safe` mode (`gh run list` is outside the safe-mode allowlist, and the implementation commit is not on the base branch before merge) and for pr route: a squash-merge commit is not a descendant of the PR's own head (`diverged`), so ancestry cannot relate a PR-branch run to the merge, and the pr-route standard form is `gh pr checks`. The job-level sub-form above reads the check-runs of the branch tip, which contains the implementation commit once it is pushed, so it needs no separate check. A newer run on the same branch contains everything an older one does, so evaluating the output after this check cannot read a run that lacks the implementation commit. If no run can ever contain the implementation commit (a `pull_request`-only workflow, path filters), the condition stays PENDING: rewrite it instead of re-running it.
```

**D. `6. Classify each condition's verification result` の `**PENDING**`** (`   - **PENDING**: CI job is in_progress; temporary execution state, re-verify after CI completes` を次に置き換える)

```markdown
   - **PENDING**: CI job is in_progress, or the run read by a `gh run list`/`gh run view` command does not yet contain the Issue's implementation commit; temporary execution state, re-verify after CI completes
```

**E. `modules/verify-classifier.md` § "Patch Route CI Verification Note"** (`When \`/verify\` detects \`github_check "gh pr checks"\` ...` の段落の後に、空行を挟んで追加)

```markdown
`/verify` does not rely on this command's output alone. Before evaluating it, `modules/verify-executor.md` § "github_check: `gh run list` In-Progress Detection Constraint" (Run/commit correspondence check) confirms that the `headSha` of the run the command reads contains the Issue's implementation commit (the commit carrying `closes #N`); a run that does not is PENDING, not PASS or FAIL. The verify command therefore needs no `headSha` term of its own.
```

**F. 同節の "Residual risk" の段落** (`**Residual risk (defect A is not fully eliminated):** ...` の段落全体を次に置き換える)

```markdown
**Residual risk (runs from later pushes by other sessions are not covered):** `--branch=main --limit=1` selects "the most recent run on the branch", not "the run produced by this Issue's own push". The first gap — the most recent run predating the implementation commit, for example right after the push and before its run is registered — is closed by the Run/commit correspondence check described above. The second gap remains: this repository runs concurrent sessions as a matter of course, and another session's push to `main` after this Issue's push becomes the new "most recent" run. That run contains the implementation commit, so the check passes, yet its result may reflect the other session's change. When the referenced run's result looks inconsistent with this Issue's own change (e.g., `cancelled`, or a `failure` on a job unrelated to the Issue's Changed Files), treat the condition as UNCERTAIN rather than a mechanical PASS/FAIL and recommend re-running `/verify` — the same operational stance as the CI Reference Fallback (#1126), applied here as guidance rather than an automated check.
```

### edge case の期待動作 (fail-safe critical)

この変更の対象は、AC を PASS にするかどうかを決める gate である。PASS は AC のチェックと Issue のクローズにつながる唯一の結果で、PENDING / UNCERTAIN は `phase/verify` に留まって再実行できる。誤った PASS のほうが高くつくので、コマンドの失敗や想定外の出力は fail-closed (UNCERTAIN) にする。実装コミットが「設計上存在しない」場合だけは失敗ではなく「対象外」にして、従来の結果を変えない。

| 状況 | 期待する結果 | 理由 |
|------|--------------|------|
| `ISSUE_NUMBER` が無い、または `git log` が exit 0 で出力が空 | 対象外 (従来どおり評価し、Details に注記) | operate route、非 main の base ブランチ (`/code` は `(closes #N)` を付けない: `skills/code/SKILL.md` の commit 規則)、XL 親には `closes #N` のコミットが設計上無い |
| `git fetch` / `git log` が非 0 終了 | UNCERTAIN | 実装コミットを確かめられない結果を PASS にしない |
| `gh run list` / `gh run view` (headSha 取得) が非 0 終了 | UNCERTAIN | 同上 |
| headSha 取得の出力が空 (run が 0 件) | PENDING | run がまだ登録されていない |
| compare が `identical` / `ahead` | 従来の評価 (`in_progress` は PENDING、`expected_value` と比較) | run の head が実装コミット以降 |
| compare が `behind` / `diverged` | PENDING (run の conclusion にかかわらず) | 古い `success` は証拠にならず、古い `failure` は判定の根拠にならない |
| compare が上記以外の出力、または非 0 終了 (HTTP 404/422/403/5xx、ネットワーク) | UNCERTAIN (再試行しない) | エラー本文は stdout に出るので終了コードを先に見る (実測: 404 の本文に `"status":"404"` が含まれる) |
| 特殊文字・改行・マルチバイト | コマンドに入る値は、40 桁の 16 進の SHA、整数の `ISSUE_NUMBER`、ref 名だけの `<branch>` に限る。コミットの件名は解析しない | 注入の余地を作らない |
| 空・巨大な入力 | `--limit=1` と `-n 1` で、各コマンドの出力は 1 行 | |

### 設計判断 (非対話モードで自動解決した点)

- **適用範囲を patch route (`PR_NUMBER` が空)・full mode・`gh run list` / `gh run view` に限る**。Issue の Purpose が patch route であり、AC 2 の rubric も `closes #N` のコミットを実装コミットとしている。pr route は、squash マージ後のコミットと PR 自身の head が祖先関係にならない (実測: `gh api "repos/{owner}/{repo}/compare/8009f1b2...a8584bc3"` = `diverged`。#1524 の squash 後コミットと PR head) ため、PR ブランチの run を読む AC がいつまでも PENDING になる。pr route の標準形は `gh pr checks` で、今回は対象外とした (merge commit を実装コミットとして扱う拡張は別 Issue の候補)。
- **実装コミットを特定できないときは「対象外」**。release branch・operate route・XL 親では `closes #N` のコミットが無いのが正常で、ここを UNCERTAIN にすると従来 PASS できた AC が手動確認に回る。Details に注記を残すので、確認されていないことは見える。patch route の main では `/code` が `closes #N` を必ず付け、`code-patch` の完了判定 (`scripts/reconcile-phase-state.sh`、`modules/phase-state.md`) も主要な成功シグネチャをこのコミットにしているので、欠けるのは異常時に限られる。
- **包含判定に GitHub の compare API を使う**。`identical` / `ahead` という肯定の語が返るので、エラーや想定外の出力は自然に fail-closed になる。ローカルの object に依存せず、`/verify` の `allowed-tools` に追加が要らない。
- **見出しを変えない**。AC 1 の `section_contains` は「`gh run list` を含む見出し」が 1 節だけであることに依存する (Issue 本文の Auto-Resolved Ambiguity Points)。見出しを改名すると、`modules/verify-classifier.md` と `skills/verify/SKILL.md` の参照、phase/verify に残る Issue の既存 verify command も壊れる。
- **ガードテストを `tests/verify-executor.bats` に足す**。このファイルは patch route の `github_check` の形をガードするためのもので、同じ系統のルールを同じ場所に置ける。

### 却下した代替案

1. AC のコマンドに `--commit=<IMPL_SHA>` を入れる: 実装コミット自身は run を持たない (run を持つのは push の先頭だけ) ので常に空になる (`modules/verify-classifier.md` の "Why `--commit` is not used")。
2. `RUN_HEAD_SHA == IMPL_SHA` の等価判定: push の先頭は retrospective コミットなので一致しない。
3. AC の jq に `headSha` を足す: 既存 AC の書き換えが要り、`expected_value` の比較 (`"success"`) の形も変わる。executor 側で見れば既存 AC がそのまま守られる。
4. `git merge-base --is-ancestor`: 終了コードが明快だが、`/verify` の `allowed-tools` に `git merge-base` が無い。足すには `skills/verify/SKILL.md` の frontmatter を編集し、`skill-body-sha` (frontmatter を含むファイル全体のハッシュ) を更新する必要がある。
5. ローカルの `git log <RUN_HEAD>..<IMPL>` が空なら包含とみなす: 「出力が空」を肯定の証拠にするため、エラーで出力が空になったときに包含と読み違えると偽 PASS になる。
6. 新規スクリプト (`scripts/check-run-contains-commit.sh` など): 3 コマンドで済む手順にスクリプト、bats、`allowed-tools`、`WHOLEWORK_SCRIPT_DIR` モックを足すのは重く、Size S を超える。手順の分岐が増えるなら将来の候補。
7. 実装コミットを Issue timeline の `closed` event の `commit_id` で特定する: #1525 では `98b5633c` と一致した (実測) が、`--paginate` と最後の要素の取り方が重い。リポジトリの既存パターン (`git log origin/main --grep="closes #N"`: `scripts/reconcile-phase-state.sh`、`modules/phase-state.md`、`modules/orchestration-fallbacks.md`) に揃えた。

### 実データでの確認 (出所)

2026-10-14 に、このリポジトリ (`saitoco/wholework`、`origin/main` = `bf86d3fd`) で実行した結果。再取得するときは同じコマンドを使う。

| コマンド | 結果 |
|----------|------|
| `git log origin/main --grep='closes #1525' --format='%H %s' -n 5` | `98b5633c6215fe34695607d5c5371762938dc442 test: add bats guard ... (closes #1525)` |
| `git log origin/main --extended-regexp --grep='closes #152([^0-9]|$)' --format='%h %s' -n 3` | `c7652de0` (closes #152) だけ。素朴な `--grep='closes #152'` は `98b5633c` (closes #1525) も返す |
| `git log origin/main --extended-regexp --grep='^closes #[0-9]+$' --format='%h' -n 2` | `4c6f7e33` と `61751675` が該当。本文に `closes #N` だけの行がある commit にも一致するので、`^` と `$` は行頭・行末に効く |
| `gh run list --workflow=test.yml --branch=main --limit=4 --json databaseId,headSha,status,conclusion,createdAt,event` | `headSha` が取れる。最新 run の `headSha` は `bf86d3fd82113ae7a7d7b41e0482120de44c544c` |
| `gh run list --workflow=test.yml --branch=no-such-branch-zz --limit=1 --json headSha,status,conclusion --jq '.[0].headSha'` | 出力は空、exit 0 |
| `gh api "repos/{owner}/{repo}/compare/98b5633c...bf86d3fd" --jq '.status'` (SHA は 40 桁) | `ahead`。逆順は `behind`、同一 SHA は `identical` |
| 同 `compare/8009f1b2...a8584bc3` (#1524 の squash 後コミットと PR head) | `diverged` |
| 同 `compare/8009f1b2...0000000000000000000000000000000000000000` | HTTP 404、exit 1、本文は stdout (`{"message":"Not Found",...,"status":"404"}`) |
| `gh pr view 1524 --json mergeCommit --jq '.mergeCommit.oid'` | `8009f1b247c6f27e9bd4be28b2e8a2a8b633f5b4` (pr route は対象外のため手順では使わない) |
| 引用符なしの `gh api repos/{owner}/{repo}/compare/98b5633c...bf86d3fd --jq '.status'` (SHA は 40 桁) を単独で実行 | worktree 隔離ガードが拒否した ("a brace expansion")。同じ endpoint を二重引用符で囲むと受理された (上の `ahead` の行)。`gh api repos/{owner}/{repo}/commits/main/check-runs --jq '.total_count'` (引用符なし、`...` なし) は単独で受理された (`modules/verify-patterns.md` §34 の記述どおり)。拒否の原因は、引用符なしの `{owner}/{repo}` と `...` を同じ語に含む形で、複合コマンドかどうかではない |

外部仕様 (公式ドキュメント、2026-10-14 に取得):

- GitHub REST API "Compare two commits" (https://docs.github.com/en/rest/commits/commits#compare-two-commits): `status` は `diverged` / `ahead` / `behind` / `identical` の 4 値。basehead は `BASE...HEAD`。parameter の説明は "Both must be branch names in repo" だが、概要は "refs (branches or tags) and commit SHAs" とある。SHA が使えることは上の実測で確認した
- `gh run list` (https://cli.github.com/manual/gh_run_list): `--json` のフィールドに `headSha` / `status` / `conclusion` / `databaseId` がある。`--limit` の既定は 20。`--commit` は commit の SHA で絞り込む

### bats テストの入力形式

新規テストは、ドキュメントの文面だけを検査する (LLM の応答はモックしない。リポジトリの他のドキュメントガードと同じ)。入力は次の Markdown。

- `md_section FILE HEADING_PREFIX [END_LEVEL]` (`tests/helpers/markdown-section.bash`): 見出しの前方一致 (リテラル) でその節を標準出力へ出す。END_LEVEL を省くと、見出しの `#` の数 (`###` なら 3) 以下の見出しの手前まで。見つからなければ exit 1
- `modules/verify-executor.md` の見出し `### github_check: \`gh run list\` In-Progress Detection Constraint`、翻訳表の行頭 `| \`github_check "gh_command" "expected_value"\` |`
- `modules/verify-classifier.md` の見出し `### Patch Route CI Verification Note`

新規テスト 4 件 (名前と検査内容)。非最終行の検査には `|| false` を付ける (`scripts/check-bare-bracket-assertions.sh` の規約)。

1. `verify-executor: gh run list section documents the headSha run/commit correspondence check`: 節の中に `headSha`、`Run/commit correspondence check`、`closes #<ISSUE_NUMBER>([^0-9]|$)`、`compare/<IMPL_SHA>...<RUN_HEAD_SHA>`、`PENDING` がある
2. `verify-executor: github_check table row points to the run/commit correspondence check`: 翻訳表の `github_check` 行に `Run/commit correspondence check` がある
3. `verify-executor: only one heading contains gh run list (section_contains heading match stays unambiguous)`: `grep -cE '^#+ .*gh run list' modules/verify-executor.md` が 1
4. `verify-classifier: Patch Route CI Verification Note points to the run/commit correspondence check`: 節の中に `Run/commit correspondence check` と `headSha` がある

新規ロジック (PENDING へ分岐する条件) を検証する新規テストケースの要件は、上の 4 件で満たす。実装コミットを含まない run を実際に返す fixture (モック) は作らない。手順は LLM が実行する文書で、スクリプトではないため。

### 他ファイルの扱い (変更不要と確認した根拠)

- `skills/verify/SKILL.md`: 変更しない。Step 2 が `modules/verify-executor.md` の翻訳表に従って実行する経路なので、翻訳表の `github_check` 行に参照句を足せば `/verify` に届く。frontmatter の `allowed-tools` は、新手順の 5 コマンド (`git fetch`、`git log`、`gh run list`、`gh run view`、`gh api`) をすべて許可済み (確認: `sed -n '1,12p' skills/verify/SKILL.md` の `git fetch:*` `git log:*` `gh run list:*` `gh run view:*` `gh api:*`)。編集すると `scripts/check-skill-body-hash.sh` の `skill-body-sha` と `skill-body-lines` の更新が要る
- `skills/issue/SKILL.md`、`skills/issue/spec-test-guidelines.md`、`modules/verify-patterns.md`、`skills/spec/SKILL.md`: AC の書き方 (標準形のコマンド) は変わらないので変更不要 (確認: 標準形の文字列は各ファイルで同一のまま)
- `skills/code/SKILL.md`: Step 10 の "CI verification AC exclusion" は push 前に標準形を評価しない規則で、新しいチェックと干渉しない (`/code` は実装コミットの前に評価する)。変更不要
- `skills/triage/skill-dev-verify-audit.md`: `github_check` 型の常時 PASS の節 (141〜155 行) は `gh issue view` / `gh pr view` 系を対象にし、full mode 専用のコマンド (`gh run list`) はレビュー判定に委ねている。Pattern 4 は標準形を勧めるだけで古い run には触れない。変更不要
- `skills/auto/SKILL.md` (410 行目付近): XL 親の横断条件の事前検証 (best-effort、full mode) も verify-executor を使う。frontmatter の `allowed-tools` に `git log` `git fetch` `gh api` が無く、許可されないコマンドは UNCERTAIN になる。その箇所は FAIL だけを警告するので影響しない。XL 親には `closes #<親>` のコミットが無いので、実装コミットを特定できず「対象外」で従来どおり。権威ある検証は `/verify` なので `allowed-tools` は変えない
- docs: `docs/guide/*`、`docs/workflow.md`、`docs/environment-adaptation.md`、`README.md` に `github_check` の記述は 0 件 (確認: `grep -rn 'github_check' docs/guide docs/workflow.md docs/environment-adaptation.md README.md`)。`docs/translation-workflow.md` の対象はトップレベルの `docs/*.md` だけで、今回の変更ファイルは含まれないので `docs/ja/` の同期は不要
- `docs/structure.md`: モジュールの役割は変わらず、ファイルの追加・削除・改名もない。Listing-side sub-check は対象外

### 消費側スイープ (PENDING の意味の拡張)

PENDING の発生条件に「run が実装コミットをまだ含まない」を加える。パターン `PENDING`、対象 `skills/ modules/ scripts/` (`modules/verify-executor.md` を除く) で 51 行が該当した (測定: `grep -rn 'PENDING' skills/ modules/ scripts/ | grep -v '^modules/verify-executor.md' | wc -l`、2026-10-14)。verify の結果としての PENDING を使う消費側は次の 2 つで、前提は崩れない。

- `skills/verify/SKILL.md` (6 行): 結果分岐 (c) "PENDING only" は `phase/verify` を保ち、「CI 完了後に `/verify $NUMBER` を再実行してください」と案内する。新しい原因 (run 未登録) でも同じ動作でよい。メッセージの「CI が実行中」は run 未登録の場合にやや不正確だが、動作は変わらないので SKILL.md は編集しない
- `skills/review/SKILL.md` (3 行): PR のチェック状態の表示。`/review` は safe mode で今回のチェックを適用しないので影響しない

残りは `run-review.sh` の exit 2 (PENDING) 系 (`scripts/run-review.sh`、`scripts/run-auto-sub.sh`、`modules/orchestration-fallbacks.md`、`modules/ci-failure-classifier.md` など) で、別の概念であり対象外。

### 既存パターンとの差分

実装コミットの探し方は、リポジトリの既存パターン `git log origin/main --grep="closes #${ISSUE_NUMBER}"` (`scripts/reconcile-phase-state.sh` の 225・235 行目、`modules/phase-state.md`、`modules/orchestration-fallbacks.md`、`skills/auto/SKILL.md` の 190 行目) に揃えた。違いは、番号の末尾を `([^0-9]|$)` で締める点。素朴な部分一致では `#152` が `#1525` のコミットにも当たる (実測は上の表)。既存の呼び出し箇所も同じ弱さを持つが、今回のスコープ外なので直さない。

### その他の確認結果

- Issue 本文の事実主張 (標準形の出典、In-Progress Detection Constraint が in-progress だけを扱うこと、共有モジュールであること、#1525 の経緯) とコードベースの矛盾は検出されなかった
- audit / investigation 型の Issue ではない (機能追加の修正)。コストの高い・不可逆な Implementation Step、外部サービスへのログインを要する Step はない
- 新しい verify command の型は使わない (AC は `section_contains` と `rubric`)。AC 1 は実装前の `headSha` が 0 件なので常時 PASS ではない
- Post-merge の `verify-type: opportunistic` は `modules/verify-classifier.md` の定義 (条件文が「`/skill-name` を実行したときに X を確かめる」の形) に沿う。実際の patch route の Issue で `/verify` が走ったときにだけ観測でき、決定的なコマンドで置き換えられないので、そのままにする
- Size の再評価 (2 軸): 変更ファイル 3 件で暫定 M、バグ修正 (原因が明確) と文書中心の変更で 1 段下げて S。CI 依存の下限に該当する変更はない。patch route のまま

### 未確認事項 (Uncertainty)

- **compare API の basehead に SHA を使う点**: 公式 docs の parameter 説明は "branch names" だが、2026-10-14 の実測では 40 桁の SHA で `ahead` / `behind` / `identical` / `diverged` が返った。仕様が変わっても `ahead` / `identical` 以外は PENDING か UNCERTAIN になるので、偽 PASS にはならない。検証方法: 上の「実データでの確認」の再取得。影響: Implementation Step 1
- **`md_section` がバッククォートを含む見出しを前方一致で拾えること**: `/code` で新規テストを実行して確認する。影響: Implementation Step 3

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (AC 1 の `section_contains` の見出し引数を `"github_check"` から `"gh run list"` に絞った判断。書き足す節は In-Progress Detection Constraint に確定) / https://github.com/saitoco/wholework/issues/1526#issuecomment-6158078372
- 参考: cutoff (`phase/issue` の付与、2026-10-14T00:23:32Z) より前の triage の AC 監査コメント (saito / MEMBER / https://github.com/saitoco/wholework/issues/1526#issuecomment-6158026872) は `/issue` で消費済みで、提案 (見出し引数の絞り込み) は Issue 本文の AC 1 に反映済み

## Code Retrospective

### Deviations from Design
- なし。Notes の A〜F の文面をそのまま `modules/verify-executor.md` (4 か所) と `modules/verify-classifier.md` (2 か所) に反映し、`tests/verify-executor.bats` に新規テスト 4 件を追加した。

### Design Gaps/Ambiguities
- `md_section` がバッククォートを含む見出しを前方一致で拾えるかという Uncertainty は、新規テスト 18 が PASS したことで解消した。
- Confirmed pre-implementation FAIL for 3 new test(s) (テスト 18、19、21)。テスト 20 は見出しの一意性を守るガードで、実装前から PASS するのは設計どおり (Spec の Notes に記載)。
- 全スイート (`bats --jobs 4 tests/`、2220 件) は FAIL なし。`validate-skill-syntax.py`、`check-forbidden-expressions.sh`、言語規約チェックも問題なし。

### Rework
- 手戻りなし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Notes の文面 A〜F をそのまま適用した (文面の独自調整なし)。
- patch route の最終 Implementation Step (テスト追加) を未コミットで Step 11 に持ち越し、`closes #1526` を実装コミットに付けた。

### Deferred Items
- Post-merge の opportunistic AC (patch route の Issue で `/verify` 開始時に実装コミットの run が未登録または `in_progress` のとき PENDING になる) は、実際の patch route Issue の `/verify` でのみ観測できるため未チェックのまま。

### Notes for Next Phase
- `/verify` の AC 2 (rubric) は `modules/verify-executor.md` の Run/commit correspondence check 節 (手順 3 の `behind` / `diverged` → PENDING) を根拠に判定できる。
- この Issue 自身の push 直後に `/verify` が走ると、新手順の最初の実例になりうる。`git log origin/main --extended-regexp --grep='closes #1526([^0-9]|$)'` で実装コミットを特定できる。
