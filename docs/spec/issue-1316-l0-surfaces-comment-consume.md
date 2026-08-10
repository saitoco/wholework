# Issue #1316: l0-surfaces: 各フェーズ冒頭でのコメント consume を必須化しパイプライン前後の欠落窓を解消

## Autonomous Auto-Resolve Log

### Code Phase

- **Step 3 `phase/ready` ラベルチェック: ラベル不在 (`phase/code` に遷移済み) だが Spec 存在のため続行** — reason: `gh issue view 1316 --json labels` で確認すると `phase/ready` は既に `phase/code` へ遷移済みで、`reconcile-phase-state.sh code-pr 1316 --check-precondition` も `matches_expected: false` (診断: `phase/ready` ラベル不在) を返した。ただし Spec (`docs/spec/issue-1316-l0-surfaces-comment-consume.md`) は既に完全な形で存在し、Implementation Steps・Verification まで記載済みであるため、Spec 不在を前提とした「Issue 本文から要件を読み取る」フォールバックは不要と判断し、既存 Spec に基づいて実装を続行した。
  - Other candidates: 中断して `/spec 1316` の再実行を促す — 却下。Spec は既に spec phase の内容を満たしており、再実行は不要な手戻りになる。

## Overview

`modules/l0-surfaces.md` の Comment Consumption Procedure は `/spec`・`/code`・`/verify` の 3 フェーズでしか呼ばれておらず、`/issue`・`/review`・`/merge` は Issue コメントを構造的に consume しない。結果として (1) Issue がパイプラインに入る前に投稿されたコメント (欠落窓 1 — #1251 で実測: 3 件の提案が `phase/done` まで一度も読まれなかった) と、(2) review/merge 期間中に投稿された通常コメント (欠落窓 2) が失われる。

本 Issue は Issue 本文が提示した対応方針案のうち **案 A (全 6 フェーズで consume を必須化)** を採用し、`/issue`・`/review`・`/merge` それぞれに Comment Consumption Procedure の呼び出しを追加する。案 B (read watermark) と案 C (marker 例外の拡大) は不採用とする理由を Alternatives Considered に記録する。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (トリアージ結果・曖昧性自動解決ログ・スコープ評価、sub-issue 分割は non-interactive のため未実施と明記) / https://github.com/saitoco/wholework/issues/1316#issuecomment-5235007944
- No new comments since last phase.

## Changed Files

- `modules/l0-surfaces.md`: Comment Consumption Procedure に `/issue` の欠落窓 1 責任を明記し、Bash wrapper fallback § Primary/Secondary の記述を `/review`・`/merge` を含む形に拡張
- `skills/issue/SKILL.md`: Existing Issue Refinement の Step 1 (生の `gh issue view --json comments` を正式な Comment Consumption Procedure 呼び出しに置換) と Step 13 (Consumed Comments 記録先の追加、skip condition 拡張)
- `skills/review/SKILL.md`: Step 2 (Worktree Entry) 末尾に Comment Consumption Procedure + bash fallback 呼び出しを追加。`allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` を追加
- `skills/merge/SKILL.md`: Step 4 (Execute Squash Merge) の既存 "Phase Handoff write" サブセクション内に Comment Consumption Procedure + bash fallback 呼び出しを追加。`allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` を追加
- `tests/append-consumed-comments-section.bats`: 欠落窓 1 (`phase/*` ラベル皆無 → cutoff 空) と欠落窓 2 (ラベル間に投稿されたコメント) を検証する `@test` を各 1 件追加

## Implementation Steps

1. **`modules/l0-surfaces.md` を更新する** (→ 受入条件 AC4)
   - Comment Consumption Procedure の説明 (Step 1 の直前、または Purpose 直後) に、`/issue` の Existing Issue Refinement フローがパイプライン開始前コメント (欠落窓 1) の consume 責任を持つことを明記する。理由: `/issue` 実行時点ではまだ `phase/*` ラベルが一切付与されていないため、Step 1 の cutoff 解決は Fallback B (cutoff 空 → 全コメント consume) に自然に到達する。
   - "Bash wrapper fallback" § Primary の箇条書きに `/review`(Step 2 末尾、`--no-push` なし)・`/merge`(Step 4 の既存 Phase Handoff write サブセクション内、`--no-push` あり) を追加する。それぞれの push 挙動の違い (Implementation Step 3・4 参照) を一文で要約する。
   - "Secondary (bash wrapper post-processor, non-pr routes only)" の箇条書きに、`/review`・`/merge` は対象外である旨を明記する — 両フェーズの Spec は常に PR ブランチ上にあり、`/code` pr route が Secondary 層から除外されているのと同じ理由 (post-exit のメインリポジトリ CWD からは到達・書き込み不能) による。

2. **`skills/issue/SKILL.md` の Existing Issue Refinement フローを更新する** (→ AC3, AC5, AC6, Post-merge observation AC) (1 と並行可)
   - **Step 1** (`### Step 1: Fetch Issue Information`, 現在 `gh issue view $NUMBER --json comments` を実行後 "Use attachment content and all comments as context for subsequent steps" としている箇所): 生の `gh issue view $NUMBER --json comments` 呼び出しを、`${CLAUDE_PLUGIN_ROOT}/modules/l0-surfaces.md` の "Comment Consumption Procedure" 呼び出し (`ISSUE_NUMBER=$NUMBER`, `COMMENT_SCOPE=issue`, `PHASE_NAME=issue`) に置き換える。この呼び出しは **Step 3 の `gh-label-transition.sh $NUMBER issue` より前に位置しなければならない** ことを明記する — ラベル付与後だと cutoff が `phase/issue` 自身の付与時刻に解決され、直前のコメントを取りこぼす (`skills/code/SKILL.md` の `phase/verify` 遷移前後の既存の記述と同じ理由付けを踏襲する)。
   - 初回 consume の**件数上限・要約は設けない**方針をこの箇所に明記し、理由 (置き換え対象の既存実装も無制限フェッチだった、他フェーズもすべて無制限、コメント量は 1M context に対し無視できるほど小さい) を一文で記載する (AC5)。
   - **Step 13** (`### Step 13: Issue Retrospective`): skip condition に 4 番目の箇条書き「Step 1 の Comment Consumption Procedure で consume したコメントが 0 件であること」を追加する。「NOT skipping」時の投稿内容に `### Consumed Comments` サブセクション (エントリ形式は l0-surfaces.md Step 5 と同じ `login / authorAssociation / trust tier / summary / URL`。0 件時は "No new comments since last phase.") を追加する。これが `/issue` の Consumed Comments 記録先である — この時点では Spec が存在しないため (AC6)。

3. **`skills/review/SKILL.md` の Step 2 (Worktree Entry) を更新する** (→ AC1) (1, 2, 4 と並行可)
   - Step 2 の末尾 (`headRefName` へのチェックアウト後、Step 3 の前) に Comment Consumption Procedure 呼び出しを追加する: `ISSUE_NUMBER=$ISSUE_NUMBER`, `COMMENT_SCOPE=issue+pr` (この時点で PR は必ず存在するため — `/code` が resume 時に `issue`→`issue+pr` へ昇格させる既存条件と同じ判断根拠), `PHASE_NAME=review`。Step 3 の Size 分岐 (XS/S early exit を含む) より前に、無条件で実行する — `/verify` の Worktree Entry が Size に関わらず必須である既存の前例と同じ扱い。
   - 続けて `bash ${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh "$ISSUE_NUMBER" review` を実行する (deterministic fallback)。**`--no-push` を付けない**: Step 3 の XS/S early exit 分岐は `## Retrospective` の無条件 push (`git push origin HEAD`) に到達する前にスキルを終了させ得るため、`--no-push` に頼ると commit がローカルの worktree ブランチに取り残されるリスクがある。この時点では PR のマージ可否判定はまだ行われていない (`/merge` の Step 1 相当の処理がない) ため、即時 push しても CI 再トリガー以外のリスクはない。
   - `skills/review/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` を追加する。

4. **`skills/merge/SKILL.md` の Step 4 (Execute Squash Merge) を更新する** (→ AC2) (1, 2, 3 と並行可)
   - 既存の「Phase Handoff write」サブセクション内、サブステップ 1 (`git fetch origin && git merge origin/main --ff-only`) の直後・サブステップ 2 (Spec の Glob) より前に、Comment Consumption Procedure 呼び出しを挿入する: `ISSUE_NUMBER`, `COMMENT_SCOPE=issue`, `PHASE_NAME=merge`。続けて `bash ${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh "$ISSUE_NUMBER" merge --no-push` を実行する。`--no-push` はサブステップ 4 の既存 `git push origin HEAD:main` にこの commit も相乗りさせるためで、Phase Handoff の commit と合わせて 1 回の push で main に届く。
   - **post-squash に配置する理由を明記する** (この Step 冒頭の `gh pr merge --squash --delete-branch` より後、Step 5 の `phase/verify` 遷移より前): 他フェーズのような「Step 1-2 相当の早い段階」に置くと、(a) squash-merge が PR ブランチを削除するため push しない commit は消失する、(b) 明示的に early push すると Step 1 で確認済みの mergeability 判定が CI 再トリガーにより無効化されるリスクがある。post-squash・`main` 直 push はこの両方を回避しつつ、Step 5 より前という順序制約 (他フェーズと同じ「ラベル遷移前」原則) を満たす。この時点での最新 `phase/*` ラベルは `phase/review` である (`/merge` 自身の `phase/verify` 遷移は Step 5 でまだ未実行)。
   - `skills/merge/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` を追加する。

5. **`tests/append-consumed-comments-section.bats` に bats テストを 2 件追加する** (→ AC7, AC8) (1〜4 と並行可)
   - **AC7 用**: `gh api ... timeline` のモックを空文字列 (`phase/*` ラベル皆無) にし、`gh issue view --json comments` のモックに 1 件以上の既存コメントを設定、スクリプトを (例) `PHASE_NAME=issue` で実行し、新規作成される `## Consumed Comments` セクションにそのコメントのエントリが含まれることを assert する。
   - **AC8 用**: `gh api ... timeline` のモックに 1 件のラベル付与イベント (非空タイムスタンプ `T1`) を設定し、`gh issue view --json comments` のモックに `createdAt > T1` のコメントと `createdAt <= T1` のコメントを両方含める。スクリプトを `PHASE_NAME=merge` (または `review`) で実行し、前者のみがエントリとして出力され後者は出力されないことを assert する。
   - いずれも `append-consumed-comments-section.sh` 自体のカットオフ解決ロジックは変更しない (既存実装で正しく動作する) ため、このステップは新しい呼び出し元 (Step 2〜4) が依存する既存メカニズムの回帰防止テストという位置づけである。

## Alternatives Considered

**案 A (採用) — 全 6 フェーズで Comment Consumption Procedure の呼び出しを必須化する**: `/issue`・`/review`・`/merge` それぞれに、既存の `l0-surfaces.md` Comment Consumption Procedure への呼び出しを追加する (各フェーズ自身のラベル遷移より前に位置するよう配置)。`/spec`・`/code`・`/verify` で既に実証済みのパターンを踏襲する、最小かつ低リスクな変更。本 Issue の Pre-merge AC はすべてこの案の具体的な挙動に対して書かれている。

**案 B (見送り) — read watermark の導入**: ラベル付与時刻からの推論をやめ、最後に consume したコメントの timestamp/URL を明示的に記録する方式。Issue 本文が「構造的により正しい」と位置づける通り、欠落窓 1・2 を原理的に排除できる。本 Issue では採用しない — 全 6 フェーズ (既に正しく動作している `/spec`・`/code`・`/verify` を含む) の cutoff 解決メカニズムそのものを再設計する必要があり、本 Issue の Acceptance Criteria が要求する範囲 (案 A の呼び出し有無・順序・記録先) を大きく超える規模とリグレッションリスクを伴う。案 A のフェーズラベル境界単位のカバレッジで実運用上不十分と判明した場合の自然な follow-up として位置づける。

**案 C (不採用) — cross-phase marker exception の対象拡大**: 既存の `verify-fail`/`preview-ac-unverified` マーカー救済の対象を通常コメントにも広げる案。Issue 本文自身が指摘する通り、「何を救済対象とするか」の場当たり的な判定基準が必要になり cutoff の意味を曖昧にする。案 A の方が原則的な解決になっている。

## Verification

### Pre-merge

- <!-- verify: grep "Comment Consumption Procedure" "skills/review/SKILL.md" --> `/review` が冒頭で Comment Consumption Procedure を呼ぶ手順になっている
- <!-- verify: grep "Comment Consumption Procedure" "skills/merge/SKILL.md" --> `/merge` が冒頭で Comment Consumption Procedure を呼ぶ手順になっている
- <!-- verify: rubric "skills/issue/SKILL.md に Comment Consumption Procedure の呼び出しステップが追加されており、そのステップが phase/issue ラベル付与ステップより前に配置されていること、およびその順序が必須である理由 (付与後だと cutoff が自身のラベル時刻に解決され直前のコメントを取りこぼす) が記述されている" --> `/issue` が Comment Consumption Procedure を呼ぶ手順になっており、その呼び出しが `phase/issue` ラベル付与より前に位置することが手順上明示されている
- <!-- verify: rubric "l0-surfaces.md の Comment Consumption Procedure に、Issue がパイプラインに入る前に投稿されたコメントの consume 責任がどのフェーズにあるかが明記されている" --> `modules/l0-surfaces.md` に、パイプライン開始前のコメントがどのフェーズで consume されるかが明記されている
- <!-- verify: rubric "長期間バックログにあった Issue で全コメントが consume 対象になる場合の扱い (件数上限 / 要約 / 制限なし) と選択理由が Spec に記載されている" --> `/issue` の初回 consume における件数上限または要約方針が決定され、その理由が Spec に記録されている
- <!-- verify: rubric "各フェーズの Consumed Comments 記録先が決定されており、/issue 実行時点で Spec が存在しない場合の記録先または記録省略の判断が記述されている" --> `/issue` / `/review` / `/merge` の Consumed Comments 記録先が決定され、Spec 不在時 (`/issue`) の扱いが記述されている
- <!-- verify: rubric "phase/* ラベルが 1 つも存在しない状態のフィクスチャで、cutoff が空に解決され既存コメントが consume 対象になることを検証する bats テストが追加されている" --> パイプライン開始前に投稿されたコメントが consume されることを検証する bats テストが追加されている
- <!-- verify: rubric "phase/ready と phase/verify の間の createdAt を持つマーカー無しコメントが、いずれかのフェーズの consume 対象になることを検証する bats テストが追加されている" --> review / merge 期間に投稿された通常コメント (マーカーを含まない) が consume されることを検証する bats テストが追加されている

### Post-merge

- <!-- verify-type: observation event=auto-run session=next --> 次に `/auto` へ入る Issue に対しパイプライン開始前にコメントを投稿し、`/issue` または `/spec` の Consumed Comments に記録されることを観察する

## Tool Dependencies

### Bash Command Patterns
- `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` — `skills/review/SKILL.md` と `skills/merge/SKILL.md` に新規call site追加 (`/spec`/`/code`/`/verify` の `allowed-tools` には既存)

### Built-in Tools
none (追加なし)

### MCP Tools
none

## Uncertainty

- **Step 13 の retrospective が「Consumed Comments のみ」で投稿されるケース**: `/issue` Step 13 の skip condition に 4 番目の条件を追加したことで、他の判断材料 (曖昧性解決・AC変更・ポリシー決定) が一切なくても Consumed Comments が 1 件でもあれば retrospective コメントが投稿されるようになる。これが有用なシグナルとして機能するか、あるいは実質ノイズになるかは実運用で確認が必要。
  - **検証方法**: 本 Issue の Post-merge observation AC が最初の実例を兼ねる (次に `/auto` に入る Issue でパイプライン開始前コメントを投稿し、実際の投稿内容を確認する) — 別途の検証手段は不要
  - **影響範囲**: Implementation Step 2 (`skills/issue/SKILL.md` Step 13)

## Notes

### Auto-Resolved Ambiguity Points (spec phase)

- **案 A のみを採用 (案 B・C は不採用)** — 理由は Alternatives Considered を参照。本 Issue の Pre-merge AC はすべて案 A の具体的挙動に対して書かれており、案 B は現状正しく動作している 3 フェーズにも手を入れる必要があるため、リスクに見合わない。
- **`/issue` の Consumed Comments 記録先**: Step 13 の "Issue Retrospective" コメント内の `### Consumed Comments` サブセクション。この時点で Spec が存在しない `/issue` にとって、唯一の実行単位ごとの成果物であるため。
- **`/review`/`/merge` の記録先**: `/spec`/`/code`/`/verify` と同じ Spec の `## Consumed Comments` セクション (両フェーズとも Spec は既に存在する)。
- **`/issue` の初回 consume に件数上限・要約を設けない**: 置き換え対象の既存実装 (無制限フェッチ) および他フェーズの既存実装 (すべて無制限) と整合させる。コメント量は 1M context に対して無視できるほど小さい (`docs/product.md` の fork context に関する記述: 1M context GA によりコスト/容量面の制約は大きく後退している)。
- **`/merge` の呼び出し位置を Step 4 (post-squash) に置く**: Implementation Step 4 に記載の理由 (squash-merge によるブランチ削除、early push による mergeability 無効化リスク) により、他フェーズの「開始直後」という配置パターンからの意図的な逸脱である。
- **`/review` の bash fallback は `--no-push` を付けない**: `/spec`/`/code`/`/verify` の慣例 (`--no-push` を付け、後続の Exit 経路に push を委ねる) からの意図的な逸脱。Step 3 の XS/S early exit 分岐が `## Retrospective` の無条件 push に到達せずスキルを終了させ得るため、確実性を優先し即時 push とした。

### Out of Scope

- **`/review`/`/merge` の `comments_consumed` イベント発火**: `scripts/emit-event.sh` の `_emit_comments_consumed()` は現状 `run-code.sh` と `run-auto-sub.sh` の spec/code パスにのみ組み込まれている (`/verify` も `run-verify.sh` が存在しないため対象外)。`run-review.sh`/`run-merge.sh` へ組み込むには `run-auto-sub.sh` → `run-review.sh`/`run-merge.sh` の呼び出し連鎖における `EMIT_ISSUE_NUMBER` 変数のスコープを精査する必要があり、本 Issue の Acceptance Criteria はこれを要求していない。`/audit stats` のメトリクス完全性が明示的な目標になった際の follow-up として残す。
- **`docs/workflow.md` の Label Transition Map における `phase/merge` 行**: `skills/merge/SKILL.md` の現在の実装は `phase/merge` ラベルをどこにも付与しておらず、ドキュメントとの乖離が既に存在する (本 Issue と無関係な pre-existing drift)。本 Issue のカットオフ順序に関する分析 (`/merge` の Comment Consumption 呼び出し時点での最新 `phase/*` は `phase/review` である) を確認する過程で気づいたため記録するが、修正は本 Issue のスコープ外とする。

### #811 の教訓の適用

`docs/spec/issue-811-consumed-comments-bash-fallback.md` の review retrospective が指摘した「bash スニペット中の変数引用符漏れ」パターンを踏まえ、本 Spec の Implementation Steps に記載した bash スニペットはすべて `"$ISSUE_NUMBER"` の形式で引用符を付けている。

### Issue 本文への反映について

案 A/B/C の採否は実装方式 (How) の判断であり、Issue の受入条件・要求 (What) を変更するものではないため、Issue 本文の更新 (`gh-issue-edit.sh`) は行わない。

## issue retrospective

### Triage (auto-chain)

- Type: Feature (Issue Types API)
- Size: XL (Axis 1: ファイル数見積り ~6-8 [skills/review/SKILL.md, skills/merge/SKILL.md, skills/issue/SKILL.md, modules/l0-surfaces.md, tests/*.bats, Spec] は L 下限。Axis 2: 「複数 skill (issue/review/merge) 横断」の複雑度要因により +1 段階し XL へ)
- Value: 3 (Impact=2: shared_flag [modules/ + 複数 skill 横断]。Alignment=4: product.md Vision「governance-and-verification harness」との強い整合。raw=6 → Level 1 正規化表で Value 3)
- Priority: 未検出 (本文・タイトルに明示的な優先度キーワードなし)
- Verify command 監査 (Pattern 1-6): 該当なし。AC1/AC2 の `grep` は main 上で 0 件 (常時 FAIL でなく正しく実装前 FAIL / 実装後 PASS として機能する)。AC3 は起票時点で Pattern 2 (常時 PASS) を自覚的に回避しレポート済み (Notes 参照)
- 重複候補: なし (`gh search issues "1316"` で他 Issue からの言及なし)
- 依存関係: なし (`Blocked by` パターン本文になし、GraphQL blocked-by も未設定)

### Ambiguity Auto-Resolve (non-interactive mode)

Post-merge observation AC の対象範囲について、以下の判断で自動解決した:

- **判断**: 欠落窓 2 (review/merge 期間) 用の post-merge observation AC は追加しない。欠落窓 1 (パイプライン開始前) のみを observation で確認する現状の AC 構成を維持
- **理由**: 欠落窓 2 は Pre-merge の bats テスト (AC7) で機構自体の回帰保護を既に得ている。`observation` 型 AC は次に自然発生するイベントで検証されることが前提 (`modules/verify-classifier.md` § Firing Likelihood Check) だが、欠落窓 2 の発火条件 (review/merge 期間中に人間がマーカー無しコメントを投稿する) は次の `/auto` 実行で確実に起こるとは言えない。欠落窓 1 の observation (次に `/auto` に入る Issue へのコメント投稿という、ほぼ毎回発生するイベント) ほど自然発火性が高くないため
- 他の選択肢: 欠落窓 2 用の observation AC を追加する (発火が保証できないため不採用)

### 軽微な整形

- `### Pre-merge` → `### Pre-merge (auto-verified)` へ見出しを標準フォーマットに正規化 (`skills/review/SKILL.md` の "Pre-merge (auto-verified)" 優先ロジックと一致させるため)

### Scope Assessment

Size=XL だが non-interactive モードのため sub-issue 分割評価 (Step 12) はスキップした。対応方針 (案 A/B/C) が `/spec` に委ねられている点、および複数 skill 横断の変更規模を踏まえると、インタラクティブモードでの `/issue 1316` 再実行による分割評価を推奨する。

## spec retrospective

### Minor observations

- `/issue` の Existing Issue Refinement Step 1 は本 Issue着手前から `gh issue view $NUMBER --json comments` で全コメントを無条件フェッチしており、Issue 本文の調査表「`/issue` の consume: なし」という記述は実態としては不正確だった。本当の欠落は trust boundary 分類と Consumed Comments 記録の欠如であり、「コメントを一切読んでいない」わけではなかった。この区別は Implementation Step 2 の設計 (Step 1 の置換対象を正確に絞る) に直結した。
- `docs/workflow.md` の Label Transition Map に `phase/merge` という、`skills/merge/SKILL.md` が実際には一度も付与しない架空のラベル記述を発見した (本 Issue と無関係な pre-existing drift)。`/merge` の Comment Consumption 呼び出し時点の最新 `phase/*` を確定させる過程で気づいた。修正は Spec の Notes § Out of Scope に記録し、本 Issue では対応しない。

### Judgment rationale

- 案 A のみを採用し案 B (read watermark) を見送った判断根拠: 全 8 件の Pre-merge AC が漏れなく案 A の具体的挙動 (呼び出しの有無・順序・記録先) に対して書かれており、案 B は現状正しく動作している `/spec`/`/code`/`/verify` の cutoff 解決メカニズムまで再設計する必要がある。ACs が要求する範囲を超えるリスクを取る理由がなかった。
- `/merge` の呼び出し位置は当初「他フェーズと同様に Step 1-2 相当の早い段階」を想定していたが、`skills/merge/SKILL.md` Step 4 を実際に読み `gh pr merge --squash --delete-branch` が Step 4 冒頭で即座に実行されること (PR ブランチの削除が Phase Handoff write より先) を確認し、post-squash configuration に変更した。コードを読まずに「他フェーズと同じパターンで」と決め打ちしていたら、squash 後に消滅するブランチへコミットするだけの実装になっていた可能性がある。
- `/review` の bash fallback で `--no-push` を外した判断は、Step 3 の XS/S early exit 分岐が `## Retrospective`/`## Worktree Exit` という番号なしセクション (`skip Steps 7-14` の対象外に見えるが、`next-action-guide.md` 呼び出しで実質的にスキル終了するように読める) を経由しない可能性を検討した結果。既存の `--no-push` 慣例をそのまま踏襲すると、この edge case でコミットが未 push のまま worktree に取り残されるリスクがあった。

### Uncertainty resolution

- Step 13 の skip condition に「Consumed Comments が 0 件でないこと」を追加したことで、他に特筆すべき内容が皆無でも retrospective コメントが投稿されるケースが生じる。これがノイズになるか有用なシグナルになるかは、本 Issue の Post-merge observation AC が最初の実例を提供する。追加の検証手段は設けず、実運用の観察に委ねた (Spec 本体の Uncertainty セクション参照)。
- `_emit_comments_consumed()` を `/review`/`/merge` にも配線すべきか検討したが、`run-auto-sub.sh` → `run-review.sh`/`run-merge.sh` の呼び出し連鎖における `EMIT_ISSUE_NUMBER` の実際のスコープを確認しきれず (どの呼び出し経路で変数が継承されるか、追加調査が必要)、本 Issue の AC が要求しない拡張のためにスコープを広げるのは非効率と判断し、Out of Scope とした。

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- 案 A (全 6 フェーズで Comment Consumption Procedure 呼び出しを必須化) を採用し、案 B (read watermark)・案 C (marker 例外拡大) は不採用とした — 理由は Spec 本体の Alternatives Considered を参照
- `/merge` の呼び出しは Step 4 (post-squash) に配置 — Step 1-2 相当の早期配置では squash-merge によるブランチ削除でコミットが消失する、または early push が Step 1 の mergeability 判定を無効化するリスクがあった
- `/review` の bash fallback (`append-consumed-comments-section.sh`) は `--no-push` を付けない — `/spec`/`/code`/`/verify` の慣例と異なるが、Step 3 の XS/S early exit 分岐が後続の無条件 push に到達しない可能性への対策
- `/issue` の Consumed Comments 記録先は Step 13 の Issue Retrospective コメント内 `### Consumed Comments` サブセクション — この時点で Spec が存在しないため

### Deferred Items
- 案 B (read watermark) は、案 A のフェーズラベル境界単位のカバレッジで実運用上不十分と判明した場合の follow-up として保留
- `/review`/`/merge` への `_emit_comments_consumed()` 配線 (`comments_consumed` イベント発火) は、`EMIT_ISSUE_NUMBER` のスコープ調査が別途必要なため見送り
- `docs/workflow.md` の `phase/merge` ラベル記述と実装の乖離 (pre-existing) は本 Issue のスコープ外として記録のみ

### Notes for Next Phase
- 3 つの SKILL.md (issue/review/merge) の挿入位置はそれぞれ理由が異なる (issue: ラベル遷移より前 / review: Worktree Entry 直後・無条件 / merge: post-squash) ため、Implementation Steps 2-4 の配置指示を「他フェーズと同様に早い段階に置けばよい」と単純化せず、記載された位置と根拠に忠実に実装すること
- `tests/append-consumed-comments-section.bats` への追加テスト (AC7, AC8) はスクリプト自体の機能変更を伴わない回帰確認テストであり、スクリプト本体 (`append-consumed-comments-section.sh`) への機能変更は不要
- `skills/review/SKILL.md` と `skills/merge/SKILL.md` の `allowed-tools` frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` の追加が必須 (現状どちらにも存在しないことを確認済み)