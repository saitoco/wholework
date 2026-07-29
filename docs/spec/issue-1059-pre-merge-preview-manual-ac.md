# Issue #1059: issue: pre-merge-preview tier を manual AC にも適用できるように

## Overview

`capabilities.pr-preview: true` の downstream プロジェクトで、PR プレビューでしか確認できない AC (verify command を持たない manual AC) が post-merge セクションに配置され、merge 後は preview 環境が消滅しているため検証不能になる構造的欠陥を修正する。原因は `skills/issue/SKILL.md` Step 4 の pre-merge-preview tier 分類条件が「verify command の種類 (URL/UX set 所属)」のみを基準にしており、「検証を行う環境 (preview で確認するか)」という軸と「検証手段 (auto/manual)」という軸を混同していること。分類条件を検証環境ベースに変更し、`<!-- ac-tier: preview --> <!-- verify-type: manual -->` の組み合わせタグで manual な preview AC を pre-merge セクションに配置できるようにする。あわせて `/review`・`/verify` 側の manual AC 対応も追加する。

## Reproduction Steps

1. downstream プロジェクトの `.wholework.yml` に `capabilities.pr-preview: true` を設定する。
2. `/issue` で、verify command を持たない (機械的に判定不能な UI/UX 挙動を人間が preview で目視確認する必要がある) AC を含む Issue を作成・リファインする (例: 「送信完了時のスクロール挙動を確認する」)。
3. `skills/issue/SKILL.md` Step 4 の pre-merge-preview tier 分類は「AC の verify command が URL/UX set (`http_status` 等) に属するか」のみを条件にしているため、verify command を持たない AC はこの条件に該当せず、常に Post-merge セクションに分類される。
4. merge 後、PR プレビュー環境は消滅する。Post-merge セクションに配置された当該 AC は「preview で確認する」という前提と「merge 後にしか検証されない」という配置が矛盾し、実質検証不能になる。

## Root Cause

`skills/issue/SKILL.md` Step 4 (`skills/issue/SKILL.md:68-80`。`Existing Issue Refinement` Step 7 はこの手続きに全面委譲しているため実体は 1 箇所) の pre-merge-preview tier 分類条件が、AC の verify command 型 (`http_status`/`html_check`/`api_check`/`http_header`/`http_redirect`/`browser_check`/`browser_screenshot`/`lighthouse_check`) の所属のみをトリガーにしている (`skills/issue/SKILL.md:72,74`)。これは「いつ検証できるか (pre-merge/preview vs. post-merge/production)」と「どう検証するか (auto な verify command vs. manual な人間判断)」という本来直交する 2 軸を 1 つの条件に混線させている。preview tier は現状「auto かつ preview」のみをカバーしており、「manual かつ preview」を表現する手段が存在しない。この結果、`/review`・`/verify` 側にも波及する: `/review` Step 8 (`skills/review/SKILL.md:252`) の「verify command なしは AI 判定を試みる」処理には、preview 環境でのみ判定可能な manual AC を除外する分岐がない。`/verify` Step 5 (`skills/verify/SKILL.md:187`) の production URL フォールバック処理は「verify command の `{{base_url}}` を解決して実行する」ことを前提にしており、verify command を持たない manual AC には適用できない。

## Changed Files

- `skills/issue/SKILL.md`: change — Step 4 (`New Issue Creation`, L68-80) の pre-merge-preview tier 分類条件を、verify command 型ベースから「preview 環境で確認するか」ベースに変更し、manual サブケースのタグ規約 (`<!-- ac-tier: preview --> <!-- verify-type: manual -->`、verify command 行・`--when` guard なし) を追記する。`Existing Issue Refinement` Step 7 (L453) は Step 4 に全面委譲しているため別途編集不要
- `docs/tech.md`: change — `HAS_PR_PREVIEW_CAPABILITY` capability flag 行 (L241) の説明を、「URL/UX-based ACs are placed...」という verify command 型ベースの記述から、環境ベースの記述に更新
- `docs/guide/customization.md`: change — 「AC verification tiers」節の pre-merge-preview 行 (L180)、`capabilities.pr-preview` キー説明行 (L131)、「Enabling pre-merge-preview」段落 (L183-185)、「Behavior summary」箇条書き 2 件 (L199, L200) を manual サブケースに対応する記述へ更新
- `tests/issue.bats`: change — manual サブケースのタグ規約が明文化されていることを確認する `@test` を追加
- `skills/review/SKILL.md`: change — Step 8 の条件判定列挙 (L246-258) に、「verify command なし + `ac-tier: preview` + `verify-type: manual`」の AC を AI 判定を試みずに UNCERTAIN (human-check 項目) として扱う分岐を、L252 の「No hint: attempt AI judgment」より前に追加する。「Acceptance Criteria Verification Results」出力例の Notes 列ガイダンス (L546-551 付近) を manual preview AC 向けに補足する
- `tests/review.bats`: change — 新規分岐が明文化されていることを確認する `@test` を、既存の `step8_section()` ヘルパーを使って追加
- `skills/verify/SKILL.md`: change — Step 5 の pre-merge-preview AC skip rule (L179-190) の冒頭文を、auto/manual 両方に適用されることが明示される記述に変更する。フォールバック分岐 (L186-188) に verify command の有無による分岐を追加し、manual AC は `{{base_url}}` 解決・実行を試みずに UNCERTAIN (人間確認が必要) として扱う。SKIPPED ケースの注記文言 (L185) も manual ケースを含む表現に更新する
- `tests/verify.bats`: change — manual サブケースの記述が存在することを確認する `@test` を、既存の `step5_section()` ヘルパーを使って追加

## Implementation Steps

1. `skills/issue/SKILL.md` の Step 4「pre-merge-preview tier」節 (L68-80) を変更する。分類条件を「AC の verify command が URL/UX set に属するか」から「AC が PR preview 環境で確認できるか」に変更し、2 つのサブケースを明記する: (a) 既存の auto サブケース (URL/UX verify command あり) — `<!-- ac-tier: preview -->` タグと `--when="test -n \"$PREVIEW_URL\""` guard の付与は現状維持する。(b) 新規の manual サブケース (verify command なし、preview 環境での人間による目視・操作確認が本質的に必要) — `<!-- ac-tier: preview --> <!-- verify-type: manual -->` を付与し (verify command 行がないため `--when` guard は付与しない)、Post-merge ではなく `### Pre-merge (auto-verified)` に配置する。節見出し「pre-merge-preview tier (URL/UX AC classification)」の括弧書きを environment ベースの表現に変更する (`tests/issue.bats` が `pre-merge-preview` という文字列自体を assert しているため、見出し本体の文言は維持する)。`Existing Issue Refinement` Step 7 (L453) は「Follow the full procedure defined in ... Step 4」で全面委譲しているため別途編集は不要。`docs/tech.md` L241 の `HAS_PR_PREVIEW_CAPABILITY` 説明と、`docs/guide/customization.md` の L131 (`capabilities.pr-preview` 行)・L180 (tier 表)・L183-185 (Enabling 段落) を同じ environment ベースの表現に同期する。`tests/issue.bats` に、manual サブケースのタグ規約 (`verify-type: manual` と preview tier ガイダンスの共起) を assert する `@test` を追加する。(→ Pre-merge AC1, AC2)

2. (after 1) `skills/review/SKILL.md` の Step 8 条件判定列挙 (L246-258) に新しい分岐を追加する。「1. With verify command」と「2. No hint: attempt AI judgment」の間、または項目 2 の冒頭に、「Pre-merge AC が verify command を持たず、かつ `<!-- ac-tier: preview -->` と `<!-- verify-type: manual -->` を両方持つ場合、AI 判定を試みずに直接 UNCERTAIN として分類し、Notes に『preview URL に対する human-check が必要』である旨を記録する」分岐を挿入する。L260-284 の「Preview-tier unverified marker」ロジックは verify command の有無を問わず「`ac-tier: preview` かつこの Step で UNCERTAIN に分類された AC」を収集する実装のため、この manual AC も自動的に `type=preview-ac-unverified` マーカーの `ac=` 索引集合に含まれる — この部分の変更は不要。Step 11 の「Acceptance Criteria Verification Results」出力例 (L544-551) の Notes 列に、manual preview-tier AC 向けの記載例を追記する。`docs/guide/customization.md` L199 (「`PREVIEW_URL` not set: preview-tier ACs are SKIPPED (the `--when` guard fires)」) を、manual AC には `--when` guard 自体が存在せず常に human-check 項目として提示される旨を補足する記述に更新する。`tests/review.bats` に、既存の `step8_section()` ヘルパーを使って新分岐が明文化されていることを assert する `@test` を追加する。(→ Pre-merge AC3)

3. (after 1) `skills/verify/SKILL.md` の Step 5「pre-merge-preview AC skip rule」(L179-190) を変更する。L181 の冒頭文に、`ac-tier: preview` タグによる分類は verify command を持つ auto AC と `<!-- verify-type: manual -->` の manual AC の両方に適用される旨を明記する。L186-188 のフォールバック分岐 (`/review` で UNCERTAIN のまま残った場合) に、`PRODUCTION_URL` の有無で分岐する前に「この AC が verify command を持つか」の判定を追加する: verify command を持たない (manual) 場合は `{{base_url}}` の解決・実行を試みず、`PRODUCTION_URL` の設定有無に関わらず UNCERTAIN として扱い、Notes に「自動フォールバック手段がなく人間による確認が必要」である旨を記録する。既存の `PRODUCTION_URL` 空/非空分岐は verify command を持つ AC にのみ適用する形に絞る。L185 の SKIPPED ケースの注記文言 (「preview-tier AC; verified at /review against preview URL」) を、`/review` で human-check 項目として提示された manual ケースも含む表現に更新する。`docs/guide/customization.md` L200 (`/verify` のフォールバック挙動の説明) を同じ分岐に同期する。`tests/verify.bats` に、既存の `step5_section()` ヘルパーを使って manual サブケースの記述を assert する `@test` を追加する。(→ Pre-merge AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md の pre-merge-preview tier の分類条件が、verify command の種類ではなく検証を行う環境 (preview で確認するかどうか) を基準にする形へ変更されている" --> preview tier の分類条件が検証環境ベースになっている
- <!-- verify: rubric "ac-tier: preview と verify-type: manual を併用した AC の記法と、その AC を誰がどのフェーズで確認するかが明文化されている" --> manual な preview AC の記法と扱いが明文化されている
- <!-- verify: rubric "skills/review/SKILL.md が、verify command を持たない (manual) preview tier AC について、検証を試みるのではなく人間が確認すべき項目として review コメントに提示する扱いを記載している" --> `/review` 側に manual preview AC の扱いが反映されている
- <!-- verify: rubric "skills/verify/SKILL.md が、manual な preview tier AC も既存の auto な preview tier AC と同じ post-merge skip 対象として扱う記述を含んでいる" --> `/verify` 側に manual preview AC の扱いが反映されている

### Post-merge

- preview 環境で人間が確認する AC を含む Issue を 1 件通しで実行し、その AC が pre-merge セクションに配置され merge 前に確認される流れになることを確認する

## Notes

- **`docs/tech.md` / `docs/guide/customization.md` を Changed Files に追加した理由**: Issue 本文の「下流スキルへの影響」表は `/review`・`/verify`・`/merge` のみを挙げているが、コードベース調査で `docs/tech.md:241` (`HAS_PR_PREVIEW_CAPABILITY` capability flag 説明) と `docs/guide/customization.md` (L131, L180, L185, L199-200 の計 4 箇所、`capabilities.pr-preview` のユーザ向け解説) が同じ「verify command 型ベース」の分類条件を記述していることを `grep -rn` で確認した (Steering Docs sync candidate check)。分類条件の変更点そのものを説明する箇所のため、Changed Files に含めた。
- **`/merge` は対象外**: Issue 本文の「検討事項」で、manual preview AC のチェック責務の正式な割り当て (merge ゲート) は別 Issue に委ねる方針が明示されている。本 Spec もこれに従い `skills/merge/SKILL.md` は変更しない。
- **Issue 本文と実装の整合性チェック**: Issue 本文の Background が引用する現行実装 (「URL/UX verify command set (exhaustive): ...」「For each AC whose verify command belongs to the above set...」) は `skills/issue/SKILL.md:72,74` の記述と完全に一致することを確認した。矛盾なし。
- **`Existing Issue Refinement` Step 7 への影響**: `skills/issue/SKILL.md:453` が「Follow the full procedure defined in ... Step 4」で分類手続きを全面委譲しているため、Step 4 (L68-80) の 1 箇所を変更すれば新規 Issue 作成・既存 Issue リファイン両方の経路に反映される。`grep -n "pre-merge-preview\|ac-tier: preview"` で同ファイル内の該当箇所が Step 4 の 1 ブロックのみであることを確認済み。
- **`modules/l0-surfaces.md` / `scripts/resolve-preview-ac-fallback.sh` は変更不要**: 両者とも `ac-tier: preview` AC の索引集合を verify command の有無に関係なく扱う実装 (前者はマーカー仕様の文書、後者は索引の文字列処理のみ) であることを確認した。変更範囲は `skills/issue/SKILL.md` の分類ロジックと `skills/review/SKILL.md`・`skills/verify/SKILL.md` の実行ロジックに閉じる。
- **Post-merge AC を `manual` のまま維持する理由**: `modules/verify-patterns.md` §11 の quick reference と照らし合わせたが、当該 AC は「新規 Issue を実際に `/issue`→`/spec` (または `/code`) まで通し、分類結果を観測する」という動的な振る舞い確認であり、`file_exists`/`file_contains`/`http_status`/`rubric` のいずれにも置換できない (rubric は Issue 本文・diff・明示ファイルへの静的判定であり、スキル実行そのものは評価対象にできない)。Issue 本文の判断をそのまま維持する。

## Consumed Comments

- saito (MEMBER, first-class): `/issue --non-interactive` によるリファインメントの Issue Retrospective コメント。Type=Bug / Size=M の判定根拠、Pre-merge AC3・AC4 の verify command を `grep` (常時 PASS 判定) から `rubric` へ変更した理由、および「検討事項」2 点 (manual preview AC のチェック責務の切り分け、`--when` 未使用方針) の自動解決ログを記録したもの。いずれも Issue 本文に既に反映済みの内容であり、本 Spec の設計判断に新規の変更は生じていない。(https://github.com/saitoco/wholework/issues/1059#issuecomment-5111765584)
- `/code --non-interactive` 実行時点でカットオフ (最新 `phase/*` ラベル付与時刻) 以降の新規コメントなし。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–3 を Spec の記述通りに実装した。

### Design Gaps/Ambiguities
- `skills/review/SKILL.md` Step 8 の項目挿入位置について、Spec は「項目 1 と項目 2 の間、または項目 2 の冒頭」の 2 択を許容していたため、新規分岐を項目 2 として挿入し、既存の「No hint: attempt AI judgment」を項目 3 に、「Classify each condition」を項目 4 に繰り下げた。これは Spec の許容範囲内の選択であり、設計逸脱ではない。

### Rework
- N/A — 各 Implementation Step の初回編集で bats テスト・`validate-skill-syntax.py`・`check-forbidden-expressions.sh` がいずれも一発で PASS し、やり直しは発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #1068 は CI SUCCESS・review approved・conflicts なし (mergeable=clean) だったため、conflict 解決手続きを経ずに squash merge をそのまま実行した。
- squash merge 後、worktree を `origin/main` に `--ff-only` で追随させてから Spec の Phase Handoff を書き換えた (merge phase はマージ後にも Spec 編集ができるよう worktree を最新化する必要がある)。

### Deferred Items
- `skills/audit/SKILL.md` の Manual Waiting Count と `skills/auto/SKILL.md` の Pending manual confirmation 集計が pre-merge な manual preview AC を誤カウントし得る問題、および `modules/verify-classifier.md` の Purpose/Input 記述更新は、review phase で SHOULD/CONSIDER としてレビューコメントに記録済みでスコープ外のため据え置き。フォローアップ Issue化を推奨。
- manual preview AC のチェック責務の正式な割り当て (merge ゲートでの強制など) は、Issue 本文の「検討事項」記載通り別 Issue に委ねられており、本 PR のスコープ外。

### Notes for Next Phase
- `/verify` は Post-merge 実行時、Step 5 の pre-merge-preview AC skip rule により auto/manual いずれの preview-tier AC もデフォルトで SKIPPED として扱う。`type=preview-ac-unverified` マーカーで未検証と報告された manual AC は、production-URL フォールバックを試みず常に UNCERTAIN (human verification required) として記録される。
- Post-merge の唯一の未チェック AC (「preview 環境で人間が確認する AC を含む Issue を 1 件通しで実行し、pre-merge セクションに配置され merge 前に確認される流れになることを確認する」) は動的確認が必要なため、`/verify` 側で human-check として扱われる想定。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — Implementation Steps 1–3 は Spec の記述通りに実装されており、`/review` の rubric ベース AC 検証 4 件もすべて PASS で diff と Spec 記述に構造的な乖離はなかった。

### Recurring issues

`verify-type: manual` タグの意味論拡張 (post-merge 専用 → pre-merge/post-merge 両対応) が、本 PR のスコープ外にある下流の集計スキルに副作用を及ぼす形跡を確認した。`skills/audit/SKILL.md` の Manual Waiting Count と `skills/auto/SKILL.md` の Pending manual confirmation 集計は、いずれも Issue 本文全体を post-merge 限定の前提でスキャンしており、pre-merge な manual preview AC ( `/verify` で SKIPPED のまま恒久的に unchecked になる) を誤って「未対応の manual AC」としてカウントし得る。`modules/verify-classifier.md` の Purpose/Input 記述も post-merge 専用という前提のままで、今回の意味論拡張を反映していない。

これは「タグ・enum の意味論を拡張する変更が、その enum 値を消費する全箇所を横断的に洗い出せていない」という、タグ拡張系 Issue に共通しやすいパターンの一例と見られる。個別の SHOULD/CONSIDER としてレビューコメントに記録済み (このレビューのスコープでは修正見送り、フォローアップ Issue 化を推奨)。

### Acceptance criteria verification difficulty

Nothing to note — Pre-merge (auto-verified) 4 件はすべて `rubric` verify command で、PR diff の該当箇所と 1 対 1 で対応が取れており UNCERTAIN は発生しなかった。verify command の記述と実装内容の乖離もなし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Pre-merge AC 4 件はすべて `rubric` verify command で記述されており、PR diff の該当箇所と 1 対 1 で対応が取れた。`/issue` 時点で `grep` (常時 PASS になる欠陥形) から `rubric` へ差し替える監査が入っていたことが、verify 段階での誤 PASS を未然に防いだ。AC の verify command 監査が実際に機能した事例。
- Post-merge AC を manual のまま維持した判断 (Spec Notes) は妥当だった。`file_exists`/`http_status`/`rubric` のいずれにも置換できない動的なスキル実行観測であり、`/verify` 側でも human-check として扱われている。

#### design
- 「タイミング (pre-merge/post-merge)」と「検証手段 (auto/manual)」の 2 軸が混線していたという Issue の根本原因分析が正確で、Spec の Implementation Steps 1–3 がそのまま実装に落ちた。設計逸脱ゼロ。
- Changed Files に `docs/tech.md` / `docs/guide/customization.md` を追加した Spec 側の判断 (`grep -rn` による Steering Docs sync candidate check) が、ドキュメント側の記述漏れを事前に防いだ。

#### code
- fixup/amend パターンなし。各 Implementation Step の初回編集で bats・`validate-skill-syntax.py`・`check-forbidden-expressions.sh` が一発 PASS。
- `docs/ja/` ミラー同期 (PATCH 4/6) が独立コミットとして追加されている。Spec の Changed Files には `docs/ja/` が列挙されていなかったが、code phase が自律的に検出して同期した。Spec 側の Changed Files 抽出で `docs/ja/` ミラーを機械的に含める仕組みがあれば、この検出は設計時に前倒しできる。

#### review
- `verify-type: manual` タグの意味論拡張 (post-merge 専用 → pre-merge/post-merge 両対応) が、スコープ外の下流集計スキルに副作用を及ぼす点を review が検出した。これは「enum の意味論拡張時に、その値を消費する全箇所を横断的に洗い出す」という汎用パターンの検出であり、review の有効性が高かった事例。
- ただし検出された SHOULD/CONSIDER 2 件はスコープ外として見送られ、フォローアップ Issue も本 verify 時点まで未起票のまま残っていた。review が「フォローアップ Issue 化を推奨」と記録するだけでは起票が担保されない。

#### merge
- CI SUCCESS・approved・mergeable=clean で conflict 解決手続きなし。特記事項なし。

#### verify
- Issue 本文の ` ```markdown ` コードフェンス内にある説明用サンプル `- [ ] <!-- ac-tier: preview --> <!-- verify-type: manual --> preview で実送信し...` (本文 55 行目) が、AC のチェックボックス番号付けに混入していることを検出した。実 AC は index 2–6 であり index 1 はサンプル。本 Issue では checkbox 更新が発生しなかったため実害はなかったが、`gh-issue-edit.sh --checkbox` を使う経路では off-by-N の誤更新を起こし得る。
- 同じサンプル行は `verify-type: manual` + 未チェックの形をしているため、`/auto` の Pending manual confirmation 集計や `/audit` の Manual Waiting Count でも「未対応の manual AC」として誤カウントされる。review が検出した「pre-merge manual preview AC の誤カウント」と症状は同じだが、原因が異なる (コードフェンス内サンプル vs. セクション前提の誤り)。

### Improvement Proposals

- `/verify`・`/audit`・`/auto` の AC チェックボックス列挙が、Issue 本文の fenced code block (` ``` ` で囲まれた領域) 内の `- [ ]` 行を実 AC として数えてしまう。記法例を本文中に示す Issue では必ず発生し、`gh-issue-edit.sh --checkbox` の index が実 AC とずれるため checkbox 誤更新のリスクがある。チェックボックス列挙時に fenced code block 内の行を除外する共通ルールを `modules/` 側に定義し、`gh-issue-edit.sh` と各スキルの列挙処理を揃えるべき。
- `skills/audit/SKILL.md` の Manual Waiting Count と `skills/auto/SKILL.md` の Pending manual confirmation 集計が、Issue 本文全体を post-merge 限定の前提でスキャンしている。#1059 で `verify-type: manual` が pre-merge にも配置可能になったため、pre-merge の manual preview AC (`/verify` で恒久的に SKIPPED/unchecked のまま) が「未対応の manual AC」として誤カウントされる。集計対象を `### Post-merge` セクション配下に限定するか、`ac-tier: preview` タグを除外条件に加えるべき。
- `modules/verify-classifier.md` の Purpose/Input 記述が「`verify-type: manual` は post-merge 専用」という前提のままで、#1059 の意味論拡張 (pre-merge にも配置可能) を反映していない。分類器の入力仕様と実際のタグ意味論が乖離している。
- タグ・enum の意味論を拡張する Issue において、その enum 値を消費する全箇所を横断的に洗い出す手順が `/spec` に存在しない。#1059 では review phase で初めて下流の集計スキルへの副作用が検出された。`/spec` の調査ステップに「変更するタグ/enum 値を `grep -rn` で全消費箇所に展開し、Changed Files または Notes に影響評価を記録する」を追加すべき。
- `/spec` の Changed Files 抽出が `docs/ja/` ミラーを機械的に含めていない。#1059 では code phase が自律的に検出して同期したが、検出漏れれば英日で記述が乖離する。`docs/` 配下のファイルを Changed Files に含める際、対応する `docs/ja/` ミラーの存在を確認して自動的に併記するルールを追加すべき。

## Auto Retrospective

### Manual recovery (spec)
- **Date**: 2026-07-29 03:15 UTC
- **Issue**: #1059, phase: spec
- **Source**: parent session manual recovery
- **Recovery type**: respawn
- **Wrapper exit code**: unknown
- **Outcome**: success
