---
title: "Rate limit (throttle) in Akka Streams"
date: 2020-06-08T00:00:00+09:00
lastmod: 2020-06-08T00:00:00+09:00
draft: false
tags: ["Scala", "Akka", "AkkaStreams", "throttle"]
categories: ["CodeReading"]
---

Recently, I got a chance to contribute to Akka by adding unprovided `throttle` operator into `FlowWithContext`, which can carry context in a Stream without care about it, like Kafka offset. It's a very good chance to learn some implementation details about Akka Streams, and here is what I've learned.

<!--more-->

**Before we start, why we need `throttle`?**

There are lots of cases we can use `throttle`, and the main reason in our use case is to do a rate-limiting for accessing external resources like APIs, so we will not DDoS the API when peak traffic comes, creating lots of error and kill the service for more errors by retries.

So, let's look at how we do a `throttle` without Akka Streams first.

## Rate limit without Akka Streams

Assume we have a method called `processJob` and it accesses external resources, and we want to only call the API once per second.

```scala
for (i <- 1 to count) yield {
  Thread.sleep(1000)
  processJob(i)
}
```

We can easily see what's the problem with this solution,

- It will block the current thread and waste compute resources.
- It's not accurate enough as we don't know how long `processJob` will take.

## `throttle` in Akka Streams

While in Akka Streams, we can just add a throttle before it.

```scala
Source.tick(0 milliseconds, 10 milliseconds, ())
    .throttle(elements = 1, per = 1 second, maximumBurst = 1, mode = ThrottleMode.shaping)
    .map(i => processJob(i))
    .runWith(Sink.foreach(println))
```

Let me add more explanation here,

- `throttle` can limit rate by the amount of message per specific duration, also cost of each message, and burstiness (explain later)
- It has two kinds of strategies.
  - Shaping: makes pauses before emitting messages to meet throttle rate
  - Enforcing: fails with exception when upstream is faster than throttle rate

## How it works inside

After seeing how to use it, it's time for the fun part, to read the implementation code.

```scala
// ...
private val tokenBucket = new NanoTimeTokenBucket(effectiveMaximumBurst, nanosBetweenTokens)
// ...
override def onPush(): Unit = {
  val elem = grab(in)
  val cost = costCalculation(elem)
  val delayNanos = tokenBucket.offer(cost)

  if (delayNanos == 0L) push(out, elem)
  else {
    if (enforcing) failStage(new RateExceededException("Maximum throttle throughput exceeded."))
    else {
      currentElement = elem
      scheduleOnce(timerName, delayNanos.nanos)
    }
  }
}
// ...
override protected def onTimer(key: Any): Unit = {
  push(out, currentElement)
  currentElement = null.asInstanceOf[T]
  if (willStop) completeStage()
}
```

Ref: [Full source code](https://github.com/akka/akka/blob/master/akka-stream/src/main/scala/akka/stream/impl/Throttle.scala)

- `onPush()` is called when the input port has now a new element. Now it is possible to acquire this element using grab(in) and/or call pull(in) on the port to request the next element.

Here we can see the logic starts by creating a `tokenBucket` with specific `maxBurst` and `nanosBetweenTokens`, which calculated by `per.toNanos / cost`.

Then when a new message comes in, Throttle class computes how long it needs to delay the message by offering the cost of the message to the `tokenBucket`.

A last it will decide whether to push the message to the next stage if no delay needed or schedule the push after the delay.

### Token bucket Algorithm

By the [scaladoc](<https://doc.akka.io/api/akka/current/akka/stream/javadsl/Flow.html#throttle(cost:Int,per:java.time.Duration,maximumBurst:Int,costCalculation:akka.japi.function.Function[Out,Integer],mode:akka.stream.ThrottleMode):akka.stream.javadsl.Flow[In,Out,Mat]>) for `throttle`, we may know:

> Throttle implements the token bucket model. There is a bucket with a given token capacity (burst size or maximumBurst). Tokens drops into the bucket at a given rate and can be 'spared' for later use up to bucket capacity to allow some burstiness.

So, what is a `Token bucket model`, we can find it in [Wikipedia](https://en.wikipedia.org/wiki/Token_bucket):

> The token bucket is an algorithm used in packet switched computer networks and telecommunications networks.
> In traffic shaping, packets are delayed until they conform.

And here is the source code:

```scala
def offer(cost: Long): Long = {
  if (cost < 0) throw new IllegalArgumentException("Cost must be non-negative")

  val now = currentTime
  val timeElapsed = now - lastUpdate

  val tokensArrived =
    // Was there even a tick since last time?
    if (timeElapsed >= nanosBetweenTokens) {
      // only one tick elapsed
      if (timeElapsed < nanosBetweenTokens * 2) {
        lastUpdate += nanosBetweenTokens
        1
      } else {
        // Ok, no choice, do the slow integer division
        val tokensArrived = timeElapsed / nanosBetweenTokens
        lastUpdate += tokensArrived * nanosBetweenTokens
        tokensArrived
      }
    } else 0

  availableTokens = math.min(availableTokens + tokensArrived, capacity)

  if (cost <= availableTokens) {
    availableTokens -= cost
    0
  } else {
    val remainingCost = cost - availableTokens
    // Tokens always arrive at exact multiples of the token generation period, we must account for that
    val timeSinceTokenArrival = now - lastUpdate
    val delay = remainingCost * nanosBetweenTokens - timeSinceTokenArrival
    availableTokens = 0
    lastUpdate = now + delay
    delay
  }
}
```

Ref: [Full source code](https://github.com/akka/akka/blob/master/akka-actor/src/main/scala/akka/util/TokenBucket.scala)

The code is quite straight forward, here's what we can see from the code:

- `TokenBucket` will not store actual message even it's called "Bucket", instead it just calculates delays for each incoming message
- `nanosBetweenTokens` will be used to calculate the ticks and delay
- `capacity` will decide how many messages can proceed without delay or how many ticks it needs to wait

### Hashed Wheel Timer Algorithm

Another interesting part is how it implements the scheduler while no blocking the working thread.

We can see it by dive deeper into `scheduleOnce`.

> This scheduler implementation is based on a revolving wheel of buckets, like Netty’s HashedWheelTimer, which it advances at a fixed tick rate and dispatches tasks it finds in the current bucket to their respective ExecutionContexts.

```scala
@volatile private var timerThread: Thread = threadFactory.newThread(new Runnable {

    var tick = startTick
    var totalTick: Long = tick // tick count that doesn't wrap around, used for calculating sleep time
    val wheel = Array.fill(WheelSize)(new TaskQueue)

    private def clearAll(): immutable.Seq[TimerTask] = {
      @tailrec def collect(q: TaskQueue, acc: Vector[TimerTask]): Vector[TimerTask] = {
        q.poll() match {
          case null => acc
          case x    => collect(q, acc :+ x)
        }
      }
      (0 until WheelSize).flatMap(i => collect(wheel(i), Vector.empty)) ++ collect(queue, Vector.empty)
    }

    @tailrec
    private def checkQueue(time: Long): Unit = queue.pollNode() match {
      case null => ()
      case node =>
        node.value.ticks match {
          case 0 => node.value.executeTask()
          case ticks =>
            val futureTick = ((
              time - start + // calculate the nanos since timer start
              (ticks * tickNanos) + // adding the desired delay
              tickNanos - 1 // rounding up
            ) / tickNanos).toInt // and converting to slot number
            // tick is an Int that will wrap around, but toInt of futureTick gives us modulo operations
            // and the difference (offset) will be correct in any case
            val offset = futureTick - tick
            val bucket = futureTick & wheelMask
            node.value.ticks = offset
            wheel(bucket).addNode(node)
        }
        checkQueue(time)
    }

    override final def run(): Unit =
      try nextTick()
      catch {
        case t: Throwable =>
          log.error(t, "exception on LARS’ timer thread")
          stopped.get match {
            case null =>
              val thread = threadFactory.newThread(this)
              log.info("starting new LARS thread")
              try thread.start()
              catch {
                case e: Throwable =>
                  log.error(e, "LARS cannot start new thread, ship’s going down!")
                  stopped.set(Promise.successful(Nil))
                  clearAll()
              }
              timerThread = thread
            case p =>
              assert(stopped.compareAndSet(p, Promise.successful(Nil)), "Stop signal violated in LARS")
              p.success(clearAll())
          }
          throw t
      }

    @tailrec final def nextTick(): Unit = {
      val time = clock()
      val sleepTime = start + (totalTick * tickNanos) - time

      if (sleepTime > 0) {
        // check the queue before taking a nap
        checkQueue(time)
        waitNanos(sleepTime)
      } else {
        val bucket = tick & wheelMask
        val tasks = wheel(bucket)
        val putBack = new TaskQueue

        @tailrec def executeBucket(): Unit = tasks.pollNode() match {
          case null => ()
          case node =>
            val task = node.value
            if (!task.isCancelled) {
              if (task.ticks >= WheelSize) {
                task.ticks -= WheelSize
                putBack.addNode(node)
              } else task.executeTask()
            }
            executeBucket()
        }
        executeBucket()
        wheel(bucket) = putBack

        tick += 1
        totalTick += 1
      }
      stopped.get match {
        case null => nextTick()
        case p =>
          assert(stopped.compareAndSet(p, Promise.successful(Nil)), "Stop signal violated in LARS")
          p.success(clearAll())
      }
    }
  })

  timerThread.start()
}
```

Ref: [Full source code](https://github.com/akka/akka/blob/master/akka-actor/src/main/scala/akka/actor/LightArrayRevolverScheduler.scala)

The code is quite long, but we can still know the important part is:

- A singleton `timerThread` will be created to manage ticks
- `TaskHolder` contains the `Runnable` task and `ExecutionContext`, will be executed by the `timerThread`, so the real task is executed in specific `ExecutionContext`.

# Conclusion

- There is an Algorithm called Token bucket used for Rate limiting(traffic shaping)
- There is another Algorithm called Hashed wheel used for scheduling - More details can be found in this [paper](<[Paper](https://blog.acolyer.org/2015/11/23/hashed-and-hierarchical-timing-wheels/)>)
