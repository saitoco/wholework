# Issue #1088: observation: 設定依存の既存 observation AC に config= を付与しゲートを実効化

## Overview

#1026 が導入した `verify-type: observation` の `config=<key>` ゲート (観察条件が `.wholework.yml` の真偽値設定に依存する場合、その設定が無効なリポジトリではマッチ対象から除外する仕組み) は実装・ドキュメント・テストとも完了しているが、既存の observation AC には 1 件も `config=` が付与されておらず、ゲートの適用対象が 0 件のままだった。

本 Issue では、`config=` ゲートが実際に作用するよう既存 observation AC を横断監査して該当するものに属性を付与し (Proposal A)、今後の新規 AC で同じ負債が積み上がらないよう `modules/verify-classifier.md` にガイドラインを追記する (Proposal B)。

横断監査はコードベース調査 (本 Spec 作成時) の時点で実施済み。対象は `phase/verify` ラベルを持つ **CLOSED** Issue (Issue 本文が前提としていた「open Issue」とは異なる — 詳細は Notes 参照) で、未チェックの `verify-type: observation` AC を持つもの。結果、`.wholework.yml` の真偽値設定に一意に依存すると明記されているのは **#797 (`always-pr`) のみ**であることが判明した。

## Changed Files

- `modules/verify-classifier.md`: `### observation Type: Event Values and Syntax` 節に `config=` 属性のガイドラインサブセクションを追加
- Issue #797 body (GitHub メタデータ、リポジトリファイルではない): post-merge observation AC 行に `config=always-pr` を追記

## Implementation Steps

1. `modules/verify-classifier.md` の `### observation Type: Event Values and Syntax` 節、「Syntax note」段落の直後・`### Tag Assignment Example` の直前に、観察条件が `.wholework.yml` の真偽値設定に依存する場合は `config=<key>` 属性を付与する旨のガイドラインサブセクションを追加する。内容は以下を含める: (a) `config=` の記法例 (`<!-- verify-type: observation event=auto-run config=always-pr -->`)、(b) 付与しない場合に起きる問題 (設定が存在しないリポジトリでも無条件マッチし notification コメントが蓄積する)、(c) `<key>` の制約 (flat kebab-case、真偽値比較のみ。ネストキー・enum 値キーは対象外)、(d) `modules/observation-trigger.md` § Condition Check Gate (`config=`) への参照 (→ acceptance criteria 3, 4)
2. Issue #797 の post-merge AC 行に `config=always-pr` を追記する: `gh issue view 797 --json body --jq .body` で現在の本文を取得し、`<!-- verify-type: observation event=auto-run -->` という部分文字列が本文中に厳密に 1 回だけ出現することを確認した上で (出現しない場合はエラー終了し、本文を書き戻さない)、`<!-- verify-type: observation event=auto-run config=always-pr -->` に置換し、`.tmp/issue-body-797.md` に書き出してから `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh 797 .tmp/issue-body-797.md` で更新する (→ acceptance criteria 2)
3. 本 Spec の Notes に記録した横断監査結果 (対象範囲・手法・マッチした Issue 一覧・#797 が唯一の該当という結論) を `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh` で Issue #1088 のコメントとして投稿する (→ acceptance criteria 1)

## Verification

### Pre-merge

- <!-- verify: rubric "verify-type: observation を含む既存 Issue の横断監査が実施され、観察条件が .wholework.yml の真偽値設定に依存する AC が特定されている (監査結果が Issue コメントまたは Spec に記録されている)" --> 既存 observation AC の横断監査が実施されている
- <!-- verify: rubric "Issue #797 の post-merge observation AC 行に config=always-pr 属性が付与されている (gh issue view 797 で確認できる)" --> #797 の observation AC に `config=always-pr` が付与されている
- <!-- verify: grep "config=" "modules/verify-classifier.md" --> 設定依存の観察条件に `config=` を付与する旨がガイドラインに追記されている
- <!-- verify: rubric "modules/verify-classifier.md または skills/issue/SKILL.md に、観察条件が .wholework.yml の特定設定に依存する場合は config=<key> を付与する旨のガイドラインが明記されている" --> 新規 AC 向けのガイドラインが定義されている

### Post-merge

- `config=` を付与した AC が、設定無効な本リポジトリの `/auto` 実行で observation scan の対象から除外され notification コメントが蓄積しなくなることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

### 実装との齟齬: 横断監査のスコープ (「open Issue」対「closed + phase/verify」)

Issue 本文の `## Auto-Resolved Ambiguity Points` は横断監査のスコープを「open Issue のみ」と定めていた (reason: 「`observation-trigger.sh --event auto-run` が実際に notification コメントを投稿する対象は稼働中 (open) の Issue であり、実測ケース #797 も open」)。しかしコードベース調査の結果、この前提は実装と食い違うことが判明した:

- `scripts/opportunistic-search.sh` L123: `gh issue list --label "phase/verify" --state closed --json number --limit 50` — 実際の走査対象は **CLOSED** Issue のみ
- `modules/observation-trigger.md` も「Fetches Issues in `phase/verify` (closed)」と明記
- `skills/verify/SKILL.md` L482 付近: unchecked な observation/opportunistic/manual 条件が残る場合は `phase/verify` ラベルを付与するが Issue state は変更しない (通常は PR マージ時の `closes #N` で既に CLOSED になっている)
- #797 自体、調査時点で `state: CLOSED` — 「open」という前提は事実と異なる

**解決 (non-interactive mode 自動解決、SPEC_DEPTH=light につき Notes 記載のみ)**: 横断監査は「`phase/verify` ラベル + CLOSED」の Issue を対象とする (`opportunistic-search.sh` の実際のゲート走査対象と一致させる)。Issue 本文の Acceptance Criteria 自体は監査スコープを「open」と明記していない (曖昧ポイントセクションのみの記載であり AC 本文は「既存 Issue の横断監査」とだけ書かれている) ため、AC 文言との矛盾はない。

### 横断監査の結果 (Proposal A)

**手法**: `gh issue list --state all --search "verify-type: observation in:body"` で全文検索した上で `phase/verify` ラベル + CLOSED (30件) に絞り込み、各 Issue 本文を `grep -n '\- \[ \].*verify-type: observation'` で走査して未チェックの AC 行のみを抽出した。

**結果**: 21 件の未チェック `verify-type: observation` AC 行が 20 Issue に分散 (#627 のみ 2 件保有)。該当 Issue: #1026, #667, #797, #1035, #1006, #1037, #885, #1009, #841, #839, #627 (×2), #984, #589, #476, #908, #802, #995, #713, #624, #626。

このうち、観察条件の文言が `.wholework.yml` の真偽値設定に一意に依存すると明記しているのは **#797 (`always-pr: true` 設定下で...) のみ**。他 19 件はいずれも「次回の `/auto`/`/review --full` 実行で X を観察する」という時間・イベント駆動の条件であり、特定の config key への言及がないため `config=` 付与の対象外と判断した。

**参考 (本 Issue のスコープ外の傍論的発見)**: #627 (`event=concurrent-batch`, `event=batch-resume`) と #908 (`event=code-pr-run`) は `modules/verify-classifier.md` の `KNOWN_EVENTS` (`pr-review-full`/`pr-review-light`/`auto-run`/`watchdog-kill`/`fix-cycle`) に存在しない event 名を使用しており、本来は unknown event fallback (`opportunistic` 扱い) に該当するはずである。`config=` ゲートとは無関係の別問題のため本 Issue では対応せず、follow-up Issue 化の候補として記録するに留める。

### #952 との関係

Out of Scope に記載の通り、observation scan の dispatch fan-out 制御 (#952) とは独立。本 Issue は「どの AC がゲート対象になるか」という設定側、#952 は「マッチした Issue 群をどう dispatch するか」という実行側であり競合しない。
