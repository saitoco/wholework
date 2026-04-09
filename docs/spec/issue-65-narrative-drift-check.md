# Issue #65: feat: /doc sync --deep に narrative セクションの意味的ドリフト検出を追加

## Overview

`/doc sync --deep` の normalization flow（Step 6-9）に、AI 判定ベースの narrative semantic drift check を追加する。これにより、`ssot_for` カテゴリ宣言なしで Architecture Decisions / Non-Goals / Coding Conventions 等の narrative セクションに対する partial description drift / missing coverage / obsolete mention を検出できるようにする。検出結果は既存の Step 7 "Drift report" パスに流し、auto-fix せず常にユーザー判定に委ねる。

あわせて、`modules/codebase-analysis.md` の実装スキャン結果が normalization flow でも確実に利用可能になるよう、Step 6 の "Load analysis sources" 記述を曖昧さなく明示する（現状「Step 2 と同じ手順」という参照だけでは --deep 時の codebase analysis 実行が normalization flow で保証されない）。

## Changed Files

- `skills/doc/SKILL.md`:
  - Step 6 "Load analysis sources and Steering Documents" に --deep 時の codebase-analysis.md 実行を明示する追記
  - Step 6 "Cross-skill consistency check" の直後に新 sub-step "Narrative Semantic Drift Check (--deep only)" を追加
  - Step 6 の Classification 一覧（Duplicate / Drift / Unreflected）に narrative drift 3 種（Missing coverage / Partial description / Obsolete mention）の位置づけを追記
  - Step 7 の "Drift report" 説明に narrative drift findings が含まれる旨を追記

## Implementation Steps

1. `skills/doc/SKILL.md` Step 6 の "Load analysis sources and Steering Documents:" パラグラフに、`--deep` フラグ有効時は `modules/codebase-analysis.md` の Processing Steps を実行し結果を保持する旨を明示（"same procedure as Step 2" の曖昧さを解消し、normalization flow でも codebase analysis 結果が利用可能になる）(→ acceptance criteria 2)
2. `skills/doc/SKILL.md` Step 6 の "Cross-skill consistency check" 直後に新 sub-step "**Narrative Semantic Drift Check (--deep only)**" を追加。内容: (a) 対象 narrative セクションの特定基準（散文中心のセクション、AI 判定）、(b) 入力（narrative セクション本文 + codebase-analysis 結果 + "Scan implementation code" で収集した skills/*/SKILL.md, modules/*.md 等）、(c) 検出 3 種の定義（Missing coverage / Partial description / Obsolete mention）、(d) drift report として Step 7 に積む旨、(e) `--deep` 限定である旨 (→ acceptance criteria 1, 3, 5)
3. `skills/doc/SKILL.md` Step 7 "Drift report" 箇条の説明に、narrative semantic drift check からの findings もこの経路で出力され auto-fix されない旨を 1 行追記 (→ acceptance criteria 4)
4. Self-check: SKILL.md 内で 5 つの acceptance criteria キーワード（"narrative" / "codebase-analysis" が "sync Bidirectional Normalization" セクション内 / "partial description" / "drift report" / "--deep"）がすべて新追加箇所に含まれていることを Grep で確認

## Verification

### Pre-merge
- <!-- verify: file_contains "skills/doc/SKILL.md" "narrative" --> `skills/doc/SKILL.md` に narrative セクション向けの semantic drift check の記述が追加されている
- <!-- verify: section_contains "skills/doc/SKILL.md" "sync Bidirectional Normalization" "codebase-analysis" --> normalization flow（Step 6 以降）で `modules/codebase-analysis.md` の結果を再利用する記述が追加されている
- <!-- verify: file_contains "skills/doc/SKILL.md" "partial description" --> partial description drift（記述はあるが不完全）を検出対象として明示している
- <!-- verify: file_contains "skills/doc/SKILL.md" "drift report" --> narrative drift は auto-fix せず drift report として Step 7 の normalization proposals に積む記述がある
- <!-- verify: file_contains "skills/doc/SKILL.md" "--deep" --> 追加される semantic drift check は `--deep` モードのみで実行される旨が明記されている

### Post-merge
- 実際に `/doc sync --deep` を wholework リポジトリで実行し、`docs/tech.md` L41 の "Sub-agent splitting" に関する partial description drift（`/issue` の sub-agent 利用未記載）が drift report として検出される <!-- verify-type: opportunistic -->
- wholework 以外のプロジェクト（ユーザーの実プロジェクト想定）で `/doc sync --deep` を実行し、Architecture Decisions に対する narrative drift が検出・提示される動作を確認する <!-- verify-type: manual -->

## Notes

### 実装方針（Issue 議論から継承）

- **AI 判定ベース**: 既存の Grep ベース・カテゴリ駆動の仕組みを拡張するのではなく、AI による semantic 比較で新 sub-step を追加する。`/audit drift` Step 2 と同様のアプローチだが、出力先は doc 側修正提案（Step 7）であり、code 側 Issue 生成ではない
- **常に drift report**: narrative 判定は false positive が出やすいため auto-fix しない。Step 7 の 3 つのアクションのうち "Drift report" 経路のみを使う
- **`--deep` 限定**: AI 判定コストを避けるため、通常の `/doc sync` では実行しない
- **既存機構との併存**: `ssot_for` カテゴリ駆動の検出経路（Step 6 後半 "Content classification based on dynamic SSoT mapping"）は変更しない。narrative drift check は追加経路として並行動作する

### 設計の曖昧さと解消

現状の Step 6 "Load analysis sources and Steering Documents" は `using the same procedure as "Step 2 (Reverse-Generation Flow — Explore Analysis Sources)"` と記述しているが、Step 2 には `--deep` 時の codebase-analysis.md 実行と .md 統合スキャン等の複数サブプロシージャが含まれる。"same procedure" がファイル読込部分だけを指すのか全体を指すのか曖昧で、normalization flow で codebase analysis 結果が使えるかが仕様上不確定になっている。本 Issue の Step 1 でこの曖昧さを明示的に解消する（= normalization flow でも --deep 時は codebase-analysis を実行）。

### narrative セクション判定

固定リスト（例: "Architecture Decisions" 等）ではなく、AI が各セクションの構造を見て narrative/structured を判定する方針。理由: ユーザープロジェクトごとに steering doc のセクション名が異なるため固定リストは汎用性を損なう。判定ヒューリスティック例: 構造化テーブルのみのセクションは structured、散文・箇条書き中心は narrative。

### 3 種検出カテゴリの定義

| カテゴリ | 定義 | 例 |
|---|---|---|
| Missing coverage | 実装に存在する重要パターンが steering doc に全く記述されていない | 新規導入されたエージェントが Architecture Decisions で言及なし |
| Partial description | 既存記述が特定ケースのみに言及し、同型パターンの他事例が未記載 | "Sub-agent splitting: `/review` splits..." のみで `/issue` の parallel investigation 未記載 |
| Obsolete mention | 実装から消えた要素の記述が残存 | 削除済みエージェントへの参照が残存 |

### 変更範囲の制約

- `skills/doc/SKILL.md` のみを変更対象とする
- `modules/codebase-analysis.md` は変更しない（既存インターフェースをそのまま再利用）
- `modules/skill-dev-checks.md` への cross-check 追加はスコープ外（前の案検討で wholework 開発リポジトリ専用のため却下）
- `scripts/validate-skill-syntax.py` の MUST 制約（半角 `!` 禁止、decimal step 禁止など）を満たすこと
- テストコード追加はスコープ外: narrative drift check は AI 判定ベースのため bats で決定論的に検証できない。動作確認は Post-merge の opportunistic/manual verify で行う

## Code Retrospective

### Deviations from Design

- "partial description" (小文字) キーワード: Spec では検出対象として明示するとあったが、実装時に table header が "Partial description" (大文字P) になっていたため `file_contains` チェックが失敗した。Introduction paragraph に "(missing coverage, partial description, obsolete mention)" と小文字で記述することで対応。Spec に「小文字を含む表現を必ず使うこと」という指定はなかったが実用上必要な追加。

### Design Gaps/Ambiguities

- Spec の Implementation Steps では "narrative" キーワードの出現位置について明示がなく、大文字/小文字の混在に起因する `file_contains` の失敗リスクが書かれていなかった。acceptance check は case-sensitive であるため、実装時に lowercase 確認が必要。

### Rework

- Step 4 の self-check で "partial description" が 0 件と判明し、Introduction paragraph に lowercase 版を追記する rework が 1 回発生した。
