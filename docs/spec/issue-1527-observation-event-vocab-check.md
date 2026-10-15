# Issue #1527: verify-classifier: observation の event 値を文書化された語彙と照合する検査を足す

## Overview

`modules/verify-classifier.md` の表は `verify-type: observation` の `event=` に使える名前を 5 値 (`pr-review-full`・`pr-review-light`・`auto-run`・`watchdog-kill`・`fix-cycle`) に限る。しかし `/issue`・`/spec` が受入条件を書く時点でこの表と照合する検査は無く、下流 repo で語彙外の独自イベント名が `/spec` により受入条件に書かれ、そのままマージされた。語彙外の event は誰も発火させず、`/verify` Step 8c は「発火元が無い」と「まだ発火していない」を区別できない (どちらも SKIPPED になる) ため、その受入条件は恒久的に未チェックのまま残り、Issue が `phase/done` に到達できなくなる。

本 Issue は検出側 (`/verify` Step 8c) ではなく、受入条件を書く側で止める (Out of Scope 準拠。Step 8c と語彙そのものは変更しない)。

1. `skills/issue/SKILL.md` の New Issue Creation Step 4 (verify-type タグ付与ブロック) に、`verify-type: observation` の `event=` を語彙表と照合し、語彙外 (省略を含む) なら警告を出して `opportunistic`/`manual` へ選び直す手順を追加する。Existing Issue Refinement の Step 7 は Step 4 の手順を丸ごと参照するため、Step 4 側の変更で両フローをカバーする
2. `skills/spec/SKILL.md` の Step 10 `verify-type tag check` に、Spec へ写す `observation` 条件について同じ照合を追加する
3. `modules/verify-classifier.md` に、作成時照合と既存の Unknown event fallback の関係 (警告 + 同一パスでの選び直し、表は唯一の参照元) を記す短い段落を追加する。表本体は変更しない
4. 上記 2 手順の消失・表の複製を CI で検出する content-assertion テストを `tests/issue.bats`・`tests/spec.bats` に追加する

## Changed Files

- `modules/verify-classifier.md`: `### observation Type: Event Values and Syntax` 節内、`**Syntax note**:` 段落の直後・`` **`config=<key>` for setting-dependent observation conditions** `` 段落の直前に、新規段落 `**Authoring-time vocabulary check**:` を追加 (内容は Implementation Steps 1 と Notes「挿入文案ドラフト」)。見出しの新設・改名はしない (他ファイルが `Event Values and Syntax` を節名で参照しているため)
- `skills/issue/SKILL.md`: Step 4 の `**Assign verify-type tags to post-merge conditions:**` ブロック内、`Read ... verify-classifier.md and assign ... tags to each post-merge condition.` の一文の直後・`**Firing likelihood check (before assigning `observation`):**` の直前に、新規段落 `**Event name vocabulary check (before assigning `observation`):**` を追加 (内容は Implementation Steps 2 と Notes「挿入文案ドラフト」)
- `skills/spec/SKILL.md`: Step 10 `**verify-type tag check:**` の箇条書き内、`` `manual`-tagged conditions `` 項目の直後・既存の `` `observation`-tagged conditions — when writing an observation event AC ... `` 項目の直前に、新規項目を追加 (内容は Implementation Steps 3 と Notes「挿入文案ドラフト」)
- `tests/issue.bats`: 末尾に content-assertion テスト 2 件を追加 (Implementation Steps 4)
- `tests/spec.bats`: 末尾に content-assertion テスト 2 件を追加 (Implementation Steps 4)
- 以下は Steering Docs sync candidate 確認の記録 (件数はすべて `grep -rl "<keyword>" docs/ tests/ scripts/ modules/` の結果。`docs/spec/` と `docs/sessions/` を含み、本 Spec 自身は除く。2026-10-15〜16 実測):
  - [Steering Docs sync candidate] keyword "verify-classifier.md" skipped: matched 146 files (no discriminating power)
  - [Steering Docs sync candidate] keyword "Event Values and Syntax" skipped: matched 9 files (no discriminating power)。参考までに履歴 (`docs/spec/`) を除くヒットは `modules/verify-classifier.md` 自身と `modules/observation-trigger.md` (Notes 末尾の節名参照) のみで、本変更は節名を変えないため参照は有効のまま
  - [Steering Docs sync candidate] keyword "Unknown event fallback": 1 file (`modules/verify-classifier.md` 自身のみ)。Changed Files 以外の追加候補なし
  - [Steering Docs sync candidate] keywords "issue" / "spec" (`skills/*/SKILL.md` 由来の bare skill name) skipped: 裸のスキル名は識別力なし。本 Issue が導入する語 (`Event name vocabulary check` / `Authoring-time vocabulary check`) は実装前のため他ファイルに存在しない
  - [Steering Docs sync candidate] Listing-side sub-check: 発火せず。サブコマンドの追加・削除なし、ファイルの追加・削除・改名なし、ディレクトリ構成の変更なし (テストは既存ファイルへの追記)
  - [Outbound pointer sync candidate] 変更ファイル自身が指す参照先を確認: `modules/verify-classifier.md` の追加段落は同ファイルの分類基準と `skills/verify/SKILL.md` Step 8c を指す (Step 8c は変更しない)。`skills/issue/SKILL.md` / `skills/spec/SKILL.md` の追加文が指す `modules/verify-classifier.md` は Changed Files に含まれる。追加候補なし
  - `docs/ja/` 同期: Changed Files に `docs/` 直下の `.md` が無いため `docs/translation-workflow.md` の同期対象外

## Implementation Steps

1. `modules/verify-classifier.md`: Changed Files 記載の位置に、新規段落 `**Authoring-time vocabulary check**:` を挿入する。内容 (英語のみ、CJK 文字を含めない。`scripts/*.sh` のパスと「exhaustive」等の網羅の断定は書かない — Notes「制約への適合」参照):
   - 既存の fallback は最後の手段であり、条件の書き方ではないこと
   - 語彙外 (省略を含む) の `event=` は誰も発火させず、`/verify` Step 8c が「未発火」と「発火元なし」を区別できないため永久に解決しないこと
   - `/issue` (Step 4) と `/spec` (Step 10 の verify-type tag check) が、書く・写す `observation` 条件の `event=` を本表と照合し、語彙外なら警告を出して同じパスでタグを置き換えること (綴り違いは名前を直し、それ以外は `observation` を外して分類基準から `observation` 行を除いた基準で再分類: `opportunistic` か `manual`)
   - エラーでなく警告 + 選び直しである理由 (置換先が基準から一意に決まる、既存 fallback の `opportunistic` 扱いと整合する)
   - 照合側は実行時に本表を読み、値を再掲しない。したがって新しい event 名を受け入れさせるために必要な編集は本表への行の追加だけであること (→ 受入条件 AC3)
2. `skills/issue/SKILL.md` (after 1): Changed Files 記載の位置に、新規段落 `**Event name vocabulary check (before assigning `observation`):**` を追加する。必須要素: (a) `modules/verify-classifier.md` § observation Type: Event Values and Syntax の語彙表と照合する、(b) 表を実行時に読み、値を SKILL.md に再掲しない、(c) `event=` は `verify-type: observation` のコメント内からのみ読む (`Tag Extraction Rule` を参照)、(d) 省略または語彙外なら警告を出す (警告文の例を `for example` で示す)、(e) 綴り違いは名前を直し、それ以外は `observation` と `event=`/`session=` を外して `opportunistic`/`manual` に再分類する、(f) 質問は不要、(g) 既存 Issue の精査時も本文中の全 `observation` 条件に適用する。**語彙の値 (5 値) を 1 つも書かない** — 特に `pr-review-light` を含めないこと (→ 受入条件 AC1, AC3)
3. `skills/spec/SKILL.md` (after 1, parallel with 2): Changed Files 記載の位置に、新規項目を追加する。必須要素は Step 2 の (a)〜(f) と同じに加え、(h) Issue 本文と Spec へ写した条件の両方を対象とする、(i) タグの修正は Spec と Issue 本文 AC の両方に行う (既存の `manual` 項目と同じ扱い)、(j) 非対話モードでもそのまま適用し、修正内容を Spec の `## Notes` に記録する。新規見出しは作らず箇条書き 1 項目とする。語彙の値を 1 つも書かない (→ 受入条件 AC2, AC3)
4. `tests/issue.bats` と `tests/spec.bats` (after 2, 3): 末尾に各 2 件の content-assertion テストを追加する (1 件目: 手順の存在、2 件目: 表の非複製)。入力形式と具体的なアンカーは Notes「新規テストの入力形式」とドラフトを参照 (→ 受入条件 AC1, AC2, AC3 の回帰保護。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケースを追加したうえでスイートが PASS すること)
5. 自己検証 (after 4): `python3 scripts/validate-skill-syntax.py skills/`、`git diff -- skills/ modules/ | python3 scripts/check-language-convention.py`、`bash scripts/check-forbidden-expressions.sh`、`bats tests/issue.bats tests/spec.bats tests/verify-executor.bats tests/opportunistic-search.bats`、続けて `bats tests/` を実行する。AC の `file_not_contains` を空撃ちする: `grep -c "pr-review-light" skills/issue/SKILL.md skills/spec/SKILL.md` が両ファイルとも 0、`grep -c "pr-review-light" modules/verify-classifier.md` が 1 以上 (→ 受入条件 AC1, AC2, AC3)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/issue/SKILL.md に、verify-type: observation の受入条件を書く際に event= の値を modules/verify-classifier.md の語彙 (5 値) と照合し、語彙外なら警告を出す手順がある" --> `/issue` が `verify-type: observation` の受入条件を書くとき、`event=` の値を `modules/verify-classifier.md` の語彙と照合し、語彙外なら警告を出す
- <!-- verify: rubric "skills/spec/SKILL.md に、Spec へ verify-type: observation の受入条件を写す際に event= の値を同じ語彙と照合する手順がある" --> `/spec` が Spec に `verify-type: observation` の受入条件を写すとき、同じ照合をする
- <!-- verify: rubric "skills/issue/SKILL.md と skills/spec/SKILL.md の event= 照合手順は、語彙 (event 名の一覧) を再掲せず modules/verify-classifier.md の該当節を参照して照合する形になっており、event 名の表は modules/verify-classifier.md の 1 か所にのみ存在する" --> 語彙の表は `modules/verify-classifier.md` の 1 か所のままで、照合する側がそこを参照する (表を複製しない)
  <!-- verify: file_not_contains "skills/issue/SKILL.md" "pr-review-light" -->
  <!-- verify: file_not_contains "skills/spec/SKILL.md" "pr-review-light" -->

### Post-merge
- なし

## Notes

- **設計判断 (非対話モードでの自動解決): 警告 + 同一パスでの選び直しとし、hard error にしない**。Issue 本文の Notes が判断を `/spec` に委ねている論点。採用理由は 3 点。(1) 置換先 (`opportunistic` か `manual`) が `modules/verify-classifier.md` の分類基準から一意に決まるので、作成者への質問は情報を足さない。(2) 既存の Unknown event fallback (語彙外は `opportunistic` 扱い) と整合する。fallback は実行時の最後の手段として残し、作成時に正しい型へ直すことで、fallback が区別できない「未発火」と「発火元なし」のうち後者を作成の時点で消す。(3) 非対話モードでも止まらない。置換後に `check-skill-change-observation-ac.sh` (`session=next` 検査) が見る最終タグが確定するよう、語彙検査は Firing likelihood check より前、Skill self-update propagation check より前に置く
- **実装形態の比較: LLM が実行する散文手順を採用し、新規スクリプトは作らない**。却下した案は、`scripts/check-skill-change-observation-ac.sh` と同型の `scripts/check-observation-event-vocab.sh <body-file>` (語彙を module の表から実行時にパースし、語彙外の行を出力して exit 2 で警告)。却下理由: (1) 受入条件 3 件はいずれも SKILL.md の手順の存在を求めており、スクリプトは要求されていない。(2) 追加すると allowed-tools (2 SKILL.md)・bats・`docs/structure.md` の Key Files・`docs/ja/structure.md`・Tag Extraction Rule の consumers 表へ連鎖し、Size が L まで膨らむ。(3) module の表組みへの依存が脆い (表の列構成を変えると壊れる)。再検討の条件: 散文の照合が実際に見逃される事例が出たとき。その場合の構成案は上記のスクリプト案
- **`event=` の省略も語彙外として扱う**: module の Syntax note が「`event=` の省略は unknown event として扱う」と定めているため、検査の対象に含める (省略されたタグも誰にも発火されず、同じ失敗になる)。Issue 本文の Purpose (「語彙外なら気づけるように」) の範囲内
- **`event=` は `verify-type: observation` のコメント内からのみ読む**: `modules/verify-classifier.md` § Tag Extraction Rule の趣旨 (Issue #1273)。本 Issue 自身の受入条件が、散文と `verify:` コメントの中で `event=` を引用している (読む範囲を限定しないと、`event=` に続く語を値と誤読する) ことが実例
- **選び直し先から `auto` を外した理由**: 分類基準の優先順 (auto > opportunistic > observation > manual) では verify command が付いていれば `auto` が先に該当するが、observation 条件に付く rubric は「event 発火後の出力品質」を評価する前提 (`/spec` の Option B) で、`auto` にすると `/verify` が発火前に評価してしまう。Issue 本文の Notes も「`manual` か `opportunistic` を選び直させる」としているので、手順文もその 2 つに限る。`config=`/`when=` は `opportunistic` でも有効な属性なので外さない (外すのは observation 専用の `event=` と `session=` のみ)
- **AC3 の rubric 差し替え (Triage の AC 監査コメントへの対応)**: コメントが「AC3 の rubric を実装後に判定できる文言へ調整するか、現状の guard AC として扱うかの判断」を `/spec` に委ねていた。調整を採用した。理由: プロジェクトの監査方針 (`skills/triage/skill-dev-verify-audit.md` の rubric 型常時 PASS の Fix options: 変更される具体的な範囲を rubric に明示する) と一致し、`theme/ac-quality` の目的にも合う。差し替え後の rubric は実装前の現状では偽 (照合手順がまだ無い) で、実装後にのみ真になる。コメントの提案から 1 点だけ変えた: 末尾の「event 名の表が複数ファイルに存在しない」を、元の AC の主張を残して「event 名の表は modules/verify-classifier.md の 1 か所にのみ存在する」とした (module から表が消える場合も検出できる)。Issue 本文を `gh-issue-edit.sh` で更新済み (SSoT は Issue 本文、Spec の Verification はそれに揃えた — `modules/verify-patterns.md` §18)。差分は rubric の 1 行のみ。補助の `file_not_contains` 2 件は回帰保護としてそのまま残した
- **不在検証 AC (`file_not_contains`) の参照点 (`modules/verify-patterns.md` §26)**: 実装前カウント — `pr-review-light` は `skills/issue/SKILL.md` に 0 件、`skills/spec/SKILL.md` に 0 件 (`grep -c`、ファイル全体、2026-10-15〜16 実測)。対照群 — `modules/verify-classifier.md` に 1 件 (表の行)。両 SKILL.md は存在し非空 (約 68KB と約 86KB) なので vacuous ではない。期待状態は実装後も 0 件のまま (不変条件)。手順文は語彙の値を一切書かない設計で、他の値も実測で両 SKILL.md に 0 件 (`pr-review-full`・`watchdog-kill`・`fix-cycle`)。`auto-run` のみ `skills/issue/SKILL.md` に既存の `session=next` 例として 1 件あり、今回は触れない
- **新規テストの入力形式 (light のため Notes に記録)**: 新規の分岐 (語彙内か語彙外か) を持つ手順それぞれに対し content-assertion テストを追加する。入力はスキル/モジュールの Markdown 実体 (`"$PROJECT_ROOT/skills/issue/SKILL.md"` 等) で、フィクスチャは不要。アンカー: `grep -qi 'event name vocabulary check'` と `grep -q 'Tag Extraction Rule'` (どちらも実装前の両 SKILL.md で 0 件 = 実装前は FAIL、実装後は PASS するので識別力がある)、`skills/spec/SKILL.md` ではさらに `grep -q 'Event Values and Syntax'` (実装前 0 件)。`skills/issue/SKILL.md` は `Event Values and Syntax` が既存 (1 件) のためアンカーに使わない (実装前から PASS する空振りを避ける)。否定アサーションは `run grep -q 'pr-review-light' <SKILL.md>` の後に `[ "$status" -eq 1 ]` とする (`grep` は不一致で 1、ファイル不在などのエラーで 2 を返すので、2 の場合もテストが落ちる)。肯定側の対照として `grep -q 'pr-review-light' "$PROJECT_ROOT/modules/verify-classifier.md"` を同じテストに置く (表が移動・削除された場合に否定アサーションが空振りで通るのを防ぐ)。LLM が実行する手順そのものの挙動は bats では検証できず、rubric の受入条件と `/review`・`/verify` に委ねる (`tests/issue.bats` のヘッダが述べる「文字列の存在はテスト、LLM 実行時の挙動は別の受入条件」という分担と同じ考え方)。bats は `/usr/bin/bats` が利用可能で、フル実行 (`bats tests/`) ができる
- **制約への適合 (`skills/spec/skill-dev-constraints.md` を light でも確認した)**: 半角 `!` を SKILL.md 本文に使わない。新規見出しは作らず、太字ラベル段落と箇条書きのみ (見出しレベルの指定は不要)。`skills/`・`modules/` への追記は英語のみ (CI の language-convention)。module の追記には `scripts/*.sh` のパスを書かない — allowed-tools impact chain check の Case 2 のゲート (追加内容が `scripts/*.sh` のパスを参照するか) が成立せず、読み手の SKILL.md の `allowed-tools` 更新が不要になる。SKILL.md の追記も新規 script 参照を含まないので frontmatter は変更しない。「exhaustive」「all」等の網羅を断定する語は module に書かない (Exhaustive claim mechanical verification の対象を増やさない)。禁止表現 (`scripts/check-forbidden-expressions.sh` は `docs/spec/` も走査する) に当たる廃止済み用語を Spec にも追記文にも書かない
- **Tag Extraction Rule の consumers 表は変更しない**: 表の対象は tag を機械的に読み戻すスクリプト群と集計系スキルで、`/issue` の割り当てパスは規則の文言上除外されている。`/spec` の verify-type tag check も同種の作成時レビュー (既に `auto`/`opportunistic`/`manual` のタグを読むが表には載っていない) で、今回の変更で性格が変わらない。読み取り範囲の限定は手順文が `Tag Extraction Rule` を参照して担保する
- **語彙の「表」と `KNOWN_EVENTS` の関係 (Out of Scope 準拠)**: AC3 の「表」は `modules/verify-classifier.md` の文書側の表を指す。`scripts/opportunistic-search.sh` の `KNOWN_EVENTS` は発火側の検証に使うコード定数で別物 (`modules/observation-trigger.md` が検証の単一情報源と位置づける) であり、変更しない。`modules/observation-trigger.md` Notes の「新 event の追加手順」の (2) 表への行の追加は本変更後も正確で、むしろ照合側が自動で新しい名前を受け入れるようになる (変更不要、該当箇所を読んで確認済み)
- **観測した既存のドリフト (本 Issue の範囲外、変更しない)**: `fix-cycle` は `skills/verify/SKILL.md` の FAIL 経路で `observation-trigger.sh --event fix-cycle` を実際に呼んでいる (Issue #656 / PR #671 で追加、2026-10-16 時点で確認)。一方 `modules/verify-classifier.md` の表の `fix-cycle` 行 (「Not yet implemented — emitter is a follow-up」) と `modules/observation-trigger.md` Notes の「`fix-cycle` event is defined but has no emitter yet」は古いまま。Issue 本文の Background は実装と一致している。本変更の手順文は表の第 1 列 (event 名) との照合だけに依存し、発火元の列の記述には依存しないため影響しない。修正は別の論点で、`/verify` の retrospective か `/audit drift` で拾う想定。あわせて Background の「スキル内の 4 か所」は厳密には `/auto` に 2 か所 (`auto-run`) あり、`watchdog-kill` は `scripts/claude-watchdog.sh` が発火する (スキル外) が、要件には影響しないため Issue 本文は直さない
- **Issue 本文の主張と実装の照合 (矛盾検出)**: Background の主張 — 表が 5 値に限ること、`/issue`・`/spec` に照合が無いこと (両 SKILL.md を `observation`/`event=` で grep し照合手順が無いことを確認)、`/verify` Step 8c が未発火を SKIPPED とし発火元なしと区別しないこと (Step 8c の本文を読んで確認) — はいずれも実装と一致。矛盾なし (上記の `fix-cycle` の古い記述は Issue 本文ではなく module 側の問題)
- **audit/investigation-type の判定**: no (機能追加であり、既存項目を分類した結果を後続処理が根拠として読む監査・調査の Issue ではない)。fail-safe critical script: 該当なし (スクリプト変更なし)。外部仕様依存・tool 検出・新規依存パッケージ・adapter 追加: いずれもなし
- **同期確認済み (変更不要)**: (a) `README.md`・`CLAUDE.md`・`docs/workflow.md`・`docs/guide/`・`docs/environment-adaptation.md` は observation の AC の書き方を扱わない (`verify-type|observation|event=|Firing` の grep ヒットは設定キー `observation-dispatch-threshold` とフェーズ遷移の説明のみ)。(b) `docs/structure.md` の `modules/verify-classifier.md` の説明 (post-merge 条件の検証可能性分類) は役割が変わらない。(c) `skills/verify/SKILL.md` Step 8c は不変 (Out of Scope)。(d) 既存 bats (`tests/verify-executor.bats` の `verify-classifier:` 系、`tests/opportunistic-search.bats`) は module の別の文字列を grep しており、追記では壊れない
- **Size**: Changed Files は 5 件 (Axis 1 = M)。複数スキルにまたがる (+1) と既存パターン (Firing likelihood check 等) の横展開 (−1) で相殺し M の見込み。triage 時点の S から Step 18 で再評価する。`ALWAYS_PR=false` (`.wholework.yml` に `always-pr` なし)。Pre-merge に `github_check "gh pr checks"` は無く、route に応じた書き換えは不要。Pre-merge 検証項目は 3 件、Implementation Steps は 5 件で light の上限内
- **Post-merge**: Issue 本文のとおり「なし」。本 Issue の要件は `/issue`・`/spec` の手順の追加で、動作は rubric の受入条件と今後の Issue 作成で現れる。`skills/*/SKILL.md` を変更するが、Post-merge の observation 条件は置かないので `session=next` の宣言は不要
- **コメント消費**: cutoff は直近の `phase/issue` ラベル付与 (2026-10-15T14:43:46Z)。cutoff 以降の 2 件はどちらも first-class。Triage の AC 監査コメントは上記「AC3 の rubric 差し替え」に反映し、Issue Retrospective コメントは AC3 の補助確認 (`file_not_contains`) の経緯と、AC1/AC2 に `section_contains` の補助を付けていない理由 (見出し位置が実装前に予測できない) の確認に使った
- **挿入文案ドラフト** (`/code` は趣旨と必須要素を保てば文言を調整してよい。英語のみで CJK 文字を含めない (`§` は既存の SKILL.md の参照表記と同じなので可)。語彙の値は書かない。警告文の例は 3 か所で同じ文言に揃えると読みやすい):

  `modules/verify-classifier.md` に挿入する段落:

  ```markdown
  **Authoring-time vocabulary check**: the fallback above is a last resort, not a way to write conditions. A condition whose `event=` is outside the table above, or omitted, is never fired by any skill, so it never resolves: `/verify` Step 8c reports an event that has not fired as SKIPPED ("waiting for event") and cannot tell it apart from an event that no skill fires. `/issue` (Step 4) and `/spec` (Step 10, verify-type tag check) therefore check the `event=` value of every `observation` condition they write or copy against this table, output a warning when it is not listed, and replace the tag in the same pass: a misspelled name is corrected; otherwise `observation` is dropped and the condition is re-classified with the criteria above minus the `observation` row (`opportunistic` when the text matches "verify X when `/skill-name` is run", else `manual`). It is a warning with a fix-up, not a hard error, because the replacement follows from the criteria and agrees with the fallback's own `opportunistic` treatment of an unknown event. These checks read this table when they run and do not restate its values, so adding a row here is the only edit needed for them to accept a new event name.
  ```

  `skills/issue/SKILL.md` に挿入する段落:

  ```markdown
  **Event name vocabulary check (before assigning `observation`):**

  Before keeping `verify-type: observation` on a condition, check its `event=<name>` against the event vocabulary table in `modules/verify-classifier.md` § observation Type: Event Values and Syntax. Read that table when the check runs and do not restate its values here. Read `event=` only from inside the `verify-type: observation` comment, per that module's § Tag Extraction Rule, not from the condition prose or from a `verify:` comment. When `event=` is omitted or its value is not in the table, no skill ever fires that event and the condition could never be verified. Output a warning (for example `Warning: observation condition uses event '<name>', which is not in the vocabulary of modules/verify-classifier.md`) and fix the tag now instead of leaving it to the module's Unknown event fallback: correct the name when it is a misspelling of a vocabulary entry; otherwise drop `observation` together with its `event=` and `session=` attributes and re-classify the condition with that module's criteria minus the `observation` row (`opportunistic` when the text matches "verify X when `/skill-name` is run", else `manual`). The replacement follows from the criteria, so no clarification question is needed. Run this check for every `observation` condition in the body, including ones that were already present when refining an existing Issue.
  ```

  `skills/spec/SKILL.md` に挿入する項目:

  ```markdown
  - `observation`-tagged conditions, event name vocabulary check: check the `event=` value of each `observation` condition, in the Issue body and as copied into the Spec, against the event vocabulary table in `modules/verify-classifier.md` § observation Type: Event Values and Syntax. Read that table when the check runs and do not restate its values in the Spec. Read `event=` only from inside the `verify-type: observation` comment, per that module's § Tag Extraction Rule. When `event=` is omitted or its value is not in the table, no skill ever fires that event and the condition would never resolve. Output a warning (for example `Warning: observation condition uses event '<name>', which is not in the vocabulary of modules/verify-classifier.md`) and fix the tag in both the Spec and the Issue body AC: correct the name when it is a misspelling of a vocabulary entry; otherwise drop `observation` together with its `event=` and `session=` attributes and re-classify the condition with that module's criteria minus the `observation` row (`opportunistic` when the text matches "verify X when `/skill-name` is run", else `manual`). The replacement follows from the criteria, so no clarification question is needed and this applies unchanged in non-interactive mode; note the correction in the Spec's `## Notes`.
  ```

  `tests/issue.bats` の末尾に追加するテスト:

  ```bash
  # Content-assertion tests for the observation event name vocabulary check (added for #1527).
  # The vocabulary table lives only in modules/verify-classifier.md; the /issue procedure must
  # point at it instead of restating its values. Guards against accidental removal or a pasted copy.

  @test "issue skill Step 4 documents observation event name vocabulary check" {
      grep -qi 'event name vocabulary check' "$PROJECT_ROOT/skills/issue/SKILL.md"
      grep -q 'Tag Extraction Rule' "$PROJECT_ROOT/skills/issue/SKILL.md"
  }

  @test "issue skill does not restate the event vocabulary table held by verify-classifier" {
      grep -q 'pr-review-light' "$PROJECT_ROOT/modules/verify-classifier.md"
      run grep -q 'pr-review-light' "$PROJECT_ROOT/skills/issue/SKILL.md"
      [ "$status" -eq 1 ]
  }
  ```

  `tests/spec.bats` の末尾に追加するテスト (`SKILL_FILE` と `PROJECT_ROOT` は既存の `setup()` で定義済み):

  ```bash
  # Content-assertion tests for the observation event name vocabulary check in Step 10's
  # verify-type tag check (added for #1527). The vocabulary table lives only in
  # modules/verify-classifier.md; the /spec procedure must point at it instead of restating it.

  @test "spec skill verify-type tag check documents observation event name vocabulary check" {
      grep -qi 'event name vocabulary check' "$SKILL_FILE"
      grep -q 'Event Values and Syntax' "$SKILL_FILE"
      grep -q 'Tag Extraction Rule' "$SKILL_FILE"
  }

  @test "spec skill does not restate the event vocabulary table held by verify-classifier" {
      grep -q 'pr-review-light' "$PROJECT_ROOT/modules/verify-classifier.md"
      run grep -q 'pr-review-light' "$SKILL_FILE"
      [ "$status" -eq 1 ]
  }
  ```

## Consumed Comments

- saito / MEMBER / first-class / ⚠️ Triage AC audit: AC3 の verify command が実装前から常時 PASS になる点の指摘と、rubric 文言の絞り込み案 (判断は /spec に委任) / https://github.com/saitoco/wholework/issues/1527#issuecomment-6194869943
- saito / MEMBER / first-class / ## Issue Retrospective: 前フェーズの実施記録 (曖昧点 0 件、AC3 に補助確認を追加した経緯) / https://github.com/saitoco/wholework/issues/1527#issuecomment-6194870393

## Code Retrospective

### Deviations from Design
- なし。Spec「挿入文案ドラフト」の 3 段落 (module / issue SKILL.md / spec SKILL.md) と bats 4 件を文言どおりに挿入した

### Design Gaps/Ambiguities
- 新規テストの肯定アサートが実装前 FAIL になることを確認した (`git show HEAD:<path>` で実装前内容を参照: `event name vocabulary check` は両 SKILL.md で 0 件)。Confirmed pre-implementation FAIL for 2 new test(s) (肯定アサートを持つ 2 件)。残り 2 件 (表の非複製) は不変条件のガードで、実装前から PASS するのは設計どおり
- `CLAUDE_PLUGIN_ROOT` が未設定の実行環境だったため、`${CLAUDE_PLUGIN_ROOT}/scripts/...` の呼び出しは worktree 内のリポジトリ相対パスで実行した (この repo 自体がプラグイン本体)
- worktree 分離ガードは `git ... | cmd` のようなパイプや `&&` 連結を含む複合コマンドを拒否した。単一コマンドに分けて実行すれば通る

### Rework
- なし

## review retrospective

### Spec vs. implementation divergence patterns
- Nothing to note。差分は Spec の「挿入文案ドラフト」と一致し、節名の参照 (`Event Values and Syntax` / `Tag Extraction Rule`) も実在する見出しに解決した

### Recurring issues
- Nothing to note。MUST / SHOULD の指摘は 0 件。CONSIDER 1 件 (非複製テストが `pr-review-light` 1 語のみを検査する) は Spec Notes に記録済みの設計上の限界で、対応は見送った

### Acceptance criteria verification difficulty
- rubric 3 件と `file_not_contains` 2 件は、差分と対象ファイルの直接確認で判定できた (UNCERTAIN は 0 件)。AC3 の `file_not_contains` は実装前から PASS する性質だが、rubric 側が「表の複製が無いこと」を実質的に見ているため判定に支障はなかった

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- 軽量レビュー (`--light`、Size M) で review-light が 4 観点を実施し、MUST 0 件・CONSIDER 1 件の結果を `COMMENTED` で投稿した
- rubric AC は grader サブエージェントを起動せず、差分と対象ファイルを直接読んで判定した

### Deferred Items
- 非複製テストの検査語を `pr-review-full` / `watchdog-kill` にも広げる案 (CONSIDER)。現状は両 SKILL.md で 0 件のため対応不要と判断した

### Notes for Next Phase
- CI は 17 件すべて SUCCESS。Post-merge の AC は無いため、`/merge 1529` 後の `/verify` は確認対象が無い
- 既存ドリフト (`fix-cycle` 行の「Not yet implemented」記述が古い) は本 Issue の範囲外のまま
