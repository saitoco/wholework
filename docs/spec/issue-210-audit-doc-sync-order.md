# Issue #210: docs: /audit drift と /doc sync --deep の推奨実行順序を明記

## Overview

`/audit drift` と `/doc sync --deep` の検出ロジックは実質的に重複しているが、現在のドキュメントは両者の関係を `docs/workflow.md` line 151 で "Complementary to `/doc sync`" と 1 行触れているだけで、推奨される実行順序が示されていない。このため、ドキュメント更新で吸収できる drift に対しても `/audit drift` が Issue を起票する運用が発生しうる。

本 Issue では `/doc sync --deep` を「ドキュメント正規化の第一段階」、`/audit drift` を「残存する semantic drift（コード改修が必要なもの）の検出」として位置付け、推奨実行順序をドキュメントに明記する。検出ロジック自体は両方に残し（セーフティネット）、運用規律で重複を解消する。`/audit drift` 側への fix-direction 分類追加や runtime チェックは Out of Scope。

## Changed Files

- `skills/audit/SKILL.md`: drift subcommand 冒頭（"## drift Subcommand" セクションの導入段落直後、Option Parsing の前）に、`/doc sync --deep` の事前実行を推奨する note ブロックを追加
- `docs/workflow.md`: `### /audit — Drift and Fragility Detection` セクションの "Complementary to `/doc sync`" を具体化し、`/doc sync --deep` を first に実行する推奨順序を明示する文に書き換える（`doc sync --deep` と `first` の 2 キーワードを含める）
- `docs/ja/workflow.md`: `docs/workflow.md` の変更に対応する日本語訳を同期更新（`docs/*.md` と 1:1 対応のミラーファイル）

## Implementation Steps

1. `skills/audit/SKILL.md` の `## drift Subcommand` セクション冒頭（既存の導入段落 "Detect semantic drift between Steering Documents + Project Documents..." の直後、`### Option Parsing` ヘディングの前）に、推奨運用を示す note ブロックを追加する。文面は「`/doc sync --deep` を先に実行してドキュメント側の drift を吸収してから `/audit drift` を実行することを推奨（コード改修が必要な semantic drift に集中できる）」という趣旨を英語で記述（→ acceptance criteria 1）
2. `docs/workflow.md` line 151 の `### /audit — Drift and Fragility Detection` セクション内、`Complementary to /doc sync (which proposes document-side fixes).` の部分を、`/doc sync --deep` を first に実行する推奨順序を具体的に明示する文に書き換える。文面には `doc sync --deep` と `first` の 2 キーワードを含める（→ acceptance criteria 2, 3）
3. `docs/ja/workflow.md` line 144 の対応する日本語訳を `docs/workflow.md` の変更に合わせて同期更新（翻訳ミラー）

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/audit/SKILL.md" "doc sync --deep" --> `skills/audit/SKILL.md` drift subcommand の冒頭付近に `/doc sync --deep` の事前実行を推奨する note が追加されている
- <!-- verify: section_contains "docs/workflow.md" "### `/audit` — Drift and Fragility Detection" "doc sync --deep" --> `docs/workflow.md` の `/audit` セクションに `/doc sync --deep` との実行順序に関する記述が追加されている
- <!-- verify: section_contains "docs/workflow.md" "### `/audit` — Drift and Fragility Detection" "first" --> 実行順序（`/doc sync --deep` が先、`/audit drift` が後）が明示的に記述されている

### Post-merge

- 次回以降 `/audit drift` 実行時、冒頭の note により `/doc sync --deep` の事前実行が利用者に認識されること

## Notes

- Size=S（patch route、SPEC_DEPTH=light）。直接 main にコミットする想定。
- 検出ロジック自体は `/audit drift` と `/doc sync --deep` の双方に残す（セーフティネット）。運用規律（ドキュメント誘導）で重複を解消する方針。
- `docs/ja/workflow.md` は `docs/workflow.md` の 1:1 翻訳ミラーのため同期更新対象に含めた。verify command は英語版 `docs/workflow.md` のみを対象とするため、日本語ミラー側の文言は自然な日本語に訳してよい（英語キーワード `doc sync --deep` / `first` を含める必要はない）。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
