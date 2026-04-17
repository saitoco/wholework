# Issue #227: run-*.sh のモデル指定を alias へ統一

## Overview

`run-*.sh`（6本）のモデル指定が pinned ID（`claude-sonnet-4-6`, `claude-opus-4-7`）で書かれており、`agents/*.md` frontmatter の alias（`sonnet`/`opus`）と不一致。新モデルリリース時に `run-*.sh` 側のみ手動更新が必要になる問題を解消するため、`run-*.sh` のモデル指定を alias に統一する。

### ANTHROPIC_MODEL

検証結果（Step 6 にて `ANTHROPIC_MODEL=sonnet claude -p "Say only 'ok'" --model sonnet --effort low` を実行し確認）：`ANTHROPIC_MODEL` は alias を受理する。よって `--model` と `ANTHROPIC_MODEL` の両方を alias 化する（alias 対応時フォールバックは不要）。

## Changed Files

- `scripts/run-spec.sh`: `MODEL="claude-sonnet-4-6"` → `MODEL="sonnet"`、`MODEL="claude-opus-4-7"` → `MODEL="opus"`。コメントに `--model sonnet`・`--model opus` のリテラル文字列を含める（verify 用）
- `scripts/run-code.sh`: `ANTHROPIC_MODEL=claude-sonnet-4-6` → `ANTHROPIC_MODEL=sonnet`、`--model claude-sonnet-4-6` → `--model sonnet`
- `scripts/run-review.sh`: 同上（sonnet × 2）
- `scripts/run-issue.sh`: 同上（sonnet × 2）
- `scripts/run-verify.sh`: 同上（sonnet × 2）
- `scripts/run-merge.sh`: 同上（sonnet × 2）。合計 12 文字列（`scripts/` 直下 6 本を対象に `grep -rn "claude-sonnet-4-6\|claude-opus-"` で確認）
- `tests/run-spec.bats`: 6 箇所（テスト名 2 個、`MODEL_VALUE=` 2 個、`ANTHROPIC_MODEL=` 2 個）を alias 形式に更新
- `tests/run-code.bats`: `ANTHROPIC_MODEL=claude-sonnet-4-6` → `ANTHROPIC_MODEL=sonnet`（1 箇所）
- `tests/run-issue.bats`: 同上（1 箇所）
- `tests/run-merge.bats`: 同上（1 箇所）
- `tests/run-review.bats`: 同上（1 箇所）
- `tests/run-verify.bats`: `--model claude-sonnet-4-6` → `--model sonnet`（1 箇所）、`ANTHROPIC_MODEL=claude-sonnet-4-6` → `ANTHROPIC_MODEL=sonnet`（1 箇所）
- `docs/tech.md`: `**Phase-specific model and effort matrix**` を `### Phase-specific model and effort matrix` 見出しに昇格し、alias 採用方針の一文を追加。インデント（2 スペース）を解除

## Implementation Steps

1. `scripts/run-spec.sh` を更新：`MODEL="claude-sonnet-4-6"` → `MODEL="sonnet"` (line 10)、`MODEL="claude-opus-4-7"` → `MODEL="opus"` (line 14)。line 10 の直前に `# Default: --model sonnet (override: --model opus with --opus flag)` コメントを追加し、verify コマンドが参照するリテラル文字列 `--model sonnet` と `--model opus` を含める（→ 受入基準 8, 9）

2. `scripts/run-code.sh`, `run-review.sh`, `run-issue.sh`, `run-verify.sh`, `run-merge.sh` を更新：各スクリプトの `ANTHROPIC_MODEL=claude-sonnet-4-6` → `ANTHROPIC_MODEL=sonnet`、`--model claude-sonnet-4-6` → `--model sonnet` に置換（計 10 文字列）（→ 受入基準 3-7）

3. `tests/run-spec.bats` を更新：テスト名 `"success: default model is claude-sonnet-4-6"` → `"success: default model is sonnet"`、`"success: --opus switches model to claude-opus-4-7"` → `"success: --opus switches model to opus"`、各 grep assertion を alias 形式へ（計 6 箇所）（→ 受入基準 13）

4. `tests/run-code.bats`, `run-issue.bats`, `run-merge.bats`, `run-review.bats`, `run-verify.bats` を更新：`ANTHROPIC_MODEL=claude-sonnet-4-6` → `ANTHROPIC_MODEL=sonnet`（各 1 箇所）、`run-verify.bats` はさらに `--model claude-sonnet-4-6` → `--model sonnet` も更新（→ 受入基準 13）

5. `docs/tech.md` を更新：`  **Phase-specific model and effort matrix** (`ssot_for: model-effort-matrix`):` を `### Phase-specific model and effort matrix` 見出しに変更し 2 スペースインデントを解除。テーブルと SSoT note も同様に unindent。SSoT note を `Model values in run-*.sh use CLI aliases (sonnet/opus); update this table when changing model/effort in run-*.sh, agents, or skills.` に更新して "alias" を含める（→ 受入基準 10）

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/run-spec.sh" "claude-sonnet-4-6" --> `run-spec.sh` から `claude-sonnet-4-6` 直書きが除去されている
- <!-- verify: file_not_contains "scripts/run-spec.sh" "claude-opus-" --> `run-spec.sh` から `claude-opus-*` 直書きが除去されている
- <!-- verify: file_not_contains "scripts/run-code.sh" "claude-sonnet-4-6" --> `run-code.sh` から直書きが除去されている
- <!-- verify: file_not_contains "scripts/run-review.sh" "claude-sonnet-4-6" --> `run-review.sh` から直書きが除去されている
- <!-- verify: file_not_contains "scripts/run-issue.sh" "claude-sonnet-4-6" --> `run-issue.sh` から直書きが除去されている
- <!-- verify: file_not_contains "scripts/run-verify.sh" "claude-sonnet-4-6" --> `run-verify.sh` から直書きが除去されている
- <!-- verify: file_not_contains "scripts/run-merge.sh" "claude-sonnet-4-6" --> `run-merge.sh` から直書きが除去されている
- <!-- verify: file_contains "scripts/run-spec.sh" "--model sonnet" --> `run-spec.sh` が `--model sonnet` alias を使用
- <!-- verify: file_contains "scripts/run-spec.sh" "--model opus" --> `run-spec.sh` の `--opus` 分岐が `--model opus` alias を使用
- <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "alias" --> matrix に alias 採用方針が記載されている
- <!-- verify: file_exists "docs/spec/issue-227-run-scripts-alias.md" --> Spec に ANTHROPIC_MODEL の alias 検証結果が記録されている
- <!-- verify: section_contains "docs/spec/issue-227-run-scripts-alias.md" "ANTHROPIC_MODEL" "." --> ANTHROPIC_MODEL の挙動検証結果が Spec に記録されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" --> `tests/run-*.bats` の全アサーションが alias 形式に更新され、bats テストがパスする

### Post-merge

- 参照 Issue で `/auto N` を実行し、CLI ログで alias 表示（`Model: sonnet` / `Model: opus`）を確認
- ベンチマーク #226 実施手順に「一時的に pin へ戻す」注意書きが追加されている

## Code Retrospective

### Deviations from Design

- なし

### Design Gaps/Ambiguities

- `run-verify.bats` のモックは `echo "$@"` で全引数をログするため `grep -q -- "--model sonnet"` の形式で検証可能（run-spec.bats とは異なるモック構造）。Spec には記載がなかったが、テスト更新時に確認して対処した。

### Rework

- なし

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body のフォールバック方針（ANTHROPIC_MODEL alias 非対応時）と Spec の `### ANTHROPIC_MODEL` 節が一致しており、設計品質は高い
- verify コマンドのターゲット文字列が将来変わりうる値（model ID）に依存するリスクを Spec で明示的に注記したのは有効（Notes セクション）
- `file_contains "scripts/run-spec.sh" "--model sonnet"` が変数展開のため直接マッチしない問題をコメント追加で回避する方針を Spec に明記した点は再利用可能なパターン

#### design
- 実装との乖離なし（Code Retrospective に記録済み）
- `run-verify.bats` のモック構造（`echo "$@"`）が `run-spec.bats` と異なる点は Spec 未記載だったが、実装時に発見・対処された。今後は bats モック構造の差異をスコープ記載に含めると良い

#### code
- 実装は Spec 通り。フィックスアップ・amend なし
- `run-verify.bats` のモック差異は実装中に発見・対処された。リワークなし

#### review
- Copilot レビューが `docs/ja/tech.md` の同期漏れを検出し、PR 内でフォローアップコミットとして修正された
- これはレビューが機能した好例（英語版変更時の日本語版漏れというよくあるパターンを捕捉）
- また `docs/spec/issue-195-bats-run-spec-auto-sub.md` の古い verify 条件（`claude-sonnet-4-6` → `sonnet`）が副次的に修正された点もレビューの成果

#### merge
- PR #228 はクリーンなマージ。コンフリクトなし

#### verify
- 全 13 条件が PASS（再実行時点で bats CI `success` を確認）
- verify コマンドはすべて正確に機能（UNCERTAIN ゼロ）
- PR ルート用の `github_check "gh pr checks"` がパッチルート向けに `gh run list --workflow=test.yml` へ変換されていた点は適切
- 初回 verify 実行時は CI が in_progress で PENDING 判定だったが、`/verify` 再実行でアイデンポテントに PASS へ更新できた（phase/verify → phase/done への遷移は post-merge 条件が未消化のため保留）

### Improvement Proposals
- `docs/` 内の英語ファイル変更時に `docs/ja/` の対応ファイルを必ずチェックするルールを `/code` または `/review` スキルのステップへ明示的に追記する（英語版 → 日本語版同期漏れの再発防止）

## Notes

### run-spec.sh の verify 対応

`file_contains "scripts/run-spec.sh" "--model sonnet"` は run-spec.sh のファイル内に文字列 `--model sonnet` がリテラルで存在することを確認する。run-spec.sh は `MODEL` 変数を使うため `--model "${MODEL}"` のように変数展開を使っており、ファイル内に `--model sonnet` がリテラルで現れない。Step 1 でコメントを追加することで対処する：`# Default: --model sonnet (override: --model opus with --opus flag)`

### docs/tech.md の section_contains 対応

`section_contains "docs/tech.md" "Phase-specific model and effort matrix" "alias"` は markdown の `#` 見出しにマッチする。現在の `**Phase-specific model and effort matrix**`（太字テキスト）は見出しではないため、Step 5 で `### Phase-specific model and effort matrix` 見出しに変換する必要がある。

### patch route: github_check 変換

Issue body の `github_check "gh pr checks" "Run bats tests"` は PR ルート用。Size=S のパッチルートでは PR が存在しないため、`github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'"` に変換した（ワークフローファイルが複数あるため `--workflow=test.yml` を付与）。

## review retrospective

### Spec vs. 実装の乖離パターン

記録なし。スクリプト・テスト・docs/tech.md のすべての変更が Spec 通りに実装されていた。

### 繰り返し発生する問題

英語版ドキュメントを更新した際に日本語版（`docs/ja/`）の同期が漏れるパターンが発生した（docs/ja/tech.md の見出し昇格と SSoT note 更新が未反映）。今後は英語版を変更する際に `docs/ja/` の対応ファイルを必ずチェックリストに含めるべき。

### 受け入れ基準の検証難易度

記録なし（UNCERTAIN ゼロ、verify コマンドはすべて正確）。ただし過去 Issue（#195）の Spec で verify 条件のターゲット文字列が安定しない値（`claude-sonnet-4-6`）に依存していたため、エイリアス移行後に条件が無効化されていた。今後 verify 条件記述時は、参照先文字列が将来変更される可能性があるか（定数か変数か）を意識する。
