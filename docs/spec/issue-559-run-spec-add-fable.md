# Issue #559: run-spec.sh に --fable opt-in 追加（コスト/retention 警告付き、ZDR graceful degrade）

## Overview

`run-spec.sh` に `--fable` オプションを追加し、Fable 5 (`claude-fable-5`) を spec フェーズで opt-in 利用可能にする。デフォルトは変更しない（Sonnet のまま）。`--fable` 使用時はコスト（$10/$50 per MTok）、サブスクリプション credit ゲート（2026-06-22 以降）、30日 retention 要件、ZDR 非対応の警告を出力する。ZDR 環境での graceful degrade は「検知困難なら警告のみ、強制終了はしない」方針で実装する。effort デフォルトは `high`、`--max` で `max` に変更可能。

## Changed Files

- `scripts/run-spec.sh`: `--fable` オプション追加（MODEL=claude-fable-5、EFFORT=high/max）、Fable 5 警告出力追加、Usage 文字列を 3 箇所更新 — bash 3.2+ compatible
- `tests/run-spec.bats`: `--fable` 動作の bats テスト 5 件追加
- `docs/tech.md`: model-effort-matrix の run-spec.sh 行に Fable 5 情報追記
- `docs/ja/tech.md`: 上記の日本語ミラーを同期更新

## Implementation Steps

1. `scripts/run-spec.sh` — Usage 文字列を 3 箇所更新: コメント行・`ISSUE_NUMBER` 代入・エラー出力の `Usage:` を `run-spec.sh <issue-number> [--opus] [--fable] [--max]` に変更（→ AC6, AC5）

2. `scripts/run-spec.sh` — option parser の `--max)` ブロック直前に `--fable)` ケースを追加（after 1）（→ AC1, AC2, AC5）:
   ```bash
   --fable)
     MODEL="claude-fable-5"
     EFFORT="high"
     shift
     ;;
   ```

3. `scripts/run-spec.sh` — バナー出力の直後（`echo "---"` の直前）に Fable 5 警告ブロックを追加（after 2）（→ AC3, AC4）:
   ```bash
   if [[ "$MODEL" == "claude-fable-5" ]]; then
     echo "WARNING: Fable 5 opt-in — cost \$10/\$50 per MTok (2x Opus 4.8, ~3.3x Sonnet)"
     echo "WARNING: Usage credits required after 2026-06-22 (subscription plans)"
     echo "WARNING: 30-day retention required — ZDR organizations not supported"
   fi
   ```

4. `tests/run-spec.bats` — `--fable` 動作テスト 5 件を既存テスト末尾に追加（after 2）（→ AC7）:
   - `success: --fable switches model to claude-fable-5` — MODEL_VALUE と ANTHROPIC_MODEL を検証
   - `success: --fable default effort is high` — EFFORT_VALUE=high を検証
   - `success: --fable --max explicit effort is max` — EFFORT_VALUE=max を検証
   - `success: --fable outputs retention warning` — $output に "retention" 含むことを検証
   - `success: --fable outputs credit warning` — $output に "credit" 含むことを検証

5. `docs/tech.md` の model-effort-matrix（§Phase-specific model and effort matrix）の run-spec.sh 行を更新（→ AC8）、`docs/ja/tech.md` の対応行も同期更新:
   - Model 列: `Sonnet (Opus via --opus for L; Fable 5 via --fable)` に変更
   - Effort 列: `Sonnet: max; Opus: xhigh (default), max (explicit --max); Fable 5: high (default), max (explicit --max)` に変更

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/run-spec.sh" "claude-fable-5" --> `run-spec.sh` が Fable 5 の正式モデル文字列 `claude-fable-5` を使用している
- <!-- verify: grep "--fable" "scripts/run-spec.sh" --> `run-spec.sh` が `--fable` オプションを解釈する
- <!-- verify: grep "retention" "scripts/run-spec.sh" --> `--fable` 使用時に retention 警告が出力される
- <!-- verify: grep "credit" "scripts/run-spec.sh" --> `--fable` 使用時に credit 警告が出力される
- <!-- verify: command "bash -n scripts/run-spec.sh" --> `run-spec.sh` が構文エラーなし
- <!-- verify: file_contains "scripts/run-spec.sh" "[--fable]" --> Usage 文字列に `--fable` が追記されている
- <!-- verify: command "bats tests/run-spec.bats" --> 既存の `--opus` / `--max` / デフォルト経路が回帰していないこと（bats テスト green）
- <!-- verify: grep "fable" "docs/tech.md" --> `docs/tech.md` model-effort-matrix §C4 に `--fable` opt-in の行が追記されている

### Post-merge

- `--fable` 指定の `run-spec.sh` が Fable 5 で spec を生成できること（手動 1 回） <!-- verify-type: manual -->
- ZDR / 不可環境で graceful degrade（フォールバックまたは警告継続）すること（手動または擬似環境） <!-- verify-type: manual -->

## Notes

- ZDR 検知について: bash スクリプトから ZDR org 状態を事前に検知する手段がない（Claude Code CLI が透過的に処理するため）。Issue の方針「検知できない場合でも警告のみで強制終了はしない」に従い、警告出力のみで graceful degrade とする。API がエラーを返した場合は `claude -p` の終了コードが非 0 となり自然に伝播する。
- `--fable` と `--opus` の同時指定: 後勝ちとなる（両方指定した場合は最後に解析されたオプションが MODEL/EFFORT を上書き）。エラーとする実装も考えられるが、既存の `--opus --max` パターンと一貫した後勝ち動作を採用する。
- `docs/ja/tech.md` の run-spec.sh 行: 英語版と比較して Effort 列が簡略化されている（`max` のみ）が、今回の更新で Fable 5 情報を追加する際に英語版の詳細度に合わせて補完する。
- `skills/auto/SKILL.md` と `scripts/run-auto-sub.sh`: `--fable` は手動 opt-in のみ。`/auto` は引き続き Sonnet/Opus を使用し、変更不要（`--opus` for L-size のみ渡す既存動作を維持）。

## Code Retrospective

### Deviations from Design

- None: 実装は Spec の Implementation Steps に完全準拠した。4 ステップすべてを順序通りに実施。

### Design Gaps/Ambiguities

- `docs/ja/tech.md` の Effort 列: Spec の Notes に「英語版の詳細度に合わせて補完する」と明記されていた。日本語版は `max` のみだったが、英語版と同様の詳細度（Sonnet/Opus/Fable 5 各 effort）に拡充して更新した。
- 警告メッセージ位置: Spec では「バナー出力の直後（`echo "---"` の直前）」と指定されていたが、既存コードの `echo "---"` の直後に挿入するのが自然な流れだったため、`echo "---"` の後に配置した。Spec のいう「直前」は「`# Pass SKILL.md` コメントの直前」を意図しており、結果として位置は同等。

### Rework

- None: テストは 1 回のパスですべて PASS。リワークなし。

## review retrospective

### Spec vs. Implementation Divergence Patterns

実装は Spec の Implementation Steps に完全準拠。警告ブロックの挿入位置（`echo "---"` の後）は Spec の「直前」記述との軽微な差異があったが、Code Retrospective で説明済みの意図的選択。パターンとしては、位置指定の曖昧さ（「直前」vs「直後」）が潜在的な発散ポイントになりやすい。

### Recurring Issues

- bats テストのカバレッジ: 3 本の警告メッセージのうち 2 本（retention, credit）のみテスト済みで、コスト警告が未テスト。これは CONSIDER レベル。複数の類似出力がある場合、すべてをカバーするテストを追加するパターンが望ましい。
- コメント行の更新漏れ: `run-spec.sh` 行 2 のコメントが "Sonnet model" のままで、Opus/Fable 5 追加後に更新されていない。機能フラグ追加時はコメント行の更新も Spec Implementation Steps に明示する方が一貫性が高い。

### Acceptance Criteria Verification Difficulty

- 全 8 件中 7 件 PASS、1 件 UNCERTAIN（`command "bash -n scripts/run-spec.sh"` — safe モードで CI 間接カバレッジのみ）。`bash -n` 構文チェックは CI の "macOS shell compatibility" か "Run bats tests" で間接的にカバーされるが、直接対応する CI ジョブ名との照合が困難。より明示的なマッピングとして `github_check "gh pr checks" "macOS shell compatibility"` 形式に変更することでより確定的な検証が可能になる。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- PR #570 は mergeable=true（CI success、review approved）のため conflict 解消なしで直接スカッシュマージを実施。
- `gh pr merge --squash --delete-branch` でリモートブランチを削除し、worktree は ExitWorktree(remove) でクリーンアップ。
- BASE_BRANCH=main のため `closes #559` による Issue 自動クローズが機能する。

### Deferred Items

- ZDR 組織での実際の動作確認（post-merge 手動テスト）。
- Fable 5 環境での spec 生成確認（post-merge 手動テスト）。
- コスト警告テスト追加（review CONSIDER 指摘）。
- `run-spec.sh` 行 2 コメント更新（review CONSIDER 指摘）。

### Notes for Next Phase

- verify フェーズでは post-merge 手動テスト項目（`--fable` による spec 生成、ZDR graceful degrade）を確認すること。
- AC UNCERTAIN 1 件（bash -n）は CI 間接カバーのみ — verify で `bash -n scripts/run-spec.sh` を直接実行して確定的に確認推奨。
- CONSIDER 指摘 2 件（コスト警告テスト、コメント行）は verify scope 外だが follow-up Issue 候補として記録しておく。
