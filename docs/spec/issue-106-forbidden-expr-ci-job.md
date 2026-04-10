# Issue #106: ci: Forbidden Expressions 違反を検出するCIジョブを追加

## Overview

`.github/workflows/test.yml` に Forbidden Expressions 違反を検出するCIジョブを追加する。対象は `docs/tech.md` Forbidden Expressions テーブルに登録された "Acceptance check" 表現。

現状: bats テストと `validate-skill-syntax.py` の2ジョブのみ。`/review` の CI フォールバック（safe モード）では `command` 形式の広範 grep が UNCERTAIN になるため、CI ジョブとして明示的に実行されると自動検証が完結する。

除外対象（CIジョブ内 grep 除外）:
- `docs/spec/` — 使い捨て Spec（歴史的参照）
- `| Acceptance check |` — Forbidden Expressions テーブル行自体
- `Formerly called` / `旧称` — 歴史的用語参照

## Changed Files

- `.github/workflows/test.yml`: `check-forbidden-expressions` ジョブを追加（`bats` / `validate-syntax` の後に配置）
- `docs/structure.md`: test.yml の説明を更新（Forbidden Expressions チェック追記）
- `docs/ja/structure.md`: 同上（日本語ミラー）

## Implementation Steps

1. `.github/workflows/test.yml` に `check-forbidden-expressions` ジョブを追加。`name: Forbidden Expressions check`。ステップで `grep -ri 'acceptance check'` を `skills/ modules/ agents/ tests/ docs/` に実行し、`grep -v 'docs/spec/'`・`grep -v 'Formerly called'`・`grep -v '旧称'`・`grep -v '| Acceptance check |'` で除外フィルタリング。違反があれば `exit 1`。 (→ 受入条件 1, 2)
2. `docs/structure.md` の `test.yml` 説明を「bats tests and skill syntax validation」→「bats tests, skill syntax validation, and forbidden expressions check」に更新（Directory Layout と Key Files 両箇所）。`docs/ja/structure.md` も同様に更新。 (→ doc consistency)

## Verification

### Pre-merge

- <!-- verify: grep "[Ff]orbidden" ".github/workflows/test.yml" --> `.github/workflows/test.yml` に Forbidden Expressions チェックジョブが追加されている
- <!-- verify: grep "[Aa]cceptance check" ".github/workflows/test.yml" --> CI ジョブが "acceptance check" を検出するコマンドを含んでいる

### Post-merge

- `/verify 106` を実行して全受入条件が PASS することを確認

## Notes

- `docs/ja/structure.md` は `/doc translate ja` で生成された翻訳ファイルではなく手動管理ファイルのため、実装ステップに含める
- test.yml の新ジョブは既存の `bats` と `validate-syntax` ジョブと並列実行可能（依存関係なし）
- docs/spec/ は歴史的参照を含むため除外。docs/product.md と docs/ja/product.md は "Formerly called" / "旧称" フィルタで除外

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue本文に「Auto-Resolved Ambiguity Points」として5点の曖昧点が整理されており、verify command の BRE/ERE 問題や大文字小文字対応が `/issue` 段階で事前解決されていた。Spec は Issue の判断を引き継ぎ、verify command に `[Ff]orbidden` / `[Aa]cceptance check` を採用した点は適切。

#### design
- Spec の変更ファイルリスト（`test.yml`, `docs/structure.md`, `docs/ja/structure.md`）と実装コミットの変更ファイルが完全一致。設計と実装の乖離なし。

#### code
- 実装コミット1件、fixup/amend なし。コード再作業ゼロ。Code Retrospective も偏差・ギャップ・再作業なし（N/A）。

#### review
- patchルートのため PR レビューなし。Forbidden Expressions チェックが CI に入ったことで、将来の用語統一違反を自動検出できる仕組みが整った。

#### merge
- mainへの直接コミット（patchルート）。コンフリクトなし、CI も issue-106 自体が追加したジョブを通過。

#### verify
- 受け入れ条件2件とも `grep` コマンドで即時 PASS。verify command の `[Ff]orbidden` / `[Aa]cceptance check` パターンが実装内容と正確に対応しており、false negative/positive なし。

### Improvement Proposals
- N/A
