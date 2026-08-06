# Issue #1175: review: 非対話モードでのバックグラウンドテスト完了待ちによる silent no-op を塞ぐ

## Overview

非対話モード (`claude -p`) の `/review` がテストをバックグラウンドで起動し完了通知を待つ形で turn を終えると、セッションはその時点で終了し、後続の Step 12 (指摘の修正) / Step 14 (Response Summary 投稿) に到達しないまま silent no-op になる。#1168 の実測 (2026-08-05、`run-review.sh 1173 --full` を 2 回実行して 2/2 で再現) では、`skills/review/SKILL.md:39` の Foreground 実行制約 (候補 A、既存実装) が実際にプロンプトへ含まれていたにもかかわらず再現しており、プロンプト指示のみでは遵守を保証できないことが確認済み。Issue 本文はこの実測を踏まえ、候補 A の追加強化ではなく候補 B (wrapper 側で検出して継続を促す) / C (`/review` のテスト実行を verify-executor 経由に寄せる) を優先的に検討するよう指定している。

本 Spec は候補 B を採用する。既存の `scripts/post-fallback-review-summary.sh` (exit 0 + `matches_expected:false` 時に `run-review.sh` が呼ぶフォールバック投稿スクリプト) の証跡ガードが「レビューが投稿された事実」しか見ておらず「MUST 指摘が未解決のまま偽の recovered 報告をしてしまう」欠陥を塞ぎ、MUST 未解決を検出した場合は `run-review.sh` が同一プロンプトで 1 回だけ継続リトライを試みるようにする。候補 C は verify-executor の safe mode が `command` 型を無条件で UNCERTAIN 化する (実行しない) ため、本 Issue の該当箇所には適用できないと判断し不採用とした (詳細は Root Cause / Notes 参照)。

## Reproduction Steps

1. `docs/spec/issue-1175-review-background-noop-fix.md` 作成時点でのライブ再現は行わない (数十分規模の `--full` レビュー実行を要するため) — 以下は Issue 本文に記録された #1168 の実測記録
2. `run-review.sh 1173 --full` を実行すると、`claude -p` セッションはテストのバックグラウンド完了待ち文言 (「バックグラウンドの bats テスト完了を待ちます」等) を最後に出力して exit 0 で終了する
3. 2 回とも `run-review.sh` 側の watchdog は発火しない (silent window 1440s/1980s を計上後にプロセス自体が正常終了扱いで終わるため)。`reconcile-phase-state.sh review <issue> --pr <PR> --check-completion` は `matches_expected:false` を返す
4. 2 回目の実行は Step 11 (Post Review Results、MUST 2 件を含むレビュー投稿) まで到達していた。現行の `scripts/post-fallback-review-summary.sh` (`gh pr view --json reviews --jq '.reviews[].body'` で "Acceptance Criteria Verification Results" の存在のみを確認) はこのケースでも証跡ありと判定し、フォールバック投稿の上で `run-review.sh` に exit 0 (recovered) を返してしまう — MUST 2 件は未修正のまま `/merge` 直前まで到達する経路が実在する

## Root Cause

`scripts/run-review.sh:276-289` は `claude` exit 0 + `matches_expected:false` を検出すると `scripts/post-fallback-review-summary.sh "$PR_NUMBER"` を呼び、成功 (exit 0) すれば無条件に recovered (`EXIT_CODE=0`) として扱う。`post-fallback-review-summary.sh` (現行実装) は `gh pr view "$PR_NUMBER" --json reviews --jq '.reviews[].body'` で "Acceptance Criteria Verification Results" という文字列の有無だけを確認しており、**そのレビューが MUST 指摘なしの clean review だったのか、MUST 指摘ありで `event=REQUEST_CHANGES` (state: `CHANGES_REQUESTED`) だったのかを区別していない**。

この結果、Step 11 (レビュー投稿) は完了したが Step 12 (指摘の修正) 以降が silent no-op になったケース (#1168 の 2 回目) では、証跡は「あり」と判定されてしまい、フォールバックが MUST 未解決のまま偽の recovered を報告する。これが Issue の Impact 「#1168 では MUST 2 件が未修正のまま `/merge` 直前まで到達した」の直接の原因である。

なお `skills/review/SKILL.md:39` の Foreground 制約 (候補 A) は既に実装済みであり、本 Spec ではこれを変更しない — Issue 本文の指定通り、実測で単独では不十分と判明した経路への追加強化は行わない。

候補 C (verify-executor 経由への統一) を不採用とした理由は Notes を参照。

## Changed Files

- `scripts/post-fallback-review-summary.sh`: `gh pr view --json reviews` の取得を 1 回にまとめ、最新レビュー (`submittedAt` でソートした末尾) の `state` が `CHANGES_REQUESTED` の場合はフォールバック投稿を行わず exit 2 で終了する MUST 未解決ガードを追加。証跡なし (exit 1) / 投稿成功 (exit 0) の既存分岐は変更しない — bash 3.2+ compatible (追加するのは既存と同じ `gh`/`jq` イディオムのみ)
- `scripts/run-review.sh`: L276-289 の `matches_expected:false` 分岐で `post-fallback-review-summary.sh` の exit code を明示的に捕捉し、exit 2 の場合は同一プロンプト (`$PROMPT`、既存の `claude-watchdog.sh` 呼び出しと同じ構成) で `claude -p` を 1 回だけ再実行してから再度 `reconcile-phase-state.sh --check-completion` を確認する。exit 0/1 の既存分岐は変更しない — bash 3.2+ compatible
- `tests/post-fallback-review-summary.bats`: 既存 3 テストの `gh` mock を `.reviews` の JSON 配列形式 (`state`/`submittedAt`/`body` を持つオブジェクトの配列) に更新 (回帰防止)。MUST 未解決 (最新レビューが `CHANGES_REQUESTED`) → exit 2 かつ `gh pr comment` が呼ばれないことを検証するテスト、および複数レビューのうち最新のみが判定対象になること (古い `CHANGES_REQUESTED` はあるが最新は `COMMENTED` → exit 0 で投稿される) を検証するテストを追加
- `tests/run-review.bats`: `post-fallback-review-summary.sh` mock を exit 2 で返すケースを追加し、(a) 継続リトライ後に `reconcile-phase-state.sh` が `matches_expected:true` を返す (対処が効くケース) → `claude` mock が 2 回呼ばれ最終 exit 0、(b) リトライ後も `matches_expected:false` のまま (対処が効かないケース) → `claude` mock が 2 回呼ばれ最終 exit 1、の 2 テストを追加
- `modules/orchestration-fallbacks.md`: `review-completion-false-negative` エントリの Fallback Steps step 0 (`post-fallback-review-summary.sh` の説明) を、MUST 未解決時は exit 2 を返し `run-review.sh` が 1 回の継続リトライを試みる旨に更新
- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] Scripts セクションの `post-fallback-review-summary.sh` の一行説明 (英語版 L226 / 日本語版 L218) を、MUST 未解決時は投稿せず exit 2 を返す旨を含む記述に更新

## Implementation Steps

1. `scripts/post-fallback-review-summary.sh` に MUST 未解決ガードを追加する (→ 受入条件 A)。既存の `REVIEW_BODIES=$(gh pr view "$PR_NUMBER" --json reviews --jq '.reviews[].body' 2>/dev/null) || true` を、`.reviews` 配列を 1 回だけ取得してから 2 通りに解析する形へ置き換える:

   ```bash
   REVIEWS_JSON=$(gh pr view "$PR_NUMBER" --json reviews --jq '.reviews' 2>/dev/null) || REVIEWS_JSON="[]"

   LATEST_STATE=$(echo "$REVIEWS_JSON" | jq -r 'sort_by(.submittedAt) | last | .state // empty' 2>/dev/null) || LATEST_STATE=""

   if [[ "$LATEST_STATE" == "CHANGES_REQUESTED" ]]; then
       echo "post-fallback-review-summary: latest PR review for #${PR_NUMBER} is CHANGES_REQUESTED (MUST issues outstanding); a fallback summary would falsely declare recovery. Skipping fallback post." >&2
       exit 2
   fi

   REVIEW_BODIES=$(echo "$REVIEWS_JSON" | jq -r '.[].body' 2>/dev/null) || true
   ```

   以降の「証跡なし → exit 1」「証跡あり → 投稿して exit 0」ロジックは変更しない。ヘッダーコメントも exit code 0/1/2 の tri-state を説明するよう更新する。

2. `scripts/run-review.sh` の `matches_expected:false` 分岐 (L276-289) を、`post-fallback-review-summary.sh` の exit code を明示的に分岐する形に変更する (after 1) (→ 受入条件 A):

   ```bash
   set +e
   "$SCRIPT_DIR/post-fallback-review-summary.sh" "$PR_NUMBER"
   _fallback_exit=$?
   set -e
   if [[ $_fallback_exit -eq 2 ]]; then
     echo "post-fallback-review-summary: latest review is CHANGES_REQUESTED (MUST issues outstanding); retrying the review session once instead of a fallback post." >&2
     # 既存の claude -p 呼び出し (AUTO_EVENTS_LOG 有無で分岐する2ブロック、L239-263と同一構成) を
     # 同じ $PROMPT・$PERMISSION_FLAG で1回だけ再実行する。重複コードを避けるため、
     # 呼び出しをローカル関数に切り出して初回呼び出しとこのリトライの両方から呼ぶことを推奨する。
     # (関数化は実装の自由度に委ねる — Spec ではリトライが $PROMPT をそのまま再利用する点のみ必須)
     _recheck_out=$("$SCRIPT_DIR/reconcile-phase-state.sh" review "$_REVIEW_ISSUE" --pr "$PR_NUMBER" --check-completion 2>/dev/null) || true
     if echo "$_recheck_out" | grep -q '"matches_expected":true'; then
       echo "review retry: recovered after one continuation retry. recheck: $_recheck_out"
       EXIT_CODE=0
     else
       echo "review retry: still does not match expected after one retry. recheck: $_recheck_out" >&2
       EXIT_CODE=1
     fi
   elif [[ $_fallback_exit -eq 0 ]]; then
     # 既存の recheck → EXIT_CODE=0/1 分岐をそのまま維持
     ...
   else
     EXIT_CODE=1
   fi
   ```

   同一プロンプトを再利用する ($PROMPT をそのまま渡す) ことで、Step 2 (Worktree Entry) が既存の stale worktree 再利用ロジック (`modules/worktree-lifecycle.md`) をそのまま踏襲でき、リトライ専用の resume プロンプトを新設した場合に生じる worktree 二重管理・作業コミット消失リスクを避ける (詳細は Notes 参照)。

3. `tests/post-fallback-review-summary.bats` の既存 3 テストの `gh` mock を `.reviews` JSON 配列形式に更新し、新規 2 テストを追加する (after 1) (→ 受入条件 C, D):
   - 既存 3 テストの `gh pr view` mock 出力を `echo '[{"state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z","body":"..."}]'` 形式に置き換える (bare text ではなく妥当な JSON 配列にする)
   - 新規: 最新レビューが `CHANGES_REQUESTED` → `run bash "$SCRIPT" 123` の `$status` が `2`、かつ `gh pr comment` が呼ばれていないことを確認
   - 新規: 複数レビューのうち古い方が `CHANGES_REQUESTED`・最新が `COMMENTED` (かつ AC Verification Results を含む) → `$status` が `0` で投稿される (「最新のみ判定対象」の回帰防止)

4. `tests/run-review.bats` に `post-fallback-review-summary.sh` mock が exit 2 を返すケースの新規 2 テストを追加する (after 2) (→ 受入条件 C, D):
   - 「対処が効くケース」: `reconcile-phase-state.sh` mock を呼び出し回数で分岐させ (既存の `"reconcile: fallback post succeeds..."` テスト L590-616 と同じ call-count パターン)、1 回目 `matches_expected:false` → 2 回目 `matches_expected:true` を返すようにする。`run bash "$SCRIPT" 123` の `$status` が `0`、かつ `$CLAUDE_CALL_LOG` 内の `FLAG_P=1` 出現回数が 2 であることを確認
   - 「対処が効かないケース」: 同じ mock 構成で 2 回目も `matches_expected:false` を返すようにする。`$status` が `1`、かつ `FLAG_P=1` 出現回数が 2 であることを確認

5. `modules/orchestration-fallbacks.md` の `review-completion-false-negative` エントリの Fallback Steps step 0、および `docs/structure.md` L226 / `docs/ja/structure.md` L218 の `post-fallback-review-summary.sh` 一行説明を、MUST 未解決時は投稿せず exit 2 を返し `run-review.sh` が 1 回の継続リトライを試みる旨に更新する (after 1, 2 と並行可能) (→ 受入条件 A)。`scripts/detect-wrapper-anomaly.sh` (L82-86) の `review-completion-false-negative` 検出条件は「ログ中に `matches_expected:true` が一切現れない」ことのみを見ており、リトライ経由の回復もリトライ失敗による恒久的な失敗報告も既存ロジックのまま正しく扱えることを確認済み (grep 済み、`scripts/detect-wrapper-anomaly.sh` / `tests/detect-wrapper-anomaly.bats` は変更不要)

## Verification

### Pre-merge

- <!-- verify: rubric "採用した方針が実装され、非対話モードの /review がバックグラウンドタスク完了待ちで turn を終える経路が塞がれている" --> 完了待ちによる silent no-op 経路が塞がれている
- <!-- verify: rubric "採用しなかった候補について不採用の判断根拠が Spec または Issue に記録されている" --> 不採用根拠が記録されている
- <!-- verify: rubric "tests/ 配下に、対処が効くケースと効かないケース (または対処前後) を区別して検証するテストが存在する" --> 検証テストが追加されている
- <!-- verify: command "bats tests/" --> テストスイート全件が PASS する

### Post-merge

- 次回以降の `/review --full` 実行で、テストのバックグラウンド化による silent no-op が発生しないことを観察する <!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - `run-review.sh` が Response Summary の投稿まで到達し、`reconcile-phase-state.sh review --check-completion` が `matches_expected: true` を返す (MUST 未解決のまま偽の recovered 報告にはならない — エージェントが直接完了したか、1 回の継続リトライで回復した場合のみ true になる)

## Notes

### 候補選定の根拠 (受入条件 A・B に対応)

- **候補 A (プロンプト側で明示) — 不採用 (追加強化なし)**: `skills/review/SKILL.md:39` に既に実装済みで `run-review.sh:201` 経由でプロンプトに含まれているが、#1168 (2026-08-05) で 2/2 再現しており、LLM の遵守のみに依存する方式は単独では不十分と実測された。Issue 本文の指定通り、本 Spec では追加の強化を行わない。
- **候補 B (wrapper 側で検出して継続を促す) — 採用**: `scripts/run-review.sh` は既に `matches_expected:false` を検出し `post-fallback-review-summary.sh` を呼ぶ機構を持つが、その証跡ガードが「レビュー投稿の有無」しか見ておらず「MUST 未解決」を見逃す欠陥があった (Root Cause 参照)。この欠陥を塞ぎ、MUST 未解決時は同一プロンプトで 1 回だけ継続リトライする形で実装する。`retry-on-kill.sh` (SIGTERM/SIGKILL 検出 + 1 回リトライ) と同種の、既にこのコードベースで実績のある wrapper 層パターンを踏襲する。
  - **保証の範囲**: このリトライは「必ず成功する」ことを保証しない。#1168 の 2 回の実測はいずれも `run-review.sh 1173 --full` の独立した試行であり、うち 2 回目 (レビュー投稿後に停止) は本 Spec のリトライが対象とする状態と同一の停止パターンである。したがって同一プロンプトでの再試行が同じ理由で再度失敗する可能性は残る。ただし本 Spec の核心的な改善は「MUST 未解決を偽の recovered として報告しない」という正しさの回復であり、リトライはこの正しさを損なわずに自動回復の機会を追加するものである — リトライが失敗しても `EXIT_CODE=1` として正しく失敗報告され、Tier 2/3 リカバリ (`modules/orchestration-fallbacks.md#review-completion-false-negative`) にエスカレーションされる。
  - Issue 本文の候補 B は「出力末尾がバックグラウンド待ち文言に一致する場合」という自由文字列パターンマッチを示唆していたが、本 Spec では既存の `reconcile-phase-state.sh` の構造化シグナル (`matches_expected`) と GitHub PR レビューの `state` フィールドを組み合わせる方式を採用した。ローカライズやフレーズのゆらぎに影響されない、より頑健な検出方法であり、既存の `post-fallback-review-summary.sh` / `reconcile-phase-state.sh` インフラをそのまま拡張できる。
  - リトライ時に新規の resume 専用プロンプトを組み立てる案 (Step 12 からの再開を指示する短いプロンプト) も検討したが、`.tmp/review-body-$NUMBER.md` 等の中間ファイルは Step 11 終了時に削除済みであり、resume プロンプトは worktree の再利用判定を独自に実装する必要が生じる。既存の `$PROMPT` (SKILL.md 全文) をそのまま再利用すれば、Step 2 (Worktree Entry) の既存 stale worktree 再利用ロジックがそのまま機能し、正しさ (作業消失・worktree 二重管理の回避) を優先してこちらを採用した。代償として、リトライ成功時に Step 10 のレビューが再実行され PR に 2 件目のレビューコメントが投稿される場合があるが、これは既存の手動リカバリ手順 (`modules/orchestration-fallbacks.md#review-completion-false-negative` Fallback Step 4「/review を再実行する」) と同じ挙動であり許容する。
- **候補 C (`/review` のテスト実行を verify-executor 経由に寄せる) — 不採用**: `modules/verify-executor.md` の `command "cmd"` は safe mode (非対話モードで `/review` が使うモード) では **コマンドを実行せず無条件で UNCERTAIN を返す** (`modules/verify-executor.md` の command 型定義: "safe → attempt CI reference fallback... return UNCERTAIN if no match")。Step 12.3 (Lightweight Re-check) のテスト再実行を verify-executor 経由に統一すると、非対話モードではテストが一切実行されなくなり、現状 (バックグラウンド化はするが実行はされる) より悪化する。また Step 12.3 の「修正後の回帰確認」は Issue の受入条件文字列を検証する verify-executor の対象範囲 (Issue AC の `<!-- verify: ... -->` 変換) と用途が異なり、素直に適用できない。Issue 本文自身も「適用範囲が広く影響も大きい」と記しており、Size M の本 Issue には不釣り合いと判断した。

### 検証済みの外部仕様

- `gh pr view <PR> --json reviews` が返す各レビューオブジェクトの `state`/`submittedAt`/`body` フィールドは、本リポジトリの実 PR (#1184) に対する live 実行で実在を確認済み (`state: "COMMENTED"`, ISO 8601 の `submittedAt`)。`CHANGES_REQUESTED` は `scripts/gh-pr-review.sh:102` の `EVENT="REQUEST_CHANGES"` 投稿に対応する GitHub API の標準 review state 値。

### 影響範囲の確認 (変更不要と判断したファイル)

- `scripts/detect-wrapper-anomaly.sh` (L82-86) の `review-completion-false-negative` 検出は「ログ中に `matches_expected:true` が一切現れないこと」のみを条件としており、本 Spec のリトライが成功した場合 (`matches_expected:true` を含む行がログに残る) は既存の reconcile-first-authority による抑止がそのまま働く。リトライが失敗した場合は既存どおり anomaly が正しく検出される。`tests/detect-wrapper-anomaly.bats` を含め変更不要 (grep 済み)。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — Background の事実訂正 (候補 A 実装済み・実測で不十分) と Post-merge observation への `session=next` 付与が既に Issue 本文へ反映済みであることの確認。Size=M のため分割不要との判断も記載。本 Spec の調査・方針選定に新たな決定事項の追加はなし / https://github.com/saitoco/wholework/issues/1175#issuecomment-5199172397
- `/code` フェーズ開始時の cutoff (最新 `phase/ready` ラベル付与時刻) 以降に新規コメントなし。

## Code Retrospective

### Deviations from Design
- N/A — Spec の Implementation Steps 1・2 に記載された bash 疑似コードをほぼそのまま採用した。Step 2 で Spec が「関数化は実装の自由度に委ねる」としていた点について、`claude -p` 呼び出し (`AUTO_EVENTS_LOG` 有無の2分岐を含む) を `_run_claude_review_session()` 関数に切り出し、初回呼び出しと継続リトライの両方から呼ぶ形にした。これは Spec が許容していた選択肢の採用であり、設計からの逸脱ではない。

### Design Gaps/Ambiguities
- N/A — Spec の bash 疑似コードが exit code 分岐・リトライ後の再チェックロジックまで具体的に記述しており、実装時に解釈の余地があった箇所はなかった。

### Rework
- N/A — 各 Implementation Step は一発で bats テスト PASS に到達し、手戻りは発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC ゲート (`check-pre-merge-ac.sh 1175`) は 4 件全てチェック済みで unchecked_count=0、`gh-pr-merge-status.sh` は `mergeable=true reason=clean ci_status=success review_status=approved` だったため、conflict 解消・追加リトライなしで Step 4 のスカッシュマージへ直行した。
- review フェーズで残されていた SHOULD 2 件・CONSIDER 3 件 (`CHANGES_REQUESTED` sticky state の限定範囲、`LATEST_STATE` の author filter 欠如、token usage 上書き 等) は、いずれも MUST 未満と判定済みでマージのブロッカーではないと判断し、本 merge フェーズでは対応しなかった。

### Deferred Items
- Post-merge observation AC (`session=next`、次回 `/review --full` 実行での silent no-op 非発生観察) は引き続き未評価のまま — 次回セッションでの `/review --full` 実行時に評価される。
- review フェーズで指摘された SHOULD 2 件・CONSIDER 3 件 (`CHANGES_REQUESTED` sticky state の限定範囲を Spec に明記、`LATEST_STATE` の author filter 追加、token usage 上書き、ドキュメント精度、docs/workflow.md・orchestration-fallbacks.md 更新) は別 Issue 化が未実施のまま残っている。

### Notes for Next Phase
- `/verify 1175` 実行時、Post-merge observation AC は次回の `/review --full` 実行で自然に検証される設計であり、`/verify` フェーズで能動的に発火させる必要はない。
- review フェーズで指摘された author filter 欠如 (severity 最高の残存ギャップ) は、別 Issue 化を検討する価値がある — 本 Issue #1175 のスコープでは対応していない。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — review-spec の Perspective 1 (Spec Deviation) 監査で構造的な逸脱は検出されなかった。Changed Files・Implementation Steps は PR 差分と完全一致し、`_run_claude_review_session()` への関数化も Spec が明示的に許容していた選択肢の範囲内だった。

### Recurring issues

2 体の review-bug エージェント (diff scan / security scan) が、互いに独立した探索でありながら同一の SHOULD 級指摘に収斂した:

- `scripts/post-fallback-review-summary.sh:36` の `CHANGES_REQUESTED` が sticky な GitHub review state であり、Step 12 で MUST を修正しても Step 14 (`gh pr comment` のみ) では変化しないため、「Step 11 到達後に MUST が解決済みだが Step 14 のみ silent no-op」という最も軽微なケースでも常にフルリトライが発火する設計上の非効率
- `scripts/run-review.sh:245` の継続リトライが `TOKEN_USAGE_FILE` を上書きし、初回セッションのトークン使用量が `run-auto-sub.sh` の `token_usage` イベントから欠落する

いずれも 4 体の独立検証サブエージェント (general-purpose) で PASS (問題として確認) と判定された。加えて 1 体のエージェントのみが検出した `LATEST_STATE` の author filter 欠如 (外部レビュー連携有効時に第三者レビューが Claude 自身の `CHANGES_REQUESTED` を覆い隠しうる) も検証で PASS だった — 単一エージェントの検出だったが、これは本 Issue が塞ごうとした「MUST 未解決を偽の recovered として報告する」バグを別経路で再導入しうる、最も severity の高い残存ギャップだった。

いずれも MUST には至らない (安全側に倒れる設計のため実害はないか、現行 `.wholework.yml` の設定では到達しない) が、Spec の Notes「保証の範囲」がリトライ失敗のリスクのみを議論し、これら 3 点 (state の非可逆性・author 未フィルタ・token usage 上書き) を扱っていなかった点は Spec 記述の抜けとして記録に値する。

### Acceptance criteria verification difficulty

Nothing to note — 4 件の Pre-merge 条件は `rubric` × 3 + `command "bats tests/"` × 1 の組み合わせで、いずれも UNCERTAIN なく PASS 判定に到達した。`command` 型は safe mode のため CI 参照フォールバック (`Run bats tests` ジョブの SUCCESS) で代替検証できた。verify command の記述・実行に起因する追加コストはなかった。
