---
name: keychain-credentials
description: Skill for passing IDs and passwords stored in macOS Keychain to commands without displaying the values. Use when credentials are needed for DB clients (mongosh / mysql / psql), API calls, or scripts, or when asked things like "entering the password every time is annoying", "I want to use the Keychain password", "I don't want to put credentials in environment variables", 「パスワードを毎回聞かれるのが面倒」「Keychain のパスワードを使いたい」「認証情報を環境変数に置きたくない」, or any similar phrasing in English or Japanese. If the item is not registered, show the registration steps.
---

# Using Keychain Credentials

Retrieve IDs and passwords from macOS Keychain generic password items and pass them to commands without printing the values to stdout.

## Principles

**Never expose password values in conversation, logs, shell history, or process lists.**

`scripts/keychain-cred.sh` deliberately has no stdout-print mode. You either pass values via `exec` as environment variables or stream them via `stdin`. Do not try to work around this boundary to read values out.

## Usage

### Check whether an item exists

```shell
keychain-cred.sh check <service>
```

The script lives under this skill's directory (`<skills>/keychain-credentials/scripts/keychain-cred.sh`). `<skills>` is the skill root where this skill is installed (`~/.claude/skills` / `~/.agents/skills`); the examples below omit the absolute path.

If found, it returns `found: service=... account=...`. If missing, it prints the registration steps and exits with code 4. Always run this before doing anything else. Explain the check result to the user in Japanese:

```
確認結果: <found: service=... account=... / 未登録のため登録手順を表示しました>。
```

### Pass as environment variables

By default the password goes into `KEYCHAIN_PASSWORD`, and the account name always goes into `KEYCHAIN_ACCOUNT`.

```shell
keychain-cred.sh exec myservice -- sh -c 'mongosh "$MONGO_URI" -u "$KEYCHAIN_ACCOUNT" -p "$KEYCHAIN_PASSWORD"'
keychain-cred.sh exec myservice --var PGPASSWORD -- psql -h host -U user db
```

`--var` changes the variable name. Putting the value directly into the variable name the tool reads (`PGPASSWORD`, `MYSQL_PWD`, ...) is safest because it never appears on the command line.

### Stream to standard input

For tools that read the password from stdin.

```shell
keychain-cred.sh stdin myservice -- gh auth login --with-token
```

### Show only the registration steps

```shell
keychain-cred.sh setup <service> [account]
```

## Registration

Registration requires interactive input, so ask the user to run it in their own regular terminal. It cannot be done through agent-run commands because there is no TTY. Present the following to the user in Japanese:

```
登録は対話入力が必要なため、お使いの通常のターミナルで以下のコマンドを実行してください。エージェント経由では TTY が無いため代行できません。
```

```shell
security add-generic-password -s '<service>' -a '<account>' -l '<service> (script)' -w
```

Do not write the value after `-w`. It stays in shell history and the process list. If omitted, you are prompted twice (entry and confirmation). Present the following to the user in Japanese:

```
`-w` の後に値は書かないでください。書くとシェル履歴とプロセス一覧に残ります。省略した場合は「入力」と「確認」の2回聞かれます。
```

On the first read after registration, an access permission dialog appears. Ask the user to choose **"Always Allow"**. With just "Allow", the dialog appears every time and unattended runs cannot proceed. Present the following to the user in Japanese:

```
初回読み出し時にアクセス許可ダイアログが表示されます。「常に許可」を選んでください。「許可」では毎回表示され、無人実行できません。
```

## Pitfalls

- **iCloud password items cannot be read**. Items saved in the Passwords app carry a sync flag and are fundamentally invisible from the `security` CLI. Even calling the Security framework directly requires an entitlement, so a self-built CLI cannot reach them either. Create a separate local generic password item for scripts
- **`-U` overwrite fails when the label mismatches**. If you see `SecKeychainItemCreateFromContent: The specified item already exists`, run `security delete-generic-password -s '<service>'` and register again
- **Verify the length right after registration**. A stray newline in a paste can confirm the prompt early and store a truncated value. Run `check` first, and if anything looks suspicious, present the following to the user in Japanese and confirm before attempting authentication:

  ```
  登録された値が短い可能性があります。`check` の結果は以下の通りです: <result>。再登録しますか? 認証を試す前にご確認ください。
  ```
- **zsh expands `!` even inside double quotes**. If you temporarily put a password in an environment variable, `export PW="...!..."` corrupts the value
- **`--password <value>` stays in the process list**. Use environment variables or stdin whenever possible

## Do not waste authentication attempts

Do not hit an authentication endpoint while the password looks doubtful. It needlessly consumes account lockout budgets and WAF rate limits. Verify the item and account name with `check`, and if the value looks suspicious, present the following to the user in Japanese and ask them to re-register before trying:

```
値が正しいか疑わしいため、認証は試していません。`check` で項目とアカウント名を確認しました。再登録してからお知らせください。
```
