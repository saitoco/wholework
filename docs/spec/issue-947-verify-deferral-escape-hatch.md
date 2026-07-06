# Issue #947: verify: documented deferral の auto-retry escape hatch を追加

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / intent: `/issue` 実行時の Issue Retrospective。曖昧点 (実装アプローチ (a)/(b) の択一) を自動解決した根拠、AC3 verify command の修正理由 (`"deferral"` → `"deferral=true"`)、Size/Value 判定根拠を記録している。内容は Issue 本文に既に反映済みで、本 Spec の設計に影響する新規情報はない / URL: https://github.com/saitoco/wholework/issues/947#issuecomment-4888188067

## Overview

Issue #939 の `/verify` 実行時、Pre-merge AC のうち rubric 2件が FAIL となったが、この FAIL は Spec の `## Code Retrospective` (`### Deviations from Design`)、`## review retrospective`、`## Phase Handoff` の全てで「実測データ収集にユーザーの明示的な `--fable` 実行認可が必要」という意図的 deferral として文書化されていた (`docs/spec/issue-939-fable-5-spec-watchdog-recalib.md` 参照。実際に merge フェーズが書いた Phase Handoff の `### Deferred Items`/`### Notes for Next Phase` が、この deferral 内容を `/verify` まで正しく引き継いでいたことを確認済み)。

しかし `skills/verify/SKILL.md` Step 11(b) の Tier-gated auto-retry check は `AUTONOMY_TIER` + `AUTO_RETRY_ENABLED` + `NEXT_ITERATION` のみで発火条件を判定しており、FAIL の性質 (実装バグ vs 意図的 deferral) を区別しない。documented deferral の場合、`/code` を再実行しても同じ deferral 判断に到達する可能性が高く、iteration count が `AUTO_RETRY_MAX_ITERATIONS` (デフォルト 3) に達するまで無駄な `/code` + `/verify` cycle を消費する構造になっている。Issue #939 では AskUserQuestion による手動確認で auto-retry を skip したが、これは L3 autonomy が意図する無停止実行という設計方針と乖離する。

本 Issue では `/verify` に documented deferral の escape hatch を追加する。検出は次の2条件の OR とする:

1. この Issue の既存 FAIL marker comment (`<!-- wholework-event: type=verify-fail ... -->`。Consumed Comments に既に含まれている — `modules/l0-surfaces.md` の verify-fail marker exception により cutoff に関わらず収集される) が既に `deferral=true` を持つ場合 (marker 検出)
2. Spec の `## Code Retrospective` (`### Deviations from Design`)、`## review retrospective`、または Phase Handoff の `### Deferred Items` (`/verify` は Step 4 の Spec 読み込み後に既に読み込み済み) が、今回 FAIL した条件を意図的な deferral として文書化している場合 (同一実行内での新規判定)

検出時は、投稿する FAIL marker comment に `deferral=true reason="..."` 属性を追加したうえで、Tier-gated auto-retry check ではこの検出結果を最優先条件として扱い、auto-retry を無条件にスキップする。新規の marker 系統は導入せず (Issue 本文で不採用と判断された案 (b) の通り)、`modules/l0-surfaces.md` が確立した `wholework-event:` namespace という単一 SSoT を維持する。

## Changed Files

- `skills/verify/SKILL.md`: Step 11(b) (FAIL 分岐) に documented deferral detection を追加し、FAIL marker comment テンプレート (2箇所) と Tier-gated auto-retry check に escape hatch を組み込む
- `modules/l0-surfaces.md`: 「Machine-Readable Event Marker」節に `type=verify-fail` marker の任意属性 `deferral` / `reason` を追記する (Issue 本文が明示する SSoT)
- `docs/tech.md`: [Steering Docs sync candidate] 120行目付近の「code-side auto-retry (silent no-op)」記述 (Step 11(b) の tier gate 説明を含む) が escape hatch 追加後も正確か確認し、必要なら更新する。採否は `/code` フェーズの最終判断とする。更新する場合は `docs/ja/tech.md` の追随翻訳も対象に含める (`docs/translation-workflow.md` 準拠)

## Implementation Steps

1. `skills/verify/SKILL.md` Step 11(b) の「Check iteration counter:」ブロック (`CURRENT_ITERATION`/`NEXT_ITERATION` 算出) の直後、`NEXT_ITERATION < VERIFY_MAX_ITERATIONS` の分岐に入る前に「Documented deferral detection」サブステップを追加する。`DEFERRAL_DETECTED` (true/false) と、true の場合は一行の `DEFERRAL_REASON` (ダブルクォートを含まないよう sanitize 済み) を算出する。`DEFERRAL_DETECTED=true` となる条件は次の OR:
   - この Issue の既存 FAIL marker comment (Consumed Comments に含まれる `<!-- wholework-event: type=verify-fail ... -->`) が既に `deferral=true` を持つ
   - Spec の `## Code Retrospective` (`### Deviations from Design`)、`## review retrospective`、または Phase Handoff の `### Deferred Items` が今回 FAIL した条件を意図的な deferral として文書化している
   (→ 受け入れ基準1・3)
2. (1の後) Step 11(b) 内の FAIL marker comment テンプレート2箇所 (`NEXT_ITERATION < VERIFY_MAX_ITERATIONS` 分岐、`NEXT_ITERATION >= VERIFY_MAX_ITERATIONS` 分岐) を拡張し、`DEFERRAL_DETECTED=true` の場合に `<!-- wholework-event: type=verify-fail phase=verify issue=$NUMBER iteration=$NEXT_ITERATION -->` 行末へ ` deferral=true reason="${DEFERRAL_REASON}"` を条件付きで付与する。`DEFERRAL_DETECTED=false` の場合は現行の marker 形式のまま変更しない。(→ 受け入れ基準3)
3. (1の後) Step 11(b) の「Tier-gated auto-retry check」節で、既存の `AUTONOMY_TIER`/`AUTO_RETRY_ENABLED`/`NEXT_ITERATION` 判定より前に評価する新条件を追加する: `DEFERRAL_DETECTED=true` の場合、tier・config・iteration count に関わらず auto-retry を無条件でスキップし、検出理由 (`DEFERRAL_REASON`) を含む advisory メッセージを出力し、`run-code.sh` を呼び出さない。(→ 受け入れ基準1)
4. (1〜3と並行) `modules/l0-surfaces.md` の「Machine-Readable Event Marker」節に、`type=verify-fail` marker が任意で `deferral=true reason=<text>` 属性を持ちうることを追記する。(→ 受け入れ基準2)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md の tier-gated auto-retry check セクションに documented deferral の escape hatch (marker 検出 → auto-retry skip) が実装されている" --> `/verify` SKILL に documented deferral escape hatch が実装されている
- <!-- verify: rubric "docs/spec/... または関連 modules に、implementation approach (a)/(b) のどちらを採用したか、両方採用したか、および他方を採用しなかった場合の判断根拠が記録されている" --> 採用したアプローチと判断根拠が記録されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "deferral=true" --> SKILL.md に `deferral=true` marker 属性の参照が存在する

### Post-merge

- 次回 documented deferral を含む Issue の `/verify` 実行時に、auto-retry が自動 skip されることを観察 <!-- verify-type: opportunistic -->

## Notes

- **採用したアプローチと不採用理由 (受け入れ基準2対応)**: Issue 本文の通り (a) 「既存 FAIL marker comment (`wholework-event: type=verify-fail`) への `deferral=true reason=...` 属性追加」を採用する。(b) 「Spec の Verification section に `<!-- known-deferral: reason=... -->` を導入する案」は、Issue/PR コメントと Spec ファイルという2つの独立した marker 系統を並存させ、`modules/l0-surfaces.md` が確立した単一 SSoT (`wholework-event:` namespace) の設計原則から外れるため不採用とした。(a)+(b) 併用案も同じ理由で不採用。
- **検出ロジックを「既存 marker 検出」と「同一実行内の新規判定」の OR とした理由**: Issue #939 の実際の precedent (`docs/spec/issue-939-fable-5-spec-watchdog-recalib.md` の Verify Retrospective) では、tier-gated auto-retry は **1回目の FAIL (iteration 1)** で即座に発火可能な状態だった。「前回の FAIL marker に `deferral=true` が付与済みかどうか」だけを検出条件にすると、1回目の FAIL では必ず auto-retry が発火してしまい (marker がまだ存在しないため)、Issue が解決したい「無駄な1サイクル」を防げない。そのため、Spec の Code/review retrospective や Phase Handoff の `### Deferred Items` を同一実行内で読み、documented deferral かどうかを新規に判定する経路を主経路とし、「既存 marker 検出」は2回目以降の防御的フォールバック (defense in depth) として位置づけた。
- **Phase Handoff 経由での情報伝播の実証確認**: Phase Handoff は「最新1フェーズのみ保持」するローテーション方式 (`modules/phase-handoff.md`) のため、`/verify` が実際に読むのは (review ではなく) merge フェーズが書いた Phase Handoff である。`docs/spec/issue-939-fable-5-spec-watchdog-recalib.md` の実例を確認したところ、merge フェーズは review の `### Deferred Items` の内容を正しく引き継いでおり、さらに `### Notes for Next Phase` に「`/verify` は N件が unchecked のままであることを踏まえて判定すること」という明示的な申し送りまで記録していた。この既存の申し送り習慣に検出ロジックが乗る設計であり、`/code`/`/review`/`/merge` 側の変更は不要と判断した。
- **既存 marker consumer への影響確認 (追加のみで安全)**: `deferral=true reason="..."` 属性は `<!-- wholework-event: type=verify-fail ... -->` 行の末尾に条件付きで追加するのみで、既存フォーマット (`type=verify-fail phase=verify issue=N`) 自体は変更しない。既存の consumer (`scripts/append-consumed-comments-section.sh`、`skills/auto/SKILL.md` の fix-cycle 判定、`modules/l0-surfaces.md` の verify-fail marker exception) はいずれも `contains("<!-- wholework-event: type=verify-fail")` という前方一致の部分文字列検索であり、末尾属性の追加による影響はない。`tests/auto.bats`・`tests/run-verify.bats` も同じ部分文字列のみを検証しており、更新不要と確認した。
- **AC3 の verify command が有効な検証になっていることの確認**: 実装前時点の `skills/verify/SKILL.md` には裸の `"deferral"` (305行目 `cannot-auto-verify deferral`、無関係な既存文言) は存在するが、`"deferral=true"` という文字列は存在しない (grep で確認済み)。Triage の AC audit 指摘 (裸の `"deferral"` は常時 PASS) を受けて Issue 本文側で既に `"deferral=true"` に修正済みであり、本実装の追加により初めて PASS に切り替わる有効な検証になっている。
- **Post-merge AC の `verify-type: opportunistic` 分類について**: 本 AC は文面上「次回 `/verify` 実行時の観察」であり `modules/verify-classifier.md` の `observation` (イベント駆動) にも近いが、同モジュールの Event Values テーブルには「documented deferral を検出した」に対応する専用イベントが存在せず、新設は本 Issue (Size S) のスコープ外と判断した。Issue 本文の Acceptance Criteria 文言・タグ変更は `/issue` フェーズの責務であり (`docs/product.md` § `/issue` (What) vs `/spec` (How) Responsibility Boundary)、`/spec` 側での変更は行わない。
- **`skills/code/SKILL.md` 側の別課題との切り分け**: `docs/spec/issue-939-fable-5-spec-watchdog-recalib.md` の review retrospective は、「`/code` が Spec の事前判断を覆す際に Verification section へのインライン注記が漏れる」構造的な課題を別途指摘しているが、これは Spec ファイル側の記法の話であり、本 Issue (`/verify` の auto-retry 判定ロジック) とは独立した別課題のため本 Spec のスコープに含めない。
- **Steering Docs sync candidate の絞り込み根拠**: `skills/verify/SKILL.md` のファイル名由来キーワード `verify` で `docs/*.md`/`docs/ja/*.md` を機械的に grep すると18ファイルがヒットするが、いずれも "verify" という汎用語への一致でノイズが大きい。代わりに変更対象の実体 (`auto-retry-on-fail`/`tier-gated`/`verify-fail`) で絞り込み、Step 11(b) の tier gate 説明を含む `docs/tech.md` のみを sync candidate とした。
- **Auto-Resolve Log (非対話モード)**: `DEFERRAL_DETECTED` の具体的な判定アルゴリズム (marker 検出との OR 構成、検出主体を `/verify` 自身の LLM 判断とする点) は Issue 本文に明記がなく、本 Spec 作成時に自動解決した。根拠は上記「検出ロジックを...OR とした理由」の通り。`skills/verify/SKILL.md` は LLM が逐次実行する prose であり、既存の rubric AC 判定や「cannot-auto-verify deferral」フォールバック (Step 11 内、305行目近傍) も同様に LLM 判断に委ねられているため、本判定を厳密なキーワードリストではなく LLM 判断として設計することは既存パターンと整合する。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜4 を計画通りの順序で実装した。

### Design Gaps/Ambiguities
- **`docs/tech.md` sync 採否 (Changed Files で `/code` フェーズの最終判断とされていた点)**: 120行目付近の「code-side auto-retry (silent no-op)」記述は `run-code.sh` 側の別の auto-retry ロジックを説明しているが、「verify-side auto-retry と対称的 (同じ tier ゲート)」という一文があり、本 Issue で verify 側に tier ゲートより優先される escape hatch を追加したことで、この対称性の記述が不正確になる (tier ゲートの手前に非対称な分岐が増えた)。実装を選択し、対称性の例外として escape hatch の存在を追記した (`docs/tech.md` / `docs/ja/tech.md` 両方)。
- **Phase Handoff だけでは検出に不十分な点の明示**: Spec Notes は「既存の申し送り習慣に検出ロジックが乗る設計」と記していたが、`modules/phase-handoff.md` のローテーション方式 (最新1フェーズのみ保持) を踏まえると、Step 4 で読む Phase Handoff だけでは `## Code Retrospective` (code フェーズ由来) の内容が確実に含まれる保証がない。そのため実装では「同一実行内の新規判定」の情報源として Phase Handoff に加え、Spec ファイルの `## Code Retrospective`/`## Review Retrospective` セクションを直接読む経路も明記した。

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Documented deferral detection を Step 11(b) の「Check iteration counter:」直後、`NEXT_ITERATION < VERIFY_MAX_ITERATIONS` 分岐の手前に追加し、`DEFERRAL_DETECTED`/`DEFERRAL_REASON` を算出したうえで Tier-gated auto-retry check の先頭でこれを最優先判定として扱う構成にした (Spec Implementation Steps 1〜3 の通り)。
- 検出は「既存 FAIL marker (`deferral=true`) 検出」と「同一実行内の Spec Code/Review Retrospective・Phase Handoff Deferred Items からの新規判定」の OR とし、後者を主経路、前者を2回目以降の defense-in-depth とした (Spec Notes に根拠記載済み)。
- `modules/l0-surfaces.md` に新規 marker 系統を追加せず、既存 `wholework-event: type=verify-fail` の末尾属性追加のみで完結させた (SSoT 単一化)。

### Deferred Items
- `docs/tech.md`/`docs/ja/tech.md` の「code-side auto-retry (silent no-op)」記述に、verify 側 escape hatch との非対称性を注記として追加したが、`run-code.sh` 自体のロジック変更は本 Issue のスコープ外のため行っていない。
- Post-merge AC (「次回 `/verify` 実行時に auto-retry が自動 skip されることを観察」) は `verify-type: opportunistic` のまま。専用 observation イベントの新設は Spec Notes の通りスコープ外と判断し、着手していない。

### Notes for Next Phase
- `/verify` はこの Issue 自身に対しては FAIL が発生しない想定 (実装 Issue であり、documented deferral の実例ではない) — pre-merge AC 3件は rubric/file_contains により本 `/code` フェーズ内で PASS 判定済みで、Issue 本文のチェックボックスも更新済み。
- Post-merge の observation AC は次回、実際に documented deferral を含む別 Issue の `/verify` 実行時に自然発火して確認される想定 (opportunistic)。`/verify` が本 Issue を処理する際は、この AC が unchecked のまま `phase/verify` に留まる分岐になる可能性を踏まえて判定すること。
