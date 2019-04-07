---
title: Create a LINE bot with Akka HTTP
date: 2016-12-25 20:35:20
tags:
- Scala
- Akka
- Akka HTTP
- LINE bot
- chat bot
categories: 
- Akka
---

最近Akka HTTPの正式版 **[X][Akka HTTP X release note]** がで出ましたね。
自分は前からAkka HTTPに興味があって、ちょうどいい機会なので、Akka HTTPを詳しく勉強するため、簡単のWebサービスを作ってみたいと思います。

<!-- more -->

# LINE Bot とは

> LINE が提供する Messaging API により、LINEのトーク画面を使った対話型Botアプリケーションの開発が可能になります。

具体的なやることは

- サーバのURLを LINE Bot アカウントと繋いています。
- ユーザがBotに対して、友たち追加、メッセージ送信などを行う際に、設定されたサーバにイベント情報が送られます。
- サーバがイベント情報を基づいて、LINE Messaging API経由でユーザに返信できます。

※ LINE アカウントの設定について、[LINEの公式ドキュメント][LINE api document]に記載されているので、割愛します。

# Akka HTTPについて

Akka HTTP は Akka Actor と Akka Stream をベースに作られた、HTTPサーバ／クライエント処理をサポートするためのツール、ライブラリです（[フレームワークではありません！][Akka HTTP philosophy]）。
主な特徴は、HTTP処理（HttpRequest => HttpResponse）をストリーム処理で実現によって、高い[パフォーマンス][Akka HTTP performance]を出せるようになっています。
そしてもう一つの特徴は、分かりやすいRoute DSLです。LINE botを作るには、Akka HTTP みたいなツールが丁度良いと思います。

# 今回作った Bot

今回は Akka HTTP の特性の紹介するため、一番シンプルな「受けたメッセージをそのまま返す」Botを例にして、Akka HTTP の特性を幾つか紹介したいと思います。

![line-bot.png](https://s27.postimg.org/vh77j8q7n/line_bot.png)

- JSON を変換する ((un)Marshalling)
- HTTP request を処理する(Server side)
- HTTP request を送る(Client side)
- サービスをテストする

最終のコードはこちらでたどり着けます: https://github.com/xoyo24/akka-http-line-bot

# TL;DR

## JSON を変換する ((un)Marshalling)

LINE Messaging API とのやりとりは全部JSONを扱っています。これに対して、Akka HTTP の特徴の一つは、(un)Marshalling 機構によって、JSON、 XML或いはバイナリデータを簡単サポート出来ます。
Akka HTTP では spray-json ベースのJson変換機構を用意しています。その使い方は以下になります。

> 1. spray-jsonモジュールを使ため、Dependencyに"akka-http-spray-json"を追加。
> 2. 次は、スコープ内に RootJsonFormat[T] を用意する。
> 3. 最後、Marshalling と Unmarshalling 機構を使うため、SprayJsonSupport を導入する。

#### RootJsonFormat を用意する方法が以下の2つのやり方があります。

- Case Class を直接変換する場合、要素の数に応じて、**jsonFormatX** メソッドを使えばいいです。

[Reply Message API][LINE API reference] の Send Message Object を JSON に変換するため、以下のjsonFormatが必要です。

```scala
case class TextMessage(`type`: String = "text", text: String)

case class Messages(replyToken: String, messages: List[TextMessage])

trait MessagesJsonSupport extends SprayJsonSupport with DefaultJsonProtocol {
  implicit val textMessageFormat = jsonFormat2(TextMessage)
  implicit val messageFormat = jsonFormat2(Messages)
}
```

- それ以外の場合、**RootJsonFormat[T]** を実装する必要があります。

Callback Event の Source の継承関係を表したい場合、以下のように自前の実装が必要になります。

```scala
trait Source {
  val `type`: String
}

case class UserSource(id: String) extends Source {
  override val `type`: String = "user"
}

case class GroupSource(id: String) extends Source {
  override val `type`: String = "group"
}

case class RoomSource(id: String) extends Source {
  override val `type`: String = "room"
}

trait SourceJsonSupport extends SprayJsonSupport with DefaultJsonProtocol {
  implicit object SourceFormat extends RootJsonFormat[Source] {
    def write(s: Source): JsValue = s match {
      case UserSource(id) => JsObject(
        "type" -> JsString(s.`type`),
        "userId" -> JsString(id)
      )
      case GroupSource(id) => JsObject(
        "type" -> JsString(s.`type`),
        "groupId" -> JsString(id)
      )
      case RoomSource(id) => JsObject(
        "type" -> JsString(s.`type`),
        "roomId" -> JsString(id)
      )
      case _ => serializationError(s"Unsupported Source Type '${s.`type`}' !")
    }

    def read(value: JsValue): Source =
      value.asJsObject.getFields("type", "userId", "groupId", "roomId") match {
        case Seq(JsString("user"), JsString(id)) => UserSource(id)
        case Seq(JsString("group"), JsString(id)) => GroupSource(id)
        case Seq(JsString("room"), JsString(id)) => RoomSource(id)
        case _ => deserializationError(s"Source expected")
      }
  }
}
```

※ 詳しい説明は [spray-json][spray-json] のドキュメントを参照してください。

#### spray-json 以外のJSONライブラリを使いたい場合

(un)Marshalling 機構の抽象化によって、JSON ライブラリの切り替えは簡単に出来るようになっています。
例えば jackson を使いたい場合、以下の用にUnmarshallerとMarshallerを定義すればいいです。

```scala
trait JacksonSupport {
  import JacksonSupport._

  private val jsonStringUnmarshaller =
    Unmarshaller.byteStringUnmarshaller
      .forContentTypes(`application/json`)
      .mapWithCharset {
        case (ByteString.empty, _) => throw Unmarshaller.NoContentException
        case (data, charset)       => data.decodeString(charset.nioCharset.name)
      }

  /**
    * HTTP entity => `A`
    */
  implicit def jacksonUnmarshaller[A](
      implicit ct: ClassTag[A],
      objectMapper: ObjectMapper = defaultObjectMapper
  ): FromEntityUnmarshaller[A] = {
    jsonStringUnmarshaller.map(
      data => objectMapper.readValue(data, ct.runtimeClass).asInstanceOf[A]
    )
  }

  /**
    * `A` => HTTP entity
    */
  implicit def jacksonToEntityMarshaller[Object](
      implicit objectMapper: ObjectMapper = defaultObjectMapper
  ): ToEntityMarshaller[Object] = {
    Jackson.marshaller[Object](objectMapper)
  }
}
```

※ 詳しいいコードはこちらのライブラリ[hseeberger/akka-http-json][akka-http-json] を参照してください。

## HTTP requestを処理する(Server side)

ユーザがLINE Botに対して、友たち追加、メッセージ送信などを行う際に、設定されたサーバにイベント情報が送られます。

HTTP サービスを実装するため、Akka HTTP は Low Level と High Level 二種類の API を提供しています。

### Low Level API

**Low Level API** は **akka-http-core** モジュールによって提供されて、ストリーム処理にみたいに、HTTP 処理を実装出来る APIです。
主に以下のスコープにフォーカスしています。

- コネクション管理
- メッセージやヘッダの変換処理
- Request とコネクションの Timeout 管理
- HTTP pipelining の Response ordering

今回は使わないですか、実際に使うと、こんな感じになります。

```scala
import akka.actor.ActorSystem
import akka.http.scaladsl.Http
import akka.http.scaladsl.model.HttpMethods._
import akka.http.scaladsl.model._
import akka.stream.ActorMaterializer
import akka.stream.scaladsl.Sink

implicit val system = ActorSystem()
implicit val materializer = ActorMaterializer()
implicit val executionContext = system.dispatcher

val serverSource = Http().bind(interface = "localhost", port = 8080)

val requestHandler: HttpRequest => HttpResponse = {
  case HttpRequest(GET, Uri.Path("/"), _, _, _) =>
    HttpResponse(entity = HttpEntity(
      ContentTypes.`text/html(UTF-8)`,
      "<html><body>Hello world!</body></html>"))

  case HttpRequest(GET, Uri.Path("/ping"), _, _, _) =>
    HttpResponse(entity = "PONG!")

  case HttpRequest(GET, Uri.Path("/crash"), _, _, _) =>
    sys.error("BOOM!")

  case r: HttpRequest =>
    r.discardEntityBytes() // important to drain incoming HTTP Entity stream
    HttpResponse(404, entity = "Unknown resource!")
}

val bindingFuture: Future[Http.ServerBinding] =
  serverSource.to(Sink.foreach { connection =>
    println("Accepted new connection from " + connection.remoteAddress)

    connection handleWithSyncHandler requestHandler
    // this is equivalent to
    // connection handleWith { Flow[HttpRequest] map requestHandler }
  }).run()
```

### High Level API

**High Level API** は **akka-http** モジュールによって提供されて、Low Level API では実装されてないルーティング機能を独自のDSLによってサポートし、分かりやすくHTTP 処理を実装出来る APIです。

今回のBotはこんなイメージで実装しています。

```scala
implicit val system = ActorSystem("LINE-bot")
implicit val materializer = ActorMaterializer()
implicit val ec = system.dispatcher

def routes: Route = {
  path("line" / "callback") {
    (post & entity(as[Events])) { request =>
      
      ...

      complete {
        "OK"
      }
    }
  }
}

Http().bindAndHandle(routes, config.getString("http.interface"), config.getInt("http.port"))
```

見た目の通り、今回は以下のDSL（Directives）を使いました。

- **path("line" / "callback")** はサービスのエンドポイントURLをフィルターします。
- **(post & entity(as[Events]))** は POST メソッドをマッチし、**Events** に変換出来るRequestをフィルターします。
- **complete** は処理成功（200コード）を表します。
- なお、フィルターされた Request は Rejection になって、エラーとしてかえします。

※ 詳しい説明は [High-level Server-Side API][Akka HTTP document] を参照してください。

#### 独自の Directive を作って、Signatureチェックする

LINE Bot を実装する際に、セキュリティのため、Signatureをチェックする必要があります。LINEの公式ドキュメントによると、

> リクエストの送信元がLINEであることを確認するために署名検証を行わなくてはなりません。
> 各リクエストには X-Line-Signature ヘッダが付与されています。
> X-Line-Signature ヘッダの値と、Request Body と Channel Secret から計算した Signature が同じものであることをリクエストごとに 必ず検証してください。
> 
> 検証は以下の手順で行います。
> 
> 1. Channel Secretを秘密鍵として、HMAC-SHA256アルゴリズムによりRequest Bodyのダイジェスト値を得る。
> 2. ダイジェスト値をBASE64エンコードした文字列が、Request Headerに付与されたSignatureと一致することを確認する。

Akka HTTP に既存の Directive を組み合わせることによって、チェック処理をシンプルに実装できます。

```scala
val channelSecret: String
val signatureVerifier: SignatureVerifier

def verifySignature: Directive0 =
  (headerValueByName("X-Line-Signature") & entity(as[String])).tflatMap {
    case (signature, body) if signatureVerifier.isValid(channelSecret, body, signature) => pass
    case _ => reject(ValidationRejection("Invalid signature"))
  }

def routes: Route = {
  (path("line" / "callback") & post & verifySignature & entity(as[Events])) { entity =>
    ...
    complete {
      "OK"
    }
  }
}
```

## HTTP request を送る(Client side)

ユーザに返信する場合、LINE の [Reply Message API](https://devdocs.line.me/ja/#reply-message) をアクセスで実現します。

他の HTTP API をアクセスするため、Akka HTTP は Connection-Level、Host-Level と Request-Level 三種類の API を提供しています。

### HTTP requestを作る

今回は以下のように、Reply Message の request を作っています。

```scala
val auth = headers.Authorization(OAuth2BearerToken(accessToken))
val content = Messages(
  replyToken = token,
  messages = List(TextMessage(text = message))
)

val request = RequestBuilding.Post(
  uri = "https://api.line.me/v2/bot/message/reply",
  content = content
).withHeaders(auth)
```

- Akka HTTPは、**Authorization** 機構を通じで、OAuth認証などをサポートしています。
- Akka HTTPでは、HTTP の body の型を HTTPEntity と呼びます。
- **HttpRequest** を直接実装するのもできますが、content を HTTPEntity に自動変換させるため、**RequestBuilding** を使いました。

### Connection-Level Client-Side API

HTTPコネクションを完全管理し、ストリーム方式で処理を実装できる、最も低レベルかつ柔軟性をもつAPIです。

```scala
val connectionFlow: Flow[HttpRequest, HttpResponse, Future[Http.OutgoingConnection]] =
  Http().outgoingConnectionHttps("api.line.me")
val responseFuture: Future[HttpResponse] =
  Source.single(request)
    .via(connectionFlow)
    .runWith(Sink.head)
```

こちらは基本一つの Request に対して一つの HTTP コネクションになっています、ストリーム処理が終わると、コネクションはクローズされます。

### Host-Level Client-Side API

HTTPコネクションの管理が不要、エンドポイント(url:port)毎にコネクションプールを作るAPIです。

```
val poolClientFlow = Http().cachedHostConnectionPoolHttps[Int]("api.line.me")
val responseFuture: Future[(Try[HttpResponse], Int)] =
  Source.single(request -> 42)
    .via(poolClientFlow)
    .runWith(Sink.head)
```

書き方は **Connection-Level Client-Side API** とほぼ同じです、変わったのは以下二箇所だけ、

- **Http().cachedHostConnectionPoolHttps()** を使うことで、"api.line.me"のアクセスする場合は、同じプールからコネクションを取得します。
- コネクションプールの使用によって、ResponseとRequestの順番が一致しない可能性が有るため、もう一つパラメーターが必要になります。今回の場合、順番は重要ではないので、固定で書いています。
- 設定ファイルから **akka.http.host-connection-pool** でコネクションプールを調整できます。

### Request-Level Client-Side API

こちらは一覧シンプルなAPIです。二種類の書き方があります。

#### Flow-base 方式

```scala
val poolClientFlow = Http().superPool[Int]()
val responseFuture: Future[(Try[HttpResponse], Int)] =
  Source.single(request -> 42)
    .via(poolClientFlow)
    .runWith(Sink.head)

```

- 上のAPIと似たような書き方、違うのはsuperPoolでエンドポイントを指定出来ないので、requestにフルなURIが必要になります。

#### Futrue-base 方式

こちらは今回の実装で使う、一番簡単なやり方です。

```scala
val responseFuture: Future[HttpResponse] = Http().singleRequest(request)
```

※ 詳しい説明は [Consuming HTTP-based Services (Client-Side)][Akka HTTP document] を参照してください。

## サービスをテストする

今回のプログランムはHerokuにデプロイしていますが、変更するたびに、確認のためデプロイし直さないといけないのは、ちょっと手間がかかります。その為、テストを追加いしたいと思います。
Akka HTTPは、**akka-http-testkit** モジュールによって、HTTP サービスを簡単にテスト出来るようにしました。

今回のBotはこんなイメージでテスト出来ます。

```scala
class EchoBotSpec
  extends FlatSpec
    with Matchers
    with ScalatestRouteTest
    with EventsJsonSupport
    with MockFactory {

  it should "reply text message as reveived" in {
    ...

    Post("/line/callback", body).withHeaders(header) ~> bot.routes ~> check {
      status shouldBe StatusCodes.OK
      responseAs[String] shouldBe "OK"
    }
  }
}
```

**REQUEST ~> ROUTE ~> check { ASSERTIONS }** の方式で Route をチェック出来ます。

チェック出来る項目につて、[Route TestKit][Akka HTTP document] を参照してください。

# おわり

今回はテキストベースのBotに必要のものを紹介しました。
後は、DBやAkka Presistenceを使えば、情報を保持出来るBotを作れるし、他の 3rd Party API に繋げば、いろんなサービスを提供することが出来ます。

[Akka HTTP X release note]:https://akka.io/news/2016/11/22/akka-http-10.0.0-released.html
[Akka HTTP document]:https://doc.akka.io/docs/akka-http/current/scala/http/
[Akka HTTP philosophy]:https://doc.akka.io/docs/akka-http/current/scala/http/introduction.html#philosophy
[Akka HTTP performance]:https://akka.io/news/2016/08/02/akka-2.4.9-RC1-released.html
[LINE api document]:https://developers.line.me/messaging-api/overview
[LINE API reference]:https://devdocs.line.me/ja/#reply-message
[spray-json]:https://github.com/spray/spray-json
[akka-http-json]:https://github.com/hseeberger/akka-http-json
