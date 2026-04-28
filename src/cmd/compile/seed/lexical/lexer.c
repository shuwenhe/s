#include "token.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "../error/error.h"

static char *dup_slice(const char *s, size_t start, size_t end) {
	size_t n = end - start;
	char *out = (char *)malloc(n + 1);
	if (!out) {
		return NULL;
	}
	memcpy(out, s + start, n);
	out[n] = '\0';
	return out;
}

void token_vec_init(token_vec *vec) {
	vec->data = NULL;
	vec->len = 0;
	vec->cap = 0;
}

bool token_vec_push(token_vec *vec, token t) {
	if (vec->len == vec->cap) {
		size_t next_cap = (vec->cap == 0) ? 16 : vec->cap * 2;
		token *next_data = (token *)realloc(vec->data, next_cap * sizeof(token));
		if (!next_data) {
			return false;
		}
		vec->data = next_data;
		vec->cap = next_cap;
	}
	vec->data[vec->len++] = t;
	return true;
}

void token_vec_free(token_vec *vec) {
	size_t i;
	for (i = 0; i < vec->len; i++) {
		free(vec->data[i].lexeme);
	}
	free(vec->data);
	vec->data = NULL;
	vec->len = 0;
	vec->cap = 0;
}

const char *token_type_name(token_type type) {
	switch (type) {
		case TOKEN_EOF: return "EOF";
		case TOKEN_IDENTIFIER: return "IDENTIFIER";
		case TOKEN_NUMBER: return "NUMBER";
		case TOKEN_STRING: return "STRING";
		case TOKEN_FN: return "FN";
		case TOKEN_LET: return "LET";
		case TOKEN_PACKAGE: return "PACKAGE";
		case TOKEN_USE: return "USE";
		case TOKEN_AS: return "AS";
		case TOKEN_IF: return "IF";
		case TOKEN_ELSE: return "ELSE";
		case TOKEN_FOR: return "FOR";
		case TOKEN_WHILE: return "WHILE";
		case TOKEN_RETURN: return "RETURN";
		case TOKEN_BREAK: return "BREAK";
		case TOKEN_CONTINUE: return "CONTINUE";
		case TOKEN_TRUE: return "TRUE";
		case TOKEN_FALSE: return "FALSE";
		case TOKEN_PLUS: return "+";
		case TOKEN_MINUS: return "-";
		case TOKEN_STAR: return "*";
		case TOKEN_SLASH: return "/";
		case TOKEN_BANG: return "!";
		case TOKEN_ASSIGN: return "=";
		case TOKEN_EQ: return "==";
		case TOKEN_NE: return "!=";
		case TOKEN_AND_AND: return "&&";
		case TOKEN_OR_OR: return "||";
		case TOKEN_LT: return "<";
		case TOKEN_LE: return "<=";
		case TOKEN_GT: return ">";
		case TOKEN_GE: return ">=";
		case TOKEN_LPAREN: return "(";
		case TOKEN_RPAREN: return ")";
		case TOKEN_LBRACE: return "{";
		case TOKEN_RBRACE: return "}";
		case TOKEN_COMMA: return ",";
		case TOKEN_DOT: return ".";
		case TOKEN_SEMICOLON: return ";";
		default: return "UNKNOWN";
	}
}

static token_type keyword_or_identifier(const char *lexeme) {
	if (strcmp(lexeme, "fn") == 0) return TOKEN_FN;
	if (strcmp(lexeme, "func") == 0) return TOKEN_FN;
	if (strcmp(lexeme, "let") == 0) return TOKEN_LET;
	if (strcmp(lexeme, "var") == 0) return TOKEN_LET;
	if (strcmp(lexeme, "package") == 0) return TOKEN_PACKAGE;
	if (strcmp(lexeme, "use") == 0) return TOKEN_USE;
	if (strcmp(lexeme, "as") == 0) return TOKEN_AS;
	if (strcmp(lexeme, "if") == 0) return TOKEN_IF;
	if (strcmp(lexeme, "else") == 0) return TOKEN_ELSE;
	if (strcmp(lexeme, "for") == 0) return TOKEN_FOR;
	if (strcmp(lexeme, "while") == 0) return TOKEN_WHILE;
	if (strcmp(lexeme, "return") == 0) return TOKEN_RETURN;
	if (strcmp(lexeme, "break") == 0) return TOKEN_BREAK;
	if (strcmp(lexeme, "continue") == 0) return TOKEN_CONTINUE;
	if (strcmp(lexeme, "true") == 0) return TOKEN_TRUE;
	if (strcmp(lexeme, "false") == 0) return TOKEN_FALSE;
	return TOKEN_IDENTIFIER;
}

static bool push_simple(token_vec *out, token_type t, const char *lexeme, size_t line, size_t col) {
	token tok;
	tok.type = t;
	tok.lexeme = dup_slice(lexeme, 0, strlen(lexeme));
	tok.pos.line = line;
	tok.pos.column = col;
	if (!tok.lexeme) {
		return false;
	}
	if (!token_vec_push(out, tok)) {
		free(tok.lexeme);
		return false;
	}
	return true;
}

bool lexer_scan(const char *source, token_vec *out_tokens, struct compile_error *err) {
	size_t i = 0;
	size_t line = 1;
	size_t col = 1;

	token_vec_init(out_tokens);
	error_clear(err);

	while (source[i] != '\0') {
		char c = source[i];
		size_t tok_line = line;
		size_t tok_col = col;

		if (c == ' ' || c == '\t' || c == '\r') {
			i++;
			col++;
			continue;
		}
		if (c == '\n') {
			i++;
			line++;
			col = 1;
			continue;
		}

		if (c == '/' && source[i + 1] == '/') {
			i += 2;
			col += 2;
			while (source[i] != '\0' && source[i] != '\n') {
				i++;
				col++;
			}
			continue;
		}

		if (c == '/' && source[i + 1] == '*') {
			i += 2;
			col += 2;
			while (source[i] != '\0') {
				if (source[i] == '*' && source[i + 1] == '/') {
					i += 2;
					col += 2;
					break;
				}
				if (source[i] == '\n') {
					i++;
					line++;
					col = 1;
					continue;
				}
				i++;
				col++;
			}
			if (source[i] == '\0') {
				error_set(err, ERR_SYNTAX, tok_line, tok_col, "unterminated block comment");
				token_vec_free(out_tokens);
				return false;
			}
			continue;
		}

		if (isalpha((unsigned char)c) || c == '_') {
			size_t start = i;
			while (isalnum((unsigned char)source[i]) || source[i] == '_') {
				i++;
				col++;
			}
			{
				token tok;
				char *lx = dup_slice(source, start, i);
				if (!lx) {
					error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
					token_vec_free(out_tokens);
					return false;
				}
				tok.type = keyword_or_identifier(lx);
				tok.lexeme = lx;
				tok.pos.line = tok_line;
				tok.pos.column = tok_col;
				if (!token_vec_push(out_tokens, tok)) {
					free(lx);
					error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
					token_vec_free(out_tokens);
					return false;
				}
			}
			continue;
		}

		if (isdigit((unsigned char)c)) {
			size_t start = i;
			while (isdigit((unsigned char)source[i])) {
				i++;
				col++;
			}
			{
				token tok;
				tok.type = TOKEN_NUMBER;
				tok.lexeme = dup_slice(source, start, i);
				tok.pos.line = tok_line;
				tok.pos.column = tok_col;
				if (!tok.lexeme || !token_vec_push(out_tokens, tok)) {
					free(tok.lexeme);
					error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
					token_vec_free(out_tokens);
					return false;
				}
			}
			continue;
		}

		if (c == '"') {
			size_t start;
			i++;
			col++;
			start = i;
			while (source[i] != '\0' && source[i] != '"' && source[i] != '\n') {
				if (source[i] == '\\' && source[i + 1] != '\0' && source[i + 1] != '\n') {
					i += 2;
					col += 2;
					continue;
				}
				i++;
				col++;
			}
			if (source[i] != '"') {
				error_set(err, ERR_UNTERMINATED_STRING, tok_line, tok_col, "unterminated string literal");
				token_vec_free(out_tokens);
				return false;
			}
			{
				token tok;
				tok.type = TOKEN_STRING;
				tok.lexeme = dup_slice(source, start, i);
				tok.pos.line = tok_line;
				tok.pos.column = tok_col;
				if (!tok.lexeme || !token_vec_push(out_tokens, tok)) {
					free(tok.lexeme);
					error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
					token_vec_free(out_tokens);
					return false;
				}
			}
			i++;
			col++;
			continue;
		}

		if (c == '=' && source[i + 1] == '=') {
			if (!push_simple(out_tokens, TOKEN_EQ, "==", tok_line, tok_col)) {
				error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
				token_vec_free(out_tokens);
				return false;
			}
			i += 2;
			col += 2;
			continue;
		}
		if (c == '!' && source[i + 1] == '=') {
			if (!push_simple(out_tokens, TOKEN_NE, "!=", tok_line, tok_col)) {
				error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
				token_vec_free(out_tokens);
				return false;
			}
			i += 2;
			col += 2;
			continue;
		}
		if (c == '<' && source[i + 1] == '=') {
			if (!push_simple(out_tokens, TOKEN_LE, "<=", tok_line, tok_col)) {
				error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
				token_vec_free(out_tokens);
				return false;
			}
			i += 2;
			col += 2;
			continue;
		}
		if (c == '>' && source[i + 1] == '=') {
			if (!push_simple(out_tokens, TOKEN_GE, ">=", tok_line, tok_col)) {
				error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
				token_vec_free(out_tokens);
				return false;
			}
			i += 2;
			col += 2;
			continue;
		}

		if (c == '&' && source[i + 1] == '&') {
			if (!push_simple(out_tokens, TOKEN_AND_AND, "&&", tok_line, tok_col)) {
				error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
				token_vec_free(out_tokens);
				return false;
			}
			i += 2;
			col += 2;
			continue;
		}
		if (c == '|' && source[i + 1] == '|') {
			if (!push_simple(out_tokens, TOKEN_OR_OR, "||", tok_line, tok_col)) {
				error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
				token_vec_free(out_tokens);
				return false;
			}
			i += 2;
			col += 2;
			continue;
		}

		switch (c) {
			case '+': if (!push_simple(out_tokens, TOKEN_PLUS, "+", tok_line, tok_col)) goto oom; break;
			case '-': if (!push_simple(out_tokens, TOKEN_MINUS, "-", tok_line, tok_col)) goto oom; break;
			case '*': if (!push_simple(out_tokens, TOKEN_STAR, "*", tok_line, tok_col)) goto oom; break;
			case '/': if (!push_simple(out_tokens, TOKEN_SLASH, "/", tok_line, tok_col)) goto oom; break;
			case '!': if (!push_simple(out_tokens, TOKEN_BANG, "!", tok_line, tok_col)) goto oom; break;
			case '=': if (!push_simple(out_tokens, TOKEN_ASSIGN, "=", tok_line, tok_col)) goto oom; break;
			case '<': if (!push_simple(out_tokens, TOKEN_LT, "<", tok_line, tok_col)) goto oom; break;
			case '>': if (!push_simple(out_tokens, TOKEN_GT, ">", tok_line, tok_col)) goto oom; break;
			case '(': if (!push_simple(out_tokens, TOKEN_LPAREN, "(", tok_line, tok_col)) goto oom; break;
			case ')': if (!push_simple(out_tokens, TOKEN_RPAREN, ")", tok_line, tok_col)) goto oom; break;
			case '{': if (!push_simple(out_tokens, TOKEN_LBRACE, "{", tok_line, tok_col)) goto oom; break;
			case '}': if (!push_simple(out_tokens, TOKEN_RBRACE, "}", tok_line, tok_col)) goto oom; break;
			case ',': if (!push_simple(out_tokens, TOKEN_COMMA, ",", tok_line, tok_col)) goto oom; break;
			case '.': if (!push_simple(out_tokens, TOKEN_DOT, ".", tok_line, tok_col)) goto oom; break;
			case ';': if (!push_simple(out_tokens, TOKEN_SEMICOLON, ";", tok_line, tok_col)) goto oom; break;
			default:
				error_set(err, ERR_ILLEGAL_CHAR, tok_line, tok_col, "illegal character: %c", c);
				token_vec_free(out_tokens);
				return false;
		}
		i++;
		col++;
		continue;

oom:
		error_set(err, ERR_OUT_OF_MEMORY, tok_line, tok_col, "out of memory");
		token_vec_free(out_tokens);
		return false;
	}

	if (!push_simple(out_tokens, TOKEN_EOF, "", line, col)) {
		error_set(err, ERR_OUT_OF_MEMORY, line, col, "out of memory");
		token_vec_free(out_tokens);
		return false;
	}
	return true;
}