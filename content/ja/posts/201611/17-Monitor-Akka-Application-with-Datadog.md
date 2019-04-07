---
title: Monitor Akka Application with Datadog
date: 2016-11-17 11:19:15
tags:
- Scala
- Akka
- Datadog
- Monitoring
categories: 
- Akka
---

最近の仕事で、本格的Akkaを取り込んでいってエラーした処理だけリトライ出来るバッチ機構を実現しました。そのバッチ機構の実行効果を確認するので、KamonとDatadogを使ってAkkaプログラムの監視をやってみました。
ここでそのやり方と問題を簡単にまとめたいと思います。

## [Kamon](http://kamon.io/) とは

<!-- more -->

JVM上で走るアプリケーションを監視するためのオープンソースツールです。

### Kamonで出来る事

アプリケーションを監視するため、Kamonはいろんなをツールが用意されています。今回はAkkaを監視するため使うものを紹介します。

#### メトリックツールとトレーシング

- **kamon-core**

  基本のメトリックツールとトレーシングAPIとその基盤。他のモジュールが全部kamon-core依存しています。内部はAkkaを使ってSubscriberとメッセージ通信で実装しているらしいです。

- **kamon-scala**

  Scala、ScalazなどのFuturesに対して、バイトコードレベルのトレーシングが出来る。 **kamon-akka** が依存しています。

- **kamon-akka**

  Akkaのactors、routersと dispatchersに対してもメトリック集計、actorのmessageに対して、バイトコードレベルのトレーシングが出来る。

- **kamon-system-metrics**

  システム上とJVMのメトリックが出来ます。

その他にも **kamon-akka-remote** 、 **kamon-jdbc** 、 **kamon-elasticsearch** 、 **kamon-play** 、 **kamon-spray** などがありますが、今回のAkka監視に関係ないので、割愛します。

#### 結果の出力

Kamonが **kamon-log-reporter** を使って監視結果をそのままログに出すことが出来ますが、SPM、Datadog、New Relicなどの監視用バックエンドもサポートしています。今回はdatadogを使用するので、 **kamon-datadog** を使います。

## [DataDog](https://www.datadoghq.com/) とは

- システムモニタリング（監視）クラウドサービスである
- Kamon導入に伴い、Kamonの結果を可視化できるサービスとしてよく使われている

### 導入

[こちら](http://tech-blog.tsukaby.com/archives/1016) を参考に、
サインインして、サーバの種類選んで、表示されたコマンド叩けば導入出来ます。

※今回はMacOS上で行いましたが、AWSやDockerにもちゃんと対応しています。

### 実装

1. **build.sbt** にライブラリ依存を追加します。

```scala
  "io.kamon" %% "kamon-system-metrics" % kamonVersion,
  "io.kamon" %% "kamon-core" % kamonVersion,
  "io.kamon" %% "kamon-akka" % kamonVersion,
  "io.kamon" %% "kamon-datadog" % kamonVersion,
  "io.kamon" %% "kamon-autoweave" % kamonVersion
```

2. **application.conf** に出力したい項目を定義する。

```
# Kamonで監視するメトリックを定義
kamon {
  metric {
    filters {
      akka-actor {
        includes = [ "StressTestBatchActorSystem/user/**" ]
      }
      akka-dispatcher {
        includes = [ "StressTestBatchActorSystem/**" ]
      }
      akka-router {
        includes = [ "StressTestBatchActorSystem/**" ]
      }
    }
  }
}
# kamonの監視データがDataDog上の表示名
kamon.datadog.application-name = "application"
# デフォルトで全部Datadogへ出力するので、必須ではない
kamon.datadog {
  subscriptions {
    akka-actor = [ "**" ]
    akka-dispatcher = [ "**" ]
    akka-router = [ "**" ]
    system-metric = [ "**" ]
  }
}
```

3. AkkaプログラムにKamonを起動する。

```scala
  Kamon.start()
```

## 監視できない

上記の設定でAkkaプログラムを実行してみたら。いろんなエラーがで出来ました。

#### 問題1: sbtから実行する際に、aspectjが見つからない

```
2016-10-04 18:55:04,519 - [error] kamon.ModuleLoaderExtension -

  ___                           _      ___   _    _                                 ___  ___ _            _
 / _ \                         | |    |_  | | |  | |                                |  \/  |(_)          (_)
/ /_\ \ ___  _ __    ___   ___ | |_     | | | |  | |  ___   __ _ __   __ ___  _ __  | .  . | _  ___  ___  _  _ __    __ _
|  _  |/ __|| '_ \  / _ \ / __|| __|    | | | |/\| | / _ \ / _` |\ \ / // _ \| '__| | |\/| || |/ __|/ __|| || '_ \  / _` |
| | | |\__ \| |_) ||  __/| (__ | |_ /\__/ / \  /\  /|  __/| (_| | \ V /|  __/| |    | |  | || |\__ \\__ \| || | | || (_| |
\_| |_/|___/| .__/  \___| \___| \__|\____/   \/  \/  \___| \__,_|  \_/  \___||_|    \_|  |_/|_||___/|___/|_||_| |_| \__, |
            | |                                                                                                      __/ |
            |_|                                                                                                     |___/

 It seems like your application was not started with the -javaagent:/path-to-aspectj-weaver.jar option but Kamon detected
 the following modules which require AspectJ to work properly:

      kamon-akka, kamon-scala
```

- 原因

Kamon-akkaの監視はAspectJを使ってバイトコードレベルの監視を実現しています。そのため起動する際にaspectj-weaverを指定しないといけないです。

- 解決

公式によると３つの方法がありますが、sbtから起動する場合は **sbt-aspectj** を使います。

1. **plugin.sbt** でSBTプラグインを導入

```scala
addSbtPlugin("com.typesafe.sbt" % "sbt-aspectj" % "0.10.6")
```

2. **build.sbt** でプラグインを設定する。

```scala
lazy val sbtAspectjSettings = aspectjSettings ++ Seq(
  fork in run := true,
  javaOptions in run <++= AspectjKeys.weaverOptions in Aspectj,
  AspectjKeys.aspectjVersion in Aspectj := "1.8.9"
)
```

これで、sbtからプログラムを実行する際には正常に動くようになりました。

### 問題2: assemblyする際に、apo.xmlのコンフリクト

今のプロジェクトはassemblyしたプログラムをサーバーに上げていますが、コマンドを実行する際に、こんなエラーが出ました。

```
[error] 1 error was encountered during merge
java.lang.RuntimeException: deduplicate: different file contents found in the following:
/Users/y_xiao/.ivy2/cache/io.kamon/kamon-core_2.11/jars/kamon-core_2.11-0.6.2.jar:META-INF/aop.xml
/Users/y_xiao/.ivy2/cache/io.kamon/kamon-akka_2.11/jars/kamon-akka_2.11-0.6.2.jar:META-INF/aop.xml
/Users/y_xiao/.ivy2/cache/io.kamon/kamon-scala_2.11/jars/kamon-scala_2.11-0.6.2.jar:META-INF/aop.xml
```

- 原因

aspectjを使う以上、 **aop.xml** で設定しないといけないですが、kamonではライブラリ別々の設定となっています。

- 解決

色々調べた結果、全部のaop設定ファイルを結合する方法を見つかりました。

```scala
// Create a new MergeStrategy for aop.xml files
lazy val aopMerge = new sbtassembly.MergeStrategy {
  val name = "aopMerge"
  import scala.xml._
  import scala.xml.dtd._

  def apply(tempDir: File, path: String, files: Seq[File]): Either[String, Seq[(File, String)]] = {
    val dt = DocType("aspectj", PublicID("-//AspectJ//DTD//EN", "http://www.eclipse.org/aspectj/dtd/aspectj.dtd"), Nil)           // xmlファイルのヘッダ−
    val file = MergeStrategy.createMergeTarget(tempDir, path)                        // 保存するファイルを取得
    val xmls: Seq[Elem] = files.map(XML.loadFile)                                                // マージ対象ファイルをXML Elem対象へ変換
    val aspectsChildren: Seq[Node] = xmls.flatMap(_ \\ "aspectj" \ "aspects" \ "_")           // aspectj/aspects配下のすべての項目を取得
    val weaverChildren: Seq[Node] = xmls.flatMap(_ \\ "aspectj" \ "weaver" \ "_")           // aspectj/weaver配下のすべての項目を取得
    val options: String = xmls.map(x => (x \\ "aspectj" \ "weaver" \ "@options").text).mkString(" ").trim           // aspectj/weaverにoptionがある場合、optionを全部取得
    val weaverAttr = if (options.isEmpty) Null else new UnprefixedAttribute("options", options, Null)           // optionをUnprefixedAttributeへ変換
    val aspects = new Elem(null, "aspects", Null, TopScope, false, aspectsChildren: _*)           // aspectsを使って、新しいaspectj/aspectsを作成
    val weaver = new Elem(null, "weaver", weaverAttr, TopScope, false, weaverChildren: _*)           // weaverを使って、新しいaspectj/weaverを作成
    val aspectj = new Elem(null, "aspectj", Null, TopScope, false, aspects, weaver)           // 新しいaspects、weaverを使って、新しいaspectjを作成
    XML.save(file.toString, aspectj, "UTF-8", xmlDecl = false, dt)           // 新しいaspectsをファイルへ保存
    IO.append(file, IO.Newline.getBytes(IO.defaultCharset))
    Right(Seq(file -> path))
  }
}

assemblyMergeStrategy in assembly := {
      case "application.conf" =>
        MergeStrategy.first
      case PathList("META-INF", "aop.xml") =>
        aopMerge
      case x =>
        val oldStrategy = (assemblyMergeStrategy in assembly).value
        oldStrategy(x)
    },

    ……
```

これて、assemblyも無事に終わって、サーバー上のAkkaプログラムを監視できるようになりました。

※ ちなみに、普通にjarから実行する際に **-javaagent** をつける必要ですが、**kamon-autoweave** を使えば、JVM起動後自動的にAspectJ loadtime weaving agentをつける、-javaagentの指定が必要無くなります。


## まとめ

後は、Datadog上で簡単に設定すれば、Akkaプログラムの実行効果を見ながら、パフォーマンスチューニングができるようになりました。
