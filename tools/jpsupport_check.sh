#!/bin/bash

echo "=== JPSupport 環境診断 ==="
echo ""

# ① 環境変数チェック
echo "① 環境変数チェック"
GTK_IM="$GTK_IM_MODULE"
XMOD="$XMODIFIERS"

if [[ "$GTK_IM" == "fcitx" || "$GTK_IM" == "fcitx5" || "$GTK_IM" == "ibus" ]]; then
    echo "  GTK_IM_MODULE=$GTK_IM ... OK"
else
    echo "  GTK_IM_MODULE=$GTK_IM ... NG（fcitx5またはibusが必要）"
    exit 1
fi

if [[ "$XMOD" == "@im=fcitx" || "$XMOD" == "@im=fcitx5" || "$XMOD" == "@im=ibus" ]]; then
    echo "  XMODIFIERS=$XMOD ... OK"
else
    echo "  XMODIFIERS=$XMOD ... NG（@im=fcitx5または@im=ibusが必要）"
    exit 1
fi

echo ""

# ② GTK2 IMモジュールの存在チェック
echo "② GTK2 IMモジュールチェック"
IMMOD_PATH=$(find /usr/lib -path "*/gtk-2.0/*" -name "im-fcitx5.so" -o -path "*/gtk-2.0/*" -name "im-ibus.so" 2>/dev/null | head -1)

if [[ -n "$IMMOD_PATH" ]]; then
    echo "  $IMMOD_PATH ... OK"
else
    echo "  GTK2 IMモジュールが見つかりません ... NG"
    echo "  sudo apt install fcitx5-frontend-gtk2 または ibus-gtk を実行してください"
    exit 1
fi

echo ""

# ③ IMサーバーの起動確認
echo "③ IMサーバー起動確認"
if [[ "$GTK_IM" == "fcitx" || "$GTK_IM" == "fcitx5" ]]; then
    REMOTE=$(fcitx5-remote 2>/dev/null)
    if [[ "$REMOTE" == "1" || "$REMOTE" == "2" ]]; then
        echo "  Fcitx5 起動中 ... OK"
    else
        echo "  Fcitx5 が起動していません ... NG"
        echo "  fcitx5 & を実行してください"
        exit 1
    fi
elif [[ "$GTK_IM" == "ibus" ]]; then
    if pgrep -x "ibus-daemon" > /dev/null; then
        echo "  IBus 起動中 ... OK"
    else
        echo "  IBus が起動していません ... NG"
        echo "  ibus-daemon -drx を実行してください"
        exit 1
    fi
fi

echo ""
echo "=== 環境チェック完了 ==="
echo "JPSupportを使用する準備が整っています。"
echo "Lazarusのソースエディタで変換キーを押して日本語入力をお試しください。"
