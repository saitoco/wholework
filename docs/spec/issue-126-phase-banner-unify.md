# Issue #126: banner: フェーズバナーの全層統一

## Overview

フェーズバナーのフォーマットを SKILL.md 層と Shell 層で統一する。`---` 区切りとプレフィックス（`Issue:`/`URL:`）を除去し、`/SKILL_NAME #N` 形式に統一。`/auto` に完了バナーとフェーズ遷移フォーマットを追加。

## Changed Files

- `modules/phase-banner.md`: change banner format from `--- /SKILL_NAME #N ---` to `/SKILL_NAME #N`, update Notes section (2-layer design → unified format)
- `scripts/phase-banner.sh`: add `skill_name` parameter to `print_start_banner`/`print_end_banner`, change output from `${label}: #N TITLE\nURL: URL` to `/${skill_name} #N\nTITLE\nURL`
- `scripts/run-code.sh`: add `"code"` third argument to `print_start_banner` (line 51) and `print_end_banner` (line 118)
- `scripts/run-spec.sh`: add `"spec"` third argument to `print_start_banner` (line 35) and `print_end_banner` (line 75)
- `scripts/run-issue.sh`: add `"issue"` third argument to `print_start_banner` (line 26) and `print_end_banner` (line 70)
- `scripts/run-review.sh`: add `"review"` third argument to `print_start_banner` (line 20) and `print_end_banner` (line 67)
- `scripts/run-merge.sh`: add `"merge"` third argument to `print_start_banner` (line 18) and `print_end_banner` (line 59)
- `scripts/run-verify.sh`: add `"verify"` third argument to `print_start_banner` (line 39) and `print_end_banner` (line 98)
- `scripts/run-auto-sub.sh`: add `"auto"` third argument to `print_start_banner` (line 92) and `print_end_banner` (line 199)
- `skills/auto/SKILL.md`: add completion banner format and phase transition format `[N/M]` to Steps 4 and 5
- `tests/phase-banner.bats`: new file — tests for updated `phase-banner.sh`

## Implementation Steps

**Step recording rules:**
- **Dependencies**: "(after N)" for sequential, "(parallel with N)" for parallel-safe
- **Acceptance criteria mapping**: "(→ AC X)" per step

1. Update `scripts/phase-banner.sh` to accept `skill_name` as third parameter and change output format (→ AC 3, 4, 5)
   - `print_start_banner`: change signature from `(entity_type, entity_number)` to `(entity_type, entity_number, skill_name)`
   - Remove `local label; [[ "$entity_type" == "pr" ]] && label="PR" || label="Issue"` line
   - Change output from `echo "${label}: #${entity_number} ${_ENTITY_TITLE}"` + `echo "URL: ${_ENTITY_URL}"` to `echo "/${skill_name} #${entity_number}"` + `echo "${_ENTITY_TITLE}"` + `echo "${_ENTITY_URL}"`
   - Apply same changes to `print_end_banner`
   - `_fetch_entity_info` signature unchanged (still uses entity_type for gh command selection)

2. Update `modules/phase-banner.md` banner format spec (parallel with 1) (→ AC 1, 2)
   - Processing Steps section: change code fence from `--- /SKILL_NAME #N ---\nTITLE\nURL\n---` to `/SKILL_NAME #N\nTITLE\nURL`
   - Notes section: update "intentional 2-layer design" text to reflect unified format. State both SKILL.md and Shell layers now use the same `/SKILL_NAME #N` format. Remove the old shell format example (`Issue: #N TITLE\nURL: URL`)

3. Update all 7 `run-*.sh` scripts to pass `skill_name` as third argument (after 1) (→ AC 9)
   - Call site pattern (exhaustive):

   | Script | Entity type | Skill name | Lines (start/end) |
   |--------|-------------|------------|-------------------|
   | `run-code.sh` | `"issue"` | `"code"` | 51, 118 |
   | `run-spec.sh` | `"issue"` | `"spec"` | 35, 75 |
   | `run-issue.sh` | `"issue"` | `"issue"` | 26, 70 |
   | `run-review.sh` | `"pr"` | `"review"` | 20, 67 |
   | `run-merge.sh` | `"pr"` | `"merge"` | 18, 59 |
   | `run-verify.sh` | `"issue"` | `"verify"` | 39, 98 |
   | `run-auto-sub.sh` | `"issue"` | `"auto"` | 92, 199 |

4. Update `skills/auto/SKILL.md` Step 4 and Step 5 (parallel with 1, 2, 3) (→ AC 6, 7)
   - Step 4 (pr route section): add phase transition output format description:
     - Before each `run-*.sh` call: output `[N/M] phase_name`
     - After each successful `run-*.sh`: output `[N/M] phase_name → done (details)`
     - Format: `[1/4] code` → (run) → `[1/4] code → done (PR #N)`
   - Step 5 (Completion Report): add completion banner format:
     ```
     /auto #N complete
     TITLE
     URL
     ```
     Followed by result table
   - Step 6 (On Failure): add stopped banner format:
     ```
     /auto #N stopped at PHASE
     TITLE
     URL
     ```
     Followed by result table (with `-` for unexecuted phases)

5. Create `tests/phase-banner.bats` (after 1) (→ AC 8)
   - Test `print_start_banner` outputs `/{skill_name} #{number}` format
   - Test `print_end_banner` outputs same format
   - Test that `_fetch_entity_info` is called correctly (mock gh command)
   - Test backward compatibility: missing third argument should not error (default to empty or graceful fallback)

## Verification

### Pre-merge

- <!-- verify: section_not_contains "modules/phase-banner.md" "## Processing Steps" "---" --> `modules/phase-banner.md` のバナーフォーマットから `---` 区切りが除去されている
- <!-- verify: grep "SKILL_NAME #" "modules/phase-banner.md" --> `modules/phase-banner.md` のバナーフォーマットが `/SKILL_NAME #N` 形式になっている
- <!-- verify: file_not_contains "scripts/phase-banner.sh" "label=\"Issue\"" --> `scripts/phase-banner.sh` から旧 entity-type ベースのラベル生成パターンが除去されている
- <!-- verify: file_not_contains "scripts/phase-banner.sh" "URL:" --> `scripts/phase-banner.sh` から `URL:` プレフィックスが除去されている
- <!-- verify: grep "skill_name" "scripts/phase-banner.sh" --> `scripts/phase-banner.sh` がスキル名を受け取りバナーに含める
- <!-- verify: grep "auto.*complete" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` に完了バナーフォーマットが定義されている
- <!-- verify: grep "\\[1/" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` にフェーズ遷移フォーマット `[N/M]` が定義されている
- <!-- verify: command "bats tests/phase-banner.bats" --> phase-banner.sh の bats テストが PASS する
- <!-- verify: grep 'print_start_banner.*"code"' "scripts/run-code.sh" --> run-*.sh でスキル名引数が追加されている（代表: run-code.sh）

### Post-merge

- `/auto` 実行時にフェーズ遷移が `[N/M] phase → done` 形式で表示される (verify-type: opportunistic)

## Notes

- `run-auto-sub.sh` 内のフェーズマーカー（`echo "--- spec phase: issue #N ---"` 等）はバナーフォーマットとは異なる機能（フェーズ開始通知）のため今回のスコープ外
- run-*.sh 内の `echo "---"` セパレータ行はメタデータと `claude -p` 出力の視覚的区切りとして保持
- `_fetch_entity_info` は `entity_type` を使って `gh issue view` と `gh pr view` を切り替える。`skill_name` は出力フォーマットのみに使用され、API 呼び出しには影響しない
- `print_start_banner`/`print_end_banner` の第3引数が未指定の場合のフォールバック: `local skill_name="${3:-}"` で空文字列にフォールバックし、出力は `/ #N` 形式になる（エラーにはならない）
- bats テストでは `gh` コマンドをモック関数で置換して API 呼び出しを回避する

### Auto-resolved ambiguity points (from /issue)

- `print_end_banner` も同一フォーマットで統一（start と同じ `/{skill_name} #N` 出力）
- `run-auto-sub.sh` のスキル名は `"auto"`（子オーケストレーター全体のバナー）
- フェーズ遷移 `[N/M]` は `/auto` オーケストレーター出力のみ（run-*.sh 内には追加しない）

## issue retrospective

### Ambiguity Resolution

5 点の曖昧性を全て自動解決:

1. **run-*.sh verify command 不足**: 代表的な `run-code.sh` の verify command 追加で対応
2. **verify command false positive**: `file_not_contains "Issue:"` が現コードでリテラル不在のため常に PASS → `file_not_contains 'label="Issue"'` に修正
3. **`print_end_banner` 統一**: `print_start_banner` と同一フォーマットで統一
4. **`run-auto-sub.sh` フェーズマーカー**: バナーとは異なる機能、スコープ外
5. **`echo "---"` セパレータ**: バナーの `---` とは異なる視覚的区切り、保持

### Key Decisions

- false positive 検出: `file_not_contains` の対象文字列がソースコードに存在しない場合を verify-patterns.md のガイドラインに照らして修正
- スコープ制限: `run-auto-sub.sh` のフェーズマーカーや `echo "---"` セパレータはバナーフォーマットとは機能的に異なるため除外

## Code Retrospective

### Deviations from Design

- bats テストの `gh` モックを関数エクスポート方式から `_fetch_entity_info` 直接モック方式に変更。Spec では `gh` コマンドをモック関数で置換すると記載されていたが、`gh issue view N --json title -q '.title'` の引数パターンとモック関数の実装がずれ、テスト1-2が失敗した。`_fetch_entity_info` を直接モックする方式が正確で簡潔なため採用。

### Design Gaps/Ambiguities

- N/A

### Rework

- `tests/phase-banner.bats`: 初回実装時に `gh` モック関数の引数マッチングが誤っており、テスト1-2が失敗。`_fetch_entity_info` を直接モックする方式に修正して解決（1回のリワーク）。

## spec retrospective

### Minor observations
- `phase-banner.sh` の `label="Issue"` / `label="PR"` は verify command の false positive を生む形式だった。動的文字列生成パターンの verify command 設計時は、ソースコードのリテラル文字列とランタイム出力文字列を区別して検証対象を選ぶ必要がある

### Judgment rationale
- `run-auto-sub.sh` のフェーズマーカー（`echo "--- spec phase: issue #N ---"` 等）をスコープ外とした理由: これらはバナー（Issue/PR 識別）とは異なるフェーズ開始通知の機能。統一すると `run-auto-sub.sh` 内の case 分岐でフェーズ番号 N/M の計算が必要になりスコープが膨らむ
- `echo "---"` セパレータ保持の理由: `claude -p` の出力がバナー直後に続くため、メタデータとの視覚的境界が必要

### Uncertainty resolution
- Nothing to note
