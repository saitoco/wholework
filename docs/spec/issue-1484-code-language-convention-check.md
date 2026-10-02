# Issue #1484: code: コミット前に変更差分を言語規約チェックに通す

## Overview

`/code` が、コミット前に CI の `language-convention` job と同じ言語規約の検査をローカルで行うようにする。

CI は `git diff -U100000 origin/<base>...HEAD -- skills/ modules/ scripts/` を `scripts/check-language-convention.py` に渡し、英語指定のパスに混入した日本語の地の文を検出している。`/code` にはこの検査が無いため、既存の行を編集すると行全体が + 行として検査対象に入り、元からその行にあった日本語が push 後の CI で初めて FAILURE になる。修正は `/review` の Step 12 で行うことになり、1 往復が増える (#1481、#1321、#476 で発生)。

方針は次の 2 点。

- 手順を新規の補助文書 `skills/code/language-convention-check.md` に置く。この検査は `scripts/check-language-convention.py` を持つ repo (Wholework 自身) でしか意味を持たない。そのため `forbidden-expressions-check.md` / `bare-bracket-assertions-check.md` と同じ File-existence 型の Domain ファイルにし、他の repo の `/code` には読み込みを課さない
- `skills/code/SKILL.md` の Step 9 `Additional validation` に、script が存在するときだけ補助文書を読む 1 行を足す (既存の 3 行と同じ形)

## Changed Files

- `skills/code/language-convention-check.md`: 新規。`type: domain` / `skill: code` / `load_when.file_exists_any: [scripts/check-language-convention.py]` の Domain ファイル。コミット前の言語規約チェックの手順 (base の決定、未追跡ファイルの登録、CI と同形の diff の検査、違反時の修正、失敗時の扱い) を英語で書く。`skills/` は英語指定のパスなので、この文書自体も検査の対象になる
- `skills/code/SKILL.md`:
  - Step 9 の `**Additional validation (run after tests):**` で、`If \`scripts/check-bare-bracket-assertions.sh\` exists, ...` の行の直後、`**Documentation consistency check (run after validation):**` の直前に 1 行を足す
  - frontmatter の `allowed-tools` に `git merge-base:*` を足す (`git branch:*,` の直後)
- `tests/code.bats`: 新規テストを末尾に追加する (一覧は Implementation Step 3)
- `docs/environment-adaptation.md`: `### Domain Files (exhaustive)` の表で、`skills/code/forbidden-expressions-check.md` の行の直後に `skills/code/language-convention-check.md` の行を足す
- `docs/ja/environment-adaptation.md`: 同じ行を日本語版の表に足す (翻訳同期。`docs/translation-workflow.md`)
- [Steering Docs sync candidate] `docs/structure.md`: Key Files の Scripts > Tooling にある `scripts/check-language-convention.py` の項目 (`run by the \`language-convention\` CI job` で終わる行) に、`/code` もコミット前に実行する旨 (`skills/code/language-convention-check.md`) を足すか、`/code` が読んで判断する。更新しなくても記述は誤りにならないが、呼び出し元の記述が不完全になる
- [Steering Docs sync candidate] `docs/ja/structure.md`: 上と同じ項目の日本語版 (`docs/structure.md` を更新する場合のみ)
- [Steering Docs sync candidate] keyword "check-language-convention" skipped: matched 20 files (no discriminating power)。実際に更新を検討すべき非履歴のヒットは上の `docs/structure.md` と `docs/ja/structure.md` で、残りは履歴 (`docs/spec/`、`docs/sessions/`) と script 自体のテスト (`tests/check-language-convention.bats`、変更なし)
- [Steering Docs sync candidate] keyword "forbidden-expressions-check.md" (同種の補助文書。7 files): 実際に更新が要るのは `docs/environment-adaptation.md` と `docs/ja/environment-adaptation.md` で、上に挙げた。残りは履歴 (`docs/spec/` 4 件、`docs/reports/` 1 件)
- [Outbound pointer sync candidate] なし: 変更するファイルが指す先 (`scripts/check-language-convention.py`、`.github/workflows/test.yml`) は、この Issue の変更で内容を変える必要が無い
- 変更しない (確認済み):
  - `scripts/check-language-convention.py`: そのまま使う (検査器の挙動は変えない)
  - `.github/workflows/test.yml`: `language-convention` job の diff 形 (`git diff -U100000 "origin/${{ github.base_ref }}...HEAD" -- skills/ modules/ scripts/`) を確認済みで、変更不要。workflow ファイルの変更は CI Dependency Minimum Override (Size M 以上) を引き起こし、環境によっては push に `workflow` scope も求められるため、コメント 1 行のためには触らない。補助文書の側に「CI の job と同期を保つ」と注記して、ずれを防ぐ
  - `README.md` / `CLAUDE.md` / `docs/workflow.md` / `docs/guide/*.md`: `/code` の個別の事前チェックを列挙している箇所が無い (`grep -n -i "forbidden\|language convention\|validate-skill-syntax"` で README.md・CLAUDE.md・`docs/guide/` は 0 件、`docs/workflow.md` の `/code` の節も確認済み)
- 測定範囲: 上のヒット数は `grep -rl "<keyword>" docs/ tests/ scripts/ modules/` (全ファイル種別、`docs/spec/` と `docs/sessions/` を含む) の件数

## Implementation Steps

1. `skills/code/language-convention-check.md` を新規作成する (→ AC2, AC3)。英語で書き、`forbidden-expressions-check.md` と同形にする (frontmatter → 見出し `# Language Convention Check (/code supplement)` → 読み込み条件の 1 文 → `## Processing Steps`)
   - frontmatter: `type: domain`、`skill: code`、`load_when:` 配下に `file_exists_any: [scripts/check-language-convention.py]`
   - 冒頭: 「この file は `scripts/check-language-convention.py` が存在する repo でだけ読み込まれる」という既存の補助文書と同じ 1 文に加え、存在しない repo (例: Wholework を plugin として使う他の repo) ではこの検査全体をスキップする (`skip this entire check`) と明記する (→ AC3)
   - `## Processing Steps` に、次の 4 手順を番号付きで書く。字面どおり含める文言は `` ` `` で示す
     1. **base の決定**: 別の手順として `git merge-base "origin/$BASE_BRANCH" HEAD` を実行し、出力された SHA を次の手順の `<base>` にそのまま入れさせる。`BASE_BRANCH` は Step 0 で決まった値 (既定 `main`)。`$(...)` は使わない (worktree 分離ガードが拒否する。さらに、inline で失敗すると `git diff -U100000  -- ...` という base 無しの形になり、黙って別の diff を検査してしまう)。merge-base を使う理由 (CI の `origin/<base>...HEAD` と同じ分岐点から比べるので、作業中に base へ入った他の変更を自分の変更と取り違えない) を 1 文で書く。失敗したら `HEAD` を `<base>` にして続行し、未コミットの変更だけを検査したことを出力する
     2. **未追跡ファイルの登録**: `git status --porcelain --untracked-files=all -- skills/ modules/ scripts/` を実行し、`??` で始まる行のファイルを `git add -N -- <path>` する (intent-to-add。内容はステージされない)。`git diff <base>` は未追跡ファイルを出さないため、これが無いと新規ファイルが黙って検査から漏れる。該当が無ければ何もしない。Step 11 は `git add <changed files>` で個別にステージするので干渉しない
     3. **検査**: `git diff -U100000 <base> -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py` を実行する。base と作業ツリーの差分なので、コミット済みの変更と未コミット (`uncommitted`) の変更を 1 回で同時に検査する。対象パスと diff 形が CI の `language-convention` job (`.github/workflows/test.yml`) と同じであること、`-U100000` は script が context 行からフェンス状態を追うために必須であること、CI の job と同期を保つことを注記する
     4. **結果の扱い**: 出力なしで exit 0 (空の diff を含む) は違反なしとして続行する。違反は `<path>:<行の内容>` の形で 1 行ずつ出力され exit 1 になる。報告された行をすべて **コミット前に** (`before committing`) 修正し、exit 0 になるまで手順 3 を再実行する。patch route は Step 11 のコミット前に、pr route は Step 11 の push 前に `git commit -s` で修正コミットを作る。修正の指針として次を書く
        - 既存の行を編集しただけでも行全体が + 行になるので、元からあった日本語の地の文も報告される。行全体を英訳する
        - 意図した日本語 (データのキーワード、出力メッセージ) は、script が除外する形 (フェンスコードブロック、インラインコード、引用符付き文字列) の中に置く。script 側を緩めて違反を消さない
        - 修正が tests の検査対象の文言に触れたら、該当テストを再実行する
        - 1 回の修正で解消しない場合は、未解決のテスト失敗と同じに扱う (Step 9 の `Test FAIL handling`: patch route の非対話は abort、patch route の対話は AskUserQuestion、pr route は継続して完了メッセージに残りを載せる)
   - **失敗時の扱い** (fail-safe 重要度の判定は Notes): `git merge-base` が失敗 → `HEAD` を base にして続行 (fail-open)。script / `python3` が実行できない・クラッシュした場合 (exit 非 0 で `<path>:<行>` の出力が無い) → 「検査未実施」として完了メッセージに載せて続行 (fail-open)。違反の報告 (`<path>:<行>` の出力あり) だけが、修正するまで進ませない (fail-closed)。理由: この検査は CI の前倒しで、CI が最終ゲートのため、手元の tool の不調で commit を止めない。diff は加工せずそのまま script に渡す (`sed` / `tr` などの整形を挟まない)
2. (after 1) `skills/code/SKILL.md` を編集する (→ AC1, AC3)
   - Step 9 の `Additional validation` に次の 1 行を足す。AC1 の検索文字列 `check-language-convention.py` を字面どおり含める (実装前は `skills/code/SKILL.md` に 0 件で、実装後に PASS になる)。script が存在するときだけ読む形が、AC3 のスキップ規定の入口になる
     `If \`scripts/check-language-convention.py\` exists, Read \`${CLAUDE_PLUGIN_ROOT}/skills/code/language-convention-check.md\` and follow the "Processing Steps" section.`
   - frontmatter の `allowed-tools` に `git merge-base:*` を足す (手順 1 の base の決定が使う。`skills/review/SKILL.md` が同じ entry を持つ先例に合わせる)
3. (after 1, 2) `tests/code.bats` に新規テストを追加し、この変更自体を新手順で検査する (→ AC1, AC2, AC3 の決定的な裏付け)
   - 既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/code.bats` に下記 9 件) を追加したうえでスイートが PASS すること。補助文書のパスは `LANG_CHECK_DOC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/code/language-convention-check.md"` で定義し、Step 9 は既存の `step9_section` で抽出する
     1. `Step 9 reads language-convention-check.md only when check-language-convention.py exists`: `step9_section` に `If \`scripts/check-language-convention.py\` exists, Read` と `skills/code/language-convention-check.md` が含まれる
     2. `SKILL.md allowed-tools pre-approves git merge-base for the language convention check`: SKILL.md の frontmatter (先頭 6 行) に `git merge-base:*` が含まれる
     3. `language-convention-check.md is a code Domain file gated on scripts/check-language-convention.py`: 先頭 8 行に `type: domain`、`skill: code`、`file_exists_any: [scripts/check-language-convention.py]` が含まれる
     4. `language-convention-check.md skips the whole check when check-language-convention.py is absent`: `skip this entire check` が含まれる
     5. `language-convention-check.md runs the CI-equivalent diff form over skills/ modules/ scripts/`: `git diff -U100000 <base> -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py` の行が含まれる
     6. `language-convention-check.md diffs from the merge base against the working tree so uncommitted changes are included`: `git merge-base "origin/$BASE_BRANCH" HEAD` と `uncommitted` が含まれる
     7. `language-convention-check.md resolves the merge base as a separate literal step (no inline command substitution)`: `$(git merge-base` が含まれない
     8. `language-convention-check.md registers untracked new files with intent-to-add before diffing`: `git add -N` が含まれる
     9. `language-convention-check.md requires fixing violations before committing`: `before committing` が含まれる
   - assertion の書き方は Notes の「新規テスト」に従う。実装前 (補助文書も Step 9 の行も無い状態) に全件 FAIL することを確認する (`/code` Step 8 の New Verification-Test Pre-implementation FAIL Check)
   - コミット前に、この変更自体を手順 1 〜 3 のコマンドで検査し、exit 0 を確認する (新規の補助文書と SKILL.md の追記が英語だけであることの自己検査。この Issue の `/code` は変更前の SKILL.md で動くため、手動で実行する)
4. (parallel with 1, 2, 3) ドキュメントを同期する (→ 受入条件なし。SHOULD レベルの整合)
   - `docs/environment-adaptation.md` と `docs/ja/environment-adaptation.md` の Domain Files の表に、`skills/code/forbidden-expressions-check.md` の行の直後へ次の行を足す
     - 英語版: `| \`skills/code/language-convention-check.md\` | \`/code\` | \`check-language-convention.py\` exists | \`file_exists_any: [scripts/check-language-convention.py]\` | Language convention pre-check |`
     - 日本語版: `| \`skills/code/language-convention-check.md\` | \`/code\` | \`check-language-convention.py\` が存在 | \`file_exists_any: [scripts/check-language-convention.py]\` | 言語規約事前チェック |`
   - `docs/structure.md` / `docs/ja/structure.md` は sync candidate。更新する場合は、`scripts/check-language-convention.py` の項目の末尾に、`/code` がコミット前にも実行する旨 (`skills/code/language-convention-check.md`) を足す

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/code/SKILL.md" "check-language-convention.py" --> `skills/code/SKILL.md` に、コミット前に変更差分を `scripts/check-language-convention.py` に通す手順 (または当該手順を記載した補助文書の読み込み指示) がある
- <!-- verify: rubric "skills/code/SKILL.md、または SKILL.md から読み込まれる skills/code/ 配下の補助文書の言語規約チェック手順が、CI の language-convention job (.github/workflows/test.yml) と同じ対象パス (skills/ modules/ scripts/) と同じ diff 形式 (git diff -U100000 <base> -- skills/ modules/ scripts/ の出力を check-language-convention.py に渡す) を使い、base との差分にコミット前の未コミット変更も含め、違反が見つかった場合はコミット前に修正するよう定めている" --> `/code` の言語規約チェックの対象と diff の取り方が CI と一致し (コミット前の未コミット変更も対象に含む)、違反はコミット前に修正すると定めている
- <!-- verify: rubric "skills/code/SKILL.md、または SKILL.md から読み込まれる skills/code/ 配下の補助文書の言語規約チェック手順が、scripts/check-language-convention.py が存在しない repo (Wholework を利用する他の repo) ではこのチェックをスキップするよう定めている" --> 言語規約チェックは `scripts/check-language-convention.py` が存在しない repo ではスキップされる

### Post-merge

- 変更が main に入った後の最初の `/review --light` 完了時に、レビュー対象 PR の diff が `skills/` `modules/` `scripts/` に及ぶ場合、その PR の CI `Language Convention check` (language-convention job) の結論が success である (diff が及ばない PR は判定対象外として SKIPPED) (observation, event=pr-review-light, session=next)

## Notes

- **配置の判断 (補助文書 + Step 9 に 1 行)**: `SKILL.md` に手順を直接書く案は採らない。(1) この検査は `scripts/check-language-convention.py` を持つ repo でしか要らない。`docs/tech.md` の Progressive disclosure の判断基準 (この tool を使わない project にも要るか) に当てはめると No で、補助文書に出すのが正しい。(2) 同種の `forbidden-expressions-check.md` / `bare-bracket-assertions-check.md` と同じ形になり、読み手が迷わない。(3) `skills/code/SKILL.md` は 891 行 (`wc -l skills/code/SKILL.md`) あり、これ以上増やしたくない。AC1 〜 AC3 は補助文書でも満たせる文言になっている
- **挿入位置 (Step 9 の `Additional validation`)**: CI の job に相当する検査 (`validate-skill-syntax.py`、`check-forbidden-expressions.sh`、`check-bare-bracket-assertions.sh`) が並ぶ場所に置く。Step 8 の各中間コミットの前には置かない。この時点の状態は、patch route が最後の Implementation Step の diff を未コミットで持ち (Step 8 の "Step 8/Step 11 Commit Boundary")、pr route が Step 8 のコミットを済ませて push 前、というもので、「base と作業ツリーの差分」はどちらも覆う。1 回の検査でブランチ全体を見られる
- **base と diff の組み立て**: `<base>` は `git merge-base "origin/$BASE_BRANCH" HEAD` の結果とし、`git diff -U100000 <base> -- skills/ modules/ scripts/` で作業ツリーと比べる。`git diff A...B` は `git diff $(git merge-base A B) B` と等価 (公式ドキュメント) なので、CI の `origin/<base>...HEAD` と同じ分岐点から始まり、`B` を作業ツリーに置き換えた形になる。これでコミット済み・ステージ済み・未ステージの追跡ファイルの変更が 1 回の diff に入る。未追跡の新規ファイルは入らない (E3) ため、手順 2 の `git add -N` が要る。Step 9 の `nproc` → `bats --jobs <N>` と同じく、変数は別手順で出力させて字面どおり代入する (`tests/code.bats` の既存テスト `Step 9 full-suite override resolves the job count as a separate literal step (no inline command substitution)` が同種の規約を固定している)
- **採用しなかった形**:
  - `git diff -U100000 origin/$BASE_BRANCH` (base の先端との直接の差分): 作業中に base が進むと、他のセッションが消した行を自分のブランチが持ち続けているだけで + 行になり、誤検出する。この repo は並行セッションが多い
  - 「コミット済み (`origin/<base>...HEAD`) と未コミット (`HEAD`) の 2 回に分けて実行」: コミット済みの違反を未コミットの編集で直した場合でも、コミット済みの側が違反を報告し続ける。作業ツリーとの 1 回の diff なら最終状態だけを評価できる
  - `git add -N -- skills/ modules/ scripts/` で一括登録: 追跡済みの変更はステージされず問題ないが (E6)、存在しない pathspec が混じると `fatal` で exit 128 になる。CI の diff は存在しないパスでも動くので、`git status` で列挙してから登録する形にした (E7)
  - `git add -N .` で全未追跡ファイルを登録: 対象パス外の無関係な未追跡ファイルまで index に入る
- **確認済みの git の挙動** (検証環境: git 2.47.3、この Spec 作成時の worktree `spec/issue-1484`、HEAD `8cd1891b`、2026-10-03。検証用の一時ファイル `modules/zz-lang-exp.md` と `modules/phase-banner.md` への一時編集は検証後に削除・復元済みで、`git status` は空):

  | # | 検証 | 結果 |
  |---|------|------|
  | E1 | `git merge-base origin/main HEAD` を worktree で実行 | SHA を出力 (exit 0) |
  | E2 | 変更が無い状態の diff (`git diff -U100000 HEAD -- skills/ modules/ scripts/`) を script に通す | 出力なし、exit 0 |
  | E3 | 日本語の地の文を含む未追跡の新規ファイルを `git diff -U100000 <base> -- skills/ modules/ scripts/ \| python3 scripts/check-language-convention.py` に通す | 検出されず exit 0 (見逃す) |
  | E4 | 同じファイルを `git add -N` した後に同じ pipeline | `modules/zz-lang-exp.md:<行>` を出力し exit 1。`git diff --cached --stat` は空 (内容はステージされない) |
  | E5 | 追跡済みの既存の英語の行の末尾に日本語を足した未コミット編集 | 行全体が + 行として検出された (exit 1)。未ステージのまま。Issue の Background の再現になる |
  | E6 | `git add -N -- skills/ modules/ scripts/` (追跡済みの未ステージ編集と `-N` 済みのファイルがある状態) | exit 0、追跡済みの編集はステージされない。存在しない pathspec を足すと `fatal: pathspec ... did not match any files` で exit 128 |
  | E7 | `git status --porcelain --untracked-files=all -- <存在しないパス> skills/ modules/ scripts/` | exit 0 (エラーなし)。`-N` 済みのファイルは ` A` と表示され `??` には再出現しない (手順 2 は冪等) |

  公式ドキュメント (取得日時 2026-10-03): <https://git-scm.com/docs/git-diff> (`git diff <commit>` は作業ツリーと commit の比較で未追跡ファイルを含まない。`A...B` は `git diff $(git merge-base A B) B` と等価。`-U<n>` は context 行数)、<https://git-scm.com/docs/git-add> (`-N` / `--intent-to-add` は「内容なしの entry を index に置く」)、<https://git-scm.com/docs/git-status> (porcelain で未追跡は `??`、`--untracked-files=all` は未追跡ディレクトリ内の個々のファイルも出す)。pathspec が 1 つも一致しないときの `git add` の挙動と、`-N` 済みの表示 (` A`) は公式ページに記述が無く、E6 / E7 の実測を根拠にした
- **fail-safe 重要度の判定: 該当 (ゲート)**: 違反を検出したら修正するまでコミット / push に進ませるので、(a) のゲートに当たる。実装対象は Markdown の手順で script は変更しないが、境界条件を手順に明記する (Implementation Step 1)。期待する挙動は次のとおり
  - 空入力 (対象パスに差分なし): 違反なし、exit 0 (E2)
  - 大きな入力: `-U100000` でファイル全体が context になるが、pipe で渡し一時ファイルを作らない (CI も同じ)
  - 特殊文字 (`>`、`"`、改行、CRLF、多バイト文字): diff を加工せずそのまま渡す。script は CI で使っている検査器そのもので、`tests/check-language-convention.bats` が既に覆っている
  - 依存コマンドの失敗: `git merge-base` → `HEAD` を base にして続行 (fail-open)。script / `python3` の実行不能・クラッシュ → 「検査未実施」を記録して続行 (fail-open)。理由は、この検査が CI の前倒しで CI が最終ゲートだから。違反の報告だけは fail-closed
  - pipe の落とし穴: `git diff ... | python3 ...` の終了コードは `python3` のもの。`git diff` が失敗すると空の入力が渡り、exit 0 で素通りする。base を別手順で先に確定させておくので、この経路は残らない
- **違反が残ったときのルーティング**: 1 回の修正で解消しない場合は Step 9 の `Test FAIL handling` と同じにする (`forbidden-expressions-check.md` の "same as test failures" と同じ扱い)。patch route の非対話は abort。patch route では CI の push 時の検査 (`git diff -U100000 "HEAD^..HEAD"`) が複数コミットの push の最後のコミットしか見ず、通常それは Spec の retrospective コミット (`docs/spec/` のみ) で `skills/ modules/ scripts/` に差分が無いため素通りする。したがって patch route では、この `/code` の検査が実質の唯一のゲートになる。CI 側の検査範囲の改善はこの Issue の対象外
- **`allowed-tools`**: `git status:*` / `git add:*` / `git diff:*` / `python3:*` は `skills/code/SKILL.md` に既にある。足りないのは `git merge-base:*` だけで、`skills/review/SKILL.md` が同じ entry を持つ先例に合わせて足す。`check-allowed-tools.sh` / `validate-skill-syntax.py` は SKILL.md 本体を検査するもので、補助文書のコマンドは検査対象外。この entry は非対話 (`claude -p --permission-mode auto`) の実行で事前承認を得るためのもの。`/code` の `allowed-tools` を縛るテストや文書は他に無い (`grep -rn 'git merge-base:\*' tests/ docs/` で 0 件)。この補助文書を読むのは `/code` だけなので、他の SKILL.md の `allowed-tools` は変更しない (`modules/*.md` の変更は無く、allowed-tools impact chain check の Case 1 / Case 2 のどちらにも該当しない)
- **新規テスト (bats test の入力形式)**: 必要な新規テストケースは Implementation Step 3 の 9 件 (Step 9 の入口と `allowed-tools` の 2 件、補助文書の frontmatter・スキップ規定・CI と同形の diff・merge-base と未コミット・`$(...)` 不使用・未追跡ファイルの登録・修正義務の 7 件)。`tests/code.bats` は section 抽出関数 + 文字列一致の構造テスト。新規の assertion は bare `[[ "$output" == ... ]]` ではなく、`[[ ... ]] || false` か `grep -qF` を使う (`skills/code/skill-dev-validation.md` の "Bash 3.2: Bare `[[ ]]` Assertions Do Not Propagate `set -e`" の指針。`check-bare-bracket-assertions.sh` が報告する形)。`@test` 名は `tests/code.bats` の既存の流儀 (英語の文) に合わせる。パターン検出 script のテスト fixture による自己参照、`WHOLEWORK_SCRIPT_DIR` の mock、新規 script の追加は無いので、それらの確認項目は該当しない
- **bats が未インストール**: この環境では `command -v bats` が見つからない (2026-10-03 確認。`python3` 3.13.5 はある。GNU `parallel` は無い)。`/code` はスイートを実行できない可能性が高い (#1481 の Code Retrospective にも同じ記録がある)。その場合は、新規テストが見る文字列を `grep -F` で直接確認し、bats の実行は CI の `bats` job に任せ、完了メッセージに「bats 未実行」と書く
- **verify command の扱い**: Pre-merge の 3 件は Issue 本文 (SSoT、`modules/verify-patterns.md` §18) をそのまま写した。AC2 の rubric には数値リテラル `-U100000` があり、§9 に従えば `file_contains` を併記したいが、Spec から Issue 本文は更新しない (§18) ので併記しない。代わりに Implementation Step 3 のテスト 5 が、補助文書に `git diff -U100000 <base> -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py` の行があることを決定的に固定する。AC1 の検索文字列は `/code` が Step 2 で字面どおり書く (§23 の実装前の anchor 選択。実装前は 0 件で FAIL、実装後は PASS になる)。Post-merge の observation AC は Issue 本文のまま。`pr-review-light` は `scripts/opportunistic-search.sh` の `KNOWN_EVENTS` にあり、`modules/verify-classifier.md` の定義は「Next `/review --light` completion」。この Issue は Size S (patch route) で `/review` を通らないため、発火は後続の M 以上の PR の `/review --light` に依存する (`/issue` が Firing Likelihood Check で許容済み)
- **premise マーカー**: Issue 本文の `<!-- premise: grep_count "check-language-convention" "skills/code/" -eq 0 -->` は、この Issue の実装で `skills/code/` に参照が入るため必ず失効する (実装前の状態を記録するマーカーとして想定どおり)。post-merge の observation AC を待つ間 Issue は `phase/verify` で open のままなので、`/audit premise` (この repo は `autonomy: L3`) が "Premise Expired" のコメントを自動投稿する可能性がある。想定内で対応不要。Issue 本文のマーカーは Spec からは変更しない
- **Size の再評価**: 確定の Changed Files は 5 件 (補助文書、`SKILL.md`、`tests/code.bats`、`docs/environment-adaptation.md` と `docs/ja/` のミラー)。軸 1 は M (3-5 件)、軸 2 は既存パターンの横展開 (`forbidden-expressions-check.md` をなぞる) で -1 となり S。triage 時の Size S から変更なし (patch route)。`docs/structure.md` と `docs/ja/structure.md` は 1 行の追記で、`/code` が読んで判断する sync candidate として件数に数えない。CI の workflow は変更しないので CI Dependency Minimum Override にも該当しない
- **その他の確認結果**:
  - Issue 本文と実装の食い違い: なし。Background の CI の diff 形は PR イベントの形で一致する (push イベントは `HEAD^..HEAD`。上の「違反が残ったときのルーティング」を参照)
  - 監査・調査型の Issue ではない (新しい手順の実装)
  - ツール検出の既存パターンとの整合: 存在判定は `If \`scripts/<name>\` exists` (repo 相対のパスの存在確認) で、既存 3 行と同じ。`${CLAUDE_PLUGIN_ROOT}` 側の script (plugin が同梱するもの) ではなく repo 側の script を見るので、plugin として使う他の repo ではスキップされる (AC3)
  - `forbidden-expressions-check.md` にある Retrospective Guard の対応物は要らない。language-convention の検査範囲 (`skills/ modules/ scripts/`) に Spec (`docs/spec/`) は入らず、retrospective の文章が違反を持ち込めない
  - 既存の抜け (この Issue の対象外): `docs/environment-adaptation.md` の "Domain Files (exhaustive)" の表に `skills/code/bare-bracket-assertions-check.md` の行が無い (#1412 由来)。触らない
  - 新規ファイルの言語: `skills/code/language-convention-check.md` と `SKILL.md` の追記は、検査される英語指定のパスなので日本語の地の文を一切含めない。Implementation Step 3 で自己検査する

## Consumed Comments

No new comments since last phase.
