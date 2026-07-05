# Issue #923: issue: run-issue.sh の effort 再校正 (Sonnet 5 medium 候補、低リスク、C4)

## Consumed Comments

- saito / MEMBER / first-class / `/triage` (トリアージ) フェーズの Issue Retrospective — Type=Task・Size=M (`[[feedback_ci_sensitive_size_m]]` 準拠の CI-sensitive 昇格)・Priority=low・Value=3 の判定根拠、背景記載の事実確認 (advisory、一致確認済み)、および曖昧性自動解決 1 件 (記録フォーマットは #921/#922 と同一パターンの踏襲) の判断根拠を確認。AC 文言への影響なし、新規アクションなし / https://github.com/saitoco/wholework/issues/923#issuecomment-4886096793

## Overview

`docs/reports/claude-sonnet-5-impact-strategy.md` §8 の候補 Issue **C4**。C1 (#914、default parent の Sonnet 5 切替) が着地し、同レポート §4.2 で issue フェーズ (`run-issue.sh`、現行 `high` 固定) が effort 再校正候補として挙げられている (4 候補中最も優先度が低い)。

本 Spec 作成時点の調査 (`run-issue.sh` の実際の呼び出し元・実行フロー・sub-agent frontmatter の確認込み) で **`high` 維持** の判定に至った。決め手は #229 (Sonnet 4.6 ベースライン) の従来根拠 (L/XL での sub-agent effort 継承) の単純な再確認ではなく、新たに発見した構造的事実にある: `run-issue.sh` は常に非対話モードで実行されるため、L/XL 向け sub-agent fan-out を含む Step 12 (Scope Assessment) は Issue サイズに関わらず常にスキップされ、実際には一度も実行されない。したがって #229 の従来根拠および `docs/tech.md` 現行表の当該行 Rationale 記述はいずれも、`run-issue.sh` が実際には到達しないコードパスを前提にしていたことになる。詳細な根拠は本 Spec の `## Notes` に記録し、実装フェーズでは専用レポート (`docs/reports/sonnet-5-effort-recalibration-issue.md`) の新規作成と `docs/tech.md`/`docs/ja/tech.md` への判定サマリ note 追記のみを行う (`run-issue.sh` 本体・matrix 表本体・bats テストの変更は伴わない)。

## Changed Files

- `docs/reports/sonnet-5-effort-recalibration-issue.md`: new file — `run-issue.sh` の Sonnet 5 effort 再評価 (評価方法・実行経路の確認・判定根拠・本番サンプル・`#229` との関係を記録)
- `docs/tech.md`: change — § Phase-specific model and effort matrix の "Sonnet 5 effort recalibration — spec (#922, C3)" note の直後 (`## Wholework Label Management` 見出しの直前) に、本 Issue (#923, C4) の判定サマリ note を追記
- `docs/ja/tech.md`: change — 上記 note の日本語ミラー同期 (`docs/translation-workflow.md` Sync Procedure 準拠。対応箇所は "Sonnet 5 effort 再校正 — spec (#922, C3)" note の直後)

## Implementation Steps

1. `docs/reports/sonnet-5-effort-recalibration-issue.md` を新規作成する。`## Notes` の「レポート構成」に従い、Background / Evaluation Method / Analysis (実行経路の確認・sub-agent 継承根拠の妥当性・構造比較と下流波及範囲・本番サンプル調査) / Recommendations / Notes の構成で判定 (「maintain high」) と根拠を記録する (→ acceptance criteria 1)
2. `docs/tech.md` § Phase-specific model and effort matrix の "Sonnet 5 effort recalibration — spec (#922, C3)" note の直後 (`## Wholework Label Management` 見出しの直前) に、`## Notes` に記載した英語 note 文言を追記する (after 1) (→ acceptance criteria 1, 2)
3. Step 2 の note を `docs/ja/tech.md` の対応箇所 ("Sonnet 5 effort 再校正 — spec (#922, C3)" note の直後) に、`## Notes` に記載した日本語訳文言で同期する (after 2) (→ acceptance criteria 1)

## Verification

### Pre-merge

- <!-- verify: rubric "run-issue.sh の effort (high → medium 候補) の評価結果と判定 (変更/据え置き) およびその根拠が docs/tech.md § Phase-specific model and effort matrix に記録されている" --> issue effort の再校正判定と根拠が docs/tech.md に記録されている
- <!-- verify: rubric "effort を変更した場合は run-issue.sh の実値と matrix 表の記述が整合している (SSoT 一致)。据え置いた場合は表に変更がない" --> 変更時は run-issue.sh と matrix 表が SSoT として一致している

### Post-merge

なし

## Notes

### 判定サマリ

| Script | 現行 | 判定 | 決め手 |
|--------|------|------|--------|
| `run-issue.sh` | `high` | **維持** | #229/現行 matrix 行の根拠 (L/XL sub-agent effort 継承) は、`run-issue.sh` が常に非対話モードで実行され Step 12 (sub-agent fan-out を含む) が常にスキップされるため実際には適用されない。正しい決め手は、単一エージェントによる 13 実効ステップの推論チェーンがパイプライン最上流の成果物 (Issue title/body/AC/verify command/Size/Priority) を生成し、その誤りが下流の全フェーズ (spec・code・review・merge・verify) に伝播する点にある |

### run-issue.sh の実行経路の確認

`run-issue.sh` の呼び出し元はコードベース内で `skills/auto/SKILL.md` の 1 箇所のみ (`phase/*` ラベル未設定の Issue に対して `/auto` が実行)。`scripts/run-issue.sh` はプロンプトを常に `"${SKILL_BODY}\n\nARGUMENTS: ${ISSUE_NUMBER} --non-interactive"` の形で構築しており (スクリプト本体で確認済み)、すべての実行が非対話モードとなる。また `$ISSUE_NUMBER` はスクリプト冒頭で数値であることが検証される (`[[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]`)。`skills/issue/SKILL.md` 自身のモード判定規則 ("If ARGUMENTS is a number, refine an existing issue; if a string, create a new one") により、`run-issue.sh` は常に「Existing Issue Refinement」フローを実行する ("New Issue Creation" には到達しない)。

### sub-agent effort 継承根拠が実際には適用されない、という発見

「Existing Issue Refinement」は 14 ステップのフロー (fetch → triage 自動連鎖 → ラベル遷移 → steering doc 参照 → 背景事実確認 → 曖昧性検出 → AC分類/verify command 割当 → 確認質問 → issue body 更新 → title drift チェック → blocked-by 検出 → **Scope Assessment (Step 12)** → issue retrospective → opportunistic verification)。sub-agent をスポーンするのは Step 12 のみで、L/XL Issue の場合 Step 12a が `issue-scope`/`issue-risk`/`issue-precedent` (いずれも `model: opus`、grep 確認済みで `effort:` 未設定 = orchestrator から継承、`#921` が `review-bug`/`review-spec` で確認したのと同一パターン) を並列スポーンする。

しかし Step 12 の本文は、Issue サイズによる分岐より前に無条件の非対話モードスキップ節から始まる: 「(non-interactive mode: skip this entire step — sub-issue splitting is a High-Stakes Decision... then proceed to Step 13.)」。前項で確認した通り `run-issue.sh` は常に非対話モードで実行されるため、Step 12 — およびその中の Step 12a の Opus sub-agent fan-out — は Issue サイズに関わらず **実際には一度も実行されない**。3 つの sub-agent が実行されるのは、人間が自身のセッションで `/issue N` を対話的に実行した場合のみであり、これは本 Issue が評価対象とする `--effort` フラグが支配しない別の実行コンテキストである。

**発見**: #229 の当初の根拠 (「L/XL では sub-agent の精度維持のため `high` を維持する必要がある」) と、現行 `docs/tech.md` 表の当該行の Rationale 記述 ("L/XL scope analysis and sub-issue splitting require thorough orchestration") はいずれも、`run-issue.sh` が実際には到達しないコードパスを前提にしていた。これは `#921` が `run-review.sh` の「mechanical」という位置づけを不正確と見出したのと同種の発見である — いずれのケースも、文書化された根拠が実際にはその対象スクリプトの挙動を正しく描写していなかった。Issue の Auto-Resolved Ambiguity Points (テーブルセルの書き換えより既存の note 方式を優先) に従い、本 Issue はマトリクス表の Rationale 列自体は書き換えず、修正後の根拠を `docs/tech.md` の prose note に記録する。

### 構造比較と下流波及範囲

Step 12a を除くと、`run-issue.sh` の実質的なワークロードは sub-agent への fan-out を持たない単一エージェントの 13 実効ステップの推論チェーンであり、`#921` が `run-code.sh` (14 ステップ) に、`#922` が `run-spec.sh` (19 ステップ) に用いたのと同じ構造クラスに属する。impact strategy レポート §4.2 の「実装ではなくスコープ分析」という位置づけは、このフローが実際に行っている作業を過小評価している: Step 6 (曖昧性検出+自動解決)・Step 7 (受入条件の分類と verify command 割当)・Step 5 (背景事実確認)・Step 10 (title drift 検出) はいずれも spec 執筆と同種の実質的な判断作業 (Issue が何を求めているか、それをどう機械的に検証するかを決定する作業) であり、受動的なスコープ記述ではない。

issue フェーズの成果物 (title・body・受入条件・verify command・Size/Priority/Type/Value) はパイプライン全体で最も上流の成果物でもある。ここでの誤りは下流の**すべて**のフェーズ (spec・code・review・merge、および割り当てられた verify command を直接実行する verify) に伝播する — これは `run-code.sh` (`#921`) や `run-spec.sh` (`#922`、code+review+merge の 3 フェーズと数えた) よりもさらに長い伝播チェーンである (issue フェーズの誤りは post-merge の受入テストで初めて `/verify` に到達する不備な AC としても現れうるため)。これは impact strategy レポート §4.2/§8 の「4 候補中最も優先度が低い」という位置づけよりも強い下流波及範囲の論拠であり、「再校正の緊急度 (優先度)」と「判定を誤った場合の波及コスト (波及範囲)」は別の軸であることを示している。本レポートの発見は後者に関するものである。

### 本番サンプル調査 (Sonnet 5 デフォルト化以降にコードされた Issue)

`docs/spec/*.md` の Code Retrospective 「Design Gaps/Ambiguities」節を、#914 (Sonnet 5 デフォルト化) 以降にコードされ本レポート作成時点で Spec が存在する全 Issue (915, 916, 917, 918, 921, 922, 927, 930, 932 — 9件、`#922` の Analysis 4 と同一母集団に、以降コードされた3件を追加) を対象に調査した:

| Issue | Design Gaps/Ambiguities — issue フェーズ起因か |
|---|---|
| #915, #916, #918, #927, #932 | N/A — 記載なし |
| #917 | リカバリーガイダンスとセキュリティ classifier の相互作用。bats テスト実行で初めて判明した環境/実行時固有の事象であり issue フェーズの成果物品質に起因しない |
| #921 | 中断した `/code` 実行の再開に関する手続き上のメモ。issue フェーズの内容に起因しない |
| #930 | macOS の `/tmp`→`/private/tmp` シンボリックリンクのテスト比較不一致。環境固有の事象であり issue フェーズの内容に起因しない |

**読み方**: 9件のサンプルいずれにも issue フェーズ (Existing Issue Refinement) の成果物品質に起因するギャップ (受入条件の誤分類、`/issue` に遡って追跡できる検証不能な verify command、Size/Priority の誤判定が spec/code 時点の手戻りとして表面化した事例など) は見つからなかった。これは `#922` の Analysis 4 と同じ意味で中立的である: `high` が必要であることを証明するものではないが、余剰マージン (「このフェーズは過剰投資である」という指摘の記録) の兆候も存在しない — 現行の `high` が引き続き適切に機能していることと整合する (証明ではない) 結果である。

### docs/tech.md に追記する note (英語、Step 2 で使用)

"Sonnet 5 effort recalibration — spec (#922, C3)" note の直後に以下を追記する:

> - **Sonnet 5 effort recalibration — issue (#923, C4)**: re-evaluated whether `run-issue.sh` effort could drop from `high` to `medium` under Sonnet 5's widened effort curve (impact strategy report §3.3/§4.2), which framed the issue phase as "scope analysis rather than implementation" and the lowest-priority candidate of the four. **Verdict: maintain `high`** (full analysis: `docs/reports/sonnet-5-effort-recalibration-issue.md`). `run-issue.sh` is invoked only by `/auto` for Issues lacking `phase/*` labels and always runs non-interactively; since it always passes a numeric Issue number, it always executes `skills/issue/SKILL.md`'s "Existing Issue Refinement" flow, a single-agent 14-step reasoning chain whose only sub-agent fan-out (Step 12's L/XL `issue-scope`/`issue-risk`/`issue-precedent` Opus sub-agents) is unconditionally skipped in non-interactive mode ("sub-issue splitting is a High-Stakes Decision") — regardless of Issue size. This means both `#229`'s original `high` rationale and this table row's own Rationale text ("L/XL scope analysis and sub-issue splitting require thorough orchestration") describe a code path `run-issue.sh` never actually reaches, an inaccuracy in the same vein as `#921`'s finding about `run-review.sh`'s "mechanical" framing. The corrected rationale: Existing Issue Refinement performs substantive judgment work (ambiguity auto-resolution, acceptance-criteria/verify-command authoring, background fact-checking) to produce the pipeline's most upstream artifact, whose errors propagate through every downstream phase (spec, code, review, merge, verify) — the longest blast radius in the C-series. A production-sample check across 9 Issues coded under Sonnet-5-as-default (#915–#932) found no issue-phase-attributable design gaps (net-neutral, consistent with continued adequate performance). No changes made to `run-issue.sh`, this matrix table, or `tests/run-issue.bats` (confirmed no `--effort` assertions present).

### docs/ja/tech.md に追記する note (日本語、Step 3 で使用)

"Sonnet 5 effort 再校正 — spec (#922, C3)" note の直後に以下を追記する:

> - **Sonnet 5 effort 再校正 — issue (#923, C4)**: Sonnet 5 の effort curve widening (impact strategy レポート §3.3/§4.2) を踏まえ、`run-issue.sh` の effort を `high` から `medium` に下げられるか再評価した。同レポートは issue フェーズを「実装ではなくスコープ分析」と位置づけ、4 候補中最も優先度が低いとしていた。**判定: `high` を維持**（詳細分析: `docs/reports/sonnet-5-effort-recalibration-issue.md`）。`run-issue.sh` は `phase/*` ラベル未設定の Issue に対して `/auto` からのみ呼び出され、常に非対話モードで実行される。Issue 番号は常に数値で渡されるため、`skills/issue/SKILL.md` の「Existing Issue Refinement」フロー（単一エージェントによる14ステップの推論チェーン）を常に実行する。このフローで唯一 sub-agent へ fan-out する箇所（Step 12 の L/XL 向け `issue-scope`/`issue-risk`/`issue-precedent` Opus sub-agent）は、Issue サイズによらず非対話モードでは無条件にスキップされる（「sub-issue 分割は High-Stakes Decision」）。つまり `#229` の当初の `high` 判定根拠、および本表の当該行の Rationale 記述（「L/XL scope analysis and sub-issue splitting require thorough orchestration」）は、いずれも `run-issue.sh` が実際には到達しないコードパスを前提にしていたことになる — `#921` が `run-review.sh` の「mechanical」という位置づけを不正確と見出したのと同種の発見である。修正後の根拠: Existing Issue Refinement は曖昧性の自動解決・受入条件と verify command の作成・背景事実確認などの実質的な判断作業を行い、パイプライン全体で最も上流の成果物を生成する。その誤りは下流の全フェーズ（spec・code・review・merge・verify）に伝播し、これは C-series の中で最も波及範囲が広い。Sonnet 5 デフォルト化後にコードされた Issue（#915〜#932、9件）の Code Retrospective を対象にした本番サンプル調査では、issue フェーズに起因する設計ギャップは見つからなかった（中立的な結果であり、現行の `high` が引き続き適切に機能していることと整合する）。`run-issue.sh`・本マトリクス表・`tests/run-issue.bats` はいずれも変更しない（`--effort` を検証するアサーションが存在しないことを確認済み）。

### スコープ外

- `run-code.sh`/`run-review.sh` (#921, C2)・`run-spec.sh` (#922, C3): impact strategy レポート §8 の別候補 (既に解決済み)
- `--effort=` フラグ露出によるサイズ条件付き effort tiering (C5): Icebox 候補 (§5.5)、本 Issue の判定とは別スコープ
- `docs/tech.md` 当該行の Rationale 列自体の書き換え、および Architecture Decisions 節の fork justification 表 (`run-issue.sh` の fork 根拠にも同様に「L/XL 並列 sub-agent investigation」という同種の不正確な記述がある) の修正: 本 Issue の Auto-Resolved Ambiguity Points により note 方式のみがスコープ内であり、テーブルセルの書き換えは意図的に実施しない。将来必要になった場合は別 Issue として扱う

### 関連 bats

判定が「維持」(`run-issue.sh` の実値変更なし) のため、`tests/run-issue.bats` の更新は不要。同ファイルは現状 `--effort` 値自体を検証するアサーションを持たない (grep 確認済み)。

### docs/ja/reports/ ミラー

`docs/translation-workflow.md` § Exclusions により `docs/reports/` は翻訳同期対象外。新規レポート `docs/reports/sonnet-5-effort-recalibration-issue.md` に ja ミラーは作成しない (`#229`/`#903`/`#921`/`#922` の既存レポートも ja ミラーなしで前例と整合)。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜3 を Spec 記載の順序・内容どおりに実施した。

### Design Gaps/Ambiguities

N/A

### Rework

N/A

## review retrospective

### Spec vs. implementation divergence patterns

特記事項なし。Implementation Steps 1〜3 は Spec 記載どおりに実施され、`review-light` エージェントによる Spec 乖離観点の検証でも issue は検出されなかった。

### Recurring issues

特記事項なし。review-bug 相当の issue は 0 件で、`#921`/`#922` と同型のドキュメントのみ変更 (レポート新規作成 + tech.md prose note 追記) であり、ワークフロー改善の余地を示す繰り返しパターンは見られなかった。

### Acceptance criteria verification difficulty

特記事項なし。AC 2件はいずれも `rubric` タイプの verify command で、`docs/tech.md`/`docs/ja/tech.md` の記載内容および `run-issue.sh` の実値 (`--effort high`) との突合により両方とも UNCERTAIN を挟まず PASS 判定できた。verify command の記述・検証しやすさに問題はなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #940 は mergeable=true (reason=clean、CI success、review approved) だったため、コンフリクト解消手順やテスト再実行は不要で、そのまま squash merge した。
- レビュー issue 0件・外部レビュー未設定 (`.wholework.yml` marker 未設定) だったため、追加の手動確認は行わず review フェーズのハンドオフ判定をそのまま踏襲した。

### Deferred Items
- `docs/tech.md` 当該行の Rationale 列自体の書き換え、および Architecture Decisions の fork justification 表の修正は、Spec の Auto-Resolved Ambiguity Points により引き続きスコープ外。

### Notes for Next Phase
- `closes #923` により Issue は squash merge で自動クローズ済み (base branch = main)。
- Issue #923 の Acceptance Criteria チェックボックスは code フェーズで既に `[x]` 済み。`/verify 923` で post-merge 検証 (該当なし) を確認可能。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- rubric 型 AC 2件は意味的に明確で、`/verify` が両者を UNCERTAIN なく即 PASS 判定できた。前例調査 (#217/#229 で run-issue.sh の Sonnet パスが初評価と確定) と rubric 単独構成 (C2/C3 に続く 3 件目の踏襲) が spec 時点で確立されており、AC 検証の曖昧性を事前に排除できていた。良好。

#### design
- Spec が「maintain high」判定と根拠 (非対話モードでの sub-agent fan-out スキップ・最上流成果物生成) を spec 時点で固定。実装は Implementation Steps 1-3 と完全一致。C2 (#921)/C3 (#922) の前例を踏襲した堅実な設計。

#### code
- 手戻り・fixup/amend なし (git 履歴クリーン、squash merge 1 コミット)。
- **注目観察 (matrix Rationale 列の不正確性 — C-series 横断 recurring)**: 再校正の過程で、matrix 表の run-issue.sh 行 Rationale 列「L/XL scope analysis and sub-issue splitting require thorough orchestration」が、非対話モードでは到達しないコードパス (Step 12 の L/XL sub-agent fan-out) を記述しており不正確であることを発見した。recalibration note で正しい根拠を文書化したが、Auto-Resolved Ambiguity により Rationale 列セル自体の書き換えはスコープ外とし未修正のまま。これは #921 が run-review.sh の「sub-agents handle deep analysis / mechanical」framing について指摘した不正確性と同型で、C-series 横断の recurring パターン。

#### review
- issue 0件 (clean review、MUST/SHOULD/CONSIDER なし)。doc-only の低リスク差分に対し review-light が適切に軽量。過検出・見逃しの兆候なし。

#### merge
- squash merge クリーン (`mergeable=true`/`reason=clean`、CI success・review approved)。コンフリクトなし。問題なし。

#### verify
- rubric 型 AC 2件とも初回 PASS、reopen サイクルなし。verify command 整合性: `run-issue.sh` の `--effort high` (line 118) が matrix 表 (Sonnet: high) と SSoT 一致し、「据え置き=表未変更」を機械照合できた。`tests/run-issue.bats` も無変更。inconsistency なし。

### Improvement Proposals
- (Tier 1 candidate, skill-infra) `docs/tech.md` § Phase-specific model and effort matrix の Rationale 列を recalibration 発見と整合させる。run-issue.sh 行の Rationale「L/XL scope analysis and sub-issue splitting require thorough orchestration」は非対話モードで到達しないコードパスを記述しており不正確 (#923 で発見)。run-review.sh 行の「Review orchestration; sub-agents handle deep analysis」も orchestrator 自身が実質的推論 (fix コミット生成) を行うため同型の不正確性 (#921 で発見)。両行の Rationale 列を、各 recalibration note が文書化した正しい根拠 (最上流/実質的推論の成果物生成、blast radius) に更新する。C-series (#921/#923) 横断の recurring パターンであり、SSoT である matrix 表の Rationale 列の記述精度に関わる skill-infrastructure improvement。
