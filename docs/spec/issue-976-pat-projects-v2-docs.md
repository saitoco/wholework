# Issue #976: docs: Fine-grained PAT の Projects V2 権限要件をドキュメント化

## Issue Retrospective

### 曖昧性解決の判断根拠

- **対象ファイルの特定 (`docs/guide/troubleshooting.md`)**: 元の Purpose では「`docs/guide/` 配下が候補」という未確定表現だった。`docs/guide/` 配下の既存ファイル (adapter-guide.md, autonomy.md, customization.md, scripting.md, troubleshooting.md 等) を調査した結果、troubleshooting.md が「Symptom / Fix」形式の既存節 (GitHub CLI Authentication, Plugin Install Failures 等) を持ち、本 Issue の「GitHub Actions + Projects V2 連携時の権限エラーとその回避策」という内容と最も一致するパターンと判断し、自動解決した。AC の rubric 文言自体はファイル名に依存しない書き方だったため、Purpose のみ具体化。

### Q&A における主要な方針決定

非対話モードのため AskUserQuestion は未使用。上記の対象ファイル特定を含め、すべて自動解決 (Auto-Resolve) で処理した。

### Acceptance Criteria 変更の理由

- 対象ファイルが `docs/guide/troubleshooting.md` に確定したため、rubric AC の対象パス表現を「docs/guide/ 配下」から「docs/guide/troubleshooting.md」に具体化した (rubric の判定対象自体は変更なし)。
- rubric + 補完チェックのガイドライン (verify-patterns.md §9) に従い、対象ファイル・セクションが予測可能になったことを受けて、`file_contains "docs/guide/troubleshooting.md" "Projects: Read and write"` を補完 AC として追加した。rubric が誤って PASS 判定するケース (別ファイルに記載されていても意味的に近ければ PASS になりうる) に対する機械的なセーフティネットとして機能する。

### その他

- Type: Task、Size: XS、Value: 2 (Impact=0: blocking/mentions/parent/shared いずれも該当なし、Alignment=2: downstream プロジェクト支援としてVisionに部分的合致) と判定。
- 重複候補、停滞パターン、依存関係の異常は検出されず。

## Consumed Comments
No new comments since last phase.

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Post-merge セクションが「- [ ] なし」というチェックボックス付きプレースホルダとして生成されていた。未チェックの `- [ ]` 行として残るため、`/verify` の「全条件チェック済み → phase/done」判定を機械的にブロックする (今回は verify がプレースホルダと判断して手動チェックで解消)。post-merge 条件が存在しない場合はチェックボックスなしの「なし」表記が望ましい。

#### code / verify
- XS patch route。実装・検証とも問題なし。batch List mode の Step 4b (Issue Retrospective 転記、#982 で追加) が本 Issue で初めて実運用され、正常に機能した。

### Improvement Proposals
- (Tier 2 memory 相当) `/issue` の AC 生成時、post-merge 条件が存在しない場合は「### Post-merge」配下にチェックボックス付き「- [ ] なし」を生成しない (プレーンテキスト「なし」とする)。単発の書式ゆらぎのため Issue 起票はせず記録のみ。
