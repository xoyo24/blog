---
title: Manage database with flyway and skinnyORM
date: 2015-10-17 12:27:04
tags:
- Scala
- DB migration
- flyway
- O/R Mapper
- Skinny-ORM
categories: 
- Scala
---
　初めまして、しょよです。８月から日本でScalaの開発を始めました。また始まってばかりですが、業務を行いながら、いろんな試行錯誤を記録したいと思います。さて、今回は今作ってるシステムで、DB周りで学んだことについて書かせていただきます。

<!-- more -->

### Flaywayを使って、DB Schemaを管理する
　[Flyway][1]とは、DB　Migrationを簡単にできるJavaライブラリです。Jvmで動くので、Scalaにも使えます。
#### 1. 設定
- **project/plugins.sbt** : flywayのpluginを導入

```scala
  addSbtPlugin("org.flywaydb" % "flyway-sbt" % "3.2.1")

  resolvers += "Flyway" at "http://flywaydb.org/repo"
```

- **build.sbt** : flywayの設定

```scala
  libraryDependencies ++= Seq(
      "com.h2database" % "h2" % "1.3.174"   //DB Driver
  )
  // flywayDB設定
  seq(flywaySettings: _*)
　//DB Url
  flywayUrl := "jdbc:h2:file:target/foobar"  
  // DBユーザー、パスワード
  flywayUser := "SA"
  flywayPassword := ""
```

#### 2. SQLを作成
- src/main/resources/db/migration/の配下で、以下のようなSQLを作成。
  `(version)__(description).sql`

  - 例：V1__Create_person_table.sql

```sql
create table PERSON (
    ID int not null,
    NAME varchar(100) not null
);
```

#### 3. flywayMigrateを実行
- コマンドラインで`sbt flywayMigrate`を実行すれば、上記のSQLが実行される
** 複数のファイルがある場合version順で実行される **

#### 4. その他
-コマンドラインで`flywayClean`を実行すれば、DBがクリアされる

### Skinny-ORMを使って、DBアクセスする
  [Skinny-ORM][2]とは、[ScalikeJDBC][3]をベースにしたRuby on Railsの[ActiveRecord][5]のようでDBにアクセスできるScalaライブラリです。
#### 1. 設定
- **build.sbt**

```build.sbt
  libraryDependencies ++= Seq(
    //scalikejdbcだけ使う場合
    // "org.scalikejdbc"   %% "scalikejdbc"       % "2.2.7", 　　　　　
    //skinny-ormを使う場合
    "org.skinny-framework" %% "skinny-orm"      % "1.3.20",
    //skinny-ormを使う場合のテストHelper 　　　　　
    "org.skinny-framework" %% "skinny-test" 　　% "1.3.20", 　　　　
    // 単独でsrc/main/resources/application.confを使って設定する場合　　
    "org.scalikejdbc" %% "scalikejdbc-config"  % "2.2.7",       
    //Play Frameworkで使う場合、playの設定を読み取り、DB接続初期化などの処理     
    "org.scalikejdbc" %% "scalikejdbc-play-initializer" % "2.4.1"　　
    "com.h2database"       %  "h2"              % "1.4.+”,  　　 //DB Driver
    "ch.qos.logback"       %  "logback-classic" % "1.1.+”　　　　　//ログ出力用
  )
```
- **application.conf**

```application.conf
  # DB接続設定
  db {
    default {
      driver="com.mysql.jdbc.Driver"
      url="jdbc:mysql://localhost/playbbs"
      username="bbs_admin"
      password="bbs"
    }
  }

  # ScalikeJDBCオリジナル設定、DB接続プールやログの設定が出来る

  # db.default.poolInitialSize=10
  # db.default.poolMaxSize=10
  # db.default.poolValidationQuery=
  # scalikejdbc.global.loggingSQLAndTime.enabled=true
  # scalikejdbc.global.loggingSQLAndTime.singleLineMode=false
  # scalikejdbc.global.loggingSQLAndTime.logLevel=debug
  # scalikejdbc.global.loggingSQLAndTime.warningEnabled=true
  # scalikejdbc.global.loggingSQLAndTime.warningThresholdMillis=5
  # scalikejdbc.global.loggingSQLAndTime.warningLogLevel=warn

  # Modules
  play.modules.enabled += "scalikejdbc.PlayModule"
```

#### 2.DBにアクセスする
1. テーブルのmapperを作る
  - 下記いずれのトレイを継承して、Mapperを作る

Mapper         　　 | 説明
-------------------|----------------
SkinnyMapper    　　| 基本のMapper、参照だけできる、ID：longが必要
SkinnyCRUDMapper   | CRUD機能できるMapper、ID：longが必要
SkinnyCRUDMapperWithId  | CRUD機能できるMapper、ID型指定できる
SkinnyNoIdMapper, SkinnyNoIdCRUDMapper    | CRUD機能できるMapper、ID必要ない
SkinnyJoinTable    | テーブルを結合し、関連性を表すMapper

２. Mapperが提供されるAPIを使う
  - 例: [skinny-ORM][2] を参照

#### 3. ScalikeJDBCを使って、DBにアクセスする
- ScalikeJDBCを使うと、SQLを書いて、DBにアクセスできる。ドキュメントからいくつ簡単の例を紹介する。

```scala
  import scalikejdbc._

  val id = 123

  // 基本の検索
  val name: Option[String] = DB readOnly { implicit session =>
  sql"select name from emp where id = ${id}".map(rs => rs.string("name")).single.apply()
  }

  // Mapperを関数として渡す
  val nameOnly = (rs: WrappedResultSet) => rs.string("name")
  val name: Option[String] = DB readOnly { implicit session =>
  sql"select name from emp where id = ${id}".map(nameOnly).single.apply()
  }

  // 検索結果をクラスにマップする
  case class Emp(id: String, name: String)
  val emp: Option[Emp] = DB readOnly { implicit session =>
  sql"select id, name from emp where id = ${id}"
    .map(rs => Emp(rs.string("id"), rs.string("name"))).single.apply()
  }
```

- バージョン1.6.0以降, Query DSLを使って、より型安全でDBにアクセスできる

```scala
  // select
  val id = 123
  val (m, g) = (GroupMember.syntax("m"), Group.syntax("g"))
  val groupMember = withSQL {
    select.from(GroupMember as m).leftJoin(Group as g).on(m.groupId, g.id)
      .where.eq(m.id, id)
  }.map(GroupMember(m, g)).single.apply()

  // insert
  withSQL {
    insert.into(Member).values(1, "Alice", DateTime.now)
  }.update.apply()

  // update
  withSQL {
    update(Member).set(
      Member.column.name -> "Chris",
      Member.column.updatedAt -> DateTime.now
    ).where.eq(Member.column.id, 2)
  }.update.apply()

  // delete
  withSQL {
    delete.from(Member).where.eq(Member.column.id, 123)
  }.update.apply()
```

#### 4. skinny-ORM(ScalikeJDBC)における、Session管理
- DB.autoCommit/readOnly/localTx/withinTx { ...} ブロクを使うとき、implicit sessionを定義する人必要がある。
- 通常はimplicit session = AutoSessionで問題無いです。
- DB指定する場合、NamedAutoSession('named))を使う。
- 他に、DB.readOnlySession、DB.autoCommitSession、db.withinTxSession()があります。

#### 5. テスト
以下のトレイを使うことで、テストを簡単化できる。
- **DBSettings** トレイ
 `src/main/resources/application.conf`でDB設定すると、テストするとき、自動的にDB接続を初期化できる。
 例：

```application.conf
development {
    db {
      default {
        driver="org.h2.Driver"
        url="jdbc:h2:mem:example"
        user="sa"
        password="sa"
        poolInitialSize=2
        poolMaxSize=10
      }
    }
  }
```

- **AutoRollback** トレイ: テスト毎に自動ロールバックできる
　例：
 - Specs2の場合

```scala
 import scalikejdbc._
 import scalikejdbc.specs2.mutable.AutoRollback
 import org.joda.time.DateTime
 import org.specs2.mutable.Specification

 object MemberSpec extends Specification extends DBSettings {

   sequential

   "Member should create a new record" in new AutoRollback {
     val before = Member.count()
     Member.create(3, "Chris")
     Member.count() must_==(before + 1)
   }

   "Member should ... " in new AutoRollbackWithFixture {
     ...
   }

 }

 trait AutoRollbackWithFixture extends AutoRollback {
   // override def db = NamedDB('db2).toDB
   override def fixture(implicit session: DBSession) {
     sql"insert into members values (1, ${"Alice"}, ${DateTime.now})".update.apply()
     sql"insert into members values (2, ${"Bob"}, ${DateTime.now})".update.apply()
   }
 }
```

 - Scalatestの場合

```scala
import scalikejdbc._
import scalikejdbc.scalatest.AutoRollback
import org.joda.time.DateTime
import org.scalatest.fixture.FlatSpec

class AutoRollbackSpec extends FlatSpec with DBSettings with AutoRollback {

  // override def db = NamedDB('anotherdb).toDB

  override def fixture(implicit session: DBSession) {
    sql"insert into members values (1, ${"Alice"}, ${DateTime.now})".update.apply()
    sql"insert into members values (2, ${"Bob"}, ${DateTime.now})".update.apply()
  }

  behavior of "Members"

  it should "create a new record" in { implicit session =>
    val before = Member.count()
    Member.create(3, "Chris")
    Member.count() should equal(before + 1)
  }

}
```

### まとめ：
 Scalaをはじまってこの二ヶ月、学びほどその素晴らしさに驚いた。関数型言語として、複雑の処理がシンプルかつ安全にかけます。JVMで動いてので、数多いJavaライブラリがそのまま使えるのも一大利点と思います。
 これからは、引き続きScalaの学習を強化したいと思います。

[1]: http://flywaydb.org/getstarted/firststeps/sbt.html
[2]: http://skinny-framework.org/documentation/orm.html
[3]: http://scalikejdbc.org/
[4]: https://github.com/scalikejdbc/scalikejdbc-cookbook/tree/master/ja
[5]: http://guides.rubyonrails.org/active_record_basics.html
