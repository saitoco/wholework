# Issue #1521: issue: Step 12a の調査エージェントが teammate として起動されると SendMessage(to="main") で結果を返せない

## Overview

`/issue` Step 12a が並列起動する `issue-scope` / `issue-risk` / `issue-precedent` は、調査結果の配信先を `SendMessage` の `to: "main"` に固定している。`SendMessage` のツール定義は `"main"` を「メイン会話 (background subagents only)」としており、`Agent` に `name:` を付けた起動が in-process の teammate になる環境 (agent teams 有効の対話セッション) では、`"main"` は依頼元を指さない。下流の repo での実行では、`issue-scope` が「自分自身が main」という意味のエラーで送れず、ファイルのフォールバックに倒れた (結果は失われなかった)。

この Issue では、エージェントが background の subagent として起動されても in-process の teammate として起動されても結果が依頼元に届くよう、配信手順を次のとおり変える。

- `SendMessage(to="main")` で送り、エラーが返ったら `SendMessage(to="team-lead")` で 1 回だけ再試行する。`team-lead` は agent team での依頼元 (リーダー) の宛先
- 両方がエラー、または `SendMessage` が使えない場合は、従来どおり `.tmp/issue-$NUMBER-{scope|risk|precedent}.md` に `Write` し、最終応答にパスを書く
- Step 12a の 3 つの prompt、3 エージェントの `Deliver Results`、Step 12a の Result collection を同じ手順に揃える

Issue 本文が Spec に委ねた 2 点は次のとおり決めた (根拠と却下案は Notes)。

1. 宛先の書き方: 順序つきの 2 宛先 (`main` → `team-lead`) を、エージェント定義と prompt の両方に書く
2. teammate から `"main"` に送ったときの実際の振る舞い: `SendMessage` のツール定義と公式ドキュメントで確認した (`"main"` は background subagent 専用)。teammate としての実機再現は、この headless 実行 (`claude -p`) では teammate が起動されないためできない。実機での確認は Post-merge の opportunistic 条件に残す

## Reproduction Steps

1. agent teams を有効にした (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) 対話の Claude Code セッションで、Size L/XL の Issue に `/issue N` を実行し、Step 12a に到達させる
2. Step 12a が `Task(..., name="scope-$NUMBER")` など `name:` つきで 3 エージェントを起動する。この環境では in-process の teammate として起動される (Issue 本文の観測: `TaskStop` の結果の `task_type` が `in_process_teammate`、依頼元が送ったメッセージの送信者名が `team-lead`)
3. 各エージェントが `### Deliver Results` の Primary に従い `SendMessage({to: "main", ...})` を呼ぶ
4. `issue-scope` は「自分自身が main」という意味のエラーで送れず、`.tmp/issue-$NUMBER-scope.md` へのフォールバックに倒れる。`issue-risk` / `issue-precedent` の結果は依頼元に届いたが、どの宛先で送ったかは確認されていない

## Root Cause

結果の宛先 `"main"` が、3 つのエージェント定義と Step 12a の 3 つの prompt に固定されている (Step 12a の Result collection も、その配信を前提に書かれている)。

- `SendMessage` のツール定義 (この実行で ToolSearch により取得) は、`to` の `"main"` を「The main conversation (background subagents only)」、`"researcher"` を「Teammate by name」としている。公式ドキュメントは、agent teams 有効の対話セッションで `name` つきの `Agent` 呼び出しは teammate として起動されると定め、agent team のリーダーのエージェント種別を `team-lead` としている。teammate が依頼元に送るときの宛先は `team-lead` である (出所は Notes)
- 履歴: #954 (`f086fc18`, 2026-07-09) が `to="main"` の配信を入れた時点で、Step 12a の `Task(...)` は `name:` なしだった (`git show f086fc18:skills/issue/SKILL.md` で確認)。#1031 (`0e932af9`, 2026-07-21) が `TaskStop` のために 3 つの起動へ `name=` を足した。公式ドキュメントの記述どおりなら、この追加で agent teams 有効の環境では 3 エージェントが teammate になり、#954 の「依頼元 = `main`」という前提が崩れる。この因果は、ドキュメントの記述とコミット履歴からの推定で、#1031 の前後に同じ環境で起動のされ方を比べてはいない
- 修正の妥当性: 宛先を `"main"` 固定から「`main` → `team-lead` → ファイル」の順序つきにすれば、どちらの起動のされ方でも依頼元に届く。`name:` を外す案は #1031 の `TaskStop` を失うため採らない (Notes)

## Changed Files

測定範囲: リポジトリ内で変更するファイル (本 Spec 自身を除く)。既存 4 件、新規 0 件。`to="main"` の参照は、この 4 ファイルの 6 行 (SKILL.md の prompt 3 行、各エージェントの Primary 1 行ずつ) で全部である (測定コマンド: `grep -rn -E 'to[:=] ?\\?"main\\?"' skills agents modules scripts tests docs README.md CLAUDE.md`、`docs/spec/` `docs/sessions/` `docs/reports/` は履歴なので除く)。

- `agents/issue-scope.md`: `### 4. Deliver Results` の Primary / Fallback を変更
- `agents/issue-risk.md`: `### 5. Deliver Results` の Primary / Fallback を変更。この見出しだけ番号が 5 (Issue 本文は 3 ファイルとも `### 4.` と書いているが、`issue-risk.md` は `### 5.`)。見出しは番号を含めて現状のまま残す
- `agents/issue-precedent.md`: `### 4. Deliver Results` の Primary / Fallback を変更
- `skills/issue/SKILL.md`: `#### Step 12a` の 3 つの prompt、"Delivery address" 段落の追加、Result collection の文言を変更。他の Step は変更しない

**同期候補の機械的スイープ** (測定コマンド: `grep -rl -- "<keyword>" docs/ tests/ scripts/ modules/ | wc -l`、範囲: 4 ディレクトリの全ファイル。`docs/spec/` と `docs/sessions/` を除いた件数は括弧内):

- `team-lead` (この変更が導入する宛先): 1 件 (括弧内 0 件。残る 1 件は過去の Spec) → 同期対象なし
- `SendMessage`: 5 件 (括弧内 1 件: `docs/reports/observation-ac-audit-d2.md`)。#954 の受入条件を記録した過去の監査レポートで履歴なので変更しない
- `Deliver Results`: 1 件 (括弧内 0 件。#954 の Spec) → 同期対象なし
- `issue-scope` 59 件 / `issue-risk` 30 件 / `issue-precedent` 30 件: いずれも 8 件を超え識別力がない (`own-issue-scope` という別の分類名も含む) ので、個別には評価しない
- [Steering Docs sync candidate] `docs/structure.md` の Agents 表と `docs/tech.md` の Sub-agent splitting / モデル表は、3 エージェントの役割 (L/XL の調査) だけを書き、配信手順を書いていないので変更しない (`grep -c -E 'SendMessage|team-lead' docs/structure.md docs/tech.md` が両方 0)。`docs/guide/workflow.md` L57 と `docs/product.md` L23 も並列調査の存在だけで、配信手順は無い
- [Listing-side sub-check] 発火しない。サブコマンドの追加・削除、ファイルの追加・削除・改名、ディレクトリ構成の変更のいずれも無い (既存 4 ファイルの文言変更だけ)
- [Outbound pointer sync candidate] 変更する範囲 (Step 12a と各 `Deliver Results`) に、他のリポジトリファイルを指す "See also" / "SSoT:" 型の pointer は無い。Step 12 冒頭の `modules/size-workflow-table.md` の Read は、今回の変更の影響を受けない
- `modules/doc-checker.md` と `modules/skill-dev-doc-impact.md` の Change Types: 「Skill の変更」「Agent の変更」に当たるが、対象文書 (`README.md` / `docs/workflow.md` / `CLAUDE.md` の skill 一覧・phase 説明・agent 一覧表) は、skill / agent の追加・削除・役割の変更で変わるもので、配信手順の文言変更では変わらない。`grep -c -E 'issue-scope|SendMessage|team-lead' README.md docs/workflow.md CLAUDE.md` が 3 ファイルとも 0 であることで確認した
- `docs/ja/*`: 翻訳元の `docs/*.md` を変更しないので同期不要
- `tests/`: 該当するテストは無い (`grep -rn -E 'Deliver Results|Step 12a|TaskStop|SendMessage' tests` が 0 件)

## Implementation Steps

1. `agents/issue-scope.md` の `### 4. Deliver Results` を変更する (→ 受入条件 1, 2)
   - Primary の bullet を次の文面に置き換える:
     ```text
     - **Primary**: after generating the Output Format markdown, call `SendMessage({to: "main", message: <full Output Format markdown>, summary: "<5-10 words>"})` to deliver the results to the requester (the session that launched you). `"main"` is the main conversation and is documented for background subagents only, so the call can be rejected when you were launched as an in-process teammate (a named agent in an agent team). If it returns an error, retry once with `to: "team-lead"`, the requester's address in an agent team. Stop at the first call that succeeds (do not send the markdown to both addresses), name that address in your final response text, and do not repeat the markdown there.
     ```
   - Fallback の bullet を次の文面に置き換える (フォールバックのパスは現状のまま維持):
     ```text
     - **Fallback**: if `SendMessage` is unavailable, or both addresses return an error, `Write` the same markdown to `.tmp/issue-$NUMBER-scope.md` and state that path in your final response text.
     ```
2. `agents/issue-risk.md` の `### 5. Deliver Results` を変更する。文面は Step 1 と同じで、Fallback のパスだけ `.tmp/issue-$NUMBER-risk.md` にする (Step 1, 3 と並行可) (→ 受入条件 1, 2)
3. `agents/issue-precedent.md` の `### 4. Deliver Results` を変更する。文面は Step 1 と同じで、Fallback のパスだけ `.tmp/issue-$NUMBER-precedent.md` にする (Step 1, 2 と並行可) (→ 受入条件 1, 2)
4. `skills/issue/SKILL.md` の `#### Step 12a` を変更する (Step 1-3 の後。エージェント側と同じ手順・語彙に揃える) (→ 受入条件 1, 2)
   - 3 つの `prompt=` を、次の形にする (scope の例。risk / precedent は現状の引数 (Steering Documents の有無) を保ち、パスだけ `-risk.md` / `-precedent.md` にする):
     ```text
     Task(subagent_type="issue-scope", description="Scope investigation", name="scope-$NUMBER",
       prompt="Issue=$NUMBER, Steering Documents=$STEERING_DOCS_FILES, Issue body=<full text>. Deliver your Output Format markdown via SendMessage(to=\"main\") on completion; if that call returns an error (for example because you run as an in-process teammate), retry once with SendMessage(to=\"team-lead\"); if SendMessage is unavailable or both calls return an error, Write it to .tmp/issue-$NUMBER-scope.md instead and state the path in your final response; otherwise name the address that worked in your final response.")
     ```
   - `Task(...)` の ```text ブロックの直後、`**Result collection**` の直前に、次の段落を足す:
     ```text
     **Delivery address**: a named launch starts each agent either as a background subagent or, in an interactive session with agent teams enabled, as an in-process teammate, and the harness decides which one applies. The requester's `SendMessage` address differs between the two: `"main"` (the main conversation, documented for background subagents only) for a background subagent, and `"team-lead"` for a teammate, for which `"main"` can be rejected. Each prompt above therefore names both addresses, `"main"` first, and falls back to a file only when both fail, so the result reaches this session in either case.
     ```
   - `**Result collection**` の最初の文を置き換える。旧: `` `SendMessage` delivers each agent's Output Format markdown automatically — no team-lead polling required. `` 新: `` `SendMessage` delivers each agent's Output Format markdown automatically, to this session under whichever of the two addresses above the agent used — no polling is required. `` (以降の文、`TaskStop` のコードブロックとそのコメント行は変更しない)
   - 3 回の `idle_notification` 周期の段落で、`treat it as silently failed:` を `treat it as silently failed (this also covers a send that the harness accepted but did not route to this session):` に置き換える
   - `On failure:` の段落と、末尾のフォールバックファイル削除の段落は変更しない
   - SKILL.md 本文の制約: 半角の感嘆符を、コードフェンス・インラインコード・HTML コメント以外に書かない。同じ範囲の外に、`allowed-tools` に無いツール名 (`Edit` など) を裸で書かない
5. 自己検証を実行する。新しいファイルは作らない (Step 4 の後) (→ 受入条件 1, 2)
   - `grep -n 'team-lead' agents/issue-scope.md agents/issue-risk.md agents/issue-precedent.md skills/issue/SKILL.md` が、4 ファイルすべてでヒットする
   - `grep -n '\.tmp/issue-\$NUMBER-' agents/issue-scope.md agents/issue-risk.md agents/issue-precedent.md` が、各ファイルでフォールバックのパスを 1 件ずつ示す (`-scope.md` / `-risk.md` / `-precedent.md`)
   - `python3 scripts/validate-skill-syntax.py skills/`、`bash scripts/check-allowed-tools.sh`、`bash scripts/check-forbidden-expressions.sh` が成功する
   - `/code` の言語規約チェック (`skills/code/language-convention-check.md`) で、追加行に CJK 文字が無い (`agents/` はこの検査の対象外だが、同じ規約で英語だけにする)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md の Step 12a の prompt と agents/issue-scope.md・issue-risk.md・issue-precedent.md の結果の届け方が、エージェントが in-process の teammate として起動された場合にも依頼元に届く宛先を指示している (\"main\" だけに頼らない)。Step 12a の Result collection もその届け方と矛盾しない" --> 調査エージェントの結果の宛先が、teammate として起動された場合にも依頼元に届く
- <!-- verify: rubric "agents/issue-scope.md・issue-risk.md・issue-precedent.md が、宛先への送信が失敗した場合のファイルへのフォールバック (.tmp/issue-$NUMBER-*.md への Write) を引き続き指示している" --> 送信失敗時のファイルへのフォールバックが残っている

### Post-merge

- Size L/XL の Issue で `/issue` を対話セッションから実行したとき、Step 12a の 3 エージェントの結果がフォールバックのファイルを使わずに依頼元に届く <!-- verify-type: opportunistic -->

## Notes

**外部仕様の確認と出所** (Issue 本文が Spec に委ねた確認):

- `SendMessage` のツール定義: この実行で ToolSearch (`select:SendMessage`) により取得 (2026-10-13)。`to` は `"researcher"` = Teammate by name、`"main"` = The main conversation (background subagents only)、`"worker"` = ListAgents の任意のエージェント。"Messages from teammates are delivered automatically; you don't check an inbox." とあり、旧プロトコルの例に `{"to": "team-lead", ...}` がある
- 公式ドキュメント (取得日 2026-10-13)。https://code.claude.com/docs/en/agent-teams: "Claude launches a teammate when it calls the Agent tool with a `name` while agent teams are enabled, unless the call is a fork or passes `isolation` on the call itself" / "In non-interactive mode with the `-p` flag ... a subagent that Claude names runs as an ordinary subagent" / "The lead's entry always carries the agent type `team-lead`" / "Idle notifications: when a teammate finishes and stops, it automatically notifies the lead and includes its final answer in the notification"。https://code.claude.com/docs/en/sub-agents (Sibling roster): "listing `main` and every other named agent in the session, each a valid `to` value for SendMessage"
- 実機の再現はしていない。この `/spec` は headless (`--non-interactive`) で動いており、上のドキュメントによれば、headless では名前つきの Agent も通常の subagent になる。teammate から `"main"` に送った実際のエラー文面は、Issue 本文の観測 (下流の repo、2026-10-13) だけが根拠で、この実行では再現できない
- 履歴の出所: `git show f086fc18:skills/issue/SKILL.md` (#954 時点で `name:` なし)、`git show 0e932af9 -- skills/issue/SKILL.md` (#1031 が 3 つの起動へ `name=` を追加)

**設計判断と却下案**:

- 採用: 順序つきの 2 宛先 (`main` → `team-lead`) + ファイル。`main` を先にするのは、agent teams が無効な既定の環境 (名前つきでも通常の background subagent) では、今までと同じ呼び出しが最初に成功し、挙動が変わらないため。teammate では `main` が明示的なエラーで返ることが観測されており (`issue-scope`)、その後の `team-lead` の再試行が成功する。失敗の仕方が分かっている宛先を先に置き、挙動が文書だけで裏付けられた宛先を後に置いた
- 却下 (`team-lead` → `main` の順): 既定の環境での `team-lead` の失敗の仕方 (明示的なエラーか、黙って捨てられるか) が確認できず、後者なら結果を失う。1 回余分に失敗する呼び出しを、teammate 環境でだけ払うほうが安全
- 却下 (自分の起動モードを推定して宛先を選ばせる): エージェントが自分の起動のされ方を正しく推定できることに依存する。順序つきの再試行は、同じ結果を機械的に得られる
- 却下 (`name:` を外して常に background subagent にする): #1031 の `TaskStop` による停止を失う
- 却下 (`ListAgents` やチーム設定ファイルで依頼元を探させる): `ListAgents` をエージェントの `tools:` に足す必要があり、チーム設定は利用者の `~/.claude/teams/` 配下 (リポジトリの外) にある
- 却下 (最終応答・idle 通知だけに頼る): `SendMessage` のツール定義は「プレーンテキストの出力は他のエージェントから見えない」とし、#954 では idle 通知に本文が届かなかった。公式ドキュメントの「idle 通知に最終応答が含まれる」は、全ての版で成り立つとは限らないので、診断用の 1 行 (どの宛先が成功したか) にだけ使う
- 却下 (ファイルだけで配信): Post-merge の条件が「フォールバックのファイルを使わずに届く」ことを求めている
- 小さな追加: 最終応答に、成功した宛先を 1 行で書かせる。Issue の Background に「どの宛先で送ったかは確かめていない」とあり、Post-merge の opportunistic 判定と今後の切り分けで、宛先が分かる痕跡が要るため。markdown 本体の重複は書かせない (トークンの無駄)

**失敗時の挙動 (Edge cases)**:

| 状況 | 動作 |
|------|------|
| `main` で送れた | そこで止める。最終応答にその宛先を書く (markdown は繰り返さない) |
| `main` がエラー、`team-lead` で送れた | そこで止める。最終応答に `team-lead` を書く |
| 両方エラー、または `SendMessage` が使えない | `.tmp/issue-$NUMBER-*.md` に `Write` し、最終応答にパスを書く |
| `Write` も失敗 | 依頼元の既存手順 (`On failure:`) で標準の scope 評価にフォールバックする |
| 送信は受理されたが依頼元に届かない | 依頼元の 3 回の `idle_notification` 周期のタイムアウトで失敗とみなし、フォールバックファイル (無い) を確認して、標準の scope 評価にフォールバックする |
| 二重配信 | 「最初に成功した呼び出しで止める」で防ぐ |

**Issue 本文との相違 (Conflict with implementation)**: Issue 本文は `agents/issue-scope.md`・`issue-risk.md`・`issue-precedent.md` の `Deliver Results` を `### 4.` と書いているが、`issue-risk.md` は `### 5. Deliver Results` である (Risk Assessment が 4 番にあるため)。設計への影響は無く、見出しは変更しない。

**その他の判定**:

- 監査・調査型の Issue か: いいえ (既存項目の分類ではなく、配信手順の修正)
- fail-safe critical か: 該当しない (スクリプト・ゲート・バリデータではなく、LLM が実行する手順の文言)。失敗時の挙動は上の表に列挙した
- 新規テストケースの要件: 不要。LLM が実行する散文の手順で、スクリプトやモジュールの分岐を足さない。command 型の受入条件も無く、この文言を検査する既存テストも無い
- Smoke Test: 置かない。teammate の実機が必要で、`/code` の headless 実行では再現できない。Post-merge の opportunistic 条件で確認する
- 費用・不可逆なステップ: 無い (`spec-approval-needed` は不要)。外部サービスへのログインも無い
- `allowed-tools` の影響: `scripts/*.sh` の新規追加も `modules/*.md` の変更も無いので対象外。`validate-skill-syntax.py` の `KNOWN_TOOLS` に `SendMessage` / `TaskStop` は無く、本文中の言及は本文のツール名検査に掛からない
- verify command: Issue 本文が SSoT なので、Pre-merge の 2 件は逐語でコピーした (`modules/verify-patterns.md` §18)。`rubric` に補助の `file_contains` を足さないのは、Issue 本文の受入条件を `/spec` が増やさないため。同等の機械的な確認は Implementation Step 5 の grep にある
- 境界: `/review` 側の同系統の症状は #1522 で扱う。`agents/review-*.md` と `skills/review/SKILL.md` は本 Issue の対象外

**不確実性 (Uncertainty)**:

- teammate から `"main"` に送ったときの実際のエラー文面と、`risk` / `precedent` が使った宛先は未確認。影響: 手順は変わらない (エラーなら `team-lead` で再試行するため)。確認方法: Post-merge の opportunistic 条件と、エージェントの最終応答に書かせる宛先の 1 行
- `team-lead` が teammate の依頼元の宛先であることは、ツール定義の例・公式ドキュメント・Issue の観測の 3 つで裏付けたが、`/issue` の Step 12a の実機では未確認。外れた場合は、ファイルのフォールバックに倒れ、結果は失われない

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (判断の根拠: /review 側の症状は #1522 に分離。宛先の書き方と "main" の実挙動の確認は Spec に委ねる) / https://github.com/saitoco/wholework/issues/1521#issuecomment-6137388535
