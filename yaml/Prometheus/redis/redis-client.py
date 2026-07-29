#!/usr/bin/env python
#coding:utf-8

import redis
import time
pool = redis.ConnectionPool(host="172.31.7.111",db=1, port=36379,password="123456")
r = redis.Redis(connection_pool=pool)
for i in range(1000):
    r.set("key%s" % i,"value%s"% i)
    #time.sleep(0.1)
    data=r.get("key%s" % i)
    print(data)
