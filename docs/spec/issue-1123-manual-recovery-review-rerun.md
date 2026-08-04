# Issue #1123: recoveries: manual-recovery-review-rerun

## Overview

`manual-recovery-review-rerun` が `docs/reports/orchestration-recoveries.md` に閾値 `3` を超えて記録された。復旧手順は 3 件とも同一 (親セッションが `Skill(wholework:review)` を直接実行) だが、そこに至る原因は 2 系統に分かれる。

- **Cause A** (#1061, #1069): 再喚起保証のない実行文脈で「完了通知を待つ」を選び、ターンが silent no-op で終わる。個別トリガー (#1097 の bats バックグラウンド実行 / #1103 の Workflow ツール) ごとには起票済みだが、**機構自体を 1 箇所で禁止する横断規約がない**
- **Cause B** (#1055): `scripts/check-verify-dirty.sh` の非ブロック分類が `docs/sessions/` 配下しか認識せず、並行セッションが `scripts/` や `tests/` を編集していると無関係な `/auto` の全フェーズが hard error でブロックされる

あわせて、頻度検出が復旧手段 (recovery type) でグルーピングしているため原因の異なる事象が同一 symptom に合流する問題も対象に含める。

## Reproduction Steps

**Cause A** (#1069 / PR #1077):

1. `.wholework.yml` に `capabilities.workflow: true` を設定する
2. Size M/L の Issue に対し `/auto` を実行する (review は `--full` になる)
3. `run-review.sh` が `claude -p` で `/review` を起動する
4. `skills/review/SKILL.md` Step 10 が Workflow パスに入り、Workflow ツールを起動して完了通知を待つ姿勢でターンを終える
5. exit 0 / PR コメント 0 件 / レビュー 0 件のまま `reconcile-phase-state` が `matches_expected:false` を返す

**Cause B** (#1055):

1. 別セッションが親リポジトリ main で `scripts/run-spec.sh` を編集し、未コミットのまま作業を継続する
2. 無関係な Issue #1055 に対し `/auto` を実行する
3. `run-review.sh` の dirty guard が `bash scripts/check-verify-dirty.sh <PR番号>` を呼ぶ
4. `scripts/run-spec.sh` が `parent-main` に分類され exit 1 → `Error: parent main has uncommitted changes. Resolve before proceeding.` で **review を起動せずに終了**する

**Cause B の派生形** (#1135):

1. code phase が silent no-op で終わり auto-retry 1/3 が発火する
2. retry 前処理の `check-verify-dirty.sh` が、leaf 自身が親リポの Spec に書いた Consumed Comments 追記 1 行 (`docs/spec/issue-1135-*.md`) を検出する
3. 自 Issue の Spec は `has_other=true` 側に落ちるため exit 1 → auto-retry がブロックされ wrapper exit 1

## Root Cause

### Cause A: 規約の適用条件が個別トリガー単位で書かれている

前景実行を要求する注記が 3 箇所に重複して存在し、いずれも適用条件を **headless `claude -p`** に限定している。

| 箇所 | 由来 | 適用条件の記述 |
|------|------|----------------|
| `modules/test-runner.md` Step 2 の Note | #1097 | 「非対話モード (headless `claude -p`)」 |
| `skills/review/SKILL.md` Non-Interactive Mode Behavior の Foreground 箇条 | #1097 | 「headless `claude -p` プロセス」 |
| `skills/code/SKILL.md` Behavioral Change Detection | #994 | 「headless `claude -p` プロセス」 |

真の失敗条件は「headless であること」ではなく **harness による再喚起 (re-invocation) が保証されないこと**である。#1142 では fork 実行された `/review` が同型の silent no-op を起こしており、#1103 では Workflow ツールが同じ機構で失敗している。適用条件を headless に限定した規約は、新しい実行サーフェスが増えるたびに抜け穴を作る。

### Cause B: 「自分に関係するファイル」の定義が存在しない

`scripts/check-verify-dirty.sh` L94-115 の分類は 4 分類 (`self-worktree` / `other-worktree` / `other-session` / `parent-main`) で、非ブロック側の判定根拠がすべて **パスプレフィックス** である。

- `.claude/worktrees/` 配下 → worktree 由来と判定できる
- `docs/sessions/*-*/` 配下 → 別セッションの作業ログと判定できる
- それ以外 → すべて `parent-main` に落ちる

しかし phase は worktree 内で作業するため、親リポ main の dirty file は構造的に「別セッションの作業」か「自セッションの wrapper による Spec 書き戻し」のいずれかである。`scripts/foo.sh` のような一般パスに対して帰属を判定する根拠がないため、前者が hard error になり、後者 (`docs/spec/issue-N-*.md`) は L128 の `has_other=true` に落ちて同じく hard error になる。

### 頻度検出: グルーピング単位が復旧手段のみ

`_write_manual_recovery_to_recoveries_log()` (`scripts/run-auto-sub.sh` L292-) は `### Diagnosis` に定型文 1 行しか書けず、`--write-manual-recovery ISSUE PHASE RECOVERY_TYPE [EXIT_CODE]` に原因を渡す引数がない。`scripts/collect-recovery-candidates.sh` は H2 ヘッダの symptom-short (`manual-recovery-${recovery_type}`) だけで集計するため、原因の異なる事象が 1 つの Issue に合流する。

## Changed Files

- `modules/execution-context.md`: 「Re-invocation Guarantee and Notification-Dependent Waiting」節を新規追加 (再喚起保証の定義 / 保証のない実行サーフェス一覧 (exhaustive) / MUST 規約 / 根拠 / 先行事例)。Callers 節を更新
- `modules/test-runner.md`: Step 2 の非対話モード Note を、適用条件「headless `claude -p`」から「再喚起保証のない実行文脈全般」に一般化し、`modules/execution-context.md` の新節への参照を追加
- `skills/review/SKILL.md`: Non-Interactive Mode Behavior の Foreground 箇条に同参照を追加 (#1097 の対象ファイル)。Step 1 相当の dirty guard 記述はこのファイルにないため他の変更なし
- `skills/review/workflow-guidance.md`: Pre-flight 節に、Workflow ツール自体が再喚起保証のない実行文脈である旨と `modules/execution-context.md` の新節への参照を追加 (#1103 の対象ファイル)
- `skills/code/SKILL.md`: Behavioral Change Detection の前景実行注記に同参照を追加 (#994 の先行事例。3 箇所の重複記述を単一 SSoT に束ねるため)
- `scripts/check-verify-dirty.sh`: `parent-main` 分岐を細分化し `self-spec` / `own-issue-scope` / `foreign-session` の 3 分類を追加。帰属判定は自 Issue の Spec `## Changed Files` マニフェストを根拠とする。Spec 不在時は現行の全ブロック挙動にフォールバック — bash 3.2+ 互換 (連想配列・`mapfile` 不使用)
- `scripts/run-review.sh`: `_REVIEW_ISSUE` の解決 (L76 付近の `gh-extract-issue-from-pr.sh` 呼び出し) を dirty guard ブロック (L34 付近) より前に移動し、`check-verify-dirty.sh` に `"${_REVIEW_ISSUE:-$PR_NUMBER}"` を渡す — bash 3.2+ 互換
- `scripts/run-merge.sh`: `_MERGE_ISSUE` について同様の移動と引数差し替え (L67 付近 → L25 付近より前) — bash 3.2+ 互換
- `scripts/run-auto-sub.sh`: `--write-manual-recovery` に `--cause SLUG` / `--diagnosis TEXT` オプションを追加。`_write_manual_recovery_to_recoveries_log()` は `### Diagnosis` に `- cause: <slug>` 行と自由記述行を出力し、`_find_known_recoveries_issue` にはグループキー (`symptom` または `symptom/cause`) を渡す。`_write_manual_recovery_to_spec()` にも `- **Cause**: <slug>` 行を追加。オプション未指定時は現行の定型文を維持 — bash 3.2+ 互換
- `scripts/collect-recovery-candidates.sh`: エントリ本文の `- cause: <slug>` 行を読み、グループキーを `<symptom-short>/<cause-slug>` に合成する。cause 行がないエントリは従来どおり `<symptom-short>` のまま。出力形式 (`<key>\t<count>`) は不変 — bash 3.2+ 互換
- `tests/verify-dirty-detection.bats`: 既存テスト `"related spec dirty: exit 1 when related spec file (same issue) is dirty"` を self-spec 非ブロック (exit 0) に更新。新規 3 ケース (並行セッション由来 / 自 Issue Changed Files 記載 / 自 Issue の Spec 残骸) と Spec 不在フォールバックの回帰ケースを追加
- `tests/collect-recovery-candidates.bats`: cause 付きエントリのグループ分離テストと、cause 行なしエントリの後方互換テストを追加
- `tests/run-review.bats`: `$MOCK_DIR` に `gh-extract-issue-from-pr.sh` のモックを追加 (`WHOLEWORK_SCRIPT_DIR` モック追加チェック — 現在ヘッダコメント L5 に記載があるのにモック実体が存在せず、移動後の解決経路が未カバーになるため)
- `skills/verify/SKILL.md`: Step 1 の exit 1 説明「related or non-spec dirty files present」を新分類に合わせて更新。recoveries-auto-fire 節 (Step の (b) Cluster by cause) に、グループキーが cause を含む場合は事前グルーピング済みである旨を追記
- `docs/structure.md`: L239 `check-verify-dirty.sh` の分類説明 (4 分類 → 6 分類)、L186 `collect-recovery-candidates.sh` のグルーピング説明を更新
- `docs/ja/structure.md`: L231 / L179 の対応箇所を同期 (`docs/translation-workflow.md` の Sync Procedure に従う)
- `docs/workflow.md`: L121 の `--write-manual-recovery ISSUE PHASE respawn [EXIT_CODE]` シグネチャに `--cause` / `--diagnosis` を追記
- `docs/ja/workflow.md`: L114 の対応箇所を同期
- `docs/tech.md`: L56 の `--write-manual-recovery` 記述に cause 欄への言及を追加
- `docs/ja/tech.md`: L47 の対応箇所を同期
- `docs/reports/orchestration-recoveries.md`: [変更不要] 既存 4 エントリは append-only の履歴記録であり、cause 行の遡及付与は行わない (cause 行のないエントリは Step 7 で従来キーのまま集計される)
- `docs/reports/external-kill-investigation.md`: [変更不要] `--write-manual-recovery` に言及するが、記述内容は本 Issue の変更で無効にならない履歴レポート (grep 確認済み)

## Implementation Steps

1. `modules/execution-context.md` に「Re-invocation Guarantee and Notification-Dependent Waiting」節を追加する (→ AC1)
   - 再喚起保証の定義: バックグラウンドタスクの完了通知は harness が対話セッションを再喚起することで届く。再喚起が保証されるのは **対話セッションでの直接実行のみ**
   - 保証のない実行サーフェス一覧 **(exhaustive)**: headless `claude -p` (`run-*.sh` 経由の fork context) / fork 実行された Skill (`Skill launched as forked execution`) / Workflow ツールのパス / それらの内部から起動されたサブエージェント・バックグラウンド Bash
   - MUST 規約: これらの文脈では完了通知に依存する待機でターンを終えてはならない。`run_in_background: true`、Workflow ツール、完了前に返る Agent/Task ディスパッチのいずれも対象。前景で同期実行する
   - 根拠: 通知が原理的に届かないため、フェーズは「遅延」ではなく「恒久的に未完了 (silent no-op)」になる
   - 判定不能時の既定: 直接の対話実行だと確証できない場合は保証なし側に倒す
   - 先行事例: #994 (`/code` の bats) / #1097 (`/review` の bats) / #1103 (Workflow ツール) / #1142 (fork 実行の `/review`)
   - Callers 節に本節を読む skill/module を列挙する
2. Step 1 の節を単一 SSoT として、既存の前景実行注記 4 箇所から参照する (after 1) (→ AC1)
   - `modules/test-runner.md` Step 2 の Note: 適用条件を「再喚起保証のない実行文脈全般」に書き換え、`modules/execution-context.md` の新節を参照させる
   - `skills/review/SKILL.md` の Foreground 箇条、`skills/review/workflow-guidance.md` の Pre-flight 節、`skills/code/SKILL.md` の Behavioral Change Detection 注記に同参照を追加する
   - SKILL.md 本文には半角感嘆符と 3 連バッククォートを入れない (`scripts/validate-skill-syntax.py` 制約)
3. `scripts/check-verify-dirty.sh` の `parent-main` 分岐 (現行 L99-115) を細分化する (→ AC2)
   - `docs/spec/issue-${NUMBER}-*.md` に一致 → `self-spec` を stderr に出力し **非ブロック**。根拠: 親リポ main のこのパスは leaf 自身の書き戻し (Consumed Comments / Auto Retrospective 追記) 以外に発生源がない
   - それ以外の parent-main ファイル → 自 Issue の Spec (`docs/spec/issue-${NUMBER}-*.md`) の `## Changed Files` 節からパストークンを抽出し、記載があれば `own-issue-scope` (**ブロック**、exit 1)、なければ `foreign-session` (**非ブロック**、警告のみ)
   - 判定根拠をスクリプト冒頭コメントに明記する: 「自分に関係するファイル = 自 Issue の Spec が `## Changed Files` に列挙したパス」
   - Spec が存在しない、または `## Changed Files` 節がない場合は帰属判定不能として現行挙動 (全 parent-main をブロック) にフォールバックし、理由を stderr に出す
   - exit code の意味 (0 / 1 / 2) と `docs/spec/issue-M-*.md` (M != N) の exit 2 経路は不変に保つ
   - パス抽出は `awk` + `grep` ベースで実装する (bash 3.2 に連想配列・`mapfile` がないため)
4. `scripts/run-review.sh` / `scripts/run-merge.sh` で、PR 番号ではなく Issue 番号を dirty guard に渡す (parallel with 3) (→ AC2)
   - 両ファイルとも `gh-extract-issue-from-pr.sh` による Issue 番号解決を既に持つが、dirty guard ブロックより **後ろ** にあるため、現状は PR 番号が渡っている
   - 解決行 (`_REVIEW_ISSUE=` / `_MERGE_ISSUE=`) を dirty guard ブロックの直前へ移動し、`check-verify-dirty.sh` の引数を `"${_REVIEW_ISSUE:-$PR_NUMBER}"` / `"${_MERGE_ISSUE:-$PR_NUMBER}"` に差し替える
   - 解決失敗時は従来どおり PR 番号にフォールバックする (Step 3 の Spec 不在フォールバックが働き、現行挙動になる)
5. `tests/verify-dirty-detection.bats` を更新する (after 3, 4) (→ AC3)
   - 既存テスト `"related spec dirty: exit 1 when related spec file (same issue) is dirty"` を self-spec 非ブロック (exit 0 / `classify=self-spec`) に更新する — 意図的な挙動変更
   - 新規 (1) 並行セッション由来: 自 Issue の Spec の `## Changed Files` に載っていない `scripts/foo.sh` が dirty → exit 0 / `classify=foreign-session`
   - 新規 (2) negative case: 自 Issue の Spec の `## Changed Files` に載っている `scripts/run-review.sh` が dirty → exit 1 / `classify=own-issue-scope`
   - 新規 (3) 自 Issue の Spec 残骸: `docs/spec/issue-123-foo.md` が dirty → exit 0 / `classify=self-spec`
   - 回帰: Spec 不在で `scripts/foo.sh` が dirty → exit 1 (フォールバック維持。既存テスト L164 と同条件)
   - `tests/run-review.bats` の `$MOCK_DIR` に `gh-extract-issue-from-pr.sh` モックを追加する
6. `scripts/run-auto-sub.sh` の `--write-manual-recovery` に原因情報を渡せるようにする (parallel with 3, 4) (→ AC4)
   - 引数解析を拡張し `--cause SLUG` と `--diagnosis TEXT` を受け取る。既存の位置引数 `ISSUE PHASE RECOVERY_TYPE [EXIT_CODE]` の順序と意味は変えない
   - `_write_manual_recovery_to_recoveries_log()` の `### Diagnosis` 出力を、cause 指定時は `- cause: <slug>` 行 + 自由記述行に、未指定時は現行の定型文 1 行にする
   - H2 ヘッダ (`## <date>: manual-recovery-<recovery_type>`) と `_is_duplicate()` の正規表現は変更しない (既存 4 エントリと `tests/collect-recovery-candidates.bats` の fixture への波及を避ける)
   - `_find_known_recoveries_issue` に渡す値をグループキー (`symptom` または `symptom/cause`) にする
   - `_write_manual_recovery_to_spec()` にも cause 指定時のみ `- **Cause**: <slug>` 行を追加する
7. `scripts/collect-recovery-candidates.sh` のグルーピング単位を cause 対応にする (after 6) (→ AC4)
   - エントリ本文 (H2 ヘッダ以降、次の H2 まで) を走査し `^- cause: (\S+)` を抽出する
   - グループキーを `<symptom-short>/<cause-slug>` に合成する。cause 行がないエントリは `<symptom-short>` のまま
   - `起票済み` 除外と `--issues-json` 重複チェックはグループキー単位で行う (原因が異なれば別 Issue として検出されるのが意図した挙動)
   - 出力形式 `<key>\t<count>` と `--threshold` の意味は不変
8. `tests/collect-recovery-candidates.bats` にテストを追加する (after 7) (→ AC4, AC5)
   - 同一 symptom で cause が 2 種類のエントリ群を fixture にし、それぞれ別キーで集計されること (閾値未満なら出力されないこと) を検証する
   - cause 行のないエントリのみの fixture で既存出力が変わらないこと (後方互換) を検証する
   - 既存 5 テストが変更なしで PASS することを確認する
9. `skills/verify/SKILL.md` を更新する (after 3, 7) (→ AC2, AC4)
   - Step 1 の exit 1 説明を新分類 (自 Issue の Changed Files に載る dirty file、または帰属判定不能な dirty file) に合わせて更新する
   - recoveries-auto-fire 節の (b) Cluster by cause に、グループキーが `/` 区切りで cause を含む場合はエントリが既に原因単位に分離済みである旨を追記する
10. Steering Docs と `docs/ja/` ミラーを同期する (after 3, 6, 7) (→ AC2, AC4)
    - `docs/structure.md` L239 / L186、`docs/workflow.md` L121、`docs/tech.md` L56 を更新する
    - `docs/translation-workflow.md` の Sync Procedure に従い `docs/ja/structure.md` L231 / L179、`docs/ja/workflow.md` L114、`docs/ja/tech.md` L47 を同期する (code fence 数の一致確認を含む)

## Verification

### Pre-merge

- <!-- verify: rubric "Cause A (再喚起保証のない実行文脈で完了通知に依存する待機を選ぶ) について、個別トリガーごとの対処 (#1097 の bats / #1103 の Workflow) を超えた横断的な規約が定義されている。具体的には、対話セッションでの直接実行以外の実行文脈 (headless の claude -p、fork agent、Workflow ツールなど、再喚起保証のない文脈全般) では完了通知に依存する待機を使わない旨が全 skill から参照される単一の箇所 (modules/ 配下) に記述され、#1097 / #1103 の対象ファイルからそこを参照する形になっている" --> Cause A に対する横断規約が単一箇所に定義され、既存 Issue の対象ファイルから参照されている
- <!-- verify: rubric "Cause B について、scripts/check-verify-dirty.sh の other-session 分類が docs/sessions/ 配下以外にも拡張されている、または run-*.sh 側で自 Issue と無関係な dirty file を hard error にしない判定が実装されている。いずれの場合も、判定根拠 (どのファイルを自分に関係すると見なすか) が明記されている。加えて、自 Issue の Spec (docs/spec/issue-$N-*.md) に leaf 自身が残した残骸 (例: Consumed Comments 追記) は『自 Issue に関係する dirty file』ではあるが hard error にはしない、という自 Issue帰属内での区別も設計に含まれている" --> Cause B の dirty guard がセッション/Issue 帰属を考慮する形になっている
- <!-- verify: rubric "tests/ 配下に、(1) 並行セッション由来の dirty file が存在する状況で対象フェーズがブロックされないことを検証するテスト、(2) 自 Issue に関係する dirty file (典型的には自 Issue とは無関係な変更) では従来どおりブロックされること (negative case) を検証するテスト、(3) 自 Issue の Spec 残骸 (Consumed Comments 追記など) ではブロックされないことを検証するテストの3種類が存在する" --> Cause B の positive / negative / 自 Issue の Spec 残骸の3ケースのテストが追加されている
- <!-- verify: rubric "docs/reports/orchestration-recoveries.md の Diagnosis 欄、または collect-recovery-candidates.sh のグルーピング単位が、復旧手段 (recovery type) だけでなく原因を区別できる形に改善されている。--write-manual-recovery が定型文しか書けない現状の制約への対処を含む" --> 頻度検出が原因を区別できるようになっている
- <!-- verify: command "bats tests/collect-recovery-candidates.bats" --> `tests/collect-recovery-candidates.bats` が PASS する

### Post-merge

- 並行セッションが main に未コミット変更を持つ状態で `/auto` を実行し、フェーズがブロックされずに完走することを確認する
- 新規の `manual-recovery-review-rerun` エントリが `docs/reports/orchestration-recoveries.md` に追加されないことを観察する

## Tool Dependencies

### Bash Command Patterns
- なし (既存の `allowed-tools` で充足。新規 `scripts/*.sh` の追加はないため allowed-tools impact chain check はスキップ)

### Built-in Tools
- なし (`Read` / `Write` / `Edit` / `Grep` / `Glob` はいずれも登録済み)

### MCP Tools
- なし

## Uncertainty

- **`run-review.sh` / `run-merge.sh` が dirty guard に PR 番号を渡している**: Spec マニフェスト方式は Issue 番号をキーにするため、PR 番号のままでは #1055 の当該フェーズ (review) が救済されない
  - **検証方法**: コード確認済み — `scripts/run-review.sh` L36 は `"${PR_NUMBER}"`、Issue 番号を解決する `_REVIEW_ISSUE` は L76 で dirty guard より後。`scripts/run-merge.sh` も同型 (L27 / L67)
  - **影響範囲**: Implementation Step 4 として解決行の移動を組み込み済み。解決失敗時は PR 番号フォールバック → Step 3 の Spec 不在フォールバックにより現行挙動に縮退する
- **`_is_duplicate()` の 24h 重複抑止が cause を見ない**: 同一 issue + phase で 24h 以内に別 cause の記録が来た場合、後発が抑止される
  - **検証方法**: `scripts/run-auto-sub.sh` の `_is_duplicate()` 実装確認済み (symptom + `- Issue #N, phase: P` の context 行で照合)
  - **影響範囲**: Implementation Step 6。cause を重複判定条件に含めるかは実装時判断とし、含めない場合は現行の抑止挙動を維持する (同一 issue/phase で 24h 以内に別原因が発生する頻度は低い)
- **Spec の `## Changed Files` が不完全な場合の縮退**: Changed Files の記載漏れは本リポジトリで繰り返し観測されている (#771 / #770 / #775)。記載漏れのあるファイルが並行セッションで dirty のとき `foreign-session` と判定され、ブロックされずに進む
  - **検証方法**: 設計上の縮退方向の確認のみ (実行時検証なし)
  - **影響範囲**: Implementation Step 3。縮退方向は「ブロックしない」側であり、Cause B の是正目的と整合する。実害が出た場合は worktree マージ時のコンフリクト検出で捕捉される

## Notes

- **Cause A 規約の設置先** — 自動解決: 新規モジュールを作らず `modules/execution-context.md` に追記する。理由: 同ファイルは既に実行コンテキストの SSoT であり `docs/tech.md` / `docs/structure.md` から参照済み。新規モジュール作成は `docs/structure.md` と `docs/ja/structure.md` のモジュール表・カウント更新を伴い、実行コンテキストの SSoT が 2 分割される。他の候補 (`modules/test-runner.md` への集約) は、Workflow ツールがテスト実行と無関係なため適用範囲を表現できない
- **Cause B の帰属判定根拠** — 自動解決: 自 Issue の Spec `## Changed Files` マニフェストを採用する。理由: AC2 が「判定根拠 (どのファイルを自分に関係すると見なすか) が明記されている」ことを要求しており、パスプレフィックスの許可リスト拡張方式では「自分に関係する」の定義そのものが書けない。全 parent-main を非ブロック化する案は AC3 の negative case を満たせない
- **AC4 のグルーピングキー表現** — 自動解決: H2 ヘッダの symptom-short は変えず、`### Diagnosis` 内の `- cause: <slug>` 行を集計側で読み `<symptom-short>/<cause-slug>` に合成する。理由: H2 ヘッダ形式を変えると `_is_duplicate()` の正規表現・`docs/reports/orchestration-recoveries.md` の既存エントリ・`tests/collect-recovery-candidates.bats` の既存 fixture すべてに波及する。Diagnosis 行の追加は追記のみで後方互換
- **既存テストの意図的な破壊的更新**: `tests/verify-dirty-detection.bats` の `"related spec dirty: exit 1 when related spec file (same issue) is dirty"` は「自 Issue の Spec は blocking」と規定しており、AC2 / AC3 の第 3 ケースと正面から矛盾する。Implementation Step 5 で exit 0 に更新する
- **セパレータに `/` を用いる理由**: `scripts/collect-recovery-candidates.sh` L89 / L106 は H2 ヘッダ末尾の括弧付きサフィックス (`sed 's/ ([^)]*) *$//'`) を除去する。グループキーに `(cause: X)` 形式を使うとこの除去と衝突するため、括弧を含まない `/` 区切りにする
- **`skills/verify/SKILL.md` の recoveries-auto-fire が生成する Issue タイトル**は `recoveries: {group-key}` であり、cause 付きキーでは `recoveries: manual-recovery-review-rerun/dirty-guard` になる。既存 Issue タイトル (`recoveries: manual-recovery-review-rerun`) との `grep -F` 部分一致は成立しないため、原因が異なる事象は新規 Issue として起票される — これが AC4 の意図した挙動である
- **Steering Docs sync candidate**: `docs/structure.md` / `docs/ja/structure.md` は `check-verify-dirty.sh` の分類数と `collect-recovery-candidates.sh` のグルーピング説明を散文で持つ。`docs/workflow.md` / `docs/tech.md` とその `docs/ja/` ミラーは `--write-manual-recovery` のシグネチャを散文とコード片の双方で持つため、両形式を確認すること
- **`.claude/` 配下のファイル変更はなし** — `git add -f` の注記は不要
- **バージョン依存の新規外部パッケージ追加はなし** — 依存バージョン事前確認はスキップ
- **クレデンシャル / セキュリティポリシー照合**: 本 Issue は秘匿情報の保管・CI シークレット・アクセス制御を扱わないためスキップ

## Consumed Comments

| login | authorAssociation | trust tier | 要旨 | URL |
|-------|-------------------|-----------|------|-----|
| saito | MEMBER | first-class | `/issue 1123 --non-interactive` のリファインメント記録。AC1 の適用条件を fork / Workflow まで拡張し、AC2 / AC3 に自 Issue の Spec 残骸ケースを追加した旨。Background の各記述はコードベースと一致を確認済み (警告なし) | https://github.com/saitoco/wholework/issues/1123#issuecomment-5175675112 |

cutoff (`phase/*` ラベルの最終付与時刻): `2026-08-04T06:58:48Z`。cutoff 以前の 3 件 (2026-07-31 ×2 / 2026-08-04 ×1) は上記コメントにより Issue 本文へ統合済みで、本 Spec では Root Cause と Notes の判断根拠として参照した。cross-phase marker (`verify-fail` / `preview-ac-unverified`) は 0 件。

### code phase (cutoff: `2026-08-04T07:20:53Z`)

No new comments since last phase.

## issue retrospective

`/issue 1123 --non-interactive` によるリファインメントを実施した。

### 実施内容

- **Step 5 (Background Factual Claim Verification)**: Background 内の `run-review.sh` / `scripts/check-verify-dirty.sh` (`other-session` 分類が `docs/sessions/` 配下のみを認識する記述) / `collect-recovery-candidates.sh` / `run-auto-sub.sh --write-manual-recovery` の各記述をコードベースと照合し、いずれも一致を確認 (警告なし)。
- **Step 8/9 (Auto-Resolved Ambiguity Points / Issue Body 更新)**: 過去 3 件のコメント (2026-07-31 ×2, 2026-08-04) で既にユーザーが決定していた 2 点をAC本文へ統合した:
  1. AC1 (Cause A 横断規約) の適用条件を「headless セッション」から「対話セッションでの直接実行以外の実行文脈全般 (headless / fork agent / Workflow ツール)」に広げた — 2026-08-04 コメント (#1142 由来、fork 実行サーフェスでの同型 silent no-op) が根拠。
  2. AC2/AC3 (Cause B dirty guard) に「自 Issue の Spec 残骸 (Consumed Comments 追記等) は自 Issue帰属だが hard error にしない」という第三のケースを追加した — 2026-07-31 コメント (#1135 由来、leaf 自身の Spec 残骸が auto-retry を自爆させた実例) が根拠。
  この2点は新規のユーザー対話ではなく、既存コメントの決定を Issue 本文 (AC の rubric テキスト) に反映する作業。
- **Related 更新**: #1128 (Cause C, 4件目の発生元。原因は異なるが同一 symptom の頻度検出に関わる)、#1135、#1142 (上記2点の根拠コメントの元 Issue) を追記した。
- **Step 10 (Title Drift Check)**: 本文の主目的・スコープに変化はなく (Cause A/B の記述強化のみ)、Title の変更は不要と判断。
- **Step 11 (Blocked-by)**: `gh-check-blocking.sh` 実行結果、オープンなブロッカーなし (exit 0)。
- **Step 12 (Scope Assessment)**: non-interactive モードのため sub-issue 分割判断をスキップ (High-Stakes Decision)。Size は既存の `L` を維持。

### Non-Interactive Mode Note

[non-interactive mode] Skipping high-stakes action: sub-issue splitting. To perform this action, run `/issue 1123` interactively.

## spec retrospective

### Minor observations

- 前景実行を要求する注記が `modules/test-runner.md` / `skills/review/SKILL.md` / `skills/code/SKILL.md` の 3 箇所に、ほぼ同一の散文で重複していた。「LLM-native prose の重複は 2 Skill まで許容、3 つ目が consolidation の判断点」という既存の判断基準にちょうど到達しており、本 Issue の AC1 はその trigger と独立に発火した — 重複検知の仕組みがなくても、失敗の再発が同じ結論に導いた事例。
- `scripts/check-verify-dirty.sh` の呼び出し元 5 箇所 (`run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh`) は完全に同一の `case` ブロックを持つ。分類ロジックをスクリプト側で直せば 5 箇所とも一斉に効くため、caller 側改修案 (AC2 が許容していた選択肢) は採らなかった。
- `docs/reports/orchestration-recoveries.md` は 1267 行あり、`--write-manual-recovery` 由来の定型文エントリが大半を占める。cause 欄を入れても既存エントリは遡及されないため、原因別の頻度検出が実際に効き始めるのは次回の記録からになる。

### Judgment rationale

- **Cause B の帰属判定根拠に自 Issue の Spec `## Changed Files` を採用した理由**: AC2 が「判定根拠が明記されている」ことを要求しているが、`docs/sessions/` のようなパスプレフィックスの許可リストを増やす方式では `scripts/foo.sh` に対する「自分に関係する」の定義が原理的に書けない。phase は worktree 内で作業するという構造的事実から、親リポ main の dirty file は「別セッションの作業」か「自セッションの wrapper による Spec 書き戻し」に限られると整理でき、前者を非ブロック・後者を専用分類にする設計が導けた。
- **AC4 で H2 ヘッダの symptom-short を変えなかった理由**: グループキーをヘッダに埋め込む案は `_is_duplicate()` の正規表現・既存 4 エントリ・`tests/collect-recovery-candidates.bats` の全 fixture に波及する。`### Diagnosis` への `- cause:` 行追加は純粋な追記であり、cause 行のないエントリが従来キーのまま集計される後方互換が自然に得られる。
- **Cause A の規約を新規モジュールにしなかった理由**: `modules/execution-context.md` が既に実行コンテキストの SSoT として存在し `docs/tech.md` / `docs/structure.md` から参照されている。新規モジュールは structure.md とその日本語ミラーのモジュール表・カウント更新を伴ううえ、実行コンテキストの SSoT が 2 分割される。

### Uncertainty resolution

- **`run-review.sh` / `run-merge.sh` が dirty guard に PR 番号を渡していた**: Issue 本文にも過去コメントにも記載がなく、コードベース調査で初めて判明した。Spec マニフェスト方式は Issue 番号をキーにするため、これを直さないと #1055 の実際の失敗箇所 (review フェーズ) が救済されないまま AC2 だけが満たされる形になっていた。両ファイルとも `gh-extract-issue-from-pr.sh` による解決を既に持ち、dirty guard より後ろにあるだけだったため、行の移動で解決できると確認して Implementation Step 4 に組み込んだ。
- **既存テストが AC と正面から矛盾していた**: `tests/verify-dirty-detection.bats` の `"related spec dirty: exit 1 when related spec file (same issue) is dirty"` は「自 Issue の Spec は blocking」を仕様として固定しており、AC2 / AC3 の第 3 ケースと両立しない。Spec 段階で検出できたため、`/code` フェーズで「テストが落ちる」形の発見にならずに済んだ。意図的な破壊的更新として Implementation Step 5 と Notes に明記した。
- **`_is_duplicate()` の 24h 重複抑止が cause を見ない点**: 同一 issue + phase で 24h 以内に別 cause が記録されると後発が抑止される。発生頻度が低く、含めるかどうかで Spec 本文が変わらないため実装時判断に委ね、Uncertainty に残した。

## Code Retrospective

### Deviations from Design

- `tests/run-review.bats` の `gh-extract-issue-from-pr.sh` モックは Spec (Notes / Implementation Step 5) が「ヘッダコメント L5 に記載があるのに実体が存在しない」と記していたが、実装時に確認したところ既にモック (`.tmp/mocks/gh-extract-issue-from-pr.sh`, `{"issue_number": 99}` を返す) が存在していた。追加作業は不要と判断し、`tests/run-review.bats` / `tests/run-merge.bats` を無変更のまま実行して 38/29 件 PASS を確認した。
- `skills/verify/SKILL.md` の更新範囲を Spec 記載の 2 点 (Step 1 の exit 1 説明、(b) Cluster by cause への注記) から拡張した。recoveries-auto-fire の (a) Extract source entries が `{symptom-short}` のみを前提にヘッダマッチしていたため、group-key (`symptom-short/cause-slug`) をそのままヘッダ照合に使うと cause 付き候補が 1 件もマッチせず機能しなくなる。そのため (a) に group-key の分割ロジックと cause 行によるエントリ絞り込みを追加し、Issue テンプレート内の残りの `{symptom-short}` プレースホルダも `{group-key}` に統一した。Spec の Changed Files には明記がなかったが、AC4 の「頻度検出が機能する」という要求を満たすために必要な修正だった。

### Design Gaps/Ambiguities

- なし (Spec の Uncertainty 節で既出の 3 点以外に、実装中に新たな設計上の空白は見つからなかった)

### Rework

- `skills/verify/SKILL.md` を `{symptom-short}` → `{group-key}` に一括置換した際、part (a) の「ヘッダは `{symptom-short}` で照合する」という説明文まで誤って `{group-key}` に書き換わってしまった (ヘッダは cause を含まないため誤り)。`validate-skill-syntax.py` は構文チェックのみでこの意味的な誤りを検出できず、diff を読み返して発見し修正した。
- `scripts/check-verify-dirty.sh` の新テスト (self-spec / foreign-session のみが dirty なケース) を追加した際、bash 3.2 の `"${arr[@]}"` 空配列 unbound-variable バグを踏んだ。既存コードの `${ignore_patterns[@]+"${ignore_patterns[@]}"}` パターンを流用して修正した。旧実装では `unrelated_spec_files` が空になる経路 (has_other=false かつ unrelated_spec_files 空) が構造的に存在しなかったため、このバグは今回の分類拡張で初めて表面化したものであり、Spec の設計自体に誤りはない。

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- Spec の設計どおり実装した。`check-verify-dirty.sh` は `self-spec` / `own-issue-scope` / `foreign-session` の3分類を追加し、`run-review.sh` / `run-merge.sh` は Issue 番号解決を dirty guard より前に移動した。
- `skills/verify/SKILL.md` の recoveries-auto-fire は、Spec が明示した2箇所 (Step 1 の exit 1 説明、(b) のクラスタリング注記) に加えて (a) Extract source entries のヘッダ照合ロジックも group-key 対応に修正した (Spec 未記載だが AC4 の機能要件として必須と判断)。
- Spec の Notes が「`tests/run-review.bats` のモック実体が存在しない」としていた点は実装時確認で誤りと判明 (既に存在) — モック追加はスキップし、既存38テストのPASSで代替確認した。

### Deferred Items

- `_is_duplicate()` (`scripts/run-auto-sub.sh`) の 24h 重複抑止条件に cause を含めるかは、Spec の判断どおり実装時 (今回) は含めないことにした。現行の symptom + context_line 一致による抑止挙動を維持。
- `docs/reports/orchestration-recoveries.md` の既存 4 エントリへの cause 行の遡及付与は行っていない (Spec の判断どおり)。
- Post-merge の2条件 (並行セッション dirty 下での `/auto` 完走、新規 `manual-recovery-review-rerun` エントリが増えないことの観察) は本 PR では未検証。マージ後の `/verify` で確認する。

### Notes for Next Phase

- Pre-merge AC (rubric ×4 + command ×1) はセルフレビューで PASS 判定し、Issue のチェックボックスは既に `[x]` 済み。`/verify` では特にこのセルフレビューの妥当性 (rubric の adversarial grading) を独立した視点で再確認すること。
- `bats tests/` フルスイート (1341件) が PASS 済み。`/review` では behavioral change の影響範囲 (execution-context.md 参照元4ファイル、check-verify-dirty.sh 呼び出し元5スクリプト) が Spec の Changed Files と一致しているか確認すること。
- Post-merge AC の検証には、並行セッションが dirty な状態で `/auto` を実際に走らせる必要がある。`/verify` 単体では再現が難しいため、実運用での観察 (`docs/reports/orchestration-recoveries.md` に新規 `manual-recovery-review-rerun` が増えないこと) が事実上の検証手段になる。

## review retrospective

### Spec vs. implementation divergence patterns

- Code Retrospective は「`tests/run-review.bats` の `gh-extract-issue-from-pr.sh` モックは既に存在するので追加不要」と判断していたが、これは "モックが存在するか" と "モックが引数を検証するか" を混同していた。既存モックは無条件 `exit 0` で、Issue番号解決の並び替えという本PRの中心的な behavioral change を一切検証できない状態だった。Spec/Code Retrospective の「モックの有無」チェックだけでは、モックの実効性 (何を assert しているか) までは検証範囲に含まれないことが分かった。同種の見落としは `tests/run-merge.bats` にも同じ形で存在しており、1箇所の Spec 上の判断ミスが対称的な2ファイルに複製されていた。
- AC4 (「頻度検出が原因を区別できる」) は、rubric 検証のスコープが `run-auto-sub.sh` / `collect-recovery-candidates.sh` / テストの3ファイルに限定されていたため技術的に PASS 判定されたが、唯一の呼び出し元 (`skills/auto/SKILL.md`) が新フラグを一切渡していないという end-to-end のギャップは rubric の対象外だった。Changed Files に列挙されたファイル集合だけを検証する rubric は、"実装されたが呼び出されない" 形の dormant feature を原理的に検出できない。

### Recurring issues

- `check-verify-dirty.sh` の own-issue-scope manifest 抽出 (`grep -oE '^- \`[^\`]+\`'`) は、Spec 自身のテンプレートで既に使われている2つの実在パターン (indented sub-bullet、`[label]` prefix bullet) を取りこぼす fail-open バグを持っていた。この PR が「Spec の記述形式を機械的に解釈する」機能を新設した際、Spec の記述に許容されている表記ゆれの幅を rubric や Implementation Steps のどちらも列挙していなかった — 自由記述の Markdown を新たにパースする機能を追加する際は、既存 Spec コーパスに対する网羅的なフォーマット調査を Implementation Steps に組み込むべきだった。
- silent no-op (`2>/dev/null || true` によるエラー握り潰し) は本 Issue のタイトルそのものが示す通り再発型の障害パターンだが、今回追加された `--cause`/`--diagnosis` の実装自体が同種の silent no-op (改行によるheredoc構文エラー) を新たに持ち込んでいた。silent-no-op を修正する PR の中で、その修正コード自身が同じ抽象化 (sed エスケープ + heredoc 埋め込み) を再利用して同じ脆弱性クラスを再導入した — 「修正対象のパターンを新規コードに適用しない」ことをレビューの明示的なチェック観点に加える価値がある。

### Acceptance criteria verification difficulty

- Pre-merge rubric (4件) はいずれも「該当ファイルの変更が存在するか」を確認する形式で、変更の正しさ (ロジックが実際に意図通り動くか) までは判定していない。本レビューで見つかった MUST 5件のうち4件 (exit2到達性、manifest抽出、silent no-op、group-key衝突) は、rubric が PASS 判定した後のコードレビューでのみ発見された、実装済みコードの振る舞い上の欠陥だった。rubric ベースの Pre-merge AC 検証は「変更漏れ」の検出には有効だが、「変更されたロジックの正しさ」の検出は多観点コードレビュー (Step 10) に完全に依存しており、rubric 側の verify command をロジック検証まで拡張する余地は小さい (実行可能なテストで代替する方が費用対効果が高い)。

## Auto Retrospective

### Orchestration Anomalies
- **[json-mode-silent-hang]** review phase (PR #1149) の leaf セッションが 2600 秒無出力となり watchdog が SIGTERM で回収 (exit 143, 2026-08-04T08:58:31Z, `watchdog_kill` event 記録済み)。外部 kill ではない (Exit code trailer あり / detect-external-kill no-match)。Tier 2 が既知パターンとして検出し、カタログ手順 (retry once) を適用
- **[json-mode-silent-hang]** merge phase (PR #1149) も同型の watchdog kill (exit 143, 2026-08-04T09:54Z 頃)。カタログ手順 (retry once) を適用
- **[notification-dependent-wait]** merge retry (exit 1): leaf セッションが「run-merge.sh をバックグラウンド実行して通知待ち」を宣言して exit 0 → silent no-op 検出。本 Issue が禁止する通知依存待機そのものの再演。親セッションが manual recovery (rebase conflict 解消 + 直接 merge) で完遂

### Manual recovery (merge)
- **Date**: 2026-08-04 10:24 UTC
- **Issue**: #1123, phase: merge
- **Source**: parent session manual recovery
- **Recovery type**: merge-rerun
- **Wrapper exit code**: 1
- **Outcome**: success

## Verify Retrospective

### Phase-by-Phase Review

#### issue / spec
- 観察 3 件 (headless ×2 トリガー / 自 Spec 残骸 / fork surface) がコメント接続 → AC への反映まで一気通貫で機能した。「再喚起保証」という概念での一般化 (Opus spec) は #1097/#1103/#994 を単一規約に束ねる適切な抽象度だった

#### code / review
- review 初回は json-mode-silent-hang (watchdog kill 2600s) → カタログ retry で回復。retry 後の review は MUST 5 件 (exit2 到達性 / manifest 抽出 fail-open / silent no-op 再導入 / group-key 衝突 / dormant feature) を検出・解消しており、--full review の価値を実証

#### merge
- **notable: 3 連続失敗** — watchdog kill ×2 (json-mode-silent-hang) → notification-dependent-wait による silent no-op ×1 (本 Issue が禁止するクラスの実演。Auto Retrospective に記録済み)。親セッションの manual recovery (merge-rerun) で完遂
- **notable (Auto Retrospective 未記録の観察): #890 系「recovery 記録が競合を生む」の再演** — 親セッションが Tier 2 検出結果を main の Spec に直接 commit/push した 2 コミットが、open PR #1149 の同一 Spec ファイル変更と本物の conflict を生成し、rebase + 手動解消 (Phase Handoff ローテーション考慮) + フルスイート再実行を要した。open PR が存在する Issue の recovery 記録を main に直接書くことは構造的に conflict を製造する。プロジェクト診断レポート (docs/reports/ja/project-structural-review-2026-07-31.md) の推奨 6「recovery 記録の main 直接 commit/push を廃止し .tmp/auto-events.jsonl への emit に一本化」が未起票のまま実害を再生産した形

#### verify
- FAIL 0。Post-merge manual は縮小検証 (foreign-session 分類の exit 0 実測) で機構レベル確認、e2e は次回並行運用で補完

### Improvement Proposals
- recovery 記録 (Tier 2/3 検出結果・manual recovery) の書き込み先を、open PR が存在する場合は main 直接 commit ではなく events emit + セッション末尾転記に変更する (#890/#1005/#1006 と本件で計 4 度目の conflict 実害。診断レポート推奨 6 の正式起票)
