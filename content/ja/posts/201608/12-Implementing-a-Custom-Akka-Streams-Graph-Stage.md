---
title: Implementing a Custom Akka Streams Graph Stage
date: 2016-08-12 12:23:49
tags:
- Scala
- Akka
- Akka Stream
categories: 
- Akka
---

前の記事で、Akka Streamsでデータ処理部品の組み立て方法を紹介した。
しかし、その部品内部の処理のカスタマイズしたい場合は、どうしましょうか？

Akka Streamsでは、Graphを作成する処理をProcessing Stageとよんでいる。
一般的なProcessing Stageは前に紹介したmap(), filter()などのメソッドがあるが、自分で実装したい場合は ***GraphStage*** を継承して実装する必要がある。

<!-- more -->

##### GraphStageの使い方

まずイメージをつけるため、GraphStageはどんなものを見って見ましょう。

```scala
import akka.stream.SourceShape
import akka.stream.stage.GraphStage

class NumbersSource extends GraphStage[SourceShape[Int]] {
  // Define the (sole) output port of this stage
  val out: Outlet[Int] = Outlet("NumbersSource")
  // Define the shape of this stage, which is SourceShape with the port we defined above
  override val shape: SourceShape[Int] = SourceShape(out)

  // This is where the actual (possibly stateful) logic will live
  override def createLogic(inheritedAttributes: Attributes): GraphStageLogic = ???
}
```

- まずGraphStageのshapeを定義、ここはSourceShapeなので、一つのoutputだけ。
- そして、createLogicがあります、ここでSourceShapeはどうデータを出力するを定義出来る。

```scala
override def createLogic(inheritedAttributes: Attributes): GraphStageLogic =
    new GraphStageLogic(shape) {
      // All state MUST be inside the GraphStageLogic,
      // never inside the enclosing GraphStage.
      // This state is safe to access and modify from all the
      // callbacks that are provided by GraphStageLogic and the
      // registered handlers.
      private var counter = 1

      setHandler(out, new OutHandler {
        override def onPull(): Unit = {
          push(out, counter)
          counter += 1
        }
      })
    }
```

これて、新しいGraphStageはGraphなって、Sourceに変換すれば、Sourceとしてに使うことが出来る。

```scala
// A GraphStage is a proper Graph, just like what GraphDSL.create would return
val sourceGraph: Graph[SourceShape[Int], NotUsed] = new NumbersSource

// Create a Source from the Graph to access the DSL
val mySource: Source[Int, NotUsed] = Source.fromGraph(sourceGraph)

// Returns 55
val result1: Future[Int] = mySource.take(10).runFold(0)(_ + _)

// The source is reusable. This returns 5050
val result2: Future[Int] = mySource.take(100).runFold(0)(_ + _)
```
