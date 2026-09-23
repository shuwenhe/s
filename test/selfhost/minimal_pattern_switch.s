package test

func test_pattern_switch(x) unit {
    switch x {
        status::ok(msg) : {
            msg
        }
        _ : {
            "default"
        }
    }
}
