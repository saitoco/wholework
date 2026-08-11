# Issue #1321: run-fact-matching: reconciliation が 120 件連続 ambiguous で auto-check に到達しない状態を解消

## Overview

`/auto` の run-fact AC reconciliation (`modules/run-fact-matching.md`) が 5 session 連続・通算 147 件で候補全件を `ambiguous` と判定し、`auto-check` が一度も発生していない。本 Spec は (1) `ambiguous` 判定を fail-safe 条件別に集計し、(2) 支配的要因である「候補の前提事象が本 run で発生していない」ケースへの対処として `scripts/scan-pending-ac.sh` の候補事前フィルタに 2 種類の除外ルールを追加し、(3) L3 retrospective を観察対象とする AC の順序問題の扱いを明文化する。

## Reproduction Steps

1. `/auto --batch` を任意の Issue セットで実行する。
2. 実行完了後の run-fact AC reconciliation ステップ (`skills/auto/SKILL.md` の Event-based observation scan 直後) で出力される要約行を確認する:
   ```
   Run-fact AC reconciliation: 0 auto-checked, N advisory, 0 not satisfied (candidates: N).
   ```
3. 直近 5 session (`74631-1786005349`〜`83307-1786372673`、2026-08-06〜2026-08-10) すべてでこの行の `auto-checked` が `0` であることを `docs/sessions/*/session.md` の `## Findings` で確認できる (通算 147 件、詳細は Root Cause 参照)。

## Root Cause

### 内訳計測 (AC1)

`ambiguous` と判定された候補が `modules/run-fact-matching.md` Step 3 の fail-safe 条件 (`:131-160`) のどれに該当したかを、条件別分類が記録されている唯一の session (`83307-1786372673`, 2026-08-10, `/auto --batch 1308 1265`, N=27) で集計した。

**測定範囲**: session `83307-1786372673` の run-fact AC reconciliation 1 回分、候補 27 件全件 (Issue コメント [issuecomment-5243181697](https://github.com/saitoco/wholework/issues/1321#issuecomment-5243181697) に Issue/ac_index 単位の内訳あり)。他 4 session (`74631-1786005349` `83694-1786088052` `91762-1786112233` `97764-1786198856`) は集計時点で条件別内訳を記録しておらず、`ambiguous` の合計件数 (各 session 30 件、`91762`/`97764` は本文で確認済み) のみが既知。

| 分類 (fail-safe 条件) | 件数 | 割合 | 該当 Issue(ac_index) |
|---|---|---|---|
| 条件の前提となる事象が本 run で発生していない | **15** | **56%** | #1200(7) #807(7) #783(11) #760(3) #627(8) #627(9) #478(6) #478(7) #355(6) #323(3) #319(12) #317(7) #303(7) #165(22) #141(11) |
| facts JSON に該当事実の表現がない | 8 | 30% | #1212(5) #953(7) #952(4) #626(4) #290(8) #278(4) #60(6) #1075(6) |
| conjunction の一部のみ facts で裏付け可能 | 4 | 15% | #1108(6) #458(5) #355(4) #249(4) |

支配的要因は「前提事象が本 run で発生していない」(15/27, 56%)。

### 支配的要因の構造分析

上記 15 件のサンプリング検証 (#1200 ac7, #807 ac7, #783 ac11 の 3 件を実際の Issue 本文で確認) から、以下が共通パターンとして判明した:

1. 3 件とも対象 Issue (#1200, #807, #783) は本 session (`83307-1786372673`) が実際に処理した Issue (#1265, #1308) と**一致しない** — バックログ上の無関係な別 Issue のペンディング AC である。
2. 3 件とも `verify-type: observation` または `opportunistic`、かつ `event=auto-run` / `event=code-run` という汎用イベント名 (特定の異常系イベント名ではなく「次回の /auto 実行一般」を指すイベント) が付与されている。
3. `scripts/scan-pending-ac.sh` の候補母集団は `gh issue list --label "phase/verify" --state all` でリポジトリ全体の未チェック post-merge AC を取得し、`--facts` の事前フィルタは「本 run の facts に含まれるどの Issue の値でもよいので、いずれかの `fact_tokens` が条件文に部分一致するか」という OR 判定に過ぎない。一方 `scripts/collect-run-facts.sh` の facts JSON は `route`/`phases`/`anomalies`/`recovery_tiers` などすべて Issue 番号キーの per-issue 構造であり、**候補 AC の対象 Issue が本 run の facts.issues[] に存在しない場合、その Issue に関する事実は facts JSON に一切存在しない**。

つまり、候補 AC の対象 Issue が本 run の処理対象と異なる場合、`observation`/`opportunistic` タイプの AC (「次回の /auto 実行で X が発生したときに Y であることを観察する」という将来イベント待ち文面) は facts JSON 上に対応する per-issue データが存在しないため、Step 3 の判定は構造的に `ambiguous` (fail-safe) にしかなりえない。既存の事前フィルタは条件文とのテキスト部分一致のみで候補化しており、この「対象 Issue の不一致」を検出していない。

**リグレッションリスク評価**: 過去 5 session 通算 147 件で `auto-check` は 0 件 (Purpose 記載のとおり)。したがって「対象 Issue が facts.issues[] に不在の observation/opportunistic 候補」を候補から除外しても、現状 `satisfied` に到達している既存ケースを壊すことはない (壊すべき成功ケースが存在しない)。

### 順序問題 (要因 2, AC3)

`skills/auto/SKILL.md` で run-fact AC reconciliation (単一 Issue 経路: `:760-764`, batch 経路: `:1299-1301`) は、いずれも L3 auto-retrospective 生成 (単一 Issue 経路: `:766-`, batch 経路: `:1307-`) より**前**に実行される。session `97764-1786198856` の実測で、L3 retrospective 自体を観察対象とする AC 3 件 (#1307 #1300 #1289) が候補に入ったが、いずれも構造的に判定不能だった。

さらに、`scripts/collect-run-facts.sh` の facts JSON スキーマ (`session_id`/`mode`/`number`/`size`/`route`/`pr`/`pr_state`/`phases`/`anomalies`/`recovery_tiers`/`fact_tokens`) には L3 retrospective の内容や notable 判定結果を表す項目が一切存在しない。したがって reconciliation の実行順序を L3 生成後に変更しても、facts JSON 自体にこの種の AC を判定する手がかりが追加されない限り解消しない — 順序問題は名前のとおり「順序」だけの問題ではなく、facts スキーマの恒久的な表現力ギャップでもある。

### 対処方針 (AC2, AC3)

`scripts/scan-pending-ac.sh` の候補列挙に、`--facts` 指定時のみ有効な除外ルールを 2 つ追加する:

- **Rule 1 (支配的要因への対処, AC2)**: 候補の `verify_type` が `observation` または `opportunistic` で、かつ候補の Issue 番号が facts JSON の `issues[].number` に含まれない場合、候補から除外する。
- **Rule 2 (順序問題への対処, AC3— 除外オプションを採用)**: 候補の条件文が L3 retrospective / session retrospective の内容を参照するキーワード (`L3 retrospective` / `L3 レトロスペクティブ` / `L3 セッションレトロスペクティブ` / `session.md` / `セッションレトロスペクティブ` / `session retrospective`、大小文字を区別しない) を含む場合、除外する。

順序問題への 3 選択肢 (除外/再実行/繰り越し) のうち「除外」を採用した理由:
- **再実行** (reconciliation を L3 生成後にも再実行) は、上記のとおり facts JSON に L3 関連フィールドが存在しない限り効果がない。フィールド追加は `collect-run-facts.sh` のスキーマ拡張を要し、本 Issue のスコープ (測定 + 支配要因対処 + 順序問題の扱い明文化) を超える。
- **繰り越し** (次 session の候補へ) は現在の設計が実質的にすでに行っている挙動 (毎回 `scan-pending-ac.sh` が候補を再計算し直す) であり、Background に記録された繰り越し候補の単調増加 (11→37) はこの「繰り越すだけで解消しない」構造そのものが原因。繰り越しは対処ではなく現状維持に等しい。
- **除外**は、facts JSON で恒久的に判定不能な種類の候補に対して無駄な rubric 判定サイクルと advisory ノイズの再生成を止める、最小コストの対処である。

## Changed Files

- `scripts/scan-pending-ac.sh`: `--facts` 指定時の候補フィルタに Rule 1 (observation/opportunistic タイプ かつ 対象 Issue が facts.issues[].number に不在の候補を除外) と Rule 2 (L3/session retrospective 参照キーワードを含む候補を除外) を追加。ヘッダーの usage コメントに両ルールを追記。bash 3.2+ 互換 (mapfile 不使用、配列不使用、既存の `while IFS= read -r` パターンを踏襲)
- `modules/run-fact-matching.md`: 「fact_tokens Vocabulary and Matching Rule」の後に新セクションを追加し、Rule 1 / Rule 2 の内容・根拠・リグレッションリスク評価と、順序問題の 3 選択肢比較 (除外を採用した理由) を明文化
- `tests/run-fact-matching.bats`: 既存の `scan-pending-ac.sh` セクション (`:333-419`) に Rule 1 / Rule 2 それぞれの bats テストケースを追加
- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] `scan-pending-ac.sh` の説明行 (「`collect-run-facts.sh` の fact token で事前絞り込みする」) は Rule 1/Rule 2 追加後も概要としては引き続き正確であり、変更不要と判断 (grep で該当行を確認済み — 詳細な除外ルールは `modules/run-fact-matching.md` が SSoT を担う)

## Implementation Steps

1. `modules/run-fact-matching.md` の「fact_tokens Vocabulary and Matching Rule」直後に新セクションを追加し、AC1 の内訳表・支配的要因の構造分析・Rule 1/Rule 2 の内容と根拠・順序問題の 3 選択肢比較を記載する (→ acceptance criteria 1, 2, 3)
2. `scripts/scan-pending-ac.sh` に Rule 1 (observation/opportunistic タイプかつ対象 Issue が facts.issues[].number に不在の候補を除外) を実装する。実装位置: 既存の `if [ -n "$FACTS_PATH" ]; then` ブロック直後に facts JSON の `issues[].number` 一覧を一度だけ読み取る変数を追加し (既存の `FACT_TOKENS_LOWER` 抽出と同じ箇所)、候補ループ内で `vtype` が `observation`/`opportunistic` のときだけ判定する (→ acceptance criteria 2)
3. `scripts/scan-pending-ac.sh` に Rule 2 (L3/session retrospective 参照キーワードを含む候補を除外) を実装する。実装位置: Rule 1 と同じ候補ループ内、`CANDIDATES` への追加直前 (→ acceptance criteria 3)
4. `tests/run-fact-matching.bats` の `scan-pending-ac.sh` セクションに、Rule 1 (facts.issues に対象 Issue 番号がない observation 候補が除外されること、facts.issues に対象 Issue 番号がある場合は除外されないこと) と Rule 2 (L3 retrospective 参照キーワードを含む候補が除外されること) の bats テストケースを追加し、`bats tests/run-fact-matching.bats` が既存スイートを含め PASS することを確認する (→ acceptance criteria 4)

## Verification

### Pre-merge

- <!-- verify: rubric "直近セッションの run-fact reconciliation について、ambiguous と判定された候補が modules/run-fact-matching.md の fail-safe 条件のどれに該当したかを条件別に集計した結果が、Spec またはレポートに記録されている" --> `ambiguous` の内訳が条件別に集計・記録されている
- <!-- verify: rubric "上記の集計で支配的と判明した要因に対する具体的な改善が、modules/run-fact-matching.md の判定基準または scripts/collect-run-facts.sh / scripts/apply-run-fact-match.sh の実装に反映されている。改善が不要と判断した場合はその根拠が記録されている" --> 支配要因への対処または不要判断の根拠がある
- <!-- verify: rubric "L3 retrospective を観察対象とする AC が reconciliation より後に生成される順序問題について、除外・再実行・繰り越しのいずれかの扱いが modules/run-fact-matching.md または skills/auto/SKILL.md に明文化されている" --> 順序問題の扱いが明文化されている
- <!-- verify: command "bats tests/run-fact-matching.bats" --> `tests/run-fact-matching.bats` の既存スイートが回帰していない (回帰保護のみを目的とする AC — 新規カバレッジの主張は前 3 項が担う)

### Post-merge

- 次に run-fact reconciliation が走った session で、`auto-check` が 1 件以上発生するか、または `ambiguous` 率が実測で低下していることを確認する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **AC2 の実装対象ファイルについて**: AC2 の rubric 文言は `modules/run-fact-matching.md の判定基準` または `scripts/collect-run-facts.sh` / `scripts/apply-run-fact-match.sh` の実装を挙げているが、本 Spec は `scripts/scan-pending-ac.sh` (候補の事前フィルタ・enumeration を担うスクリプト) を実装対象とした。`modules/run-fact-matching.md` 自身の Purpose セクションが「three scripts... candidate enumeration and pre-filtering」として `scan-pending-ac.sh` を本メカニズムの構成要素と明記しており、かつ Rule 1/Rule 2 の根拠・判定基準は `modules/run-fact-matching.md` 側にも明文化するため、AC2 の意図 (支配要因への具体的改善が判定基準に反映されている) は満たされると判断した。`collect-run-facts.sh` (facts JSON スキーマ拡張) や `apply-run-fact-match.sh` (verdict/action ロジック) 自体の変更は不要と判断した — Rule 1/Rule 2 はいずれも「候補化する前に不要な候補を弾く」層で完結し、Step 3 の判定基準 (`satisfied`/`not_satisfied`/`ambiguous`) や Step 4 の tier gate ロジックには手を入れない。
- **Rule 1 のスコープを observation/opportunistic に限定した理由**: `manual`/`auto` タイプの AC は、対象 Issue 固有の実装内容ではなく Wholework 自身の一般的な振る舞い (どの run でも成立しうる構造的な主張) を記述しているケースがあり (例: `#1212 ac5` — 「/verify の CI 検証が headSha を照合してから判定する」という一般的挙動の主張。ただし facts JSON に「どの run を参照したか」を表す項目がなく `no representation` 分類に該当し `satisfied` には到達しない)、対象 Issue が facts.issues[] に不在であることを理由に機械的除外すると、まれに成立しうる判定機会を失うリスクがある。`observation`/`opportunistic` は本質的に「将来のイベント発生を待つ」文面であり、対象 Issue 不一致時に facts JSON 上で判定可能な情報が原理的に存在しないことがサンプル検証 (#1200/#807/#783) で確認できたため、除外対象をこの 2 タイプに限定した。
- **Rule 2 のキーワード選定について**: 単純に `L3` を bare token として使うと `autonomy: L3` など無関係な文脈まで誤除外するため、`L3 retrospective` 等の複合語のみを対象とした。
- **`opportunistic-search.sh` は対象外**: `modules/run-fact-matching.md` の fact_tokens セクションが `scan-pending-ac.sh --facts` と `opportunistic-search.sh --facts` を並記しているが、後者は observation AC のイベント名一致ディスパッチ機構であり、本 Issue が扱う「facts JSON との照合で `ambiguous` に倒れ続ける」問題を持たない別メカニズムのため、変更対象に含めなかった。
- Issue body とコードの記述に矛盾は検出しなかった (verdict → action マッピング等はすべて `scripts/apply-run-fact-match.sh` の実装と一致することを確認済み)。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective コメント。session `83307-1786372673` の追加実測 (27 件全件 ambiguous の内訳分類と pre-filter 改善の示唆) を Background・対応方針へ統合済みであることの記録。本 `/spec` フェーズでの追加アクションは不要 (Issue 本文に統合済みの内容を Root Cause セクションでそのまま活用した) / https://github.com/saitoco/wholework/issues/1321#issuecomment-5248548214
- `/code` フェーズ (本コミット時点): cutoff (最新 `phase/*` ラベル付与時刻 `2026-08-11T03:35:39Z`) 以降の新規コメントなし。
- `/review` フェーズ (本コミット時点): cutoff (最新 `phase/*` ラベル付与時刻 `2026-08-11T03:41:58Z`) 以降の新規コメントなし (Issue/PR とも)。

## Code Retrospective

### Deviations from Design

- N/A — Spec の Implementation Steps 1〜4 をそのままの順序・対象ファイルで実装した。

### Design Gaps/Ambiguities

- N/A — Spec の Root Cause / 対処方針 (Rule 1 スコープ限定の理由、Rule 2 キーワード選定の理由、順序問題 3 選択肢の比較) が実装判断に必要な情報を過不足なく提供していた。

### Rework

- N/A — 手戻りは発生しなかった。

### Test Execution Note

- `scripts/scan-pending-ac.sh` は `tests/scan-pending-ac.bats` からも参照されているため (Spec の Changed Files に記載のない参照)、Step 9 の Behavioral Change Detection により `bats --jobs <N> tests/` のフルスイート実行が確定した。フルスイート 1745 件全 PASS を確認済み (`tests/run-fact-matching.bats` 単体の 35 件 PASS を含む)。

## review retrospective

### Spec vs. implementation divergence patterns

- N/A — review-light の Perspective 1 (Spec 逸脱) で Spec の Implementation Steps 1〜4 と実装の一致を確認済み。構造的な乖離は検出されなかった。

### Recurring issues

- CI `Language Convention check` が FAILURE (MUST) となり `/review` の Step 12 で修正した。根本原因は `scripts/check-language-convention.py` の除外ロジック (フェンス/インラインコード/二重引用符の3種) が (1) 複数行にまたがるインラインコードスパンの行単位バックティック対応判定のずれ、(2) heredoc 内の機能的な日本語キーワードリテラル (二重引用符でもフェンスでもない生テキスト) のいずれにも対応していないこと。今回は `printf '%s\n' "..."` 形式への書き換えと行折り返し位置の調整で回避したが、`scripts/scan-pending-ac.sh`/`modules/run-fact-matching.md` に限らず「AC 条件文が日本語である (`CLAUDE.md` の Issue body 言語規約) ため、マッチング用キーワードデータも日本語で持たざるを得ない」パターンは他の pre-filter 実装でも今後発生しうる。`check-language-convention.py` 自体に (a) 複数行インラインコードスパンの状態追跡、(b) heredoc/配列リテラル形式の機能的データを対象外とする除外ルールを追加する改善の余地がある — 次回同様の FAILURE が発生した場合は `check-language-convention.py` 自体の改善を検討する Issue 起票を優先する。

### Acceptance criteria verification difficulty

- N/A — rubric 3 件・command 1 件とも PR diff / CI 参照から明確に判定でき、UNCERTAIN は発生しなかった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Step 9 の CI Blocking by default ルールに従い、`Language Convention check` FAILURE を MUST として扱い REQUEST_CHANGES 相当でブロック、Step 12 で修正した (self-review のため実際の投稿イベントは COMMENT フォールバック)。
- 修正はチェッカーの誤検知を回避する目的の純粋なフォーマット変更 (heredoc → `printf` + 二重引用符、インラインコードスパンの改行位置調整) に限定し、Rule 1/Rule 2 の判定ロジック・キーワード内容には手を入れていない。修正後に `L3_KEYWORDS_LOWER` の出力がバイト同一であることを確認済み。

### Deferred Items
- Post-merge AC (「次に run-fact reconciliation が走った session で auto-check が 1 件以上発生するか、または ambiguous 率が実測で低下していることを確認する」) は `session=next` の observation 型のため、次回の `/auto` 実行後の観察に委ねる (`/code` フェーズから継続、未解消)。
- `check-language-convention.py` 自体の除外ロジック改善 (複数行インラインコードスパン追跡、heredoc データリテラルの除外) は本 PR のスコープ外 — 再発時に別 Issue での対応を検討 (review retrospective参照)。

### Notes for Next Phase
- `/merge` 実行前に CI は全 11 件 SUCCESS (コミット `22b00a7a`) を確認済み。
- Pre-merge AC は 4/4 PASS、Issue チェックボックスは既にすべて `[x]` (変更不要)。
