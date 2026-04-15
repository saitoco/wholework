# Issue #173: docs: Establish Periodic Sync Process for docs/ja and English docs

## Overview

`docs/ja/*` mirrors `docs/*` in Japanese, but translation lag has caused gaps. Issue #165
(fix-cycle removal) updated `docs/*` without updating `docs/ja/*` (noted as "coincidental" in
the spec retrospective). The issue body also stated `docs/ja/guide/` did not exist, but
investigation confirms it **already exists** with all 5 guide files matching `docs/guide/`.

Currently out of sync (English newer than Japanese, via git timestamp comparison):
- `docs/structure.md` vs `docs/ja/structure.md`
- `docs/workflow.md` vs `docs/ja/workflow.md`

This issue establishes a sync process: (1) a shell script that shows which `docs/ja/*` files
are outdated relative to `docs/*`, and (2) a documentation section in `docs/workflow.md`
explaining the correspondence and how to regenerate translations.

## Changed Files

- `scripts/check-translation-sync.sh`: new file — sync status checker that compares git
  timestamps of `docs/*.md` and `docs/guide/*.md` against `docs/ja/*` counterparts
- `docs/workflow.md`: add Translation Sync paragraph to the `### /doc` subsection in
  Supporting Skills
- `docs/structure.md`: add `check-translation-sync.sh` to the Tooling section of Key Files /
  Scripts
- `docs/ja/workflow.md`: translate the new Translation Sync paragraph to Japanese
- `docs/ja/structure.md`: translate the new script entry to Japanese

## Implementation Steps

1. Create `scripts/check-translation-sync.sh`: iterate over `docs/*.md` and `docs/guide/*.md`
   (excluding `docs/spec/` and `docs/stats/`); for each file, check if a corresponding
   `docs/ja/*` path exists; compare git timestamps using `git log -1 --format="%ct"`; output a
   table showing IN_SYNC / OUTDATED / MISSING_JA status per file; always exit 0 (→ acceptance
   criteria 1)

2. Update `docs/structure.md`: add `check-translation-sync.sh` to the Tooling section under
   Key Files / Scripts with description "check translation sync status of docs/ja/* against
   docs/*" (after step 1) (→ docs/structure.md SSoT maintenance)

3. Add Translation Sync paragraph to `docs/workflow.md` immediately after the existing
   `### /doc — Foundation Document Management` paragraph body (before the blank line to the
   next section): include 1:1 correspondence note (`docs/*.md` ↔ `docs/ja/*.md`,
   `docs/guide/*.md` ↔ `docs/ja/guide/*.md`), sync check command
   (`scripts/check-translation-sync.sh`), and update command (`/doc translate ja`) (after
   step 1) (→ acceptance criteria 1)

4. Add Japanese translation of the Translation Sync paragraph to `docs/ja/workflow.md` at the
   corresponding position under the `/doc` subsection (after step 3) (→ acceptance criteria
   1, 2)

5. Add Japanese translation of the `check-translation-sync.sh` script entry to
   `docs/ja/structure.md` at the corresponding Tooling section position (after step 2)
   (→ docs/structure.md SSoT maintenance)

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/check-translation-sync.sh" "docs/ja" --> スクリプトが docs/ja への参照を含む
- <!-- verify: file_contains "docs/workflow.md" "check-translation-sync" --> workflow.md に同期スクリプトへの参照が追加されている
- <!-- verify: file_contains "docs/structure.md" "check-translation-sync" --> structure.md にスクリプトが記載されている
- <!-- verify: file_contains "docs/ja/workflow.md" "check-translation-sync" --> 日本語版 workflow.md が更新されている
- <!-- verify: file_contains "docs/ja/structure.md" "check-translation-sync" --> 日本語版 structure.md が更新されている

### Post-merge

- `bash scripts/check-translation-sync.sh` を実行し、docs/ja/* との対応状況一覧が出力される
- docs/workflow.md の Translation Sync 段落に docs/guide/ ↔ docs/ja/guide/ の対応が明記されている

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- `mapfile` (bash 4+) was used initially in `check-translation-sync.sh`, causing failure on macOS system bash (3.2). Changed to `while IFS= read -r` loop for compatibility. The spec did not mention bash version compatibility requirements.

### Rework
- `check-translation-sync.sh` was rewritten once after initial implementation to replace `mapfile` with `while read` for macOS bash 3.2 compatibility.

## Notes

- `docs/ja/guide/` は Issue 作成時点では存在しないとされていたが、調査の結果すでに全ファイルが揃っている
  (`customization.md`, `index.md`, `quick-start.md`, `troubleshooting.md`, `workflow.md`)
- 現在の非同期ファイル (英語版が新しい): `docs/structure.md`, `docs/workflow.md`。
  この Issue 完了後に `/doc translate ja` を実行して全体を同期することを推奨
- `docs/ja/*` の verify コマンドでスクリプト名 `check-translation-sync.sh` を英語のまま使用
  (コードリファレンスのため翻訳不要)
- `check-translation-sync.sh` は常に exit 0 — out-of-sync 検知でもプロセスを止めない設計
  (CI チェックで使う場合は `--fail-if-outdated` フラグ追加を別 Issue で検討)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 本文の不正確な記述（`docs/ja/guide/` が存在しない）をスペック調査で発見・修正した。Issue 作成時の前提確認不足だったが、spec フェーズで早期に修正できた点は良好。
- 受け入れ条件に verify コマンドが付与されており、自動検証が可能な品質で記述されていた。

#### design
- 設計は実装と高い整合性があり、変更ファイルと実装ステップが1対1で対応していた。
- bash バージョン互換性要件（macOS system bash 3.2）が設計に含まれていなかった点が唯一の設計漏れ。シェルスクリプトを伴う Spec では対象環境の bash バージョンを明記する習慣が望ましい。

#### code
- `mapfile` (bash 4+) から `while IFS= read -r` への書き直しが1回発生（macOS bash 3.2 互換性）。Spec の Design Gaps に記録済み。
- パッチルート（PR なし）で直接 main にコミット。5コミットで段階的に実装された構成は追跡しやすい。

#### review
- パッチルート実装のため正式コードレビューなし。bash 互換性問題は PR レビューがあれば初期コミットで検出可能だった可能性がある。
- パッチルートのシェルスクリプト実装では、互換性テストを CI で自動実行する仕組みが有効。

#### merge
- パッチルートで直接 main へコミット。コンフリクトなし。

#### verify
- 全条件 PASS。`file_contains` コマンドで5箇所の参照を確認し、実装の整合性を確認。
- `verify-type: manual` が付与されているが verify コマンドも存在する条件について、自動検証が正常に機能した。`verify-type: auto` への変更を検討しても良い。

### Improvement Proposals
- シェルスクリプトを含む Spec では対象環境の bash バージョン要件を明記するガイドラインを追加する（例: "bash 3.2+ compatible" を Changed Files に注記）
- パッチルートで実装されるシェルスクリプトについて、CI に bash 互換性テスト（macOS 環境での実行確認）を追加することを検討する
