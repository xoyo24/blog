---
title: Reading Reactive Messaging Patterns with the Actor Model 01
date: 2016-03-06 14:28:33
tags:
- Reactive
- Scala
- Akka
categories: 
- Akka
---

お久しぶりです。しょよです。
前回のScala祭りから、Reactiveについての興味はどんどん高まって、つい最近こちらの本を買って、Reactiveを勉強しようと思いました。

今回は、この本を2章目にある、Akkaについての紹介を、簡単にまとめよと思いました。

<!-- more -->

## Programming with Akka
- 従来のマルチスレッドプログラミングは複雑過ぎて難しい
- AkkaはActorモデルを使って、従来のマルチスレッドプログラミングの弱点を克服した
- Akkaを使う場合、コンカレンシーの考えを捨てるわけではない
- Akkaはデッドロック、ライブロック、非効率のコード、スレッドを第一で考えるプログラミングモデルを克服し、コンカレントソフトウェア設計をシンプルにできるようにんした

### Actor System
- すべてのAkkaアプリケーションはActorSystemを作らないといけない
- ActorSystemは同じ設定を共有するActorの階層を集めている
 - 例：以下のコードはローカルJVMで、ReactiveEnterpriseという名前のデフォルト設定のActorSystemを作成

 ``` scala
 import akka.actor._
 ...
 val system = ActorSystem("ReactiveEnterprise")
 ```
- Akkaは環境によって違う値を設定ファイルで管理する。
 - メールボックス種類、リモートActorアクセス方法、dispatcherの声明など、ActorSystemやActorの設定

#### ActorSystemの設定

 ```
 Grokking Configuration
  # application.conf for ActorSystem: RiskRover
  akka {
    # default logs to System.out
    loggers = ["akka.event.Logging$DefaultLogger"]

    # Akka configured loggers use this loglevel.
    # Use: OFF, ERROR, WARNING, INFO, DEBUG
    loglevel = "DEBUG"

    # Akka ActorSystem startup uses this loglevel
    # until configs load; output to System.out.
    # Use: OFF, ERROR, WARNING, INFO, DEBUG
    stdout-loglevel = "DEBUG"

    actor {
      # if remoting:   akka.remote.RemoteActorRefProvider
      # if clustering: akka.cluster.ClusterActorRefProvider
      provider = "akka.actor.LocalActorRefProvider"
      default-dispatcher {
        # Default Dispatcher throughput;
        # set to 1 for as fair as possible,
        # but also poor throughput
        throughput = 1
      }
    }
  }
 ```
- 一つのAkkaアプリケーションで複数のActorSystemが作成可能ですが、１アプリ１ActorSystemの方式が推奨されます。
 - Playを使う場合、Play自身がActorSystem持つため、別のActorSystemを作成するを推奨
- ActorSystemと他のActorSystem協力する時は、Akka Clusterを使う
- Akka Clusterを使うと、違うJVMを一つのActorSystemとして使える

#### ActorSystemの構造
- ActorSystemが作らてると、root guardian、user guardian、とsystem guardian、３つのActorが自動に作られる。これらがすべてのActorのスーパーバイザ構造の基礎。
- アプリケーションで作成されたActorが全部user guardianの下になる
- Actorを作るActor場合、親Actorは子Actorのスーパーバイザになる。子Actorが異常発生する場合、どう対処するのを決める（resume, restart, stop, or escalate）。

#### ActorSystemを使う
- ```system.actorOf()```を使って、user guardianの直下でActorを作る

``` scala
...
// create actor and get its ActorRef
val processManagers: ActorRef =
      system.actorOf(Props[ProcessManagers], "processManagers")
// send message to actor using ActorRef
processManagersRef ! BrokerForLoan(banks)
```
 - ```actorOf()``` で作られるのはActorのインスタンスではなく、ActorRefという、Actorの参照。これによって、実際のActorとActorを使う側の間に、一つの間接抽象が作られた。
 - ```system.actorOf()```だけを使うと、すべてのActorがuser guardianの直下になります。管理が難しくなり、性能にも影響が出る、設計的にuser guardianが直接アプリケーション異常とやりとりするのも良くない。だから、Actorの階層を作るべき
 - 例えば、user guardianの下に、processManagersとdomainModelの２つのActorがあって、processManagersはプロセスマネージャActorのスーパーバイザ、domainModelはドメインモデルActorのスーパーバイザ　

- ActorRefがない場合、```actorSelection()```を使って、ActorSelectionを取得

```scala
val system = ActorSystem("ReactiveEnterprise")
...
val selection = system.actorSelection("/user/processManagers")
selection ! BrokerForLoans(banks)
```
 - ActorSelectionはActorRefと同じように、Actorにメッセージを送れるが、ActorRefよりは遅い、リソースをより多く使う。
 - ActorSelectionはActorRefと違って、ワイルドカードを使って、複数のActorにメッセージを送れる。

 ```scala
 val system = ActorSystem("ReactiveEnterprise")
 ...
 val selection = system.actorSelection("/user/*")
 selection ! FlushAll()
 ```
- ActorSystemには他の```awaitTermination```、```deadLetters```、```eventStream```、```isTerminated```、```log```、```name```、```scheduler```、```shutdown```、```stop```などのメソッドがあります。詳しくはAkkaのドキュメントを参照。
http://doc.akka.io/docs/akka/2.4.2/general/actor-systems.html

### Actorの実装
- すべてのActorは```akka.actor.Actor```トレイを継承し、```receive```を定義しないと行けない

```scala
import akka.actor._
class ShoppingCart extends Actor {
  def receive = {
    case _ =>
  }
}
```
- Actorのライフサイクル
 - preStart()：Actorが作成後、開始前に呼ばれる。普通はActorの初期化処理を書く。
 - postStop()：stop(ActorRef)が呼ばれた後実行。クリン処理を書く。
 - preRestart()：失敗のスーパーバイザストラテジーがRestartの場合、再起動前実行。実行後postStop()が呼ばれるので、普通はoverrideしない。
 - postRestart()：再起動後実行。preStart()が呼ばれるので、普通はoverrideしない。
- ActorにはActorContextがある、```context```を使ってアクセスする。
 - ActorContextを使って、Actorのいち部分の機能を安全で使える。

 ```scala
 import akka.actor._
  class TaskManager extends Actor {
  ...
    def nextTaskName(): String = {
      "task-" + ...
    }
    def receive = {
      case RunTask(definition) =>
        val task = context.actorOf(Props[Task], nextTaskName)
        task ! Run(definition)
        ...
      case TaskCompleted =>
        ...
    }
  }
 ```
 - ```context.actorOf()```を使うと、Actorの下で子Actorを作れる

- ActorContextを使って、Actorの振る舞いを一つの```receive```から別の```receive```に切り替える。

```scala
import akka.actor._
class TaskManager extends Actor {
  var statusWatcher: ActorRef = None
  ...
  override def preStart(): Unit {
    context.become(houseKeeper)
  }
  def houseKeeper: Receive = {
    case StartTaskManagement(externalStatusWatcher) =>
      statusWatcher = Some(externalStatusWatcher)
      context.become(taskDistributor)
    case StartTaskManagementWithoutStatus =>
      context.become(taskDistributor)
  }
  def taskDistributor: Receive = {
    case RunTask(definition) =>
      val task = context.actorOf(Props[Task], nextTaskName)
      task ! Run(definition, statusWatcher)
      ...
    case TaskCompleted =>
      ...
  }
}
```

- ActorContextには他の```children```、```parent```、```props```、```self```、```sender()```、```stop(actor: ActorRef)```、```system```、```unbecome```などのメソッドがあります。詳しくはAkkaのドキュメントを参照。
http://doc.akka.io/docs/akka/2.4.2/scala/actors.html

### Supervision
- デフォルトsupervisorStrategy
 - ActorInitializationException：失敗した子Actorが停止
 - ActorKilledException：子Actorが停止
 - Exception：異常した子Actorが再起動
 - 他のThrowable異常が親Actorに上昇

- supervisorStrategyのoverrideする場合
 - AllForOneStrategyもしくはOneForOneStrategyを指定。
  - 普通はOneForOneStrategyを指定、問題ある子Actorだけに対して処理を行う。
	- AllForOneStrategyを指定する場合、すべての子Actorに対して処理を行う。
 - 行う処理を決まる：Escalate, Restart, Resume, or Stop

```scala
class LoanRateQuotes extends Actor {
  override val supervisorStrategy =
      OneForOneStrategy(
          maxNrOfRetries = 5,
          withinTimeRange = 1 minute) {
    case NullPointerException
    case ArithmeticException
    case IllegalArgumentException
    case UnsupportedOperationException => Stop
    case Exception                     => Escalate
  }
  ...
  def receive = {
    case RequestLoanQuotation(definition) =>
      val loadRateQuote =
               context.actorOf(Props[LoanRateQuote], nextName)
      loadRateQuote ! InitializeQuotation(definition)
      ...
    case LoanQuotationCompleted =>
      ...
  }
}
```
- 例えば、一つのクエリーの実行に失敗の場合は、失敗したActorだけに処理する方がいい。一方、データベースがアクセス出来ない場合、すべてのActorを停止する方がいい。
