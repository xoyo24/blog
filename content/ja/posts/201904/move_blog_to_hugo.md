---
title: "ブログをHexoからHugoに移行し、多言語対応した"
date: 2019-04-07 00:00:00
draft: false
description: 個人ブログの基盤を「Hexo+Github Pages」から「Hugo＋Netlify」への切り替え、そして自前で多言語対応した話
tags:
- Blog
- Hugo
- Hexo
- Netlify
- Github Pages
- i18n
- HTML
- CSS
categories:
- Blog
featured_image: /images/hugo.png
# author: ""
---

# Why

数年前からブログを描き始めて、途中で途切れましがた、そろそろ再開しようと思って、心機一転して、見た目も中身もHugoに変えた。

特に変えないといけないな理由はないが、いくつかの要因があった。

- Hexoページ生成がちょっと遅いに対して、Hugoが早すぎる
- Hexoがjsベースに対して、HugoはGoで作られている、自分で色々いじりたいので、Goをついでに触れると思った
 
# Hugo
Hugo自体についての紹介は公式サイトから参考できるので、詳細は割愛しますが、一言というと「世界最速の静的サイトジェネレーター」。

https://gohugo.io/

# Theme

公式サイトのテーマ一覧ページに色々探します

https://themes.gohugo.io/

最終的にこちらのテーマをベースにつかいはじめた。

https://themes.gohugo.io/keepit/
https://themes.gohugo.io/hugo-theme-hello-friend/

# 多言語対応



