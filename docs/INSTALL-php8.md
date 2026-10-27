# NetCommons3 PHP 8.x インストール手順

PHP 8.0〜8.5 で NetCommons3 を新規構築する。互換パッチは `composer install` 時に自動適用される。
検証済み: PHP 8.5.12 / MySQL 8.4 / macOS（ServBay）。Linux は未検証だが手順は同じ。

## クイックスタート

```sh
git clone https://github.com/hinyhiny/NetCommons3.git
cd NetCommons3
sh scripts/setup-php8.sh
```

これで前提チェック → `composer install`（パッチ自動適用）→ 権限確認まで終わる。
最後に Web サーバのドキュメントルートを **`app/webroot`** に向けて `http://<host>/install` を開く。
CUI で入れるなら `app/Console/cake install.install`。

何が足りないかだけ知りたいとき（何も変更しない）:

```sh
sh scripts/setup-php8.sh --check
```

## 前提

| 項目 | 要件 |
| --- | --- |
| PHP | 8.0 以上（CLI と FPM を同じバージョンに） |
| PHP 拡張 | `pdo_mysql` `mbstring` `intl` `gd` `zip` `curl` `openssl` `fileinfo` `dom` `xml` `SimpleXML` `exif` |
| MySQL | 8.0 / 8.4（5.7 も可） |
| コマンド | `composer` 2.x / `git` / `patch` / `node`+`npm`（bower 用） |

不足があれば `setup-php8.sh` が NG として列挙する。`mcrypt` は不要（CakePHP 2.10 は openssl を使う）。

## setup スクリプトがやること

| # | 内容 |
| --- | --- |
| 1 | PHP のバージョンと必須拡張を確認 |
| 2 | `composer` `git` `patch` `bower` の有無を確認 |
| 3 | 書き込み権限を確認（`app/Config` `app/tmp` `app/Uploads` `app/webroot/{css,js,img,theme}`）。無いディレクトリは作成 |
| 4 | `vendors/` が無ければ `composer install` |
| 5 | 互換パッチを適用（冪等。2 回目以降は `[skip]`） |
| 6 | `app/webroot/components` の取得数を確認 |

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

| # | 確認 | 期待 | NG の原因 |
| --- | --- | --- | --- |
| 1 | `app/Console/cake` が起動 | ヘルプが出る | パッチ 01 未適用 |
| 2 | 管理者でログイン | 管理画面に入れる | パッチ 01（`ATTR_STRINGIFY_FETCHES`） |
| 3 | ページを新規作成 | 保存できる | migration 未完了 / 権限 |
| 4 | **WYSIWYG で画像挿入 / ファイル添付** | アップロードできる | `$_FILES['full_path']` 混入で black-hole |
| 5 | ユーザーを新規作成 | 作成できる | `space_id` の型比較ずれ |
| 6 | MathJax を含む記事 | 数式が描画される | bower の MathJax が 3.x |

```sh
tail -f app/tmp/logs/error.log
```

`E_DEPRECATED` は動作に影響しない。`Fatal error` / `Uncaught TypeError` を潰す。

## つまずきポイント

| 症状 | 原因 | 対処 |
| --- | --- | --- |
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
# 適用（冪等）/ 状態確認 / 元に戻す
sh scripts/apply-php85-patches.sh
patch -p1 -R -N -s --dry-run -i patches/01-cakephp-2.10.24-php85.patch && echo applied
patch -p1 -R -i patches/01-cakephp-2.10.24-php85.patch
```

## 付録: 運用上の注意

- **`composer update` を実行しない。** `composer.lock` の ref にパッチが紐づいている。依存を上げるときはパッチ再作成と確認をセットで。
- デプロイは「`git pull` → `composer install`」。パッチは自動で当たる。
- 本番は `app/Config/core.php` の `debug` を `0` に。
- **CakePHP 2.x は 2021 年に EOL**。セキュリティパッチは来ない。PHP 8.5 で動くのは延命であって安全になるわけではない。
- ライセンスは FreeBSD License（`license.txt`）。再配布時は著作権表示と条件文の同梱が必要。
  「NetCommons」は情報・システム研究機構の登録商標なので、名称を冠した配布物は事前確認。
