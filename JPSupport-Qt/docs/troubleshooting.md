# JPSupport-Qt トラブルシューティングガイド

「方法2: 自分のLazarus環境に組み込む」を実際に試した際に発生した(または発生しうる)エラーと、その対処法をまとめます。基本の導入手順は[README.ja.md](../README.ja.md)を参照してください。

このガイドは、開発者自身が検証中に実際につまずいた内容をベースにしています。「自分の環境ではまだ確認していない」ものも含め、気づいた範囲で追記していく想定です。

## 目次

1. [ビルド関連](#1-ビルド関連)
2. [パッチ適用関連](#2-パッチ適用関連)
3. [起動・設定関連](#3-起動設定関連)
4. [IME関連](#4-ime関連)
5. [その他・既知の制限](#5-その他既知の制限)

---

## 1. ビルド関連

### 1.1 `libQt6Pas.so`が自動配置されない/実行時にリンクエラーが出る

`build_jpsupport_qt.sh`は、`ldconfig -p`から`libQt5Core.so`の配置先ディレクトリを逆算し、そこに`libQt6Pas.so`をコピーします。この自動判定がうまく働かない環境(ディストリビューションやアーキテクチャによってライブラリパスの構成が異なる場合など)では、コピーが行われず、Lazarus起動時に`libQt6Pas.so: cannot open shared object file`のようなエラーになることがあります。

**対処法**: 手動でコピーし、`ldconfig`を実行してください。

```bash
# 配置先の確認(環境により /usr/lib/x86_64-linux-gnu や /usr/lib/aarch64-linux-gnu など)
ldconfig -p | grep libQt6Core

# 該当ディレクトリへ手動コピー
sudo cp -P lazarus-src/lcl/interfaces/qt6/cbindings/libQt6Pas.so* /usr/lib/x86_64-linux-gnu/
sudo ldconfig
```

Qt5は多くのディストリビューションで既にシステムに`libQt5Pas`相当が存在するため、この手順が省略されがちですが、Qt6は自前ビルドが前提です。この手順を忘れると、ビルド自体は成功していてもLazarus起動時にエラーになるため気づきにくい点に注意してください。

### 1.2 `make bigide`でコンパイルエラーになる

Lazarus本体のビルド(`make bigide`)は、ユニット間の依存順序がシビアです。**`-j`(並列)オプションを付けると、依存関係の解決順が崩れてエラーになることがあります。** `build_jpsupport_qt.sh`はこの点を踏まえ、Lazarus本体のビルドはシングルスレッドで実行するようになっています。

一方、`libQt5Pas`/`libQt6Pas`(cbindings配下)のビルドは、独立したライブラリのビルドであるため`-j$(nproc)`を使って問題ありません。

**手動でビルドし直す場合は、この違いを混同しないよう注意してください。**

```bash
# NG: Lazarus本体を並列ビルドしない
cd lazarus-src && make bigide -j4 LCL_PLATFORM=qt6

# OK: Lazarus本体はシングルスレッド
cd lazarus-src && make bigide LCL_PLATFORM=qt6

# OK: cbindingsは並列ビルドしてよい
cd lazarus-src/lcl/interfaces/qt6/cbindings && qmake6 Qt6Pas.pro && make -j$(nproc)
```

### 1.3 Qt6版のビルドに必要なパッケージが足りない

Qt6版は`qt6-base-dev`が必要です(Qt5版の`qtbase5-dev`に相当)。Ubuntu 22.04/24.04の標準リポジトリに存在しますが、**Qt5版の開発環境を先に構築した後にQt6版を試す場合、このパッケージのインストールを忘れがちです。**

```bash
sudo apt-get install qt6-base-dev
```

`qmake6`コマンドが見つからない場合は、このパッケージが未インストールである可能性が高いです。

---

## 2. パッチ適用関連

### 2.1 `LM_IM_QUERY_CARET_POS`が未定義というコンパイルエラーが出る

`patches/upstream/`配下の単体パッチファイル(`git diff`形式)を、クリーンな`fixes_4`チェックアウトに直接適用しようとすると、このエラーが発生することがあります。

**原因**: `patches/upstream/`内のファイルは、あくまで**特定の変更範囲だけを切り出した、人間によるレビュー用の差分**です(例: `jpsupport-qt-lazsynime-refactor.patch`はSynEditのリファクタリング部分のみを含み、`lmessages.pp`への`LM_IM_QUERY_CARET_POS`追加など、前提となる別のパッチが当たっている前提で作られています)。単体では完結したパッチにはなっていません。

**対処法**: 実際にビルド・動作確認したい場合は、単体パッチファイルではなく、必ずフルセットを適用するスクリプトを使ってください。

```bash
python3 patches/apply_jpsupport_patches.py qt5   # または qt6、both
```

詳細は[`patches/upstream/README.md`](../patches/upstream/README.md)にも記載しています。

### 2.2 `apply_jpsupport_patches.py`を再実行すると重複挿入エラーになる

`lmessages.pp`など、Qt5/Qt6共通で「常に適用される」パッチ関数を、**既にパッチ済みの状態に対してもう一度実行すると**、パッチが探しているアンカー文字列が既に変更後の内容に置き換わっているため、二重挿入や不一致でエラーになることがあります。

**対処法**:

- クリーンなチェックアウトに対して一度だけ実行するのが基本です
- Qt6専用のパッチだけを個別に当て直したい場合(共通パッチはそのままで、Qt6側のみ再適用したい場合など)は、スクリプトを丸ごと実行せず、該当する関数だけを個別に呼び出してください(`patch_qevent_c_qt6()`、`patch_qt62()`、`patch_qtwidgets_qt6()`など)
- どちらか判断がつかない場合は、`lazarus-src`ディレクトリごと削除し、クリーンな状態から`build_jpsupport_qt.sh`を再実行するのが最も確実です

---

## 3. 起動・設定関連

### 3.1 「既存の設定と衝突する可能性がある」という警告が出た

JPSupport-Qt検証用にビルドしたLazarusを、`--pcp`オプションなしで起動すると、既に別のLazarus(既存のGTK2版など)を使っている環境では、この警告が表示されることがあります。

**絶対に「そのまま使う/更新する」を選ばないでください。** 既存のLazarus環境の設定ファイルが、検証用ビルドによって書き換えられてしまう可能性があります。

**対処法**: 必ず専用の設定ディレクトリを指定して起動してください。

```bash
./lazarus --pcp=~/.lazarus_jpsupport_qt5
# Qt6版なら
./lazarus --pcp=~/.lazarus_jpsupport_qt6
```

複数の検証環境(Qt5用、Qt6用、GTK2版など)を並行して行き来する場合は、`--pcp`のパスを環境ごとに完全に分けて管理することを強く推奨します。混同すると、ある環境向けの設定が別の環境に紛れ込み、原因の特定が難しい不具合につながります。

---

## 4. IME関連

### 4.1 IME自体がまったく反応しない(変換キーを押してもインジケーターすら反応しない)

**まず最初に試してほしいこと: Fcitx5デーモンの再起動。** これが最も見落としやすく、かつ最も効く対処法です。

```bash
fcitx5-remote -e   # 現在のFcitx5デーモンを終了
sleep 1
fcitx5 -d          # デーモンとして再起動
```

長時間起動しっぱなしのFcitx5デーモンが、内部的に不安定な状態に陥ることがあります。この状態では、`fcitx5-remote`コマンドが`Failed to get reply.`を返す、D-Bus自体は生きているように見えるのに実際のIMEイベント(`QInputMethodEvent`)がアプリケーションに一切送られない、変換キーを押してもインジケーターアイコンがまったく反応しない、といった症状が起こり得ます。しかもこの症状は**Qt/GTKを問わず、環境内のすべてのアプリケーションで同時に発生します**(JPSupport-Qtで作ったLazarusだけでなく、GeditのようなGTKアプリでも同様に無反応になります)。そのため一見「特定のアプリ・特定のウィジェットのコードに原因がある」ように見えて、実際には**Fcitx5デーモン側の問題**だった、というケースがあります。切り分けとして、まず無関係な別のアプリ(GTK/Qtどちらでもよい)で日本語入力を試し、そちらも同様に無反応であれば、まずデーモン再起動を試してください。

再起動後、`半角/全角`キーを押してインジケーターアイコンが反応するか確認してください。これで直らない場合は、以下を順に確認してください。

**環境変数の確認**

```bash
echo $QT_IM_MODULE      # 通常は "fcitx" または "ibus"
echo $XMODIFIERS        # 通常は "@im=fcitx" または "@im=ibus"
echo $GTK_IM_MODULE      # GTKアプリにも入力するなら同様に設定
```

未設定の場合は、シェルの設定ファイル(`.bashrc`や`.xprofile`など、デスクトップ環境の起動方式による)に追記し、ログインし直してください。

**デーモンの起動確認**

```bash
ps aux | grep -E 'fcitx5|ibus-daemon'
```

**入力方式(Mozc等)が実際に有効になっているかの確認**

パッケージ(`fcitx5-mozc`など)がインストール済みでも、Fcitx5の設定上で入力方式として有効化されていなければ、変換キーを押しても実際には日本語入力エンジンに切り替わりません。

```bash
cat ~/.config/fcitx5/profile
```

出力の中に、使いたい入力方式(例: `mozc`)が`[Groups/0/Items/N]`として登録されているか確認してください。登録されていなければ、`fcitx5-configtool`を起動し、GUIで入力方式一覧に追加してください。

### 4.2 Fcitx5 + Qt6で変換キーを押しても何も起きない

Ubuntu 22.04の標準リポジトリには、Qt6用のFcitx5フロントエンドプラグイン(`fcitx5-frontend-qt6`)が存在しません。この場合、Qt6アプリケーション側からFcitx5への接続経路自体が確立されないため、変換キーを押しても一切反応しません。

これは**JPSupport-Qtのコード側の問題ではなく、ディストリビューションのパッケージ提供状況による環境側の制約**です。ビルドやパッチ適用そのものが失敗しているわけではない点に注意してください——ビルドは成功し、Lazarusも起動しますが、IME入力だけが機能しない、という状態になります。

**対処法: ソースからプラグインをビルドする**

Ubuntu 22.04の実機でも、`fcitx5-qt`をソースからビルドすることでQt6対応が可能です(実機で実際に成功を確認済みです)。ただし、システムのFcitx5コアのバージョンと、GitHub上の最新`fcitx5-qt`が要求するバージョンとの間にズレがあることが多いため、そのままでは`cmake`の設定段階でエラーになります。

```bash
# 1. ビルド依存パッケージ
sudo apt install -y cmake extra-cmake-modules libxcb1-dev libxkbcommon-dev \
    qt6-base-dev qt6-base-private-dev libfcitx5core-dev libfcitx5config-dev \
    libfcitx5utils-dev

# 2. ソース取得
git clone --depth 1 https://github.com/fcitx/fcitx5-qt.git
cd fcitx5-qt
```

システムのFcitx5コアのバージョンを確認します。

```bash
apt-cache policy fcitx5
```

`CMakeLists.txt`内で要求されているバージョンと、システムの実際のバージョンを比較してください。

```bash
grep -n "find_package(Fcitx5Utils" CMakeLists.txt
```

もしバージョンが一致しない(要求バージョンの方が新しい)場合、この行の要求バージョンをシステムの実バージョンに書き換えます(例: システムが`5.0.14`なら、要求も`5.0.14`に下げる)。この回避策は、システムのコアが実際に要求APIを満たしている場合にのみ有効です。要求バージョン以降で追加された新しいAPIをソース側が使っている場合は、コンパイルエラーになる可能性があります。

```bash
mkdir build && cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_SKIP_INSTALL_RPATH=ON \
      -D ENABLE_QT4=OFF \
      -D ENABLE_QT5=OFF \
      -D ENABLE_QT6=ON \
      -Wno-dev ..
make -j$(nproc)
sudo make install
```

インストール後、プラグインが正しい場所(`qmake6 -query QT_INSTALL_PLUGINS`で確認できるパス配下の`platforminputcontexts/`)に配置されているか確認し、Fcitx5デーモンを再起動してから(4.1参照)、Qt6版Lazarusで試してください。

### 4.3 IBus環境で `Ctrl+Space` が効かない/候補ウィンドウが左上に固定される

これはJPSupport-Qtの不具合ではなく、既知の制限として案内しています。詳細は[`docs/verification-matrix.md`](verification-matrix.md)を参照してください。

- `Ctrl+Space`が効かないのは、Lazarus IDE自体がこのキーをコード補完のショートカットとしてハードコードしているためです。`半角/全角`キーは影響を受けず正常に動作します
- 候補ウィンドウが左上に固定されるのは、IBus自身のQt統合(`QIBusPlatformInputContext`)側の制約と考えられ、JPSupport-Qt側からの修正は困難です

Fcitx5環境ではどちらの制限も発生しません。安定した動作を求める場合はFcitx5の利用を推奨します。

---

## 5. その他・既知の制限

### 5.1 word wrap(折り返し)環境でのキャレット位置がずれる可能性

SynEditのword wrapは、単純な`WordWrap`プロパティではなく`TLazSynEditLineWrapPlugin`という専用プラグインを介して実現されています。理論上、この場合のキャレット位置計算が候補ウィンドウの追随処理と干渉する可能性が考えられますが、**実際に問題が確認されたわけではありません**。優先度は低く設定しており、余裕があれば検証する位置づけです。該当する不具合に気づいた場合は、Issueなどで報告いただけると助かります。

---

## このガイドに載っていない問題に遭遇したら

上記で解決しない場合は、以下の情報を添えてIssueを立てていただけると、切り分けがしやすくなります。

- OS/ディストリビューションとバージョン(例: Ubuntu 22.04、Raspberry Pi OS Debian 12など)
- Qt5/Qt6のどちらか
- Fcitx5/IBusのどちらか、またそのバージョン
- 発生したエラーメッセージの全文(可能であれば`make`や`apply_jpsupport_patches.py`実行時のログも)
- `--pcp`で指定した設定ディレクトリのパス
