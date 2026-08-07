# Issue #1239: opportunistic-search: run-fact token 絞り込みを opportunistic mode に導入

## Overview

`scripts/opportunistic-search.sh` の opportunistic mode (`--event` なしで skill 名指定時) には絞り込みゲートが実質存在せず、`/verify` 完了時の実測 (session `33233-1786023637`) では 6 回の実行すべてで同じ 14 件が候補として列挙され全て SKIP と判定された (84 回判定 / PASS 0 件)。

既存の `keyword=` ゲートは match loop 内で mode 非依存に実装済みだが、呼び出し元 `modules/opportunistic-verify.md` が `--context-file` を渡していないため到達不能になっている。また `keyword=` 属性自体も既存 AC の大半に付いていない (`/verify` 向け候補 14 件中主要 8 件が `keyword=0`)。

一方 `scripts/scan-pending-ac.sh --facts <path>` は AC 側の属性を必要としない run-fact token 照合を実装済みで、実測 (session `3340-1786079730`) で 418 件 → 186 件 (55.5% 除外) の効果が確認されている。本 Issue はこの同じロジックを `opportunistic-search.sh` の opportunistic mode に横展開し、属性付与を待たずに即座に効く絞り込みを導入する。あわせて `--context-file` 伝播で `keyword=` ゲートの到達不能な穴も塞ぐ。

## Changed Files

- `scripts/opportunistic-search.sh`: change — `--facts <path>` オプション追加 (既存の `--facts-file <path>` とは別物)。opportunistic mode (`--event` なし) の per-line match loop に fact-token フィルタを追加。header usage コメント更新。bash 3.2+ 互換 (macOS system bash) — `mapfile`/`${VAR,,}` は使わず、`scripts/scan-pending-ac.sh` と同じ `while read` ベースのトークン照合パターンに合わせる
- `modules/opportunistic-verify.md`: change — Step 1 に、`restore_auto_session_pointer` による session id 解決 → `collect-run-facts.sh` 呼び出し → `--facts`/`--context-file` を `opportunistic-search.sh` へ伝播する手順を追加
- `modules/verify-patterns.md`: change — §10 (Opportunistic Post-Merge Conditions) に `keyword=` の既存 AC 一括付与スコープ外方針を追記
- `tests/opportunistic-search.bats`: change — `--facts` トークンフィルタの新規テストケース追加 (`fact gate: ...` 命名規則)
- `docs/structure.md`: [Steering Docs sync candidate] `scripts/opportunistic-search.sh` の説明 ("opportunistic skill search and observation event scan", line 206) が `--facts` 追加後も正確か確認。役割自体は変わらないため変更不要見込みだが `/code` で最終判断 (`docs/ja/structure.md` の対応行も同様)

## Implementation Steps

1. `scripts/opportunistic-search.sh` に `--facts <path>` オプションと fact-token フィルタを追加する (→ acceptance criteria AC1, AC2)
   - 引数パースに `--facts <path>` を追加 (既存の `--facts-file <path>` とは別のケース分岐。文字列前方一致ではなく `case` の完全一致なので衝突しない)
   - パース後、`scripts/scan-pending-ac.sh` と同じロジック (`jq -r '[.issues[].fact_tokens[]?] | unique | .[]'` → lowercase) で `FACT_TOKENS_LOWER` を解決する。ファイル不在・parse 失敗時は stderr に warning を出してフィルタを無効化 (fail-open — `scan-pending-ac.sh` のような hard error ではなく、本スクリプトの既存 `--context-file`/`--facts-file` と同じ規約に合わせる)
   - 共有 per-line match loop 内に `[ -z "$EVENT_NAME" ]` (opportunistic mode のみ) でガードした新規ゲートを追加: `FACT_TOKENS_LOWER` が非空かつ行の小文字化テキストがどのトークンも部分文字列として含まない場合はスキップ。event mode 側の `--facts-file`/`when=` ゲートは変更しない
   - header usage コメントに `--facts <path>` (この文字列そのもの。`--facts PATH` 等の別表記にしない) を `--facts-file <path>` と並べて追記し、両者の違い (`--facts`: condition text へのトークン部分文字列照合・AC 属性不要・opportunistic mode 限定 / `--facts-file`: 構造化 `when=` 節照合・event mode) を一行で説明する

2. `modules/opportunistic-verify.md` Step 1 で `--facts`/`--context-file` を生成・伝播する (→ acceptance criteria AC3, AC4, AC5, AC6) (parallel with 1)
   - `opportunistic-search.sh` 呼び出し前に `source scripts/emit-event.sh` して `restore_auto_session_pointer <呼び出し元スキル自身の Issue/PR 番号>` を呼ぶ (Step 3 が既に行っている呼び出しと同一 — 新しい session-id 受け渡しフラグは導入しない)
   - `AUTO_SESSION_ID` が解決できた場合: `collect-run-facts.sh` を `--session` 明示なしで呼ぶ (今設定された `AUTO_SESSION_ID` 環境変数を既存のフォールバック順で自動的に拾う) → `.tmp/facts-<session>.json` へ出力 → `--facts .tmp/facts-<session>.json` を付与。解決できない場合 (standalone 実行等) は `--facts` を省略し、現行と同じ無絞り込み動作を維持する
   - Write ツールで `.tmp/context-<呼び出し元 Issue 番号>.md` を生成する (内容: 現在処理中の Issue の body。`$SPEC_PATH/issue-<番号>-*.md` に Spec が存在する場合はその `## Changed Files` セクションも含める) → `--context-file .tmp/context-<番号>.md` を付与
   - session id 解決方式が `restore_auto_session_pointer()` の再利用であり新規フラグを要しないことをモジュール本文に明記する (AC3 の「session id の解決方法が明記されていること」を満たす)

3. `modules/verify-patterns.md` §10 に `keyword=` 一括付与スコープ外方針を記録する (→ acceptance criteria AC7) (parallel with 1, 2)
   - 「既存の opportunistic AC への `keyword=` 一括付与は本 Issue のスコープ外とし、新規 AC から適用する」という方針を一文で追記する。#1172 が `when=` について同じ判断をした前例に合わせる (`docs/spec/issue-1169-search-population-limit.md` 134行目に前例の引用あり — Spec は disposable のため一次情報としては残らず、本追記が耐久的な記録になる)

4. `tests/opportunistic-search.bats` に `--facts` フィルタのテストケースを追加する (after 1) (→ acceptance criteria AC9, AC10)
   - 既存の `"context gate: ..."` / `"config gate: ..."` / `"when gate: ..."`命名規則に倣い `"fact gate: ..."` を新設
   - カバー範囲: トークン一致で該当 Issue を含む / トークン不一致で除外する / `--facts` 未指定時は無条件マッチ (後方互換) / 存在しない `--facts` パスは warning 付きでゲート無効化 / event mode (`--event`) では `--facts` が効かない (`--facts-file`/`when=` のみ有効) ことの確認
   - fixture JSON は `collect-run-facts.sh` の出力形式に合わせる: `{"session_id":"s1","issues":[{"number":1,"fact_tokens":["token"]}]}` (`tests/run-fact-matching.bats` の `scan-pending-ac.sh --facts` テストと同じ形)

5. 絞り込み効果を実測し Spec に記録する (after 1, 2) (→ acceptance criteria AC8)
   - Step 1, 2 実装後、`scripts/opportunistic-search.sh /verify --facts <実際または代表的な run-facts JSON>` を実行し、Issue #1239 本文記載のベースライン 14 件 (計測 scope: `phase/verify` ラベル付き closed Issue のうち `verify-type: opportunistic` タグ + skill `/verify` を含むもの。session `33233-1786023637` で計測) と比較する
   - 前後の件数・facts のソース (session id またはファイル)・計測日を本 Spec の `## Verification` セクション (Pre-merge リスト直下のプレースホルダ行) に追記する

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/opportunistic-search.sh" "--facts <path>" --> `opportunistic-search.sh` が `--facts` オプションを受け付ける
- <!-- verify: rubric "scripts/opportunistic-search.sh の opportunistic mode (--event なし) の match loop で、--facts で渡された run-fact token による condition text の絞り込みが適用されている。--facts 未指定時は全件通過する後方互換が維持されていること" --> opportunistic mode に token 絞り込みが適用され後方互換が維持されている
- <!-- verify: rubric "modules/opportunistic-verify.md の Processing Steps で、collect-run-facts.sh の出力を opportunistic-search.sh へ --facts で渡す手順が記述されている。session id の解決方法が明記されていること" --> `opportunistic-verify.md` が facts を渡す手順を持つ
- <!-- verify: file_contains "modules/opportunistic-verify.md" "--facts" --> `opportunistic-verify.md` に `--facts` の記述がある
- <!-- verify: rubric "modules/opportunistic-verify.md の Processing Steps で、opportunistic-search.sh 呼び出し時に --context-file を渡す手順が記述されており、渡す内容 (今回処理した Issue の body + Spec の Changed Files など) が明記されている" --> `opportunistic-verify.md` から `--context-file` を伝播する手順が記述されている
- <!-- verify: file_contains "modules/opportunistic-verify.md" "--context-file" --> `opportunistic-verify.md` に `--context-file` の記述がある
- <!-- verify: rubric "既存 AC への keyword= 一括付与を行わない方針と、新規 AC から適用する指針が modules/ 配下のいずれかに記録されている" --> `keyword=` の適用方針が記録されている
- <!-- verify: rubric "変更前後の候補件数の比較が Spec の Verification セクションに数値で記録されている。ベースラインは /verify skill で 14 件" --> 絞り込み効果が数値で記録されている
- <!-- verify: command "bats tests/opportunistic-search.bats" --> `tests/opportunistic-search.bats` が PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) が PR で pass する

**Effect measurement (baseline)**: 14 件 (opportunistic mode, skill `/verify`。scope: `phase/verify` ラベル付き closed Issue のうち `verify-type: opportunistic` タグ + skill 名 `/verify` を含む Pre-merge/Post-merge 条件。session `33233-1786023637` で計測、Issue #1239 本文記載)。Implementation Step 5 の実施後、`/code` はこの行の直下に実装後の件数・facts のソース・計測日を追記すること (AC8 の充足条件)。

**Effect measurement (after implementation, 2026-08-07)**: `scripts/opportunistic-search.sh /verify` (`--facts` なし) で同じ母集団を再計測したところ **13 件** (ベースライン計測時点 session `33233-1786023637` から2日経過し数件クローズ等で微減。14→13 は同一計測手法の自然変動であり、`--facts` 未指定時に絞り込みが効いていないこと自体はこの再計測で確認済み — 後述のバックワード互換性確認と同義)。同じ母集団に対して `--facts` を付与し、spec→code→review→merge を完了した pr route セッション (Size M) を想定した代表的な run-facts JSON (`fact_tokens: ["pr route","Size M","spec","code","review","merge","#1300"]`) で絞り込むと **5 件** (#1051, #1053, #231, #436, #781) まで減少した — **61.5% 除外 (13→5)**。facts のソース: 実行中の `/auto` セッションが存在しない単発実行環境のため、Implementation Step 5 の指示 (「実際または代表的な run-facts JSON」) に従い、実際の `collect-run-facts.sh` 出力形式に相当する代表的 JSON (`.tmp/facts-repr-1239.json`) を使用した。

### Post-merge

- 次回以降の skill 完了時の opportunistic verification で、候補件数が変更前 (14 件) より減少していることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **session id 解決方式の決定**: Issue 本文は「#1234 と同じ方式 (`observation-trigger.sh` への `--session` 追加) を採るか、#1234 着地後にその実装を流用するか」を設計時判断に委ねていた。調査の結果、`collect-run-facts.sh` は既に `--session` フラグ / `AUTO_SESSION_ID` 環境変数 / `.tmp/auto-session-current` ポインタファイルの3段フォールバックを持ち (#1075/#1224)、`modules/opportunistic-verify.md` Step 3 は既にこのフォールバックの一部である `restore_auto_session_pointer()` (`scripts/emit-event.sh`) を呼んでいる。したがって #1234 の `observation-trigger.sh --session` 拡張を待つ・流用する必要はなく、Step 1 で `restore_auto_session_pointer` を先出しして `AUTO_SESSION_ID` を解決させ、`collect-run-facts.sh` を `--session` 明示なしで呼ぶだけで済む。この関数は `[[ -n "${AUTO_EVENTS_LOG:-}" ]] && return 0` で冪等なため、Step 3 で再度呼ばれても副作用はない。#1234 への依存はなく、blocked-by も不要という Issue 本文の記載と整合する
- **`--facts` と `--facts-file` の役割分担**: 命名が近いため、実装時に両者を混同しないよう Implementation Step 1 で明示した。`--facts` (本 Issue で新規追加): condition text への生トークン部分文字列照合、AC 属性不要、opportunistic mode (`--event` なし) 限定。`--facts-file` (既存): `when=<axis>:<value>` 属性を run facts JSON の構造化フィールドと照合、event mode 用だが実装上は mode 非依存の共有ループ内にある。event mode で `--facts` を渡しても (ガードにより) 無視される — 誤用時に warning を出す等の追加防御は本 Issue の AC に含まれないため `/code` の裁量とする
- **`keyword=` ゲート自体の修正は不要**: `keyword=` ゲートの実装 (`opportunistic-search.sh` L255-266) は既に mode 非依存で、`--context-file` さえ渡されれば opportunistic mode でも正しく動作する。今回の変更は呼び出し元 (`modules/opportunistic-verify.md`) から `--context-file` を渡す配線のみで、ゲート実装自体への変更はない
- **BRE メタ文字チェック**: Issue 本文の verify command はいずれも `file_contains`/`rubric`/`command`/`github_check` で `grep` 形式の `\|` 等の BRE メタ文字は含まれない。該当なし
- **patch route 検証**: `ALWAYS_PR=false` かつ Size=M → pr route (PR が存在する) のため `github_check "gh pr checks" "Run bats tests"` はそのまま正しい形。実際に `.github/workflows/test.yml` のジョブ名が `Run bats tests` であることを確認済み。修正不要
- **Issue 本文との整合性確認**: Background の事実主張 (2 モード構成、`keyword=` ゲートの mode 非依存性、`modules/opportunistic-verify.md` の `--context-file` 未伝播、`scan-pending-ac.sh --facts` のロジック) はいずれもコードベース実測で確認済み。実装との矛盾なし

## Consumed Comments

- **saito** (MEMBER, first-class): Issue Retrospective。Auto-Resolved Ambiguity Points の根拠 (`--facts` 検索文字列を `--facts-file` との部分文字列衝突を避けて `--facts <path>` に変更した理由、`--context-file` 伝播検証 AC を追加した理由、session id 解決方式を設計時判断に据え置いた理由) を記録。Background の事実主張はコードベース実測で裏付け確認済みとのこと — 本 Spec の調査でも独立に同じ結論を確認した。https://github.com/saitoco/wholework/issues/1239#issuecomment-5216043099
