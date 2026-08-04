# Issue #1159: retro-proposals: 三層判定のデフォルトと記録欠如を見直し improvement proposal の起票レートを抑制

## Overview

`modules/retro-proposals.md` の Tier 分類 (#484 導入) が実効的に機能していない問題を、生成側の 3 点で手当てする。

1. **デフォルトの反転**: 「判断に迷ったら Tier 1 (起票)」を「判断に迷ったら Tier 2 (memory 提案のみ)」へ変更する
2. **Tier 1 基準の positive-evidence gate 化**: 「複数 skill/module OR 再発性 OR 影響範囲」の緩い OR 判定を、3 つの実証可能シグナルのいずれかを積極的に示せる場合のみ Tier 1 とする形へ引き締める
3. **判定結果の永続化と集計**: 提案 1 件ごとに `retro_proposal_classified` イベントを `.tmp/auto-events.jsonl` へ emit し、`scripts/get-auto-session-report.sh` の `## Metrics` に Tier 内訳と filter hit rate を出す

方針候補 A / B / D (軽量版) を採用し、C は不採用。採否の根拠は Issue body `## 採用方針 (/spec で確定)` と本 Spec の `## Notes` に記録済み。

## Consumed Comments

No new comments since last phase. (cutoff: `phase/*` ラベル最終付与時刻 `2026-08-04T20:51:26Z`、`type=verify-fail` / `type=preview-ac-unverified` マーカーも該当なし)

## Changed Files

- `modules/retro-proposals.md`: Step 6 の Tier 1 行を positive-evidence gate へ書き換え、Mechanical heuristics を「キーワード単独では Tier 1 を選ばない」形へ引き締め、`**Default**` を Tier 2 へ反転して根拠ブロックを追加、`**Tier classification persistence**` サブ節を追加。冒頭 `Called by:` の step 番号 (`/verify` Step 13 → Step 16、`/auto` Step 4a → Step 5 L3 auto-retrospective) と `## Output` 節を更新
- `scripts/emit-event.sh`: ヘッダーの documented event schema ブロックに `retro_proposal_classified` を追記 — bash 3.2+ 互換 (コメント追記のみ、実行ロジック変更なし)
- `modules/event-emission.md`: `## Non-Wrapper Emitters` 節に `retro_proposal_classified` の emitter と numeric `EMIT_ISSUE_NUMBER` ガードを追記
- `scripts/get-auto-session-report.sh`: `RETRO_TIER_COUNTS` / `RETRO_TIER_BREAKDOWN` を jq で算出し、Summary テーブルに 1 行と `### Retro Proposal Tier Breakdown` サブ節 (h3) を追加 — bash 3.2+ 互換
- `skills/audit/SKILL.md`: `auto-session` Subcommand の `### Output Template Structure` 番号付きリストに項目 9 を追加
- `docs/structure.md`: `modules/retro-proposals.md` の Key Files 行を更新 (step 番号の訂正 + Tier 判定イベント emit の明記) [Steering Docs sync candidate]
- `docs/ja/structure.md`: 上記の日本語ミラーを同内容で更新 (日本語表記のまま、`docs/translation-workflow.md` の sync 手順に従う)
- `tests/get-auto-session-report.bats`: Tier breakdown の表示テストと、イベント不在時の graceful degrade テストを追加
- `tests/retro-proposals.bats`: デフォルト Tier と Tier 1 evidence gate の判定関数テストを追加 (既存ファイルの「module の規則を bash ヘルパーで写す」方式に合わせる)

**変更不要と確認済み (grep 実施)**:

- `scripts/get-config-value.sh` / `.wholework.yml`: 新規設定キーを追加しないため変更なし (`grep -n "retro" .wholework.yml` → 0 hit)
- `skills/verify/SKILL.md` / `skills/auto/SKILL.md` の `allowed-tools`: 両者とも `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` を既に含む (frontmatter を直接確認済み)。新規 `scripts/*.sh` の追加もないため allowed-tools impact chain check は該当なし
- `docs/workflow.md` / `docs/ja/workflow.md`: `retro-proposals.md` を「Step 11 で `set-blocked-by.sh` を呼ぶ」と参照している (line 302 / 295)。本変更は Step 6 内へのサブ節追加のみで Step 7–11 を繰り下げないため、参照は有効なまま
- `tests/audit-auto-session.bats`: 同じ `get-auto-session-report.sh` を対象とするが、既存 7 テストは特定の Summary 行と節見出しを grep しており、行の追加では壊れない (`grep -n "@test" tests/audit-auto-session.bats` で確認)
- `scripts/setup-labels.sh`: ラベルの追加・変更・削除なし

## Implementation Steps

**acceptance criteria 4 について**: 不採用方針 (C) の判断根拠は本 Spec の `## Notes` と Issue body の `## 採用方針 (/spec で確定)` に spec フェーズ時点で記録済みのため、code フェーズの実装ステップは不要。

1. `modules/retro-proposals.md` Step 6 の Tier 分類テーブルの **Tier 1** 行を positive-evidence gate へ書き換える (→ acceptance criteria 1)
   - 判定基準を「次の 3 シグナル **(exhaustive)** のいずれかを積極的に実証できる場合のみ Tier 1」に変更する:
     - (a) **複数ファイル波及**: 提案が `skills/` / `modules/` / `agents/` / `scripts/` 配下の 2 ファイル以上を変更対象として名指ししている
     - (b) **再発性の実証**: 同種の提案が 2 つ以上の異なる Spec retrospective に既出、または提案自身が 2 件以上の先行 Issue 番号を根拠として挙げている。機械的確認手順として `grep -rl "{keyword}" $SPEC_PATH/ | wc -l` が 2 以上であることを添える
     - (c) **SSoT / 共有面への波及**: frontmatter に `ssot_for:` を宣言したファイル、または 2 つ以上の skill が Read する共有 module を変更対象としている
   - 3 シグナルのいずれも積極的に実証できない場合は Tier 1 としない旨を明記する
   - 既存の verify command (`grep "再発性" "modules/retro-proposals.md"`, #484 由来) が壊れないよう、(b) の見出しに `再発性` の語を残す
2. 同 Step 6 の **Mechanical heuristics** を引き締める (after 1) (→ acceptance criteria 1)
   - 「キーワードの存在だけでは Tier 1 を選ばない。キーワードは step 1 の (a)/(b)/(c) 実証チェックを起動する合図に過ぎない」を明記する
3. 同 Step 6 の `**Default**` 行を反転し、根拠ブロックを追加する (after 1, 2) (→ acceptance criteria 1)
   - 新しい本文: `**Default**: When classification is difficult, assign **Tier 2** (memory proposal only) rather than Tier 1.`
   - 直後に根拠を段落で追加する: #484 の保守的デフォルトを反転する理由 (backlog の 84% が `retro/verify` に到達し、Tier 2/3 判定が実測ゼロ件だったこと)、および反転が安全である理由 (提案テキストは Spec retrospective に残り、判定結果自体も step 4 の永続化により後から監査できる)
   - **制約**: 旧デフォルト文 `assign Tier 1 (conservative setting to avoid false negatives)` を根拠ブロック内で逐語引用しない (AC1 の `file_not_contains "modules/retro-proposals.md" "assign Tier 1 (conservative"` が偽陰性になるため)。言い換えで説明する
4. 同 Step 6 に `**Tier classification persistence**` サブ節を追加する (after 3) (→ acceptance criteria 2)
   - Tier 分類が全提案について確定した直後に実行する手順として記述する
   - 提案 1 件につき 1 回、次を実行する:
     - `source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"` → `restore_auto_session_pointer` → `EMIT_ISSUE_NUMBER=<numeric> emit_event "retro_proposal_classified" "tier=<1|2|3>" "title=<提案タイトル (先頭 80 文字まで)>" "reason=<判定根拠 1 行>" "action=<issue_created|memory_proposal|spec_only>"`
   - **numeric ガード (必須)**: `NUMBER` が裸の整数でない場合 (`/auto` L3 経路の `BRIDGE_NUMBER="batch-<session-id>"` など) は `EMIT_ISSUE_NUMBER=0` を渡す。`emit_event()` は `"issue":${_issue}` を引用符なしで出力するため、非数値を渡すと不正な JSON 行が混入し、`get-auto-session-report.sh` の `jq -s` がログ全体の読み取りに失敗する
   - `AUTO_EVENTS_LOG` が未設定のまま `restore_auto_session_pointer` でも復元できない場合 (`/auto` 外の単独 `/verify` 実行) は emit をスキップする旨を明記する。既存の非 wrapper emitter と同じ方針
   - Tier に関わらず、全提案について terminal に 1 行のサマリを出力する: `Tier classification: {n1} Tier 1 / {n2} Tier 2 / {n3} Tier 3 (filter hit rate {p}%)`。`p` は `(n2 + n3) / (n1 + n2 + n3) * 100` を切り捨てた整数、総数 0 のときは `0`
5. `modules/retro-proposals.md` 冒頭の `Called by:` リストと `## Output` 節を更新する (after 4) (→ acceptance criteria 2)
   - `Called by:` を `/verify` Step 16 / `/auto` Step 5 L3 auto-retrospective に訂正する
   - `## Output` に「`retro_proposal_classified` イベント (`AUTO_EVENTS_LOG` 設定時)」と terminal サマリ行を追記する
6. `scripts/emit-event.sh` のヘッダー documented event schema ブロックに `retro_proposal_classified` を追記する (parallel with 1-5) (→ acceptance criteria 2)
   - `recoveries_threshold_fire` エントリの記法に合わせ、`tier` / `title` / `reason` / `action` の 4 フィールドと numeric `EMIT_ISSUE_NUMBER` ガードを 1 エントリとして記述する
7. `modules/event-emission.md` の `## Non-Wrapper Emitters` 節に `retro_proposal_classified` の段落を追加する (after 4, 6) (→ acceptance criteria 2)
   - emitter は `modules/retro-proposals.md` であり、`/verify` Step 16 と `/auto` Step 5 の両方から実行されること、`AUTO_EVENTS_LOG` 未設定時はスキップされること、非数値 `NUMBER` に対して `EMIT_ISSUE_NUMBER=0` を使うことを記述する
8. `scripts/get-auto-session-report.sh` に Tier 集計を追加する (after 6) (→ acceptance criteria 3)
   - `BACKFILLED_COUNT` の算出直後 (`# Verify phase residuals` コメントの直前) に、既存の `RECOVERY_COUNTS` と同じ jq パターンで `RETRO_TIER_COUNTS` (`"{n1} / {n2} / {n3}"` 形式、イベント不在時は `"0 / 0 / 0"`) と `RETRO_TIER_BREAKDOWN` (Tier ごとの件数行 + `Filter hit rate: {p}% ({n2}+{n3}/{total})`、イベント不在時は `(none)`) を算出する
   - Summary テーブル (`| Backfilled phase_complete events |` 行の直後) に `| Retro proposal tiers (1/2/3) | ${RETRO_TIER_COUNTS} |` を追加する
   - heredoc 末尾の `### Improvement Candidates Surfaced` の後ろに h3 見出し `### Retro Proposal Tier Breakdown` と `${RETRO_TIER_BREAKDOWN}` を追加する
   - jq 呼び出しはすべて `2>/dev/null || echo <default>` で degrade させ、bash 3.2+ 互換の範囲に収める (`mapfile` などの bash 4 機能を使わない)
9. `skills/audit/SKILL.md` の `auto-session` Subcommand `### Output Template Structure` の番号付きリストに項目 9 を追加する (after 8) (→ acceptance criteria 3)
   - `9. **Retro Proposal Tier Breakdown** — retro_proposal_classified イベントから算出した Tier 1/2/3 件数と filter hit rate` の形式で、既存 8 項目と同じ書式に合わせる
   - 半角感嘆符・小数点付き Step 番号・3 連バッククォートを本文に入れない (`validate-skill-syntax.py` の MUST 制約)
10. ドキュメントとテストを更新する (after 5, 8, 9)
    - `docs/structure.md` の `modules/retro-proposals.md` 行を `Improvement Proposal collection, Tier classification (with retro_proposal_classified event emission), and Issue creation (shared by /verify Step 16 and /auto Step 5)` 相当へ更新し、`docs/ja/structure.md` の対応行を日本語で同内容に更新する (→ acceptance criteria 2)
    - `tests/get-auto-session-report.bats` に 2 テストを追加する: (a) `retro_proposal_classified` イベント (tier 1/2/3 混在) を含む fixture で `### Retro Proposal Tier Breakdown` 見出し・Summary 行・`Filter hit rate` が出力されること、(b) 当該イベントを含まない fixture で `0 / 0 / 0` と `(none)` に degrade すること。既存テストと同じく `--no-github` でハーメティックに実行する (→ acceptance criteria 5)
    - `tests/retro-proposals.bats` に判定関数テストを追加する: (a) いずれのシグナルも実証できない入力でデフォルトが `tier2` を返すこと、(b) (a)/(b)/(c) いずれかを満たす入力でのみ `tier1` を返すこと。既存ファイルの `route_proposal()` と同じく module の規則を bash ヘルパーとして写す方式にする (→ acceptance criteria 5)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/retro-proposals.md の Tier 分類節において、判断が困難な場合のデフォルト挙動が見直されている。Tier 1 (起票) 以外へ倒す変更、または倒さない場合はその判断根拠が明記されている" --> <!-- verify: file_contains "modules/retro-proposals.md" "assign **Tier 2**" --> <!-- verify: file_not_contains "modules/retro-proposals.md" "assign Tier 1 (conservative" --> Tier 判定のデフォルト挙動が見直され、判断根拠が記録されている
- <!-- verify: rubric "Tier 1 / Tier 2 / Tier 3 の判定結果が永続化される仕組み (Spec の retrospective セクションへの記録、または .tmp/auto-events.jsonl へのイベント emit) が実装されている。terminal 出力のみで消える現状が解消されていることが実装から確認できる" --> <!-- verify: file_contains "modules/retro-proposals.md" "retro_proposal_classified" --> <!-- verify: file_contains "scripts/emit-event.sh" "retro_proposal_classified" --> Tier 判定結果が永続化されている
- <!-- verify: rubric "永続化された Tier 判定結果を集計してフィルタの hit rate (Tier 1 / 2 / 3 の件数比) を確認できる手段が存在する。/audit stats への組み込み、または独立したスクリプトのいずれでもよい" --> <!-- verify: file_contains "scripts/get-auto-session-report.sh" "retro_proposal_classified" --> <!-- verify: grep "Retro Proposal Tier Breakdown" "skills/audit/SKILL.md" --> Tier 判定の hit rate を集計できる
- <!-- verify: rubric "採用しなかった方針候補 (A/B/C/D のうち不採用としたもの) について、不採用の判断根拠が Spec または Issue に記録されている" --> <!-- verify: section_contains "docs/spec/issue-1159-retro-proposal-tier-default.md" "## Notes" "不採用" --> 不採用方針の判断根拠が記録されている
- <!-- verify: command "bats tests/" --> テストスイート全件が PASS する

### Post-merge

- 変更後に `/auto` を複数回実行し、`retro/verify` の起票レートが変更前 (2026-07 の 148 件/月) から低下していることを `/audit stats` で確認する

## Tool Dependencies

### Bash Command Patterns

- なし (新規パターンの追加なし)。`modules/retro-proposals.md` が新たに実行する `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh` は、呼び出し元である `skills/verify/SKILL.md` と `skills/auto/SKILL.md` の `allowed-tools` に既に登録済み

### Built-in Tools

- なし (既存の Read / Edit / Bash の範囲)

### MCP Tools

- なし

## Notes

### 方針候補 A/B/C/D の採否と根拠

| 候補 | 採否 | 根拠 |
|---|---|---|
| A. デフォルト反転 | **採用** (倒し先 = Tier 2) | Issue 本文の根本原因 1 に直接対応。Tier 3 の定義「一回限り・再発可能性が低い」は提案に対する積極的な主張であり、判定困難な提案に既定で適用するのは不正確。Tier 2「単発の学びだが再発性あり。memory 記載で十分」が「構造的重要度が不明」の受け皿として意味的に整合し、#484 の保守的意図も terminal への memory 提案出力として残る |
| B. 判定結果の永続化 | **採用** (`.tmp/auto-events.jsonl` イベント) | Issue 本文の根本原因 2 に直接対応。Spec retrospective への追記は `/verify` では worktree Exit (Step 13) 後の Step 16 に走るため main への追加 commit/push が必要になり、`/auto` L3 経路では書き込み先が `$SESSION_DIR` の bridge file に分岐して二重管理になる。既存 `emit-event.sh` はロック付き追記・session_id 付与・bats カバレッジが揃っており追加コストが最小 |
| C. 毎 run 起票の廃止 / consolidation 化 | **不採用** | `/verify` → 起票のフィードバックループを断ち切り、提案が Spec に埋もれたまま誰も横断レビューしないリスクが高い。週次 consolidation の実行主体 (`/audit` 系サブコマンドの新設) が別途必要で、本 Issue の範囲を大きく超える。A + B の効果測定後、起票レートが十分下がらなかった場合の次段として保留する |
| D. Tier 1 基準の定量化 | **採用** (軽量版) | A のデフォルト反転が実効性を持つための前提。Tier 1 基準が緩い OR 判定のままだと、デフォルトを反転しても提案は Tier 1 に流れ続ける。ただし「再発性 = 同種提案が過去 N 件以上」の完全機械判定は提案テキストの意味的クラスタリングを要し、LLM 判定を別の LLM 判定に置き換えるだけになるため、positive-evidence gate 化 (3 シグナル + 各シグナルの機械的確認手順) に留める |

### hit rate 集計先の選定

AC は「`/audit stats` への組み込み、または独立したスクリプトのいずれでもよい」としている。`/audit stats` は `gh issue list` を入力とする GitHub Issue メタデータ集計器で、`.tmp/auto-events.jsonl` を読む経路を持たない。一方 `scripts/get-auto-session-report.sh` は同ログを `session_id` でフィルタして集計する唯一の既存基盤であり、`/audit auto-session` から消費され、`tests/get-auto-session-report.bats` / `tests/audit-auto-session.bats` の 2 ファイルでテスト済み。後者を拡張する。

### 既知の制約: `/auto` L3 自身の分類はその session の `## Metrics` に載らない

`skills/auto/SKILL.md` Step 5 は sub-step 4 で `get-auto-session-report.sh --metrics-only` を実行して `## Metrics` を生成し、sub-step 6 で `modules/retro-proposals.md` を呼ぶ。したがって L3 レベルの retro-proposals 呼び出しが emit する `retro_proposal_classified` は、同じ session の `session.md` に埋め込まれた `## Metrics` には反映されない (`.tmp/auto-events.jsonl` には記録される)。

各 Issue の `/verify` Step 16 が emit する分 — 件数の大半 — は session 中を通じて Step 5 より前に発生するため正常に集計される。sub-step 2 で抽出される `$SESSION_DIR/events.jsonl` も同じ理由で L3 分を含まない。この非対称を解消するには `/auto` Step 5 のサブステップ順序変更が必要で、AC 2/3 の要件を超えるため本 Issue では扱わない。

### `emit_event()` の JSON 破壊リスク

`scripts/emit-event.sh` の `emit_event()` は `"issue":${_issue}` を引用符なしで出力する。`/auto` L3 経路の `BRIDGE_NUMBER` は `batch-<session-id>` という非数値になりうるため、そのまま `EMIT_ISSUE_NUMBER` に渡すと不正な JSON 行が `.tmp/auto-events.jsonl` に混入する。`get-auto-session-report.sh` は `jq -s` でファイル全体を一括読みするため、1 行の破壊でレポート全体が空 (`[]`) に degrade する。Implementation Step 4 の numeric ガードはこの回避が目的であり、実装時に省略してはならない。

### 旧デフォルト文の逐語引用禁止

AC1 の `file_not_contains "modules/retro-proposals.md" "assign Tier 1 (conservative"` は旧ポリシーの削除を検証する。Implementation Step 3 で追加する根拠ブロックが旧デフォルト文を逐語引用すると偽陰性になるため、言い換えで説明する。

### Tier 1 シグナルの網羅性マーカー

Implementation Step 1 で追加する 3 シグナルのリストには **(exhaustive)** マーカーを付ける (`modules/skill-dev-checks.md` の Exhaustive/Example Markers 規約)。

### 用語

`retro/verify` ラベルおよび Tier 1/2/3 の呼称は既存のまま維持する。本 Issue では新しい用語を導入しない。

### 自動解決した曖昧点 (非対話モード)

`/spec --non-interactive` のため `AskUserQuestion` が使用できず、以下 5 点をモデル判断で自動解決した。詳細な根拠は Issue #1159 の `## issue retrospective` コメント (Autonomous Auto-Resolve Log) に記録済み。

1. 方針候補の採否 → A + B + D (軽量版) を採用、C は不採用
2. A の倒し先 → Tier 3 ではなく Tier 2
3. B の永続化先 → Spec retrospective ではなく `.tmp/auto-events.jsonl` イベント
4. hit rate 集計先 → `/audit stats` ではなく `scripts/get-auto-session-report.sh`
5. D の深さ → positive-evidence gate 化に留め、機械判定スクリプトは新設しない
