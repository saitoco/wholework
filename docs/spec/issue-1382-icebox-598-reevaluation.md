# Issue #1382: icebox: #598 (/auto 子フェーズ in-session 移行) の凍結継続可否を再評価

## Overview

#598 (`/auto` 子フェーズの in-session 移行: spawn-and-block → 長命親 + 非同期 sub-agent) は Icebox にあり、既存の再評価トリガーは「#587 結論後 + Fable 5 復帰後」。本 Issue は #1146 (external kill 調査、再オープン中) の AC 2 が求める #598 再評価の実行先であり、#598 を「Active化 / 凍結継続 / クローズ」のいずれかに判定し、根拠を #598 へのコメントおよび Wholework の永続 memory (Icebox index) に記録する。

起票時 (2026-08-16) の前提「#1146 決着により external kill 由来の移行圧力は消えた」は同日中のバースト kill 再発 (`docs/reports/external-kill-investigation.md` § 2026-08-16 Update (2)) により撤回され、#1146 は再オープンされた。現在の論点は「移行圧力が消えたか」ではなく「移行圧力が強い状態で、なお凍結を継続する理由があるか」である。

**Spec 作成時点の追加調査で判明した事実 (Issue 本文の前提と食い違う可能性がある点)**: #598 自身が定める再評価トリガー「#587 結論後 + Fable 5 復帰後」は、**両条件とも文面上は既に成立している**。

- #587 は Opus 4.8 対 Fable 5 親セッションの実比較データを含むレポート (`docs/reports/auto-parent-session-comparison-2026-06-14.md`) を伴って完了しており (Pre-merge AC 1-10 全 PASS 確認済み)、CLOSED 済み
- Fable 5 は 2026-07-01 に再デプロイ済み (`docs/reports/watchdog-recovery-strategy.md:126` — 2026-06-13 の政府指令停止から 2026-07-01 に再開)
- ただし #587 自身の Post-merge AC (Fable 5 復帰後の結論再評価) は、#1165 (manual AC retype 一括処理) により「比較基準だった Opus 4.8 親構成が Sonnet 5 (2026-06-30) / Opus 5 (2026-07-24) のリリースで陳腐化しており再評価に残存価値がない」との理由で SKIPPED のまま `phase/done` に遷移している (`docs/spec/issue-1165-manual-ac-retype-d3.md:84`)

Issue 本文の Notes は「Fable 5 復帰待ちという既存トリガーは... 未充足のまま残る」「最も可能性が高い着地は凍結継続、理由は Fable 5 待ち」と述べるが、上記の事実はこの想定と単純には整合しない。#598 自身の既存トリガーの成立状況を再確認したうえで判断することが、本 Issue の Post-merge AC 全 5 件の前提になる (詳細は Notes の "Issue 本文との食い違い" を参照)。

## Changed Files

None (repository files)。本 Issue は `<!-- implementation-type: metadata-only -->` であり、成果物はすべて wholework git リポジトリの外にある:

- Issue #598 の本文編集 (「再評価トリガー」節) とコメント投稿 (GitHub state、リポジトリ外)
- Wholework の永続 memory ファイル (`~/.claude/projects/-Users-saito-src-wholework/memory/project_icebox_index.md` 等、ローカルファイルシステム上だが git 管理外)

Diff-less / operate route の判定根拠は Notes を参照。

## Implementation Steps

1. 判断材料を収集する: (a) #598 の現行本文 (凍結理由 4 件・再評価トリガー 3 件、`gh issue view 598 --json body`)。(b) #587 の実際の結了状態 — Pre-merge AC 1-10 全 PASS、比較レポート `docs/reports/auto-parent-session-comparison-2026-06-14.md` 産出済み、CLOSED — と、その Post-merge AC (Fable 5 復帰後の結論再評価) が #1165 により「Opus 4.8 基準の陳腐化」を理由に SKIPPED のまま `phase/done` 遷移した経緯。(c) Fable 5 の現在の稼働状況 (`docs/reports/watchdog-recovery-strategy.md:126` — 2026-07-01 再デプロイ、opt-in 採用中。ただし #598/#587 が求める「Fable 5 親オーケストレータでの /auto 連続実行比較データ」自体が実際に取得されたかは別途確認する — 既存の #939 注記が言及する「Fable 5 実トラフィックは #560 の単一データ点のみ」は spec フェーズ `--fable` 実行の話であり、/auto 親オーケストレータとしての Fable 5 実行データとはスコープが異なるため、混同せず個別に確認する)。(d) `docs/reports/external-kill-investigation.md` § 2026-08-16 Update (2) / § 2026-08-17 Update の最新結論 (H-a = harness episodic supervision が最有力、上流 #76974 実測 background 1.45%/dispatch 対 foreground 0.007%/dispatch、補償層実績 17/17)。(e) #1146 の現在の状態 (OPEN、再オープン中)。(f) #1395 の現在の状態 (CLOSED — `detect-unrecorded-kills.sh` の偽陽性・window 不足を解消済みで、Issue 本文 Notes が指摘した「記録率の観測性が不完全」は Spec 作成時点より改善している)。(g) 永続 memory `project_icebox_index.md` #598 行と `project_external_kill_pattern.md` の現行内容。(→ AC1, AC2, AC3, AC4, AC5 の判断材料)

2. ステップ1(a)(b)(c) を突き合わせ、#598 自身が定める再評価トリガー「#587 結論後 + Fable 5 復帰後」が現時点で文面上成立しているか (Spec 作成時点の調査では成立していると見られる: #587 は比較データを伴って結了済み、Fable 5 は再デプロイ済み) を確認する。成立している場合、それが (i) #598 の判断にそのまま使える実質的な成立なのか、(ii) #587 の比較基準 (Opus 4.8 親) 自体が Sonnet 5 / Opus 5 のリリースで陳腐化しているために参照価値が薄い、形式的な成立にとどまるのかを評価する。この評価は Issue 本文 Notes の「Fable 5 復帰待ちが未充足のまま残る」という前提を裏付けるか、または覆すかのいずれかになるため、判断の結論に関わらず明示的に記録する。(after 1) (→ AC1, AC2)

3. #598 の動機を「external kill 回避」(#1146 再オープンにより復権、上流 #76974 実測の foreground/background 構造的格差が根拠) と「それ以外」(spawn-and-block のオーバーヘッド、親セッションの文脈保持、フェーズ間の状態受け渡し、`wrapper_exit_code` の観測不能性 — #1395 着地により部分的に改善) に分解し、ステップ2で確認した #598 自身のトリガー成立状況を踏まえて、各動機の現在の強さを評価する。「Active化 / 凍結継続 / クローズ」を判断する。凍結継続の場合、その理由が動機の弱さではなく他条件の未充足 (in-session 移行の XL 規模実装コスト、比較データの再取得要否など、ステップ2で具体的に特定されたもの) であることを明示する。補償層 (respawn 17/17) との関係 — in-session 移行が「補償層を不要にする根本策」か「補償層と併存する別軸の改善」かを判断に含める。以上を #598 への単一コメントとして投稿する (`gh issue comment 598`)。(after 2) (→ AC1, AC2, AC4)

4. 凍結継続と判断した場合、#598 の Issue 本文「再評価トリガー」節を更新する: `gh issue view 598 --json body --jq .body` で現在の本文を取得し (取得失敗時は本文を上書きせず中断する)、ステップ2で判明した「#587結論後 + Fable5復帰後」トリガーの成立状況を反映 (成立済みとして解消するか、比較データの再取得を要求する形に書き換えるかはステップ2の評価に従う) するとともに、external kill 由来のトリガーを強化する方向で追加・書き換える (Issue 本文が明示的に撤回した「削除または書き換え」ではなく「強化」)。既存の 3 トリガーの記法・形式に準拠させる。更新後の本文を `.tmp/` に Write ツールで書き出し、`scripts/gh-issue-edit.sh 598 <file>` で反映する。Active化 または クローズと判断した場合、この手順は対象外 (N/A) と記録する。(after 3) (→ AC3)

5. Wholework の永続 memory `project_icebox_index.md` の #598 行を更新する (現行の「半発火 + 再評価中 (#1382)」表記を、ステップ3の判断結果とステップ4のトリガー更新状況を反映した内容に書き換える)。`project_external_kill_pattern.md` の記載内容と矛盾がないか確認する (矛盾があれば追記、なければ確認のみで編集不要)。(after 3, 4) (→ AC5)

## Verification

### Pre-merge

None (診断・判断のみで実装差分を伴わない Issue のため — Issue 本文 `### Pre-merge (auto-verified)` に準拠)

### Post-merge

- #598 の動機を「external kill 回避」と「それ以外」(spawn-and-block のオーバーヘッド、親セッションの文脈保持、フェーズ間の状態受け渡し、`wrapper_exit_code` の観測不能性など) に分解し、前者が 2026-08-16 のバーストで復権したことを踏まえたうえで各動機の現在の強さが評価されている <!-- verify-type: manual -->
- 「Active化 / 凍結継続 / クローズ」の判断と根拠が #598 にコメントとして記録されている。凍結継続の場合、その理由が動機の弱さではなく他条件の未充足であることが明示されている <!-- verify-type: manual -->
- 凍結継続の場合、再評価トリガーが更新されている。当初 AC が想定していた「external kill 由来の条件は削除または書き換え」は撤回する — external kill 由来の条件はむしろ強化する方向で書き換える <!-- verify-type: manual -->
- 補償層 (respawn) との関係が整理されている。補償層は 15/15 で全 kill を吸収しており実務上は回っている — in-session 移行が「補償層を不要にする根本策」なのか「補償層と併存する別軸の改善」なのかを判断に含める <!-- verify-type: manual -->
- Icebox index の memory との整合が取れている (半発火状態の更新を含む) <!-- verify-type: manual -->

## Notes

- **verify-type: manual の妥当性**: 評価対象が GitHub Issue 本文・コメント (#598 側) という本 Issue (#1382) 自身の git diff 外にあるリポジトリ外の状態であり、`rubric` のグレーダー入力範囲 (Issue 本文 + git diff + rubric 文中で明示したファイル、`modules/verify-executor.md` § Rubric Command Semantics) には #1382 自身の本文と diff しか含まれず、#598 側の内容には及ばない。判断の質 (動機分解の妥当性、判断根拠の明示性) も主観的判断を要するため機械判定は不採用。#1381 (`docs/spec/issue-1381-respawn-layer-scaledown.md`) の precedent と同じ判断。
- **audit/investigation-type 判定**: 否 — 分類対象は #598 という単一の Icebox 候補であり、`/spec` Step 6 が定義する「複数の既存項目を定義済みカテゴリに分類する」条件を厳密には満たさない。ただし Implementation Steps が判断根拠として複数の具体的識別子 (#587 の PASS 記録、#1395 の CLOSED 状態、`docs/reports/watchdog-recovery-strategy.md:126` など) を引用するため、#1274/#1276 の教訓 (メモリ/推測からの引用が誤りだった) に倣い、本 Spec 作成時点でこれらすべてを `gh issue view` / `grep` で実在・現状確認済み。/code 実行時、Spec 作成からの時間経過で状態が変わっている可能性がある (#1146 系は急速に動いている) ため、再度現状確認すること。
- **Issue 本文との食い違い (Step 6 conflict detection、SPEC_DEPTH=light のため Notes 記録のみ)**: Issue 本文 Notes は「Fable 5 復帰待ちという既存トリガーは... 未充足のまま残る」「最も可能性が高い着地は凍結継続、理由は Fable 5 待ち」と述べるが、Spec 作成時の調査で #598 自身の再評価トリガー「#587結論後 + Fable5復帰後」は両条件とも文面上成立していることが判明した (#587 は比較データ産出済みで CLOSED、Fable 5 は 2026-07-01 再デプロイ済み)。ただし #587 の比較基準 (Opus 4.8 親) 自体が Sonnet 5 / Opus 5 のリリースで陳腐化しているため、この成立が #598 の判断にどれだけの実質的重みを持つかは別途評価が必要 (Implementation Step 2)。非対話モードのため AskUserQuestion は使わず、この食い違いを Implementation Steps に組み込むことで auto-resolve した。
- **Diff-less / operate route の判定根拠**: `## Changed Files` にリポジトリファイルのエントリなし、`## Implementation Steps` の各項目は GitHub CLI 操作 (`gh issue comment` / `gh-issue-edit.sh`) と Wholework 永続 memory ファイル (git 管理外) への書き込みのみで、リポジトリへのコミットを伴う手順はない。`/spec` Step 18 の Diff-less Axis 判定で `ROUTE=operate` に解決されることを想定している。
- **read-then-write ガード**: Implementation Step 4 (#598 本文更新) は read-then-write 操作。`gh issue view 598 --json body --jq .body` の取得失敗時は本文を上書きせず中断することを明示している。
- **#596 との整合について**: Issue 本文 Notes に準拠し、本 Issue の AC 対象外として扱う。判断過程で #596 との扱いを揃えるべきと分かった場合は #598 へのコメントに一言記録するに留め、新規 AC・新規 Issue は起票しない。
- **SPEC_DEPTH=light**: Step 7 (Ambiguity Resolution) の形式的な Auto-Resolve Log は生成していない。上記 Notes は Spec 作成時の調査に基づく判断メモである。曖昧性 3 件 (AC3/AC4/AC5 の記録先解釈) は `/issue` フェーズで既に Issue 本文の「Auto-Resolved Ambiguity Points」節に解決済み。
- **精度確認済みの数値** (`modules/measurement-scope.md` 準拠): 補償層実績 17/17 (`docs/reports/external-kill-investigation.md` § 2026-08-17 Update 時点、Issue 本文記載の「15/15」は起票時点 2026-08-16 の値で 8/17 バースト分が未反映 — Implementation Step 3 は現在値 17/17 を使用する)。kill 率格差 background 1.45%/dispatch 対 foreground 0.007%/dispatch (上流 #76974 実測値、同 report § 2026-08-16 Update 引用)。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / [comment](https://github.com/saitoco/wholework/issues/1382#issuecomment-5325739215)
  - 内容: `/issue` フェーズの Issue Retrospective。起票時 (2026-08-16) の前提撤回の経緯説明と、非対話モードでの refinement 内容 (AC の Pre-merge/Post-merge 再構成、`implementation-type: metadata-only` マーカー付与、曖昧性 3 件の Auto-Resolve ログ) を記録している。本文は既にこの内容を反映済みであり、本 Spec に追加で取り込むべき新規情報はなし。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜5 を記載順にそのまま実行した。Step 4 の対象を「再評価トリガー」節のみに限定した点も Spec の指定通り (「凍結理由」節は未変更のまま残しており、Issue #598 のコメント履歴で背景を追える構成にした)。

### Design Gaps/Ambiguities

- Spec Notes は「Issue 本文の想定 (最も可能性が高い着地は『凍結継続、理由は Fable 5 待ち』) と Spec 作成時点調査の食い違い」を明示的に Implementation Step に組み込んでいた。実際の判断はこの食い違いの通り、「Fable 5 待ち」ではなく「H-a 未確定 + 補償層が実務上機能中」を凍結継続の理由とした — Spec の事前調査が正しく判断を導いた事例として記録する。
- AC4 (補償層との関係整理) は「根本策 or 別軸の改善」の二択で問われていたが、実際の判断は「H-a が対象とする機構 (background task-supervision kill) には根本的に効くが、genuine hang や CI インフラ障害由来の kill には効かないため、どちらか一方ではなく両立する」という中間的な結論になった。#598 へのコメント §4 に記録済み。

### Rework

N/A — 手戻りなし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- #598 を凍結継続と判断。理由は動機の弱さではなく (1) H-a (harness episodic background-task supervision) が未確定、(2) 補償層 (respawn) が 17/17 で実務上 100% 機能中、の 2 点
- 旧再評価トリガー (#587結論後 + Fable5復帰後) は文面上成立済みだが、#587 の比較データが #1165 により再取得断念済みで実質空洞化していたため「解消」として取り消し線付きで記録し、H-a 確定 / 補償層取りこぼしの 2 条件に置き換えた
- 補償層との関係は「根本策」「別軸の改善」の二択ではなく、対象とする kill 機構によって両方の性質を持つと整理した

### Deferred Items
- #596 (XL 並列度の adaptive throttling) との扱い揃えは、Issue #1382 本文 Notes の指示通りスコープ外とし、#598 へのコメント §6 に一言記録するに留めた。新規 Issue・新規 AC は起票していない
- H-a 確定に向けた `WHOLEWORK_SPAWN_DETACH=1` 対照実験は `docs/reports/external-kill-investigation.md` が「スケジュール不能なバーストを1回消費するため現時点では実行不能」としており、本 Issue のスコープ外のまま未着手

### Notes for Next Phase
- 本 Issue は `implementation-type: metadata-only` (operate route) であり、リポジトリへの実装差分はない。post-merge AC 5 件はすべて `verify-type: manual` — `/verify` は #598 へのコメントと本文更新を目視確認する
- #598 の新トリガーは GitHub 上 (Issue #598 本文) が正本。本 Spec とコメントは判断根拠の記録
