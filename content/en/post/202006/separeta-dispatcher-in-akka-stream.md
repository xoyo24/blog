---
title: "Separate dispatcher for blocking call in Akka Stream"
date: 2020-05-10
# lastmod: 2017-08-31T15:43:48+08:00
draft: true
tags: ["preview", "English", "tag-2"]
categories: ["English"]
# author: "Michael Henderson"
# comment: false
# toc: false
# autoCollapseToc: true
---

## Introduction

Now so long after I change my job, I get the chance to work on improving performance on application using Akka stream to process event comes from Kafka.

<!--more-->

As I read from Akka document before, I always believe we must use separated dispatcher(thread pool) for blocking operations, like DB access. I think by removing blocking calls away from default dispatcher, we make it only handle non-blocking operations. Can make it more preferment.

While my colleague argued, if we run all the operation in a flow, the overall process time for one event won't change by running internal flow in other thread poll. It won't be too much difference if we make default dispatcher bigger.

As we can't really convince each other. we can only run test a again and again to see the difference. Here are some simple summary of these tests

1. Standard, running all operation in 1 thread.
2. High parallelism, 1 thread pool, 1 flow
   1. Run all operation in 1 flow
3. High parallelism, 1 thread pool,
   1. running all operation in 10 thread with 10 parallelism
4. High parallelism, 2 thread pool
   1. 10 parallelism, blocking thread pool 5, default pool 5

Result shows we will have better process time with 1 big default thread pool.

# Background

## time

## space

# Mantain

## Easier to read
