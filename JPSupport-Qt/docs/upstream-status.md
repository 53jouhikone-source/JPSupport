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

## 続報(2026-07-27時点)

| 日付 | 内容 |
|---|---|
| 2026-07-27 | dbannon氏(Hero Member、tomboy-ng開発者)より、zeljko氏の懸念に理解を示しつつも「的を絞った目的のはっきりした変更は良いこと。CJK文字利用者は多く、必要なら実施すべき」と、C++拡張に前向きなコメント |
| 2026-07-27 | Martin_fr氏より、IMEクライアント実装の3段階(①何もしない、②カーソル位置のみ返す、③自前で仮テキスト描画)の整理と、「WM/LMメッセージ経由の設計は、richeditなど他のコンポーネントにも再利用できる汎用的な良い設計」との評価コメント |

**現状の温度感**: zeljko氏本人からの、こちらの質問(代替手段の有無・安全な失敗パターン・機能分離案)への
直接回答はまだない。ただしdbannon氏の援護、Martin_fr氏の好意的な技術解説により、
「C++拡張は絶対に避けるべき」という空気ではなく、「必要性が正当なら受け入れる」という
コミュニティの温度感が見えてきた。zeljko氏本人の回答を待って、次の対応を判断する方針
(拙速に畳みかけず、いったん静観)。

## 今後の想定ステップ

1. zeljko氏本人からの回答を待つ(静観中)
2. `LazSynIme`サブクラス方式(`LazSynImeQt`など)への設計作り直しは、回答を待たずに並行して着手可能
3. `libQt5Pas`/`libQt6Pas`へのC++拡張について、zeljko氏の回答を踏まえて要否・回避策を確定する
4. Windows版の実装(`SetImeTempText`、`TSynEditMarkupSelection`)を参考に、プリエディット表示・文節ハイライトの実装方式を見直す
5. word wrap環境でのキャレット位置計算の検証を追加する
6. 上記を踏まえた改訂版を、GitLabへのMerge Requestとして提出する

## 投稿内容の要旨(記録用)

- GTK2版JPSupportの実績を踏まえ、GTK2の将来性への懸念からQt5/Qt6版を開発したこと
- 実現した機能(確定処理の正確性、変換キー、候補ウィンドウ追随、プリエディット表示、文節ハイライト)
- Fcitx5+Mozc、IBus+Mozc双方で動作確認済みであること(IBusには既知の制限あり)
- パッチスクリプト・Docker環境の両方を用意していること
- 本家取り込みの是非、および次のステップ(Issue/MR等)について意見を求めた

## 2026-07-30: LazSynImeサブクラス方式へのリファクタリング完了

Martin_fr氏の提案を受け、Qt5/Qt6のIME実装を`TCustomSynEdit`への直接実装から
`LazSynIme`サブクラス(`LazSynImeQt`、新規ユニット`lazsynqtimm.pas`)方式へ
作り直した。既存の`LazSynImeGtk2`など他プラットフォームのハンドラと同じ設計に揃えている。

- `LazSynIme`(lazsynimmbase.pas): `WMImeQueryCaretPos` / `WMImeSetPreedit`を
  仮想メソッドとして追加(デフォルトは空実装、他プラットフォームへの影響なし)
- `LazSynImeQt`(lazsynqtimm.pas、新規): 従来`TCustomSynEdit`に直接実装していた
  プリエディット描画ロジック(文節ハイライト、カーソル追跡含む)をすべて移動
- `synedit.pp`: `FImeHandler`への薄い転送のみに整理。新規`QtIME`定義
  (LCLQt5/LCLQt6双方で有効)でインスタンス生成を制御

クリーンなLazarusチェックアウト(x86_64/Ubuntu22.04、Qt5、Fcitx5+Mozc)でビルド・
動作確認済み。既存の検証済み機能(確定処理、変換キー2種、候補ウィンドウ追随、
プリエディット表示、文節ハイライト、文節移動)がすべて正常に動作することを確認。

`patches/apply_jpsupport_patches.py`もこの設計に追従済み(commit 87b1ddd)。
`git worktree`でクリーンなチェックアウトに適用し、手動検証済みの状態とdiffで
突き合わせて確認 — コメント文言のみの差分で、機能面の相違なし。

フォーラムスレッド(topic 74458)へ改訂版の報告を投稿済み。Qt6でのビルド・
動作確認は未着手。zeljko氏からの`libQt5Pas`/`libQt6Pas`へのC++バインディング
拡張に関する懸念への回答はまだ届いていない。

## パッチ内訳(開発者・メンテナー向け参考情報)

`patches/apply_jpsupport_patches.py`が適用する変更は、以下10個の個別パッチ(Python関数)で構成されています。一般ユーザーがこの内訳を意識する必要はありません(`build_jpsupport_qt.sh`が自動的にすべて適用します)が、本家への取り込みを検討するメンテナーや、類似の改修を行いたい開発者向けに、変更範囲の全体像を記録しておきます。

**共通パッチ(Qt5・Qt6両方に適用)**

- `patch_lmessages`(パッチ): `LM_IM_QUERY_CARET_POS`等、IME関連の新しいメッセージ定数を`lcl/lmessages.pp`に追加
- `patch_synedit`(パッチ): `synedit.pp`を、新しい`LM_IM_*`メッセージを`LazSynIme`ハンドラクラスへ転送するだけの薄い窓口に整理(Martin_fr氏の設計指摘を反映)
- `patch_lazsynimmbase`(パッチ): `LazSynIme`基底クラス(`lazsynimmbase.pas`)に、`WMImeQueryCaretPos`/`WMImeSetPreedit`を仮想メソッドとして追加
- `patch_lazsynqtimm`(新規ファイル追加): `LazSynImeQt`(`lazsynqtimm.pas`)という、Qt5/Qt6共通の`LazSynIme`サブクラスを新規作成。従来`TCustomSynEdit`に直接書いていたプリエディット描画・文節ハイライト・カーソル追跡ロジックをすべてここに集約

**Qt5用パッチ**

- `patch_qevent_c`(パッチ): `libQt5Pas`のC++バインディング(`qevent_c.h`/`qevent_c.cpp`)に、`QInputMethodEvent::attributes()`(文節・カーソル位置情報)を取得するゲッター関数群を追加
- `patch_qt56`(パッチ): 上記C++関数に対応するPascal側の外部関数宣言を`qt56.pas`に追加
- `patch_qtwidgets`(パッチ): `qtwidgets.pas`の`TQtWidget.SlotInputMethod`/`SlotInputMethodQuery`に、確定文字列のUTF-16対応(以前は文字化け・欠落があった)、文節ハイライト処理、キャレット位置追随ロジックを追加

**Qt6用パッチ**(Qt5用パッチと同じ変更を、Qt6のソースツリーに対しても行うもの)

- `patch_qevent_c_qt6`(パッチ): `patch_qevent_c`のQt6版
- `patch_qt62`(パッチ): `patch_qt56`のQt6版
- `patch_qtwidgets_qt6`(パッチ): `patch_qtwidgets`のQt6版

このうち、Qt5用・Qt6用の3つずつ(`qevent_c`系・`qt56`/`qt62`・`qtwidgets`系)が、zeljko氏が懸念を示した「`libQt5Pas`/`libQt6Pas`へのC++バインディング拡張」に該当する部分です。
