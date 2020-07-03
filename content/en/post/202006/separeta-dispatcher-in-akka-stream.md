---
title: "Throughput tuning with Parallelism in Akka Streams"
date: 2020-06-18
# lastmod: 2017-08-31T15:43:48+08:00
draft: false
tags: ["Scala", "AkkaStreams", "parallelism", "concurrency", "performance"]
# categories: ["AkkaStreams"]
---

When we using Akka Streams to do stream processing with infinity elements, it's been processed 1 after 1 by default.
With back-pressure provided by Akka Stream, we can notify the producer to slow down to solve the fast producer vs. slow consumer problem.
But sometimes we can't control the production speed, like Kafka messages, we need to find some way to fasten the consuming speed.

Let's say a Kafka topic produce 100 messages per second per partition while consumer will spend 1 second to consume each message.
Put it in code will be something like this:

```scala
Source
    .tick(0.milliseconds, 10.milliseconds, ())
    .zipWithIndex
    .map(i => processJob(i._2))
    .runWith(Sink.foreach(println))
```

We can not solve this by adding more consumers as 1 topic partition can only be consumed by 1 consumer, so we must find a way to increase consumption speed.

In Akka Streams, we can easily make the process ran parallelly by using `mapAsync` and specify the parallelism (ex. 100).

```scala
Source
    .tick(0.milliseconds, 10.milliseconds, ())
    .zipWithIndex
    .mapAsync(parallelism = 100)(i => processJobAsync(i._2))
    .runWith(Sink.foreach(println))
```

Will the problem be solved? Probably no, concurrency problems will never be so easy, otherwise, there will not be so many books about it.

In this post, I'll try to provide my answer to `How to increase throughput in Akka stream by tuning the thread pool` and hope you can find something interesting or useful.

## Case #1: non-blocking process

There are different kinds of definitions and implementations of `non-blocking`, we won't run into details of them this time. Instead, let's define `non-blocking` as,

**The process will not block current thread or thread pool, so they can use the processing time to process other tasks**

I'll use the below code to simulate a simple non-blocking process with 1 second of delay. And call it with `mapAsync` with 100 parallelisms, so at most 100 `nonBlockingCall` can run parallels.

```scala
def nonBlockingCall(value: Int)(implicit system: ActorSystem, ec: ExecutionContext): Future[Int] = {
  val promise = Promise[Int]
  val max = FiniteDuration(1000, MILLISECONDS)
  system.scheduler.scheduleOnce(max) {
    promise.success(value)
    println(s"[${Thread.currentThread().getName}] ${LocalDateTime.now()}: Finished call with ${value}")
  }
  promise.future
}

val start = Instant.now
val future = Source
    .tick(0.milliseconds, 10.milliseconds, ())
    .take(100)
    .zipWithIndex
    .mapAsync(100)(a ⇒ nonBlockingCall(a._2.toInt))
    .runWith(Sink.ignore)

Await.result(future, 1.minutes)
val end = Instant.now
println("Finished: " + Duration.between(start, end))
```

With the default Akka dispatcher(thread poll) setting on my 4 cores CPU PC, this program took 4s to finish processing 100 messages.
And even if I limit the default thread pool to 1 thread, it will still spend the same time.

Part of the logs looks like this:

```
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.243018: Finished call with 90
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.273625: Finished call with 91
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.303692: Finished call with 92
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.333440: Finished call with 93
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.363533: Finished call with 94
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.393380: Finished call with 95
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.423460: Finished call with 96
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.453227: Finished call with 97
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.483068: Finished call with 98
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:33:44.523523: Finished call with 99
Finished: PT4.099787S
```

The reason whey it's not 1 second is because the 100 messages won't come at the same time.
But if we do not limit the production speed and produce messages in a batch like `Source(0 to 100)`, it can finish around 1 second.

As the non-blocking process will not block the current thread, the thread pool can use the time to execute other tasks in another stage.
So the first thing we can learn here is to try using the non-blocking process whenever you can in Akka Streams, then you can make the process faster by simply using `mayAsync` and increase the `parallelism`.

## Case #2: Blocking process

On the contrary, a blocking process will block the current thread so it can't execute other task. Here is an example:

```scala
def blockingCall(value: Int): Int = {
  Thread.sleep(1000 + random.nextInt(10)) // Simulate long processing *don't sleep in your real code!
  println(s"[${Thread.currentThread().getName}] ${LocalDateTime.now()}: Finished call with ${value}")
  value
}

val start = Instant.now
val future = Source
  .tick(0.milliseconds, 10.milliseconds, ())
  .take(100)
  .zipWithIndex
  .mapAsync(100)(a ⇒ Future(blockingCall(a._2.toInt)))
  .runWith(Sink.ignore)

Await.result(future, 1.minutes)
val end = Instant.now
println("Finished: " + Duration.between(start, end))
```

This time, the log looks like this:

```
[default-akka.actor.default-dispatcher-7] 2020-06-20T21:42:10.337691: Finished call with 90
[default-akka.actor.default-dispatcher-8] 2020-06-20T21:42:10.379012: Finished call with 91
[default-akka.actor.default-dispatcher-9] 2020-06-20T21:42:10.403279: Finished call with 92
[default-akka.actor.default-dispatcher-10] 2020-06-20T21:42:10.434547: Finished call with 93
[default-akka.actor.default-dispatcher-11] 2020-06-20T21:42:10.465673: Finished call with 94
[default-akka.actor.default-dispatcher-6] 2020-06-20T21:42:10.506012: Finished call with 95
[default-akka.actor.default-dispatcher-5] 2020-06-20T21:42:11.288412: Finished call with 96
[default-akka.actor.default-dispatcher-4] 2020-06-20T21:42:11.322124: Finished call with 97
[default-akka.actor.default-dispatcher-7] 2020-06-20T21:42:11.349151: Finished call with 98
[default-akka.actor.default-dispatcher-8] 2020-06-20T21:42:11.387368: Finished call with 99
Finished: PT13.27612S
```

First, we can see it spent 13 seconds to finish 100 messages this time.
That's because, with the default Akka dispatcher setting, it creates a thread pool with 8 threads (`dispatcher-4` ~ `dispatcher-11`) on my machine.
So 8 tasks can run at the same time, with each task around 1 second, it took around 100/8 seconds.
We can make it faster by introduce more threads in configuration like this:

```
akka {
  actor {
    default-dispatcher {
      fork-join-executor {
        # Min number of threads to cap factor-based parallelism number to
        parallelism-min = 100
        # Parallelism (threads) ... ceil(available processors * factor)
        parallelism-factor = 1.0
        # Max number of threads to cap factor-based parallelism number to
        parallelism-max = 100
      }
    }
  }
}
```

With this configuration, the example can finish in 4 seconds like the non-blocking one.

But that's not enough.

## Problem

To explain what's the problems with our solution with the blocking process, let's compare thread usage of the previous 2 examples.

#### Non-blocking

![Non-blocking](/images/202006/blocking-threads.jpg)

#### Blocking

![Blocking](/images/202006/non-blocking-threads.jpg)

What we can see here is that: Non-blocking process is not using threads most of the time while the blocking process will block threads it uses.

It's fine if it's just a sample program, but for a real-world application, there will be problems like:

- If blocking is making all threads in a pool busy(or sleep), they will not able to process other tasks, this will be a big problem if we have more than 1 stream in our application.
- Don't like the example, the blocking process is hard to identify sometimes, especially when all processes run in the same thread pool. We'll need to look into corners of code to find it.
- As we can't make full use of computing resources if we only have 1 thread pool, it's hard to maximize the performance.

To solve the above problems, we need to run blocking processes in a separate thread pool.

## Use a custom thread pool

By using Akka dispatcher, we can specify and tune a thread pool easily.

First create a configuration for dispatcher (ex. a fixed size thread pool) in `application.conf` like:

```
akka {
  actor {
    blocking-io-dispatcher {
      type = Dispatcher
      executor = "thread-pool-executor"
      thread-pool-executor {
        fixed-pool-size = 20
      }
    }
  }
}
```

_There are more types of dispatchers, you can choose base on your need from the [official doc](https://doc.akka.io/docs/akka/current/dispatchers.html)._

Then use it in the stream like:

```scala
val blockingDispatcher = system.dispatchers.lookup("akka.actor.blocking-io-dispatcher")

val start = Instant.now
val future = Source
  .tick(0.milliseconds, 10.milliseconds, ())
  .take(100)
  .zipWithIndex
  .mapAsync(100)(a ⇒ Future(blockingCall(a._2.toInt))(blockingDispatcher))
  .runWith(Sink.ignore)

Await.result(future, 1.minutes)
val end = Instant.now
println("Finished: " + Duration.between(start, end))
```

From the log we can see the task is running on the specify dispatcher and now it can finish around 5 seconds.

```
[default-akka.actor.blocking-io-dispatcher-6] 2020-06-20T22:49:52.904651: Finished call with 80
[default-akka.actor.blocking-io-dispatcher-7] 2020-06-20T22:49:52.915199: Finished call with 81
[default-akka.actor.blocking-io-dispatcher-8] 2020-06-20T22:49:52.943886: Finished call with 82
[default-akka.actor.blocking-io-dispatcher-9] 2020-06-20T22:49:52.981177: Finished call with 83
[default-akka.actor.blocking-io-dispatcher-10] 2020-06-20T22:49:53.010724: Finished call with 84
[default-akka.actor.blocking-io-dispatcher-11] 2020-06-20T22:49:53.044375: Finished call with 85
[default-akka.actor.blocking-io-dispatcher-12] 2020-06-20T22:49:53.084106: Finished call with 86
[default-akka.actor.blocking-io-dispatcher-13] 2020-06-20T22:49:53.112741: Finished call with 87
[default-akka.actor.blocking-io-dispatcher-14] 2020-06-20T22:49:53.141283: Finished call with 88
[default-akka.actor.blocking-io-dispatcher-15] 2020-06-20T22:49:53.152561: Finished call with 89
[default-akka.actor.blocking-io-dispatcher-16] 2020-06-20T22:49:53.199201: Finished call with 90
[default-akka.actor.blocking-io-dispatcher-17] 2020-06-20T22:49:53.232378: Finished call with 91
[default-akka.actor.blocking-io-dispatcher-18] 2020-06-20T22:49:53.265670: Finished call with 92
[default-akka.actor.blocking-io-dispatcher-19] 2020-06-20T22:49:53.276495: Finished call with 93
[default-akka.actor.blocking-io-dispatcher-20] 2020-06-20T22:49:53.322675: Finished call with 94
[default-akka.actor.blocking-io-dispatcher-21] 2020-06-20T22:49:53.348531: Finished call with 95
[default-akka.actor.blocking-io-dispatcher-22] 2020-06-20T22:49:53.370512: Finished call with 96
[default-akka.actor.blocking-io-dispatcher-23] 2020-06-20T22:49:53.415814: Finished call with 97
[default-akka.actor.blocking-io-dispatcher-24] 2020-06-20T22:49:53.434158: Finished call with 98
[default-akka.actor.blocking-io-dispatcher-25] 2020-06-20T22:49:53.453626: Finished call with 99
Finished: PT5.690817S
```

And if we see the thread usage, now the default thread pool is not been blocked anymore.

![Block with dispatcher](/images/202006/blocking-threads-with-dispatcher.jpg)

## Summary

To summarize what we have learned:

- For non-blocking processes, specify a separate dispatcher is not be necessary, using `mapAsync` increase `parallelism` can increase throughput.
- For blocking processes, using `mapAsync` increase `parallelism` can increase throughput. But usually better to specify a separate dispatcher to avoid blocking on the main thread pool, and help manage thread pools and throughput easier.
