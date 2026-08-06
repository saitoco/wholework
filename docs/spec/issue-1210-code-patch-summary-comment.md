# Issue #1210: code: patch route の実装完了時に Issue へサマリコメントを投稿

## Overview

patch route の `/code` は現状、`closes #N` コミット以外に Issue タイムライン上へ進捗の痕跡を残さない (pr route は PR の cross-reference、operate route は `## Execution Log`/`## Execution Plan` コメントで進捗を追える一方、patch route だけが空白になる)。`### Step 14: Worktree Exit` の patch route ブロックに、push 完了後・`gh-label-transition.sh $NUMBER verify` 呼び出しの**前**に `## Implementation Complete` サマリコメントを投稿する手順を追加する。投稿位置を label transition の前にするのは、`modules/l0-surfaces.md` の Comment Consumption Procedure が cutoff を「直近の `phase/*` label 付与時刻」に取るため — 後に投稿すると後続の `/verify` (再実行を含む毎回) が first-class input として consume してしまう。あわせて、pr route の `**Change tracking comment (post-PR):**` が patch route では出力されないギャップを、新コメントの `### Change Tracking` サブセクションで埋める。

対象は patch route のみ。pr route (PR イベントで進捗を追える) と operate route (既存の Execution Log/Execution Plan が要約を兼ねる) は対象外で変更しない。

## Changed Files

- `skills/code/SKILL.md`: `### Step 14: Worktree Exit` の patch route ブロック (`**patch route (XS/S common)**:` 段落) に、`gh-label-transition.sh $NUMBER verify` 呼び出しの直前へ `## Implementation Complete` コメント投稿のサブブロックを追加
- `docs/workflow.md`: `` ### 3. `/code` `` セクションに、patch route が `## Implementation Complete` コメントを投稿する旨の説明を追加

**Steering Docs sync candidate check (実施済み、追加候補なし)**: `skills/code/SKILL.md` を変更対象に含むため `grep -rn` で `docs/`, `tests/`, `scripts/` を横断確認した。`docs/guide/workflow.md` / `README.md` / `CLAUDE.md` はいずれも他フェーズ (`/spec` の `Design Complete`、`/verify` の `Acceptance Test Results` 等) についても per-phase の Issue コメント内容を記載しておらず、本 Issue のためだけに詳細度を上げる整合性要求はない — 対象外と判断。`tests/gh-issue-comment.bats` 等の既存テストは `gh-issue-comment.sh` 自体の変更を伴わないため対象外。

## Implementation Steps

1. `skills/code/SKILL.md` の `### Step 14: Worktree Exit` を、以下のとおり書き換える (→ acceptance criteria 1, 2, 3, 4, 5, 7)。

   **置き換え対象** (`**patch route (XS/S common)**:` から `patch route completes here. Follow the completion report section to inform the user.` まで、直前の位置コンテキストは `**patch route (merge-to-main pattern):**` 段落の直後):

   置き換え後の内容:

   ```markdown
   **patch route (XS/S common)**: After push completes, post an `## Implementation Complete` summary comment to the Issue, then transition to `phase/verify`.

   **Implementation Complete comment (patch route, before label transition):**

   Post this before running `gh-label-transition.sh $NUMBER verify` below, not after — the ordering is required, not incidental. `modules/l0-surfaces.md`'s Comment Consumption Procedure resolves each phase's cutoff to the most recent `phase/*` label assignment; `scripts/gh-issue-comment.sh` posts via `gh issue comment` under the executor's own token, so the comment's `authorAssociation` (`MEMBER` or similar) does not qualify for the bot-skip exception in the Trust Boundary table, and the comment is injected as first-class prompt-equivalent input by whichever phase consumes it next. Posting after the `verify` label transition would place this comment's `createdAt` after `/verify`'s own cutoff, so every `/verify` run on this Issue — including re-verify passes in a fix cycle — would re-consume it as new context, even though it only summarizes what the Spec's Code Retrospective and Phase Handoff already record. Posting before the transition keeps the comment older than `/verify`'s cutoff, matching the same before-transition ordering `/spec` already uses (Step 15 Issue comment → Step 16 label transition).

   Write the comment body to `.tmp/implementation-complete-$NUMBER.md` with the Write tool, then post:

   \`\`\`bash
   mkdir -p .tmp
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/implementation-complete-$NUMBER.md
   rm -f .tmp/implementation-complete-$NUMBER.md
   \`\`\`

   Comment template:

   \`\`\`markdown
   ## Implementation Complete

   **Route**: patch (direct commit to main)
   **Commit**: `{sha}` {commit subject}

   ### Changes
   - `{path}` — {change summary}

   ### Tests
   - {test command} — {result}

   ### Change Tracking
   - {only when Step 10's verify command rewrite or Spec sync occurred during this run — omit the whole subsection when neither occurred}

   Spec: [{spec filename}]({blob URL})
   Next: `phase/verify`
   \`\`\`

   \`\`\`bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER verify
   \`\`\`

   patch route completes here. Follow the completion report section to inform the user.
   ```

   実装メモ:
   - `{sha}` / `{commit subject}` は Step 11 の patch route コミット (`git log -1 --format=...`) から取得
   - `### Changes` は `git show --stat` 等から変更ファイル一覧を要約
   - `### Tests` は Step 9 (該当があれば) やスキル固有のテスト実行結果を記載
   - `### Change Tracking` のトリガーは Step 10 由来の 2 件 (`verify command was rewritten` / `Spec sync`) のみ — 既存の pr route ブロックにある 3 件目 (`Step 11 auto-append: acceptance conditions were appended to the Issue body`) は `**For pr route (branch + PR)**:` 内の `**Auto-append acceptance conditions to Issue:**` に限定された PR 作成時トリガーであり、patch route では構造上発生しないため含めない
   - `{blob URL}` は既存の Step 15 (Issue Comment) 等と同じ GitHub blob URL 形式 (`https://github.com/{REPO}/blob/main/$SPEC_PATH/issue-$NUMBER-short-title.md`)

2. `docs/workflow.md` の `` ### 3. `/code` — Implementation `` セクション、Size ベースルーティングを説明する段落 (`Implements the design from the Spec. Size-based routing: ...`) の直後に、以下の段落を追加する (→ acceptance criteria 6)。

   ```markdown
   On completion, patch route posts an `## Implementation Complete` summary comment to the Issue (changed files, tests, commit, Spec link) before transitioning to `phase/verify` — this is patch route's only progress signal on the Issue timeline, since it creates no PR. pr route relies on the PR's own cross-reference instead, and operate route already posts an `## Execution Log` (or `## Execution Plan` under `autonomy: L1`) comment, so neither route adds this comment.
   ```

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/code/SKILL.md" "Step 14: Worktree Exit" "Implementation Complete" --> `skills/code/SKILL.md` の `### Step 14: Worktree Exit` 内 patch route ブロックに、Issue へ `## Implementation Complete` コメントを投稿する手順が追加されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 14: Worktree Exit" "gh-issue-comment.sh" --> 同ブロックの投稿手順が `scripts/gh-issue-comment.sh` を使う形で記述されている
- <!-- verify: rubric "skills/code/SKILL.md の Step 14 patch route ブロックにおいて、Issue コメント投稿の手順が gh-label-transition.sh の呼び出しより前に記述されており、label transition の後に投稿すると Comment Consumption Procedure の cutoff より新しくなり後続 /verify に consume される、という理由が明記されている" --> 投稿手順が `gh-label-transition.sh` 呼び出しより前に置かれ、その理由が明記されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 14: Worktree Exit" "Comment Consumption" --> 同ブロックに Comment Consumption Procedure の cutoff との関係が記載されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 14: Worktree Exit" "Change Tracking" --> コメントテンプレートに `### Change Tracking` サブセクション (patch route で change tracking が発生した場合のみ出力) が含まれている
- <!-- verify: section_contains "docs/workflow.md" "3. `/code`" "Implementation Complete" --> `docs/workflow.md` の `/code` 節に patch route の Issue コメント投稿が記載されている
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の全 job が PASS する (SKILL.md 編集による構文検証・Forbidden Expressions 違反の検出。patch route のため `gh run list` 形式)

### Post-merge

- 次に patch route で `/code` が実行された Issue に `## Implementation Complete` コメントが投稿され、その `createdAt` が同 Issue の `phase/verify` label 付与時刻より前である <!-- verify-type: observation event=auto-run session=next -->

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — 投稿位置 (label transition 前)・Step 14 サブブロック配置 (Step 番号非繰り下げ)・`wholework-event` マーカー不要・bats テストを AC に含めない、の 4 点の自動解決根拠と、pr/operate route 対象外化・常時 PASS な verify command 3 件削除などの方針判断を記録 / https://github.com/saitoco/wholework/issues/1210#issuecomment-5205161524

## Notes

- **Verification 件数について**: light depth の目安 (pre-merge 5 件以内) を pre-merge 7 件で超過している。Issue body の `## Acceptance Criteria > Pre-merge` (7 件) は `/issue --non-interactive` の自動解決で既に精査済み (常時 PASS になる 3 件の回帰ガードを削除した結果が 7 件) であり、「Verify command sync rule」により Spec は Issue body を verbatim で転記する — `/issue` (What) が確定した受入条件を `/spec` (How) 側で独自に間引かない、という責務境界 (`docs/product.md` § `/issue` vs `/spec` Responsibility Boundary) を優先した
- **tests/code.bats は Changed Files に含めない**: `/issue` retrospective の判断を踏襲。同ファイルは SKILL.md の構造テストであり、本 Issue の pre-merge AC は `section_contains` で同等の構造検証を行っているため、bats アサーション追加は二重化になる
- **依存関係 (#1208)**: `modules/l0-surfaces.md` の Comment Consumption Procedure は既に `skills/code/SKILL.md` の Worktree Entry (Step 2, `PHASE_NAME=code`, cutoff は直近の `phase/ready` label 付与時刻) に組み込み済みであることを確認した (#1208 実装済み)。本 Issue の「投稿位置は label transition の前」という設計判断は、この既存の cutoff 機構に対して有効
- **Change Tracking トリガーの絞り込み**: コメントテンプレートのトリガーを Issue body の 3 条件 (Step 10 書き換え / Spec sync / AC 追記) から 2 条件に絞った。AC 追記の実体である「Auto-append acceptance conditions to Issue」は `**For pr route (branch + PR)**:` ブロック内限定で PR 作成イベントに紐づくため、patch route では構造上発火しない。Issue body の記述は pr route の既存文言をそのまま踏襲した一般化表現と判断し、Spec (How) の精度としてより正確な 2 条件に修正した。AC の `section_contains "Change Tracking"` は文字列存在のみを見るため、この絞り込みは AC 判定に影響しない

## Code Retrospective

### Deviations from Design
- N/A — Spec Implementation Steps 1・2 の置き換え後テキストをそのまま適用した。バッククォート 3 連のエスケープ (`\`\`\``) は Spec 内側のフェンスに包まれていたための表記であり、実ファイルへの反映時は通常のフェンスに戻すだけで内容の変更はなかった

### Design Gaps/Ambiguities
- **Pre-merge AC の `github_check` と Step 10/Step 11 の実行順序**: Issue AC #7 (`github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) ..."`) は「その時点の HEAD に対する CI 結果」を見る verify command だが、`skills/code/SKILL.md` の Step 10 (verify command consistency check) は Step 11 (commit) より前に実行される。patch route では Step 11 の実装コミットがまだ存在しない時点で Step 10 を評価すると、無関係な直前コミットの CI 結果を参照してしまい、意図した検証にならない。今回は Step 10 の同ステップ内で他 6 件のローカル `section_contains`/`rubric` を先に確認・PASS させ、`github_check` 1 件のみ Step 11 のコミット・push 完了後に個別に再実行する運用で対処した。SKILL.md 自体にはこの時間的依存関係の扱いが明記されていない — 同種の commit-scoped `github_check` AC を持つ他の patch route Issue でも同じ判断が必要になるため、`modules/verify-executor.md` か `skills/code/SKILL.md` Step 10 に一般化した注記を追加する余地がある (今回は Spec 変更範囲外のため見送り)

### Rework
- N/A — 手戻りなし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps 1・2 の置き換えテキストを逐語適用し、独自の言い回し変更は行わなかった (`### Change Tracking` トリガー絞り込みなど How レベルの判断は Spec 段階で既に確定済みのため)
- `docs/ja/workflow.md` の対応段落を同時に翻訳・追記し、`docs/translation-workflow.md` の同期義務を本コミット内で満たした (コードフェンス数を英日で一致確認済み)
- Pre-merge AC 7 件のうち 6 件 (ローカル `section_contains`/`rubric`) は commit 前に PASS 確認済み。`github_check` (AC #7) のみ commit-scoped のため commit・push 完了後に個別実行する運用とした

### Deferred Items
- なし

### Notes for Next Phase
- 本 Issue は `/code` patch route 自身に `## Implementation Complete` コメント投稿を追加する変更である。本セッション自体は着手時点でロードされた旧 `skills/code/SKILL.md` に従って実行しているため、このコミット自体は新しい Implementation Complete コメントを投稿しない (機能が有効化されるのは次回以降の patch route 実行から)。`/verify` は Post-merge AC (「次に patch route で `/code` が実行された Issue に `## Implementation Complete` コメントが投稿され...」`verify-type: observation event=auto-run session=next`) で次回実行を待つ形になる
- Pre-merge AC #7 (`github_check`) は commit・push 後に別途確認し、PASS 後に Issue チェックボックスを更新する (Code Retrospective の Design Gaps/Ambiguities 参照)

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue --non-interactive` が「常時 PASS になる verify command 3 件」を削除した判断は妥当だった。残った 7 件はいずれも実際に実装差分を判別しており、空振りした AC はゼロ

#### spec
- Spec の Implementation Steps が置き換え後テキストを逐語で持っていたため、code フェーズの Deviations が N/A で着地した。SKILL.md のような散文ファイルへの変更では、この「置き換え対象 + 置き換え後の全文」形式が手戻りを構造的に防いでいる
- light depth の目安 (pre-merge 5 件以内) を 7 件で超過したが、これは `/issue` (What) が確定した AC を `/spec` (How) で間引かないという責務境界を優先した結果であり、Notes に理由が明記されていた。目安違反を「逸脱」ではなく「意識的な優先順位判断」として記録できている

#### code
- Code Retrospective の Design Gaps/Ambiguities が指摘した **commit-scoped `github_check` AC と Step 10/Step 11 の実行順序**は、verify 側でも同じ形で再現した。`$(git rev-parse HEAD)` は評価時点の HEAD を指すため、code フェーズ (Step 10、commit 前) では直前の無関係コミット、verify フェーズでは retrospective コミット (`599fb8a4`) を参照する — いずれも AC が意図した「実装コミット (`6a08557c`) の CI 結果」とは一致しない。今回 PASS したのは、このリポジトリの `test.yml` が `docs/spec/` のみの変更コミットでも起動し success を返すためで、AC の文言が正しかったからではない
- この論点は #1212 (`verify-classifier: patch route の CI 検証 AC の run 参照形を是正し推奨形を SSoT に一本化`) のスコープと重なる。本 Issue 単体では追加対応せず、#1212 側で推奨形を確定させるのが妥当

#### review
- patch route のため `/review` なし。pre-merge AC 7 件のうち 6 件がローカル `section_contains`/`rubric` で、review 相当の構造検証を AC 自身が担った

#### merge
- 特記事項なし (patch route、`worktree-merge-push.sh` の rebase fallback が spec フェーズで 1 回自動発火したが Auto Retrospective 記録対象外の正常系)

#### verify
- **AC 8 (observation `session=next`) は本 Issue では構造的に発火しない**。本 Issue 自身が `/code` patch route に `## Implementation Complete` 投稿を追加する self-hosting 変更であり、code フェーズは変更前の SKILL.md をロードして実行された。Phase Handoff § Notes for Next Phase がこの制約を先回りして記録しており、verify 側は SKIPPED 判定 (Step 8c の未発火パス) で素直に着地できた
- **`.tmp/auto-session-current` の session_id 汚染**: verify 開始時の `restore_auto_session_pointer` が、並行実行中の別 `/auto` セッション (`56317-1786026050`、single mode) が上書きした `auto-session-current` を読み、本 verify の `phase_start` イベントが誤った `session_id` で記録された。バッチ本体の `session_id` は `33233-1786023637`。これは #1075 (session_id 双方向誤帰属) の実例で、in-session `Skill()` 経由の `/verify` は PGID pointer を持たないため `auto-session-current` にしかフォールバックできず、並行セッション下では構造的に誤帰属する

### Improvement Proposals
- commit-scoped `github_check` AC (`--commit=$(git rev-parse HEAD)` 形) の評価タイミング依存を、`modules/verify-executor.md` か `skills/code/SKILL.md` Step 10 に注記する — ただし #1212 のスコープと重なるため、本 Issue からの独立起票は行わず #1212 側で扱う
- `.tmp/auto-session-current` の並行セッション上書き問題 — 既存 #1075 の実例として追記済み。新規起票は不要

