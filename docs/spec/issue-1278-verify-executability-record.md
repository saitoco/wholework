# Issue #1278: verify: Step 8b の Claude 実行可否判定を記録し Manual waiting を reason 別に内訳可能にする

## Overview

`/verify` Step 8b は未チェックの manual post-merge AC について「Claude が直接実行できるか」を rubric 判定しているが、その結果を機械可読な形で残していない。2a (executable) 側は `AskUserQuestion` への応答を `verify_user_confirm` として記録するだけで判定自体は残らず、2b (non-executable) 側は一切記録がない。しかも `/auto --batch` の verify は確認なしで実行するため `verify_user_confirm` すら発火しない。

結果として `/audit stats --retention` の「Manual waiting」は「issue 時点で機械可読な形が書かれなかった AC を持つ Issue の数」を数えているだけで、「本当に人間を待っている件数」を表していない (#1158 の精査では 79 件中 5 件 = 6% のみが真に人間必須)。

本 Issue は Step 8b の判定結果を **Step 9 の既存コメント内のマーカー** (SSoT) と **`.tmp/auto-events.jsonl` の `verify_executability` イベント** (補助) の 2 系統に記録し、`/audit` の Manual Waiting Count を reason 別の内訳へ拡張する。AC の書き換えや型の移行は行わない — 判定は実行時に毎回行われるため、装備が変われば次の `/verify` で自動追従する。

## Changed Files

- `scripts/verify-executability-marker.sh`: 新規。`format` サブコマンド (マーカー 1 行の生成 + reason 語彙の検証) と `resolve` サブコマンド (latest-wins 解決 + TSV 出力) を提供 — bash 3.2+ 互換 (`mapfile` / 連想配列を使わない)
- `modules/l0-surfaces.md`: § Machine-Readable Event Marker に `type=verify-executability` 節を追加 (形式・属性・reason 語彙表・latest-wins 解決規則・未記録 AC の扱い)
- `skills/verify/SKILL.md`: Step 8b を「判定 → 記録 → 2a/2b 分岐」構造へ改修、Step 9 のコメント本文冒頭にマーカー行を埋め込む手順を追加、`allowed-tools` に新規スクリプトを追加
- `skills/audit/SKILL.md`: § Manual Waiting Count を reason 別内訳へ拡張、Section 8 の `Manual waiting` 行を 2 行 (total / human queue) へ分割し WARNING 閾値を human queue に付け替え、`allowed-tools` に新規スクリプトを追加
- `scripts/emit-event.sh`: ヘッダコメントのイベント辞書に `verify_executability` のフィールド定義を追加 — コメントのみの変更で実行コードは触らない (`emit_event()` は event 名を引数で受けるため実装追加は不要)。bash 3.2+ 互換は現状維持
- `modules/event-emission.md`: § Non-Wrapper Emitters の `/verify` 段落に `verify_executability` を追記
- `tests/verify-executability-marker.bats`: 新規。`format` (executable / non-executable + reason / capability-unavailable / other) と `resolve` (latest-wins、マーカー無し、gh 失敗時 fail-open、引数バリデーション) を検証
- `tests/verify.bats`: Step 8b / Step 9 の構造テストを追加 (両分岐で記録すること、Step 9 が新規コメントを投稿しないこと)
- `docs/structure.md`: scripts 一覧に `scripts/verify-executability-marker.sh` の行を追加 (`scripts/resolve-preview-ac-fallback.sh` の行の直後)
- `docs/ja/structure.md`: 同じ行を日本語で追加 (`docs/translation-workflow.md` の同期義務対象 — top-level `docs/*.md` の変更に伴うミラー更新)
- `docs/workflow.md`: [Steering Docs sync candidate] L231 が `modules/l0-surfaces.md` のマーカー形式を `type=verify-fail` の例で参照している。新マーカーは `/verify` の FAIL 経路とは無関係なため変更不要の見込みだが、`/code` 時に本文を読んで判断すること
- `scripts/collect-verify-retention-stats.sh`: [Steering Docs sync candidate] L18 のヘッダコメントが "Manual waiting" という指標名を参照している。本スクリプトは verify-type 別の生集計を出力するもので reason 内訳は持たないため変更不要の見込みだが、`/code` 時に確認すること

## Implementation Steps

1. `scripts/verify-executability-marker.sh` を新規作成する (→ 受け入れ条件 B/F/H)。bash 3.2+ 互換。`set -uo pipefail` (`resolve` は gh 失敗時 fail-open が必要なため `-e` は付けない)。`SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` の既存慣行に従う。2 サブコマンド:
   - `format <issue> <ac_index> <executable> [reason] [capability=<key>|detail=<text>]` — 標準出力にマーカー 1 行のみを出す。バリデーション (すべて満たさない場合は stderr にメッセージを出して exit 1):
     - `<issue>` / `<ac_index>` は正の整数
     - `<executable>` は `true` または `false`
     - `executable=true` のとき `reason` 以降の引数は禁止
     - `executable=false` のとき `reason` は必須、かつ語彙 (`browser-required` / `external-service-required` / `production-action-required` / `subjective-judgment` / `capability-unavailable` / `other`) のいずれか
     - `reason=capability-unavailable` のとき `capability=<key>` が必須
     - `reason=other` のとき `detail=<text>` が必須。`detail` の値は出力時に `"` で囲むため、`"` と `-->` を含む場合は exit 1
     - 出力形式 (`executable=true` のとき `reason` 以降を省略):
       `<!-- wholework-event: type=verify-executability phase=verify issue=<N> ac=<index> executable=<true|false> [reason=<slug>] [capability=<key>] [detail="<text>"] -->`
   - `resolve <issue>` — `gh issue view <issue> --json comments --jq` で `<!-- wholework-event: type=verify-executability` を含むコメントのうち `createdAt` 最大のものを 1 件だけ取り、その本文に含まれる全マーカー行を解析して 1 行 1 AC の TSV を出す: `<ac_index>\t<executable>\t<reason>\t<capability>` (`reason` / `capability` は該当属性がなければ空文字列)。マーカーが無い場合・gh が失敗した場合は空出力 + exit 0 (fail-open。`scripts/resolve-preview-ac-fallback.sh` と同一方針)。不正引数は exit 1
   - `format` / `resolve` 以外のサブコマンド、および引数なしは usage を stderr に出して exit 1。`--help` / `-h` は usage を stdout に出して exit 0
2. `modules/l0-surfaces.md` § Machine-Readable Event Marker に `**`type=verify-executability`**` 節を追加する (→ 受け入れ条件 C/D/G)。既存の `type=pre-merge-ac-gate` 節の直後に置き、同節と同じ記述順 (投稿元 → 属性 → 例 → latest-wins) に揃える。記述内容 (網羅):
   - 投稿元: `/verify` Step 9 の `## Acceptance Test Results` コメント本文の冒頭。**専用コメントは投稿しない**
   - 1 AC につき 1 マーカー行。属性は `ac=<1-based index>` (Issue 本文の全 checkbox 通し番号。`gh-issue-edit.sh --checkbox` と同一規約)、`executable=<true|false>`、`executable=false` のときのみ `reason=<slug>`、`reason=capability-unavailable` のときのみ `capability=<key>`、`reason=other` のときのみ `detail="<一行>"`
   - reason 語彙表 (6 行、網羅): `browser-required` / `external-service-required` / `production-action-required` / `subjective-judgment` / `capability-unavailable` / `other`。表の直後に「`capability-unavailable` は**人間が必要という意味ではなく、`.wholework.yml` に該当 capability を追加すれば Claude が解ける**ことを意味する。したがって metric 上は人間キューと別区分として数える」という区別を明記する
   - latest-wins: Issue コメントは append-only なので、消費側は **`type=verify-executability` マーカーを含むコメントのうち `createdAt` 最大の 1 件のみ**を解決し、それ以前のコメントは全て無視する (既存 2 マーカーと同じ「earlier marker's set is superseded in full, never merged with a later one」規約)。粒度は AC 単位ではなくコメント単位である — 直近の `/verify` は「その時点で未チェックだった manual AC 全件」を判定するため、そのコメントが現在の未チェック集合に対する完全なスナップショットになる
   - 未記録の扱い: 最新スナップショットに `ac=` が存在しない未チェック manual AC は「判定記録なし (未評価)」として扱い、人間必須区分には数えない
   - 解決は `scripts/verify-executability-marker.sh resolve <issue>` に委譲する
   - `type=pre-merge-ac-gate` と同様、消費側 (`/audit`) は Comment Consumption Procedure を経由せず `gh issue view` で直接解決するため、Processing Steps の Cross-phase marker exception への追加は不要である旨を明記する
3. `skills/verify/SKILL.md` Step 8b を改修する (→ 受け入れ条件 A/E) (2 の後)。挿入位置は「**1. Claude Executability Judgment (rubric-based)**」の Non-executable examples 行の直後、「**2a. If executable: ...**」の直前。追加内容:
   - 「**1b. Record the judgment (both branches)**」見出しを新設し、判定ごとに `(ac_index, executable, reason, capability)` を保持して `EXECUTABILITY_RECORDS` として Step 9 まで引き継ぐことを明記する。reason 語彙は `${CLAUDE_PLUGIN_ROOT}/modules/l0-surfaces.md` § Machine-Readable Event Marker の `type=verify-executability` 節を参照する (二重定義しない)
   - `reason` 選択の指針: 唯一の障害が未設定の project capability である場合 (Step 4 で `detect-config-markers.md` 経由で取得済みの `HAS_BROWSER_CAPABILITY` 等が false) は `capability-unavailable` + `capability=capabilities.<key>` を使う。それ以外は語彙表から選び、いずれにも当てはまらない場合のみ `other` + `detail=` を使う
   - **この記録は 2a / 2b の分岐前に行う**こと、および `AskUserQuestion` を呼ぶかどうかとは独立であることを明記する。`/auto --batch` の verify は Claude 実行可能な AC を確認なしで実行するため `AskUserQuestion` を経ない — 応答時点ではなく判定時点で記録しないと、その経路の判定が丸ごと欠落する
   - `verify_executability` イベント emit を追加する。既存の `verify_user_confirm` emit と同一構造 (`source emit-event.sh` → `restore_auto_session_pointer $NUMBER` → `AUTO_EVENTS_LOG` ガード) にする。フィールドは `ac_index={N}` / `executable={true|false}` / `reason={slug or empty}`
4. `skills/verify/SKILL.md` Step 9 を改修する (→ 受け入れ条件 B) (3 の後)。「**Comment body format:**」のコードフェンス内の `## Acceptance Test Results` 見出しより前に、`EXECUTABILITY_RECORDS` の各件に対して `${CLAUDE_PLUGIN_ROOT}/scripts/verify-executability-marker.sh format ...` を実行して得たマーカー行を並べる手順を追加する。併せて明記すること: (a) `EXECUTABILITY_RECORDS` が空 (この run で manual AC を判定していない) の場合はマーカー行を一切追加しない、(b) この記録のために**新規コメントを投稿してはならない** — Step 9 の既存コメント 1 件に同梱する
5. `skills/verify/SKILL.md` frontmatter の `allowed-tools` の `Bash(...)` リストに `${CLAUDE_PLUGIN_ROOT}/scripts/verify-executability-marker.sh:*` を追加する (→ 受け入れ条件 A) (1 の後)。挿入位置は `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*` の直後
6. `scripts/emit-event.sh` のヘッダコメント辞書に `verify_executability` の項を追加し (`verify_user_confirm` の項の直前、`verify_fail_marker_posted` の直後)、`modules/event-emission.md` § Non-Wrapper Emitters の `/verify` 段落末尾に `verify_executability` (Step 8b、判定ごとに 1 イベント、`AskUserQuestion` の有無に依存しない) を追記する (→ 受け入れ条件 E) (3 の後)
7. `skills/audit/SKILL.md` の metric 側を改修する (→ 受け入れ条件 F/G) (1・2 の後):
   - § Manual Waiting Count の本文を差し替える。現行の「Issue 件数を数える」定義 (`N`) は維持したうえで、各 Issue について `scripts/verify-executability-marker.sh resolve <issue>` の出力と、未チェック `verify-type: manual` AC 行の 1-based 通し番号を突き合わせ、以下 4 区分へ**排他的に 1 Issue 1 区分**で割り当てる (優先順位は N4 > N3 > N1 > N2 の順で判定。したがって `N1 + N2 + N3 + N4 = N` が常に成立する):
     - `N4` human queue: `reason` が `browser-required` / `external-service-required` / `production-action-required` / `subjective-judgment` / `other` のいずれかの AC を 1 件以上持つ (`other` は「装備で解ける」保証がないため human queue 側に含める)
     - `N3` capability-unavailable: `reason=capability-unavailable` の AC を 1 件以上持つ
     - `N1` 判定記録なし (未評価): 最新スナップショットに `ac=` が無い未チェック manual AC を 1 件以上持つ
     - `N2` executable: 未チェック manual AC の全件が `executable=true` として記録されている
   - Section 8 の表の `| Manual waiting | N | > 5 | OK / WARNING |` 行を 2 行へ置き換える: `| Manual waiting (total) | N | — | — |` と `| Manual waiting (human queue) | N4 | > 5 | OK / WARNING |`。表の直後に 4 区分の内訳を箇条書きで表示する手順を追加し、WARNING 閾値は N4 に対してのみ適用すること、および N1 (未評価) を human queue に混入させないことを明記する
   - frontmatter `allowed-tools` の `Bash(...)` リストに `${CLAUDE_PLUGIN_ROOT}/scripts/verify-executability-marker.sh:*` を追加する (挿入位置は `${CLAUDE_PLUGIN_ROOT}/scripts/collect-opportunistic-retire-candidates.sh:*` の直後)
8. `tests/verify-executability-marker.bats` を新規作成する (→ 受け入れ条件 H/I) (1 の後)。`tests/resolve-preview-ac-fallback.bats` の PATH prepend による `gh` モック方式をそのまま踏襲する (`MOCK_DIR="$BATS_TEST_TMPDIR/mocks"`、`gh` モックは `--jq` を解釈せず、gh 側の `sort_by(.createdAt) | .[-1]` で最新 1 件に絞り込まれた結果の本文を canned output として返す)。Issue 本文が要求する 3 ケースを最低限含めたうえで、以下を検証する:
   - `format` executable 判定: `@test "format: executable=true emits marker without reason"` — 出力が `ac=3 executable=true` を含み `reason=` を含まないこと
   - `format` non-executable + reason 判定: `@test "format: executable=false with reason emits reason attribute"` — `executable=false reason=browser-required` を含むこと。加えて `reason=capability-unavailable` で `capability=` 必須、`reason=other` で `detail=` 必須、`executable=false` で `reason` 省略時に exit 1、語彙外 slug で exit 1 を検証
   - `resolve` latest-wins: `@test "resolve: latest-wins snapshot yields one TSV row per marker"` — 2 マーカーを含む最新コメント本文から 2 行の TSV (`3\ttrue\t\t` / `5\tfalse\tbrowser-required\t`) が得られること。加えてマーカー無しで空出力 + exit 0、gh 失敗で空出力 + exit 0 (fail-open)、非数値引数で exit 1 を検証
9. `tests/verify.bats` に構造テストを追加する (→ 受け入れ条件 A/B) (3・4 の後)。既存の `step8a_section()` / `step8c_section()` と同じ awk 抽出ヘルパー `step8b_section()` (`/^#### Step 8b: /` 開始、次の `^#### ` または `^### ` 見出しで終了) と `step9_section()` (`/^### Step 9: /` 開始、次の `^### ` 見出しで終了) を追加し、(a) Step 8b が `verify-executability` と `verify_executability` の両方を含むこと、(b) Step 8b の記録手順が 2a 見出しより前の行に現れること (`grep -n | cut -d: -f1` の行番号比較。既存の Step 2 ガードテストと同じ手法)、(c) Step 9 が `verify-executability-marker.sh` を含むこと、を検証する
10. `docs/structure.md` と `docs/ja/structure.md` の scripts 一覧に `scripts/verify-executability-marker.sh` の行を追加する (→ 受け入れ条件 F の SHOULD 相当) (1 の後)。挿入位置は両ファイルの `scripts/resolve-preview-ac-fallback.sh` の行の直後。`docs/ja/structure.md` は日本語で記述する

## Alternatives Considered

| 案 | 内容 | 採否 |
|---|---|---|
| `manual` を `deferred` / `human` に型分割する | 著作時点で「人間必須」を宣言する型を導入する | **却下** (Issue 本文の決定)。Claude と人間の境界は (a) プロジェクトの装備、(b) セッション状態、(c) 操作者の判断 で動くため、著作時点の型に固定すると必ず陳腐化する |
| マーカー生成を LLM prose に任せる (スクリプト新設なし) | Step 9 でマーカー行を LLM が直接書く | **却下**。受け入れ条件 H が「マーカー生成」の bats 検証を要求しており、prose 生成は bats で検証できない。また reason 語彙の妥当性 (`capability-unavailable` に `capability=` 必須等) を決定的に強制できない |
| 判定結果を専用コメントとして投稿する | `type=verify-executability` 専用コメントを Step 8b で投稿 | **却下** (Issue 本文の決定)。Step 9 が既に AC ごとの結果コメントを投稿しているため、コメント数を増やさず同梱する |
| latest-wins を `(issue, ac)` ペア単位で解決する | AC ごとに最新マーカーを個別に探す | **却下**。既存 2 マーカー (`preview-ac-unverified` / `pre-merge-ac-gate`) の「earlier marker's set is superseded in full」規約から外れる。かつ metric は「現在未チェックの manual AC」しか数えないため、直近 run が評価した集合が現在の未チェック集合と一致し、コメント単位で情報が失われない |
| 内訳の単位を AC 行数に変える | Manual waiting を AC 行数で数え直す | **却下**。既存の WARNING 閾値 5 は Issue 件数基準で設定されている。単位を変えると閾値の意味が変わり、内訳導入と閾値再調整が同時に混ざる |
| `reason=other` を capability 側 (N3) に数える | 判定不能を装備投資側に寄せる | **却下**。`other` は「装備で解ける」保証がないため、human queue (N4) 側に数える方が安全側 (過小報告しない) |

## Verification

### Pre-merge

- <!-- verify: grep -n "verify-executability" skills/verify/SKILL.md --> `skills/verify/SKILL.md` Step 8b が、2a / 2b の両分岐で判定結果を記録する手順になっている (2b 側は現在まったく記録していない)
- <!-- verify: rubric "Step 8b の記録手順が Step 9 の Acceptance Test Results コメントへのマーカー埋め込みとして定義されており、独立したコメント投稿を行わないことが明記されている" --> 記録が Step 9 の既存コメント内のマーカーとして行われ、新規コメントを追加しない手順になっている
- <!-- verify: grep -n "verify-executability" modules/l0-surfaces.md --> `modules/l0-surfaces.md` の Machine-Readable Event Marker 節に `type=verify-executability` が追加され、latest-wins の解決規則が既存マーカーと同じ形で記述されている
- <!-- verify: rubric "reason の語彙一覧が定義され、capability-unavailable が装備投資で解決可能な区分として人間必須の区分と明確に分けて説明されている" --> reason の語彙が定義され、`capability-unavailable` が「装備で解ける」を意味し人間キューと区別されることが明記されている
- <!-- verify: grep -n "verify_executability" skills/verify/SKILL.md --> `.tmp/auto-events.jsonl` への `verify_executability` イベント emit が、既存 emit と同じ `AUTO_EVENTS_LOG` ガード付きで追加されている
- <!-- verify: grep -n "capability-unavailable" skills/audit/SKILL.md --> `skills/audit/SKILL.md` の Manual Waiting Count が reason 別の内訳を出力し、WARNING 閾値が人間キュー分に対して適用される形に変更されている
- <!-- verify: rubric "判定記録のない AC が未評価区分として分離され、人間必須件数に含まれないことが手順上明確である" --> 判定記録が存在しない AC (未評価) が内訳上で独立した区分として扱われ、人間キューに混入しない
- <!-- verify: command "bats tests/verify-executability-marker.bats" --> bats テストが追加され、(1) executable 判定のマーカー生成、(2) non-executable + reason のマーカー生成、(3) latest-wins の解決、の 3 ケースを検証している
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 判定記録が蓄積した後、`/audit stats --retention` の Manual waiting 内訳で「本当の人間キュー」が全体の何割かを実測し、#1158 が推定した 6% と比較する
- `capability-unavailable` に分類された件数を確認し、`.wholework.yml` に該当 capability を追加すれば解ける件数が把握できることを確認する

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/verify-executability-marker.sh:*` — マーカー行の生成 (`format`) と latest-wins 解決 (`resolve`)。`skills/verify/SKILL.md` と `skills/audit/SKILL.md` の両方の `allowed-tools` に追加が必要

### Built-in Tools

なし (既存の Read / Write / Edit / Grep で足りる)

### MCP Tools

なし

## Uncertainty

- **`reason=other` の内訳帰属**: Issue 本文の metric 案は human queue (N4) を 4 slug で列挙し `other` に触れていない
  - **検証方法**: Issue 本文の reason 語彙表を読む。`other` は「上記のいずれでもない」であり「装備で解ける」保証がない
  - **結論**: N4 (human queue) に含める。過小報告しない安全側を採る。Implementation Step 7 に明記済み
  - **影響範囲**: Implementation Steps 7、受け入れ条件 F/G
- **`/verify` worktree セッション内での `source emit-event.sh` ブロック**: `/verify` は Step 3 で worktree に入るため、worktree isolation guard が `source` 経由の関数呼び出しを拒否する (`modules/worktree-lifecycle.md` § "`source`-based shell function calls are blocked by the worktree isolation guard")
  - **検証方法**: 既存の Step 8b `verify_user_confirm` emit が同じ構造で同じ制約下にあることをコード上で確認済み (`skills/verify/SKILL.md` L383-392)
  - **結論**: 新規制約ではない。jsonl イベントは Issue 本文で「補助」と位置づけられており、SSoT である Step 9 のマーカーは `gh issue comment` 経由なのでこの制約の影響を受けない。設計は成立する
  - **影響範囲**: Implementation Steps 3 (emit がベストエフォートである旨は既存 emit と同じ扱いで足りる)

## Notes

### allowed-tools impact chain

新規スクリプト `scripts/verify-executability-marker.sh` について、`skills/*/SKILL.md` の `allowed-tools` に対する literal エントリの有無を確認した。両呼び出し元に明示追加が必要である (ワイルドカード `scripts/*.sh` を含む `allowed-tools` は存在しない):

- `skills/verify/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/verify-executability-marker.sh:*` の追加が必要 (Implementation Step 5)
- `skills/audit/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/verify-executability-marker.sh:*` の追加が必要 (Implementation Step 7)

`scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` は組み込みツール名 (`Read` / `Write` / `Bash` 等) のみを対象としており、`Bash(...)` 内のスクリプトパスは検査対象外のため、同ファイルの更新は不要。

### SKILL.md 変更時の MUST 制約 (`scripts/validate-skill-syntax.py` 検出)

`skills/verify/SKILL.md` / `skills/audit/SKILL.md` を編集する際、以下は validator が検出する:

- 半角 `!` をコードフェンス / インラインコード / HTML コメントの外の本文で使わない
- Step 番号に小数を使わない (本 Spec の Step 8b / 9 は既存の見出し規約であり新規の小数付与ではない)
- `<!-- verify: command "..." -->` のパスはリポジトリ相対 (`tests/...`) で書く

### 非対話モードでの auto-resolve ログ (3 件)

| # | 曖昧点 | 解決 | 根拠 |
|---|---|---|---|
| 1 | latest-wins の解決粒度 (コメント単位か `(issue, ac)` ペア単位か) | **コメント単位** | 既存 2 マーカー (`preview-ac-unverified` / `pre-merge-ac-gate`) の「earlier marker's set is superseded in full, never merged with a later one」規約に一致。加えて metric は「現在未チェックの manual AC」のみを数えるため、直近 `/verify` が評価した集合が現在の未チェック集合と一致し情報が失われない |
| 2 | 内訳の単位 (Issue 件数か AC 行数か) | **Issue 件数を維持**し、優先順位 N4 > N3 > N1 > N2 で 1 Issue を 1 区分へ排他割当 | 既存 § Manual Waiting Count が Issue 件数を数えており、WARNING 閾値 5 もその単位で設定されている。単位変更は閾値の意味を変えるため内訳導入と混ぜない |
| 3 | マーカー生成を script 化するか LLM prose に任せるか | **script 化** (`scripts/verify-executability-marker.sh format`) | 受け入れ条件 H が「マーカー生成」の bats 検証を要求しており prose では検証不能。reason 語彙の妥当性検証 (`capability-unavailable` に `capability=` 必須、`other` に `detail=` 必須) も決定的に強制できる |

### Issue 本文の verify command を 2 件修正した

`/issue` フェーズの retrospective コメント (2026-08-08T13:27:07Z) が指摘した常時 PASS 系欠陥 2 件を、本フェーズで Issue 本文側を修正した (Issue 本文が verify command の SSoT のため、Spec 側は修正後の値を verbatim コピーしている):

- 受け入れ条件 F: `grep -n "Manual Waiting Count" skills/audit/SKILL.md` → `grep -n "capability-unavailable" skills/audit/SKILL.md`。`Manual Waiting Count` は既存見出しとして main に存在するため実装前から PASS していた。`capability-unavailable` は現在 0 hit で、内訳導入によって初めて出現する
- 受け入れ条件 H: `ls tests/` → `command "bats tests/verify-executability-marker.bats"`。`tests/` は既に多数のファイルを含むため新規テストの有無に関わらず PASS していた

### 本 Issue が扱わない第 2 の manual AC 評価経路

`scripts/post_merge_check.sh` は複数 Issue の `verify-type: manual` AC を束ねて P/F/S を対話プロンプトで問う別経路であり、判定結果を記録しない。本 Issue のスコープは Step 8b に閉じているため変更対象外だが、この経路を通った Issue の判定は metric に現れない。実測データが出た後に必要性を判断する材料として記録しておく。

### 既存実装との齟齬検出

Issue 本文の前提記述と既存実装を突き合わせた結果、齟齬は検出されなかった。特に以下は本文の主張どおりであることを確認した:

- `skills/verify/SKILL.md` Step 8b の 2b 分岐 (L396-398) は検証ガイドを端末出力するだけで、イベント emit もコメント投稿も行っていない
- `.wholework.yml` に `capabilities.browser` / `capabilities.visual-diff` はいずれも未設定 (`capabilities:` 配下は `workflow: true` のみ)
- `skills/audit/SKILL.md` § Manual Waiting Count は単一の Issue 件数のみを算出し、Section 8 の閾値 5 はその総数に対して適用されている

### Consumed Comments

| login | authorAssociation | trust tier | 意図の要約 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue` フェーズの retrospective。AC verify command の常時 PASS 欠陥 2 件 (`Manual Waiting Count` grep / `ls tests/`) を非破壊で報告し、後続 `/spec` での修正を委任。Issue 本文への `session=next` 付与 (2 件) は既に適用済み。曖昧点の新規検出なし、サブ Issue 分割不要と判断 | https://github.com/saitoco/wholework/issues/1278#issuecomment-5226306395 |
