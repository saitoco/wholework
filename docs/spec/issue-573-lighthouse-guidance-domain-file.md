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
