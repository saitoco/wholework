# Issue #1335: auto: --until モードの Round 内 issue 処理順序を Value/Size と関連性で最適化

## Overview

`/auto --batch --until <query>` の Until mode は、`resolve-batch-query.sh` が返す `ROUND_LIST` (昇順 issue 番号、機械的ソート) をそのまま List mode に渡して処理する。関連する issue 同士 (例: #1049/#1153、#1105/#1323) が ROUND_LIST 上で離れて配置されると手戻り・二重編集・コンフリクトが起きやすい。本 Issue は Until mode の Round ループに ROUND_LIST の並び替えステップを追加し、(1) Value/Size による ROI 順、(2) title prefix クラスタリング、(3) 意味的関係判断 (LLM) の 3 シグナルを組み合わせて、関連 issue が隣接し、かつ ROI の高い issue から着手されるようにする。既存の blocked-by gate (List mode step 4) は代替しない — 並び替えは処理順序のみを変更し、gate 自体は並び替え後も per-issue で従来どおり動作する。

## Changed Files

- `scripts/compute-round-order.sh`: new file — ROUND_LIST の各 issue について title/Size/Value を取得し ROI を計算する (bash 3.2+ compatible)
- `tests/compute-round-order.bats`: new file — ROI 計算とフォールバック値のテスト (`WHOLEWORK_SCRIPT_DIR` mock)
- `modules/round-ordering.md`: new file — 3 シグナルの組み合わせ手順、blocked-by gate との関係、実運用確認手順を定義する shared module
- `skills/auto/SKILL.md`: Until mode step 6 に並び替えステップを挿入し、`allowed-tools` に `compute-round-order.sh` を追加 (bash compat: n/a — Markdown skill file)
- `tests/auto-batch.bats`: Until mode セクション向けの新規 `@test` を追加 (bash compat: bats 1.13.0 で動作確認済み — #1334 と同じ awk 抽出パターンを再利用)
- `docs/structure.md`: Directory Layout のファイル数コメント更新 (`modules/` 44→45、`scripts/` 83→84、`tests/` 119→120 — 実装時点の実測ベースラインに合わせ Spec 記載の118→119から補正、Code Retrospective参照) と Key Files への新規エントリ追加 [Steering Docs sync candidate — 本 Issue で直接対応]
- `docs/workflow.md`: `--batch --until <query>` の説明段落に並び替えステップの記述を追加 [Steering Docs sync candidate — 本 Issue で直接対応]

## Implementation Steps

1. `scripts/compute-round-order.sh` を新規作成する (→ AC1, AC2)。

   呼び出し規約: `compute-round-order.sh "$ROUND_LIST"` — 空白区切りの issue 番号を 1 引数として受け取り (`auto-checkpoint.sh write_batch` と同じ引数規約)、`for num in $1` で反復する。

   各 issue について、`get-issue-size.sh` の Project field 取得パターン (GraphQL 優先 → `size/*`/`value/*` label フォールバック) を踏襲しつつ、`get-issue-size.sh` の `GQL_QUERY` に `title` フィールドを追加した 1 種類のクエリを使い、1 issue あたり 1 回の `gh-graphql.sh` 呼び出しで `title`/Size/Value をまとめて取得する (`get-issue-value.sh` に相当するスクリプトは既存に存在しない — Notes 参照)。`gh-graphql.sh` は `jq` に `-r` を渡さないため、`--jq` フィルタは JSON オブジェクト (`{title, size, value}`) を返す形にとどめ、取得後に呼び出し元でローカルに `jq -r '... | @tsv'` を再適用してタブ区切りに変換する (Code Retrospective参照。GraphQL 往復自体は 1 issue あたり 1 回のまま)。

   `size_rank` (XS=1, S=2, M=3, L=4, XL=5。未設定/取得失敗時は中立値 3) と `value_num` (1–5。未設定/取得失敗時は中立値 3) から `roi = value_num / size_rank` を awk で計算し (小数第2位まで)、`number<TAB>size<TAB>value<TAB>roi<TAB>title` を入力順のまま 1 行ずつ標準出力する。クラスタリング・並び替えは行わない (責務は module 側 — Notes 参照)。bash 3.2+ 互換 (連想配列不使用)。

2. `tests/compute-round-order.bats` を新規作成する (after 1) (→ AC1)。

   `WHOLEWORK_SCRIPT_DIR` mock で `gh-graphql.sh` を差し替え (`modules/tech.md` の BATS Mocking Convention に準拠)、以下を検証する:
   - ROI 計算の正しさ (例: Value=5/Size=XS → roi=5.00 が Value=1/Size=XL → roi=0.20 より大きい)
   - Value・Size がいずれも未設定の issue で中立値 (roi=1.00) にフォールバックすること
   - 出力順序が入力順序のまま保持されること (並び替えをしないことの確認)

3. `modules/round-ordering.md` を新規作成する (after 1) (→ AC1, AC2, AC3, AC4)。

   - **Signal 1 + 2 (機械的)**: `scripts/compute-round-order.sh` を呼び出して各 issue の roi を取得し、title の最初の `:` (先頭40文字以内に出現する場合) より前の prefix が一致する issue 同士を同一クラスタにまとめる。
   - **Signal 3 (意味的、LLM 判断)**: prefix クラスタリングで単独クラスタのままの issue について、ROUND_LIST 内の他 issue の body (`gh issue view $NUMBER --json body`) を読み、共有される file/script/module 名や明示的な相互参照 (例: 「See #N」) からクラスタを統合する。
   - **組み合わせ (`cluster-first` という語を含む見出しで明記)**: クラスタの代表値をクラスタ内最大 roi と定義し、クラスタ単位で代表値の降順に並べる。クラスタ内は個別 roi の降順 (同点は issue 番号昇順 — `resolve-batch-query.sh` 自身のタイブレークと同じ) で並べ、フラット化した issue 番号列を並び替え後の `ROUND_LIST` とする。
   - **「Relationship to the blocked-by gate」という見出し**: 本並び替えは List mode step 4 の blocked-by gate を代替しないこと、並び替えは処理順序のみを変更し gate 自体は並び替え後も per-issue で従来どおり動作することを明記する。
   - **「Confirming real-world effectiveness」という見出し**: 実運用確認の手順 — `auto-checkpoint.sh read_batch "$BATCH_ID"` の出力または session transcript で実際の round 処理順序を確認し、隣接する issue の title prefix と `compute-round-order.sh` の roi 値を突き合わせて、関連 issue が隣接しているか・高 roi issue が先行しているかを確認する — を明記する。

4. `skills/auto/SKILL.md` を編集する (after 3) (→ AC1)。

   - Until mode (`--batch --until <query>`) セクションの既存 step 6 で、「Record the output as `ROUND_LIST`.」の直後・`${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh write_batch` 呼び出しの直前に、「Read `${CLAUDE_PLUGIN_ROOT}/modules/round-ordering.md` and follow its Processing Steps to reorder `ROUND_LIST`.」を挿入する (この時点以降、`write_batch` の永続化にも per-issue 処理にも並び替え後の順序が使われる)。
   - frontmatter `allowed-tools` の `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-batch-query.sh:*` の直後に `${CLAUDE_PLUGIN_ROOT}/scripts/compute-round-order.sh:*` を追加する (allowed-tools impact chain check — Notes 参照)。
   - `tests/auto-batch.bats` の既存 `@test "Until mode section: List mode reused for per-round Issue processing"` の直後に、Until mode セクション内で `round-ordering.md` が参照されていることを確認する新規 `@test` を追加する (既存テストと同じ awk 抽出パターンを再利用)。

5. ドキュメント同期 (parallel with 4) (→ SHOULD)。

   - `docs/structure.md`: Directory Layout の `modules/` (44→45 files)・`scripts/` (83→84 files)・`tests/` (119→120 files — 実測ベースライン補正、Code Retrospective参照) コメントを更新し、Key Files の Modules 一覧に `modules/round-ordering.md` を、Scripts の Project utilities 一覧に `scripts/compute-round-order.sh` を追加する。
   - `docs/workflow.md`: `--batch --until <query>` の説明段落内、"Each round resolves the query via `scripts/resolve-batch-query.sh`" の直後に、並び替えステップ (`modules/round-ordering.md` 参照) への言及を追加する。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の Until mode (--batch --until <query>) セクションで、ROUND_LIST を resolve-batch-query.sh から受け取った直後、かつ List mode への処理委譲より前に、ROUND_LIST の並び替えステップが実装されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "Until mode (--batch --until <query>)" "round-ordering.md" --> Until mode の Round ループに ROUND_LIST の並び替えステップが実装されている
- <!-- verify: rubric "modules/round-ordering.md に、Value/Size ソート・title prefix クラスタリング・意味的関係判断の3シグナルをどう組み合わせて ROUND_LIST の順序を決定するか (優先順位を含む) が明記されている" --> <!-- verify: file_contains "modules/round-ordering.md" "cluster-first" --> Value/Size ソート・title prefix クラスタリング・意味的関係判断の3シグナルの優先順位/組み合わせ方が明記されている
- <!-- verify: rubric "modules/round-ordering.md に、並び替えステップと既存の blocked-by gate (List mode step 4) との関係 — 並び替えが blocked-by gate を代替しないこと — が明記されている" --> <!-- verify: file_contains "modules/round-ordering.md" "Relationship to the blocked-by gate" --> 既存の blocked-by gate (List mode step 4) との関係が明文化されている
- <!-- verify: rubric "modules/round-ordering.md に、実運用 (--until 実行) でこの並び替えが意図通り機能しているか (関連 issue の隣接処理、または高 ROI issue の先行処理) を確認する具体的な手順が定義されている" --> <!-- verify: file_contains "modules/round-ordering.md" "Confirming real-world effectiveness" --> 実運用でこの並び替えが意図通り機能することを確認する手順が定義されている

### Post-merge

N/A — 4件の受入条件はいずれも Pre-merge で機械検証可能なため、Post-merge 確認項目はなし。実運用効果の継続確認は Implementation Steps 3 の「Confirming real-world effectiveness」手順、および Notes を参照。

## Notes

- **Issue 本文のステップ番号と実装の乖離**: Issue 本文は挿入位置を「Step 3 (`resolve-batch-query.sh` 呼び出し) の直後、Step 5 で List mode 処理を開始する前」と記述しているが、これは #1334 (bulk `/triage` 挿入ステップの追加。本 Issue より先に merge 済み) によって Until mode のステップ番号がすでに1つ繰り下がった後の現在の実装とは一致しない (現在: `resolve-batch-query.sh` 呼び出し = step 4、ROUND_LIST 記録+`write_batch`+List mode 処理委譲 = step 6)。`docs/spec/issue-1334-auto-until-triage-insertion.md` が同じ番号繰り下げを経験済みであることからも裏付けられる。実装は Issue 本文の字面のステップ番号ではなく、現在の `skills/auto/SKILL.md` の実際のステップ構成を基準に、step 6 内の「Record the output as `ROUND_LIST`.」の直後・`write_batch` 呼び出しの直前に並び替えステップを挿入する。この位置は Issue の意図 (クエリ解決の直後・List mode 処理開始の直前) と実質的に同じであり、ステップ番号の若返りによる表記のずれのみで設計意図の対立ではない。SPEC_DEPTH=light のため AskUserQuestion による確認は行わず、この解釈で auto-resolve した。

- **3シグナルの優先順位・組み合わせ方針の決定根拠**: Issue 本文は「Value/Size を第一キーにするか、クラスタリングをタイブレーカーにするか」の判断を `/spec` に委ねている。本 Spec は cluster-first (クラスタリングを先に確定し、クラスタ順序を ROI で決める) を採用する。理由: Value/Size を第一キーにすると、ROI が異なる関連 issue 同士 (例: #1049/#1153) が ROUND_LIST 上で離れて配置されうるため、Issue の Purpose が掲げる「関連する issue 同士が近接して処理される」という主目的を損なう。cluster-first であれば隣接性は常に保たれたうえで、グループ間の処理順に ROI が反映される。

- **script と module の責務分割 (bash 3.2 互換性が動機)**: `scripts/compute-round-order.sh` は Value/Size/title 取得と ROI 計算という機械的な部分のみを担当し、prefix クラスタリング・意味的クラスタリング・グループ順序決定という「組み合わせ」ロジックは `modules/round-ordering.md` 側の LLM 手順として実装する。クラスタ管理 (issue 番号のグループ化・グループごとの代表値追跡) は連想配列があれば自然だが、bash 3.2 (macOS 標準 bash) はこれをサポートしない。`resolve-batch-query.sh` 等の既存スクリプトが bash 3.2 互換を前提にシンプルなループ・文字列結合で実装されているのと同じ制約に従い、スクリプト側はクラスタリングを行わず 1 issue 1 行の TSV 出力のみに責務を絞った。

- **`get-issue-value.sh` は存在しない**: `scripts/` には `get-issue-size.sh`/`get-issue-priority.sh` はあるが、Value 専用の取得スクリプトは存在しない (Value の既存実装は `gh-graphql.sh` の batch mutation 経由の書き込みのみで、読み出しは `/triage` 内で個別に GraphQL を叩いている)。`compute-round-order.sh` は `get-issue-size.sh` の Project field 取得パターンを踏襲しつつ、1 issue あたり 1 回の `gh-graphql.sh` 呼び出しで `title`+Size+Value をまとめて取得する新規クエリを定義する (3種類のスクリプトを個別に呼ぶより round-trip 数が少ない)。

- **allowed-tools 追加が必要**: `skills/auto/SKILL.md` の frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/compute-round-order.sh:*` の追加が必要 (allowed-tools impact chain check — 新規 `scripts/*.sh` を呼ぶ SKILL.md に literal entry が必要。Implementation Steps 4 に反映済み)。

- **verify command の空撃ち検証記録**: Pre-merge 4件すべての mechanical anchor (`round-ordering.md` / `cluster-first` / `Relationship to the blocked-by gate` / `Confirming real-world effectiveness`) について、実装前の現在のコードベース全体 (`skills/`, `modules/`, `docs/`, `scripts/`, `tests/`, `docs/ja/` 除く) を対象に `grep -rn` で0件一致であることを確認済み (実装後にのみ真になることを保証)。

- **Issue #953 / #1334 との関係**: 本 Issue は #953 (`--until` モード本体) の実運用検証から派生し、直前に merge された #1334 (triage 挿入ステップ) と同じ Until mode セクションを対象とする独立した改善。`resolve-batch-query.sh` 自体への変更はなく (クエリ解決ロジックはそのまま)、その出力を受け取った後の並び替えのみが対象。

- **AC4 の解釈 (auto-resolve)**: Issue 本文の AC4「実運用でこの並び替えが意図通り機能する... ことを確認する手順が定義されている」は文言どおり「手順が定義されていること」を要求しており、「実運用で実際に確認済みであること」までは要求していないと解釈した。実運用での実際の効果測定には新規の event 発火の仕組み (例: `verify-type: observation`) が必要になり、本 Issue (Size M) のスコープを超えるため、Pre-merge で機械検証可能な「手順が module に文書化されていること」の確認に留めた。

## Code Retrospective

### Deviations from Design

- `docs/structure.md` の `tests/` ファイル数コメントは Spec 記載の `118→119` ではなく `119→120` を採用した。実装開始前に `git ls-files tests/*.bats | wc -l` で実測したところ、変更前ベースラインが既に 119 だった (Spec 記述時点から他 Issue のマージでファイルが増えていたと推定される)。`modules/`（44）・`scripts/`（83）のベースラインは Spec 記載どおりで一致していた。

### Design Gaps/Ambiguities

- Spec Implementation Step 1 は「`get-issue-size.sh` の Project field 取得パターンを踏襲しつつ...1 issue あたり 1 回の `gh-graphql.sh` 呼び出しでまとめて取得する」とだけ記述しており、複数フィールドを 1 回の `--jq` 呼び出しで TSV 化する具体的な実装方法までは規定していなかった。`gh-graphql.sh` は `jq` に `-r` (raw output) を渡さないため、`--jq '... | @tsv'` の結果はダブルクォートで囲まれ `\t` がエスケープされた文字列としてそのまま出力され (実際のタブ文字にならない)、`IFS=$'\t' read` によるフィールド分割が機能しなかった。対応として `--jq` フィルタは JSON オブジェクト (`{title, size, value}`) を返す形にとどめ、呼び出し元 (`compute-round-order.sh`) が自前で `jq -r '... | @tsv'` に再度通してからパースする 2 段階構成にした。GraphQL 往復は 1 issue あたり 1 回のまま (`jq` の追加呼び出しはローカル処理でネットワーク往復を伴わない) なので、Spec の「1 回の `gh-graphql.sh` 呼び出し」という制約は満たしている。

### Rework

- N/A

## Consumed Comments

No new comments since last phase.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `scripts/compute-round-order.sh` は Spec 通り機械的データ取得と ROI 計算のみに責務を絞り、prefix クラスタリング・意味的クラスタリング・グループ順序決定 (cluster-first) は `modules/round-ordering.md` 側の LLM 手順として実装した (bash 3.2 に連想配列がないため)。
- `gh-graphql.sh` が `jq` に `-r` を渡さない制約に対応するため、`--jq` フィルタは JSON オブジェクトを返す形にとどめ、呼び出し元でローカルに `jq -r` を再適用して TSV 化する 2 段階構成を採用した (詳細は Code Retrospective 参照)。
- Until mode step 6 への並び替えステップ挿入位置は、Spec Notes の解釈 (Issue 本文のステップ番号は #1334 のステップ繰り下げにより既にずれている) に従い、「`ROUND_LIST` 記録直後・`write_batch` 呼び出し直前」とした。

### Deferred Items
- AC4 (実運用確認手順) は「手順が module に文書化されていること」の確認に留め、実際の `--until` 実行による効果測定は行っていない (Spec Notes の auto-resolve 解釈どおり、Size M のスコープ外)。
- `modules/round-ordering.md` の「Confirming real-world effectiveness」手順に基づく実運用検証は次回以降の `--until` 実行時に行う想定 (新規 event 発火の仕組みが必要になった場合は別 Issue で起票)。

### Notes for Next Phase
- `tests/` ファイル数の実測ベースラインが Spec 記載 (118) と異なり 119 だったため、`docs/structure.md` のコメントは 119→120 とした。今後同種の Spec で `docs/structure.md` のファイル数コメントを扱う際は、実装直前に `git ls-files` で実測してから差分を決めること。
- `modules/round-ordering.md` の Signal 3 (意味的関係判断) は `ROUND_LIST` 内の Issue body のみを読む設計であり、ラウンド外の Issue とのクラスタリングは意図的にスコープ外としている。将来この制約を緩和する提案が出た場合は、この設計判断を踏まえて検討すること。
