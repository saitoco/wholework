# Issue #1053: verify: /review 異常終了時に preview tier AC が検証済みと誤認される fail-open を塞ぐ

## Overview

`/review --full` が preview tier AC の marker (`<!-- wholework-event: type=preview-ac-unverified ... -->`) を投稿する前に異常終了 (silent no-op) した場合、`/verify` Step 5 の pre-merge-preview AC skip rule が `scripts/resolve-preview-ac-fallback.sh` の fail-open な空出力を「`/review` で検証済み」と誤認し、実際には一度も検証されていない `ac-tier: preview` AC を SKIPPED として記録してしまう不具合を修正する。

`resolve-preview-ac-fallback.sh` の出力が空のときに限り、PR の Review Response Summary コメントの有無を `scripts/reconcile-phase-state.sh review --check-completion` の判定ロジックで追加確認し、Summary が見つからない場合は SKIPPED ではなく fallback 検証または UNCERTAIN に倒す。あわせて `modules/orchestration-fallbacks.md` の `review-completion-false-negative` エントリに、入力側 (巨大 diff・content filter 発火など) が原因で同条件の再実行も空振りするケースの代替手段 (`--light` フォールバック・手動レビュー) を追記する。

## Reproduction Steps

1. `capabilities.pr-preview: true` を設定したプロジェクトで、Pre-merge に `ac-tier: preview` AC を含む Issue の PR に対して `/review --full` を実行する
2. `/review` が (巨大 diff・PR 内容に対する content filter 発火などが原因で) `<!-- wholework-event: type=preview-ac-unverified ... -->` marker と Review Response Summary の投稿前に異常終了する (exit 0 の silent no-op を含む)
3. PR がマージされ、`phase/verify` 遷移後に `/verify` が実行される
4. `/verify` Step 4 のコメント消費時点で `type=preview-ac-unverified` marker は 1 件も存在しない
5. Step 5 で `scripts/resolve-preview-ac-fallback.sh $NUMBER` を呼ぶと、marker 不在のため空文字列を返す (スクリプト自身の設計として fail-open)
6. 現行実装は空出力を「fallback 不要 = `/review` で検証済み」と解釈し、`ac-tier: preview` の AC を SKIPPED として記録する — 実際には一度も検証されていない

## Root Cause

`scripts/resolve-preview-ac-fallback.sh` は `type=preview-ac-unverified` marker が「存在しない」場合と「`ac=none` で明示的に空集合を示している」場合を区別せず、いずれも空文字列に畳み込んで出力する (スクリプト自身のコメントにも `there is no marker, the marker's ac= is empty, or ac=none` の3ケースがすべて空出力である旨が明記されている)。

`skills/verify/SKILL.md` Step 5 のpre-merge-preview AC skip ruleはこの空出力を単一の意味 (「fallback 不要」) としてのみ扱っており、(a) `/review` が marker 投稿前に異常終了したケース (= 一度も検証されていない) と (b) `/review` が正常完了して `ac=none` を明示的に投稿した、または関連 index が対象外だったケース (= 検証済み) を区別する手段を持たない。`modules/l0-surfaces.md` の marker 仕様は `ac=none` sentinel で (b) を明示的に表現する設計だが、(a) のように marker 自体が存在しないケースは想定の外にある。

## Changed Files

- `skills/verify/SKILL.md`: frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*` を追加。Step 5 の pre-merge-preview AC skip rule に、`resolve-preview-ac-fallback.sh` の出力が空のときに限定した Review Response Summary 存在確認ロジックを追加
- `modules/orchestration-fallbacks.md`: `## review-completion-false-negative` の `### Fallback Steps` に、入力側原因で再実行が空振りするケースの代替手段 (`--light` フォールバック・手動レビュー) を追記
- `tests/verify.bats`: Step 5 ブロックに新規 `@test` を追加し、Review Response Summary 確認ロジックの記載を検証 (test file search check — 既存の Step 5 構造テスト (44-55行目) と同じ grep アサーション方式)
- `docs/guide/customization.md`: [Steering Docs sync candidate] 202行目が `type=preview-ac-unverified` marker ベースの fallback 分岐 (auto/manual サブケース) を説明済み。本 Issue は「marker 自体が無いケースの安全網」を追加するのみで既存の auto/manual 分岐自体は変更しないため必須ではないが、安全網の追記可否は `/code` が最終判断する

## Implementation Steps

1. `skills/verify/SKILL.md` の Step 5 pre-merge-preview AC skip rule を書き換える (→ 受入条件1, 受入条件2)
   - frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*` を追加する (現状このスクリプトは verify SKILL.md の allowed-tools に含まれていない)
   - `resolve-preview-ac-fallback.sh $NUMBER` の呼び出し直後、その標準出力が空のときに限り実行する「Review completion check」を新設する: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh review $NUMBER --check-completion --pr $PR_NUMBER --warn-only` を **1回だけ** 実行し (このPre-merge セクション内の `ac-tier: preview` AC ごとに繰り返さない)、標準出力の JSON から `matches_expected` を読み取る。`matches_expected` が文字列 `true` のときのみ `REVIEW_SUMMARY_FOUND=true` とし、それ以外 (`false`・JSON がパースできない・コマンドが標準出力を生成せず終了した場合を含むすべてのケース) は `REVIEW_SUMMARY_FOUND=false` とする (fail-closed — 判定不能なら「検証済み」とみなさない)
   - per-AC 判定ロジックを書き換える: 1つ目の分岐 (現行「script の出力が空、またはこの AC の index が出力リストに無い」→ SKIPPED) を、「script の出力が非空でこの AC の index が出力リストに無い」**または**「script の出力が空かつ `REVIEW_SUMMARY_FOUND=true`」の場合に限定する。2つ目の分岐 (現行「この AC の index が出力リストにある」→ 非 SKIPPED) に「script の出力が空かつ `REVIEW_SUMMARY_FOUND=false`」のケースを追加する。この新サブケースの note 文言は既存の "preview-tier AC unverified at /review; ..." と区別できるよう "preview-tier AC unverified — /review ended without posting a Review Response Summary (likely abnormal termination); ..." のように書き分ける
   - 既存の "This is also the fallback-open outcome when the script itself fails (e.g., `gh` unavailable), since it fails open with empty output rather than erroring." の一文は、script 失敗時に無条件で SKIPPED になるという記述がもう成立しないため、"script 自体が失敗した場合も `REVIEW_SUMMARY_FOUND=false` を経由して fallback/UNCERTAIN 側に倒れる" 旨に書き換える (削除ではなく趣旨の更新)
   - 新設テキストには文字列 `Review Response Summary` を含める (`reconcile-phase-state.sh` の診断メッセージ "Review Response Summary found in PR #N comments" を踏襲する言い回しでよい)
2. `tests/verify.bats` に Step 5 ブロック向けの新規 `@test` を追加し、`step5_section` が `Review Response Summary` および `reconcile-phase-state.sh` を含むことを検証する (既存の44-55行目の grep アサーションと同じ構造) (after 1) (→ 受入条件1, 受入条件2 のテスト裏付け)
3. `modules/orchestration-fallbacks.md` の `## review-completion-false-negative` セクション `### Fallback Steps` のStep 4 (「summary comment が見つからない場合は `/review <PR>` を再実行」) に追記する: 同条件での再実行も空振りする場合、原因が入力側 (巨大 diff・PR 内容に対する content filter 発火など) にある可能性があり、単純な再実行では再度失敗しうる旨を明記した上で、代替手段として (a) `/review --light <PR>` (軽量モードは単一エージェント構成のため、同じトリガー要因を回避できる可能性がある) と (b) 手動レビューへの切り替え (`<!-- review-summary -->` マーカー付きで Review Response Summary を人手で投稿し、下流の `/merge`・`/verify` の completion check を通す) の2つを列挙する (parallel with 1, 2) (→ 受入条件3, 受入条件4 — 追記文に `--light` を含める)

## Verification

### Pre-merge

- <!-- verify: rubric "verify スキルの Step 5 で、resolve-preview-ac-fallback.sh が空を返した場合に PR の Review Response Summary 存在確認を行い、不在なら SKIPPED 以外 (fallback 実行または UNCERTAIN) に倒す処理が記載されている" --> summary 不在時の分岐が追加されている
- <!-- verify: grep "Review Response Summary" "skills/verify/SKILL.md" --> `skills/verify/SKILL.md` に summary 存在確認への言及がある
- <!-- verify: rubric "orchestration-fallbacks.md の review-completion-false-negative に、同条件での再実行が空振りするケースと代替手段 (--light フォールバック / 手動レビュー) が記載されている" --> catalog に代替手段が追記されている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## review-completion-false-negative" "--light" --> `review-completion-false-negative` セクション内に `--light` への言及がある

### Post-merge

- `/review` が異常終了した Issue で `/verify` を実行した際、preview tier AC が SKIPPED にならない <!-- verify-type: opportunistic -->

## Notes

- **`resolve-preview-ac-fallback.sh` 自体は変更しない**: marker の「不在」と「`ac=none`」の区別はスクリプト内部では行わず、`/verify` Step 5 側で Review Response Summary の有無という別シグナルを追加参照することで区別する設計とした。スクリプトの出力インタフェース (1-based index のカンマ区切り、または空) を変更すると `tests/resolve-preview-ac-fallback.bats` の既存ケースおよび `docs/spec/issue-1035-preview-ac-marker-staleness.md` で確立された「latest-wins・ac=none sentinel」設計との整合を崩すリスクがあるため、影響範囲をより小さく保てる `/verify` 側の追加チェックを採用した
- **`reconcile-phase-state.sh` の再利用**: `_completion_review()` は既に「PR コメント + review 内の `<!-- review-summary -->` marker または `## Review Response Summary` / `## レビュー回答サマリ` 見出し」の存在を判定するロジックを持っており (`modules/orchestration-fallbacks.md` の `review-completion-false-negative` エントリの自動復旧が既に依拠している判定ロジックと同一)、これを Tier 1 recovery 経路とは独立に `/verify` からも直接呼び出す。呼び出しには Pre-merge 区分に `ac-tier: preview` AC を含む Issue が既に PR route (Size M/L) を経由していることが前提となるため `PR_NUMBER` (Step 2 で取得済み) は非空であることを前提としてよい
- **`tests/orchestration-fallbacks.bats` は変更対象に含めない**: 同ファイルは catalog 全エントリ共通の構造検証 (見出し構成・Issue参照の有無など) のみを行っており、エントリ個別の内容検証パターンが存在しない。個別内容の検証は Issue 本文の AC4 (`section_contains` verify command) が担う既存の役割分担を踏襲した
- **入力側原因の完全な自動検知は本 Issue のスコープ外**: `modules/orchestration-fallbacks.md` への追記は「代替手段の提示」に留め、「巨大 diff / content filter 発火」を機械的に判定するロジックの追加は行わない (Issue 本文の対応方針にも機械判定への言及はない)

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective。Background の技術的記述 (`resolve-preview-ac-fallback.sh` の fail-open 挙動、`l0-surfaces.md` の `ac=none` sentinel 設計、`reconcile-phase-state.sh` の Review Response Summary 判定ロジック、`orchestration-fallbacks.md` の `review-completion-false-negative` エントリ) を実ファイルで確認済みと報告。`skills/verify/SKILL.md` に現時点で "Review Response Summary" という文字列が存在しないことも確認済み (受入条件2 は未実装 → 実装後 PASS の健全な pre-merge チェックとして機能する)。AC3 に補助的な `section_contains` verify command (`--light` キーワード) を追加した Auto-Resolve Log を記録済み。本 Spec のコードベース調査でも同内容を独立に再確認した (矛盾なし)。 — https://github.com/saitoco/wholework/issues/1053#issuecomment-5132345005

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1〜3 は Spec の記載通りに実装した (Step 5 の新設パラグラフ位置・per-AC 分岐構造・`orchestration-fallbacks.md` Step 4 への追記位置を含め、順序・範囲とも設計通り)。

### Design Gaps/Ambiguities

- `docs/guide/customization.md` (Changed Files に「安全網の追記可否は `/code` が最終判断する」と明記されていた任意項目) は更新しないと判断した。理由: 同ファイルは `PREVIEW_URL`/`type=preview-ac-unverified` marker ベースの既存 fallback 分岐 (auto/manual サブケース) のみを説明しており、本 Issue が追加した「marker 自体が無い (=summary 不在) ケースの安全網」を書き足すと当該分岐の説明がより正確になるが、AC の verify command はいずれもこのファイルを対象にしておらず、追記しなくても受入条件は full に満たせる。スコープを Changed Files が要求する最小限に留め、ドキュメントの完全性より diff の小ささを優先した。

### Rework

- N/A — 手戻りは発生しなかった。

## Autonomous Auto-Resolve Log

- **Step 3 の `phase/ready` ラベル欠如を許容して実装を継続** — reason: Issue #1053 のラベルは `phase/ready` ではなく `phase/code` (かつ Spec ファイルは既に完全な内容で存在) だった。`reconcile-phase-state.sh code-pr 1053 --check-precondition` も `matches_expected:false` (`phase/ready` 欠如が理由) を返したが、`--non-interactive` モードのポリシー (`modules/ambiguity-detector.md` Three-Tier Policy の auto-resolve) に従い、warn のみで続行した。ブランチ・worktree・PR は事前に存在せず (`git branch -a` / `git worktree list` / `gh pr list` で確認済み)、コミット履歴も Spec 作成コミットのみだったため、以前の `/code` 実行が Step 4 (ラベル遷移) 直後に中断した状態と推測される。Spec 本文は完全であり要件解釈に不確実性はないため、実装への影響はない。
  - Other candidates: hard-error abort して `/spec` の再実行を促す (Spec は既に完全な内容で存在しており、再実行は無駄な手戻りになるため見送り)

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- pre-merge AC ゲートは 4/4 checked、`gh-pr-merge-status.sh` は `mergeable=true, reason=clean` だったため、conflict 解消・test 再実行を行わず Step 4 (Squash Merge) に直行した。
- `--non-interactive` モードで実行したが、AskUserQuestion を要する分岐 (conflict・review_pending 等) は一切発生しなかった。

### Deferred Items

- Post-merge の observation AC (`/review` が異常終了した Issue で `/verify` を実行した際、preview tier AC が SKIPPED にならないことの確認) は引き続き `/verify` フェーズでの opportunistic 観察に委ねる (review phase からの持ち越し、未解消)。
- `docs/guide/customization.md` への安全網追記 (任意項目) は本 PR では実施しなかった (review phase からの持ち越し、変更なし)。

### Notes for Next Phase

- `/verify` では、本 Issue 自体には `ac-tier: preview` の AC が存在しないため、Step 5 の新ロジックは本 Issue の `/verify` 実行では経路を通らない (ロジックの効果は他の preview-tier AC を持つ Issue で発現する) — review phase からの申し送り事項を維持。
- squash merge 後、`closes #1053` により Issue は auto-close される見込み (base branch は `main`)。Step 6 (Verify Issue State) のフォールバック確認で state を再確認すること。

## review retrospective

### Spec vs. implementation divergence patterns

- 軽微な乖離を1件検出: Spec の Implementation Step 1 は「`resolve-preview-ac-fallback.sh` 自体が失敗した場合も fail-open で空を返す」という既存の一文を、削除ではなく `REVIEW_SUMMARY_FOUND=false` 経由の fail-closed パスに倒れる旨へ**書き換える**よう明示的に指示していたが、実装では単純削除のみが行われ、置き換え相当の説明が追加されていなかった。Code Retrospective の「Deviations from Design: N/A」という自己申告はこの点を見落としていた。実行時の挙動自体は正しく (どちらのスクリプトが失敗しても同じ fail-closed パスを通る) 機能バグではなかったが、Spec の「書き換え」指示が「削除」として実装され、かつ自己レトロスペクティブでも検知されなかった点は、`/review` 側の独立検証 (review-light agent) が有効に機能した事例として記録する。SHOULD として指摘し、`/review` 側で修正済み。

### Recurring issues

- Nothing to note — 検出した2件の指摘 (SHOULD 1件・CONSIDER 1件) はいずれも本 PR 固有の内容であり、ワークフロー改善を要する反復パターンは見られなかった。

### Acceptance criteria verification difficulty

- Nothing to note — Pre-merge AC 4件 (rubric 2件・grep 1件・section_contains 1件) はいずれも明確に PASS 判定でき、UNCERTAIN や verify command の不備は発生しなかった。

## Verify Retrospective

### Phase-by-Phase Review

#### issue / spec
- Spec の設計 (空出力時に `reconcile-phase-state.sh review --check-completion` で summary 存在を追加確認し fail-closed に倒す) が、本 batch 内で実際に踏んだ事象 (#1066 の review が kill され Review Response Summary 不在のまま終了、completion check が `matches_expected: false` を返して未完了を検知) と正確に対応していた。実運用で観測された経路をそのまま安全側判定に組み込む設計になっている。

#### code
- Deviations / Rework とも N/A。実装は Spec の想定を超えて 2 つの縁のケースまで fail-closed 側に倒しており (「`reconcile-phase-state.sh` 自体が失敗し stdout が出ない場合」を既定で `false` に落とす、「verify command を持たない manual preview-tier AC」は `PRODUCTION_URL` の有無によらずフォールバック実行を試みず UNCERTAIN にする)、設計意図の理解が正確だった。
- `docs/guide/customization.md` を更新しない判断も、AC の verify command が同ファイルを対象にしていないことを根拠に明示的に記録されている。

#### review
- `--light` で実施。修正コミット 2 件が追加され、silent no-op なし (comments 0→1、reviews 0→1、`matches_expected: true`)。

#### merge
- pre-merge AC 4/4 checked、`mergeable=true, reason=clean` を確認して squash merge。conflict なし。

#### verify
- pre-merge 4 件すべて PASS、FAIL / UNCERTAIN なし、auto-retry 発火なし。
- post-merge の opportunistic 1 件は未チェックのまま `phase/verify` 留置 (設計どおり)。

### Improvement Proposals

- **`skills/code/SKILL.md` Step 3 が `--check-precondition` の `matches_expected: false` を「Spec missing」と誤って説明している**: L169 は次のように書かれている。

  > Parse the JSON output. If `matches_expected` is `false` (**Spec missing** and Size is not XS):
  > - Output: "Spec が見つかりません。`/spec $NUMBER` を実行してください"

  しかし `scripts/reconcile-phase-state.sh <code-pr|code-patch> --check-precondition` が実際に評価しているのは **`phase/ready` ラベルの有無**であって Spec ファイルの存在ではない。本 batch 内で観測した実際の出力 (#1066):

  ```json
  {"phase":"code-pr","matches_expected":true,
   "actual":{"labels":["triaged","phase/ready","retro/verify"],"spec_file":"docs/spec/issue-1066-....md"},
   "diagnosis":"issue #1066 has phase/ready label (code phase precondition met)"}
  ```

  `diagnosis` が示すとおり判定軸はラベルであり、`spec_file` は付随情報として返されるだけである。

  **実害 (本 Issue で発生)**: `/code` 実行時に precondition が `false` を返した際、SKILL.md の説明に従って「Spec が無い」と解釈された結果、`## Autonomous Auto-Resolve Log` に「`phase/ready` ラベル欠如を許容して実装を継続」「Spec ファイルは既に完全な内容で存在」という噛み合わない記述が残った。同ログは原因を「以前の `/code` 実行が Step 4 直後に中断した状態」と推測しているが、Issue のラベル timeline を確認すると `phase/ready` (15:04:09Z) → `phase/code` (15:07:35Z) と遷移しており、この `phase/code` は**本実行自身の Step 4** による遷移で説明がつく。先行する中断済み `/code` 実行の痕跡 (ブランチ・worktree・PR・コミット) はいずれも存在しなかったと同ログ自身が記録しており、推測された原因は成立しない。

  誤った説明が誤った原因推定を誘導し、それが retrospective に残って後続の判断材料を汚染する経路になっている。

  **対応方針 (案)**: (a) L169 の括弧書きを実際の判定軸に合わせる (`phase/ready` label absent)。あわせて L170 の出力文言も「Spec が見つかりません」から実態に合わせる。(b) precondition の判定軸を Spec ファイル存在に変える (説明側を正とする)。(c) 両方を判定材料にし、`diagnosis` でどちらが欠けているか区別できるようにする。現状の `actual` は `labels` と `spec_file` の両方を返しているため (c) の実装コストは低い。

### 観察

- 本 Issue はフェーズを個別のバックグラウンド呼び出しに分割して実行し (issue / spec / code / review / merge を別々に起動)、**kill ゼロで pr route を完走**した。連結実行 (`run-auto-sub.sh`) を用いた #1066 (Size L) が 3 回 kill されたのと対照的。本 batch 時点での集計は「分割: 完走 5/5、連結: kill 3 回」。ただし Size (M vs L) も同時に異なるため、分割の効果と規模の効果は本データだけでは分離できない。
