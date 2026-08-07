# Issue #1214: auto: next-cycle seed (経路 E) を撤去し次サイクル選定を audit session に一本化

## Consumed Comments

cutoff: `2026-08-06T14:27:00Z` (直近の `phase/issue` label 付与時刻)

| login | authorAssociation | trust tier | intent | URL |
|-------|-------------------|-----------|--------|-----|
| saito | MEMBER | first-class | `/issue 1214 --non-interactive` の Issue Retrospective (Triage 結果・verify command 監査・自動解決 2 件・AC 補強 2 件) | https://github.com/saitoco/wholework/issues/1214#issuecomment-5206082995 |
| saito | MEMBER | first-class | 削除系事前スキャンの追実施報告。`docs/guide/autonomy.md` の記載漏れ検出、`docs/spec/**` と `docs/sessions/**` は歴史的記録として編集対象外と確定 | https://github.com/saitoco/wholework/issues/1214#issuecomment-5206139243 |

いずれも本 Spec の設計前提として取り込み済み。2 件目が確定させた「編集対象外 = 歴史的記録」の線引きは、本 Spec の `## Exclusions` にそのまま引き継いだ。

## Overview

`/auto --batch` 完了 tail の next-cycle seed (Loop Engineering 経路 E: Seed file emission、#703 実装) を撤去する。20 回発火して全回 `candidate_count=0`、かつ `.tmp/next-cycle.json` を読むコードがリポジトリ全体でゼロという「書き込み専用の死んだ機能」を、設定キー・イベントスキーマ・ガバナンス語彙 (経路 E) ごと削除する。

バッチ側に残すのは path A の advisory 出力 1 行のみ。次サイクル候補の選定は独立した `/audit` session に責務移管し、バッチはそこへのポインタだけを出力する。

## Changed Files

### 実装・設定

- `skills/auto/SKILL.md`:
  - frontmatter `loop-paths-used: [A, E]` → `loop-paths-used: [A]`
  - frontmatter `loop-paths-fallback: [A]` 行を削除 (E が消えると A は全 tier で常に許可されるため発火しえない死んだ宣言。`skills/verify/SKILL.md` が `loop-paths-used: [A]` のみで fallback 行を持たず、これが既存の慣例)
  - `**Next-cycle seed (batch, best-effort):**` ブロック全体を削除し、無条件の advisory 出力 1 段落に置換。挿入位置は `**Run-fact AC reconciliation (runs after the observation scan, best-effort):**` ブロック直後・`**L3 auto-retrospective (batch route):**` 直前 (行番号ではなく前後の見出しで特定すること)
  - `allowed-tools` は**変更しない** (下記 Exclusions 参照)
- `.wholework.yml`: `next-cycle-seed:` ブロック (`next-cycle-seed:` + `  enabled: true` の 2 行) を削除
- `scripts/emit-event.sh`: `# next_cycle_seeded: ...` スキーマコメントブロック (ヘッダ 1 行 + `candidate_count` / `source_breakdown` / `batch_session_id` の 3 フィールド行 + 直後の区切り `#` 行) を削除。bash 3.2+ 互換 — コメント削除のみで実行コードに変更なし
- `modules/detect-config-markers.md`: (a) Marker Definition Table の `| next-cycle-seed.enabled | NEXT_CYCLE_SEED_ENABLED | ... |` 行、(b) YAML Parsing Rules の `- next-cycle-seed.* nested keys are interpreted under ...` 行、(c) Output Format コードフェンス内の `NEXT_CYCLE_SEED_ENABLED: ...` 行 — 計 3 箇所を削除

### フレームワーク (経路 E 削除)

- `modules/autonomy-tier.md`:
  - L2→L1 Path Catalog から `| **E** | Seed file emission | ... |` 行を削除
  - Tier × L2→L1 Path Matrix から `E` 列を削除 (ヘッダ行 `| Tier | A | B | C | E | Default use |`、区切り行、L1/L2/L3 の 3 データ行すべて)
  - 同マトリクス L2 Assisted 行の Default use 文 `Mid-scale modernization (anchor case). Seed is automated; cron requires a human to trigger.` → `Mid-scale modernization (anchor case). The main workflow is automated; cron requires a human to trigger.`
  - L0 Layer Table の L2 行 drive mechanism `Tail extension (#700/702/703)` → `Tail extension (#700/702)`
  - Skill Frontmatter Declaration Rules のコード例 `loop-paths-used: [A, E]` → `loop-paths-used: [A]`
  - 宣言規則本文 `list of path IDs the skill uses (\`A\`, \`B\`, \`C\`, \`E\`). D is omitted (not supported).` から `` `E` `` を除去
  - マトリクス直後の除外注記 `Path D is excluded from the matrix because it is not supported.` は**変更しない** (D は経路表に残存しつつ列だけ除外、E は行ごと削除で状況が異なる)
  - 両テーブル見出しの `(exhaustive)` マーカーは維持 (E 削除後も網羅性の主張は変わらない)

### ドキュメント

- `docs/guide/customization.md`: (a) 設定リファレンス表の `| next-cycle-seed.enabled | ... |` 行を削除、(b) `.wholework.yml` サンプルのコメント `# L1 = advisory only (safest), L2 = assisted (main workflow + seed), L3 = unattended (CronCreate allowed)` から `+ seed` を除去、(c) 設定リファレンス表 `autonomy` 行の `` `L2` Assisted (in-loop + seed) `` → `` `L2` Assisted (in-loop) ``
- `docs/ja/guide/customization.md`: `| next-cycle-seed.enabled | ... |` 行を削除 (翻訳同期)。EN 側 (b)(c) に対応する記述は JA ミラーに存在しない (本 Issue 以前からの翻訳ドリフト) ため同期対象は 1 行のみ — grep 確認済み
- `docs/tech.md`: Architecture Decisions の Autonomy tier 項 (1 段落) について、(a) 経路列挙 `(A Advisory / B CronCreate / C ScheduleWakeup / E Seed file emission)` → `(A Advisory / B CronCreate / C ScheduleWakeup)`、(b) 末尾文 `Remaining gating enforcement (#702, #703) is tracked in follow-up Issues.` を文ごと削除 (#702/#703 とも CLOSED 済みかつ #703 は本 Issue の撤去対象)
- `docs/ja/tech.md`: 同項 (翻訳同期) について、(a) `（A Advisory / B CronCreate / C ScheduleWakeup / E Seed file emission）` → `（A Advisory / B CronCreate / C ScheduleWakeup）`、(b) 末尾の `残りのゲーティング実施（#702、#703）はフォローアップ Issue で追跡` を削除し、直前の `#700（...）で実装済み。` で段落を終える
- `docs/guide/autonomy.md`: (a) L2 tier 節 `Allowed L2→L1 paths: **A (Advisory), C (ScheduleWakeup in-loop), E (Seed file emission)**` → `Allowed L2→L1 paths: **A (Advisory), C (ScheduleWakeup in-loop)**`、(b) L3 tier 節 `Allowed L2→L1 paths: **A, B (CronCreate), C, E**` → `Allowed L2→L1 paths: **A, B (CronCreate), C**`、(c) Why it exists 節の `... through Claude Code primitives (\`CronCreate\`, \`ScheduleWakeup\`) or seed files.` から `or seed files` を除去、(d) L2 tier 節 `Skills write GitHub state (same as current \`/auto\` and \`/verify\` behavior) and may emit seed files for the next cycle.` から `and may emit seed files for the next cycle` を除去。JA ミラー (`docs/ja/guide/autonomy.md`) は未作成であり、`docs/translation-workflow.md` の同期義務は top-level `docs/*.md` 限定のため新規作成しない
- `docs/reports/external-kill-investigation.md`: 2026-07-15 Update 節の `#1006, #1007 — confirmed via the \`next_cycle_seeded\` event's \`batch_session_id\` field` 記述に、代替判別手段の注記を追加。注記内容は「`next_cycle_seeded` は #1214 で撤去済み。以降のバッチセッション判定には `.tmp/auto-session-<AUTO_SESSION_ID>.json` の `"mode": "batch"` フィールドを使う」。歴史的記録なので既存記述自体は書き換えず、注記の追加のみ

### Steering Docs sync candidate

- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] `scripts/emit-event.sh` の説明行あり。ただし記述は `emit_event()` / `restore_auto_session_pointer()` の役割と呼び出し元一覧のみで、個別イベント型のスキーマ列挙は無い。本 Issue の変更はコメント削除のみのため更新不要と判断 (grep 確認済み)。`/code` フェーズで最終判断すること
- `modules/event-emission.md`: [Steering Docs sync candidate] イベント emission 契約の SSoT だが `next_cycle_seeded` への言及なし (repo 全体 grep で 0 件)。更新不要
- `tests/emit-event.bats`: [Steering Docs sync candidate] `scripts/emit-event.sh` のテスト。`next_cycle_seeded` への言及なし (grep 確認済み)。コメント行削除のみのため更新不要
- `docs/workflow.md` / `docs/ja/workflow.md`: [Steering Docs sync candidate] `autonomy:` tier への言及はあるが blocked-by の tier-aware action に限定され、経路 E / seed への言及なし (grep 確認済み)。更新不要

## Exclusions

削除系事前スキャン (`next-cycle-seed` / `next_cycle_seeded` / `next-cycle.json` / `Seed file emission` / `NEXT_CYCLE_SEED_ENABLED` + 追加の `seed` 単独キーワード) でヒットするが、意図的に変更しないもの。

- `docs/spec/issue-701-*.md`, `issue-703-*.md`, `issue-704-*.md`, `issue-772-*.md`, `issue-854-*.md`, `issue-1014-*.md` — 実装当時 / 関連整理時の Spec (歴史的記録)
- `docs/reports/loop-engineering-wholework-2026-06-18.md` / `docs/ja/reports/loop-engineering-wholework-2026-06-18.md` — 日付入りの設計レポート (経路 E の原設計)
- `docs/sessions/**/events.jsonl` — 記録済み `next_cycle_seeded` イベント (実行履歴)
- `skills/auto/SKILL.md` `allowed-tools` の `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` — 本文からの `emit-event.sh` 参照は削除ブロック内 1 箇所のみだが、`scripts/check-allowed-tools.sh` が呼ぶ `validate-skill-syntax.py` の検出方向は「本文で参照しているのに allowed-tools に無い」(過少宣言) のみで、過剰宣言は検出されない (実装確認済み: `validate-skill-syntax.py` は body 側の `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` を走査して allowed-tools 側に存在するかを見る片方向チェック)。無害かつ将来の再利用余地があるため残す
- `skills/audit/SKILL.md` の `seeds of future problems` — 無関係な英単語 (fragility の severity 説明)

## Implementation Steps

1. `skills/auto/SKILL.md` の frontmatter を修正 — `loop-paths-used: [A, E]` を `loop-paths-used: [A]` に変更し、直後の `loop-paths-fallback: [A]` 行を削除する。`allowed-tools` は変更しない (→ acceptance criteria 4, 5)

2. `skills/auto/SKILL.md` の Batch Completion Report 内 `**Next-cycle seed (batch, best-effort):**` ブロック (見出し行から `If any step in path E fails, ...` の段落まで) を削除し、同じ位置に無条件の advisory 段落を置く (parallel with 1)。挿入位置は Run-fact AC reconciliation ブロック直後・`**L3 auto-retrospective (batch route):**` 直前。置換後の本文は次の 2 要素とする (→ acceptance criteria 1, 2, 3):
   - 見出し行: `**Next-cycle candidate handoff (batch):**`
   - 本文 1 段落: `Recommend: run /audit drift to identify next-cycle candidates` をそのまま出力する旨と、autonomy tier / 設定フラグによる分岐を持たない唯一の挙動である旨、および次サイクル候補の選定責務が独立した `/audit` session にある旨
   - 制約: 半角感嘆符・triple backtick・YAML block scalar を新規導入しないこと (`validate-skill-syntax.py`)。`AUTONOMY_TIER` / `NEXT_CYCLE_SEED_ENABLED` の読み込み記述と `modules/detect-config-markers.md` の Read 指示はブロックごと消えるため、この段落には残さない

3. `.wholework.yml` から `next-cycle-seed:` ブロック 2 行を削除する (parallel with 1, 2) (→ acceptance criteria 6)

4. `scripts/emit-event.sh` から `next_cycle_seeded` スキーマコメントブロックを削除する (parallel with 1, 2, 3)。前後のイベント (`retro_proposal_classified` / `verify_fail_marker_posted`) のコメントブロック区切り (`#` 単独行) が二重にも欠落にもならないよう確認すること (→ acceptance criteria 7)

5. `modules/detect-config-markers.md` の 3 箇所 (Marker Definition Table 行 / YAML Parsing Rules 行 / Output Format 行) を削除する (parallel with 1-4) (→ acceptance criteria 8, 9)

6. `modules/autonomy-tier.md` を修正する (parallel with 1-5) — Path Catalog の E 行削除、Tier × Path Matrix の E 列削除 (ヘッダ・区切り・3 データ行)、L2 Assisted 行 Default use 文の書き換え、L0 Layer Table の `#700/702/703` → `#700/702`、frontmatter 宣言例 `[A, E]` → `[A]`、宣言規則 path ID 列挙から `E` を除去。除外注記 (`Path D is excluded ...`) は変更しない (→ acceptance criteria 10, 11, 12, 13, 14)

7. `docs/guide/customization.md` の 3 箇所 (`next-cycle-seed.enabled` 行削除 / `.wholework.yml` サンプルコメントの `+ seed` 除去 / `autonomy` 行の `+ seed` 除去) を修正し、続けて `docs/ja/guide/customization.md` の `next-cycle-seed.enabled` 行を削除する (after 5) (→ acceptance criteria 15, 16, 17)

8. `docs/tech.md` の Autonomy tier 項 2 箇所 (経路列挙から `/ E Seed file emission` 除去 / 末尾 follow-up 文の削除) を修正し、続けて `docs/ja/tech.md` の対応 2 箇所を同期する (after 6) (→ acceptance criteria 18, 19, 20, 21)

9. `docs/guide/autonomy.md` の 4 箇所 (L2 tier の Allowed paths / L3 tier の Allowed paths / Why it exists 節の `or seed files` / L2 tier 節の `and may emit seed files for the next cycle`) を修正する (after 6) (→ acceptance criteria 22, 23)

10. `docs/reports/external-kill-investigation.md` の `next_cycle_seeded` を根拠に使う記述へ、代替判別手段 (`.tmp/auto-session-<AUTO_SESSION_ID>.json` の `"mode": "batch"`) の注記を追加する (after 4) (→ acceptance criteria 24)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "skills/auto/SKILL.md" "next-cycle.json" --> `skills/auto/SKILL.md` から next-cycle seed ブロックが削除されている
- <!-- verify: file_contains "skills/auto/SKILL.md" "Recommend: run /audit drift" --> path A の advisory 出力は残っている
- <!-- verify: rubric "skills/auto/SKILL.md の Batch Completion Report において、/audit drift を推奨する advisory 出力が autonomy tier や設定フラグによる条件分岐なしに常に実行される形になっている" --> advisory 出力が無条件の唯一の挙動になっている
- <!-- verify: grep "loop-paths-used: \[A\]" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` の frontmatter が `loop-paths-used: [A]` になっている
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "loop-paths-fallback" --> `skills/auto/SKILL.md` の frontmatter から死んだ `loop-paths-fallback` 宣言が削除されている
- <!-- verify: file_not_contains ".wholework.yml" "next-cycle-seed" --> `.wholework.yml` から `next-cycle-seed` 設定が削除されている
- <!-- verify: file_not_contains "scripts/emit-event.sh" "next_cycle_seeded" --> `scripts/emit-event.sh` から `next_cycle_seeded` スキーマが削除されている
- <!-- verify: file_not_contains "modules/detect-config-markers.md" "NEXT_CYCLE_SEED_ENABLED" --> `modules/detect-config-markers.md` から marker 定義が削除されている
- <!-- verify: file_not_contains "modules/detect-config-markers.md" "next-cycle-seed" --> `modules/detect-config-markers.md` から YAML パース規則の記述も含めて `next-cycle-seed` キーへの言及が削除されている
- <!-- verify: file_not_contains "modules/autonomy-tier.md" "Seed file emission" --> `modules/autonomy-tier.md` の経路表から経路 E が削除されている
- <!-- verify: file_not_contains "modules/autonomy-tier.md" "A, E" --> frontmatter 宣言例が `[A]` に更新されている
- <!-- verify: rubric "modules/autonomy-tier.md の Tier × L2→L1 Path Matrix から E 列が削除され、残る列が A / B / C のみになっている。また frontmatter 宣言規則の path ID 列挙からも E が除かれている" --> Tier × 経路マトリクスと宣言規則から経路 E が除かれている
- <!-- verify: file_not_contains "modules/autonomy-tier.md" "Seed is automated" --> Tier × 経路マトリクスの L2 Assisted 行 Default use 文から seed 前提の記述が除かれている
- <!-- verify: file_not_contains "modules/autonomy-tier.md" "#700/702/703" --> L0 Layer Table の drive mechanism から撤去済み #703 への言及が除かれている
- <!-- verify: file_not_contains "docs/guide/customization.md" "next-cycle-seed" --> `docs/guide/customization.md` から設定行が削除されている
- <!-- verify: file_not_contains "docs/guide/customization.md" "seed" --> `docs/guide/customization.md` の `.wholework.yml` サンプルコメントと `autonomy` 行からも seed 前提の記述が削除されている
- <!-- verify: file_not_contains "docs/ja/guide/customization.md" "next-cycle-seed" --> `docs/ja/guide/customization.md` から設定行が削除されている (翻訳同期)
- <!-- verify: file_not_contains "docs/tech.md" "Seed file emission" --> `docs/tech.md` の経路列挙から E が削除されている
- <!-- verify: file_not_contains "docs/tech.md" "is tracked in follow-up Issues" --> `docs/tech.md` から #702/#703 フォローアップ言及の文が削除されている
- <!-- verify: file_not_contains "docs/ja/tech.md" "Seed file emission" --> `docs/ja/tech.md` の経路列挙から E が削除されている (翻訳同期)
- <!-- verify: file_not_contains "docs/ja/tech.md" "フォローアップ Issue で追跡" --> `docs/ja/tech.md` から #702/#703 フォローアップ言及の文が削除されている (翻訳同期)
- <!-- verify: file_not_contains "docs/guide/autonomy.md" "Seed file emission" --> `docs/guide/autonomy.md` の L2/L3 tier 説明から経路 E への言及が削除されている
- <!-- verify: file_not_contains "docs/guide/autonomy.md" "seed files" --> `docs/guide/autonomy.md` の散文から seed file 前提の記述が削除されている
- <!-- verify: rubric "docs/reports/external-kill-investigation.md の next_cycle_seeded を根拠に使っている記述に、代替判別手段 (.tmp/auto-session-*.json の mode: batch) の注記が追加されている" --> external-kill 調査の判別手段に代替が注記されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが green
- <!-- verify: github_check "gh pr checks" "Validate skill syntax" --> CI の skill 構文検証が green

### Post-merge

- 次回以降の `/auto --batch` 完走時に `.tmp/next-cycle.json` が生成されず、`next_cycle_seeded` イベントも emit されず、代わりに `/audit drift` の推奨が出力されることを観察する (`verify-type: observation event=auto-run session=next`)

## Tool Dependencies

実装は既存ファイルの編集のみで、新規ツール権限の追加は不要。

### Bash Command Patterns
- none (新規追加なし)

### Built-in Tools
- none (`Read` / `Edit` はいずれも `/code` の `allowed-tools` に登録済み)

### MCP Tools
- none

## Notes

### 設計前提の検証結果 (実装前に確認済み)

- **過去イベントの後方互換**: `.tmp/auto-events.jsonl` に残る 20 件の `next_cycle_seeded` は削除しない。`scripts/collect-run-facts.sh` と `scripts/get-auto-session-report.sh` はいずれも `select(.event == "<既知イベント名>")` のホワイトリスト方式で、未知イベント型は一致しないだけで無視される (両スクリプトを grep 確認)。撤去後も読み取りは壊れない
- **`"mode": "batch"` の実在確認**: `skills/auto/SKILL.md` Step 1 の session metadata 書き込みで `.tmp/auto-session-<SESSION_ID>.json` に `"mode": "<batch|single>"` が書かれることを確認済み。`external-kill-investigation.md` に注記する代替判別手段は有効
- **過剰宣言は検出されない**: `scripts/check-allowed-tools.sh` → `validate-skill-syntax.py` のチェックは body → allowed-tools の片方向 (過少宣言のみ検出)。`emit-event.sh:*` エントリを残しても CI は落ちない

### Issue 本文との差分 (本 Spec で確定させた事項)

Issue 本文が記載していた行番号のうち、実ファイルとずれていたもの — `skills/auto/SKILL.md` の該当ブロックは本文記載の L1210-1236 ではなく L1215-1241、`modules/autonomy-tier.md` のマトリクスは L41-48 ではなく L43-47 (除外注記は L48 ではなく L49)。行番号は編集で動くため、Implementation Steps では前後の見出し・文脈で位置を指定している。実装時も行番号ではなく文脈で特定すること。

### verify command に関する注意

- AC 11 のパターンは Issue 起票時 `"loop-paths-used: [A, E]"` だったが、`file_not_contains` が Grep 経由で評価される際 `[A, E]` が文字クラスとして解釈され、変更前でもマッチせず常時 PASS になる欠陥があった (ripgrep で実検証)。メタ文字を含まない `"A, E"` に差し替え済み — 変更前は `[A, E]` にマッチして FAIL、変更後は `[A]` になり PASS で、削除検証として正しく機能する
- AC 4 の `grep "loop-paths-used: \[A\]"` は ERE でのエスケープ済み角括弧 (リテラル一致) であり、BRE メタ文字 (`\|` `\(` `\)` `\+` `\?`) は含まれない。ERE 書き換えは不要
- AC 16 `file_not_contains "docs/guide/customization.md" "seed"` は AC 15 (`next-cycle-seed`) を包含する広いパターンだが、両方を残す。AC 15 は削除対象の設定行を名指しで文書化する役割、AC 16 は散文 2 箇所を含むファイル全体の掃き出しを保証する役割で、意図が異なる
- Pre-merge 検証項目は 26 件で、Spec Simplicity Rules の full 上限 (10 件) を超える。Issue 本文の Acceptance Criteria と verify command を verbatim 同期する規則が優先されるため意図的に維持した。項目数が多いのは削除対象ファイルが 11 個に分散しているためで、1 ファイル 1-2 件の機械的な削除検証に相当する

### SKILL.md 編集時の validator 制約 (`validate-skill-syntax.py`)

- 半角感嘆符を本文 (コードフェンス・インラインコード外) に導入しない
- triple backtick を本文に導入しない
- frontmatter に YAML block scalar (`|` / `>`) を導入しない
- Step 番号は整数のみ (本 Issue の編集対象ブロックには番号付き Step が無いため実質影響なし)

### 翻訳同期の範囲

`docs/translation-workflow.md` の同期義務は top-level `docs/*.md` に限定される。本 Issue では `docs/tech.md` → `docs/ja/tech.md` がこれに該当する。`docs/guide/customization.md` は top-level ではないが JA ミラーが既に存在するため同期対象に含めた。`docs/guide/autonomy.md` は JA ミラーが未作成であり、新規作成は本 Issue のスコープ外とする。

## issue retrospective

`/issue 1214 --non-interactive` 実行時の記録 (Issue コメント 2 件から転記)。

### Triage 結果
- Type: Task (削除・責務移管系のリファクタリングのため)
- Size: L (変更対象 10 ファイル。実質的なロジック変更は `skills/auto/SKILL.md` の 1 ファイルのみで、他は設定・ドキュメントの削除が中心のため、複雑度調整は増減が相殺され L のまま確定)
- Value: 3 (Impact=2 [shared component: modules/ 配下の共有ファイルを変更 +2]、Alignment=4 [product.md Vision「governance-and-verification harness」への高い適合 — 1 か月半動作しなかった死んだ機能の撤去は harness の監査可能性を直接改善]、raw=6)
- 重複候補: なし (#953 `--until` モードは近縁だが別スコープと判断)

### Verify command 監査
既存 AC の verify command に構文上の欠陥 (grep 引数順、常時 PASS/FAIL、checkbox format 等) は検出されなかった。`file_contains "skills/auto/SKILL.md" "Recommend: run /audit drift"` は現状の main でも既に文字列が存在するため単体では常時 PASS だが、これは「advisory 文言がリファクタ中に誤って削除されないことを検証する」意図的な回帰防止用チェックであり、隣接する rubric AC (無条件昇格の意味的検証) とセットで機能するため、欠陥としては扱わなかった。

### 自動解決した曖昧点
1. **`docs/tech.md` / `docs/ja/tech.md` の `#702, #703` フォローアップ言及** — 該当文を丸ごと削除。#702・#703 とも CLOSED 済みで、#703 は本 Issue の撤去対象そのもの。「フォローアップ Issue で追跡中」が事実と矛盾するため。他の選択肢 (Issue 番号を最新化して残す) は追跡すべき follow-up が実在しないため棄却
2. **`modules/autonomy-tier.md` 除外注記の扱い** — 変更不要。D はマトリクス列のみ除外 (経路表には残存)、E は経路表の行ごと削除で状況が異なるため、注記を E に拡張する必要はない

### AC 完全性の補強
- `modules/autonomy-tier.md` の frontmatter 宣言例に対応する verify command を追加
- `modules/detect-config-markers.md` は `NEXT_CYCLE_SEED_ENABLED` チェックだけでは YAML パース規則行を取りこぼすため、`next-cycle-seed` キー全体を対象とする verify command を追加

### 削除系事前スキャン (追記)
先の retrospective 投稿後に実施し忘れに気づき、追って `next-cycle-seed` / `next_cycle_seeded` / `next-cycle.json` / `Seed file emission` / `NEXT_CYCLE_SEED_ENABLED` を repo 全体で grep。当初の Changed Files に無かった `docs/guide/autonomy.md` を検出し追記した。その他のヒット (`docs/spec/issue-{701,703,704,772,854,1014}-*.md`、`docs/sessions/**/events.jsonl`) はすべて歴史的記録として編集対象外と確定。

### その他
- Dependency check: ブロッカーなし
- Stale check: 停滞パターンなし
- Sub-issue splitting: non-interactive モードのため skip

## spec retrospective

### Minor observations

- 削除系事前スキャンのキーワード集合が複合語 (`next-cycle-seed` / `Seed file emission` / `NEXT_CYCLE_SEED_ENABLED` 等) のみで構成されていたため、機能の**素の名詞** (小文字 `seed`) を使った散文言及を 4 箇所取りこぼしていた。`/spec` の追加 grep で `docs/guide/autonomy.md:13,32` と `docs/guide/customization.md:73,147` を検出。削除系スキャンのキーワード集合には、識別子だけでなく機能を指す素の名詞を含めるべき
- Issue 本文が引用していた行番号のうち 2 箇所が実ファイルとずれていた (`skills/auto/SKILL.md` の対象ブロック: 本文 L1210-1236 / 実際 L1215-1241、`modules/autonomy-tier.md` の除外注記: 本文 L48 / 実際 L49)。起票から `/spec` までの間に main が進んだことによるもので、Spec 側は行番号ではなく前後の見出し・文脈で位置指定した
- `skills/auto/SKILL.md` frontmatter の `loop-paths-fallback: [A]` は `validate-skill-syntax.py` の `KNOWN_FIELDS` に含まれておらず、unknown field 警告を出し続けていた。本 Issue の削除でこの警告も解消される (副次的な効果であり Issue の目的ではない)

### Judgment rationale

- **マトリクスの列削除は、同じ行の自由記述セルも読む**。`modules/autonomy-tier.md` の Tier × 経路マトリクスから E 列を消すと、L2 Assisted 行の Default use 文「Seed is automated; cron requires a human to trigger.」が指示対象を失う。この文はどのスキャンキーワードにも一致しない (機能を名前ではなく意味で参照している) ため、grep ベースの影響調査だけでは構造的に検出できない。列・行の削除を伴う変更では、削除対象と同じ表内の自由記述セルを必ず目視すること
- **撤去対象 Issue 番号の連鎖参照**。`modules/autonomy-tier.md` の L0 Layer Table が L2 層の drive mechanism を「Tail extension (#700/702/703)」と説明していた。#703 = 本 Issue の撤去対象そのものであり、撤去後は存在しない実装を実装例として挙げ続けることになる。機能撤去時は「その機能を実装した Issue 番号」も検索キーとして扱う価値がある
- **`loop-paths-fallback` は削除**。経路 E が消えると `loop-paths-used` に残るのは A のみで、A は全 tier で常に許可される (`modules/autonomy-tier.md` 宣言規則) ため fallback が発火する条件が存在しなくなる。同じく `[A]` のみを宣言する `skills/verify/SKILL.md` が fallback 行を持たないことを確認し、既存の慣例に合わせた
- **`allowed-tools` の `emit-event.sh:*` は残す**。本文からの参照はゼロになるが、`validate-skill-syntax.py` のチェックは body → allowed-tools の片方向 (過少宣言のみ検出) で、過剰宣言は CI を落とさない。実装を読んで確認した上で「無害かつ将来の再利用余地あり」として意図的に残す判断とし、Spec の `## Exclusions` に根拠ごと記録した

### Uncertainty resolution

- **`file_not_contains` の角括弧パターンは常時 PASS の罠**。Issue 起票時の AC `file_not_contains "modules/autonomy-tier.md" "loop-paths-used: [A, E]"` は、Grep 経由で評価される際 `[A, E]` が文字クラスとして解釈される。ripgrep で実検証したところ、このパターンは文字列 `loop-paths-used: [A, E]` に**マッチしない** (クラスは 1 文字ぶん、実文字は `[`) ため、変更前でも PASS してしまい削除を検証できない。メタ文字を含まない `"A, E"` に差し替えた。`/issue` の verify command 監査は grep 引数順・常時 PASS/FAIL・checkbox format を見ているが、「`file_contains` 系のパターンに正規表現メタ文字が含まれ、リテラル解釈と正規表現解釈で結果が変わる」クラスは検出対象外だった
- **Issue 本文が `/code` に先送りしていた 2 件を設計時に解消**。(a) `collect-run-facts.sh` / `get-auto-session-report.sh` が未知イベント型を無視するか → 両スクリプトとも `select(.event == "<既知イベント名>")` のホワイトリスト方式であることを確認、過去 20 件の `next_cycle_seeded` は無害。(b) `.tmp/auto-session-*.json` の `"mode": "batch"` が実在するか → `skills/auto/SKILL.md` Step 1 の session metadata 書き込みで確認。どちらも Spec の Notes に検証済みとして記録し、`/code` が再調査しなくて済むようにした
- **`docs/ja/guide/autonomy.md` の未作成は放置でよい**。`docs/guide/autonomy.md` の冒頭に JA へのリンクがあるが実ファイルは存在しない。`docs/translation-workflow.md` の同期義務は top-level `docs/*.md` に限定されており、`docs/guide/` 配下は対象外。本 Issue 以前からの状態であり、翻訳ファイル新規作成はスコープ外とした

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1-10 をすべて Spec の指示どおり (文脈による位置指定、置換文言、削除範囲) に実装した。挿入位置・削除範囲とも Spec の記述と実ファイルの前後見出しが一致しており、行番号のずれ (spec retrospective に記録済み) 以外の追加調整は不要だった。

### Design Gaps/Ambiguities

- N/A — 実装中に新たな設計判断を要する曖昧点は見つからなかった。

### Rework

- N/A

### Minor observations

- `docs/reports/external-kill-investigation.md` への注記は、Spec Notes の文面 (日本語) をそのまま挿入せず、ドキュメント本体の言語 (English) に合わせて英語で追記した。CLAUDE.md の Language Conventions は Spec 自体を日本語対象としているが、既存ドキュメント本体を編集する場合はその文書の言語に従うべきという判断
- behavioral change detection (Step 9) が `skills/auto/SKILL.md` / `modules/autonomy-tier.md` / `.wholework.yml` など複数ファイルで direct-associated test 以外からの参照を検出したため `bats tests/` フルスイート (1480 件) を実行した。全件 PASS

## review retrospective

### Spec vs. implementation divergence patterns

- Nothing to note — Implementation Steps 1-10 と実ファイルの差分が完全に一致しており、Spec の指定範囲を超える巻き添え削除も、指定範囲の削除漏れも検出されなかった (review-spec / review-bug×2 いずれも Perspective 1 で確認)。

### Recurring issues

- 自己レビュー (PR 作成者と `/review` 実行者が同一) では GitHub API が `REQUEST_CHANGES` を許可しないため、MUST 指摘がある場合は `COMMENT` として投稿しゲートマーカーで代替する既存の挙動が今回も発生した (前セッションで `macOS shell compatibility` CI FAILURE を MUST として記録し、修正コミット後に CI green を確認済み)。これは `gh-pr-review.sh` の既知の設計であり、本 Issue 固有の問題ではない。
- 本セッションは `--non-interactive` (fork context) で実行されたため、`capabilities.workflow: true` が設定されていても Workflow tool の re-invocation guarantee が確認できず、`skills/review/workflow-guidance.md` の Pre-flight 判定により静的 Task fan-out (Steps 10.1–10.3) にフォールバックした。これは想定どおりの分岐であり、workflow-guidance.md のガードが正しく機能した事例として記録する。

### Acceptance criteria verification difficulty

- Nothing to note — Pre-merge AC 26 件 (`file_contains`/`file_not_contains`/`grep`/`rubric`/`github_check` の組み合わせ) はすべて一意に PASS/FAIL を判定でき、UNCERTAIN は 0 件だった。rubric 系 3 件 (AC 3, 12, 24) も、Issue 本文の記述が具体的だったため意味的検証の曖昧さは生じなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- Pre-merge AC ゲート (`check-pre-merge-ac.sh`) は `unchecked_count=0`、review-incomplete-fallback チェックも `matches_expected=true` (organic Step 14 完了) だったため、override マーカーなしでそのままマージ可と判断した
- `gh-pr-merge-status.sh` の結果は `mergeable=true reason=clean ci_status=success review_status=approved` だったため、conflict 解消フローや CI 待機は不要だった
- 非対話モード (`--non-interactive`) だが、ゲート条件がすべてクリアだったため auto-resolve 分岐(Non-Interactive Mode Behavior)を使う必要はなかった

### Deferred Items

- Post-merge の observation AC (`event=auto-run session=next`) は次回 `/auto --batch` 完走時の観察待ち。`.tmp/next-cycle.json` が生成されないこと・`next_cycle_seeded` が emit されないこと・`/audit drift` 推奨が出ることの 3 点を確認する
- CONSIDER 指摘 (`modules/autonomy-tier.md` の `loop-paths-fallback` ドキュメントと `validate-skill-syntax.py` の `KNOWN_FIELDS` 不一致、`docs/guide/customization.md` の Breaking Changes 未記録、`scripts/emit-event.sh` の retired event 未記録、`docs/reports/external-kill-investigation.md` の代替判別手段の拡充) は本 PR では対応せず、必要であれば別 Issue で扱う
- `.tmp/auto-events.jsonl` に残る過去 20 件の `next_cycle_seeded` は削除しない (読み取り側は未知イベント型を無視するため無害)
- `docs/ja/guide/customization.md` の翻訳ドリフト (EN 側の `.wholework.yml` autonomy サンプルブロックと `autonomy` 設定行が JA ミラーに存在しない) は本 Issue 以前からの既知状態。本 Issue では解消しない

### Notes for Next Phase

- `/verify` は Post-merge observation AC (`event=auto-run session=next`) の確認が主タスク。次回 `/auto --batch` 完走を待つ必要があり、即時確認はできない点に注意
- Issue #1214 の base branch は `main` なので `closes #1214` により自動クローズされる見込み。Step 6 のフォールバック確認で state を再検証すること
