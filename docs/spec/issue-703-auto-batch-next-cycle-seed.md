# Issue #703: auto: --batch tail での next-cycle 候補 Issue emit

## Overview

`/auto --batch` 完了時の tail に軽量スキャンステップを追加し、バッチセッション中に生成された `audit/*` ラベル付き Issue を候補として `.tmp/next-cycle.json` に書き出す。次セッションでユーザー (または `/auto --batch --resume`) が候補リストを拾える状態にする。

L2→L1 経路 E (Seed file emission) の最初の実装。autonomy tier が L1 の場合は経路 A (advisory print) に格下げする。`skills/auto/SKILL.md` frontmatter に `loop-paths-used: [A, E]` を宣言する。

## Consumed Comments

No new comments since last phase.

## Changed Files

- `modules/detect-config-markers.md`: add `next-cycle-seed.enabled` → `NEXT_CYCLE_SEED_ENABLED` table row; add YAML parsing rule (block/flat key両対応); add output variable entry
- `scripts/emit-event.sh`: add `next_cycle_seeded` event schema documentation (comment only; 関数実装は変更なし)
- `skills/auto/SKILL.md`: (a) frontmatter に `loop-paths-used: [A, E]` + `loop-paths-fallback: [A]` を追加; (b) `### Batch Completion Report` 末尾 (Daily rollup の直後、L3 auto-retrospective の直前) に "Next-cycle seed" ステップを追加 — bash 3.2+ compatible
- `docs/guide/customization.md`: add `next-cycle-seed.enabled` row to configuration reference table

## Implementation Steps

1. `modules/detect-config-markers.md` 更新 — Marker Definition Table に `next-cycle-seed.enabled` → `NEXT_CYCLE_SEED_ENABLED` 行を追加 (after `recoveries-auto-fire.threshold`); YAML Parsing Rules に `next-cycle-seed.*` ネストキー説明を追加; Output Format に `NEXT_CYCLE_SEED_ENABLED` 行を追加 (→ AC3)

2. `scripts/emit-event.sh` 更新 — 既存イベントスキーマコメントブロックの末尾 (recoveries_threshold_fire の直後) に `next_cycle_seeded` スキーマを追記:
   ```
   # next_cycle_seeded: batch 完了 tail が次サイクル候補を emit した
   #   candidate_count=<n>
   #   source_breakdown=<flat: "audit/drift:N1,audit/fragility:N2">
   #   batch_session_id=<session_id>
   ```
   (→ AC2)

3. `skills/auto/SKILL.md` 更新:
   - (a) frontmatter に `loop-paths-used: [A, E]` と `loop-paths-fallback: [A]` を追加 (immediately after `description:` line)
   - (b) `### Batch Completion Report` 内の `**Daily rollup...**` ブロックの直後 (L3 auto-retrospective の直前) に `**Next-cycle seed (batch, best-effort):**` ブロックを追加。内容:
     1. Load `AUTONOMY_TIER` and `NEXT_CYCLE_SEED_ENABLED` from `.wholework.yml`
     2. Tier check: `AUTONOMY_TIER=L1` または `NEXT_CYCLE_SEED_ENABLED=false` の場合 → path A のみ (advisory print `Recommend: run /audit drift to identify next-cycle candidates`); それ以外は path E へ
     3. Read `session_start` from `.tmp/auto-session-${AUTO_SESSION_ID}.json` via jq. 取得失敗時は warning を出し skip
     4. `gh issue list --label "audit/drift"` と `--label "audit/fragility"` を別々に実行し `--json number,createdAt,state` を取得。jq で `createdAt > session_start` かつ `state == "OPEN"` でフィルタし、source ラベルとともに candidates 配列を構築
     5. 各 candidate の `size_hint` を `get-issue-size.sh $NUMBER` で取得 (best-effort; 失敗時は omit)
     6. Write `.tmp/next-cycle.json` using Write tool with schema `{schema_version, seeded_at, seeded_by_session, candidates}`
     7. Append row `| HH:MM:SS | batch | next-cycle-seed | candidates:N |` to `docs/reports/loop-state-{DATE}.md` (best-effort; create file with frontmatter + table header if not exists)
     8. Emit `next_cycle_seeded` event via `emit-event.sh` (→ AC1)

4. `docs/guide/customization.md` 更新 — 既存の `recoveries-auto-fire.enabled` 行の直後に以下の行を追加:
   `| next-cycle-seed.enabled | boolean | false | Enable next-cycle candidate seeding after batch completion. Emits .tmp/next-cycle.json with audit/* Issues created during the batch session (requires autonomy: L2 or L3). When false or autonomy is L1, prints a recommendation instead. |`

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/auto/SKILL.md" "next-cycle.json" --> `/auto` SKILL.md にバッチ完了 tail での `next-cycle.json` emit ステップが記述されている
- <!-- verify: file_contains "scripts/emit-event.sh" "next_cycle_seeded" --> `next_cycle_seeded` イベント型が `emit-event.sh` に追加されている
- <!-- verify: grep "next-cycle-seed" "modules/detect-config-markers.md" --> `.wholework.yml` フラグが marker テーブルに登録されている

### Post-merge

- `.wholework.yml: next-cycle-seed.enabled: true` の状態で `/auto --batch N1 N2` を完走させ、`.tmp/next-cycle.json` が生成され、`docs/reports/loop-state-*.md` に `next-cycle-seed` 行が追記されることを観察

## Notes

- **blocked by #704**: `autonomy-tier.md` の tier × path matrix は既に E path を L2/L3 で ○ と定義済み (line 43-44 で確認)。#704 は tier gating の enforcement 実装であり、本 Issue 実装後に #704 が gating ロジックを追加する想定
- **batch start time の取得**: `session_start` は Step 1 で生成される `.tmp/auto-session-${AUTO_SESSION_ID}.json` から jq で読む。resume モード (`--batch --resume`) では新しい `AUTO_SESSION_ID` が生成されるため、resume 開始後に作られた Issue のみが候補になる (安全側)
- **`--resume` と next-cycle.json の読み込み**: Issue body の通り、non-interactive mode では `.tmp/next-cycle.json` を読まず通常 resume を継続 (present Issue scope 外; 将来の `/auto --batch --resume` の拡張で対応)
- **gh issue list の OR フィルタ**: `--label` は AND 結合なので `audit/drift` と `audit/fragility` を別クエリで取得し結合する
- **loop-state-{DATE}.md の append 形式**: 既存の heartbeat 行 (`| ts | #N | from→to | snapshot |`) と同じテーブルに特殊行として追記。`issue` カラムは `batch`、`transition` カラムは `next-cycle-seed`、`snapshot` カラムは `candidates:N`
- **auto-resolve**: 曖昧ポイントなし (SPEC_DEPTH=light、自動解決不要)

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST/SHOULD 指摘なし。CONSIDER 2件 (変数名不一致、暗黙変数定義) は Spec retrospective に記録のみ、修正は行わない。
- Forbidden Expressions CI 失敗は `docs/spec/issue-710-blocked-by-workflow.md` の pre-existing 違反であることを確認し、本 PR 起因ではないと判断。
- `REVIEW_DEPTH=light` で全 4 観点を軽量カバー。外部レビューツール設定なしのため Step 7 はスキップ。

### Deferred Items
- CONSIDER 指摘 2件 (session_start/SESSION_START 不一致、暗黙変数定義) は改善提案として本 retrospective に記録。別 Issue での対応推奨。
- Forbidden Expressions CI 違反 (`docs/spec/issue-710-blocked-by-workflow.md`) は本 PR 範囲外のため別途対応が必要。

### Notes for Next Phase
- MUST/SHOULD 指摘なし。`/merge 720` で即時マージ可能。
- post-merge AC (observation 型) は `next-cycle-seed.enabled: true` の実運用環境での観察が必要。

## Code Retrospective

### Deviations from Design

- `emit-event.sh` を `skills/auto/SKILL.md` の `allowed-tools` に追加した。Spec の実装ステップには明示されていなかったが、`validate-skill-syntax.py` が body 参照スクリプトと allowed-tools の不一致を検出したため追加が必要だった。

### Design Gaps/Ambiguities

- `validate-skill-syntax.py` が `loop-paths-fallback` フィールドを unknown field として warning を出す。これは新規フィールドであり、バリデーターのスキーマが未更新なため。エラーではなく warning 止まりなので CI はパスするが、将来 `loop-paths-fallback` をスキーマに追加する改善余地がある。

### Rework

- `emit-event.sh` の allowed-tools 追加を最初のコミット後に発見し、別コミットで修正した。実装→バリデーション実行→不一致発見→修正のフローで 1 コミット余分になった。

## review retrospective

### 観点 1: Spec vs 実装の乖離パターン

- Spec と PR diff の一致度は高く、構造的乖離なし。SKILL.md の LLM-executed skill という性質上、bash スニペット内の変数名 (`$SESSION_START`) とステップ説明文の変数名 (`session_start`) の不一致が生じた。LLM-executed skill では変数名の大文字小文字を Spec レベルで統一しておく価値がある改善余地。

### 観点 2: 繰り返し指摘

- 今回は同種指摘の繰り返しなし。CONSIDER 2件は異なる種別 (変数命名、暗黙変数定義)。LLM-executed skill の文書記述で暗黙の変数定義を残しがちなパターンは過去 PR でも見られており、将来の skill 執筆時に意識すべき共通パターン。

### 観点 3: 承認条件検証の難度

- Pre-merge AC 3件はすべて `file_contains`/`grep` で PASS が確認でき、検証コマンドの精度は十分だった。
- Post-merge AC は `verify-type: observation` (実際のバッチ完走が必要) であり、自動検証不可。これは観察型 AC の適切な使い分けとして問題なし。
- Nothing to note 以外: UNCERTAIN が 0件であり、verify command の品質は高い。
