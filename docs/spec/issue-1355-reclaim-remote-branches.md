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

- saito (MEMBER, first-class) — `/verify` の Acceptance Test Results コメント (`type=verify-executability`, post-merge AC #4 は実行可能と判定): https://github.com/saitoco/wholework/issues/1355#issuecomment
- saito (MEMBER, first-class) — verify iteration 1/3、FAIL につき Issue を fix cycle 用に reopen した旨の通知: https://github.com/saitoco/wholework/issues/1355#issuecomment
- saito (MEMBER, first-class) — `type=verify-fail` 診断コメント。post-merge AC の実データ実行結果、`worktree-code+issue-*` が 38→38 件で一件も削除されなかった根本原因 (`kind=issue` の headRefOid フォールバック欠如) と推奨修正方針を記録。本フェーズはこの診断を一級入力として本 PR の実装方針に採用した: https://github.com/saitoco/wholework/issues/1355#issuecomment

- saito / MEMBER / first-class / <!-- wholework-event: type=verify-fail phase=verify issue=1355 iteration=1 --> / https://github.com/saitoco/wholework/issues/1355#issuecomment-5298543562
## Code Retrospective

### Deviations from Design
- N/A — Spec の Implementation Steps 1〜4 通りに実装した。

### Design Gaps/Ambiguities
- `resolve_default_branch()` の base ブランチ解決方法 (`origin/HEAD` symbolic ref → 未設定時は `main` にフォールバック) は Spec に明記がなかったため実装時に判断した。`git remote add` (clone ではなく) で作成したリポジトリでは `origin/HEAD` symbolic ref が自動設定されないため、フォールバックが実質的な既定動作になる。全 wholework worktree の base branch は `main` 固定という前提 (他のリポジトリ全体の慣習と一致) に立った判断であり、他プロジェクトへの配布を考慮する場合は再検討の余地がある。
- kind=issue の祖先チェックは `git fetch origin refs/heads/<branch>:refs/remotes/origin/<branch>` でブランチ tip オブジェクトを都度取得する設計とした (任意 SHA1 の直接 fetch は GitHub 側で許可されないケースがあるため)。この fetch 回数は「安全策 (b) の判定に到達したブランチ」に絞られるよう `ensure_default_branch_ready()` で遅延評価しているが、Spec 自体はこの実装細部までは指定していなかった。

### Rework
- Post-merge `/verify` FAIL (iteration 1) で判明: `worktree-code+issue-N` (= `/code` pr route が squash merge するブランチ) は `classify_name()` により `kind=issue` に分類されるが、`kind=issue` の安全性チェックは `origin/<default-branch>` への祖先チェックのみで、squash merge されたブランチは常にこれに失敗するため一件も削除されなかった (実データ: 38→38件。対照的に `worktree-verify+issue-*` は `/verify` 由来で ff-only マージ相当のため 93→20件と正常動作)。原因は当初の Spec/Notes (「未コミット変更なしガードの相当実装」) が「`kind=issue` = ff-only マージのみ」という前提に立っており、`/code` pr route のブランチ名も同じ `kind=issue` パターンに一致しうる点が設計時に考慮されていなかったこと。修正: `closes #<N>` を検索し `gh-extract-issue-from-pr.sh` で実際の紐付けを検証した MERGED PR から `headRefOid` を取得し (`/verify` Step 2 の PR 探索と同じ技法)、`kind=issue` にも `kind=pr` と同じ `headRefOid` フォールバックを適用 (ローカル `delete_branch_safe()` の `-D` フォールバック、リモート safety (b) の両方)。bats に回帰テスト3件を追加 (ローカル -D フォールバック1件、リモートの成功/divergence 各1件、計22件 PASS)。

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
- Pre-merge AC ゲート (3件) はいずれも [x] 済みで unchecked_count=0、review-incomplete-fallback も検出されなかったため追加確認なしでマージを実行した。
- Squash merge (gh pr merge --squash --delete-branch) を実行し、closes #1355 により Issue は auto-close される見込み。

### Deferred Items
- Post-merge AC: scripts/reclaim-stale-worktrees.sh --apply-remote を実データで再実行し、worktree-code+issue-* 等の残留ブランチが解消されることを確認する (/verify フェーズで実施、iteration 2)。
- SHOULD 指摘 (review フェーズ、resolve_merged_pr_head_ref_oid の eager 呼び出し・レート制限リスク) — Post-merge AC の実データ実行で実際にレート制限が問題化した場合、lazy evaluation + memoization への再設計を別 Issue で検討する。

### Notes for Next Phase
- /verify 実行時は、--apply-remote (dry-run ではない) を実データで実行し、worktree-code+issue-* の削除件数が 0 から改善していることを確認すること。
- /verify 実行中に gh pr list --search 由来のレート制限警告が出ていないか観察すること。出ていればレート制限リスクの SHOULD 指摘を別 Issue 化する優先度を上げること。

## Consumed Comments

- saito / MEMBER / first-class / `<!-- wholework-event: type=verify-fail phase=verify issue=1355 iteration=1 -->` (cross-phase marker、cutoff 以前だが exception により消費対象) — `/code` フェーズで既に一級入力として採用済みの診断コメント。本 review フェーズでは新規の未消費コメントなし: https://github.com/saitoco/wholework/issues/1355#issuecomment-5298543562

## review retrospective

### Spec vs. implementation divergence patterns
- review-light (Perspective 2: Edge Cases and Robustness) が MUST を1件検出した: `resolve_merged_pr_head_ref_oid()` 内の `gh pr view "$candidate" --json headRefOid` 呼び出しが `set -euo pipefail` 下でエラーガードなしだったため、transient な gh API 失敗でスクリプト全体が中断しうる問題。これは Spec の Implementation Steps や Code Retrospective のどちらにも想定されていなかった実装細部で、「新規追加した `gh` 呼び出しは同ファイル内の既存パターン (`2>/dev/null` + `|| true`/`|| { ...; return; }`) に揃える」という暗黙の規約が Spec に明文化されていなかったために生じた漏れ。修正自体は Spec の設計方針を変更するものではなく、既存の防御パターンを新規関数にも適用しただけ (`docs/spec/issue-1355-reclaim-remote-branches.md` の Implementation Steps とは非整合ではない)。

### Recurring issues
- 同じ Issue #1355 のサイクル内で、`set -euo pipefail` とエラーハンドリングの整合性に起因する問題が2件連続で表面化した (1件目: `/verify` iteration 1 の `kind=issue` headRefOid フォールバック欠如そのもの、2件目: 今回のフォールバック実装自体が導入した未ガード `gh pr view` 呼び出し)。両者は原因は異なるが、「bash script に `gh` 呼び出しを追加する際、同ファイル内の既存ガードパターンとの整合を機械的にチェックする」観点があれば2件目は実装時点で防げた可能性がある。SHOULD 指摘 (line 163、eager 呼び出しによる API 呼び出し重複) も同根で、新規追加コードが既存ファイルの確立された設計原則 (`ensure_default_branch_ready()` の lazy 評価パターン) から逸脱していた。
- review-light (light mode, 1エージェント) が bug/logic/edge-case/security/documentation の4観点を単独でカバーし、review-bug 相当の指摘も含め MUST 1件・SHOULD 1件を検出できた。Size M の light mode でも十分な指摘密度が得られており、fan-out (review-spec + review-bug×2) が必須ではないケースだったと言える。

### Acceptance criteria verification difficulty
- 3件の Pre-merge AC (rubric×2, grep×1) はいずれも前回サイクルで既に `[x]` 済みであり、今回の PR 差分に対する再検証でも同様に自動判定可能で UNCERTAIN は発生しなかった。Post-merge AC (`--apply-remote` の実データ実行確認) は `/verify` フェーズに引き続き持ち越し。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Pre-merge AC 3件 (rubric×2, grep×1) は両サイクルとも自動判定可能で問題なし。Post-merge AC の文言自体は明確だったが、「安全策を維持する」という Purpose の要求が `kind=issue`/`kind=pr` の分類軸まで踏み込んで規定していなかったため、実装時に安全策の適用範囲にギャップが生じた。今後同種の Issue では、Purpose に「既存の安全策と同水準」とだけ書くのではなく、対象となる分類軸 (今回で言えば worktree ブランチの kind) を明示するとギャップを未然に防げた可能性がある。

#### design
- N/A — 設計方針自体 (ローカルロジックを踏襲したリモート安全策) は最後まで妥当だった。

#### code
- 1周目の実装は Spec 通りに完了したが、`worktree-code+issue-N` (`/code` pr route の PR ブランチ) が `kind=issue` に分類されるため、squash merge 済みブランチの安全な削除に必要な headRefOid フォールバックが `kind=pr` 専用のままだった、という設計ギャップが実データ実行で初めて顕在化した。rubric ベースの Pre-merge AC はこのギャップを検出できなかった (機能の「存在」は確認できても、「特定の分岐に対して機能するか」までは検証範囲外だったため)。2周目の修正 (`closes #<N>` 検索による MERGED PR の headRefOid フォールバックを `kind=issue` にも追加) はスコープが明確で手戻りは最小限だった。

#### review
- review-light が2周目の修正自体に含まれていた新規バグ (`resolve_merged_pr_head_ref_oid()` の未ガード `gh pr view` 呼び出し) を MUST として検出し、実データ実行前に修正できた。実データで70件超のリモートブランチを操作する直前にこの防御漏れを塞げた意義は大きい。

#### merge
- 2回とも squash merge・CI green・pre-merge AC 全 PASS でクリーンに完了。conflict や CI failure は発生しなかった。

#### verify
- FAIL root cause は、pre-merge の rubric 判定では検出できない「特定の入力パターン (squash merge された `kind=issue` ブランチ) に対してのみ機能しない」という部分的な実装ギャップだった。dry-run ではなく実データで `--apply-remote` を実行して初めて発覚した — これは本 AC を post-merge・manual (dry-run 不可、実データ実行必須) として設計した判断が正しかったことの裏付けでもある。`AUTONOMY_TIER=L3` + `auto-retry-on-fail.enabled=true` による auto-retry (iteration 1) が正しく機能し、FAIL コメントの根本原因診断をそのまま `/code` の入力として消費し、1回の追加サイクルで収束した。

### Retry Count

Retry Count: 1/3

### Improvement Proposals
- N/A — 今回の FAIL は auto-retry サイクル内で完全に解消済み。review retrospective が指摘した「新規 `gh` 呼び出しのエラーガード規約」は単発の設計改善点として Spec に記録済みであり、複数ファイル/複数 Issue にまたがる再発性の証拠 (Tier 1 の positive-evidence gate) を今回時点では確認できないため、Issue化は見送る。
