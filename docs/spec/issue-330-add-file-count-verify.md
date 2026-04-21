# Issue #330: docs: module 追加 PR の verify command にファイルカウント検証を追加

## Overview

`modules/` や `scripts/` にファイルを追加する PR で `docs/structure.md` と `docs/ja/structure.md` のファイルカウントコメント（例: `(29 files)`）の更新漏れが繰り返し発生している（直近: Issue #314）。

本 Issue では `docs/structure.md` の Key Files セクション Maintenance rule を拡張し、module/script 追加 PR に向けた verify command 追加ガイドを整備する。現在の実ファイル数はすでに `docs/structure.md`（modules=29、scripts=41）および `docs/ja/structure.md`（modules=29、scripts=41）と一致しているため、カウント自体の修正は不要。

## Changed Files

- `docs/structure.md`: Key Files セクションの Maintenance rule を拡張（`modules/`・`scripts/` へのファイル追加・削除時はカウントコメント更新と verify command 追加が必要という一文を追記）
- `docs/ja/structure.md`: 上記に対応する日本語保守ルールを拡張

## Implementation Steps

1. `docs/structure.md` の Key Files セクション Maintenance rule（`> **Maintenance rule**: ...still expected.` の末尾）に段落を追加:
   ```
   >
   > When adding or removing a file in `modules/` or `scripts/`, also update the file count comment (e.g., `(29 files)`) in the Directory Layout section above, and include a verify command in the PR's acceptance criteria to confirm the count (e.g., `<!-- verify: grep "(29 files)" "docs/structure.md" -->`).
   ```
   (→ acceptance criteria 5)

2. `docs/ja/structure.md` の保守ルール（`> **保守ルール**: ...期待される。` の末尾）に段落を追加:
   ```
   >
   > `modules/` または `scripts/` にファイルを追加・削除した場合は、上記ディレクトリ構成のファイルカウントコメント（例: `（29 ファイル）`）も更新すること。また、PR の acceptance criteria に verify command を含め、カウントが一致していることを確認すること（例: `<!-- verify: grep "29 ファイル" "docs/ja/structure.md" -->`）。
   ```
   (→ acceptance criteria 5)

## Verification

### Pre-merge

- <!-- verify: grep "(29 files)" "docs/structure.md" --> `docs/structure.md` の modules/ ファイルカウントコメントが現在の実ファイル数（29）と一致している
- <!-- verify: grep "(41 files)" "docs/structure.md" --> `docs/structure.md` の scripts/ ファイルカウントコメントが現在の実ファイル数（41）と一致している
- <!-- verify: grep "29 ファイル" "docs/ja/structure.md" --> `docs/ja/structure.md` の modules/ ファイルカウントコメントが現在の実ファイル数（29）と一致している
- <!-- verify: grep "41 ファイル" "docs/ja/structure.md" --> `docs/ja/structure.md` の scripts/ ファイルカウントコメントが現在の実ファイル数（41）と一致している
- <!-- verify: rubric "docs/structure.md maintenance rule section or CLAUDE.md contains guidance that PRs adding modules or scripts should include a verify command to check file count comments in docs/structure.md" --> module/script 追加 PR に向けた verify command 追加ガイドが `docs/structure.md` または `CLAUDE.md` に整備されている

### Post-merge

- `/verify 330` を実行して全 acceptance criteria が PASS することを確認

## Notes

- 自動解決済み曖昧点 1: 具体的な grep パターンを使用（`grep "files" "docs/structure.md"` は汎用すぎるため、現在の実ファイル数と一致する具体的パターンに置き換え済み）
- 自動解決済み曖昧点 2: ガイド配置先は `docs/structure.md` の既存 Maintenance rule に拡張（最もスコープが小さく自然）
- 自動解決済み曖昧点 3: ファイルカウント一致確認（grep）とガイド存在確認（rubric）を分割して検証精度を向上

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
