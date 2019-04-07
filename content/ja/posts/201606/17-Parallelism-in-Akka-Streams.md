---
title: Parallelism in Akka Streams
date: 2016-06-17 11:31:42
tags:
- Scala
- Akka
- Akka Stream
categories: 
- Akka
---

Akka Streamsは非同期処理のオーバーヘッドを避けるため、デフォルトでStageを処理する時は順番で一つづつで処理していく。
しかし、複数のStageを非同期処理したい場合も必ずある。その時は ***async*** メソッドを使う。
***async*** をつけたStageは一つ単独のActorで実行される。一方、付けてないStageは全部もう一つのActorで実行される。

以下、2つのフライパンでパンケーキを作る例を通して、非同期処理の2つのやり方を紹介する。

<!-- more -->

#### Pipelining
まずはPipelining方式、2つのフライパンを違う工程をし、順番で行う方式。
一つのフライパンは生のパンケーキの片面を焼く、もう一つのフライパンは半分焼いたパンケーキのもう一面を焼く。

```scala
// Takes a scoop of batter and creates a pancake with one side cooked
val fryingPan1: Flow[ScoopOfBatter, HalfCookedPancake, NotUsed] =
  Flow[ScoopOfBatter].map { batter => HalfCookedPancake() }

// Finishes a half-cooked pancake
val fryingPan2: Flow[HalfCookedPancake, Pancake, NotUsed] =
  Flow[HalfCookedPancake].map { halfCooked => Pancake() }

// With the two frying pans we can fully cook pancakes
val pancakeChef: Flow[ScoopOfBatter, Pancake, NotUsed] =
  Flow[ScoopOfBatter].via(fryingPan1.async).via(fryingPan2.async)
```

この方式は、主に依存しているStageを非同期で処理する時に使う。
上記の例では、fryingPan2はfryingPan1の結果を依存しているが、非同期処理するので、fryingPan2が処理する時は、fryingPan1が次のパンケーキの処理に入れる。

#### Parallel
まずはParallel方式、2つのフライパン同時に同じ工程を行う方式。
2つのフライパンは生のパンケーキの両面を焼く。

```scala
val fryingPan: Flow[ScoopOfBatter, Pancake, NotUsed] =
  Flow[ScoopOfBatter].map { batter => Pancake() }

val pancakeChef: Flow[ScoopOfBatter, Pancake, NotUsed] = Flow.fromGraph(GraphDSL.create() { implicit builder =>
  val dispatchBatter = builder.add(Balance[ScoopOfBatter](2))
  val mergePancakes = builder.add(Merge[Pancake](2))

  // Using two frying pans in parallel, both fully cooking a pancake from the batter.
  // We always put the next scoop of batter to the first frying pan that becomes available.
  dispatchBatter.out(0) ~> fryingPan.async ~> mergePancakes.in(0)
  // Notice that we used the "fryingPan" flow without importing it via builder.add().
  // Flows used this way are auto-imported, which in this case means that the two
  // uses of "fryingPan" mean actually different stages in the graph.
  dispatchBatter.out(1) ~> fryingPan.async ~> mergePancakes.in(1)

  FlowShape(dispatchBatter.in, mergePancakes.out)
})
```

この方式は、主に依存していないStageを非同期で処理する時に使う。
メリットとしてはスケールアップしやすい、同じ工程で三つ目のフライパンにの出来る。
正しい結果の順番が保証されないので、注意が必要。
順番を保証したい場合は、[こちらの例](http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-cookbook.html#cookbook-balance-scala)を参照。

#### Combining pipelining and parallel processing
勿論、2つ方式を合成することも出来る。

まずはpipelining処理を2つparallelに合成。

```scala
val pancakeChef: Flow[ScoopOfBatter, Pancake, NotUsed] =
  Flow.fromGraph(GraphDSL.create() { implicit builder =>

    val dispatchBatter = builder.add(Balance[ScoopOfBatter](2))
    val mergePancakes = builder.add(Merge[Pancake](2))

    // Using two pipelines, having two frying pans each, in total using
    // four frying pans
    dispatchBatter.out(0) ~> fryingPan1.async ~> fryingPan2.async ~> mergePancakes.in(0)
    dispatchBatter.out(1) ~> fryingPan1.async ~> fryingPan2.async ~> mergePancakes.in(1)

    FlowShape(dispatchBatter.in, mergePancakes.out)
  })
```

この方式はフライパンを焼くような工程を相互影響しない場合に適用。
次はparallelな処理を2つのpipeliningに合成。

```scala
val pancakeChefs1: Flow[ScoopOfBatter, HalfCookedPancake, NotUsed] =
  Flow.fromGraph(GraphDSL.create() { implicit builder =>
    val dispatchBatter = builder.add(Balance[ScoopOfBatter](2))
    val mergeHalfPancakes = builder.add(Merge[HalfCookedPancake](2))

    // Two chefs work with one frying pan for each, half-frying the pancakes then putting
    // them into a common pool
    dispatchBatter.out(0) ~> fryingPan1.async ~> mergeHalfPancakes.in(0)
    dispatchBatter.out(1) ~> fryingPan1.async ~> mergeHalfPancakes.in(1)

    FlowShape(dispatchBatter.in, mergeHalfPancakes.out)
  })

val pancakeChefs2: Flow[HalfCookedPancake, Pancake, NotUsed] =
  Flow.fromGraph(GraphDSL.create() { implicit builder =>
    val dispatchHalfPancakes = builder.add(Balance[HalfCookedPancake](2))
    val mergePancakes = builder.add(Merge[Pancake](2))

    // Two chefs work with one frying pan for each, finishing the pancakes then putting
    // them into a common pool
    dispatchHalfPancakes.out(0) ~> fryingPan2.async ~> mergePancakes.in(0)
    dispatchHalfPancakes.out(1) ~> fryingPan2.async ~> mergePancakes.in(1)

    FlowShape(dispatchHalfPancakes.in, mergePancakes.out)
  })

val kitchen: Flow[ScoopOfBatter, Pancake, NotUsed] = pancakeChefs1.via(pancakeChefs2)
```

### まとめ

以上、Stageに関して説明はここまで、適切なStageを扱うことで、データを思うように操る事ができるでしょう。
Stageは流れで処理するので、処理の順番が保証される。
非同期処理にする方法もあります。

### 参考資料
- http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-customize.html
- http://doc.akka.io/docs/akka/2.4.7/scala/stream/stages-overview.html
- http://doc.akka.io/docs/akka/2.4.7/scala/stream/stream-parallelism.html
