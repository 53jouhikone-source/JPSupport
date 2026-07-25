# Lazarus本家へのアップストリーム提案 - 経緯記録

JPSupport-Qtの内容を、Lazarus公式(fpc-lazarus本体)に取り込んでもらうための働きかけの記録です。

## 経緯

| 日付 | 内容 | リンク |
|---|---|---|
| 2026-07-25 | Lazarusフォーラム(Third party)に、JPSupport-Qtの紹介と本家への取り込みについて意見を求める投稿を実施 | https://forum.lazarus.freepascal.org/index.php/topic,74458.msg587218/topicseen.html#new |

## 今後の想定ステップ

1. フォーラムでの反応を待つ(意見・懸念点・歓迎の声など)
2. 反応内容を踏まえ、GitLab(gitlab.com/freepascal.org/lazarus/lazarus)へのIssue報告、あるいはMerge Requestの提出を検討する
3. 必要に応じて、レビューでの指摘に基づきパッチ内容を調整する

## 投稿内容の要旨(記録用)

- GTK2版JPSupportの実績を踏まえ、GTK2の将来性への懸念からQt5/Qt6版を開発したこと
- 実現した機能(確定処理の正確性、変換キー、候補ウィンドウ追随、プリエディット表示、文節ハイライト)
- Fcitx5+Mozc、IBus+Mozc双方で動作確認済みであること(IBusには既知の制限あり)
- パッチスクリプト・Docker環境の両方を用意していること
- 本家取り込みの是非、および次のステップ(Issue/MR等)について意見を求めた
