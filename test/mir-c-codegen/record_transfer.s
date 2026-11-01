package record_transfer_test

struct transfer_record {
    string label
    int[] payload
}

func transfer_records(transfer_record[] items) transfer_record[] {
    copied := []transfer_record{}
    i := 0
    for i < len(items) {
        copied.push(items[i])
        i = i + 1
    }
    return copied
}

func main() int {
    items := []transfer_record{}
    items.push(transfer_record { label: "kept", payload: int[]{42} })
    i := 0
    for i < 30 {
        items = transfer_records(items)
        record := items[0]
        if record.label != "kept" { return 1 }
        if len(record.payload) != 1 { return 2 }
        if record.payload[0] != 42 { return 3 }
        i = i + 1
    }
    return 0
}
