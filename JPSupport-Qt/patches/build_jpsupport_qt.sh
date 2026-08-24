#!/bin/bash
# build_jpsupport_qt.sh
#
# JPSupport-Qt を、自分のマシンに実際にビルド・導入するための一連の
# 作業(ソース取得・パッチ適用・ライブラリビルド・Lazarus本体ビルド)を
# まとめて行うスクリプトです。
#
# 使い方:
#   ./build_jpsupport_qt.sh qt5      # Qt5版をビルド(動作確認済みバージョン)
#   ./build_jpsupport_qt.sh qt6      # Qt6版をビルド(動作確認済みバージョン)
#   ./build_jpsupport_qt.sh --show-version   # 動作確認済みバージョンを表示して終了
#
# Qt5・Qt6の両方を試したい場合は、このスクリプトをそれぞれ個別に
# 実行してください。ビルド先はバージョンごとに自動的に分かれる
# (jpsupport-qt-build-qt5/ , jpsupport-qt-build-qt6/)ため、
# 両方を同時に共存させて使えます。
#
# 動作確認済み以外のLazarusバージョンを試す場合(未対応・保証外):
#   ./build_jpsupport_qt.sh qt5 --lazarus-version=lazarus_4_6
#   これは開発者による新バージョン追従の検証作業を想定したオプションで、
#   一般利用では動作確認済みバージョン(デフォルト)のままの使用を推奨します。
#   デフォルト以外を指定すると、確認プロンプトが表示されます。自動実行等で
#   確認を省略したい場合は --yes を併用してください。
#   ビルドが成功すると、そのバージョンをデフォルトに格上げするか
#   確認されます(実機でのIME動作確認は別途ご自身で行ってください)。
#
# 実行前に確認してください:
#   - 必要な開発パッケージ(qtbase5-dev等)は、事前にインストール
#     しておく必要があります。詳細はREADME.mdを参照してください。
#   - このスクリプトは、既存のLazarus環境を上書きしません。新しい
#     ディレクトリにソース一式を取得し、独立してビルドします。
#   - システムのlibQt5Pas/libQt6Pasライブラリを上書きします。
#     心配な方は事前にバックアップを取ってください。

set -e

# JPSupport-Qtが動作確認済みのLazarusバージョン。ここを変更する際は、
# 新バージョンでパッチ適用・ビルド・実機でのIME動作確認を行った上で
# 更新し、docs/upstream-status.mdにも検証結果を記録してください。
DEFAULT_LAZARUS_VERSION="lazarus_4_8"

TARGET=""
LAZARUS_VERSION="$DEFAULT_LAZARUS_VERSION"
ASSUME_YES=0

usage() {
    echo "使い方: $0 [qt5|qt6] [--lazarus-version=<tag>] [--yes]"
    echo "       $0 --show-version"
    echo ""
    echo "Qt5・Qt6の両方を試したい場合は、このスクリプトをそれぞれ"
    echo "個別に実行してください(例: $0 qt5 の後に $0 qt6)。"
    echo ""
    echo "  --lazarus-version=<tag>  動作確認済み以外のバージョンを指定(保証外、要確認)"
    echo "  --yes                    上記の確認プロンプトを省略する"
    echo "  --show-version           動作確認済みバージョンを表示して終了する"
}

for arg in "$@"; do
    case "$arg" in
        qt5|qt6)
            TARGET="$arg"
            ;;
        --lazarus-version=*)
            LAZARUS_VERSION="${arg#*=}"
            ;;
        --yes)
            ASSUME_YES=1
            ;;
        --show-version)
            echo "動作確認済みのLazarusバージョン: $DEFAULT_LAZARUS_VERSION"
            echo "検証記録: docs/upstream-status.md を参照してください。"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "不明な引数です: $arg"
            echo ""
            usage
            exit 1
            ;;
    esac
done

if [[ "$TARGET" != "qt5" && "$TARGET" != "qt6" ]]; then
    usage
    exit 1
fi

if [[ "$LAZARUS_VERSION" != "$DEFAULT_LAZARUS_VERSION" ]]; then
    echo "======================================================================"
    echo "警告: 指定されたLazarusバージョン '$LAZARUS_VERSION' は、本プロジェクトで"
    echo "動作確認されていません(動作確認済み: $DEFAULT_LAZARUS_VERSION)。"
    echo "パッチ適用・ビルド・IME動作のいずれかで失敗する可能性があります。"
    echo "このオプションの利用は保証外です。"
    echo "======================================================================"
    if [[ "$ASSUME_YES" != "1" ]]; then
        read -r -p "続行しますか？ [y/N]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "中止しました。"
            exit 1
        fi
    fi
fi

QTVER="${TARGET#qt}"   # "5" or "6"
if [[ "$QTVER" == "5" ]]; then
    QMAKE_CMD="qmake"
else
    QMAKE_CMD="qmake6"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(pwd)/jpsupport-qt-build-${TARGET}"
LAZARUS_SRC="${WORK_DIR}/lazarus-src"

echo "=== [1/6] 作業ディレクトリの準備 (${TARGET}版: ${WORK_DIR}) ==="
mkdir -p "$WORK_DIR"

if [ -d "$LAZARUS_SRC" ]; then
    echo "既存のLazarusソース($LAZARUS_SRC)が見つかりました。再利用します。"
    echo "注意: 別バージョン(qt5/qt6)のパッチが既に当たっている場合、"
    echo "      次のパッチ適用ステップでエラーになることがあります。"
    echo "      その場合は $LAZARUS_SRC を削除してから再実行してください。"
else
    echo "=== [2/6] Lazarusソース(${LAZARUS_VERSION}、正式リリース版)を取得 ==="
    git clone --branch "$LAZARUS_VERSION" https://gitlab.com/freepascal.org/lazarus/lazarus.git "$LAZARUS_SRC"
fi

echo "=== [3/6] JPSupportパッチを適用 (対象: $TARGET) ==="
cd "$LAZARUS_SRC"
python3 "$SCRIPT_DIR/apply_jpsupport_patches.py" "$TARGET"

echo "=== [4/6] libQt${QTVER}Pas の自前ビルド ==="
cd "$LAZARUS_SRC/lcl/interfaces/qt${QTVER}/cbindings"
"$QMAKE_CMD" "Qt${QTVER}Pas.pro"
make -j"$(nproc)"

echo "=== libQt${QTVER}Pas をシステムにインストール ==="
libdir=$(dirname "$(ldconfig -p | grep "libQt${QTVER}Core.so " | head -1 | awk '{print $NF}')")
if [ -z "$libdir" ]; then
    # Fallback: common paths
    if [ -d "/usr/lib/x86_64-linux-gnu" ]; then
        libdir="/usr/lib/x86_64-linux-gnu"
    elif [ -d "/usr/lib/aarch64-linux-gnu" ]; then
        libdir="/usr/lib/aarch64-linux-gnu"
    else
        echo "警告: ライブラリの配置先が自動判定できませんでした。手動でコピーしてください:"
        echo "  cp -P $LAZARUS_SRC/lcl/interfaces/qt${QTVER}/cbindings/libQt${QTVER}Pas.so* /path/to/lib/dir/"
        exit 1
    fi
fi
echo "配置先: $libdir"
sudo cp -P "libQt${QTVER}Pas.so"* "$libdir/"
sudo ldconfig
cd "$LAZARUS_SRC"

echo "=== [5/6] Lazarus本体をビルド (${TARGET}版、時間がかかります) ==="
make bigide LCL_PLATFORM=qt${QTVER}

echo "=== [6/6] 完了 ==="
echo ""
echo "ビルドが完了しました。既存のLazarus環境と設定が衝突しないよう、"
echo "必ず --pcp オプションを付けて起動してください:"
echo ""
echo "  cd $LAZARUS_SRC"
echo "  ./lazarus --pcp=~/.lazarus_jpsupport_${TARGET}"
echo ""
echo "初回起動時に「既存の設定と衝突する可能性がある」という警告が"
echo "出た場合は、必ず「中止(Abort)」を選んでください。"

if [[ "$LAZARUS_VERSION" != "$DEFAULT_LAZARUS_VERSION" ]]; then
    echo ""
    echo "======================================================================"
    echo "このバージョン($LAZARUS_VERSION)でのビルドが成功しました。"
    read -r -p "今後デフォルトとして使いますか？(実機での日本語入力動作は、この確認とは別にご自身で確認してください) [y/N]: " promote
    if [[ "$promote" == "y" || "$promote" == "Y" ]]; then
        SELF_SCRIPT="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
        sed -i "s/^DEFAULT_LAZARUS_VERSION=\".*\"/DEFAULT_LAZARUS_VERSION=\"$LAZARUS_VERSION\"/" "$SELF_SCRIPT"
        echo "更新しました: DEFAULT_LAZARUS_VERSION=\"$LAZARUS_VERSION\""
        echo "docs/upstream-status.md にも検証結果の記録をお忘れなく。"
    else
        echo "デフォルトは変更しませんでした。次回もこのバージョンを使う場合は"
        echo "改めて --lazarus-version=$LAZARUS_VERSION を指定してください。"
    fi
    echo "======================================================================"
fi
