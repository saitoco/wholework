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
