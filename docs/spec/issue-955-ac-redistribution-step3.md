# Issue #955: issue: sub-issue 分割手順 Step 3 (AC 再配分) の実行手順・完了確認を追加

## Issue Retrospective

### Triage
- Title normalization: `/issue の sub-issue 分割手順 Step 3 (AC 再配分) に具体的な実行手順・完了確認が欠けている` → `issue: sub-issue 分割手順 Step 3 (AC 再配分) の実行手順・完了確認を追加`
- Type: Bug (実際に発生した不具合の再発防止が目的のため)
- Size: XS (単一ファイル `skills/issue/SKILL.md` のドキュメント修正、CI 依存なし)
- Value: 3 (Impact=0: 他 Issue からの参照・ブロッキングなし / Alignment=4: governance-and-verification harness の中核ワークフローの正確性を扱うため product.md Vision との整合度は高い)
- 重複候補: なし
- Stale / 依存関係: 異常なし

### Ambiguity 自動解決 (非対話モード)
Issue body には検出せず解決した曖昧点が2点あったため、以下の判断根拠を記録する (AC 文言自体は変更なし — いずれも `/spec` フェーズが担う実装レベルの判断のため)。

1. **再配分実行のタイミング**: 既存 Procedure の番号順序 (`2 → 3 → 3a → 4 ...`) から、Step 2 で全 sub-issue の作成が完了した後に Step 3 を一括実行する設計が一意に読み取れると判断した。
2. **再配分完了確認が失敗した場合の挙動**: `modules/project-field-update.md` の verify-after-write パターン (リトライ後も不一致なら warn のみで処理続行、ブロッキングしない) を precedent として採用した。対象が non-destructive なドキュメント編集であるため、この既存方針との整合を優先した。

いずれも「既存コードベースパターンから一意に推論可能」「AC 文言は選択によらず不変」の自動解決条件を満たすため、ユーザー確認なしで解決済みとした。
