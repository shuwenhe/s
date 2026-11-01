package runtime_record_probe

struct probe_record { string label }

func make_probe_record() probe_record {
    return probe_record { label: "retained" }
}

func read_probe_record(probe_record[] records) string {
    record := records[0]
    return record.label
}

func main() int {
    records := []probe_record{}
    record := make_probe_record()
    records.push(record)
    if read_probe_record(records) != "retained" { return 1 }
    return 0
}
