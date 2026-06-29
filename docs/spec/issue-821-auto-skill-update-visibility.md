# Issue #821: auto: session 中の skill self-update propagation を可視化

## Overview

`/auto --batch` や `/auto XL` の長時間セッション中に、別の PR が skill ファイルを更新した場合、セッション開始時にロードした古い prompt が継続して使用される。現行は「想定動作とのズレ」が発生しても可視化されないため、session 終了後に原因分析が困難になる。

本 Issue では:
1. **セッション開始時** に `.tmp/auto-session-${SESSION_ID}.json` へ主要 8 skill の commit hash を記録
2. **L3 retrospective 時 (batch/XL route のみ)** にセッション開始時の hash と最新 main の hash を比較し、差分があれば `session.md` に `## Skill Self-Update Propagation Note` セクションを追加

## Changed Files

- `skills/auto/SKILL.md`:
  - Step 1: session JSON schema に `skill_versions` フィールド追加 + 8 skill の commit hash 収集ロジック追加
  - L3 auto-retrospective (batch/XL route のみ): Backlink (step 6) とコミット (step 7) の間に skill diff check サブステップを追加し、diff があれば `session.md` に注記セクションを後付け書き込み

## Implementation Steps

1. **Step 1 modification: session JSON に skill_versions を追加** (→ AC1, AC3)

   `skills/auto/SKILL.md` の "Write `.tmp/auto-session-${SESSION_ID}.json`" サブステップを以下のように変更する:

   - JSON 書き込みの直前に 8 skill (auto/code/spec/verify/review/merge/issue/audit) の commit hash を `git log -1 --format=%H -- skills/<skill>/SKILL.md` で収集するステップを追記する (ハッシュ取得失敗時は空文字列を記録; bash 3.2+ 互換)
   - `.tmp/auto-session-${SESSION_ID}.json` の JSON スキーマに `skill_versions` フィールドを追加する (ファイルパス → commit hash の map):

   ```json
   {
     "session_id": "<SESSION_ID>",
     "session_start": "<current UTC timestamp in ISO8601>",
     "skill_versions": {
       "skills/auto/SKILL.md": "<commit-hash>",
       "skills/code/SKILL.md": "<commit-hash>",
       "skills/spec/SKILL.md": "<commit-hash>",
       "skills/verify/SKILL.md": "<commit-hash>",
       "skills/review/SKILL.md": "<commit-hash>",
       "skills/merge/SKILL.md": "<commit-hash>",
       "skills/issue/SKILL.md": "<commit-hash>",
       "skills/audit/SKILL.md": "<commit-hash>"
     }
   }
   ```

2. **L3 sub-step: skill diff check の追加** (→ AC2)

   `skills/auto/SKILL.md` の L3 auto-retrospective セクション内で、Backlink step (step 6) とコミット step (step 7) の間に独立サブステップを追加する:

   - `.tmp/auto-session-${AUTO_SESSION_ID}.json` から `skill_versions` を `jq` で読み込む (ファイル不在または jq 失敗時はサブステップをスキップ)
   - 8 skill それぞれについて `git log -1 --format=%H -- skills/<skill>/SKILL.md` で現在の hash を取得し、保存値と比較する
   - 差分がある skill が 1 つ以上あれば、`$SESSION_DIR/session.md` に `## Skill Self-Update Propagation Note` セクションを末尾追記する。形式例:
     ```markdown
     ## Skill Self-Update Propagation Note

     Session 中に以下の skill が更新されました (本 session には未適用、次 session から反映):
     - skills/auto/SKILL.md: <start-hash> → <current-hash>
     - skills/code/SKILL.md: (no change)
     ```
   - 差分がない場合はサブステップをスキップ (section 追記なし)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md Step 1 の session metadata 書き込みで、主要 skill (auto / code / spec / verify / review / merge / issue / audit) の commit hash を git log で取得して JSON に記録する手順が記述されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "### Step 1" "skill_versions" --> Step 1 の session JSON schema に skill_versions フィールドが追加されている
- <!-- verify: rubric "skills/auto/SKILL.md L3 step で、.tmp/auto-session-${SESSION_ID}.json の skill_versions と現在の git log の skill commit hash を比較し、diff があれば session.md に注記セクションを追加する手順が記述されている" --> <!-- verify: grep "Skill Self-Update Propagation Note" "skills/auto/SKILL.md" --> L3 step に session.md への注記セクション追加ロジックが記述されている
- <!-- verify: rubric "skills/auto/SKILL.md の Checkpoint Design セクション (もしくは関連 schema 文書) に skill_versions フィールド (主要 skill のファイルパス → commit hash の map) が定義されている" --> <!-- verify: grep "skill_versions" "skills/auto/SKILL.md" --> skill_versions フィールドがファイル内に定義されている

### Post-merge

- 次回 `/auto --batch` 完走時の session.md に skill versions または "Skill Self-Update Propagation Note" セクションが含まれることを観察 <!-- verify-type: observation event=auto-run -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: 3 auto-resolved ambiguity points + AC update notes / https://github.com/saitoco/wholework/issues/821#issuecomment-4828328044

## Notes

### Auto-Resolved Ambiguity Points

1. **`skill_versions` schema の文書化場所**: Step 1 の session JSON schema 定義箇所に追記する方式を採用。`## Checkpoint Design` セクションのスコープは checkpoint files (`.tmp/auto-state-*.json`, `.tmp/auto-batch-state-*.json`) であり、session metadata (`.tmp/auto-session-${SESSION_ID}.json`) の schema は Step 1 インラインが既存の SSoT。AC3 rubric の "(もしくは関連 schema 文書)" 句でカバーされる。

2. **"主要 skill" の定義範囲**: 8 skills (auto/code/spec/verify/review/merge/issue/audit) を採用。`triage` は inline invocation で skill ファイル変更が minimal, `doc` は batch session で通常実行されない。

3. **skill diff 比較の L3 サブステップ位置**: Backlink (step 6) とコミット (step 7) の間に独立サブステップとして追加。session.md のすべての本体コンテンツ (retro-proposals, backlink) 書き込み完了後に注記を末尾追記する形が実装上最も自然で、既存 L3 フローへの影響を最小化する。

## Consumed Comments (code phase)

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- Step 1 の旧 step 3 (Set AUTO_SESSION_ID) を step 4 に繰り下げ: 新たに追加した hash 収集 (step 2) と JSON 書き込み (step 3) の挿入により既存の step 番号をシフトした。Spec には「JSON 書き込みの直前に追記」と記載されており、番号シフトは Spec の意図に沿った自然な結果。

### Design Gaps/Ambiguities
- L3 skill diff check の `CHANGED_SKILLS` 変数はローカル変数として bash ループ内で累積しているが、bash でのスペース区切り連結パターンは可読性が低い。実装上は機能するが、jq を使った配列構築の方が安全。今回は最小変更方針を維持し、既存の bash スタイルに合わせた。

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Step 1 に skill hash 収集 (bash 3.2+ 互換、failure-safe) → JSON schema 拡張という 2-sub-step 構成を採用。既存の step 1/2/3 番号体系を 1/2/3/4 に変更してシフトした。
- L3 step 7 (新) を Backlink (step 6) とコミット (旧 step 7 → 新 step 8) の間に挿入。既存 L3 フローへの影響を最小化するため session.md の全コンテンツ書き込み完了後に追記する設計とした。
- `CHANGED_SKILLS` 変数によるループ集積ではなく、8 skill 全件をリスト形式で `session.md` に出力する形式 (changed → hash、unchanged → "(no change)") を採用。

### Deferred Items
- L3 diff check の bash スタイル連結 (スペース区切り) は jq 配列構築に将来改善できるが、今回は最小変更を優先。
- Smoke Test なし (Spec に `## Smoke Test` セクション不在)。次回 `/auto --batch` 実行による観察が事実上の統合テスト。

### Notes for Next Phase
- `/verify` では AC1-3 の mechanical verify が全 PASS したことを確認済み (section_contains + grep)。rubric verify は /verify フェーズで正式実行予定。
- Post-merge AC (observation event=auto-run) は次回 `/auto --batch` 完走後に確認する。

## Auto Retrospective
### Orchestration Anomalies
- **[code-patch-silent-no-op]** Tier 2 fallback applied: phase=`code-patch`, action=run-code.sh-patch-retry, result=recovered.

### Improvement Proposals
- N/A (resolved by Tier 2 fallback catalog)
