# Lazarus本家へのアップストリーム提案 - 経緯記録

JPSupport-Qtの内容を、Lazarus公式(fpc-lazarus本体)に取り込んでもらうための働きかけの記録です。

## 経緯

| 日付 | 内容 | リンク |
|---|---|---|
| 2026-07-25 | Lazarusフォーラム(Third party)に、JPSupport-Qtの紹介と本家への取り込みについて意見を求める投稿を実施 | https://forum.lazarus.freepascal.org/index.php/topic,74458.msg587218/topicseen.html#new |
| 2026-07-26 | Martin_fr氏(SynEdit/Debuggerメンテナー)より好意的な返信。設計方針についての重要な指摘あり(下記参照) | https://forum.lazarus.freepascal.org/index.php/topic,74458.msg587218 (Reply #1) |
| 2026-07-26 | 上記への返信。`LazSynIme`サブクラス方式への作り直しに合意する旨を回答 | (Reply #2) |
| 2026-07-26 | zeljko氏(Qt担当)より、`libQt5Pas`/`libQt6Pas`へのC++拡張について懸念表明 | (Reply #3) |
| 2026-07-26 | Martin_fr氏より追加コメント。Windows版IME実装(`LazSynImeFull.SetImeTempText`)や`TSynEditMarkupSelection`についての技術的助言、word wrap環境でのテストの推奨 | (Reply #4) |
| 2026-07-26 | zeljko氏の懸念に対し、背景説明と代替案(C++拡張を伴わない設計、機能を分離してのマージ、あるいは文節ハイライト機能自体の見送り)を提案する返信を投稿 | https://forum.lazarus.freepascal.org/index.php/topic,74458.msg587283/topicseen.html#new |

## 本家からの主な指摘・助言(記録用)

### Martin_fr氏(SynEdit/Debuggerメンテナー)より

- **設計方針**: SynEdit自体は、LM/WMメッセージを`LazSynIme`ハンドラクラス(基底クラスとそのサブクラス)へ転送するだけの薄い窓口に留めたい。今回の実装(`TCustomSynEdit`に直接メッセージハンドラを追加)は、この設計思想に沿っていないため、`LazSynIme`のサブクラス(GTK2版の`LazSynImeGtk2`と同様の位置づけ、例えば`LazSynImeQt`)に作り直す必要がある
- **Windows版IME実装の参考情報**: Windows版(`LazSynImeFull.SetImeTempText`)は、実は変換中の一時テキストをエディタのバッファに直接書き込む方式。ただしUndo履歴を汚すため、確定・キャンセル前に必ず元に戻す処理が必要
- **ハイライト表示の参考情報**: `TSynEditMarkupSelection`という、SynEdit標準のマークアップ機構を使って、変換中の下線等を表現している
- **候補ウィンドウ**: OS側が描画するため、SynEdit側はキャレット座標を返すだけでよい
- **テストの助言**: word wrap(折り返し)が有効な状態でも、キャレット座標が正しく計算されるかテストすること。論理・物理・表示上のキャレット位置の違いについては https://wiki.freepascal.org/SynEdit#Logical,_Physical_or_Viewed_caret_position を参照

### zeljko氏(Qt担当)より

- `libQt5Pas`/`libQt6Pas`へのC++バインディング変更は、過去に「リンクできない」「更新方法が分からない」という混乱を繰り返し引き起こしてきたため、可能な限り避けたい

## 今後の想定ステップ

1. `LazSynIme`サブクラス方式(`LazSynImeQt`など)への設計作り直し
2. `libQt5Pas`/`libQt6Pas`へのC++拡張について、zeljko氏からの回答を待つ(代替手段の有無、機能分離の可否など)
3. Windows版の実装(`SetImeTempText`、`TSynEditMarkupSelection`)を参考に、プリエディット表示・文節ハイライトの実装方式を見直す
4. word wrap環境でのキャレット位置計算の検証を追加する
5. 上記を踏まえた改訂版を、GitLabへのMerge Requestとして提出する

## 投稿内容の要旨(記録用)

- GTK2版JPSupportの実績を踏まえ、GTK2の将来性への懸念からQt5/Qt6版を開発したこと
- 実現した機能(確定処理の正確性、変換キー、候補ウィンドウ追随、プリエディット表示、文節ハイライト)
- Fcitx5+Mozc、IBus+Mozc双方で動作確認済みであること(IBusには既知の制限あり)
- パッチスクリプト・Docker環境の両方を用意していること
- 本家取り込みの是非、および次のステップ(Issue/MR等)について意見を求めた
