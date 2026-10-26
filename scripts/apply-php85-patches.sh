#!/bin/sh
#
# PHP 8.5 互換パッチ適用スクリプト
#
# NetCommons3 が依存する CakePHP 2.10 と cakedc/migrations は composer 管理
# (vendors/, app/Plugin/) のため、PHP 8 系で動かすための修正をこのリポジトリへ
# 直接コミットできない。そこで patches/*.patch に差分を持ち、composer install /
# update のたびに自動適用する。
#
# 使い方:
#   sh scripts/apply-php85-patches.sh
#
# composer.json の scripts.post-install-cmd / post-update-cmd から自動実行される。
#
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

failed=0

for p in patches/*.patch; do
	[ -f "$p" ] || continue

	if patch -p1 -N -s --dry-run -i "$p" >/dev/null 2>&1; then
		if patch -p1 -N -s -i "$p"; then
			echo "[applied] $p"
		else
			echo "[FAILED]  $p (適用に失敗しました)" >&2
			failed=1
		fi
	elif patch -p1 -R -N -s --dry-run -i "$p" >/dev/null 2>&1; then
		echo "[skip]    $p (適用済み)"
	else
		echo "[FAILED]  $p (コンフリクト。手動で確認してください)" >&2
		failed=1
	fi
done

if [ "$failed" -ne 0 ]; then
	echo "" >&2
	echo "パッチが適用できませんでした。依存パッケージのバージョンが変わった可能性があります。" >&2
	echo "composer.lock の cakephp/cakephp と cakedc/migrations のバージョンを確認してください。" >&2
	exit 1
fi

exit 0
