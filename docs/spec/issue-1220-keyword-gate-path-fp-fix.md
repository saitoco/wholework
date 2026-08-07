# Issue #1220: observation-trigger: keyword= フィルタのファイル名部分一致誤検知を解消

## Overview

`scripts/opportunistic-search.sh` の `keyword=` Condition Check Gate は `grep -qi -- "$KEYWORD" "$CONTEXT_FILE"` による単純な大小文字非区別の部分文字列マッチで実装されており、キーワードがファイルパス文字列の一部として偶然出現した場合 (例: `keyword=workflow` が `docs/workflow.md` というパス表記に部分一致) にトピック非関連の PR に対しても誤発火する。本 Issue はこの誤検知を抑制し、意図した「トピック関連性」判定に近づける。

## Reproduction Steps

1. Issue に `<!-- verify-type: observation event=pr-review-full keyword=workflow -->` 形式の post-merge AC が存在する (例: Issue #476)
2. `--context-file` に渡される Spec/diff コンテキストファイルが、GitHub Actions ワークフローとは無関係な `` `docs/workflow.md` `` のようなファイルパス列挙を含む (実例: PR #1218, `docs/spec/issue-1082-worktree-commits-found-hint.md` L26)
3. `scripts/opportunistic-search.sh --event pr-review-full --context-file <path>` が `grep -qi -- "workflow" <path>` を実行し、パス文字列内の部分一致でゲートを通過してしまう
4. 該当 observation AC が誤発火し、`/verify` が dispatch されるが該当欠陥なしのため UNCERTAIN に終わる (compute burn のみ発生)

## Root Cause

`scripts/opportunistic-search.sh` L234-241 の `keyword=` ゲート実装が、`$CONTEXT_FILE` の全文に対する素朴な大小文字非区別の部分文字列マッチ (`grep -qi -- "$KEYWORD" "$CONTEXT_FILE"`) のみに依存しており、キーワードが意味のある文脈で出現したのか、無関係なファイルパス文字列の断片として出現したのかを区別していない。

なお、素朴な単語境界マッチ (`grep -qiw`) では本件は解消しないことを実機検証済み: 正規表現の `\b` は `/` と `.` を非単語文字として扱うため、`docs/workflow.md` 内の `workflow` は `/` と `.` に挟まれた時点で既に `\bworkflow\b` の単語境界条件を満たしてしまう (`echo "docs/workflow.md" | grep -qiw "workflow"` は一致する)。

## Changed Files

- `scripts/opportunistic-search.sh`: `keyword=` ゲート (L234-241 付近) を変更し、マッチ前に `$CONTEXT_FILE` の内容からパス様トークンを除去する処理を追加。bash 3.2+ 互換 (`sed -E` を使用。本リポジトリでは `scripts/get-config-value.sh`・`scripts/hook-rename-on-auto.sh` 等で既に使われている確立済みパターン)
- `modules/observation-trigger.md`: § Condition Check Gate (`keyword=`) の導入段落 (L187-191 付近) と「Matching specification」の Comparison 箇条書き (L202 付近) を、パス様トークン除去の挙動を記述するように更新。Issue #1220 を根拠として引用する短い補足段落を追加
- `tests/opportunistic-search.bats`: 既存の「context gate」テスト群 (L221-283 付近) に隣接する形で 2 件の `@test` を追加 — (a) パス様トークン内にのみキーワードが出現するケースは除外される、(b) 地の文にキーワードが出現するケースは除外されない (過剰除去の回帰防止)

## Implementation Steps

1. `scripts/opportunistic-search.sh` の `keyword=` ゲート (既存の `if ! grep -qi -- "$KEYWORD" "$CONTEXT_FILE"; then` 判定、L239 付近) を変更する。`resolve_run_facts()` (同ファイル内、`when=` ゲート向けに既に実装されているプロセス内 1 回だけの遅延キャッシュパターン) に倣い、`resolve_filtered_context()` という関数を新設して `$CONTEXT_FILE` の内容から**パス様トークン** (`[A-Za-z0-9._-]` 文字の連続で `/` を 1 個以上含むもの。例: `docs/workflow.md`, `scripts/opportunistic-search.sh`, `.github/workflows/ci.yml`) を `sed -E 's#[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+##g'` で除去し `FILTERED_CONTEXT` にキャッシュする。ゲート判定は `echo "$FILTERED_CONTEXT" | grep -qi -- "$KEYWORD"` に変更する (→ 受け入れ基準1)
2. `modules/observation-trigger.md` § Condition Check Gate (`keyword=`) を更新する (after 1)。導入段落 (L187-191 付近) に「path-like tokens stripped first」への言及を追加し、`docs/workflow.md` の実例と Issue #1220 を引用する短い補足段落 (見出し例: "Path-like token exclusion (Issue #1220)") を挿入する。「Matching specification」の Comparison 箇条書き (L202 付近) を実装後のコマンド (`sed -E '...' "$CONTEXT_FILE" | grep -qi -- "$KEYWORD"`) に一致させて書き換える。改訂後のセクション本文に **`token` という語を含める** こと (検証項目3で機械チェックされる) (→ 受け入れ基準2)
3. `tests/opportunistic-search.bats` の既存「context gate」テスト群 (L221-283 付近) に隣接して `@test` を2件追加する (after 1)。テスト形式は既存の `context gate: keyword found/absent...` に倣う: `MOCK_ISSUE_BODY_<N>` に `- [ ] ... <!-- verify-type: observation event=pr-review-full keyword=workflow -->` 形式の1行を設定し、`echo "..." > "$BATS_TEST_TMPDIR/<name>.md"` でコンテキストファイルを作成し、`run bash "$SCRIPT" --event pr-review-full --context-file "$BATS_TEST_TMPDIR/<name>.md"` を実行して `$output` を `jq -e` で検証する。(a) コンテキストファイルの内容が `` `docs/workflow.md` `` のようなパス表記のみで地の文の言及がない場合、結果が `[]` になることを確認するテスト。(b) コンテキストファイルの内容が "This PR changes the CI workflow configuration." のような地の文の場合、Issue が結果に含まれることを確認するテスト (過剰除去がないことの回帰防止) (→ 受け入れ基準1)

## Verification

### Pre-merge
- <!-- verify: rubric "scripts/opportunistic-search.sh の keyword= ゲート実装が、単純な grep -qi 部分文字列マッチのみに依存しない誤検知抑制策 (例: ファイルパス文字列除外、単語境界マッチ、対象拡張子ベースの構造化マッチ等) を含んでいる" --> keyword= ゲートの誤検知抑制策が実装されている
- <!-- verify: rubric "modules/observation-trigger.md § Condition Check Gate (keyword=) の説明が、単純な grep -qi 部分文字列マッチのみに依存しない誤検知抑制策の挙動を正確に記述している" --> `modules/observation-trigger.md` § Condition Check Gate (`keyword=`) の説明が改善後の挙動と整合している
- <!-- verify: section_contains "modules/observation-trigger.md" "keyword=" "token" --> §Condition Check Gate (`keyword=`) セクションに誤検知抑制策の記述 (`token` を含む) が反映されている (rubric の機械的補助チェック)

### Post-merge
- 次回 `docs/workflow.md` 等、キーワードを含むが無関係なファイルパスのみを参照する PR の `/review --light` 完了時に、該当 `keyword=` ゲート付き observation AC が誤発火しないことを観察

## Notes

- **AC3 (補助チェック) の差し替え経緯**: Consumed Comments (2026-08-07T10:10:11Z、`/issue` Existing Issue Refinement Step 15 の AC Verify Command Integrity Audit コメント) が、Issue 本文 AC3 の verify command `grep -i "keyword" "modules/observation-trigger.md"` は対象セクションの見出し自体に既に "keyword" という語が多数出現するため常時 PASS になる (Pattern 2: 常時 PASS な verify command) と指摘した。本 Spec 作成時点で `modules/observation-trigger.md` § Condition Check Gate (`keyword=`) 該当区間 (L174-208) を実測した結果、"token" / "slash" / "strip" / "embedded" はいずれも出現数 0 件であることを確認した。`modules/verify-patterns.md` §9 の「rubric + 補助 section_contains」推奨パターン (`section_contains "path" "heading" "text"`) に従い、`section_contains "modules/observation-trigger.md" "keyword=" "token"` へ差し替えた。この差し替えは Issue 本文にも反映済み (本 Spec 作成時に `gh-issue-edit.sh` で更新)
- **単語境界マッチが不十分であることの実機検証**: `echo "docs/workflow.md" | grep -qiw "workflow"` は一致する (BSD grep 2.6.0-FreeBSD、macOS システム標準 `/usr/bin/grep` で確認)。正規表現の `\b` は `/` `.` を非単語文字として扱うため、パス区切り文字に挟まれた語も単語境界条件を満たしてしまう。この理由により、本 Issue の AC1 rubric が提示する3候補 (ファイルパス文字列除外/単語境界マッチ/構造化マッチ) のうち「ファイルパス文字列除外」系統 (パス様トークンの事前除去) を採用した
- **移植性確認**: `scripts/opportunistic-search.sh` は `#!/bin/bash` で実行され、対話シェルの `grep`/`ugrep` ラッパー関数とは独立して macOS システム標準の `/usr/bin/grep`・`/usr/bin/sed` (いずれも BSD 版) を解決することを実機確認した。`sed -E` は本リポジトリの既存スクリプト (`scripts/get-config-value.sh`, `scripts/collect-recovery-candidates.sh`, `scripts/hook-rename-on-auto.sh`, `scripts/hook-worktree-path-guard.sh`) で既に使われている確立済みパターンであり、新規の外部依存は発生しない
- **UI Design Phase**: 本 Issue はバックエンド/CLI スクリプトの内部マッチングロジック修正であり、インタラクティブ UI コンポーネントを含まないため、`skills/spec/figma-design-phase.md` の Auto-detection Criteria により「UI design not needed」と判定した (UI Design セクションは省略)
- **`config=` / `when=` ゲートとの関係**: 同スクリプト内の `config=` ゲート (`.wholework.yml` キー解決) と `when=` ゲート (run facts JSON の enum 一致) は元々列挙値に対する構造化マッチであり、本 Issue の対象である自由テキスト部分文字列マッチ (`keyword=`) とは性質が異なる。今回の修正は `keyword=` ゲートのみを対象とし、他二つのゲートには変更を加えない

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの retrospective — 曖昧性検出なし、AC2 の verify command を rubric + 補助チェックパターンへ変更した経緯を記録 — https://github.com/saitoco/wholework/issues/1220#issuecomment-5215669688
- saito / MEMBER / first-class / AC3 の verify command (`grep -i "keyword" ...`) が既存ドキュメント中に "keyword" が多数出現するため常時 PASS になるという監査指摘。代表語の差し替えまたは補助チェック削除を提案 — 本 Spec で `section_contains` + `token` へ差し替えて対応 (Notes 参照) — https://github.com/saitoco/wholework/issues/1220#issuecomment-5215691447
