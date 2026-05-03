# Issue #393: reconcile: reconcile-phase-state.sh のレビュー完了パターンを skill 出力に合わせて修正

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | -     | SUCCESS | phase/* 未設定だったため triage 自動実行 |
| code  | patch | SUCCESS | 直接 main コミット (55b8f73) |
| verify (1) | patch | PENDING | CI が実行中で一部条件 PENDING |
| verify (2) | patch | FAILED (exit 1) | 別 Issue (#397) の Spec 編集が未コミットで dirty working tree |
| verify (3) | patch | SUCCESS | working tree clean 化後の retry で受入条件全 PASS、phase/done 遷移 |

### Orchestration Anomalies
- **verify wrapper exit 1 (iteration 2)**: `run-verify.sh` が `VERIFY_FAILED` を返した。原因は `docs/spec/issue-397-permission-auto-lazy-catch.md` の未コミット変更（別 Issue の作業残り）。Tier 1 reconcile は `matches_expected:true` を返したが label は `phase/verify` のままで実質未完了。Tier 2 anomaly detector は空出力（未知パターン）。
- **手動リカバリ手順**: 親セッションが working tree の状態を確認したところ、当該ファイルは別コミット (b9ad188) に取り込み済みで working tree は既に clean だった。iteration counter を 3 に進めて `run-verify.sh` を再実行 → 成功。

### Improvement Proposals
- **verify pre-check の改善**: `/verify` 開始時に「未コミット変更が検出された場合、別 Issue の Spec ファイルかどうか自動判定する」拡張を検討。現状はパスを human-readable な error message に出すだけで、unrelated file かどうかの判断はユーザに委ねている。auto orchestration では特に未関連ファイルの dirty 状態が偽陽性を生むため、ホワイトリスト or 自動 stash の選択肢を提示する設計が候補。
- **reconcile-phase-state.sh verify completion 判定の厳格化**: 現状 `phase/verify` + CLOSED で `matches_expected:true` を返してしまい、実質的な verify 完了 (`phase/done`) を判定できない。`phase/done` を必須とするチェックを追加することで、Tier 1 で誤って success override する誤判定を防げる。
- **anomaly detector への "dirty working tree" パターン追加**: `VERIFY_FAILED` + `Cannot run verify because there are uncommitted changes` を既知パターンとして登録すれば、次回以降は Tier 2 catalog で「`git status` 確認 → unrelated file なら通知し iteration retry」を半自動化できる。
