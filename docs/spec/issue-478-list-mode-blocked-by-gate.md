# Issue #478: auto: List mode Blocked-by Gate for Manual Post-merge Pending

## Overview

`/auto --batch N1 N2 ...` の List mode において、blocked-by 先 Issue が manual post-merge 条件未完了（`phase/verify` OPEN 等）のまま次 Issue の処理を開始してしまう問題を修正する。

修正方針（Option A）: 各 Issue の `run-auto-sub.sh` 実行前に、Issue body の blocked-by 関係を確認する。blocker が CLOSED または `phase/done` であれば処理続行、それ以外はスキップして `remaining` に保持し、`/auto --batch --resume` で再試行可能にする。

## Reproduction Steps

1. `/auto --batch A B C` を実行（B は `blocked-by A`、C は `blocked-by A`）
2. A の `run-auto-sub.sh` が exit 0 で完了するが、A の post-merge 条件に `verify-type: manual` が含まれており `phase/verify` OPEN のまま
3. List mode は A の exit 0 を「処理完了」とみなし、即座に B の処理を開始してしまう

## Root Cause

`run-auto-sub.sh` は verify を親セッションに委ねて exit 0 するため（issue #485）、exit 0 が A の manual post-merge 条件完了を意味しない。`### List mode` のステップに blocked-by の phase 状態チェックが存在しない。

## Changed Files

- `skills/auto/SKILL.md`: `### List mode` に blocked-by フェーズチェック（新ステップ 4）を追加；旧ステップ 4→5、5→6 に番号繰り下げ — bash 3.2+ 互換（awk/grep のみ使用）
- `tests/auto-batch.bats`: blocked-by チェックの構造テスト 3 件追加
- `docs/workflow.md`: `--batch N1 N2 ...` の説明に blocked-by ゲートの記述を追加
- `docs/ja/workflow.md`: `docs/workflow.md` と同箇所を日本語で同期更新

## Implementation Steps

1. `skills/auto/SKILL.md` の `### List mode` に新ステップ 4「Blocked-by check」を追加（→ AC 1, 2, 3）:
   - 現在のステップ 4（`run-auto-sub.sh`）の直前に挿入。旧ステップ 4 → 5、旧ステップ 5 → 6 に繰り下げ。
   - 新ステップ 4 の内容:
     - Issue body から "blocked by #N" パターン（大文字小文字無視）で blocker 番号を抽出:
       `gh issue view $NUMBER --json body -q '.body' | grep -ioE "blocked by #[0-9]+" | grep -oE "[0-9]+"` 
     - blocker が存在しない場合はスキップ（次のステップへ）
     - 各 blocker について: `gh issue view $BLOCKER --json state,labels -q '{state: .state, phases: [.labels[].name | select(startswith("phase/"))]}'`
       - CLOSED または labels に `phase/done` を含む → ゲート解除（次の blocker をチェック）
       - それ以外 → 警告を出力して当該 Issue をスキップ（`update_batch` は呼ばない — `remaining` に保持）:
         ```
         Warning: #$NUMBER blocked by #$BLOCKER which is $BLOCKER_PHASE (manual post-merge pending). Skipping #$NUMBER. After completing #$BLOCKER manually, resume with /auto --batch --resume.
         ```
         （$BLOCKER_PHASE は blocker の `phase/*` ラベルまたは OPEN 状態から取得）

2. `tests/auto-batch.bats` に 3 件の `@test` を追加（→ AC 5 の CI 通過）:
   - `@test "List mode section: blocked-by check present"` — `### List mode` セクションに "blocked" が含まれるか
   - `@test "List mode section: phase/done gate condition present"` — `### List mode` セクションに "phase/done" が含まれるか
   - `@test "List mode section: --batch --resume in blocked warning present"` — `### List mode` セクションに "--batch --resume" が含まれるか

3. `docs/workflow.md` の `--batch N1 N2 ...` 説明（3 文目以降）を更新:
   - 「Before running each Issue, the parent session checks for `blocked-by` relationships in the Issue body: if a blocker is not yet CLOSED or `phase/done`, the Issue is skipped and kept in `remaining` for retry via `/auto --batch --resume`.」を先頭に追加

4. `docs/ja/workflow.md` を対応箇所（`--batch N1 N2 ...` の説明）で同期更新（日本語）

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/auto/SKILL.md" "### List mode" "blocked" --> `### List mode` セクションに blocked-by チェック手順が追加される
- <!-- verify: section_contains "skills/auto/SKILL.md" "### List mode" "phase/done" --> blocker が CLOSED または `phase/done` の場合のみ処理続行する条件が追加される
- <!-- verify: section_contains "skills/auto/SKILL.md" "### List mode" "--batch --resume" --> スキップ時の警告メッセージに resume 方法が含まれる
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/auto/SKILL.md" --> `skills/auto/SKILL.md` の syntax validation が通過する
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) が成功する（patch 経路）

### Post-merge

- `/auto --batch A B C` で A が `phase/verify` OPEN の場合、B の処理がスキップされ適切な警告メッセージが出力される <!-- verify-type: manual -->
- スキップされた B が checkpoint の `remaining` に保持され、A の manual 条件完了後に `/auto --batch --resume` で再処理できる <!-- verify-type: manual -->

## Notes

- `update_batch fail` を呼ばないことで NUMBER が `remaining` に保持される。`update_batch fail` を呼ぶと `failed` に移動してしまい、resume で再試行できなくなる。
- 既存の `gh-check-blocking.sh` は CLOSED/OPEN のみを判定し `phase/done` チェックは行わないため、SKILL.md にインラインで記述する。
- `### List mode` のステップ番号変更: 旧 4 → 5（run-auto-sub.sh）、旧 5 → 6（Verify orchestration）。
- `docs/ja/workflow.md` は `docs/translation-workflow.md` の sync 規約により更新対象。

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- Spec の警告メッセージ例では `$BLOCKER_PHASE` を「blocker の `phase/*` ラベルまたは OPEN 状態から取得」と示していたが、SKILL.md の実装記述では "first `phase/*` label of blocker, or `"OPEN"` if no `phase/*` label" と明確化した。Spec の記述をそのまま踏襲した。

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Blocked-by チェックを step 3（Size チェック）と step 4（run-auto-sub.sh）の間に挿入し、旧ステップ 4→5、5→6 に繰り下げ。Resume 連携のため `update_batch` を呼ばずに `remaining` 保持とした。
- 警告メッセージに blocker 番号・フェーズ・resume 方法を全て含む形式を採用（Issue body の Spec 仕様に完全準拠）。
- 既存の `gh-check-blocking.sh` は `phase/done` チェックを持たないため SKILL.md にインラインで記述。

### Deferred Items
- 実際の動作検証（post-merge manual AC）は verify フェーズで手動確認が必要。
- `gh-check-blocking.sh` を `phase/done` 対応に更新する改善は後続 Issue 候補。

### Notes for Next Phase
- 全 pre-merge AC（section_contains 3件 + validate-skill-syntax 1件）はローカル検証 PASS 済み。CI (test.yml) は push 後に確認が必要。
- tests/auto-batch.bats に 3件追加（合計 6件、全 PASS 確認済み）。
- docs/workflow.md と docs/ja/workflow.md 両方更新済み。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 4 つの自動 AC (section_contains 3件 + command syntax) で実装範囲を網羅。CI AC は patch route 用の `gh run list` 形式を正しく採用。
- Post-merge 2 件の manual AC が観察的・依存的シナリオを的確にカバー。

#### design
- step 3 と step 4 の間への挿入位置選定が論理的に整合。`update_batch` を呼ばず `remaining` 保持で resume 連携を確保した設計が適切。
- 既存 `gh-check-blocking.sh` を改修せず SKILL.md インライン記述で対応する判断も妥当（後続 Issue 候補として明記）。

#### code
- 6 件の bats テスト追加で機能網羅。docs/workflow.md と日本語版も同時更新で SSoT 維持。rework なし。

#### review
- patch route のため非実行 (N/A)。

#### merge
- patch route のため非実行。worktree-merge-push.sh で main 直マージ成功。

#### verify
- Pre-merge 4 件 PASS、CI 1 件 PENDING（実行中）。Post-merge manual 2 件は実シナリオでの観察待ち。CI 完了後再 verify が望ましい。

### Improvement Proposals
- N/A

### 2026-08-09 re-run (observation 条件の評価 + AC5 の再判定)

`/auto --batch 1280 1282 1283 1281` (session `97764-1786198856`) の end-of-batch observation scan で `event=auto-run` が発火。post-merge 2 条件に加え、未チェックのまま残っていた pre-merge AC5 も再評価した。

#### verify (再実行分)

- **AC5 の前回判定 (PENDING、「CI 完了後再 verify が望ましい」) は誤診だった**。この verify command は CI の完了を待っても解決しない
  ```
  github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success"
  ```
  - **原因 1**: `$(git rev-parse HEAD)` が verify 実行時に評価される。`/verify` は `verify/issue-478` worktree 内で走るため HEAD は未 push のローカルコミット (`da7b01cf`) で、CI run が存在しない
  - **原因 2**: 実装コミット `359a4a1a` にも run がない。`test.yml` は `on: push` トリガーで、GitHub Actions は push の **head SHA に対してのみ** run を作る。patch route は `worktree-merge-push.sh` が複数コミットをまとめて push するため、中間コミットは run を持たない
  - すなわち patch route では**実装内容にかかわらず PASS しえない**構成であり、`modules/verify-patterns.md` §9 が戒める常時 FAIL 側の形に該当する
- FAIL ではなく UNCERTAIN と判定した。AC1-4 (`section_contains` 3 件 + syntax validation) で実装は検証済みで、CI 実態も green (`01b84816` / `e642794d` とも success)。ここで FAIL を出すと Step 11(b) により reopen + L3 auto-retry で `run-code.sh` が自動再実行されるが、修正すべき実装が存在しないため有害な動作になる
- 推奨修正は `--commit=$(git rev-parse HEAD)` → `--branch=main` (`modules/verify-classifier.md` が patch route 向けに案内している形)
- 条件 6/7 は `when=mode:batch` ゲートを通過したが (本 run は mode=batch)、観察対象の状況が未発生のため SKIPPED。blocked-by ゲートは 4 件すべてで実行されたものの**いずれも exit 0 (ブロッカーなし)** でスキップ分岐を通っておらず、`--resume` も未使用

#### Improvement Proposals (再実行分)

- **[Tier 2 / Spec 記録のみ] `github_check` で `--commit=$(git rev-parse HEAD)` を使うと patch route で常時 FAIL になる** — 理由は上記 2 点。`modules/verify-patterns.md` §9 の具体例、または `modules/verify-classifier.md` の patch route ガイダンスに「`--commit=` ではなく `--branch=<base>` を使う。patch route の実装コミットは multi-commit push の中間コミットになるため run を持たない」を追記する余地がある。ただし (1) 実測できた事例は本 Issue の 1 件のみで open Issue に同型パターンは 0 件、(2) `verify-patterns:` 系の未着手 open Issue が既に 4 件 (#1132 #1087 #1084 #490) 積み上がっている、の 2 点から起票せずここに記録する。同型が 2 例目として観測された時点で起票を再検討する
- **前回 verify の PENDING 誤判定** — 「値が空 → CI 実行中 → PENDING」という判定は、`gh run list` が空を返す原因を区別していなかった。空の理由は (a) run が実行中で `conclusion` が null、(b) 指定 SHA に run が存在しない、の 2 通りあり、(b) は待っても解決しない。上記の記載追加を行う際は、この区別も併せて記述すると診断精度が上がる

### 2026-08-11 re-run (AC5 解消 + 条件 6/7 の 2 セッション目観測)

`/auto --batch --until "label:theme/observability"` (session `29601-1786367167`) の Batch Completion Report observation scan で `event=auto-run` が再発火。

#### verify (再実行分)

- **AC5 が今回は PASS した**。`--commit=$(git rev-parse HEAD)` をそのまま使わず、main の実際に push 済みの HEAD (`git log <worktree-commit>^` で解決) の完全 SHA (`6b5c3f10...`) を手動で特定して `gh run list --commit=` に渡したところ `success` を得た。推奨修正 (`--branch=main` への置き換え) 自体はまだ未適用だが、原因 2 点 (worktree ローカルコミット参照 / 中間コミットに run が無い) のいずれも「main の実際の push 済み HEAD を参照する」ことで回避可能であることが実地で確認できた
- **条件 6/7 は今回も SKIPPED**。本 run は Round 1 で 10 Issue を処理したが、blocked-by ゲートで実際にブロッカーが検出された件は 0 件 (全件 exit 0)。これで観測 2 セッション連続 (`97764-1786198856` → `29601-1786367167`) でシナリオ自体が未発生

#### Improvement Proposals (再実行分)

- N/A — `--commit=` バグの起票再検討トリガー (「同型が 2 例目として観測」) は他 Issue での同パターン再現を指すものであり、本 Issue 自身の再評価では発火しない。条件 6/7 の非発生も、現状は「機能が正しく動作しているが誘発条件がまだ発生していない」health signal であり、改善提案には至らない

## Consumed Comments
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/478#issuecomment-4703000955
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/478#issuecomment-5212257510
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/478#issuecomment-5225312674
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/478#issuecomment-5227713254
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/478#issuecomment-5229257180
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/478#issuecomment-5235673183
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/478#issuecomment-5241663510
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/478#issuecomment-5249500692
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/478#issuecomment-5249543656
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/478#issuecomment-5296374095
