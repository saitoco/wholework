# Issue #1055: config: nested キーの block format 非対応による silent failure を解消

## Overview

`.wholework.yml` の nested キー (`capabilities.*`, `auto-retry-on-fail.*` 等) は、LLM 経由の読み取り (`modules/detect-config-markers.md`) では block format・flat format 両方に対応しているが、bash 経由の読み取り (`scripts/get-config-value.sh`) は flat format のみに対応しており、block format で設定された nested キーに対して常にデフォルト値 (通常 `false`) を無言で返す。

#1088 (2026-07-30 close) により `scripts/opportunistic-search.sh` の `config=` ゲート (L161-170) がこの bash 経路を実際に使うようになったため、Issue 本文に自由記述される `config=<key>` が nested キーの場合に silent failure が実害として顕在化した (本リポジトリの `.wholework.yml` で `get-config-value.sh capabilities.workflow false` が誤って `false` を返すことを確認済み)。ドキュメント整備のみ (Issue 本文の対応方針案 A) では既に発生している failure を解消できないため、本 Spec では `scripts/get-config-value.sh` 自体に単一階層の nested キー (block format) 対応を追加し (対応方針案 B)、bash 経路と LLM 経路の解釈範囲を一致させる。

## Changed Files

- `scripts/get-config-value.sh`: 単一階層の nested キー (block format) 読み取りに対応するフォールバック処理を追加、ヘッダーコメントと `--help` の nested キー非対応記述を更新 — bash 3.2+ compatible
- `tests/get-config-value.bats`: nested キー (block format) の回帰テストケースを追加 — bash 3.2+ compatible
- `modules/detect-config-markers.md`: bash 経由の読み取りが単一階層 nested キー (block format) に対応したことを示す注記を追加
- `modules/verify-classifier.md`: `config=` の scope 記述 (「nested キーは非対応」) を bash 側の対応状況に合わせて更新
- `modules/observation-trigger.md`: 同上 (`config=` の scope 記述を更新)
- [Steering Docs sync candidate — checked, no change needed] `docs/structure.md`: `get-config-value.sh` の説明 (line 187) は format に依存しない一般的な記述のため変更不要
- [Steering Docs sync candidate — checked, no change needed] `docs/tech.md`: `WHOLEWORK_CONFIG_PATH` の説明 (line 231) は本 Issue のスコープ外のため変更不要

## Implementation Steps

1. `scripts/get-config-value.sh` に単一階層 nested キーの block format フォールバック処理を追加する (→ 受入条件 1, 2)
   - 既存の flat キー一致ループ (現状 L71-82) で `VALUE` が見つからず、かつ引数 `KEY` がドットを 1 個だけ含む場合にフォールバックを実行する
   - `KEY` を最初のドットで `SECTION` (ドット前) と `SUBKEY` (ドット後) に分割する
   - `.wholework.yml` を再度 1 行ずつスキャンし、`IN_SECTION` フラグを保持する: 行が `^${SECTION}[[:space:]]*:[[:space:]]*$` (先頭に空白がなく、コロン以降が空のトップレベル行) に一致したら `IN_SECTION=true` にする
   - `IN_SECTION=true` の間、空行はセクション継続とみなしスキップする。空白始まりでない (コメント行を除く) 行に出会ったら `IN_SECTION=false` に戻す (セクション終了と判定し、以降その行では SUBKEY 一致判定を行わない)
   - `IN_SECTION=true` かつ空白始まりの行が `^[[:space:]]+${SUBKEY}[[:space:]]*:` に一致したら、既存の flat キー分岐と同じ strip chain (コメント除去 → 前後空白除去 → クオート除去) で `VALUE` を確定し break する
   - ヘッダーコメント (現状 L18-22 の Notes 箇条書き) と `--help` テキスト (現状 L47-51) の「Supports only flat kebab-case keys (nested keys ... are not supported)」という記述を、「flat キーおよび単一階層の nested キー (block format、例: `capabilities.workflow`) に対応。ドット 2 個以上のキーや inline hash format (`capabilities: { workflow: true }`) は非対応」という趣旨に更新する

2. `tests/get-config-value.bats` に nested キー (block format) の回帰テストを 3 ケース追加する (after 1) (→ 受入条件 1, 2)
   - ケース1: `capabilities:\n  workflow: true` を含む `.wholework.yml` に対して `capabilities.workflow false` を呼ぶと `true` を返すことを確認する
   - ケース2: `capabilities:\n  browser: true` (workflow キーなし) を含む `.wholework.yml` に対して `capabilities.workflow false` を呼ぶとデフォルト `false` を返すことを確認する
   - ケース3: `recoveries-auto-fire:\n  enabled: true` の直後に `capabilities:\n  workflow: true` が続く `.wholework.yml` に対して `recoveries-auto-fire.workflow false` を呼ぶとデフォルト `false` を返すことを確認する (セクション境界を正しく認識し、後続セクションの同名サブキーを誤って拾わないことの回帰テスト)

3. `modules/detect-config-markers.md` の YAML Parsing Rules 箇条書きの末尾 (`## Output Format` 見出しの直前、現状 L101 の `capabilities.mcp` に関する箇条書きの後) に、bash 側読み取り (`scripts/get-config-value.sh`) が単一階層 nested キーの block format に対応したことを示す注記を追加する (parallel with 1, 2) (→ 受入条件 3, 4)

4. `modules/verify-classifier.md` (line 65 付近) と `modules/observation-trigger.md` (line 182 付近) の `config=` scope 記述「`<key>` は flat kebab-case キーのみ対応、nested キー (例: `capabilities.browser`) は非対応」を、「`<key>` は flat kebab-case キーまたは単一階層の nested キー (block format) に対応、inline hash format や 2 階層以上のネストは非対応」という趣旨に更新する (parallel with 1, 2, 3)
   - 背景: `scripts/opportunistic-search.sh` の `config=` ゲート自体はコード変更不要 (Step 1 の修正により `get-config-value.sh` の呼び出し結果が自動的に正しくなるため) だが、ゲートの scope を説明するこれら 2 箇所のドキュメントが「nested キー非対応」という古い記述のまま残ると、本 Issue が解消しようとしている「ドキュメントと実装の不一致」が別の形で再発するため、整合を取る

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/opportunistic-search.sh の config check gate、または get-config-value.sh が、nested キー (例: capabilities.workflow) を block format で設定された .wholework.yml から正しく true/false を判定できる。現状 (get-config-value.sh capabilities.workflow false が誤って false を返す) の修正が含まれていること" --> nested キーの config= ゲートが silent failure を起こさない (振る舞いの修正が必須、ドキュメントのみでは不可)
- <!-- verify: command "test \"$(scripts/get-config-value.sh capabilities.workflow false)\" = true" --> `scripts/get-config-value.sh capabilities.workflow false` が本リポジトリの block format 設定 (`capabilities:\n  workflow: true`) を正しく `true` と判定する (B を選択した場合の直接的回帰テスト。D を選択した場合はこの AC を `opportunistic-search.sh` 側の同等テストに差し替えること)
- <!-- verify: rubric "detect-config-markers.md の nested キー記述に、block format が LLM 経由の解釈でのみサポートされ get-config-value.sh は flat key のみ対応である旨の注記がある、または get-config-value.sh が block format に対応しておりこの注記が不要になっている" --> 適用範囲が明示されている、または block format に対応している
- <!-- verify: grep "get-config-value" "modules/detect-config-markers.md" --> `detect-config-markers.md` から `get-config-value.sh` の制約への言及がある

### Post-merge

- `capabilities.*` や `auto-retry-on-fail.*` のような nested キーを `config=` に指定した observation/opportunistic AC が、実運用 (`/auto` や `/review --full` 実行時) で正しく判定されることを確認する <!-- verify-type: opportunistic -->

## Notes

- **設計判断 (対応方針案 B を採用)**: Issue 本文の対応方針案 A〜D のうち、案 B (`get-config-value.sh` の block format 対応) を採用した。理由: `config=<key>` は Issue 本文執筆者が自由記述するため、どの nested キーが渡されるかは事前に決められない。案 D (ゲート側のガード) は silent failure を「無言の false」から「警告付きの false/skip」に変えるだけで、`capabilities.workflow` のようなキーを正しく `true` と判定できるようにはならない。案 B なら `get-config-value.sh` の全呼び出し元 (15 箇所以上) に対して根本的に正しい値を返すようになり、`opportunistic-search.sh` 側のコード変更も不要になる。
- **既存事例 (#760) との整合**: #760 の Spec は `recoveries-auto-fire.threshold` を `get-config-value.sh` 経由ではなく `awk` で直接パースする判断をしており、その理由も「get-config-value.sh はネスト key 非対応のため」だった。ただし #760 は単一スクリプト内で静的に決まった 1 キーだけを読むユースケースであり、汎用スクリプトを拡張するより呼び出し側で awk 実装する方が影響範囲が小さいという判断だった。本 Issue の `config=<key>` はキーが実行時に自由記述されるため呼び出し側での個別対応が不可能であり、`get-config-value.sh` 自体を汎用的に拡張する以外の解決策がない。両者はユースケースの違いに基づく別々の妥当な判断であり矛盾しない。
- **inline hash format はスコープ外**: `detect-config-markers.md` は LLM 経由で `capabilities: { browser: true }` のような inline hash format にも対応しているが、`get-config-value.sh` は本 Issue でも block format のみに対応する (inline hash format は非対応のまま)。理由: 本リポジトリを含む既知の `.wholework.yml` 実例はすべて block format を使用しており、Issue の実測再現ケースも block format のため。2 階層以上のネスト (現行の marker 定義テーブルには存在しない) も同様にスコープ外。
- **`docs/guide/customization.md` は変更不要と判断**: Issue 本文の対応方針案 A は customization.md への注記追加も提案していたが、grep で確認した限り同ファイルは bash 経由 vs LLM 経由の対応範囲について現状何も記述しておらず、誤った記述は存在しない。案 B により両経路の対応範囲が (単一階層 nested キーの範囲で) 一致するため、追加の注記なしでも矛盾は生じない。
- **`get-config-value.sh` のインラインコメント制約について**: Issue 本文の補足で言及されている別制約 (インラインコメントを含む値行の扱い) は既に #979 で対応済みであり、本 Issue のスコープには含めない。

## Consumed Comments

- saito (MEMBER, first-class) — 2026-07-31T01:43:04Z — `/issue` フェーズの Issue Retrospective コメント。#1088 により前提「現時点で実害はない」が崩れたことを受けて Issue 本文 (Background/Purpose/対応方針/AC) を全面更新した経緯の記録。案 A 単独では不可・案 B または D のいずれかで振る舞い修正が必須という結論、および Post-merge AC を将来形から opportunistic 確認形へ差し替えた理由を含む。Issue 本文には既に反映済みであり、本 Spec の設計判断に対する新たな指示は含まれない。 https://github.com/saitoco/wholework/issues/1055#issuecomment-5138247917

## Auto Retrospective

### Orchestration Anomalies
- **[code-completed-no-pr]** Watchdog killed the process in phase `code-pr` (exit code 1) after code-pr completed its commits but before PR creation: `matches_expected:false` and `phase:code-pr` detected in reconcile-phase-state output. The run-code.sh phase exited without creating a PR. Reference: #415.
  - Root cause observed in this run is the **headless background-execution pattern**, not a watchdog timeout. The wrapper log's last LLM output line is `バックグラウンドで bats tests/ フルスイート実行中です。完了通知を待ちます (ポーリングはしません)。` — the code phase committed its work, then launched the full bats suite in the background and ended its turn waiting for a completion notification that `claude -p` can never deliver. `checkpoint milestone = post-commit` / `resume_action = push-and-pr`.
  - This is the **second confirmed occurrence** of the pattern #1097 describes (first: session `25766-1785288928`, PR #1090, `/review` phase). #1097's scope covers `modules/test-runner.md` and `skills/review/SKILL.md`; this occurrence is in the **`/code` phase**, which #1097's Acceptance Criteria do not cover.
- **[auto-retry blocked by parallel-session dirty files]** `run-code.sh`'s built-in auto-retry (`auto-retry: code phase silent no-op, retry 2/3`) aborted immediately with `Error: parent main has uncommitted changes. Resolve before proceeding.` The dirty files (`scripts/append-consumed-comments-section.sh`, `tests/append-consumed-comments-section.bats`) belong to a **concurrent session working on #1113**, not to this Issue. The parent-main dirty guard is session-agnostic, so an unrelated session's work-in-progress silently disables auto-retry for every other running `/auto`.

### Improvement Proposals
- `#1097` の対象範囲を `/code` フェーズにも広げる (または `/code` 用の follow-up を立てる)。現在の AC は `modules/test-runner.md` と `skills/review/SKILL.md` のみを対象としており、本件のように `/code` がフルスイートをバックグラウンド実行して通知待ちするケースは修正後も残る。`modules/test-runner.md` 側に headless 制約を書けば両フェーズを同時にカバーできる可能性がある。
- `run-code.sh` の parent-main dirty guard を **セッション帰属で判定**できるようにする。現状は main に未コミット変更があれば発生源を問わず auto-retry を止めるため、並行セッションが作業中のファイルによって無関係な `/auto` の自動復旧が無効化される。`scripts/check-verify-dirty.sh` は既に `classify=parent-main` を出力しているので、対象 Issue の変更ファイル集合 (Spec の `## Changed Files`) と突き合わせて「自分に関係しない dirty は auto-retry を止めない」判定にする余地がある。

## review retrospective

### Spec vs. implementation divergence patterns

構造的な乖離はなし。実装は Spec の Implementation Steps を忠実に再現していた。**問題は乖離ではなく Spec 側の仕様の穴**だった。

Spec の Step 1 は nested フォールバックのパース規則を「空白始まりの行が `^[[:space:]]+${SUBKEY}[[:space:]]*:` に一致したら」と正規表現レベルまで書き下ろしていたが、(a) インデント深度の検証、(b) セクションヘッダー行の末尾インラインコメント、(c) キー文字種の検証、の 3 点を規定していなかった。実装者は書き下ろされた正規表現をそのまま転記したため、3 点とも silent failure として残った (レビューで検出・修正、commit `7a84ecac`)。

学び: パーサ系の Spec では正規表現そのものではなく **満たすべき性質** (「セクション直下の子のみに一致する」「ヘッダーの末尾コメントを許容する」「キーは正規表現として解釈されない」) を書くほうがよい。具体的な正規表現を Spec に置くと、実装フェーズでその妥当性が再検討されずに転記されやすい。

### Recurring issues

1. **同一スクリプトへの制約の継ぎ足しが 3 件目**。#979 (インラインコメントの strip)、#1055 (nested キーの block format)、今回のレビュー修正 (直下の子限定 + キー文字種) と、`scripts/get-config-value.sh` の行指向 grep/sed パースは対応形状を継ぎ足す形で拡張が続いている。Issue 本文の補足も「同一スクリプトに関する 2 つ目の制約となるため、まとめて整理する価値があるかもしれない」と既に述べていた。

2. **AC でも Spec でも検出されない欠陥が、レビュー時の手動 edge case 実測ではじめて表面化した**。今回の 3 件はいずれも一時的な `.wholework.yml` を作って実際にスクリプトを走らせることで検出した。review-light エージェントは静的読解と既存テストの実行までは行ったが、未テストの入力形状を自分で構成して実行するところまでは踏み込まず、指摘 0 件で完了している。パーサ・バリデータ系の変更を含む PR では、negative/edge case 入力を実際に構成して実行することを review の定型手順にする価値がある。

### Acceptance criteria verification difficulty

UNCERTAIN は 0 件、Pre-merge 4 件すべて PASS で、verify command の記述精度そのものに問題はなかった。

ただし `command` type の AC (`test "$(scripts/get-config-value.sh capabilities.workflow false)" = true`) は safe mode では直接実行されず CI 参照フォールバックに落ちる。今回は `Run bats tests` job に同等の回帰テストがあったため PASS と判定したが、**AC は「本リポジトリの実 `.wholework.yml` に対する挙動」を問うているのに対し、bats テストは一時ファイルに対する挙動を検証している**という差がある。両者の同一性は現状モデル判断に委ねられており、判定根拠が暗黙になりやすい。

### Improvement Proposals

- `scripts/get-config-value.sh` の行指向パースの根本整理。対応/非対応の入力形状を 1 箇所に列挙した仕様テーブルを設け、テーブル駆動テストに寄せるか、最小 YAML サブセットパーサへ一本化する。制約の継ぎ足しが 3 件目であり、次の拡張要求が来る前に整理する価値がある。
- パーサ・バリデータ系の変更を含む PR に対する review フェーズの定型手順として、「negative/edge case 入力を実際に構成して実行する」ことを明文化する。今回の 3 件はすべてこの手順でのみ検出された。`review-light` / `review-bug` の観点定義に反映する余地がある。
- `modules/verify-executor.md` の CI Reference Fallback 節に、「CI ジョブが AC と同一の入力を検証していると確信できない場合は PASS ではなく UNCERTAIN に倒す」指針を明記する。現状は関連ジョブが SUCCESS であれば PASS とするだけで、検証対象の同一性はモデル判断に委ねられている。

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- `review-light` は指摘 0 件で完了したが、レビュー側の独自 edge case 実測で SHOULD×2 / CONSIDER×1 を検出した。MUST ではないものの、いずれも本 Issue が解消対象としている silent failure と同一クラス (エラーにならず誤った値 / default が返る) だったため、フォローアップに回さず review フェーズ内で修正した (commit `7a84ecac`)。
- 修正内容は 3 点: (a) nested キーの照合をセクション直下の子に限定 (孫キーの誤採用を防止)、(b) セクションヘッダー行の末尾インラインコメントを許容、(c) キー文字種を `[A-Za-z0-9._-]` に制限。
- (c) のガードはスクリプト冒頭 (flat キーループより前) に配置した。free-text 由来のキーは flat ループの正規表現にも補間されるため、nested フォールバック内に閉じたガードでは露出面の半分しか塞げないという判断。既存の静的呼び出し元はすべてこの文字種に収まることを確認済み。
- 受入条件の更新は行っていない。3 点の修正はいずれも照合範囲を厳密化する方向であり、AC テキストおよび verify command と矛盾しない (Pre-merge 4 件は修正後も PASS を維持)。

### Deferred Items

- Post-merge AC (nested キーを `config=` に指定した observation/opportunistic AC の実運用確認) は未消化。`/verify` の opportunistic 判定に委ねる。
- `get-config-value.sh` の行指向パースの根本整理 (仕様テーブル化 / 最小 YAML パーサ化) は本 Issue のスコープ外として見送り、上記 Improvement Proposals に記録した。
- inline hash format (`capabilities: { workflow: true }`) は Spec の明示的スコープ外のまま据え置き。

### Notes for Next Phase

- PR ブランチ `worktree-code+issue-1055` は `.claude/worktrees/code+issue-1055` (code フェーズの silent no-op の残骸) にチェックアウトされたままである。merge 後のブランチ削除がこれで失敗する可能性があるため、必要に応じて先に `git worktree remove` を実施すること。
- review 中の追加コミット (`7a84ecac` 修正 / `2625abc8` retrospective) に対する CI は確認済み: 9 checks 全 PASS (`wait-ci-checks.sh 1120` → `total=9 passed=9 failed=0`)。
- ローカル実行分は確認済み: `bats tests/get-config-value.bats` 27/27 PASS、`validate-skill-syntax.py skills/` 0 error、`bash -n scripts/get-config-value.sh` PASS。
