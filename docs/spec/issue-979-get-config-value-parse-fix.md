# Issue #979: get-config-value: インラインコメント付き値と改行なし最終行のパースを修正

## Overview

`scripts/get-config-value.sh` の `.wholework.yml` パース処理に2つの欠陥がある。

1. インラインコメント (`always-pr: true  # comment`) の `# comment` 部分が strip されず、値に残ってしまう。
2. 末尾に改行のない最終行のキーが読み取れず、デフォルト値にフォールバックしてしまう。

両欠陥が downstream repo の `.wholework.yml` で同時発生し、(1) により `always-pr` 昇格が発動せず、(2) により `auto-stop-at` がデフォルト `verify` に落ちる実インシデントが発生した (詳細は Issue 本文 Background 参照)。本 Spec ではこの2つのパース欠陥を修正する。

## Reproduction Steps

修正前の実装に対して以下を実行すると再現する (worktree 内で実施・確認済み)。

```bash
printf 'k1: v1  # comment\nk2: v2' > /tmp/gcv-test.yml
WHOLEWORK_CONFIG_PATH=/tmp/gcv-test.yml scripts/get-config-value.sh k1
# 実際の出力: "v1  # comment" (期待値: "v1")
WHOLEWORK_CONFIG_PATH=/tmp/gcv-test.yml scripts/get-config-value.sh k2
# 実際の出力: "" (期待値: "v2"。デフォルト値未指定のため空文字にフォールバック)
```

## Root Cause

`scripts/get-config-value.sh` の値抽出ロジック (65行目付近) に起因する。

1. **インラインコメント未 strip**: 79行目の VALUE 抽出 sed チェーンは「key: 接頭辞除去」「末尾空白除去」「前後の引用符除去 (2回)」のみを行い、コメント区切りの `#` を扱う処理が存在しない。そのため `v1  # comment` のような値がそのまま返る。
2. **改行なし最終行の読み飛ばし**: 71行目 `while IFS= read -r line; do ... done < "$CONFIG_FILE"` は、`read` が最終行 (末尾改行なし) で非ゼロを返すため、ループ条件が偽になりループ本体が実行されない。`read` 自体は `$line` に最終行の内容を格納するが、ループ本体に到達しないため該当キーが処理されずデフォルト値にフォールバックする。

修正方針: (1) はキー接頭辞除去の直後に「空白1つ以上 + `#` + 行末まで」を除去する sed ステージを追加することで対応する (`#` の直前が空白の場合のみコメント開始とみなすため、`https://example.com/#section` のような URL fragment を含む値は破壊されない)。(2) はループ条件を `while IFS= read -r line || [ -n "$line" ]; do` に変更し、`read` が失敗しても `$line` が非空なら最後の1回だけループ本体を実行させる、標準的な bash イディオムで対応する。

## Changed Files
- `scripts/get-config-value.sh`: VALUE 抽出 sed チェーンにインラインコメント除去ステージを追加し、`while` ループ条件を `|| [ -n "$line" ]` 付きに変更する — bash 3.2+ compatible (`sed -E` は同スクリプトで既に使用済みの拡張正規表現フラグのみを使用し、GNU 専用機能や bash 4+ 専用機能は導入しない)
- `tests/get-config-value.bats`: インラインコメント付き値の strip、改行なし最終行のキー読み取りの回帰テストケースを追加
- `docs/structure.md`: [Steering Docs sync candidate] `get-config-value.sh` の説明が最新か確認 (使用方法・出力契約は変更されないため通常は変更不要と見込むが、`/code` で最終確認する)
- `docs/tech.md`: [Steering Docs sync candidate] 同上 (`WHOLEWORK_CONFIG_PATH` 環境変数の説明含む)
- `docs/ja/structure.md`: [Steering Docs sync candidate] 同上
- `docs/ja/tech.md`: [Steering Docs sync candidate] 同上

## Implementation Steps
1. `scripts/get-config-value.sh` の VALUE 抽出 sed チェーン (現状: キー接頭辞除去 → 末尾空白除去 → 引用符除去 → 引用符除去) の「キー接頭辞除去」の直後に `sed -E 's/[[:space:]]+#.*$//'` ステージを挿入する (→ Acceptance Criteria 1)
2. `scripts/get-config-value.sh` の `while IFS= read -r line; do` を `while IFS= read -r line || [ -n "$line" ]; do` に変更する (→ Acceptance Criteria 2)
3. `tests/get-config-value.bats` に以下2ケースの回帰テストを追加する (→ Acceptance Criteria 1, 2):
   - インラインコメント付きの値 (`k1: v1  # comment` 形式) からコメントが strip されて `v1` が返ることを検証するテスト
   - 改行のない最終行 (`printf` で末尾 `\n` なしのファイルを生成) のキーが読み取れて正しい値が返ることを検証するテスト

## Verification
### Pre-merge
- <!-- verify: command "printf 'k1: v1  # comment\nk2: v2' > /tmp/gcv-test.yml && test \"$(WHOLEWORK_CONFIG_PATH=/tmp/gcv-test.yml scripts/get-config-value.sh k1)\" = v1" --> インラインコメント付きの値からコメントが strip される
- <!-- verify: command "printf 'k1: v1  # comment\nk2: v2' > /tmp/gcv-test.yml && test \"$(WHOLEWORK_CONFIG_PATH=/tmp/gcv-test.yml scripts/get-config-value.sh k2)\" = v2" --> 改行なしの最終行のキーが読める

### Post-merge
なし

## Notes

- **/issue フェーズの Auto-Resolved Ambiguity Points を設計に反映**: Issue Retrospective コメント (2026-07-11T22:38:16Z, MEMBER) に記録された3件の自動解決判断をそのまま設計に採用した。
  1. コメント開始判定は「`#` の直前が空白または行頭」の場合のみ — 本 Spec の sed ステージ (`[[:space:]]+#.*$`) はこれに準拠し、URL fragment (`production-url` 等) を破壊しない設計とした。
  2. quote 内リテラル `#` の保護はスコープ外 — 本 Spec でも同様に対応しない (get-config-value.sh は flat kebab-case キー限定の軽量パーサであり、既存値の型に quote 内 `#` の実例がないため)。
  3. `tests/get-config-value.bats` への回帰テスト追加 — Implementation Step 3 で対応。
- 修正前の実装に対して Reproduction Steps を実際に実行し、両 AC が FAIL することを確認済み (k1 → `"v1  # comment"`, k2 → `""`)。
- `scripts/get-config-value.sh` の呼び出し元 (`run-auto-sub.sh`, `run-code.sh`, `run-review.sh` 等15箇所以上) をグレップし、パースロジックを重複実装している箇所がないことを確認した。全呼び出し元はこのスクリプトを呼ぶのみで、本 Spec のスコープはこの1ファイル + テストファイルに閉じる。
- 関連 Issue #980 の Spec (`docs/spec/issue-980-run-auto-sub-tier3-skip.md`) で「#979 は別 Issue として既にスコープ分離されており、#980 の Spec では扱わない」ことが明記されており、本 Issue との作業範囲重複がないことを相互確認済み。
- 回帰テストの入力データ形式: 既存 bats テストの慣例 (`cat > .wholework.yml << 'EOF' ... EOF` heredoc、末尾改行あり) に加え、改行なし最終行ケースは `printf` で末尾 `\n` を付けずに明示的に生成する。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 「`/issue 979 --non-interactive` の triage 判断根拠 (Type=Bug, Size=S, Value=4) と Auto-Resolve Log (コメント開始判定・quote内#スコープ外・回帰テスト追加方針の3件) を記録した Issue Retrospective」/ https://github.com/saitoco/wholework/issues/979#issuecomment-4949014017

## Autonomous Auto-Resolve Log

- **[continue execution using the existing Spec]** — reason: `/code 979 --patch --non-interactive` の Step 3 で `phase/ready` ラベルが不在であることを検出した (直前の3回の自動リトライが `auto-retry-on-fail.max_iterations: 3` を使い切って `phase/code` のまま停止していたため)。ただし `docs/spec/issue-979-get-config-value-parse-fix.md` の Spec 自体は既に存在し内容も有効だったため、Issue 本文のみへのフォールバックではなく Spec を継続利用して実装を進めた。
  - Other candidates: 中断して `/spec 979` の再実行を促す (Spec が既に有効なため不要と判断)

## Code Retrospective

### Deviations from Design
- 実装コミット (Step 8) の時点では `(closes #979)` サフィックスを付けなかった。Step 11 が要求する形式だが、実装変更はその1コミットで完結しておりコミット単位を分割する理由がなかったため、`closes #979` は本 Retrospective コミット (同じく main へ push される) のメッセージに含めることで GitHub の自動クローズ条件を満たす。

### Design Gaps/Ambiguities
- Step 9 の Behavioral Change Detection は `scripts/get-config-value.sh` が15件以上のテストファイルから参照されていることを正しく検出し、`bats tests/` フルスイート実行を要求した。直前の3回の自動リトライはこのフルスイートをバックグラウンドで起動し、完了通知を待ち続けたまま進捗せず auto-retry を使い切っていた (`.tmp/wrapper-out-979-code-patch.log` に記録)。本セッションでは同じフルスイートをフォアグラウンドで実行し、約6分47秒で正常完了した。この非対話実行時のバックグラウンド待機問題は Issue #979 のスコープ外のため、follow-up Issue #994 として起票した。
- フルスイート初回実行で `tests/run-code.bats` の auto-retry 関連テスト2件が一時的に FAIL したが、原因を追跡した結果、実装や既存テストの欠陥ではなく、対話デバッグセッション中に同一シェルへ `CODE_RETRY_COUNT` 等の環境変数が残留していたことによる汚染と判明した (`env -u CODE_RETRY_COUNT` で該当2件は PASS、かつ本Issueの変更前コミット `3c089a02` でも同一条件で同じ FAIL を再現)。クリーンな環境での再実行 (`env -u ... bats tests/`) で全1142件 PASS を確認した。

### Rework
- 上記の調査以外に実装のやり直しは発生していない。実装自体は Spec の Implementation Steps 通り一度で完了した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `bats tests/` フルスイートはフォアグラウンドで実行した (バックグラウンド化すると headless 実行で完了通知が届かず無限待機になるため。follow-up #994 参照)。
- 実装コミット単体には `closes #979` を含めず、本 Retrospective コミットの方に含めた (両方とも同じ push で main に反映されるため、GitHub 側の自動クローズ条件は満たされる)。

### Deferred Items
- headless (`--non-interactive`) 実行時のフルスイート実行ガイダンス整備は follow-up #994 に委譲した。

### Notes for Next Phase
- 本 Issue はパッチルート (直接 main コミット) のため `/review` フェーズは走らない。`/verify` フェーズでは AC の2つの verify command (`get-config-value.sh k1`/`k2`) が引き続き PASS することを確認すればよい。
- `tests/run-code.bats` の auto-retry 関連テストで FAIL が再現した場合、まず環境変数 (`CODE_RETRY_COUNT` 等) の残留汚染を疑うこと — 本 Issue の実装とは無関係な既知の偽陽性パターンである。

