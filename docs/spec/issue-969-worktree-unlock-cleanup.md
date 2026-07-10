# Issue #969: run-code: retry 時の stale worktree クリーンアップに git worktree unlock を追加

## Consumed Comments

- No new comments since last phase. (verify cutoff: 2026-07-10T16:34:49Z)

## Issue Retrospective

### 構造修正

- `## Acceptance Criteria` に `### Pre-merge (auto-verified)` / `### Post-merge` のセクション見出しが欠落していたため追加した。既存の3条件 (`grep`/`rubric`/`command` の各 verify command) はいずれも機械検証可能な pre-merge 条件のため、全件を Pre-merge セクションへ配置し、Post-merge は「なし」とした。Acceptance Criteria の条件文言・verify command 自体は変更していない。

### 事実確認 (Background)

- Background に記載された「`scripts/run-code.sh` の178-184行目付近が `git worktree remove --force` のみを実行し、事前に `git worktree unlock` を呼び出していない」という記述を実コードで確認し、一致することを確認した (現在は183行目)。

### 自動解決した曖昧点 (Auto-Resolve Log)

- **`git worktree unlock` の失敗抑制パターンは既存の `git worktree remove --force ... 2>/dev/null || echo Warning` と同様の慣習に合わせる** — 理由: 同ファイル内の直後の `remove`/`branch -D` 処理が同一パターンを採用しており、実装時の一貫性が高い。Acceptance Criteria の文言はこの選択に依存せず変化しないため、ユーザー確認は不要と判断した。
  - 他候補: unlock 失敗時にエラーで停止する — worktree がそもそもロックされていないケース (通常の stale worktree) で誤って停止する副作用があるため不採用。
- **新規 bats テストの追加は本Issueのスコープに含めない** — 理由: 既存の AC3 は「既存テストスイート (該当する場合) が PASS する」であり、新規テスト作成を要求していない。stale worktree の unlock 挙動に対する新規テスト追加は実装時 (`/spec`/`/code`) の裁量に委ね、Issueの Acceptance Criteria としては明示しない (過剰スコープ拡張を避けるため)。

### ブロッキング関係

- `gh-check-blocking.sh` を実行したが `Blocked by #N` パターンは検出されず、依存関係の設定はなし (exit code 0)。

(この Issue Retrospective は Issue コメントから転記 — /auto Step 4b 相当の処理を verify セッションが実施。XS patch route のため Spec は本ファイルが初出)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue phase の triage で AC のセクション構造欠落 (Pre-merge/Post-merge 見出し) が修正され、3 条件すべてが機械検証可能な verify command 付きで揃っていた。verify は全件機械判定で完了。

#### design
- N/A (Size XS のため spec phase はスキップ — 設計判断は Issue 本文の Auto-Resolve Log で完結)。

#### code
- 単一コミット 22679c20 でクリーンに完了。修正内容は #966 の Verify Retrospective 改善提案から起票された Issue であり、retro → 起票 → 実装のパイプラインが機能した事例。

#### review
- N/A (patch route)。

#### merge
- N/A (patch route、main 直コミット)。

#### verify
- 全 3 AC が初回 verify で PASS (grep / rubric / bats 46 tests 0 failures)。
- **プロセス観察**: batch 経由 (`run-auto-sub.sh`) の XS patch route では、`/auto` SKILL.md Step 4b (Issue Retrospective コメントの Spec 転記) が実行されず、verify 開始時点で Spec ファイルが存在しなかった。単一 Issue の `/auto N` では親セッションが Step 4b を実行するが、batch List mode は phases を run-auto-sub.sh に委譲しており Step 4b 相当の処理が経路上に存在しない。今回は verify セッションが手動で転記したが、転記がなければ Issue Retrospective は Spec 読取ベースの retro パイプライン (retro-proposals / cross-session audit) から不可視になる。

### Improvement Proposals
- run-auto-sub.sh (または /auto batch List mode): XS patch route 完了時に Issue Retrospective コメントを Spec へ転記する Step 4b 相当の処理を追加すべき。現状は単一 Issue の `/auto N` 経路のみ Step 4b が実行され、batch 経路では Spec が作成されず Issue Retrospective が retro パイプラインから漏れる (Skill infrastructure improvement)。
