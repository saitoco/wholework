# Issue #1265: detect-config-markers: watchdog phase default の記載値を watchdog-defaults.sh と一致させる

## Overview

`modules/detect-config-markers.md` の Marker Definition Table にある watchdog phase default (spec/code/review/merge/issue の 5 phase 別タイムアウト既定値) の記載のうち、code/review/issue の 3 phase が SSoT である `scripts/watchdog-defaults.sh` の実装値と乖離している。加えて、本 Spec のコードベース調査で `docs/guide/customization.md` (および対訳 `docs/ja/guide/customization.md`) にも review/issue の同じ乖離が見つかった。両ファイルの値を実装と一致させ、`modules/detect-config-markers.md` 側は SSoT を参照する記法に変更して再乖離を防ぐ。

## Reproduction Steps

```bash
$ grep -E "watchdog-timeout-(spec|code|review|merge|issue)-seconds" modules/detect-config-markers.md
watchdog-timeout-spec-seconds     ... phase default `1800`
watchdog-timeout-code-seconds     ... phase default `1800`
watchdog-timeout-review-seconds   ... phase default `2000`
watchdog-timeout-merge-seconds    ... phase default `600`
watchdog-timeout-issue-seconds    ... phase default `600`

$ grep -E "^WATCHDOG_TIMEOUT_(SPEC|CODE|REVIEW|MERGE|ISSUE)_DEFAULT" scripts/watchdog-defaults.sh
WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800
WATCHDOG_TIMEOUT_CODE_DEFAULT=4680
WATCHDOG_TIMEOUT_REVIEW_DEFAULT=5400
WATCHDOG_TIMEOUT_MERGE_DEFAULT=600
WATCHDOG_TIMEOUT_ISSUE_DEFAULT=1200
```

code (1800 vs 4680)、review (2000 vs 5400)、issue (600 vs 1200) の 3 phase が乖離している (spec/merge は一致)。

追加調査で、`docs/guide/customization.md` の Config Key Reference 表とコメント例にも同じ review (`2600`、実装 `5400`)・issue (`600`、実装 `1200`) の乖離を確認した (`docs/ja/guide/customization.md` の対訳ミラーも同様)。

## Root Cause

`scripts/watchdog-defaults.sh` の phase default 値は個別 Issue で継続的に引き上げられてきた (`ISSUE_DEFAULT` 600→1200: #628、`CODE_DEFAULT`/`REVIEW_DEFAULT` の ×1.3 再較正: #903、`REVIEW_DEFAULT` 2600→5400: #939) が、そのたびに `modules/detect-config-markers.md` の Marker Definition Table 側が追随していなかった。

加えて、`modules/detect-config-markers.md` 自身が「SSoT key reference」として参照している `docs/guide/customization.md` にも同じ review/issue の値が独立に転記されており、同様に追随できていなかった。この 2 箇所目は Issue 本文の grep 対象 (`modules/detect-config-markers.md` のみ) に含まれておらず、本 Spec のコードベース調査で新たに発見した。

## Changed Files

- `modules/detect-config-markers.md`: Marker Definition Table の `watchdog-timeout-spec-seconds` / `-code-seconds` / `-review-seconds` / `-merge-seconds` / `-issue-seconds` 5 行の「Value When `false`/Unset」列を、`` `""` (unset; falls through to global key or phase default `N`) `` の数値直書きから `` `""` (unset; falls through to global key or phase default — see `scripts/watchdog-defaults.sh` `WATCHDOG_TIMEOUT_{PHASE}_DEFAULT`) `` の SSoT 参照形に変更する
- `docs/guide/customization.md`: コメント例ブロック (`watchdog-timeout-review-seconds: 2600` → `5400`、`watchdog-timeout-issue-seconds: 600` → `1200`) と Config Key Reference 表 (review 行のフォールバック値 `2600`→`5400`、issue 行のフォールバック値 `600`→`1200`) の計 4 箇所を修正する
- `docs/ja/guide/customization.md`: 上記と対応する対訳 4 箇所 (コメント例 2 行 + 表 2 行) を同様に修正する (Steering Docs sync candidate — `docs/translation-workflow.md` の Sync Procedure 対象。既存ミラーあり)

## Implementation Steps

1. `modules/detect-config-markers.md` の Marker Definition Table で、`watchdog-timeout-{spec,code,review,merge,issue}-seconds` 5 行の「Value When `false`/Unset」列を SSoT 参照形に書き換える。対象は 5 行全体 (既に一致している spec/merge も含む) — 乖離のあった 3 行のみ参照形にすると表内の表記が数値直書きと参照形で混在するため (→ acceptance criteria 1, 2)
2. `docs/guide/customization.md` の該当 4 箇所 (コメント例ブロックの `watchdog-timeout-review-seconds`/`watchdog-timeout-issue-seconds` 行、Config Key Reference 表の同 2 行) の値を実装と一致させる (→ acceptance criteria 5 (Spec 追加分))
3. (after 2) `docs/ja/guide/customization.md` の対応する 4 箇所を日本語で同様に修正する (→ acceptance criteria 5 (Spec 追加分))
4. `docs/ja/` 配下に `modules/detect-config-markers.md` の対訳が存在しないこと、および `docs/translation-workflow.md` の Sync Procedure 対象が top-level `docs/*.md` に限定され `modules/` を含まないことを確認する (ファイル変更なし、確認のみ) (→ acceptance criteria 3)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/detect-config-markers.md の Marker Definition Table における watchdog-timeout-code-seconds / watchdog-timeout-review-seconds / watchdog-timeout-issue-seconds の phase default の記述が、scripts/watchdog-defaults.sh の WATCHDOG_TIMEOUT_CODE_DEFAULT / WATCHDOG_TIMEOUT_REVIEW_DEFAULT / WATCHDOG_TIMEOUT_ISSUE_DEFAULT の実装値と一致している (値を直接記載する案、または SSoT を参照させて数値を書かない案のいずれでもよい)" --> 3 phase の phase default 記述が実装と一致している
- <!-- verify: file_not_contains "modules/detect-config-markers.md" "phase default `2000`" --> 旧 REVIEW_DEFAULT 値 (2000) の記述が残っていない
- <!-- verify: rubric "docs/ja/ 配下に modules/detect-config-markers.md の対訳が存在する場合、同じ修正が反映されている。対訳が存在しない場合はその旨が確認されている" --> 対訳の同期状態が確認されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の bats テストジョブが全て PASS する (Size S = patch route)
- <!-- verify: rubric "docs/guide/customization.md および docs/ja/guide/customization.md の watchdog-timeout-review-seconds のフォールバック値が 5400、watchdog-timeout-issue-seconds のフォールバック値が 1200 になっている (コメント例ブロックおよび Config Key Reference 表の両方の箇所で)" --> customization.md とその対訳の watchdog phase default 値が実装と一致している

### Post-merge

なし

## Notes

- **対応方針: 案 B (SSoT 参照形) を採用**: Issue 本文の対応方針候補 (A/B/C) のうち `modules/detect-config-markers.md` は案 B を採用した。Purpose が「以後の乖離を防ぐ参照形にする」と明記しており、Pre-merge AC1 のルーブリックも「SSoT を参照させて数値を書かない案」を明示的に許容している。案 A (値のみ修正) は Issue 本文の比較表が指摘する通り「次に watchdog-defaults.sh が変わったら再び乖離する」ため不採用。案 C (追随テスト新設) は Size S / light spec でのテスト新設コストに見合わないと判断し不採用 (`tests/detect-config-markers.bats` を前提にしていた元 AC は、Issue 側で既に Size S の CI 全体チェックに差し替え済み)。
- **SSoT 参照形は 5 phase 行全体に適用**: Purpose の「phase default 値」は Issue 本文の調査対象である 5 phase (spec/code/review/merge/issue) 全体を指すと解釈し、既に一致している spec/merge の 2 行も同じ参照形に統一した。乖離のあった 3 行だけ参照形にすると表内の表記が不統一になり、かつ spec/merge も将来同じ経路で再乖離しうるため。
- **追加発見: `docs/guide/customization.md` (+ 対訳) にも同じ乖離**: `modules/detect-config-markers.md` 自身が「SSoT key reference」として参照するこのファイルに、review (記載 `2600`、実装 `5400`) と issue (記載 `600`、実装 `1200`) の同じ乖離をコメント例・Config Key Reference 表それぞれで発見した。Issue 本文の grep パターンは `modules/detect-config-markers.md` のみを対象としており、このファイルは対象外だったため見落とされていた。Purpose の「以後の乖離を防ぐ」に直接資するため Changed Files に追加し修正する。対訳 `docs/ja/guide/customization.md` は既存ミラーがあり `docs/translation-workflow.md` の Sync Procedure 対象のため同様に修正する。この追加により Pre-merge Verification 件数が Issue 本文の 4 件から 5 件に増える (Count alignment check の警告が出るが、意図した追加のため許容する)。
- **スコープ外の追加乖離 (本 Issue では未対応)**: 調査中に `modules/detect-config-markers.md` 内の 3 箇所 (Marker Definition Table の `watchdog-timeout-seconds` 行 / YAML Parsing Rules / Output Format) で、グローバルキー `watchdog-timeout-seconds` (`WATCHDOG_TIMEOUT_SECONDS`) のフォールバック値が `1800` と記載されているが、実装 (`scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_DEFAULT`) は `2700` (#556 で 1800→2700 に引き上げ済み) であり、同種の乖離が存在することを確認した。本 Issue の Purpose/AC は「phase default」(spec/code/review/merge/issue の 5 phase 別キー) に明示的にスコープされており、この「global default」(phase 未指定時のフォールバック) は対象外のため本 Issue では修正しない。別途対応を検討されたい。
- **`docs/ja/` 対訳確認 (AC3 に対応)**: `docs/ja/` 配下に `modules/detect-config-markers.md` の対訳ファイルは存在しない (`find docs/ja -iname "*detect-config-markers*"` で確認済み、ヒットなし)。`docs/translation-workflow.md` の Sync Procedure は対象を「top-level `docs/*.md` files」に限定しており `modules/` 配下は対象外であるため、対訳が存在しないのは仕様どおりであり追加対応は不要。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: Issue Retrospective — 対応方針の判断根拠 (Pre-merge AC 差し替え理由、Post-merge AC 削除理由) の記録 (Issue 本文の `## Auto-Resolved Ambiguity Points` に既に反映済みの内容で、Spec 設計への新規影響なし) / URL: https://github.com/saitoco/wholework/issues/1265#issuecomment-5242581998
