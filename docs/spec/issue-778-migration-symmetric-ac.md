# Issue #778: spec: migration Issue で SKILL.md と実装スクリプト両層への対称的 file_not_contains AC を Spec template に追加

## Overview

migration / rename / path 変更を伴う Issue では、SKILL.md (markdown 記述) と bash スクリプト (実装側) の2層が存在するが、`/spec` が生成する `file_not_contains` AC は SKILL.md 側にのみ適用され、bash スクリプト側の旧 path 残存を検出できない死角がある。

実例: Issue #772 の AC8 `file_not_contains "skills/auto/SKILL.md" "docs/reports/loop-state-"` は PASS したが、同等機能を実装する `scripts/append-loop-state-heartbeat.sh` 側の旧 path 残存は検出できず、review フェーズで初めて発覚 (commit d0a9288)。

`modules/verify-patterns.md` に新ガイダンスセクション (§16) を追加し、`/spec` 実行時の設計死角を構造的に排除する。

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — 自動解決した曖昧ポイント3件を記録。AC1 verify command の実装前 PASS 問題を `rubric + grep "Migration"` 組み合わせに変更、実装ターゲットを `modules/verify-patterns.md` に決定、専用テンプレートファイル不作成の方針を確認。[link](https://github.com/saitoco/wholework/issues/778#issuecomment-4820838956)

## Changed Files

- `modules/verify-patterns.md`: add §16 "Migration / Rename / Path-change Issues — Apply file_not_contains to Both SKILL.md and Script Layers" section — bash 3.2+ compatible (no bash-specific features used; pure markdown addition)

## Implementation Steps

1. `modules/verify-patterns.md` の末尾 (現 §15 直後) に §16 セクションを追加する (→ AC1, AC2)
   - セクションタイトル: `### 16. Migration / Rename / Path-change Issues — Apply file_not_contains to Both SKILL.md and Script Layers`
   - 追加内容の構成:
     - **Background**: migration/rename/path 変更 Issue では SKILL.md と bash スクリプトの2層に同等機能が分散することが多い。SKILL.md 側の `file_not_contains` が PASS しても、スクリプト側に旧 path が残存する死角がある (実例: Issue #772 AC8)。
     - **Recommended Pattern**: SKILL.md 側と実装スクリプト側の両方に対称的な `file_not_contains` を設計する具体例を記載:
       ```
       <!-- verify: file_not_contains "skills/auto/SKILL.md" "docs/reports/old-path-" -->  SKILL.md 側の旧 path 削除確認
       <!-- verify: file_not_contains "scripts/impl-script.sh" "docs/reports/old-path-" -->  実装スクリプト側の旧 path 削除確認
       ```
     - **Detection procedure**: migration/rename/path 変更 Issue で `/spec` AC を設計する際、`grep -rn 'old-path' .` で参照ファイルを列挙し、SKILL.md 以外の実装スクリプトを確認するステップを明示する。
     - **Note**: スクリプト側の旧 path 残存は CI が検出できない (テストカバレッジ外); `file_not_contains` AC による明示的チェックが唯一の自動検出手段。

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-patterns.md に migration / rename / path 変更 Issue での SKILL.md と実装スクリプト両層への対称的 file_not_contains 適用ガイドが追記されている" --> migration / rename / path 変更 Issue での対称的 `file_not_contains` AC ガイドが `modules/verify-patterns.md` に追記されている
- <!-- verify: grep "Migration" "modules/verify-patterns.md" --> `modules/verify-patterns.md` に "Migration" セクションが存在する
- <!-- verify: rubric "migration を伴う Issue の Spec template / AC 設計ガイドで、SKILL.md と実装スクリプト両方の旧 path 削除を verify command で検証する具体例が含まれている" --> ガイダンス内に SKILL.md + 実装スクリプト両層をカバーする `file_not_contains` 具体例が提示されている

### Post-merge

- 次回 migration Issue (path 変更を伴う) で Spec 生成時に SKILL.md + script の対称的 `file_not_contains` AC が含まれる

## Notes

- 実装ターゲットは `modules/verify-patterns.md`。`skills/spec/SKILL.md` は `modules/verify-patterns.md` を `Read` して参照するため、modules 側への追加で `/spec` 実行時に自動的にガイドが適用される。
- 専用テンプレートファイル (e.g., `docs/spec/migration-template.md`) は作成しない。`modules/verify-patterns.md` の §16 がテンプレートの役割を担う。
- docs/ja/ への翻訳同期は不要 (verify-patterns.md は modules/ 配下; 翻訳対象の docs/ja/ には対応ファイルが存在しない)。
