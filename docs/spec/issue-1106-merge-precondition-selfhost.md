# Issue #1106: reconcile-phase-state: merge precondition の reviewDecision 要求を単一アカウント運用に適合

## Overview

`scripts/reconcile-phase-state.sh` の `_precondition_merge()` は merge precondition の判定を `reviewDecision == "APPROVED"` の一致のみで行っている。wholework は単一アカウントが Issue 起票・実装・レビュー・マージをすべて行う自己ホスト運用が前提だが、GitHub は自分自身の PR に対する `APPROVE` / `REQUEST_CHANGES` を HTTP 422 で拒否するため、`reviewDecision` は構造的に永久に空 (または `REVIEW_REQUIRED`) のままになる。結果として merge precondition の警告が毎回発火し、「本当に review が未完了なケース」と「自己 PR のため APPROVE できないだけのケース」を区別できないシグナルになっている。

`_completion_review()` (review フェーズの completion check) が既に採用している `<!-- review-summary -->` marker (または `## Review Response Summary` / `## レビュー回答サマリ` 見出しへのフォールバック) の検出ロジックを、`_precondition_merge()` にも代替シグナルとして導入する。`reviewDecision=APPROVED` の場合は従来どおり満足、`reviewDecision=CHANGES_REQUESTED` の場合は従来どおり mismatch とし、それ以外 (空 / `REVIEW_REQUIRED` など) の場合のみ marker の有無で判定する。

## Reproduction Steps

1. 自己ホスト運用のリポジトリで Issue を PR route (`/code` M/L サイズ) で実装し、PR を作成する。
2. `/auto` または直接 `scripts/reconcile-phase-state.sh merge $ISSUE --pr $PR --check-precondition --warn-only` を実行する。
3. PR 作成者と実行アカウントが同一のため、GitHub は self-`APPROVE`/`REQUEST_CHANGES` を 422 で拒否しており `reviewDecision` は空文字 (または `REVIEW_REQUIRED`) のまま。
4. `_precondition_merge()` は `pr_review_decision == "APPROVED"` の一致のみを満足条件とするため、`_handle_mismatch "PR #... reviewDecision is , not APPROVED (merge precondition not met)"` が実行のたびに必ず発火する。`--warn-only` のため進行自体は止まらないが、常時発火する警告はシグナルとして機能しない。

## Root Cause

`_precondition_merge()` (`scripts/reconcile-phase-state.sh:500-526`) は `reviewDecision == "APPROVED"` のみを満足条件とする。これは複数アカウントで運用するリポジトリ (別アカウントが実際にレビュー承認できる) では正しいが、wholework の自己ホスト運用では GitHub が self-review action を 422 で拒否するため `APPROVED` に構造的に到達できない。「review が本当に未完了」と「self-PR のため APPROVE できないだけ」を区別する代替シグナルが実装されていないことが根本原因。

同スクリプト内の `_completion_review()` (`scripts/reconcile-phase-state.sh:343-364`) は review フェーズの completion check で既に同種の問題 (GitHub のネイティブレビュー機構に依存しない完了判定) を `<!-- review-summary -->` marker 検出で解決済みだが、`_precondition_merge()` は導入時にこのパターンを踏襲しなかった。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_precondition_merge()` (L500-526) を変更し、`reviewDecision != APPROVED` かつ `!= CHANGES_REQUESTED` の場合に review-summary marker 検出 (`_completion_review()` と同じ検出範囲: PR comments + `gh api repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews`) を代替シグナルとして追加
- `modules/phase-state.md`: Phase Table (`ssot_for: phase-signatures`) の merge 行 (現行 L41: `PR is OPEN and reviewDecision is APPROVED`) を新しい判定ロジックに合わせて更新。Steering Docs sync candidate check (`scripts/reconcile-phase-state.sh` を変更対象に含む場合の grep 横断調査) で確認済み — `docs/structure.md` / `docs/workflow.md` / `docs/tech.md` / `README.md` は `reconcile-phase-state.sh` に汎用的な言及のみで `reviewDecision` の詳細記述はなく、更新不要と判断
- `tests/reconcile-phase-state.bats`: 既存の `merge precondition: PR OPEN but not APPROVED -> mismatch` テスト (L689-705) の直後に新判定を検証する bats テストを3件追加 (下記 Notes に入力データ形式を明記)

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` の `_precondition_merge()` (L500-526) を変更する。既存の `pr_state != OPEN` 早期リターン (L516-519) と `pr_review_decision == "APPROVED"` の満足分岐 (L521-522) はそのまま維持し、その後に以下を追加する:
   - `pr_review_decision == "CHANGES_REQUESTED"` の場合は無条件で `_handle_mismatch "PR #${PR_NUMBER} reviewDecision is CHANGES_REQUESTED (merge precondition not met)" "$actual_json"` を呼んで終了する (marker フォールバックの対象外)
   - それ以外 (空文字 / `REVIEW_REQUIRED` / その他) の場合は `_completion_review()` (L343-364) と同じ検出範囲で marker を調べる: `gh pr view "$PR_NUMBER" --json comments -q '.comments[].body'` と `gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews" -q '.[].body'` を結合し、既存の正規表現 `<!--[[:space:]]*review-summary[[:space:]]*-->|## Review Response Summary|## レビュー回答サマリ` に一致すれば `_emit_result "true" "PR #${PR_NUMBER} is OPEN and review-summary marker found (merge precondition met via marker fallback)" "$actual_json"`、一致しなければ `_handle_mismatch "PR #${PR_NUMBER} reviewDecision is ${pr_review_decision}, not APPROVED, and no review-summary marker found (merge precondition not met)" "$actual_json"` を呼ぶ
   (→ acceptance criteria AC1, AC2)
2. (after 1) `modules/phase-state.md` の Phase Table merge 行を、新しい OR 条件 (reviewDecision=APPROVED または review-summary marker、ただし CHANGES_REQUESTED は無条件 mismatch) を反映した記述に更新する (→ ドキュメント同期)
3. (parallel with 1, 2) `tests/reconcile-phase-state.bats` に新判定を検証する bats テストを3件追加する。入力データ形式は Notes を参照 (→ acceptance criteria AC3)
4. (after 1, 3) 追加・変更した bats テストをローカルで実行し全てパスすることを確認してからコミットする。CI (`.github/workflows/test.yml` の `Run bats tests` ジョブ) でのグリーンは AC4 で検証する (→ acceptance criteria AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/reconcile-phase-state.sh の merge precondition が、reviewDecision=APPROVED に加えて review-summary marker の存在を代替シグナルとして受け入れる。reviewDecision=CHANGES_REQUESTED は従来どおり mismatch のまま、どちらのシグナルも無い場合のみ mismatch を報告する" --> merge precondition が代替シグナルを受け入れ、CHANGES_REQUESTED は従来どおり mismatch のままになっている
- <!-- verify: grep "review-summary" "scripts/reconcile-phase-state.sh" --> `reconcile-phase-state.sh` が `review-summary` marker に言及している
- <!-- verify: rubric "merge precondition の新判定を検証する bats テストが追加されている。reviewDecision 空 + marker あり → 満足、reviewDecision 空 + marker なし → mismatch、reviewDecision=CHANGES_REQUESTED → mismatch (negative case) の 3 経路を検証している" --> 新判定の bats テストが 3 経路分追加されている
- <!-- verify: github_check "gh run view $(gh run list --workflow=test.yml --limit=1 --json databaseId --jq '.[0].databaseId') --json jobs --jq '.jobs[] | select(.name==\"Run bats tests\").conclusion'" "success" --> bats テストスイートが CI で pass する (patch route)

### Post-merge

- 自己 PR に対して `/auto` の pr route を実行し、merge precondition の警告が出ずに進行することを確認する

## Notes

### bats テスト入力データ形式 (3件追加分)

既存の `merge precondition: PR OPEN and APPROVED -> matches_expected true` (L671-687) と同じ `$MOCK_DIR/gh` モックパターン (`"$*"` を `--json state` / `--json reviewDecision` で分岐) に、`--json comments` と `gh api` (`$1 == "api"`) の分岐を追加する。参考: `review completion: marker only in PR Review body -> matches_expected true` (L376-392) の `case "$1" in pr) ...; api) ...; esac` パターン。

1. **`reviewDecision` 空 + marker あり (PR comments) → matches_expected true**: `--json state`→`OPEN`, `--json reviewDecision`→空文字, `--json comments`→`<!-- review-summary -->` を含む行, `api ...`→空
2. **`reviewDecision` 空 + marker なし → mismatch**: `--json state`→`OPEN`, `--json reviewDecision`→空文字, `--json comments`→marker を含まない行, `api ...`→空
3. **`reviewDecision=CHANGES_REQUESTED` → mismatch (negative case)**: `--json state`→`OPEN`, `--json reviewDecision`→`CHANGES_REQUESTED`, `--json comments`→marker を含む行 (marker があっても CHANGES_REQUESTED は無条件 mismatch になることを証明するため意図的に marker を含める), `api ...`→空

いずれも `run bash "$SCRIPT" merge 42 --pr 10 --check-precondition --strict` で実行し、1は `[ "$status" -eq 0 ]` + `matches_expected:true`、2・3は `[ "$status" -eq 1 ]` + `matches_expected:false` を検証する。

### 外部仕様確認 (External spec dependency check)

GitHub GraphQL API の `PullRequestReviewDecision` enum は `APPROVED` / `CHANGES_REQUESTED` / `REVIEW_REQUIRED` の3値 (加えて未リクエスト時は `null`/空文字)。既存 bats テストが `REVIEW_REQUIRED` を「not APPROVED の代表例」として使っている点、および本 Issue の Auto-Resolved Ambiguity Points が「`APPROVED` でも `CHANGES_REQUESTED` でもない状態は全て marker フォールバック対象」と解決している点と整合する。Source: GitHub GraphQL API Enums docs (`docs.github.com/en/graphql/reference/enums`)。

### Issue 本文の Auto-Resolved Ambiguity Points (issue phase で解決済み、再掲)

- `reviewDecision` の中間状態 (`REVIEW_REQUIRED` 等) の扱い: `APPROVED` でも `CHANGES_REQUESTED` でもない状態は全て marker フォールバック判定の対象とする
- review-summary marker の検出範囲: `_completion_review()` と同じ検出範囲 (PR comments + `gh api .../reviews`) を踏襲する

### Steering Docs sync candidate check

`scripts/reconcile-phase-state.sh` を対象に `grep -rn` で `docs/` `tests/` `scripts/` を横断調査した結果、直接の記述更新が必要なのは `modules/phase-state.md` の Phase Table (Changed Files に記載済み) のみ。`docs/structure.md` (L211) は `reconcile-phase-state.sh` を「general-purpose state reconciler for precondition and completion checks across all phases」と汎用的に説明するのみで `reviewDecision` の詳細には触れておらず、更新不要。`docs/workflow.md` / `docs/tech.md` / `README.md` も同様に `reviewDecision` 固有の記述なし。`docs/spec/issue-1069-*.md` 等の既存 Spec ファイルは本症状の発生記録 (disposable な履歴) であり対象外。

### 資格情報・セキュリティポリシー整合性チェック

本 Issue は credential/secret 管理や access control を変更するものではない (merge precondition の判定シグナルの追加のみ) ため、スキップ対象と判断した。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: issue phase の Auto-Resolve Log — `reviewDecision` 中間状態の扱いと review-summary marker 検出範囲の2点のambiguityを解決し、AC4 の verify command を patch route 形式 (`gh run view` 経由) に修正したことを記録。`_precondition_merge` (L500-526) と `_completion_review` (L343-364) の実コード内容を grep で事実確認済みと記載。 / URL: https://github.com/saitoco/wholework/issues/1106#issuecomment-5138236658

### code phase (cutoff: `2026-07-31T01:56:15Z`)

新規コメントなし。

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在 (code phase Step 3)**: Issue は既に `phase/code` ラベルが付与されており `phase/ready` が存在しなかった。`reconcile-phase-state.sh code-patch 1106 --check-precondition` も `matches_expected: false` (`issue #1106 does not have phase/ready label`) を返したが、Spec ファイル (`docs/spec/issue-1106-merge-precondition-selfhost.md`) 自体は存在し内容も完備しているため「Spec 欠落」には該当しない。`git log --grep=1106` / `gh pr list --search 1106` で確認した限り実装コミットも PR も存在せず、直前の `/code` 実行が Step 4 (ラベル遷移) 直後で中断し実装未着手のまま終了した状態と判断した。非対話モードの auto-resolve ポリシーに従い、既存 Spec を正として実装を続行する。

## Code Retrospective

### Deviations from Design

- Changed Files には `modules/phase-state.md` の Phase Table merge 行更新のみが明記されていたが、実装では既存の「Operate Route Completion Signature」「Stray PR Completion Signature」と同じ文書構成に合わせ、新規の `### Merge Precondition Marker Fallback` 説明セクションも追加した。Phase Table の行だけでは「なぜ marker フォールバックが必要か」という背景 (自己ホスト運用での 422 拒否) が読み取れず、他の SSoT セクションとの一貫性を優先した。AC (grep / rubric) はどちらも満たされており、追加セクションは補足情報のため AC の内容や verify command には影響しない。

### Design Gaps/Ambiguities

- Spec の Implementation Steps は「Step 8: 各ステップ完了後に commit」と「Step 11: `{prefix} <summary> (closes #N)` 形式の単一コミット」という2つの commit 規約を暗黙に前提としているが、本 Issue のように Implementation Steps が複数ステップ (scripts / modules / tests) に分かれ Step 8 の指示どおり都度コミットすると、Step 11 で新規に commit すべき差分が残らず `closes #N` 付与のタイミングを失う。今回は worktree ローカルの未push状態であることを確認した上で最終コミットを `git commit --amend` して `(closes #1106)` を追加し要件を満たしたが、SKILL.md 上はこのケース (Step 8 の粒度コミットと Step 11 の closes-commit 要件の衝突) が明文化されていない。将来的に Step 8 の粒度コミット規約と Step 11 の closes-commit 要件を明示的に整合させる余地がある。

### Rework

- N/A — 実装・テスト追加ともに手戻りなし。全73件 (`tests/reconcile-phase-state.bats` 単体) および全1322件 (`bats tests/` フルスイート、`modules/phase-state.md` が `tests/operate-route.bats` からも参照されているため behavioral change detection によりフル実行) がいずれも1回のテスト実行で PASS した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `_precondition_merge()` に `_completion_review()` と同一の marker 検出ロジック (PR comments + `gh api .../reviews`、同一正規表現) を導入し、コードの重複よりも既存パターンとの一貫性を優先した。
- `reviewDecision=CHANGES_REQUESTED` は marker の有無に関わらず無条件 mismatch とし、marker フォールバックの対象から明示的に除外した (未解決の指摘を merge 可能状態に見せない安全側の設計)。
- `modules/phase-state.md` に新規 `### Merge Precondition Marker Fallback` セクションを追加し、Phase Table の1行だけでは伝わらない背景 (自己ホスト運用での 422 拒否) を明文化した。

### Deferred Items
- Post-merge AC (「自己 PR に対して `/auto` の pr route を実行し、merge precondition の警告が出ずに進行することを確認する」, `verify-type: manual`) は本 PR のマージ後、実際の自己 PR 運用下で手動確認が必要。

### Notes for Next Phase
- Pre-merge AC 4件はすべて実装確認済み (rubric x2 / grep / github_check) だが、AC4 (`github_check ... test.yml ... "Run bats tests"`) は push 前時点での baseline CI run に対する確認であり、本コミット群に対する CI 実行結果ではない。push 後の CI (patch route の場合、`worktree-merge-push.sh` によるマージ後の origin/main 上の CI run) で改めて green を確認すること。
- Step 8 の粒度別コミット (3件) と Step 11 の closes-commit 要件が衝突したため、最終コミットを `git commit --amend` して `(closes #1106)` を追加した (未 push のローカル worktree 内でのみの操作、履歴共有前)。Code Retrospective の Design Gaps/Ambiguities に詳細を記録済み。

## Verify Retrospective

### Phase-by-Phase Review

#### issue / spec
- 「自己ホスト運用では GitHub が self-`APPROVE` を 422 で拒否するため `reviewDecision` が構造的に `APPROVED` に到達できない」という根本原因の特定が正確で、GraphQL の `PullRequestReviewDecision` enum を公式ドキュメントで裏付けている。
- 解法として、同一スクリプト内の `_completion_review()` が既に採用している `<!-- review-summary -->` marker 検出を流用する設計は、新機構を持ち込まず一貫性を保つ点で優れている。とくに **`CHANGES_REQUESTED` を従来どおり mismatch のまま維持**した点が重要で、「常時発火する警告を黙らせる」だけの緩和に陥らず、本物の却下は fail-closed のまま残している。

#### code
- Changed Files の想定 (Phase Table の行更新のみ) を超えて `### Merge Precondition Marker Fallback` 説明セクションを追加した判断は妥当。既存の「Operate Route Completion Signature」等と同じ文書構成に揃えており、AC への影響もない。
- テストは 3 経路 (marker あり→満足 / marker なし→mismatch / `CHANGES_REQUESTED`→無条件 mismatch) を追加し、既存の APPROVED / not-APPROVED と合わせて 5 経路を保護している。negative case を明示的に含めた点が良い。
- Rework なし。`tests/reconcile-phase-state.bats` 73 件、フルスイート 1322 件がいずれも 1 回で PASS。

#### verify
- pre-merge 4 件すべて PASS。AC4 は判定時点で CI が `in_progress` だったため **PENDING で打ち切らず完了まで待機**し、`Run bats tests` = `success` を確認して確定させた。これは Phase Handoff が明示的に要請していた「push 後の CI で改めて green を確認すること」に対応する。
- post-merge の manual 1 件 (自己 PR での pr route 実走) は Claude では実行不能。`phase/verify` 留置。

### Improvement Proposals

- **`/code` Step 8 の粒度別コミット規約と Step 11 の closes-commit 要件が衝突し、`git commit --amend` での回避が必要になる**: `skills/code/SKILL.md` は Step 8 で「各 Implementation Step 完了後にコミットする」ことを求め、Step 11 で「`{prefix} <summary> (closes #N)` 形式のコミット」を求めている。本 Issue のように Implementation Steps が複数 (scripts / modules / tests) に分かれ、Step 8 の指示どおり都度コミットすると、**Step 11 の時点で新規にコミットすべき差分が残らず `closes #N` を付与するタイミングを失う**。
  - 本実行では worktree ローカルの未 push 状態であることを確認したうえで最終コミットを `git commit --amend` して `(closes #1106)` を追加し要件を満たした。履歴共有前の操作であり安全だが、**SKILL.md にはこのケースの扱いが明文化されていない**ため、実行者ごとに回避方法が分かれうる (amend / 空コミット / 最後のステップだけコミットを遅延、など)。
  - `closes #N` は `reconcile-phase-state.sh` の `code-patch` completion check が完了判定に使う一級のシグナルであるため、付与に失敗すると silent no-op と誤判定される。回避方法が非決定的なのはリスクがある。
  - **対応方針 (案)**: (a) Step 11 に「Step 8 の粒度コミットにより新規差分が無い場合は、最終コミットを `--amend` して `closes #N` を付与する (push 前に限る)」と明記する。(b) Step 8 の規約を「最終ステップのコミットは Step 11 に委ねる」と変更し、衝突自体を作らない。(c) `closes #N` をコミットメッセージではなく Issue コメントの marker で表現し、コミット粒度から独立させる。(a) が最小変更、(b) が構造的。

### 観察

- **#1097 の修正効果が確認できた**: 本 Issue の code フェーズは 1 回目 (#1097 merge 前) に「フルテストスイートの完了を待っています」でターンを終了して silent no-op で失敗し、2 回目 (#1097 merge 後) は同一 Issue・同一 patch route・テスト実行を伴う実装という条件で **silent no-op ゼロ**で完走した (`grep -c "silent no-op"` = 0)。
  - ただし 1 回目の失敗には並行セッションの dirty tree による auto-retry 中断も重なっており、変数は完全には統制されていない。それでも「background 実行 → 通知待ちでターン終了」という症状そのものが消えた点は #1097 の直接的な効果と見てよい。
  - ドキュメント注記 (`modules/test-runner.md` への一般原則追加) が headless セッションの実際の挙動を変えた事例として記録に値する。
- 本 Issue の修正により、本セッションの merge 4 件すべて (#1066 / #1053 / #1050 / #1115) で観測していた `reviewDecision is , not APPROVED` の常時発火警告が解消される見込み。
