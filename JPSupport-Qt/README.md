# JPSupport-Qt

Lazarus (FreePascal) の Qt5 / Qt6 ウィジェットセットで、SynEdit(Lazarus IDEのソースエディタコンポーネント)に日本語(および他のCJK言語)の入力メソッド(IME)対応を追加するパッチ集です。

[JPSupport](https://github.com/53jouhikone-source/JPSupport)(GTK2版)の姉妹プロジェクトです。GTK2版が`gtk_key_snooper_install`を用いた独立パッケージとして実装されているのに対し、本プロジェクトはQtの標準的な入力メソッドAPI(`QInputMethodEvent`/`QInputMethodQueryEvent`)を活用し、Lazarus/LCL本体への直接的なパッチという形で実装しています。

## 背景

Lazarus公式のSynEditコンポーネントは、長年([Issue #13374](https://gitlab.com/freepascal.org/lazarus/lazarus/-/issues/13374)など)、GTK2/Carbon双方で日本語入力に対応できないという課題を抱えてきました。Qt5/Qt6についても同様で、`TEdit`/`TMemo`など一部のネイティブQtウィジェットは(Qt自身の標準機能により)日本語入力ができる一方、SynEditのようなLCLの自前描画コンポーネントは対応していませんでした。

本プロジェクトは、Qt5/Qt6インターフェース層(`lcl/interfaces/qt5`, `qt6`)およびSynEditコンポーネント(`components/synedit`)に対するパッチ、加えてLazarus同梱の`libQt5Pas`/`libQt6Pas`バインディングライブラリへのC++拡張を通じて、この課題の解決を試みたものです。

## 実現した機能

Fcitx5 + Mozc環境での動作を前提に、以下を実現しています。

- **確定処理の正確性**: 複数文字(CJK文字)の確定文字列が正しく反映される(UTF-16をUTF-8として誤読していたバグの修正)
- **IME切り替えキー**: `Ctrl+Space`、`半角/全角`キーの両方が正常に機能する
- **候補ウィンドウのカーソル追随**: 変換候補ウィンドウが、キャレット位置に正しく追随して表示される(固定位置に表示される問題の解消)
- **プリエディット(変換中)表示**: 変換中の文字列が、専用のオーバーレイ描画により画面に表示される(何も表示されない問題の解消)
- **文節区切り表示**: Fcitx5/Mozcが報告する文節(bunsetsu)の区切りを認識し、現在編集中の文節を水色文字+太字下線でハイライト表示する
- **文節内カーソル追随**: `←`/`→`、`Shift+←`/`→`による文節移動・区切り調整に、表示上のカーソルが正しく追随する

一般的なGTKネイティブアプリ(Geditなど)と比較しても遜色ない表示品質を確認しています。

## 対応ブランチ・バージョン

- Lazarus: `fixes_4`ブランチ(4.8/4.9系)を対象に開発・検証
- ウィジェットセット: Qt5、Qt6の両方に対応(同一のパッチ構造をそれぞれのインターフェース層に適用)
- 入力メソッド: Fcitx5 + Mozcで動作確認(他のIMEでの動作は未検証)
- 検証環境: Ubuntu 24.04 (Docker/ARM64、Raspberry Pi 4/5上)

## 導入方法

2通りの方法を用意しています。

### 方法1: Dockerで試す(検証・お試し向け)

ビルド済み環境をすぐに試せます。実機のLazarus環境には影響しません。

```bash
cd docker
./run-jpsupport-qt5-ubuntu.sh   # Qt5版
# または
./run-jpsupport-qt6-ubuntu.sh   # Qt6版
```

初回はDockerイメージのビルド(Lazarus本体のソースビルドを含む)が走るため、数分〜数十分かかります。以降はキャッシュにより高速に起動します。

### 方法2: 自分のLazarus環境にパッチを当てる(実機導入向け)

`fixes_4`ブランチのLazarusソースツリーに対して、パッチスクリプトを直接適用します。

```bash
# Lazarusソースのルートディレクトリで実行
python3 /path/to/JPSupport-Qt/patches/apply_jpsupport_patches.py [qt5|qt6|both]
```

引数で対象ウィジェットセットを指定できます(省略時は`both`、両方に適用)。

適用後、以下の手順でビルドしてください。

1. `libQt5Pas`(または`libQt6Pas`)を`lcl/interfaces/qt5/cbindings`(または`qt6/cbindings`)で再ビルドし、システムにインストール
2. `make bigide LCL_PLATFORM=qt5`(または`qt6`)でLazarus本体をビルド

詳細な手順は`docker/Dockerfile.ubuntu`(または`Dockerfile.qt6.ubuntu`)内のコメント、および実際のビルドステップを参照してください。

## 技術的な補足

- **なぜ`libQt5Pas`/`libQt6Pas`にC++拡張が必要だったか**: Qtの`QInputMethodEvent::attributes()`(文節区切り・カーソル位置などの情報)が、Lazarus同梱のバインディングライブラリに一切公開されていなかったため、C++側に直接アクセサ関数を追加しました
- **なぜプリエディット文字列をバッファに挿入しないか**: テキストバッファを汚さず、Undo履歴やシンタックスハイライトへの副作用を避けるため、`TPaintBox`によるオーバーレイ描画方式を採用しています
- **`SlotInputMethodQuery`の`Result`について**: `QEvent::InputMethodQuery`は複数の情報を同時に問い合わせるため、一部の問い合わせにしか答えられない場合でも`Result`を無条件に`True`にしてはいけません(Qt自身の他の処理、特に`Qt::ImEnabled`の判定を妨げ、IME自体が起動しなくなります)。詳細はソースコード中のコメントを参照してください

## 既知の制限・未検証事項

- Fcitx5 + Mozc以外の入力メソッド(ibus等)での動作は未検証です
- Qt5/Qt6以外のウィジェットセット(GTK3等)への対応は含まれません(GTK2版は[JPSupport](https://github.com/53jouhikone-source/JPSupport)を参照してください)
- ルビ(Ruby)属性、周辺テキスト(Surrounding Text)関連の機能には対応していません

## 今後の展望

本プロジェクトの内容は、Lazarus公式へのアップストリーム提案(バグ報告・マージリクエスト)を見据えた検証・叩き台という位置づけでもあります。将来的に本家に取り込まれることが、最も望ましい解決だと考えています。

## ライセンス

[JPSupport](https://github.com/53jouhikone-source/JPSupport)本体と同じくMITライセンスです。詳細はリポジトリルートの`LICENSE`を参照してください。
