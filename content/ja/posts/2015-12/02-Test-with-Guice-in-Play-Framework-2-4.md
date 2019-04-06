---
title: PlayFramework2.4におけるDIのテスト方法
date: 2015-12-02 14:48:32
tags:
- Scala
- PlayFramework
- Test
- Guice
- Dependency Injection
categories: 
- Scala
---

少し前から ***[PlayFramework2.4][1]*** を使い始めて、いろいろ良い変化を感じました。その中でもPlay2.4では ***[Guice][3]*** を使って正式に ***[DI][2]*** 機能が導入されました。DIを導入するメリットの一つとしてテストにおけるモックが凄くシンプルに実装できる点があります。

今回は簡単なユーザー認証の例を通じて、自分の試行錯誤中に勉強した、PlayFramework2.4におけるDIのテスト方法を紹介したいと思います。

<!-- more -->

## DI機能を使っての実装

■ まず、データを取得するためのRepositoryのインタフェースの定義及び実装を行います。

<font color='grey'>※ テストで使わないので、実装は省略します。</font>

``` scala
case class User(username: String, password: String)

trait UserRepository {
  def resolve(username: String): Option[User]
}

class UserRepositoryOnJDBC extends UserRepository {
  def resolve(username: String) : Option[User] = {
    ...
  }
}
```

■ 次は、DI機能を使ってRepositoryを利用するServiceを作成します。（今回のテスト対象です）

<font color='grey'>※ 説明のため、セキュリティなどの問題は無視してください。</font>

``` scala
class AuthService @Inject()(userRepository: UserRepository) {
  def auth(user: User): Boolean = {
    userRepository.resolve(user.username) match {
      case Some(u) => u == user
      case None => false
    }
  }
}
```

■ DI機能を使ってServiceを利用するControllerを作成します。（今回のテスト対象です）

``` scala
class AuthController @Inject()(val authService: AuthService) extends Controller {
  val loginForm = Form(
    mapping(
      "username" -> nonEmptyText,
      "password" -> nonEmptyText
    )(User.apply)(User.unapply)
  )

  def login = Action { implicit request =>
    loginForm.bindFromRequest.fold(
      _ => BadRequest(),
      user => if(authService.auth(user)) {
        Ok()
      } else {
        Unauthorized()
      }
    )
  }
}
```

■ テストのためRouteを定義します。

``` scala
POST        /login               controllers.AuthController.login
```

■ 最後にModuleでRepositoryの実装クラスを指定します。

<font color='grey'>※ AuthServiceはインタフェースではないので、自動Injectできます。</font>

``` scala
class GuiceModule extends AbstractModule {
  def configure() = {
    bind(classOf[UserRepository]).to(classOf[UserRepositoryOnJDBC])
  }
}
```

## DI機能のテスト方法
ここからは***[specs2][4]*** を使って、上記の例のテストのしかたを紹介します。
では、実際のテストコードを見てみましょう。

■ Serviceのテスト

まず、一番シングルの例としてUserRepositoryをモック化、UserServiceをテストします。

``` scala
class UserServiceSpec extends Specification with Mockito {
  "UserService#auth" should {
    "ユーザー名、パスワードが正しいの場合、Trueを返す" in {
      // setup
      val testUser = User("user1", "password1")
      val userRepository = mock[UserRepository]
      userRepository.resolve("user1") returns testUser
      val userService = new UserService(userRepository)
      // execute & verify
      userService.auth(User("user1", "password1")) must beTrue
    }
  }
  ...
}
```

■ Controllerのテスト

Controllerをテストする際には、リクエストする必要があります。PlayFrameworkは幾つのツールを提供しています。

- ***FakeRequest***, ***call()***

これらを使えば、直接Actionをテストすることができます。Controllerの単体テストに使えます。

``` scala
class AuthControllerSpec extends Specification with Mockito {
  "AuthController" should {
    "ユーザー名、パスワードが正しいの場合、ログインできます" in {
      // setup
      val request = FakeRequest(POST, "/login").withFormUrlEncodedBody(
        "username" -> "user1",
        "password" -> "password"
      )
      val userService = mock[UserService]
      userService.auth(any) returns true
      val controller = new AuthController(userService)
      // execute
      val actual = call(controller.authenticate(),request)
      // verify
      status(actual) must equalTo(OK)
    }
  }
}
```

- ***WithApplication***, ***FakeApplication***, ***route()***

こちらを使えば、Actionを呼び出す代わりにRouterからテストできます。機能テストに使えます。
他にも ***WithServer***, ***WithBrowser***, ***PlaySpecification*** などのツールがありますが、DIのテストに特に関係ないので省略します。

<font color='grey'>※ 興味のある方は ***[Writing functional tests with specs2][5]*** でご確認ください。</font><br />

■ Guiceを使っての機能テスト

PlayFramework2.4ではGuiceを使ってDIを実装したアプリケーションに対して、***GuiceApplicationBuilder***、 ***GuiceInjectorBuilder*** の2つのBuilderを提供しています。テスト中にこの2つのクラスを使って、アプリケーションの環境、配置、或いは依存関係を直接設定できます。

<font color='grey'>※ 詳しい説明は ***[Testing With Guice][6]*** でご確認ください。</font><br />

``` scala
class MockUserRepository extends UserRepository {
  def resolve(username: String) : Option[User] = Some(
      User("user1", "password")
    )
}

class AuthControllerSpec extends Specification {
  val app: Application = new GuiceApplicationBuilder()
    .overrides(bind[UserRepository].to[MockUserRepository])
    .build()

  "AuthController" should {
    "ユーザー名、パスワードが正しいの場合、ログインできます" in new WithApplication(app) {
      val request = FakeRequest(POST, "/login").withFormUrlEncodedBody(
        "username" -> "user1",
        "password" -> "password"
      )
      val result = route(request).get
      status(result) must equalTo(OK)
    }
  }
}
```

## まとめ

  すごく基本の話ですが、以上となります。テストは成功のケースだけを書きましたが、他のケースも同じ書き方で簡単にできると思います。

  DI機能を導入することで、PlayFramework2.4がモジュール間の依存関係をなくし、単体テストも機能テストも簡単かつシンプルにできるようになりましたね。
  今やっているプロジェクトもPlay2.4をWebServiceポートとして使われて、複雑のロジックは別のレイヤーで隔離させています。Play2.4でロジックを簡単にモック化できるので楽です。

  最後まで読んでいただきありがとうございました。

[1]: https://www.playframework.com/documentation/2.4.x/Highlights24
[2]: https://ja.wikipedia.org/wiki/%E4%BE%9D%E5%AD%98%E6%80%A7%E3%81%AE%E6%B3%A8%E5%85%A5
[3]: https://www.playframework.com/documentation/2.4.x/ScalaDependencyInjection
[4]: https://www.playframework.com/documentation/2.4.x/ScalaTestingWithSpecs2
[5]: https://www.playframework.com/documentation/2.4.x/ScalaFunctionalTestingWithSpecs2
[6]: https://www.playframework.com/documentation/2.4.x/ScalaTestingWithGuice
