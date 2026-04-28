#ifndef S_SEED_TOKEN_H
#define S_SEED_TOKEN_H

#include <stdbool.h>
#include <stddef.h>

typedef enum token_type {
	TOKEN_EOF = 0,
	TOKEN_IDENTIFIER,
	TOKEN_NUMBER,
	TOKEN_STRING,

	TOKEN_FN,
	TOKEN_LET,
	TOKEN_PACKAGE,
	TOKEN_USE,
	TOKEN_AS,
	TOKEN_IF,
	TOKEN_ELSE,
	TOKEN_FOR,
	TOKEN_WHILE,
	TOKEN_RETURN,
	TOKEN_BREAK,
	TOKEN_CONTINUE,
	TOKEN_TRUE,
	TOKEN_FALSE,

	TOKEN_PLUS,
	TOKEN_MINUS,
	TOKEN_STAR,
	TOKEN_SLASH,
	TOKEN_BANG,
	TOKEN_ASSIGN,
	TOKEN_EQ,
	TOKEN_NE,
	TOKEN_AND_AND,
	TOKEN_OR_OR,
	TOKEN_LT,
	TOKEN_LE,
	TOKEN_GT,
	TOKEN_GE,

	TOKEN_LPAREN,
	TOKEN_RPAREN,
	TOKEN_LBRACKET,
	TOKEN_RBRACKET,
	TOKEN_LBRACE,
	TOKEN_RBRACE,
	TOKEN_COMMA,
	TOKEN_DOT,
	TOKEN_COLON,
	TOKEN_SEMICOLON,
} token_type;

typedef struct source_pos {
	size_t line;
	size_t column;
} source_pos;

typedef struct token {
	token_type type;
	char *lexeme;
	source_pos pos;
} token;

typedef struct token_vec {
	token *data;
	size_t len;
	size_t cap;
} token_vec;

struct compile_error;

void token_vec_init(token_vec *vec);
bool token_vec_push(token_vec *vec, token t);
void token_vec_free(token_vec *vec);

const char *token_type_name(token_type type);

bool lexer_scan(const char *source, token_vec *out_tokens, struct compile_error *err);

#endif