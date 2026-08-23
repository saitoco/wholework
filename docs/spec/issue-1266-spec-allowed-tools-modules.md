# Issue #1266: spec: allowed-tools impact chain check の発火条件に modules/*.md への新規スクリプト呼び出しを追加

## Overview

`skills/spec/SKILL.md` Step 10 の `#### allowed-tools impact chain check` (#721 で導入) は、Spec の Changed Files に**新規** `scripts/*.sh` が含まれる場合のみ発火し、「既存スクリプトへの新規呼び出しを共有モジュール (`modules/*.md`) に追加する」変更を素通りさせる構造的ギャップを持つ。`modules/*.md` は複数 skill から "Read and follow" される共有面であり、1 モジュールへの 1 スクリプト呼び出し追加が、そのモジュールを読む全 skill の `allowed-tools` 更新を要求する。

2026-08-07 の同一セッションで #1236 (`modules/opportunistic-verify.md` への `scripts/emit-event.sh` 呼び出し追加、2 skill 漏れ) と #1239 (同モジュールへの `scripts/collect-run-facts.sh` 呼び出し追加、5 skill 漏れ) が連続再発し、いずれも `/spec` 段階では検出されず `scripts/validate-skill-syntax.py` のクロスファイル検証が code フェーズで初めて捕捉した。

本 Issue は、`allowed-tools impact chain check` の発火条件を `modules/*.md` の変更にも拡張し、`/spec` 段階で呼び出し元 SKILL.md の `allowed-tools` 漏れを検出できるようにする。

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective — AC3 の検証コマンドを自己一致していた `"skills/*/SKILL.md"` パターンから `"grep -rl"` に修正済み、Post-merge AC に `session=next` を付与済みであることを確認。曖昧性検出・タイトルドリフトともになし。(https://github.com/saitoco/wholework/issues/1266#issuecomment-5226595466)

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1266#issuecomment-5226874897
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5226962959
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5230976160
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5235407854
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5246566187
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5255761367
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5296390601
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5304277450
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5310551828
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5327736889
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5341249464
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5354384247
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5369700393
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5378426723
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1266#issuecomment-5384000406
## Changed Files

- `skills/spec/SKILL.md`: Step 10 の `#### allowed-tools impact chain check` サブ節を拡張 — 発火条件に `modules/*.md` を追加し、"Case 1" (既存の新規スクリプト判定、変更なし) と "Case 2" (module 経由の新規呼び出し判定) に分割、skip 条件を更新 — bash 3.2+ 互換 (対象は Markdown 文書のみで bash コードは含まないため該当なし)

## Implementation Steps

1. `skills/spec/SKILL.md` の `#### allowed-tools impact chain check` サブ節 (現行 572-581 行目) を以下の内容に置き換える (→ AC1, AC2, AC3)
   - 発火条件を「Changed Files に新規 `scripts/*.sh` を含む」**または**「Changed Files に `modules/*.md` を含む」の 2 条件に拡張
   - 既存の 4 ステップ手順を "Case 1 — new `scripts/*.sh` files" として維持 (内容変更なし)
   - "Case 2 — `modules/*.md` changes" を新設: (a) 変更対象モジュールの新規/変更内容が `scripts/*.sh` への参照を含むかを確認する軽量ゲート、(b) 含む場合のみ `grep -rl "modules/<name>\.md" skills/*/SKILL.md` で読者 (呼び出し元 skill) を洗い出す、(c) 各読者の `allowed-tools` frontmatter に対象スクリプトの literal エントリがあるか確認、(d) 漏れがあれば Case 1 と同じ形式で Notes に記録するか Changed Files に追加
   - wildcard 不可の注記は Case 1 の既存 4 ステップを逐語的に維持したまま、Case 2 側のステップに「Case 1 step 4 と同じ wildcard 不可ルールがここにも適用される」という参照文を追加する形で両 Case に共通適用させる (Deviations from Design 参照)
   - skip 条件を「Changed Files に新規 `scripts/*.sh` も `modules/*.md` も含まれない場合のみ skip」に更新
   - 背景注記として #1236 / #1239 の再発事例を1文で残す (既存の "Feature deletion impact chain check" 等と同じ *斜体背景* 引用スタイル)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の allowed-tools impact chain check セクションが、新規 scripts/*.sh の追加だけでなく、modules/*.md に既存スクリプトへの新規呼び出しを追加するケースも検出対象としている" --> `skills/spec/SKILL.md` の `allowed-tools impact chain check` が、`modules/*.md` への新規スクリプト呼び出し追加を発火条件に含めている
- <!-- verify: rubric "skills/spec/SKILL.md の当該 skip 条件が、modules/*.md 経由のケースを誤って skip しない記述になっている" --> 現行の `**Skip** if no new scripts/*.sh files are being added.` が新しい発火条件を反映した記述に更新されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "allowed-tools impact chain check" "grep -rl" --> 呼び出し元 skill の洗い出し手順 (`grep -rl "modules/<name>\.md" skills/*/SKILL.md` 相当) が明記されている
- <!-- verify: rubric "modules/*.md 変更時の発火粒度 (全 module 変更で発火 / 新規スクリプト呼び出しを含む場合のみ発火) についての判断と理由が Spec に記載されている" --> 過剰発火を許容するか抑制するかの判断とその理由が Spec に記録されている

### Post-merge

- 次に `modules/*.md` へ新規スクリプト呼び出しを追加する Issue の `/spec` 実行時、呼び出し元 SKILL.md の `allowed-tools` が Changed Files または Notes に記録されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

**過剰発火の許容/抑制粒度の判断 (AC4):** 外側の発火条件は「Changed Files に `modules/*.md` が 1 件でも含まれる」で機械的に判定する (既存の新規 `scripts/*.sh` 条件と同じ Changed-Files ベースの機械判定スタイル)。一方、コストの高い処理 (`grep -rl` による読者洗い出し + 各読者の `allowed-tools` 確認) は、Case 2 step (a) の軽量ゲート — 「変更対象モジュールの新規/変更内容が `scripts/*.sh` への参照を含むか」という文字列存在チェック — の後段でのみ実行する。

このゲートを意図的に「作者が新規呼び出し追加を意図したか」という意味論的判断にしなかった理由: この check が防ごうとしている #1236 / #1239 はいずれも、まさにその種の意図判断が見落とされたことで発生した再発である。ゲート自体を同種の意味論的判断にすると、見落としリスクを再導入することになる。文字列存在チェックによる過剰発火 (スクリプト呼び出しを追加しないモジュール変更が `scripts/` という語を偶然含む場合など) のコストは `grep -rl` 一発と「漏れなし」の一行メモ程度だが、見逃しのコストは #1236 (2 skill 漏れ) / #1239 (5 skill 漏れ) と同種の code フェーズ手戻りである。非対称性から過剰発火を許容する側を採用した。

**`/code` フェーズの既存セーフティネットとの関係 (#857):** `scripts/check-allowed-tools.sh` (#857 で導入、`skills/code/SKILL.md` Step 8 から呼び出し) は、SKILL.md を変更する中間コミット前に `skills/` 配下全体を `allowed-tools` と突き合わせて再検証する既存の安全網である。この機構は `modules/*.md` 自体を読まないため `/spec` 段階のギャップを代替できないが、本 Issue の Spec 時点チェックが見逃した場合の最終防波堤として引き続き独立に機能する。`check-allowed-tools.sh` / `skills/code/SKILL.md` への変更は本 Issue のスコープ外であり、実施しない。

## Code Retrospective

### Deviations from Design

- Implementation Steps は「wildcard 不可の注記を両 Case 共通の文言に更新する」ことと「既存の 4 ステップ手順を Case 1 として内容変更なしで維持する」ことの両方を求めていた。文字通り両立させるため、Case 1 の 4 ステップは一切変更せず、Case 2 側の該当ステップに「Case 1 step 4 と同じ wildcard 不可ルールがここにも適用される」という参照文を追加する形にした (独立した共通段落へ抽出する案は Case 1 の逐語的な内容不変という制約と衝突するため採らなかった)。

### Design Gaps/Ambiguities

- `/code` 開始時点で Issue のラベルは `phase/ready` ではなく既に `phase/code` だった (`reconcile-phase-state.sh --check-precondition code-patch` は `matches_expected: false` を返した)。Spec (`docs/spec/issue-1266-spec-allowed-tools-modules.md`) 自体は存在していたため、non-interactive mode の既定動作 (warn し続行) に従って実装を進めた。ラベルタイムラインを確認すると `phase/ready` 付与と `phase/code` への遷移が同一タイムスタンプ (2026-08-08T15:04:31Z) で発生しており、原因 (前回セッションでの部分実行か、`/spec` が `phase/ready` を経由せず直接遷移する設計上の挙動か) は未調査。本 Issue のスコープ外として深追いしていない。

### Rework

- N/A

## Autonomous Auto-Resolve Log

- **Step 3 (`phase/ready` ラベル不在の precondition mismatch) — 実装を継続** — 理由: `reconcile-phase-state.sh` の `matches_expected: false` は「Spec 不在」ではなく「ラベルが `phase/ready` を経由せず `phase/code` に進んでいる」ことに起因しており、Spec 自体 (`docs/spec/issue-1266-spec-allowed-tools-modules.md`) は存在し内容も本 Issue の要件と一致していたため、warn して続行する非対話モードの既定動作を採用した。
  - Other candidates: 実装を中断してユーザー確認を待つ (hard-error abort) — 対話不可のためこのセッションでは選択不可

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `allowed-tools impact chain check` を Case 1 (既存の新規 `scripts/*.sh` 判定、内容不変) と Case 2 (`modules/*.md` 変更 + 軽量ゲート + 読者洗い出し) の二本立てにし、Case 1 の逐語的維持と wildcard 注記の共通化を両立させるため、Case 2 側から Case 1 step 4 を参照する形にした。
- AC4 (過剰発火の許容/抑制粒度) は Spec 作成時点の Notes セクションで既に判断・記録済みだったため、SKILL.md 側の追加変更は不要と判断した。

### Deferred Items
- Post-merge AC (`session=next` observation) — 次回 `modules/*.md` へ新規スクリプト呼び出しを追加する Issue の `/spec` 実行時に、本 Case 2 ロジックが実際に発火し、呼び出し元 SKILL.md の allowed-tools 漏れを検出できるかを観察する。

### Notes for Next Phase
- `/review` では、Case 2 の軽量ゲート (文字列存在チェック) が意図的に「意味論的判断ではない」設計になっている点 (Notes 参照) を踏まえてレビューすること — 過剰発火を許容する非対称性のトレードオフが再度指摘されないよう、Spec Notes の記載を確認してほしい。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- `/issue` が Step 7 で AC3 の always-PASS 不備を修正し、`section_contains "skills/spec/SKILL.md" "allowed-tools impact chain check" "grep -rl"` という判別可能な形に置き換えた。修正前は `grep -rl` という文字列の存在だけを見る形で、実装なしでも PASS しうる状態だった。既存の triage コメントによる指摘が `/issue` フェーズで実際に消化された事例
- post-merge AC に `session=next` が追加された点も適切。本 Issue は `skills/spec/SKILL.md` 自体を変更するため、同一会話セッションでは変更後の skill 本文が読み込まれず観察が構造的に不可能

#### spec

- 過剰発火の許容/抑制粒度 (AC4) を Notes で明示的に判断し、「ゲート自体を意味論的判断にすると、本 check が防ごうとしている #1236 / #1239 と同種の見落としリスクを再導入する」という非対称性の論証を残した。判断の根拠が後から追える形になっている
- `#857` の `/code` フェーズ側セーフティネットとの関係を調査し、スコープの独立性を明記した点も妥当

#### code

- Implementation Steps の「wildcard 不可の注記を共通化」と「Case 1 を内容変更なしで維持」が文字通りには両立しないため、Case 2 側から Case 1 step 4 を参照する形で解決した。設計逸脱として正しく記録されている
- Code Retrospective は `### Rework` を `N/A` と記録しているが、これは code フェーズ内部から見た視点であり、**オーケストレーション層では code フェーズが 2 回走っている**。`.tmp/auto-events.jsonl` に `{"ts":"2026-08-08T15:18:25Z","issue":1266,"event":"code_retry_fire","iteration":"1","trigger_reason":"silent_no_op"}` が記録されており、1 回目の試行が silent no-op と判定されてリトライで着地した。code フェーズ開始 (15:04:31Z) からリトライ発火まで約 14 分を消費している。リトライは fresh context で起動するため、2 回目の実行が書く Code Retrospective は 1 回目の失敗を構造的に観測できない
- 同フェーズ中に `concurrent_commit_detected` が 5 件記録されたが、いずれも他セッションの commit (#1278 系の PR merge 等) であり本 Issue の実装とは無関係
- **Design Gaps/Ambiguities の事実主張に誤りがあった** (下記 verify を参照)

#### review

- patch route のため `/review` フェーズは実行されていない

#### merge

- patch route の直コミット。コンフリクト・CI 失敗なし

#### verify

- Pre-merge 4 件は `/code` フェーズで既に `[x]`、post-merge の observation 1 件は `auto-run` 未発火で SKIPPED。FAIL・UNCERTAIN ゼロ
- **Code Retrospective の precondition mismatch の帰属が誤りだった**: 「`phase/ready` 付与と `phase/code` 遷移が同一タイムスタンプ (15:04:31Z)」という記述に対し、実測のラベルイベントは `phase/ready` = 14:59:01Z、`phase/code` = 15:04:31Z で 5 分 30 秒の間隔がある。`/spec` は `phase/ready` を正常に付与しており、「`phase/ready` を経由しない」という仮説は成立しない
- **実際に発火した分岐の特定**: `scripts/reconcile-phase-state.sh` の `_precondition_code_common` が `matches_expected: false` を返す分岐は (1) `phase/ready` 不在、(2) Spec 不在かつ Size ≠ XS の 2 つのみ。`skills/code/SKILL.md` では precondition check が Step 3 (`:165`)、ラベル遷移が Step 4 (`:187`) であり、`run-auto-sub.sh` / `run-code.sh` はいずれも `gh-label-transition.sh` を呼ばない (grep ヒット 0)。したがって分岐 1 は構造的に成立不能で、発火したのは分岐 2 (Spec 不在、Size は S) である
- Spec ファイルは最終的に読めており実装は Implementation Steps に沿っているため、Step 3 の時点でのみ worktree から見えていなかったことになる。その時間窓が生じた理由 (worktree の base ref と `/spec` の push 伝播タイミング) は本 verify では未確定
- `/verify` Step 2 の PR 検索は `closes #1266` で PR #1090 を返したが、`gh-extract-issue-from-pr.sh` による実参照確認で `closes #1061` と判明し正しく除外された。#1202 で入った全文検索の誤ヒット対策が実際に機能した事例

### Improvement Proposals

- **`/code` Step 3 の precondition mismatch が診断可能な形で伝わっていない (Tier 2 — 記録のみ)**: `reconcile-phase-state.sh` は 2 分岐を区別できる message を返しているにもかかわらず、Code Retrospective はラベル起因と誤帰属し「原因未調査」で残した。結果としてラベルタイムラインの読み違えという二次的な誤りも生じている。スクリプト側の出力は既に十分で、`skills/code/SKILL.md` Step 3 も `matches_expected: false` を「Spec missing」と正しく説明しているため、修正すべきコード上の欠陥は特定できない。単独起票は見送る
- **`/code` の worktree が `/spec` の push 直後に Spec を見られない時間窓がありうる (Tier 2 — 記録のみ)**: 上記の分岐 2 発火は、fresh worktree の base ref と Spec push の伝播タイミングに起因する可能性がある。今回は non-interactive の warn-and-continue により実害ゼロで、Spec も実装時点では読めていた。ただしこの経路が成立する場合、`/code` が Spec なしで「Issue 本文から要件を読む」degraded モードへ静かに落ちるリスクを含む。機構は本 verify では未確定のため、確定的な証拠 (同型の再発、または worktree base ref の実測) が得られた時点で Tier 1 へ引き上げる

- **`code_retry_fire` がどの SSoT にも到達せず、Code Retrospective からも構造的に不可視 (Tier 2 — 記録のみ)**: 本 Issue の code フェーズは silent no-op によるリトライで 2 回走ったが、この事実は (1) Spec の Code Retrospective (`### Rework: N/A`)、(2) `docs/reports/orchestration-recoveries.md` (`Issue #1266` の grep ヒット 0) のいずれにも記録されていない。唯一の記録は `.tmp/auto-events.jsonl` の `code_retry_fire` イベントのみで、これは gitignore 対象のため永続的な監査記録にならない。リトライは fresh context で起動するので、2 回目が書く Code Retrospective が 1 回目の失敗を観測できないのは構造的な帰結であり、code フェーズ側の記述漏れではない。なお #869 の post-merge observation AC (「次回 silent no-op が観測された session で `code_retry_fire` イベントが `.tmp/auto-events.jsonl` に記録される」) は本イベントで満たされうる — 同 AC は `observation event=auto-run` のため `/verify` の opportunistic scan の対象外で、次回 `auto-run` 発火時に評価される。単独起票は見送るが、`code_retry_fire` の耐久記録先を持たせる提案が再度出た場合は #1279 (Metrics 汚染) と同じ「測定 SSoT の欠落」系統として Tier 1 を検討する
