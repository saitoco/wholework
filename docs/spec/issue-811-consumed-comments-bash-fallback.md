# Issue #811: Spec への Consumed Comments セクション追記を LLM 駆動から bash/post-processor 駆動に移行

## Overview

`modules/l0-surfaces.md` Comment Consumption Procedure の Step 5 (Spec への `## Consumed Comments` セクション追記) が、context pressure や fix-cycle path で LLM により silent skip されるケースが観測されている (#705, #774 AC8)。

本 Issue では Candidate B (post-processor fallback) を採用する:
- `/spec` `/code` フェーズ (bash-wrapped): LLM が書かなかった場合に bash post-processor がフォールバック追記
- `/verify` フェーズ (in-session): SKILL.md の明示的 bash 呼び出しで決定論的に追記

判断根拠:
- Candidate A (bash helper 化) → comment の 1 行要約が機械的 truncate になり情報品質が低下する
- Candidate B (post-processor) → LLM 版の質を保ちつつ silent skip を防止; `/spec`/`/code` は pre/post カウント比較で発火可否を判定
- Candidate C (subskill 化) → 追加 LLM call コスト増・新 subskill 設計が必要; 本 Issue の規模に対し過剰

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: 3 件の曖昧ポイント自動解決 (bats; true 除去、run-verify.bats 不在の扱い、候補選択を /spec へ委任) / https://github.com/saitoco/wholework/issues/811#issuecomment-4823224834

## Changed Files

- `scripts/append-consumed-comments-section.sh`: 新規スクリプト — ISSUE_NUMBER PHASE_NAME を受け取り、Spec ファイルに `## Consumed Comments` セクションを追記して git commit + push。best-effort (常に exit 0)。bash 3.2+ compatible
- `scripts/emit-event.sh`: `_append_consumed_comments_section()` ラッパー関数を追加 — `"$SCRIPT_DIR/append-consumed-comments-section.sh"` を呼び出す (WHOLEWORK_SCRIPT_DIR モック対応)
- `scripts/run-spec.sh`: claude 呼び出し前に Spec ファイルの `## Consumed Comments` 数を capture → claude 完了後にカウントが増えていなければ `_append_consumed_comments_section()` を呼び出す (post-processor fallback)。bash 3.2+ compatible
- `scripts/run-code.sh`: 同様 pre/post カウント比較 + fallback 呼び出し。bash 3.2+ compatible
- `modules/l0-surfaces.md`: Step 5 に bash wrapper fallback の注記を追加 — `/spec`/`/code` は post-processor が保証; `/verify` は SKILL.md の明示 bash 呼び出しで保証
- `skills/verify/SKILL.md`: Step 1 Comment Consumption 後に `bash ${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh $NUMBER verify` の明示 bash 呼び出し step を追加; frontmatter allowed-tools に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` を追加
- `tests/run-spec.bats`: `_append_consumed_comments_section` fallback の bats テスト追加 (カウント増えず → 呼ばれる, カウント増加 → 呼ばれない)
- `tests/run-code.bats`: 同様テスト追加
- `tests/run-verify.bats`: 新規 bats テストファイル — `scripts/append-consumed-comments-section.sh` の動作を verify フェーズシナリオでテスト (Spec なし → skeleton 作成, セクション既存 → スキップ, verify-fail marker 含む comment → 記録)
- `docs/structure.md`: scripts/ ファイル数カウント更新 (58 → 59); `append-consumed-comments-section.sh` をスクリプト一覧に追加
- `docs/ja/structure.md`: 英語版の変更を日本語版に反映 (translation sync)

## Implementation Steps

1. `scripts/append-consumed-comments-section.sh` を新規作成 + `scripts/emit-event.sh` に `_append_consumed_comments_section()` ラッパーを追加 (→ AC1)
   - スクリプトは `ISSUE_NUMBER` `PHASE_NAME` を引数に取る
   - `docs/spec/issue-$ISSUE_NUMBER-*.md` を glob で spec ファイルを探す; 見つからない場合は issue title を gh から取得して skeleton ファイルを作成
   - `grep -q "^## Consumed Comments" "$spec_file"` でセクション存在確認。存在しない場合のみ追記 (各呼び出しで1つずつ追記する設計ではなく、セクション不在のみに対応するシンプル判定)
   - カットオフ取得: `gh api repos/{owner}/{repo}/issues/$ISSUE_NUMBER/timeline --paginate --jq '[.[] | select(.event=="labeled" and (.label.name|startswith("phase/"))) | .created_at] | last // empty'`
   - comment 取得: カットオフ以降 + verify-fail marker コメント (cutoff に依らず)
   - Trust tier 分類: OWNER/MEMBER/COLLABORATOR = first-class, CONTRIBUTOR/NONE = external, `[bot]` suffix = bot (wholework-event マーカー有の場合は例外)
   - 追記フォーマット: `- login / authorAssociation / trust-tier / body 先頭行 truncate / URL`; コメントなし: `No new comments since last phase.`
   - `git -C "$_repo_root" diff --quiet "$spec_rel_path"` で変更確認 → `git add + commit -s + push` (best-effort、失敗しても exit 0 維持)
   - emit-event.sh の `_append_consumed_comments_section()` は `"$SCRIPT_DIR/append-consumed-comments-section.sh" "$@"` を呼び出す

2. `scripts/run-spec.sh` と `scripts/run-code.sh` に pre/post カウント比較 + fallback 呼び出しを追加 (→ AC1)
   - claude 呼び出し前: `PRE_COUNT=$(grep -c "^## Consumed Comments" "$(ls "$SPEC_DIR/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1)" 2>/dev/null || echo 0)`
   - claude 終了後 (EXIT_CODE=0 時): `POST_COUNT=$(...)` で再計算
   - `[[ "$POST_COUNT" -le "$PRE_COUNT" ]]` の場合: `_append_consumed_comments_section "$ISSUE_NUMBER" "spec"` (または "code") を呼び出す
   - SPEC_DIR は `scripts/get-config-value.sh spec-path docs/spec` で取得 (既存パターン踏襲)

3. `modules/l0-surfaces.md` Step 5 と `skills/verify/SKILL.md` Step 1 を更新 (→ AC1, AC2)
   - l0-surfaces.md Step 5 に: "Bash wrapper fallback: `/spec`/`/code` フェーズは `run-*.sh` の post-processor が `append-consumed-comments-section.sh` でフォールバック保証。`/verify` フェーズは SKILL.md の明示 bash 呼び出しで保証。" を追記
   - verify SKILL.md: Comment Consumption 手順の最後に明示 bash step を追加: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh $NUMBER verify`
   - verify SKILL.md frontmatter allowed-tools に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` を追加

4. `tests/run-spec.bats`, `tests/run-code.bats` にテストを追加、`tests/run-verify.bats` を新規作成 (→ AC3)
   - run-spec.bats: emit-event.sh モックに `_append_consumed_comments_section()` を追加; Spec ファイルへのセクション追記なし (カウント不変) → fallback 呼ばれる; セクション追記あり (カウント増加) → fallback 呼ばれない
   - run-code.bats: 同様パターン
   - run-verify.bats: `scripts/append-consumed-comments-section.sh` を直接 bats でテスト。gh/git をモック。test: Spec 不在 → skeleton + section 作成; section 既存 → skip (exit 0, no git commit); verify-fail marker コメントあり → 記録される
   - WHOLEWORK_SCRIPT_DIR モックパターン踏襲 (既存 bats テストと同一構造)

5. `docs/structure.md` および `docs/ja/structure.md` を更新 (→ doc)
   - scripts/ ファイル数を 58 → 59 に更新
   - Scripts セクションの **Process management** か適切な場所に `append-consumed-comments-section.sh` のエントリを追加

## Verification

### Pre-merge

- <!-- verify: rubric "候補 A/B/C のいずれかを採用した実装が `scripts/` または `modules/l0-surfaces.md` または各 `run-*.sh` に反映されており、parent /auto 単一 Issue path および fix-cycle path でも Spec への `## Consumed Comments` セクション追記が確実に発火する仕様になっている" --> Spec writeback の確実な発火が実装されている
- <!-- verify: rubric "実装内容 (採用した候補 A/B/C と理由) が docs/spec/issue-811-consumed-comments-bash-fallback.md に記録され、tradeoff 比較が残されている" --> 設計判断が Spec に記録されている
- <!-- verify: command "bats tests/run-code.bats tests/run-spec.bats tests/run-verify.bats" --> 関連 bats テストが green (新規 spec writeback テスト追加含む)

### Post-merge

- 次回 fix-cycle 経由の `/auto N` または通常の `/spec N` / `/code N` 実行時に、Spec ファイルに `## Consumed Comments` セクションが追記され、cutoff 以降の comment (verify-fail marker 含む) が記録されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- **Candidate B 採用理由**: LLM 版の品質を保ちつつ、silent skip の防止に最小コストで対応できる。pre/post カウント比較は bash 組み込みパターン (`grep -c`) で実装可能で複雑さが低い
- **`/verify` 向け設計**: in-session 実行かつ worktree なしのため、`append-consumed-comments-section.sh` が直接 main ブランチへ commit + push する。verify SKILL.md への明示 bash call 追加は "LLM が Bash ツール呼び出しを行う" ことで信頼性を向上させる (pure prose より高信頼)
- **スクリプト count drift**: `docs/structure.md` の現行値 "58 files" は実際の 60 files (scripts/*.sh + scripts/*.py) と乖離しているが、本 Issue での更新は +1 (59 → ドキュメント値基準) で対応する。drift 修正は別 Issue
- **`tests/run-verify.bats` 名について**: `run-verify.sh` は存在しないが、`append-consumed-comments-section.sh` の verify フェーズ固有動作 (verify-fail marker 処理など) をテストする意図でこのファイル名を使用する
- **`section 既存 → skip` ロジック**: `append-consumed-comments-section.sh` は `grep -q "^## Consumed Comments"` で既存チェック。複数フェーズでセクションが積み重なる場合、post-processor は 1 呼び出しにつき 1 回のみ追記するシンプル設計。重複防止は run-*.sh の pre/post カウント比較に依存
- **git commit sign-off**: `git commit -s` を使用して DCO sign-off を付与 (既存 `_write_tier2_recovery_to_spec` パターン踏襲)
- **`docs/ja/structure.md` 更新**: Japanese format の verify command に `## Consumed Comments` パターンは含まれないため format 影響なし

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- SHOULD issue 1 件 (`$NUMBER` 引用符不在 in skills/verify/SKILL.md) を修正してプッシュ済み
- MUST issues なし → REQUEST_CHANGES ではなく COMMENT イベントでレビュー投稿
- Candidate B 実装の全 3 フェーズ (spec/code/verify) 網羅を確認、受け入れ条件 3 件すべて PASS

### Deferred Items
- Post-merge observation AC (次回 /auto または /spec N 実行時の Spec ファイルへの Consumed Comments セクション追記確認) は merge 後の観察タスク
- `docs/structure.md` スクリプトカウント drift 修正は別 Issue で対応予定

### Notes for Next Phase
- 修正コミット (912423e) がプッシュ済み、CI が通過すれば `/merge 813` で完了
- `validate-skill-syntax.py` の既存警告 (`loop-paths-fallback` 未知フィールド) は本 PR と無関係なので無視してよい

## review retrospective

### Spec vs. 実装の乖離パターン

特筆すべき構造的乖離なし。Candidate B の実装は Spec の設計意図に忠実で、3 フェーズ (spec/code/verify) の網羅が確認できた。

### 繰り返しパターン (ワークフロー改善の余地)

`skills/verify/SKILL.md` の bash call に `$NUMBER` の引用符不在 (SHOULD) を検出。SKILL.md 内の bash スニペットは手書き prose 混在のため変数引用符漏れが起きやすい。Spec に verify command を追記する際のテンプレートチェックリストで「変数は必ず `"$VAR"` 形式」を明記すると同種のパターンを予防できる。

### 受け入れ条件検証の難易度

- `rubric` 条件 2 件とも PASS が AI 判定で確認できた (安定)
- `command "bats ..."` は CI リファレンスフォールバックで PASS (local 実行不要)
- UNCERTAIN 発生なし、verify command 品質は良好

## Code Retrospective

### 実装サマリ

Candidate B (post-processor fallback) を採用した。`scripts/append-consumed-comments-section.sh` を新規作成し、`run-spec.sh` / `run-code.sh` に pre/post カウント比較ロジックを追加。`skills/verify/SKILL.md` には明示 bash call を追加して 3 フェーズ全てを網羅した。

### 発見した技術的問題

**`grep -c ... || echo 0` パターンのバグ**: `grep -c` はマッチなし時に `0` を stdout に出力して exit 1 する。`|| echo 0` を続けると command substitution が両方の出力を捕捉して `"0\n0"` を返し、`[[ "$count" -le 0 ]]` の整数比較が破綻してフォールバックが発火しない。修正: `|| true` に変更し `${COUNT:-0}` でデフォルト設定する形に統一。

**git モックの引数位置ミス** (tests/run-verify.bats): `git -C /repo/path diff --quiet` の呼び出しで `$2` はパス、`$3` が `"diff"` になる。当初モックは `$2 == "diff"` を確認していたため diff 検出が機能せず test 68 が失敗。`$3 == "diff"` に修正。

### テスト結果

- 68 テスト全グリーン (run-code.bats, run-spec.bats, run-verify.bats)
- 追加テスト: fallback 呼ばれる (2) + fallback 呼ばれない (2) + verify 動作 (6) = 計 10 新規テスト

### PR

https://github.com/saitoco/wholework/pull/813
