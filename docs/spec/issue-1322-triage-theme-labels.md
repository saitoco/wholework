# Issue #1322: triage: テーマ label (theme/*) を導入し Backlog をテーマ単位で消化可能にする

## Overview

`theme/*` という新しい GitHub label namespace (kebab-case、`phase/*` / `audit/*` / `retro/*` と同じ prefix 方式) を導入し、Backlog Issue をテーマ単位で選定・消化できるようにする。初期テーマセットは `theme/observability` / `theme/ac-quality` / `theme/concurrency` / `theme/verify-backlog` の 4 つ。

`/triage` の 3 経路 (Single Issue Execution / Bulk Execution / Backlog Analysis) すべてにテーマ判定を組み込む。判定は Issue 本文と GitHub 上の `theme/*` label カタログ (label 説明文を判定基準として動的に fetch — SKILL.md にハードコードしない) を AI が比較して行い、複数該当を許容し、未分類 (0 件) も許容する。

`docs/product.md § Future Direction` にテーマ駆動での Backlog 消化という方針を追記する。テーマの実体 (どの Issue がどのテーマか) は GitHub label 側を SSoT とし、ドキュメントには書かない。

## Changed Files

- `scripts/setup-labels.sh`: `ALWAYS_LABELS` に `theme/observability` / `theme/ac-quality` / `theme/concurrency` / `theme/verify-backlog` の 4 エントリを追加。label 総数コメントを 2 箇所とも 17→21 に更新
- `skills/triage/SKILL.md`: Single Issue Execution に `### Step 6a: Theme Determination` を新設。Bulk Execution Step 2 (分類項目・catalog fetch・JSON スキーマ・スキーマ表) と Step 3 (label 付与アクション) にテーマ対応を追加。frontmatter `description` を更新。Backlog Analysis Phase 1 は既存の delegation 記述により自動的にカバーされるため直接編集不要
- `docs/product.md`: `## Future Direction` にテーマ駆動 Backlog 消化の方針を追記。`## Terms` の `Issue triage` 行に Theme を追記
- `docs/ja/product.md`: 上記 2 点を日本語ミラー (`docs/translation-workflow.md` の同期対象)
- `docs/tech.md`: `## Wholework Label Management § Label Groups` 表を更新 (Always 17→21、`theme/*` (4) 追加)。`/triage` skill の一行説明に Theme を追記
- `docs/ja/tech.md`: 上記 2 点を日本語ミラー

## Implementation Steps

1. `scripts/setup-labels.sh`: `ALWAYS_LABELS` の `stale-verify` エントリ直後 (配列末尾、閉じ `)` の直前) に以下 4 行を追加:
   ```
   "theme/observability|006B75|Theme: observability — detection without persistence, logging gaps"
   "theme/ac-quality|006B75|Theme: acceptance criteria / verify command quality"
   "theme/concurrency|006B75|Theme: concurrent session conflicts, session_id misattribution"
   "theme/verify-backlog|006B75|Theme: post-merge verify backlog accumulation"
   ```
   ファイル冒頭のコメントブロック (`# Label groups:` ブロック、`set -euo pipefail` の直前) の `Always-group (17 labels): phase/*, triaged, retro/verify, retro/code, retro/recoveries, audit/drift, audit/fragility, audit/auto, stale-verify` を、末尾に `, theme/*` を足して `17`→`21` に更新。`ALWAYS_LABELS=(` 直前の `# Count: 17 labels` コメントも `# Count: 21 labels` に更新。bash 3.2+ 互換 (配列への文字列追加のみ、新規構文なし) (→ acceptance criteria 1, 2)

2. `skills/triage/SKILL.md`:
   - frontmatter `description`: `Type/Priority/Size/Value assignment` → `Type/Priority/Size/Value/Theme assignment`
   - `### Step 6: Size Determination` の内容末尾の直後 (`### Step 7: AC Verify Command Integrity Audit` の直前) に `### Step 6a: Theme Determination` を新設する。内容: `gh label list --limit 200 --json name,description --jq '.[] | select(.name | startswith("theme/"))'` で現在の theme label カタログを fetch し、各 label の `description` と Issue title/body を AI 判断で比較する。複数テーマの該当を許容する (単一に絞らない) こと、0 件の場合は未分類のまま label を付与しないことを明記する。結果を `DETERMINED_THEMES` (0 件以上のリスト) として保持し、各テーマについて `gh issue edit $NUMBER --add-label "theme/<name>"` を実行する
   - `#### Step 2: Bulk Classification`: 「Classification per issue」の箇条書きに「Theme determination (0 件以上、catalog fetch と判定方針は Step 6a と同一)」を追加。Phase 2 冒頭の Steering Documents 読み込みと同様に、theme label カタログの fetch (Step 6a と同じ `gh label list` コマンド) をバッチ全体で 1 回だけ実行する旨を追記。Output JSON スキーマ例に `"theme": ["theme/observability"]` を追加し、スキーマ表に `theme` 行 (`string[]` / required / 「0 件以上の `theme/*` label 名。未分類なら空配列 `[]`。複数可」) を追加
   - `#### Step 3: Bulk Update`: 既存の項目 5 (`Add triaged label`) の直後に新規アクション `theme[]` の各要素について `gh issue edit $NUMBER --add-label "<theme>"` (空なら skip) を挿入し、既存の項目 6 (Duplicate comment) → 7、項目 7 (AC verify command audit) → 8 に繰り下げる
   - `## Backlog Analysis (`/triage --backlog`)` § Step 5 の Phase 1 は直接編集しない — 既存の「Bulk Execution の Step 1→2→3 と同じ手順」という delegation 記述により、上記 Bulk Execution への変更を自動的に継承する
   (→ acceptance criteria 3, 4, 5)

3. `docs/product.md` + `docs/ja/product.md`:
   - `## Future Direction` (英語) の末尾に追加: `- **Theme-driven backlog consumption**: Issues carry \`theme/*\` labels (assigned by \`/triage\`) so that batches of related backlog Issues can be selected and consumed together, rather than relying solely on Value/Priority ordering. Unclassified Issues remain untagged — full coverage is not required. The theme catalog itself lives on GitHub labels (SSoT), not in this document, to avoid dual-maintenance between GitHub state and docs.`
   - `## 今後の方向性` (日本語ミラー) の末尾に対応する内容を追加: `- **テーマ駆動での Backlog 消化**: Issue に \`theme/*\` label (\`/triage\` が付与) を持たせることで、Value/Priority 順だけに頼らず、関連する backlog Issue をまとめて選定・消化できるようにする。未分類の Issue には無理に label を付与しない (全件網羅は要求しない)。テーマの実体は GitHub の label 側を SSoT とし、本ドキュメントには記述しない (GitHub state とドキュメントの二重管理を避けるため)。`
   - 両ファイルの `## Terms` (`## 用語` 相当のテーブル) の `Issue triage` 行: `Type/Priority/Size/Value` → `Type/Priority/Size/Value/Theme`
   (→ acceptance criteria 6)

4. `docs/tech.md` + `docs/ja/tech.md`: `## Wholework Label Management § Label Groups` 表の `Always`/`常時` 行を `17`→`21` に更新し、Labels セルに `theme/*` (4) を追記 (各ファイル既存の半角/全角括弧表記に合わせる — `docs/tech.md` は半角 `(4)`、`docs/ja/tech.md` は既存行の全角`（4）`表記を踏襲)。`/triage` skill の一行説明 (`Type/Priority/Size/Value` を含む行) にも Theme を追記。SHOULD レベルの同期 — acceptance criteria 1–3 が主張する事実の一貫性を補強する

5. `bats tests/setup-labels.bats` を実行し全件 PASS を確認する。`count_always_labels()` は `ALWAYS_LABELS` を `awk` で動的にパースするため、新規 4 エントリに自動追従しテストファイル自体の変更は不要 (→ acceptance criteria 7)

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/setup-labels.sh" "theme/" --> `scripts/setup-labels.sh` に `theme/*` label が定義されている
- <!-- verify: rubric "scripts/setup-labels.sh に定義された theme/* label が 4 つ以上あり、それぞれ既存 label と同じ name|color|description 形式に従っている。あわせて冒頭のコメントにある label 総数の記述が実際の定義数と一致している" --> 初期テーマセットが既存形式に従って定義され、総数の記述も同期している
- <!-- verify: rubric "skills/triage/SKILL.md の Single Issue Execution / Bulk Execution / Backlog Analysis の 3 経路すべてに theme label の判定と付与のステップが追加されている。Bulk Execution については Step 2 の分類 JSON スキーマにも theme フィールドが追加されている" --> `/triage` の 3 経路すべてにテーマ判定が組み込まれている
- <!-- verify: section_contains "skills/triage/SKILL.md" "Step 2: Bulk Classification" "theme" --> Bulk Execution Step 2 の出力 JSON スキーマ節に `theme` フィールドの記述がある (前項 rubric の補助的機械チェック)
- <!-- verify: rubric "skills/triage/SKILL.md に、テーマが判定できない Issue には theme label を付与しない (未分類を許容する) 旨と、1 Issue に複数テーマが該当する場合の扱いが明記されている" --> 未分類の許容と複数該当時の扱いが明記されている
- <!-- verify: section_contains "docs/product.md" "Future Direction" "theme" --> `docs/product.md § Future Direction` にテーマ駆動の方針が追記されている
- <!-- verify: command "bats tests/setup-labels.bats" --> `tests/setup-labels.bats` の既存スイートが回帰していない (回帰保護のみを目的とする AC — 新規カバレッジの主張は前 5 項が担う)

### Post-merge

- 次に `/triage` が実行された Issue について、テーマが判定可能なものに `theme/*` label が付与されていることを確認する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **Issue 本文 AC4 の verify command 修正**: コメント消費フェーズで、MEMBER (saito) による Triage AC audit コメントが AC4 の `section_contains` heading 引数に `####` が含まれている問題を指摘した。`modules/verify-executor.md` の `section_contains` 仕様は見出し行から先頭の `#` と空白を除去してから部分一致するため、`"#### Step 2: Bulk Classification"` は恒久的に UNCERTAIN になる。Issue 本文側を `"Step 2: Bulk Classification"` に修正済み (本 Spec の Verification にも修正後の形で反映)
- **テーマカタログは動的 fetch、SKILL.md にハードコードしない**: `gh label list --jq 'startswith("theme/")'` で実行時に現在の `theme/*` label 一覧を取得する設計とした。Issue 本文の「SSoT は GitHub の label 側」という設計方針に従うもので、将来テーマを追加・改名する際は `scripts/setup-labels.sh` の変更のみで済み、`skills/triage/SKILL.md` の編集は不要になる。各 label の `description` フィールドが AI 判定基準を兼ねるため、`scripts/setup-labels.sh` の description は `Theme: <slug>` だけでなく判定に資する具体的な文言にした
- **label 色**: 新規 4 label には `006B75` (teal) を採用。既存の全 label 色 (`phase/*`=`1B4F8A`, `triaged`=`0E8A16`, `retro/*`=`5319E7`, `audit/*`=`D93F0B`/`E4E669`, `stale-verify`=`EDEDED` 等) と重複しない
- **`docs/guide/workflow.md` はスコープ外**: 同ファイルの `/triage` 説明 (`Assigns Type (...), Size (...), and Priority to issues`) は既に `Value` を欠いている (本 Issue と無関係な既存の記載漏れ)。Theme もそこには追加せず、本 Issue のドキュメント変更は用語/label の SSoT 面 (`docs/product.md § Terms`, `docs/tech.md § Label Groups`) に絞った
- **Backlog Analysis Phase 1 の無編集判断**: AC3 の rubric verify command は `skills/triage/SKILL.md` をテキスト中で明示しているため (`modules/verify-executor.md` の rubric 仕様により diff だけでなくファイル全文が grader に渡る)、Phase 1 の既存 delegation 記述 (「Bulk Execution の Step 1→2→3 と同じ手順」) がそのまま theme 対応を継承していることを grader 側で確認できる

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust: first-class / `/issue 1322 --non-interactive` によるリファインメント実行記録 (曖昧ポイント自動解決の根拠: 複数テーマ許容、AC への section_contains 補助チェック追加、機械チェック結果は全て問題なし) / https://github.com/saitoco/wholework/issues/1322#issuecomment-5236132378
- login: saito / authorAssociation: MEMBER / trust: first-class / Triage AC audit — AC4 の `section_contains` verify command のバグ指摘 (heading 引数の `####` が恒久的 UNCERTAIN を招く)。本 Spec 作成時に Issue 本文へ修正を適用済み / https://github.com/saitoco/wholework/issues/1322#issuecomment-5236162342
- (review phase, cutoff 2026-08-10T05:37:20Z) No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–5 を計画通りに実施した

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A — ただし Step 9 の behavioral change detection で `docs/tech.md` が `tests/run-merge.bats` / `tests/verify-dirty-detection.bats` から参照されている (直接対応テストなし) ことを検知し、フルスイート並列実行 (`bats --jobs 18 tests/`) を追加実施した。`tests/post_merge_check.bats` の1件 (`fail: gh issue reopen called when FAIL input given`) が並列実行時のみ FAIL したが、単体実行では PASS したため並列実行時のフレークと判断し、本 Issue の変更 (`scripts/setup-labels.sh` / `skills/triage/SKILL.md` / docs) との関連はない

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implementation Steps 1–5 を Spec 通りに実施 (`scripts/setup-labels.sh` の 4 label 追加、`skills/triage/SKILL.md` の 3 経路統合、`docs/product.md`/`docs/tech.md` とその日本語ミラーの更新)
- Pre-merge AC 7 件すべてを verify-executor full mode で実行し PASS を確認、Issue 側チェックボックスを更新済み

### Deferred Items
- Post-merge AC (`/triage` が次回実行された Issue に `theme/*` label が付与されることの確認) は `session=next` の observation として未実施のまま。次回 `/verify` または `/triage` 実行時に検証される
- 検討したが採らない案 (`docs/roadmap.md` 新設、Projects Theme field、XL parent Issue 化) は Spec Notes に既出、フォローアップ不要

### Notes for Next Phase
- `docs/tech.md` を編集したことで `tests/run-merge.bats` / `tests/verify-dirty-detection.bats` がフルスイート実行対象に入った。`tests/post_merge_check.bats` の1件が並列実行下でのみ FAIL したが単体では PASS (フレーク、本 Issue の変更とは無関係) — review/merge フェーズで再発した場合は無関係な既存フレークとして扱ってよい
- `docs/structure.md` および `docs/guide/autonomy.md` / `docs/guide/index.md` の `docs/ja/` 未同期は本 Issue 着手前からの既存ギャップで、本 Issue のスコープ外

## review retrospective

### Spec vs. implementation divergence patterns
- `docs/spec/issue-1322-triage-theme-labels.md` の Changed Files には `modules/label-conventions.md` が含まれていなかったが、実装は `scripts/setup-labels.sh` に新規 namespace `theme/*` を追加していた。`modules/label-conventions.md` はラベル namespace の SSoT であり「新規 namespace 追加時は本ファイルと `scripts/setup-labels.sh` を同時更新」と明記しているにもかかわらず、Spec 立案時にこの同期要件が見落とされていた (review で SHOULD として検出・修正済み)。新規 label namespace を追加する Issue は、今後 Spec の Changed Files 検討時に `modules/label-conventions.md` を機械的にチェックリストへ含めることが望ましい

### Recurring issues
- 特筆事項なし — 今回検出した3件 (SHOULD 1・CONSIDER 2) は異なるカテゴリで、同一パターンの反復ではない

### Acceptance criteria verification difficulty
- 特筆事項なし — Pre-merge AC 7件すべてが verify command (`file_contains`/`rubric`/`section_contains`/`command`) により UNCERTAIN なくクリーンに PASS した。verify command の記述精度が高く、/code フェーズでの事前検証と一致していた

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #1331 は mergeable=true (CI success, review approved) だったため Step 2/3 (Worktree Entry / Resolve Conflicts) をスキップし、Step 4 (Squash Merge) を直接実行
- Pre-merge AC gate: 7/7 checked、review-incomplete-fallback も検出なし。マージ前ゲートは無条件通過

### Deferred Items
- Post-merge AC (`/triage` が次回実行された Issue に `theme/*` label が付与されることの確認) は引き続き `session=next` の observation として未実施

### Notes for Next Phase
- `/verify 1322` で post-merge AC (observation, session=next) を確認すること
- `tests/post_merge_check.bats` の並列実行時フレークは本 PR の変更と無関係の既知フレーク
