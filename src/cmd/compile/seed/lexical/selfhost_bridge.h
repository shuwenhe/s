#ifndef S_SEED_SELFHOST_LEXER_BRIDGE_H
#define S_SEED_SELFHOST_LEXER_BRIDGE_H

#include "token.h"
#include "../error/error.h"

bool selfhost_lexer_scan(const char *source, token_vec *out_tokens, compile_error *err);

#endif
