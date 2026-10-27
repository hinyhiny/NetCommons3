# NetCommons3 PHP 8.5.12 以降インストール手順

> PHP の緊急セキュリティ対応が適用された PHP 8.5 で動作する NetCommons3 の、修正パッチ同梱インストーラーです（非公式）。
> **PHP 8.5.12 以上が必須**です。8.5.12 以前はサポート対象外です。
> **アップデート（既存サイトの移行）を目的としていない**ため、システム検証などで新規に構築する場合に使えます。
> ご利用に際しては、末尾の [付録: 運用上の注意](#付録-運用上の注意) を先に確認してください。
> 問題があれば GitHub の [Issues](https://github.com/hinyhiny/NetCommons3/issues) でご連絡ください。
> ご利用には `sudo` が使えるサーバー環境が必要です。

互換パッチは `composer install` 時に自動適用される。
検証: PHP 8.5.12 / MySQL 8.4 / macOS（ServBay）と Debian 12 + nginx。**要件は PHP 8.5.12 以上**。
NetCommons3 本体の概要・ライセンスは [README.md](../README.md) を参照。

## クイックスタート

```sh
git clone https://github.com/hinyhiny/NetCommons3.git
cd NetCommons3
sh scripts/setup-php8.sh
```

これで前提チェック → `composer install`（パッチ自動適用）→ 権限確認まで終わる。
最後に Web サーバのドキュメントルートを **`app/webroot`** に向けて `http://<host>/install` を開く。
CUI で入れるなら `app/Console/cake install.install`。

何が足りないかだけ知りたいときは `--check`（何も変更しない）:

```sh
sh scripts/setup-php8.sh --check
```

### オプション

| オプション | 動作 |
| --- | --- |
| （なし） | チェック → `composer install` → パッチ適用 → components 確認 |
| `--check` | 変更せず判定のみ。パッチは逆適用のドライランで「適用済み」を判定する |
| `--skip-composer` | 依存導入を飛ばして、パッチ適用と確認だけ行う |
| `-h` / `--help` | 使い方を表示 |

### 出力の見方

3 種類のラベルで出る。`[要修正]` が 1 件でもあれば終了コード 1。

| ラベル | 意味 |
| --- | --- |
| `[OK]` | 問題なし |
| `[注意]` | 続行できるが確認したい（bower 未導入、スキップなど） |
| `[要修正]` | 解消するまでインストール不可 |

```
== 1. PHP の確認 ==
  [OK]     PHP 8.5.12
  [OK]     必要な拡張が揃っています
== 5. 互換パッチの適用 ==
  [OK]     適用済み patches/01-cakephp-2.10.24-php85.patch
== 6. bower パッケージの取得数 ==
  [OK]     app/webroot/components: 18 件
```

## 前提

| 項目 | 要件 |
| --- | --- |
| PHP | **8.5.12 以上**（CLI と FPM を同じバージョンに。8.5.12 以前は非対応） |
| PHP 拡張 | `pdo_mysql` `mbstring` `intl` `gd` `zip` `curl` `openssl` `fileinfo` `dom` `xml` `SimpleXML`（`exif` は任意） |
| MySQL | 8.0 / 8.4（5.7 も可） |
| コマンド | `composer` 2.x / `git` / `patch` / `node`+`npm`（bower 用） |
| 権限 | `sudo` が使えること（`composer install` と、`app/Config` などへの書き込み権限の設定に使用） |
| PHP 関数 | `exec()` が使えること。インストーラが `cake` を `exec()` で呼ぶ（aaPanel は FPM 側だけ既定で無効） |

不足があれば `setup-php8.sh` が「要修正」として列挙する。`mcrypt` は不要（CakePHP 2.10 は openssl を使う）。

## setup スクリプトがやること

| # | 内容 |
| --- | --- |
| 1 | PHP のバージョンと必須拡張を確認 |
| 2 | `composer` `git` `patch` `bower` の有無を確認 |
| 3 | 書き込み権限を確認（`app/Config` `app/tmp` `app/Uploads` `app/webroot/{css,js,img,theme}`）。無いディレクトリは作成 |
| 4 | `vendors/` が無ければ `composer install` |
| 5 | 互換パッチを適用（冪等。`composer install` 直後は適用済みのため `[skip]` になる） |
| 6 | `app/webroot/components` の取得数を確認 |

## Web サーバの設定

ドキュメントルートは **`<repo>/app/webroot`** にする。`app/` 配下には DB パスワードを含む
`app/Config/database.php` があるため、リポジトリ直下をそのまま公開してはいけない。

CakePHP はすべてのリクエストを `index.php` に通すので、rewrite も必要。

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}
```

### aaPanel の場合

aaPanel の「実行ディレクトリ」はサイトディレクトリ直下の 1 階層しか選べないため、
2 階層下の `app/webroot` を画面から指定できない。**設定ファイルを直接編集する。**

1. `/www/server/panel/vhost/nginx/<domain>.conf` の `root` を書き換える

   ```nginx
   root /www/wwwroot/<domain>/app/webroot;
   ```

2. `/www/server/panel/vhost/rewrite/<domain>.conf` に上の `location /` を書く

3. 所有者を Web サーバユーザに合わせる

   ```sh
   chown -R www:www /www/wwwroot/<domain>
   ```

4. 反映する

   ```sh
   nginx -t && systemctl reload nginx
   ```

5. FPM 側の `exec` を許可する（インストーラが `cake` を `exec()` で呼ぶため）

   ```sh
   # 例: PHP 8.5。disable_functions から exec だけを外す
   cp -a /www/server/php/85/etc/php.ini /www/server/php/85/etc/php.ini.bak
   sed -i 's/passthru,exec,system/passthru,system/' /www/server/php/85/etc/php.ini
   /etc/init.d/php-fpm-85 reload
   ```

   画面から設定する場合は「App Store → PHP 8.5 → 設定 → 無効な関数」で `exec` を削除する。

注意点:

- 画面から「サイトディレクトリ」を変更すると conf が再生成され、`root` が戻る。その場合は 1 をやり直す。
- `.user.ini`（`open_basedir`）はサイト直下のままでよい。`app/webroot` は配下なので許可される。
- aaPanel は `.user.ini` に immutable 属性を付けるため `chown -R` が 1 件だけ失敗するが、無視してよい。
- aaPanel は `php-cli.ini`（CLI）と `php.ini`（FPM）を分けており、CLI 側は `exec` が許可済み。そのため `setup-php8.sh` は通るのに Web インストーラだけ 500 になる、という分かりにくい症状になる。
- `exec` はインストール完了後に戻してもよいが、戻す前に管理画面の一通りを確認しておく。

## データベース

インストーラが `CREATE DATABASE` から実行するので、**CREATE 権限のあるユーザ**を渡せば事前準備は不要。
事前に作る場合:

```sql
CREATE DATABASE netcommons DEFAULT CHARACTER SET utf8mb4;
CREATE USER 'netcommons'@'localhost' IDENTIFIED BY '<パスワード>';
GRANT ALL PRIVILEGES ON netcommons.* TO 'netcommons'@'localhost';
```

`app/Config/database.php` はインストーラが `database.php.install` から生成する。
手で書く場合は `'settings' => ['@@SESSION.sql_mode' => "''"]` の行を落とさない
（MySQL 8 の `ONLY_FULL_GROUP_BY` で migration が落ちる）。テーブルは migration が作るので手動で流さない。

## インストーラ

Web の場合、ドキュメントルートを `app/webroot` に向けて順に開く。

| ステップ | URL | 内容 |
| --- | --- | --- |
| 1 | `/install` | 利用規約 |
| 2 | `/install/init_permission` | 書き込み権限チェック |
| 3 | `/install/init_db` | DB 接続情報 → DB 作成 + migration |
| 4 | `/install/init_admin_user` | 管理者アカウント |
| 5 | `/install/init_site_setting` | サイト名・言語・URL |
| 6 | `/install/finish` | 完了 |

完了すると `app/Config/application.yml` に `installed: true` が入り、以降 `/install` は 404 になる。

## インストール後の確認

上から順に。**#4 が最重要**（ログインもページ作成も通った後に発覚する）。

| # | 確認 | 期待 | 失敗時の原因 |
| --- | --- | --- | --- |
| 1 | `app/Console/cake` が起動 | ヘルプが出る | パッチ 01 未適用 |
| 2 | 管理者でログイン | 管理画面に入れる | パッチ 01（`ATTR_STRINGIFY_FETCHES`） |
| 3 | ページを新規作成 | 保存できる | migration 未完了 / 権限 |
| 4 | **WYSIWYG で画像挿入 / ファイル添付** | アップロードできる | `$_FILES['full_path']` 混入で black-hole |
| 5 | ユーザーを新規作成 | 作成できる | `space_id` の型比較ずれ |
| 6 | MathJax を含む記事 | 数式が描画される | bower の MathJax が 3.x |
| 7 | お問い合わせフォームから送信 | メールが届く | サイト設定のメールサーバ（SMTP / PHP `mail()`）と送信元アドレス。`app/tmp/logs/error.log` と MTA 側のログを見る |

```sh
tail -f app/tmp/logs/error.log
```

`E_DEPRECATED` は動作に影響しない。`Fatal error` / `Uncaught TypeError` を潰す。

## つまずきポイント

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `[要修正] PHP 8.5.11 は非対応` と出る | 8.5.12 未満 | PHP を 8.5.12 以上に更新する（CVE 対応版） |
| `/install` は出るが「同意」の後が 404（`InitPermissionController` が見つからない） | `CakePlugin::load(..., 'routes' => true)` は読込予約のみ。未インストール分岐で `CakePlugin::routes()` が呼ばれていない | `app/Config/routes.php` の未インストール分岐を `CakePlugin::routes('Install');` にする |
| `/install/init_permission` が 500（`Call to undefined function exec()`） | aaPanel が FPM 側の `exec` を無効化している | `php.ini` の `disable_functions` から `exec` を外して php-fpm を再読込（[aaPanel の場合](#aapanel-の場合) の 5） |
| 全ページが 500 になる | `/install/finish` を URL 直打ちで開いた。`finish()` は状態を見ずに `installed: true` を書き込む | `app/Config/application.yml` の `installed:` を `false` にして `/install` を開き直す |
| 「imagick が見つかりません」と出る | ImageMagick 未導入（`gd` で代替可） | 警告のみで続行できる。必要なら imagick を追加 |
| aaPanel の実行ディレクトリに `app/webroot` が無い | 1 階層しか選べない仕様 | nginx conf の `root` を直接書き換える（[Web サーバの設定](#web-サーバの設定)） |
| `composer install` が `requires php <8.0` で停止 | `config.platform.php` が消えた | `composer.json` の `7.4.33` を戻す |
| `composer install` は成功したのに UI が崩れる | bower 未導入（**失敗が無音**） | `npm install -g bower && bower --allow-root update` |
| `cake` が `ReflectionMethod ... must be of type string` | パッチ 01 未適用 | `sh scripts/apply-php85-patches.sh` |
| ファイル付き POST が 400 `black-holed` | `full_path` 混入 | `app/Config/bootstrap.php` の除去処理を確認 |
| `--no-scripts` で入れた | パッチが当たっていない | スクリプト有効で入れ直す |
| migration が `each()` で落ちる | パッチ 02 未適用 | 同上 |
| `emotionloop/visualcaptcha` が取得できない | 配布元リポジトリ消失 | `composer.lock` の参照先が `NetCommons3/emotionloop-visualcaptcha` か確認 |
| `There is no active transaction` | DDL の暗黙コミット | パッチ 01（`DboSource`） |

## 付録: パッチの内容

| ファイル | 対象 | 修正 |
| --- | --- | --- |
| `patches/01-cakephp-2.10.24-php85.patch` | `cakephp/cakephp` 2.10.24 | `Shell::hasMethod()` の null ガード / `Folder::read()` の `array_values()` / `DboSource` の commit・rollback 吸収 / `Mysql` の `ATTR_STRINGIFY_FETCHES` |
| `patches/02-cakedc-migrations-2.6.1-php85.patch` | `cakedc/migrations` 2.6.1 | 削除された `each()` を `reset()` / `key()` / `current()` に置換 |
| `app/Config/bootstrap.php`（アプリ側） | 本体 | `$_FILES` の `full_path` 除去、`CakePlugin::load('Install')` |

`vendors/` と `app/Plugin/` は `.gitignore` 対象なので、修正はパッチとして保持し `composer install` 時に当てている。

```sh
# 適用（冪等）
sh scripts/apply-php85-patches.sh

# 状態確認（全パッチまとめて・変更なし）
sh scripts/setup-php8.sh --check

# 元に戻す（パッチ単位。逆向きに当てる）
patch -p1 -R -i patches/01-cakephp-2.10.24-php85.patch
patch -p1 -R -i patches/02-cakedc-migrations-2.6.1-php85.patch
```

元に戻すのは依存バージョンが変わっていない間だけ有効。バージョンを上げた後は逆適用できないので、
その場合は該当パッケージを消して入れ直す（例: `rm -rf vendors/cakephp && composer install`）。

## 付録: 運用上の注意

- **`composer update` を実行しない。** `composer.lock` の ref にパッチが紐づいている。依存を上げるときはパッチ再作成と確認をセットで。
- デプロイは「`git pull` → `composer install`」。パッチは自動で当たる。
- 本番は `app/Config/core.php` の `debug` を `0` に。
- **CakePHP 2.x は 2021 年に EOL**。セキュリティパッチは来ない。PHP 8.5.12 以上で動かすのは延命であって、アプリ側が安全になるわけではない。
- ライセンスは FreeBSD License（`license.txt`）。再配布時は著作権表示と条件文の同梱が必要。
  「NetCommons」は情報・システム研究機構の登録商標なので、名称を冠した配布物は事前確認。
