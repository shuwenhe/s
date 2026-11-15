package std.kafka
struct consumer_group_description {
    string group_id
    string state
    string protocol_type
    string protocol_name
    int member_count
    string[] member_ids
}
func consumer_build_describe(string client, int correlation, string group) (string,error) {
    if len(group) < 1 || len(group) > 255 { return "", failure(error_invalid, "DescribeGroups group ID") }
    w := _kc_header(client, correlation, 15, 1)
    put_int(w*, 1, 4)
    put_string(w*, group)
    return w.data, w.failure
}
func consumer_parse_describe(string data, string group) (consumer_group_description,error) {
    result := consumer_group_description {}
    c := new_cursor(data, 1048576)
    throttle := read_int(c*, 4)
    groups := read_int(c*, 4)
    status := read_int(c*, 2)
    result.group_id = read_string(c*, 255)
    result.state = read_string(c*, 32767)
    result.protocol_type = read_string(c*, 32767)
    result.protocol_name = read_string(c*, 32767)
    members := array_count(c*, 128, false)
    result.member_count = members
    i := 0
    while i < members && c.failure.code == 0 {
        id := read_string(c*, 32767)
        client := read_string(c*, 32767)
        host := read_string(c*, 32767)
        metadata := read_nullable(c*, 4, 1048576)
        assignment := read_nullable(c*, 4, 1048576)
        if id == "" || _kc_contains(result.member_ids, id) || !metadata.present || !assignment.present { return result, failure(error_protocol, "DescribeGroups member") }
        result.member_ids = append(result.member_ids, id)
        i = i + 1
    }
    problem := finished(c*)
    if problem.code != 0 { return consumer_group_description {}, problem }
    if throttle < 0 || groups != 1 || result.group_id != group { return result, failure(error_protocol, "DescribeGroups response identity") }
    return result, _kc_broker_error(status, "DescribeGroups error")
}
