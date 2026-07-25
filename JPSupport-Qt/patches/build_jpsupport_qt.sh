#!/bin/bash
# build_jpsupport_qt.sh
#
# JPSupport-Qt を、自分のマシンに実際にビルド・導入するための一連の
# 作業(ソース取得・パッチ適用・ライブラリビルド・Lazarus本体ビルド)を
# まとめて行うスクリプトです。
#
# 使い方:
#   ./build_jpsupport_qt.sh qt5      # Qt5版のみビルド
#   ./build_jpsupport_qt.sh qt6      # Qt6版のみビルド
#   ./build_jpsupport_qt.sh both     # 両方ビルド(デフォルト)
#
# 実行前に確認してください:
#   - 必要な開発パッケージ(qtbase5-dev等)は、事前にインストール
#     しておく必要があります。詳細はREADME.mdを参照してください。
#   - このスクリプトは、既存のLazarus環境を上書きしません。新しい
#     ディレクトリにソース一式を取得し、独立してビルドします。
#   - システムのlibQt5Pas/libQt6Pasライブラリを上書きします。
#     心配な方は事前にバックアップを取ってください。

set -e

TARGET="${1:-both}"
if [[ "$TARGET" != "qt5" && "$TARGET" != "qt6" && "$TARGET" != "both" ]]; then
    echo "使い方: $0 [qt5|qt6|both]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(pwd)/jpsupport-qt-build"
LAZARUS_SRC="${WORK_DIR}/lazarus-src"

echo "=== [1/6] 作業ディレクトリの準備 ==="
mkdir -p "$WORK_DIR"

if [ -d "$LAZARUS_SRC" ]; then
    echo "既存のLazarusソース($LAZARUS_SRC)が見つかりました。再利用します。"
else
    echo "=== [2/6] Lazarusソース(fixes_4ブランチ)を取得 ==="
    git clone --branch fixes_4 https://gitlab.com/freepascal.org/lazarus/lazarus.git "$LAZARUS_SRC"
fi

echo "=== [3/6] JPSupportパッチを適用 (対象: $TARGET) ==="
cd "$LAZARUS_SRC"
python3 "$SCRIPT_DIR/apply_jpsupport_patches.py" "$TARGET"

build_qt_binding() {
    local qtver="$1"          # "5" or "6"
    local qmake_cmd="$2"      # "qmake" or "qmake6"
    local libname="libQt${qtver}Pas"

    echo "=== libQt${qtver}Pas の自前ビルド ==="
    cd "$LAZARUS_SRC/lcl/interfaces/qt${qtver}/cbindings"
    "$qmake_cmd" "Qt${qtver}Pas.pro"
    make -j"$(nproc)"

    echo "=== libQt${qtver}Pas をシステムにインストール ==="
    local libdir
    libdir=$(dirname "$(ldconfig -p | grep "libQt5Core.so " | head -1 | awk '{print $NF}')")
    if [ -z "$libdir" ]; then
        # Fallback: common paths
        if [ -d "/usr/lib/x86_64-linux-gnu" ]; then
            libdir="/usr/lib/x86_64-linux-gnu"
        elif [ -d "/usr/lib/aarch64-linux-gnu" ]; then
            libdir="/usr/lib/aarch64-linux-gnu"
        else
            echo "警告: ライブラリの配置先が自動判定できませんでした。手動でコピーしてください:"
            echo "  cp -P $LAZARUS_SRC/lcl/interfaces/qt${qtver}/cbindings/${libname}.so* /path/to/lib/dir/"
            return 1
        fi
    fi
    echo "配置先: $libdir"
    sudo cp -P "${libname}.so"* "$libdir/"
    sudo ldconfig
    cd "$LAZARUS_SRC"
}

if [[ "$TARGET" == "qt5" || "$TARGET" == "both" ]]; then
    echo "=== [4/6] Qt5用ライブラリのビルド ==="
    build_qt_binding "5" "qmake"
fi

if [[ "$TARGET" == "qt6" || "$TARGET" == "both" ]]; then
    echo "=== [4/6] Qt6用ライブラリのビルド ==="
    build_qt_binding "6" "qmake6"
fi

echo "=== [5/6] Lazarus本体をビルド ==="
cd "$LAZARUS_SRC"
if [[ "$TARGET" == "qt5" || "$TARGET" == "both" ]]; then
    echo "--- Qt5版をビルド中 (時間がかかります) ---"
    make bigide LCL_PLATFORM=qt5
fi
if [[ "$TARGET" == "qt6" || "$TARGET" == "both" ]]; then
    echo "--- Qt6版をビルド中 (時間がかかります) ---"
    make bigide LCL_PLATFORM=qt6
fi

echo "=== [6/6] 完了 ==="
echo ""
echo "ビルドが完了しました。既存のLazarus環境と設定が衝突しないよう、"
echo "必ず --pcp オプションを付けて起動してください:"
echo ""
echo "  cd $LAZARUS_SRC"
echo "  ./lazarus --pcp=~/.lazarus_jpsupport_qt"
echo ""
echo "初回起動時に「既存の設定と衝突する可能性がある」という警告が"
echo "出た場合は、必ず「中止(Abort)」を選んでください。"
