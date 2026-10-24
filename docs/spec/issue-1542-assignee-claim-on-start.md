# Issue #1542: skills: 精査・実装の着手時に実行ユーザーを assignee に設定し、他メンバーの担当 Issue への重複着手を防止

## Auto Retrospective

### Execution Summary
| # | Title | Route | Result | Notes |
|---|-------|--------|--------|-------|
| #1543 | scripts: Issue の担当状況の判定・assignee の付与と付け替えを行う共通処理と auto-assign 設定を追加 | pr (L, review full) | SUCCESS | level 1。PR #1547。spec 後に Size を M → L に更新 (Changed Files 14 件、うち翻訳ミラー 3)。21:44 → 22:48 |
| #1544 | skills: /issue・/spec・/code の着手時に assignee を設定し、他メンバーの担当なら付け替え・続行・中止を確認 | pr (L, review full) | SUCCESS | level 2 (#1545 と並行)。PR #1548。spec 後に Size を M → L に更新 (Changed Files 10 件)。22:48 → 23:42 |
| #1545 | auto: 開始時に他メンバーの担当を確認し、--batch の自動選定から他メンバーの担当 Issue を除外 | pr (L, review full) | SUCCESS | level 2 (#1544 と並行)。PR #1549。spec 後に Size を M → L に更新 (Changed Files 12 件、うち翻訳ミラー 2)。22:48 → 23:54 |

### Parallel Execution Issues
- テキスト競合・回復処理はなし。3 件とも wrapper は exit 0 で、Tier 2 / Tier 3 の回復は発生していない
- level 2 の並行 spec で、#1545 は先に main に入った #1544 の Spec を読み、3 択の文言・順序、メッセージ、非対話警告の書式を揃えた (コミット `aed1d549`)。`modules/l0-surfaces.md` は両者とも表のセルを変えず、編集箇所が重ならないように調整した
- #1545 の /review 時点で main は #1544 のマージで先に進んでおり、`docs/workflow.md`・`docs/structure.md` と日本語ミラーの 4 ファイルが両側で編集されていたが、mergeStateStatus は CLEAN で意味上の矛盾もなかった
- 並行実装の副産物として、`/auto` Step 1a の担当確認手順が #1544 の `modules/assignee-check.md` と同じ内容を SKILL.md 内に重複して持っている。#1545 の Spec Notes でモジュール呼び出しへの置き換えを改善候補とし、#1545 の /verify 振り返りに委ねている (ここでは重複して起票しない)
- `/auto` 配下の子フェーズ (`run-*.sh` は常に `--non-interactive`) は、親が「付け替えずに続ける」を選んだ後も 1 フェーズにつき 1 回警告を出す。#1544 の Spec が許容と判断し、#1545 も抑止の引数は足していない (設計上の判断であり不具合ではない)
- 3 件の sub-issue は、この実行の時点では新機能のマージ前の skill で処理されたため、自身には assignee が付いていない (想定どおり)

### Improvement Proposals
- XL 分割時の sub-issue の Size 見積もりが 3 件とも過小で、spec 後に M → L に更新された。分割時の見積もり (約 4〜7 ファイル) は翻訳ミラー (`docs/ja/`)・`docs/structure.md`・`docs/workflow.md` などの索引系ドキュメントと bats テストを数えておらず、実際の Changed Files は 10〜14 件だった。`/issue` の Scope Assessment (sub-issue 分割) で Size を見積もる際に、これらの付随ファイルを含めて数える指針を足すと、post-spec の Size 更新 (review depth の変更) を減らせる。現状は Step 3a の post-spec Size refresh が自動で吸収しており実害はない

## Issue Retrospective

### 確認で決めたこと

- **autonomy tier では制御しない**: `autonomy:` を設定していない場合の既定は L1 であり、「L1 ではスキップ」と「既定で有効」を両方採ると、設定を触らない下流リポジトリでは assignee が付かない (実質 opt-in になる) という矛盾があった。フェーズラベル遷移も L1 で実行されている (L1 で止めているのは retire・auto-retry・premise コメントなど一部の機能だけ) ことから、フェーズ進行の一部として tier に依存させない方針をユーザーが選んだ
- **`--batch --until` も除外対象に含める**: `--batch N` と同じく候補を自動で選ぶモードなので、他のメンバーの担当 Issue を拾わないようにする。番号を明示する List mode だけを除外の対象外にする

### 自動で決めたこと

- **設定キー名を `auto-assign` にした**: 既存キー (`always-pr`、`session-auto-rename` など) と同じ kebab-case の boolean。既定値 true は `steering-hint` と同じ「既定で有効、false で無効」の形
- **付けるタイミングを「`/spec` と `/code` の両方の開始時」と書いた**: 当初は「最初の着手フェーズ」と表現していたが、未アサインのときだけ付けるルールなので、両方の開始時に処理を置けば実質最初の着手時にだけ付く。spec を省く XS/S は `/code` で付く。spec を A さん、code を B さんが実行した場合は、`/code` 開始時に付け替え確認 (対話) か警告 (非対話) が出る
- **`/auto` の候補除外は `auto-assign` の設定に依存させない (常に有効) と判断した**: `auto-assign: false` で自動付与を止めても、人が手動で付けた assignee は残る。その Issue を batch が拾わないことは自動付与の有無と関係なく望ましいため。AC には明記していないので、`/spec` で異論があれば見直す

### AC の作り方

- 実装手段 (`gh-label-transition.sh` へのオプション追加) は AC に入れず、背景の「実装案 (参考)」に留めた。AC は振る舞い (未アサインなら付く、上書きしない、失敗しても止めない、batch から除外) を rubric で書き、SKILL.md・設定ドキュメントへの記載を grep で補った
- 判定処理がスクリプトと SKILL.md のどちらに入るかは `/spec` で決まるため、bats テストは個別ファイルを指定せず、ケース網羅を rubric で求め、回帰は CI の bats ジョブを参照する形にした
- AC 自己監査で、`section_contains` の見出し引数に `## ` を付けていた不備を検出した (判定不能 (UNCERTAIN) になる)。手順に従い本文は書き換えず監査コメントとして残したので、`/spec` で修正すること

## Issue Retrospective

### ユーザーと決めたこと

- **既存 Issue の精査 (`/issue 123`) でも assignee を付ける**: 精査も重複すると無駄になる作業なので、着手した時点で他のメンバーに見えるようにする。新規作成 (`/issue "タイトル"`) では付けない (起票した人が担当するとは限らず、作成直後の精査は同じ実行の中で終わる)
- **他のメンバーがアサイン済みのときは 3 択で確認する**: 「自分に付け替えて続ける / 付け替えずに続ける / 中止」。重複を防ぐことが目的なので中止も選べるようにした。`/issue 123`・`/spec`・`/code` で共通
- **`/auto` は親が開始時に 1 回確認する**: 精査にも付けると「精査した人と実装する人が違う」ケースが普通になる。子フェーズは非対話なので、子フェーズの中で確認すると assignee が精査した人のまま残る。そのため確認を親に移した
- **同時着手は付与後の読み直しで検出する**: assignee はロックではないので、事後の警告にとどめる
- **3 分割**: 調査で必須の変更が 12 ファイル (ja ミラーを含めると 14) と分かり、分割の目安を超えた。基盤 (#1543) を先に作り、各スキルへの組み込み (#1544) と `/auto` (#1545) を並行で進める

### 自動で決めたこと

- **`/auto 123 --non-interactive` は警告して続ける**: `/auto` 自体も `--non-interactive` に対応している。その場合は子フェーズと同じく、assignee を変えずに警告だけを出す
- **`auto-assign: false` で止まるのは付与・付け替えだけにした**: 他のメンバーの担当の確認・警告と `/auto` の候補除外は、人が手で付けた assignee を尊重するためのものなので、設定に関係なく動く。前回の Retrospective で「候補除外は `auto-assign` に依存しない」としていた判断を、確認・警告にも広げた (#1543 の AC に明記した)
- **「中止」はフェーズラベルを変えずに終わる**: 中止したのに `phase/spec` などが付いていると、他のメンバーには着手済みに見えてしまうため
- **sub-issue の Size はすべて M**: 調査結果の見積もり (① 約 6〜7 ファイル、② 約 4〜5 ファイル、③ 約 5〜6 ファイル) に基づく。① には外部サービスの挙動の確認が含まれるので、`/spec` で規模を見直してよい

### 調査で分かったこと (sub-issue の背景に反映した)

- **当初の実装案の問題**: `gh-label-transition.sh` の既存の `gh issue edit` に `--add-assignee @me` を相乗りさせると、assignee の設定に失敗したときにラベル遷移ごと失敗する。assignee の更新はラベルの更新と別の呼び出しにする必要がある
- **確認のタイミング**: 中止で副作用が残らないよう、確認はラベル遷移の直前ではなく、`/issue 123` では triage の自動実行より前、`/spec`・`/code` では worktree に入る前に置く必要がある
- **許可設定とドキュメントの不整合**: `/auto` の allowed-tools に `gh issue edit` も `gh api` もない。また `modules/autonomy-tier.md` は L1 での L0 書き込みを不可としており、「tier で制御しない」方針と食い違う
- **実機で確かめる必要があること**: `gh issue edit --add-assignee` が追加型か置換型か、REST が割り当てできないユーザーを黙って無視するか、bot や Copilot の割り当てがどう見えるか。いずれも外部サービスの挙動なので、`/spec` で確認する

### AC の変更

- 前回の監査コメントの指摘を反映した: `section_contains` の見出し引数から `## ` を除いた。新しく追加する bats テストが修正前の実装で FAIL することを求める rubric AC も加えた
- 親の AC はすべて sub-issue に移し、親に固有の条件は残さなかった (すべての sub-issue が `phase/done` になれば親も完了する)

### Consumed Comments

- saito / MEMBER / first-class / AC の監査: `section_contains` の見出し引数の不備と、新規テストの検出力についての注意喚起 / https://github.com/saitoco/wholework/issues/1542#issuecomment-6383893048
- saito / MEMBER / first-class / 前回の Issue Retrospective (確認で決めたこと、自動で決めたこと) / https://github.com/saitoco/wholework/issues/1542#issuecomment-6383899932
