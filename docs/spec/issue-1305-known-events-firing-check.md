# Issue #1305: observation-trigger: KNOWN_EVENTS 発火経路チェックのコメント/usage行誤マッチを修正

## Overview

`scripts/opportunistic-search.sh` の `KNOWN_EVENTS` (`pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle` の5種) について、各イベント名の実際の発火呼び出し箇所 (`--event <name>` の呼び出し) の有無をコメント行・usage 文字列を除外したうえで機械的に判定する新規スクリプト `scripts/check-known-events-firing.sh` を追加する。

当初 Issue は「2イベントに発火経路がなく11件の Issue が永久 SKIPPED」と主張していたが、この核心的事実主張は誤りだった (Triage AC audit と本 Issue のリファインメントで確認済み — 5イベントいずれも既に実発火経路を持つ)。唯一残る実バグは、当初想定の検証方法 (`grep -rq -- "--event $e" scripts/ skills/ modules/`) が `scripts/opportunistic-search.sh` 自身のヘッダーコメント例・usage 文字列にも誤マッチし、実発火箇所の有無に関わらず常時 PASS してしまう欠陥のみである (Pattern 2: 常時 PASS)。本 Issue はこの検証手段そのものを新規スクリプトとして正しく実装することにスコープを絞る。

## Reproduction Steps

1. `scripts/opportunistic-search.sh` のヘッダーコメント (7-18行目) には `--event pr-review-full` / `--event auto-run` を含む usage 例が literal に記載されており、165行目の usage echo 文字列にも `--event pr-review-full` が含まれる。
2. 仮に `skills/review/SKILL.md:903` の実呼び出し (`--event pr-review-full`) が削除されたとしても、`grep -rq -- "--event pr-review-full" scripts/ skills/ modules/` は `scripts/opportunistic-search.sh` のコメント/usage 行にマッチし続けるため exit 0 (真) を返し続ける。
3. つまり実発火箇所が失われても検証が失敗として検知できない — 常時 PASS のため検証手段として機能しない。

## Root Cause

当初想定の検証方法は「イベント名の文字列が `scripts/ skills/ modules/` のどこかに存在するか」だけを見る単純な substring grep であり、(a) 実際の呼び出し箇所、(b) usage/ドキュメント例としてのコメント行、(c) usage/エラーメッセージの echo/printf 文字列リテラル、の3者を区別しない。`scripts/opportunistic-search.sh` 自身のヘッダーコメント (7-18行目) と usage 文字列 (165行目) に `pr-review-full` / `auto-run` の具体例が literal に記載されているため、これら2イベントは呼び出し箇所の実在に関わらず常時マッチする。修正方針は、grep 結果からシェルコメント行 (`#` 始まり) と echo/printf usage 文字列を機械的に除外したうえで判定する新規スクリプトを追加すること。

## Changed Files

- `scripts/check-known-events-firing.sh`: new file。`scripts/opportunistic-search.sh` から `KNOWN_EVENTS` を動的に読み取り、各イベント名について `scripts/ skills/ modules/` を対象にコメント行・usage 文字列 (echo/printf) を除外した `--event <name>` 実呼び出し箇所の有無を判定する。全イベントに実呼び出し箇所があれば exit 0、1件以上欠けていれば非ゼロ exit で欠落イベント名を出力する。bash 3.2+ 互換。
- `tests/check-known-events-firing.bats`: new file。コメント行/usage 文字列のみのケースで誤って PASS しないこと (false-positive 回帰防止) と、実呼び出し箇所が存在するケースで正しく検出することの双方をカバーする bats テスト。
- `docs/structure.md`: Directory Layout の `scripts/` ファイル数コメントを 81 files→82 files、`tests/` を 116 files→117 files に変更。Key Files > Scripts > Tooling セクションに `scripts/check-known-events-firing.sh` のエントリを追加。
- `docs/ja/structure.md`: 上記 `docs/structure.md` の変更に対応する日本語ミラーの同期 (`docs/translation-workflow.md` の同期義務)。
- `modules/observation-trigger.md`: `## Notes` セクション既存箇条書き「Adding a new event requires: (1)...(2)...(3)...」に、新スクリプトでの事前検証を推奨する一文を追記。

## Implementation Steps

1. `scripts/check-known-events-firing.sh` を新規作成する。処理内容:
   - `scripts/opportunistic-search.sh` から `^KNOWN_EVENTS=` 行を `grep`/`sed` で抽出し、空白区切りのイベント名リストを得る (抽出元ファイルが存在しない、または `KNOWN_EVENTS` 行が見つからない場合は usage エラーを stderr に出力して exit 2)
   - 各イベント名 `$e` について `grep -rn -- "--event $e" scripts/ skills/ modules/` を実行し、マッチした行のうち (a) 行内容が (前後の空白を除き) `#` から始まる行 (シェルコメント)、(b) `echo`/`printf` を単語として含む行 (usage/エラーメッセージ文字列リテラル) を除外する
   - 除外後に1件も残らないイベント名を「発火経路なし」として収集する
   - 発火経路なしのイベントが1件もなければ exit 0。1件以上あれば該当イベント名一覧を stdout に出力して非ゼロで exit する
   - スクリプト自身のヘッダーコメント・usage 文字列には特定のイベント名を literal に書かない (自己参照による誤検出を避けるため。このスクリプトは引数を取らないため、他スクリプトのような `--event <example>` 形式の usage 例は不要)
   (→ acceptance criteria AC1, AC2)
2. `tests/check-known-events-firing.bats` を新規作成する (after 1)。`tests/check-forbidden-expressions.bats` と同じパターン (`SCRIPT` を `$BATS_TEST_FILENAME` から絶対パスで解決し、`setup()` で `$BATS_TEST_TMPDIR` 配下に `scripts/`/`skills/`/`modules/` を作成して `cd`) を踏襲し、各テストで fixture `scripts/opportunistic-search.sh` (`KNOWN_EVENTS="..."` 行を含む、実プロダクションのイベント名と衝突しないテスト専用イベント名を使う) を書き込む。最低限のカバレッジ:
   - 全イベントに実呼び出し箇所がある場合に exit 0
   - コメント行のみに存在するイベント名は「発火経路なし」と判定される (false-positive 回帰防止)
   - usage 文字列 (echo/printf) のみに存在するイベント名は「発火経路なし」と判定される (false-positive 回帰防止)
   - コメントでも usage 文字列でもない実呼び出し箇所が存在するイベント名は正しく検出される
   (→ acceptance criteria AC3)
3. `docs/structure.md` を更新する (after 1): Directory Layout の `scripts/` ファイル数コメント (81 files→82 files)、`tests/` ファイル数コメント (116 files→117 files) を更新し、Key Files > Scripts > Tooling セクションに `scripts/check-known-events-firing.sh` のエントリを追加する。あわせて `docs/ja/structure.md` を同じ変更内容で日本語同期する (`docs/translation-workflow.md` の同期手順に従う: 見出し・構成を保ったまま日本語で記述し、コードフェンス数の整合を確認する)。
4. `modules/observation-trigger.md` の `## Notes` セクション既存箇条書き (「Adding a new event requires: (1)...(2)...(3)...」) に、新スクリプトでの事前検証を推奨する一文を追記する (after 1)。

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/check-known-events-firing.sh" --> `scripts/observation-trigger.sh` の `KNOWN_EVENTS` 各イベント名について、コメント行・usage 文字列を除外したうえで実際の発火呼び出し箇所 (`--event <name>` の呼び出し) の有無を判定するスクリプトが追加されている
- <!-- verify: command "bash scripts/check-known-events-firing.sh" --> 現状の `KNOWN_EVENTS` 全イベントに対しスクリプトを実行すると exit 0 (全イベントに発火経路あり) を返す
- <!-- verify: command "bats tests/check-known-events-firing.bats" --> 新スクリプトの bats テストが追加されている。テスト対象ファイル `tests/check-known-events-firing.bats` は本 Issue の実装で新規作成する。コメント行・usage 文字列のみを含むケースで誤って PASS しないこと (false-positive 回帰防止) と、実際の呼び出し箇所が存在するケースで正しく PASS することの双方をカバーする

### Post-merge

- 今後 `KNOWN_EVENTS` に新しいイベント名を追加する PR で、`scripts/check-known-events-firing.sh` によって発火経路の有無が確認されている

## Notes

- **Issue 本文の記述誤りの訂正**: Issue 本文 (Related セクション) は `KNOWN_EVENTS` の定義箇所を `scripts/observation-trigger.sh:163` としているが、codebase investigation により実際の定義箇所は `scripts/opportunistic-search.sh:170` (`KNOWN_EVENTS="pr-review-full pr-review-light auto-run watchdog-kill fix-cycle"`) であることを確認した。`observation-trigger.sh` は153行のみで `KNOWN_EVENTS` を含まない。実装は `scripts/opportunistic-search.sh` を読み取り元とする。旧 spec (`docs/spec/issue-1251-ac-authoring-convention.md`) も同じ誤記を継承していた可能性がある。SPEC_DEPTH=light のためユーザー確認は行わず、本記録のみで解決する。
- **検出ロジックの事前検証**: 上記の検出アルゴリズム (コメント行・usage 文字列除外) を現状の main に対して worktree 内で手動シミュレーションし、5イベント全てで実呼び出し箇所が正しく検出され `MISSING` が空 (exit 0 相当) になることを確認済み (2026-08-09)。
- **既知の限界 (意図的スコープ外)**: 本検出ロジックはシェルコメント (`#` 行) と echo/printf usage 文字列のみを除外対象とする。`modules/verify-classifier.md` のイベント一覧表のようなドキュメント上の言及 (例:「`opportunistic-search.sh --event pr-review-full`」という説明文) は除外されず「実呼び出し箇所」としてカウントされる。これは Issue のスコープ (コメント行・usage 文字列の除外) の通りであり、SKILL.md の実手順プローズと単なる説明文をテキストレベルで機械的に区別することは非現実的なため意図的に対応しない。
- **allowed-tools 影響チェーン確認**: `modules/observation-trigger.md` は現状どの `SKILL.md` からも "Read and follow" されていない (`grep -rl "observation-trigger.md" skills/` が0件)。Notes セクションへの新規スクリプト言及追加により `allowed-tools` の更新が必要な箇所はない。
- **`modules/verify-classifier.md:40` の `fix-cycle` 行の記述陳腐化 (スコープ外)**: 同ファイルの emitter 列は `fix-cycle` を「Not yet implemented」としているが、実際には `skills/verify/SKILL.md:625` で既に発火している。本 Issue のスコープ外のため対応しない。将来の `/audit drift` または別 Issue での検出に委ねる。
- **CI ワイヤリングは対象外**: Post-merge AC は `verify-type: manual` であり、将来の新規イベント追加 PR での手動実行を期待する運用。`.github/workflows/test.yml` への自動実行組み込みは Issue のスコープに含まれないため行わない (`check-forbidden-expressions.sh` のような常時稼働 linter とは性質が異なる)。
- **SHOULD-level 追加の採用理由**: `docs/structure.md`/`docs/ja/structure.md`/`modules/observation-trigger.md` の更新は Issue 本文の明示 AC (3件) には含まれないが、(a) `docs/structure.md` のファイル数・Key Files 更新は既存の maintenance rule で「同じ change 内での更新」が明記されている、(b) `docs/ja/structure.md` は `docs/translation-workflow.md` の同期義務、(c) `modules/observation-trigger.md` の Notes 追記は Post-merge AC (今後の新規イベント追加 PR での本スクリプト利用) を実務上発見可能にするために必要、の3点から採用した。Issue の Auto-Resolved Ambiguity Points は「単一スクリプト + bats テストの追加のみ」とスコープを絞っているが、これは「11件の再型付けや `/review` 変更を含めない」という意図であり、ドキュメント整合性の維持まで排除する意図ではないと判断した。

## Consumed Comments
No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — implemented exactly per the four Implementation Steps (script, bats test, docs/structure.md + docs/ja/structure.md sync, modules/observation-trigger.md Notes addition).

### Design Gaps/Ambiguities
- N/A — no gaps found during implementation.

### Rework
- N/A — no rework occurred.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implemented `scripts/check-known-events-firing.sh` following the Spec's algorithm exactly: extract `KNOWN_EVENTS` from `scripts/opportunistic-search.sh`, grep for `--event <name>` under `scripts/ skills/ modules/`, exclude lines that are shell comments (leading `#`) or contain `echo`/`printf` as a word, and report any event with zero remaining matches as missing (exit 1) vs. all-present (exit 0).
- Verified via bats (8 cases) that the false-positive exclusion actually works: an event mentioned only in a comment line or only in an echo/printf usage string is correctly reported as missing, while an event with a real call site is correctly detected even alongside comment/usage noise for the same name.
- Ran the script against the current `main` state and confirmed exit 0 — all 5 production `KNOWN_EVENTS` entries (`pr-review-full`, `pr-review-light`, `auto-run`, `watchdog-kill`, `fix-cycle`) have real firing sites, consistent with the Issue's corrected Background finding.

### Deferred Items
- None from this phase — the Issue's own Post-merge AC (`verify-type: manual`) already defers CI wiring to a future new-event-addition PR, and the Spec's Notes already record the pre-existing `modules/verify-classifier.md:40` staleness and this repository's structural limitation (documentation prose mentioning `--event <name>` counts as a real call site) as explicitly out of scope.

### Notes for Next Phase
- No PR exists for this patch-route Issue — `/verify` should confirm the 3 pre-merge AC (already checked in the Issue body during this phase) and the single `verify-type: manual` post-merge AC remains open until a future `KNOWN_EVENTS` addition PR actually exercises the new script.
