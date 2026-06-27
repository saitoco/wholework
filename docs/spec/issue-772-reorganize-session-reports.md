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
