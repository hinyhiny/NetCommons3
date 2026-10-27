# NetCommons3 PHP 8.x 新規インストール手順

PHP 8 系で NetCommons3 を新規構築するための手順。`patches/` の互換パッチは
`composer install` の `post-install-cmd` で自動適用される（冪等）。

- **検証済み**: PHP 8.5.12 / MySQL 8.4 / macOS（ServBay）、2026-10
- **未検証**: Linux（Rocky / Ubuntu）本番系。手順は同じだが §7 の確認は必須
- **対象**: 新規インストール。既存サイトの PHP 8 移行は別途（`patches/README.md` 参照）

---

## 1. 必要環境

| 項目 | 要件 | 備考 |
| --- | --- | --- |
| PHP | 8.0 以上（検証は 8.5.12） | CLI と FPM で同じバージョンを使う |
| PHP 拡張 | `pdo_mysql` `mbstring` `intl` `gd` `zip` `curl` `openssl` `fileinfo` `exif` `dom` `xml` `SimpleXML` | `mcrypt` は不要（CakePHP 2.10 は openssl を使用） |
| MySQL | 8.0 / 8.4 | 5.7 でも可。`sql_mode` はインストーラが空に設定する |
| Composer | 2.x | v1 では installers の挙動が異なる |
| その他 | `git` `patch` `node` + `npm`（bower 用） | `patch` が無いと互換パッチが当たらない |

PHP の拡張確認:

```sh
php -v
php -m | grep -E '^(pdo_mysql|mbstring|intl|gd|zip|curl|openssl|fileinfo|exif|dom|xml|SimpleXML)$'
```

`intl` と `gd` が欠けていると、それぞれ日付・ロケール処理と画像のサムネイル生成で落ちる。

---

## 2. ソースの取得

パッチ同梱の fork から取得する（推奨）:

```sh
git clone https://github.com/hinyhiny/NetCommons3.git
cd NetCommons3
```

upstream（`NetCommons3/NetCommons3`）から取得する場合は、clone 後に
`patches/` `scripts/` と `app/Config/bootstrap.php` の変更をこのリポジトリからコピーする。
パッチは upstream のファイル内容に依存するため、**upstream の master を更新したら
`patches/README.md` の対象 ref を確認する**こと。

---

## 3. composer install（ここでパッチが当たる）

```sh
composer install
```

実行される順序:

1. `vendors/` と `app/Plugin/` に依存を導入
   （`config.platform.php = 7.4.33` により、CakePHP 2.10 の `php >=5.3,<8.0` 制約を満たして解決する）
2. `scripts/apply-php85-patches.sh` — `patches/*.patch` を適用
3. `app/Console/cake install.install install_bower` — bower パッケージを取得

期待するログ:

```
[applied] patches/01-cakephp-2.10.24-php85.patch
[applied] patches/02-cakedc-migrations-2.6.1-php85.patch
```

2 回目以降の `composer install` では `[skip] ... (適用済み)` になる。これが正常。

### やってはいけないオプション

| オプション | 何が起きるか |
| --- | --- |
| `--no-scripts` | **パッチが当たらない**。CakePHP 2.10 が PHP 8 で起動しない状態になる |
| `--ignore-platform-reqs` | `composer.lock` と実際の解決結果がずれる。使わない |
| `composer update` | 依存が動いてパッチの文脈が外れる。**lock を固定して使う** |

`composer install` が途中で失敗した場合は `patches/README.md` の「注意」を参照。

---

## 4. bower の確認（重要・無音で失敗する）

`InstallBowerTask` は `` `which bower` `` を実行するだけで、**失敗しても戻り値を見ていない**。
つまり bower が無くても `composer install` は成功扱いになり、`app/webroot/components` が
空のまま UI が壊れる。

```sh
which bower
ls app/webroot/components | wc -l    # 18 前後あれば OK
```

空だった場合:

```sh
npm install -g bower
cd /path/to/NetCommons3
bower --allow-root update
```

bower は EOL で registry が不安定。`ECONNRESET` などで落ちる場合は時間をおいて再実行する。
`bower.json` は MathJax を 2.x に固定している（Wysiwyg が 2.x の API で URL を組み立てるため）。

---

## 5. データベースの準備

```sql
CREATE DATABASE netcommons DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'netcommons'@'localhost' IDENTIFIED BY '<パスワード>';
GRANT ALL PRIVILEGES ON netcommons.* TO 'netcommons'@'localhost';
FLUSH PRIVILEGES;
```

テーブルはインストーラが migration で作るので、**手動でスキーマを流さない**。

`app/Config/database.php` はインストーラが `database.php.install` から生成する。
このテンプレートには `'settings' => ['@@SESSION.sql_mode' => "''"]` が入っており、
MySQL 8 のデフォルト `sql_mode`（`ONLY_FULL_GROUP_BY` など）による migration 失敗を避ける。
**手で `database.php` を書く場合はこの行を落とさないこと。**

---

## 6. インストーラの実行

### 6-A. Web インストーラ

Web サーバのドキュメントルートを `<repo>/app/webroot` に向け、`http://<host>/install` を開く。

| ステップ | URL | 内容 |
| --- | --- | --- |
| 1 | `/install` | 利用規約 |
| 2 | `/install/init_permission` | `app/tmp` `app/webroot/files` などの書き込みチェック |
| 3 | `/install/init_db` | DB 接続情報 → DB 作成 + migration |
| 4 | `/install/init_admin_user` | 管理者アカウント |
| 5 | `/install/init_site_setting` | サイト名・言語・URL |
| 6 | `/install/finish` | 完了 |

完了すると `app/Config/application.yml` に `installed: true` が書き込まれ、
以降 `/install` は 404 になる（`InstallController::beforeFilter` のガード）。

### 6-B. CUI インストーラ

```sh
cd /path/to/NetCommons3
app/Console/cake install.install
```

`[S]tart` を選び、base URL → 言語 → DB 情報 → 管理者 → サイト設定の順に入力する。
bower は §3 の `composer install` で取得済みなので、この経路では再実行されない。

> `cake` コマンド自体が起動しない場合は、パッチ 01 の `Shell::hasMethod()` 修正が
> 当たっていない。§3 のログを確認する。

---

## 7. インストール後の確認チェックリスト

PHP 8 系で壊れやすい箇所を狙った確認。**上から順に実施する。**

| # | 確認 | 期待結果 | NG のときの原因 |
| --- | --- | --- | --- |
| 1 | `app/Console/cake` が起動する | ヘルプが出る | パッチ 01 `Shell::hasMethod()` 未適用 |
| 2 | 管理者でログイン | 管理画面に入れる | パッチ 01 `Mysql` の `ATTR_STRINGIFY_FETCHES` 未適用 |
| 3 | ページを新規作成 | 保存できる | migration 未完了 / 権限 |
| 4 | **WYSIWYG で画像を挿入**（ファイル付き POST） | アップロードできる | `$_FILES['full_path']` 混入 → black-hole（400） |
| 5 | ファイルキャビネットにファイル添付 | 添付できる | 同上 |
| 6 | ユーザーを新規作成 | 作成できる | `space_id` の型比較ずれ（パッチ 01） |
| 7 | 各プラグインの一覧を開く | 500 にならない | 個別プラグインの deprecation |
| 8 | お知らせ等で MathJax を含む記事 | 数式が描画される | bower の MathJax が 3.x になっている |

4 と 5 が**最も落としやすい**。ここが通れば実運用の入口はほぼ OK。

ログの確認:

```sh
tail -f app/tmp/logs/error.log
```

PHP 8.1+ では deprecation が大量に出る。`E_DEPRECATED` は動作に影響しないが、
`Fatal error` / `Uncaught TypeError` は必ず潰す。

---

## 8. つまずきポイント

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| `composer install` で `cakephp/cakephp ... requires php <8.0` | `config.platform.php` が消えた | `composer.json` の `config.platform.php: 7.4.33` を復活させる |
| `cake` が `TypeError: ReflectionMethod::__construct(): Argument #2 ($name) must be of type string` | パッチ 01 未適用 | `sh scripts/apply-php85-patches.sh` |
| ファイル付き POST が 400 `The request has been black-holed` | `$_FILES` の `full_path` 混入 | `app/Config/bootstrap.php` の除去処理が入っているか確認 |
| ユーザー作成・スペース作成が失敗する | mysqlnd が int を返し `===` 比較が外れる | パッチ 01 `Mysql.php` の `ATTR_STRINGIFY_FETCHES` |
| 全プラグインの migration が起動時に失敗 | `each()` 削除（PHP 8.0） | パッチ 02 |
| `emotionloop/visualcaptcha` の取得に失敗 | 配布元リポジトリ消失 | `composer.lock` の参照先が `NetCommons3/emotionloop-visualcaptcha` になっているか確認 |
| UI の JS/CSS が崩れる | bower 未実行（無音失敗） | §4 |
| `Database connection ... "There is no active transaction"` | DDL の暗黙コミット | パッチ 01 `DboSource` の commit/rollback 吸収 |

---

## 9. パッチの内容

| ファイル | 対象 | 修正内容 |
| --- | --- | --- |
| `patches/01-cakephp-2.10.24-php85.patch` | `cakephp/cakephp` 2.10.24 | `Shell::hasMethod()` の null ガード / `Folder::read()` の `array_values()` / `DboSource` の commit・rollback 吸収 / `Mysql` の `ATTR_STRINGIFY_FETCHES` |
| `patches/02-cakedc-migrations-2.6.1-php85.patch` | `cakedc/migrations` 2.6.1 | 削除された `each()` を `reset()` / `key()` / `current()` に置換 |
| `app/Config/bootstrap.php`（アプリ側） | 本体 | `$_FILES` の `full_path` 除去、`CakePlugin::load('Install')` |

`patches/*.patch` は `vendors/` と `app/Plugin/`（いずれも `.gitignore` 対象）に当たるため、
パッチとして保持し `composer install` 時に適用している。詳細は `patches/README.md`。

手動操作:

```sh
# 適用（冪等）
sh scripts/apply-php85-patches.sh

# 状態確認（逆向きに当たるか = 適用済みか）
patch -p1 -R -N -s --dry-run -i patches/01-cakephp-2.10.24-php85.patch && echo applied

# 元に戻す
patch -p1 -R -i patches/01-cakephp-2.10.24-php85.patch
patch -p1 -R -i patches/02-cakedc-migrations-2.6.1-php85.patch
```

`cakephp/cakephp` や `cakedc/migrations` のバージョンを上げた場合は、
パッチを作り直す必要がある（`patches/README.md` の対象 ref を更新）。

---

## 10. 運用上の注意

- **`composer update` を実行しない。** `composer.lock` の ref にパッチが紐づいている。
  依存を更新するときは、パッチの再作成と §7 の再確認をセットで行う。
- `vendors/` と `app/Plugin/` は git 管理外。デプロイは
  「`git pull` → `composer install`」で、パッチは自動で当たる。
- 本番は `app/Config/core.php` の `debug` を `0` にする。
- **CakePHP 2.x は 2021 年に EOL**。セキュリティパッチは今後提供されない。
  PHP 8.5 で動作するのは延命であり、脆弱性が修正されるわけではない。
  公開サーバで使う場合は WAF / リバースプロキシ側の防御も併せて検討する。
- ライセンスは FreeBSD License（`license.txt`）。再配布する場合は著作権表示と
  条件文の同梱が必要。「NetCommons」は情報・システム研究機構の登録商標のため、
  名称を冠した配布物は事前に確認する。
