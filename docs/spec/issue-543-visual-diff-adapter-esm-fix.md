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

## Issue Retrospective

### Triage

- **Type=Bug / Size=S / Value=3 / Priority=未指定**
- Size=S 判定理由: 変更対象は実質 `modules/visual-diff-adapter.md` の 1 ファイルだが、Step 5b/5c の埋め込み Node スクリプトを sharp raw decode へ書き換える非自明な logic change を含むため、root-cause 明確な bug fix (−1) と script logic change (+1) が相殺し S。patch route + Spec 必須となり、正確なコードは `/spec` で確定する。(/spec フェーズで XS に再判定)
- Priority は本文に明示指定なし (「blocker」表現は技術的詰まりを指す記述でありプライオリティ指定ではない) のためスキップ。

### Q&A による方針決定

- **pngjs の扱い (AC2)**: ユーザー確認の結果「sharp 統一のみ」を採用。pngjs 参照を Step 5b/5c から全廃し sharp raw RGBA に統一する単一パスに AC を確定。adapter は既に sharp を必須検出し Step 5c も sharp composite 済みで、追加依存ゼロ・pnpm hoist 問題の構造的回避・AC の機械検証可能化 (file_not_contains で pngjs 排除確認) という利点が決め手。「pngjs 直接依存明文化」の代替案は不採用 (Scope §2 に明記)。

### 自動解決した曖昧ポイント

- **pixelmatch interop 記法**: `require('pixelmatch').default ?? require('pixelmatch')` のインライン形を採用 (dynamic import は async 化リファクタが必要なため不採用)。両形とも AC を満たし文面に影響しないため自動解決。
- **follow-on 制約の記録方法**: worktree node_modules は既存 #443 で追跡済みのため新規起票せず adapter 注記でリンク。画像高さ不一致は未実測のため post-merge 再走での再現確認まで adapter 注記の caveat に留める (先行起票を回避)。

### Acceptance Criteria の変更理由

- 各 pre-merge AC に verify command を付与 (元の本文は plain checkbox のみだった)。意味判定は `rubric`、機械的安全網として naive 形除去を `file_not_contains` (`const pixelmatch = require('pixelmatch');` / `require('pngjs')` / `require.resolve('pixelmatch')`)、sharp raw 採用を `file_contains ".raw()"` で補強。
- AC2 を OR から「sharp 統一」単一パスに確定 (上記 Q&A)。
- AC4 (follow-on 記録) を「adapter ドキュメントの注記として記録」へ具体化し、`file_contains "#443"` で worktree gap トラッカーへのリンクを検証可能化。
- post-merge 条件は実プロジェクト (koganezawa-com#58) での runtime 再走が必須なため `verify-type: manual` を維持。

### 参照の更新

- worktree node_modules gap が wholework 側で **#443** として既にトラッキングされていることを発見し、参照に追加 (元本文は downstream の koganezawa-com#45 のみ参照)。#441=CLOSED / #437=OPEN を確認。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は Size を S→XS に正しく再判定し、Root Cause / Changed Files / Implementation Steps を的確に記述。実装は Spec の順序通りに完了し deviation なし。
- 独立した `## Spec Retrospective` セクションは未生成（patch route で軽量だったため）。実害はないが、Code Retrospective が design gap（`node -e` 内 `${var}` のエスケープが実装例で未明示）を捕捉済み。

#### design
- 設計判断（interop はインライン `.default ??`、pngjs→sharp 統一、follow-on は新規起票せず注記）はいずれも妥当で、実装・検証まで一貫。dynamic import を避けた判断は async 化リファクタ回避として適切。

#### code
- rework ゼロ。初回実装で全 4 AC を満たす。fixup/amend パターンなし（clean な単一 fix commit `ebf894c`）。
- async IIFE ラップと callback→`await .toFile()` 統一は Spec 未明示だが必要な実装判断として正しく追加された。

#### review
- patch route (XS) のため review フェーズなし (N/A)。
- ただし重要な観察: 本 adapter の diff 生成ロジックは **markdown 内の埋め込み Node スクリプト**であり lint/CI/test の対象外。#441 (`implHeight` 未定義) も #543 (ESM interop / pnpm pngjs / async 化) も、lint 不可視の埋め込みスクリプトの runtime 失敗で、実 dogfooding でしか検出されなかった。同一クラスの欠陥が 2 回連続で発生している。

#### merge
- patch route で main 直コミット。conflict なし。clean。

#### verify
- pre-merge AC 4 件すべて PASS。verify command（`file_not_contains` / `file_contains` / `rubric`）が実装と完全一致し、UNCERTAIN/FAIL ゼロ。Issue refinement 時の cross-reference（naive 形除去を `file_not_contains` で確認、`.raw()` を `file_contains` で確認）が機能した。
- post-merge manual 条件は外部プロジェクト (koganezawa-com#58) の runtime 再走が必須で本コンテキストから実行不可のため pending 維持（設計通りで gap ではない）。Issue は CLOSED のまま `phase/verify`。

### Improvement Proposals
- **埋め込み Node スクリプトの実行可能テスト不在**: `modules/visual-diff-adapter.md` の Step 5b/5c は markdown 内の `node -e` スクリプトで lint/CI/test がかからず、runtime バグ（#441 implHeight, #543 ESM interop/pnpm/async）が実 dogfooding まで露見しない。fixture PNG に対して埋め込みスクリプトを抽出・実走する smoke test、または埋め込み JS の構文/契約チェックを追加し、この欠陥クラスを pre-merge で捕捉する仕組みを検討すべき。（既存の #437 親考察 / #443 worktree node_modules とは別軸の testability gap。）
