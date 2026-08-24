#ifndef S_SEED_SROUTINE_ABI_H
#define S_SEED_SROUTINE_ABI_H

#define SROUTINE_ABI_VERSION 1

typedef enum sroutine_state {
	SROUTINE_IDLE = 0,
	SROUTINE_RUNNABLE = 1,
	SROUTINE_RUNNING = 2,
	SROUTINE_WAITING = 3,
	SROUTINE_DEAD = 4,
} sroutine_state;

typedef enum sroutine_park_reason {
	SROUTINE_PARK_NONE = 0,
	SROUTINE_PARK_CHANNEL = 1,
	SROUTINE_PARK_NETPOLL = 2,
	SROUTINE_PARK_TIMER = 3,
	SROUTINE_PARK_JOIN = 4,
} sroutine_park_reason;

static inline int sroutine_state_can_transition(sroutine_state from, sroutine_state to) {
	switch (from) {
	case SROUTINE_IDLE: return to == SROUTINE_RUNNABLE;
	case SROUTINE_RUNNABLE: return to == SROUTINE_RUNNING || to == SROUTINE_DEAD;
	case SROUTINE_RUNNING: return to == SROUTINE_RUNNABLE || to == SROUTINE_WAITING || to == SROUTINE_DEAD;
	case SROUTINE_WAITING: return to == SROUTINE_RUNNABLE || to == SROUTINE_DEAD;
	case SROUTINE_DEAD: return 0;
	}
	return 0;
}

#endif
