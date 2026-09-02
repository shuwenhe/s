package src.runtime

import (
	"src/sync"
	"src/unsafe"
)

enum channel_status {
	ch_open = 0
	ch_closed = 1
	ch_recv_waiting = 2
	ch_send_waiting = 3
}

struct channel {
	element_size u64
	buffer u8[]
	buf_capacity i32
	buf_size i32
	buf_head i32
	buf_tail i32
	status channel_status
	recv_queue u64[]
	send_queue u64[]
	recv_lock sync.mutex
	send_lock sync.mutex
	close_lock sync.mutex
	recv_count u64
	send_count u64
	closed_count u64
}

struct channel_op {
	g u64
	data unsafe.pointer
	is_send bool
	is_close bool
}

func make_channel(element_size u64, buffer_size i32) (channel*, error) {
	if element_size == 0 {
		nil, "element size must be > 0"
	}

	ch := &channel{
		element_size: element_size,
		buffer: make(u8[], u64(buffer_size)*element_size),
		buf_capacity: buffer_size,
		buf_size: 0,
		buf_head: 0,
		buf_tail: 0,
		status: ch_open,
		recv_queue: make(u64[], 0),
		send_queue: make(u64[], 0),
		recv_count: 0,
		send_count: 0,
		closed_count: 0,
	}

	return ch, nil
}

func (ch channel*) send(data unsafe.pointer) error {
	if ch == nil {
		return "channel is nil"
	}

	ch.send_lock.lock()
	defer ch.send_lock.unlock()

	if ch.status == ch_closed {
		return "send on closed channel"
	}

	if ch.buf_size < ch.buf_capacity {
		copy_element_to_buffer(ch, data)
		ch.buf_size += 1
		ch.send_count += 1

		if len(ch.recv_queue) > 0 {
			receiver_g := ch.recv_queue[0]
			ch.recv_queue = ch.recv_queue[1:]
			wake_sroutine(receiver_g)
		}

		return nil
	}

	if ch.buf_capacity == 0 {
		if len(ch.recv_queue) > 0 {
			receiver_g := ch.recv_queue[0]
			ch.recv_queue = ch.recv_queue[1:]
			copy_element_to_g(receiver_g, data, ch.element_size)
			wake_sroutine(receiver_g)
			return nil
		}

		current_g := get_current_sroutine_id()
		ch.send_queue = append(ch.send_queue, current_g)
		ch.send_count += 1

		sleep_sroutine(current_g)

		return nil
	}

	current_g := get_current_sroutine_id()
	ch.send_queue = append(ch.send_queue, current_g)
	ch.send_count += 1

	sleep_sroutine(current_g)

	nil
}

func (ch channel*) recv() (unsafe.pointer, error) {
	if ch == nil {
		return nil, "channel is nil"
	}

	ch.recv_lock.lock()
	defer ch.recv_lock.unlock()

	if ch.buf_size > 0 {
		data := get_element_from_buffer(ch)
		ch.buf_size -= 1
		ch.recv_count += 1

		if len(ch.send_queue) > 0 {
			sender_g := ch.send_queue[0]
			ch.send_queue = ch.send_queue[1:]
			wake_sroutine(sender_g)
		}

		return data, nil
	}

	if ch.status == ch_closed {
		return nil, "recv on closed channel"
	}

	if ch.buf_capacity == 0 {
		if len(ch.send_queue) > 0 {
			sender_g := ch.send_queue[0]
			ch.send_queue = ch.send_queue[1:]

			receiver_g := get_current_sroutine_id()
			data := recv_element_from_g(receiver_g)
			wake_sroutine(sender_g)
			ch.recv_count += 1

			return data, nil
		}

		current_g := get_current_sroutine_id()
		ch.recv_queue = append(ch.recv_queue, current_g)
		ch.recv_count += 1

		sleep_sroutine(current_g)

		data := recv_element_from_g(current_g)
		return data, nil
	}

	current_g := get_current_sroutine_id()
	ch.recv_queue = append(ch.recv_queue, current_g)
	ch.recv_count += 1

	sleep_sroutine(current_g)

	get_element_from_buffer(ch), nil
}

func (ch channel*) close() error {
	if ch == nil {
		return "channel is nil"
	}

	ch.close_lock.lock()
	defer ch.close_lock.unlock()

	if ch.status == ch_closed {
		return "close of closed channel"
	}

	ch.status = ch_closed
	ch.closed_count += 1

	for _, g := range ch.recv_queue {
		wake_sroutine(g)
	}

	for _, g := range ch.send_queue {
		wake_sroutine(g)
	}

	ch.recv_queue = make(u64[], 0)
	ch.send_queue = make(u64[], 0)

	nil
}

func (ch channel*) len() i32 {
	return ch.buf_size
}

func (ch channel*) cap() i32 {
	return ch.buf_capacity
}

struct select_case {
	ch channel*
	data unsafe.pointer
	is_send bool
	is_default bool
}

struct select_result {
	chosen i32
	received_ok bool
}

func select_channels(cases select_case[]) select_result {
	result := select_result{chosen: -1, received_ok: false}

	for i := i32(0); i < i32(len(cases)); i += 1 {
		if cases[i].is_default {
			result.chosen = i
			return result
		}

		if cases[i].is_send {
			if cases[i].ch.buf_size < cases[i].ch.buf_capacity {
				result.chosen = i
				return result
			}
		} else {
			if cases[i].ch.buf_size > 0 {
				result.chosen = i
				result.received_ok = true
				return result
			}
		}
	}

	current_g := get_current_sroutine_id()

	for i := i32(0); i < i32(len(cases)); i += 1 {
		if cases[i].is_send {
			cases[i].ch.send_queue = append(cases[i].ch.send_queue, current_g)
		} else {
			cases[i].ch.recv_queue = append(cases[i].ch.recv_queue, current_g)
		}
	}

	sleep_sroutine(current_g)

	for i := i32(0); i < i32(len(cases)); i += 1 {
		if cases[i].is_send {
			if cases[i].ch.buf_size > 0 {
				result.chosen = i
				return result
			}
		} else {
			if cases[i].ch.buf_size > 0 {
				result.chosen = i
				result.received_ok = true
				return result
			}
		}
	}

	result
}

func copy_element_to_buffer(ch channel*, data unsafe.pointer) {
	offset := i64(ch.buf_tail) * i64(ch.element_size)
	dst := unsafe.pointer(u64(unsafe.pointer(ch.buffer)) + u64(offset))
	copy_memory(dst, data, ch.element_size)
	ch.buf_tail = (ch.buf_tail + 1) % ch.buf_capacity
}

func get_element_from_buffer(ch channel*) unsafe.pointer {
	offset := i64(ch.buf_head) * i64(ch.element_size)
	src := unsafe.pointer(u64(unsafe.pointer(ch.buffer)) + u64(offset))
	ch.buf_head = (ch.buf_head + 1) % ch.buf_capacity
	return src
}

func copy_element_to_g(g u64, data unsafe.pointer, size u64) {
}

func recv_element_from_g(g u64) unsafe.pointer {
	return nil
}

func copy_memory(dst unsafe.pointer, src unsafe.pointer, size u64) {
}

func wake_sroutine(g u64) {
}

func sleep_sroutine(g u64) {
}

func get_current_sroutine_id() u64 {
	return 0
}
