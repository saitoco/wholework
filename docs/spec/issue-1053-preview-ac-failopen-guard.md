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
