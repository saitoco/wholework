# Issue #1063: agents: Opus sub-agent に effort frontmatter を導入し親セッション継承から分離する

## Overview

`agents/*.md` には現在 `effort:` frontmatter を持つファイルが 1 つもなく (`grep -rn "^effort:" agents/*.md` はゼロ件)、6 つの Opus sub-agent (`review-bug` / `review-spec` / `issue-scope` / `issue-risk` / `issue-precedent` / `frontend-visual-review`) の実効 effort は起動元セッションの設定に依存している。本 Issue は `#921` の follow-up として、6 sub-agent の frontmatter に `effort:` を明示し、実効値は現状維持のまま親セッション継承から分離する。あわせて `docs/tech.md` の Phase-specific model and effort matrix 表を実態に合わせて更新する。Sonnet sub-agent (`review-light` / `orchestration-recovery`) を対象に含めるかは実装時判断とし、根拠を本 Spec に記録する。

## Changed Files

- `agents/review-bug.md`: frontmatter に `effort: high` を追加
- `agents/review-spec.md`: frontmatter に `effort: high` を追加
- `agents/issue-scope.md`: frontmatter に `effort: high` を追加
- `agents/issue-risk.md`: frontmatter に `effort: high` を追加
- `agents/issue-precedent.md`: frontmatter に `effort: high` を追加
- `agents/frontend-visual-review.md`: frontmatter に `effort: high` を追加
- `agents/review-light.md`: frontmatter に `effort: high` を追加 (判断根拠は Notes 参照)
- `docs/tech.md`: Phase-specific model and effort matrix 表を更新 — 上記 7 行の Effort 列を `—` → `high` に変更し、Rationale から「effort inherited from parent」等の記述を削除・修正。`orchestration-recovery` 行の Rationale に対象外である旨の注記を追記
- `docs/ja/tech.md`: 上記と同じ表更新を日本語訳に反映 (`docs/translation-workflow.md` § Sync Procedure)

`agents/orchestration-recovery.md` 自体は変更しない (Notes 参照)。

## Implementation Steps

1. `agents/review-bug.md` / `agents/review-spec.md` / `agents/issue-scope.md` / `agents/issue-risk.md` / `agents/issue-precedent.md` の frontmatter (`model:` 行の直後) に `effort: high` を追加する。`scripts/run-review.sh` (review-bug/review-spec の起動元) と `scripts/run-issue.sh` (issue-scope/issue-risk/issue-precedent の起動元) はいずれも `--effort high` を渡しており、これは現状の実効値を維持する設定である (→ 受入条件 1-5)
2. `agents/frontend-visual-review.md` の frontmatter に `effort: high` を追加する (parallel with 1)。この経路は `/verify` スキルのセッションコンテキストで直接起動され、`run-*.sh` ラッパーを経由しないため実効 effort が不定だった。Opus 5 指針 (intelligence-sensitive な作業の推奨最低値 `high`) に基づき新たに明示値を定める (→ 受入条件 6)
3. `agents/review-light.md` の frontmatter に `effort: high` を追加する (parallel with 1, 2)。`skills/review/SKILL.md` で `subagent_type="review-light"` として Task ツール経由で起動されることを確認済みで、review-bug/review-spec と同じく `run-review.sh` の `--effort high` を継承している。`agents/orchestration-recovery.md` は対象から除外する — `scripts/spawn-recovery-subagent.sh` はこの agent を Task ツール subagent として起動しておらず、`AGENT_BODY=$(tail -n +"$((FRONTMATTER_END + 1))" "$AGENT_FILE")` で frontmatter を除去した本文のみを独立した `claude -p --effort medium` プロセスのプロンプトに埋め込んでいるため、`effort:` frontmatter を追加しても読み込まれず無効になる。effort の明示自体は当該スクリプトの `--effort medium` フラグで既に達成されている (→ 受入条件 8: 判断根拠の記録)
4. `docs/tech.md` の Phase-specific model and effort matrix 表を更新する (after 1, 2, 3): `review-bug` / `review-spec` / `review-light` / `issue-scope` / `issue-risk` / `issue-precedent` / `frontend-visual-review` 各行の Effort 列を `—` → `high` に変更。Rationale 文言から「effort inherited from parent」を削除し、`effort:` frontmatter を明示した旨を追記。`orchestration-recovery` 行の Rationale 末尾に、Task ツール subagent 経由でないため本 Issue の対象外である旨を追記 (→ 受入条件 7)
5. `docs/ja/tech.md` の同じ表を `docs/translation-workflow.md` § Sync Procedure に従って日本語訳に同期する (after 4) (→ 受入条件 7)

## Verification

### Pre-merge

- <!-- verify: grep "^effort:" "agents/review-bug.md" --> `agents/review-bug.md` の frontmatter に `effort:` が設定されている
- <!-- verify: grep "^effort:" "agents/review-spec.md" --> `agents/review-spec.md` の frontmatter に `effort:` が設定されている
- <!-- verify: grep "^effort:" "agents/issue-scope.md" --> `agents/issue-scope.md` の frontmatter に `effort:` が設定されている
- <!-- verify: grep "^effort:" "agents/issue-risk.md" --> `agents/issue-risk.md` の frontmatter に `effort:` が設定されている
- <!-- verify: grep "^effort:" "agents/issue-precedent.md" --> `agents/issue-precedent.md` の frontmatter に `effort:` が設定されている
- <!-- verify: grep "^effort:" "agents/frontend-visual-review.md" --> `agents/frontend-visual-review.md` の frontmatter に `effort:` が設定されている
- <!-- verify: rubric "docs/tech.md の Phase-specific model and effort matrix 表において、effort frontmatter を設定した sub-agent 行の Effort 列が `—` ではなく実際の effort 値になっており、Rationale から effort が親セッションから継承される旨の記述が削除または修正されている" --> `docs/tech.md` の matrix 表の Effort 列と Rationale が実態に合わせて更新されている
- <!-- verify: rubric "Spec または Issue 本文に、Sonnet sub-agent (review-light / orchestration-recovery) に effort frontmatter を設定するか否かの判断とその根拠が記録されている" --> Sonnet sub-agent を対象に含めるか否かの判断根拠が記録されている

### Post-merge

- `/review --full` を実行し、`review-bug` / `review-spec` が frontmatter の effort で起動して従来同等の検出結果を返すことを確認する <!-- verify-type: opportunistic -->

## Notes

- **review-light を対象に含める判断根拠**: `skills/review/SKILL.md` (400-413行付近) で `subagent_type="review-light"` として Task ツール経由で起動されることを確認した。これは `review-bug`/`review-spec` (`subagent_type="wholework:review-bug"` 等) と同じ起動機構であり、`scripts/run-review.sh` が light/full いずれのモードでも `--effort high` で自身の `claude -p` セッションを起動する (`_run_claude_review_session()` 内 2 箇所、AUTO_EVENTS_LOG の有無で分岐するのみで両方とも `--effort high`) ため、`review-light` の実効継承値も現状 `high` である。frontmatter 明示は他の Opus sub-agent と同じ decouple 効果を持つため対象に含めた。
- **orchestration-recovery を対象から除外する判断根拠**: `scripts/spawn-recovery-subagent.sh` を確認したところ、この agent は Task ツールによる subagent 起動ではなく、`AGENT_FILE="${SCRIPT_DIR}/../agents/orchestration-recovery.md"` を読み込んだ上で `FRONTMATTER_END` を awk で検出し `AGENT_BODY=$(tail -n +"$((FRONTMATTER_END + 1))" "$AGENT_FILE")` で frontmatter 部分を完全に除去してから、その本文だけを独立した `claude -p "$PROMPT" --model sonnet --effort medium ...` プロセスのプロンプトに埋め込んでいる (159行目)。つまり frontmatter は起動経路上どこにも読まれないため、`effort:` を追加しても実行に一切影響しない (無効な記述になる)。この agent の effort 分離は既にスクリプト側の `--effort medium` 明示フラグで達成済みであり、本 Issue のスコープ (frontmatter 導入によるデカップリング) には該当しないと判断した。
- **`effort:` frontmatter の公式仕様確認**: `https://code.claude.com/docs/en/sub-agents` (2026-08-07 WebFetch 確認) の Supported frontmatter fields 表に `effort` フィールドが記載されている — "Effort level when this subagent is active. Overrides the session effort level. Default: inherits from session. Options: `low`, `medium`, `high`, `xhigh`, `max`" — Issue 本文および `docs/tech.md` (#921 記載) の前提と一致することを確認した。
- **Pre-merge verification item count について**: 8 件で `$STEERING_DOCS_PATH/tech.md` の Spec Simplicity Rules が定める light 上限 (5 件) を超えるが、「Verify command sync rule」により Issue 本文の Pre-merge acceptance criteria (8 件) を改変せず逐語コピーした結果である。`/verify` はこれらをインデックスで個別にチェックするため、統合による件数圧縮は行わなかった。
- **`recoveries-auto-fire: enabled: false`** (`.wholework.yml`) — 本 Issue と直接の関係はないが、`orchestration-recovery` 調査中に確認した現在の設定として記録する。
