# Issue #1028: review/verify: preview AC の review 時未検証状態を機械可読で記録し verify でフォールバック

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: Issue retrospective — Type=Bug・Size=S→M (review/verify 複数スキル横断)・Value=4 の判定根拠、triage 時に AC2 の常時 PASS だった `section_contains` supplementary verify command を除去し rubric 判定へ一本化した経緯、および「機械可読マーカーの記録場所 (PR/Issue コメント) と粒度 (AC 単位/PR 単位)」の曖昧性解決を `/spec` のコードベース調査に委譲する旨 / URL: https://github.com/saitoco/wholework/issues/1028#issuecomment-5031305909

## Overview

`<!-- ac-tier: preview -->` タグ付き AC (Issue #781 で導入) は「`/review` が preview URL に対して検証し、`/verify` は二重検証防止のため無条件 SKIPPED として記録する」という前提で設計されている (`skills/verify/SKILL.md` Step 5)。しかし `/review` が外部制約により当該 AC を UNCERTAIN のまま処理を終えた場合でも、この前提により **実際には一度も検証されていない AC が検証済み扱いで通過する** 構造的ギャップがある。

本 Spec は (1) `/review` が preview AC を検証できなかった状態を機械可読マーカー (Issue コメント) として記録し、(2) `/verify` の skip rule がそのマーカーを検出した場合に production URL への代替検証、またはマーカーはあるが production URL 未設定なら明示的な未検証警告にフォールバックする設計を行う。

## Reproduction Steps

1. `capabilities.pr-preview: true` を設定したプロジェクトで、`/issue` が URL/UX 系 AC に `<!-- ac-tier: preview -->` タグを付与する
2. `/review` が preview URL 未解決や外部制約 (例: 認証済みブラウザの無関係タブに未保存ダイアログが残っており自動操作が安全に実行できない) により、当該 AC を UNCERTAIN のまま Step 8 の処理を終える
3. UNCERTAIN は `skills/review/SKILL.md` の「FAIL Blocking Behavior」の対象外 (FAIL のみが REQUEST_CHANGES をブロックする) のため、PR はそのまま `/merge` される
4. `/verify` が `skills/verify/SKILL.md` Step 5 の pre-merge-preview AC skip rule に従い、`ac-tier: preview` タグを持つ当該 AC を無条件で SKIPPED (「verified at /review against preview URL」) として記録する
5. 結果として、当該 AC は一度も実際には検証されていないにもかかわらず、検証済み扱いのまま `phase/done` まで通過する

## Root Cause

`skills/verify/SKILL.md` Step 5 の skip rule は「`ac-tier: preview` タグ付き AC は `/review` で検証済み」という前提を無条件に信頼しており、`/review` が実際に検証を完了した (PASS/FAIL) のか、UNCERTAIN のまま終了したのかを機械的に区別していない。

一方 `/review` 側にも、UNCERTAIN で終わった preview AC の状態を後続フェーズへ機械可読な形で伝える手段が存在しない。唯一の cross-phase 引き継ぎ機構である Phase Handoff (`modules/phase-handoff.md`) は「直近 1 フェーズのみ保持 (rotation)」であり、`review` → `merge` → `verify` と 2 回のローテーションを経る間、`merge` フェーズの LLM が `review` の Deferred Items を毎回手動で転記し続けない限り情報が失われる。Issue Background で報告された「`/verify` 実行者が Phase Handoff の Deferred Items から偶然気づいた」という経緯は、この LLM 依存の転記に頼った結果である。

## Changed Files

- `modules/l0-surfaces.md`: 「Machine-Readable Event Marker」節に `type=preview-ac-unverified` の属性説明 (`ac=<comma-separated 1-based indices>`) を追記し、Comment Consumption Procedure の「verify-fail marker exception」を汎化して `type=preview-ac-unverified` も cutoff 無視で拾うようにする (→ AC1, AC2 の前提条件)
- `skills/review/SKILL.md`: Step 8 の AC 分類直後に、UNCERTAIN と分類された `ac-tier: preview` AC の 1-based インデックスを収集し `gh-issue-comment.sh` で Issue コメントとしてマーカーを記録する手順を追加 (→ AC1)
- `skills/verify/SKILL.md`: Step 5 の pre-merge-preview AC skip rule を、マーカー検出時は無条件 SKIPPED ではなく production URL 代替検証または明示的未検証警告にフォールバックするよう書き換え (→ AC2)
- `docs/guide/customization.md`: pre-merge-preview の skip 挙動説明を新しい条件付きフォールバック仕様に更新 (doc 整合性)
- `docs/ja/guide/customization.md`: 上記 customization.md 変更の ja ミラー同期 (consistency。translation-workflow.md の必須スコープ外だが既存 ja ミラーが存在するため同期)

## Implementation Steps

1. `modules/l0-surfaces.md` を編集 (→ AC1, AC2 の前提):
   - 「Machine-Readable Event Marker」節の既存 `type=verify-fail` 属性説明の直後に、`type=preview-ac-unverified` の例を追記する: `<!-- wholework-event: type=preview-ac-unverified phase=review issue=<N> ac=<comma-separated 1-based indices> -->`。`ac=` は `gh-issue-edit.sh --checkbox` と同じ、Issue 本文全体を通した 1-based インデックス方式であることを明記する
   - Comment Consumption Procedure の「verify-fail marker exception (defense in depth)」段落を汎化し、`<!-- wholework-event: type=verify-fail` に加えて `<!-- wholework-event: type=preview-ac-unverified` も cutoff 無視でスキャン対象に含める旨に書き換える (見出しは「Cross-phase marker exception」等に変更してよい)

2. `skills/review/SKILL.md` Step 8 を編集 (after 1) (→ AC1): 「3. Classify each condition」リスト (PASS/FAIL/UNCERTAIN/POST-MERGE) の直後、「**`file_contains` exact match check:**」節の直前に新規段落を追加する。内容: Pre-merge 内の `<!-- ac-tier: preview -->` タグ付き AC が UNCERTAIN に分類された場合、その 1-based インデックス (Issue 本文全体通し番号) を収集し、`.tmp/` に Write ツールで一時ファイルを作成した上で `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh "$ISSUE_NUMBER" <file>` を実行して `<!-- wholework-event: type=preview-ac-unverified phase=review issue=$ISSUE_NUMBER ac=<indices> -->` を含む Issue コメントを投稿する。UNCERTAIN な preview AC が 0 件なら投稿しない

3. `skills/verify/SKILL.md` Step 5 を編集 (after 1, parallel with 2) (→ AC2): 「pre-merge-preview AC skip rule」段落を書き換える。Step 4 で収集済みの consumed comments から `type=preview-ac-unverified` マーカーのうち最新のもの (createdAt 最大) を 1 件特定し、検証対象 AC の 1-based インデックスがその `ac=` リストに含まれる場合は SKIPPED にせず: (a) `PRODUCTION_URL` が空でなければ verify command の `{{base_url}}` を `PRODUCTION_URL` に解決して通常の post-merge AC と同様に実際に検証し、結果 (PASS/FAIL/UNCERTAIN) に "preview-tier AC unverified at /review; fallback-verified against production URL" という note を付与する、(b) `PRODUCTION_URL` が空なら UNCERTAIN とし "preview-tier AC unverified at /review; no production-url configured for fallback — manual verification required" という note を付与する。マーカーが無い場合、またはインデックスが `ac=` リストに含まれない場合は既存の SKIPPED 挙動を変更しない

4. `docs/guide/customization.md` の「At `/verify` (post-merge): all `ac-tier: preview` ACs are skipped...」という記述を、新しい条件付きフォールバック仕様 (review で実際に検証済みの場合のみ skip。未検証マーカーがあれば production URL 代替検証、または production URL 未設定なら明示的警告) に更新する (after 3)。`docs/ja/guide/customization.md` の対応箇所を同じ内容で日本語同期する (consistency)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/review/SKILL.md に、preview AC を実行できなかった場合 (UNCERTAIN 等) にその状態を機械可読マーカー (PR または Issue コメント) で記録する手順が定義されている" --> `/review` が preview AC 未検証状態を機械可読で記録する
- <!-- verify: rubric "skills/verify/SKILL.md の pre-merge-preview AC skip rule が、review 時未検証マーカーを検出した場合に SKIPPED ではなく production URL への代替検証 (または明示的な未検証警告) にフォールバックする" --> `/verify` の skip rule が未検証ケースをフォールバック処理する

### Post-merge
- none (Issue 本文の Post-merge AC 指定なし)

## Notes

### Auto-Resolve Log (non-interactive mode)

triage retrospective コメント (2026-07-21) で「マーカーの記録場所 (PR/Issue コメント) と粒度 (AC 単位/PR 単位)」の解決が `/spec` のコードベース調査に委譲されていたため、以下の通り決定した:

- **記録場所: Issue コメント (PR コメントではなく)** — reason: `/verify` は既に `skills/verify/SKILL.md` Step 4 で L0 Comment Consumption Procedure (`COMMENT_SCOPE=issue`) により Issue コメントを取得している。PR コメントを選ぶと `/verify` 用に `COMMENT_SCOPE` を `issue+pr` に広げる (全 verify 実行のコスト増) か PR_NUMBER を使った専用フェッチを追加する必要があり、どちらも Issue コメント案より変更範囲が大きい。`/review` は既に `gh-issue-comment.sh` を allowed-tools に持ち、Step 13.3 で Issue コメント投稿の前例がある。
- **粒度: レビュー実行単位のコメント 1 件に AC 単位のインデックスリストを埋め込む (`ac=<indices>`)** — reason: `ac-tier: preview` 自体が per-AC タグであり、1 PR に複数 preview AC がある場合に一部だけ UNCERTAIN になるケースを区別する必要がある。一方で AC ごとに 1 コメントずつ投稿すると re-review のたびにコメントが増殖するため、既存の `gh-issue-edit.sh --checkbox 1,3` のカンマ区切りインデックス規約を踏襲し 1 コメントに集約した。
- **cutoff 越境問題**: `phase/verify` ラベルは `/review` ではなく `/merge` (`skills/merge/SKILL.md` Step 5) が付与するため、`/review` 実行時点で投稿されるコメントは `/verify` Step 4 の cutoff (直近の `phase/*` ラベル = `phase/verify` 付与時刻) より必ず前になる。既存の `verify-fail` マーカー用「regardless of cutoff」例外 (`modules/l0-surfaces.md`) と同一の問題であり、同じ仕組みを汎化して再利用する (新規の並行した bypass 機構は作らない)。

### Conflict / precedent

- triage retrospective コメントの通り、Issue 本文の AC2 には元々 `section_contains "skills/verify/SKILL.md" "### Step 5" "preview"` という常時 PASS な supplementary verify command が付いていたが、triage 段階で defective と判断され除去済み。Spec 側もこれに従い `rubric` のみの 2 AC 構成を維持する (Verify command sync rule により Issue 本文と同数)。
- `ac-tier: preview` の原設計は `docs/spec/issue-781-three-tier-ac-preview.md` (disposable だが本 Issue と直接関連するため参照)。同 Spec の Notes で「Shared module 不要 (ac-tier タグの SSoT は `/issue` Step 4)」と決定されている。本 Issue はタグの意味論自体は変更せず、`/review`→`/verify` 間の「検証済みかどうかの伝達」を追加するのみのため、この決定と矛盾しない。
- 新規 bats テストは追加しない: Issue 本文の両 AC は `rubric` のみ (triage で defective な grep 系チェックを意図的に除去した経緯があるため)。`tests/review.bats` / `tests/verify.bats` は既存の別機能 (#942 / #1000) を対象とした content-assertion テストであり、本変更後もその既存アサーションと矛盾しない (Step 8 / Step 5 の見出し構造自体は変更しないため)。
- `docs/workflow.md` は変更不要: 同ファイルは pre-merge/post-merge を phase 説明・label 遷移レベルでしか言及しておらず、AC tier の詳細は記述していない (#781 Spec Notes で同じ判断が既になされている)。本 Issue も phase 遷移/routing 自体は変えないため同期不要。

### Doc sync scope note

Steering Docs sync candidate check の一般手順 (skill 名 "review"/"verify" での grep) は、これらが一般的な英単語のため大量の無関係ヒットを生む。代わりに `ac-tier: preview` / `pre-merge-preview` というより特異的なキーワードで直接調査し、`docs/guide/customization.md` (と ja ミラー) のみが該当することを確認した。`docs/tech.md` は新規 `.wholework.yml` キーを追加しないため変更不要。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜4 を Spec 記載順・記載内容通りに実施した。追加/省略/並べ替えはない。

### Design Gaps/Ambiguities
- N/A — Spec Notes の Auto-Resolve Log で記録場所・粒度・cutoff 越境問題が事前に解決済みだったため、実装時に新たな曖昧性は発生しなかった。

### Rework
- N/A — 手戻りは発生しなかった。

### Test scope note (out-of-spec observation)
- `skills/code/SKILL.md` Step 9 の Behavioral Change Detection は、変更ファイル名 (パス抜き) で `tests/` 配下を grep する経験則を持つが、`SKILL.md` は全 Skill 共通のファイル名であるため、`skills/review/SKILL.md` / `skills/verify/SKILL.md` という狭い変更に対しても常に `bats tests/` フルスイート (1213 件) が発火した。実測は PASS (0 failures) だったため本 Issue の実装自体には影響しないが、経験則の汎用ファイル名対応漏れという `/code` 自体の改善余地であり、本 Issue のスコープ外のため follow-up Issue #1034 (`retro/code`) として起票した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の設計通り、preview AC 未検証マーカーは Issue コメント (PR コメントではなく) に `<!-- wholework-event: type=preview-ac-unverified ac=<indices> -->` として記録する方式を採用 (Spec Notes の Auto-Resolve Log 通り、実装からの逸脱なし)。
- `modules/l0-surfaces.md` の「verify-fail marker exception」を「Cross-phase marker exception」に汎化し、`type=verify-fail` と `type=preview-ac-unverified` の両方を cutoff 越境スキャン対象にした (新規の並行 bypass 機構は作らず既存機構を再利用)。
- `skills/verify/SKILL.md` Step 5 のフォールバックは、`PRODUCTION_URL` の有無で分岐 (設定時は実検証、未設定時は明示的 UNCERTAIN 警告) する Spec 記載の仕様通りに実装した。

### Deferred Items
- 新規 bats テストは追加していない (Spec Notes の判断を踏襲: 両 AC が `rubric` のみのため既存 content-assertion テストと衝突しない)。`/verify` 実行時、両 rubric AC が実際に PASS 判定されるかは post-merge の実地確認が必要。
- Behavioral Change Detection の汎用ファイル名対応漏れは follow-up Issue #1034 に切り出し、本 Issue では対応していない。

### Notes for Next Phase
- 本 Issue はコードレベルの変更のみで、`.wholework.yml` の新規キー追加はない。`docs/tech.md` の更新も不要と判断済み (Doc sync scope note 参照)。
- `skills/review/SKILL.md` Step 8 の新規段落と `skills/verify/SKILL.md` Step 5 の書き換えが、既存の Step 見出し構造・番号を変更していないことを Spec Notes で確認済み — `/review`/`/merge` フェーズは通常のフローで進行してよい。
