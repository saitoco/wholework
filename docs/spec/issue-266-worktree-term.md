# Issue #266: docs: Terms に `Worktree` エントリを追加（product.md）

## Issue Retrospective

### 曖昧性解決の判定根拠

新規 Issue のため曖昧点は発生せず。前回実行された `/doc sync --deep` の Terms consistency check 結果 (Worktree: 6 files で使用されるが Terms 未登録) を背景にそのまま Issue 化。定義案は `modules/worktree-lifecycle.md` の既存設計に基づく（XL sub-issue 並列実行時のファイル衝突回避）。

### Acceptance Criteria 設計理由

- **Pre-merge**: `section_contains "docs/product.md" "## Terms" "Worktree"` / `"sub-issue"` の 2 件で Terms 追加と定義内容の両方を検証
- **Post-merge**: 日本語翻訳 (`docs/ja/product.md`) 同期は `/doc translate ja` 経由のため post-merge manual とする（#264 のパターンを踏襲、translation document exclusion 規約に従い pre-merge verify は付けない）
- **Post-merge**: `/doc sync --deep` 再実行で drift 解消確認 (#264, #265 と同パターン)

### triage 連鎖結果

- Type=Task / Size=XS / Priority=未指定 / Value=3
- 重複候補なし (同テーマの #264 Adapter, #265 Capability は別 term で既 closed)
- Blocked-by なし
