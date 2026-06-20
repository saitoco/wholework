# Issue #704: config: .wholework.yml に autonomy tier を導入し L2→L1 経路 (A advisory / B CronCreate / C ScheduleWakeup / E seed-file) の許可リストとして使う

## Overview

`.wholework.yml` に `autonomy:` field (L1 | L2 | L3、未設定時 L1) を導入し、Wholework skill (L2) が Claude Code primitive / 外部発火 (L1) を呼び出す経路の許可レベルをプロジェクト単位で宣言できるようにする。許可マトリクスの SSoT として `modules/autonomy-tier.md` を新規作成し、ユーザ向けガイド `docs/guide/autonomy.md` を追加する。

本 Issue は **薄い実装 (thin enforcement)** にとどめる: 導入するのは「config field + SSoT module + guide + config marker 登録」のみ。各 skill frontmatter への `loop-paths-used` 宣言と loader による実ゲーティングは後続の #700 / #702 / #703 で着地させる (本 Issue はそれらが参照するマトリクスを先に確定させる位置付け)。SKILL.md の編集は本 Issue では行わない。

L0 substrate (GitHub state) の言語化と、Tier × L0 write の許可範囲ルックアップ先は #705 で SSoT 化済の `modules/l0-surfaces.md` を参照する (#705 は CLOSED、blocked-by 解消済)。

## Changed Files

- `modules/autonomy-tier.md`: **新規作成**。4 セクション標準構造 (Purpose / Input / Processing Steps / Output)。L0 layer table、L2→L1 経路カタログ A〜E、Tier × 経路マトリクス、Tier × L0 write マトリクス (l0-surfaces.md 参照)、`autonomy:` schema、skill frontmatter 宣言ルール (`loop-paths-used` / `loop-paths-fallback`)、loader 動作 (強制依存→hard-error / 降格可能→warning + 経路 A fallback)、`CronList` による cron registry 可視性メモを記載
- `modules/detect-config-markers.md`: marker 定義テーブルに `autonomy` 行を追加 (Variable=`AUTONOMY_TIER`、value `L1`|`L2`|`L3`、default `L1`)。YAML Parsing Rules と Output Format リストにも対応エントリを追加
- `docs/guide/autonomy.md`: **新規作成**。ユーザ向けガイド。tier (L1/L2/L3) の選び方、各 tier が許可する L2→L1 経路の違い、`.wholework.yml: autonomy:` 設定例を記載
- `docs/structure.md`: modules ファイル数コメント `(37 files)` → `(38 files)`、Key modules 箇条書きに `modules/autonomy-tier.md` を追加、`guide/` 説明リストに `autonomy` を追加
- `docs/guide/customization.md`: Available Keys テーブル (SSoT) に `autonomy` 行を追加、サンプル `.wholework.yml` ブロックにコメント付きで追加
- `docs/tech.md`: Architecture Decisions に autonomy tier governance の項を追加 (新規 `.wholework.yml` key 追加に伴う必須更新)
- `docs/guide/index.md`: guide ページ一覧テーブルに Autonomy 行を追加
- `docs/workflow.md`: Related Documents リストに `modules/autonomy-tier.md` を追加 (l0-surfaces.md の隣)
- `docs/ja/structure.md`: 上記 structure.md 変更のミラー同期 (translation-workflow.md: top-level docs)
- `docs/ja/tech.md`: 上記 tech.md 変更のミラー同期 (translation-workflow.md: top-level docs)
- `docs/ja/workflow.md`: 上記 workflow.md 変更のミラー同期 (translation-workflow.md: top-level docs)

bash 互換: シェルスクリプト変更は含まないため bash 互換メモは不要。`get-config-value.sh` は汎用 flat kebab-case key 抽出機なので `autonomy` key 読み取りに**スクリプト変更不要** (確認済: `case "$line"` 汎用パース)。

## Implementation Steps

1. `modules/autonomy-tier.md` を新規作成 (→ acceptance criteria 1, 3, 4, 5, 6)。標準 4 セクション構造で記述し、新規テーブルには `(exhaustive)` マーカーを付す:
   - **Purpose**: L2→L1 経路の許可マトリクスを SSoT 化し、`autonomy` tier が「Wholework がどこまで GitHub state (L0) を書き換えてよいか」のガバナンス宣言であることを述べる
   - **L0 layer table (exhaustive)**: L0 (GitHub state) / L1 (Claude Code primitive) / L2 (Wholework skill 内部) / L3 (OS / `CronCreate`) の 4 層
   - **L2→L1 経路カタログ (exhaustive)**: A=Advisory、B=`CronCreate`、C=`ScheduleWakeup`、D=Detached subprocess (**本 Issue / 現行スコープでは非対応**と明記)、E=Seed file emission
   - **Tier × 経路マトリクス (exhaustive)**: `L1 Report` / `L2 Assisted` / `L3 Unattended` の 3 tier × 経路 A/B/C/E の ○×、各 tier のデフォルト用途
   - **Tier × L0 write マトリクス**: L0 read / L0 write / recurring 起票 の段階化。per-surface な「これは L0 write か」の判定は `modules/l0-surfaces.md` を参照する旨を記載 (Read 指示は見出し直後の段落に配置)
   - **`autonomy:` schema**: `L1 | L2 | L3`、未設定時 `L1` (safest)
   - **skill frontmatter 宣言ルール**: `loop-paths-used: [A, E]` 形式、`loop-paths-fallback: [A]` 形式
   - **Processing Steps (loader 動作)**: 宣言経路が現 tier で不許可のとき、強制依存なら hard-error で起動拒否、降格可能なら warning + 経路 A (advisory) に fallback
   - **CronList 可視性メモ**: cron registry は既存 primitive `CronList` で確認できるため Wholework 側で重複ストレージを持たない
2. `modules/detect-config-markers.md` を更新 (after 1 不要・parallel 可) (→ acceptance criteria 2)。Marker Definition Table に `autonomy` 行 (`| `autonomy` | `AUTONOMY_TIER` | tier 文字列をそのまま抽出 | `L1` |`) を追加し、YAML Parsing Rules に「`autonomy` は `L1`/`L2`/`L3` のいずれか。未設定または不正値は `L1` (safest) にフォールバック」を追記、Output Format リストに `AUTONOMY_TIER` エントリを追加。`Purpose` 先頭の SSoT 参照文と整合させる
3. `docs/guide/autonomy.md` を新規作成 (parallel with 1, 2) (→ acceptance criteria 7, 8, 9)。tier 選択基準 (L1 Report=監査/ドリフトのみ、L2 Assisted=mid-scale modernization、L3 Unattended=完全無人)、各 tier が許可する L2→L1 経路 (A/B/C/E) の違い、`.wholework.yml: autonomy: L2` 設定例を記載。`modules/autonomy-tier.md` への相互リンクを張る。`L2 Assisted` の文字列を含める
4. `docs/structure.md` を更新 (after 1) (documentation consistency; 直接対応する numbered AC なし、/review の doc consistency check が検証)。Directory Layout の modules 行を `(37 files)` → `(38 files)` に変更 (structure.md maintenance rule: モジュール追加時の必須更新)、Key modules 箇条書き末尾 (`skill-dev-doc-impact.md` 行の後) に `modules/autonomy-tier.md` の 1 行説明を追加、`guide/` 説明リストの末尾 (`xl-decomposition` の後) に `autonomy` を追加
5. `docs/guide/customization.md` を更新 (parallel with 4)。Available Keys テーブル (SSoT) に `| `autonomy` | string | `L1` | Autonomy tier governing which L2→L1 loop-firing paths skills may use. `L1` Report / `L2` Assisted / `L3` Unattended. See docs/guide/autonomy.md |` を追加、サンプル `.wholework.yml` ブロックにコメント付き 1 行を追加
6. `docs/tech.md` を更新 (parallel with 4, 5)。Architecture Decisions セクションに `**Autonomy tier (L0 write governance)**` の項を追加。L0/L1/L2/L3 層モデルと L2→L1 経路マトリクスの位置付け、SSoT が `modules/autonomy-tier.md` であること、`permission-mode` (Claude Code 層の権限付与) とは直交する governance 層であることを記載
7. 索引系リストを更新 (parallel with 4, 5, 6)。`docs/guide/index.md` の guide ページ一覧テーブルに `| [Autonomy](autonomy.md) | Choose an autonomy tier (L1/L2/L3) governing how far skills may fire follow-on loops and write GitHub state |` 行を追加、`docs/workflow.md` の Related Documents リストの `l0-surfaces.md` 行の直後に `- [modules/autonomy-tier.md](../modules/autonomy-tier.md) — autonomy tier (L2→L1 path permission) SSoT` を追加
8. 翻訳ミラー同期 (after 4, 6, 7)。translation-workflow.md の sync 手順に従い、top-level docs の変更を日本語ミラーに反映: `docs/ja/structure.md` (count + 2 箇所追加)、`docs/ja/tech.md` (Architecture Decision 項)、`docs/ja/workflow.md` (Related Documents 行)。日本語で記述し見出し/構造を英語版と一致させる

## Alternatives Considered

- **変数名 `HAS_AUTONOMY_TIER` (Issue body 記載) を採用する案**: Issue body の "Enforcement の薄い実装" は export 変数を `HAS_AUTONOMY_TIER` と記載しているが、`modules/detect-config-markers.md` の marker テーブル慣習では boolean key のみ `HAS_*` を使い、値を持つ key (`PERMISSION_MODE`, `SPEC_PATH`, `PRODUCTION_URL` 等) は plain な値名を使う。`autonomy` は tier 値 (L1/L2/L3) を持つため `AUTONOMY_TIER` が慣習整合。→ **不採用** (Notes の conflict 解決参照)。`HAS_` prefix は boolean を想起させ誤読を招く
- **経路 D (Detached subprocess) を許可マトリクスに含める案**: Issue body 通り「親終了で死ぬため信頼性が低い」ことから、カタログには記載するがマトリクスの許可対象列 (A/B/C/E) からは外す。→ カタログ記載 + 非対応明記を採用
- **product.md § Terms に "autonomy tier" を登録する案**: 用語 SSoT への登録は discoverability 上有益だが、どの AC でも要求されておらず、SSoT module (`autonomy-tier.md`) が用語を網羅定義する。translation mirror (docs/ja/product.md) 同期コストも増える。→ **本 Issue では見送り**、enforcement 着地 (#700-703) 時の follow-up 候補として Notes に記録
- **enforcement (skill 側ゲーティング) を本 Issue に含める案**: Issue body の実装順序 (本 Issue → #700/#701/#702/#703) に従い、tail 拡張側が tier ゲートを参照する形で後続に委ねる。本 Issue は「先にマトリクスを確定」する thin scope。→ thin enforcement を採用

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/autonomy-tier.md" --> `modules/autonomy-tier.md` が新規作成され経路定義とマトリクスを SSoT 化している
- <!-- verify: grep "autonomy" "modules/detect-config-markers.md" --> `modules/detect-config-markers.md` の marker テーブルに `autonomy` が追加されている
- <!-- verify: file_contains "modules/autonomy-tier.md" "loop-paths-used" --> skill frontmatter での `loop-paths-used` 宣言ルールが SSoT に記述されている
- <!-- verify: file_contains "modules/autonomy-tier.md" "L1 Report" --> 3 tier (L1 Report / L2 Assisted / L3 Unattended) の用途と許可経路が表で記述されている
- <!-- verify: file_contains "modules/autonomy-tier.md" "L2 Assisted" --> (L2 Assisted tier 名の存在確認)
- <!-- verify: file_contains "modules/autonomy-tier.md" "L3 Unattended" --> (L3 Unattended tier 名の存在確認)
- <!-- verify: file_exists "docs/guide/autonomy.md" --> ユーザ向けガイドが追加されている (`.wholework.yml: autonomy` の選び方と影響)
- <!-- verify: rubric "docs/guide/autonomy.md が autonomy tier (L1/L2/L3) の選び方と各 tier が許可する L2→L1 経路の違いを説明している" --> ガイドに tier 選択基準と経路許可範囲の説明が含まれている
- <!-- verify: file_contains "docs/guide/autonomy.md" "L2 Assisted" --> ガイドに tier 名が記述されている (rubric の補助確認)

### Post-merge

- `.wholework.yml: autonomy: L2` の状態でいずれかの skill (例: 将来の #700 着地後の `/verify`) が許可された経路のみ実行することを観察 <!-- verify-type: manual -->

## Tool Dependencies

実装は既存ツール (Read / Write / Edit、および `gh` コマンド系) のみで完結する。新規ツール追加なし。

### Bash Command Patterns
- none (新規パターンなし)

### Built-in Tools
- `Read` / `Write` / `Edit`: ファイル作成・編集 (allowed-tools 登録済)

### MCP Tools
- none

## Uncertainty

- **Claude Code primitive 名の正確性**: `modules/autonomy-tier.md` が参照する `CronCreate` / `ScheduleWakeup` / `CronList` / `/loop` / `/goal` は実在する Claude Code primitive。
  - **検証方法**: 本セッションで `CronCreate` / `CronList` / `ScheduleWakeup` は deferred tool として、`/loop` / `/schedule` は skill として提示済であることを確認した。本 Issue では module は記述 (descriptive SSoT) のみで runtime 呼び出しは行わないため、名称整合の確認で十分
  - **影響範囲**: Implementation Steps 1 (経路カタログ B/C の記述)
- **enforcement の前提**: 実ゲーティング (skill frontmatter 宣言 + loader 照合) は本 Issue では非実装、#700-703 に委譲。これは設計前提であり不確実性ではない。Post-merge manual AC は #700 着地後の観察を前提とする

## Notes

### Consumed Comments

- `saito` / `MEMBER` / first-class — Issue Retrospective (`/issue` フェーズの Auto-Resolved Ambiguity Points 3 点: OR パターン分割 / `verify-type: manual` 化 / `rubric` + 補助 `file_contains` 追加) / https://github.com/saitoco/wholework/issues/704#issuecomment-4756585645

### Conflict with implementation (Issue body vs marker-table convention)

- **内容**: 変数名。Issue body "Enforcement の薄い実装" は export 変数を `HAS_AUTONOMY_TIER` と記載
- **Issue body 引用**: 「`modules/detect-config-markers.md` の marker テーブルに `autonomy` を追加し、`HAS_AUTONOMY_TIER` を export」
- **実装側慣習**: `modules/detect-config-markers.md` Marker Definition Table — boolean key のみ `HAS_*` (`HAS_OPPORTUNISTIC_VERIFY` 等)、値 key は plain 名 (`PERMISSION_MODE` default `"auto"`、`SPEC_PATH` default `docs/spec`)
- **解決 (非対話 auto-resolve)**: `AUTONOMY_TIER` (string `L1`/`L2`/`L3`、default `L1`) を採用。tier 値を持つため `HAS_` prefix は不適。AC2 (`grep "autonomy"`) は YAML key のみ検査するため変数名選択の影響を受けない

### security policy alignment (governance / access control)

- 本 Issue は GitHub state への書き込み権限の段階化 (governance) を扱うため `SECURITY.md` を確認。autonomy tier は `SECURITY.md § Side Effects (gh Operations)` が列挙する L0 write の上位ガバナンス層であり、`permission-mode` (Claude Code 層の subprocess 権限付与) とは**直交**。**policy conflict なし**
- 本 Issue は thin enforcement (実 side-effect 変更なし) のため `SECURITY.md` 更新は時期尚早。実ゲーティングが skill に配線される #700-703 着地時に SECURITY.md への cross-reference 追記を follow-up 候補とする

### Autonomous Auto-Resolve Log (spec phase, non-interactive)

- **変数名 `AUTONOMY_TIER` を採用** — 理由: marker テーブル慣習 (値 key は plain 名) に整合。other candidate: `HAS_AUTONOMY_TIER` (Issue body 記載、boolean 想起で誤読リスク)
- **不正/未設定値は `L1` (safest) にフォールバック** — 理由: Issue body が未設定時 `L1` を明示。不正値 (例 `autonomy: L9`) の扱いは未記載だが、`permission-mode` / `watchdog-timeout-*` の「不正値→default」フォールバック慣習に整合。other candidate: 不正値で hard-error (起動阻害リスクが高く不採用)
- **product.md § Terms への "autonomy tier" 登録は本 Issue で見送り** — 理由: どの AC でも非要求、SSoT module が用語網羅、translation mirror 同期コスト増。#700-703 着地時の follow-up 候補。other candidate: 即時登録 (scope 拡大)

### scope / simplicity

- translation sync は translation-workflow.md の「top-level docs/*.md」obligation に厳密準拠し、top-level (structure / tech / workflow) のミラーのみ本 PR で同期。guide 配下のミラー (`docs/ja/guide/customization.md`, `index.md`, 新規 `autonomy.md`) は `/doc translate ja` の bulk 同期に委ねる (sync debt として記録)
- 新規 module は 4 セクション標準構造 (Purpose/Input/Processing Steps/Output) を遵守 (skill-dev-checks Shared Module Check)
- 新規テーブル/リストには `(exhaustive)` マーカーを付す (skill-dev-checks Exhaustive/Example markers)
- 本 Issue では SKILL.md / agents の編集なし。Read 指示配置ルール・caller condition propagation は skill 側配線 (#700-703) で扱う
- structure.md の `(37 files)` → `(38 files)` 更新は実装 Step 4 の必須編集。structure.md maintenance rule は count 確認用 verify AC の追加を推奨するが、(1) Issue body の 9 AC との verbatim 整合 (count alignment 9=9) を保ち、(2) `/spec` での issue body 改変 (複雑な escape を含む Auto-Resolved table の再構築リスク) を避けるため、独立 AC 化せず Step 4 + `/review` doc consistency check で担保する
