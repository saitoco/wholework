# Spec: あいまいさ抽出の上限件数の SSoT を ambiguity-detector に一本化 (#1085)

No Spec existed prior to `/code` (Issue already had `phase/ready` when this run started; Size=XS). Requirements were read directly from the Issue body, including its `## 対応方針 (案)` section.

## Implementation Steps

1. `skills/spec/SKILL.md` Step 7 (Ambiguity Resolution) の固定上限記述「extract **at most 3** ambiguity points」を、`modules/ambiguity-detector.md` の Size Routing Table (Detection Limit) を参照する記述に置き換えた。Step 2 で取得済みの Size を根拠に判定する旨も明記した。

## Code Retrospective

### Deviations from Design
- N/A — Issue 本文の「対応方針 (案)」に記載された修正方針 (Size Routing Table を参照する記述への置換) をそのまま適用した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `skills/issue/SKILL.md:506` (Existing Issue Refinement Step 6) の既存参照形式 ("XS/S/M or unset → **at most 3**; L/XL → **at most 5**") にならい、`skills/spec/SKILL.md:226` も同じ表現スタイルで Size Routing Table を参照する形に統一した。
- `skills/issue/SKILL.md:51` (New Issue Creation Step 5) の「extract **at most 3** ambiguity points」はそのまま残した — 新規 Issue 作成フローでは Size が定義上 unset であり、Size Routing Table の Unset 行 (Max 3) と矛盾しないため、今回の食い違い修正の対象外と判断した。

### Deferred Items
- なし

### Notes for Next Phase
- Pre-merge AC1-4 (rubric 2件 + section_contains 1件 + command 1件) は `/code` 内で検証し全て PASS、Issue 本文のチェックボックスも更新済み。
- Behavioral Change Detection により `bats --jobs 18 tests/` (フルスイート) を実行し、1786 件全て PASS を確認済み。
- Post-merge AC (`verify-type: manual` — Size L の Issue を `/spec` に通し、あいまいさ抽出が最大 5 件の上限で動作することを確認する) は未実施のまま残している。

## Issue Retrospective

### 実施内容

- Background Factual Claim Verification: `skills/spec/SKILL.md:205` / `modules/ambiguity-detector.md:30-36` への言及を検証したところ、内容自体は正確だったが `skills/spec/SKILL.md` 側の該当行が既に L226 にドリフトしていた (Issue 起票後の別編集による行番号ズレ)。Background / 対応方針 / Related の行番号参照を L205 → L226 に更新。
- 重複記述の横断確認: `grep -rn "at most 3\|at most 5"` で `skills/spec/SKILL.md:226` 以外の該当箇所 (`skills/issue/SKILL.md:51,506`) を確認したが、いずれも Size Routing Table と整合する記述だった (Unset→Max3, XS/S/M→Max3/L/XL→Max5 の対応が正しい) ため、修正対象は `skills/spec/SKILL.md:226` の 1 箇所のみと確定。AC2 (「他に同じ上限値を独自に記述している箇所が残っていないこと」) の検証範囲として記録。
- `/spec` の Size 取得タイミングを確認 (`skills/spec/SKILL.md:36`、Step 2 で取得): あいまいさ抽出 (Step 7, L226) より先に Size が確定しているため、Detection Limit をテーブル参照に変更する実装に手戻りリスクがないことを Background に追記。
- rubric + 補助的機械チェックの追加 (`modules/verify-patterns.md` §9 のガイドラインに従い): AC1 に `section_contains "skills/spec/SKILL.md" "### Step 7" "ambiguity-detector.md"` を追加し、rubric 単独では見落としうる「参照先ファイルが変わらず残っているか」を機械的に補強。

### Auto-Resolve Log (non-interactive mode)

- **行番号参照の更新 (L205→L226)** — reason: 現在のファイル内容と Issue 記載箇所を突き合わせた結果、コード内容は Issue の指摘通り正確だったが行番号のみドリフトしていた。AC のテキスト (rubric) はファイルパス・記述内容ベースで判定するため行番号の正誤に依存せず、Issue 本文の可読性向上のみが目的。他の選択肢 (行番号を更新しない) は Spec 作成時の混乱を招くため不採用。
- **補助 verify command の追加方式** — reason: `modules/verify-patterns.md` §9 の precedent (同モジュール内の自己言及 AC 例) に倣い、rubric と同一の意味を持つ独立した AC 行として追加 (1 行に複数 `<!-- verify: ... -->` を連結する形式ではなく)。他候補 (rubric のみで運用) は却下 — rubric 単独だと「テーブル参照に変わったが誤って別ファイルへの参照になった」ケースを見逃しうる。

### Consumed Comments (at /issue time)

No new comments since last phase.

## Consumed Comments

No new comments since last phase.
