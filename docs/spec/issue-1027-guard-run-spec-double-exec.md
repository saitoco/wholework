# Issue #1027: spec: run-spec.sh の二重実行をガードする precondition チェックを追加

## Consumed Comments

| login | authorAssociation | trust tier | intent | URL |
|-------|--------------------|-----------|--------|-----|
| saito | MEMBER | first-class | Issue Retrospective (`/issue 1027 --non-interactive` の Auto-Resolve Log: 実装配置場所=run-spec.sh 本体、観測可能性チャネル=stderr ログ、フェーズラベル列挙に phase/merge を追加、という3件の判断根拠)。内容は Issue 本文の Auto-Resolved Ambiguity Points と整合しており、追加の設計変更は不要と判断 | https://github.com/saitoco/wholework/issues/1027#issuecomment-5030693973 |

## Overview

`/auto` の pr route 実行中に、同一 Issue に対する `/spec` フェーズの二重実行が観測された (2026-07-20、利用側プロジェクト実測)。1 回目の `run-spec.sh` 完了後、code フェーズ進行中に 2 回目の `run-spec.sh` が (起動経路不明のまま) 実行され、Spec への追加コミットが main へ push されて `phase/code` → `phase/spec` へのラベル巻き戻し、および PR の base conflict という連鎖障害に至った。本 Issue は `scripts/run-spec.sh` に `scripts/check-verify-dirty.sh` と同様のシェルレベル precondition ガードを追加し、対象 Issue のフェーズラベルが `phase/code` 以降 (code/review/merge/verify/done) の場合に spec 実行を構造的に中断する。

## Reproduction Steps

1. `/auto` の pr route 実行で、親セッションが `run-spec.sh N` を起動する。1 回目の実行は watchdog が「still waiting, silent for 1200s」を記録するほど長時間化したのち、正常に完了する (Spec 作成・main へ push・exit 0)。
2. 親セッションが `run-code.sh N --pr` に進み、code フェーズが実行中の間に、同一 Issue に対して `run-spec.sh N` が再度実行される (起動経路は未特定だが、1 回目が watchdog の長時間無音を経ていたことから watchdog kill → 再実行系のパスが疑われる)。
3. `run-spec.sh` 側に「対象 Issue が既に spec フェーズを越えて進行しているか」を確認する precondition チェックが存在しないため、2 回目の実行はそのまま `/spec` 本体 (SKILL.md) の実行まで進む。2 回目の spec 自身の Consumed Comments には「(spec 再実行, cutoff `phase/code` label = ...)」と記録され、cutoff 時点で既に `phase/code` ラベルが付いていたことを 2 回目の spec 自身が認識しているにもかかわらず、処理を継続する。
4. 2 回目の spec が Spec への追加コミット (「Update design」) を main に push し、`phase/code` → `phase/spec` へのラベル巻き戻しが発生する (code フェーズの Phase Handoff に記録)。code フェーズは自力で `phase/code` に再設定して完走する。
5. 2 回目の spec の main への push により PR が base conflict (CONFLICTING/DIRTY) になり、`run-code.sh` は exit 0 + 警告を出力する。親セッションが `orchestration-fallbacks.md#code-base-conflict` を手動適用して回復する。

## Root Cause

`scripts/run-spec.sh` には、`/verify` の `scripts/check-verify-dirty.sh` (session isolation check) に相当する「対象 Issue が既に spec フェーズを越えて進行済みか」を確認する precondition ガードが存在しなかった。そのため、何らかの理由 (watchdog kill 後の再実行パスが疑われるが未確定) で `run-spec.sh` が同一 Issue に対して再度起動されると、フェーズラベルの状態にかかわらず `/spec` 本体の実行が最後まで進み、Spec への不要な追加コミットとフェーズラベルの巻き戻しを引き起こす。`run-spec.sh` は既に `check-verify-dirty.sh` を呼び出す「Session isolation check」ブロックを持っており (dirty file の検出は行うが、フェーズラベルに基づく重複実行の検出は行わない)、同種の shell レベル precondition ガードを追加できる構造上の前例が既に存在する。

## Changed Files

- `scripts/run-spec.sh`: `REPO_ROOT` 定義の直後・既存の `# Session isolation check` ブロックの直前に phase label precondition ガードを追加 — bash 3.2+ compatible (no arrays, no mapfile, no declare -A)
- `tests/run-spec.bats`: 新設した phase guard の bats テストを追加 (ガード発火 2 ケース + 非発火の境界値確認 1 ケース) — bash 3.2+ compatible

**Steering Docs sync candidate** (`grep -l "run-spec.sh" docs/*.md docs/ja/*.md` 実施済み。以下は候補列挙であり、内容確認の結果いずれも本変更 (内部 precondition ガードの追加) による記述更新は不要と判断 — run-spec.sh の役割説明・model/effort 表・usage 文字列・移行履歴のいずれも変更対象外のため):
- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] `run-spec.sh` の役割説明 ("run spec skill" 等) が最新か確認 — 内部ロジック追加のみのため更新不要と判断
- `docs/tech.md` / `docs/ja/tech.md`: [Steering Docs sync candidate] model/effort matrix・fork 要否表の `run-spec.sh` 記述が最新か確認 — 本変更は model/effort/fork 要否に影響しないため更新不要と判断
- `docs/migration-notes.md` / `docs/ja/migration-notes.md`: [Steering Docs sync candidate] `run-spec.sh` の interface 変更履歴が最新か確認 — 本変更は既存 CLI 引数 (usage 文字列) を変更しないため追記不要と判断

## Implementation Steps

1. `scripts/run-spec.sh` に phase label precondition ガードを追加する。挿入位置: `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` の直後、既存の `# Session isolation check` コメントブロックの直前。実装: `gh issue view "$ISSUE_NUMBER" --json labels --jq '.labels[].name' 2>/dev/null || true` で現在のラベル一覧を取得し (`scripts/gh-label-transition.sh` の `CURRENT_LABELS=$(gh issue view ... 2>/dev/null || true)` と同じ fail-open パターン)、`phase/code phase/review phase/merge phase/verify phase/done` のいずれかを含む場合、`echo "[run-spec] classify=phase-guard-blocked issue=${ISSUE_NUMBER} label=${_phase}" >&2` で `check-verify-dirty.sh` の `classify=` ログ出力 (`scripts/check-verify-dirty.sh` 行 102-108) と同様の stderr ログを出力し、続けて人間可読な `Error: issue #${ISSUE_NUMBER} already has label '${_phase}' (phase/code or later) — aborting spec to prevent duplicate execution.` を stderr に出力したうえで `exit 1` する。`gh` 呼び出し失敗時はラベル一覧が空文字列となりガードは発火しない (fail-open) (→ acceptance criteria 1, 2, 3)
2. `tests/run-spec.bats` に新設した phase guard のテストを追加する (after 1)。既存 setup() の `gh` モックはデフォルトで空ラベルを返すため、既存テストは無改修で green のまま維持される。入力データ形式: run-spec.sh 内で `gh` を実際に呼び出す箇所は新設ガードのみ (`guard-prefix.sh` / `retry-on-kill.sh` は `gh` を呼ばず、`claude` サブプロセスは別途モック済み) なので、新規テストでは `$MOCK_DIR/gh` を丸ごと `#!/bin/bash\necho "<label>"\nexit 0` 形式で上書きしてよい (`--jq '.labels[].name'` は 1 行 1 ラベルの改行区切り出力のため、単一ラベルなら `echo "<label>"` で模擬できる)。新規ケース: (a) `gh` モックを `phase/code` を返すよう上書きし、`status -eq 1`・出力に `classify=phase-guard-blocked` が含まれる・`claude` モック呼び出しログ (`$CLAUDE_CALL_LOG`) が生成されていないことを検証、(b) 同様に `phase/merge` ラベルで exit 1 になることを検証 (acceptance criteria 2 の `phase/merge` 分岐到達を保証)、(c) `gh` モックを `phase/ready` を返すよう上書きし、ガードが発火せず `status -eq 0` のまま既存フローが継続することを検証 (ガード対象が `phase/code` 以降のみであり `phase/ready` を誤ってブロックしないことの境界値確認) (→ acceptance criteria 1, 2, 3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-spec.sh に、scripts/check-verify-dirty.sh と同様のシェルレベル precondition ガードとして、対象 Issue のフェーズラベルが phase/code 以降 (code/review/merge/verify/done) の場合に spec 実行を中断するチェックが存在する" --> フェーズラベルが phase/code 以降 (code/review/merge/verify/done) の Issue に対して run-spec.sh レベルで spec 実行が中断される
- <!-- verify: file_contains "scripts/run-spec.sh" "phase/merge" --> run-spec.sh のガード対象フェーズラベル列挙に phase/merge が含まれる
- <!-- verify: rubric "spec の二重実行ガードが発火した場合、scripts/check-verify-dirty.sh の classify= ログ出力と同様に stderr へのログ出力として観測可能である (サイレントスキップではない)" --> ガード発火が stderr ログ出力として観測可能である

### Post-merge

- /auto の pr route 実行で spec → code 進行中に spec が再実行されないことを実運用で確認する <!-- verify-type: observation event=auto-run -->

## Notes

- **SPEC_DEPTH=light (Size M) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** Issue 本文に `/issue` フェーズの Auto-Resolved Ambiguity Points が既に記載されており (実装配置場所=run-spec.sh 本体 [check-verify-dirty.sh 呼び出しの既存パターンに追随]、観測可能性チャネル=stderr ログ [Issue コメント投稿は追加 API コストがあり不採用]、フェーズラベル列挙=phase/merge を追加 [`gh label list` で実在確認済み])、本 Spec はそれをそのまま設計に反映した。
- **実装配置の判断 (Issue 本文の自動解決を継承)**: 独立スクリプト化はせず `run-spec.sh` 本体へのインライン実装とした。`check-verify-dirty.sh` は dirty file の 4-way classification という独立した複雑なロジックを持つため別スクリプト化されているが、本ガードは「ラベル一覧取得 + membership チェック」のみで完結する数行のロジックであり、新規スクリプトファイル・新規 bats テストファイルを追加するほどの複雑度がないと判断した。
- **`phase/ready` は意図的にガード対象外**: Issue 本文の Acceptance Criteria が明示的に「phase/code 以降」と定義しており、spec 完了後の再設計 (phase/ready 状態での `/spec` 再実行) は正当なユースケースとして許容する。
- **fail-open 方針**: `gh` API 呼び出し失敗時はガードを発火させず素通りする (`scripts/gh-label-transition.sh` の既存フォールバック方針と同じ)。理由: 一時的な API 障害時は後続の Step 1 (`gh issue view $NUMBER --json title,body,labels`) を含む `/spec` 本体の GitHub 呼び出しも同様に失敗する可能性が高く、このガード単体を fail-closed にしても実質的な安全性向上にならない一方、誤検知で正当な spec 実行をブロックするリスクの方が大きい。
- **ドキュメント同期は対象外と判断**: `README.md` / `docs/workflow.md` に "run-spec" への言及なし (grep 実施、0 件)。`docs/structure.md` / `docs/tech.md` / `docs/migration-notes.md` (および対応する `docs/ja/*`) には `run-spec.sh` への言及があり Changed Files の Steering Docs sync candidate として列挙したが、内容確認の結果いずれも役割説明・model/effort 表・移行履歴レベルの記述にとどまり、本変更 (内部的な安全策の追加) は既存の CLI インターフェース (usage 文字列・フラグ) や model/effort/fork 要否に影響しないため、実質的な参照更新は不要と判断した。`modules/skill-dev-doc-impact.md` の「Script addition, change, or deletion」変更種別には技術的に該当するが、上記の通り更新不要と判断している。
- **起動経路の根本原因は本 Issue の対象外**: Issue 本文が明記する通り、2 回目の `run-spec.sh` がどの経路で再起動されたかは未特定 (watchdog kill → 再実行系のパスが疑われるのみ)。本 Spec は症状 (二重実行がフェーズ状態を破壊しうること) を構造的にガードすることに限定し、起動経路そのものの調査・修正は別 Issue のスコープとする。
