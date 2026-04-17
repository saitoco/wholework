# Issue #216: 並列 sub-agent 起動指示を明示化 (Opus 4.7 保守的スポーン対策)

## Overview

Opus 4.7 は Opus 4.6 と比べてデフォルトで sub-agent を積極的にスポーンしない挙動に変化した。`/issue` Step 11a（L/XL Issue の 3 並列調査）と `/review` Step 10.2（`review-spec` + `review-bug`×2 の 3 並列）で、Opus 4.7 でも並列 fan-out が保証されるよう、「単一メッセージ内で N 個の Task を並列起動する」指示を明示化する。

追加文言（英語）: `in a single message to ensure parallel fan-out (Opus 4.7 may otherwise serialize the spawns)`

## Changed Files

- `skills/issue/SKILL.md`: Step 11a の並列起動指示行に "in a single message" 文言を追加
- `skills/review/SKILL.md`: Step 10.2 sub-step 3 の Task コードブロック直前に "in a single message" 文言を追加

## Implementation Steps

1. `skills/issue/SKILL.md` Step 11a の変更（→ 受け入れ条件 1, 3）
   - 現在の行 334: `Get steering doc paths with Glob. Launch 3 agents in parallel:`
   - 変更後: `Get steering doc paths with Glob. Launch these 3 subagents in a single message to ensure parallel fan-out (Opus 4.7 may otherwise serialize the spawns):`

2. `skills/review/SKILL.md` Step 10.2 sub-step 3 の変更（→ 受け入れ条件 2, 4）
   - Task コードブロック（`` ```text `` 開始行）の直前に以下の行を追加する（空行を挟む）:
     ```
     Launch these subagents in a single message to ensure parallel fan-out (Opus 4.7 may otherwise serialize the spawns):
     ```
   - 挿入位置: `SKIP_REVIEW_BUG=false` の説明行（review-bug agent 2 の説明行）と `` ```text `` の間の空行の後

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/issue/SKILL.md" "Step 11a" "in a single message" --> `/issue` Step 11a セクションに "in a single message" 文言が追加されている
- <!-- verify: section_contains "skills/review/SKILL.md" "10.2" "in a single message" --> `/review` Step 10.2 セクションに "in a single message" 文言が追加されている
- <!-- verify: grep "in a single message" "skills/issue/SKILL.md" --> `/issue` SKILL.md に "in a single message" の指示が grep で検出できる
- <!-- verify: grep "in a single message" "skills/review/SKILL.md" --> `/review` SKILL.md に "in a single message" の指示が grep で検出できる

### Post-merge

- L/XL サイズ Issue で `/issue N` を実行し、`issue-scope` / `issue-risk` / `issue-precedent` の 3 並列 Task が単一メッセージで起動することをログから確認
- PR に対して `/review` を full モードで実行し、`review-spec` + `review-bug`×2 の 3 並列 Task が単一メッセージで起動することを確認 (`SKIP_REVIEW_BUG=true` 設定時は `review-spec` 単独起動)

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
- `/issue` skill が verify コマンドの脆弱性（"N Task" 文字列マッチ）を事前に検出し、`section_contains` + `grep` の組合せに再設計した。この判断により verify が確実に実行可能になった
- 受け入れ条件の verify コマンドが具体的で自動化しやすく、verify フェーズでの UNCERTAIN がゼロになった

#### design
- 実装がデザインに完全一致。追加文言も Spec で指定した通りに実装された
- Spec の "Changed Files" と "Implementation Steps" が正確で、実装側の判断余地がほぼなかった

#### code
- リワークなし。単一のクリーンなコミット（509a70a）で実装完了
- Size=S（2ファイルのテキスト追加）と評価されており、対象範囲が明確に絞られていた

#### review
- パッチルート（PR なし）のため正式なコードレビューなし。Size=S かつロジック変更なしの軽微な変更のためスキップは適切

#### merge
- main への直接コミット（パッチルート）。コンフリクトなし

#### verify
- 全 4 条件が PASS。Post-merge opportunistic 条件は実際の動作確認が必要なためユーザー検証に委ねた
- パッチルートのため PR_NUMBER が空で、`github_check "gh pr checks"` を使用した条件は存在しなかった（問題なし）

### Improvement Proposals
- N/A
