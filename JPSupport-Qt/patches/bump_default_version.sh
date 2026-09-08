#!/bin/bash
# bump_default_version.sh
#
# 002: 3つの安全対策を追加。
#      (a) 書式チェック: lazarus_の後に数字とアンダースコアのみを許可
#      (b) ローカル検証済みチェック: qt5-alt/qt6-altのいずれかで、指定バージョンが
#          実際にビルド・パッチ適用済みであることを必須化(一度も試していない
#          バージョンをうっかり正式デフォルトにしてしまう事故を防ぐ)
#      (c) ダウングレード検知: 新しい値が現在より古い場合、専用の警告を表示
#
# 001: プロジェクトの正式なデフォルトバージョン(DEFAULT_LAZARUS_VERSION)を
#      更新するための、開発者向けメンテナンススクリプト。
#
#      これは build_jpsupport_qt.sh 内の「格上げしますか」ダイアログ
#      (ローカルの実機・個人の一時的な設定を想定したもの)とは別物で、
#      「git clone した瞬間から、指定したバージョンがデフォルトになる」
#      という、プロジェクト本体の更新を行う。ローカルのビルドフォルダ
#      (jpsupport-qt-build-*)の状態には一切左右されない。
#
# 使い方:
#   ./bump_default_version.sh lazarus_5_0
#
# 実行後にやること(自動化されていないため、手動で対応してください):
#   - docs/upstream-status.md に検証結果を記録
#   - git add patches/build_jpsupport_qt.sh docs/upstream-status.md
#   - git commit -m "Bump default Lazarus version to lazarus_5_0"

set -e

if [ -z "$1" ]; then
    echo "使い方: $0 <新しいデフォルトバージョンのタグ>"
    echo "例:     $0 lazarus_5_0"
    exit 1
fi

NEW_VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/build_jpsupport_qt.sh"
WIZARD_DIR="$SCRIPT_DIR/../wizard"

# (a) 書式チェック: lazarus_の後は数字とアンダースコアのみ許可(例: lazarus_5_0)。
#     sedの置換文字列としてそのまま使うため、/や&等を含む文字列は特に危険。
if ! [[ "$NEW_VERSION" =~ ^lazarus_[0-9]+(_[0-9]+)*$ ]]; then
    echo "エラー: バージョンの形式が不正です(例: lazarus_5_0)。" >&2
    echo "  指定された値: $NEW_VERSION" >&2
    exit 1
fi

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "エラー: build_jpsupport_qt.sh が見つかりません: $SCRIPT_PATH" >&2
    exit 1
fi

CURRENT_VERSION="$(grep '^DEFAULT_LAZARUS_VERSION=' "$SCRIPT_PATH" | sed -E 's/^DEFAULT_LAZARUS_VERSION="(.*)"$/\1/')"

if [ -z "$CURRENT_VERSION" ]; then
    echo "エラー: 現在のDEFAULT_LAZARUS_VERSIONを読み取れませんでした。" >&2
    exit 1
fi

if [ "$CURRENT_VERSION" == "$NEW_VERSION" ]; then
    echo "既に DEFAULT_LAZARUS_VERSION=\"$NEW_VERSION\" になっています。何もしません。"
    exit 0
fi

# (b) ローカル検証済みチェック: 非デフォルトバージョンは常に-altフォルダで
#     ビルドされる設計(unit1.pas GetTargetBuildDirName)なので、qt5-alt/qt6-alt
#     いずれかの.jpsupport-patchedマーカーが今回指定したバージョンと一致するかで
#     「実機で試したことがあるか」を判定する。一致が無ければ拒否する(警告では
#     なく、明確に処理を止める)。
VERIFIED_TARGETS=()
for t in qt5 qt6; do
    MARKER="$WIZARD_DIR/jpsupport-qt-build-${t}-alt/lazarus-src/.jpsupport-patched"
    if [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" == "${t}:${NEW_VERSION}" ]; then
        VERIFIED_TARGETS+=("$t")
    fi
done

if [ "${#VERIFIED_TARGETS[@]}" -eq 0 ]; then
    echo "エラー: '$NEW_VERSION' は、このマシンでまだビルド・検証されていないようです。" >&2
    echo "先にウィザードの「上級者向け設定」からこのバージョンを指定してビルドし、" >&2
    echo "実機での日本語入力動作を確認してから、改めて実行してください。" >&2
    exit 1
fi

echo "ローカルで検証済み: ${VERIFIED_TARGETS[*]}"
echo ""

echo "=== 確認 ==="
echo "  現在のデフォルト: $CURRENT_VERSION"
echo "  新しいデフォルト: $NEW_VERSION"
echo "  対象ファイル:     $SCRIPT_PATH"
echo ""
echo "※ これはプロジェクト本体(gitにコミットする側)の更新です。"
echo "  ローカルのビルドフォルダ(jpsupport-qt-build-*)には触れません。"
echo ""

# (c) ダウングレード検知: lazarus_X_Y形式の"_"を"."に置き換え、sort -Vで
#     数値として比較する。新しい値の方が古ければ、ダウングレードである旨を
#     明示して確認を挟む。
CURRENT_KEY="$(echo "$CURRENT_VERSION" | sed 's/^lazarus_//; s/_/./g')"
NEW_KEY="$(echo "$NEW_VERSION" | sed 's/^lazarus_//; s/_/./g')"
LARGER_KEY="$(printf '%s\n%s\n' "$CURRENT_KEY" "$NEW_KEY" | sort -V | tail -1)"

if [ "$LARGER_KEY" == "$CURRENT_KEY" ]; then
    echo "警告: これは $CURRENT_VERSION から $NEW_VERSION への、バージョンを"
    echo "  下げる操作です(通常のアップグレードではありません)。"
    read -r -p "  本当にダウングレードしますか？ [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "中止しました。"
        exit 1
    fi
    echo ""
fi

# タグが本当にupstreamに存在するか、念のため確認する(ネットワークが無い環境では
# スキップして続行するか聞く)。
echo "upstreamに '$NEW_VERSION' タグが存在するか確認しています..."
if git ls-remote --tags https://gitlab.com/freepascal.org/lazarus/lazarus.git "refs/tags/$NEW_VERSION" 2>/dev/null | grep -q "$NEW_VERSION"; then
    echo "  確認できました。"
else
    echo "  警告: upstreamで確認できませんでした(ネットワーク不通、またはタグが存在しない可能性)。"
    read -r -p "  それでも続行しますか？ [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "中止しました。"
        exit 1
    fi
fi

read -r -p "上記の内容で更新しますか？ [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "中止しました。"
    exit 1
fi

sed -i "s/^DEFAULT_LAZARUS_VERSION=\".*\"/DEFAULT_LAZARUS_VERSION=\"$NEW_VERSION\"/" "$SCRIPT_PATH"
echo ""
echo "更新しました: DEFAULT_LAZARUS_VERSION=\"$NEW_VERSION\""
echo ""
echo "忘れずに以下を行ってください:"
echo "  1. docs/upstream-status.md に検証結果を記録"
echo "  2. git add patches/build_jpsupport_qt.sh docs/upstream-status.md"
echo "  3. git commit -m \"Bump default Lazarus version to $NEW_VERSION\""
echo ""
echo "これで、この変更をpull(またはclone)した環境では、"
echo "何も指定せず「インストール・ビルド」を実行するだけで"
echo "$NEW_VERSION がいきなり手に入るようになります。"
