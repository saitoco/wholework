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

