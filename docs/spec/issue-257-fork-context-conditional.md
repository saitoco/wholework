# Issue #257: tech: fork-context table の issue/spec 行を conditional 表記に（product.md と整合）

## Issue Retrospective

### 曖昧性解決の判定根拠

- **選択肢 A（Reason 列を明確化）を採用**: Issue 本文で明示的に「推奨」と記載されていた点を尊重。選択肢 B は列構造変更により他行（triage/code/review/merge/verify/auto/audit/doc）まで 2 列化する波及が大きく、XS スコープ内で吸収困難。選択肢 C は実装（`skills/issue/SKILL.md`/`skills/spec/SKILL.md` の frontmatter が shared）を tech.md に揃えると product.md とのズレが残るため不適。

### Acceptance Criteria 変更理由

- **Pre-merge verify commands を `section_contains` → `file_contains` に置換**: 当初の verify が指していた `section_contains "docs/tech.md" "fork context vs main context" ...` は Markdown heading ではなく bold ラベル（`- **fork context vs main context**:`）を見出しとして扱っており解決不能だった。代わりに、更新後の行テキスト（`| issue | Conditional`, `| spec | Conditional`, `fork when via run-`）に対する直接照合に変更。いずれも現状の tech.md には存在しない fix-unique なフレーズで、false positive を回避。
- **Pre-merge 条件を 2 件 → 3 件に拡張**: issue 行更新、spec 行更新、Reason 列の run-*.sh 経由条件記述、を独立に検証できるよう分離。

### triage 連鎖結果

- Type=Task / Size=XS / Priority=未指定 / Value=3（Impact=2: steering docs は shared component として +2、Alignment=3: vision 関連=+2, steering mention=+1）
- 重複候補なし・Stale なし・Blocked-by なし
