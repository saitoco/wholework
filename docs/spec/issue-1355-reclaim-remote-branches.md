# Issue #1355: worktree: reclaim-stale-worktrees.sh にリモートブランチ削除オプションを追加

## Overview

Issue #1119 で追加した `scripts/reclaim-stale-worktrees.sh` はローカルの stale worktree ディレクトリと対応するローカルブランチの棚卸し・回収のみを行い、リモート (`origin`) 上のブランチには一切操作しない。実測で `main` を除く全リモートブランチ 132 件中 130 件超が `worktree-*` パターンに一致しており (2026-08-14 時点の再計測でも同水準)、大半が完了済み Issue/PR に対応する不要ブランチと判明している。本 Issue では同スクリプトに、対応する Issue が CLOSED、または PR が MERGED/CLOSED であるリモート `worktree-*` ブランチを安全に削除するオプションを追加する。既定は非破壊 (dry-run) とし、新規フラグ `--apply-remote` を明示指定した場合のみ実際に削除する。安全策はローカル削除ロジック (Issue #1119 の Step E/F/G) と同等の水準を、リモート専用ブランチに適用可能な形で実装する。

## Changed Files

- `scripts/reclaim-stale-worktrees.sh`: リモート `worktree-*` ブランチの列挙・分類・安全性チェック・削除ロジックを新規フラグ `--apply-remote` の背後に追加 (bash 3.2+ 互換。既存の `classify_name`/`check_completion` を再利用し、連想配列・`mapfile`/`readarray` は使用しない)
- `tests/reclaim-stale-worktrees.bats`: リモート回収の dry-run レポート・`--apply-remote` による削除・ローカル worktree 存在時の除外・安全性ガード拒否 (非祖先 / headRefOid 不一致) の各テストケースを追加
- `docs/structure.md`: `scripts/reclaim-stale-worktrees.sh` の Key Files 説明にリモート回収機能と `--apply-remote` を追記
- `docs/ja/structure.md`: [Steering Docs sync candidate / 翻訳同期] 上記説明の日本語ミラーを `docs/translation-workflow.md` の同期手順に従って更新
- `modules/worktree-lifecycle.md`: [Steering Docs sync candidate] "Broader stale worktree/branch reclaim" Notes サブセクションに `--apply-remote` オプションへの言及を追記 (既存の #1119 spec へのポインタと同じ形式)

## Implementation Steps

1. `scripts/reclaim-stale-worktrees.sh` にリモートブランチ回収ロジックを追加する。`git ls-remote --heads origin 'worktree-*'` で列挙し、既存の `classify_name`/`check_completion` を再利用して分類・完了判定する。安全性チェックは以下の2種を実装する: (a) 並行セッション除外相当 — 既存 Step B/C で収集済みの `SEEN_BRANCHES` (現在ローカルにチェックアウト中のブランチ) に含まれる場合はスキップし、対応するローカル worktree 自体の回収時に併せて扱う; (b) 未コミット変更なし相当 — kind=issue は `git symbolic-ref refs/remotes/origin/HEAD` で解決した base ブランチに対する `git merge-base --is-ancestor <remote-branch-sha> origin/<base>` で main 取り込み済みを確認、kind=pr は既存の `COMPLETION_HEAD_REF_OID` と一致するかで判定 (squash merge は祖先関係を保持しないため)。この時点では dry-run レポートのみ出力する (→ 受入条件 AC1, AC2 の前半)
2. `--apply-remote` フラグ (既存 `--apply` から独立し、単独指定可能) を追加し、Step 1 の安全性チェックを通過したブランチに対してのみ実際に `git push origin --delete <branch>` を実行するようゲートする。スクリプトの usage/ヘッダーコメントも更新する (after 1) (→ 受入条件 AC2)
3. `tests/reclaim-stale-worktrees.bats` にリモート回収のテストケースを追加する。既存テスト方針 (git バイナリ非モック、`gh` のみ PATH モック) を踏襲し、実ベアリポジトリを `origin` として `git remote add` した上でリモートブランチを push して検証する (parallel with 2) (→ 受入条件 AC1, AC2 の検証)
4. `docs/structure.md` の該当箇所を更新し、`docs/translation-workflow.md` の同期手順に従って `docs/ja/structure.md` を同期する。`modules/worktree-lifecycle.md` の "Broader stale worktree/branch reclaim" Notes サブセクションにも `--apply-remote` への言及を追記する (after 1) (→ 受入条件 AC3)

## Verification

### Pre-merge
- <!-- verify: rubric "reclaim-stale-worktrees.sh (または同等のスクリプト) が origin 上の worktree-* ブランチを列挙し、対応する Issue/PR が CLOSED/MERGED である場合に安全策 (未コミット変更なし相当のガード、並行セッション除外相当のガード) を経て削除できる機能を持つ" --> リモートの不要 worktree ブランチを安全に削除する機能が実装されている
- <!-- verify: rubric "新機能はデフォルトで dry-run 動作し、明示的なフラグ指定時のみ実際にリモートブランチを削除する" --> 誤操作防止のため既定値は非破壊 (dry-run) 側に倒されている
- <!-- verify: grep "reclaim-stale-worktrees" "docs/structure.md" --> docs/structure.md の該当スクリプトの説明が、リモートブランチ削除機能を含む内容に更新されている

### Post-merge
- マージ後、実装したリモート削除オプションを実際に (dry-run でない) 実行し、GitHub 上に 2026-08-13 時点で残留していた worktree-verify+issue-* および worktree-code+issue-* 等の不要ブランチが解消されていることを確認する <!-- verify-type: manual -->

## Notes

- **インターフェース設計判断 (Issue 本文で /spec フェーズに委譲されていた点)**: 新規フラグ `--apply-remote` を既存 `--apply` から独立させ、単独指定可能とした。理由: (1) リモートブランチ削除は GitHub 上の共有状態に影響し、ローカル専用の worktree/ブランチ削除より影響範囲が大きいため、明示的な opt-in を分離するのが安全側; (2) Issue 背景に記載の主要ケース (verify/code 由来の残留ブランチ) は、実行マシン上には対応する worktree/ブランチが既に存在しない孤児リモートブランチであり、`--apply` (ローカル回収) を伴わず `--apply-remote` 単独でも動作できる必要がある。
- **並行セッション除外ガードの相当実装**: ローカル worktree が存在しない (= 純粋な孤児リモートブランチ) 場合、既存の Step E ロック判定はそのままでは適用できない。代わりに、ローカル Step B/C で収集済みの `SEEN_BRANCHES` に含まれるブランチはこの新ステップの対象から除外し、対応するローカル worktree 自体が回収されるタイミングまで温存する (ローカルスコープに限定された安全性という既存スクリプトの前提を踏襲する — 他マシン上のチェックアウトは既存ローカル回収ロジックも検知できておらず、本追加もこの既知の限界を継承する)。
- **未コミット変更なしガードの相当実装**: kind=issue のブランチは `git merge-base --is-ancestor` による base ブランチへの祖先関係確認 (`worktree-merge-push.sh` の ff-only マージを経て main に取り込み済みであることの確認に相当)。kind=pr のブランチは既存の `delete_branch_safe()` と同じ `headRefOid` 一致判定を再利用する (squash merge は祖先関係を保持しないため、ff-only 前提のチェックが使えない)。
- bats テストは実 git worktree を使う既存方針 (git バイナリ非モック、`gh` のみ PATH モック) を踏襲する。リモート相当の検証には実ベアリポジトリを `origin` として `git remote add` する必要がある — 入力データ形式として、テストの `setup()` で bare repo を作成し `git push` でブランチを配置する形を想定する。
- 実データでの `--apply-remote` 実行は本 PR では行わない (Post-merge AC としてマージ後に実施)。

## Consumed Comments

前フェーズ以降の新規コメントなし。

## Code Retrospective

### Deviations from Design
- N/A — Spec の Implementation Steps 1〜4 通りに実装した。

### Design Gaps/Ambiguities
- `resolve_default_branch()` の base ブランチ解決方法 (`origin/HEAD` symbolic ref → 未設定時は `main` にフォールバック) は Spec に明記がなかったため実装時に判断した。`git remote add` (clone ではなく) で作成したリポジトリでは `origin/HEAD` symbolic ref が自動設定されないため、フォールバックが実質的な既定動作になる。全 wholework worktree の base branch は `main` 固定という前提 (他のリポジトリ全体の慣習と一致) に立った判断であり、他プロジェクトへの配布を考慮する場合は再検討の余地がある。
- kind=issue の祖先チェックは `git fetch origin refs/heads/<branch>:refs/remotes/origin/<branch>` でブランチ tip オブジェクトを都度取得する設計とした (任意 SHA1 の直接 fetch は GitHub 側で許可されないケースがあるため)。この fetch 回数は「安全策 (b) の判定に到達したブランチ」に絞られるよう `ensure_default_branch_ready()` で遅延評価しているが、Spec 自体はこの実装細部までは指定していなかった。

### Rework
- N/A — 手戻りなし。

## review retrospective

### Spec vs. implementation divergence patterns
- N/A — review-light による突き合わせでも Spec の Implementation Steps 1〜4 との構造的乖離は検出されなかった。既知の設計ギャップ (`resolve_default_branch()` の `main` フォールバック) も Spec の Code Retrospective に明記済みで、fail-safe 側に倒れていることを確認した。

### Recurring issues
- Nothing to note — review-bug 相当の指摘は 0 件だった (SKIP_REVIEW_BUG=false の light mode だが review-light が bug/logic/security 観点も含めて 0 件と報告)。

### Acceptance criteria verification difficulty
- Nothing to note — 3件の Pre-merge AC (rubric×2, grep×1) はいずれも safe mode で自動判定可能で、UNCERTAIN は発生しなかった。rubric 条件文は削除対象の安全策 (並行セッション除外相当・未コミット変更なし相当) を明示的に言及しており、grader が判定しやすい形になっていた。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC 3件はすべてチェック済み、review-incomplete-fallback は organic completion (fallback 経由ではない) と確認した上で squash merge を実行した。
- `mergeable=true` (CI success, review approved, conflicts なし) だったため、conflict resolution ステップはスキップした。

### Deferred Items
- Post-merge AC: `scripts/reclaim-stale-worktrees.sh --apply-remote` を実データで実行し、`worktree-verify+issue-*` / `worktree-code+issue-*` 等の残留ブランチが解消されることを確認する (`/verify` フェーズで実施)。

### Notes for Next Phase
- `/verify` では上記 Post-merge AC の実データ検証を忘れずに実施すること。dry-run report で対象ブランチの残存を先に確認してから `--apply-remote` を実行するのが安全。
