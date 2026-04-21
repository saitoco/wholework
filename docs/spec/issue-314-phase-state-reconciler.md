# Issue #314: auto: state reconciler と precondition チェックを各 phase に導入

## Overview

`/auto` の全 phase で wrapper exit code に依らず実状態を検査する共通 reconciler を導入する。既存 `scripts/watchdog-reconcile.sh` の phase 別 success signature テーブル（#243 SSoT）を `modules/phase-state.md` に移譲し、precondition + completion 双方の検査をサポートする `scripts/reconcile-phase-state.sh` に発展させる。

本 Issue は **foundation**: #316 (recovery sub-agent)、#317 (checkpoint/resume)、#319 (run-auto-sub.sh adaptive hook) が本 Issue の state snapshot JSON schema に依存。下流 cascade 修正を防ぐため schema を `schema_version: "v1"` で固定化する。

recover scope は最小限（label 同期 / skip to completed phase のみ）に限定し、catalog lookup は #315、sub-agent recovery は #316、bash-level tier 3 は #319 に明示的に委譲。precondition fail-fast は gh API eventual consistency 対策として **`--warn-only` デフォルトで段階導入**し、運用 2 週間以上を経て `--strict` 昇格を判断する。

## Changed Files

**New (3):**
- `modules/phase-state.md`: SSoT module — phase 別 precondition/success signature 表 + JSON schema (v1) 定義。`type: steering` frontmatter 付き
- `scripts/reconcile-phase-state.sh`: 共通 helper — `watchdog-reconcile.sh` の phase dispatcher を汎化し、`--check-precondition` / `--check-completion` / `--strict` / `--warn-only` フラグをサポート。bash 3.2+ 互換
- `tests/reconcile-phase-state.bats`: 既存 `watchdog-reconcile.bats` の 32 ケースを意味単位で移植 + precondition テスト + JSON schema テスト + `--strict`/`--warn-only` テストを追加（推定 45 ケース）。bash 3.2+ 互換

**Update (9):**
- `skills/auto/SKILL.md`: change Step 4 を Observe-Diagnose-Act 構造に再構成（precondition check → phase 実行 → completion check）、allowed-tools frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*` 追加
- `scripts/run-issue.sh`: change line 82 の `watchdog-reconcile.sh issue` を `reconcile-phase-state.sh issue --check-completion` に置換 — bash 3.2+ 互換
- `scripts/run-spec.sh`: change line 94 の置換 — bash 3.2+ 互換
- `scripts/run-code.sh`: change line 163 の `$_RECONCILE_PHASE` 分岐維持のまま置換 — bash 3.2+ 互換
- `scripts/run-review.sh`: change line 86 の `--pr $PR_NUMBER` を含む置換 — bash 3.2+ 互換
- `scripts/run-merge.sh`: change line 77 の置換 — bash 3.2+ 互換
- `scripts/run-verify.sh`: change line 118 の置換 — bash 3.2+ 互換
- `docs/structure.md`: change Scripts > Process management の `watchdog-reconcile.sh` 行を `reconcile-phase-state.sh` に置換
- `docs/ja/structure.md`: change 翻訳同期
- `.github/workflows/test.yml`: add CI grep-gate（`grep -r watchdog-reconcile scripts/ && exit 1` を validate-syntax job 前後に追加）

**Delete (2):**
- `scripts/watchdog-reconcile.sh`: delete
- `tests/watchdog-reconcile.bats`: delete

合計 14 ファイル（新設 3、更新 9、削除 2）。docs/tech.md は `claude -p` CLI フラグ変更に該当しないため更新不要（AD 確認済）。

## Implementation Steps

**Step recording rules:**
- Step 番号は整数のみ
- 各 Step に対応する Acceptance Criteria を記載

1. **`modules/phase-state.md` 新設** (parallel with 2) (→ AC1, AC7)
   - YAML frontmatter: `type: steering`, `ssot_for: [phase-signatures, reconcile-json-schema]`
   - 4-section 標準構造: Purpose / Input / Processing Steps / Output
   - Phase 表 (Precondition + Success Signature): `issue / spec / code-patch / code-pr / review / merge / verify` の 7 phase を `watchdog-reconcile.sh` から移植
   - JSON schema v1 定義 (Output format):
     ```json
     {
       "schema_version": "v1",
       "phase": "<phase-name>",
       "matches_expected": true|false,
       "actual": { "labels": [...], "pr_state": "...", "pr_number": N, "commits_found": bool, "spec_file": "...", "issue_state": "OPEN|CLOSED" },
       "diagnosis": "..."
     }
     ```
   - "Actual State Inspection" と "Precondition Inspection" の 2 モードを Processing Steps に記載

2. **`scripts/reconcile-phase-state.sh` 新設** (parallel with 1) (→ AC2, AC7)
   - CLI: `<phase> <issue-number> [--check-precondition | --check-completion] [--pr <pr-number>] [--strict | --warn-only]`
   - `watchdog-reconcile.sh` の `_reconcile_<phase>` 関数群を `_completion_<phase>` として移植
   - 新規関数 `_precondition_<phase>` を 7 phase 分実装:
     - `issue`: Issue exists and not CLOSED (`gh issue view --json state`)
     - `spec`: `phase/issue` or `phase/spec` label、Spec file 不在 or 上書き許可
     - `code-patch` / `code-pr`: `phase/ready` label、Spec 存在、open PR unique
     - `review`: PR exists、CI green or pending
     - `merge`: PR approved、CI green、no conflict
     - `verify`: merge commit on main、Issue CLOSED or `phase/verify`
   - Output: stdout に JSON (schema v1)、exit code `0`/`1`/`2` (Issue body 指定通り)
   - `--warn-only` (default): 不整合でも exit 0 + stderr warning
   - `--strict`: 不整合で exit 1
   - Stage 2 recovery (push+PR 作成) は削除 (#316 sub-agent へ委譲の旨 stderr comment に記載)
   - bash 3.2+ 互換: `declare -A` / `mapfile` 禁止、`case` + 関数 dispatcher で統一

3. **`tests/reconcile-phase-state.bats` 新設** (after 2) (→ AC3, AC6)
   - `watchdog-reconcile.bats` 32 ケースを意味単位で移植（既存 `_reconcile_<phase>` → `_completion_<phase>` への rename に追従）
   - 新規: `_precondition_<phase>` 7 phase 分のテスト (14 ケース: PASS/FAIL 各 1)
   - 新規: JSON schema 出力テスト (2 ケース: 全キー存在、schema_version 固定)
   - 新規: `--strict` vs `--warn-only` 挙動差テスト (2 ケース)
   - 新規: phase 別 precondition と completion を同一 fixture で比較するテスト (2 ケース)
   - 合計推定 52 ケース。`setup()` は既存 `watchdog-reconcile.bats` の mock パターン (gh / get-config-value.sh のモック生成) を流用
   - bash 3.2+ 互換、`$BATS_TEST_TMPDIR` で per-test 独立

4. **`skills/auto/SKILL.md` Step 4 再構成** (after 2) (→ AC8)
   - 既存 Step 4 の各 phase (code/review/merge/verify) 呼び出しを下記 pattern に変更:
     ```
     [N/M] phase_name
       1. ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh <phase> <issue> --check-precondition --warn-only
          - 不整合は stderr 警告出力のみ、実行継続（段階導入初期）
       2. Run <run-*.sh> ...
       3. ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh <phase> <issue> --check-completion
          - exit 0 (completed) なら続行、exit 1 (mismatch) なら既存 on-failure flow
     ```
   - 全 phase 対称に precondition / completion 呼び出し（#132 教訓: 非対称 guard は drift の原因）
   - allowed-tools frontmatter (line 4) に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*` を `detect-wrapper-anomaly.sh` の直後に挿入
   - patch route / pr route / XL route すべてに対称配置

5. **6 本の `scripts/run-*.sh` 一括更新** (after 2) (→ AC9)
   - `run-issue.sh:82`: `watchdog-reconcile.sh issue $ISSUE_NUMBER` → `reconcile-phase-state.sh issue $ISSUE_NUMBER --check-completion`
   - `run-spec.sh:94`: 同様の置換 (spec phase)
   - `run-code.sh:163`: `$_RECONCILE_PHASE` 分岐を維持 (code-patch/code-pr)、`--check-completion` 追加
   - `run-review.sh:86`: `--pr $PR_NUMBER` を含む置換 (review phase)
   - `run-merge.sh:77`: `--pr $PR_NUMBER` を含む置換 (merge phase)
   - `run-verify.sh:118`: 置換 (verify phase)
   - exit 143 分岐自体は維持、内部の `watchdog-reconcile.sh` 呼び出しだけを `reconcile-phase-state.sh` に置換 (呼び出し契約は同じ)
   - bash 3.2+ 互換性を維持

6. **`scripts/watchdog-reconcile.sh` + `tests/watchdog-reconcile.bats` 削除** (after 5) (→ AC4, AC5)
   - `git rm scripts/watchdog-reconcile.sh tests/watchdog-reconcile.bats`
   - 削除前に Step 5 の置換漏れを `grep -r watchdog-reconcile scripts/` で確認

7. **`.github/workflows/test.yml` CI grep-gate 追加** (after 6)
   - 既存の validate-syntax job に続くステップとして追加:
     ```yaml
     - name: Detect residual watchdog-reconcile references
       run: |
         if grep -r watchdog-reconcile scripts/; then
           echo "Residual watchdog-reconcile reference found"; exit 1
         fi
     ```
   - 置換漏れが今後発生しても CI で永続的に検出

8. **`docs/structure.md` + `docs/ja/structure.md` 更新** (parallel with 1)
   - `docs/structure.md` Scripts > Process management セクション:
     - `scripts/watchdog-reconcile.sh` 行を削除
     - `scripts/reconcile-phase-state.sh` 行を追加 (`— general-purpose state reconciler for precondition and completion checks across all phases (supersedes watchdog-reconcile.sh)`)
   - `docs/ja/structure.md` 同様の翻訳同期更新

9. **Self-review (完了前の内部整合性チェック)**
   - `tests/reconcile-phase-state.bats` で期待される `@test` 名パターンを予め grep で確認し、verify command の `command` hint が正確にテスト実行を指すことを確認
   - Changed Files と Implementation Steps の対応確認
   - AC (pre-merge 9 件) と Implementation Steps (9 件) の 1:1 マッピング確認

## Alternatives Considered

### 採用: 完全置換 (watchdog-reconcile.sh 削除 + 新 helper)

- メリット: single responsibility、code path が simple、将来の拡張（#316/#317/#319）で単一の reconciler を参照できる
- デメリット: 6 スクリプトの呼び出し更新が必要、CI grep-gate 追加必須

### 不採用 1: thin wrapper 化 (watchdog-reconcile.sh を維持、内部で reconcile-phase-state.sh 呼び出し)

- メリット: 後方互換、呼び出し元更新不要
- デメリット: 2 箇所の維持、deprecation window が長期化、新 helper の機能 (precondition / JSON output / --strict/warn-only) が旧 wrapper 経由だと使えない
- **理由**: ユーザー確認で「完全削除 + 呼び出し元更新」を採択

### 不採用 2: 既存 watchdog-reconcile.sh に precondition 機能を追加 (module 化しない)

- メリット: 新ファイル最小
- デメリット: SSoT が script 内部にハードコードされ、SKILL.md から参照不可、下流 Issue が参照する schema が固定化しづらい
- **理由**: #316/#317/#319 が JSON schema に依存するため、SSoT module 化が必須

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/phase-state.md" --> 新 module `modules/phase-state.md` が作成されている
- <!-- verify: file_exists "scripts/reconcile-phase-state.sh" --> 新 helper が作成されている
- <!-- verify: file_exists "tests/reconcile-phase-state.bats" --> bats テストが追加されている
- <!-- verify: file_not_exists "scripts/watchdog-reconcile.sh" --> 旧 helper が削除されている
- <!-- verify: file_not_exists "tests/watchdog-reconcile.bats" --> 旧 bats テストが削除されている
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> 全 bats テスト PASS
- <!-- verify: rubric "scripts/reconcile-phase-state.sh outputs JSON with required keys (schema_version, phase, matches_expected, actual, diagnosis) per phase-state.md SSoT, supporting --check-precondition and --check-completion modes plus --strict/--warn-only flags" --> JSON schema と mode フラグが仕様通り実装されている
- <!-- verify: rubric "skills/auto/SKILL.md Step 4 is restructured so each phase is preceded by a precondition check (--warn-only by default) and followed by a completion reconciliation via scripts/reconcile-phase-state.sh" --> `/auto` SKILL.md が Observe-Diagnose-Act 構造に再構成されている
- <!-- verify: rubric "All 6 run-*.sh scripts (run-issue, run-spec, run-code, run-review, run-merge, run-verify) invoke scripts/reconcile-phase-state.sh instead of the removed scripts/watchdog-reconcile.sh" --> 6 本の run-*.sh すべてで呼び出し元が更新されている

### Post-merge

- 意図的に wrapper を失敗させた状態（例: run-auto-sub.sh の glob 抽出バグ再現）で `/auto` 実行し、reconciler が「実作業は成功」を診断して後続 phase に進むことを確認 <!-- verify-type: manual -->
- `phase/ready` なしで `/auto` 実行し、precondition check が warn-only モードで警告を出しつつ実行継続することを確認 <!-- verify-type: manual -->
- 本 Issue merge 後の運用期間（2 週間以上）で precondition check の false-positive 発生率を観察し、`--strict` デフォルト昇格の判断材料とする <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*`: 新 helper を `/auto` skill から呼び出す — `skills/auto/SKILL.md` の allowed-tools に追加必要

### Built-in Tools

- なし（既存 Bash/Read/Write/Grep/Glob のみで実装）

### MCP Tools

- なし

## Notes

### Auto-Resolved Ambiguity Points (dynamic partitioning)

- **CLI interface の phase naming**: 既存 `watchdog-reconcile.sh` の `issue / spec / code-patch / code-pr / review / merge / verify` 命名を踏襲（SSoT 踏襲による最小サプライズ）
- **Exit code convention**: Issue body の指定通り `0/1/2`（0=matches_expected, 1=mismatch, 2=error）。既存 `watchdog-reconcile.sh` の `0/143/2` は watchdog 専用意味付けだったが、新汎用 helper では意味を clean に設計
- **issue phase の precondition**: `Issue exists and not CLOSED`（`gh issue view --json state`）。既存 dispatcher に issue phase の precondition は存在しなかったが、対称性のため追加

### Backward Compatibility

- 完全削除方式のため、呼び出し元 (6 run-*.sh) を同一 PR で一括更新する必要がある（原子的マイグレーション）
- worktree 内の stale コピー 2 件 (`.claude/worktrees/patch+issue-301/`, `verify+issue-325/`) は PR merge 後に rebase 必要（ユーザー作業）

### Risk Mitigations

- **Precondition false-positive (gh API eventual consistency)**: `--warn-only` デフォルトで段階導入。post-merge 運用観察 2 週間以上を経て `--strict` 昇格判断
- **state schema 設計不足 → cascade 修正**: `schema_version: "v1"` 必須キー含め、下流 #315/#316/#317/#319 で同 schema を参照
- **Stage 2 recovery の一時退行**: `watchdog-reconcile.sh` の push+PR 作成機能は本 Issue で削除。#316 recovery sub-agent 実装までの過渡期は Auto Retrospective で検知（機能退行を受容）
- **置換漏れ検出**: CI grep-gate で永続的に検出 (`grep -r watchdog-reconcile scripts/`)

### bats test 設計詳細

- 既存 32 ケースの移植方針:
  - `@test "error: ..."` (4 件) → そのまま移植、phase 名は変更なし
  - `@test "<phase>: ..."` (28 件) → `_reconcile_<phase>` 参照を `_completion_<phase>` に rename
- 新規追加ケース:
  - `_precondition_<phase>` 7 phase × (PASS / FAIL) = 14 ケース
  - JSON schema 出力フォーマット = 2 ケース
  - `--strict` vs `--warn-only` mode 差 = 2 ケース
  - Same phase precondition vs completion 比較 = 2 ケース
- test fixture 入力データ形式: 既存 `watchdog-reconcile.bats` と同様、mock として `gh` / `get-config-value.sh` を `$MOCK_DIR` 配下に配置し `WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` で差し替える

### Count Alignment Check

- Issue body `## Acceptance Criteria > Pre-merge`: 9 件
- Spec `## Verification > Pre-merge`: 9 件
- 一致 ✓

### Architecture Decisions

- `docs/tech.md` Architecture Decisions への影響なし: 本 Issue は `claude -p` CLI フラグ追加・`.wholework.yml` キー追加のどちらにも該当しないため更新不要
- 新 SSoT module 追加に伴う `docs/structure.md` の Modules セクションへの追加は不要（phase-state.md は modules/ に分類される shared module であり、既存の記載規則内で収まる）

### 先例参照

- #243: watchdog-reconcile.sh 新設時の phase テーブル設計パターン → 本 Issue で汎化
- #308: Stage 2 recovery 追加 → 本 Issue では削除 + #316 へ移譲
- #310: `worktree-code+issue-N` 命名 SSoT → code-pr phase の precondition/completion 検査で踏襲
- #113: 新規 shared module 設立パターン (phase-banner.md) → phase-state.md の設計テンプレート
- #132: label transition 非対称性の教訓 → 全 phase 対称な precondition/completion 呼び出し
- #284: post-validation idiom (wrapper exit 0 でも state 再確認) → 本 Issue の completion check が同 idiom の汎化
