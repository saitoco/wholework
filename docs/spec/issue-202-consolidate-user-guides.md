# Issue #202: docs: ユーザー向けガイドを docs/guide/ に集約

## Overview

`docs/adapter-guide.md` と `docs/figma-best-practices.md` はユーザー向けガイドだが `docs/` 直下にある。`docs/guide/` 配下の他ページ（quick-start, workflow, customization, troubleshooting）と同じ階層に移動し、`docs/guide/index.md` の Guide Pages テーブルに追加する。合わせて日本語版（`docs/ja/`）も同様に移動し、全参照パスを更新する。

## Changed Files

- `docs/adapter-guide.md` → `docs/guide/adapter-guide.md`: git mv + language toggle link を `ja/adapter-guide.md` → `../ja/guide/adapter-guide.md` に更新 + raw GitHub URL 2箇所を `docs/guide/adapter-guide.md` に更新
- `docs/figma-best-practices.md` → `docs/guide/figma-best-practices.md`: git mv + language toggle link を `ja/figma-best-practices.md` → `../ja/guide/figma-best-practices.md` に更新
- `docs/ja/adapter-guide.md` → `docs/ja/guide/adapter-guide.md`: git mv + language toggle link を `../adapter-guide.md` → `../../guide/adapter-guide.md` に更新 + raw GitHub URL 2箇所を `docs/guide/adapter-guide.md` に更新
- `docs/ja/figma-best-practices.md` → `docs/ja/guide/figma-best-practices.md`: git mv + language toggle link を `../figma-best-practices.md` → `../../guide/figma-best-practices.md` に更新
- `docs/guide/index.md`: Guide Pages テーブルに Adapter Authoring Guide と Figma Best Practices の2行を追加
- `docs/ja/guide/index.md`: ガイドページテーブルに同等の2行を追加
- `docs/guide/customization.md`: `../adapter-guide.md` → `adapter-guide.md` に更新
- `docs/ja/guide/customization.md`: `../adapter-guide.md` → `adapter-guide.md` に更新
- `docs/structure.md`: Directory Layout の `adapter-guide.md` と `figma-best-practices.md` 行を `docs/` 直下から削除し、`guide/` の description に追加
- `docs/ja/structure.md`: 同上（日本語版）

## Implementation Steps

1. git mv で4ファイルを移動 (→ acceptance criteria: file existence/absence)
   ```
   git mv docs/adapter-guide.md docs/guide/adapter-guide.md
   git mv docs/figma-best-practices.md docs/guide/figma-best-practices.md
   git mv docs/ja/adapter-guide.md docs/ja/guide/adapter-guide.md
   git mv docs/ja/figma-best-practices.md docs/ja/guide/figma-best-practices.md
   ```

2. 移動した4ファイルの language toggle リンクを更新 (→ 内部リンク整合性)
   - `docs/guide/adapter-guide.md` line 7: `[日本語](ja/adapter-guide.md)` → `[日本語](../ja/guide/adapter-guide.md)`
   - `docs/guide/figma-best-practices.md` line 7: `[日本語](ja/figma-best-practices.md)` → `[日本語](../ja/guide/figma-best-practices.md)`
   - `docs/ja/guide/adapter-guide.md` line 1: `[English](../adapter-guide.md)` → `[English](../../guide/adapter-guide.md)`
   - `docs/ja/guide/figma-best-practices.md` line 1: `[English](../figma-best-practices.md)` → `[English](../../guide/figma-best-practices.md)`

3. raw GitHub URL を更新 (→ 外部からの直接参照が有効)
   - `docs/guide/adapter-guide.md`: `docs/adapter-guide.md` → `docs/guide/adapter-guide.md` (2箇所)
   - `docs/ja/guide/adapter-guide.md`: 同上 (2箇所)

4. `docs/guide/index.md` と `docs/ja/guide/index.md` の Guide Pages テーブルに2行追加 (→ acceptance criteria: section_contains)
   - EN: `| [Adapter Authoring Guide](adapter-guide.md) | Write project-specific adapters for MCP servers, CLI tools, and external services |`
   - EN: `| [Figma Best Practices](figma-best-practices.md) | Design Figma files for optimal AI code generation accuracy |`
   - JA: 同等の日本語行

5. `docs/guide/customization.md` と `docs/ja/guide/customization.md` のリンクを更新 (→ acceptance criteria: file_not_contains "../adapter-guide.md")
   - EN line 106: `(../adapter-guide.md)` → `(adapter-guide.md)`
   - JA line 98: `(../adapter-guide.md)` → `(adapter-guide.md)`

6. `docs/structure.md` と `docs/ja/structure.md` の Directory Layout を更新 (→ acceptance criteria: file_contains "guide/adapter-guide.md")
   - `adapter-guide.md` と `figma-best-practices.md` の2行を `docs/` 直下エントリから削除
   - `guide/` 行の description を更新して adapter-guide と figma-best-practices を含める

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/guide/adapter-guide.md" --> `docs/guide/adapter-guide.md` が存在する
- <!-- verify: file_not_exists "docs/adapter-guide.md" --> `docs/adapter-guide.md` が削除されている
- <!-- verify: file_exists "docs/guide/figma-best-practices.md" --> `docs/guide/figma-best-practices.md` が存在する
- <!-- verify: file_not_exists "docs/figma-best-practices.md" --> `docs/figma-best-practices.md` が削除されている
- <!-- verify: file_exists "docs/ja/guide/adapter-guide.md" --> `docs/ja/guide/adapter-guide.md` が存在する
- <!-- verify: file_not_exists "docs/ja/adapter-guide.md" --> `docs/ja/adapter-guide.md` が削除されている
- <!-- verify: file_exists "docs/ja/guide/figma-best-practices.md" --> `docs/ja/guide/figma-best-practices.md` が存在する
- <!-- verify: file_not_exists "docs/ja/figma-best-practices.md" --> `docs/ja/figma-best-practices.md` が削除されている
- <!-- verify: section_contains "docs/guide/index.md" "📚 Guide Pages" "adapter-guide" --> Guide Pages テーブルに Adapter Authoring Guide 行が追加されている
- <!-- verify: section_contains "docs/guide/index.md" "📚 Guide Pages" "figma-best-practices" --> Guide Pages テーブルに Figma Best Practices 行が追加されている
- <!-- verify: file_not_contains "docs/guide/customization.md" "../adapter-guide.md" --> `docs/guide/customization.md` 内の `../adapter-guide.md` 参照が新パスに更新されている
- <!-- verify: file_not_contains "docs/ja/guide/customization.md" "../adapter-guide.md" --> `docs/ja/guide/customization.md` 内の旧参照が更新されている
- <!-- verify: file_contains "docs/structure.md" "guide/adapter-guide.md" --> `docs/structure.md` のディレクトリ図が新パスを示している
- <!-- verify: file_contains "docs/ja/structure.md" "guide/adapter-guide.md" --> `docs/ja/structure.md` のディレクトリ図が新パスを示している

### Post-merge

- `/audit drift` 実行時に `docs/guide/` と実装・参照パスに関するドリフトが検出されないこと

## Spec Retrospective

N/A

## Code Retrospective

### Deviations from Design

- なし。Spec の実装ステップをそのまま順番通りに実行した。

### Design Gaps/Ambiguities

- `docs/structure.md` の更新方法について Spec には「`adapter-guide.md` と `figma-best-practices.md` の2行を `docs/` 直下エントリから削除し、`guide/` 行の description を更新して adapter-guide と figma-best-practices を含める」とあったが、`guide/` 行の description が長くなり可読性に懸念があった。最終的には「guide/adapter-guide.md、guide/figma-best-practices.md」を括弧内に追記する形で対応した。

### Rework

- なし。

## review retrospective

### Spec vs. 実装乖離パターン

特記なし。ドキュメント移動のみの変更で、Spec の全ステップが正確に実装されていた。

### 繰り返し問題

特記なし。

### 受け入れ基準検証困難度

14項目すべてが verify コマンド付きで、`file_exists`/`file_not_exists`/`section_contains`/`file_not_contains`/`file_contains` の各コマンドで自動検証可能だった。すべて PASS で UNCERTAIN なし。verify コマンドの網羅性が高く、今後のリファレンスとして有効。

## Notes

- `docs/adapter-guide.md` 内の raw GitHub URL (`raw.githubusercontent.com/saitoco/wholework/main/docs/adapter-guide.md`) が2箇所 × 英語/日本語版で計4箇所存在する。これらは外部プロジェクトの `.wholework.yml` からの WebFetch 参照先となっているため、移動後のパスに更新が必要
- `docs/spec/issue-119-adapter-guide.md` は過去の Spec ファイルであり、歴史的記録として旧パスのまま保持する（更新対象外）
