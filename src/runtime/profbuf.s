package src.runtime

struct profile_buffer {
    runtime_profile_sample[] samples
    int limit
    int dropped
}

func profile_buffer_new(int limit) profile_buffer {
    if limit < 1 {
        limit = 1
    }
    profile_buffer { samples: runtime_profile_sample[](), limit: limit, dropped: 0 }
}

func (profile_buffer* self) record(string name, int nanos) () {
    if len(self.samples) >= self.limit {
        self.dropped = self.dropped + 1
        return
    }
    self.samples.push(runtime_profile_sample { name: name, count: 1, nanos: nanos })
}

func (profile_buffer* self) snapshot() runtime_profile_sample[] {
    self.samples
}

func (profile_buffer* self) dropped_count() int { self.dropped }

func profbuf_unit_name() string {
    "src/runtime/profbuf"
}

func profbuf_unit_ready() int {
    1
}
