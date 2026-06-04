# Issue #501: auto: phase 間で Phase Handoff 要約を引き継ぎ context 非共有を軽減

## Overview

`/auto` の各 phase は forked session で実行されるため phase 間で in-context メモリが共有されない。Spec ファイルへの retrospective append という既存の cross-phase memory 設計を拡張し、各 phase の完了時に「次 phase 向け要約（重要判断・保留事項・注意点）」を `## Phase Handoff` セクションとして Spec に書き出し、次 phase の起動時に読み込む仕組みを導入する。handoff は最新 1 phase 分のみ保持（ローテーション）。XS route など Spec が存在しない経路では graceful skip。

実装箇所: 新設する共有モジュール `modules/phase-handoff.md` に読み書き手順を集約し、各 SKILL.md から参照する。

## Changed Files

- `modules/phase-handoff.md`: 新規 — Phase Handoff read/write 共有モジュール (bash 3.2+ 非該当; markdown のみ)
- `skills/spec/SKILL.md`: Step 13 retrospective append 後・commit 前に Phase Handoff write 手順を追加 (`modules/phase-handoff.md` Write Procedure 参照)
- `skills/code/SKILL.md`: Step 5 (Load Spec) 後に Phase Handoff read 手順追加、Step 12 retrospective commit 前に Phase Handoff write 手順追加
- `skills/review/SKILL.md`: Step 5 (Fetch Issue Information) 後に Phase Handoff read 手順追加、Retrospective step commit 前に Phase Handoff write 手順追加
- `skills/merge/SKILL.md`: Step 1 に Issue 番号の早期抽出を追加し Phase Handoff read 手順追加、Step 4 (Execute Squash Merge) 後・Step 5 (Label Transition) 前に Phase Handoff write 手順追加
- `skills/verify/SKILL.md`: Step 4 (Fetch Issue Acceptance Conditions) 後・Spec 読み込み完了後に Phase Handoff read 手順追加 (write は最終 phase のため不要)
- `docs/structure.md`: modules/ ファイル数コメント 34→35 に更新、Key Files モジュール一覧に `modules/phase-handoff.md` エントリ追加
- `docs/ja/structure.md`: `docs/structure.md` 変更内容の日本語ミラー同期

## Implementation Steps

1. `modules/phase-handoff.md` 新規作成 — 以下の構成で実装
   - **Phase Handoff セクションフォーマット**: `## Phase Handoff` ヘッダー + `<!-- phase: {name} -->` マーカー + `### Key Decisions` / `### Deferred Items` / `### Notes for Next Phase` の 3 サブセクション
   - **Write Procedure**: (1) Spec ファイル存在確認（なければ graceful skip）、(2) 要約コンテンツ生成（重要判断・保留事項・次 phase 注意点、各 3–5 bullet 目安）、(3) `grep -n "^## Phase Handoff"` で既存セクション確認、(4) 存在すれば Edit tool で old section 全体を new content に置換（ローテーション）、存在しなければ Edit tool で末尾に append、(5) 同一 commit に含める（retrospective commit と同タイミング）
   - **Read Procedure**: (1) Spec ファイル存在確認（なければ graceful skip + ログ出力）、(2) `## Phase Handoff` セクション存在確認（なければ "no handoff from prior phase" ログ出力して続行）、(3) 存在すれば内容を読み取り当該 phase の実行コンテキストに反映
   - **Phase 位置による非対称性**: spec（最初の実行 phase）は read をスキップし write のみ実施、verify（最後の phase）は write をスキップし read のみ実施、code/review/merge は read/write 両方実施

2. Phase Handoff write を各 phase の completion に追加（→ AC1）
   - `skills/spec/SKILL.md` Step 13: spec retrospective append 後・commit コマンド実行前の sub-step として「`modules/phase-handoff.md` Write Procedure に従い Phase Handoff をスペックに書き出す」を追記
   - `skills/code/SKILL.md` Step 12: code retrospective append 後・commit コマンド実行前の sub-step として同様に追記
   - `skills/review/SKILL.md` Retrospective step: review retrospective append 後・commit コマンド実行前の sub-step として追記
   - `skills/merge/SKILL.md`: Step 4 完了後・Step 5 の前に新 sub-step として「Issue 番号から Spec を特定し `modules/phase-handoff.md` Write Procedure を実行」を追記（merge は独立した retrospective step がないため単独 sub-step）

3. Phase Handoff read を各 phase の startup に追加（→ AC2）
   - `skills/code/SKILL.md` Step 5 末尾: "Spec を読み込んだ後、`modules/phase-handoff.md` Read Procedure に従い Phase Handoff を読み込む" を追記
   - `skills/review/SKILL.md` Step 5 末尾: Spec ファイルパス特定後（`$SPEC_PATH/issue-$ISSUE_NUMBER-*.md`）に Read Procedure 実行を追記
   - `skills/merge/SKILL.md` Step 1: `gh pr view "$NUMBER" --json title,body` で PR body を取得し Issue 番号を抽出（既存の headRefName/baseRefName fetch に body を追加）、その後 `modules/phase-handoff.md` Read Procedure 実行を追記
   - `skills/verify/SKILL.md` Step 4 末尾: Spec 読み込み後（既存 Spec 参照処理の後）に Read Procedure 実行を追記

4. `docs/structure.md` 更新（→ AC5 の構造面を補強）
   - Directory Layout の `modules/` コメントを `(34 files)` → `(35 files)` に変更
   - Key Files § Modules の `modules/phase-banner.md` と `modules/phase-state.md` のエントリ間（アルファベット順）に `modules/phase-handoff.md` エントリを追記: `- \`modules/phase-handoff.md\` — phase 間 Phase Handoff 要約の read/write（cross-phase context carryover）`

5. `docs/ja/structure.md` 更新 — Step 4 の変更を日本語ミラーに反映（ファイル数コメント・モジュール一覧エントリ）

## Verification

### Pre-merge

- <!-- verify: rubric "各 phase（spec/code/review/merge/verify）の完了時に、対象 Issue の Spec ファイル末尾へ次 phase 向けの Phase Handoff 要約（重要判断・保留事項・次 phase が注意すべき点）を append する処理が実装されている（実装箇所が wrapper / SKILL.md / 共有モジュールのいずれかは不問）" --> phase 完了時の Phase Handoff 書き出しが実装されている
- <!-- verify: rubric "各 phase の起動時に、対象 Issue の Spec から最新の Phase Handoff を読み込み、当該 phase の手順／プロンプトへ反映する処理が実装されている" --> 次 phase 起動時の handoff 読み込みが実装されている
- <!-- verify: rubric "Phase Handoff の保持は最新 1 phase 分のみ（次 phase 完了時に古い handoff をローテーション）で、context 累積を抑制する設計になっている" --> ローテーション設計が実装されている
- <!-- verify: rubric "Spec が存在しない経路（XS patch route）では Phase Handoff の読み書きを graceful に skip し、エラーや処理停止を起こさない" --> Spec 非存在時の graceful skip が実装されている
- <!-- verify: rubric "関連 SKILL.md（spec/code/review/merge/verify）に Phase Handoff の読み書き手順が追記されている" --> 各 SKILL.md への手順追加が実装されている
- <!-- verify: github_check "gh pr checks --json name,state --jq '[.[] | select(.name | test(\"bats\"; \"i\")) | .state] | unique | join(\",\")'" "SUCCESS" --> bats テスト CI が SUCCESS

### Post-merge

- downstream プロジェクトで `/auto` 実行時に phase 間の文脈喪失（前 phase 判断の引継ぎ漏れ）が体感的に減ることを観察する <!-- verify-type: manual -->

## Notes

- **merge の Issue 番号早期抽出**: 現在の merge SKILL.md は Step 1 で `gh pr view --json headRefName,baseRefName,isDraft` のみ取得し、Issue 番号は Step 5 (Label Transition) の後で抽出している。Phase Handoff read を Step 1 後に行うため、Step 1 の fetch クエリに `body,title` を追加して Issue 番号を早期に抽出する必要がある
- **verify の Spec 読み込みタイミング**: verify SKILL.md Step 4 は `detect-config-markers.md` 読み込み + acceptance conditions 取得が主目的だが、Step 12 (Retrospective) で Spec を読み込んでいる。Phase Handoff read はより早い Step 4 段階で行う（Spec が存在する場合に限り追加読み込み）
- **ローテーション実装の注意点**: Spec 末尾の `## Phase Handoff` セクションを Edit tool で置換する際、セクション境界は「次の `##` ヘッダー or ファイル末尾」を正確に特定する必要がある。`/code` 実装時は既存 retrospective セクションとの境界に注意
- **Non-interactive mode 対応**: Phase Handoff の read/write は決定論的操作（Spec が存在するかどうかの判断）のみであり、AskUserQuestion を必要としない。non-interactive mode でも問題なく動作する
- **XS route の graceful skip 確認**: `/auto` SKILL.md Step 4b で XS route 用 Spec が code 完了後に生成される場合、code phase 実行中は Spec が存在しないため Phase Handoff write もスキップされる（Spec 存在確認が先行する）

## Code Retrospective

### Deviations from Design

- review SKILL.md の Phase Handoff read 挿入箇所を Spec の「Step 5 末尾」から「Step 7.0 detect-config-markers 後」に変更した。SPEC_PATH が Step 7.0 で初めて確定するため、正しい Spec パスで read するにはこちらが適切。
- merge SKILL.md の Phase Handoff write で `git fetch origin && git merge origin/main --ff-only` を先行させる手順を追加した。`gh pr merge` 後に origin/main が進んでいるため、worktree ブランチを追従させてから commit/push する必要があった。
- merge SKILL.md の allowed-tools に `Glob` を追加した（Spec ファイル探索に必要）。Spec では allowed-tools の変更について言及がなかったが、validate-skill-syntax.py の検証でエラーが発覚し修正。

### Design Gaps/Ambiguities

- phase-handoff.md "Write Procedure" の文字列が merge SKILL.md 本文に現れると validate-skill-syntax.py が `Write` ツール参照と誤検知する。他の SKILL.md（code/review/spec）は `Write` が allowed-tools にあるためパスしていたが、merge は含まれていなかった。バッククォートでの inline code 記法（`Write Procedure`）により回避した。
- merge SKILL.md は独立した retrospective step を持たないため、Phase Handoff write は Step 4 完了後の standalone sub-step となった（Spec 通り）。

### Rework

- merge SKILL.md: allowed-tools への `Glob` 追加と "Write Procedure" 表記の変更（2 回の Edit）。validate-skill-syntax.py 検証で発覚したため、実装後に修正が必要になった。

## review retrospective

### Spec vs. 実装の乖離パターン

Spec の「Step 5 末尾」指定に対し、review SKILL.md は「Step 7.0 detect-config-markers 後」に Phase Handoff read を配置した。SPEC_PATH が Step 7.0 で確定するため技術的に正当な逸脱であり、Code Retrospective に記録済み。今後同様のパターン（`SPEC_PATH` 参照が前提のステップ）では、Spec 作成時点で解決タイミング依存関係を明示するとよい。

### 繰り返し発生する指摘パターン

Phase Handoff write を追加した際、Commit and push を sub-bullet から top-level ステップ 4 に昇格させたが、後続ステップ（`If improvement proposals exist`）の番号更新を漏らした（`3.` → `5.`）。ステップ番号の変更を伴う SKILL.md 編集では後続全ステップの番号確認が必要。spec/code/merge SKILL.md は正しく更新されており、review のみ発生した。

### 受け入れ条件の自動検証難易度

rubric 型の条件（AC 1–5）は全て diff 参照で PASS 判定可能だった。github_check 型（bats CI）も `gh pr checks` で即時確認可能。verify command の記述品質は高く、UNCERTAIN は 0 件。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- review SKILL.md Retrospective のステップ番号重複（`3. If improvement proposals exist` が `5.` であるべき）を SHOULD 指摘として検出し修正した。validate-skill-syntax.py は構文エラーを検知するが、ステップ番号の論理的な重複は検知しない。
- Phase Handoff read の位置を Step 7.0 detect-config-markers 後に採用（Spec は Step 5 末尾を指定していたが、SPEC_PATH 確定のタイミングから逸脱が正当）。この判断を再確認し、merge phase に引き継ぐ。

### Deferred Items
- merge SKILL.md の Phase Handoff write 後の `git push origin HEAD:main` が並行マージ時に失敗する可能性は確認済みだが、graceful fallback（verify が graceful skip）により実害なし。実地確認は post-merge 検証に委ねる。
- Spec が存在しない XS route での graceful skip 動作の実地確認も引き続き post-merge 対象。

### Notes for Next Phase
- merge SKILL.md の Phase Handoff write commit は `git push origin HEAD:main` で main へ直接 push する設計。競合時は push が失敗する可能性があるが、verify は graceful skip するため致命的な障害にはならない。
- merge phase で detect-config-markers.md を読み込むようになったため（SPEC_PATH 取得目的）、`.wholework.yml` の `spec-path` 設定が merge にも反映される。デフォルト値（`docs/spec`）を使う場合は影響なし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC は rubric 主体で挙動レベルに一般化されており（実装箇所を wrapper/SKILL.md/モジュール不問）、diff 参照で全 PASS・UNCERTAIN 0。verify command の記述品質が高い。
- spec phase が Size を M→L に再評価（変更ファイル 8）。`/issue` 時点は M だったが spec の詳細化で L 相当と判明。Size 再評価が `/auto` の review 深度（light/full）に影響した（Improvement 参照）。

#### design
- 新規共有モジュール `modules/phase-handoff.md` に read/write を集約し 5 SKILL.md から参照する設計は progressive-disclosure 原則に合致。
- merge phase の「Issue 番号早期抽出」という非自明な依存を Spec が事前に Notes で指摘しており、実装の手戻りを軽減した。

#### code
- merge SKILL.md で `Write Procedure` の文字列が validate-skill-syntax.py に Write ツール参照と誤検知された（merge は allowed-tools に Write 不在）。inline code 記法で回避。実装後に発覚した rework。
- merge SKILL.md allowed-tools への `Glob` 追加が Spec 未記載だったが Spec 探索に必要だった。

#### review
- review SKILL.md Retrospective のステップ番号重複（`3.` → `5.`）を SHOULD 指摘として検出・修正。番号変更を伴う SKILL.md 編集では後続番号の一括確認が必要（review のみ発生、spec/code/merge は正しく更新済）。
- **bootstrap 検証**: review phase が新実装の Phase Handoff write を実行し、本 Spec に `## Phase Handoff <!-- phase: review -->` を書き出した。機構が自己の実装 PR 内で end-to-end 動作した証跡。
- **orchestration anomaly（review completion signature ドリフト）**: review wrapper が exit 1 で終了したが、レビュー自体は成功（サマリ投稿・CI 全 PASS・SHOULD 1件解消・MUST なし）。原因は `reconcile-phase-state.sh:227` / `modules/phase-state.md:40` の review 成功シグネチャ（`## Review Response Summary` / 旧称: review answer summary の和文形）と、review SKILL.md が実際に投稿する見出し（`## レビューレスポンスサマリー`）の不一致。`/auto` の review phase で false-negative completion を誘発した。親セッションが直接証拠（CLEAN mergeable・CI 全 SUCCESS・サマリ存在）で manual recovery 判断し success へ override。

#### merge
- merge は OLD merge SKILL.md で実行されたため handoff write（phase: merge）は未実施で、review の handoff が最新のまま残存。これは実装 PR 特有の bootstrap 事象で、次回以降の `/auto` では merge も handoff を書き出す。
- merge 自体は正常（squash merge・remote branch 削除・CI 全 PASS）。

#### verify
- 全 pre-merge 条件 PASS（rubric 5 + bats CI SUCCESS）。FAIL/UNCERTAIN/PENDING 0。
- post-merge manual 条件（downstream `/auto` での文脈喪失軽減の体感観察）は runtime の主観・継続観察を要し自動検証不可 → 未チェックのまま `phase/verify` 維持。

### Improvement Proposals

- **[高優先] review completion signature のドリフト修正**: `reconcile-phase-state.sh:227` / `modules/phase-state.md:40` が期待する review 成功シグネチャ（`## Review Response Summary` および和文形）と、review SKILL.md が投稿する見出し `## レビューレスポンスサマリー` が不一致。`/auto` の review phase で false-negative completion を引き起こし、不要な Tier 1–3 recovery 判断を誘発する。対応案: (a) review SKILL.md の見出しを既存シグネチャに合わせる、または (b) `phase-state.md` / `reconcile-phase-state.sh` のシグネチャ集合に `## レビューレスポンスサマリー` を追加する。distributable layer（scripts/modules/skills）の修正。
- **[中] `/auto` の spec 後 Size 再取得**: spec phase が Size を更新し得るが、`/auto` は Step 2 取得の Size（キャッシュ）で route／review 深度を決める。spec 成功後に `get-issue-size.sh --no-cache` で再取得し review 深度を再判定すべき。本 run では M→L 変化を親セッションが手動検出して `--full` へ切替えた。
- **[軽微] SKILL.md ステップ番号変更時の後続一括確認**: review でステップ番号重複が発生。番号変更を伴う編集では後続全ステップの番号確認を徹底する。

## Auto Retrospective

### Execution Summary

| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec | pr (L) | SUCCESS | Size を M→L に再評価（変更ファイル 8） |
| code | pr (L) | SUCCESS | PR #527 作成 |
| review | pr (L) | SUCCESS (manual recovery) | wrapper exit 1 だが署名 false-negative。mergeStateStatus=CLEAN・CI 全 SUCCESS・サマリ投稿済を直接確認し success へ override |
| merge | pr (L) | SUCCESS | squash merge・remote branch 削除 |
| verify | - | SUCCESS (opportunistic pending) | 全 auto 条件 PASS、manual 条件 pending で phase/verify 維持 |

### Orchestration Anomalies

- **review phase の false-negative completion**: `run-review.sh` が exit 1 で終了したが review は実質成功（サマリ投稿済・CI 全 PASS・SHOULD 1件解消・MUST なし）。原因は `reconcile-phase-state.sh` の review completion signature ドリフト — review LLM が要約見出しを `## レビューレスポンスサマリー` にローカライズして投稿したが、reconcile の署名集合（`## Review Response Summary` + 和文形）に非該当。Tier 2 `detect-wrapper-anomaly.sh` は空（unknown pattern）を返したため、親セッションが直接証拠（`mergeStateStatus=CLEAN`・CI 全 SUCCESS・サマリ存在）に基づき manual recovery 判断し success へ override した。catalog / recovery-sub-agent / wrapper-anomaly-detector のいずれも発火していないため `docs/reports/orchestration-recoveries.md` への append は対象外。
- **spec 後の Size 変化が route に未追従**: spec phase が Size を M→L に更新したが、`/auto` Step 2 で取得した Size（キャッシュ）が stale のままだった。親セッションが `get-issue-size.sh --no-cache` で L を手動検出し review を `--full` に切替えて整合を確保した。

### Improvement Proposals

- 起票済み: #528（review 完了署名のローカライズ分散による false-negative 解消）、#529（`/auto` spec 後 Size を no-cache 再取得し review 深度を再判定）。本 retrospective の改善提案は verify retrospective 経由で既に Issue 化済みのため、ここでの再起票は行わない（重複防止）。

