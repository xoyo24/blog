---
title: Akka Streamを始めました
date: 2016-06-15 12:00:00
tags:
- Scala
- Akka
- Akka Stream
categories: 
- Akka
---

こんにちは、ショウです。
Akka Streamが2.4以降からexperimentalを外して、正式版をリリースしました。丁度会社で3日のHackerDaysを機に、Akka Streamを勉強しはじめました。
この記事では、Akka Streamの公式ドキュメントを抜粋し、翻訳しながら、Akka Streamの基礎概念を説明します。

### Akka Streamでなに

#### 背景

今のInternet上、我々は膨大なデータを消費している。その大量のデータを人々はビッグデータと呼んでいるw。
もう昔みたいにデータを全部ダウンロードして処理、処理完了してアップロード的な処理は時間掛かりすぎ、そもそも一台のサーバに保存しきれないデータは処理できないので、Streamみたいな流れとしての処理が必要になっている。
Akkaが使うActorモデルもその一例、データを分割し、メッセージとしてActorに送る、Actorは只々流れてきたメッセージを処理し、リアルタイムの処理が出来る。

#### 課題

##### ただし、Actor間の安定メッセージを実現するのは難し。

メッセージを送る側をPublisherとして、受け取る側をSubscriberと呼ぶ。

- Publisher側の処理が早い場合Subscriber側のバッファーが溢れてしまう。
- Subscriberに遠慮してPublisher側の処理を抑えた場合は無駄が多くなってしまう。

#### Akka Streamという解決案

<!-- more -->

##### Back Pressure

- それをSubscriberが自分が処理できる量をPublisherにリクエストを送ることで無駄なくSubscriberが処理できる量を処理する仕組み。

##### Reactive Streams

- 違うStream処理ツール間でもBack Pressure実現出来るため、Reactive Streams（ノンブロッキングでback pressureな非同期ストリーム処理の標準仕様）を提唱。

##### その他のメリット

- Akka StreamはいろんなデータをStreamのように処理することが出来る。
- 直感的なユーザAPIを使って、処理を共通モジュール化出来る。
- 処理過程を図を書くようにシンプル。
- 処理のコンテスト、処理過程と処理の実行を分けている。処理過程必要なところに持ち込んで、好きなタイミングで実行出来る。
- Back Pressureがあるので、性能を最大限まで引き出す能力を持っている。
- Block処理がある場合、実行時間は既存の処理としてあんまり変わらないので。Futureを使って、Non-blockingの実装が望ましい。

## Akka Streams API

Akka Streamsはバージョン2.4以降、APIを一新させ、experimental（実験的）でなくなった。Akka Streamsを使うため、まずAPIの中の基本概念を覚えよう。

### Materializer

Stream処理を実行する環境の抽象化、Actorで実行たい場合は、ActorMaterializerを使う。
※ 本文で書かれたコード例は、全部以下のコードを含む。

``` scala
import scala.concurrent._
import akka._
import akka.actor._
import akka.stream._
import akka.stream.scaladsl._
import akka.util._

implicit val system = ActorSystem("TestSystem")
implicit val materializer = ActorMaterializer()
import system.dispatcher
```

### Source

源流、データを作る側、input channelを持たない、一つのoutput channelを持っている。

![Source](https://prismic-io.s3.amazonaws.com/boldradius/f11b4a37597064e93856d4d0880b9e74e5507635_akka-streams-source.png)

※Image taken from [boldradius.com](http://boldradius.com/blog-post/VS0NpTAAADAACs_E/introduction-to-akka-streams)

#### Sourceを使い方

1. まずは、有限のデータをSourceにする方法。遅延評価のため、run* 実行しないと、評価されない。

``` scala
scala> val s = Source.empty
s: akka.stream.scaladsl.Source[Nothing,akka.NotUsed] = ...

scala> val s = Source.single("single element")
s: akka.stream.scaladsl.Source[String,akka.NotUsed] = ...

scala> val s = Source(1 to 3)
s: akka.stream.scaladsl.Source[Int,akka.NotUsed] = ...

scala> val s = Source(Future("single value from a Future"))
s: akka.stream.scaladsl.Source[String,akka.NotUsed] = ...

scala> s runForeach println
res0: scala.concurrent.Future[akka.Done] = ...
single value from a Future
```

2. 次は、無限データをSourceにする方法。無限で評価されないため、takeを入れた。

```scala
scala> val s = Source.repeat(5)
s: akka.stream.scaladsl.Source[Int,akka.NotUsed] = ...

scala> s take 3 runForeach println
res1: scala.concurrent.Future[akka.Done] = ...
5
5
5
```

3. そして、Actorに送るメッセージをSourceにする方法。
結果から、Futureが違うスレッドで並行実行されることが分かる。
※ ただし、この方法はBack Pressure出来ないので、BufferとBuffer超える際の処理を指定する必要。

```scala
def run(actor: ActorRef) = {
  Future { Thread.sleep(300); actor ! 1 }
  Future { Thread.sleep(200); actor ! 2 }
  Future { Thread.sleep(100); actor ! 3 }
}
val s = Source
  .actorRef[Int](bufferSize = 0, OverflowStrategy.fail)
  .mapMaterializedValue(run)

scala> s runForeach println
res1: scala.concurrent.Future[akka.Done] = ...
3
2
1
```

### Sink
水槽、最終的にデータを受け取る側。Sourceの反対で、output channelを持たない、一つのinput channelを持っている。

![Sink](https://prismic-io.s3.amazonaws.com/boldradius/41943c3155b7d7ce99faba52b846272e99a41fa9_akka-streams-sink.png)

※Image taken from [boldradius.com](http://boldradius.com/blog-post/VS0NpTAAADAACs_E/introduction-to-akka-streams)

#### Sinkを使い方

1. Sourceと直接繋ぐ

***to*** を使えば、SourceとSinkを繋ぐことが出来る。戻り値は ***RunnableFlow*** と呼ぶ。RunnableFlowに対して ***run()*** を実行すれば、評価される。

```scala
scala> val source = Source(1 to 3)
source: akka.stream.scaladsl.Source[Int,akka.NotUsed] = ...

scala> val sink = Sink.foreach[Int](elem => println(s"sink received: $elem"))
sink: akka.stream.scaladsl.Sink[Int,scala.concurrent.Future[akka.Done]] = ...

scala> val flow = source to sink
flow: akka.stream.scaladsl.RunnableGraph[akka.NotUsed] = ...

scala> flow.run()
res3: akka.NotUsed = NotUsed
sink received: 1
sink received: 2
sink received: 3
```

![runaable-flow](https://prismic-io.s3.amazonaws.com/boldradius/82c03ac92626e43f8e3a530289ad5c1174e1881c_akka-streams-runaable-flow.png)

※Image taken from [boldradius.com](http://boldradius.com/blog-post/VS0NpTAAADAACs_E/introduction-to-akka-streams)

2. すべてのデータをActorに渡すことも当然できる。

``` scala
val actor = system.actorOf(Props(new Actor {
  override def receive = {
    case msg => println(s"actor received: $msg")
  }
}))

scala> val sink = Sink.actorRef[Int](actor, onCompleteMessage = "stream completed")
sink: akka.stream.scaladsl.Sink[Int,akka.NotUsed] = ...

scala> val runnable = Source(1 to 3) to sink
runnable: akka.stream.scaladsl.RunnableGraph[akka.NotUsed] = ...

scala> runnable.run()
res3: akka.NotUsed = NotUsed
actor received: 1
actor received: 2
actor received: 3
actor received: stream completed
```

### Flow

既存systemのデータをAkka Streamに渡すだけなら、SourceとSinkが十分ですが、出来ないこともある。
Flowがoutput channelとinput channelの両方をも行っている、SourceとSinkの間で、データを好きのように変換出来る。

![Flow](/images/akka-streams-flow.png)

※Image taken from [boldradius.com](http://boldradius.com/blog-post/VS0NpTAAADAACs_E/introduction-to-akka-streams)

SourceとFlowを繋げば、新しいSourceになる、FlowとSinkを繋げば、新しいSinkになる、すべて繋げば、 ***RunnableFlow*** になる。

![source-flow-sink](/images/akka-streams-source-flow-sink.png)

※Image taken from [boldradius.com](http://boldradius.com/blog-post/VS0NpTAAADAACs_E/introduction-to-akka-streams)

#### Flowを使い方

1. ***via*** を使えて、SourceとFlowを繋ぐ、inputの型が指定する必要がある。
SourceとFlowとSinkは完全独立なので、再利用出来る。

```scala
scala> val source = Source(1 to 3)
source: akka.stream.scaladsl.Source[Int,akka.NotUsed] = ...

scala> val sink = Sink.foreach[Int](println)
sink: akka.stream.scaladsl.Sink[Int,scala.concurrent.Future[akka.Done]] = ...

scala> val invert = Flow[Int].map(elem => elem * -1)
invert: akka.stream.scaladsl.Flow[Int,Int,akka.NotUsed] = ...

scala> val doubler = Flow[Int].map(elem => elem * 2)
doubler: akka.stream.scaladsl.Flow[Int,Int,akka.NotUsed] = ...

scala> val runnable = source via invert via doubler to sink
runnable: akka.stream.scaladsl.RunnableGraph[akka.NotUsed] = ...

scala> runnable.run()
res10: akka.NotUsed = NotUsed
-2
-4
-6
```

2. SourceとSinkとFlowを繋ぐ

```scala
scala> val s1 = Source(1 to 3) via invert to sink
s1: akka.stream.scaladsl.RunnableGraph[akka.NotUsed] = ...

scala> val s2 = Source(-3 to -1) via invert to sink
s2: akka.stream.scaladsl.RunnableGraph[akka.NotUsed] = ...

scala> s1.run()
res10: akka.NotUsed = NotUsed
-1
-2
-3

scala> s2.run()
res11: akka.NotUsed = NotUsed
3
2
1
```

### まとめ

以上、Akka Streamにおける、最も基礎な部分を話ししました。
Streamを構成するSource、Flow、Sink、3つの基礎概念がある。これらを使えば、ほとんどの線形処理を書くことが出来る。
なお、再利用出来る共通モジュールも作ることが出来る。

### 参考資料
- http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-introduction.html
- http://doc.akka.io/docs/akka/2.4.7/general/stream/stream-design.html
- https://stackoverflow.com/questions/35120082/how-to-get-started-with-akka-streams
