# Issue #1099: observation-trigger: advisory コメントの重複投稿を防ぐ冪等性ガードを追加

## Overview

`scripts/observation-trigger.sh` は同一 `--event` を短時間に複数回実行されると、matched Issue ごとに毎回新規の advisory コメントを無条件投稿してしまう。実例 (session `25766-1785288928`) では `observation-trigger.sh --event auto-run` が意図せず3回実行され、11 件の Issue に同一コメントが3通ずつ投稿された。

本 Issue では、(1) 投稿前に同一 `event`・同一 Issue の advisory コメントが直近 24 時間以内に既に存在するかを確認し、存在すればコメント投稿をスキップする冪等性ガードを追加し、(2) `gh issue comment` 呼び出しの標準出力 (コメント URL) を抑制して呼び出し元の `$(...)` キャプチャが URL 行と Issue 番号行の混在で壊れないようにする。

## Reproduction Steps

1. 少なくとも1件の Issue が、未チェックの `verify-type: observation event=<name>` AC を持つ状態で `scripts/observation-trigger.sh --event <name>` を実行する。
2. 同じ `event` で、間を置かずに同スクリプトを再実行する (例: stdout の出力形式を確認する目的で再実行、あるいは複数 emitter や `--batch` 処理が短時間に同一 event を発火)。
3. 実行のたびに、matched Issue 全件へ重複排除なしで新規 advisory コメントが投稿される — N 回実行すれば Issue ごとに N 通の重複コメントが残る (参照実例では 3 回実行 × 11 Issue = 33 件の重複コメント)。
4. 加えて、呼び出し元が `$(...)` で stdout をキャプチャすると、`gh issue comment` 自身が標準出力に出すコメント URL 行と、スクリプト末尾の Issue 番号一覧行が混在する (`scripts/observation-trigger.sh:79` は `2>/dev/null` で標準エラーのみ抑制しており、標準出力は無抑制)。

## Root Cause

- `for N in $NUMBERS; do ... done` ループ (`scripts/observation-trigger.sh:78-80`) には投稿前の重複チェックが一切なく、スクリプトを呼ぶたびに matched Issue 全件へ無条件で新規コメントが追加される。過去の投稿履歴と照合する仕組みが存在しない。
- `gh issue comment "$N" --body "..." 2>/dev/null || true` (行 79) は標準エラーのみを抑制しており、`gh issue comment` がデフォルトで標準出力に書き出すコメント URL は抑制されない。これが Background に記載された「stdout に URL と Issue 番号が混在する」症状の直接の技術的原因である。
- 修正方針の妥当性: 投稿直前にマーカー付きコメントの existence + 経過時間をチェックするスキップ判定を追加すれば、スクリプトの外部契約 (stdout の形状、呼び出しインターフェース) を変えずに重複投稿症状を解消できる。`gh issue comment` 呼び出しに `>/dev/null` を追加すれば、stdout 混在症状をその発生源で直接解消できる。

## Changed Files

- `scripts/observation-trigger.sh`: 冪等性ガード (マーカーベース、24時間ウィンドウ) を追加、投稿コメント本文に machine-readable マーカーを埋め込み、`gh issue comment` の標準出力を抑制、ヘッダコメントに stdout 出力形式を明記 — bash 3.2+ 互換
- `tests/observation-trigger.bats`: `gh` モックをサブコマンド分岐 (`issue view` / `issue comment`) に拡張し、冪等性スキップ・ウィンドウ期限切れ・stdout hygiene・マーカー形式の新規テストケースを追加
- `modules/observation-trigger.md`: 冪等性ガード (マーカー形式・24時間ウィンドウ・`phase=observation-trigger` 採用理由) をドキュメント化。既存の「unconditional」記述 (メイン説明部・`/auto` dispatch cap 節) を更新 — Steering Docs sync candidate (本スクリプトの SSoT 設計ドキュメント)
- `docs/guide/customization.md`: `observation-dispatch-threshold` 行の「(existing `observation-trigger.sh` behavior, unconditional)」記述を更新 — Steering Docs sync candidate (grep で `unconditional` の記述箇所として確認済み)
- `docs/ja/guide/customization.md`: 同上、日本語ミラー — `docs/translation-workflow.md` の同期対象

## Implementation Steps

1. `scripts/observation-trigger.sh` を修正する (→ acceptance criteria 1, 2, 3, 4):
   - `for N in $NUMBERS; do ... done` ループ内、`gh issue comment` 呼び出しの直前に冪等性ガードを追加する。分岐を漏れなく列挙する:
     - **マーカー未検出** (`MARKER_TS` が空): `SKIP=false` のまま → 従来どおりコメント投稿
     - **マーカー検出、日時変換失敗** (BSD `date -j` / GNU `date -d` の両方が失敗する異常系): `SKIP=false` のまま (fail-open。本スクリプトの既存方針「エラーは non-fatal」を踏襲) → コメント投稿
     - **マーカー検出、日時変換成功、経過時間 ≥ 86400 秒 (24時間)**: `SKIP=false` → コメント投稿 (ウィンドウ期限切れ)
     - **マーカー検出、日時変換成功、経過時間 < 86400 秒**: `SKIP=true` → コメント投稿をスキップ。`$N` は `$NUMBERS` から除外されない (`NUMBERS` はループ開始前に確定済みの変数であり、ループ内のスキップ判定はこの変数に影響しない) ため、末尾の `echo "$NUMBERS"` は変更不要
   - 実装イメージ (bash 3.2+ 互換、配列展開は使用しない — 空配列 + `set -u` で `unbound variable` になる既知の落とし穴 (#934 retrospective) を避けるため if/else の明示分岐のみ使用):
     ```bash
     for N in $NUMBERS; do
         SKIP=false
         MARKER_TS=$(gh issue view "$N" --json comments \
           --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=observation-trigger phase=observation-trigger issue='"$N"' event='"$EVENT_NAME"' -->"))] | sort_by(.createdAt) | .[-1].createdAt // empty' \
           2>/dev/null || true)
         if [ -n "$MARKER_TS" ]; then
             if MARKER_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$MARKER_TS" "+%s" 2>/dev/null) || \
                MARKER_EPOCH=$(date -d "$MARKER_TS" "+%s" 2>/dev/null); then
                 NOW_EPOCH=$(date +%s)
                 ELAPSED=$(( NOW_EPOCH - MARKER_EPOCH ))
                 if [ "$ELAPSED" -lt 86400 ]; then
                     SKIP=true
                 fi
             fi
         fi
         if [ "$SKIP" = false ]; then
             BODY=$(printf '<!-- wholework-event: type=observation-trigger phase=observation-trigger issue=%s event=%s -->\nobservation event `%s` detected. Run `/verify %s` to verify the condition and update the checkbox.' "$N" "$EVENT_NAME" "$EVENT_NAME" "$N")
             gh issue comment "$N" --body "$BODY" >/dev/null 2>/dev/null || true
         fi
     done

     echo "$NUMBERS"
     ```
     `date` の BSD/GNU 両対応フォールバックは `scripts/get-auto-session-report.sh` の既存パターン (`date -j -f ... || date -d ...`) を再利用する。
   - `phase=observation-trigger` は固定リテラルとする (`spec`/`code`/`review`/`merge`/`verify` のようなワークフローフェーズ名ではない)。理由: 本スクリプトは `/auto`・`/review`・`/verify` の fix-cycle・`scripts/claude-watchdog.sh` という複数の異なるフェーズから呼ばれ、`--phase` 引数もなく呼び出し元の実際のフェーズを知る信頼できる手段がないため、スクリプト自身の識別子を代わりに使う。他の `wholework-event` マーカー消費者はいずれも `phase=` の値ではなく `type=` プレフィックスでマッチしている (コードベース grep で確認済み) ため、この選択は既存の消費ロジックに影響しない。
   - 24時間 (86400秒) はスクリプト内の固定定数とし、`.wholework.yml` の新規設定キーにはしない (Issue 本文の「例: 24時間」は例示であり必須の設定可能性を求めていない。新規キー追加は `detect-config-markers.md` のマーカー表更新等の付随変更を要し、Size S の軽量修正としては過剰)。
   - ヘッダコメント (ファイル冒頭) に、(a) 冪等性ガードとその 24 時間ウィンドウ、(b) stdout 契約 — matched Issue 番号のみ・1行1番号・昇順・URL 等の他出力は含まれない — を明記する。

2. (after 1) `tests/observation-trigger.bats` を修正する (→ acceptance criteria 5):
   - `setup()` 内の `gh` モックをサブコマンド分岐に拡張する: `$1 $2` が `issue view` の場合は `${MOCK_EXISTING_MARKER_CREATED_AT:-}` を stdout に出力 (デフォルト空文字列 — 既存テストのマーカー未検出パスをそのまま維持); `$1 $2` が `issue comment` の場合は既存の呼び出しログ追記に加えて `https://github.com/mock/repo/issues/$3#issuecomment-999999` のような擬似 URL を stdout に出力する (実際の `gh issue comment` の stdout 挙動を再現するため)。
   - 新規テストケースを追加する:
     - 冪等性スキップ: `MARKER_TS` を「1時間前」の ISO8601 (BSD/GNU 両対応の `date` フォールバックでテスト内で算出、スクリプト側と同じ変換ロジック) に設定し、`gh issue comment` が呼ばれないこと (`gh-calls.log` に `issue comment` 行がないこと) と `$output` が matched Issue 番号のままであることを確認する。
     - ウィンドウ期限切れで非スキップ: 同様に「25時間前」を設定し、`gh issue comment` が呼ばれること (スキップされないこと) を確認する。
     - stdout hygiene: 通常の単一マッチ実行後、`$output` に `https://` が含まれないことを確認する (URL 漏れ回帰の検知)。
     - マーカー形式: `gh-calls.log` に記録された `issue comment` 呼び出しの `--body` 引数に `type=observation-trigger phase=observation-trigger issue=<N> event=<name>` が含まれることを確認する。
   - モック拡張後も既存の全テストケース (引数エラー、dry-run、マッチなし、単一マッチ、複数マッチ、同一Issue dedup、`--context-file` 転送、`opportunistic-search.sh` エラー時の継続) が回帰なく PASS することを確認する。

3. (parallel with 1, 2) `modules/observation-trigger.md` を修正する (AC への直接マッピングなし — Steering Docs sync candidate として、スクリプトの SSoT 設計ドキュメントを実装と整合させるための補助的な変更):
   - `## \`scripts/observation-trigger.sh\` (実装済み #656; stdout output added in #897)` の見出しに `; idempotency guard added in #1099` を追記する。
   - 見出し直後の説明文中「comment-posting side effect; unconditional regardless of caller context」の記述を、冪等性ガードの挙動 (同一 `event`・同一 Issue に対する `type=observation-trigger` マーカーが直近 24 時間以内に存在する場合は投稿をスキップする。スキップされた Issue 番号も stdout の一覧には引き続き含まれる) を反映した記述に更新する。
   - 上記の直後に、マーカー形式 (`<!-- wholework-event: type=observation-trigger phase=observation-trigger issue=<N> event=<name> -->`) と `phase=observation-trigger` を固定リテラルとした採用理由 (Implementation Step 1 と同内容) をサブセクションとして追加する。
   - `/auto` dispatch cap (#952) を説明するサブ箇条書き中の「the notification comment above is posted to every matched Issue unconditionally regardless of the cap」を、上記の冪等性ガードの対象である旨を補足する記述に更新する。

4. (parallel with 1, 2, 3) `docs/guide/customization.md` と `docs/ja/guide/customization.md` を修正する (AC への直接マッピングなし — Steering Docs sync candidate として、`observation-dispatch-threshold` の説明文の陳腐化を防ぐための補助的な変更):
   - `docs/guide/customization.md` の `observation-dispatch-threshold` 行にある「(existing \`observation-trigger.sh\` behavior, unconditional)」を「(existing \`observation-trigger.sh\` behavior, subject to its idempotency guard — see \`modules/observation-trigger.md\`)」に置き換える。
   - `docs/ja/guide/customization.md` の対応行にある「(\`observation-trigger.sh\` の既存の無条件挙動)」を「(\`observation-trigger.sh\` の既存の挙動、ただし冪等性ガードの対象。\`modules/observation-trigger.md\` 参照)」に置き換える。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/observation-trigger.sh が、同一 event・同一 Issue に対する advisory コメントが既に存在する場合に再投稿をスキップする実装になっている。スキップの判定条件 (マーカーと期間) が明確である" --> 重複投稿のスキップが実装されている
- <!-- verify: rubric "スキップした Issue も stdout の Issue 番号一覧には含まれ、呼び出し側の後続 dispatch 判定に影響しないことが確認できる" --> スキップしても stdout の一覧には含まれる
- <!-- verify: rubric "scripts/observation-trigger.sh の gh issue comment 呼び出しが標準出力 (コメント URL) も抑制するよう修正されており、スクリプト全体の stdout には Issue 番号一覧以外の行が含まれない" --> `gh issue comment` の URL が stdout に漏れないよう抑制されている
- <!-- verify: rubric "scripts/observation-trigger.sh のヘッダコメントに stdout の出力形式 (どの行が URL でどの行が Issue 番号か) が明記されている" --> stdout の出力形式がヘッダコメントに明記されている
- <!-- verify: command "bats tests/observation-trigger.bats" --> `tests/observation-trigger.bats` が PASS する

### Post-merge

- `observation-trigger.sh --event auto-run` を連続 2 回実行し、2 回目で advisory コメントが重複投稿されないこと、かつ stdout の Issue 番号一覧が 1 回目と同じであることを確認する <!-- verify-type: manual -->

## Notes

- **`phase=observation-trigger` の採用理由**: `modules/l0-surfaces.md` のマーカー基本フィールド (`type`/`phase`/`issue`) は本来ワークフローフェーズ名 (`spec`/`code`/`review`/`merge`/`verify`) を想定しているが、`observation-trigger.sh` は複数の異なるフェーズから呼ばれる共有スクリプトであり、呼び出し元の実際のフェーズを知る手段がない (`--phase` 引数なし)。新規に `--phase` 引数を追加し全 4 emitter (`/auto`・`/review`・`/verify`・`claude-watchdog.sh`) に配線することは Size S の本 Issue のスコープを超えるため、スクリプト自身の識別子 (`observation-trigger`) を `phase=` の値として使う設計とした。既存の全マーカー消費者は `type=` プレフィックスでマッチしており `phase=` の値では分岐していないことをコードベース grep で確認済みのため、この設計判断は既存の消費ロジックに影響しない。
- **24時間ウィンドウを固定定数とした理由**: Issue 本文の「例: 24 時間」は例示であり、`.wholework.yml` での設定可能性を要求していない。新規設定キーの追加は `modules/detect-config-markers.md` のマーカー表更新・`docs/guide/customization.md` への行追加など付随変更を伴い、Size S の軽量な冪等性修正としては過剰と判断した。将来的に運用上ウィンドウ値の調整ニーズが生じた場合は、別 Issue でのフォローアップとする。
- **Steering Docs sync candidate 確認結果**: `grep -rn "observation-trigger" docs/ tests/ scripts/` を実行し、`modules/observation-trigger.md`・`docs/guide/customization.md`・`docs/ja/guide/customization.md` の3ファイルが「unconditional」という、本 Issue の変更後に不正確となる記述を含んでいることを確認した (Changed Files に反映済み)。一方 `docs/structure.md`・`docs/ja/structure.md` の `scripts/observation-trigger.sh` 1行説明は「dispatch 契約」レベルの粒度で `unconditional` 等の言及がなく、本変更後も正確なままのため更新不要と判断した (Issue #934 spec retrospective の前例と同じ判断基準)。
- **`gh issue comment` の stdout URL 挙動**: Issue 本文が既にソースコードレベルで技術的原因を特定済み (`scripts/observation-trigger.sh:79` の `2>/dev/null` は標準エラーのみ抑制)。この挙動は `gh` のバージョンに依存する仕様ではなく、修正 (`>/dev/null` 追加によるシェルリダイレクト) も `gh` の特定フラグに依存しないため、`gh` 公式ドキュメントの追加確認は不要と判断した。

## Consumed Comments

- saito (MEMBER, first-class): `/issue 1099 --non-interactive` の Issue Retrospective — マーカー形式の `l0-surfaces.md` 基本フィールド準拠修正、および `gh issue comment` stdout URL 抑制の新規 AC 化について、非対話モードでの自動解決ログを記録したもの。内容は Issue 本文に既に反映済みで、Spec フェーズに対する新規の指示は含まれていない。(https://github.com/saitoco/wholework/issues/1099#issuecomment-5173969887)
