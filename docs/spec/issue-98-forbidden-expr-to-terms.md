# Issue #98: terminology: Forbidden Expressions の用語エントリを Terms に統合

## Overview

`docs/tech.md` Forbidden Expressions テーブルに混在する「技術的制約」と「用語統一」の2種類エントリのうち、用語統一エントリ（Design file、Issue Spec、Verify hint、Dispatch、および #94 で追加予定の Acceptance check）を `docs/product.md` Terms の "Formerly called" に統合し移動する。Forbidden Expressions には技術的制約（半角 `!`）のみを残す。また Terminology Migration Scope Rule の参照先を Forbidden Expressions から Terms "Formerly called" に更新する。日本語ミラー（`docs/ja/`）も同期する。

本 Issue は #94 のマージ後に実施する（#94 が "Acceptance check" を Forbidden Expressions に追加するため）。

## Changed Files

- `docs/product.md`: Terms テーブルの Spec エントリに "Formerly called 'Design file' / 'Issue Spec'" を追加、/auto エントリに "Formerly called 'Dispatch'" を追加
- `docs/tech.md`: Forbidden Expressions から Design file・Issue Spec・Verify hint・Dispatch・Acceptance check（#94 追加分）の行を削除、Terminology Migration Scope Rule のテキストを "Terms 'Formerly called'" 参照に更新
- `docs/ja/tech.md`: Forbidden Expressions から同じ用語行を削除（Design file・Issue Spec・Verify hint・Dispatch・Acceptance check）、用語移行のスコープルールのテキストも同期更新
- `docs/ja/product.md`: Terms の Spec エントリに「旧称「Design file / Issue Spec」」を追加、/auto エントリに「旧称「Dispatch」」を追加

## Implementation Steps

1. `docs/product.md` Terms 更新: Spec 行の Definition 末尾に ". Formerly called 'Design file' / 'Issue Spec'" を追加、/auto 行の Definition 末尾に ". Formerly called 'Dispatch'" を追加 (→ 受入条件 1, 2)
2. `docs/tech.md` Forbidden Expressions 更新: Design file・Issue Spec・Verify hint・Dispatch の行を削除（#94 マージ後に Acceptance check 行も削除）; Half-width `!` 行のみ残す (→ 受入条件 4-9)
3. `docs/tech.md` Terminology Migration Scope Rule 更新: "adds deprecated terms to Forbidden Expressions" → "adds deprecated terms to Terms 'Formerly called'" に変更; 日本語 `docs/ja/tech.md` の用語移行のスコープルールも "Terms の 'Formerly called'" 参照に更新 (→ 受入条件 10)
4. `docs/ja/tech.md` Forbidden Expressions 更新: Step 2 と同じ用語行（Design file・Issue Spec・Verify hint・Dispatch・Acceptance check）を削除; 半角 `!` 行のみ残す (→ 受入条件 11)
5. `docs/ja/product.md` Terms 更新: Spec 行の定義末尾に「旧称「Design file / Issue Spec」」を追加、/auto 行の定義末尾に「旧称「Dispatch」」を追加 (→ 受入条件 12)

## Verification

### Pre-merge

- <!-- verify: grep "Formerly called.*Design file" "docs/product.md" --> Spec の Terms エントリに "Formerly called 'Design file' / 'Issue Spec'" が記載されている
- <!-- verify: grep "Formerly called.*Dispatch" "docs/product.md" --> `/auto` の Terms エントリに "Formerly called 'Dispatch'" が記載されている
- <!-- verify: grep "Formerly called.*Acceptance check" "docs/product.md" --> verify command の Terms エントリに "Formerly called" に "Acceptance check" が含まれている
- <!-- verify: section_not_contains "docs/tech.md" "## Forbidden Expressions" "Design file" --> `docs/tech.md` Forbidden Expressions から "Design file" が除去されている
- <!-- verify: section_not_contains "docs/tech.md" "## Forbidden Expressions" "Issue Spec" --> `docs/tech.md` Forbidden Expressions から "Issue Spec" が除去されている
- <!-- verify: section_not_contains "docs/tech.md" "## Forbidden Expressions" "Verify hint" --> `docs/tech.md` Forbidden Expressions から "Verify hint" が除去されている
- <!-- verify: section_not_contains "docs/tech.md" "## Forbidden Expressions" "Dispatch" --> `docs/tech.md` Forbidden Expressions から "Dispatch" が除去されている
- <!-- verify: section_not_contains "docs/tech.md" "## Forbidden Expressions" "Acceptance check" --> `docs/tech.md` Forbidden Expressions から "Acceptance check" が除去されている
- <!-- verify: section_contains "docs/tech.md" "## Forbidden Expressions" "Half-width" --> `docs/tech.md` Forbidden Expressions に技術的制約（半角 `!`）が残っている
- <!-- verify: grep "Terms.*Formerly called" "docs/tech.md" --> Terminology Migration Scope Rule が Terms "Formerly called" 追加を参照する形に更新されている
- <!-- verify: section_not_contains "docs/ja/tech.md" "## Forbidden Expressions" "Design file" --> `docs/ja/tech.md` Forbidden Expressions から用語エントリが除去されている
- <!-- verify: grep "旧称.*Design file" "docs/ja/product.md" --> `docs/ja/product.md` Terms に Spec の旧称が記載されている

### Post-merge

- `/verify 98` で全12項目が自動検証にてパスすること
- `docs/product.md` Terms を目視確認し、Spec エントリと /auto エントリに "Formerly called" 記述が自然な形で組み込まれていること
- `docs/tech.md` Forbidden Expressions が半角 `!` の1行のみになっていること

## Notes

- 受入条件3（`Formerly called.*Acceptance check`）は現時点で既にパスしている（verify command の Terms エントリが "Formerly called 'verification hint / Acceptance check'" を含む）。ただし実装時も確認すること
- 受入条件8（`section_not_contains Acceptance check`）は現時点でパスしているが、#94 マージ後に Acceptance check が Forbidden Expressions に追加されるためフェイルに転じる。本 Issue では Step 2 でこれを除去する
- `docs/ja/tech.md` の用語移行スコープルール（「Forbidden Expressions に非推奨用語を追加する」）も英語側と合わせて「Terms の 'Formerly called' に追加する」に更新する
- 日本語ミラーの受入条件はDesign file除去のみ検証するが、実装時は Issue Spec・Verify hint・Dispatch（・Acceptance check）も同様に `docs/ja/tech.md` から除去すること

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- 受入条件8（`section_not_contains Acceptance check`）は Spec 作成時点では "pending (#94 マージ後にフェイルになる)" と注記されていたが、実装時点でも #94 は未マージのため Acceptance check は Forbidden Expressions に存在せず、条件は既にパスしていた。Spec の Step 2 では「#94 マージ後に Acceptance check 行も削除」と記載されていたが、実際は削除対象行がなかったため削除処理をスキップした。

### Rework

- N/A
