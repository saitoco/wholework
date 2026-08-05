# Issue #1179: recoveries-auto-fire: recovery 頻度シグナルからの Issue 自動起票を絞り retro/verify の流入を止める

## Overview

`recoveries-auto-fire` (`docs/reports/orchestration-recoveries.md` → `scripts/collect-recovery-candidates.sh` → `/verify` Step 15) が retro/verify Issue の主要な供給源になっている (open Issue 83 件中 67 件、81%)。原因の大半 (orchestration-recoveries.md 66 エントリ中 58%) は `parent-session-manual-recovery` — external kill でフェーズが落ちた後の定型的な再実行であり、根本原因は upstream `anthropics/claude-code` の未対応 Issue にあって本リポジトリ側では解消できない (`docs/reports/external-kill-investigation.md` が SSoT)。加えて #1123 の group-key 細分化 (`symptom-short/cause-slug`) により、同一症状が複数キーに分かれて閾値到達しやすくなっている。

Issue 本文が挙げる 4 候補 (無効化 / 閾値引き上げ / group-key 細分化の撤回 / external-kill 系 group-key の除外) のうち、**方針 1 (`recoveries-auto-fire` を既定で無効化する)** を採用する。配布コンポーネント側の `recoveries-auto-fire.enabled` は元々デフォルト `false` (`modules/detect-config-markers.md`) であり、本リポジトリ自身の `.wholework.yml` が `enabled: true` で opt-in していたことが直接の原因だった。この opt-in を撤回し配布デフォルトへ戻すことで、`/verify` Step 15 の自動起票分岐 (`RECOVERIES_AUTO_FIRE_ENABLED=true` かつ `AUTONOMY_TIER=L2/L3`) が既定で通らなくなる。Step 15 自体の分岐ロジックは変更しない。`docs/reports/orchestration-recoveries.md` の蓄積と `collect-recovery-candidates.sh` による頻度集計は影響を受けないため、頻度の可視化は失われない。

他候補を採用しない理由、および関連 Issue (#1152 / #1123 / #1180 / #1181) との関係は `## Notes` を参照。

## Changed Files

- `.wholework.yml`: `recoveries-auto-fire:\n  enabled: true` を `enabled: false` に変更し、経緯 (#1179) と頻度確認コマンドへの参照コメントを追加
- `docs/tech.md`: Architecture Decisions に本方針転換を記録する箇条書きを追加 (`code-side auto-retry (silent no-op)` の直後に挿入)
- `docs/ja/tech.md`: 上記箇条書きの日本語訳を対応箇所 (`code フェーズ自動リトライ (silent no-op)` の直後) に追加 (`docs/translation-workflow.md` の Sync Procedure に従う)

## Implementation Steps

1. `.wholework.yml` の `recoveries-auto-fire:` ブロックを `enabled: false` に変更し、直上に「#1179 により既定 opt-out。頻度確認は `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1`」を示す 1 行コメントを追加する (→ 受入条件 1)
2. `docs/tech.md` の Architecture Decisions セクション、`code-side auto-retry (silent no-op)` 箇条書きの直後に、方針転換の経緯・根拠・頻度確認手段を記録する新しい箇条書きを追加する (after 1) (→ 受入条件 1, 2)
3. `docs/ja/tech.md` の対応箇所 (`code フェーズ自動リトライ (silent no-op)` 箇条書きの直後) に Step 2 の日本語訳を追加する (after 2) (→ 受入条件 4)
4. `bats tests/collect-recovery-candidates.bats` を実行し、`collect-recovery-candidates.sh` 自体は無変更のまま既存の回帰スイートが green であることを確認する (parallel with 1, 2, 3) (→ 受入条件 3)

## Verification

### Pre-merge

- <!-- verify: rubric "recoveries-auto-fire による自動起票が既定で発生しない状態になっている (無効化・閾値引き上げ・除外条件のいずれかで実装され、docs/tech.md および skills/verify/SKILL.md Step 15 の記述が実装と一致している)" --> 自動起票が既定で発生しない状態になっている
- <!-- verify: rubric "頻度シグナル自体は失われていない — collect-recovery-candidates.sh の出力または /audit stats から group-key ごとの発生回数が引き続き参照できることが実装・ドキュメントで確認できる" --> 頻度シグナルの参照手段は残っている
- <!-- verify: command "bats tests/collect-recovery-candidates.bats" --> `tests/collect-recovery-candidates.bats` が PASS する
- <!-- verify: command "bash scripts/check-translation-sync.sh" --> docs/ja 側の翻訳が同期している

### Post-merge

- `recoveries-auto-fire` が動作する `/verify` 実行で recovery 由来の Issue が自動生成されないことを観察する <!-- verify-type: observation event=auto-run -->

## Notes

**他候補を採用しない理由:**

- **方針 2 (閾値 3→8):** Issue 本文が自ら指摘する通り「発生ペース次第で同じ状態に戻る」— 7 月の external kill 集中期のような発生ペースでは、閾値を上げても遅かれ早かれ同じ量の自動起票に戻る。構造的な修正にならないため不採用。
- **方針 3 (#1123 の group-key 細分化を撤回):** `symptom-short/cause-slug` 分割は「同一症状で原因が異なる事象を区別して追跡する」ための改善であり、それ自体に価値がある (#1181 の `--cause`/`--diagnosis` フローもこの分割を前提にしている)。分割を撤回すると group-key 数は減るが、external kill 由来の起票自体は止まらない。方針 1 のほうが直接的かつ副作用が小さいため不採用。
- **方針 4 (external-kill 系 group-key の除外):** 方針 1 の採用により `recoveries-auto-fire.enabled: false` が既定になるため、本リポジトリでは方針 4 がなくても目的 (既定での自動起票停止) を達成できる。除外ロジックの追加 (`collect-recovery-candidates.sh` への除外パターン実装、cause-slug 分類、テスト追加) は SPEC_DEPTH=light の実装ステップ上限に対して過剰投資であり、将来 `recoveries-auto-fire.enabled: true` に再度 opt-in するプロジェクトが同じ問題に直面した場合の follow-up として温存する。

**関連 Issue との関係:**

- **#1152** (close 済み group-key の重複起票抑止): 本リポジトリでは `recoveries-auto-fire` が既定 opt-out になるため、当面の実害は発生しなくなる。ただし `collect-recovery-candidates.sh` 自体の重複抑止ギャップ (他プロジェクトが opt-in した場合に再発しうる) は残るため、#1152 はクローズせず open のまま残す。
- **#1123** (group-key の cause slug 細分化、close 済み): 撤回しない (上記方針 3 不採用の理由を参照)。
- **#1181** (`--write-manual-recovery` の記録先集約): `--cause` / `--diagnosis` フラグは撤去しない。cause-slug 分割を維持する前提と整合する。
- **#1180** (発火実績ゼロの fallback catalog エントリ退避): 本 Issue と同じ「recovery 関連の維持コスト削減」方針の一部だが、対象範囲が異なるため本 Issue の実装には含めない。

**`docs/guide/customization.md` / `docs/ja/guide/customization.md` は変更しない:** 両ファイルは既に `recoveries-auto-fire.enabled` のデフォルトを `false`・opt-in と正しく記載しており (`docs/guide/customization.md` Available Keys 表)、本 Issue で内容が古くなるドリフトは発生しない。変更が必要なのは本リポジトリ自身の `.wholework.yml` の opt-in 設定のみ。

## Autonomous Auto-Resolve Log

- **`phase/ready` label absent at code phase start**: at the start of this `/code 1179 --patch --non-interactive` run, the Issue already carried `phase/code` (not `phase/ready`). A Spec already existed at `docs/spec/issue-1179-recoveries-auto-fire-disable.md` and matched the Issue's acceptance criteria, so auto-resolved by proceeding with execution using the existing Spec rather than aborting. No content gap was found — the label state reflects an already-advanced phase transition, not a missing Spec.

## Code Retrospective

### Deviations from Design
- N/A — implemented exactly as planned (4 Implementation Steps, no reordering or consolidation)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Adopted policy 1 as scoped by the Spec: retracted `.wholework.yml`'s `recoveries-auto-fire.enabled: true` opt-in back to the distributed default (`false`), without touching `/verify` Step 15's branch logic itself.
- Verified `skills/verify/SKILL.md` Step 15's existing branch description (`RECOVERIES_AUTO_FIRE_ENABLED=false` → print recommendation only, no auto-fire) already matches the post-change behavior, so no edit to that file was needed — confirmed via direct read rather than assumed.
- Recorded frequency-visibility preservation explicitly in both `docs/tech.md` and `docs/ja/tech.md` (the exact `collect-recovery-candidates.sh --threshold 1` command), satisfying the Spec's rubric AC #2 without any code change to `collect-recovery-candidates.sh`.

### Deferred Items
- Policy 4 (exclude external-kill-cause group-keys from auto-fire eligibility) intentionally not implemented — Spec Notes judge it unnecessary once policy 1 makes auto-fire opt-out by default in this repository; left as a future follow-up for projects that re-opt-in.
- #1152 (duplicate group-key re-filing suppression) left open per Spec Notes — this Issue removes the immediate practical impact in this repository but does not fix the underlying gap in `collect-recovery-candidates.sh` for other projects that opt in.

### Notes for Next Phase
- Post-merge AC is an `observation` type (`event=auto-run`) — `/verify` should not expect it to resolve immediately; it resolves only once a subsequent `/verify` run with `recoveries-auto-fire` active is observed to not auto-file.
- All 4 pre-merge ACs (2 rubric, 2 command) were verified PASS during `/code` itself (patch route) and the Issue checkboxes were already updated — `/verify` re-confirmation is expected to be a formality here.

## Consumed Comments

No new comments since last phase.

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 受入条件の post-merge observation AC (`recoveries-auto-fire` が動作する `/verify` 実行で recovery 由来の Issue が自動生成されないことを観察する) が、**実装の内容によって観察前提を失う構造**になっていた。本 Issue の実装は `recoveries-auto-fire.enabled` を `false` にするものであり、条件文が要求する「auto-fire が動作する `/verify` 実行」は本リポジトリでは以後発生しない。条件文を「Step 15 が実行され起票が発生しない」と読めば観察可能だが、この読み替えは AC 文面からは一意に定まらない
- 起票時点でこの自己矛盾を検出するには、observation AC の前提 (`event=` が指す実行文脈) が実装後も成立するかを AC 監査時に確認する必要がある。#1118 / #1172 の `when=` 実行文脈ゲート、#1156 の解決不能 post-merge 条件検出がいずれも同型の課題を追跡しており、本件は新規の構造ではない

#### spec
- Issue 本文が挙げた 4 候補に対し、不採用理由が `## Notes` に個別に記録されており判断が追跡可能。方針 2 (閾値引き上げ) を「発生ペース次第で同じ状態に戻る」として構造的でないと退けた判断は、実測 (7 月の external kill 集中期に 52 件起票) と整合している
- 方針 3 (group-key 細分化の撤回) を #1181 の `--cause`/`--diagnosis` フローとの依存関係を理由に不採用としたのは、Issue 間の依存を正しく読んだ判断

#### code
- 実装は Spec の 4 ステップ通りで逸脱なし。`skills/verify/SKILL.md` Step 15 の既存分岐が変更後の挙動と一致することを**直接読んで確認**し、不要な編集を避けた判断が Phase Handoff に記録されている
- Size が spec フェーズ後に M → S へ再評価され、patch route に降格。Changed Files 3 件・低複雑度という実態と整合しており、`/triage` 時点の M 判定 (docs/ja 翻訳を含む 6 ファイル想定) より正確

#### review / merge
- patch route のため未実行 (該当なし)

#### verify
- pre-merge 4 条件はすべて PASS。うち rubric 2 件は実測を伴って確認した (`collect-recovery-candidates.sh --threshold 1` を実行し 10 件の group-key 出力を確認)
- 本 `/verify` の Step 15 で、閾値 3 を超える group-key (`manual-recovery-review-rerun` = 3) が存在するにもかかわらず自動起票が発生しないことを実測。本 Issue の目的は達成されている

### Improvement Proposals

- N/A — observation AC の前提失効の課題は #1118 / #1172 / #1156 が既に追跡中であり、新規起票は行わない。本 retrospective への記録をもって既存 Issue の裏付け事例とする
