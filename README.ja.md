# JPSupport

Lazarus の統合開発環境(IDE)のソースエディタで日本語入力を可能にするパッケージです。

## これは何ですか？

Linux版のLazarusでは、ソースコードを編集する画面に日本語を直接入力することができませんでした。

JPSupportをインストールすることで、この問題が解決され、ソースエディタに日本語コメントや文字列を自然に入力できるようになります。

## 主な機能

- 日本語の変換中に、入力中の文字に下線が表示されます
- 変換候補ウィンドウがカーソルの近くに表示されます
- 複数のファイルをタブで開いていても、正しく動作します

## 動作環境

- OS：Linux（Debian、Ubuntuなど）
- Lazarus 2.2.6以降
- Free Pascal Compiler 3.2.2以降
- 画面描画システム(GTK2)バックエンド
- 日本語入力：Fcitx5またはIBus（Mozc推奨）
- 動作確認済み：
  - Raspberry Pi 4（ARM64）/ Debian 12 / Lazarus 2.2.6 / Fcitx5 + Mozc
  - Raspberry Pi 4（ARM64）/ Debian 12 / Lazarus 2.2.6 / IBus + Mozc
  - Raspberry Pi 5（ARM64）/ Debian 12 / Lazarus 2.2.6 / Fcitx5 + Mozc
  - VMware Debian 12（x86_64）/ Lazarus 2.2.6 / IBus + Mozc
  - VMware Debian 12（x86_64）/ Lazarus 2.2.6 / Fcitx5 + Mozc

## インストール方法

### 準備

このリポジトリの `package` フォルダ内のファイルを、適当な場所にコピーしてください。

### 手順

2つのパッケージを順番にインストールします。

**1つ目のパッケージ（JPSupport）：**

1. Lazarusを起動します
2. 上部メニューの「パッケージ」→「パッケージファイル(.lpk)を開く」をクリック
3. `JPSupport.lpk` を探して開きます（JPSupportフォルダの中にあります）
4. 小さなウィンドウが開くので「コンパイル」をクリック
5. 下部メッセージボックスに「パッケージJPSupport1.0をコンパイル.成功」と表示されたら完了です
6. 「使用」→「インストール」をクリック
7. 「Lazarusを再構築しますか？」に「はい」をクリック
8. 画面が一時的に消えて再起動が始まります（数分かかります。正常な動作です）

**2つ目のパッケージ（JPSupportIDE）：**

Lazarusが再起動したら、開いているJPSupportのウィンドウを閉じ、同じ手順で `JPSupportIDE.lpk` をインストールします（閉じなくても構いませんが、混乱を避けるためお勧めします）。

### 確認

2回目の再起動後、ソースエディタをクリックして変換キー（通常は半角/全角キー）を押してみてください。反応があればほぼ成功です。そのまま文字を入力して日本語が表示されれば完了です。

インストールは一度だけで済みます。以降はLazarusを起動するだけで日本語入力が使えます。

## 技術的な説明（開発者向け）

GTK2の`gtk_key_snooper_install`を使用してキーイベントをグローバルに横取りし、独自のGtkIMContextに転送します。標準のLazarusビルドでは`synedit.ppu`が`Gtk2IME`フラグなしでコンパイルされているため、通常の方法では日本語入力ができません。JPSupportはLazarusの内部を改変せずにこの問題を解決しています。

主要ファイル：
- `JPSupportAdapter.pas` — コアとなるアダプタクラス
- `JPSupportIDEMain.pas` — Lazarusへの組み込み処理
- `JPSupportUnit.pas` — スタンドアロン版コンポーネント

## 既知の制限事項

- 画面描画システム(GTK2)バックエンドのみ対応（GTK3・Qt版は未対応）
- IBus・Fcitx5ともに動作確認済み

## 中国語・韓国語ユーザーへの注記

JPSupportは`gtk_key_snooper_install`を使用してキーイベントをグローバルに横取りし、独自のGtkIMContextに転送する方式を採用しています。この方式は原理的に中国語・韓国語の入力メソッド（Fcitx5/IBus + Pinyin、Hangulなど）にも応用できる可能性があります。中国語・韓国語ユーザーからのフィードバックを歓迎します。

## ライセンス

MITライセンス

このパッケージを改変・再配布される場合、作者への一報をいただけると嬉しいです（義務ではありません）。ご意見・ご感想・バグ報告もお気軽にどうぞ。

## 作者

Shortcut (53jou.hikone@gmail.com)

開発にあたり、Claude（Anthropic）・ChatGPT（OpenAI）・Gemini（Google）の支援を受けました。

## 謝辞

- ATSynEditのGTK2 IME実装を参考にしました
- LazarusおよびFree Pascalコミュニティに感謝します
