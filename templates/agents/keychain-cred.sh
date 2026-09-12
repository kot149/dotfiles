#!/usr/bin/env bash
# macOS Keychain に保存した資格情報を、値を表に出さずにコマンドへ渡す。
#
#   keychain-cred.sh check <service>
#   keychain-cred.sh setup <service> [account]
#   keychain-cred.sh exec  <service> [--var NAME] -- <command> [args...]
#   keychain-cred.sh stdin <service> -- <command> [args...]
#
# パスワードを stdout に出す手段は意図的に持たない。exec か stdin を使う。
set -euo pipefail

usage() {
	sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
	echo "$*" >&2
	exit 1
}

[[ $(uname) == Darwin ]] || die "macOS 専用です"
command -v security >/dev/null || die "security コマンドが見つかりません"

# 項目の acct 属性。見つからなければ空文字と非ゼロ。
account_of() {
	local out
	out=$(security find-generic-password -s "$1" 2>/dev/null) || return 1
	sed -n 's/^[[:space:]]*"acct"<blob>="\(.*\)"$/\1/p' <<<"$out"
}

password_of() {
	security find-generic-password -s "$1" -w 2>/dev/null
}

# 項目が無いときは登録手順を案内して終了する。
require_item() {
	local service=$1
	if ! security find-generic-password -s "$service" >/dev/null 2>&1; then
		echo "Keychain に service=\"$service\" の項目がありません。" >&2
		echo >&2
		print_setup "$service" "" >&2
		exit 4
	fi
}

print_setup() {
	local service=$1 account=${2:-'<account>'}
	cat <<EOF
通常のターミナルで次を実行して登録してください。パスワードは対話で 2 回聞かれます。

  security add-generic-password -s '$service' -a '$account' -l '$service (script)' -w

-w に値を書かないのが重要です。書くとシェル履歴とプロセス一覧に残ります。

既に同じ service の項目があって上書きしたい場合は、先に削除します。
-U による上書きはラベルが食い違うと "already exists" で失敗します。

  security delete-generic-password -s '$service'

登録後の初回読み出しでアクセス許可ダイアログが出ます。「常に許可」を選んでください。
「許可」だと毎回ダイアログが出て、無人実行できません。
EOF
}

cmd=${1:-}
[[ -n $cmd ]] || {
	usage >&2
	exit 2
}
shift

case "$cmd" in
check)
	service=${1:-} && [[ -n $service ]] || die "service を指定してください"
	if acct=$(account_of "$service"); then
		echo "found: service=$service account=$acct"
	else
		echo "missing: service=$service"
		echo
		print_setup "$service"
		exit 4
	fi
	;;

setup)
	service=${1:-} && [[ -n $service ]] || die "service を指定してください"
	print_setup "$service" "${2:-}"
	;;

exec)
	service=${1:-} && [[ -n $service ]] || die "service を指定してください"
	shift
	var=KEYCHAIN_PASSWORD
	if [[ ${1:-} == --var ]]; then
		var=${2:?--var に変数名が必要です}
		shift 2
	fi
	[[ ${1:-} == -- ]] || die "-- のあとに実行するコマンドを書いてください"
	shift
	[[ $# -gt 0 ]] || die "実行するコマンドがありません"

	require_item "$service"
	pw=$(password_of "$service") || die "パスワードを読み出せませんでした"
	acct=$(account_of "$service" || true)
	export "$var=$pw" KEYCHAIN_ACCOUNT="$acct"
	exec "$@"
	;;

stdin)
	service=${1:-} && [[ -n $service ]] || die "service を指定してください"
	shift
	[[ ${1:-} == -- ]] || die "-- のあとに実行するコマンドを書いてください"
	shift
	[[ $# -gt 0 ]] || die "実行するコマンドがありません"

	require_item "$service"
	pw=$(password_of "$service") || die "パスワードを読み出せませんでした"
	printf '%s\n' "$pw" | "$@"
	;;

*)
	usage >&2
	exit 2
	;;
esac
