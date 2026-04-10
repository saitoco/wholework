# Issue #80: settings: permissions.allow のハードコードパスを ~/ 展開に置換

## Issue Retrospective

### 曖昧点の解決

**[ユーザ確認] 解決戦略を `~/` 展開に確定**

選択肢:
1. `~/` 展開に置換（推奨）
2. 絶対パスを全削除し相対パスのみに
3. install.sh で環境別に settings.json を生成

選択: 1（`~/` 展開）

判断根拠:
- `docs/migration-notes.md` で過去に `~/.claude/scripts/*.sh *` 形式の使用実績があり、SKILL.md frontmatter `allowed-tools` 側では機能することが確認されている
- install.sh 方式より仕組みが単純で、保守負担が軽い
- 相対パスのみ案は plugin cache 経由の呼び出しをカバーできず、`/auto` 実行時のプロンプト抑制効果（#78 で確認済み）を失う

**[ユーザ確認] スコープに `docs/migration-notes.md` を含めない**

`docs/migration-notes.md` 内の `/Users/saito/` 参照は過去の Issue #23 等の移行記録（歴史文書）であり、実働コードではない。本 Issue のスコープ外に確定。

**[自動解決] Repo 直下パス `Bash(/Users/saito/src/wholework/scripts/*.sh *)` を削除**

冗長性の観点から自動削除方針に決定:
- 既存の相対パス `Bash(scripts/*.sh *)` が dev モード（repo 内で直接スクリプト呼び出し）をカバー
- 新規の `~/.claude/plugins/cache/saitoco-wholework/wholework/*/scripts/*.sh *` が installed plugin 経由の呼び出しをカバー
- 上記 2 つで呼び出し経路を網羅するため、repo 直下の絶対パスエントリは不要

### 受入条件

初回作成のため変更なし。3 件の Pre-merge 条件は `file_contains` / `file_not_contains` による機械的検証が可能。`grep` ベースの検証は複雑化を避けるため `file_contains` に統一した。

### Risk Notes の補足

`~/` が `.claude/settings.json` の `permissions.allow` レイヤーで機能するかは未検証。Post-merge の実地検証（`/auto` 実行でプロンプトが発生しないか）でフォローする。機能しなかった場合は install.sh 方式の別 Issue を起票する方針。

### hot-reload 挙動の事前検証

Risk Notes の実装前検証として、`.claude/settings.json` の hot-reload 挙動を実測した。

**テスト:**
1. `Bash(scripts/get-issue-size.sh *)` および `Bash(/Users/saito/src/wholework/scripts/*.sh *)` を settings.json から削除
2. `scripts/get-issue-size.sh 80` を Bash ツールで実行
3. プロンプト発生の有無を観察

**結果**: プロンプトは発生せず、コマンドは実行された。残存する他のパターンで `scripts/get-issue-size.sh 80` にマッチするものは存在しないため、**settings.json はセッション開始時にキャッシュされ、hot-reload されない**と結論。

**影響**: 同一セッション内での `~/` 展開動作検証（プローブ方式）は hot-reload 不在により偽陰性リスクがあり、採用不可。Post-merge 検証はセッション再起動を伴う実地確認（本 Issue の acceptance criteria 通り）で行う方針とした。
