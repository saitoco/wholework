# Issue #573: verify-executor: extract lighthouse capability guidance to load_when-gated Domain file

(XS patch route — no spec phase ran. This file was created by /auto Step 4b to carry the issue retrospective for the /verify improvement pipeline.)

## Issue Retrospective

### 曖昧性の自動解決

**[AC3 verify command の誤り修正]**
- 元の `command "bash scripts/check-eager-load-capability.sh"` は、スクリプトが設計上 always exit 0 を返す（ISSUE 行を stdout に出力するだけ）ため、lighthouse ISSUE が出力されても verify が常に PASS してしまう誤りがあった。
- `command "test -z \"$(bash scripts/check-eager-load-capability.sh | grep lighthouse)\""` に修正。lighthouse の ISSUE 行が出力された場合のみ FAIL となる。
- 他の候補: スクリプト全体出力を検査する `test -z "$(bash scripts/check-eager-load-capability.sh)"` は、lighthouse 以外の ISSUE に過剰反応するため採用しなかった。

**[Domain file 配置スキルの確定: `skills/verify/`]**
- 本文「配置先スキルは /spec 時に確定。skills/verify/ を第一候補とする」は AC1 の verify command `skills/verify/lighthouse-guidance.md` と不整合。
- AC を正として `skills/verify/` に確定。`visual_diff`（#441）は `skills/spec/` Domain file だが、`lighthouse_check` は verify-executor でのみ参照されるため `/verify/` が意味的に適切。
- 代替案の `skills/spec/` は不採用。

### 受入条件の変更

- **AC3**: verify command を `command "bash scripts/check-eager-load-capability.sh"` → `command "test -z \"$(bash scripts/check-eager-load-capability.sh | grep lighthouse)\""` に修正（常に PASS してしまう誤りの修正）
- **AC1 条件テキスト**: 「配置先スキルは /spec 時に確定」の注記を削除し `skills/verify/lighthouse-guidance.md` に確定
- **Related Issues**: `Related to #441` を追加（visual-diff 抽出の先行パターン参照）

### Triage 結果

- Type: Task（モジュール再構成・Progressive disclosure 原則準拠）
- Size: XS（対象ファイル2件・既存パターンの横展開）
- Value: 3（Impact=4: shared_flag=2×2、Alignment=2）

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- audit/drift 起票 → triage の流れで AC3 の「常に PASS する verify command」（exit 0 固定スクリプトの command 直叩き）が検出・修正された。verify command の実効性チェックが triage 段で機能した好例

#### code
- XS patch で Domain file 新規作成 + verify-executor.md からのガイダンス抽出を完了。AC 4 件は実装直後にすべて成立

#### verify
- pre-merge 4/4 PASS。post-merge opportunistic 条件は本 verify 実行の domain-loader 評価そのものが観測機会となり Claude Execute で PASS（capabilities.lighthouse 未設定 → 非ロード確認）
- **検出した積み残し**: 新規 Domain file が `docs/environment-adaptation.md` の Layer 3 Domain Files table（exhaustive）に未登録。Issue の AC には含まれないが、次回 `/audit drift` の table-missing 検出対象。Improvement Proposal として起票する

### Improvement Proposals
- `docs/environment-adaptation.md`（+ ja ミラー）の Layer 3 Domain Files table に `skills/verify/lighthouse-guidance.md` の行（load_when: `capability: lighthouse`）を追加する。新規 Domain file 追加時のテーブル同期は #573 のスコープ外だったが、exhaustive table の整合維持に必要
