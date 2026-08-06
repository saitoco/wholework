# Issue #1058: code: Spec ファイルの編集先を一貫させ並行編集コンフリクトを防ぐ

## Overview

Spec ファイル (`docs/spec/issue-N-*.md`) への追記先が、実行主体によって base ブランチと PR ブランチに分かれている。結果として同一ファイルが両側で並行編集され、merge 時にコンフリクトする (#1186 / #1163 / downstream 1 件で実測)。

書き込み先が分岐する正確な位置は 2 経路ある。本 Issue は **経路 (a)** を扱う。

| 経路 | 内容 | 扱い |
|---|---|---|
| (a) bash wrapper の post-processor | `scripts/run-code.sh:367-374` / `scripts/run-spec.sh:202-209` が `_append_consumed_comments_section()` を `claude` subprocess の **exit 後** に呼ぶ。その時点の CWD は worktree ではなく main repository のため、`append-consumed-comments-section.sh` は main の Spec を編集し `git push origin HEAD` で base へ直接 push する | **本 Issue** |
| (b) SKILL.md のステップ順序 | `skills/code/SKILL.md` の Comment Consumption が Step 1、Worktree Entry が Step 2 の順で、LLM が worktree 作成前に main の Spec を Edit する | #1078 (別 Issue) |

`/code` の **pr route** では LLM 側の Spec 追記 (Code Retrospective) が PR ブランチに載るのに対し、(a) の post-processor は main に載るため、同一ファイルが 2 ブランチに分岐する。これがコンフリクトの構造的原因である。

さらに副次的な欠陥として、pr route では post-processor の発火判定 (`_POST_COUNT <= _PRE_COUNT`) が **main の Spec ファイルを見ている**ため worktree 側の追記を観測できず、LLM が正しく書いた場合でも常に fallback が発火する。#1186 の `aa416dfe Add consumed comments fallback ...` はこの誤発火である。

## Changed Files

- `scripts/append-consumed-comments-section.sh`: `--no-push` フラグ追加 (フラグ指定時は commit のみ行い push しない)。main tree で実行された場合の `git push origin HEAD` を `worktree-merge-push.sh --base "$(git rev-parse --abbrev-ref HEAD)"` によるロック付き push に置換 — bash 3.2+ 互換 (`mapfile` 等の bash 4+ 構文を導入しない)
- `scripts/run-code.sh`: post-processor fallback ブロック (L367-374) を、`reconcile-phase-state.sh` が観測した実際の open PR 番号 (`_PR_NUM`) が空の場合のみ実行するようゲート (実装時に `ROUTE_FLAG != "--pr"` から変更 — `ROUTE_FLAG` だけでは Size auto-detection 等による auto-detected pr route を判定できないため、review #1201 指摘)。pr route では Spec の書き込み先が PR ブランチであり main repository からは観測も安全な書き込みもできないため — bash 3.2+ 互換
- `skills/code/SKILL.md`: Step 12 の `git add` 直前に `append-consumed-comments-section.sh $NUMBER code --no-push` の必須 bash 呼び出しを追加。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` を追加 (現在は未登録)
- `skills/spec/SKILL.md`: Step 13 の `git add` 直前に `append-consumed-comments-section.sh $NUMBER spec --no-push` の必須 bash 呼び出しを追加。frontmatter `allowed-tools` に同エントリを追加 (現在は未登録)
- `modules/worktree-lifecycle.md`: Notes に「Spec file write destination」節を新設 — 「Spec ファイルはフェーズ自身の作業ブランチ (worktree ブランチ / PR ブランチ) 上でのみ編集し、base へは既存の Exit 経路 (`worktree-merge-push.sh` または PR merge) 経由でのみ反映する」という規約を明文化する。`## Consumed Comments` との相互作用にも言及する
- `modules/l0-surfaces.md`: L248-255 の「Bash wrapper fallback (Issue #811)」の 2 bullet を、新しい配置 (`/spec` `/code` `/verify` いずれも in-session mandatory call、wrapper post-processor は非 pr route のみ) に合わせて書き換え
- `tests/append-consumed-comments-section.bats`: `--no-push` 指定時に push されないこと、main tree 実行時に `worktree-merge-push.sh` が呼ばれることを検証するテストを追加。`setup()` の `$MOCK_DIR` に `worktree-merge-push.sh` のモックを追加する (`WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` が設定済みのため必須)
- `tests/run-code.bats`: pr route で `_append_consumed_comments_section` が呼ばれないことを検証するテストを追加 (既存の L511 "fallback: no consumed comments section before and after claude → _append_consumed_comments_section called" と同じモック構造を流用)
- `docs/structure.md`: L172 の `scripts/append-consumed-comments-section.sh` の説明文を新しい呼び出し構成に更新 [Steering Docs sync candidate]
- `docs/ja/structure.md`: L165 の同じ行を日本語ミラーとして同期 (`docs/translation-workflow.md` の Sync Procedure に従う) [Steering Docs sync candidate]

## Implementation Steps

1. `scripts/append-consumed-comments-section.sh` に `--no-push` フラグを追加し、main tree 判定 (既存の `_git_dir == _git_common_dir` チェック) が真のときの push を `worktree-merge-push.sh --base "$(git -C "$_repo_root" rev-parse --abbrev-ref HEAD)"` に置き換える。失敗時は既存同様 best-effort 警告のみ (→ acceptance criteria 2)
2. `scripts/run-code.sh` の post-processor fallback ブロックの条件を、`reconcile-phase-state.sh` が観測した open PR 番号 (`_PR_NUM`) が空かどうかで判定するよう変更し、pr route では wrapper が Spec を編集しないようにする。スキップ理由を同ブロックのコメントに記載する (実装時に判定軸を `ROUTE_FLAG` から `_PR_NUM` に変更 — review #1201 指摘。auto-detected pr route を `ROUTE_FLAG` だけでは判定できないため) (→ acceptance criteria 2)
3. `skills/code/SKILL.md` Step 12 の retrospective commit ブロックの**直後**に、`bash ${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh $NUMBER code --no-push` の必須呼び出しを追加する。あわせて frontmatter の `allowed-tools` に該当エントリを追加する (after 1) (→ acceptance criteria 2) (実装時に「commit の直前」から「commit の直後」に変更 — 直前に置くと、未コミットの retrospective / Phase Handoff 編集がスクリプト自身の commit に巻き込まれてしまうため)
4. `skills/spec/SKILL.md` Step 13 の commit ブロックの**直後**に、`bash ${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh $NUMBER spec --no-push` の必須呼び出しを追加する。あわせて frontmatter の `allowed-tools` に該当エントリを追加する (after 1, parallel with 3) (→ acceptance criteria 2) (実装時に「直前」から「直後」に変更 — 理由は 3 と同様)
5. `modules/worktree-lifecycle.md` の `## Notes` に「Spec file write destination」節 (見出しレベル `###`) を追加し、Spec ファイルの書き込み先規約とフェーズ別の base 反映経路 (`/spec`・`/code` patch/operate・`/verify` は `worktree-merge-push.sh`、`/code` pr は PR merge) を表で明文化する。表には `**(exhaustive)**` マーカーを付す (`modules/skill-dev-checks.md` "Exhaustive/Example Markers") (→ acceptance criteria 1)
6. `modules/l0-surfaces.md` の「Bash wrapper fallback (Issue #811)」節を、新しい 2 層構成 (in-session mandatory call が第一の安全網、wrapper post-processor は非 pr route の第二の安全網) に書き換え、Step 5 で追加した `worktree-lifecycle.md` の節を参照させる (after 5) (→ acceptance criteria 1)
7. `tests/append-consumed-comments-section.bats` の `setup()` に `worktree-merge-push.sh` モックを追加し、`--no-push` 指定時に push されないテストと main tree 実行時に `worktree-merge-push.sh` が呼ばれるテストを追加する (after 1)
8. `tests/run-code.bats` に pr route で `_append_consumed_comments_section` が呼ばれないことを検証するテストを追加する (after 2)
9. `docs/structure.md` と `docs/ja/structure.md` の `append-consumed-comments-section.sh` 説明行を新しい呼び出し構成に更新する (after 1, 2, 3, 4)

## Verification

### Pre-merge

- <!-- verify: rubric "Spec ファイルへの追記先 (base ブランチ / PR ブランチ) が全フェーズで一貫するよう設計が明文化されている" --> `modules/worktree-lifecycle.md` の新設節と `modules/l0-surfaces.md` の書き換えにより、Spec ファイルの書き込み先規約が全フェーズ横断で明文化されている
- <!-- verify: rubric "append-consumed-comments-section.sh と code フェーズの retrospective 追記が同一ブランチを対象とするようになっている" --> `skills/code/SKILL.md` Step 12 の in-session 呼び出しと `scripts/run-code.sh` の pr route ゲートにより、両者が worktree ブランチ (= PR ブランチ) を対象とする

### Post-merge

- pr route の Issue を 1 件通しで実行し、Spec ファイルのコンフリクトが発生しないことを確認する

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/append-consumed-comments-section.sh:*` — `skills/code/SKILL.md` と `skills/spec/SKILL.md` の `allowed-tools` に追加が必要 (両者とも現在未登録。`skills/verify/SKILL.md` には登録済み)

### Built-in Tools

- なし (既存の `Read` / `Edit` / `Write` で足りる)

### MCP Tools

- なし

## Notes

### 新設する分岐の挙動全列挙 (`skills/spec/skill-dev-constraints.md` #642)

**`scripts/append-consumed-comments-section.sh` の push 分岐 (exhaustive):**

| 分岐条件 | 挙動 | 終了コード |
|---|---|---|
| `--no-push` 指定あり | commit まで実行し push をスキップ。スキップした旨を stderr に出力しない (通常経路のため) | 0 |
| `--no-push` なし かつ worktree 内 (`_git_dir != _git_common_dir`) | 従来どおり `git -C "$_repo_root" push origin HEAD` | 0 (push 失敗時も best-effort 警告のみで 0) |
| `--no-push` なし かつ main tree (`_git_dir == _git_common_dir`、いずれも非空) | 既存の defense-in-depth 警告を stderr に出力したうえで、`worktree-merge-push.sh --base "$(git -C "$_repo_root" rev-parse --abbrev-ref HEAD)"` を実行 | 0 (`worktree-merge-push.sh` が非 0 で終了しても best-effort 警告のみで 0) |
| `--no-push` なし かつ `_git_dir` / `_git_common_dir` のいずれかが空 (git 解決失敗) | 非空ガード (`-n "$_git_dir" && -n "$_git_common_dir"`) が真にならないため main tree 分岐に入らず、従来どおり `git -C "$_repo_root" push origin HEAD` にフォールスルー | 0 (push 失敗時も best-effort 警告のみで 0) |
| Spec ファイルに差分なし (`git diff --quiet` が真) | commit も push も実行しない | 0 |

上記 4 分岐目 (非空ガード) は `tests/run-verify.bats` の既存 fixture が `rev-parse --git-dir`/`--git-common-dir` 未実装で両者が空文字を返すことで発覚した実装時のギャップ。Code Retrospective の Deviations from Design に記録済み。

スクリプト全体の best-effort 契約 (常に exit 0) は既存どおり維持し、呼び出し側をブロックしない。

**`scripts/run-code.sh` の post-processor 分岐 (exhaustive):**

判定は `ROUTE_FLAG` (CLI フラグ) ではなく `_PR_NUM` (`reconcile-phase-state.sh` が `worktree-code+issue-N` ブランチに対して観測した実際の open PR 番号) を用いる。route は Size auto-detection や `always-pr: true` により in-session で解決されることがあり (`/code N --auto` は M/L Issue に対しフラグ無しで pr route を選ぶ)、`ROUTE_FLAG` だけでは実際に pr route を通ったかを判定できないため (review #1201 指摘、MUST として修正)。

| 分岐条件 | 挙動 |
|---|---|
| `EXIT_CODE != 0` | 従来どおり post-processor をスキップ |
| `EXIT_CODE == 0` かつ `_PR_NUM` が非空 (open PR が観測された = 実際に pr route を通った) | post-processor をスキップ。Spec の書き込み先は PR ブランチであり main repository からは観測も安全な書き込みもできないため。安全網は `skills/code/SKILL.md` Step 12 の in-session 呼び出しが担う |
| `EXIT_CODE == 0` かつ `_PR_NUM` が空 (open PR 未観測 = patch / operate route) | 従来どおり pre/post カウント比較を行い、増えていなければ `_append_consumed_comments_section` を実行 |

### `validate-skill-syntax.py` の制約

`skills/code/SKILL.md` / `skills/spec/SKILL.md` への追記は bash コードフェンス内に閉じ、本文プロース中に半角感嘆符・3 連バッククォート・小数点付き Step 番号を導入しない。`allowed-tools` に追加するのは `Bash(...)` 内のパターンのみで新規ベースツール名を導入しないため、`scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` (L19-26) の更新は不要。`.claude/settings.json.template` も `Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` のワイルドカードで既にカバーされているため変更不要。

### 案 A / 案 B の評価 (Issue コメント issuecomment-5201930509 の指示に対する回答)

**採用: 案 B (Spec は常にフェーズの作業ブランチ)**。ただし「PR ブランチ」を「フェーズ自身の worktree ブランチ」へ一般化し、base へは既存の Exit 経路経由でのみ反映する形とする。

**評価軸 1 — 並行セッション耐性:**

案 A (Spec は常に base) は「並行セッションが base に commit/push する」ことを設計として正当化するため、コメントで実測された 3 事象 (ff-only merge 失敗 → rebase fallback がセッション全体で 4 回以上、進行中セッションの dirty による `git pull --ff-only` 失敗、`check-verify-dirty.sh` exit 2) の頻度をいずれも押し上げる。加えて案 A を `/code` pr route に適用すると、worktree ブランチにコミットする実装差分とは別に Spec だけを base へ運ぶ第 2 の経路が必要になり、**pr route の全実行が新たに base への push を 1 回追加する**。並行耐性の観点では案 A は明確に劣る。

案 B では base への書き込みが `worktree-merge-push.sh` (patch lock + fetch-after-lock + push retry + #1076 の rebase fallback) に一本化される。これは `/verify` が Issue #1037 で既に到達した結論と同一であり、`skills/verify/SKILL.md` L130 に「Step 3 (Worktree Entry) をスキップすると `append-consumed-comments-section.sh` が worktree 外のブランチへ直接 commit/push し、`worktree-merge-push.sh` のロック機構をバイパスして race のリスクがある」と明記されている。本 Issue はこの既存規約を `/spec` と `/code` にも適用するもので、新規の設計判断ではなく**既存パターンへの整合**である。

**評価軸 2 — patch route での案 B の実現コスト:**

triage は案 B を「patch route (PR なし) との整合を新たに設計する必要があり変更範囲が広い」として退けたが、実測すると**追加設計はほぼ不要**だった。patch route は既に worktree で作業し `worktree-merge-push.sh` で base へ merge する構造を持つため (`skills/code/SKILL.md` Step 14 "patch route (merge-to-main pattern)")、Spec 追記も同じ経路にそのまま載る。本 Spec の patch route 向け変更は Step 3 の in-session 呼び出し 1 行のみで、`worktree-merge-push.sh` 側の変更は不要。

**triage が挙げた案 A の論拠に対する応答:**

- 「`/spec` は既に base へ直接コミットしている」— 正確には `ENTERED_WORKTREE=false` のときのみ直接 push であり、`ENTERED_WORKTREE=true` (`run-spec.sh` 経由の通常経路) では `worktree-merge-push.sh --from` を通す。つまり `/spec` の主経路は既に案 B 側である
- 「変更対象が `/code` 側の 1 経路に閉じる」— 案 B も変更対象は同じ 1 経路 (wrapper post-processor) に閉じており、変更ファイル数の差はない
- 「案 C は根治しない」— 同意。案 C は不採用

### 棚卸しスコープの判断 (Issue Related セクションの未確定事項に対する回答)

**別 Issue へ切り出す。本 Issue には含めない。**

- 本 Issue の AC 2 件はいずれも「Spec ファイルの書き込み先」に限定されており、全 skill / script 横断の監査は AC が要求する範囲を超える
- 監査は「調査 → 発見ごとに個別の修正」という発散型の作業で、発見のそれぞれが独立した Issue になる性質を持つ。本 Issue の pr route ゲートと in-session 呼び出しの着地を待たずに並行させると、監査結果と本 Issue の変更が衝突する
- 監査の**方針**にあたる部分 (Spec ファイルの書き込み先規約) は本 Issue の AC1 で `modules/worktree-lifecycle.md` に明文化されるため、切り出し先の Issue はその規約を前提に**掃き出し**だけを行えばよい

切り出し先の Issue を起票する際は以下を前提として引き継ぐこと:
- #1078 (`/code` Step 1 の Consumed Comments 追記が worktree fresh 作成時に失われうる) と重複しないこと。#1078 は同じ症状の別経路 (SKILL.md のステップ順序) を扱う
- 本 Issue が扱う wrapper post-processor 経路も既に処理済みとして除外すること
- 監査起点リストは issuecomment-5200989170 に記載済み (Worktree Entry より前のファイル書き込み / subprocess exit 後の後処理 / repo root を解決する 8 スクリプト / 意図的に main へ書く箇所)

起票そのものは本 Spec の実装範囲外とし、`/verify` の Improvement Proposal 集約 (`modules/retro-proposals.md`) に委ねる。

### pr route の wrapper fallback を「無効化」とした理由 (自動解決)

pr route で書き込み先を揃える手段は 2 つある。

| 案 | 内容 | 判定 |
|---|---|---|
| 無効化 (採用) | wrapper post-processor を pr route ではスキップし、安全網を `skills/code/SKILL.md` Step 12 の in-session mandatory call に一本化する | 採用 |
| PR ブランチへ書き込む | wrapper が `git fetch origin <pr-branch>` → 一時 worktree 作成 → 追記・commit → `git push origin HEAD:refs/heads/<pr-branch>` を行う | 不採用 |

不採用の理由: (1) main repository 側から他ブランチへ書き戻す新しい経路を増やすことになり、本 Issue が解消しようとしている「書き込み先の分散」を別の形で再導入する、(2) 一時 worktree の作成・削除は並行セッション下で `git worktree` の競合を新たに生む、(3) `/verify` が Issue #1037 で確立した in-session パターンで同じ保証が得られる。

なお pr route の wrapper fallback は現状ほぼ常に誤発火しており (Overview 末尾参照)、無効化による安全網の実質的な損失はない。

### AC を rubric のまま維持した理由

`modules/verify-patterns.md` §9 は rubric に決定的な `file_contains` を併記することを推奨するが、Issue コメント (issuecomment-5201930509) が「結果指向の rubric AC は変更不要」と明示しているため、Pre-merge AC 2 件は Issue 本文からそのまま転記し、決定的 verify command の追加は行わない。Spec 側の Verification 項目本文で対象ファイルを具体的に示すことで、`/review` / `/verify` 時の判定材料を補っている。

### `origin/worktree-*` ブランチの残留 (`--no-push` を導入する理由)

`append-consumed-comments-section.sh` は現在 worktree 内で実行されると `git push origin HEAD` により worktree ブランチを origin へ push する。本リポジトリ (`saitoco/wholework`) の `git branch -r` 実測 (2026-08-06 時点、リモートブランチ計 60 本) では、この経路により `origin/worktree-verify+issue-*` が 16 本残留していた。`/spec` と `/code` patch route にも同じパターンを無条件に適用すると Issue 1 件あたり最大 2 本の残留ブランチが追加されるため、新規呼び出し箇所には `--no-push` を指定する。

`--no-push` でも base への反映は損なわれない: `/code` pr route は Step 12 で直後に `git push origin HEAD` を実行し、`/code` patch/operate route と `/spec` は Step 14 の `worktree-merge-push.sh` で base へ merge される。

既存の `skills/verify/SKILL.md` L153 の呼び出しは本 Issue では変更しない (`/verify` の挙動変更は AC の要求範囲外)。`/verify` 側の残留ブランチ解消は独立した改善候補として spec retrospective に記録する。

### base ブランチ非 `main` 時の扱い

`worktree-merge-push.sh` の `--base` 既定値は `main` だが、`run-code.sh` は `--base` フラグをサポートする。main tree での実行時は HEAD が base ブランチそのものであるため、`--base "$(git -C "$_repo_root" rev-parse --abbrev-ref HEAD)"` を渡すことで非 `main` base でも正しく動作する。`append-consumed-comments-section.sh` に新たな `--base` フラグを追加する必要はない。

### Issue 本文との整合

Issue 本文 Related の「`scripts/append-consumed-comments-section.sh` (base ブランチへ書き込み)」は、スクリプト自体は `git rev-parse --show-toplevel` で CWD からリポジトリルートを解決する worktree 対応済み実装 (L21) であり、base へ書くのは呼び出し位置の帰結である。この訂正は 2026-08-06 のコメントと Issue 本文 Background に既に反映されており、未解決のコンフリクトはない。

### bats テストの前提

- `tests/append-consumed-comments-section.bats` は `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定済みのため、`append-consumed-comments-section.sh` が新たに呼び出す `worktree-merge-push.sh` は `$MOCK_DIR` にモックを置かないと解決できない。Step 7 でモック追加を必須とする
- `$MOCK_DIR/git` モックは `rev-parse --git-dir` / `rev-parse --git-common-dir` に異なる値を返して「worktree 内」を模擬している (L47-54)。main tree 経路のテストでは両者が同値を返すようモックを分岐させる必要がある
- `tests/run-code.bats` は `_append_consumed_comments_section() { echo "CALLED \$*" >> "${FALLBACK_LOG}"; }` でスタブ化する既存パターン (L511-) を持つため、pr route での非呼び出しは同じログファイルが空であることで検証できる

## Consumed Comments

- saito / MEMBER / first-class / `## Issue Retrospective` — `/issue` の自動解決ログ (案 A 推奨、post-merge verify-type を observation へ変更) / https://github.com/saitoco/wholework/issues/1058#issuecomment-5201478146
- saito / MEMBER / first-class / `## /spec への申し送り: 案 A / 案 B を並行耐性の軸で再評価すること` — 並行セッション耐性と patch route コストの 2 軸追加、棚卸しスコープの判断依頼 / https://github.com/saitoco/wholework/issues/1058#issuecomment-5201930509

cutoff: 2026-08-06T07:00:47Z (`phase/issue` ラベル付与時刻)。cutoff 以前の issuecomment-5200989170 (2026-08-06T06:04:28Z) は Issue 本文 Background に既に反映済みのため、本フェーズの前提として参照した。

## issue retrospective

`--non-interactive` モードで既存 Issue の refinement を実行した。

### 曖昧性の自動解決 (Auto-Resolve Log)

- **検討候補 A/B/C のうち `/spec` への推奨方針**: 案 A (Spec は常に base ブランチ) を Auto-Resolved Ambiguity Points セクションに明記した。
  - 理由: `/spec` は既に `ENTERED_WORKTREE=false` 時 `git push origin main` で base へ直接コミットする既存パターンがあり (`skills/spec/SKILL.md`)、`/code` pr route の Code Retrospective 追記のみが `git push origin HEAD` で worktree ブランチ (= PR ブランチ) 行きになっていることをコード上で確認した (`skills/code/SKILL.md` Step 12)。案 A は既存パターンとの整合性が高く、変更範囲が `/code` 側の 1 経路に閉じる。
  - 他候補: 案 B は patch route との整合を新設する必要があり範囲が広い。案 C は根治的ではない。
  - AC 自体は結果指向の rubric のまま変更していない — 実装手段の選択は `/spec` に委ねる。
- **Post-merge 条件の verify-type**: `manual` → `observation event=auto-run when=route:pr session=next` に変更した。
  - 理由: 条件文「次に pr route の Issue が実行された際にコンフリクトが発生しないことを確認する」は `modules/verify-classifier.md` の observation 分類基準 (event-driven な観測条件) に合致する。`when=route:pr` で `/auto` 実行時の route 軸に絞り込める (`modules/observation-trigger.md`)。本 Issue が `skills/code/SKILL.md` の変更を伴う可能性が高く、観測対象がその変更後の挙動そのものであるため `session=next` を付与した (`scripts/check-skill-change-observation-ac.sh` で warning なしを確認済み)。

### 検証済みの事実確認 (Background Factual Claim Verification)

Background の「`append-consumed-comments-section.sh` は main へ、`/code` の retrospective 追記は worktree へ書く」というクレームをコード上で確認し、事実と一致することを確認した。合わせて、2026-08-06 の追記コメントで特定された「問題は post-processor の呼び出し位置 (`scripts/run-code.sh` / `scripts/run-spec.sh` の subprocess exit 後)」という詳細を Background に短く反映した (フルコンテキストはコメントを参照する形を維持)。

### スコープ拡張 (棚卸し) の扱い

2026-08-06 のコメントで提案された「worktree セッション中の main repository 書き込み全般の棚卸し」は、コメント内で既に `/spec` での判断に委ねると明記されていたため、本 refinement では決定せず Related セクションに参照を追加するに留めた。

### チェックスクリプト結果

- `check-skill-change-observation-ac.sh`: exit 0 (警告なし)
- `check-ac-checkbox-format.sh`: exit 0 (フォーマット違反なし)
- `gh-check-blocking.sh`: exit 0 (未解決の blocked-by なし)

### Size / タイトル

Size は既に `L` (変更なし)。タイトルとの意味的乖離は検出されなかったため変更していない。

## spec retrospective

### Autonomous Auto-Resolve Log

- **案 B (Spec は常にフェーズの作業ブランチ) を採用** — 理由: `/issue` triage は案 A を推奨したが、その判断軸には並行セッション耐性が含まれていなかった。`/verify` が Issue #1037 で既に案 B 側の規約に到達しており (`skills/verify/SKILL.md` L130 に明文化済み)、base への書き込みを `worktree-merge-push.sh` のロック機構に一本化できる。patch route の追加コストも実測すると in-session 呼び出し 1 行のみで、triage が想定した「変更範囲が広い」は成立しなかった。
  - 他候補: 案 A (pr route の全実行が base への push を 1 回追加し、実測済みの ff-only 失敗事象を増やす)、案 C (コンフリクト確率を下げるのみで根治しない)
- **棚卸しスコープは別 Issue へ切り出す** — 理由: 本 Issue の AC 2 件はいずれも Spec ファイルの書き込み先に限定されており、全 skill / script 横断の監査は AC の範囲外。監査は発見ごとに独立した修正へ発散する性質を持ち、本 Issue の変更着地前に並行させると衝突する。監査の方針にあたる規約は本 Issue の AC1 で明文化されるため、切り出し先は掃き出しに専念できる。
  - 他候補: 本 Issue に含める (AC がカバーせず、Size L の見積もりも崩れる)
- **pr route の wrapper fallback は「PR ブランチへ書き込む」ではなく「無効化」** — 理由: main repository から他ブランチへ書き戻す経路を新設すると、本 Issue が解消しようとしている書き込み先の分散を別の形で再導入する。一時 worktree の作成・削除も並行セッション下で新たな競合源になる。
  - 他候補: wrapper が fetch + 一時 worktree 経由で PR ブランチへ push する
- **新規呼び出し箇所には `--no-push` を指定** — 理由: `append-consumed-comments-section.sh` の `git push origin HEAD` により `origin/worktree-verify+issue-*` が 16 本残留している実測があり、`/spec` と `/code` patch route に無条件適用すると Issue 1 件あたり最大 2 本増える。base への反映は各フェーズの Exit 経路が担保するため push は不要。
  - 他候補: 無条件に push する (残留ブランチが増える)、`/verify` も含めて一括で `--no-push` 化する (AC の範囲外の挙動変更)

### Minor observations

- `origin/worktree-verify+issue-*` が 16 本残留している (本リポジトリの `git branch -r` 実測、2026-08-06 時点、リモートブランチ計 60 本)。`/verify` の `append-consumed-comments-section.sh` 呼び出しが worktree ブランチを push するためで、本 Issue では `/verify` を変更対象外としたため解消しない。`--no-push` を `/verify` にも適用すれば解消できる独立した改善候補。
- `run-code.sh` / `run-spec.sh` の pre/post カウント比較は `## Consumed Comments` の**見出し数**を数えているため、`/spec` フェーズで見出しが作られた後は増分が発生せず、patch route では毎回 fallback が発火する。スクリプトが URL 単位で冪等なため無害だが、実行ごとに `gh api` + `gh issue view` のコストが掛かっている。本 Issue の pr route ゲートはこの誤発火のうち pr route 分のみを解消する。
- `docs/spec/issue-1069-html-check-css-combinator.md` の retrospective は「`append-consumed-comments-section.sh` の dedup ガードが見出し単位のため `/verify` の安全網が構造的に発火しない」と記録しているが、現行実装 (L106-165) は既存セクションへの URL 単位 dedup 追記に修正済みで、この記述は現行実装と乖離している。過去 Spec の retrospective を根拠に設計判断する際は実装との突き合わせが要る事例。

### Judgment rationale

- Issue 本文の Related は `append-consumed-comments-section.sh` を「base ブランチへ書き込み」と記していたが、スクリプト自体は `git rev-parse --show-toplevel` (L21) で CWD からリポジトリルートを解決する worktree 対応済み実装であり、base へ書くのは呼び出し位置の帰結である。この訂正は 2026-08-06 のコメントと Background に既に反映済みだったため、Issue 本文との未解決コンフリクトとしては扱わなかった。
- Pre-merge AC 2 件はいずれも rubric のみで決定的な `file_contains` を伴わない。`modules/verify-patterns.md` §9 は決定的な併記を推奨するが、Issue コメントが「結果指向の rubric AC は変更不要」と明示していたため追加せず、Spec 側の Verification 項目本文で対象ファイルを具体化することで判定材料を補った。AC 件数の整合 (Issue 2 件 / Spec 2 件) も維持されている。
- `/code` pr route の安全網を in-session 呼び出しに一本化することで、Issue #811 が wrapper に求めた「LLM のプロース実行に依存しない決定性」は pr route では失われる。`/verify` が同じトレードオフを受け入れている先例があること、および pr route の wrapper fallback が現状ほぼ常に誤発火していて安全網として機能していないことから、実質的な後退はないと判断した。

### Uncertainty resolution

- ISSUE_TYPE=Task のため Uncertainty セクションは省略した。設計時点で外部仕様への未検証依存はなく、`git worktree` / `git push` の挙動はいずれもローカル実測で確認できる既知仕様だった。
- `worktree-merge-push.sh` の `--base` 既定値が `main` である点は、main tree では HEAD が base ブランチそのものであることを利用し `--base "$(git rev-parse --abbrev-ref HEAD)"` を渡すことで解決した。`append-consumed-comments-section.sh` に `--base` フラグを新設する必要はない。
- `tests/append-consumed-comments-section.bats` は `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定済みのため、新たに呼ばれる `worktree-merge-push.sh` のモック追加が必須である点を Implementation Steps 7 に明記した。`$MOCK_DIR/git` モックが `rev-parse --git-dir` と `rev-parse --git-common-dir` に異なる値を返して worktree 内を模擬している (L47-54) ことも確認済み。

## Code Retrospective

### Deviations from Design

- The `-n` guard fix recorded under Design Gaps/Ambiguities below is the only *code-behavior* deviation from the original plan. Additionally, three *documentation* deviations were identified in `/review` (#1201) and corrected here: (1) Implementation Step 2 / Changed Files described `scripts/run-code.sh`'s post-processor gate as `ROUTE_FLAG != "--pr"`; the actual implementation gates on the observed open-PR number (`_PR_NUM`) instead, since `ROUTE_FLAG` alone cannot distinguish an auto-detected pr route (Size auto-detection, `always-pr: true`) from patch route. (2) Implementation Steps 3/4 described the `skills/code/SKILL.md` / `skills/spec/SKILL.md` safety-net calls as placed *before* the retrospective/handoff commit; the actual implementation places them *after*, to avoid the safety-net script's own commit sweeping up not-yet-committed retrospective/handoff edits. Both Changed Files and Implementation Steps above have been updated to match.

### Design Gaps/Ambiguities

- `tests/run-verify.bats` was not listed in Changed Files but broke on first full-suite run: its `git` mock does not implement `rev-parse --git-dir`/`--git-common-dir` (both calls fall through to the default branch and return an empty string), and the new main-tree push-routing check in `append-consumed-comments-section.sh` originally compared `"$_git_dir" == "$_git_common_dir"` without the non-empty guard the adjacent defense-in-depth warning check already had — two empty strings compare equal, so it misclassified this fixture as "main tree" and called the (unmocked) `worktree-merge-push.sh` instead of `git push origin HEAD`. Fixed by adding the same `-n "$_git_dir" && -n "$_git_common_dir"` guard to the routing check (Implementation Step 1). The Spec's own Changed Files list scoped `tests/run-verify.bats` out because #1058 does not modify `/verify`'s call site, but a script-level behavior change still has to satisfy every existing caller's test fixture, not just the ones the Spec enumerates — the Step 9 Behavioral Change Detection full-suite override (triggered because `append-consumed-comments-section.sh` is referenced by more than its direct-counterpart test) is what caught this, confirming that override's value beyond narrow-scope test runs.
- Executing this Issue's own `/code` run reproduced the sibling defect this Issue's Related section attributes to #1078: `skills/code/SKILL.md`'s Comment Consumption (Step 1) runs before Worktree Entry (Step 2), so writing the code-phase `## Consumed Comments` entry per that step order edited the main repository's Spec copy directly, before `EnterWorktree` was called. That edit never reached the worktree branch and was left as an uncommitted diff in the main repository, requiring manual reconciliation after Worktree Exit. This is out of scope for #1058 (which explicitly handles only the wrapper post-processor path, route (a), and defers the SKILL.md step-order path to #1078) but is recorded here as a concrete, first-hand reproduction for whoever picks up #1078.

### Rework

- The `-n` guard fix above was the only rework cycle: full-suite `bats tests/` surfaced the `tests/run-verify.bats` failure, root-caused to the missing guard, fixed, and the full suite re-run clean (1443/1443).

## review retrospective

### Spec vs. implementation divergence patterns

- The code phase's own Code Retrospective claimed "Deviations from Design: None" while the implementation actually diverged from the Spec's Implementation Steps in three places (post-processor gate axis `ROUTE_FLAG`→`_PR_NUM`; safety-net call position moved from before to after the commit, ×2 SKILL.md sites). The divergence was real but was categorized as "not a design deviation" because it was framed as an in-scope refinement rather than a plan change — this is exactly the kind of self-assessment gap `skills/code/SKILL.md` Step 12 item 4's "update Spec Implementation Steps to match" rule exists to catch, and it was missed at code-phase time. Recommendation: when future review passes find a Spec/implementation mismatch that the Code Retrospective already claims doesn't exist, treat the Retrospective's own "Deviations: None" as a signal worth double-checking, not as evidence the search is unnecessary.
- This PR is itself about eliminating a documentation/implementation split (Spec write-destination inconsistency), and `/review` found the PR's own newly-added documentation (the "Spec file write destination" exhaustive table, the "all in-session callers pass --no-push" claim) had internal self-contradictions on the same axis — new prose asserting completeness/consistency that wasn't actually complete/consistent. Worth naming as a category: "exhaustive-marker" tables and absolute claims ("all", "always") are exactly the phrasing that HIGH SIGNAL review should stress-test hardest, since they're falsified by a single missing case.

### Recurring issues

- Two independent review-bug agents (diff-scan and security-scan) both surfaced the `modules/worktree-lifecycle.md` exhaustive-table gap and the `scripts/run-code.sh:345` stale-`ROUTE_FLAG` inconsistency independently, from different angles — confirms the 2-lens review-bug fan-out has real recall value beyond a single pass, at least for this PR's size/shape.
- `gh-pr-review.sh`'s `HAS_MUST` detection requires each line-comment JSON object to carry an explicit `"severity"` field (documented in the script's own header comment); a line-comments JSON built with severity only embedded in the comment body text (not as a JSON key) silently defaults to `EVENT="COMMENT"` with no error. This is an easy transcription mistake since the severity is *also* human-readable inside the body text, making the omission easy to miss. Separately, and independently of that mistake: the GitHub Pull Request Reviews API rejects `REQUEST_CHANGES` on your own PR (`422 Unprocessable Entity: "Review Can not request changes on your own pull request"`) — a hard platform constraint for any single-maintainer / self-hosted repo where the reviewer and PR author are the same GitHub account. `gh-pr-review.sh` has no handling for this case; a correctly-populated `severity` field would still have hit the same 422 and, per the script's current `|| { echo Error; exit 1; }` handling, aborted the entire review post (comments included) rather than degrading gracefully to `COMMENT`. Both points are worth an improvement proposal for `/verify` to aggregate: (1) `gh-pr-review.sh` should catch the self-review 422 specifically and retry with `event=COMMENT` instead of failing the whole post, and (2) the MUST-issue visibility that `REQUEST_CHANGES` provides needs a non-event-based fallback (e.g. a bolded banner in the review body) for the self-review case, since the event field cannot carry that signal here.

### Acceptance criteria verification difficulty

- Nothing to note. Both Pre-merge conditions used `rubric` verify commands with self-contained, unambiguous text; grading against the worktree's modified files was straightforward and did not surface any UNCERTAIN cases.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- Squash-merged PR #1201 to main after confirming `mergeable=true` (reason=clean, CI success, review approved) and the pre-merge AC gate reported 0 unchecked conditions — no conflict resolution or fallback logic was needed.
- Label-transitioned Issue #1058 to `phase/verify` per Step 5, since `BASE_BRANCH=main` makes the Issue eligible for `closes #N` auto-close.

### Deferred Items

- Carried forward unchanged from the review-phase handoff (not addressed by merge, out of merge's scope): worktree-session main-repository write audit spun out to a future Issue; `/verify`'s own `--no-push` adoption (residual `origin/worktree-verify+issue-*` branches); patch-route pre/post count fallback mis-fire (idempotent, harmless); #1078 (SKILL.md step-order path); `skills/spec/SKILL.md` Step 14's `ENTERED_WORKTREE=false` bare `git push origin main` (documented as a known gap, not fixed); `gh-pr-review.sh`'s missing severity-field validation and self-review-422 handling.

### Notes for Next Phase

- Post-merge AC (observation, `event=auto-run when=route:pr session=next`) is unchanged — still unfired, still SKIPPED by design; `/verify` should leave it SKIPPED unless a pr route Issue has since run in this session.
- Pre-merge AC 1 and 2 were both PASS at merge time (0 unchecked conditions per `check-pre-merge-ac.sh`).

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- triage の Auto-Resolve は案 A を「`/spec` が既に base へ直接コミットしている現状と一致する」ことを主根拠に推奨したが、この既存実装の認識自体が不正確だった (`ENTERED_WORKTREE=false` のときのみ直接 push であり、`run-spec.sh` 経由の主経路は既に `worktree-merge-push.sh` を通る = 案 B 側)。Auto-Resolve が「既存パターンとの整合」を根拠に使う場合、その既存パターンの記述精度が推奨方針の妥当性を直接左右する。
- Post-merge 条件の `verify-type` を `manual` → `observation event=auto-run when=route:pr session=next` へ精緻化した判断は妥当だった。`session=next` の付与により、本 verify で「未発火のため SKIPPED」と正しく判定できた。

#### spec

- Issue コメントで指定した 2 軸 (並行セッション耐性 / patch route での実現コスト) の再評価により、triage の案 A 推奨を案 B へ覆した。特に評価軸 2 は triage が「変更範囲が広い」として退けた前提を実測で否定しており (patch route 向けの変更は in-session 呼び出し 1 行のみ)、未実測の前提に基づく却下を洗い直す指示が有効に機能した事例。
- 副次的欠陥 (pr route の wrapper fallback がほぼ常に誤発火) を Spec 段階で特定できた。`#1186` の `aa416dfe` という既存コミットの正体が判明したことで、無効化の判断に実データの裏付けが付いた。

#### code

- code フェーズ自身が経路 (b) (`#1078` の対象、Comment Consumption が Worktree Entry より前) を踏み、main repository の Spec を直接編集した。本 Issue が扱う経路 (a) を修正するフェーズが、未修正の経路 (b) を同一実行内で実演した形。手動 revert で PR への影響は回避。
- pr route ゲートを `ROUTE_FLAG == "--pr"` で実装したが、route は Size auto-detection や `always-pr: true` により in-session で解決されるため判定軸として不十分だった (review で MUST として検出)。CLI フラグは「呼び出し側が何を指定したか」であって「実際にどの route を通ったか」ではない、という区別が必要だった。

#### review

- watchdog kill (exit 143, silent 2600s) で中断。fan-out と指摘の修正まで完了していたがコミット前に死んだため、成果 11 ファイル分が worktree に未コミットで残留した。親セッションが関連 bats 63 件 (0 failures) で健全性を確認したうえでコミット・push し、`.wholework.yml` に `watchdog-timeout-review-seconds: 5400` を設定して再実行した。
- 再実行の review が MUST 1 件を含む 10 件を検出。うち 1 件は 1 回目の kill 時点の修正内容 (親セッションがそのままコミットしたもの) に含まれていた穴 — `reconcile-phase-state.sh` が空出力を返したとき明示 `--pr` でも post-processor が誤発火する反転リスク — であり、再実行の review がこれを塞いだ。「中断成果をコミットしてから再実行する」回復パターンが、単なる時間節約ではなく品質面でも機能した。
- `gh-pr-review.sh` に渡す JSON で `severity` フィールドを省いたため、MUST issue があるにもかかわらず `COMMENT` イベントで投稿された。加えて GitHub API の self-review 制約 (自分が作成した PR への `REQUEST_CHANGES` は 422) に未対応。

#### merge

- 特記なし。`mergeable=true` (reason=clean)、CI 9 件 SUCCESS、pre-merge AC gate 2/2 で squash merge。

#### verify

- 本セッションにロードされている `skills/verify/SKILL.md` が `#1186` 着地前のバージョンだった (セッション開始時のスナップショット、Step 5 に already-checked AC skip rule なし・Step 6 に旧文言 "Re-verify even if already checked" が残存)。リポジトリ上の実ファイル (L210) には当該ルールが存在するため、実ファイルを SSoT として適用した。`session=next` 属性 (`#1168`) が対象とする skill 自己更新の非伝播が、`/verify` 自身にも同じ形で発生した事例。
- 適用の結果、pre-merge 2 件が SKIPPED となり、旧ルールなら発生していた rubric 2 件の再実行 (新規情報ゼロ) を回避した。`#1186` の効果が同一セッション内の 2 Issue 目でも継続して確認できた。

### Improvement Proposals

- `scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_REVIEW_DEFAULT=2600` は Size L の `/review --full` に対して不足する (本 Issue で 3300s 超えて kill)。本セッションでは `.wholework.yml` に 5400s を設定して回避したが、既定値そのものの再調整を検討すべき。`WATCHDOG_TIMEOUT_CODE_DEFAULT=4680` に対し review が 2600s という比率は、fan-out + 2 段階検証 + 修正 + CI 待ちを直列に回す `--full` の実態と合っていない。
- `modules/orchestration-fallbacks.md` の `review-completion-false-negative` / `reconciler-header-mismatch` は回復手順を「re-run `/review`」としているが、watchdog kill の場合は worktree に未コミットの成果が残っていることがある。「残留成果の有無を確認 → 関連テストで健全性を検証 → コミット・push してから再実行」という手順を追記すべき。本 Issue では成果を捨てずに済んだが、手順書どおりに再実行していれば 11 ファイル分の修正を失っていた。
- `scripts/gh-pr-review.sh` の `severity` フィールド未指定時の挙動 (MUST があっても `COMMENT` で投稿される) と、GitHub API の self-review 422 制約への未対応。review retrospective に記録済み。
