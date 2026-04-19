# Issue #277: spec: 英語ドキュメント更新時の docs/ja/ 翻訳同期をチェックリストに追加

## Issue Retrospective

### Autonomous Auto-Resolve Log

- **"英語ドキュメント"の範囲 = `docs/*.md` 全般** — reason: Issue #276 Spec の retro（line 84）に `docs/environment-adaptation.md`、`docs/structure.md` が具体例として記載されており、`docs/ja/` 以下に mirror が存在する英語ドキュメント全般が対象と判断
  - Other candidates: `skills/*.md` 等他のドキュメント形式も含む可能性 → `docs/ja/` mirror が存在しないため除外

- **"Changed Files リストまたは実装ステップ"のどちらに記述するか = SHOULD-level チェックリストへの追記** — reason: `/spec` スキルの SHOULD-level セクションが「Changed Files リストに含めるべき対象」の共有パターンであり、他の同種ガイドライン（`docs/ja/*` verify command ガイダンス等）と同じ配置が自然
  - Other candidates: 実装ステップテンプレートへの直接埋め込み → 汎用性が低く、SHOULD-level チェックリストの追記の方が適切

- **`docs/ja/` のみを対象とする（`README.ja.md` 等は含まない）** — reason: 受入条件の verify command が `docs/ja` に絞られており、Issue の Purpose も `docs/ja/` に限定している
  - Other candidates: `README.ja.md` 等も含む → Issue スコープ外

### Acceptance Criteria Changes

**Pre-merge verify コマンド変更:**

変更前: `<!-- verify: grep "docs/ja" "skills/spec/SKILL.md" -->`
変更後: `<!-- verify: grep "translation" "skills/spec/SKILL.md" -->`

**理由:** `skills/spec/SKILL.md` の line 335 に既に `docs/ja/*` の記述（verify command 形式ガイダンス）が存在するため、`grep "docs/ja"` は実装前から PASS してしまう偽陽性リスクがある。「translation」はファイルに現在存在しないため、新規実装のより信頼性の高い指標となる。

### Background 補完

背景文中の `（, 等）` の欠落していたファイル名を Issue #276 Spec の retro から補完: `（docs/environment-adaptation.md`、`docs/structure.md` 等）
