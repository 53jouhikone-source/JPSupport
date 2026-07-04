# JPSupportCheck

JPSupportの動作環境を自動診断するツールです。

## 前提条件

- Lazarusが起動済みであること
- ソースエディタが開いていること
- 実行前にソースエディタの内容を保存しておくこと

## 実行方法

```bash
~/Projects/JPSupport/tools/JPSupportCheck
```

## チェック項目

① GTK_IM_MODULE・XMODIFIERSの環境変数確認
② GTK2 IMモジュールの存在確認
③ IMサーバー（Fcitx5/IBus）の起動確認
④ JPSupportのインストール確認
⑤ 実際の日本語入力テスト

## 注意事項

テスト中はLazarusのソースエディタが一時的に操作されます。
ソースエディタの内容はテスト後に元に戻されます。
