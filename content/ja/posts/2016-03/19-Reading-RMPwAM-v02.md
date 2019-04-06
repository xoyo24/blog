---
title: Reading Reactive Messaging Patterns with the Actor Model 02
date: 2016-03-19 19:03:36
tags:
- Reactive
- Scala
- Akka
- Remoting
categories: 
- Akka
---

## Remoting

- Akka Remoteとは、分離したActorSystemをネットワーク経由でアクセスすることをサポートする機能。
- 通信方式はP2P。
- 違うActorSystemの命名は任意、ActorPathはホスト名とActorSystem名両方持つもで、同じActorSystem名でもいい。要は必要に合う。
- Actor間のアクセスは位置透過性(Location Transparency)がある。Actorにとって、ローカルかリモートか関係ない。

<!-- more -->

```scala
val someActor: ActorRef = ...
someActor ! SomeMessage(...)
```

- 2つのActorSystemは物理的に同じ機械にあるかどうかが関係なく、すべてのリモート通信はネットワーク経由。
- Actorはネットワークを考えてないが、君が考えなくていけない。帯域幅、レイテンシーなどに問題ある場合、ネットワークの最適化が必要。
- もう一つ考えなくていけない問題はシリアル化。デフォルトはJava serialization、パフォーマンスは一番悪い。
- Protocol Buffersと Kryo serializationがおすすめ。

```
  # application.conf for ActorSystem: RiskRover
	akka {
	 actor {
	   serializers {
	     proto = "akka.remote.serialization.ProtobufSerializer"
	     kryo = "com.romix.akka.serialization.kryo.KryoSerializer"
	     ...
	   }
	   serialization-bindings {
			 "java.io.Serializable" = none
		... }
	kryo {
	  type = "graph"
	  idstrategy = "incremental"
	  serializer-pool-size = 16
	  buffer-size = 4096
	  max-buffer-size = -1
	  ...
	} }
	}
```

- Akka remotingの設定
```
# application.conf for ActorSystem: RiskRover
akka {
... actor {
    # default is: "akka.actor.LocalActorRefProvider"
    provider = "akka.remote.RemoteActorRefProvider"
... }
  remote {
    # actors at: akka.tcp://RiskRover@hounddog:2552/user
    enabled-transports = ["akka.remote.netty.tcp"]
    netty.tcp {
      hostname = "hounddog"
      port = 2552
    }
  }
}
```
- RemoteActorRefProviderを設定した場合、ローカルActorは自動的にLocalActorRefProviderを使う。

### Remote Creation
- ローカルActorがリモートActorSystemにで子Actorを作る、ローカルActorがそのリモートActorのスーパーバイザになる。
例：
```
# application.conf for ActorSystem: RiskRover
akka {
... actor {
    provider = "akka.remote.RemoteActorRefProvider"
...
    deployment {
      /riskManager1 {
        remote = "akka.tcp://RiskyBusiness@bassethound:2552"
      }
		}
	}
}
```

```riskManager1``` という名前のActorを作る際、 ```bassethound:2552``` のホストで ``RiskyBusiness``` のActorSystem上で作られる。ActorPathな ```akka.tcp//RiskyBusiness@bassethound:2552/remote/RiskRover@↵ hounddog:2552/user/riskWorkManager/riskManager1``` になります。

```scala
// riskWorkManager deployed on hounddog:2552
class RiskWorkManager extends Actor {
  val riskManager =
        context.system.actorOf(Props[RiskManager], "riskManager1")
  def receive = {
      ...
      riskManager ! CalculateRisk(...)
... }
}
```
- この場合、CalculateRiskがシリアル化して、リモートActorに送る。そして、送る側の情報はRemoteActorRefとして送られる。

- リモートで作られたActorはすべて ```/remote``` の下にある。
  - リモートで大量なActorを作るべきではない、性能の影響が多きから。
	- リモートで作るべきActorは、スーパーバイザActor、そのActor内で子Actorを作る。この場合、スーパーバイザActorを止まったら、その子Actorたちも止められた。

- もう一つリモートActorを作る方法は、すべての子Actorをリモートで作る。
例：

```
# application.conf for ActorSystem: RiskyBusiness, RiskRover
akka {
... actor {
  provider = "akka.remote.RemoteActorRefProvider"
  ...
  deployment {
    /riskManager1 {
      remote = "akka.tcp://RiskyBusiness@bassethound:2552"
		}
		/riskManager1/* {
 		remote = "akka.tcp://RiskCalculators@bassethound:2553"
		}
	}
	}
}
```

- 同じホストで作る際に、違うポートを使う必要。

```scala
// riskManager1 deployed on bassethound:2552
class RiskManager extends Actor {
  val riskCalculator1 =
        context.system.actorOf(Props[RiskCalculator],
                               "riskCalculator1")
  val riskCalculator2 =
        context.system.actorOf(Props[RiskCalculator],
                               "riskCalculator2")
  val riskCalculator3 =
        context.system.actorOf(Props[RiskCalculator],
                               "riskCalculator3")
   ... }
```

### Remote Lookup
- もう一つリモートActorを使う方法は、リモートActorSystemから検索する。

```scala
import akka.actor.ActorSelection
...
val path = "akka.tcp://RiskyBusiness@bassethound:2552/user/riskManager1"
val selection = context.system.actorSelection(path)
selection ! CalculateRisk(...)
```
- 返り値はActorSelection、３種類の結果がある。
 - Zero actors found:  指定のPathでActorが見つからない。
 - One actor found: 一つのActorが見つかれた。
 - Multiple actors found: 一つ以上のActorが見つかれた。

- ActorSelectionとActorRef
 - ActorRefが停止もしくは存在しないActorを参照する可能性がある。
 - ActorSelectionは停止もしくは存在しないActorを検索しない、再起動したActorは常に同じPathである。
なので、ActorSelectionがActorRefより信頼性が高い。

- ActorSelectionからActorRefを取得する方法：
```scala
import akka.actor.ActorSelection
...
val path = "akka.tcp://RiskyBusiness@bassethound:2552/user/↵ riskManager1"
val selection = context.system.actorSelection(path)
val resolvedActor =
 selection.resolveOne(Timeout(3000)).onComplete {
   case Success(resolved) => Some(resolved)
   case Failure(e) => None
 }
if (resolvedActor isEmpty) createWithCalculateRisk
else resolvedActor.get ! CalculateRisk(...)
```

- もう一つ指定のActorにアクセスする方法は、ActorSelectionにIdentifyメッセージを送る。

```scala
private var calculatorPath: String = _
private var calculator: ActorRef = _
...
def receive = {
 case CalculateUsing(searchPath) =>
   val selection = context.actorSelection(searchPath)
   selection ! Identify(searchPath)
   calculatorPath = searchPath
 case identity: ActorIdentity =>
   if (identity.correlationId.equals(calculatorPath) {
     calculator = identity.ref.get
     calculator ! CalculateRisk(...)
```

- Akka clusteringはAkka remotingをベースに作られた、そして、ほとんどの場合、Akka clusteringを使えばいいですが。Akka remotingは特別の状況ではもっと使いやすくなる。
