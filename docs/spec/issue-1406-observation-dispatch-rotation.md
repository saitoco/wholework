# Issue #1406: auto: observation-dispatch の oldest-first固定選出により chronically-stalled Issue がdispatchスロットを恒久占有する問題を解消

## Overview

`/auto` の Event-based observation scan (`observation-trigger.sh --event auto-run` の matched Issue に `Skill(wholework:verify)` を dispatch する処理) は、`skills/auto/SKILL.md` の single-issue route・batch route 双方で「`observation-trigger.sh` が返す ascending-sorted (oldest-pending-first) な候補リストの先頭から `OBSERVATION_DISPATCH_THRESHOLD` (既定 5) 件を機械的に取る」という固定選出を行っている。この結果、同じ低番号の 5 Issue (#478/#562/#589/#590/#724) が premise (依存する config/実行条件) の構造的な不変により毎回 SKIPPED/UNCERTAIN で再確認が終わるにもかかわらず、dispatch スロットを恒久的に占有し、より新しい observation-pending Issue が一度も dispatch されない状態が発生している (2026-08-18 の 2 セッションで観測)。

本 Spec では、Issue 本文が挙げる 3 案 (一時除外 / ラウンドロビン / 構造的評価不能条件の除外) のうち **ラウンドロビン方式** を採用する。永続化した 1 件のカーソル (最後に dispatch した Issue 番号) を基準に候補リストを回転させたうえで cap を適用する新規スクリプト `scripts/rotate-observation-dispatch.sh` を導入し、`skills/auto/SKILL.md` の cap 選出ロジックをこれに置き換える。採用理由は `## Notes` を参照。

## Changed Files

- `scripts/rotate-observation-dispatch.sh` (新規): カーソルに基づく候補リストの回転 + `OBSERVATION_DISPATCH_THRESHOLD` cap 適用 + カーソル永続化を行うスクリプト
- `tests/rotate-observation-dispatch.bats` (新規): 上記スクリプトの新規分岐ロジックを検証する bats テスト
- `skills/auto/SKILL.md`: single-issue route (`**Event-based observation scan (auto-run event, ...)**`, 現 L754 付近) と batch route (`**Event-based observation scan (batch, best-effort)**`, 現 L1293 付近) の cap 選出ロジックを新スクリプト呼び出しに置換。frontmatter `allowed-tools` に新スクリプトのエントリを追加
- `modules/observation-trigger.md`: `## scripts/observation-trigger.sh` § "Who invokes `/verify`" § "`/auto` dispatch cap (#952)" の "cap naturally prioritizes the longest-waiting Issue first" 記述をラウンドロビン方式の説明に更新 (実装と SSoT ドキュメントの一致。bash compat: 全て bash 3.2+ 互換)

## Implementation Steps

1. `scripts/rotate-observation-dispatch.sh` を新規作成する (→ AC1)。bash 3.2+ 互換。
   - Usage: `<candidates, one issue number per line> | scripts/rotate-observation-dispatch.sh --threshold <N> [--cursor-file <path>]`
   - `--threshold <N>`: 必須。欠落・非数値・0 以下の場合はエラーメッセージを stderr に出力し exit 1 (呼び出し側が `detect-config-markers.md` で解決済みの値を渡す契約であり、これは呼び出し側バグを示すため fail-open ではなく hard error とする — `observation-trigger.sh` の `--event` 必須チェックと同じ扱い)。
   - `--cursor-file <path>`: 省略可。デフォルト `.tmp/observation-dispatch-cursor` (CWD 相対)。
   - 処理: stdin から候補を読み取り、空行除外・数値以外の行を除外 (`^[0-9]+$` に一致しない行は無視) したうえで `sort -un` により昇順・重複排除する。空候補なら何も出力せず exit 0 (カーソルファイルには触れない)。
   - カーソル読み取り: `--cursor-file` の内容を読み、`^[0-9]+$` に一致しなければ (ファイル欠落・読み取り失敗・不正な内容いずれも) カーソル値を `0` として fail-open で継続する (stderr に warning を出力するが非致命的。今回のカーソル読み取り失敗は「回転なし = 本 Issue 導入前の挙動」に縮退するだけなので、dispatch 自体をブロックする fail-closed にはしない)。
   - 回転: 候補リストを「カーソル値より大きい要素 (昇順)」→「カーソル値以下の要素 (昇順)」の順に連結する (カーソルが候補の最大値以上の場合は前者が空になり、結果的に元の昇順リストへ折り返す = wrap-around)。
   - cap: 回転後リストの先頭から `--threshold` 件を今回の dispatch 対象集合として採用する。
   - カーソル書き込み: dispatch 対象集合が空でなければ、その最後の要素を `--cursor-file` へ best-effort で書き込む (`mkdir -p` で親ディレクトリを作成してから書き込む。書き込み失敗は非致命的で stderr に warning を出すのみとし、dispatch 対象集合は通常通り標準出力へ出す — exit code は常に 0)。
   - 出力: dispatch 対象集合を 1 行 1 Issue 番号で標準出力へ出力する (回転後の順序のまま。昇順への再ソートはしない)。

2. `tests/rotate-observation-dispatch.bats` を新規作成する (after 1) (→ AC1)。既存の `tests/filter-session-verified-issues.bats` と同じ素朴な bats スタイル (bats-support/bats-assert 不使用、`run` + `[ ]`) に合わせる。`setup()` で `cd "$BATS_TEST_TMPDIR"` し、`--cursor-file` は `$BATS_TEST_TMPDIR` 配下の明示パスを渡す (相対 `.tmp/` に依存しない)。以下のケースを含む新規テストケースを追加し、スイートが PASS すること:
   - カーソルファイルが存在しない (初回実行) → 昇順リストの先頭から `--threshold` 件がそのまま dispatch 対象になる (Issue 導入前の挙動と同一であることの確認)
   - カーソルが候補リストの中間値 → カーソルより大きい要素が先に来て、`--threshold` 件で cap される
   - カーソルが候補リストの最大値以上 → 昇順リストの先頭へ折り返す (wrap-around)
   - カーソルファイルへの書き込みが失敗する状況 (例: 親ディレクトリを作成できないパスを `--cursor-file` に指定) → dispatch 対象集合は標準出力に出力され、exit code は 0 のまま
   - stdin が空 → 標準出力は空、exit code は 0、カーソルファイルは変化しない

3. `skills/auto/SKILL.md` を編集する (after 1) (→ AC1)。
   - frontmatter `allowed-tools` (L5) の `${CLAUDE_PLUGIN_ROOT}/scripts/filter-session-verified-issues.sh:*,` の直後に `${CLAUDE_PLUGIN_ROOT}/scripts/rotate-observation-dispatch.sh:*,` を追加する。
   - single-issue route (`**Event-based observation scan (auto-run event, runs after Completion Report regardless of success/failure):**` 配下、現 L760 の箇条書き) の "Then exclude `$NUMBER` ... take at most the first `OBSERVATION_DISPATCH_THRESHOLD` ..." 以降を、`FILTERED_MATCHES` を得たうえで `printf '%s\n' "$FILTERED_MATCHES" | "${CLAUDE_PLUGIN_ROOT}/scripts/rotate-observation-dispatch.sh" --threshold "$OBSERVATION_DISPATCH_THRESHOLD"` を実行して `DISPATCH_SET` を得る記述に置き換える。スクリプトが `.tmp/observation-dispatch-cursor` に永続化したカーソルを基準に `FILTERED_MATCHES` を回転させてから cap を適用するため、各 dispatch サイクルは前回の続きから始まり、固定された Issue の部分集合が毎回のスロットを恒久占有しなくなる旨を明記する。`DISPATCH_SET` の各番号に対し `Skill(skill="wholework:verify", args="$N --session-id=<literal SESSION_ID value from step 1>")` を順次 dispatch する。"Observation dispatch capped at ..." の出力メッセージは K = `FILTERED_MATCHES` 件数 − `DISPATCH_SET` 件数、M = `FILTERED_MATCHES` 件数に基づいて出力する条件文へ更新する。
   - batch route (`**Event-based observation scan (batch, best-effort):**` 配下、現 L1299 の箇条書き) も同様に、`$NUMBER` ではなく `BATCH_LIST` 除外である点以外は single-issue route と同一の置き換えを行う。
   - 既存の Resume mode (`BATCH_LIST`/`REMAINING` 再利用) には手を入れない (スコープ外、#952 retrospective と同じ扱い)。

4. `modules/observation-trigger.md` を編集する (after 3) (→ AC1)。`## scripts/observation-trigger.sh` § "**Who invokes `/verify`**" § "**`/auto` dispatch cap (#952)**" サブ箇条書き内の "`observation-trigger.sh`'s stdout is already ascending-sorted by Issue number (`sort -un`), so the cap naturally prioritizes the longest-waiting Issue first." の一文を、`scripts/rotate-observation-dispatch.sh` によるカーソルベースのラウンドロビン回転 (`.tmp/observation-dispatch-cursor` に最後に dispatch した Issue 番号を永続化し、次回はその続きから候補を回転させる) の説明に更新する。同箇条書き内の他の記述 (全 matched Issue への通知コメント投稿は cap に関係なく行われる、deferred Issue は次回 `auto-run` イベントで再マッチする) はそのまま維持する。

5. `docs/structure.md` および対訳ミラー `docs/ja/structure.md` を編集する (after 1) (→ `docs/structure.md` 自身の Maintenance rule 準拠、実装フェーズで追加判明)。`scripts/rotate-observation-dispatch.sh` の新規追加により `scripts/`/`tests/` のファイル数コメントを更新 (89→90 files / 125→126 files) し、Key Files > Scripts の一覧に新規スクリプトの説明行を追記する。

## Verification

### Pre-merge
- <!-- verify: rubric "the observation-dispatch selection logic described in skills/auto/SKILL.md and/or scripts/observation-trigger.sh no longer always selects the same handful of Issues indefinitely when their premise has not changed across multiple prior dispatches, and the exclusion/rotation mechanism is documented in skills/auto/SKILL.md" --> observation-dispatch の選出ロジックに、premise 不変の chronically-stalled Issue を dispatch スロットから恒久的に占有させない仕組みが導入され、`skills/auto/SKILL.md` に明記されている

### Post-merge
- 次回 `/auto --batch` 実行時に、#478/#562/#589/#590/#724 以外の observation-pending Issue が dispatch 対象に含まれることを確認 <!-- verify-type: opportunistic -->

## Notes

### 採用アプローチの判断根拠

Issue 本文は3つの想定アプローチ (N 回連続 SKIPPED/UNCERTAIN での一時除外 / oldest-first からラウンドロビンへの変更 / 構造的に評価不能な条件の除外) を列挙し、具体的な選定は `/spec` の責務としている (Issue #1406 の Issue Retrospective コメントでも同様の整理がされている)。本 Spec ではラウンドロビン方式を採用した。

- 「premise 不変」を判定する一時除外方式は、`/verify` 側の SKIPPED/UNCERTAIN 結果を Issue ごとに履歴集計する新規の状態追跡機構が必要であり、Size M の実装コストを超える。
- ラウンドロビン方式は「最後に dispatch した Issue 番号」という整数 1 個のカーソルのみを追跡すればよく、Issue #1406 が報告する症状 (同じ 5 件が無期限にスロットを専有し新しい Issue が一度も dispatch されない) を構造的に解消するのに必要十分である。chronically-stalled な Issue 自体は将来的な dispatch から完全に除外されるわけではなく、公平な巡回の中で定期的に順番が回ってくる (無害かつ意図通り — 「一度も dispatch されない Issue が生まれる」状態を防ぐことが目的であり、「特定 Issue を binary に締め出す」ことは目的ではない)。
- Pre-merge の rubric AC の文言 ("exclusion/rotation mechanism") はラウンドロビン (rotation) の採用を明示的に許容している。

### カーソルの永続化スコープと同時実行に関する既知の制約

`.tmp/observation-dispatch-cursor` は BATCH_ID やセッションに紐付けない単一のグローバルな状態とする (single-issue route と batch route の両方が同じ回転列に参加することで、公平性の効果がルート間でも成立するため)。`.tmp/` はローカル環境で `git` 管理対象外だが `auto-events.jsonl` 同様にセッションをまたいで永続する前提のディレクトリであり、本用途もこれに準じる。読み取り/書き込みはロックを取らないベストエフォートであり、複数 `/auto` セッションが真に同時にカーソルを更新した場合は一方の更新が失われ得るが、本機能は正当性が壊れるものではなく公平性の質が低下するだけであるため、`filter-session-verified-issues.sh` 等と同じ fail-open の設計方針を踏襲し、ロック機構は導入しない (Size M スコープ外)。

### 新規分岐ロジックに対する新規テストケース要件

`scripts/rotate-observation-dispatch.sh` はカーソルに基づく回転・wrap-around・カーソル永続化・書き込み失敗時の fail-open という新規分岐ロジックを持つため、既存スイートが PASS することに加えて `tests/rotate-observation-dispatch.bats` に新規テストケース (初回実行 / カーソル中間値 / wrap-around / カーソル書き込み失敗 / 空 stdin の 5 ケース、Implementation Steps 2 参照) を追加したうえでスイートが PASS することを要件とする (SPEC_DEPTH=light のため `## spec retrospective` を省略し、本節に要約を記録)。

### `docs/guide/customization.md` は変更不要

`observation-dispatch-threshold` の Available Keys 行は cap の件数上限のみを説明しており選出順序には言及していないため、本 Issue の変更 (選出順序の変更) では更新不要と判断した (grep で確認済み)。

## Code Retrospective

### Deviations from Design

- Spec の `## Changed Files` には含まれていないが、`docs/structure.md` の Maintenance rule (「`modules/`/`scripts/` 配下にファイルを追加/削除/リネームした場合は同じ変更でこのセクションの表・リストを更新すること」) に従い、`docs/structure.md`（`scripts/`/`tests/` ファイル数コメント更新 + Key Files 一覧への `rotate-observation-dispatch.sh` 追記）と、その `docs/ja/` 対訳ミラー (`docs/translation-workflow.md` の同期義務) を追加で更新した。Spec の Notes には記載がなかったが、既存の SSoT ドキュメントメンテナンスルールの直接適用であり、設計判断の変更ではない。

### Design Gaps/Ambiguities

- N/A — Spec の Implementation Steps は具体的で、実装は手順どおりに進んだ。

### Rework

- N/A — 新規テストは実装前に FAIL することを確認済みで、実装後は初回実行で全件 PASS した。手戻りは発生していない。

### Notes

- `scripts/check-forbidden-expressions.sh` の非推奨用語チェックが `skills/auto/SKILL.md` の追記文言中の大文字始まりの "Dispatch"（文頭語としての通常語）に誤反応した。これは `/auto` の旧称という固有名詞としての用語 (docs/product.md § Terms 参照) との文字列一致によるもので、文を「Then dispatch ...」と書き換えて回避した。今後同様の追記をする際、文頭に大文字の "Dispatch" を置く言い回しは避けるとよい。

## Consumed Comments

| login | authorAssociation | trust tier | 意図 | URL |
|-------|-------------------|-----------|------|-----|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective。Pre-merge AC1 の常時 PASS パターン (grep ベース AC) を rubric AC へ統合したことの記録。新規の曖昧点なし、`/spec` へ委任した実装方式選定の方針を確認 | https://github.com/saitoco/wholework/issues/1406#issuecomment-5359151015 |

## review retrospective

### Spec vs. implementation divergence patterns

- N/A — 実装は Spec の Implementation Steps 1〜4 と完全に一致していた。Spec に含まれていなかった `docs/structure.md`/`docs/ja/structure.md` の追加変更 (Implementation Step 5) も、実装フェーズで Spec に事後追記済みで、Code Retrospective に記録された正当な Maintenance rule 適用であり、構造的な乖離ではなかった。

### Recurring issues

- 新規スクリプト `scripts/rotate-observation-dispatch.sh` の Parser/Validator Edge Case Pre-check (外部入力を正規表現で検証・正規化するスクリプトが該当) が発火し、実際にスクリプトを実行する専用エージェントと `review-light` エージェントの両方が、それぞれ独立に類似のパターン (境界値/異常な引数を渡した際、意図した単一のエラーメッセージ経路を通らず生の shell/coreutils 内部エラーが stderr に漏れる) を検出した。1件は `--threshold` に極端に大きい値を渡した場合 (bash の符号付き64bit整数比較の限界)、もう1件は `--cursor-file` に既存ディレクトリを渡した場合 (リダイレクト自体のシェルレベル失敗が `2>/dev/null` で抑制されない) で、いずれも「fail-open/hard-error の契約は守られているが、契約が約束する『単一のメッセージ』という粒度では守られていない」という共通パターンだった。両方とも Step 12 で修正済み (`^[0-9]{1,15}$` による桁数上限、`if` 条件全体を `{ ... } 2>/dev/null` でラップ)。今後、外部入力を検証する新規スクリプトを書く際は、値の型 (正規表現) だけでなく実行時の数値範囲・パス種別 (ディレクトリ vs ファイル) も含めて、意図したエラーメッセージ経路から外れないかを実行して確認するとよい。

### Acceptance criteria verification difficulty

- N/A — Pre-merge AC は rubric 1件のみで、Issue 本文と git diff から明確に判定可能だった。UNCERTAIN や verify command の不備は発生しなかった。`tests/rotate-observation-dispatch.bats` の 8ケース PASS が客観的な補強証跡として機能した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- mergeable=true (clean) だったためコンフリクト解消は不要。pre-merge AC ゲートは unchecked_count=0、review_incomplete_fallback なしで通過し、そのままスカッシュマージを実行した。
- Base branch は `main` のため `closes #1406` により Issue は自動クローズされる想定。

### Deferred Items
- Post-merge AC (`/auto --batch` で #478/#562/#589/#590/#724 以外の Issue が dispatch されることの確認) は opportunistic 検証のまま、後続の運用サイクルに委ねる。

### Notes for Next Phase
- `/verify` は post-merge AC (opportunistic) の確認を担う。次回 `/auto --batch` 実行時の dispatch 対象を確認すること。
- pre-merge AC (rubric) はチェック済み。post-merge AC は未チェックのまま (意図通り)。
