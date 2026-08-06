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

## spec retrospective

### Minor observations

- 関連する先行 Issue (#1168, #821, #1157) の Spec を読むことで、「skill 自己更新の非伝播」というテーマに複数の異なる原因 (ディスクレベルの git 同期遅れ = 本 Issue、会話セッション単位のキャッシュ = #1168) が存在することが分かった。Issue 本文の Related 節はこれらを横断的には接続していなかった (#1206 は #1168 を参照していない) — テーマが近い Issue 間の相互参照は、起票時点で見えている情報だけでは漏れることがある

### Judgment rationale

- AC2 (不採用根拠の記録) は Issue 本文に既に十分な記録があったため、Spec 側に新規の実装ステップを立てず、Notes での要約引用のみとした。AC の文言が「Spec **または** Issue」と選択を許容していたことが、この判断の根拠になった
- Proposal C の実装位置は `skills/merge/SKILL.md` (LLM 実行、worktree 内で完結) ではなく `scripts/run-merge.sh` (bash wrapper) を選んだ。`/merge` 自身は自分の worktree (`merge/pr-$NUMBER`) 内で完結するため、親リポジトリの `main` を直接操作するには worktree 分離を越える必要がある。一方 `run-merge.sh` はサブプロセスの外側で `MAIN_REPO_ROOT` に居続けるため、追加の分離越えロジックなしに実装できる。既存の `_pull_ff_only()` (`scripts/run-auto-sub.sh`) も同じく bash wrapper 層に実装されており、パターンとして一貫する

### Uncertainty resolution

- **AC4 (「ローカル HEAD と origin で skill hash が異なる条件」のテスト方法)**: Step 8 のロジックは SKILL.md prose に埋め込まれた bash スニペットであり、直接ユニットテストできる独立スクリプトではない。`tests/pre-merge-check.bats` が使う bare origin + working repo の実 git fixture パターンを踏襲し、Step 1 で導入する 2 つの git コマンド (ローカル HEAD 比較 / origin 比較) が実際に異なる結果を返すことを実 git 操作で検証する形とした。SKILL.md prose のリファクタ (スクリプトへの抽出) は本 Issue のスコープを超えるため行わない
