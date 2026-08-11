# Issue #1345: spec: Changed Files 洗い出しに See-also ポインタ先ファイルの追跡を追加

Size XS / patch route のため `/spec` フェーズは実行されていない。本ファイルは `/auto` Step 4b により、Issue Retrospective を `/verify` の improvement proposal パイプラインから参照可能にする目的で作成された。

## Changed Files

- `skills/spec/SKILL.md`: Changed Files 洗い出し手順 (Step 10) に outbound pointer sync candidate check を追加

実装コミット: `c38f34a5` (`feat: add outbound pointer sync candidate check to /spec Changed Files enumeration (closes #1345)`)

## Issue Retrospective

### 判断根拠

- **Background の事実確認**: `skills/spec/SKILL.md:281-305` の「Steering Docs sync candidate check」の存在、`modules/label-conventions.md` の `setup-labels.sh` 同期記述、`docs/guide/customization.md` から `modules/detect-config-markers.md` への「for the full reference」参照、いずれも `grep` で実在を確認済み。Background の事実誤認なし。
- **AC の verify command 修正 (Auto-Resolved)**: AC1 の `<!-- verify: section_contains "skills/spec/SKILL.md" "Changed Files" "See also" -->` は、`skills/spec/SKILL.md` 内で `## Changed Files` という Markdown 見出しが実在するのは 657 行目・703 行目の Spec 出力テンプレート例 (light/full template) 内のみであり、実装対象の「Steering Docs sync candidate check」(Step 10 内、太字サブ見出し) とは無関係な箇所を指していた。実装が意図通りでも `## Changed Files` セクション内に "See also" が現れない限り常時 FAIL する懸念があった。heading 引数を実際に変更対象を包含する最寄りの見出し「Step 10: Create Spec」に修正し、意図通りの検証精度を確保した。詳細は Issue 本文の「Auto-Resolved Ambiguity Points」セクション参照。
- この修正は、Issue 本文に既についていた `saito` (MEMBER) による Triage AC audit コメントの指摘をそのまま踏襲したもの。

### Q&A からの主要な方針決定

なし (非対話モードのため質問なし。上記の verify command 修正のみ自動解決)。

### AC 変更理由

- AC1 の `section_contains` heading 引数のみ修正 (`"Changed Files"` → `"Step 10: Create Spec"`)。AC の文言・rubric・件数に変更なし。

### Consumed Comments

- saito / MEMBER / first-class / Triage AC audit: AC1 の `section_contains` heading 引数の不一致 (常時 FAIL の懸念) を指摘し、修復案 (heading 修正 または `file_contains`/`grep` への変更) を提示 / https://github.com/saitoco/wholework/issues/1345#issuecomment-5246584972

## Consumed Comments
No new comments since last phase.
