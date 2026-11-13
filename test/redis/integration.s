package main

import (
    "std.redis";
    "std.prelude"
)

func integration_checks() int {
    config, config_error := redis_test_options()
    if config_error != 0 {
        return config_error
    }

    c, e := std.redis.connect(config)
    if e.code != 0 {
        return 1
    }

    result := checks(c*)
    close_error := std.redis.close(c*)
    if result != 0 {
        return result
    }

    if close_error.code != 0 || std.redis.close(c*).code != 0 {
        return 2
    }

    bad_config := config
    bad_config.password = "wrong"
    bad, be := std.redis.connect(bad_config)
    if be.code != std.redis.error_server || !bad.closed {
        return 3
    }

    acl_config := config
    acl_config.username = "tester"
    acl_config.password = "acl-test-secret"
    acl_config.database = 1
    acl, ae := std.redis.connect(acl_config)
    if ae.code != 0 {
        return 4
    }

    std.redis.close(acl*)
    println("redis local integration: PASS")
    return 0
}

func checks(std.redis.connection* c) int {
    if std.redis.ping(c*).code != 0 {
        return 10
    }

    binary := "值\r\n" + std.redis.byte_string(0) + std.redis.byte_string(255)
    bound_args_1 := std.redis.set_options {}
    wrote, we := std.redis.set(c*, "键", binary, bound_args_1)
    if we.code != 0 || !wrote {
        return 11
    }

    value, ve := std.redis.get(c*, "键")
    if ve.code != 0 || !value.present || value.value != binary {
        return 12
    }

    missing, me := std.redis.get(c*, "missing")
    if me.code != 0 || missing.present {
        return 13
    }

    bound_args_2 := std.redis.set_options { nx: true }
    nx, ne := std.redis.set(c*, "键", "bad", bound_args_2)
    bound_args_3 := std.redis.set_options { xx: true }
    xx, xe := std.redis.set(c*, "missing", "bad", bound_args_3)
    if ne.code != 0 || nx || xe.code != 0 || xx {
        return 14
    }

    ex, exerr := std.redis.exists(c*, "键")
    if exerr.code != 0 || ex != 1 {
        return 15
    }

    expired, exp_e := std.redis.expire(c*, "键", 60)
    ttl, te := std.redis.ttl(c*, "键")
    if exp_e.code != 0 || !expired || te.code != 0 || ttl < 1 || ttl > 60 {
        return 16
    }

    persist, pe := std.redis.persist(c*, "键")
    if pe.code != 0 || !persist {
        return 17
    }

    kind, ke := std.redis.type(c*, "键")
    if ke.code != 0 || kind != "string" {
        return 18
    }

    deleted, de := std.redis.del(c*, "键")
    if de.code != 0 || deleted != 1 {
        return 19
    }

    h, he := std.redis.hset(c*, "hash", "field", binary)
    hv, hve := std.redis.hget(c*, "hash", "field")
    ha, hae := std.redis.hgetall(c*, "hash")
    hx, hxe := std.redis.hexists(c*, "hash", "field")
    hd, hde := std.redis.hdel(c*, "hash", "field")
    if he.code != 0 ||
        h != 1 ||
        hve.code != 0 ||
        !hv.present ||
        hv.value != binary ||
        hae.code != 0 ||
        ha.count != 3 ||
        hxe.code != 0 ||
        !hx ||
        hde.code != 0 ||
        hd != 1 {
        return 20
    }

    lp, lpe := std.redis.lpush(c*, "list", "a")
    rp, rpe := std.redis.rpush(c*, "list", "b")
    end_index := -1
    range, re := std.redis.lrange(c*, "list", 0, end_index)
    left, le := std.redis.lpop(c*, "list")
    right, r_e := std.redis.rpop(c*, "list")
    if lpe.code != 0 ||
        lp != 1 ||
        rpe.code != 0 ||
        rp != 2 ||
        re.code != 0 ||
        range.count != 3 ||
        le.code != 0 ||
        left.value != "a" ||
        r_e.code != 0 ||
        right.value != "b" {
        return 21
    }

    sa, sae := std.redis.sadd(c*, "set", binary)
    sm, sme := std.redis.sismember(c*, "set", binary)
    members, mse := std.redis.smembers(c*, "set")
    sr, sre := std.redis.srem(c*, "set", binary)
    if sae.code != 0 ||
        sa != 1 ||
        sme.code != 0 ||
        !sm ||
        mse.code != 0 ||
        members.count != 2 ||
        members.nodes[1].text != binary ||
        sre.code != 0 ||
        sr != 1 {
        return 22
    }

    if std.redis.multi(c*).code != 0 {
        return 23
    }

    bound_args_4 := []string { "SET", "tx", "one" }
    queued, qe := std.redis.execute(c*, bound_args_4)
    if qe.code != 0 || queued.nodes[0].text != "QUEUED" {
        return 24
    }

    done, done_e := std.redis.exec(c*)
    if done_e.code != 0 || done.nodes[0].kind != "array" || done.count != 2 {
        return 25
    }

    if std.redis.multi(c*).code != 0 {
        return 26
    }

    bound_args_5 := []string { "SET", "tx", "discarded" }
    discarded, dqe := std.redis.execute(c*, bound_args_5)
    if dqe.code != 0 || std.redis.discard(c*).code != 0 {
        return 27
    }

    tx, txe := std.redis.get(c*, "tx")
    if txe.code != 0 || tx.value != "one" {
        return 28
    }

    if std.redis.watch(c*, "tx").code != 0 {
        return 29
    }

    other_config, config_error := redis_test_options()
    if config_error != 0 {
        return config_error
    }

    other, oe := std.redis.connect(other_config)
    if oe.code != 0 {
        return 30
    }

    other_options := std.redis.set_options {}
    changed, ce := std.redis.set(other*, "tx", "two", other_options)
    std.redis.close(other*)
    if ce.code != 0 || !changed {
        return 31
    }

    if std.redis.multi(c*).code != 0 {
        return 32
    }

    bound_args_6 := []string { "GET", "tx" }
    q, q_e := std.redis.execute(c*, bound_args_6)
    aborted, abe := std.redis.exec(c*)
    if q_e.code != 0 || abe.code != 0 || aborted.nodes[0].kind != "null_array" {
        return 33
    }

    if std.redis.multi(c*).code != 0 {
        return 34
    }

    empty, eme := std.redis.exec(c*)
    if eme.code != 0 || empty.nodes[0].kind != "array" || empty.nodes[0].length != 0 {
        return 35
    }

    commands := []std.redis.command {
        std.redis.command { arguments: []string { "SET", "pipe", "one" } },
        std.redis.command { arguments: []string { "GET", "pipe" } },
        std.redis.command { arguments: []string { "NO_SUCH_REDIS_COMMAND" } },
        std.redis.command { arguments: []string { "PING" } }
    }
    batch, be := std.redis.pipeline(c*, commands)
    if be.code != 0 ||
        batch.count != 4 ||
        batch.replies[0].nodes[0].text != "OK" ||
        batch.replies[1].nodes[0].text != "one" ||
        batch.replies[2].nodes[0].kind != "error" ||
        batch.replies[3].nodes[0].text != "PONG" {
        return 36
    }

    if std.redis.ping(c*).code != 0 {
        return 37
    }

    if std.redis.multi(c*).code != 0 {
        return 38
    }

    bound_args_7 := []string { "SET", "wrongtype", "text" }
    q1, q1e := std.redis.execute(c*, bound_args_7)
    bound_args_8 := []string { "LPUSH", "wrongtype", "x" }
    q2, q2e := std.redis.execute(c*, bound_args_8)
    errors, ere := std.redis.exec(c*)
    if q1e.code != 0 || q2e.code != 0 || ere.code != 0 || errors.nodes[2].kind != "error" {
        return 39
    }

    if std.redis.watch(c*, "tx").code != 0 || std.redis.unwatch(c*).code != 0 {
        return 40
    }

    // Validate local options before I/O and preserve a reusable connection.
    invalid_options := std.redis.set_options { nx: true, xx: true }
    invalid, invalid_e := std.redis.set(c*, "key", "x", invalid_options)
    if invalid_e.code != std.redis.error_invalid || c.closed {
        return 41
    }

    ex_options := std.redis.set_options { ex_seconds: 60, nx: true }
    ex_ok, ex_e := std.redis.set(c*, "ex", "x", ex_options)
    px_options := std.redis.set_options { px_milliseconds: 60000, xx: true }
    px_ok, px_e := std.redis.set(c*, "ex", "y", px_options)
    if ex_e.code != 0 || !ex_ok || px_e.code != 0 || !px_ok {
        return 42
    }

    empty_options := std.redis.set_options {}
    empty_ok, empty_e := std.redis.set(c*, "empty", "", empty_options)
    empty_value, empty_ve := std.redis.get(c*, "empty")
    if empty_e.code != 0 || !empty_ok || empty_ve.code != 0 || !empty_value.present || empty_value.value != "" {
        return 43
    }

    big := "0123456789abcdef"
    n := 0
    while n < 12 {
        big = big + big
        n = n + 1
    }

    big_ok, big_e := std.redis.set(c*, "big", big, empty_options)
    big_value, big_ve := std.redis.get(c*, "big")
    if big_e.code != 0 || !big_ok || big_ve.code != 0 || big_value.value != big {
        return 44
    }

    if std.redis.multi(c*).code != 0 {
        return 45
    }

    typed := std.redis.ping(c*)
    if typed.code != std.redis.error_state || !c.in_multi {
        return 46
    }

    bad_command := []string { "NOT_A_COMMAND" }
    bad, bad_e := std.redis.execute(c*, bad_command)
    if bad_e.code != std.redis.error_server || !c.in_multi {
        return 47
    }

    aborted_error, aborted_e := std.redis.exec(c*)
    if aborted_e.code != std.redis.error_server || c.in_multi || std.redis.ping(c*).code != 0 {
        return 48
    }

    refused := []string { "CLIENT", "REPLY", "OFF" }
    refusal, refusal_e := std.redis.execute(c*, refused)
    if refusal_e.code != std.redis.error_state || c.closed {
        return 49
    }

    long_verb := "a"
    n = 0
    while n < 7 {
        long_verb = long_verb + long_verb
        n = n + 1
    }

    long_args := []string { long_verb }
    long_reply, long_e := std.redis.execute(c*, long_args)
    if long_e.code != std.redis.error_bounds || c.closed {
        return 50
    }

    if std.redis.ping(c*).code != 0 {
        return 51
    }

    return 0
}
