# Issue #772: reports: auto-session / auto-events-rollup / loop-state を docs/sessions/ 配下に整理

## Overview

`docs/reports/` 直下に curated な audit/spike/strategy memo と auto 系の自動生成物 (session retro data-layer report、daily rollup、loop-state heartbeat) が混在し、signal/noise 比が劣化している。

session-related な自動生成物を `docs/sessions/` 配下に集約し、`docs/reports/` 直下を curated コンテンツ + cross-Issue SSoT のみに整理する。具体的には:

- `get-auto-session-report.sh` の default output path を `docs/sessions/{sid}-{date}/data-layer.md` (+ `data-layer-ja.md` sibling) に変更
- `auto-events-rollup.sh` の default OUTPUT_DIR を `docs/sessions/_daily` に変更
- `/auto` Loop State Heartbeat の loop-state 書き込み先を `docs/sessions/_daily/loop-state-{DATE}.md` に変更
- `skills/auto/SKILL.md` / `skills/audit/SKILL.md` の path 記述・cross-link を新 path に更新
- `docs/structure.md` (+ `docs/ja/structure.md` mirror) を新 path に更新
- 既存 16 ファイル (data-layer 8 + rollup 7 + loop-state 1) を新 path にマイグレーション

## Changed Files

- `scripts/get-auto-session-report.sh`: default OUTPUT_PATH (`OUTPUT_PATH="docs/reports/auto-session-${SESSION_ID}-${TODAY}.md"`) を `docs/sessions/${SESSION_ID}-${TODAY}/data-layer.md` に変更。先頭の usage コメント (`--output <path>` 行の `default: docs/reports/auto-session-<id>-<date>.md`) も新 path に更新。`mkdir -p "$(dirname "$OUTPUT_PATH")"` は既存のままで新 dir を自動生成。`--output` 指定時の挙動は不変 — bash 3.2+ 互換
- `scripts/auto-events-rollup.sh`: default `OUTPUT_DIR="docs/reports"` を `OUTPUT_DIR="docs/sessions/_daily"` に変更。`--output-dir` 指定時の挙動は不変。`mkdir -p "$OUTPUT_DIR"` は既存のまま — bash 3.2+ 互換
- `skills/auto/SKILL.md`: (1) Loop State Heartbeat セクションの loop-state 書き込み先 (本文 + File 行 + 存在チェック + batch phase 追記指示) を `docs/sessions/_daily/loop-state-{DATE}.md` に変更。(2) data layer report cross-link を新 path に変更 (glob を `docs/sessions/${AUTO_SESSION_ID}-*/data-layer.md`、リンクを `docs/sessions/{AUTO_SESSION_ID}-{DATE}/data-layer.md` に)
- `skills/audit/SKILL.md`: auto-session subcommand の output path 記述 3 箇所 (Output Template Structure の report path、`--output` default 記述、Step 4 の `-ja.md` sibling 生成例) を `docs/sessions/{session-id}-{date}/data-layer.md` / `data-layer-ja.md` に更新
- `docs/structure.md`: (1) `auto-events-rollup.sh` スクリプト説明の出力先を `docs/sessions/_daily/auto-events-rollup-YYYY-MM-DD.md` に更新。(2) Directory Layout tree の `sessions/` ブロックに `data-layer.md` / `data-layer-ja.md` (under `{SID}-{DATE}/`) と `_daily/` サブツリーを追加
- `docs/ja/structure.md`: 翻訳ミラーの該当行 (`auto-events-rollup.sh` 出力先) を新 path に同期 (translation-workflow.md 準拠)
- 既存 data-layer report 8 ファイル: `docs/reports/auto-session-{sid-ts-date}[-ja].md` → `docs/sessions/{sid-ts-date}/data-layer[-ja].md` に `git mv`
- 既存 _daily ファイル 8 個: `docs/reports/auto-events-rollup-*.md` (7) + `docs/reports/loop-state-2026-06-20.md` (1) → `docs/sessions/_daily/` に `git mv`

## Implementation Steps

1. `scripts/get-auto-session-report.sh` の default output path を変更 — Report mode の `if [[ -z "$OUTPUT_PATH" ]]; then OUTPUT_PATH="docs/reports/auto-session-${SESSION_ID}-${TODAY}.md"; fi` を `OUTPUT_PATH="docs/sessions/${SESSION_ID}-${TODAY}/data-layer.md"` に変更。併せて先頭 usage コメントの `--output <path>` 行の default 記述も `docs/sessions/<id>-<date>/data-layer.md` に更新。`mkdir -p "$(dirname ...)"` は据え置き (新 dir を自動生成) (→ acceptance criteria 1, 2, 3)

2. `scripts/auto-events-rollup.sh` の `OUTPUT_DIR="docs/reports"` を `OUTPUT_DIR="docs/sessions/_daily"` に変更 (Defaults セクション。`--output-dir` 引数処理は不変) (parallel with 1) (→ acceptance criteria 4, 5)

3. `skills/auto/SKILL.md` の Loop State Heartbeat セクションの loop-state path を更新 — 「append a line to `docs/reports/loop-state-{DATE}.md`」本文行、「File: `docs/reports/loop-state-{DATE}.md`」行、「If `docs/reports/loop-state-{DATE}.md` does not exist」存在チェック行、および batch phase (next-cycle-seed) の「Append a row to `docs/reports/loop-state-{DATE}.md`」行をすべて `docs/sessions/_daily/loop-state-{DATE}.md` に変更 (parallel with 1, 2) (→ acceptance criteria 6, 7, 8)

4. `skills/auto/SKILL.md` の data layer report cross-link (L3 retro セクション「Cross-link to data layer report」) を更新 — glob 条件を `docs/reports/auto-session-${AUTO_SESSION_ID}-*.md` から `docs/sessions/${AUTO_SESSION_ID}-*/data-layer.md` に、`[Data layer report](...)` リンクを `docs/sessions/{AUTO_SESSION_ID}-{DATE}/data-layer.md` に変更 (after 3) (→ acceptance criteria 6)

5. `skills/audit/SKILL.md` の auto-session subcommand 内 output path 記述 3 箇所を更新 — (a) Output Template Structure の `The generated report (docs/reports/auto-session-{session-id}-{date}.md)` を `docs/sessions/{session-id}-{date}/data-layer.md` に、(b) `--output` の `default: docs/reports/auto-session-<id>-<date>.md` を `default: docs/sessions/<id>-<date>/data-layer.md` に、(c) Step 4 の sibling 生成例 `docs/reports/auto-session-<id>-<date>.md → docs/reports/auto-session-<id>-<date>-ja.md` を `docs/sessions/<id>-<date>/data-layer.md → docs/sessions/<id>-<date>/data-layer-ja.md` に変更 (parallel with 1, 2, 3) (→ acceptance criteria 9, 10)

6. `docs/structure.md` を更新 — (a) `auto-events-rollup.sh` 説明行の出力先を `docs/sessions/_daily/auto-events-rollup-YYYY-MM-DD.md` に変更、(b) Directory Layout tree の `sessions/` ブロックに `{SID}-{DATE}/` 配下の `data-layer.md` / `data-layer-ja.md` と新規 `_daily/` サブツリー (`auto-events-rollup-{DATE}.md` / `loop-state-{DATE}.md`) を追加 (parallel with 1-5) (→ acceptance criteria 13)

7. `docs/ja/structure.md` の `auto-events-rollup.sh` 出力先記述行を新 path (`docs/sessions/_daily/auto-events-rollup-YYYY-MM-DD.md`) に同期。Directory Layout tree も英語版に合わせて `_daily/` / `data-layer` エントリを追加 (translation-workflow.md 準拠の手動ミラー更新) (after 6)

8. data-layer report 8 ファイルをマイグレーション — 各 `docs/reports/auto-session-{REST}.md` について、`{REST}` から `-ja.md` または `.md` を除いた `{sid-ts-date}` を session dir 名とし、`mkdir -p docs/sessions/{sid-ts-date}/` してから `git mv` で `data-layer.md` (非 ja) / `data-layer-ja.md` (ja) に移動。`3480-1782440098-2026-06-27` と `58975-1781511640-2026-06-16` は対応 dir が無い/日付不一致のためファイル名由来で新規 dir を作成 (Auto-Resolved A2) (parallel with 1-7) (→ acceptance criteria 11)

9. _daily ファイル 8 個をマイグレーション — `mkdir -p docs/sessions/_daily/` してから、`docs/reports/auto-events-rollup-*.md` 7 ファイルと `docs/reports/loop-state-2026-06-20.md` 1 ファイルを `git mv` で `docs/sessions/_daily/` に移動 (ファイル名不変) (parallel with 1-8) (→ acceptance criteria 11, 12)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/get-auto-session-report.sh の default output path が docs/sessions/${SESSION_ID}-${TODAY}/data-layer.md 形式に変更されている (-ja.md sibling は data-layer-ja.md として同ディレクトリに生成される)。--output 指定時の仕様は維持" --> get-auto-session-report.sh の output path 変更
- <!-- verify: grep "docs/sessions.*data-layer" "scripts/get-auto-session-report.sh" --> get-auto-session-report.sh に新 path パターンが含まれる
- <!-- verify: file_not_contains "scripts/get-auto-session-report.sh" "docs/reports/auto-session-" --> get-auto-session-report.sh から旧 docs/reports/auto-session- パスが削除されている
- <!-- verify: rubric "scripts/auto-events-rollup.sh の default OUTPUT_DIR が docs/sessions/_daily に変更されている" --> auto-events-rollup.sh の output path 変更
- <!-- verify: grep "docs/sessions/_daily" "scripts/auto-events-rollup.sh" --> auto-events-rollup.sh に新 path のキーワードが含まれる
- <!-- verify: rubric "skills/auto/SKILL.md の Loop State Heartbeat セクションで loop-state-{DATE}.md の書き込み先が docs/sessions/_daily/loop-state-{DATE}.md に更新されている。line 935 付近の batch phase での loop-state 追記指示も含む。さらに、data layer report へのクロスリンク (旧 docs/reports/auto-session-... 形式) が docs/sessions/{AUTO_SESSION_ID}-{DATE}/data-layer.md を指すよう更新されている" --> skills/auto/SKILL.md の loop-state path + cross-link 更新
- <!-- verify: grep "docs/sessions/_daily" "skills/auto/SKILL.md" --> skills/auto/SKILL.md に docs/sessions/_daily キーワードが含まれる
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "docs/reports/loop-state-" --> skills/auto/SKILL.md から旧 loop-state パスが削除されている
- <!-- verify: rubric "skills/audit/SKILL.md の auto-session subcommand の output path 記述 (default path、-ja.md sibling 生成パス記述、説明セクション) が新 path (docs/sessions/{session-id}-{date}/data-layer{-ja}.md) に更新されている" --> audit SKILL.md の path 記述更新
- <!-- verify: file_not_contains "skills/audit/SKILL.md" "docs/reports/auto-session-" --> skills/audit/SKILL.md から旧 docs/reports/auto-session- パスが削除されている
- <!-- verify: rubric "既存ファイルのマイグレーション (docs/reports/ → docs/sessions/{sid}-{date}/ または docs/sessions/_daily/) が完了し、対象 4 session の data-layer report 8 ファイル + auto-events-rollup 7 ファイル + loop-state 1 ファイルがすべて新 path に移動済み、docs/reports/ 直下から消えている" --> 既存 16 ファイルのマイグレーション完了
- <!-- verify: dir_exists "docs/sessions/_daily" --> docs/sessions/_daily ディレクトリが存在する
- <!-- verify: grep "docs/sessions/_daily" "docs/structure.md" --> docs/structure.md の auto-events-rollup.sh 説明が新パスを反映している

### Post-merge

- 次回 `/audit auto-session --full <sid>` 実行で data-layer report が `docs/sessions/{sid}-{date}/data-layer.md` に生成されることを観察 <!-- verify-type: manual -->
- 次回 daily rollup 実行で auto-events-rollup が `docs/sessions/_daily/` 配下に生成されることを観察 <!-- verify-type: manual -->

## Consumed Comments

| login | authorAssociation | trust tier | intent | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective (曖昧ポイント A1-A5 の自動解決根拠 + AC 変更履歴) | https://github.com/saitoco/wholework/issues/772#issuecomment-4817455169 |

cutoff: `2026-06-27T12:16:14Z` (最新 `phase/issue` ラベル付与時刻)。Issue Retrospective の内容は本 Spec の設計に反映済み (Notes の Auto-Resolve Log 参照)。

## Notes

### Auto-Resolve Log (`/issue` フェーズで解決済み、本 Spec に継承)

Issue body の "Auto-Resolved Ambiguity Points" および Issue Retrospective comment で以下が解決済み。`/spec` で新規に検出した曖昧ポイントは無し。

- **A1**: `skills/auto/SKILL.md` の data-layer クロスリンク更新を含める (実装 Step 4)
- **A2**: session dir が存在しない/日付不一致の auto-session ファイルは、ファイル名の `{sid-ts-date}` から `mkdir -p` で新規作成 (実装 Step 8 で `3480-...-2026-06-27`、`58975-...-2026-06-16` に適用)
- **A3**: AC2 の grep を `docs/sessions.*data-layer` に修正 (誤検知排除済み — Issue body 反映済み)
- **A4**: `docs/structure.md` の script 説明更新を含める (実装 Step 6)。`docs/ja/structure.md` は translation mirror として手動同期 (実装 Step 7)
- **A5**: Spec ファイル・curated reports 内の旧パス参照はスコープ外

### Conflict with implementation (Auto-Resolve, non-interactive)

- **内容**: Issue body Background は「`loop-state-*.md` ... `scripts/auto-events-rollup.sh` または `/auto` の Loop State Heartbeat で生成」と記載
- **実際**: `scripts/auto-events-rollup.sh` は loop-state を生成しない (grep 確認済み)。loop-state を生成するのは `skills/auto/SKILL.md` の Loop State Heartbeat (本文 line 566-593) と batch phase next-cycle-seed (line 935) のみ
- **解決**: 移行は (a) 既存 loop-state ファイルの `git mv` (Step 9) と (b) `/auto` SKILL.md の書き込み先 path 更新 (Step 3) の 2 経路でカバーされ、migration の正しさには影響しない。`auto-events-rollup.sh` 側に loop-state 関連の変更は不要

### Migration path derivation rule

data-layer report の移動先は統一規則で導出: `docs/reports/auto-session-` プレフィックスと末尾 `-ja.md` / `.md` を除いた残り `{sid-ts-date}` が session dir 名。非 ja → `data-layer.md`、ja → `data-layer-ja.md`。具体的 8 件:

| 移動元 (docs/reports/) | 移動先 (docs/sessions/) |
|---|---|
| auto-session-22753-1782519060-2026-06-27.md | 22753-1782519060-2026-06-27/data-layer.md |
| auto-session-22753-1782519060-2026-06-27-ja.md | 22753-1782519060-2026-06-27/data-layer-ja.md |
| auto-session-3480-1782440098-2026-06-27.md | 3480-1782440098-2026-06-27/data-layer.md (新規 dir) |
| auto-session-3480-1782440098-2026-06-27-ja.md | 3480-1782440098-2026-06-27/data-layer-ja.md |
| auto-session-58975-1781511640-2026-06-16.md | 58975-1781511640-2026-06-16/data-layer.md (新規 dir) |
| auto-session-58975-1781511640-2026-06-16-ja.md | 58975-1781511640-2026-06-16/data-layer-ja.md |
| auto-session-98315-1782515143-2026-06-27.md | 98315-1782515143-2026-06-27/data-layer.md |
| auto-session-98315-1782515143-2026-06-27-ja.md | 98315-1782515143-2026-06-27/data-layer-ja.md |

_daily 8 件は filename 不変で `docs/sessions/_daily/` へ移動: `auto-events-rollup-{2026-06-15,16,17,18,20,26,27}.md` (7) + `loop-state-2026-06-20.md` (1)。

全ファイル git-tracked のため `git mv` を使用 (Bash リダイレクト/plain mv ではなく)。

### get-auto-session-report.sh cross-link (out of scope)

スクリプト末尾 (L3 session retro への `## See also` cross-link、現行コード) は `docs/sessions/${SESSION_ID}-*/session.md` を glob して repo-relative リンクを data-layer report に追記する。default path 変更後は data-layer.md と session.md が同 dir に co-locate するが、cross-link ロジック自体は本 Issue スコープ外 (output path のみ変更要求)。既存挙動を維持し変更しない。bats `session-xlink` テストは `--output` 明示指定のため影響なし。

### Test impact

`tests/auto-events-rollup.bats` は全テストが `--output-dir docs/reports` を明示指定、`tests/get-auto-session-report.bats` は全テストが `--output <tmp>` を明示指定するため、default path 変更によるテスト破壊は無い (default path は本 Issue では grep/rubric verify でカバー)。新規テスト追加は不要。

### verify-type tag check

post-merge 2 件はいずれも `<!-- verify-type: manual -->`。「次回 `/audit`/daily rollup 実行で...生成されることを観察」は将来の runtime 挙動の観察であり、verify 時点では対象ファイルが未生成のため `file_exists` 等への置換不可。`manual` 分類が適切。

### Exclusions (移動しない / 変更しない)

- `docs/reports/auto-session-performance-2026-06-13.md` — curated audit memo (据え置き)
- `scripts/watchdog-defaults.sh:14` の `docs/reports/auto-session-performance-2026-06-13.md` 参照 — 上記 curated file への comparison/baseline 参照 (変更不要)
- `docs/reports/orchestration-recoveries.md` — cross-Issue SSoT log (据え置き)
- `docs/reports/loop-engineering-wholework-2026-06-18.md` / `docs/ja/reports/loop-engineering-wholework-2026-06-18.md` — curated strategy memo。旧 `docs/reports/loop-state-*` / `docs/reports/auto-events-rollup-*` への参照は設計経緯の historical record のためスコープ外 (A5)
- `docs/spec/*` 内の旧パス参照 — disposable historical record (A5)

### allowed-tools

新規 `scripts/*.sh` 追加なし → SKILL.md frontmatter `allowed-tools` の変更不要。`auto-events-rollup.sh` / `get-auto-session-report.sh` は既存 allowed-tools 登録済み。

### skill-dev-checks (design-time, SPEC_DEPTH=full)

- settings.json 追加: 不要 (新規 skill 無し)
- shared module 抽出: 不要 (path 文字列更新のみ、新規 module 無し)
- Tool Dependencies: なし (実装は `/code` の Edit / Bash `git mv` / `mkdir -p` のみ。frontmatter `allowed-tools` 追加なし、KNOWN_TOOLS 変更なし)
- `validate-skill-syntax.py` 制約: `skills/auto/SKILL.md` / `skills/audit/SKILL.md` の編集は既存構造内の path 文字列置換のみ。frontmatter 不変、半角 `!` 導入なし、triple-backtick 導入なし — 制約違反リスク無し
- Migration Step-Number Reference Check: N/A (本件はリポジトリ内のファイル配置移行であり、他リポジトリからの workflow doc 移行ではない)

## issue retrospective

### 曖昧ポイント自動解決 (non-interactive モード)

| # | ポイント | 解決内容と根拠 |
|---|---------|-------------|
| A1 | `skills/auto/SKILL.md` の data-layer クロスリンク (line 644-650) がスコープに含まれるか | **含める**。SKILL.md のクロスリンクは `docs/reports/auto-session-${AUTO_SESSION_ID}-*.md` を参照しており、マイグレーション後は新パスを指す必要がある。AC3 (SKILL.md path 更新) の当然の一部として扱うのが最リスクの低い判断。 |
| A2 | 既存 auto-session ファイルのマイグレーションで session dir が存在しない / 日付不一致のケース | `auto-session-58975-1781511640-2026-06-16.md` は対応する session dir が存在しない、`auto-session-3480-1782440098-2026-06-27.md` は日付不一致 (`2026-06-26`)。**ファイル名の `{sid-timestamp-date}` 部分を使って `mkdir -p` で新規作成してからマイグレーション**することが最リスクの低い解決 (既存 sessions dir との整合は副次的)。 |
| A3 | AC6 (旧) の `grep "data-layer"` が既存コメント行でマッチする誤検知リスク | `scripts/get-auto-session-report.sh` 冒頭の description コメントに "data-layer" が既に存在するため、旧 AC6 は変更なしで PASS してしまう。**`grep "docs/sessions.*data-layer"` に修正**して新パス文字列を明示的に検証する。 |
| A4 | `docs/structure.md` / `docs/ja/structure.md` の script 説明更新スコープ | `docs/structure.md` line 186 に `docs/reports/auto-events-rollup-YYYY-MM-DD.md` への言及がある。スクリプトの出力先変更に合わせて更新するのが自然。**含める**。`docs/ja/structure.md` は翻訳文書のため verify command なし (再生成は `/doc translate docs/structure.md ja` で対応)。 |
| A5 | Spec ファイルや curated reports 内の旧パス参照 | docs/spec/ 多数と docs/reports/ 内の curated reports に歴史的参照が残る。Spec は disposable historical record であり、curated reports は移動しない対象。**スコープ外**として明記。 |

### Acceptance Criteria の主な変更

1. **AC6 修正**: `grep "data-layer"` → `grep "docs/sessions.*data-layer"` (誤検知リスク排除)
2. **AC1 補強**: `file_not_contains` で旧パス削除を検証する verify command を追加
3. **AC3 拡張**: rubric に data-layer クロスリンク更新を明記。`grep "docs/sessions/_daily"` と `file_not_contains "docs/reports/loop-state-"` を補足追加
4. **AC4 補強**: `file_not_contains "docs/reports/auto-session-"` を追加し旧パス削除を機械的に検証
5. **AC7 補強**: `dir_exists "docs/sessions/_daily"` を追加
6. **新規 AC**: `docs/structure.md` の auto-events-rollup.sh 説明更新を verify command 付きで追加
7. **マイグレーション補足セクション追加**: session dir 不存在ケースの対処方針を明記

## spec retrospective

### Minor observations
- Issue Background に事実誤認: 「`loop-state-*.md` は `scripts/auto-events-rollup.sh` または `/auto` の Loop State Heartbeat で生成」とあるが、`auto-events-rollup.sh` は loop-state を生成せず `/auto` SKILL.md のみが生成する (codebase grep で検出)。migration の正しさには影響しないが、`/issue` 起票時の Background 記述精度の改善余地。

### Judgment rationale
- マイグレーション dir 名はファイル名由来の統一規則 (`auto-session-` プレフィックス + `[-ja].md` サフィックス除去) で導出。A2 に従い、日付不一致 (`3480-...`: filename 06-27 / existing L3 dir 06-26) や対応 dir 不在 (`58975-...`) でもファイル名を SSoT として新規 dir を作成。既存 L3 session dir との物理的 co-location は副次的とした (data-layer と session.md が別 dir になるケースを許容)。
- pre-merge verify 13 件は full テンプレートの soft limit (10) を超えるが、Issue AC との 1:1 verbatim 整合 (count alignment + verify command sync rule) を優先し統合せず維持。
- `get-auto-session-report.sh` 末尾の L3 cross-link ロジックは output path 変更後に data-layer.md と session.md が co-locate するが、本 Issue は output path のみ要求のためスコープ外として変更しない判断。

### Uncertainty resolution
- loop-state 生成元の不確実性は codebase grep (`scripts/auto-events-rollup.sh` 内に loop-state 言及なし) で解消。生成元は `/auto` SKILL.md (Loop State Heartbeat + next-cycle-seed) に限定と確定。
- default path 変更がテストを破壊しないことを bats 確認 (`auto-events-rollup.bats` / `get-auto-session-report.bats` は全テストが `--output-dir` / `--output` を明示指定) で解消。新規テスト追加不要と判断。

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- 全 16 ファイルを `git mv` で移行 (全ファイル git-tracked 確認済み)。data-layer は `docs/sessions/{sid-ts-date}/data-layer[-ja].md`、rollup/loop-state は `docs/sessions/_daily/` へ。
- script の default path 変更が新 dir を自動生成する仕組み (既存 `mkdir -p "$(dirname ...)"` / `mkdir -p "$OUTPUT_DIR"` を活用) を採用、追加の dir 作成ロジックは不要。
- `/auto` は `auto-events-rollup.sh` を引数なしで呼ぶため (SKILL.md line 562/909)、`OUTPUT_DIR` default 変更だけで新 path に自動ルーティング。

### Deferred Items
- post-merge 観察 2 件 (次回 `/audit auto-session` / daily rollup での新 path 生成) は runtime 挙動のため `manual` verify-type。
- `docs/ja/structure.md` の翻訳同期は手動更新 (verify command なし、translation mirror)。

### Notes for Next Phase
- `git mv` 前に各 data-layer の移動先 session dir を `mkdir -p` すること。`3480-1782440098-2026-06-27` と `58975-1781511640-2026-06-16` は新規 dir。
- `file_not_contains` 3 件 (get-auto-session-report.sh / auto SKILL.md loop-state / audit SKILL.md auto-session) は旧 path の完全除去を要求。usage コメント・例示行も漏れなく更新すること。
- `scripts/watchdog-defaults.sh:14` の `auto-session-performance-...` 参照は curated file で据え置き、`file_not_contains "...auto-session-"` の対象外 (別ファイル)。
- shell 編集は bash 3.2+ 互換 (`mapfile` 等 bash4 機能を使わない)。
