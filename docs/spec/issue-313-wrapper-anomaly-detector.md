# Issue #313: auto: shell wrapper 定型失敗パターン自動検出 detector 追加

## Overview

`/auto` parent session が shell wrapper (`run-code.sh` 等) の非ゼロ終了を検出した際、既知パターン（PR 抽出失敗・lock timeout・DCO 欠落・watchdog kill）を自動マッチして markdown 断片を生成する helper script `scripts/detect-wrapper-anomaly.sh` を追加する。SKILL.md Step 6 の failure handling に detector 呼び出しを組み込み、検出結果を Spec の `## Auto Retrospective` へ自動追記することで LLM の注意依存による見落としを防ぐ。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: new file — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: new file — 4 pattern + no-match bats tests
- `skills/auto/SKILL.md`: Step 6 に detector 呼び出しフローを追加; `detect-wrapper-anomaly.sh:*` と `Write` を allowed-tools に追加
- `docs/structure.md`: Process management セクションに detect-wrapper-anomaly.sh エントリ追加; scripts 数 39→40 に更新

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` を作成する — bash 3.2+ 互換 (→ AC1, AC6)
   - Arguments: `--log <path>`, `--exit-code <N>`, `--issue <N>`, `--phase <name>`
   - 4 パターンを `grep -q` で順次マッチ（連想配列不使用、if/elif ブロック形式）
   - パターンマッチ時のみ stdout に markdown 断片を出力（`### Orchestration Anomalies` 行と `### Improvement Proposals` 行の bullet 形式）; マッチなしは空出力
   - 初期 4 パターン（`Could not retrieve PR number`, `Patch lock acquisition timeout`, `ERROR: missing sign-off`, `watchdog: kill and state not reached`）と対応する improvement proposal hint

2. `tests/detect-wrapper-anomaly.bats` を作成する — 各 pattern に対して tmp log fixture を準備し出力を確認 (→ AC2, AC3)
   - `@test` ケース: PR 抽出失敗・lock timeout・DCO 欠落・watchdog kill の各パターン（fixture は BATS_TEST_TMPDIR に一時ファイル作成）
   - マッチなし（空出力）ケース
   - fixture ファイルにパターン文字列を含む行を書き込み、detector の stdout を検証

3. `skills/auto/SKILL.md` を更新する (→ AC4, AC5)
   - allowed-tools frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-wrapper-anomaly.sh:*` と `Write` を追加
   - Step 6 の "If any phase exits with a non-zero exit code:" 直後に以下フローを挿入（既存の manual recovery hand-off と stop/report の前に実行）:
     1. 失敗フェーズの出力を `.tmp/wrapper-out-$NUMBER-$PHASE.log` に Write ツールで保存
     2. `${CLAUDE_PLUGIN_ROOT}/scripts/detect-wrapper-anomaly.sh --log .tmp/wrapper-out-$NUMBER-$PHASE.log --exit-code $EXIT_CODE --issue $NUMBER --phase $PHASE` を Bash で実行
     3. 出力が非空の場合: `detect-config-markers.md` を読んで SPEC_PATH を取得し、Spec ファイル（`$SPEC_PATH/issue-$NUMBER-*.md`）に `## Auto Retrospective` → `### Orchestration Anomalies` / `### Improvement Proposals` として detector 出力を追記し commit+push
     4. `.tmp/wrapper-out-$NUMBER-$PHASE.log` を削除
   - 挿入箇所: "If any phase exits with a non-zero exit code:" の冒頭（"Manual recovery hand-off" 段落より前）

4. `docs/structure.md` を更新する (→ 文書同期)
   - line 30: `39 files` → `40 files` に変更
   - **Process management:** セクション末尾（`scripts/worktree-merge-push.sh` 行の直後）に以下を追加:
     `- \`scripts/detect-wrapper-anomaly.sh\` — detect known failure patterns in shell wrapper output and generate Auto Retrospective markdown fragments`

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/detect-wrapper-anomaly.sh" --> `scripts/detect-wrapper-anomaly.sh` が作成されている
- <!-- verify: file_exists "tests/detect-wrapper-anomaly.bats" --> bats テストが追加されている
- <!-- verify: command "bats tests/detect-wrapper-anomaly.bats" --> bats テストが全件 PASS する
- <!-- verify: grep "detect-wrapper-anomaly.sh" "skills/auto/SKILL.md" --> `/auto` SKILL.md に `scripts/detect-wrapper-anomaly.sh` の参照が追加されている
- <!-- verify: rubric "skills/auto/SKILL.md 'On failure' handling invokes scripts/detect-wrapper-anomaly.sh and appends its output to the Spec's Auto Retrospective when non-empty" --> `/auto` SKILL.md の on-failure flow が detector を呼び出す形に更新されている
- <!-- verify: rubric "scripts/detect-wrapper-anomaly.sh contains at least the four initial patterns: PR extraction failure, patch lock timeout, DCO sign-off missing, watchdog kill, each mapped to a human-readable improvement proposal hint" --> 初期 4 パターンが実装されている

### Post-merge

- 意図的に `run-auto-sub.sh` の PR 抽出を失敗させる環境を作り、`/auto` 実行 → detector が該当パターンを検出 → Spec に追記 → `/verify` で Issue 自動起票されるフローを確認 <!-- verify-type: manual -->

## Notes

- **Step 6 統合先の確定（auto-resolved）**: Issue body の「Changes item 3」は元々「Step 4 の On failure」と記述されていたが、現 SKILL.md の統合的な失敗ハンドラーは Step 6（On Failure: Stop and Report Error）であるため Step 6 への追加に確定。Step 4 内の `On failure` は XL route のサブ Issue 失敗セット管理に限定される（Issue body の Auto-Resolved Ambiguity Points で明記）。
- **`Write` の allowed-tools 追加**: 失敗ログを `.tmp/` に保存するために Write ツールが必要。現在の auto SKILL.md allowed-tools に Write が未登録のため追加が必要。
- **bash 3.2+ 互換**: macOS system bash は bash 3.2 のため、`declare -A`（bash 4+）を使用した連想配列は不可。パターンテーブルは `if/elif grep -q` ブロック形式で実装する。
- **detector の入力**: `--log` はファイルパス。parent session は Bash ツール結果（失敗 wrapper の stdout/stderr）を Write ツールで `.tmp/wrapper-out-$NUMBER-$PHASE.log` に書き出し、detector に渡す。

## Code Retrospective

### Deviations from Design

- 設計通りに実装。特筆すべき逸脱なし。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Review Retrospective

### Spec vs. 実装乖離パターン

特筆すべき乖離なし。受け入れ条件 6 件が全て PASS。ただし、Step 6 の新「Anomaly detection」ブロックと既存の「Manual recovery hand-off」が同一セクションへの書き込みを両方記述しており、手動リカバリーパスでの重複書き込みリスクが生まれていた。この種の「新機能と既存フローの相互作用による曖昧さ」は Issue spec に明示されていなかったため、Code 段階で見落とされた。Spec ではフロー統合時の既存セクションとの相互作用を明示すると今後の実装・レビューで早期発見できる。

### 繰り返し問題

今回は SHOULD 1件・CONSIDER 1件のみで品質は高い。SHOULD 問題（重複書き込みリスク）は「新機能追加時の既存フローとの相互作用チェック」が漏れたケース。verify コマンドでこの種の相互作用を事前検証する rubric を設計段階で書いておくと効果的。

### 受け入れ条件検証困難度

全条件が自動検証可能（file_exists, grep, command/CI参照, rubric）で UNCERTAIN なし。verify コマンドの設計は適切。`rubric` 2件も明確な記述で grader が判断しやすかった。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は Issue body の Auto-Resolved Ambiguity Points（Step 6 統合先）をそのまま引き継いで記述しており、設計意図が明確に文書化されている。
- Post-merge 条件を `verify-type: manual` として E2E フロー確認に割り当てた設計は適切。自動検証できない環境依存フローを正確に分類できている。

#### design
- 設計通りに実装。Spec → 実装間の逸脱なし。
- Review Retrospective で指摘された「新機能と既存フローの相互作用による重複書き込みリスク」は、SKILL.md の Manual recovery hand-off の注釈で対処されている（"if the anomaly detector already detected and appended a known pattern, skip the Orchestration Anomalies / Improvement Proposals append"）。

#### code
- fixup/amend なし、rework なし。コミットは 1 件でクリーンな実装。
- bash 3.2+ 互換制約（連想配列不使用）を Spec Notes で事前文書化し、`if/elif grep -q` ブロック形式を選択した判断は適切。

#### review
- Review で SHOULD 1件・CONSIDER 1件のみ検出。品質は高い。
- SHOULD 問題（重複書き込みリスク）は Code 段階で見落とされていたが、review で発見し実装側で対処済み。

#### merge
- マージは FF で完了。コンフリクトなし。

#### verify
- 全 6 pre-merge 条件が PASS。bats 8/8 PASS、rubric 2件も明確に PASS 判定。
- Post-merge の manual 条件（E2E フロー確認）が未チェックのため `phase/verify` を割り当て。

### Improvement Proposals
- N/A
