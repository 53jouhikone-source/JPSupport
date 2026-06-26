# JPSupport - Lazarusソースエディタ日本語入力 問題報告書
# 作成日：2026-06-23

## プロジェクト概要

- 目標：LazarusのソースエディタへのLinux日本語入力実現
- 環境：Raspberry Pi 4 / ARM64 / Debian 12 / Lazarus 2.2.6 / FPC 3.2.2 / GTK2バックエンド / Fcitx5 + Mozc
- 達成済み：TJPSupport（TSynEdit継承クラス）として日本語入力は完全動作確認済み

## 技術的背景

### LCLのGTK2 IME処理フロー

1. キーイベント時にgtk2proc.incのCheckDeadKeyがim_context_widgetを設定
2. Mozcが変換候補を確定するとGTKのシグナル（preedit-changed/commit等）が発火
3. gtk2widgetset.incのコールバックがSendMessage(control.Handle, LM_IM_COMPOSITION, ...)を呼ぶ
4. controlはGetNearestLCLObject(im_context_widget)で取得したTWinControl
5. TSynEditのGTK_IMCompositionがFImeHandler.WMImeCompositionを呼ぶ

### Lazarusソースエディタの構造

- TIDESynEditor = class(TSynEdit)（sourcesyneditor.pasの242行目）
- SourceEditorManagerIntf.ActiveEditor.EditorControlでTIDESynEditorのインスタンスを取得可能
- semEditorActivateイベントでエディタ切り替えを検知可能

### 重要な発見

- インストール済みsynedit.ppuはGtk2IMEフラグ無効でビルドされている
- そのためGTK_IMCompositionメッセージハンドラが存在しない
- LM_IM_COMPOSITIONが送られてもFImeHandler.WMImeCompositionが呼ばれない

## 試みたアプローチと結果

### アプローチ1：GTKコールバック直接登録（失敗）
- g_signal_connectでpreedit/commitコールバックを追加
- LCLが既に同じシグナルを処理しているため二重処理が発生
- 文字が複数回挿入される問題が発生

### アプローチ2：ImeHandler差し替え（失敗）
- TSynEditAccess(FEditor).ImeHandler := TJPSynImeGtk2.Create(...)
- ImeHandlerはprotectedだが同ユニット内アクセサクラス経由で差し替え可能
- しかしGtk2IMEフラグ無効のためGTK_IMComposition自体が存在せずWMImeCompositionが呼ばれない

### アプローチ3：WindowProc差し替え（失敗・原因不明）
- FEditor.WindowProc := @NewWindowProcでLM_IM_COMPOSITIONを横取りしようとした
- Attachは成功しHandleも取得できているがNewWindowProcが一切呼ばれない
- LM_CHARもLM_IM_COMPOSITIONも届いていない
- TSynEditがWindowProcを使わず別の経路でメッセージ処理している可能性

## 未解決の疑問

1. TSynEditはWndProcをオーバーライドしているが、WindowProcとの関係は？
2. LM_IM_COMPOSITIONはSendMessageで送られるが、なぜWindowProcに届かないのか？
3. Gtk2IMEフラグを有効にしてSynEditを再ビルドすればImeHandler差し替えは機能するか？
4. SendMessageの送信先control.HandleとTIDESynEditor.Handleは一致しているか？

## 現在のファイル構成

~/Projects/JPSupport/package/
- JPSupportUnit.pas      TJPSupport（TSynEdit継承）動作確認済み 最重要
- JPSupportAdapter.pas   TJPSupportAdapter（アタッチ方式）現在調査中
- JPSupportIDEMain.pas   Lazarusパッケージ登録・semEditorActivateフック
- JPSupport.lpk          RunAndDesignTimeパッケージ
- JPSupportIDE.lpk       DesignTimeパッケージ（IDE組み込み用）

## 動作確認済みの事実

- TJPSupportをフォームに貼り付けたデモアプリでは日本語入力完全動作
- semEditorActivateでLazarusのソースエディタ切り替えを検知できる
- SourceEditorManagerIntf.ActiveEditor.EditorControlでTIDESynEditor取得可能
- TJPSupportAdapter.Attachは正常に呼ばれHandleも取得できている

## 求める解決策

TIDESynEditor（Lazarusのソースエディタ）に対して、
ソースを改変せずに外部から日本語IME処理をアタッチする方法。

具体的には以下のいずれか：
- LM_IM_COMPOSITIONメッセージを横取りする方法
- GTKコールバックを二重登録せずにIME処理を挿入する方法
- その他のアプローチ
