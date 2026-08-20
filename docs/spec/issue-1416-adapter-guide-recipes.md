# Issue #1416: adapter-guide: preview-url-command (Amplify) / preview-basic-auth-command 実装例 (recipe) を追加

## Issue Retrospective

### 実行モード

`--non-interactive` (headless skill execution)。`AskUserQuestion` は使用できないため、`modules/ambiguity-detector.md` の三層ポリシーに従い、検出した曖昧点はすべて Auto-Resolve で処理した。

### Autonomous Auto-Resolve Log

- **セクション配置** — `## Further Reading` の手前に配置
  - 根拠: `docs/guide/adapter-guide.md` は `## Further Reading` を最終セクションとする既存構成であり、末尾直前への追加が既存ドキュメント構造と最も整合する。Proposal (Outline) 項目1の推奨をそのまま採用した。
  - Other candidates: `## Adapter Contract Template` 直後 (却下: 実装例レシピは Adapter Contract とは異なる仕組みであり、混在させると誤解を招く)
- **サンプルスクリプトのファイル名** — Amplify レシピ `.wholework/adapters/resolve-preview-url.sh`、Basic Auth レシピ `.wholework/adapters/resolve-preview-basic-auth.sh`
  - 根拠: `docs/guide/customization.md` の `preview-url-command` / `preview-basic-auth-command` 節が設定例としてこれらのファイル名を既に明記している。レシピとドキュメント間でファイル名を一致させ一貫性を保つ。
  - Other candidates: 汎用名 (`preview.sh` 等) — 却下 (customization.md の既存表記と食い違う)
- **Basic Auth レシピの環境変数名** — `WHOLEWORK_PREVIEW_BASIC_USER` / `WHOLEWORK_PREVIEW_BASIC_PASS` (Proposal 本文の例示どおり)
  - 根拠: `WHOLEWORK_` プレフィックスは `docs/tech.md` の環境変数一覧 (`WHOLEWORK_CONFIG_PATH` 等) で確立された命名規約であり、汎用イラスト的テンプレートの命名として自然。
  - Other candidates: provider 非依存を強調した汎用名 (`PREVIEW_BASIC_USER` 等、prefix なし) — 却下 (他の `WHOLEWORK_*` 系環境変数との一貫性を優先)

いずれも Acceptance Criteria のテキスト・verify command には影響しない (rubric 判定範囲・grep 対象は変更なし)。Issue 本文に "Auto-Resolved Ambiguity Points" セクションとして記録済み。

### Acceptance Criteria の変更

なし。既存の AC (rubric + grep 補助チェックの組み合わせ) はいずれも適切に構成されており、`scripts/check-ac-checkbox-format.sh` / `scripts/check-skill-change-observation-ac.sh` の両方が exit 0 (問題なし) だった。

### Background 事実確認

Background の `scripts/run-review.sh` に関する記述 (`preview-url-command` 宣言時の自動解決) を `grep` で確認済み。当該スクリプトに実装が存在し、記述は正確。

### Consumed Comments

- saito / MEMBER / first-class / 2026-08-20 のスコープ拡大 (`#1417` 着地を受け `preview-basic-auth-command` レシピを追加対象に含める決定) を伝える内容。内容は既に Issue 本文の Background "2026-08-20 追記" セクションへ反映済みだったため、本文への追加変更は不要と判断した / https://github.com/saitoco/wholework/issues/1416#issuecomment-5356338255

## Consumed Comments
No new comments since last phase.
