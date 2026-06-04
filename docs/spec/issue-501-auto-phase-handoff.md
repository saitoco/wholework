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

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 実装箇所は SKILL.md + 共有モジュール（`modules/phase-handoff.md`）の組み合わせとした。SKILL.md が呼び出し側、modules が手順書として役割分担。
- review の Phase Handoff read 位置を「Step 7.0 detect-config-markers 後」とした。SPEC_PATH が Step 7.0 で確定するため、正しいパスでの Spec 探索を保証するため。
- merge の Phase Handoff write で worktree ブランチを origin/main に fast-forward した後 commit/push する手順を採用。gh pr merge 後の状態に確実に追従するため。

### Deferred Items
- Phase Handoff の実際の動作確認（downstream プロジェクトでの `/auto` 実行）は post-merge 検証として残っている。
- merge SKILL.md の standalone Phase Handoff commit が main への push 競合を起こさないかの実地確認は未実施。
- Spec が存在しない XS route での graceful skip 動作は実地確認未実施（設計上は問題ないが）。

### Notes for Next Phase
- validate-skill-syntax.py が SKILL.md 本文の大文字 "Write" を Write ツール参照と検知する。modules/phase-handoff.md の `Write Procedure` セクション名を SKILL.md 内で参照する際は backtick 記法か、allowed-tools に Write を含む SKILL.md 内で参照すること（merge はバッククォートで回避済み）。
- merge SKILL.md の Step 1 に detect-config-markers.md 読み込みを追加したが、merge は従来この読み込みをしていなかった。パフォーマンス面で懸念があれば SPEC_PATH をデフォルト値で固定する代替案もある。
- Phase Handoff write の内容（Key Decisions 等）は LLM が実装時の判断に基づき生成する。review phase はこの内容の品質も評価対象に含めるとよい。
