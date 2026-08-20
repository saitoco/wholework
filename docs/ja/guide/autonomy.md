[English](../../guide/autonomy.md) | 日本語

# Autonomy Tier

Wholework の **autonomy tier** は、スキルが GitHub state をどこまで書き込めるか (L0) と、後続ループをどこまで発火できるかを制御します。これは `.wholework.yml` に設定するプロジェクトレベルのガバナンス宣言です。

## 存在意義

Wholework のスキルは GitHub state を書き込み (ラベル作成、issue クローズ、コメント投稿) 、Claude Code のプリミティブ (`CronCreate`、`ScheduleWakeup`) を通じて後続ループを発火できます。これをどこまで自動で行わせたいかは、プロジェクトの信頼レベル、レビュー文化、自律的な副作用への許容度によって異なります。

autonomy tier は、各スキルを個別に設定することなく、これらすべてを一括で制御する単一のダイヤルを提供します。

## 3 つのティア

### L1 Report (デフォルト)

スキルは GitHub state を読み取り、推奨事項を表示します。**GitHub state への自動書き込みも、自動ループ発火も行いません。**

L1 を使うべき場合:
- Wholework を初めて評価している
- プロジェクトが GitHub state のあらゆる変更に人間の承認を要求する
- 自律的なアクションなしで audit とドリフト検出だけを行いたい

許可される L2→L1 パス: **A (Advisory のみ)**

### L2 Assisted

スキルは GitHub state を書き込みます (現行の `/auto` と `/verify` の挙動と同じ) 。**自動 cron スケジューリングは行いません。**

L2 を使うべき場合:
- 中規模モダナイゼーションを実行している (Wholework のアンカーケース: $10K / 10 日 / 50〜100 PR)
- メインワークフロー (issue → spec → code → review → merge → verify) を自律的に実行させたい
- Wholework が Issue を自動でクローズしラベルを遷移させることに抵抗がない
- 定期スケジュールは自分で手動起動したい (例: `/auto --batch` を自分で実行する)

許可される L2→L1 パス: **A (Advisory)、C (ScheduleWakeup in-loop)**

### L3 Unattended

スキルは GitHub state (ラベル遷移、close/reopen、コメント) を完全に無人で書き込みます。`CronCreate` は L2→L1 パス (B) として利用可能ですが、セッションスコープかつインメモリです — ディスクには何も書き込まれず、登録済みジョブは 7 日で自動失効し、無人でのセルフ登録は Claude Code の auto mode classifier によってブロックされます。したがって `CronCreate` スケジュールの登録には attended セッションが必要であり、無人の L3 実行が単独で行えるものではありません。

L3 を使うべき場合:
- L2 がプロジェクトでうまく機能することを確認済み
- GitHub state 関連の作業 (ラベル遷移、close/reopen、コメント) を人間のトリガーなしで進めたい
- Wholework が GitHub state を自律的に変更することを受け入れる一方、`CronCreate` スケジュールの登録には引き続き attended セッションが必要であることも受け入れる

許可される L2→L1 パス: **A、B (CronCreate)、C**

## ティアの設定

プロジェクトルートの `.wholework.yml` で:

```yaml
# .wholework.yml
autonomy: L2   # L1 | L2 | L3
```

`autonomy` が未設定 (または未知の値が設定されている) 場合、`L1` がデフォルトになります。

## スキルがティアで許可されないパスを必要とした場合

スキルは frontmatter (`loop-paths-used`) で使用する L2→L1 パスを宣言します。スキルがティアで禁止されたパスを呼び出した場合:

- **必須依存** (そのパスなしではスキルが動作しない) : スキルは起動を拒否し、どのティアを設定すべきかを示すエラーを表示します。
- **degradable** (そのパスなしでもスキルが動作する) : スキルは警告を表示し、パス A (advisory — 推奨事項を表示し、ユーザーがアクションを取る) にフォールバックします。

## ティアと `--permission-mode` の関係

Claude Code の `--permission-mode` フラグは、サブプロセスの権限 (どの `gh` コマンドやシェルコマンドを自動承認するか、それとも確認を求めるか) を制御します。autonomy tier は **Wholework がどの GitHub state を書き込めるか、どのループを発火できるか** を制御します。両者は直交しており、サブプロセスの権限設定と `autonomy: L1` は独立して設定できます。

ティア × パスの完全な権限マトリクスと L0 の書き込みルールについては、[`modules/autonomy-tier.md`](../../../modules/autonomy-tier.md) を参照してください。

---

← [ユーザーガイド](index.md)
