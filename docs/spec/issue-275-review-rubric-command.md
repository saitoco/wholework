# Issue #275: review: rubric による意味レベルのレビュー観点 opt-in を導入

## Overview

`/verify` の `<!-- verify: rubric "text" -->` marker を `/review` からも grader 実行できるようにする。既存の `/review` Step 8(Static Acceptance Criteria Verification)が `modules/verify-executor.md` を safe モードで呼び出しているが、現状の verify-executor は `rubric` コマンドを safe モードで UNCERTAIN に落とすため grader が呼ばれていない。

この挙動は #276 で導入された Permission 宣言との不整合(`rubric` は `always_allow` = 副作用なしで自動実行可)であり、`rubric` の safe モード扱いを「grader 実行」に変更することで、`/review` でも pre-merge 時点で AC の意味判定を働かせる。

新 marker namespace(`review:` 等)、新セクション(`## Review Criteria`)、新モジュール(`review-rubric-phase.md`)はいずれも導入しない。設計の全体は既存の "Rubric Command Semantics" セクションと `verify: rubric` marker にそのまま乗る。

## Changed Files

- `modules/verify-executor.md`: (a) 翻訳テーブルの `rubric` 行を `**Mode-dependent**: safe/full 共に grader を呼ぶ(always_allow, no side effects)` に変更、(b) "Rubric Command Semantics" の "Safe mode behavior" 節を書き換え — 旧 "returns UNCERTAIN in safe mode" を削除し、`always_allow` Permission 宣言との整合、および safe モードでも grader を呼ぶ理由(副作用なし・Managed Agents `permission_policy: always_allow` portability)を記述
- `modules/verify-patterns.md`: §9(`rubric` 使い所ガイド)に `/review` pre-merge でも grader が走る旨を追記。`verify: rubric` を AC に書くと pre-merge(`/review`)と post-merge(`/verify`)の両時点で意味判定される運用メリットを説明
- `tests/review-rubric-safe.bats`: 新規作成。(i) `modules/verify-executor.md` の `rubric` 翻訳テーブル行が safe モードでも grader 実行する旨を記述していること、(ii) "Safe mode behavior" 節が `always_allow` への言及を含み、旧 "returns UNCERTAIN" を含まないこと、(iii) `modules/verify-patterns.md` に `/review` pre-merge 言及が含まれることを shallow に検証 — bash 3.2+ 互換(grep / awk のみ使用、LLM 応答自体の assertion はしない)

## Implementation Steps

1. `modules/verify-executor.md` の `rubric` 翻訳テーブル行(現 L82)を書き換える。旧: `**Mode-dependent**: safe → return UNCERTAIN. full → invoke grader ...`。新: `**Mode-dependent**: safe/full 共に grader を呼ぶ(always_allow Permission 宣言により副作用なし)。grader は adversarial system prompt で ...(以下既存)` — Mode 境界で挙動が変わらない旨を明示 (→ AC 1)

2. `modules/verify-executor.md` の "Rubric Command Semantics" の "Safe mode behavior" 節(現 L103-104)を書き換える。旧: `rubric returns UNCERTAIN in safe mode. Semantic grading requires full access to git diff and may trigger tool use; this is reserved for full mode.`。新: safe / full 共に grader を呼ぶこと、`always_allow` Permission 宣言(#276)が safe モードでの自動実行許可を意味すること、`/review` Step 8 経由(safe モード)でも rubric が走ることで pre-merge 意味判定が可能になる旨を 3〜5 文で記述 (→ AC 2, 3)

3. `modules/verify-patterns.md` §9(`rubric` 使い所ガイド)の末尾に `/review` pre-merge 時点でも grader が走ることを追記(2〜3 文)。AC に書いた `verify: rubric` は `/verify` post-merge で checkbox 更新と意味判定、`/review` pre-merge で grader 結果コメント表示、という 2 フェーズ運用を説明 (→ AC 4)

4. `tests/review-rubric-safe.bats` を新規作成。bats テストで以下を shallow に検証: (i) `modules/verify-executor.md` に `rubric` と safe/full 併記 + `always_allow` の整合記述が存在、(ii) "Safe mode behavior" 節に `returns UNCERTAIN in safe mode` が存在**しない**、(iii) `modules/verify-patterns.md` に `/review` pre-merge 言及がある。bash 3.2+ 互換(grep / awk のみ、mapfile 等 bash 4+ 機能は避ける)。LLM 応答そのものは mock せず assertion しない (→ AC 5, 6)

## Verification

### Pre-merge
- <!-- verify: file_not_contains "modules/verify-executor.md" "safe` → return UNCERTAIN. `full` → invoke grader" --> `modules/verify-executor.md` の `rubric` 翻訳テーブル行から「safe → UNCERTAIN」の記述が削除されている
- <!-- verify: section_not_contains "modules/verify-executor.md" "Rubric Command Semantics" "returns UNCERTAIN in safe mode" --> "Safe mode behavior" 節から "returns UNCERTAIN in safe mode" の記述が削除または更新されている
- <!-- verify: section_contains "modules/verify-executor.md" "Rubric Command Semantics" "always_allow" --> "Safe mode behavior" 節に `always_allow` 宣言との整合が記述されている
- <!-- verify: file_contains "modules/verify-patterns.md" "/review" --> `modules/verify-patterns.md` rubric 使い所ガイドに `/review` pre-merge 言及が追記されている
- <!-- verify: command "find tests -name '*rubric*safe*.bats' -o -name '*review-rubric*.bats' -type f | grep -q ." --> safe モード経路の rubric dispatch を検証する bats テストが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 追加されたテストを含む全 bats テストが CI で PASS する
- <!-- verify: rubric "変更が既存 AC 構造・marker syntax(`## Acceptance Criteria`, `<!-- verify: ... -->`)・他 verify command の safe/full 挙動を一切壊していない(rubric 以外の command は挙動変化なし)" --> 既存 AC 構造・他 verify command への影響ゼロ

### Post-merge
- 実 PR で AC に `<!-- verify: rubric "text" -->` を含めると、`/review` のコメントに grader 結果(PASS/FAIL/UNCERTAIN + gap)が表示されることを確認(verify-type: opportunistic)

## Notes

- **元案(2026-04-20)からの転換**: 当初は `## Review Criteria` 新設 + `<!-- review: rubric "text" -->` 新 namespace + `review-rubric-phase.md` 新 module を提案していたが、(a) `/review` Step 8 が既に verify-executor を safe モードで呼び出し AC 検証済みである事実、(b) #276 で `rubric` が `always_allow` 宣言済みである事実、から「既存経路の挙動修正のみで目的達成可能」と判断した。新概念・新 namespace・新 module はいずれもゼロ
- **Permission 層との整合修復**: `rubric` の Permission `always_allow` と Mode safe → UNCERTAIN の挙動は元々矛盾しており(他 `always_allow` コマンドは safe モードで実行される)、本変更はその不整合の修復。副次的に verify-executor 自体の健全化にも寄与
- **grader 入力範囲**: safe モードでも grader 入力範囲(Issue body + git diff + 言及ファイル、Spec 除外)は full モードと同じ。`/review` 実行時の git diff は PR diff を指す。この解釈は既存の Rubric Command Semantics の記述そのままで、本 Issue で追加記述は不要
- **既存 AC 互換性**: `verify: rubric` を持たない AC、および他 verify command(`file_exists`, `command`, `build_success` 等)の safe/full 挙動はいずれも変更なし
- **bats テストの粒度**: 既存 `tests/verify-rubric.bats`(#271)と同じ方針で shallow test に留める。文書存在・必要文言・削除された古い文言の 3 点検証のみで、LLM 応答自体の assertion は行わない
- **Managed Agents portability 維持**: 単一 namespace(`verify:`)で `always_allow` portability 契約を保持。将来 `/review` phase を Managed Agents Outcome に移植する際も `rubric` は 1:1 マップ可能

## Code Retrospective

### Deviations from Design

- `tests/verify-rubric.bats` の既存テスト "safe mode returns UNCERTAIN for rubric" を更新した。Spec には明記されていなかったが、変更後の `modules/verify-executor.md` には "returns UNCERTAIN in safe mode" の文言が存在しなくなるため stale assertion となり、テストが失敗する。Spec Step 4 の shallow test 方針に従い同ファイルを更新した

### Design Gaps/Ambiguities

- `awk '/Rubric Command Semantics/,/^### /'` の range pattern は、start 行と end 行が同じパターン (`^### `) にマッチする場合に macOS BSD awk で単一行しか出力しないことが判明。`{f=1; next}` を使い start 行をスキップする形に修正した (tests/review-rubric-safe.bats)

### Rework

- `tests/review-rubric-safe.bats` の test #2 ("Rubric Command Semantics section mentions always_allow for safe mode") で awk range が機能せず FAIL。awk パターンを修正して再実行し PASS を確認

## review retrospective

### Spec vs. 実装の乖離パターン

変更が非常に局所的（rubric 1行 + Rubric Command Semantics 節 + verify-patterns.md §9 + bats テスト）だったため、Spec との乖離は発生しなかった。唯一の修正は Return values リストの "safe mode" 記述（Spec 未言及の残存テキスト）であり、Spec に書くべきだったが書かれていなかったケース。

### 繰り返し指摘パターン

同種の指摘なし（変更規模が小さいため）。ただし、secion 内 Return values のような「変更対象セクション外の関連記述」を Spec でカバーしていない点は今後も発生しうる。

### 受入条件検証の困難さ

全 AC が静的検証可能（file_not_contains / section_contains 等）で UNCERTAIN は 0 件。rubric AC も grader が PASS を返した。verify command の品質が高く、検証負荷が低かった。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue の AC は全て静的検証可能な verify command を持ち、UNCERTAIN ゼロ。rubric AC も明確に定義されており、grader が迷いなく PASS を返した
- 元案(新 namespace + 新モジュール)から既存経路の修正のみへのピボットは適切だった。変更規模が最小化され、verify での FAIL リスクも低かった

#### design
- Spec の Implementation Steps は実装と 1:1 に対応。唯一の gap は `tests/verify-rubric.bats` の既存テスト更新（Code Retrospective 記載）で、Spec は明示していなかったが stale assertion の修正は Spec の意図に沿っている
- "Return values" リストの残存 "safe mode" 記述は Spec の変更スコープに含まれていなかったが、Code フェーズで発見・修正済み

#### code
- `tests/review-rubric-safe.bats` の test #2 (awk range pattern) で macOS BSD awk の挙動差による FAIL が発生し、`{f=1; next}` で修正。awk のポータビリティ考慮が Spec に記載されていれば rework を避けられた
- `tests/verify-rubric.bats` の stale assertion 更新は小規模で問題なし

#### review
- PR #280 のレビューで全 AC が静的検証可能と確認。awk range pattern の問題は review 時点では未検出(ローカル実行で発見)
- 変更規模が局所的（5ファイル、64行変更）のため review 負荷が低く、漏れなし

#### merge
- FF-only マージで競合なし。Spec コミット 2回（design追加・rewrite）の後、PR #280 がスクワッシュマージされた。クリーンなマージ経路

#### verify
- 7条件すべて PASS。CI も "Run bats tests" PASS。verify command の品質が高く 1回のパスで完了
- Post-merge opportunistic 条件（実 PR での grader 結果表示確認）は手動確認待ち

### Improvement Proposals
- N/A
