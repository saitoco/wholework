# Issue #1095: code: Patch route verify command check の発火条件に operate route を含める

## Overview

`skills/code/SKILL.md` Step 10「Patch route verify command check」の発火条件は、PR #1090 (#1061) で `Size is XS/S or --patch flag` から `ROUTE is patch` へ書き換えられた。この書き換えは `ALWAYS_PR=true` 下での Size XS/S → pr route ケースを正しく除外する一方、`ROUTE=operate` (Step 0 が解決する、PR を作らないもう一つの route) を発火対象から漏らしてしまっている。本 Issue はこの発火条件を `patch`/`operate` 両方をカバーする形に修正し、あわせて `skills/spec/SKILL.md` 側の同種チェックの扱いを確認する。

## Reproduction Steps

1. Spec が operate route と判定される内容になっている (`## Changed Files` にリポジトリ内ファイルがなく、`## Implementation Steps` が external-tool operation のみ) が、Pre-merge AC に `<!-- verify: github_check "gh pr checks" ... -->` が残っている状態で `/code` を実行する。
2. `/code` Step 0 が `ROUTE=operate` を解決する。
3. Step 10「Patch route verify command check」の条件は `If ROUTE is \`patch\`` のみを見ているため `ROUTE=operate` では発火せず、`gh pr checks` がそのまま残る。
4. 直後の verify-executor full-mode パスに未修正の `gh pr checks` が渡るが、operate route には PR が存在しないため UNCERTAIN/FAIL になる — 本来 `gh run list` 形式へ自動修正されるべきところが放置される。

## Root Cause

PR #1090 は `ALWAYS_PR=true` 下で Size XS/S が pr route に昇格するケースを正しく扱うために、条件を Size/`--patch` ベースから `ROUTE is patch` へ書き換えた。しかし `/code` Step 0 は `patch`/`pr` に加えて **`operate` route も解決する** (`modules/size-workflow-table.md` § "Diff-less Axis (operate route)")。operate route も PR を作らない点は patch route と同じだが、条件が `patch` への単純な等値比較になったことで `operate` が対象外になった。`/review 1090` が Logic Error (SHOULD) として指摘したが、PR のスコープ外として未解消のまま merge された (Issue Background より)。

`skills/spec/SKILL.md` 側の同種チェックは、そもそも #1061 の書き換え対象になっておらず、現在も #1061 以前の `Size is XS/S` ベースの条件のままである。この条件は独立した (より狭い) 盲点を持つ: operate route は Size と直交する軸のため、Size M/L の Issue でも operate route に解決しうるが、その場合この条件は素通りしてしまう。加えて `/spec` は `ROUTE` を Step 18 まで解決しない (Step 10 の時点では未確定) ため、`/code` と同じ「`ROUTE is patch or operate`」という書き方はそのまま転用できない。修正するには `modules/size-workflow-table.md` § "Diff-less Axis (operate route)" の 2 基準を Step 10 の時点で Spec 本文に対して直接評価する必要がある (Step 18 が後で行う判定を、この 1 チェックのためだけに先取りする形になる)。

`skills/code/SKILL.md` 側を修正すると、同じ Step 10 内の直後にある「Patch route branch-scoped CI AC exclusion」に新たな到達可能性が生まれる。この除外ノートは「`gh run list` へ自動変換された AC を、実装コミットがまだ存在しない段階で誤って PASS/FAIL 判定しないための保護」だが、現状は文面上 `patch route` にしか適用されない。今回の修正で `ROUTE=operate` の AC も同じ Step 10 内で `gh run list` へ自動変換されるようになるため、この除外ノートが operate route を認識しないままだと、変換直後の AC がその場で (対応する CI 結果がまだ存在しない段階で) 誤評価されてしまう — 修正前は発火しなかったため潜在化していたバグが、今回の修正によって新たに到達可能になる。同じ Step 10・同じ根本原因のため、このノートも合わせて修正する (スコープの詳細は Notes 参照)。

## Changed Files

- `skills/code/SKILL.md`: Step 10「Patch route verify command check」の発火条件を `ROUTE is patch` → `ROUTE is patch or operate` に拡張し、warning メッセージの route 表記を汎用化。直後の「Patch route branch-scoped CI AC exclusion」の条件文も同じ理由で patch/operate 両方を対象にする形に拡張
- `skills/spec/SKILL.md`: Step 10「Patch route verify command check」の発火条件に、`Size is XS/S` に加えて `modules/size-workflow-table.md` § "Diff-less Axis (operate route)" の 2 基準 (Changed Files が空 / Implementation Steps が external-tool operation のみ) を OR 条件として追加。warning メッセージも同様に汎用化
- `tests/code.bats`: 「Patch route verify command check」および「Patch route branch-scoped CI AC exclusion」の条件文に `operate` が含まれることを検証する新規テストケースを追加
- `tests/spec.bats`: 「Patch route verify command check」に Diff-less Axis 基準への参照が含まれることを検証する新規テストケースを追加
- `modules/verify-classifier.md`: [Steering Docs sync candidate] § "Patch Route CI Verification Note" の説明文 ("For Issues implemented via the patch route...") が patch route のみを対象とした記述になっている。技術的な置換フォーム (`--branch=main --limit=1` 等) 自体は route に依存せず変更不要だが、説明文の scope 記述を patch/operate 両対応に更新するかどうかは `/code` が判断する

## Implementation Steps

1. `skills/code/SKILL.md` Step 10 の「Patch route verify command check」を修正する: 発火条件 `If ROUTE is \`patch\`...` を `If ROUTE is \`patch\` or \`operate\`...` に拡張し、「両 route とも PR を作らない」ことを理由として明記する。warning メッセージ (`"Warning: patch route — ..."`) も route 名を汎用化する (例: `"Warning: $ROUTE route — ..."`)。直後の「Patch route branch-scoped CI AC exclusion」の条件文 (`For patch route, Step 10 runs before Step 11's implementation commit exists`) についても、operate route の場合は Step 12 の retrospective commit より前である旨を追記し、patch/operate 両方が対象である形に拡張する (見出し自体のリネームは必須ではない) (→ acceptance criteria A)
2. `skills/spec/SKILL.md` Step 10 の「Patch route verify command check」を修正する: `ALWAYS_PR=false` かつ `Size is XS/S` の条件に、OR で「Spec の `## Changed Files`/`## Implementation Steps` が `modules/size-workflow-table.md` § "Diff-less Axis (operate route)" の 2 基準を満たす」場合を追加する。warning メッセージも route 表記を汎用化する (→ acceptance criteria B)
3. `tests/code.bats` に新規テストケースを追加する: 「Patch route verify command check」の条件文字列 (該当箇所) に `operate` が含まれることを検証するテスト、および「Patch route branch-scoped CI AC exclusion」にも同様の検証を追加するテストを追加する。既存スイートが PASS することだけでなく、この新規テストケースを追加したうえで `bats tests/code.bats` が PASS すること (→ acceptance criteria C)
4. `tests/spec.bats` に新規テストケースを追加する: 「Patch route verify command check」に Diff-less Axis 基準 (`size-workflow-table.md`) への参照が含まれることを検証するテストケースを追加し、`bats tests/spec.bats` が PASS すること (→ acceptance criteria B の実装保証。Issue body に対応する明示的な bats AC はないが、ステップ2の修正内容を担保するために追加する)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/code/SKILL.md の Patch route verify command check の発火条件が、ROUTE が patch の場合だけでなく operate の場合にも発火する形になっている。両 route とも PR を作らないことが理由として示されている" --> 発火条件が `patch` と `operate` の両方をカバーしている
- <!-- verify: rubric "同種の発火条件を持つ skills/spec/SKILL.md 側の Patch route verify command check についても、operate route の扱いが確認され、必要なら同様に修正されている (不要な場合はその理由が記述されている)" --> `/spec` 側の同種チェックについても operate route の扱いが確認されている
- <!-- verify: command "bats tests/code.bats" --> `tests/code.bats` が PASS する

### Post-merge
- operate route と判定される Issue (Spec の Changed Files にリポジトリ内ファイルがない) に `github_check "gh pr checks"` を含む AC を置いて `/code` を実行し、`gh run list` 形式へ自動修正されることを確認する <!-- verify-type: manual -->

## Notes

- **新規テストケース要件のまとめ** (light depth のため、Step 13 retrospective の代わりにここへ記録): `tests/code.bats` に「Patch route verify command check」と「Patch route branch-scoped CI AC exclusion」の双方が `operate` route を対象にしていることを検証する新規テストケースを追加する。`tests/spec.bats` に「Patch route verify command check」が Diff-less Axis 基準を参照していることを検証する新規テストケースを追加する。いずれも既存スイートの PASS に加えて、新規テストケース追加後の PASS を要件とする。
- **Issue body と実装の整合性**: Issue Background の記述 (PR #1090 による `Size is XS/S or --patch flag` → `ROUTE is patch` への書き換え) は `skills/code/SKILL.md` の現行実装 (Step 10「Patch route verify command check」) と一致しており、コンフリクトは検出されなかった。
- **スコープについて**: Issue の AC は「Patch route verify command check」の発火条件のみを明示的に要求しているが、`skills/code/SKILL.md` 側の修正では直後の「Patch route branch-scoped CI AC exclusion」も合わせて修正する。理由は Root Cause 参照。この修正によって operate route の AC が同じ Step 10 内で `gh run list` へ変換されるようになるため、除外ノート側も追随しないと、変換直後に誤評価される新規到達可能なバグを残すことになるため。
- **Steering Docs sync candidate**: `modules/verify-classifier.md` § "Patch Route CI Verification Note" の scope 記述 ("patch route" のみ) を patch/operate 両対応に更新するかどうかは `/code` が実装時に判断する (Changed Files 参照)。技術的な置換フォームは route に依存しないため、更新は必須ではない。
- **`modules/size-workflow-table.md` の Diff-less Axis 記述との関係**: 同モジュール § "Diff-less Axis (operate route)" は「evaluated by `/spec` from the Spec it produces, and re-checked by `/code` from the same Spec」と既に記述しており、本 Issue で `/spec` Step 10 が同基準を Step 18 より前倒しで参照するようになっても、この記述と矛盾しない (Step 18 の判定自体は変更されない)。

## Consumed Comments
No new comments since last phase.
