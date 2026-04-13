# Issue #143: verify: GitHub Actions workflow 導入 Issue の受け入れ条件に CI check 検証を追加

## Overview

GitHub Actions workflow を導入する Issue の受け入れ条件に、CI 実行結果を検証する `github_check "gh run list"` verify command を `file_contains` と併用するパターンのガイドラインを追加する。

Issue #73（DCO 導入）の verify レトロスペクティブにて、`file_contains` のみでは GitHub Action の設定ミス（必須オプション未設定等）を `/verify` 段階で検出できないことが判明した。追加先は distributable-first 原則に従い以下 2 箇所:

1. `modules/verify-patterns.md`: verify command 設計ガイドラインの正規配置先に新セクションを追加
2. `skills/spec/SKILL.md`: SHOULD 制約表に行を追加し、Spec 生成時に自動参照されるようにする

## Changed Files

- `modules/verify-patterns.md`: Section 7「GitHub Actions Workflow Changes — Combine file_contains and github_check」を追加（`## Output` セクションの直前）
- `skills/spec/SKILL.md`: SHOULD 制約表末尾（`| Permission pattern verification | ...` 行の直後）に「GitHub Actions workflow CI verify」行を追加

## Implementation Steps

1. `modules/verify-patterns.md` の `## Output` セクション直前に、以下の内容で `### 7. GitHub Actions Workflow Changes — Combine file_contains and github_check` セクションを追加する (→ 受け入れ条件1, 2):
   - 背景: `.github/workflows/*.yml` が変更対象になる Issue では、`file_contains` だけでは Action の設定ミス（必須オプション未設定等）を検出できない
   - 推奨パターン: `file_contains`（設定内容の存在確認）と `github_check "gh run list"`（CI 実行結果確認）を併用する
   - パターン例と説明を含める（`file_contains` の役割、`github_check "gh run list"` の役割）
   - パッチルート Issue では `gh pr checks` 使用不可のため `gh run list` が必須であることを注記

2. `skills/spec/SKILL.md` の SHOULD 制約表の `| Permission pattern verification | ...` 行の直後に以下の行を追加する (→ 受け入れ条件3):
   ```
   | GitHub Actions workflow CI verify | When `.github/workflows/*.yml` is changed, include both `file_contains` (config content) and `github_check "gh run list"` (CI execution result) in acceptance criteria. See `${CLAUDE_PLUGIN_ROOT}/modules/verify-patterns.md` | #73 |
   ```

## Verification

### Pre-merge

- <!-- verify: grep "gh run list" "modules/verify-patterns.md" --> `modules/verify-patterns.md` に `gh run list` を用いた CI 実行結果検証ガイドラインが追加されている
- <!-- verify: grep "\.github/workflows" "modules/verify-patterns.md" --> 同ガイドラインが対象として `.github/workflows` を明示している
- <!-- verify: grep "\.github/workflows.*github_check" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` の SHOULD 制約表に、`.github/workflows/*.yml` 変更時に `github_check` を併用する指示行が追加されている

### Post-merge

- GitHub Actions workflow 追加を目的とする Issue に対して `/spec` を実行すると、受け入れ条件に `github_check "gh run list"` 形式の verify command が提案されることを確認

## Notes

なし
