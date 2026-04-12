# Issue #135: spec: 新規出力ディレクトリを生成するSkill追加時にdocs/structure.mdのChanged Files記載を必須化

## Issue Retrospective

### Triage 結果
- Type=Task, Size=XS, Priority=low, Value=2
- Size XS: `skills/spec/SKILL.md` の SHOULD リストへの 1 行追記で完結するため

### 判断根拠 (auto-resolved ambiguity points)

- **AC #1 verify command の変更**: 元の `grep "output director"` を `file_contains "skills/spec/SKILL.md" "output director"` に置換。`/review` safe mode の UNCERTAIN を避け、専用コマンドを優先する wholework の方針に合わせた。部分一致で "output directory" / "output directories" 双方を検出可能。
- **AC #2 の具体例依存の解消**: 元の `file_contains "docs/stats"` は `/audit stats` の具体例そのものであり、将来他の出力ディレクトリ例に差し替えられるとルール側も書き換えが必要になる脆弱性があった。代わりに追記位置 (SHOULD セクション内) を `section_contains` で検証するよう変更。
- **Post-merge 条件の追加**: ルール追記の「実効性」を検証する条件が無かったため、future Spec 実行時の観測を `verify-type: manual` で追加。実際の効果は将来 Issue でしか確認できない特性。

### 分割判定
- 単一ファイル (`skills/spec/SKILL.md`) への 1 行 (= SHOULD-level リスト 1 項目) 追記で完結。分割不要、XS 維持。

### Related Issues
- 兄弟 Issue #136 (ghコマンドの allowed-tools 必須化) は同じ verify retrospective から派生した別トピック。依存関係なしで並行実装可能。

## Refinement Retrospective

### Design decisions (確定事項)

- **ルール対象範囲**: 新規出力 **ディレクトリ** のみ（ユーザー確認済み）。単一ファイル出力は別途統合の余地を残して対象外。#75 の発端事例と一致。

### Auto-resolved points

1. **Mermaid 更新は対象外**: 出力ディレクトリは Directory Layout tree の領域であり、Mermaid graph（modules/agents 依存関係用）には関係しない。既存 new modules ルールが両方に言及しているが、本ルールは tree のみ。
2. **既存 AC2 削除**: `file_contains "docs/stats"` を必須化するのは恣意的（Issue 本文の「具体的な文言は実装者判断」と矛盾）。AC1 がルール追加を検証しており冗長。
3. **配置位置**: `skills/spec/SKILL.md` の SHOULD-level acceptance criteria consideration セクション、`For new modules:` 行の直後に対称配置。

### Acceptance criteria 変更

- 旧 2 条件（pre-merge）→ 新 2 条件（pre-merge）+ opportunistic 1 条件（post-merge）。
- verify コマンドを `file_contains "output director"` と `section_contains ... "structure.md"` に統一し、具体的な文言を要求せずルールの追加場所と内容を検証。
- post-merge opportunistic 条件を追加し、次回の実機適用で自動検知できるように。
