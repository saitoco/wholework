# Issue #964: auto: code-patch フェーズの Tier 3 リカバリで action=skip 選択前に完了確認ガードを追加

## Consumed Comments

- saito (MEMBER, 2026-07-10T15:13:26Z): Issue Retrospective — 非対話モード (`--non-interactive`) での `/issue` 実行時に3件の曖昧ポイント (対象スクリプトの特定・`matches_expected: false` 時のフォールバック方針・regression テストの対象範囲) を自動解決した根拠を記録。内容は現在の Issue body の「Auto-Resolved Ambiguity Points」セクションと同一であり、本 Spec フェーズでの追加対応は不要と判断した。 (https://github.com/saitoco/wholework/issues/964#issuecomment-4936748922)

## Overview

`scripts/spawn-recovery-subagent.sh` の Tier 3 リカバリで、`orchestration-recovery` サブエージェントが `action=skip` を返した際、既に取得済みの `RECONCILE_OUTPUT` (`reconcile-phase-state.sh <phase> --check-completion` の結果、111行目) の `matches_expected` を機械的にチェックせずに skip (exit 0、フェーズ完了扱い) を適用していた。これにより、サブエージェントが `matches_expected: false` (未完了) にも関わらず `action=skip` を誤って選択した場合、false-positive な「完了」判定が発生し、実装コミットが `origin/main` に反映されないまま後続フェーズに進んでしまう (saitoco/tofas#268、saitoco/tofas#279 で2回発生)。本 Issue では `skip)` 分岐の直前に `matches_expected` を読み取るガードを追加し、`true` の場合のみ skip を許可、それ以外 (`false` または `RECONCILE_OUTPUT` が空/パース不能) の場合は `abort` と同じ exit code 契約 (非ゼロ exit、human 判断のため停止) で拒否する。

## Reproduction Steps

1. `/auto` の code-patch フェーズで、`run-code.sh` が実装コミットを作成した後、worktree ブランチから `origin/main` へのマージ・push に失敗する (例: `worktree-merge-push.sh` の失敗)。
2. Tier 1 (`reconcile-phase-state.sh code-patch --check-completion`) は正しく `matches_expected: false` (`origin/main` に `closes #N` を含むコミットが見つからない) を検出する。
3. Tier 3 (`spawn-recovery-subagent.sh`) が `agents/orchestration-recovery` を起動する。入力 JSON には `reconcile_snapshot` として手順2の `matches_expected: false` を含む `RECONCILE_OUTPUT` が渡っているが、サブエージェントが誤診断により `{"action":"skip", ...}` を返す。
4. 現行コードの `skip)` 分岐 (289-313行目) は `RECONCILE_OUTPUT` の内容を一切参照せず、`write_recovery_entry "skip"` を実行して無条件に `exit 0` する。
5. `run-auto-sub.sh` は exit 0 を「フェーズ完了」として扱い、`phase/code` へ遷移する。実装コミットは worktree ブランチに取り残されたまま、`/auto` の後続処理は完了したものと誤認識する。

## Root Cause

`scripts/spawn-recovery-subagent.sh` の `skip)` 分岐は、Tier 3 サブエージェントの `action=skip` という判断を無条件の指示として実行しており、その判断材料として既に渡してある `RECONCILE_OUTPUT.matches_expected` (111行目で計算済み) と機械的に突き合わせるガードが存在しない。サブエージェントの `action` はあくまで advisory な LLM 判断であり、`reconcile_snapshot` を入力に含めても、その解釈を誤る (`matches_expected: false` を見ても skip を選んでしまう) ケースを防げていなかった。他のアクション (`retry`/`recover`/`abort`) は実行結果やバリデーション (`validate-recovery-plan.sh`) を経由するのに対し、`skip` だけは何のチェックも経ずに「完了扱い」という最も楽観的な結果を確定させる非対称な設計になっていた。

## Changed Files

- `scripts/spawn-recovery-subagent.sh`: `skip)` 分岐 (289-313行目) の先頭に `matches_expected` ガードを追加。`RECONCILE_OUTPUT` から `matches_expected` を読み取り、`true` の場合のみ既存の skip 処理 (echo → `write_recovery_entry "skip"` → `exit 0`) を実行、それ以外 (`false` または未パース) の場合は `abort` と同じ契約 (stderr へメッセージ出力 → `exit 1`、`write_recovery_entry` は呼ばない) で拒否する。bash 3.2+ 互換 (既存パターンと同じ `python3 -c` を使用、連想配列・`mapfile` 不使用)
- `tests/spawn-recovery-subagent.bats`: "action=skip: exits 0 without runner invocation" テスト (111行目、デフォルトの `matches_expected:false` モックのまま) を「skip が拒否される」regression テストとして更新。`matches_expected:true` モック時に skip が成功する新規テストを追加。"stale slot lock (dead pid) is reclaimed and script proceeds" テスト (160行目) と "CLAUDE_BIN mock returns prose + JSON + prose" テスト (173行目) は元々の検証意図 (スロット再利用ロジック / プロース混じり出力からの JSON 抽出) がガード追加によって壊れないよう、各テスト内で `reconcile-phase-state.sh` モックを `matches_expected:true` に上書き
- `tests/auto-recovery.bats`: "action=skip writes recovery-sub-agent entry to report" テスト (98行目) と "missing report file skips write gracefully" テスト (140行目) は、いずれも `write_recovery_entry` の skip 経路の挙動を検証する目的のため、各テスト内で `reconcile-phase-state.sh` モックを `matches_expected:true` に上書きし、ガード追加後も skip 経路に到達できるようにする
- `docs/product.md`: [Steering Docs sync candidate] Terms の「Orchestration recovery」エントリ (spawn-recovery-subagent.sh の Tier 3 説明) が今回の変更後も正確か確認。内容確認のみで変更不要の見込み (grep 済み、既存記述は skip 判断の内部ガード有無に言及しない抽象度)
- `docs/structure.md`: [Steering Docs sync candidate] Scripts 一覧の `spawn-recovery-subagent.sh` の一行説明 (218行目) を確認。同上、変更不要の見込み
- `docs/tech.md`: [Steering Docs sync candidate] Tier 3 リカバリの説明 (55行目、100行目) を確認。同上、変更不要の見込み
- `docs/ja/product.md` / `docs/ja/structure.md` / `docs/ja/tech.md`: [Steering Docs sync candidate] 上記3ファイルの日本語ミラー。英語版が変更不要なら追従不要 (`docs/translation-workflow.md` のミラー同期規則に従う)

## Implementation Steps

1. `scripts/spawn-recovery-subagent.sh` の `skip)` ケース (現行289-313行目、case文内) を以下のロジックに置き換える (→ acceptance criteria AC1, AC2):
   ```bash
   skip)
     SKIP_MATCHES_EXPECTED=$(python3 -c "
   import json, sys
   try:
       data = json.loads(sys.argv[1])
       print('true' if data.get('matches_expected') is True else 'false')
   except Exception:
       print('false')
   " "$RECONCILE_OUTPUT")

     if [[ "$SKIP_MATCHES_EXPECTED" != "true" ]]; then
       echo "[spawn-recovery] action=skip rejected: matches_expected != true in RECONCILE_OUTPUT; stopping for human judgment" >&2
       exit 1
     fi

     echo "[spawn-recovery] action=skip: treating phase as complete"
     write_recovery_entry "skip" || true
     exit 0
     ;;
   ```
   `RECONCILE_OUTPUT` が空文字列またはパース不能な場合も `matches_expected != true` として扱い (fail-closed)、`retry`/`recover` への自動フォールバックは行わない。拒否時は `write_recovery_entry` を呼ばない (既存の `abort)` 分岐と同じ挙動)。
2. `tests/spawn-recovery-subagent.bats` を更新する (→ AC3):
   - 111行目の "action=skip: exits 0 without runner invocation" テストを、デフォルトモック (`matches_expected:false`) のまま `status -ne 0` および拒否メッセージ (例: `"rejected"` を含む) を検証するテストへ書き換える (テスト名も拒否の意図が分かるよう更新)
   - 新規テストを追加: `reconcile-phase-state.sh` モックを `matches_expected:true` に上書きした状態で `action=skip` を返す claude モックを使い、`status -eq 0`・`"action=skip"` 出力・`RUNNER_LOG` 不在を検証
   - 160行目 "stale slot lock (dead pid) is reclaimed and script proceeds" と 173行目 "CLAUDE_BIN mock returns prose + JSON + prose" の各テスト内で、`$MOCK_DIR/reconcile-phase-state.sh` を `matches_expected:true` を返すよう上書きしてから実行する
3. `tests/auto-recovery.bats` を更新する (→ AC3): 98行目 "action=skip writes recovery-sub-agent entry to report" と140行目 "missing report file skips write gracefully" の各テスト内で、`$MOCK_DIR/reconcile-phase-state.sh` を `matches_expected:true` を返すよう上書きしてから実行する (デフォルト setup の `matches_expected:false` モックのままだと、ガード追加後は `write_recovery_entry` に到達する前に拒否されてしまうため)
4. (after 1, 2, 3) ローカルで関連 bats スイート全体を実行して回帰がないことを確認する (→ AC3): `bats tests/spawn-recovery-subagent.bats tests/auto-recovery.bats tests/run-auto-sub.bats tests/auto-sub-observability.bats`。後者2ファイルは `spawn-recovery-subagent.sh` をテスト境界でモック置換しているため本体ロジック変更の影響を受けず、ソース変更は不要 (Notes 参照)。

## Verification

### Pre-merge

- <!-- verify: grep "matches_expected" "scripts/spawn-recovery-subagent.sh" --> `scripts/spawn-recovery-subagent.sh` の `skip)` 分岐 (289行目付近) が、`action=skip` を適用する前に既存の `RECONCILE_OUTPUT` (`reconcile-phase-state.sh <phase> --check-completion` の結果) から `matches_expected` を機械的に読み取るガードを実装している
- <!-- verify: rubric "scripts/spawn-recovery-subagent.sh の skip 分岐は、matches_expected が true の場合のみ skip (exit 0) を許可し、false の場合は skip を拒否して abort と同じ exit code 契約で human 判断のため停止する（他の Tier 3 アクション (retry/recover) への自動フォールバックは行わない）" --> `matches_expected: false` の場合に skip が拒否され、human 判断のため停止する（run-auto-sub.sh 側で既存フェーズが失敗継続として扱われる）
- <!-- verify: github_check "gh run view $(gh run list --workflow=test.yml --limit=1 --json databaseId --jq '.[0].databaseId') --json jobs --jq '.jobs[] | select(.name==\"Run bats tests\").conclusion'" "success" --> `spawn-recovery-subagent.sh` に依存する既存 bats テスト (`tests/spawn-recovery-subagent.bats`, `tests/auto-recovery.bats`, `tests/run-auto-sub.bats`, `tests/auto-sub-observability.bats` を含むフルスイート) が CI で全て pass する。特に `tests/spawn-recovery-subagent.bats` の "action=skip: exits 0 without runner invocation" テストは、`matches_expected: false` 時に skip が拒否される regression テストとして更新されている

### Post-merge

なし

## Notes

- **fail-closed 判断 (Spec 時点の追加判断)**: Issue 本文の AC2 は `matches_expected` が `true`/`false` の2値であることを前提に「false の場合は拒否」と記述しているが、`RECONCILE_OUTPUT` は `reconcile-phase-state.sh` 自体がエラー終了した場合など空文字列になるケースもありうる (`|| true` で握り潰される、111行目)。本 Spec ではこのケースも「`true` と確認できない」として拒否側に倒す (fail-closed) 設計とした。理由: AC2 のレビューコメント文言「matches_expected が true の場合のみ skip を許可」を字義通り解釈すれば、true 以外は全て拒否対象と読めるため、Issue の意図と矛盾しない最小リスクの解釈と判断した。
- **Steering Docs sync candidate 6件は変更不要の見込み**: `docs/product.md`/`docs/structure.md`/`docs/tech.md`/日本語ミラー3件は `spawn-recovery-subagent.sh` に言及するが、いずれも Tier 3 全体の役割 (サブエージェント起動・バリデーション・並行制御・recovery entry 記録) を抽象度高く説明しており、`skip` 分岐内部のガード有無という実装詳細には踏み込んでいない (grep 済み、既存記述はそのまま正確)。`doc-checker.md` の必須列挙ルールに従い候補として列挙したが、`/code` フェーズでの実読による最終確認を経ても変更不要と判断される可能性が高い。
- **tests/run-auto-sub.bats・tests/auto-sub-observability.bats はソース変更不要**: 両ファイルとも `setup()` で `$MOCK_DIR/spawn-recovery-subagent.sh` 自体を丸ごとモックスクリプトに置き換えており (`run-auto-sub.sh` 側から見て `WHOLEWORK_SCRIPT_DIR` 経由で解決される)、実体である `scripts/spawn-recovery-subagent.sh` のロジック変更の影響を受けない。Issue 本文 AC3 が両ファイルを「cross-file test coupling」としてフルスイートに含めているのは安全網としての実行であり、ソース側の修正が必要という意味ではないことを確認済み。
- **Issue body の背景記述との整合性確認**: Background に記載された行番号 (111行目の `RECONCILE_OUTPUT`、289-313行目の `skip)` 分岐) は実装コードの現況と一致しており、コンフリクトは検出しなかった。

## Code Retrospective

### Deviations from Design
N/A — 実装は Implementation Steps 1-3 の記述通り。

### Design Gaps/Ambiguities
N/A

### Rework
N/A — Spec の設計 (fail-closed、abort と同じ exit code 契約、write_recovery_entry を呼ばない) をそのまま実装し、関連4ファイルのフルスイート (72件) がローカルで一発 pass した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- mergeable=true (reason=clean, CI success, review approved) を確認したため Step 3 (競合解決) をスキップし、Step 4 (squash merge) に直接進んだ
- `gh pr merge 978 --squash --delete-branch` で main へ squash merge、リモートブランチ `worktree-code+issue-964` を削除

### Deferred Items
- None

### Notes for Next Phase
- `/verify 964` を実行可能。closes #964 により Issue は squash merge 時に自動クローズ済み
- Post-merge verification 項目は Spec 上「なし」

## review retrospective

### Spec vs. implementation divergence patterns
Nothing to note — diff は Spec の Implementation Steps の記述と一致しており、構造的な乖離は検出しなかった。

### Recurring issues
Nothing to note — `review-light` (4観点: spec deviation / edge cases・robustness / security・safety / documentation consistency) で issue 0件。同種の指摘の繰り返しも観測されなかった。

### Acceptance criteria verification difficulty
Nothing to note — AC1 (`grep`)・AC2 (`rubric`)・AC3 (`github_check`) の3件とも UNCERTAIN なく機械的に PASS 判定できた。AC3 は Phase Handoff (code) の "Notes for Next Phase" が指示した通り、PR #978 の CI ("Run bats tests" ジョブ) 完了後に確認しチェックボックスを更新した。
