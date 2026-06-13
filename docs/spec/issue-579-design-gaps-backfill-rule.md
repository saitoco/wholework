# Issue #579: spec-skill-dev: Design Gaps セクションの実装知見を Implementation Step 本文に補記するルール化

## Overview

`/spec` 実行時、Spec の振り返りセクション（`## Design Gaps/Ambiguities` 等）に記録した実装時の知見（変数名・呼び出し形式・パラメータ渡しなど）が、対応する `## Implementation Steps` 本文に反映されないケースを構造的に防止するため、`skills/spec/skill-dev-constraints.md` の SHOULD 制約テーブルに補記ルールを追加する。

`/code`・`/review` フェーズは Implementation Steps 本文を順に辿るため、retrospective セクションだけに記載された知見は構造的に見落とされやすい（発生例: #575 — Design Gaps に args 渡し形式を記録したが Implementation Step 3(c) 本文には反映されず、review で事後指摘）。

## Changed Files

- `skills/spec/skill-dev-constraints.md`: SHOULD 制約テーブルに Design Gaps → Implementation Steps 補記ルールの行を追加

## Implementation Steps

1. `skills/spec/skill-dev-constraints.md` の SHOULD 制約テーブル末尾に下記の行を追加する（→ 受入条件 1・2）:

   | Design Gaps → Implementation Steps backfill | When recording specific implementation knowledge (variable names, call forms, parameter passing methods) in spec retrospective sections (e.g., `## Design Gaps/Ambiguities`, `## Implementation Notes`), also write it directly in the corresponding `## Implementation Steps` body. `code` and `review` phases follow Implementation Steps sequentially — knowledge recorded only in retrospective sections is structurally prone to being overlooked | #579 |

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/spec/skill-dev-constraints.md" "Design Gaps" --> `skill-dev-constraints.md` に Design Gaps 補記ルールが追加されている
- <!-- verify: grep "Implementation Step|実装ステップ" "skills/spec/skill-dev-constraints.md" --> 補記先（Implementation Step 本文）が明示されている

### Post-merge

- 次回 L 以上の spec phase 実行で、Design Gaps セクションの知見が Implementation Steps 本文にも反映されることを確認

## Notes

- ISSUE_TYPE=Task のため UI Design・Uncertainty セクションは省略
- 変更対象は `skills/spec/skill-dev-constraints.md` 単一ファイル（domain file）であり、skill/agent/script の追加・削除ではないため `docs/structure.md` や `docs/workflow.md` の更新は不要
- **verify command 2 の弱さ（auto-resolve）**: `grep "Implementation Step|実装ステップ"` は実施前から "Implementation Steps" が複数箇所に存在するため、変更前後で PASS となり検証力が低い。意味のある検証は verify command 1（"Design Gaps" の初出確認）。verify command はイシューボディから verbatim コピーのため変更しないが、この弱さを記録する。
- 追加する行の `Reference` 列には `#579` を使用（発生元は `#575` だが、ルール化 Issue は `#579`）
