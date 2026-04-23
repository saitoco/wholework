# Issue #316: auto: 未知異常に対する recovery sub-agent を追加

## Overview

`/auto` の未知異常対応として、orchestration-recovery sub-agent を新設し、既存の Tier 1 (状態 reconcile) / Tier 2 (既知パターン catalog) と組み合わせた 3 層 recovery 階層を `skills/auto/SKILL.md` Step 6 に統合する。Safety guard (schema 検証・forbidden ops・step 上限) はオーケストレーター側でスクリプト化し、guard 通過後のみ sub-agent の recovery 計画を実行する。

## Changed Files

- `agents/orchestration-recovery.md`: 新規 — recovery diagnostician sub-agent 定義
- `scripts/validate-recovery-plan.sh`: 新規 — recovery plan JSON schema 検証 + forbidden ops ガード — bash 3.2+ 互換
- `tests/orchestration-recovery.bats`: 新規 — validate-recovery-plan.sh の bats 単体テスト
- `skills/auto/SKILL.md`: Step 6 "On Failure" を 3 層階層に拡張、allowed-tools に `validate-recovery-plan.sh:*` と `Task, TaskCreate, TaskUpdate, TaskList, TaskGet` を追加
- `docs/structure.md`: Agents テーブルに orchestration-recovery を追加 (6→7 ファイル)、Scripts に validate-recovery-plan.sh を追加 (40→41 ファイル)

## Implementation Steps

1. **`agents/orchestration-recovery.md` を作成する** (→ acceptance criteria 1, 2)
   - frontmatter: `name: orchestration-recovery`, description (recovery diagnostician for unknown orchestration failures), `tools: Read, Glob, Grep, Bash(git log:*, git status:*, git branch:*, gh issue view:*, gh pr view:*, gh pr list:*, ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*)`, `model: sonnet`
   - Input section: phase name, wrapper exit code, log tail (last 200 lines), reconcile JSON snapshot (`reconcile-phase-state.sh --check-completion` output), issue labels/PR/branch state
   - Processing steps: analyze inputs, consult reconcile state, identify anomaly pattern, produce minimal recovery plan
   - Output section: JSON with keys `action` (one of `retry` | `skip` | `recover` | `abort`), `rationale` (string), `steps` (array of op objects with `op` field)

2. **`scripts/validate-recovery-plan.sh` を作成する** — bash 3.2+ 互換 (→ acceptance criteria 4, 6)
   - 第 1 引数にファイルパス (なければ stdin) で JSON を受け取る
   - `python3` を使って以下を検証:
     - 必須キーの存在: `action`, `rationale`, `steps`
     - `action` の値が `retry` / `skip` / `recover` / `abort` のいずれか
     - `steps` の配列長 ≤ 5
     - 各 step の `op` フィールドに forbidden op が含まれないこと: `force_push`, `reset_hard`, `close_issue`, `merge_pr`, `direct_push_main` (大文字小文字を区別しないサブストリング照合)
   - 有効時 exit 0、無効時 exit 1 (エラーを stderr に出力)

3. **`tests/orchestration-recovery.bats` を作成する** (→ acceptance criteria 5, 6)
   - `@test "orchestration-recovery: valid plan with retry action passes"`
   - `@test "orchestration-recovery: valid plan with abort action passes"`
   - `@test "orchestration-recovery: missing action key fails"`
   - `@test "orchestration-recovery: missing rationale key fails"`
   - `@test "orchestration-recovery: missing steps key fails"`
   - `@test "orchestration-recovery: invalid action value fails"`
   - `@test "orchestration-recovery: forbidden op force_push fails"`
   - `@test "orchestration-recovery: forbidden op reset_hard fails"`
   - `@test "orchestration-recovery: step count exceeds limit fails"`
   - `@test "orchestration-recovery: empty steps array passes"`
   - bash 3.2+ 互換 (mapfile 不使用、連想配列不使用)

4. **`skills/auto/SKILL.md` Step 6 を拡張する** (→ acceptance criteria 3, 4)
   - 現行の Step 6 "On Failure: Stop and Report Error" を以下の 3 層階層に置き換える:
     - **Tier 1 (Observe)**: `reconcile-phase-state.sh <phase> <issue> --check-completion` — `matches_expected: true` ならば success に override して続行
     - **Tier 2 (Known pattern)**: `detect-wrapper-anomaly.sh` でパターン検出 + `modules/orchestration-fallbacks.md` catalog を Read and follow — 既知パターン一致時は catalog の recovery steps を適用
     - **Tier 3 (Unknown)**: orchestration-recovery sub-agent を Task で spawn し、phase/exit-code/log-tail/reconcile-snapshot を渡す。output を `.tmp/recovery-plan-$NUMBER-$PHASE.json` に書き込み、`validate-recovery-plan.sh` で検証。検証失敗または `action=abort` の場合は従来の stop-and-report にフォールバック。`action=retry` → 失敗 phase を 1 回再実行、`action=skip` → 次フェーズへ進む、`action=recover` → steps を順番に実行
   - Safety guard (orchestrator 側で inline 記述):
     - output schema 検証: `validate-recovery-plan.sh` の終了コードで判定
     - forbidden ops リスト: force push, git reset --hard, issue close, pr merge, main 直 push
     - step 数上限: ≤ 5 (validate-recovery-plan.sh で enforce)
   - frontmatter `allowed-tools` の Bash セクションに `${CLAUDE_PLUGIN_ROOT}/scripts/validate-recovery-plan.sh:*` を追加
   - frontmatter built-in tools に `Task, TaskCreate, TaskUpdate, TaskList, TaskGet` を追加 (/issue・/review の sub-agent spawn パターンに合わせる)

5. **`docs/structure.md` を更新する** (step 1 完了後) (→ SHOULD: agent addition doc sync)
   - Agents テーブルに行を追加: `orchestration-recovery | agents/orchestration-recovery.md | Recovery diagnostician for unknown orchestration failures`
   - Directory Layout の `agents/` コメントを `6 files` → `7 files` に変更
   - Scripts > Process management グループに `scripts/validate-recovery-plan.sh` の説明行を追加
   - Directory Layout の `scripts/` コメントを `40 files` → `41 files` に変更

## Verification

### Pre-merge

- <!-- verify: file_exists "agents/orchestration-recovery.md" --> `agents/orchestration-recovery.md` sub-agent 定義が存在する
- <!-- verify: rubric "agents/orchestration-recovery.md frontmatter defines name, description, and read-only tools, and the system prompt specifies the input fields (phase, exit code, log tail, reconcile state snapshot) and the output JSON schema (action in {retry, skip, recover, abort}, rationale, steps)." --> sub-agent の入出力 schema が定義されている
- <!-- verify: rubric "skills/auto/SKILL.md Step 6 (On Failure) implements 3-tier recovery: Tier 1 uses reconcile-phase-state.sh for state check, Tier 2 looks up orchestration-fallbacks.md catalog (with detect-wrapper-anomaly.sh as pattern detector), Tier 3 spawns the orchestration-recovery sub-agent, and action dispatch falls back to the original stop-and-report flow on abort or validation failure." --> 階層的 recovery が `/auto` SKILL.md Step 6 に組み込まれている
- <!-- verify: rubric "skills/auto/SKILL.md Step 6 describes orchestrator-side enforcement of safety guards: output schema validation, forbidden ops list (including force push, git reset --hard, issue close, pr merge), and a step-count limit for the recovery plan." --> Safety guard (schema 検証 + forbidden ops + step 上限) が orchestrator 側で定義されている
- <!-- verify: file_exists "tests/orchestration-recovery.bats" --> bats テストファイルが存在する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが CI で PASS する

### Post-merge

- 未知パターンの異常 (catalog 未登録、reconcile expected 非一致) を意図的に発生させた状態で `/auto` を実行し、sub-agent が diagnosis + recovery plan を生成し、それに従って続行されることを確認
- Safety guard が作動し、forbidden op (force push / reset --hard / issue close / pr merge 等) を含む plan が拒否されて Step 6 従来処理にフォールバックすることを確認

## Notes

**allowed-tools 更新 (step 4):**
- `Task, TaskCreate, TaskUpdate, TaskList, TaskGet` の追加は `/issue` および `/review` SKILL.md と同じ sub-agent spawn パターンに準拠する

**Tier 2 → Tier 3 遷移:**
- Tier 2 は `detect-wrapper-anomaly.sh` を pattern detector として使用し、`orchestration-fallbacks.md` を LLM "Read and follow" パターンで参照する
- Tier 2 で一致なし (unknown pattern) の場合のみ Tier 3 に進む

**recovery sub-agent は diagnostician のみ:**
- sub-agent は状態を読み取るが、ファイルシステムへの書き込みや git/GitHub 操作は行わない
- recovery steps の実行はすべて親オーケストレーター (SKILL.md) が validate-recovery-plan.sh 通過後に実施する

**validate-recovery-plan.sh の JSON 入力形式:**
- 第 1 引数にファイルパスを渡す形式が標準 (例: `validate-recovery-plan.sh .tmp/recovery-plan.json`)
- 引数なしの場合は stdin から読み取る
- JSON parsing に `python3` を使用 (CI と macOS で利用可能)

**bats テストの自己参照 exclusion:**
- `tests/orchestration-recovery.bats` は forbidden op 文字列 (`force_push` 等) をテストフィクスチャとして含む
- `validate-recovery-plan.sh` は JSON を入力とするため、.bats ファイル自体を処理することはなく自己参照問題は発生しない

## Spec Retrospective

(Spec フェーズで記録済み)

## Code Retrospective

### Deviations from Design

- bats テストで `<(echo "$plan")` (process substitution) から `$BATS_TEST_TMPDIR/plan.json` への temp file パターンに変更: 既存テストの bats パターンと合わせて信頼性を高めるため

### Design Gaps/Ambiguities

- なし

### Rework

- なし

## Review Retrospective

### Spec vs. 実装乖離パターン

特になし。実装はSpecの設計スケッチに忠実で、allowed-tools/model の選定、input/output schema、step op vocabulary も spec 通りだった。

### 繰り返し発生 issue

`Forbidden Expressions check` CI FAILURE が発生。原因: `skills/auto/SKILL.md` Step 6 の新規追加テキストに廃止用語 "/auto" が混入していた。実装時に `check-forbidden-expressions.sh` のローカル実行が省略されたと思われる。
改善提案: `/code` 完了後にローカルで `bash scripts/check-forbidden-expressions.sh` を実行するステップを実装チェックリストに追加することで、CI では初めて検知される類の違反を事前に防げる。

### 受け入れ条件検証難易度

`rubric` 系の verify コマンドが多く、safe mode では全て AI 判定。今回は実装が spec に忠実だったため実質的な問題はなかった。
verify コマンドを `file_contains "skills/auto/SKILL.md" "Tier 3 (Unknown): Recovery Sub-Agent"` などの `file_contains` 型に変換できれば、将来的に自動判定精度が上がる。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec ファイルは `docs/spec/issue-316-orchestration-recovery-agent.md` として作成済み。Issue body の Scope (Design Sketch) を忠実に反映しており、acceptance criteria と実装ステップの対応が明確だった。
- `## Spec Retrospective` セクションは存在するが内容が "(Spec フェーズで記録済み)" のみで空。具体的な観察が欠けているが、設計の質は問題なかった。

#### design
- 3 層 recovery 階層（Tier 1/2/3）の設計は Issue body の設計スケッチと一致し、安全ガード（forbidden ops・step上限）の責務分離も明確だった。
- bats テストでの `<(echo "$plan")` → `$BATS_TEST_TMPDIR/plan.json` パターン変更は既存テストとの整合性のための小さな逸脱であり、設計上の問題ではない。

#### code
- 禁止用語 "/auto" の混入 (fix commit あり: `fix: replace deprecated term '/auto' in skills/auto/SKILL.md Step 6`) が唯一のコードリワーク。
- fixup! / amend パターンは観察されず、全体的に実装品質は高かった。

#### review
- Review コメントにより forbidden expressions violation が検知され修正 commit が追加された。Review が期待通りに機能した。
- rubric ベースの verify コマンドが多いため、pre-merge の safe mode review では全て AI 判定に依存する。精度向上の余地あり（`file_contains` 型への部分置換）。

#### merge
- PR #340 が単一 merge commit (`04a42d6`) でクリーンに main に統合された。コンフリクトなし。

#### verify
- 全 6 条件が PASS。CI（`Run bats tests`）も pass を確認。
- Post-merge の `verify-type: manual` 条件 2 件が残存するため `phase/verify` に遷移。

### Improvement Proposals
- rubric 型 verify コマンドは自動判定精度が低い。実装がどのファイルのどのセクションに書かれるか事前にわかる場合は、`file_contains` や `section_contains` を補足的に追加することで `rubric` の精度を補完できる。例: `<!-- verify: file_contains "skills/auto/SKILL.md" "Tier 3 (Unknown): Recovery Sub-Agent" -->` を条件3に追加する。
- `/code` フェーズ完了後に `bash scripts/check-forbidden-expressions.sh` をローカル実行するステップを実装チェックリスト（または `/code` SKILL.md）に追加し、CI でのみ検知される forbidden expressions 違反を事前に防ぐ。
