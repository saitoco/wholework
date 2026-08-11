[English](../versioning.md) | 日本語

# バージョニングポリシー

このドキュメントは Wholework のバージョニング規則の SSoT です。`.claude-plugin/plugin.json` を bump したりリリースタグを打つ前に、Claude Code セッションは本ドキュメントを参照すべきです。

## 現状

- **Pre-1.0 フェーズ。** Wholework はアクティブ開発中であり、フィードバック取得のため選定された協力者に配布されています。
- **1.0.0 は予約** — Public API を凍結し marketing / outreach を開始する時点のために確保されています。
- 1.0.0 までは marketing 活動を行いません。

## Bump レベル規則

| 変更種別 | Bump | 備考 |
|----------|------|------|
| 新しい skill、新しいサブコマンド、新しい flag（safe default）、新しいファイル（例: `SECURITY.md`）、README/docs の新しいセクション、新しい verify command タイプ | **minor**（例: 0.1.0 → 0.2.0） | 追加型 — 既存ユーザーは変更なしでインストール可能 |
| バグ修正、ドキュメント化された意図を復元する挙動修正、typo 修正、絵文字だけの外観変更 | **patch**（例: 0.1.0 → 0.1.1） | 新機能追加なし |
| skill のリネーム、サブコマンド削除、必須引数シグネチャの変更、既存コマンドの意味変更、`phase/*` や `triaged` ラベルのリネーム、`.wholework.yml` キーのリネーム、出力ファイル場所の移動（`docs/spec/` → 他へ）、verify command タイプの削除・変更 | **minor** pre-1.0 / **major** post-1.0 | 破壊的 — リリースノートの `### Breaking Changes` に記録 |

**判定ショートカット**: 「既存ユーザーが新バージョンをインストールするには何か変更が必要か？」
- No → patch（修正の場合）または minor additive
- Yes → 破壊的変更（pre-1.0 なら minor / post-1.0 なら major）

## Pre-1.0 の緩和ルール

SemVer は 0.x 期間中、minor bump での破壊的変更を許容します。Wholework もこの慣例に従います:

- 0.x → 0.(x+1) は破壊的変更を含んでもよい
- **破壊的変更は必ず明示** — リリースノート / タグメッセージに明記し、pre-1.0 → 1.0 移行時に clean な audit trail が残るようにする

## クローズされた Issue からの Bump レベル判定

リリース準備時、前回タグ以降にクローズされた Issue セットを確認します。Claude Code がこれを自動で discovery + classification できます。

### Discovery 手順

1. **前回のタグを取得**:
   ```sh
   git describe --tags --abbrev=0
   ```

2. **そのタグ以降のコミットを列挙**（`closes #N` 参照を抽出）:
   ```sh
   git log <prev-tag>..HEAD --pretty=format:'%H %s'
   ```
   コミットメッセージから `closes #N`、`fixes #N`、`(closes #N)` パターンをパース。

3. **タグ日付以降にクローズされた Issue を列挙**（コミットメッセージ外でクローズされた Issue をカバー）:
   ```sh
   TAG_DATE=$(git log -1 --format=%aI <prev-tag>)
   gh issue list --state closed --search "closed:>${TAG_DATE}" --json number,title,closedAt,labels --limit 200
   ```

4. **2 つのソースをマージし重複除外**、分類のため各 Issue body を取得:
   ```sh
   gh issue view <N> --json title,body,labels
   ```

### Classification 手順

各 discovery Issue について:

1. Issue title + body + `closing commit message` を読む
2. 上記の「Bump レベル規則」テーブルに従って分類（Added / Changed / Fixed / Breaking）
3. highest-wins ルールで集計:
   - 破壊的 Issue が 1 件でもあれば → リリースは破壊的（pre-1.0 なら minor / post-1.0 なら major）
   - 追加型 Issue が 1 件でもあれば → minor
   - Fix のみ → patch

### 除外ルール

以下はカウントから除外:
- `not planned` としてクローズされた Issue、別 Issue にマージされた Issue（コード影響なし）
- 親トラッカー Issue（`phase/verify` プレースホルダ）で全作業が sub-issue に分割されているもの（代わりに sub-issue をカウント）
- ユーザーから見える変更のない refactor / cleanup → patch

### 曖昧な場合の扱い

Issue を一意に分類できない場合、Claude Code は:
1. 該当 Issue を分類案と根拠付きで提示
2. 適用前にユーザー確認を求める
3. 確認後のみタグ付け / bump に進む

### 呼び出し例

ユーザー: 「次のリリースレベルは？」または「v{next} のリリースノート準備」

Claude Code の応答フロー:
1. 上記 discovery コマンドを実行
2. テーブルを提示: `| # | Title | Category | Rationale |`
3. Bump レベル案を 1 文の justification 付きで提案
4. 確認後に下記 Release 手順を実行

## 既知の先例と例外

| バージョン | 日付 | 実際の内容 | 本来のレベル | 備考 |
|-----------|------|-----------|-------------|------|
| 0.1.1 | 2026-04-16 | Additive（SECURITY.md、Issue テンプレート、README セクション追加） | 0.2.0 | 判定ミス; audit trail のためここに記録 |

**訂正ルール**: 誤判定時は retag せず、本来の番号をスキップする。例: 0.1.1 が実質 0.2.0 相当だったため、次リリースは **0.2.0**（0.1.2 ではない）とし、0.1.2 はスキップ slot として残す。

## リリース Cut 基準

本節は **いつリリースを切るか** の SSoT です。上の Bump レベル規則が *どの番号にするか* を決めるのに対し、本節は *そもそも切る時期か* を決めます。

本節が明記するために存在する規則: **Backlog が空であることはリリース条件ではなく、それを待つことはリリースしないことと同義です。** Wholework 自身の retrospective パイプラインは `/auto` 実行のたびに改善 Issue を起票するため、open backlog はゼロで均衡しない構造になっています。

### トリガー (OR — いずれか 1 つでリリース候補になる)

| # | トリガー | 根拠 |
|---|---------|------|
| 1 | 前回タグ以降のクローズ Issue が **100 件** (`not planned` を除く — 上の除外規則を参照) | 主トリガー。Issue を 1 件ずつ記述できた最後のリリースである v0.2.0 → v0.3.0 (108 件) を基準に較正した。 |
| 2 | 前回タグから **6 週 (42 日)** 経過 | スループットが落ちてトリガー 1 が発火しない期間の保険。小さいリリースの方が、古いリリースより望ましい。 |
| 3 | **Breaking change** が base branch に landed した | Breaking change は landed した時期に近いタイミングで利用者に届けるべきで、まとめるべきではない。v0.4.0 は 97 日後に 5 件を一度に出したため、導入者は 5 件の移行を 1 回のアップグレードで受け止めることになった。 |

トリガーは検討を開始する条件であり、それ自体がタグ付けを承認するものではありません。下記のゲートを実行してください。

### ゲート (AND — すべて満たしてからタグを打つ)

| # | ゲート | 確認方法 |
|---|-------|---------|
| 1 | base branch の CI が緑 | `gh run list --branch main --workflow Test --limit 10 --json conclusion` — `failure` がないこと |
| 2 | 未リリースの成果を抱えた open PR がない | `gh pr list --state open` — 空、またはレビュー/CI 待ちの PR のみ |
| 3 | 既知のテスト FAIL・リグレッションがない | 出荷面で再現する failure を記述した open Issue が解消済み、または理由を記録した上で明示的に見送られていること |
| 4 | ドキュメント drift チェックが通る | 下記 4 項目を参照 |
| 5 | stale / untriaged Issue がない | `/audit stats` が stale (90 日以上) 0 件・untriaged 0 件を報告すること |

**ゲート 4 — ドキュメント drift チェック:**

```sh
# a. structure.md のファイルカウントが実数と一致 (英日とも)
ls scripts/ | wc -l ; ls tests/ | wc -l ; ls modules/*.md | wc -l
grep -E '（[0-9]+ ファイル）' docs/ja/structure.md

# b. 利用者向けリファレンスと実装 SSoT の config キーが一致
#    (docs/guide/customization.md § Available Keys と modules/detect-config-markers.md)

# c. top-level の docs/*.md すべてに docs/ja/ の対訳が存在する
ls docs/*.md | sed 's|docs/||' | sort > /tmp/en.txt
ls docs/ja/*.md | sed 's|docs/ja/||' | sort > /tmp/ja.txt
comm -23 /tmp/en.txt /tmp/ja.txt   # 空であること

# d. plugin.json のバージョンが、これから打つタグと一致
jq -r '.version' .claude-plugin/plugin.json
```

### 明示的にブロッカーとしないもの

以下でリリースを遅らせては **いけません**。いずれも恒常的な背景状態であり、欠陥ではありません:

- **Open Issue 総数 / Backlog が空であること。** `retro/verify` が大半を占める backlog は、品質ではなくスループットの関数として増加します。
- **`phase/verify` の滞留。** `observation` / `opportunistic` / `manual` のマージ後確認を待っている Issue は、すでにマージ・出荷済みです。AC のチェックボックスはそれとは別の、より遅いループに属します。2026-08 時点で滞留の median は 39 日、30 日超過が 126 件あり、これをリリースゲートにすると無期限にブロックされます。
- **Icebox の Issue。** 定義上凍結されており、独自の再評価トリガーを持ちます。
- **未起票の retrospective 改善提案。** Spec / session retrospective に記録済みであり、先に出荷しても失われるものはありません。

### 過去実績による較正

| 区間 | 経過 | クローズ Issue (`not planned` 除く) | 評価 |
|------|------|-----------------------------------|------|
| v0.2.0 → v0.3.0 | 16 日 | 108 | 健全 — リリースノートで各テーマを Issue 単位の詳細付きで記述できた |
| v0.3.0 → v0.4.0 | 97 日 | 557 | 大きすぎた — Issue 列挙ではなくテーマ集約を強いられ、5 件の breaking change を 1 回のアップグレードに繰り延べた |

v0.4.0 直前 90 日の実測スループットは週あたり約 44 件のクローズで、このペースならトリガー 1 は概ね 2〜3 週ごとに発火する想定です。持続的なスループットが約 2 倍以上変化した場合は閾値を再較正してください。

## リリース手順

1. Bump レベルを決定（上記テーブルまたはクローズされた Issue リストで Claude Code に訊く）
2. `.claude-plugin/plugin.json` の `"version"` フィールドを更新
3. メッセージ `chore: bump version to vX.Y.Z` でコミット
4. main に push
5. annotated タグを作成:
   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z: <summary>

   - <change 1>
   - <change 2>"
   git push origin vX.Y.Z
   ```
6. （任意）`gh release create vX.Y.Z --notes-file ...` でより詳細な GitHub Release を作成

## 1.0.0 の基準

以下のすべてが満たされた場合 **のみ** 1.0.0 を打つ:

- Public API（skills、サブコマンド、flags、labels、config schema、ファイルレイアウト）が後方互換のため凍結宣言されている
- 0.x → 1.0 までの道のりを統合した CHANGELOG またはリリースノートが準備されている
- Marketing / outreach 準備が完了（Web サイト、発表計画、採用ファネル）
- 0.x からのインストール / アップグレードパスがドキュメント化されている

これらの条件が揃うまでは 0.x として minor bump を続ける — このフェーズのプロジェクトでは高い minor 番号（0.10、0.15、0.20 …）は正常で健全です。

1.0-launch 時に 0.x の minor 番号がやや収まりが悪いと感じる場合、**より大きな major にスキップ**することも許容される（例: 0.15 → 2.0）。React（0.14 → 15）や Node.js（0.12 → 4）の先例がある。

## 自動判定 vs 要確認

- **Claude Code は自動で Bump レベルを決定可能** — クローズされた Issue セットが単一カテゴリに明確にマップされる場合（全て fix → patch、全て追加型 → minor）
- **Claude Code は不確実性を明示すべき** — いずれかの Issue のカテゴリが曖昧な場合、タグ付け前にユーザーに確認を求める
- **ユーザー判断がテーブル解釈より常に優先**
