# Issue #136: spec: ghコマンドをallowed-toolsに追加する場合のChanged Files記載を必須化

## Issue Retrospective

### Triage 結果
- Type=Task, Size=XS, Priority=low, Value=2
- `skills/spec/SKILL.md` の SHOULD 制約テーブル (L284 付近) に 1 行追加で完結するため XS。

### 判断根拠 (auto-resolved ambiguity points)

- **AC #1 verify command を regex `grep` のまま維持**: 両方向の語順 (`gh.*allowed-tools` / `allowed-tools.*gh`) を検出するには regex が必要。`grep` は wholework の dedicated regex command として supported commands 表に掲載されており `/review` safe mode でも UNCERTAIN にならないため、そのまま採用。
- **元 AC #2 「既存 L282 記述と整合」を具体条件に分解**: "整合" は主観判断で機械検証不能だったため、(a) 新規ルールが "gh command pattern" を含むこと、(b) 追記位置が SHOULD Constraint checklist セクション内であること、の 2 条件に分解して `file_contains` / `section_contains` に落とし込んだ。位置制約を加えることで、本文中の別箇所にまぎれるのを防ぐ。
- **Post-merge 条件の追加**: 元は Pre-merge のみ。ルール追記の「実効性」検証が無かったため、future Spec 実行時の観測を `verify-type: manual` で追加。

### 分割判定
- 単一ファイル (`skills/spec/SKILL.md`) への 1 行 (= SHOULD-level テーブル 1 行) 追記。分割不要、XS 維持。

### Related Issues
- 兄弟 Issue #135 (新規出力ディレクトリの `docs/structure.md` 更新必須化) と同じ verify retrospective から派生。依存関係なしで並行実装可能。Issue #135 は `/audit stats` の Output directory 視点、本 Issue は allowed-tools frontmatter 視点。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective が Spec 内に記録されており、AC の具体化プロセス（"整合"を機械検証可能な2条件に分解）が明確に文書化されている。受け入れ条件の品質は高く、verify コマンドがすべて実行可能な形式で記述されていた。
- Post-merge の `verify-type: manual` 条件（将来の `/spec` 実行時の効果確認）はトレーサビリティのために適切に追加されている。

#### design
- Spec なし（実装ヒントは Issue 本文に記載、XS サイズのため Spec Design セクションは作成されなかった）。SHOULD 制約テーブルへの 1 行追記という単純な変更のため設計工程を省略したことは妥当。

#### code
- コミット `34e3e4e` が直接 `closes #136` として main にマージ（パッチルート）。fixup/amend パターンなし。1 行追記で完結しており、リワークは発生していない。

#### review
- パッチルート（PR なし）のため PR レビューは実施されていない。XS 規模・単一行変更のため、PR レビューなしで直接マージは適切な判断。

#### merge
- パッチルート（PR なし）で直接 main にコミット。コンフリクトなし、CI 実行も確認済み（`gh run list` によるローカル検証相当）。

#### verify
- 全 3 件の Pre-merge 自動検証条件がすべて PASS。verify コマンド（`grep`、`file_contains`、`section_contains`）がすべて期待通り動作。
- Post-merge 条件（`verify-type: manual`）は未チェックのままで、`phase/verify` ラベルを付与。将来の `/spec` 実行時に手動確認が必要。

### Improvement Proposals
- N/A
