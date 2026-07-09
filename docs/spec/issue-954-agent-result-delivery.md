# Issue #954: agents: issue-scope/issue-risk/issue-precedent の調査結果配信失敗を修正 (Write/SendMessage 未付与)

## Overview

`/issue` Step 12a で並列起動する `issue-scope` / `issue-risk` / `issue-precedent` の 3 エージェントは、調査自体は完了するものの、結果を team-lead (呼び出し元セッション) へ配信する手段を持たない。3 エージェントの `tools:` frontmatter に `SendMessage` (能動送信の主経路) と `Write` (到達性フォールバック用ファイル出力) を追加し、`skills/issue/SKILL.md` Step 12a に両経路を明記する。

## Reproduction Steps

1. Size=XL の Issue に対して `/issue` を実行し、Step 12a で `issue-scope` / `issue-risk` / `issue-precedent` の 3 エージェントをバックグラウンドサブエージェントとして並列起動する。
2. 3 エージェントとも調査 (Processing Steps) を完了し、idle 状態になる。
3. team-lead 側では完了シグナル (`idle_notification`) は複数回受信できるが、エージェントの Output Format markdown 本文は一度も届かない。
4. team-lead から `SendMessage` で明示的にレポート送信を依頼しても、エージェント側は `SendMessage` ツールを持たないため応答できず、再び idle になるだけで終わる。

## Root Cause

`agents/issue-scope.md` / `agents/issue-risk.md` / `agents/issue-precedent.md` の `tools:` frontmatter はいずれも読み取り専用ツール (`Read, Glob, Grep[, Bash(git log:*, git diff:*)]`) のみに限定されている。

`SendMessage` ツールの実際の schema (ToolSearch で確認) によれば、バックグラウンドサブエージェントが親セッションへメッセージを届ける手段は `SendMessage({to: "main", message, summary})` の能動呼び出しのみであり、"Messages from teammates are delivered automatically; you don't check an inbox" とある通り、team-lead 側からのポーリングでは代替できない。3 エージェントはこのツールを持たないため、Output Format markdown を生成しても呼び出し元に届ける経路が構造的に存在しない。`Write` によるフォールバック (team-lead が既知パスを `Read` する経路) も同様に付与されていない。

`skills/issue/SKILL.md` Step 12a 自体も、エージェント起動 (`Task(...)`) のみを記述し、結果をどう回収するかを明記していない。これが実際の障害 (tofas リポジトリでの `/issue 250` 実行時) に直結した。

## Changed Files

- `agents/issue-scope.md`: `tools:` frontmatter に `SendMessage, Write` を追加し、「Deliver Results」ステップを追加
- `agents/issue-risk.md`: 同様の変更
- `agents/issue-precedent.md`: 同様の変更
- `skills/issue/SKILL.md`: Step 12a の `Task(...)` プロンプトに配信手順を追加し、team-lead 側の受信待ち・フォールバック手順を明記

## Implementation Steps

1. `agents/issue-scope.md` を更新する (→ acceptance criteria 1, 2):
   - 4 行目 `tools: Read, Glob, Grep, Bash(git log:*, git diff:*)` を `tools: Read, Glob, Grep, Bash(git log:*, git diff:*), SendMessage, Write` に変更
   - `### 3. Dependency Mapping` の直後に `### 4. Deliver Results` サブセクションを追加し、以下を記載:
     - **Primary**: Output Format markdown 生成後、`SendMessage({to: "main", message: <Output Format markdown 全文>, summary: "<5-10 words>"})` を呼び出して team-lead へ配信する
     - **Fallback**: `SendMessage` が使用不可またはエラーになった場合、同じ markdown を `Write` で `.tmp/issue-$NUMBER-scope.md` に書き出し、最終応答テキストにそのパスを明記する

2. `agents/issue-risk.md` を更新する (→ acceptance criteria 3, 4):
   - 4 行目 `tools: Read, Glob, Grep` を `tools: Read, Glob, Grep, SendMessage, Write` に変更
   - `### 4. Risk Assessment` の直後に `### 5. Deliver Results` サブセクションを追加し、Step 1 と同一パターン (fallback パスは `.tmp/issue-$NUMBER-risk.md`) を記載

3. `agents/issue-precedent.md` を更新する (→ acceptance criteria 5, 6):
   - 4 行目 `tools: Read, Glob, Grep` を `tools: Read, Glob, Grep, SendMessage, Write` に変更
   - `### 3. Pattern Analysis` の直後に `### 4. Deliver Results` サブセクションを追加し、Step 1 と同一パターン (fallback パスは `.tmp/issue-$NUMBER-precedent.md`) を記載

4. `skills/issue/SKILL.md` の `#### Step 12a: Parallel Investigation (Scope / Risk / Precedent Agents)` (Task ブロックは現状 481〜488 行目付近) を更新する (→ acceptance criteria 7, 8):
   - 3 つの `Task(...)` プロンプト文字列それぞれに、対応する fallback パス (`.tmp/issue-$NUMBER-scope.md` / `.tmp/issue-$NUMBER-risk.md` / `.tmp/issue-$NUMBER-precedent.md`) を明示した配信指示を追記する。例:
     ```text
     Task(subagent_type="issue-scope", description="Scope investigation",
       prompt="Issue=$NUMBER, Steering Documents=$STEERING_DOCS_FILES, Issue body=<full text>. Deliver your Output Format markdown via SendMessage(to=\"main\") on completion; if SendMessage is unavailable or fails, Write it to .tmp/issue-$NUMBER-scope.md instead and state the path in your final response.")
     ```
     (issue-risk / issue-precedent も同様に、対応する fallback パスで追記する)
   - `Task(...)` ブロックの直後に「Result collection」段落を追加する: `SendMessage` によるテキストは自動配信される (team-lead 側のポーリングは不要) ため、3 エージェントすべてからのメッセージ受信を待ってから Step 12b に進む。あるエージェントからのメッセージが届かない場合 (エラー終了など) は、そのエージェントに対応する `.tmp/issue-$NUMBER-{scope|risk|precedent}.md` を `Read` して代替回収する
   - 既存の「On failure: fall back to standard scope assessment.」の一文は、`SendMessage` 配信と `Write` フォールバックの両方が失敗した場合の条件として維持する

## Verification

### Pre-merge
- <!-- verify: file_contains "agents/issue-scope.md" "SendMessage" --> `issue-scope` agent の `tools:` frontmatter に `SendMessage` (調査結果配信の主経路) が追加されている
- <!-- verify: file_contains "agents/issue-scope.md" "Write" --> `issue-scope` agent の `tools:` frontmatter に `Write` (配信失敗時のフォールバック用ファイル出力) が追加されている
- <!-- verify: file_contains "agents/issue-risk.md" "SendMessage" --> `issue-risk` agent の `tools:` frontmatter に同様の追加がされている (`SendMessage`)
- <!-- verify: file_contains "agents/issue-risk.md" "Write" --> `issue-risk` agent の `tools:` frontmatter に同様の追加がされている (`Write`)
- <!-- verify: file_contains "agents/issue-precedent.md" "SendMessage" --> `issue-precedent` agent の `tools:` frontmatter に同様の追加がされている (`SendMessage`)
- <!-- verify: file_contains "agents/issue-precedent.md" "Write" --> `issue-precedent` agent の `tools:` frontmatter に同様の追加がされている (`Write`)
- <!-- verify: rubric "skills/issue/SKILL.md の Step 12a が、3 エージェントに調査結果を SendMessage で team-lead へ能動送信させる手順を主経路として明記し、かつ SendMessage が届かない場合に team-lead が Write 出力ファイル (.tmp/ 配下の既知パス) を Read して回収するフォールバック手順を明記している" --> `/issue` SKILL.md Step 12a に SendMessage 優先・Write フォールバックの結果配信手順が明記されている
- <!-- verify: section_contains "skills/issue/SKILL.md" "#### Step 12a" "SendMessage" --> Step 12a セクションに `SendMessage` に関する記述が含まれる (rubric の機械的な安全網)

### Post-merge
- 実際に Size=XL の Issue で `/issue` を実行し、3 エージェントの調査結果が手動介入なしに (SendMessage 経由、または未達時は Write+Read フォールバック経由で) 回収できることを確認する

## Notes

- **外部仕様確認**: `SendMessage` は Claude Code ハーネス内蔵ツールであり公開 API ドキュメントは存在しないため、`modules/external-spec.md` の WebFetch/WebSearch 手順ではなく ToolSearch で実際の tool schema を取得して仕様を確認した (`to: "main"` — バックグラウンドサブエージェントが親セッションへ届ける唯一の経路。"Messages from teammates are delivered automatically" — team-lead 側のポーリングは不要かつ非対応)。
- **Steering Docs sync candidate 調査**: `skills/issue/SKILL.md` を変更対象に含むため、キーワード `issue` で `docs/*.md` / `docs/ja/*.md` を grep したが、"issue" は汎用語のため全 steering doc (8 件) にヒットし信号にならなかった (scope: `docs/*.md`, `docs/ja/*.md` 全体、除外なし)。代わりにエージェント名 (`issue-scope` / `issue-risk` / `issue-precedent`) で `docs/workflow.md` と `README.md` を個別に grep したが 0 件だった (scope: `docs/workflow.md`, `README.md` の全文)。`docs/structure.md` の Agents 表は description のみを記載し tools 列を持たないため更新不要。以上より Steering Docs sync candidate なしと判断した。
- **スコープ**: Issue #954 の Auto-Resolved Ambiguity Points により、本 Spec の対象は `issue-scope` / `issue-risk` / `issue-precedent` の 3 エージェントに限定する。`agents/review-bug.md` 等の同種パターンを持つ他エージェントの横断監査は対象外 (別 Issue で扱う)。
