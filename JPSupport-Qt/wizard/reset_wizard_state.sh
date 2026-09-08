#!/bin/bash
# reset_wizard_state.sh
#
# 001: 「JPSupport-Qtウィザードを初めて手に入れた状態」を再現するための
#      リセットスクリプト。ビルド成果物・Lazarus設定ディレクトリ・
#      build_jpsupport_qt.sh自身の自己書き換え(DEFAULT_LAZARUS_VERSION)を
#      初期状態に戻す。patches/・docs/・README等のプロジェクト本体には
#      一切触れない。
#
# 使い方:
#   ./reset_wizard_state.sh

set -e

PROJECT_DIR="$HOME/Projects/JPSupport/JPSupport-Qt"
WIZARD_DIR="$PROJECT_DIR/wizard"
SCRIPT_PATH="$PROJECT_DIR/patches/build_jpsupport_qt.sh"

# 検証記録(docs/upstream-status.md)が確かな、出荷時のデフォルトバージョン。
# 一連の混乱で生じたlazarus_4_6への格上げは、実機でのIME動作確認が本当に
# 完了していたか確信が持てないため、「初めて手に入れた状態」としては採用しない。
SHIPPED_DEFAULT_VERSION="lazarus_4_8"

BUILD_TARGETS=(
    "$WIZARD_DIR/jpsupport-qt-build-qt5"
    "$WIZARD_DIR/jpsupport-qt-build-qt5-alt"
    "$WIZARD_DIR/jpsupport-qt-build-qt6"
    "$WIZARD_DIR/jpsupport-qt-build-qt6-alt"
)

echo "=== 削除対象の確認 ==="
FOUND_ANY=0
for t in "${BUILD_TARGETS[@]}"; do
    if [ -d "$t" ]; then
        FOUND_ANY=1
        SIZE="$(du -sh "$t" 2>/dev/null | cut -f1)"
        echo "  削除: $t (${SIZE})"
    fi
done

for t in "$HOME"/.lazarus_jpsupport_*; do
    if [ -d "$t" ]; then
        FOUND_ANY=1
        echo "  削除: $t"
    fi
done

if [ "$FOUND_ANY" == "0" ]; then
    echo "  (削除対象のビルド成果物・設定ディレクトリは見つかりませんでした)"
fi

echo ""
echo "スクリプトのDEFAULT_LAZARUS_VERSIONを '${SHIPPED_DEFAULT_VERSION}' に戻します:"
echo "  ${SCRIPT_PATH}"
if [ -f "$SCRIPT_PATH" ]; then
    echo "  (現在の値: $(grep '^DEFAULT_LAZARUS_VERSION=' "$SCRIPT_PATH" 2>/dev/null || echo '見つかりません'))"
fi
echo ""

read -r -p "本当に上記を削除・リセットしますか？ [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "中止しました。"
    exit 1
fi

echo ""
echo "=== 実行 ==="
for t in "${BUILD_TARGETS[@]}"; do
    if [ -d "$t" ]; then
        rm -rf "$t"
        echo "削除しました: $t"
    fi
done

for t in "$HOME"/.lazarus_jpsupport_*; do
    if [ -d "$t" ]; then
        rm -rf "$t"
        echo "削除しました: $t"
    fi
done

if [ -f "$SCRIPT_PATH" ]; then
    sed -i "s/^DEFAULT_LAZARUS_VERSION=\".*\"/DEFAULT_LAZARUS_VERSION=\"${SHIPPED_DEFAULT_VERSION}\"/" "$SCRIPT_PATH"
    echo "DEFAULT_LAZARUS_VERSIONを '${SHIPPED_DEFAULT_VERSION}' に戻しました。"
else
    echo "警告: ${SCRIPT_PATH} が見つかりません。手動で確認してください。"
fi

echo ""
echo "=== 旧セキュリティ実装(sudoラッパー)の残骸チェック ==="
echo "(自動削除はしません。見つかった場合は内容を確認の上、手動で削除してください)"
find "$HOME" -maxdepth 2 \( -iname "*sudo*wrapper*" -o -iname "*jpsupport*sudo*" \) 2>/dev/null || true

echo ""
echo "リセット完了。「JPSupport-Qtウィザードを初めて手に入れた状態」に戻りました。"
echo "システムに導入済みのlibQt5Pas/libQt6Pasはそのままです(次回のインストール・"
echo "ビルド実行時に、通常通り上書きされます)。"
