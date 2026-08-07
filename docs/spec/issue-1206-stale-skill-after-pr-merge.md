# Issue #1206: auto: pr route で merge した skill 修正がローカル main 未追従で巻き戻る経路を検出する

## Consumed Comments

cutoff (最新の `phase/*` ラベル付与時刻) は `2026-08-06T14:53:25Z`。cutoff 以降の新規コメントは 0 件。cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の再走査でも該当なし。No new comments since last phase.

## Overview

pr route で `skills/*/SKILL.md` を修正する Issue を merge した直後、同一セッション内で別 Issue のフェーズがその skill を呼ぶと、ローカル main が origin に追従していないために修正前の版が実行されうる (`gh pr merge` は origin のみを進め、ローカル main を直接更新しない)。

Issue 本文が推奨する **A + C** の組み合わせを採用する:

- **A**: 既存の Skill Self-Update Propagation check (`skills/auto/SKILL.md` L3 retrospective Step 8) の比較対象をローカル HEAD から `origin/${BASE_BRANCH}` に変更し、あわせて Note の文言を実際に起こりうる状態に合わせて見直す (検出側)
- **C**: `/merge` 完了時 (`scripts/run-merge.sh`) に、merge した PR の変更ファイルが `skills/` を含む場合はローカル main を `git pull --ff-only` で同期する (防止側)

方針 B (skill 実行前の全面同期) は不採用。判断根拠は Issue 本文の「Proposal (Outline)」節に既に記録されている (`## Notes` 参照)。

## Reproduction Steps

1. `/auto --batch` 等、単一の会話セッション内で複数 Issue を連続処理するフローで、ある Issue (例: #1188) が `skills/verify/SKILL.md` を修正し、pr route で PR が `gh pr merge --squash` により merge される
2. `gh pr merge` は GitHub API 経由で origin/main のみを進める。ローカル main を同期するステップは単発 `/auto` の実行経路 (`run-code.sh` / `run-review.sh` / `run-merge.sh`) に一つも無い (同期は並行セッションの副次的操作に依存する非決定的な経路でのみ起こる)
3. 同一セッション内で直後に別 Issue (例: #1188 自身の verify フェーズ) の `/verify` が起動する。`/verify` は in-session 実行 (`run-verify.sh` を経由しない) であり、読み込む `skills/verify/SKILL.md` はローカル main 上のファイルである
4. ローカル main が未追従のため、ステップ1の修正前の `skills/verify/SKILL.md` が読み込まれる。実測 (`docs/sessions/63129-1785977471-2026-08-06/session.md`) では、Step 2 が修正前の `git pull origin main` を実行し dirty tree で確定的に失敗し、その状態で検証した AC 2 件を FAIL と誤判定する寸前だった

## Root Cause

1. `gh pr merge --squash` は GitHub API 経由で origin のみを進め、ローカル main を直接更新しない
2. 単発 `/auto` フローにローカル main を同期するステップが存在しない。同期は `worktree-merge-push.sh` の in-place merge、`run-auto-sub.sh` の `_pull_ff_only()`、`/verify` Step 2 の base 更新など、並行セッションの副次的操作に依存する非決定的な経路でしか起きない
3. 既存の Skill Self-Update Propagation check (`skills/auto/SKILL.md` L3 Step 8) は `CURRENT_HASH` をローカル HEAD (`git log -1 --format=%H -- <path>`) から取得するため、ローカル main が origin から遅れている状態そのものを検出できず、常に「変更なし」と報告する
4. 同 check の Note 文言 (「本 session には未適用、次 session から反映」) は、実際に起こりうる状態 (更新済みだが、本 session の以降の実行でも古い版が使われうる) と整合していない

## Changed Files

- `skills/auto/SKILL.md`: Step 8 (Skill Self-Update Propagation check) の `CURRENT_HASH` 取得元をローカル HEAD から `origin/${BASE_BRANCH}` に変更 (事前に `git fetch origin "$BASE_BRANCH"` を追加)。`## Skill Self-Update Propagation Note` の説明文を見直す
- `scripts/run-merge.sh`: squash merge 成功後、merge した PR の変更ファイルに `skills/` が含まれる場合、ローカル main を `git pull --ff-only` で同期する処理を追加 (warn-only、bash 3.2+ 互換 — 新規に使う構文は `if`/コマンド置換/`grep`/`echo` のみ)
- `tests/auto.bats`: ローカル HEAD と origin で skill hash が異なる条件を実 git fixture (bare origin + working repo) で検証するテストを追加
- `tests/run-merge.bats`: 変更ファイルに `skills/` を含む PR の merge 後に `git pull --ff-only` が呼ばれることを検証するテストを追加

**変更不要と確認済み (grep 実施)**:
- `docs/structure.md`: `scripts/run-merge.sh` の一覧行は「run merge skill」という汎用的な一行のみで、他の `run-*.sh` エントリも内部の副次動作までは列挙していない (既存の記述粒度と整合するため変更不要)。同様に `docs/tech.md` / `docs/workflow.md` に "Skill Self-Update Propagation" の記述はなく、sync 対象なし

## Implementation Steps

1. `skills/auto/SKILL.md` Step 8 を修正する (→ AC1, AC3)
   - `CURRENT_HASH` を算出するループの直前に、origin の最新化を追加する:
     ```bash
     git fetch origin "$BASE_BRANCH" 2>/dev/null || echo "Warning: git fetch origin ${BASE_BRANCH} failed; comparing against a possibly-stale origin ref" >&2
     ```
   - `CURRENT_HASH=$(git log -1 --format=%H -- "skills/${skill}/SKILL.md" 2>/dev/null || echo "")` を次に置き換える:
     ```bash
     CURRENT_HASH=$(git log -1 --format=%H "origin/${BASE_BRANCH}" -- "skills/${skill}/SKILL.md" 2>/dev/null || echo "")
     ```
     `$BASE_BRANCH` は Step 0 で `--base` フラグから解決済みの変数 (未指定時 `main`) をそのまま再利用する
   - `## Skill Self-Update Propagation Note` の説明文を次のように置き換える (比較対象が origin である旨と、本 session 内でも古い版が使われうる旨を明記する):
     `Session 中に以下の skill が origin 上で更新されました (比較対象: origin/${BASE_BRANCH})。ローカル main が追従できていない場合、本 session 内の以降の実行や次回セッションが更新前の版を使う可能性があります:`

2. `scripts/run-merge.sh` に post-merge sync を追加する (parallel with 1) (→ AC1)
   - 挿入位置: `if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then ... fi` ブロック (Step 6 相当、Issue state fallback) の直後、`# CI test_result emit` コメントの直前
   - 追加するロジック:
     ```bash
     if [[ $EXIT_CODE -eq 0 ]]; then
       _pr_files=$(gh pr view "$PR_NUMBER" --json files -q '.files[].path' 2>/dev/null || true)
       if echo "$_pr_files" | grep -q '^skills/'; then
         echo "Merged PR touched skills/ — syncing local main..." >&2
         if ! git pull --ff-only; then
           echo "Warning: git pull --ff-only failed; local main may be stale for subsequent in-session skill calls." >&2
         fi
       fi
     fi
     ```
   - `run-merge.sh` は起動直後に `MAIN_REPO_ROOT` に `cd` 済み (line 21 相当) であり、`claude -p` サブプロセスが自身のセッション内で worktree に移動しても親スクリプト自身の CWD には影響しないため、`-C` 等の追加指定は不要
   - 失敗しても `EXIT_CODE` は変更しない (warn-only, fail-open)。`_pull_ff_only()` (`scripts/run-auto-sub.sh`) と同じ方針

3. `tests/auto.bats` にテストを追加する (after 1) (→ AC4)
   - `tests/pre-merge-check.bats` の setup パターン (bare origin + working repo の実 git fixture) を踏襲する: bare origin を作成し、working repo に `skills/x/SKILL.md` を commit して push (ローカル HEAD = origin = commit A)
   - 別の一時 clone (または同 bare origin への直接 push) から `skills/x/SKILL.md` を変更する commit B を作成し、origin にのみ push する (working repo のローカル HEAD は commit A のまま)
   - working repo で `git fetch origin main` を実行した後、`git log -1 --format=%H -- skills/x/SKILL.md` (ローカル HEAD、commit A) と `git log -1 --format=%H origin/main -- skills/x/SKILL.md` (origin、commit B) を比較し、両者が異なることを assert する — Step 1 で導入する origin 比較方式が、ローカル HEAD のみの比較 (常に commit A を返し「変更なし」と誤判定する) では検出できない乖離を検出できることを示す

4. `tests/run-merge.bats` にテストを追加する (after 2) (→ AC4)
   - 既存の `setup()` が用意する `$MOCK_DIR/gh` を新しいテスト内で上書きし、`--json files` を含む呼び出しに `skills/verify/SKILL.md` を1行返すようにする (他の `-q .title` / `.url` / `.state` 分岐は既存のまま維持する)
   - `$MOCK_DIR/git` を新規追加し、呼び出し引数をログファイルに記録するモックにする (`tests/worktree-merge-push.bats` の `git` モックパターンを踏襲)
   - `run "$SCRIPT" 88` を実行し、ログファイルに `pull --ff-only` の呼び出しが記録されていることを assert する

## Verification

### Pre-merge

- <!-- verify: rubric "採用した方針が実装され、pr route で merge された skill 修正がローカル main 未追従のまま次の in-session 実行で使われる状態が検出または防止されるようになっている" --> stale skill の実行が検出または防止される
- <!-- verify: rubric "採用しなかった候補について不採用の判断根拠が Spec または Issue に記録されている" --> 不採用根拠が記録されている
- <!-- verify: rubric "Skill Self-Update Propagation Note の文言が、実際に起こりうる状態 (更新済みだがローカル未追従のまま実行される) と整合するよう見直されているか、見直し不要と判断した根拠が Spec に記録されている" --> ノート文言の妥当性が検討されている
- <!-- verify: rubric "tests/ 配下に、ローカル HEAD と origin で skill hash が異なる条件を検証するテストが存在する" --> 該当条件がテストで保護されている

### Post-merge

- 次回 skill を変更する Issue を pr route で完走させた後、同一セッション内でその skill を呼ぶ実行があった際、stale な版が使われないこと (または警告が出ること) を観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### 不採用方針とその根拠 (→ AC2)

Issue 本文「Proposal (Outline)」節に既に記録済みのため、Spec 側での重複記載はしない。要旨のみ引用する:

| 候補 | 判断 | 根拠 (Issue 本文より) |
|------|------|------|
| A. 既存 check を origin 比較に変更 | 採用 | 実装コスト最小。ただし検出タイミングは batch 完了時のままなので、誤判定の防止にはならない (事後記録の正確化にとどまる) — この限界を補うのが C |
| B. skill 実行前にローカル base を同期 | 不採用 | 各 `run-*.sh` / phase 遷移時の同期は、同時に走る他セッションの作業ツリーを動かすため、`#1076` / `#1188` が扱ってきた並行実行時の git 競合と同じ領域に踏み込む。慎重な設計が要る |
| C. skill 変更を含む Issue の merge 後にローカル同期を必須化 | 採用 | 影響範囲が B より狭く、`/merge` は既にローカル state を触る位置にいる |

### `#1168` との関係 (会話セッション単位のキャッシュ)

`modules/verify-classifier.md` に文書化されている通り、wholework の harness は **skill 内容を会話セッション単位でキャッシュする** (`/auto` の実行単位ではない)。これは #1206 が扱う「ローカル main が origin に追従しない」というディスクレベルの問題とは別の軸の制約であり、本 Issue のスコープには含めない。

この制約下での A + C の役割分担:

- **C (run-merge.sh の同期)** は、新しい `claude -p` サブプロセスを spawn するフェーズ (code / review / merge / spec — いずれも headless) に対しては確実に有効 — 次のフェーズが読むファイルはディスク上で既に同期済みになる
- **同一会話セッション内で in-session 実行される `/verify` 等** については、ディスクを同期しても、その会話セッションが既にキャッシュした skill 内容を読み直すとは限らない (`modules/verify-classifier.md` の `session=next` 節が明文化する制約)。この残存リスクは Post-merge AC の「または警告が出ること」という表現で許容されている — **A の Note (検出)** が、C の同期が届かない場合の可視化を担う
- 実測 (`docs/sessions/63129-1785977471-2026-08-06/session.md`) では、ローカル main 更新後の `/verify` 再実行で修正後の版が使われたことが確認されている。これは会話セッション単位キャッシュが常に本 Issue の対処を無効化するわけではないことを示すが、キャッシュ挙動の完全な解明は本 Issue のスコープ外とする
- Post-merge observation AC (`session=next`) は、A + C 導入後も stale 実行が残るかどうかを実地で確認する機会でもある。残存する場合は新規 Issue として起票する

### 実装確認済みの前提

- `$BASE_BRANCH` は `skills/auto/SKILL.md` の冒頭 (`--base` フラグ解決箇所) で一度だけ設定され、全フェーズに伝播する単一の session-wide 変数であることを確認した (Step 8 時点でも参照可能)
- `scripts/run-merge.sh` は起動直後に `MAIN_REPO_ROOT` へ `cd` しており、以降スクリプトが CWD を変更する箇所は無いことを確認した (`claude -p` サブプロセス内の worktree 移動は親プロセスの CWD に影響しない)
- `scripts/run-merge.sh` は現状 `git` を直接呼び出していないことを確認した (既存呼び出しは全て `gh`) — 今回追加する `git pull --ff-only` が最初の直接呼び出しであり、追加による既存動作への副作用はない

### 実装方針の理由

- **Proposal C の実装位置**: `skills/merge/SKILL.md` (LLM 実行、自分の worktree `merge/pr-$NUMBER` 内で完結) ではなく `scripts/run-merge.sh` (bash wrapper) を選んだ。`/merge` 自身は worktree 内で完結するため、親リポジトリの `main` を直接操作するには worktree 分離を越える必要がある。一方 `run-merge.sh` は `claude -p` サブプロセスの外側で `MAIN_REPO_ROOT` に居続けるため、追加の分離越えロジックなしに実装できる。既存の `_pull_ff_only()` (`scripts/run-auto-sub.sh`) も同じく bash wrapper 層に実装されており、パターンとして一貫する
- **AC4 のテスト方法**: Step 8 のロジックは SKILL.md prose に埋め込まれた bash スニペットであり、直接ユニットテストできる独立スクリプトではない。`tests/pre-merge-check.bats` が使う bare origin + working repo の実 git fixture パターンを踏襲し、Step 1 で導入する 2 つの git コマンド (ローカル HEAD 比較 / origin 比較) が実際に異なる結果を返すことを実 git 操作で検証する形とした。SKILL.md prose のリファクタ (スクリプトへの抽出) は本 Issue のスコープを超えるため行わない

## Autonomous Auto-Resolve Log

- **Step 3 (`phase/ready` label check)**: `/code 1206` 実行時点で Issue ラベルは `phase/code` であり `phase/ready` は不在だった。Issue タイムラインを確認したところ、`phase/ready` は一度付与された後 `phase/code` へ遷移済み (2026-08-06T15:31:55Z) — 本 Issue に対する `/code` の先行実行が Step 4 (ラベル遷移) まで進んだ後、worktree/branch を作成せずに中断していたと判明した (worktree 一覧・リモートブランチのいずれにも `code+issue-1206` 相当の痕跡なし)。Spec (`docs/spec/issue-1206-stale-skill-after-pr-merge.md`) は既に存在し内容も完成しているため、"Continue" を自動選択し Spec を使って実装を継続した。`reconcile-phase-state.sh --check-precondition code-pr 1206` の `matches_expected:false` も同じ `phase/ready` 不在が理由であり、Spec 欠如ではないことを確認した上で warn のみとして続行した。

## Code Retrospective

### Deviations from Design
- None. Implementation Steps 1–4 を Spec の記述通りに実装した。

### Design Gaps/Ambiguities
- Spec の「実装確認済みの前提」節は「`scripts/run-merge.sh` は現状 `git` を直接呼び出していない」と記載しているが、実際には起動直後に `git worktree list --porcelain`という読み取り専用の呼び出しが既に存在していた (`MAIN_REPO_ROOT` 解決のため)。今回追加した `git pull --ff-only` は状態を変更する最初の呼び出しである、という主張自体は正しく実装への影響もなかったが、前提の文言はやや不正確だった。次回この Spec を参照する際は「`git` の読み取り専用呼び出しは既存、書き込みを伴う呼び出しは今回が最初」と読み替えること。

### Rework
- `tests/auto.bats` の新規テストで `git clone` 直後に `skills/x/SKILL.md` へ書き込めず失敗した。原因は bare origin の `HEAD` が `refs/heads/main` を指しておらず (`branch -M main` 後も symbolic-ref 未設定)、`git clone` が空のチェックアウトを作っていたため。`git -C "$origin_dir" symbolic-ref HEAD refs/heads/main` を push 後に追加して解消した。
- `tests/run-merge.bats` の否定側テスト (`git pull --ff-only` が呼ばれないことの確認) で当初 `[ ! -f "$GIT_LOG" ]` を使ったが、`run-merge.sh` が既存の `git worktree list --porcelain` 呼び出しで `git` モックを起動するため常に失敗した。`grep -q "^pull --ff-only$" "$GIT_LOG"` の否定に変更して解消した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC ゲートは 4/4 checked、review-incomplete-fallback も未検出のため override 不要でそのまま squash merge を実行
- `gh pr merge --squash --delete-branch` はリモートブランチ削除まで成功。ローカルブランチ削除のみ `worktree-code+issue-1206` を review worktree が使用中のため失敗したが、リモート反映には影響しないため無視して続行

### Deferred Items
- Post-merge observation AC (`session=next`): 次回 skill を修正する Issue を pr route で完走させた後、同一セッション内でその skill を呼ぶ実行で stale な版が使われないか (または警告が出るか) を観察する (review フェーズからの引き継ぎを維持)
- `gh pr view --json files` の 100件 truncation パターンは他呼び出し箇所にも既存。今回のスコープ外のまま据え置き (review retrospective 参照)

### Notes for Next Phase
- `/verify` は post-merge AC (`session=next` observation) を次回セッションで確認すること
- worktree `code+issue-1206` / `review+pr-1217` 等の残存有無は本 skill のスコープ外 (merge worktree の exit のみ担当)

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note。review-light の Perspective 1 判定通り、Implementation Steps 1–4 は Spec 記述と一致していた。

### Recurring issues

`gh pr view --json files -q '.files[].path'` は GraphQL の `files` connection をページングせず、100件で暗黙に打ち切られる。review-light の指摘によれば同じパターンが `skills/review/SKILL.md` (Step 6 の diff ファイル一覧取得) にも既存で存在する。今回は本 Issue が実装する検出・防止機構そのものの信頼性に直結する箇所 (`scripts/run-merge.sh` の skills/ 変更検出) だったため SHOULD として修正したが、他の呼び出し箇所は影響の性質が異なる (ファイル一覧の表示用途など) ため今回のスコープには含めていない。100件超のPRで `gh pr view --json files` を使っている箇所を横断的に洗い出す価値があるかもしれないが、頻度は低いと見て新規 Issue化は保留する。次に同種の truncation を踏んだ際に横断監査の起票を検討する。

### Acceptance criteria verification difficulty

Nothing to note。Pre-merge AC 4件は全て `rubric` 形式で、Issue 本文と diff のみから明確に PASS 判定できた。UNCERTAIN や verify command の不備は発生しなかった。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 起票時の Proposal (A / B / C の 3 案 + 「A + C を推奨」) がそのまま採用され、issue フェーズは Background の事実確認に徹した。**Issue 側で選択肢と推奨を提示しておくと `/spec` の判断が速い**
- ただし起票時の根本原因の記述は**不正確だった**。「`gh pr merge --squash` はリモートだけ進めるのでローカル main は追従しない」と書いたが、実際にはローカル main は並行セッションの操作 (`worktree-merge-push.sh` の in-place merge、他セッションの `_pull_ff_only`、`/verify` Step 2) によって**非決定的に**同期される。`/auto 1200` 実行中に reflog で発見し、spec 開始前にコメントで訂正した

#### spec
- 訂正コメントを取り込み、問題定義を「同期されない」から「**同期が非決定的**」に更新したうえで A + C を採用。C の推奨度が上がった理由 (単発 `/auto` 経路に同期ステップが皆無) も反映されている
- 一方で「実装確認済みの前提」節が「`run-merge.sh` は現状 `git` を直接呼び出していない」と記載していたが、`git worktree list --porcelain` が既に存在した。実装への影響はなかったが、**この不正確な前提が code フェーズのテスト設計に波及した** (下記)

#### code
- Rework 2 件。いずれもテスト基盤側の問題で、実装ロジックの手戻りではない
  - `git clone` が空チェックアウトを作った (bare origin の HEAD が `refs/heads/main` を指していなかった) → `symbolic-ref HEAD` の明示設定で解消
  - **否定側テストが常に失敗した** — 「`git pull --ff-only` が呼ばれないこと」を `[ ! -f "$GIT_LOG" ]` で検証したが、`run-merge.sh` は起動直後に既存の `git worktree list --porcelain` を呼ぶため git モックのログが必ず生成される。`grep -q "^pull --ff-only$"` の否定に変更して解消。**spec の前提の不正確さが、そのままテストの誤設計として現れた事例**

#### review
- `gh pr view --json files` が GraphQL の files connection を 100 件で暗黙に打ち切る問題を検出し、**本 Issue の検出機構そのものの信頼性に直結する箇所**として SHOULD 修正 (paginated REST endpoint に変更)。さらに `run-merge.bats:331` で 100 件 cap 超えの境界をテストで保護した
- 同じパターンが `skills/review/SKILL.md` にも既存だが、用途が異なる (表示目的) ためスコープ外とし、「次に同種の truncation を踏んだら横断監査を起票」と判断を記録

#### merge
- ローカルブランチ削除のみ失敗 (review worktree が `worktree-code+issue-1206` を使用中)。リモート反映には影響しないため続行

#### verify
- **CI インフラ障害で review が 1 度失敗した**。`run-review.sh` が exit 2 (PENDING) を返し `run-auto-sub.sh` が exit 1。CI ログを読むと `Validate skill syntax` が `Failed to resolve action download info. Error: Service Unavailable` で **Set up job 段階から失敗**しており、検証自体が実行されていなかった。同時刻にリポジトリ全体で 12 run 中 7 failure / 4 queued 停滞という GitHub Actions の広域障害だった
- 復旧は **CI ジョブの再実行のみ**。コード修正・spec 見直しは一切不要で、再実行後は全 9 ジョブ pass。障害当時から `Run bats tests` は SUCCESS だったため、実質的な検証は最初から通っていた
- 本 Issue が直した経路の実地確認として merge 直後にローカル main を確認したところ origin と一致していたが、**これは #1206 の修正が効いた証拠にはならない** — 並行セッションによる副次的同期でも同じ結果になるため。まさに訂正コメントで指摘した非決定性であり、確定的な検証は post-merge observation AC に委ねられる

### Improvement Proposals

- **`/auto` の Tier 1/2/3 が CI インフラ障害を分類できない** — 今回 Tier 1 (reconciler) は `matches_expected: false` と正しく報告したが、その原因が「実装が不完全」なのか「外部サービスの一時障害」なのかは判別できない。`skills/verify/SKILL.md` Step 5 には既に **CI Infrastructure Failure Detection** の判定表 (steps が空 / timeout / runner error / network error) が存在するが、これは `/verify` 内でのみ使われ、`run-review.sh` の exit 2 経路や `/auto` の recovery ラダーからは参照されない。結果として**親セッションが `gh run view --log-failed` を手で読んで初めて切り分けられた**。既存の判定表を `/auto` 側からも参照できるようにする (または Tier 2 のカタログエントリとして登録する) 余地がある
- **spec の「実装確認済みの前提」の不正確さがテスト設計に波及した (観察のみ)** — 今回は実装への影響がなく Rework 1 件で済んだが、前提節はコードから機械的に検証できる主張を含むため、`/spec` 時点で `grep` 等による裏取りを促す価値があるかもしれない。単発事例のため起票は見送る
