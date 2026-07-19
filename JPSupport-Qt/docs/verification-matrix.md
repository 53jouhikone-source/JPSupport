# JPSupport-Qt 実機検証記録

各環境・条件での動作確認状況を記録します。「4点セット」とは以下を指します。

1. 変換キー2種（`Ctrl+Space`、`半角/全角`）
2. 候補ウィンドウのカーソル追随
3. 文節移動（`←→`、`Shift+←→`）
4. 変換対象文節の水色文字＋水色太線下線表示

## 検証マトリクス

| 環境 | 方式 | IME | 4点セット | 確認日 | 備考 |
|---|---|---|---|---|---|
| RasPi5 | Docker(Ubuntu24.04) | Qt5 + Fcitx5+Mozc | ✅ | 2026-07-16 | 開発時の検証環境 |
| RasPi5 | Docker(Ubuntu24.04) | Qt6 + Fcitx5+Mozc | ✅ | 2026-07-17 | Qt5からの横展開で成功 |
| RasPi4 | 実機(Debian12) | Qt5 + Fcitx5+Mozc | ✅ | 2026-07-18 | `--pcp`分離必須(既存Lazarus 2.2.6と設定衝突) |
| RasPi4 | 実機(Debian12) | Qt5 + IBus+Mozc | 未検証 | | |
| RasPi4 | 実機(Debian12) | Qt6 + いずれか | 未検証 | | |
| VMware(x86_64) | 実機(Ubuntu) | Qt5 + Fcitx5+Mozc | 未検証 | | |
| VMware(x86_64) | 実機(Ubuntu) | Qt5 + IBus+Mozc | 未検証 | | |
| VMware(x86_64) | 実機(Ubuntu) | Qt6 + いずれか | 未検証 | | |

## 今後の検証方針

- Qt6はコード差分がQt5とほぼ皆無であることを確認済みのため、代表的な1環境で成功を確認できれば、他環境への横展開は基本的に問題ないと判断する
- IBusでの動作確認では、`QT_IM_MODULE=ibus`への切り替えに加え、Qt用IBusプラグインの要否を事前に確認する
