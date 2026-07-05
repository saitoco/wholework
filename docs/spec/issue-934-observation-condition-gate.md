# Issue #934: verify: observation イベントの粒度を細分化し無駄な SKIP dispatch を削減

## Consumed Comments

- `saito` (MEMBER, first-class) — Issue Retrospective (`/issue` phase Auto-Resolve Log): Option B (`observation-trigger.sh`/`opportunistic-search.sh` への条件チェックゲート追加) を Option A (細粒度イベント名の追加) より優先する判断。理由: `opportunistic-search.sh` は既に `verify-type: observation`/`event=` のテキストマッチングでフィルタ済みであり、条件充足チェックの追加は既存の grep ベース仕組みの自然な延長。細粒度イベント方式は `modules/observation-trigger.md` に明記された3ステップ (`KNOWN_EVENTS` 追加・emitter table 追加・emitter 配線) を条件パターンごとに繰り返すことになり、組み合わせ爆発を招きやすい。最終設計判断は `/spec` に委ねる、との記載あり。([コメント](https://github.com/saitoco/wholework/issues/934#issuecomment-4886132273))

## Overview

`verify-type: observation event=X` 型の Acceptance Criteria は、指定イベントが発火するたびに `opportunistic-search.sh --event X` が全 `phase/verify` (closed) Issue を横断検索し、対象条件が実際に成立しているかに関わらず無条件でマッチ・dispatch する。Issue #794 では `event=pr-review-full` が2026-06-28〜07-05の間に8回発火し、うち7回は対象 Spec に enum 定義がなく SKIP と判定されるまで `/verify` dispatch のラウンドトリップが繰り返された (詳細: `docs/spec/issue-794-review-enum-coverage-check.md` `## Verify Retrospective`)。

本 Issue では、`scripts/opportunistic-search.sh` / `scripts/observation-trigger.sh` に軽量な条件チェックゲートを追加する。observation AC タグに任意の `keyword=<値>` 属性を追加できるようにし、呼び出し側が `--context-file <path>` でコンテキストファイル (例: 直近レビュー対象の Spec) を渡した場合のみ、そのファイル内容に `keyword` が含まれる Issue だけを dispatch 対象として絞り込む。`keyword=` 属性がない、または `--context-file` が指定されていない場合は既存動作 (無条件マッチ) を維持し、後方互換性を保つ。

Auto-Resolved Ambiguity (Issue 本文 / Issue Retrospective で確認済み): 細粒度イベント名の追加 (Option A) ではなく、既存スクリプトへの条件チェックゲート追加 (Option B) を採用する。既存の `opportunistic-search.sh` の grep ベース仕組みを自然に拡張でき、条件パターンごとに新規イベント名を増やす組み合わせ爆発を回避できるため。

なお、本 Issue のスコープは条件チェックゲートの汎用機構自体の実装に限定する。実際の呼び出し元 (例: `/review` SKILL.md の `observation-trigger.sh --event pr-review-full` 呼び出しに実 Spec を `--context-file` として渡す配線) は対象外とし、Triage 時点で Size M (script + module + bats テストの3ファイル規模) と見積もられている範囲に従う。実配線は自然なフォローアップとして残す。

## Changed Files

- `scripts/opportunistic-search.sh`: `--context-file <path>` 引数の追加と、event モードでの `keyword=` 条件チェックゲートの実装 (bash 3.2+ 互換)
- `scripts/observation-trigger.sh`: `--context-file <path>` 引数の追加と `opportunistic-search.sh` への転送 (bash 3.2+ 互換)
- `modules/observation-trigger.md`: `keyword=` AC 属性構文、`--context-file` 引数、設計判断根拠 (Option B 採用理由) のドキュメント化
- `tests/opportunistic-search.bats`: `keyword=` ゲートのテストケース追加 (マッチ / 不一致 / 後方互換 / context-file 未指定)
- `tests/observation-trigger.bats`: `--context-file` 転送のテストケース追加

## Implementation Steps

1. `scripts/opportunistic-search.sh`: `--context-file <path>` の CLI 引数パースを追加 (`--event` と同様、値省略時はエラー終了)。パース後、`--context-file` が指定されているがパスが存在しない場合は stderr に警告を出し `CONTEXT_FILE` を空にリセット (ゲート無効化、フィルタなしにフォールバック)。既存の event モードマッチングループ (`for N in $ISSUE_NUMBERS` → `while IFS= read -r line` 内) で、各マッチ行を JSON エントリ化する直前に、`grep -oE 'keyword=[^ >]+'` で行から `keyword=<値>` 属性を抽出 (`keyword=` プレフィックスを除去)。keyword が抽出でき、かつ `CONTEXT_FILE` が設定されている場合、`grep -qi -- "$KEYWORD" "$CONTEXT_FILE"` が失敗したらその行を `continue` でスキップする。`keyword=` 属性がない行、または `--context-file` 未指定の実行では、現状と同じく無条件でマッチに含める (後方互換)。 (→ acceptance criteria A)
2. `scripts/observation-trigger.sh`: `--context-file <path>` の CLI 引数パースを追加 (Step 1 と同じパターン)。設定されている場合、`opportunistic-search.sh --event "$EVENT_NAME"` 呼び出しに `--context-file "$CONTEXT_FILE"` を追加して転送する。 (after 1) (→ acceptance criteria A)
3. `modules/observation-trigger.md`: 「Condition Check Gate (`keyword=`)」サブセクションを Trigger Interface 配下に追加。内容: (a) `<!-- verify-type: observation event=<name> keyword=<text> -->` タグ拡張構文の説明、(b) 両スクリプトの Arguments テーブルに `--context-file <path>` 行を追加、(c) マッチング仕様 (`CONTEXT_FILE` 内容に対する大文字小文字を区別しない部分一致。`keyword=` 属性がない場合・`--context-file` 未指定の場合・指定パスが存在しない場合はいずれもゲート無効 = 無条件マッチ)。さらに `## Notes` に、新規 `KNOWN_EVENTS` 追加 (3ステップ: `KNOWN_EVENTS` 追加・emitter table 追加・emitter 配線) と比較した軽量な代替手段である旨を1文で追記する。 (parallel with 1, 2) (→ acceptance criteria B)
4. `tests/opportunistic-search.bats`: 以下のテストケースを追加: (a) AC が `event=pr-review-full keyword=enum` を持ち、`--context-file` が指す fixture ファイルに "enum" を含む → Issue がマッチに含まれる、(b) 同 AC で fixture ファイルに "enum" を含まない → マッチから除外 (空配列)、(c) `keyword=` 属性を持たない AC で `--context-file` 指定時も従来通りマッチに含まれる (後方互換)、(d) `keyword=` 属性を持つ AC で `--context-file` 未指定時はゲート非適用でマッチに含まれる。fixture ファイルは `$BATS_TEST_TMPDIR` 配下のプレーンテキストファイルとして作成する。 (after 1) (→ acceptance criteria A)
5. `tests/observation-trigger.bats`: モックの `opportunistic-search.sh` を拡張し、受け取った引数を (既存の `gh` モックの call-log パターンに倣って) ログファイルへ記録するようにする。その上で、`observation-trigger.sh` に渡した `--context-file <path>` が、モックされた `opportunistic-search.sh` 呼び出しへそのまま転送されることを確認するテストケースを追加する。 (after 2) (→ acceptance criteria A)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/observation-trigger.sh または scripts/opportunistic-search.sh に、対象条件が成立しない場合の無駄な /verify dispatch を減らす仕組み (条件チェックゲート or 細粒度イベント) が追加されている" --> `scripts/observation-trigger.sh` または `scripts/opportunistic-search.sh` に、無関係な SKIP dispatch を削減するための条件チェックまたは細粒度イベントの仕組みが実装されている
- <!-- verify: rubric "modules/observation-trigger.md に、対象条件充足を考慮したイベント設計に関する記述が追加されている" --> 上記設計が `modules/observation-trigger.md` にドキュメント化されている

### Post-merge

なし

## Notes

- Steering Docs sync candidate 確認済み: `docs/structure.md` (および `docs/ja/structure.md`) は `scripts/observation-trigger.sh` / `scripts/opportunistic-search.sh` / `modules/observation-trigger.md` の1行説明を既に含むが、いずれも本変更後も内容の正確性に影響なし (説明文の粒度が「dispatch 契約」レベルであり `keyword=` ゲート追加で陳腐化しない)。更新不要と判断 (grep で該当2ファイルの記載を確認済み)。
- `docs/migration-notes.md` (および `docs/ja/migration-notes.md`) にも `opportunistic-search.sh` の記載があるが、private→public 移行時点の英語化チェックリストとしての凍結済み履歴記録であり、今回の変更対象外。
- スコープ境界: 本 Issue は条件チェックゲートの汎用機構を実装するのみ。`/review` SKILL.md 等の実際の呼び出し元を `--context-file` 付きで配線する対応は含まない (Triage Size M = script + module + bats テストの3ファイル規模、との整合)。
- `keyword=` の抽出・比較は大文字小文字を区別しない (`grep -qi`) 単純な部分一致とし、意味的な条件評価 (LLM 判定) は行わない。厳密な判定は引き続き `/verify` 本体が担う。既存の `event=` 未知イベント時のフォールバック処理 (opportunistic 扱いへの後退) とは独立した経路であり、干渉しない。

## Auto Retrospective
### Orchestration Anomalies
- **[json-mode-silent-hang]** Tier 2 fallback applied: phase=`code-pr`, action=run-code.sh-pr-retry, result=recovered.

### Improvement Proposals
- N/A (resolved by Tier 2 fallback catalog)

## Code Retrospective

### Deviations from Design
- N/A (Implementation Steps 1〜5 をそのまま実装)

### Design Gaps/Ambiguities
- N/A

### Rework
- `scripts/observation-trigger.sh` で当初 `CONTEXT_FILE_ARGS=(--context-file "$CONTEXT_FILE")` という配列展開で `opportunistic-search.sh` への引数転送を実装したところ、macOS 標準の bash 3.2 では `set -u` 下で空配列を `"${arr[@]}"` 展開すると `unbound variable` エラーになる既知の挙動があり、既存 bats テスト (`observation-trigger.bats`) が軒並み FAIL した。配列を使わず `if [ -n "$CONTEXT_FILE" ]; then ... else ... fi` の分岐で明示的に2パターンのコマンドを呼び分ける実装に書き換えて解消。Spec の Implementation Steps には "bash 3.2+ 互換" と明記されていたが、具体的な落とし穴 (空配列 + `set -u`) までは記載がなかったため、実装時に手戻りが発生した。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Light モード (Size M) のため review-light エージェント1体で4観点 (Spec乖離/エッジケース/セキュリティ/ドキュメント整合性) を統合レビュー。Pre-merge AC 2件は両方とも `verify-type: rubric` で PASS 判定
- SHOULD 指摘2件 (keyword抽出の末尾ダッシュ処理、Arguments テーブル未更新) は影響が小さく安全に直せる内容だったため修正。CONSIDER 指摘1件 (`grep -qi` の正規表現扱い) は reviewer 自身が「本PRでは対応不要」と明記していたためスキップ
- ドキュメント指摘の PR インラインコメントは、当初の指摘行 (既存の一次 Arguments テーブル、diff 範囲外) では GitHub API が解決できず 422 エラーとなったため、diff に含まれる新規追加行に付け替えて投稿 (詳細は review retrospective 参照)

### Deferred Items
- `scripts/opportunistic-search.sh:148` の `grep -qi` が `$KEYWORD` を正規表現として扱う件 (CONSIDER) は本PRでは未対応。将来 `keyword=` に正規表現メタ文字を含む値が使われる場面が出てきた場合のフォローアップとして残す
- 実際の呼び出し元 (`/review` SKILL.md 等) への `--context-file` 配線は Spec のスコープ境界どおり本 Issue に含めていない (code フェーズからの引き継ぎ事項、変更なし)

### Notes for Next Phase
- CI は全ジョブ SUCCESS (DCO, bats tests ×2, skill syntax ×2, forbidden expressions ×2, macOS shell compatibility ×2)。マージ時に追加の懸念事項なし
- レビュー中に追加した bats テストケース1件を含め、計33ケース PASS (bash 3.2.57 ローカル確認込み)

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — 実装は Spec の Implementation Steps 1〜5 に厳密に沿っており、両 AC (rubric 判定) とも PASS。diff の範囲 (`docs/structure.md` 更新不要判断など) も Spec Notes の判断と一致していた。

### Recurring issues

review-light エージェントが指摘した「ドキュメント不整合」(既存の一次 Arguments テーブルが更新されていない) について、PR インラインコメント投稿時に `gh-pr-review.sh` が `422 Line could not be resolved` で失敗した。原因は、指摘対象行 (`modules/observation-trigger.md:26`) が今回の diff に含まれない pre-existing 行だったため。GitHub の Review API は diff hunk に含まれる行にしかインラインコメントを付けられない制約があり、「既存箇所の未更新」を指摘するレビューコメントは、diff 内の関連する新規追加行 (今回は新設された「Arguments table addition」セクションの行) に付け替えることで解決した。

この失敗パターンは今後も起こりうる: レビューエージェントが「既存箇所を更新すべきだった」という趣旨の指摘をする場合、指摘対象行がしばしば diff の外側 (変更されていない箇所) になる。`/review` の Step 10 統合フェーズで、レビューエージェントの出力する `path`/`line` が実際に diff のハンク範囲内かを事前チェックし、範囲外の場合は diff 内の関連行に自動的に付け替えるか、`path: null` の General Comments 扱いにフォールバックする仕組みがあると、`gh-pr-review.sh` の 422 エラーによる手戻りを削減できる可能性がある。

### Acceptance criteria verification difficulty

Nothing to note — 両 AC とも `verify-type: rubric` で明確に判定でき、UNCERTAIN は発生しなかった。
