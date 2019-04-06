---
title: Akka Stream 2.4からの新API
date: 2016-06-16 11:31:42
tags:
- Scala
- Akka
- Akka Stream
categories: 
- Akka
---

### A little Advanced Akka Streams API

前回の部分で、Source、Flow、Sinkを繋いていけば、線形の処理をシンプルに実装出来る。
でも非線形の処理はどうでしょうか？

#### Graph

Akka StreamはStreamの実行トポロジー、どう処理するのを表す概念をGraph（図）と呼ぶ。
線形、非線形、分岐のあるデータ処理は全部Graphである。

#### Junctions

まず、非線型処理をするため、Akka Streamが提供した分岐を見てみよう。

<!-- more -->

##### Fan-out 複数出力

- ***Broadcast[T]*** – (1 input, N outputs) inputをすべてのoutputに出す。
- ***Balance[T]*** – (1 input, N outputs) inputを任意一つのoutputに出す。
- ***UnZip[A,B]*** – (1 input, 2 outputs) Tuple[A, B]のinputをAとBに分割して、2つのoutputに別々で送る。
- ***UnzipWith[In,A,B,...]*** – (1 input, N outputs) inputを受け取って、N個の結果お返す関数を渡すことで、N個の結果を別々のoutputへ別々で送る (N <= 20)。

##### Fan-in 複数入力

- ***Merge[In]*** – (N inputs , 1 output) すべてのinputを一つのoutputに出す。
- ***MergePreferred[In]*** – 指定ポートを優先でmergeする。
- ***ZipWith[A,B,...,Out]*** – (N inputs, 1 output) 複数の入力を受け取って、一つの結果お返す関数を渡すことで、N個のinputを処理する。
- ***Zip[A,B]*** – (2 inputs, 1 output) inputのAとBをTuple[A, B]に合成する。
- ***Concat[A]*** – (2 inputs, 1 output) 2つのstreamを繋がる

必要な部件を揃うところで、Graphは以下のように作成出来る。

![simple-graph](/images/simple-graph-example1.png)

※Image taken from [doc.akka.io](http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-graphs.html)

``` scala
val g = RunnableGraph.fromGraph(GraphDSL.create() { implicit builder: GraphDSL.Builder[NotUsed] =>
  import GraphDSL.Implicits._
  val in = Source(1 to 10)
  val out = Sink.ignore

  val bcast = builder.add(Broadcast[Int](2))
  val merge = builder.add(Merge[Int](2))

  val f1, f2, f3, f4 = Flow[Int].map(_ + 10)

  in ~> f1 ~> bcast ~> f2 ~> merge ~> f3 ~> out
  bcast ~> f4 ~> merge
  ClosedShape
})
```

上記のコードでtweetsのSourceを2つのFlowにブロードキャストした。

- ***GraphDSL.create() { implicit b =>***　でGraphを作成

- ***GraphDSL.Implicits._*** をimportすることで、***~>*** (connect, via, toなど)みたいなGraph記号を使うことが出来る。反対の ***<~*** もある。

- ***ClosedShape*** (閉じた図形)はこのGraphは完全に繋がっている（SourceからSinkまで）の意味

- ClosedShapeになると、このGraphはRunnableGraphになる、 ***run()*** で実行出来る。

#### Shape

図の形状、図はClosedShape以外、いろんな形状になれる。
ClosedShape閉じ違って、完全に繋がっていないShapeを持つGraphは、 ***Partial graph*** と呼ぶ。

以下のように、Shapeを定義出来る。

```scala
// A shape represents the input and output ports of a reusable
// processing module
case class PriorityWorkerPoolShape[In, Out](
  jobsIn:         Inlet[In],
  priorityJobsIn: Inlet[In],
  resultsOut:     Outlet[Out]) extends Shape {

  // It is important to provide the list of all input and output
  // ports with a stable order. Duplicates are not allowed.
  override val inlets: immutable.Seq[Inlet[_]] =
    jobsIn :: priorityJobsIn :: Nil
  override val outlets: immutable.Seq[Outlet[_]] =
    resultsOut :: Nil

  // A Shape must be able to create a copy of itself. Basically
  // it means a new instance with copies of the ports
  override def deepCopy() = PriorityWorkerPoolShape(
    jobsIn.carbonCopy(),
    priorityJobsIn.carbonCopy(),
    resultsOut.carbonCopy())

  // A Shape must also be able to create itself from existing ports
  override def copyFromPorts(
    inlets:  immutable.Seq[Inlet[_]],
    outlets: immutable.Seq[Outlet[_]]) = {
    assert(inlets.size == this.inlets.size)
    assert(outlets.size == this.outlets.size)
    // This is why order matters when overriding inlets and outlets.
    PriorityWorkerPoolShape[In, Out](inlets(0).as[In], inlets(1).as[In], outlets(0).as[Out])
  }
}
```

##### Akka Streamでは、以下のShapeを用意している。

- ***SourceShape, SinkShape, FlowShape*** 普通のShapeを代表する,
- ***UniformFanInShape and UniformFanOutShape*** 複数かつ同じ型のinput、もしくはoutputを持つShape,
- ***FanInShape1, FanInShape2, ..., FanOutShape1, FanOutShape2, ...*** 複数かつ違うじ型のinput、もしくはoutputを持つShape。

##### Shapeの使い方
FanInShapeを使えば、上と同じPriorityWorkerPoolShapeを定義出来る。

```scala
import FanInShape.{ Init, Name }

class PriorityWorkerPoolShape2[In, Out](_init: Init[Out] = Name("PriorityWorkerPool"))
  extends FanInShape[Out](_init) {
  protected override def construct(i: Init[Out]) = new PriorityWorkerPoolShape2(i)

  val jobsIn = newInlet[In]("jobsIn")
  val priorityJobsIn = newInlet[In]("priorityJobsIn")
  // Outlet[Out] with name "out" is automatically created
}
```

PriorityWorkerPoolShapeを使って、Graphを作成する。

```scala
object PriorityWorkerPool {
  def apply[In, Out](
    worker:      Flow[In, Out, Any],
    workerCount: Int): Graph[PriorityWorkerPoolShape[In, Out], NotUsed] = {

    GraphDSL.create() { implicit b =>
      import GraphDSL.Implicits._

      val priorityMerge = b.add(MergePreferred[In](1))
      val balance = b.add(Balance[In](workerCount))
      val resultsMerge = b.add(Merge[Out](workerCount))

      // After merging priority and ordinary jobs, we feed them to the balancer
      priorityMerge ~> balance

      // Wire up each of the outputs of the balancer to a worker flow
      // then merge them back
      for (i <- 0 until workerCount)
        balance.out(i) ~> worker ~> resultsMerge.in(i)

      // We now expose the input ports of the priorityMerge and the output
      // of the resultsMerge as our PriorityWorkerPool ports
      // -- all neatly wrapped in our domain specific Shape
      PriorityWorkerPoolShape(
        jobsIn = priorityMerge.in(0),
        priorityJobsIn = priorityMerge.preferred,
        resultsOut = resultsMerge.out)
    }

  }

}
```

#### 複雑な例

以上の概念の組み合わせて行けば、下記のような複雑な処理をそのまま書ける。

##### ClosedShape

![compose_graph](/images/compose_graph1.png)

※Image taken from [doc.akka.io](http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-graphs.html)

```scala
import GraphDSL.Implicits._
RunnableGraph.fromGraph(GraphDSL.create() { implicit builder =>
  val A: Outlet[Int]                  = builder.add(Source.single(0)).out
  val B: UniformFanOutShape[Int, Int] = builder.add(Broadcast[Int](2))
  val C: UniformFanInShape[Int, Int]  = builder.add(Merge[Int](2))
  val D: FlowShape[Int, Int]          = builder.add(Flow[Int].map(_ + 1))
  val E: UniformFanOutShape[Int, Int] = builder.add(Balance[Int](2))
  val F: UniformFanInShape[Int, Int]  = builder.add(Merge[Int](2))
  val G: Inlet[Any]                   = builder.add(Sink.foreach(println)).in

                C     <~      F
  A  ~>  B  ~>  C     ~>      F
         B  ~>  D  ~>  E  ~>  F
                       E  ~>  G

  ClosedShape
})
```

Source、Flow、Sinkはaddする必要ないので、下記のようにも書ける。

```scala
import GraphDSL.Implicits._
RunnableGraph.fromGraph(GraphDSL.create() { implicit builder =>
  val B = builder.add(Broadcast[Int](2))
  val C = builder.add(Merge[Int](2))
  val E = builder.add(Balance[Int](2))
  val F = builder.add(Merge[Int](2))

  Source.single(0) ~> B.in; B.out(0) ~> C.in(1); C.out ~> F.in(0)
  C.in(0) <~ F.out

  B.out(1).map(_ + 1) ~> E.in; E.out(0) ~> F.in(1)
  E.out(1) ~> Sink.foreach(println)
  ClosedShape
})
```

##### Partial graph

![compose_graph_partial](/images/compose_graph_partial1.png)

※Image taken from [doc.akka.io](http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-graphs.html)

```scala
import GraphDSL.Implicits._
val partial = GraphDSL.create() { implicit builder =>
  val B = builder.add(Broadcast[Int](2))
  val C = builder.add(Merge[Int](2))
  val E = builder.add(Balance[Int](2))
  val F = builder.add(Merge[Int](2))

                                   C  <~  F
  B  ~>                            C  ~>  F
  B  ~>  Flow[Int].map(_ + 1)  ~>  E  ~>  F
  FlowShape(B.in, E.out(1))
}.named("partial")
```

※ named()はモジュールに名付けことが出来る、デバッグ時が有用。

FlowShapeになるので、Flowのように使える。

```scala
Source.single(0).via(partial).to(Sink.ignore)
```

### まとめ

今回はここまで、もうちょっと複雑なAPIの紹介しました。
Junctionsを使って、複雑なGraphを作成することが出来た。
これから、紙上で書いたフローチャートはそのまま書くことが出来るでしょう。

### 参考資料

- http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-quickstart.html
- http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-graphs.html
- http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-composition.html
