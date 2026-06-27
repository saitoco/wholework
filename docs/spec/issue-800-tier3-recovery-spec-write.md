# Issue #800: auto: Tier 3 recovery 後の sub-issue Spec へ Auto Retrospective 自動追記を実装 (Tier 2 と対称)

## Overview

`run-auto-sub.sh` の Tier 3 recovery 成功時に、sub-issue Spec (`docs/spec/issue-N-*.md`) の `## Auto Retrospective` セクションへ recovery 情報を自動追記する仕組みを追加する。

現状の Tier 2 は `_write_tier2_recovery_to_spec()` が recovery 記録を Spec に書くが、Tier 3 は `orchestration-recoveries.md` への記録のみで Spec が更新されない。これにより `/verify` Step 12 の skip 判定で Tier 3 recovery が "already recorded" として扱われず、verify retrospective での手動補完が必要になる。

Tier 2 実装 (`_write_tier2_recovery_to_spec()`) を対称的に Tier 3 に適用することで SSoT を確立する。

## Changed Files

- `scripts/run-auto-sub.sh`: `_write_tier3_recovery_to_spec()` 関数を追加 (line 184 付近、`_write_tier2_recovery_to_spec()` の直後); Tier 3 成功 block に呼び出しを追加 — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: "Tier 3 bash path: Spec Auto Retrospective write" セクションを追加 (既存 "Tier 2 bash path" セクションの直後)
- `skills/auto/SKILL.md`: Step 4a Source 1 note を Tier 3 対応に更新 (Tier 2 のみ言及している箇所に Tier 3 を追記)
- `tests/run-auto-sub.bats`: "run-auto-sub: tier3 recovery: writes Auto Retrospective to spec file" テストを追加

## Implementation Steps

1. `scripts/run-auto-sub.sh` に `_write_tier3_recovery_to_spec()` 関数を追加する (→ AC1)
   - 配置: `_write_tier2_recovery_to_spec()` の直後 (line 185 付近、`run_phase_with_recovery()` の前)
   - パラメータ: `issue`, `phase`, `exit_code`
   - 処理: `_write_tier2_recovery_to_spec()` と同様のロジックで spec ファイルを発見/作成 → `## Auto Retrospective` セクションを確保 → 以下の recovery info block を `printf` で追記 → `git add/commit/push`

   ```
   ### Tier 3 recovery ({phase})
   - **Date**: {YYYY-MM-DD HH:MM UTC}
   - **Issue**: #{issue}, phase: {phase}
   - **Source**: spawn-recovery-subagent.sh
   - **Wrapper exit code**: {exit_code}
   - **Outcome**: success
   - **Recovery details**: see docs/reports/orchestration-recoveries.md
   ```

   - commit メッセージ: `"Record Tier 3 recovery in auto retrospective for issue #${issue}"`
   - 警告: git commit/push 失敗時は WARNING を stderr に出力し続行 (Tier 2 と同様)
   - bash 3.2 互換: `mapfile` 不使用; `local` 変数, `$(...)`, `printf` のみ使用

2. `run_phase_with_recovery()` の Tier 3 成功 block に `_write_tier3_recovery_to_spec` 呼び出しを追加する (→ AC2)
   - 挿入位置: `orchestration-recoveries.md` の commit block の直後、`emit_event "recovery"` の前
   - コード: `_write_tier3_recovery_to_spec "$issue" "$phase" "$exit_code"`

3. `modules/orchestration-fallbacks.md` に "Tier 3 bash path: Spec Auto Retrospective write" セクションを追加する (→ AC3)
   - 挿入位置: 既存 "Tier 2 bash path: Spec Auto Retrospective write" セクション (line 504) の直後
   - 内容: Tier 3 の Spec write 設計を Tier 2 と対称的に説明 (`_write_tier3_recovery_to_spec()` の役割, 呼び出し条件, SSoT 設計)
   - grep pattern を満たすキーワードを含める: `Tier 3` + `Auto Retrospective` または `_write_tier3_recovery_to_spec`

4. `skills/auto/SKILL.md` Step 4a Source 1 note を更新する (→ AC3 rubric complement)
   - 現在: "For XL routes, `run-auto-sub.sh` Tier 2 bash path writes the sub-issue's Spec Auto Retrospective directly..."
   - 変更: Tier 2 に加えて Tier 3 も `run-auto-sub.sh` が直接 Spec に書く旨を追記 (`_write_tier3_recovery_to_spec()` への参照を含める)

5. `tests/run-auto-sub.bats` にテストを追加する (after line 725, Tier 2 spec write テストの直後)
   - テスト名: `"run-auto-sub: tier3 recovery: writes Auto Retrospective to spec file"`
   - setup: `$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md` を作成; git mock を dirty-on-issue-42 で設定; `spawn-recovery-subagent.sh` mock を exit 0 で設定
   - assertion: `grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"`; `grep -qE "commit.*Tier 3 recovery" "$GIT_LOG"`

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh に Tier 3 recovery 成功時に docs/spec/issue-N-*.md の ## Auto Retrospective セクションに recovery 情報を自動追記する関数 (_write_tier3_recovery_to_spec 等) が実装されている" --> AC1: `_write_tier3_recovery_to_spec()` 関数が `scripts/run-auto-sub.sh` に実装されている
- <!-- verify: grep "tier.?3.*spec|spec.*tier.?3|_write_tier3_recovery_to_spec" "scripts/run-auto-sub.sh" --> AC2: Tier 3 自動追記の呼び出しが `run-auto-sub.sh` に追加されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md または skills/auto/SKILL.md で Tier 3 recovery 後の sub-issue Spec への自動追記設計 (Tier 2 と同等の SSoT 保持) が明文化されている" --> <!-- verify: grep "Tier 3.*Auto Retrospective|Auto Retrospective.*Tier 3|_write_tier3_recovery_to_spec" "modules/orchestration-fallbacks.md" --> AC3: `modules/orchestration-fallbacks.md` に Tier 3 Spec write 設計が文書化されている

### Post-merge

- 次回 Tier 3 recovery 発生時に対象 sub-issue の Spec に `## Auto Retrospective` が自動追記されることを観察

## Notes

- `spawn-recovery-subagent.sh` は `orchestration-recoveries.md` に recovery 詳細 (diagnosis, steps, action) を書く。`_write_tier3_recovery_to_spec()` は `$phase`, `$issue`, `$exit_code` の変数から minimal な Spec エントリを構築し、詳細は `orchestration-recoveries.md` 参照とする (Tier 2 の `apply-fallback.sh` stdout パターンと異なる設計だが、変数で取得可能な情報で十分)
- Auto-Resolved Ambiguity (Issue comment より):
  - 実装対象ファイル: `run-auto-sub.sh` に統一 (Tier 2 の対称設計)
  - ドキュメント対象: `modules/orchestration-fallbacks.md` に追加 (既存 Tier 2 セクションとの対称性)
- `_write_tier3_recovery_to_spec()` の commit メッセージは Tier 2 の "Record Tier 2 recovery" パターンに合わせる (bats test で `grep -qE "commit.*Tier 3 recovery"` が期待)

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective — 自動解決済み曖昧ポイント 3 件の記録 (実装対象ファイル, AC2 verify command 修正, ドキュメント対象) / https://github.com/saitoco/wholework/issues/800#issuecomment-4822489200

## Code Retrospective

### Deviations from Design

- None: 実装はすべて Spec の実装ステップに沿って完了。`_write_tier3_recovery_to_spec()` のシグネチャ (`issue`, `phase`, `exit_code`) と配置 (`_write_tier2_recovery_to_spec()` の直後) は設計通り。

### Design Gaps/Ambiguities

- Tier 3 ブロック内の `orchestration-recoveries.md` commit と Spec commit の順序: `orchestration-recoveries.md` commit が先に行われるが、これは Spec Notes に「`orchestration-recoveries.md` の commit block の直後」と明記されており問題なし。ただし、`orchestration-recoveries.md` commit が失敗した場合でも `_write_tier3_recovery_to_spec` は呼ばれる設計になっているため、部分的な記録が残る可能性がある。Tier 2 の `_write_tier2_recovery_to_spec()` も同様の設計であり、既存の一貫性を維持。

### Rework

- None: 1 pass で全実装ステップ完了。テストも初回から PASS。

## review retrospective

### Spec vs. implementation divergence patterns

- None: PR diff は Spec の全受け入れ基準 (AC1-AC3) を満たしており、設計からの逸脱は確認されなかった。`_write_tier3_recovery_to_spec()` のシグネチャ・配置・内部ロジックはすべて Spec の実装ステップ通り。

### Recurring issues

- None: MUST/SHOULD 指摘なし。CONSIDER 1 件のみ (未追跡ファイルの commit スキップリスク)。これは `_write_tier2_recovery_to_spec()` との対称設計を維持するためのトレードオフであり、個別修正よりも future issue 扱いが適切。

### Acceptance criteria verification difficulty

- AC1/AC3a: `rubric` verify command を使用。grader が PR branch のファイルを読むため、`$PWD` (worktree root) 基準での解決が必要。今回は inline 実行のため問題なかったが、subagent 経由の `rubric` grader は main branch ファイルを参照するリスクがある。verify command を `file_contains` + `grep` の組み合わせに変更することで安定性が向上する可能性がある。
- AC2/AC3b: `grep` verify command で明確に PASS。verify command の精度が高く UNCERTAIN ゼロ。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- AC1/AC2/AC3 すべて PASS を確認。MUST/SHOULD 指摘なし、CONSIDER 1 件のみ (未追跡ファイル commit スキップリスク) — Tier 2 との対称設計を維持するため許容。
- `review-light` subagent type が登録されていないため、agent instructions に従いインライン実行した。CI はすべて SUCCESS。
- 受け入れ基準の verify command 精度が高く (rubric + grep の組み合わせ)、UNCERTAIN ゼロ。

### Deferred Items
- CONSIDER 指摘: 未追跡 spec ファイルの commit スキップリスクは future issue 扱い。
- post-merge AC (次回 Tier 3 recovery 観察) は自然発生待ち。

### Notes for Next Phase
- `/merge 810` で本 PR をマージ可能。MUST issues なし、CI 全 SUCCESS。
- `review-light` agent type がプロジェクト `agents/` ディレクトリに定義されているが Claude Code が認識しない問題を確認。
