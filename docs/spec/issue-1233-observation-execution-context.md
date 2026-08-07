# Issue #1233: observation-trigger: when= 条件ゲートに execution-context 軸を追加

## Overview

`modules/observation-trigger.md` の `when=<axis>:<value>` 条件ゲートは現状 `route` / `mode` / `recovery-tier` の3軸のみを宣言可能で、いずれも `scripts/collect-run-facts.sh` が生成する `/auto` run facts JSON から解決される。`/review` が発火する `pr-review-full`/`pr-review-light` イベント (`skills/review/SKILL.md:902-903`) はこの facts JSON を紐付ける `--session`/`--facts-file` を一切渡していないため、実行文脈 (main/fork) に依存する observation AC (例: Issue #575 の Workflow 経路完走確認) を `when=` で表現する手段がなく、fork context (`/auto` 経由の通常運用では常にこちら) でも無条件に dispatch → SKIPPED を繰り返す。

本 Issue は `when=` に新軸 `execution-context` (`main`/`fork`) を追加する。route/mode/recovery-tier は `/auto` run 全体に属する事実だが、execution-context は「発火元スキル自身の実行文脈」という個別呼び出しのプロパティであり、`collect-run-facts.sh` の facts JSON とは性質が異なる。そのため execution-context は facts JSON を経由せず、発火元スキルが `modules/execution-context.md` の Context Detection (`ARGUMENTS` に `--non-interactive` が含まれるか) で判定した値を新規 `--execution-context <main|fork>` 引数として直接渡し、`opportunistic-search.sh` がそれを直接比較する設計とする。

## Changed Files
- `scripts/opportunistic-search.sh`: `--execution-context <main|fork>` オプションを追加し、`when=execution-context:<value>` 節を `collect-run-facts.sh` を経由せず直接比較で評価する。既存の `route`/`mode`/`recovery-tier` 節評価も合わせて再構成する (詳細は Implementation Steps 1)。bash 3.2+ compatible
- `scripts/observation-trigger.sh`: `--execution-context <main|fork>` オプションを追加し、既存の `--session` と同じ受け渡し形で `opportunistic-search.sh` へ透過的に渡す。bash 3.2+ compatible
- `skills/review/SKILL.md`: Opportunistic Verification 内の Event-based observation scan (L902-903、`pr-review-full`/`pr-review-light` の2箇所) で `EXECUTION_CONTEXT` を判定し `--execution-context` を追加する
- `modules/observation-trigger.md`: § Condition Check Gate (`when=`) の Declarable axes テーブル・Arguments テーブル・Matching specification に `execution-context` 軸を追加し、既存の「facts JSON 経由でのみ解決される」旨の記述を execution-context には適用されない形に修正する (Steering Docs sync candidate — `docs/`/`tests`/`scripts` 対象の機械的 grep 範囲外の `modules/` 配下だが、変更対象スクリプト自身のコメントがこのファイルを参照ドキュメントとして名指ししているため、直接調査で発見し Changed Files に追加。先行する Issue #1234 の Spec と同じ扱い)
- `tests/opportunistic-search.bats` / `tests/observation-trigger.bats`: 新軸・新引数のカバレッジを追加 (詳細は Implementation Steps 5)

## Implementation Steps

1. `scripts/opportunistic-search.sh` に `EXECUTION_CONTEXT_ARG=""` 変数と `--execution-context` の CLI パース (既存の `--session` と同じ必須引数チェックパターン) を追加する。続けて `when=` 節評価ループを次のとおり再構成する (現状は `resolve_run_facts` を `WHEN_ATTR` 非空時に無条件先出し呼び出しし、その結果が空なら節ループ全体をスキップして gate 全体を fail-open — 全節が facts JSON 依存という前提の構造):
   - `WHEN_MATCH=true` を `WHEN_ATTR` 非空判定の直後 (facts 解決を待たず) に設定する
   - `resolve_run_facts` の呼び出しを、ループ先頭から `route`/`mode`/`recovery-tier` の `case` アーム内部 (既存の jq 判定の直前) に移す。同関数は `RUN_FACTS_RESOLVED` guard によりプロセス内で1回しか実際には実行されないため、呼び出し位置を遅延させても複数回実行にはならない
   - `route`/`mode`/`recovery-tier` の各アームで `resolve_run_facts` 呼び出し直後に `[ -z "$RUN_FACTS_JSON" ]` なら `continue` (既存の "run facts unavailable" 警告は `resolve_run_facts` 内で既に出力される。この節のみ無視 — 従来の gate 全体 fail-open ではなく節単位の fail-open に変わるが、単一節の AC (既存 bats 実測範囲) では観測結果は変わらない)
   - 新規 `execution-context)` アームを追加: `EXECUTION_CONTEXT_ARG` が空なら `Warning: --execution-context not given, ignoring when=execution-context clause` を stderr に出力して次節へ (節単位 fail-open)。非空なら `[ "$EXECUTION_CONTEXT_ARG" != "$WHEN_VALUE" ]` のとき `WHEN_MATCH=false`
   - ループ終了後の `if [ "$WHEN_MATCH" = false ]; then continue; fi` は `WHEN_ATTR` 非空ブロックの末尾 (旧 `if [ -n "$RUN_FACTS_JSON" ]` の外) に1回だけ残す
   (→ acceptance criteria 1, 2)
2. `scripts/observation-trigger.sh` に `EXECUTION_CONTEXT=""` 変数と `--execution-context` の CLI パースを追加し、非空のとき `SEARCH_ARGS+=(--execution-context "$EXECUTION_CONTEXT")` として `opportunistic-search.sh` へ転送する (既存の `--session`/`SESSION_ID` と同型) (→ acceptance criteria 1, 2)
3. `skills/review/SKILL.md` の Opportunistic Verification § Event-based observation scan で、`--event pr-review-full`/`--event pr-review-light` 呼び出し (L902-903) の直前に「`modules/execution-context.md` § Context Detection に従い、`ARGUMENTS` に `--non-interactive` が含まれれば `EXECUTION_CONTEXT=fork`、含まれなければ `EXECUTION_CONTEXT=main`」の判定を追加し、両呼び出しに `--execution-context "$EXECUTION_CONTEXT"` を追加する (→ acceptance criteria 1, post-merge acceptance criteria)
4. `modules/observation-trigger.md` § Condition Check Gate (`when=`) を更新する:
   - Declarable axes テーブルに `execution-context` 行を追加 (Fact JSON field 列は「facts JSON 不使用、`--execution-context` 引数から直接解決」である旨を明記、Values 列は `main` \| `fork`)
   - 「Arguments table addition (both scripts)」テーブルに `--execution-context <main\|fork>` 行を追加 (説明: 発火元スキル自身の実行文脈を渡す引数。`when=execution-context:<value>` 節を facts JSON を経由せず直接比較する。`observation-trigger.sh` は as-is で転送)
   - 「`opportunistic-search.sh` matches `when=` clauses against the run facts JSON ... It never collects its own execution context independently.」の一文を修正: この記述は `route`/`mode`/`recovery-tier` 軸にのみ適用され、`execution-context` 軸は発火元スキルが明示的に渡す `--execution-context` 引数から直接解決される (facts JSON 不使用) 旨を明記
   - Matching specification に `execution-context:<v>` の比較仕様 (`--execution-context` 引数値との直接比較、未指定時は当該節のみ無視する節単位 fail-open) を追記し、既存の「Fail-open (unconditional match) when: run facts cannot be resolved」の記述が `route`/`mode`/`recovery-tier` 節にのみ適用される節単位 fail-open に変わったことを明記
   - 「`when=` presumes `event=auto-run`」の注記に、この前提は `route`/`mode`/`recovery-tier` 軸にのみ適用され、`execution-context` 軸は `event=auto-run` を前提としない (`pr-review-full`/`pr-review-light` など発火元スキルが main/fork いずれでも動作しうるイベントに対して意味を持つ) 旨を追記
   (parallel with 1, 2, 3) (→ acceptance criteria 1, 2)
5. `tests/opportunistic-search.bats` に以下の `@test` を追加する (既存の "when gate: ..." 群と同じスタイル):
   - "when gate: execution-context matches includes the issue" (`when=execution-context:main` + `--execution-context main` → 含まれる)
   - "when gate: execution-context mismatch excludes the issue" (`when=execution-context:main` + `--execution-context fork` → 除外される)
   - "when gate: execution-context clause without --execution-context flag fails open with a warning" (`when=execution-context:main`、`--execution-context` 未指定 → 含まれる + 警告)
   `tests/observation-trigger.bats` に既存の "forwarding: --session ..." 対と同型で以下を追加する:
   - "forwarding: --execution-context is forwarded to opportunistic-search.sh"
   - "forwarding: no --execution-context means opportunistic-search.sh is called without it"
   (after 1, 2) (→ acceptance criteria 1, 2)

## Verification

### Pre-merge
- <!-- verify: rubric "modules/observation-trigger.md の when= 宣言可能軸に execution-context (main/fork) を判定する手段が追加されている、または AC 条件文レベルでの運用ルールが SSoT ドキュメントに明記されている" --> execution-context 軸の追加、または代替運用ルールが記録されている
- <!-- verify: grep "execution-context" "modules/observation-trigger.md" --> `when=` 宣言可能軸のドキュメントが更新されている

### Post-merge
- 次回 fork context で発火した `event=pr-review-full` (または類似の main-context 限定条件を持つ) observation AC が、`/verify` 実行時に誤って UNCERTAIN/SKIPPED を繰り返さず適切に扱われることを観察する <!-- verify-type: observation event=pr-review-full session=next -->

## Notes

- **AC2 の verify command 修正**: Issue 本文の AC2 は当初 `<!-- verify: grep "when=" "modules/observation-trigger.md" -->` だったが、`modules/observation-trigger.md` には既存の3軸 (route/mode/recovery-tier) の記述として `when=` という文字列が実装前から16箇所以上存在するため、実装内容に関わらず常時 PASS してしまう Pattern 2 (常時PASS) に該当することが triage フェーズの AC audit コメント (Consumed Comments 参照) で指摘済みだった。同コメントは「どちらの語句にするかは `/spec`/`/code` 側で確定させるのが妥当」と明記し判断を本フェーズに委ねていたため、本 Spec で `execution-context` 軸の追加を採用したことを踏まえ `grep "execution-context" "modules/observation-trigger.md"` に修正した (`execution-context` は実装前時点で同ファイルに一致なしを grep で確認済み — 実装後にのみ真になる)。Issue 本文側の AC2 も本 Spec 作成と同時に `gh-issue-edit.sh` で同内容に同期する
- **facts JSON を使わない設計判断の根拠**: (1) `/review` の event 発火呼び出し (`skills/review/SKILL.md:902-903`) は `--session`/`--facts-file` を渡していない。仮に execution-context を facts JSON 経由にすると `collect-run-facts.sh` の無引数フォールバック (`AUTO_SESSION_ID` env var → `.tmp/auto-session-current` pointer file) に依存することになり、`/review` を `/auto` 経由でなく直接実行した main context のケースでは無関係な/存在しないセッションポインタを参照する fail-open 状態になりかねない。(2) `docs/tech.md` のフォーク方針表により `/auto` 経由の `/review` は常に fork context で実行されるため、route/mode/recovery-tier と異なり execution-context は「`/auto` run 全体の事実」ではなく「個々のスキル呼び出しの事実」であり、発火元スキル自身が `modules/execution-context.md` の Context Detection で直接判定できる。facts JSON を経由させるより発火元から直接渡す方が正確かつ `collect-run-facts.sh` の不要な呼び出し (spurious warning) も避けられる
- **スコープ外 (フォローアップ候補)**: 本 Issue の検出元である Issue #575 (CLOSED、`phase/verify` のまま) の既存 observation AC (`event=pr-review-full config=capabilities.workflow`) 自体に `when=execution-context:main` を追記するリトロフィットは、本 Issue の Acceptance Criteria に含まれないためスコープ外とした。次回 `/verify 575` 実行時に手動で追記を検討する余地がある
- **`skills/auto/SKILL.md` の `event=auto-run` 呼び出し (L745, L1215) は対象外**: `/auto` 自身は `docs/tech.md` のフォーク方針表で常に in-session (fork不要) と分類されるため、`event=auto-run` に対する execution-context は常に `main` の定数となり、`when=` 軸として宣言する意味を持たない。#1234 の `--session` (route/mode/recovery-tier に必要) とは非対称なスコープ判断であり、意図的に対象から除外した
- **「変更不要」と判定したファイル (grep で事前確認済み)**: `docs/structure.md` (module 説明は "caller interface, emitter lookup, and dispatch contract" という一般的表現のままで正確) / `docs/guide/customization.md` (grep 一致は `--when="test -n ..."` という無関係な verify command 修飾子のみ、`when=<axis>:<value>` ゲートの CLI フラグ単位の記述はない) / `docs/migration-notes.md` (private→public repo 移行 (#6) 専用の Interface Changes 追跡記録であり、通常の機能追加の対象ではない) / `scripts/claude-watchdog.sh` (`--event watchdog-kill` は `--facts-file`/`--session` も渡しておらず、`--execution-context` も同様に不要 — watchdog は fork context 実行のみを監視するため execution-context は定数) / `scripts/get-config-value.sh` (`config=` ゲート専用、本変更で `.wholework.yml` キーは追加しない) / `tests/verify.bats` (`opportunistic-search.sh --event` という文字列が `skills/verify/SKILL.md` の別セクションに含まれるかを見るテストで CLI 引数とは無関係)
- **bash 互換性**: `scripts/observation-trigger.sh` / `scripts/opportunistic-search.sh` はいずれも既存の `case` 文ベースの引数パースを踏襲するため bash 3.2+ (macOS system bash) 互換を維持する
- **SPEC_DEPTH=light 自動判定**: Size=M (pr route) のため `--light`/`--full` 未指定でも light に auto-detect。Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はいずれも light のためスキップ

## Consumed Comments
- saito (MEMBER, first-class): Issue Retrospective (triage フェーズ)。Background の事実確認2件が実装と一致することを確認 (警告なし)。Post-merge AC の `verify-type: observation event=pr-review-full` に `session=next` を追記 (`modules/observation-trigger.md` が `/auto`/`/review`/`/verify` の3 skill から参照される共有モジュールであるため、skill self-update propagation rule に該当) — https://github.com/saitoco/wholework/issues/1233#issuecomment-5218237672
- saito (MEMBER, first-class): Triage AC audit (非破壊警告)。AC2 の verify command (`grep "when=" "modules/observation-trigger.md"`) が既存3軸の記述により実装前から常時 PASS してしまう Pattern 2 に該当することを指摘。修復案として実装後にのみ真になる具体的な文字列への変更を提案し、語句の確定を `/spec`/`/code` フェーズに委ねた。本 Spec の Notes と Verification で `execution-context` への修正として反映済み — https://github.com/saitoco/wholework/issues/1233#issuecomment-5218270335

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-5 をそのまま実装。when= 節評価ループの再構成 (`resolve_run_facts` を case アーム内へ遅延、execution-context アーム新設) も Spec 記述どおりの構造で反映した

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

### Test Execution Note
- `bats --jobs 18 tests/` によるフルスイート実行 (behavioral change 検出: `skills/review/SKILL.md` を `tests/review.bats` 以外に `tests/run-review.bats` も参照していたため発火) で `tests/post_merge_check.bats` の1テストが実行ごとに異なるケースで間欠的に FAIL した (`gh issue reopen called when FAIL input given` → 次回実行では `multiple issues: processed sequentially`)。単体実行 (`bats tests/post_merge_check.bats`) では10/10 安定して PASS し、本 Issue の変更対象ファイル (`scripts/opportunistic-search.sh` / `scripts/observation-trigger.sh` / `skills/review/SKILL.md` / `modules/observation-trigger.md`) とは無関係。既存 Issue #1255 (「並列 bats 実行下でのみ落ちる flaky を機械的に切り分ける」) が同種の事象を追跡対象としているため、重複 follow-up Issue は起票していない

## review retrospective

### Spec vs. implementation divergence patterns
- 大きな乖離はなし。Implementation Steps 1-5 は Spec 記述どおりに実装され、Changed Files も Spec の列挙と一致した
- 唯一の軽微なギャップ: Spec の Changed Files には `modules/observation-trigger.md` (変更対象スクリプトのコメントが直接参照するため発見) が含まれていたが、`modules/verify-classifier.md` (`when=` の AC 起票ガイダンス SSoT で、`/issue`/`/spec` から参照される) と `modules/run-fact-matching.md` (facts JSON 消費の説明文書) は Spec 調査時に発見されず、review-spec/review-bug 双方が独立に指摘した。`when=` のような複数ドキュメントに跨る概念変更では、変更対象ファイル自身の直接参照だけでなく「同じ概念 (`when=`) を説明する他ドキュメント」への横断 grep (`grep -rl "when="  modules/ docs/` 等) を Spec 調査段階で行う価値がある

### Recurring issues
- review-bug×2 (diff scan / security scan) が独立に同一指摘 (`scripts/opportunistic-search.sh:442` の `execution-context` 値未検証による無警告 fail-closed) を報告したが、アドバーサリアル検証で false positive と判定された (唯一の呼び出し元が main/fork の固定リテラルを渡す設計のため、不正値が実際には到達しない)。2エージェントが同じ箇所に着目したこと自体は「未検証の文字列比較」という表層パターンへの反応であり、実際の呼び出し元コンテキストを追わないと誤検知しやすい典型例。find/filter separation の設計 (finder は網羅重視、verifier が個別呼び出し元を確認して除外) が意図通り機能した事例として記録

### Acceptance criteria verification difficulty
- 2件の Pre-merge AC (rubric + grep) はいずれも明確に PASS/FAIL 判定可能で、UNCERTAIN や verify command の不備は発生しなかった
- `ac-tier: preview` 系の AC は存在せず、preview 未検証マーカーの投稿判断も不要だった

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC ゲートは2件とも `[x]` 済みで `unchecked_count=0`、review-incomplete-fallback も検出されなかったためゲート通過は無条件で成立した
- PR #1267 の CI は `tests/reconcile-phase-state.bats` の1テスト (`issue completion: phase/issue label present -> matches_expected true`) のみ failing だったが、同一 PR の別 CI 実行では全 PASS しており本 PR の変更対象ファイルとは無関係と判断。non-interactive ポリシー (ci_failing は conflicts 以外の理由として自動解決対象) に従いマージを試行し、Auto-Resolve Log を Issue #1233 にコメント投稿した上で squash merge を実行した
- ブランチ削除・Issue クローズは `gh pr merge --squash --delete-branch` の `closes #1233` 記載により自動処理される想定

### Deferred Items
- Post-merge AC (`verify-type: observation event=pr-review-full session=next`) は引き続き未観測 — 次回 fork context での `pr-review-full` 発火時に `when=execution-context:main` AC が UNCERTAIN/SKIPPED を繰り返さないことの確認が必要 (review フェーズから継続)
- `tests/post_merge_check.bats` および `tests/reconcile-phase-state.bats` の並列実行下 flaky は既存 Issue #1255 の追跡対象 (code/review フェーズから継続)
- CONSIDER 3件 (mixed-axis when= テストカバレッジ不足、Spec Notes の /verify 呼び出し元未記載、`modules/run-fact-matching.md` の facts JSON 説明の軽微な誤解可能性) は低リスクと判断し未対応のまま

### Notes for Next Phase
- `/verify 1233` 実行時、Pre-merge AC 2件は既に `[x]` 済みのため再検証は不要。Post-merge AC (observation) の観測結果に注目すること
- CI の間欠的 flaky (`reconcile-phase-state.bats` 含む) が再発する場合は Issue #1255 側での切り分けが優先
