---
name: keychain-credentials
description: macOS Keychain に保存した ID とパスワードを、値を画面に出さずにコマンドへ渡すスキル。DB クライアント (mongosh / mysql / psql) や API 呼び出し、スクリプトで資格情報が必要になったとき、また「パスワードを毎回聞かれるのが面倒」「Keychain のパスワードを使いたい」「認証情報を環境変数に置きたくない」といった依頼で使用する。項目が未登録なら登録手順を案内する。
---

# Keychain の資格情報を使う

macOS Keychain の generic password 項目から ID とパスワードを取り出し、値を stdout に出さずにコマンドへ渡す。

## 原則

**パスワードの値を会話・ログ・シェル履歴・プロセス一覧に出さない。**

`scripts/keychain-cred.sh` は値を stdout に出す手段を意図的に持たない。`exec` で環境変数として渡すか、`stdin` で標準入力に流すかの二択にしてある。この境界を回避して値を読み出そうとしないこと。

## 使い方

### 項目があるか調べる

```shell
keychain-cred.sh check <service>
```

スクリプトはこのスキルのディレクトリ配下 (`<skills>/keychain-credentials/scripts/keychain-cred.sh`) にある。`<skills>` はこのスキルが置かれているスキルルート (`~/.claude/skills` / `~/.agents/skills`) で、以下の例では絶対パスを省略して書く。

見つかれば `found: service=... account=...` を返す。無ければ登録手順を出して終了コード 4 になる。何かを実行する前にまずこれを叩く。

### 環境変数として渡す

既定では `KEYCHAIN_PASSWORD`、アカウント名は常に `KEYCHAIN_ACCOUNT` に入る。

```shell
keychain-cred.sh exec myservice -- sh -c 'mongosh "$MONGO_URI" -u "$KEYCHAIN_ACCOUNT" -p "$KEYCHAIN_PASSWORD"'
keychain-cred.sh exec myservice --var PGPASSWORD -- psql -h host -U user db
```

`--var` で変数名を変えられる。`PGPASSWORD` や `MYSQL_PWD` のように、ツールが読む変数名に直接入れるのが最も安全で、コマンドラインに載らない。

### 標準入力に流す

パスワードを stdin から読むツール向け。

```shell
keychain-cred.sh stdin myservice -- gh auth login --with-token
```

### 登録手順だけ表示する

```shell
keychain-cred.sh setup <service> [account]
```

## 登録

登録は対話入力が必要なので、ユーザー自身に通常のターミナルで実行してもらう。agent 経由のコマンド実行には TTY が無いため代行できない。

```shell
security add-generic-password -s '<service>' -a '<account>' -l '<service> (script)' -w
```

`-w` に値を書かないこと。書くとシェル履歴とプロセス一覧に残る。値を書かない場合は「入力」と「確認」の 2 回聞かれる。

登録後の初回読み出しでアクセス許可ダイアログが出る。**「常に許可」** を選んでもらう。「許可」だと毎回ダイアログが出て無人実行できない。

## 落とし穴

- **iCloud パスワードの項目は読めない**。パスワードアプリに保存された項目は同期対象フラグが付いており、`security` CLI からは原理的に見えない。Security フレームワークを直接叩いても entitlement が要るので自前の CLI からは通らない。スクリプト用にローカルの generic password 項目を別途作る
- **`-U` による上書きはラベルが食い違うと失敗する**。`SecKeychainItemCreateFromContent: The specified item already exists` が出たら、`security delete-generic-password -s '<service>'` で消してから登録し直す
- **登録直後は文字数を確認する**。ペーストに改行が混ざるとプロンプトが途中で確定し、短い値が入る。`check` を通したうえで、疑わしければ実際に認証を試す前にユーザーへ確認する
- **zsh はダブルクォート内でも `!` を履歴展開する**。パスワードを一時的に環境変数へ入れる場合、`export PW="...!..."` は値が壊れる
- **`--password <値>` の形はプロセス一覧に残る**。可能な限り環境変数か stdin を使う

## 認証失敗を安売りしない

パスワードが正しいか怪しい状態で認証エンドポイントを叩かない。アカウントのロックアウトや WAF のレート制限を無駄に消費する。`check` で項目とアカウント名を確かめ、値が疑わしければユーザーに再登録を依頼してから試す。
