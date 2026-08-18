# Issue #1395: detect-unrecorded-kills: verify フェーズの偽陽性と既定 window 不足を解消

## Overview

`scripts/detect-unrecorded-kills.sh` (#1387 で実装、PR #1393) をマージ後の実データで検証した結果判明した 2 つの実用上の欠陥を修正する。(1) wrapper を持たないフェーズ (`verify`) の `phase_start` 再発を respawn シグナルとして誤検出する構造的な偽陽性 (実データで検出 13 バースト中 8 件)、(2) 既定 `--window 120` が実測の respawn 間隔 (169 秒) を下回りバーストを誤分割する問題。

AC 監査 (Issue コメント参照) で、当初の Pre-merge AC のうち 1 件の rubric verify command が「抑制ロジックが存在しない現状でも常時 PASS してしまう」欠陥を指摘されたため、`/spec` 時点で当該 AC をフィクスチャテスト要件 (現 AC4) に統合済み。詳細は Issue 本文 Notes 「AC 監査による修正」を参照。

## Reproduction Steps

1. `/verify` (opportunistic verify を含む) 実行時、ある Issue の verify フェーズが `phase_complete` を出さずに終了する (早期終了コードパスなど、kill 以外の理由でも起こりうる)
2. opportunistic verify の設計上、同じ Issue の verify が後日 (実例では 3.5 日後) 再実行される
3. `/verify` Step 15 が `detect-unrecorded-kills.sh` を実行すると、手順 1-2 の `phase_start` ペアが respawn シグナルとして誤検出され `recorded: no` として報告される
4. 加えて、同一セッション内の 2 連続 kill が 169 秒間隔だった場合 (2026-08-17 の実バースト)、既定 `--window 120` を超えるため本来 1 つのバーストが 2 つに分割される

## Root Cause

- **偽陽性 (欠陥 1)**: `/verify` は wrapper スクリプト (`scripts/run-verify.sh`) を持たず `wrapper_exit` を構造的に emit できない。respawn シグナルの判定は「`wrapper_exit`/`phase_complete`/`manual_intervention` のいずれも存在しない連続 `phase_start` ペア」だが、verify では `phase_complete` だけが終了の証拠になる。`phase_complete` は kill 以外の理由でも欠落しうるため、それを欠いた実行の直後 (数日後を含む) の再実行が respawn と誤判定される。現在の実装はこの区別を一切行っていない
- **window 不足 (欠陥 2)**: 既定 `--window 120` の根拠 (ヘッダコメント「observed bursts cluster within 16s」) は 2026-08-16 の 1 件のバーストのみを母集団としていた。2026-08-17 の実測で respawn 間隔 169 秒のバーストが観測され、既定値を超過して誤分割された

## Changed Files

- `scripts/detect-unrecorded-kills.sh`: wrapper を持たないフェーズの respawn シグナル生成を除外するロジックを追加 (`SCRIPT_DIR` 解決 + `scripts/run-<phase-base>.sh` の存在チェック)、`WINDOW` 既定値を 120→300 に変更、ヘッダコメントを両方の変更理由で更新 — bash 3.2+ 互換 (`${BASH_SOURCE[0]}` のみ使用、`mapfile` 等の bash 4+ 構文は使わない)
- `tests/detect-unrecorded-kills.bats`: 新規テストケース 3 件を追加 (偽陽性抑制・169 秒束ね・wrapper フェーズ長時間 kill の取りこぼし防止)。既存の「a deeper heading inside a Context block」テストの合成フェーズ名 `leaked-phase` を `code-pr` にリネーム (`leaked-phase` は実在する `scripts/run-*.sh` に対応せず、新フィルタで誤除外されテストが壊れるため)
- `docs/structure.md`: `scripts/detect-unrecorded-kills.sh` の一行説明中 "default 120s" を "default 300s" に更新 (Steering Docs sync candidate — `grep -rn "detect-unrecorded-kills.sh" docs/ tests/ scripts/ modules/` で確認済み、他のヒットは `docs/spec/issue-1387-*.md` / `docs/sessions/*/session.md` / `docs/reports/external-kill-investigation.md` のみで、いずれも disposable な Spec または過去時点のスナップショット記録のため対象外)
- `docs/ja/structure.md`: 上記の日本語ミラーを同期 (`docs/translation-workflow.md` の Sync Procedure に従う)

## Implementation Steps

1. `scripts/detect-unrecorded-kills.sh`: wrapper を持たないフェーズを respawn シグナル生成から除外する。bash 部で `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"` を解決して python3 heredoc に新しい位置引数として渡し、python 側に `has_wrapper(phase)` (base = `phase` を最初の `-` で分割した先頭部分、例: `code-pr`→`code`; `<SCRIPT_DIR>/run-<base>.sh` の存在チェック) を追加、`has_wrapper()` が false になる `(issue, phase)` グループはシグナル生成そのものをスキップする (→ AC1)
2. 同ファイルのヘッダコメントに、wrapper 非保持フェーズ除外の判定基準と理由 (`wrapper_exit` を構造的に emit できないこと、`phase_complete` の欠落が kill 以外の理由でも起こりうること、`scripts/run-<phase>.sh` の存在有無による汎用判定であり特定フェーズ名のハードコードではないこと) を明記する (→ AC2)
3. 同ファイルの `WINDOW=120` を `WINDOW=300` に変更し、`--window` のヘッダコメントを 2026-08-17 の実測値 (respawn 間隔 169 秒) を根拠として更新する (→ AC3)
4. `tests/detect-unrecorded-kills.bats` に新規テストケースを 3 件追加する: (a) `verify` フェーズで `phase_complete` を欠いたまま数日後に再実行しても出力が生成されないこと、(b) wrapper を持つフェーズ (例: `code-pr`) で 169 秒間隔の連続 kill が既定 `--window` (300, フラグ省略) のもとで 1 つのバーストに束ねられること、(c) wrapper を持つフェーズで約 7,000 秒間隔かつ終端イベントを挟まない kill が、抑制導入後も respawn シグナルとして検出されること (取りこぼし防止の回帰ガード)。あわせて既存の「a deeper heading inside a Context block」テストの合成フェーズ名 `leaked-phase` を `code-pr` にリネームする (→ AC4)
5. `bats tests/detect-unrecorded-kills.bats` をローカルで実行し、既存テスト + 新規 3 テストケースを含めたスイート全体が PASS することを確認する (→ AC5, CI)

## Verification

### Pre-merge

- <!-- verify: rubric "detect-unrecorded-kills.sh が、wrapper_exit を構造的に emit しないフェーズ (verify) について、phase_complete を欠いた実行の直後の再実行を respawn シグナルとして報告しないようになっている" --> wrapper を持たないフェーズ (`verify`) の `phase_start` 重複が respawn シグナルとして誤検出されない
- <!-- verify: rubric "偽陽性を抑制する方式とその選択理由が detect-unrecorded-kills.sh のヘッダコメントに記載されている" --> 除外または判別の基準がスクリプトのヘッダコメントに明記されている
- <!-- verify: rubric "detect-unrecorded-kills.sh の --window 既定値が 169 秒以上に更新され、その根拠として 2026-08-17 の実測値が言及されている" --> 既定 `--window` が 2026-08-17 の実測値 (respawn 間隔 169 秒) を包含する値に更新されている
- <!-- verify: rubric "tests/detect-unrecorded-kills.bats に、(a) verify フェーズの phase_complete 欠落による偽陽性ケース、(b) 169 秒間隔の連続 kill の束ねケース、(c) wrapper を持つフェーズにおける elapsed 7,000 秒程度の長時間 kill が抑制後も respawn として検出されるケースの 3 つすべてを検証するテストが追加されている" --> 実データ相当のフィクスチャで、偽陽性が抑制され本物の kill のみが検出されることがテストで保護されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが通る

### Post-merge

- 次回 `/verify` Step 15 実行時に、出力されるバーストが本物の kill のみで構成されていることを確認 <!-- verify-type: opportunistic -->

## Notes

### AC 構成の変更 (Issue コメントの AC 監査結果を反映)

Issue #1395 は `/issue` 実行後の AC 監査で、Pre-merge AC の 1 件 (「偽陽性の抑制が、wrapper を持つフェーズで発生する長時間 kill を取りこぼさない」) の rubric verify command が常時 PASS パターンに該当すると指摘された。監査が提示した 2 案のうち「rubric から外し、テスト AC 側にフィクスチャケースを追加して機械的に保護する」(より確実、と監査自身が明記) を採用し、`/spec` 実行時に Issue 本文を編集して当該 AC をフィクスチャテスト要件 (現 AC4) の (c) ケースに統合した。Pre-merge AC 数は 6 → 5 に減少し、Size M (light spec) の Simplicity Rule (Pre-merge 5 件上限) にも合致する。この編集は本 Spec 作成前に完了しており、上記 Verification は編集後の Issue 本文と一致する。

### 抑制方式の選択 (Issue 本文 Notes のトレードオフ表を踏まえた判断)

Issue 本文 Notes は (a) wrapper 非保持フェーズの除外、(b) `elapsed` 上限、(c) 併用の 3 方式を挙げ、(a) または (c) を安全側としていた。本 Spec は **(a) のみ**を採用する — `elapsed` 上限を一切導入しないため、AC4 (c) が要求する「wrapper を持つフェーズの長時間 kill (7,000 秒程度) が抑制後も検出される」は、そのフェーズの検出ロジックを変更しないことで自明に満たされる。(b)/(c) が抱えていた「偽陽性の下限 (3,636 秒) と wrapper の watchdog timeout 上限 (7,200 秒) が重なり、閾値設定次第で本物の kill を取りこぼす」リスクを構造的に回避できるため、(a) 単独が最も安全側かつ実装量が少ない選択と判断した。

### 除外判定の汎用性

`scripts/run-<phase-base>.sh` の存在チェックによる判定 (`phase` を最初の `-` で分割: `code-pr`/`code-patch` → `code`、`verify` → `verify` など) を採用し、`verify` という特定フェーズ名をハードコードしない。現状 `scripts/run-*.sh` が存在するのは issue/spec/code/review/merge の 5 フェーズのみで、`verify` のみが対応する wrapper を持たない (`grep` で確認済み)。将来 wrapper を持たない新フェーズが追加されても、この判定は自動的に対応する。

### 既存テストへの影響 (コードベース調査で確認)

- `WINDOW` 既定値の変更 (120→300): 既存の `tests/detect-unrecorded-kills.bats` の全ケースは `--window` を明示指定している (`--window 120` / `--window 60` / エラーケース) か、明示しない場合でもバースト境界を検証しない (単一シグナルのみ、またはウィンドウ値によらず単一バーストになるギャップ) ため、影響なし
- wrapper 非保持フェーズ除外の追加: 既存テストで phase_start に使われる値は `review`/`code-pr`/`code-patch` (すべて wrapper 保持) のみだが、1 件だけ例外がある — 「a deeper heading inside a Context block does not leak into a later unrelated bullet」テストが `leaked-phase` という合成フェーズ名を使っており、これは `scripts/run-leaked.sh` が存在しないため新フィルタで誤って除外され、テストの期待出力 (`Issue #9999, phase: leaked-phase`...`recorded: no`) が得られなくなる。このテストの本来の検証対象は recoveries.md の Markdown 見出し境界解析 (ネストした `#### Sub-detail` が後続の無関係な bullet に "漏れない" こと) であり phase 名自体に意味はないため、`code-pr` へのリネームで意図を保ったまま新フィルタと両立させる (Changed Files / Implementation Step 4 に反映済み)

### 新規分岐ロジックのテスト要件

Implementation Step 1 (wrapper 非保持フェーズ除外) は既存スクリプトへの新規分岐追加にあたるため、Verification の AC4 (`command "bats tests/detect-unrecorded-kills.bats"` 相当を含む rubric) は、既存スイートの PASS だけでなく新規テストケース 3 件 (Implementation Step 4) を追加したうえでのスイート PASS を要件とする。

## Consumed Comments

Cutoff: most recent `phase/*` label assignment at Step 2 (Worktree Entry) time (`2026-08-18T05:49:22Z`, the `phase/issue` label assignment predating this `/spec` run's own `phase/spec` transition in Step 3). Note: the bash safety-net script (`append-consumed-comments-section.sh`, run in Step 12) recomputes this cutoff fresh from GitHub's current timeline, by which point Step 3's own `phase/spec` label assignment is the most recent `phase/*` event — newer than both comments below — so its automated pass found 0 new entries and wrote a placeholder. This section replaces that placeholder with the actual comments consumed during this run's own Step 2 procedure (correct cutoff, run before Step 3's label transition).

- saito / MEMBER / first-class / Issue Retrospective (auto-resolved ambiguity points, rationale for the AC added at `/issue` time) / https://github.com/saitoco/wholework/issues/1395#issuecomment-5324187653
- saito / MEMBER / first-class / AC audit: flagged the "wrapper-holding-phase elapsed-upper-bound" rubric AC as an always-PASS risk (no suppression logic yet exists, so "long kills still detected" is vacuously true); recommended folding it into the fixture-test AC instead of relying on rubric alone — acted on in this Spec (see Notes § "AC 構成の変更") / https://github.com/saitoco/wholework/issues/1395#issuecomment-5324193556

### /code phase

No new comments since last phase (cutoff: most recent `phase/*` label assignment, `2026-08-18T07:40:22Z`, the `phase/ready` label predating this `/code` run's own `phase/code` transition).

### /review phase

No new comments since last phase (cutoff: most recent `phase/*` label assignment, `2026-08-18T07:49:09Z`, the `phase/review` label predating this `/review` run; issue+pr scope, no comments found).

## Code Retrospective

### Deviations from Design

N/A — implementation followed the Spec's Implementation Steps 1-5 as written, including the (a)-only suppression approach and the `scripts/run-<phase-base>.sh` existence check.

### Design Gaps/Ambiguities

N/A

### Rework

N/A

## review retrospective

### Spec vs. implementation divergence patterns
- なし。review-light Perspective 1 (Spec Deviation) で Spec Implementation Steps 1〜5 と PR diff の一致 (suppression 方式 (a) のみ、汎用 `run-<base>.sh` 存在チェック、`WINDOW` 120→300 とヘッダ根拠、フィクスチャ3件、`leaked-phase`→`code-pr` リネーム) を確認した。

### Recurring issues
- **Parser/Validator Edge Case Pre-check が実装判断で見落とされがちな正規化漏れを検出**: `has_wrapper(phase)` は外部ログ (`.tmp/auto-events.jsonl`) 由来の `phase` 文字列を `.strip()` せずに `split("-", 1)[0]` していたため、先頭空白を含む `phase` 値 (`" code-pr"`) では wrapper 保持フェーズが無診断で wrapper 非保持と誤判定されていた。実データ相当のフィクスチャテスト (AC4) は正常系の文字列のみを対象としており、この種の入力表記ゆれは Spec のトレードオフ検討 (Notes「抑制方式の選択肢とトレードオフ」) にも記載がなかった。エッジケース実行サブエージェントによる実測 (シミュレーションではなく実行) がこの回帰を検出し、`/review` Step 12 で修正・テスト追加した。
  - **改善提案**: 「外部プロセスが書き込むログファイルの文字列フィールドをキーとして使う」パターン (今回は `phase`) を持つ Spec では、Implementation Steps に「該当フィールドの正規化 (strip 等) を明示するか、正規化しない場合はその理由を明記する」ことを Notes に含めるべきかもしれない。頻度が低い ( #1395 系列で初観測) ため、次回同種のパターンが出た場合に起票判断する。

### Acceptance criteria verification difficulty
- なし。Pre-merge AC 5件は rubric 4件 + github_check 1件で UNCERTAIN なく PASS 判定できた。CI (`Run bats tests`) は Step 9 の待機完了後に SUCCESS を確認した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC ゲート: `check-pre-merge-ac.sh` で Pre-merge AC 5件すべて `[x]` を確認、`unchecked_count=0` で通過
- review-incomplete-fallback チェック: `reconcile-phase-state.sh review 1395 --pr 1396 --check-completion` の結果に `review_incomplete_fallback` フィールドなし (false 相当) — 追加ゲート条件なし
- PR #1396 は squash merge + ブランチ削除で完了 (mergeable=clean, CI success, review approved)

### Deferred Items
- None

### Notes for Next Phase
- Post-merge AC (`/verify` Step 15 実行時にバーストが本物の kill のみで構成されることを確認) は `/verify` 側の責務
- `/verify 1395` を実行可能
