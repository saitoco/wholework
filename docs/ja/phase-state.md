[English](../../modules/phase-state.md) | 日本語

# phase-state

`scripts/reconcile-phase-state.sh` と `/auto` の SKILL.md が使用する、フェーズレベルの状態定義に関する SSoT モジュール。

## 目的

各フェーズについて期待される前提条件と成功シグネチャ (完了状態) を定義し、`scripts/reconcile-phase-state.sh` が出力する JSON 出力スキーマ (v1) を規定する。

## 入力

直接の入力はない — 本モジュールは読み取り専用である。呼び出し元はフェーズ定義を理解するためにこのファイルを参照する。

## 処理手順

### 実際の状態検査 (--check-completion)

完了チェックでは、`reconcile-phase-state.sh` が実際の状態 (GitHub のラベル、PR の状態、git log、ファイルの存在) を検査し、フェーズの成功シグネチャに到達しているかどうかを検証する。成功シグネチャが満たされている場合は `matches_expected: true` を、そうでない場合は `false` を返す。

### 前提条件検査 (--check-precondition)

前提条件チェックでは、`reconcile-phase-state.sh` がフェーズ実行前に必要な条件が整っているかどうかを検証する。すべての前提条件が満たされている場合は `matches_expected: true` を、そうでない場合は `false` を返す。デフォルトモードは `--warn-only` であり、GitHub API の結果整合性 (eventual consistency) を許容するため、不一致時も中断せず終了コード 0 で stderr に警告を出力する。

## 出力

### フェーズ一覧表

| フェーズ | 前提条件 | 成功シグネチャ (完了) | 実装状況 |
|-------|-------------|-------------------------------|----------------------|
| issue | Issue が存在し、状態が CLOSED でない | Issue に `phase/(issue\|ready\|code\|review\|merge\|verify\|done)` ラベルが付与されている | 実装済み |
| spec | Issue に `phase/issue` または `phase/spec` ラベルが付与されている | `$SPEC_PATH/issue-N-*.md` が存在し、かつ `phase/(ready\|code\|review\|merge\|verify\|done)` ラベルが付与されている | 実装済み |
| code-patch | Issue に `phase/ready` ラベルが付与されている、かつ Spec exists OR Size=XS | `git log origin/main --after=<reopen_ts> --grep="closes #N"` が新規コミットを 1 件以上返す (reopen タイムスタンプは `get-last-reopen` で取得); reopen タイムスタンプが取得できない場合は `git log origin/main --grep="closes #N"` にフォールバック; または operate ルート完了マーカーコメントが見つかる (後述の「Operate ルート完了シグネチャ」参照); または `worktree-code+issue-N` ブランチ上にオープンな PR が見つかる (後述の「残留 PR 完了シグネチャ」参照) | 前提条件: `phase/ready` — 実装済み; Spec exists OR Size=XS — 実装済み (Spec exists OR Size=XS)。完了判定: 実装済み |
| code-pr | Issue に `phase/ready` ラベルが付与されている、かつ Spec exists OR Size=XS | `worktree-code+issue-N` ブランチにオープンな PR (#310 が SSoT) | 前提条件: `phase/ready` — 実装済み; Spec exists OR Size=XS — 実装済み (Spec exists OR Size=XS)。完了判定: 実装済み |
| review | PR が OPEN | PR に `<!-- review-summary -->` マーカーを含むコメントがある (主判定); または `## Review Response Summary` / `## レビュー回答サマリ` (マーカー不在の投稿に対するフォールバック)。同一コメントが `type=review-incomplete` マーカー (`post-fallback-review-summary.sh` が投稿) も併せ持つ場合、完了判定は引き続き `true` を返すが、その完了がオーガニックではなくフォールバック起源であることを示すため `actual.review_incomplete_fallback` が設定される (#1174 参照) | 実装済み |
| merge | PR が OPEN であり、かつ (reviewDecision が APPROVED、または reviewDecision が CHANGES_REQUESTED でなく PR のコメント/レビューに review-summary マーカーが見つかる — 後述の「Merge 前提条件マーカーフォールバック」参照); reviewDecision=CHANGES_REQUESTED の場合は無条件で不一致 | `gh pr view --json state == MERGED` | 実装済み |
| verify | Issue に `phase/verify` ラベルが付与されている、または CLOSED である | Issue が CLOSED である、または `phase/done` ラベルが付与されている | 実装済み |

**注記**: Stage 2 のリカバリ (watchdog kill 後の code-pr における push + PR 作成) は #316 のリカバリサブエージェントに委譲される。`reconcile-phase-state.sh` は検査のみを行い、リカバリ処理は一切行わない。

### Operate ルート完了シグネチャ

`code-patch` フェーズは、patch ルートと operate ルート (`/code --patch` において Step 0 が `ROUTE=operate` を検出した場合。`skills/code/SKILL.md` 参照) の両方に対して同じ完了シグネチャを再利用する。operate ルートは実装差分を生成しない — Step 11 の commit/push/PR ブロックは完全にスキップされる — ため、`closes #N` コミットが発行されることはない。したがって `closes #N` シグネチャのみをチェックすると、operate ルートの実行が成功していても未完了と誤判定してしまう。

このギャップを埋めるため、`scripts/reconcile-phase-state.sh` の `_completion_code_patch()` は、operate ルート完了マーカーコメントを代替の成功シグネチャとして扱う:

- **L2/L3** (外部操作を実行): Step 11 が投稿する Issue コメントが `<!-- wholework-event: type=execution-log phase=code issue=N -->` で始まる。
- **L1 advisory** (Execution Plan のみで操作は未実行): Step 8 が投稿する Issue コメントが `<!-- wholework-event: type=execution-plan phase=code issue=N -->` で始まる。L1 advisory は `/code` の正常かつ成功した完了形態であるため (`skills/code/SKILL.md` Step 14 参照)、そのマーカーは L2/L3 マーカーと同等の完了シグナルとして受理される。

**新しさゲート**: 既存の `closes #N` シグネチャと同一のセマンティクス — reopen タイムスタンプが取得できる場合 (`get-last-reopen` 経由)、マーカーコメントの `createdAt` はそれより後である必要がある; 取得できない場合、新しさの制約は適用されない (既存の `closes #N` フォールバックと同様に無制限)。

**チェック順序**: commit (`closes #N`) → operate マーカー → label/state フォールバック (`phase/verify`/`phase/done`/`CLOSED`)。operate マーカーチェックは label/state フォールバックより先に実行されるため、fix-cycle の再実行時にも適用される (`reopen_ts` が非 null の場合、label/state フォールバックは無条件にスキップされる — operate マーカーチェックを先に配置することで、operate ルートの再実行が成功した場合にもそれを検知でき、`run-code.sh` が外部書き込みを再実行することを防ぐ)。

**既知の制約**: reopen タイムスタンプが取得できず、かつ Issue の Spec が reopen されないまま operate ルートから patch ルートへ書き換えられた場合、前回の operate サイクルの古いマーカーが、本来検出されるべき patch ルートのサイレント no-op を覆い隠してしまう可能性がある。これは `closes #N` フォールバックにすでに存在する同型の制約 (reopen タイムスタンプがない場合の無制限 grep) と同じ形であり、同じ理由で許容されている — 片方のシグネチャにのみ非対称な新しさ処理を追加すると、新たな失敗モードの類型を生んでしまうためである。

**2 つ目の利用元**: `scripts/collect-run-facts.sh` は同じマーカークエリを再利用して `code-patch` 実行に `route: operate` のラベルを付けるが、reopen タイムスタンプの代わりにセッションスコープの新しさゲート (実行の最初のイベントタイムスタンプ) を用いる — この 2 つの利用元は異なる問いに答えている (フェーズの完了 vs. その `/auto` セッションで何が起きたか)。`modules/run-fact-matching.md` § Fact JSON Fields 参照。

### 残留 PR 完了シグネチャ

ルート誤判定 (#979 系) により、`code-patch` フェーズの実際の成果物が、期待される `main` への `closes #N` コミットではなく、push 済みブランチ + オープンな PR (pr ルート形状の結果) として残ることがある。これに対する専用のシグネチャがない場合、Issue の作業が実際には完了しているにもかかわらず `_completion_code_patch()` は `matches_expected: false` を報告してしまい、その結果 `spawn-recovery-subagent.sh` の `skip)` ディスパッチガードが正しい `action=skip` のリカバリ推奨を却下してしまう (#993 参照)。

`_completion_code_patch()` は、SSoT の worktree ブランチ名 `worktree-code+issue-N` — `_completion_code_pr()` がすでに使用しているものと同じブランチ名パターン — にオープンな PR がないかをチェックすることで、このギャップを埋める (`gh pr list --head "worktree-code+issue-N" --state open`)。

**検出方法**: 該当ブランチのオープンな PR 件数を問い合わせ、1 件以上あればその PR の `createdAt` を取得し、以下の新しさゲートを適用する; 通過した場合は PR 番号を取得し、`actual.stray_pr_signal: true` と `actual.pr_number` を設定した上で `matches_expected: true` を出力する。

**新しさゲート**: 上記「Operate ルート完了シグネチャ」のゲートと同一のセマンティクス — reopen タイムスタンプが取得できる場合 (`get-last-reopen` 経由)、PR の `createdAt` はそれより後である必要がある; 取得できない場合、新しさの制約は適用されない。これにより、fix-cycle の reopen *より前* に残っていた残留 PR が、本来検出されるべき再実行失敗を覆い隠すことを防ぐ。

**チェック順序**: commit (`closes #N`) → operate マーカー → 残留 PR → label/state フォールバック (`phase/verify`/`phase/done`/`CLOSED`)。残留 PR チェックは operate マーカーチェックの直後、label/state フォールバックの前に実行される。理由は operate マーカーチェックが同じ位置に置かれている理由と同じである: `reopen_ts` が非 null の場合 label/state フォールバックは無条件にスキップされるため、残留 PR チェックを先に配置することで、fix-cycle の再実行中に作成された残留 PR もなお検知できる。

### Merge 前提条件マーカーフォールバック

Wholework のセルフホスト運用モデルでは、単一のアカウントが Issue のトリアージ・実装・レビュー・マージのすべてを行う。GitHub は自己 `APPROVE`/`REQUEST_CHANGES` 操作を HTTP 422 で拒否するため、self-PR では `reviewDecision` が `APPROVED` に到達することは決してなく、空または `REVIEW_REQUIRED` のまま無期限に留まる。したがって `reviewDecision == APPROVED` のみをチェックすると、merge の前提条件がすべての実行で警告を出してしまい、使い物にならないシグナルになる (「レビューが本当に未完了」なのか「self-PR は構造上 APPROVED になり得ない」だけなのかを区別できない)。

`scripts/reconcile-phase-state.sh` の `_precondition_merge()` は、`_completion_review()` がすでに使用している review-summary マーカー検出 (PR コメント + `gh api repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews` を `<!-- review-summary -->` / `## Review Response Summary` / `## レビュー回答サマリ` に照合) を代替シグナルとして採用する:

- `reviewDecision == APPROVED`: 前提条件を満たす (従来の挙動から変更なし)。
- `reviewDecision == CHANGES_REQUESTED`: 無条件で前提条件を満たさない — マーカーフォールバックは適用されない。古い/時期尚早な review-summary コメントの有無にかかわらず、未解決の requested changes は merge をブロックしなければならないため。
- それ以外の値 (空、`REVIEW_REQUIRED`、その他): review-summary マーカーが見つかった場合にのみ前提条件を満たす。それ以外は満たさない。

### JSON スキーマ (v1)

`reconcile-phase-state.sh` は、呼び出しのたびに以下の JSON を stdout に出力する:

```json
{
  "schema_version": "v1",
  "phase": "<phase-name>",
  "matches_expected": true,
  "actual": {
    "labels": ["phase/code"],
    "pr_state": "OPEN",
    "pr_number": 309,
    "commits_found": true,
    "spec_file": "docs/spec/issue-N-short-title.md",
    "issue_state": "OPEN"
  },
  "diagnosis": "Human-readable one-line description of the check result"
}
```

**フィールド契約 (下流の #315, #316, #317, #319 がこのスキーマに依存する):**

| フィールド | 型 | 必須 | 備考 |
|-------|------|----------|-------|
| `schema_version` | string | 常に | 固定値 `"v1"`; 破壊的変更時にインクリメント |
| `phase` | string | 常に | 7 つのフェーズ名のいずれか |
| `matches_expected` | boolean | 常に | `true` = 状態が期待値と一致; `false` = 不一致 |
| `actual` | object | 常に | フェーズ固有の実際の状態。関連するキーのみが含まれる |
| `actual.labels` | string[] | ラベルをチェックする場合 | issue の現在の GitHub ラベル |
| `actual.pr_state` | string | PR の状態をチェックする場合 | `"OPEN"`、`"MERGED"`、`"CLOSED"`、または `null` |
| `actual.pr_number` | number\|null | PR をチェックする場合 | PR 番号。見つからない場合は `null` |
| `actual.commits_found` | boolean | git log をチェックする場合 | `true` の場合 origin/main 上で該当するコミットが見つかった |
| `actual.operate_signal` | boolean | code-patch の完了判定で `closes #N` コミットが見つからない場合 | operate ルート完了マーカーコメント (execution-log または execution-plan) が見つかった場合 `true`。上記「Operate ルート完了シグネチャ」参照 |
| `actual.stray_pr_signal` | boolean | code-patch の完了判定で `closes #N` コミットも operate マーカーも見つからない場合 | `worktree-code+issue-N` ブランチにオープンな PR が見つかり、新しさゲートを通過した場合 `true`。上記「残留 PR 完了シグネチャ」参照。`true` の場合、`actual.pr_number` にも PR 番号が設定される |
| `actual.worktree_commits_found` | boolean | code-patch の完了判定で `closes #N` コミット・operate マーカー・残留 PR のいずれも見つからない場合、または code-pr の完了判定でオープンな PR が見つからない場合 | `worktree-code+issue-N` ブランチが `origin/main` に対してコミットが先行している場合 `true` (`git rev-list --count`、読み取り専用)。「まだ開始していない」(`false`) と「worktree ではコミット済みだが push/PR 作成が未完了」(`true`) を区別する — この区別がなければ両者は同じ `commits_found: false` (code-patch) または `pr_state: null` (code-pr) の観測結果に収束してしまう。ブランチが存在しない場合も `false` になる (1 回の `git rev-list` 呼び出しで両ケースを畳み込む)。診断目的のみであり、`matches_expected` には影響しない。`_completion_code_pr()` により無条件に出力される (PR なしの分岐の内側に限定されない)。これは `_completion_code_patch()` 自身の無条件配置を踏襲している。 |
| `actual.spec_file` | string\|null | spec をチェックする場合 | spec ファイルのパス。見つからない場合は `null` |
| `actual.issue_state` | string | issue の状態をチェックする場合 | `"OPEN"` または `"CLOSED"` |
| `actual.size` | string | Size チェックを伴う spec の前提条件チェック時 | `get-issue-size.sh` が返す Issue の Size 値 (例: `"M"`、`"XS"`、`""`)。Spec が存在せず Size チェックが実行される場合に存在する |
| `actual.hint_recent_commit` | string\|null | フェーズラベルの不一致検出時 | issue を参照する最新の git コミット、または `null`。フェーズラベルのリカバリのために追加 |
| `actual.hint_pr_state` | string\|null | フェーズラベルの不一致検出時 | 見つかった場合は PR の状態 (`"OPEN"`、`"MERGED"`、`"CLOSED"`)、見つからない場合は `null`。フェーズラベルのリカバリのために追加 |
| `actual.review_incomplete_fallback` | boolean | `type=review-incomplete` マーカーも併せ持つコメントによって review の完了が満たされた場合 | 一致した review-summary コメントが `/review` 自身の Step 14 の投稿 (オーガニックな完了) ではなく `post-fallback-review-summary.sh` (フォールバック完了) に由来する場合 `true`。それ以外は省略される。`modules/l0-surfaces.md` の `type=review-incomplete` マーカー参照 |
| `diagnosis` | string | 常に | 人間が読める 1 行の説明 |

**終了コード:**

| コード | 意味 |
|------|---------|
| 0 | `matches_expected: true` (状態が一致); 不一致時も `--warn-only` モードで使用される |
| 1 | `matches_expected: false` (不一致) — `--strict` フラグ指定時のみ |
| 2 | エラー (gh コマンドの失敗、不正な引数など) |
