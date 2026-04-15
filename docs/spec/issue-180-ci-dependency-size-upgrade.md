# Issue #180: Size 判定に CI 依存度の最小 Size オーバーライドを追加

## Overview

`modules/size-workflow-table.md` の 2 軸 Size 判定フローに、CI 依存度による最小 Size オーバーライドルールを追加する。
`.github/workflows/*.yml` 変更やテスト並列化など、正当性検証が CI 実行に依存する変更は、ファイル数・複雑度に関わらず **Size M 以上** に格上げする。
これにより patch route（main 直接コミット）経由での CI 未検証マージリスクを構造的に低減する。

背景: Issue #177（`bats --jobs 4` 並列化）で顕在化。Size S→patch route を選択した結果、CI 実行がマージ後になり race condition を main ブランチ上で検出した（リバート: コミット 63895ae）。

## Changed Files

- `modules/size-workflow-table.md`: "Size Determination Flow" の図を更新し「CI dependency check」ステップを追加; Axis 2 直後に「CI Dependency Minimum Override」セクションを新設
- `skills/triage/SKILL.md`: Step 6 の説明文「2-axis method」を「2-axis + CI dependency check」へ変更

## Implementation Steps

1. `modules/size-workflow-table.md` を更新する (→ 受入れ基準 A, B, D)
   - "Size Determination Flow" の Mermaid/テキスト図を次のように更新:
     ```
     Estimated file count → Provisional Size → Complexity adjustment (±1 step) → CI dependency check → Final Size → Workflow selection
     ```
     ※ 「CI dependency check」ステップを Axis 2 の後、Final Size の前に挿入
   - Axis 2 セクション直後に「### CI Dependency Minimum Override」セクションを追加（以下の内容）:
     - Axes 1–2 適用後、変更ファイルに以下パターンがあれば Final Size を **M at minimum** へ格上げ
     - 対象パターン表（`.github/workflows/*.yml`、`tests/` 並列化・fixture 共有構造変更、CI 環境依存の検証変更）
     - 各パターンの理由（patch route ではマージ後 CI、PR route ではマージ前 CI）
     - `**Minimum upgrade target: Size M**`（PR route 強制; CI がマージ前に実行される）
     - 付記: このオーバーライドは加算的 — Axes 1–2 が L/XL の場合はその結果を維持
   
2. `skills/triage/SKILL.md` Step 6 を更新する (after 1) (→ 受入れ基準 C)
   - 既存テキスト: `Size determination flow (2-axis method) to determine Size.`
   - 変更後: `Size determination flow (2-axis + CI dependency check) to determine Size.`

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/size-workflow-table.md" "CI" --> `modules/size-workflow-table.md` に CI 依存度ルールが追加されている
- <!-- verify: file_contains "modules/size-workflow-table.md" ".github/workflows" --> 格上げ対象パターン（`.github/workflows/*.yml`）が明示されている
- <!-- verify: file_contains "skills/triage/SKILL.md" "size-workflow-table" --> `skills/triage/SKILL.md` Step 6 から `size-workflow-table` を参照している
- <!-- verify: file_contains "modules/size-workflow-table.md" "Size M" --> 格上げの最低 Size M が明示されている

### Post-merge

- 次回以降の `/triage` で `.github/workflows/*.yml` を含む Issue が Size M 以上に判定されることを観測

## Notes

- `docs/ja/workflow.md` は「2 軸基準」と記載しているが、translation output のため実装対象外（`/doc translate ja` で再生成する場合は自動更新される）
- オーバーライドルールはあくまで **加算的**（Axis 2 の ±1 ステップと独立）。LOC/file count ベース判定は廃止しない（Non-Goals 準拠）
- 格上げパターンは「ファイルパスベースのヒューリスティック」として設計。高度な自動判定は Non-Goals
- 既存 auto-memory `feedback_ci_sensitive_size_m.md` と同内容を distributable layer（`size-workflow-table.md`）へ昇格させる位置付け
