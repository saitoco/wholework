# Issue #1107: append-consumed-comments: dedup ガードを phase 単位にし verify の安全網を実効化

## Overview

`scripts/append-consumed-comments-section.sh` の dedup ガード (L36-38) は `## Consumed Comments` 見出しの存在のみを判定材料にしており、当該 phase のエントリが実際に記録されたかどうかを見ていない。`## Consumed Comments` 見出しは `/spec` / `/code` フェーズで必ず作成されるため、`/verify` フェーズが実行される時点では常に見出しが存在し、`modules/l0-surfaces.md` § "Bash wrapper fallback (Issue #811)" が規定する `/verify` の決定的書き戻し安全網が構造的に一度も発火しない。実測として #1069・#1074 の 2 件で同一の取りこぼしが確認されている (詳細は本 Issue 本文の実測セクションおよび `docs/spec/issue-1069-html-check-css-combinator.md` の Verify Retrospective を参照)。

本 Spec では、見出しの存在有無で即 `exit 0` する現行ガードを、既存セクションへの追記可否を URL 単位の重複排除で判定するロジック (Issue 本文の方針 B) に置き換える。方針選定の理由は `## Notes` を参照。

## Reproduction Steps

1. 既にある phase (`/spec` または `/code`) によって `## Consumed Comments` 見出しが書き込み済みの Spec ファイルを用意する。
2. 後続の phase (例: `/verify`) のコメント消費フォールバックとして `scripts/append-consumed-comments-section.sh $NUMBER verify` が呼ばれる状況で、Issue に当該 phase の cutoff より後の新規コメントが存在するようにする。
3. スクリプト L36-38 のガード (`grep -q "^## Consumed Comments" "$SPEC_FILE"`) が見出しの存在のみで真になり、新規コメントを一度も読みにいかないまま `exit 0` することを確認する。

## Root Cause

L36-38 の dedup ガードは「`## Consumed Comments` という文字列が Spec ファイル中に存在するか」だけを条件にしている。この見出しは `/spec` (および `/code`) フェーズで必ず作成されるため、`/verify` フェーズ到達時点では常に存在する。結果として、`/verify` 自身のコメント消費ステップがエントリを 1 件も記録していなくても、フォールバックスクリプトは即座に `exit 0` して何もしない。`modules/l0-surfaces.md` が「`/verify` phase (in-session): `SKILL.md` contains an explicit bash call to `append-consumed-comments-section.sh` ... ensuring deterministic writeback regardless of prose execution」と規定する安全網の役割が、このガードによって名目上のものになっている。

## Changed Files

- `scripts/append-consumed-comments-section.sh`: L36-38 の「見出し存在のみで `exit 0`」ガードを、見出しが存在する場合は既存の `## Consumed Comments` セクション本文に含まれる URL と重複しない新規エントリのみを算出して追記し、新規エントリが無ければ何も書き換えずに `exit 0` するロジックに置き換える。bash 3.2+ 互換 (macOS system bash) を維持すること — 連想配列 (`declare -A`, bash 4+) は使用しない。
- `tests/append-consumed-comments-section.bats`: 「既存セクションに新規コメント (新しい URL) が追記される」ケースと「同一 phase 再実行時に同じコメントが重複追記されない」ケースの 2 テストを追加する。
- Steering Docs sync candidate (grep 済み、変更不要と確認):
  - `modules/l0-surfaces.md` (L220-227 の fallback 説明は post-processor という役割の記述のみで、内部ガードのロジックには言及していないため現状のまま正確)
  - `scripts/run-spec.sh` / `scripts/run-code.sh` (pre/post 比較は `grep -c "^## Consumed Comments"` による見出し件数比較のみで、本修正は見出しを複数作らないため無影響)
  - `docs/structure.md` L171 (スクリプトの役割説明は "post-processor fallback" のままで正確)
  - `scripts/emit-event.sh` L165-172 (呼び出しラッパーのコメントのみで内部ロジックに非依存)
  - `tests/run-verify.bats` / `tests/run-code.bats` / `tests/run-spec.bats` (いずれも該当テストは comments 配列が空のモックを使うシナリオで、新規エントリ 0 件 → 追記なしという結果は新ロジックでも変わらないため既存のアサーションのまま成立)

## Implementation Steps

1. `scripts/append-consumed-comments-section.sh` の L36-38 を、`## Consumed Comments` 見出しの有無で分岐する構造に変更する (見出しが無ければ Step 2、あれば Step 3 に進む)。(→ 受入条件 1, 2)
2. 見出しが存在しない場合: 現行動作を維持する (見出し + エントリ、またはコメントが無い場合は "No new comments since last phase." を新規作成)。(after 1) (→ 受入条件 1)
3. 見出しが存在する場合: 現行どおり `ALL_COMMENTS` (cutoff フィルタ + verify-fail 例外 + `unique_by(.url)`) を算出したうえで、Spec ファイル中の `^## Consumed Comments` 行から次の `^## ` 行 (または EOF) までを既存セクション本文として抽出し、その本文中に `.url` が部分文字列として既に含まれる要素を除外する。残った要素を新規エントリとする。(after 1) (→ 受入条件 1, 4)
4. 新規エントリが 1 件以上残る場合: 既存の見出し・既存エントリはそのままに、新規エントリのみを既存セクション本文の末尾 (次の `## ` 見出しの直前、無ければ EOF) に追記する。新規エントリが 0 件の場合: ファイルを一切変更せず `exit 0` する (同一 phase の再実行で新規コメントが無いケースも、このパスで自然に重複を防げる)。(after 3) (→ 受入条件 1, 3, 4)
5. `tests/append-consumed-comments-section.bats` に、(a) 既存セクションに新しい URL のコメントが追記されること、(b) 同一 phase を同じコメントで再実行しても重複しないこと、を検証する 2 つの `@test` を追加する。(after 4) (→ 受入条件 3, 4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/append-consumed-comments-section.sh の dedup ガードが、## Consumed Comments 見出しの存在のみでは exit 0 しなくなり、当該 phase のエントリ有無 (方針 A) または URL による重複排除つきの既存セクション追記 (方針 B) に置き換えられている" --> dedup ガードが phase 単位または URL 単位になっている
- <!-- verify: file_not_contains "scripts/append-consumed-comments-section.sh" "# Check if section already exists; skip if present (deduplicate guard)" --> 見出し存在のみで exit 0 する旧ガードが除去されている
- <!-- verify: rubric "tests/ 配下に、## Consumed Comments 見出しが既に存在する Spec に対して当該 phase の新規エントリが追記されることを検証するテストケースが追加されており、bats 実行が通る" --> 既存セクションありのケースを検証するテストが追加されている
- <!-- verify: rubric "同一 phase を再実行した場合に同じコメントが二重に記録されないことを検証するテストケースが tests/ 配下に存在する" --> 重複追記が起きないことのテストが追加されている

### Post-merge

- 次回 `/verify` 実行時に cutoff より後の Issue コメントが `## Consumed Comments` に記録されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- **方針 B (URL 単位の重複排除 + 既存セクション追記) を採用した理由**: Issue 本文は方針 A (phase 名のエントリ有無で判定) と方針 B (URL 重複排除での追記) を両論併記し「`/spec` で確定する」としていた。方針 A は「当該 phase のエントリが既に存在するか」という二値判定であるため、`verify-max-iterations` (デフォルト 3、`.wholework.yml` で設定可能) による `/verify` 再実行ループのように、同一 phase 名 (`verify`) が同一 Issue のライフサイクル内で複数回実行され、かつ各回で新しいコメントが投稿され得るケースを正しく扱えない — 1 回目の `verify phase` エントリが存在する時点で 2 回目以降が丸ごとスキップされ、本 Issue が修正しようとしている「見出し単位の過剰なガード」と同型の問題を phase 単位に縮小再生産するだけになる。方針 B は個々のコメント URL で重複を判定するため、同一 phase の再実行でも新規コメントは正しく追記され、既知のコメントは正しく重複除外される。また方針 B はスクリプト単体の変更で閉じ、`modules/l0-surfaces.md` の Step 5 (LLM 側のエントリ記述フォーマット) や他 2 スキルの prose 記述規約には手を入れずに済むため、変更範囲が小さい。
- **不在検証型 AC の参照点** (`modules/verify-patterns.md` §26、Issue 本文からの引き継ぎ): 2 番目の Pre-merge AC (`file_not_contains ... "# Check if section already exists; skip if present (deduplicate guard)"`) は不在検証型。参照点 (2026-07-30 時点、`/issue` 実行時点で確認): `scripts/append-consumed-comments-section.sh` L36 に当該コメント行が現在存在し、ファイル自体は 90 行超の非空スクリプトである。`/verify` はこの文字列がスクリプト中から実際に取り除かれたことをもって判定すること (ファイル不在・空ファイル化による見かけ上の不在ではない)。
- **Out of Scope (Issue 本文から引き継ぎ)**: `/spec` / `/code` フェーズの pre/post count comparison 経路 (見出し件数比較のみのため現行ガードのままで正しく機能する); `#1078` (worktree fresh 作成時の追記消失、別機構の問題); cutoff 決定ロジックの変更 (#1069/#1074 の実測で cutoff の問題ではないことを確認済み)。

## Consumed Comments

- saito (MEMBER, first-class): `/issue 1107 --non-interactive` の Issue Retrospective。#1054 の opportunistic verification で、本 Issue の Pre-merge AC 2 番目 (不在検証型) に参照点が authoring 時点で未記録だったことを検出し、`## Notes` セクションに 2026-07-30 時点の参照点 (`scripts/append-consumed-comments-section.sh` L36 に該当コメントが存在) を追加した経緯を記録したもの。この追加は Issue 本文に既に反映済みで、本 Spec の `## Notes` に引き継ぎ済み。あわせて Type=Bug・Size=M・タイトル/AC分類/sub-issue分割は変更なしと確認。 (https://github.com/saitoco/wholework/issues/1107#issuecomment-5132340110)

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在のまま実行を継続** — reason: Issue のラベルは `phase/code` (Spec は既に存在) であり、`/spec` フェーズがラベルを `phase/ready` を経由せず直接 `phase/code` に遷移させたと推測される。`reconcile-phase-state.sh --check-precondition code-pr` は `matches_expected: false` を返したが、Spec ファイル自体は存在し内容も完備しているため、SKILL.md の非対話モード既定 (「warn and continue」) に従い、警告を出力のうえ Spec を使用して実装を続行した。
  - Other candidates: 実行を中断し `/spec 1107` の再実行を促す (Spec が既に存在するため不要と判断)

## Code Retrospective

### Deviations from Design
- なし。Spec の Implementation Steps 1-5 をそのまま実装した。

### Design Gaps/Ambiguities
- なし。Spec の `## Notes` (方針 B 採用理由) が十分具体的で、実装中に追加の解釈判断は不要だった。

### Rework
- jq フィルタ `select(($body | contains(.url // "")) | not)` は jq のパイプスコープ規則により `.url` が `$body` context (文字列) に対して評価されてしまい `Cannot index string with string ("url")` エラーとなっていた。エラーは `2>/dev/null` に隠蔽され `NEW_COMMENTS` が常に `[]` にフォールバックし、新規テストが無言で FAIL していた。`(.url // "") as $u | ($body | contains($u)) | not` の形に修正し、`.url` をオブジェクトコンテキストで先に束縛することで解消した。jq のパイプ内で `.` を再束縛する式に他のフィールド参照を混在させる際は、参照対象を `as` で先に固定してからパイプする必要がある。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の方針 B (URL 単位の重複排除 + 既存セクション追記) をそのまま採用し、実装は Spec Implementation Steps 1-5 通りに完了した
- 既存セクションに新規エントリが 0 件の場合はファイルを一切変更せず `exit 0` する設計とした (プレースホルダー "No new comments since last phase." を上書きしない仕様も Spec 通り維持)
- behavioral change detection (`tests/run-verify.bats` が対象ファイルを参照) によりフルスイート `bats tests/` (1285 tests) を実行し全て PASS を確認

### Deferred Items
- なし

### Notes for Next Phase
- Pre-merge AC 4件 (rubric x3, file_not_contains x1) は本フェーズで目視検証済みで Issue チェックボックスを更新済み。`/review` では念のため再確認を推奨
- Post-merge AC (observation, event=auto-run) は次回 `/verify` 実行時に別 Issue でのコメント投稿を待って自然検証される想定。今回の PR 内では検証不要
- `#1078` (worktree fresh 作成時の Consumed Comments 追記消失) は本 Issue のスコープ外の別機構の問題として明示的に残置されている
