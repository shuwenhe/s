package src.runtime

var race_enabled = false
var race_read_count = 0
var race_write_count = 0

func race_enable() () { race_enabled = true }
func race_disable() () { race_enabled = false }
func race_is_enabled() bool { race_enabled }

func race_read(int address, int size) () {
    if race_enabled {
        race_read_count = race_read_count + 1
        runtime_race_read(address, size)
    }
}

func race_write(int address, int size) () {
    if race_enabled {
        race_write_count = race_write_count + 1
        runtime_race_write(address, size)
    }
}

func race_reads() int { race_read_count }
func race_writes() int { race_write_count }

func race_unit_name() string {
    "src/runtime/race"
}

func race_unit_ready() int {
    1
}
