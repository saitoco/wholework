# Issue #543: visual-diff-adapter: pixelmatch@6 (ESM) と pnpm 非hoist pngjs での実行不能を修正

## Overview

bundled `visual-diff-adapter` (`modules/visual-diff-adapter.md`) の Step 5b/5c で発生する 2 件の実行不能バグを修正する:

1. **Bug 1** — `pixelmatch@6` は ESM 専用で `require('pixelmatch')` の戻り値が関数でなく `TypeError: pixelmatch is not a function` が発生する
2. **Bug 2** — `pngjs` が pnpm non-hoist layout で解決できず `MODULE_NOT_FOUND` が発生する

また、Step 3 の pixelmatch tool detection を `require.resolve` (パス解決のみ) から実 load + 関数取得可否チェックに強化し、out-of-scope 2 項目を adapter ドキュメントの注記として記録する。

## Reproduction Steps

1. `pixelmatch@6.0.0` + pnpm (strict layout) 環境で `.wholework.yml` に `capabilities.visual-diff: true` を設定
2. `visual_diff` verify command を実行
3. Step 5b の Node スクリプトが `TypeError: pixelmatch is not a function` (Bug 1) または `MODULE_NOT_FOUND: pngjs` (Bug 2) で終了し UNCERTAIN になる

## Root Cause

**Bug 1**: Step 5b の `const pixelmatch = require('pixelmatch');` で得られる値は `pixelmatch@6` (ESM) では `{ __esModule: true, default: [Function] }` であり、直接関数として呼び出せない。

**Bug 2**: Step 5b/5c が `require('pngjs')` を使用しているが、`pngjs` は adapter の直接依存として Step 3 detection に含まれていない。pnpm strict layout では推移的依存は hoist されないため `require('pngjs')` が `MODULE_NOT_FOUND` になる。`sharp` は既に必須依存として検出・要求済みのため、PNG decode/encode を sharp raw RGBA に統一することで pngjs 依存を構造的に排除できる。

## Changed Files

- `modules/visual-diff-adapter.md`: Step 3 pixelmatch detection 変更 / Step 5b・5c Node スクリプト書き換え / Notes に follow-on 制約追記

## Implementation Steps

1. **Step 3 pixelmatch detection 変更** (→ AC3): `require.resolve('pixelmatch')` を次の実 load + 関数チェックに置換:
   `node -e "const p=require('pixelmatch'); if (typeof (p.default??p) !== 'function') process.exit(1)"`

2. **Step 5b Node スクリプト書き換え** (→ AC1, AC2): pngjs を除去し sharp raw RGBA + pixelmatch interop に統一。async IIFE でラップ:
   ```js
   (async () => {
     const sharp = require('sharp');
     const pixelmatch = require('pixelmatch').default ?? require('pixelmatch');
     const ref = await sharp('.tmp/visual-diff-${run_id}/${viewport}-${state}-ref.png').ensureAlpha().raw().toBuffer({ resolveWithObject: true });
     const impl = await sharp('.tmp/visual-diff-${run_id}/${viewport}-${state}-impl.png').ensureAlpha().raw().toBuffer({ resolveWithObject: true });
     const { width, height } = ref.info;
     const diff = Buffer.alloc(width * height * 4);
     pixelmatch(ref.data, impl.data, diff, width, height, { threshold: 0.1, includeAA: false });
     await sharp(diff, { raw: { width, height, channels: 4 } }).png().toFile('.tmp/visual-diff-${run_id}/${viewport}-${state}-diff.png');
   })();
   ```

3. **Step 5c Node スクリプト書き換え** (after 2) (→ AC2): `pngjs` 参照 (`const { PNG } = require('pngjs')` と `PNG.sync.read`) を除去し、ref 画像の高さ取得を `sharp().metadata()` に置換。async IIFE でラップ:
   ```js
   (async () => {
     const sharp = require('sharp');
     const { height: imgHeight } = await sharp('.tmp/visual-diff-${run_id}/${viewport}-${state}-ref.png').metadata();
     await sharp({
       create: { width: 3 * ${viewport}, height: imgHeight, channels: 4, background: { r: 255, g: 255, b: 255, alpha: 1 } }
     }).composite([
       { input: '.tmp/visual-diff-${run_id}/${viewport}-${state}-ref.png', left: 0, top: 0 },
       { input: '.tmp/visual-diff-${run_id}/${viewport}-${state}-impl.png', left: ${viewport}, top: 0 },
       { input: '.tmp/visual-diff-${run_id}/${viewport}-${state}-diff.png', left: 2 * ${viewport}, top: 0 }
     ]).toFile('.tmp/visual-diff-${run_id}/${viewport}-${state}-3panel.png');
   })();
   ```

4. **Notes 追記** (parallel with 1) (→ AC4): 既存 Notes セクションに follow-on 制約 2 項目を追加:
   - worktree node_modules (→ #443 リンク): fresh worktree には node_modules が無く sharp/pixelmatch が Step 3 で UNCERTAIN になる
   - ref/impl 高さ不一致 caveat: pixelmatch は同一寸法を要求するため高さ不一致で Step 5b が失敗する可能性がある (post-merge 再走で確認)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "modules/visual-diff-adapter.md" "const pixelmatch = require('pixelmatch');" --> <!-- verify: rubric "modules/visual-diff-adapter.md Step 5b acquires pixelmatch in an ESM/CJS interop-safe way (e.g. require('pixelmatch').default ?? require('pixelmatch')) so pixelmatch@6 (ESM-only) does not throw 'pixelmatch is not a function' when called" --> Step 5b の pixelmatch 取得が ESM/CJS interop-safe になっている (naive な `const pixelmatch = require('pixelmatch');` が除去されている)
- <!-- verify: file_not_contains "modules/visual-diff-adapter.md" "require('pngjs')" --> <!-- verify: file_contains "modules/visual-diff-adapter.md" ".raw()" --> <!-- verify: rubric "modules/visual-diff-adapter.md Step 5b/5c no longer reference pngjs; PNG decode/encode uses sharp raw RGBA buffers (sharp(path).ensureAlpha().raw().toBuffer(...) for decode and sharp(buf,{raw:{...}}).png().toFile(...) for encode), structurally removing the pnpm non-hoist pngjs dependency" --> Step 5b / 5c から `pngjs` 参照が全廃され、PNG decode/encode が sharp raw RGBA に統一されている
- <!-- verify: file_not_contains "modules/visual-diff-adapter.md" "require.resolve('pixelmatch')" --> <!-- verify: rubric "modules/visual-diff-adapter.md Step 3 tool detection for pixelmatch actually loads the module and checks that a callable function is obtained (e.g. typeof (p.default ?? p) === 'function'), not merely require.resolve path resolution, so a detection PASS implies the runtime call will not fail" --> Step 3 の pixelmatch tool detection が `require.resolve` ではなく実 load + 関数取得可否で判定する
- <!-- verify: file_contains "modules/visual-diff-adapter.md" "#443" --> <!-- verify: rubric "modules/visual-diff-adapter.md records the two follow-on limitations: (1) a fresh worktree has no node_modules so node-dependency command verify becomes UNCERTAIN (tracked by #443), and (2) pixelmatch requires equal ref/impl image dimensions so a height mismatch can fail diff generation and must be re-checked in a post-fix run" --> Out of scope 2 項目 (worktree node_modules → #443 リンク / 画像高さ不一致 caveat) が adapter ドキュメントの注記として記録されている

### Post-merge

- pnpm + `pixelmatch@6` 環境で `visual_diff` が diff highlight 生成 Step を完走し、3-panel composite + `frontend-visual-review` レポートが生成される (saitoco/koganezawa-com#58 を再走して確認)

## Notes

- 埋め込み Node スクリプトは lint/コンパイル対象外。書き換え時はスコープミス・変数未定義に特に注意すること (cf. #441 spec retrospective: Step 5c の `implHeight` 未定義バグ記録あり)
- Step 5b/5c の書き換えは async 処理を含むため async IIFE `(async () => { ... })();` でラップし、callback 形式の `.toFile(fn, cb)` は `await .toFile(fn)` に統一する

## Code Retrospective

### Deviations from Design

- None. 実装ステップはすべて Spec の順序通りに実行した。Step 3 検出変更 → Step 5b 書き換え → Step 5c 書き換え → Notes 追記の順序で完了。

### Design Gaps/Ambiguities

- `node -e` の Bash スクリプト埋め込みで `${variable}` のエスケープが必要。Spec の実装例ではバックスラッシュなしで `${run_id}` と書かれているが、実際の Node スクリプト文字列内で shell 変数展開されないよう `\${run_id}` にエスケープが必要。Spec では「概ね次の形」として示されており、詳細なエスケープは実装時の判断に委ねられていたため問題なし。

### Rework

- None. 初回実装で全 AC を満たし、rework は発生しなかった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `require('pixelmatch').default ?? require('pixelmatch')` (インライン interop 形) を採用。dynamic `import()` は Step 5b の async 化追加リファクタが必要で低リスク形を優先。
- PNG decode/encode を pngjs から sharp raw RGBA に統一し、pngjs 依存を構造的に排除（`pnpm add -D pngjs` 不要）。
- Step 5b/5c を async IIFE でラップし、callback `.toFile(fn, cb)` を `await .toFile(fn)` に統一。
- Step 3 pixelmatch detection を実 load + `typeof (p.default??p) === 'function'` チェックに変更（`require.resolve` パス解決のみでは ESM/CJS 形状不保証）。
- follow-on 2 件（worktree node_modules → #443 リンク / 画像高さ不一致 caveat）を Notes に記録（新規起票は未確認の問題への先行起票を避けるため保留）。

### Deferred Items
- worktree node_modules 問題は #443 で追跡中。本 Issue ではアダプタ注記のリンクのみ。
- ref/impl 画像高さ不一致は post-merge の koganezawa-com#58 再走で確認予定。再現した場合は別 Issue 起票。
- post-merge verify は koganezawa-com#58 の再走が必要（手動 AC）。

### Notes for Next Phase
- 変更ファイルは `modules/visual-diff-adapter.md` のみ。
- 全 pre-merge AC（4 件）は file_contains/file_not_contains + rubric いずれも PASS 確認済み。
- Node スクリプト内の `\${run_id}` 等のエスケープは意図的（Bash 変数展開防止）。
- patch route で直接 main にマージ済み（PR なし）。
