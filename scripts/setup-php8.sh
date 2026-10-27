#!/bin/sh
#
# NetCommons3 PHP 8.x セットアップ補助
#
#   sh scripts/setup-php8.sh              # 前提チェック → composer install → パッチ → bower 確認
#   sh scripts/setup-php8.sh --check      # チェックだけ（何も変更しない）
#   sh scripts/setup-php8.sh --skip-composer   # 依存導入を飛ばしてパッチ/確認のみ
#
# 終了コード: 0 = 続行可 / 1 = 未解決の前提あり
#
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

CHECK_ONLY=0
SKIP_COMPOSER=0
for arg in "$@"; do
	case "$arg" in
		--check) CHECK_ONLY=1 ;;
		--skip-composer) SKIP_COMPOSER=1 ;;
		-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
		*) echo "不明なオプションです: $arg" >&2; exit 2 ;;
	esac
done

ng=0
ok()   { echo "  [OK]     $1"; }
warn() { echo "  [注意]   $1"; }
bad()  { echo "  [要修正] $1"; ng=$((ng + 1)); }

# インストーラ (InstallValidatorUtil) が要求する書き込みパス
WRITABLES="app/Config app/tmp app/Uploads app/webroot/css app/webroot/js app/webroot/img app/webroot/theme"

# 拡張は「無いと実際に落ちるもの」だけを必須扱いにする
EXT_REQUIRED="pdo_mysql mbstring intl gd zip curl openssl fileinfo dom xml SimpleXML exif"

echo "== 1. PHP の確認 =="
if ! command -v php >/dev/null 2>&1; then
	bad "php が見つかりません"
else
	PHP_VERSION=$(php -r 'echo PHP_VERSION;')
	PHP_ID=$(php -r 'echo PHP_VERSION_ID;')
	if [ "$PHP_ID" -ge 80000 ]; then
		ok "PHP ${PHP_VERSION}（8.x）"
	else
		warn "PHP $PHP_VERSION は 8.0 未満。互換パッチは不要です（当てても動作に影響なし）"
	fi
	missing=""
	for ext in $EXT_REQUIRED; do
		php -m | grep -qx "$ext" || missing="$missing $ext"
	done
	if [ -z "$missing" ]; then
		ok "必要な拡張が揃っています"
	else
		bad "不足している拡張:$missing"
	fi
fi

echo "== 2. 必要なコマンド =="
for cmd in composer git patch; do
	if command -v "$cmd" >/dev/null 2>&1; then
		ok "$cmd"
	else
		bad "$cmd が見つかりません"
	fi
done
if command -v bower >/dev/null 2>&1; then
	ok "bower ($(bower --version 2>/dev/null | head -1))"
else
	warn "bower が見つかりません。UI が崩れます -> npm install -g bower"
fi

echo "== 3. 書き込み権限 =="
for dir in $WRITABLES; do
	if [ ! -d "$dir" ]; then
		if [ "$CHECK_ONLY" -eq 1 ]; then
			bad "$dir がありません"
		else
			mkdir -p "$dir" && ok "$dir を作成"
		fi
		continue
	fi
	if [ -w "$dir" ]; then
		ok "$dir"
	else
		bad "$dir に書き込めません"
	fi
done

echo "== 4. 依存パッケージの導入 =="
if [ "$CHECK_ONLY" -eq 1 ]; then
	warn "--check のためスキップ"
elif [ "$SKIP_COMPOSER" -eq 1 ]; then
	warn "--skip-composer のためスキップ"
elif [ -f vendors/autoload.php ]; then
	warn "vendors/ 導入済み。再実行するなら composer install を直接実行"
else
	echo "  -> composer install（パッチは post-install-cmd で自動適用）"
	if ! composer install; then
		bad "composer install が失敗しました"
	fi
fi

echo "== 5. 互換パッチの適用 =="
if [ ! -f scripts/apply-php85-patches.sh ]; then
	bad "scripts/apply-php85-patches.sh がありません"
elif [ "$CHECK_ONLY" -eq 1 ]; then
	# 変更せず、適用済みかどうかだけ判定する
	for p in patches/*.patch; do
		[ -f "$p" ] || continue
		if patch -p1 -R -N -s --dry-run -i "$p" >/dev/null 2>&1; then
			ok "適用済み $p"
		elif patch -p1 -N -s --dry-run -i "$p" >/dev/null 2>&1; then
			warn "未適用 $p（--check では適用しません）"
		else
			bad "文脈が一致しません $p"
		fi
	done
elif sh scripts/apply-php85-patches.sh; then
	ok "パッチ適用済み"
else
	bad "パッチが適用できません（patches/README.md を確認）"
fi

echo "== 6. bower パッケージの取得数 =="
if [ -d app/webroot/components ]; then
	COUNT=$(ls app/webroot/components | wc -l | tr -d ' ')
	if [ "$COUNT" -ge 15 ]; then
		ok "app/webroot/components: $COUNT 件"
	else
		bad "app/webroot/components が $COUNT 件しかありません -> bower --allow-root update"
	fi
else
	bad "app/webroot/components がありません -> bower --allow-root update"
fi

echo
if [ "$ng" -eq 0 ]; then
	echo "前提チェック完了。次の手順:"
	echo "  1) Web サーバのドキュメントルートを $ROOT/app/webroot に向ける"
	echo "  2) http://<host>/install を開く（CUI なら app/Console/cake install.install）"
	exit 0
else
	echo "未解決の項目が $ng 件あります。上の NG を解消してから再実行してください。"
	exit 1
fi
