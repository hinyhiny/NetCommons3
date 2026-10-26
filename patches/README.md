# PHP 8.5 互換パッチ

NetCommons3 が依存する **CakePHP 2.10** と **cakedc/migrations** は composer 管理
（`vendors/` と `app/Plugin/` は `.gitignore` 対象）のため、PHP 8 系で動かすための
修正をこのリポジトリへ直接コミットできません。

そこで差分をパッチとしてここに置き、`composer install` / `composer update` の
直後に `scripts/apply-php85-patches.sh` で自動適用しています
（`composer.json` の `scripts.post-install-cmd` / `post-update-cmd`）。

手動で適用する場合:

```sh
sh scripts/apply-php85-patches.sh
```

適用済みなら `[skip]`、未適用なら `[applied]`、依存バージョンが変わって
文脈が合わなければ `[FAILED]` を出して終了コード 1 を返します（冪等）。

## 01-cakephp-2.10.24-php85.patch

対象: `cakephp/cakephp` 2.10.24（ref `cf14e6546ec44e3369e3531add11fdb946656280`）

| ファイル | 修正内容 |
| --- | --- |
| `lib/Cake/Console/Shell.php` | `hasMethod()` に null / 空文字ガードを追加。PHP 8 では `ReflectionMethod($obj, null)` が TypeError になる（`cake` コマンドが起動しない） |
| `lib/Cake/Utility/Folder.php` | `call_user_func_array('array_merge', $x)` に `array_values()` を挟む。PHP 8 では文字列キーが名前付き引数として解釈され `Unknown named parameter` で失敗する |
| `lib/Cake/Model/Datasource/DboSource.php` | `commit()` / `rollback()` で “There is no active transaction” を吸収。MySQL の DDL は暗黙コミットするため、PHP 8 では例外になる |
| `lib/Cake/Model/Datasource/Database/Mysql.php` | `PDO::ATTR_STRINGIFY_FETCHES => true` と `ATTR_EMULATE_PREPARES => true` を追加。PHP 8 の mysqlnd は int を返すため、NetCommons の `===` 比較（例: `space_id` と `Space::PRIVATE_SPACE_ID = '3'`）が外れてユーザー作成などが失敗する |

## 02-cakedc-migrations-2.6.1-php85.patch

対象: `cakedc/migrations` 2.6.1（NetCommons3 ミラー、ref `dacd4f47806eace276434f54c6cdf2b8c524fd1e`）

| ファイル | 修正内容 |
| --- | --- |
| `Lib/MigrationVersion.php` | PHP 8 で削除された `each()` を `reset()` / `key()` / `current()` に置換（2 箇所）。これが無いと全プラグインの migration が起動時に失敗する |

## 注意

- パッチは**依存パッケージのバージョンに強く依存**します。`composer.lock` の
  `cakephp/cakephp` と `cakedc/migrations` を上げた場合はパッチを作り直してください。
- アプリ側で完結する修正（`$_FILES['full_path']` の除去など）は
  `app/Config/bootstrap.php` に入れてあり、パッチではありません。
