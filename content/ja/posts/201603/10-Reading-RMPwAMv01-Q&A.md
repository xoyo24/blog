---
title: Reading Reactive Messaging Patterns with Actor Model v01 Q&A
date: 2016-03-06 14:28:33
tags:
- Reactive
- Scala
- Akka
categories: 
- Akka
---

## Reading Reactive Messaging Patterns with Actor Model v01 Q&A

1. Playを使う場合、別のActorSystemを作らないといけないですか？

<!-- more -->

  - 本の中にはそう書いていますが、実際Playのドキュメントを見れば、PlayはAkkaのよく設定されているので、PlayのActorSystemを使用を推奨されている（https://www.playframework.com/documentation/2.4.x/ScalaAkka）。別のActorSystemを作るのは可能ですが、使う時は以下の注意事項があります。
    - Playがシャットダウンの時、ActorSystemもシャットダウン出来る機構を作る。
    - Playアプリケーション側のクラスをアクセスするため、classloaderを渡す。
    - play.akka.configを使って、PlayのAkka設定呼び出すパスを変えるか、或いは別のところから新しいActorSystemの設定を呼び出すか。そうしないと、 2つのActorSystemが同じリモートポートをバインドするみたいな問題が発生する。

2. Propsは何？どう使う？

 - Akkaのドキュメントによると、PropsはActorの作成必要な設定、レシピみたいのもの。以下の様な使い方があります。

 ```scala
 import akka.actor.Props

 val props1 = Props[MyActor] // パラメータなしのアクター
 val props2 = Props(new ActorWithArgs("arg")) // Actorのインスタンスを渡す、使う際に注意が必要
 val props3 = Props(classOf[ActorWithArgs], "arg") // コンストラクタとパラメータを渡す
 ```

 - 二番目の形式が暗黙で使う側のthisを渡しましたので、危険です。本当に必要の場合は、以下のようにするほうがいい。

 ```scala
  object DemoActor {
    /**
     * Create Props for an actor of this type.
     *
     * @param magicNumber The magic number to be passed to this actor’s constructor.
     * @return a Props for creating this actor, which can then be further configured
     *         (e.g. calling `.withDispatcher()` on it)
     */
    def props(magicNumber: Int): Props = Props(new DemoActor(magicNumber))
  }

  class DemoActor(magicNumber: Int) extends Actor {
    def receive = {
      case x: Int => sender() ! (x + magicNumber)
    }
  }

  class SomeOtherActor extends Actor {
    // Props(new DemoActor(42)) would not be safe
    context.actorOf(DemoActor.props(42), "demo")
    // ...
  }
 ```

3. Actorとcontextは具体的どう違う？

 - contextはActorトレイトで定義したフィルドの一つ、Actorの文脈上の情報を提供している。例えば、
   - 子Actorを作るファクトリーメソッド
   - Actorが属するActorSystem
   - 親スーパーバイザ
   - 子actors
   - ライフサイクル監視
   - Actorの振る舞いを変更方法

4. context.becomeを使うと、Actorの挙動変わるので、危ないではないか？

 - まず、FPと違って、Actorモデルでは、immutableな状態の存在が許容されている、Actor内で閉じ込める、メッセージがimmutableの前提で。
 - becomeを使う際に、前の振る舞いは消えるではなく、スタック方式で保存されている、unbecomeで前の振る舞いに戻れる
 - become/unbecomeの使う場面としては、有限オートマトンを一つActorの中で定義するなどがあります。
 - unbecomeがbecomeより多く呼ばれた場合はメモリリークになるので、注意が必要

参考：
- http://doc.akka.io/docs/akka/2.4.2/general/actor-systems.html#actor-systems
- http://doc.akka.io/docs/akka/2.4.2/scala/actors.html
