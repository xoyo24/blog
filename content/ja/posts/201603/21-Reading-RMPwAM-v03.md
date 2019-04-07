---
title: Reading Reactive Messaging Patterns with the Actor Model 03
date: 2016-03-21 22:51:34
tags:
- Reactive
- Scala
- Akka
- Testing
categories: 
- Akka
---

## Testing Actors

- 2種類のテスト方法が提供されている。Actor内部の状態マシンの振る舞いのテストと、メッセージを使って、外部とのコミュニケーションのテスト。

<!-- more -->

### Unit Testing Actors

- TestKitをインポートして, TestActorRefを取得して、 実actorを取得する.

```scala
import akka.testkit.TestActorRef
val riskManagerRef = TestActorRef[RiskManager]
val riskManager = actorRef.underlyingActor
```

- これて、Actor内部のメソッドを直接テストすることができる。

  ※ 内部のメソッドを外部からアクセスさせでもいい。原因はActorは直接作れない、TestActorRefが唯一Actor内部のメソッドを直接アクセスする方法。

- TestActorRefのもう一つのメリットは、TestActorRefに送るメーセージはメールボックス経由せず、直接receiveに送れる。

ScalaTestを使う場合の例：

```scala
import org.scalatest.FunSuite
import akka.testkit.TestActorRef
class RiskManagerTestSuite extends FunSuite {
  val riskManagerRef = TestActorRef[RiskManager]
  val riskManager = actorRef.underlyingActor
  test("Must have risks when told to calculate.") {
    riskManagerRef ! CalculateRisk(Risk(...))
    assert(!riskManager.risksToCalculate.isEmpty)
	}
	...
}
```

### Behavioral Testing Message Processing

- BDDスタイルのテスト。

```scala
import org.scalatest.BeforeAndAfterAll
import org.scalatest.WordSpecLike
import org.scalatest.matchers.Matchers
import akka.testkit.ImplicitSender
import akka.testkit.TestKit
class RiskCalculatorSpec(testSystem: ActorSystem)
      extends TestKit(testSystem)
      with ImplicitSender
      with WordSpecLike
      with Matchers
      with BeforeAndAfterAll {
  // there is an implicit class argument
  def this() = this(ActorSystem("RiskCalculatorSpec"))
  override def afterAll {
    TestKit.shutdownActorSystem(system)
	}

	"A RiskCalculator" must {
    "confirm that a risk calculation request is in progress" in {
      val riskCalculator = system.actorOf(Props[RiskCalculator])
      riskCalculator ! CalculateRisk(Risk(...))
      expectMsg(CalculatingRisk(...))
		}
}
```
