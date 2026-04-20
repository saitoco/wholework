# Issue #288: docs/ja: docs/ja/structure.md の get-config-value.sh エントリ欠落を修正

## Issue Retrospective

### 判断根拠（Auto-Resolve）

- **「内容が一致」の判定基準**: rubric で「EN 版と同等のスクリプトエントリ集合を保持」と定義。文言の翻訳差は許容する方針は、docs/ja の翻訳運用として自然で、既存の同期 Issue でも採用されている考え方。
- **エントリ配置**: EN 版を reference として、「プロジェクトユーティリティ」セクション内に追加。並び順の EN/JA 間の差異は low-risk・既存慣習として scope 外にし、検出時は別 Issue 起票。
- **Scope 限定**: 本 Issue は #286 verify retrospective で単一エントリ欠落として検出されたドリフトのみ対応。`docs/ja/structure.md` 全体の翻訳品質レビューは対象外。

### 受け入れ条件の変更理由

- `grep "get-config-value.sh" "docs/ja/structure.md"` を dedicated な `file_contains` に置換（`command` hint は `/review` safe mode で UNCERTAIN 扱いになるため）
- 追加エントリの説明文が意味のある内容を含むことを確認するため `.wholework.yml` 言及の verify を追加
- rubric の判定対象を「Key Files > Scripts セクション」から「プロジェクトユーティリティ セクション」（JA 側の実セクション名）に揃え、grader の誤判定を減らす
- Pre-merge / Post-merge のセクション区分を追加

### Triage 結果

- Type: Bug、Size: XS、Value: 2（Impact=0 / Alignment=1, Level 1）
- Duplicate / stale / dependency 異常なし
