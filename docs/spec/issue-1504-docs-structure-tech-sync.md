# Issue #1504: docs: structure.md の scripts 件数・hooks 記述と tech.md の python3 依存を実装に合わせる

## Issue Retrospective

### 受け入れ条件の変更

- **AC4 (python3 依存)**: `grep "python3" "docs/tech.md"` を `section_contains "docs/tech.md" "Key Dependencies" "python3"` に変更した。`docs/tech.md` には `WHOLEWORK_SPAWN_DETACH` の行 (285 行目) にすでに `python3` が含まれており、元の `grep` は実装前から常時 PASS になる状態だった。Key Dependencies セクション内には `python3` がまだ存在しないため、実装後にのみ真になる
- **AC6 (日本語版の反映) を削除**: `docs/ja/` は `/doc translate` の翻訳出力であり、翻訳出力ファイルには verify command を付与しない規約 (`/issue` Step 4 "Translation document exclusion") に従った。代わりに `## Scope` セクションを追加し、日本語版にも同じ修正を反映する旨を実装側への依頼として明記した (AC では検証しない)

### Auto-Resolve Log

- **日本語版は AC から外し Scope に記載** — reason: 翻訳出力への verify command 付与禁止という規約に従うのが最も一貫性がある。直近のコミット (#1493, #1494) は `docs/ja/structure.md` も同時に更新しているため、実装側の作業としては従来どおり反映される
  - Other candidates: AC6 の rubric をそのまま残す (規約違反)、post-merge に移す (pre-merge で完結する作業なので不適)

### 確認事項

- Background の事実主張は事前に実装と突き合わせて確認した: `scripts/` の実数は 98、`hooks.json` に PreToolUse (`Edit|Write|NotebookEdit|Read`) が登録済み、`gh-pr-review.sh` / `run-review.sh` / `run-merge.sh` が `python3` を呼ぶ、`test.yml` の job ID が `check-forbidden-expressions`
- 残りの AC (1, 2, 3, 5) は現状の main に対して空撃ちし、いずれも実装前は FAIL になることを確認した (常時 PASS ではない)

### Consumed Comments

No new comments since last phase.
