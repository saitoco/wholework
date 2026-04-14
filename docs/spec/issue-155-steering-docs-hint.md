# Issue #155: feat: skill 完了時に steering docs 導入を促す動的ヒント

## Overview

Steering Documents 未整備のまま wholework 経由で一定数（5 件以上）の Issue を完了したプロジェクトに対し、
`/doc init` の導入を促す 1 行ヒントを skill 完了レポート末尾に動的表示する機能を実装する。

ヒントは opt-out 方式（`.wholework.yml` の `steering-hint: false` で抑制可能）で、
`next-action-guide` 出力後に 1 行追加するパターンを採用。表示対象 skill: `/issue`, `/spec`, `/review`, `/audit`。

発動条件（AND）:
1. `steering-hint` が `false` でない（デフォルト: true）
2. Steering docs 不在（`STEERING_DOCS_PATH/*.md` に `type: steering` frontmatter を持つファイルが存在しない）
3. `phase/done` ラベル付き closed issue 数 >= 5

## Changed Files

- `modules/steering-hint.md`: new file（ヒント判定ロジック共有モジュール）
- `modules/detect-config-markers.md`: Marker Definition Table に `steering-hint` 行追加、Output Format に `HAS_STEERING_HINT` 追加
- `skills/issue/SKILL.md`: Completion Report の next-action-guide 呼び出し直後に steering-hint モジュール read 追加
- `skills/spec/SKILL.md`: Step 19 Completion Message の next-action-guide 呼び出し直後に steering-hint モジュール read 追加
- `skills/review/SKILL.md`: Completion Report の next-action-guide 呼び出し直後に steering-hint モジュール read 追加
- `skills/audit/SKILL.md`: drift/stats/fragility/integrated 各サブコマンドの最終ステップ末尾に steering-hint モジュール read 追加
- `docs/structure.md`: Key Files modules リストに `modules/steering-hint.md` エントリ追加、modules ファイル数を 25 → 27 に更新

## Implementation Steps

1. **`modules/steering-hint.md` を作成する**（→ AC: file_exists, phase/done）

   4-section 構造（Purpose / Input / Processing Steps / Output）で新規作成。
   Processing Steps:
   1. `.wholework.yml` を Read し、`steering-hint: false` なら skip（出力なし）
   2. `STEERING_DOCS_PATH`（利用可能なら使用、そうでなければ `docs`）配下の `*.md` を Glob し、
      frontmatter に `type: steering` を含むファイルが 1 件以上あれば skip（steering docs 存在）
   3. `gh issue list --state closed --label "phase/done" --json number | jq length` を実行し、
      結果 < 5 なら skip（閾値未達）
   4. 1 行メッセージを出力:
      "`/doc init` を実行すると今後の skill の精度が上がる可能性があります"

2. **`modules/detect-config-markers.md` に `steering-hint` キーを追加する**（→ AC: detect-config-markers に steering-hint）

   Marker Definition Table に以下の行を追加（`skill-proposals` 行の後）:
   | `steering-hint` | `HAS_STEERING_HINT` | `true` | `true` (default true, false when `steering-hint: false`) |

   Output Format セクションに追加:
   ```
   HAS_STEERING_HINT: false if steering-hint: false is set (default: true)
   ```

3. **`/issue`, `/spec`, `/review` SKILL.md の完了セクションに steering-hint 呼び出しを追加する**（→ AC: issue/spec/review SKILL.md に steering-hint）

   各 SKILL.md の `next-action-guide` 呼び出しブロック末尾（`---` の直前）に以下を追加:
   ```
   Then read `${CLAUDE_PLUGIN_ROOT}/modules/steering-hint.md` and follow the "Processing Steps" section.
   ```
   - `skills/issue/SKILL.md`: Completion Report セクション、`RESULT={success|blocked}` 行の後
   - `skills/spec/SKILL.md`: Step 19、`BLOCKED_BY_OPEN=$HAS_OPEN_BLOCKING` 行の後
   - `skills/review/SKILL.md`: Completion Report セクション、`RESULT=success` 行の後

4. **`/audit` SKILL.md の各サブコマンド最終ステップ末尾に steering-hint 呼び出しを追加する**（→ AC: audit SKILL.md に steering-hint）

   各サブコマンドの最終ステップ末尾（`---` の直前、または末尾）に以下を追加:
   ```
   Then read `${CLAUDE_PLUGIN_ROOT}/modules/steering-hint.md` and follow the "Processing Steps" section.
   ```
   追加箇所:
   - `drift` サブコマンド: Step 5（Issue Generation）末尾
   - `stats` サブコマンド: Step 4（Save）末尾
   - `fragility` サブコマンド: Step 5（Issue Generation）末尾
   - `Integrated Execution` セクション: Step 4（Issue Generation）末尾

5. **`docs/structure.md` の Key Files modules リストを更新する**（→ doc sync）

   Directory Layout の `modules/` コメントを `25 files` → `27 files` に変更。
   Key Files > Modules セクションの末尾（`modules/phase-banner.md` 行の後）に追加:
   ```
   - `modules/steering-hint.md` — dynamic hint recommending `/doc init` when steering docs are absent
   ```

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/steering-hint.md" --> `modules/steering-hint.md` が作成されている
- <!-- verify: file_contains "modules/steering-hint.md" "phase/done" --> `modules/steering-hint.md` のカウントロジックが `phase/done` ラベルでフィルタしている
- <!-- verify: file_contains "modules/detect-config-markers.md" "steering-hint" --> `detect-config-markers.md` に `steering-hint` キーが追加されている
- <!-- verify: file_contains "skills/issue/SKILL.md" "steering-hint" --> `/issue` skill からヒントモジュールが参照されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "steering-hint" --> `/spec` skill からヒントモジュールが参照されている
- <!-- verify: file_contains "skills/review/SKILL.md" "steering-hint" --> `/review` skill からヒントモジュールが参照されている
- <!-- verify: file_contains "skills/audit/SKILL.md" "steering-hint" --> `/audit` skill からヒントモジュールが参照されている

### Post-merge

- steering docs 不在 + `phase/done` ラベル付き closed issue 5 件以上のプロジェクトで `/issue` を実行した際、完了レポート末尾に `/doc init` を推奨する 1 行ヒントが表示される <!-- verify-type: opportunistic -->
- `.wholework.yml` に `steering-hint: false` を設定するとヒントが抑制される <!-- verify-type: opportunistic -->
- steering docs が存在するプロジェクトではヒントが表示されない <!-- verify-type: opportunistic -->

## Notes

- **`docs/guide/` 更新は本 Issue スコープ外**: `docs/guide/customization.md` と `docs/guide/quick-start.md` は #154 で新規作成予定。#154 完了後に steering-hint フラグ説明と役割分担の記述を追記するフォローアップが必要。

- **`/audit` drift/fragility/integrated での到達不能**: drift/fragility/integrated サブコマンドは steering docs 不在時に早期終了（"Steering Documents not found. Run `/doc init`."）するため、steering-hint の発動条件（steering docs 不在）と矛盾し、実際にはヒントが到達不能。`stats` サブコマンドのみ実質的に機能する。構造的には全サブコマンドに追加して問題ない（モジュール内条件チェックで skip されるだけ）。

- **Auto-Resolved Ambiguity（`/issue` 時）**: ヒント出力位置は `next-action-guide` 出力後に 1 行追加（既存 opportunistic-verify パターンと整合）。

- **`steering-hint` デフォルト true**: `detect-config-markers.md` の既存キーと異なり、`steering-hint` はデフォルト `true`（有効）。`false` 設定で抑制。Marker Definition Table の値説明はこの逆転に注意。

- **モジュール自己完結設計**: `steering-hint.md` はモジュール内で `.wholework.yml` を直接 Read する（呼び出し元での事前チェック不要）。detect-config-markers.md への追加は設定スキーマの公式認識のため。
