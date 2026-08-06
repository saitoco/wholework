# Issue #1180: orchestration-fallbacks: 発火実績ゼロの fallback catalog エントリを退避し Tier 2 の維持コストを削減

## Consumed Comments

No new comments since last phase.

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1180#issuecomment-5195139906
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1180#issuecomment-5195224905
## Overview

`modules/orchestration-fallbacks.md` (fallback catalog) と `scripts/detect-wrapper-anomaly.sh` (anomaly detector) のエントリ/パターンを発火実績と参照元で仕分け、恒常的な維持コストを持たないアーカイブへ退避する。

Issue 本文の方針 3 (「手順書として参照されているエントリは削除対象から除外する」) を一般化した **2 軸判定** を採用する:

- **軸 A — 発火実績**: `docs/reports/orchestration-recoveries.md` にそのエントリ/パターンが記録されているか
- **軸 B — live 参照元**: `docs/spec/` `docs/sessions/` 以外 (script の pointer コメント、検出器の IMPROVEMENT_HINT、SKILL.md、steering docs、実装済みハンドラ) から参照されているか

両軸ともゼロのものだけを退避する。検出器側は軸 B を「trigger 文字列を発行する live なスクリプト/ツールが存在するか」に読み替える (発行元が存在しないパターンは条件が構造的に真にならない = 到達不能コード)。

判定結果: **catalog 19 エントリ中 2 件を退避** (17 件残置)、**検出器 12 パターン中 2 件を退役** (10 件残置)。

## Inventory

Issue AC 1 の根拠。集計日 2026-08-06。母集団は `docs/reports/orchestration-recoveries.md` の全 68 エントリ。

計測範囲: 「発火実績」列は recoveries ログ本文中のアンカー/symptom-short 出現回数 (`rg -o` の実測値)。「live 参照元」列は `rg -n 'orchestration-fallbacks\.md#<anchor>'` から `docs/spec/**` `docs/sessions/**` を除外した実測値。

### fallback catalog エントリ (19 件)

| # | エントリ | 発火 | live 参照元 | 判定 |
|---|---|---|---|---|
| 1 | `ff-only-merge-fallback` | 2 | `scripts/worktree-merge-push.sh` x2 / `scripts/run-auto-sub.sh` / `scripts/apply-fallback.sh` / `modules/worktree-lifecycle.md` | 残置 |
| 2 | `gh-pr-list-head-glob` | 0 | `scripts/apply-fallback.sh` (未実装アンカーのコメントのみ) | **退避** |
| 3 | `ci-flake-retry` | 0 | なし | **退避** |
| 4 | `dco-signoff-missing-autofix` | 0 | `scripts/apply-fallback.sh` (実装済みハンドラ) / `scripts/detect-wrapper-anomaly.sh` (`dco-missing`) | 残置 |
| 5 | `conflict-marker-residual` | 0 | `scripts/worktree-merge-push.sh` (inline logic pointer) / `scripts/apply-fallback.sh` | 残置 |
| 6 | `dirty-working-tree` | 0 | `scripts/detect-wrapper-anomaly.sh` (退役予定) → 手順自体は現役 (下記 Notes 参照) | 残置 (Symptom 修正) |
| 7 | `reconciler-header-mismatch` | 0 | `scripts/detect-wrapper-anomaly.sh` | 残置 |
| 8 | `review-completion-false-negative` | 0 | `scripts/detect-wrapper-anomaly.sh` | 残置 |
| 9 | `code-completed-no-pr` | 0 | `scripts/detect-wrapper-anomaly.sh` | 残置 |
| 10 | `mid-run-api-error` | 0 | `scripts/detect-wrapper-anomaly.sh` | 残置 |
| 11 | `code-base-conflict` | 0 | `scripts/run-code.sh` x2 | 残置 |
| 12 | `async-external-commit` | 0 | `scripts/reconcile-phase-state.sh` (built-in 4 段チェックの SSoT) | 残置 |
| 13 | `json-mode-silent-hang` | 0 | `scripts/apply-fallback.sh` (実装済みハンドラ) / `scripts/detect-wrapper-anomaly.sh` | 残置 |
| 14 | `baseline-failure` | 0 | `scripts/run-merge.sh` | 残置 |
| 15 | `code-patch-silent-no-op` | 1 | `scripts/run-auto-sub.sh` / `scripts/apply-fallback.sh` (実装済みハンドラ) | 残置 |
| 16 | `wrapper-retry-on-kill` | 0 | `scripts/run-auto-sub.sh` x3 / `scripts/run-code.sh` x2 / `scripts/run-spec.sh` / `scripts/run-issue.sh` / `scripts/retry-on-kill.sh` / `docs/reports/external-kill-investigation.md` | 残置 |
| 17 | `external-kill-parent-respawn` | 0 (ただし recoveries ログの `manual-recovery-respawn` 22 件は本手順の実行結果) | `skills/auto/SKILL.md` / `scripts/run-auto-sub.sh` / `scripts/detect-external-kill.sh` / `docs/tech.md` / `docs/workflow.md` / `docs/structure.md` / `docs/ja/{tech,workflow,structure}.md` / `docs/reports/external-kill-investigation.md` x2 | 残置 |
| 18 | `review-pending-not-failure` | 0 | `skills/auto/SKILL.md` / `scripts/run-review.sh` / `scripts/run-auto-sub.sh` / `scripts/detect-wrapper-anomaly.sh` / `docs/tech.md` / `docs/workflow.md` / `docs/ja/{tech,workflow}.md` | 残置 |
| 19 | `manual-recovery-spec-write` | 39 (`### Recovery Applied` 行) | `skills/auto/SKILL.md` / `scripts/run-auto-sub.sh` / `docs/workflow.md` / `docs/ja/workflow.md` / `tests/run-auto-sub.bats` | 残置 |

### detect-wrapper-anomaly.sh パターン (12 件)

| # | パターン | 発火 | trigger 文字列の live 発行元 | 判定 |
|---|---|---|---|---|
| 1 | `pr-extraction-failure` | 0 | `scripts/run-auto-sub.sh:942,1021` (`Could not retrieve PR number`) | 残置 (アーカイブ参照を追記) |
| 2 | `patch-lock-timeout` | 0 | `scripts/worktree-merge-push.sh:63` | 残置 |
| 3 | `dco-missing` | 0 | 各 SKILL.md の sign-off ガード (`ERROR: missing sign-off`) | 残置 |
| 4 | `code-completed-no-pr` | 0 | `scripts/reconcile-phase-state.sh` の JSON 出力 | 残置 |
| 5 | `json-mode-silent-hang` | 0 | `scripts/claude-watchdog.sh:71` | 残置 |
| 6 | `watchdog-kill` | 0 | **なし** — `watchdog: kill and state not reached` を発行するスクリプトが存在しない (現行の `claude-watchdog.sh:78,98` は `watchdog: no output for <N>s, killing process` を発行) | **退役** |
| 7 | `dirty-working-tree` | 0 | **なし** — AND 条件の `VERIFY_FAILED` が `run-verify.sh` 削除 (#485) 以降どこからも発行されない | **退役** |
| 8 | `reconciler-header-mismatch` | 0 | `scripts/reconcile-phase-state.sh` | 残置 |
| 9 | `review-completion-false-negative` | 0 | `scripts/reconcile-phase-state.sh` | 残置 |
| 10 | `mid-run-api-error` | 0 | Claude API エラー出力 | 残置 |
| 11 | `preview-deployment-absent` | 0 | `scripts/run-review.sh:183,191` | 残置 |
| 12 | `silent-no-op` | 9 | exit 0 + 成功フレーズ | 残置 |

## Changed Files

- `docs/reports/orchestration-fallbacks-archive.md`: 新規作成。退避した catalog 2 エントリと退役した検出器 2 パターンを収容
- `modules/orchestration-fallbacks.md`: `## gh-pr-list-head-glob` / `## ci-flake-retry` の 2 エントリを削除。`## dirty-working-tree` の Symptom / Rationale から失効した `VERIFY_FAILED` + 検出器発行の記述を除去し現行シグナルに差し替え。`## code-completed-no-pr` と `## json-mode-silent-hang` の Rationale から `watchdog-kill` との優先順位記述を除去。`## Operational Notes` に `### Entry Retention Criterion` と `### Archived Entries` を追加
- `scripts/detect-wrapper-anomaly.sh`: `watchdog-kill` と `dirty-working-tree` の elif ブロックを削除。`pr-extraction-failure` の `IMPROVEMENT_HINT` にアーカイブ参照を追記 — bash 3.2+ 互換
- `scripts/apply-fallback.sh`: `detect_symptom_anchor()` 末尾の `# See modules/orchestration-fallbacks.md#gh-pr-list-head-glob (not yet implemented)` をアーカイブ参照に差し替え — bash 3.2+ 互換
- `tests/detect-wrapper-anomaly.bats`: 退役 2 パターンのテスト計 4 件 (`watchdog kill: ...` 1 件、`dirty working tree: ...` 3 件) を削除。`PR extraction failure: ...` にアーカイブ参照のアサーションを追加
- `tests/orchestration-fallbacks.bats`: アーカイブファイルの存在、退避 2 アンカーが live catalog に無いこと、アーカイブが両アンカーを保持していること、`Entry Retention Criterion` セクションの存在を検証するテストを追加
- `docs/structure.md`: Key Files > Modules の `modules/orchestration-fallbacks.md` 行にアーカイブ (`docs/reports/orchestration-fallbacks-archive.md`) への参照を追記
- `docs/ja/structure.md`: 上記の日本語ミラー (`docs/ja/structure.md:136`)
- `docs/reports/orchestration-recoveries.md`: 変更なし (append-only の履歴ログ。過去エントリの `Recovery Applied` 行に残る退避済みアンカーは履歴記録として保持)
- `tests/fixtures/orchestration-recoveries-sample.md`: 変更なし (`gh-pr-list-head-glob` は `collect-recovery-candidates` の頻度集計テスト用 group-key であり、カタログへの参照ではない — grep 確認済み)

Steering Docs sync candidate (`grep -rn` による横断検索の結果):

- `docs/structure.md:224` / `docs/ja/structure.md:216`: [Steering Docs sync candidate] `scripts/apply-fallback.sh` の説明にハンドラ名が列挙されている。本 Issue はハンドラを変更しないため更新不要の見込みだが、`/code` 側で内容を確認すること
- `docs/structure.md:220` / `docs/ja/structure.md:212`: [Steering Docs sync candidate] `scripts/detect-wrapper-anomaly.sh` の説明。パターン数を記載していないため更新不要の見込みだが、要確認
- `docs/tech.md:55` / `docs/ja/tech.md:46` / `docs/product.md:178` / `docs/ja/product.md:167`: [Steering Docs sync candidate] Tier 1/2/3 の構成説明。個別パターン名を列挙していないため更新不要の見込みだが、要確認

## Implementation Steps

1. `docs/reports/orchestration-fallbacks-archive.md` を新規作成する。frontmatter は `type: report` (`docs/reports/orchestration-recoveries.md` と同形式)。冒頭に (a) 本ファイルの役割、(b) 退避基準 (2 軸ゼロ)、(c) 復帰手順 (再発時に該当節を `modules/orchestration-fallbacks.md` へ戻し、参照元の pointer コメントを再指定する) を記述する。続けて `## Archived catalog entries` 配下に `gh-pr-list-head-glob` / `ci-flake-retry` を Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale の 5 セクション構造のまま移設し、各エントリ末尾に「退避理由 / 退避日 / 退避 Issue #1180」を追記する。さらに `## Retired detector patterns` 配下に `watchdog-kill` / `dirty-working-tree` を、trigger 文字列・失効経緯・復帰時に使うべき現行シグナル (`watchdog-kill` → `scripts/claude-watchdog.sh` の `watchdog: no output for <N>s, killing process`、`dirty-working-tree` → `skills/verify/SKILL.md` Step 1 の `Cannot run verify because there are uncommitted changes`) 付きで記録する (→ 受け入れ条件 4)
2. `modules/orchestration-fallbacks.md` から `## gh-pr-list-head-glob` と `## ci-flake-retry` の節を、直後の `---` 区切りごと削除する (→ 受け入れ条件 5, 6)
3. `modules/orchestration-fallbacks.md` の `## Operational Notes` に `### Entry Retention Criterion` を追加する。内容は本 Spec の 2 軸判定 (発火実績 OR live 参照元のいずれかがあれば残置、両方ゼロならアーカイブへ退避) と、新規エントリ追加時に既存の「When a new fallback pattern is discovered」手順とセットで退役経路も存在することの明示。続けて `### Archived Entries` に退避済みアンカーの一覧を置く。**一覧の各行はインラインコード + 矢印形式 (例: バッククォート囲みの `ci-flake-retry` に続けて `— docs/reports/orchestration-fallbacks-archive.md` ) とし、H2 見出し形式 (`## <anchor>`) は使わない** — 受け入れ条件 5/6 の `file_not_contains` が誤検知するため (after 2) (→ 受け入れ条件 2, 3)
4. `modules/orchestration-fallbacks.md` の失効記述を修正する (after 2): (a) `## dirty-working-tree` の Symptom から `VERIFY_FAILED` および「`scripts/detect-wrapper-anomaly.sh` emits pattern」の記述を除去し、現行シグナル (`skills/verify/SKILL.md` Step 1 / `scripts/check-verify-dirty.sh` が出す `Cannot run verify because there are uncommitted changes`) に差し替え、Rationale 末尾に「検出器側パターンは #1180 で退役 (アーカイブ参照)」を追記する。(b) `## code-completed-no-pr` の Rationale から `watchdog-kill` との first-match-wins 優先順位に関する 1 行を削除する。(c) `## json-mode-silent-hang` の Rationale の同種の記述から `watchdog-kill` への言及を削除する (→ 受け入れ条件 2)
5. `scripts/detect-wrapper-anomaly.sh` から `watchdog-kill` (`elif grep -q "watchdog: kill and state not reached"` ブロック) と `dirty-working-tree` (`elif grep -q "VERIFY_FAILED" ... && grep -q "uncommitted"` ブロック) を削除する。削除後も elif チェーンの残る分岐順序 (`json-mode-silent-hang` → `reconciler-header-mismatch` → `review-completion-false-negative` → `mid-run-api-error` → `preview-deployment-absent` → `EXIT_CODE == 0`) が維持されることを確認する。あわせて `pr-extraction-failure` の `IMPROVEMENT_HINT` に `docs/reports/orchestration-fallbacks-archive.md` への参照を追記する (既存の `#311` 参照は残す) (→ 受け入れ条件 7)
6. `scripts/apply-fallback.sh` の `detect_symptom_anchor()` 末尾コメント `# See modules/orchestration-fallbacks.md#gh-pr-list-head-glob (not yet implemented)` を `# gh-pr-list-head-glob: archived — see docs/reports/orchestration-fallbacks-archive.md (#1180)` に差し替える。`ff-only-merge-fallback` / `conflict-marker-residual` の 2 行はカタログに残置するため変更しない (after 2) (→ 受け入れ条件 2)
7. `tests/detect-wrapper-anomaly.bats` を更新する (after 5): `watchdog kill: detects watchdog: kill and state not reached` (1 件) と `dirty working tree:` で始まる 3 件、計 4 件の `@test` を削除する。`PR extraction failure: detects Could not retrieve PR number` に、出力へアーカイブファイル名が含まれることのアサーションを 1 行追加する (既存の `#311` アサーションは残す) (→ 受け入れ条件 8)
8. `tests/orchestration-fallbacks.bats` にテストを追加する (after 1, 2, 3): (a) `docs/reports/orchestration-fallbacks-archive.md` が存在する、(b) live catalog に `## ci-flake-retry` / `## gh-pr-list-head-glob` が無い、(c) アーカイブに両アンカーの H2 見出しと 5 必須セクションが存在する、(d) live catalog に `### Entry Retention Criterion` が存在する。既存の `>= 6` 閾値テストと「5 必須セクションの出現回数が一致する」テストは 19→17 エントリでも成立するため変更しない (→ 受け入れ条件 8)
9. `docs/structure.md` の Key Files > Modules にある `modules/orchestration-fallbacks.md` の行末に、退避済みエントリのアーカイブ先 (`docs/reports/orchestration-fallbacks-archive.md`) への参照を追記する。あわせて `docs/ja/structure.md:136` の対応行に同内容の日本語ミラーを反映する (→ 受け入れ条件 2, 9)

## Verification

### Pre-merge

- <!-- verify: rubric "各 fallback catalog エントリの発火実績と参照元の一覧が Spec に記録され、残置/退避の判断根拠が追跡できる" --> 発火実績と参照元の一覧が Spec に記録されている
- <!-- verify: rubric "退避後も skills/auto/SKILL.md・docs/tech.md・docs/workflow.md・docs/structure.md およびそれらの docs/ja 翻訳から orchestration-fallbacks.md への参照リンクが壊れていない (退避したエントリへのアンカー参照が残っていない)" --> カタログへの参照リンクが壊れていない
- <!-- verify: rubric "手順書として参照されているエントリ (external-kill-parent-respawn / manual-recovery-spec-write) の内容が、退避された場合も参照元から辿れる形で保持されている" --> 手順書用エントリの参照可能性が保たれている
- <!-- verify: file_exists "docs/reports/orchestration-fallbacks-archive.md" --> 退避先アーカイブファイルが存在する
- <!-- verify: file_not_contains "modules/orchestration-fallbacks.md" "## ci-flake-retry" --> `ci-flake-retry` エントリが live catalog から除去されている
- <!-- verify: file_not_contains "modules/orchestration-fallbacks.md" "## gh-pr-list-head-glob" --> `gh-pr-list-head-glob` エントリが live catalog から除去されている
- <!-- verify: file_not_contains "scripts/detect-wrapper-anomaly.sh" "watchdog: kill and state not reached" --> 到達不能な検出器パターンが除去されている
- <!-- verify: command "bash scripts/test-skills.sh" --> skill 構文検証と bats スイートが PASS する
- <!-- verify: command "bash scripts/check-translation-sync.sh" --> docs/ja 側の翻訳が同期している

### Post-merge

- 退避後の `/auto` 実行で Tier 2 が不在によるエラーを起こさず、未知パターンが Tier 3 へ正しく落ちることを観察する (verify-type: observation, event=auto-run)
  - 期待される出力構造:
    - `apply-fallback.sh` が未知アンカーで exit 1 を返し、`run-auto-sub.sh` が Tier 3 (`spawn-recovery-subagent.sh`) へ escalate する
    - `detect-wrapper-anomaly.sh` が退役 2 パターンの入力に対して空出力 (exit 0) を返し、エラー終了しない

## Tool Dependencies

### Bash Command Patterns

- なし (実装は Read / Write / Edit と既存の bats 実行のみ)

### Built-in Tools

- なし (`/code` の既存 allowed-tools で充足)

### MCP Tools

- なし

## Notes

### 判定基準を Issue 本文の前提から一般化した点

Issue 本文は「17 エントリは発火実績ゼロ」を退避候補の規模として提示しているが、方針 3 の除外条件 (手順書として参照されているエントリ) を実測で当てると 17 件中 15 件が該当し、退避対象は 2 件に収束する。これは前提の誤りではなく、方針 3 の適用範囲が本文で例示された 2 件 (`external-kill-parent-respawn` / `manual-recovery-spec-write`) より広かったということ。Inventory セクションが AC 1 の「判断根拠が追跡できる」を満たす一次資料になる。

### 検出器側の到達不能パターンは別性質の発見

`watchdog-kill` と `dirty-working-tree` は「未発火」ではなく「条件が構造的に真にならない」。前者は `claude-watchdog.sh` の出力文字列が現行 (`watchdog: no output for <N>s, killing process`) と一致しておらず、後者は AND 条件の `VERIFY_FAILED` が `run-verify.sh` 削除 (#485) 以降どこからも発行されない。後者は `skills/spec/SKILL.md` の Feature deletion impact chain check セクションに「#485 retro で検出されたが除去されなかった dead pattern」として既に事例記載がある。

### 汎用 watchdog kill の検出が現在不在という副次的発見

`watchdog-kill` の退役により「json mode 以外の watchdog タイムアウト kill」に対する Tier 2 検出が明示的に不在となる (退役前も分岐が到達不能だったため実効的には既に不在)。これは本 Issue のスコープ (維持コスト削減) 外の欠陥であり、修復 (trigger 文字列を現行に合わせる) は別 Issue に委ねる。アーカイブファイルに復帰時に使うべき現行シグナルを記録することで、修復に必要な情報は失われない。spec retrospective にも記録し `/verify` の Improvement Proposal 集約に載せる。

### 退避先を docs/reports/ にした理由

`docs/translation-workflow.md` の Exclusions が `docs/reports/` を翻訳同期対象外とし、`modules/doc-checker.md` の Processing Steps 2 も `docs/reports/` を候補から除外している。退避後にアーカイブが恒常的な同期義務を生まないため、本 Issue の目的 (維持コスト削減) と整合する。`docs/reports/ja/` に一部レポートの翻訳が存在するが、translation-workflow.md 上の義務ではないため本 Issue では作成しない。

### AC 5/6 の file_not_contains が誤検知しない条件

`modules/orchestration-fallbacks.md` に追加する `### Archived Entries` 一覧が `## ci-flake-retry` / `## gh-pr-list-head-glob` という H2 見出し形式を含むと AC 5/6 が FAIL する。Implementation Step 3 でインラインコード + 矢印形式を明示指定している。

### AC 9 (check-translation-sync.sh) の性質

`scripts/check-translation-sync.sh` は `--fail-if-outdated` なしでは常に exit 0 を返す情報提供専用スクリプト。本 Spec 作成時点の baseline は `1 OUTDATED (docs/guide/index.md) / 1 MISSING_JA (docs/guide/autonomy.md)` で、いずれも本 Issue とは無関係な既存ギャップ。Implementation Step 9 の `docs/ja/structure.md` 更新を怠っても AC としては PASS してしまうため、`/code` および `/review` では出力表の `docs/structure.md` 行が `IN_SYNC` であることを目視確認すること。

### tests/fixtures の gh-pr-list-head-glob は対象外

`tests/fixtures/orchestration-recoveries-sample.md` に `gh-pr-list-head-glob` が 3 エントリ分の symptom-short として現れるが、これは `collect-recovery-candidates.sh` の頻度集計テスト用の合成データであり、カタログエントリへの参照ではない。変更すると `tests/collect-recovery-candidates.bats` の期待値が壊れるため対象外とする。

### bats テストの閾値への影響

`tests/orchestration-fallbacks.bats` の既存テストはすべて `>= 6` 閾値と「5 必須セクションの出現回数一致」で構成されており、エントリを丸ごと削除する限り 19→17 でも成立する (確認済み)。

## spec retrospective

### Minor observations

- Issue 本文の「実装規模」表が引用するカタログ行数 (675 行) は #1181 のマージ後に 658 行へ縮んでおり、Issue 起票時のスナップショットのまま。数値そのものは判断に影響しないが、Issue 本文の実測値が起票時点で凍結される性質は `/verify` の再測定時に注意が要る。
- `docs/reports/orchestration-recoveries.md` は Issue 起票時の 66 エントリから 68 エントリに増えている。本 Spec の Inventory は 2026-08-06 時点の 68 エントリで再集計した。
- `manual-recovery-spec-write` のアンカーが recoveries ログに 39 回現れるのは、`run-auto-sub.sh --write-manual-recovery` が `### Recovery Applied` 行に固定文字列として書き込むため。Issue 本文の「recoveries ログに出現するのは 2 エントリのみ」という記述はこの自動出力を除外した集計であり、両者は矛盾しない。

### Judgment rationale

- Issue 方針 3 の除外条件 (「手順書として参照されているエントリ」) は本文で 2 件しか例示されていないが、条件そのものを実測で適用すると 17 件中 15 件が該当した。例示を候補リストと解釈せず条件として一般化したことが、退避対象を 2 件に絞る判断の分岐点。判断根拠が追える形 (Inventory テーブル) を Spec に残すことが AC 1 の要求そのものであり、規模の小ささは調査結果であって手抜きではない。
- 検出器側の「縮約」を発火実績ではなく trigger 文字列の live 発行元の有無で判定した。発火実績ゼロを理由に退役すると、稀にしか起きないが起きたら検出したいパターン (例: `patch-lock-timeout`) まで落ちる。到達不能コードの除去なら検出能力は 1 ビットも失われない。
- `dirty-working-tree` は catalog エントリと検出器パターンで判定が分かれた唯一のケース。検出器は到達不能だが、手順そのもの (dirty file を分類して cleanup し再実行) は `check-verify-dirty.sh` 経由で今も起きるシナリオに有効なため catalog 側は残置し Symptom だけ現行シグナルに更新する、という非対称な結論になった。

### Uncertainty resolution

- **カタログからエントリを削るとスキーマ検証 bats が壊れるか**: `tests/orchestration-fallbacks.bats` を読み、全テストが `>= 6` 閾値と 5 セクションの出現回数一致で構成されていることを確認。19→17 でも成立するため既存テストの変更は不要と判断した。
- **`docs/reports/` 配下に新規ファイルを置くと翻訳同期が要るか**: `docs/translation-workflow.md` の Exclusions と `scripts/check-translation-sync.sh` の SOURCE_FILES 収集ロジック (`docs` maxdepth 1 と `docs/guide` のみ) の両方を確認し、不要と確定。これが退避先選定の決め手になった。
- **`AC 9` の `check-translation-sync.sh` が実質的な検証になっているか**: スクリプトを読み、`--fail-if-outdated` なしでは常に exit 0 を返すことを確認。本 Spec 作成時点で既に 1 OUTDATED / 1 MISSING_JA の既存ギャップがあり、AC としては素通りする。verify command は Issue body の記述を verbatim で引き写す規約のため書き換えず、代わりに Notes に「`/code` / `/review` で出力表の `docs/structure.md` 行を目視確認する」という運用上の補いを明記した。

## Code Retrospective

### Deviations from Design
- Implementation Step 1 says the two archived entries move "配下に" (under) `## Archived catalog entries`, which reads as nesting the anchors as H3. Instead they were kept as H2 headings (siblings following the `## Archived catalog entries` label, not its children), because Step 8's AC test description explicitly requires "アーカイブに両アンカーの H2 見出し" — literal H2 for the anchor names. Resolving the ambiguity toward the literal AC wording (H2) rather than the "配下に" nesting implication keeps the archive's per-entry structure identical to the live catalog's own H2-anchor / H3-subsection convention, which also made the bats test in Step 8 a straightforward structural mirror of the existing catalog schema tests.

### Design Gaps/Ambiguities
- The retired `dirty-working-tree` detector pattern and the still-live `dirty-working-tree` catalog entry share the same anchor name across two different files (archive vs. live catalog). The archive heading was written as `### dirty-working-tree (detector pattern)` to disambiguate it from a hypothetical future archival of the catalog entry itself; this qualifier is not prescribed by the Spec but avoids an anchor collision within the single archive file (the catalog entry itself was never archived, so no collision exists today, but the qualifier front-loads the disambiguation).

### Rework
- N/A — no repair cycles or backtracking occurred during implementation; the H2/H3 heading-level ambiguity above was resolved once at authoring time (Step 1/Step 8) before the first test run, not discovered via a failing test.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- Merged via squash with `--non-interactive`; pre-merge AC gate (`check-pre-merge-ac.sh`) reported `unchecked_count=0` (9/9 checked), so no override marker was needed.
- `gh-pr-merge-status.sh` returned `mergeable=true, reason=clean, ci_status=success, review_status=approved` — proceeded directly to squash merge without conflict resolution or worktree entry.

### Deferred Items

- AC 9 (`check-translation-sync.sh`) remains unchecked/UNCERTAIN as expected (no corresponding CI job) — `/verify` is the phase that can actually execute it and flip the checkbox.
- Generic (non-json-mode) watchdog-kill Tier 2 detection recovery remains out of scope (unchanged from code/review-phase handoff).
- Issue Related #1122 / #1105 / #1076 (proposed catalog/detector entry additions) — still a post-merge judgment call against the corrected Entry Retention Criterion (unchanged from prior handoffs).

### Notes for Next Phase

- `/verify` should run in full mode to execute `check-translation-sync.sh` and resolve AC 9.
- The post-merge verification item from the PR body applies: confirm a subsequent `/auto` run with an unrecognized wrapper-anomaly pattern escalates cleanly to Tier 3 without erroring on the archived Tier 2 entries.

## review retrospective

### Spec vs. implementation divergence patterns

The newly authored `### Entry Retention Criterion` (added in the code phase, not prescribed verbatim by the Spec) did not fully reproduce the retention decisions the same PR actually made: Axis B as written would have retained `gh-pr-list-head-glob` (it had a script pointer comment, which the criterion counted as a live reference, with no carve-out for a comment explicitly marked `(not yet implemented)` and backed by no handler), and neither axis explained why `dirty-working-tree` stayed live after its only reference (the detector branch) was removed in the same PR. This is a case where a governance/criterion document was written in the same PR that exercises it, but not validated against its own worked examples before being committed — three independent review agents (review-spec + both review-bug instances) converged on the same root gap independently, which is a strong signal it was a real, checkable omission rather than a stylistic nitpick. Fixed in review (Step 12): added the missing carve-out, an archive-file self-reference exclusion, and a new Axis C for procedure applicability, mirrored into both `modules/orchestration-fallbacks.md` and `docs/reports/orchestration-fallbacks-archive.md`.

### Recurring issues

Documentation-only PRs that add a brand-new `docs/reports/*.md` file are not covered by any automated CLAUDE.md language-convention check — `docs/reports/orchestration-fallbacks-archive.md` shipped to review with English body sections but Japanese `Archival Note` / `Retired detector patterns` sections, and a stray full-width-parentheses violation, both of which only surfaced via manual review reading. `scripts/check-forbidden-expressions.sh` and the CI `Forbidden Expressions check` job do not check language consistency or 約物 formatting, only a fixed deprecated-term list. This is not new to this PR — it is a structural gap (no automated check exists for this class of issue) rather than an implementation mistake specific to this PR — but it is the second consecutive fallback-catalog-adjacent PR in recent history to add a new `docs/reports/` file, so the absence of automated coverage is worth flagging for `/verify`'s retro-proposal aggregation to consider (e.g., extending `check-forbidden-expressions.sh` or a new lightweight checker to flag full-width parentheses in prose lines, or mixed-language sections within a single English-designated `docs/reports/*.md` file).

### Acceptance criteria verification difficulty

AC 9 (`command "bash scripts/check-translation-sync.sh"`) has no corresponding CI job (confirmed by reading `.github/workflows/test.yml` in full), so `/review`'s safe-mode CI-reference fallback can never resolve it — it will UNCERTAIN on every `/review` run regardless of the actual state of the translation sync, permanently leaving that Pre-merge checkbox unchecked until `/verify` (full mode) runs post-merge. The Spec's own Notes section already anticipated this ("AC 9 の `check-translation-sync.sh` が実質的な検証になっているか" — the script always exits 0 without `--fail-if-outdated`), so this is a known, accepted limitation rather than a new discovery, but it's worth reiterating for `/verify`'s retro-proposal aggregation: `command`-type Pre-merge ACs with no CI job counterpart are structurally unreviewable pre-merge under `/review`'s safe mode, and Issue authors should either add a CI job for such scripts or mark them as a different verify-type (e.g. `verify-type: manual` or an explicit post-merge check) if pre-merge blocking via `/review` is not actually intended.

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 起票時の分析が **軸 A (発火実績) のみ**で「19 エントリ中 17 件が発火実績ゼロ」としていたのに対し、spec が軸 B (live 参照元の有無) を追加した結果、実際の退避は 2 エントリに留まった。起票時点で「発火していない = 不要」と短絡していたことになる。手順書として参照されているエントリは発火実績がなくても機能しており、削除すると参照が壊れる — AC 3 に「手順書用エントリの参照可能性」を含めていたおかげで、この観点が spec に引き継がれた
- Pre-merge AC 9 (`command "bash scripts/check-translation-sync.sh"`) が **対応 CI job を持たない `command` 型**であり、`/review` の safe mode では構造的に検証不能。結果として未チェックのまま merge gate をブロックした。同じ AC を使った #1179 / #1181 / #1180 の 3 件中 2 件で merge が止まっている

#### spec
- 2 軸 (発火実績 / live 参照元) での仕分け設計が適切。判定表に全 19 エントリの根拠と計測方法 (`rg -o` 実測値、`docs/spec/**` `docs/sessions/**` 除外) を残したため、後から判断を再検証できる
- 検出器側の軸 B を「trigger 文字列の live 発行元が存在するか」に読み替えた点が的確。これにより `dirty-working-tree` の AND 条件にある `VERIFY_FAILED` が `run-verify.sh` 削除 (#485) 以降どこからも発行されない**到達不能コード**であることを発見した。`skills/spec/SKILL.md` に #485 retro の事例として記載されながら実コードから除去されていなかったもので、本 Issue で解消された
- 副次的発見として「汎用 watchdog kill (json mode 以外) の Tier 2 検出が不在」を spec retrospective に記録。退役前から到達不能だったため実効的な変化はないが、修復は別 Issue の対象

#### code
- 実装は Spec の 9 ステップどおり。退避先 `docs/reports/orchestration-fallbacks-archive.md` を翻訳同期・doc-checker いずれの対象外パスに置いた設計により、アーカイブの恒常維持コストがゼロになっている

#### review
- AC 9 の構造問題を review 時点で正しく分析し、`/verify` の retro-proposal 集約へ明示的に委ねていた。review が「検出はしたが自分では解決できない構造問題」を下流へ正しくエスカレーションした好例
- `docs/reports/*.md` を新規追加する documentation-only PR が CLAUDE.md の言語規約チェックの対象外である点も指摘。実際に本 PR のアーカイブファイルが英語本文に日本語セクション混在・全角括弧混入の状態で review に到達し、人手の読解でのみ検出された

#### merge
- pre-merge AC gate が AC 9 の未チェックを検出してブロック (#1181 と同一原因の 2 件目)。親セッションが PR ブランチ上で `docs/structure.md` / `docs/ja/structure.md` の同一コミットを確認して AC をチェックし、`run-merge.sh` 再実行で解消
- merge 後の `--write-manual-recovery` は #1181 の実装 (Spec 書き込み撤去) 後の**初回のクリーンな実行**となり、Spec のコミットハッシュ・ファイルハッシュとも無変更、deferred stash ファイルも生成されず、記録先が `docs/reports/orchestration-recoveries.md` 1 ファイルのみであることを実測で確認した

#### verify
- pre-merge 9 件すべて PASS。うち rubric 3 件は退避エントリのアンカー参照を実地 grep して確認 (`tests/fixtures/` の 3 件はサンプルデータであり rubric が指定する参照元ではない)

### Improvement Proposals

- **`command` 型 Pre-merge AC に対応 CI job がない場合、`/review` の safe mode では構造的に検証不能となり、未チェックのまま `/merge` の pre-merge AC gate をブロックする**。本セッションで #1181 / #1180 の 2 件が同一原因で merge に失敗し、いずれも親セッションの手動介入 (実質検証 → チェックボックス更新 → merge 再実行) を要した。加えて `check-translation-sync.sh` のように `--fail-if-outdated` なしで常に exit 0 を返すスクリプトを `command` 型 AC に使うと、判別力のない「常時 PASS な verify command」にもなる (`/triage` の AC 監査 Pattern 2 は文字列存在ベースの常時 PASS のみを扱い、exit code 設計に起因するものは検出対象外)。`/issue` の AC 作成時点で「`command` 型 AC は対応 CI job があるか」「スクリプトが失敗時に非ゼロを返すか」を確認し、満たさない場合は post-merge へ回すか `verify-type: manual` にするガイドラインが必要
- (記録のみ) `docs/reports/*.md` を新規追加する documentation-only PR は CLAUDE.md の言語規約チェックの対象外。`scripts/check-forbidden-expressions.sh` は固定の deprecated 用語リストのみを見ており、言語混在や約物違反は検出しない。本 PR で実際に混入が発生したが、既存 checker の拡張範囲であり本 Issue のスコープ外
