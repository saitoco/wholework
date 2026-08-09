# Issue #1285: opportunistic-verify: run-fact トークン事前フィルタが判定可能な候補を落とさないように

## Overview

`modules/opportunistic-verify.md` Step 1 が `scripts/opportunistic-search.sh` に渡す `--facts` (run-fact トークン事前フィルタ) は、候補の条件テキストがどの run-fact トークンとも一致しない場合、その候補を候補集合から即座に除外する。実測 (`session 46468-1786195191`, `/auto 1278` の `/verify` Step 14) では、ゲートなしで 13 件あった候補が `--facts` 適用後に 0 件になり、うち #400 は本実行の事実で判定可能だった。フィルタの目的は「LLM 判定コストの削減 (候補集合の絞り込み)」であり「除外」ではないため、この挙動は目的に反する。

本 Issue は `--facts` の役割を「除外ゲート」から「優先順位付け (トークン一致を先頭に、不一致を後段に配置) + 上限件数キャップ」に変更し、トークン不一致のみを理由に判定可能な候補が失われないようにする。Issue 本文が提示した対応方針 (a) (フィルタを推奨順序付けに降格) を採用し、(b) (空集合時フォールバック) は (a) の設計により構造的に不要になる (後述 Root Cause 参照)。

## Reproduction Steps

1. `collect-run-facts.sh` 形式の facts JSON を用意する。`fact_tokens` が、判定対象の `verify-type: opportunistic` 条件テキストとどの部分文字列でも一致しないものとする (例: `/verify` のみに到達したセッションの facts — `modules/run-fact-matching.md` の記録によれば bare なフェーズ名トークンは Issue #1238 で意図的に除去されているため、この種のセッションの `fact_tokens` は route/Size/PR番号/anomaly カウンタ等の粗い軸に限られる)。
2. `scripts/opportunistic-search.sh /verify --facts <facts.json>` を、上記 facts と部分文字列が一致しない条件テキストを持つ Post-merge AC (例: #400 の「Issue #393 と同様のシナリオ...で、reconcile が `matches_expected` を返すことを確認」) に対して実行する。
3. 出力が `[]` になることを確認する。この AC は当該実行の事実で判定可能だったにもかかわらず、トークン不一致のみを理由に候補集合から除外される。実測では 13 件の候補全てがこの経路で除外された。

## Root Cause

`scripts/opportunistic-search.sh` の `--facts` ゲート (opportunistic mode 専用、`--event` 未指定時のみ有効。342-362行目) は、候補の条件テキストが `FACT_TOKENS_LOWER` のいずれの部分文字列とも一致しない場合、`continue` により候補を即座に除外する (359-361行目)。フィルタの意図は「LLM 判定コストの削減のための絞り込み」だが、実装は「不一致 = 除外」という強い等式を採用しており、これが判定可能な候補を落とす直接原因である。

この挙動が実害化する理由は `fact_tokens` の語彙の薄さにある。`modules/run-fact-matching.md` の記録によると、`fact_tokens` は元々 bare なフェーズ名 (`verify` 等) を含んでいたが、AC 条件文の大半がプロパティ内でフェーズ名に言及するためフィルタが事実上 no-op 化しており (`13→13`, session `83694-1786088052`)、Issue #1238 で意図的に除去された。`/verify` は `wrapper_for()` マッピングを持たない (`run-verify.sh` が存在せず in-session 実行のため — `docs/tech.md` Fork context 表) ため、`/verify` のみに到達したセッションの `fact_tokens` は route/Size/PR番号/anomaly カウンタ等の粗い軸に限られ、条件テキストの自然言語表現とはほぼ重ならない。結果として `/verify` 中心のセッションで発火する opportunistic 候補は、フィルタが「不一致 = 除外」で動く限り高確率で全滅する構造になっている。Issue #1238 は「フィルタが緩すぎて no-op 化する」問題を修正した副作用として、`/verify` 専用セッションで「フィルタが厳しすぎて判定可能な候補まで落とす」本 Issue の問題を生んでいる。

`--context-file` (`keyword=` ゲート) の寄与については、#400 の実際の Post-merge AC 行を確認した結果 `keyword=` 属性を持たないため無条件マッチであり、13→0 の結果は `--facts` ゲート単独の挙動と判断できる (Issue 本文に切り分け結果を追記済み)。

## Changed Files

- `scripts/opportunistic-search.sh`: `--facts` ゲート (opportunistic mode 専用) を「除外」から「並べ替え + 上限件数キャップ」に変更。bash 3.2+ 互換を維持
- `modules/opportunistic-verify.md`: Step 1 の `--facts` の説明を「候補集合を絞り込む」から「候補集合を順序付ける (トークン不一致のみを理由に落とさない)」契約へ更新
- `tests/opportunistic-search.bats`: 既存テスト `"fact gate: token mismatch excludes the issue"` (635行目) を新挙動に合わせてリネーム・修正し、新規回帰テストを追加

## Implementation Steps

1. `scripts/opportunistic-search.sh`: `--facts` ゲートを「除外」から「並べ替え + 上限件数キャップ」に変更する (→ acceptance criteria 2)。
   - 342-362行目のトークン不一致チェックから `continue` を削除し、`FACT_MATCHED` の真偽値を保持したまま候補を結果集合に残す
   - 475行目付近の結果追加時、各エントリに一時的な優先度フィールド (例: `_fact_matched`) を付与する。`--facts` 未指定または `--event` 指定時 (フィルタ非適用) は常に一致扱いとする
   - 全 Issue のループ完了後 (479行目 `echo "$RESULTS"` の直前)、`FACT_TOKENS_LOWER` が非空のときのみ以下を実行する:
     (a) 一致優先度でソートする。jq の `sort_by` の安定性に依存せず、元の追加順インデックスを第二ソートキーとして明示的に使うこと (一致候補どうし・不一致候補どうしの相対順序を保証するため)
     (b) ソート後、新規定数 `FACTS_CANDIDATE_LIMIT=30` (`scan-pending-ac.sh` の既存 `MAX_CANDIDATES` デフォルト値を踏襲。同スクリプトの候補数上限という同種の問題に対する既存の precedent — 独自の新規測定値ではない) で全体件数を切り詰める
     (c) 切り詰めが発生した場合のみ、`scan-pending-ac.sh` の `Note: truncated ...` 形式に倣った非サイレントな stderr メッセージを出力する
     (d) 出力前に一時フィールドを取り除き、既存の `{"number":N,"condition":"..."}` 出力形状を維持する (下流の `modules/opportunistic-verify.md` Step 2 消費側に影響しない)
   - `--facts` 未指定時 (`FACT_TOKENS_LOWER` が空) は上記の並べ替え・キャップ処理を一切適用せず、現行の無制限・非フィルタ挙動を完全に保持する

2. (after 1) `modules/opportunistic-verify.md`: Step 1 の `--facts` パラグラフ (26行目の括弧書き) の説明を「narrows the opportunistic-mode candidate set without requiring AC-side attributes」から、「reorders the opportunistic-mode candidate set by run-fact relevance without requiring AC-side attributes; matched candidates are prioritized, but unmatched candidates are never dropped solely for lacking a token match」へ変更する。直後に、Ordering-not-exclusion の契約 (トークン不一致は除外理由にならないこと、`opportunistic-search.sh` 側の上限件数キャップは population サイズが大きい場合のみ働く別レイヤーの安全弁であり非サイレントであること) を明記する箇条書きを追加する (→ acceptance criteria 1)。

3. (parallel with 2) `tests/opportunistic-search.bats`: 635行目の既存テスト `"fact gate: token mismatch excludes the issue"` を `"fact gate: token mismatch is deprioritized, not excluded"` にリネームし、アサーションを `[ "$output" = "[]" ]` から候補が出力に含まれることの確認 (`jq -e 'length == 1'` および `.[0].number == 801`) に変更する。加えて新規テスト `"fact gate: matched candidates ordered before unmatched, none dropped"` を追加し、fact token に一致する候補と一致しない候補を同一実行に投入した際、両方が出力に含まれ (`jq -e 'length == 2'`)、一致した候補が配列の先頭に来ることを確認する (→ acceptance criteria 3)。

4. (after 1, 3) `bats tests/opportunistic-search.bats` を実行し、全件 PASS することを確認する (→ acceptance criteria 4)。

## Verification

### Pre-merge

- <!-- verify: rubric "modules/opportunistic-verify.md の --facts の記述が、候補を除外するゲートではなく順序付けまたはフォールバック付きの絞り込みとして定義されており、トークン不一致だけを理由に候補が失われないことが明記されている" --> `modules/opportunistic-verify.md` Step 1 の `--facts` の役割が「除外ゲート」から変更され、判定可能な候補が落ちない設計になっている
- <!-- verify: grep "FACTS_CANDIDATE_LIMIT" "scripts/opportunistic-search.sh" --> `scripts/opportunistic-search.sh` の実装が上記の設計に一致している
- <!-- verify: command "bats tests/opportunistic-search.bats -f 'matched candidates ordered before unmatched'" --> 本 Issue の実測ケース (候補 13 件がトークン不一致で 0 件になる) が再現しないことを検証する bats テストが追加されている
- <!-- verify: command "bats tests/opportunistic-search.bats" --> `bats tests/opportunistic-search.bats` が PASS する

### Post-merge

- 次回以降の `/verify` で opportunistic 候補が 0 件になった場合、それがトークン不一致ではなく真に候補なしであることを確認する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **verify command の事前修正 (Comment Consumption 起因)**: `/issue` Step 15 相当の Triage AC audit コメントが、Pre-merge AC2/AC3 の verify command を Pattern 問題 (AC2: `grep -n "facts" scripts/opportunistic-search.sh` が `grep "pattern" "path"` 形式と不一致かつ `"facts"` は実装前の main に既に多数出現し常時 PASS。AC3: `command "bats tests/opportunistic-search.bats"` が直後の AC4 と同一コマンドで区別不能かつ新規テスト未追加でも既存 54 件が PASS するため常時 PASS) と判定していた。Comment Consumption Procedure でこれを読み取り、`/spec` 実行時点で Issue 本文の該当 2 件を本実装に固有の新規文字列へ修正した (`grep`/`command -f` の verify command のみ変更、条件文自体は不変)。修正前に `grep -c "facts" scripts/opportunistic-search.sh` (53件) と `bats tests/opportunistic-search.bats` (54件全 PASS) で常時 PASS リスクを確認済み。Issue 本文は `gh-issue-edit.sh` で更新済み。本 Spec の Verification セクションは更新後の Issue 本文から逐語コピーしている (Verify command sync rule)
- **`FACTS_CANDIDATE_LIMIT` の値 (30) の根拠**: 新規測定ではなく、`scripts/scan-pending-ac.sh` の既存 `MAX_CANDIDATES` デフォルト値 (30、非サイレント truncation note 付き) を踏襲した。同スクリプトは `--facts` フィルタとは独立に、候補数上限という同種の安全弁を既に持っている
- **`scripts/scan-pending-ac.sh` の同型パターンについて (スコープ外)**: コードベース調査で、`scan-pending-ac.sh` の `--facts` ゲート (170-185行目) も本 Issue と同じ「不一致 = `continue` 除外」実装であることを確認した。本 Issue のタイトル・本文は `modules/opportunistic-verify.md`/`scripts/opportunistic-search.sh` に明示的にスコープされており `scan-pending-ac.sh` への言及はないため、Issue 本文の「本 Issue が扱わないこと」方針に倣い本 Spec でもスコープ外として扱う。`scan-pending-ac.sh` は `modules/run-fact-matching.md` の rubric 判定 (Step 3) の入力を作る別の消費者であり、判定不能候補の扱いが同じ設計で良いかは別途検討が必要
- **jq ソート安定性の実装ガードレール**: Implementation Step 1 で触れたとおり、jq の `sort_by` は安定ソートを仕様として保証していないため、一致優先度のみをソートキーにすると同一優先度内の相対順序が処理系依存になり得る。元の追加順インデックスを第二キーとして明示することで、テストの再現性を確保すること
- **(b) 空集合時フォールバックについて**: Issue 本文の対応方針 (b) は、(a) の並べ替え設計を採用したことで構造的に不要になった。並べ替えは常に全候補を出力に残すため (上限キャップを超えない限り)、「フィルタ結果が 0 件になる」状況自体が発生しない
- **`--context-file` (`keyword=` ゲート) の切り分け**: #400 の実際の Post-merge AC 行を確認したところ `keyword=` 属性を持たないため、`--context-file` ゲートは無条件マッチであり実測の 13→0 に寄与していない。Issue 本文に切り分け結果を追記済み (Notes 参照)

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜4 を Spec の記載順どおりに実施した (`FACTS_CANDIDATE_LIMIT=30` 定数の追加、facts ゲートの除外→並べ替え+キャップ変更、`opportunistic-verify.md` の契約説明更新、bats テストのリネーム+新規追加)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Consumed Comments

- saito (MEMBER, first-class): Triage AC audit — Pre-merge AC2 (`grep -n "facts" scripts/opportunistic-search.sh` の引数形式不正 + 常時 PASS) と AC3 (`command "bats tests/opportunistic-search.bats"` が直後の AC4 と同一コマンドで区別不能 + 常時 PASS) を指摘し、実装方針確定後の `/spec` での具体化を推奨。本 Spec 作成時に Issue 本文の該当 2 件を修正して対応 (Notes 参照)。https://github.com/saitoco/wholework/issues/1285#issuecomment-5229038068
- (code phase) No new comments since last phase.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Step 1 の設計どおり、facts ゲートの `continue` (除外) を除去し、各候補に `_fact_matched` を付与した上でループ完了後に一括で並べ替え+キャップする方式を採用した (逐次除外より、jq の安定ソート非保証を追加順インデックス `_idx` で明示的に補う設計のほうが Spec の要求 (相対順序の保証) に忠実だったため)
- `FACTS_CANDIDATE_LIMIT=30` は新規測定値ではなく `scan-pending-ac.sh` の `MAX_CANDIDATES` 既定値を踏襲 (Spec Notes 参照)
- truncation メッセージは `scan-pending-ac.sh` の `Note: truncated ...` 形式を踏襲し、非サイレントな stderr 出力とした

### Deferred Items
- Post-merge observation AC (`session=next` の `/verify` で opportunistic 候補が 0 件になった場合、真に候補なしであることを確認) は未着手 — 次回以降の `/verify` 実行で評価される
- `scripts/scan-pending-ac.sh` の同型パターン (Spec Notes に記載のスコープ外項目) は本 Issue のスコープ外のまま。別途 Issue化を検討する余地あり

### Notes for Next Phase
- Pre-merge AC 4件は全て verify command 実行で PASS 済み、Issue body のチェックボックスも更新済み
- Spec からの実装乖離なし (Deviations from Design は N/A)
- `bats tests/opportunistic-search.bats` は全 55 件 PASS (新規テスト2件を含む)
