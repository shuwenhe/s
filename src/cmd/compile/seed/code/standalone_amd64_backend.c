#if !defined(__APPLE__) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif
#include <ctype.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include "target.h"
#include "../intermediate/array_type.h"
#define STANDALONE_MAX_INS 262144
#define STANDALONE_MAX_FUNCS 4096
#define STANDALONE_MAX_SLOTS 2048
#define STANDALONE_MAX_LITERALS 65536
#define STANDALONE_MAX_ARGS 6
#define STANDALONE_MAX_PENDING_ARGS 64
#define STANDALONE_TEXT_CAP 1024
typedef struct standalone_ins {
    bool discard_snapshot;
	char op[32];
	char result[STANDALONE_TEXT_CAP];
	char operand1[STANDALONE_TEXT_CAP];
	char operand2[STANDALONE_TEXT_CAP];
} standalone_ins;
typedef struct standalone_ir {
	standalone_ins ins[STANDALONE_MAX_INS];
	size_t len;
} standalone_ir;
typedef struct standalone_slot {
	char name[STANDALONE_TEXT_CAP];
	char reg[8];
	int offset;
} standalone_slot;
typedef struct standalone_function {
	char name[STANDALONE_TEXT_CAP];
	size_t begin;
	size_t end;
	standalone_slot *slots;
	size_t slot_count;
	size_t slot_capacity;
	int frame_size;
	bool integer_only;
    bool region_safe;
    bool region_globals;
    unsigned long long readonly_params;
    bool region_loop_safe;
    unsigned long long *live_in;
    unsigned long long borrow_mask;
    int borrow_schema[64];
    int borrow_flow_state;
    bool borrow_owner_needed;
} standalone_function;
typedef struct standalone_literal {
	char encoded[STANDALONE_TEXT_CAP];
	unsigned char bytes[STANDALONE_TEXT_CAP];
	size_t len;
} standalone_literal;
typedef struct standalone_record_field {
    char name[STANDALONE_TEXT_CAP];
    char type[STANDALONE_TEXT_CAP];
    int kind, nested, name_literal;
} standalone_record_field;
typedef struct standalone_record_schema {
    char name[STANDALONE_TEXT_CAP];
    standalone_record_field *fields;
    size_t count;
    int type_literal, state, default_state;
} standalone_record_schema;
typedef struct standalone_global {
    char name[STANDALONE_TEXT_CAP],type[STANDALONE_TEXT_CAP],initializer[STANDALONE_TEXT_CAP];
} standalone_global;
typedef struct standalone_module {
    const standalone_ins **transfer_index;
    size_t transfer_count;
    standalone_global *globals;
    size_t global_count;
    size_t global_order[STANDALONE_MAX_SLOTS], global_order_count;
    bool fs_bridges[3];
	standalone_record_schema *records;
	size_t record_count;
	standalone_ir ir;
	standalone_function funcs[STANDALONE_MAX_FUNCS];
	size_t func_count;
	standalone_literal literals[STANDALONE_MAX_LITERALS];
	size_t literal_count;
} standalone_module;
static void copy_text(char *dst, size_t cap, const char *src) {
	if (!src) src = "";
	if (cap == 0) return;
	size_t i = 0;
	for (; i + 1 < cap && src[i] != '\0'; i++) dst[i] = src[i];
	dst[i] = '\0';
}
static bool split_ir_record(char *line, char *fields[4]) {
	size_t count = 0;
	char *read = line;
	char *write = line;
	fields[count++] = write;
	for (;;) {
		char ch = *read++;
		if (ch == '\\') {
			char escaped = *read++;
			if (escaped == '\0') return false;
			if (escaped == 'n') ch = '\n';
			else if (escaped == 'r') ch = '\r';
			else if (escaped == 't') ch = '\t';
			else ch = escaped;
			*write++ = ch;
			continue;
		}
		if (ch == '|') {
			if (count >= 4) return false;
			*write++ = '\0';
			fields[count++] = write;
			continue;
		}
		if (ch == '\0' || ch == '\n' || ch == '\r') {
			*write = '\0';
			break;
		}
		*write++ = ch;
	}
	return count == 4;
}
static bool load_ir(const char *path, standalone_ir *ir, compile_error *err) {
	FILE *fp = fopen(path, "rb");
	char *line = NULL;
	size_t cap = 0;
	ssize_t n;
	bool saw_header = false;
	ir->len = 0;
	if (!fp) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to open standalone IR input: %s", path);
		return false;
	}
	while ((n = getline(&line, &cap, fp)) >= 0) {
		char *fields[4];
		standalone_ins *ins;
		(void)n;
		if (!saw_header) {
			saw_header = true;
			if (strncmp(line, "SSEED-TARGET-V1", 15) != 0) {
				error_set(err, ERR_SEMANTIC, 1, 1, "invalid standalone IR header");
				free(line);
				fclose(fp);
				return false;
			}
			continue;
		}
		if (line[0] == '\0' || line[0] == '\n' || line[0] == '\r') continue;
		if (ir->len >= STANDALONE_MAX_INS || !split_ir_record(line, fields)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "invalid or oversized standalone IR");
			free(line);
			fclose(fp);
			return false;
		}
		ins = &ir->ins[ir->len++];
		copy_text(ins->op, sizeof(ins->op), fields[0]);
		copy_text(ins->result, sizeof(ins->result), fields[1]);
		copy_text(ins->operand1, sizeof(ins->operand1), fields[2]);
		copy_text(ins->operand2, sizeof(ins->operand2), fields[3]);
	}
	free(line);
	if (fclose(fp) != 0 || !saw_header) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed reading standalone IR input: %s", path);
		return false;
	}
	return true;
}
static int standalone_integer_base(const char *text) {
    const char *digits=text;
    if(*digits=='+' || *digits=='-') digits++;
    return digits[0]=='0' && (digits[1]=='x' || digits[1]=='X')?16:10;
}
static bool is_integer(const char *text) {
	char *end = NULL;
	if (!text || !*text) return false;
	errno = 0;
	(void)strtoll(text, &end, standalone_integer_base(text));
	return errno == 0 && end && *end == '\0';
}
static bool is_string_literal(const char *text) {
	size_t n = text ? strlen(text) : 0;
	return n >= 2 && text[0] == '"' && text[n - 1] == '"';
}
static bool is_value_variable(const char *text) {
	if (!text || !*text || strcmp(text, "_") == 0) return false;
	if (is_integer(text) || is_string_literal(text)) return false;
	if (strcmp(text, "true") == 0 || strcmp(text, "false") == 0) return false;
	if (text[0] == '[') return false;
	return true;
}
static void symbol_text(const char *name, char *out, size_t cap) {
	size_t used = 0;
	const unsigned char *p = (const unsigned char *)name;
	while (*p && used + 1 < cap) {
		unsigned char ch = *p++;
		out[used++] = (isalnum(ch) || ch == '_') ? (char)ch : '_';
	}
	out[used] = '\0';
}
static int slot_index(standalone_function *fn, const char *name, bool create) {
	size_t i;
	for (i = 0; i < fn->slot_count; i++) {
		if (strcmp(fn->slots[i].name, name) == 0) return (int)i;
	}
	if (!create || fn->slot_count >= STANDALONE_MAX_SLOTS) return -1;
	if (fn->slot_count == fn->slot_capacity) {
		size_t capacity = fn->slot_capacity ? fn->slot_capacity * 2 : 16;
		if (capacity > STANDALONE_MAX_SLOTS) capacity = STANDALONE_MAX_SLOTS;
		standalone_slot *slots = realloc(fn->slots, capacity * sizeof(*slots));
		if (!slots) return -1;
		fn->slots = slots;
		fn->slot_capacity = capacity;
	}
	memset(&fn->slots[fn->slot_count], 0, sizeof(*fn->slots));
	copy_text(fn->slots[fn->slot_count].name, sizeof(fn->slots[fn->slot_count].name), name);
	fn->slots[fn->slot_count].offset = -(int)((fn->slot_count + 1) * 8);
	return (int)fn->slot_count++;
}
static bool collect_operand(standalone_function *fn, const char *operand, compile_error *err) {
	if (is_value_variable(operand) && slot_index(fn, operand, true) < 0) {
		if (fn->slot_count >= STANDALONE_MAX_SLOTS)
			error_set(err, ERR_SEMANTIC, 0, 0, "too many standalone locals in %s", fn->name);
		else
			error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory allocating standalone locals in %s", fn->name);
		return false;
	}
	return true;
}
static bool parse_index_projection(const char *projection, char *index_out, size_t index_cap) {
	size_t n;
	if (!projection || strncmp(projection, "index(", 6) != 0) return false;
	n = strlen(projection);
	if (n < 8 || projection[n - 1] != ')') return false;
	if (n - 7 >= index_cap) return false;
	memcpy(index_out, projection + 6, n - 7);
	index_out[n - 7] = '\0';
	return index_out[0] != '\0';
}
static void assign_local_registers(standalone_module *m,standalone_function *fn) {
	static const char *regs[] = {"%r12", "%r13", "%r14", "%r15"};
	size_t i;
	size_t r=0;
	for (i = 0; i < fn->slot_count && r < sizeof(regs) / sizeof(regs[0]); i++) {
        bool global=false;
        for(size_t g=0;g<m->global_count;g++) if(!strcmp(m->globals[g].name,fn->slots[i].name)) global=true;
        if(global) continue;
		copy_text(fn->slots[i].reg, sizeof(fn->slots[i].reg), regs[r++]);
	}
}
static void detect_integer_only(standalone_module *module, standalone_function *fn) {
	size_t i;
	fn->integer_only = true;
    for(size_t g=0;g<module->global_count;g++) {
        for(size_t slot=0;slot<fn->slot_count;slot++) {
            if(!strcmp(module->globals[g].name,fn->slots[slot].name)) { fn->integer_only=false; return; }
        }
    }
	for (i = fn->begin; i < fn->end; i++) {
		standalone_ins *ins = &module->ir.ins[i];
		if (strcmp(ins->op, "PARAM") == 0 || strcmp(ins->op, "CALL") == 0 ||
			strcmp(ins->op, "READ") == 0 ||
			strcmp(ins->op, "INDEX_GET") == 0 || strcmp(ins->op, "INDEX_SET") == 0 ||
			is_string_literal(ins->result) || is_string_literal(ins->operand1) ||
			is_string_literal(ins->operand2)) {
			fn->integer_only = false;
			return;
		}
		if (strcmp(ins->op, "MOV") != 0 && strcmp(ins->op, "ADD") != 0 &&
			strcmp(ins->op, "SUB") != 0 && strcmp(ins->op, "MUL") != 0 &&
			strcmp(ins->op, "DIV") != 0 && strcmp(ins->op, "MOD") != 0 &&
			strcmp(ins->op, "BOR") != 0 && strcmp(ins->op, "BXOR") != 0 &&
			strncmp(ins->op, "CMP_", 4) != 0 && strcmp(ins->op, "JUMP") != 0 &&
			strcmp(ins->op, "JUMP_IF_FALSE") != 0 && strcmp(ins->op, "LABEL") != 0 &&
			strcmp(ins->op, "RET") != 0 && strcmp(ins->op, "NOP") != 0) {
			fn->integer_only = false;
			return;
		}
	}
}
static bool decode_literal(const char *encoded, standalone_literal *lit, compile_error *err) {
	size_t i;
	size_t n = strlen(encoded);
	lit->len = 0;
	copy_text(lit->encoded, sizeof(lit->encoded), encoded);
	for (i = 1; i + 1 < n; i++) {
		unsigned char ch = (unsigned char)encoded[i];
		if (ch == '\\' && i + 1 < n - 1) {
			unsigned char next = (unsigned char)encoded[++i];
			switch (next) {
			case 'n': ch = '\n'; break;
			case 'r': ch = '\r'; break;
			case 't': ch = '\t'; break;
			case '\\': ch = '\\'; break;
			case '"': ch = '"'; break;
			case '|': ch = '|'; break;
			default: ch = next; break;
			}
		}
		if (lit->len + 1 >= sizeof(lit->bytes)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "standalone string literal is too long");
			return false;
		}
		lit->bytes[lit->len++] = ch;
	}
	return true;
}
static int literal_index(standalone_module *module, const char *encoded, compile_error *err) {
	size_t i;
	for (i = 0; i < module->literal_count; i++) {
		if (strcmp(module->literals[i].encoded, encoded) == 0) return (int)i;
	}
	if (module->literal_count >= STANDALONE_MAX_LITERALS) {
		error_set(err, ERR_SEMANTIC, 0, 0, "too many standalone string literals");
		return -1;
	}
	if (!decode_literal(encoded, &module->literals[module->literal_count], err)) return -1;
	return (int)module->literal_count++;
}
static const char *runtime_callee(const char *name);
static const char *defined_function_name(const standalone_module *,const char *);
static int standalone_global_index(standalone_module *m,const char *name) {
    for(size_t i=0;i<m->global_count;i++) if(!strcmp(m->globals[i].name,name)) return (int)i;
    return -1;
}
/* Walk value operands, including array literals, without interpreting quoted
 * text as identifiers. Unknown names in the reserved namespace fail closed. */
static int standalone_next_global(standalone_module *m,const char **cursor) {
    bool quoted=false,escaped=false;
    for(const char *p=*cursor;*p;p++) {
        if(quoted) {
            if(escaped) escaped=false;
            else if(*p=='\\') escaped=true;
            else if(*p=='"') quoted=false;
            continue;
        }
        if(*p=='"') { quoted=true; continue; }
        if(*p!='$') continue;
        char name[STANDALONE_TEXT_CAP]; size_t n=strcspn(p,".[], ");
        if(n>=sizeof(name)) { *cursor=p+strlen(p); return -2; }
        memcpy(name,p,n); name[n]=0;
        if(!strncmp(name,"$global",7)) {
            *cursor=p+n;
            int g=standalone_global_index(m,name);
            return g<0?-2:g;
        }
        if(n) p+=n-1;
    }
    *cursor+=strlen(*cursor); return -1;
}
static bool standalone_collect_globals(standalone_module *m,compile_error *err) {
    bool inside=false;
    for(size_t i=0;i<m->ir.len;i++) {
        standalone_ins *x=&m->ir.ins[i];
        if(!strcmp(x->op,"FUNC_BEGIN")) inside=true;
        if(!strcmp(x->op,"FUNC_END")) inside=false;
        if(strcmp(x->op,"NOP") || strncmp(x->result,"global-slot:",12)) continue;
        const char *name=x->result+12;
        char initializer[STANDALONE_TEXT_CAP];
        if(inside || strncmp(name,"$global",7) || !name[7] || strspn(name+7,"0123456789")!=strlen(name+7) ||
           snprintf(initializer,sizeof(initializer),"$init%s",name)>=(int)sizeof(initializer) || strcmp(initializer,x->operand2) ||
           standalone_global_index(m,name)>=0 || m->global_count>=STANDALONE_MAX_SLOTS) {
            error_set(err,ERR_SEMANTIC,0,0,"invalid or duplicate native global at IR record %zu",i+2); return false;
        }
        standalone_global *next=realloc(m->globals,(m->global_count+1)*sizeof(*next));
        if(!next) { error_set(err,ERR_OUT_OF_MEMORY,0,0,"native global allocation failed"); return false; }
        m->globals=next;
        standalone_global *g=&m->globals[m->global_count++];
        copy_text(g->name,sizeof(g->name),name);
        copy_text(g->type,sizeof(g->type),x->operand1);
        copy_text(g->initializer,sizeof(g->initializer),x->operand2);
    }
    return true;
}
#include "standalone_records.h"
/* The legacy result helpers return an untyped two-word tuple. Native S
 * results are schema-bearing records and require an actual representation
 * bridge, not merely a declared return-type annotation. */
static int standalone_fs_bridge_kind(const char *runtime) {
    if(!runtime) return -1;
    if(!strcmp(runtime,"s_read_result")) return 0;
    if(!strcmp(runtime,"s_write_result")) return 1;
    if(!strcmp(runtime,"s_temp_result")) return 2;
    return -1;
}
static int standalone_fs_bridge_schema(standalone_module *m,int kind,compile_error *err) {
    const char *ok=kind==1?"()":"string";
    const char *name=kind==1?"std.result.result[(),std.fs.fs_error]":"std.result.result[string,std.fs.fs_error]";
    int result=standalone_record_index(m,name),error=standalone_record_index(m,"std.fs.fs_error");
    if(result<0 || error<0) return -1;
    standalone_record_schema *r=&m->records[result],*e=&m->records[error];
    if(r->count!=3 || e->count!=1 || strcmp(e->fields[0].name,"message") || strcmp(e->fields[0].type,"string")) return -1;
    const char *fields[]={"__variant","__payload_ok","__payload_err"};
    const char *types[]={"int",ok,"std.fs.fs_error"};
    for(size_t f=0;f<3;f++) {
        bool found=false;
        for(size_t j=0;j<r->count;j++) if(!strcmp(r->fields[j].name,fields[f]) && !strcmp(r->fields[j].type,types[f])) found=true;
        if(!found) return -1;
    }
    return standalone_validate_record_schema(m,result,err)?result:-1;
}
#include "standalone_borrows.h"
/* Initializers follow dependency order, including globals accessed through
 * helper calls. Cycles fail before assembly or output replacement. */
static bool standalone_order_global(standalone_module *,size_t,unsigned char *,unsigned char *,compile_error *);
static bool standalone_global_dependency(standalone_module *m,const char *value,unsigned char *states,unsigned char *seen,compile_error *err) {
    const char *cursor=value;
    for(;;) {
        int g=standalone_next_global(m,&cursor);
        if(g==-1) break;
        if(g<0) { error_set(err,ERR_SEMANTIC,0,0,"unknown native global operand"); return false; }
        if(!standalone_order_global(m,(size_t)g,states,seen,err)) return false;
    }
    return true;
}
static bool standalone_initializer_dependencies(standalone_module *m,standalone_function *fn,size_t owner,unsigned char *states,unsigned char *seen,compile_error *err) {
    size_t index=owner*m->func_count+(size_t)(fn-m->funcs);
    if(seen[index]) return true;
    seen[index]=1;
    const char *pending[64]; size_t argc=0;
    for(size_t i=fn->begin;i<fn->end;i++) {
        standalone_ins *x=&m->ir.ins[i];
        if(!strcmp(x->op,"NOP") || !strcmp(x->op,"LABEL") || !strcmp(x->op,"JUMP")) continue;
        const char *values[]={x->result,x->operand1,x->operand2};
        for(size_t v=0;v<3;v++) if(!standalone_global_dependency(m,values[v],states,seen,err)) return false;
        if(!strcmp(x->op,"ARG")) {
            if(argc==64) { error_set(err,ERR_SEMANTIC,0,0,"too many native initializer arguments"); return false; }
            pending[argc++]=x->result;
        }
        if(!strcmp(x->op,"CALL")) {
            char *end; long count=strtol(x->operand2,&end,10);
            if(*end || count<0 || (size_t)count>argc) { error_set(err,ERR_SEMANTIC,0,0,"invalid native initializer call"); return false; }
            size_t first=argc-(size_t)count;
            if(!strcmp(x->operand1,"__vec_len") || !strcmp(x->operand1,"__vec_push") || !strcmp(x->operand1,"__vec_set")) {
                char path[STANDALONE_TEXT_CAP];
                if(!count || !borrow_flow_literal(pending[first],path,sizeof(path),err) ||
                   !standalone_global_dependency(m,path,states,seen,err)) return false;
            }
            argc=first;
            standalone_function *callee=standalone_borrow_callee(m,x->operand1);
            if(callee && !standalone_initializer_dependencies(m,callee,owner,states,seen,err)) return false;
        }
    }
    return true;
}
static bool standalone_order_global(standalone_module *m,size_t g,unsigned char *states,unsigned char *all_seen,compile_error *err) {
    if(states[g]==2) return true;
    if(states[g]==1) { error_set(err,ERR_SEMANTIC,0,0,"cyclic native global initializer: %s",m->globals[g].name); return false; }
    states[g]=1;
    standalone_function *init=standalone_borrow_function(m,m->globals[g].initializer);
    if(!init || !standalone_initializer_dependencies(m,init,g,states,all_seen,err)) return false;
    states[g]=2; m->global_order[m->global_order_count++]=g;
    return true;
}
static bool standalone_order_globals(standalone_module *m,compile_error *err) {
    if(!m->global_count) return true;
    unsigned char *states=calloc(m->global_count,1),*seen=calloc(m->global_count*m->func_count,1);
    bool ok=states && seen;
    if(!ok) error_set(err,ERR_OUT_OF_MEMORY,0,0,"native initializer dependency allocation failed");
    for(size_t g=0;ok && g<m->global_count;g++) ok=standalone_order_global(m,g,states,seen,err);
    free(states); free(seen); return ok;
}
static bool analyze_module(standalone_module *module, compile_error *err) {
	size_t i;
	standalone_function *current = NULL;
	module->func_count = 0;
	module->literal_count = 0;
	if (!standalone_build_transfer_index(module, err)) return false;
	if (!standalone_collect_record_schemas(module, err) || !standalone_collect_globals(module,err)) return false;
	for (i = 0; i < module->ir.len; i++) {
		standalone_ins *ins = &module->ir.ins[i];
		const char *values[3] = {ins->result, ins->operand1, ins->operand2};
		size_t v;
		if (strcmp(ins->op, "FUNC_BEGIN") == 0) {
			if (module->func_count >= STANDALONE_MAX_FUNCS) {
				error_set(err, ERR_SEMANTIC, 0, 0, "too many standalone functions");
				return false;
			}
			current = &module->funcs[module->func_count++];
			memset(current, 0, sizeof(*current));
			copy_text(current->name, sizeof(current->name), ins->result);
			current->begin = i + 1;
			continue;
		}
		if (strcmp(ins->op, "FUNC_END") == 0) {
			if (!current) {
				continue;
			}
			current->end = i;
			assign_local_registers(module,current);
			detect_integer_only(module, current);
			current->frame_size = (int)((((current->slot_count + 4) * 8 + STANDALONE_MAX_PENDING_ARGS * 16 + 15) / 16) * 16) + 16;
			current = NULL;
			continue;
		}
		for (v = 0; v < 3; v++) {
			if (is_string_literal(values[v]) && literal_index(module, values[v], err) < 0) return false;
		}
		if (!current) continue;
        for(v=0;v<3;v++) {
            const char *cursor=values[v];
            for(;;) {
                int g=standalone_next_global(module,&cursor);
                if(g==-1) break;
                if(g<0) { error_set(err,ERR_SEMANTIC,0,0,"unknown native global at IR record %zu",i+2); return false; }
                if(!collect_operand(current,module->globals[g].name,err)) return false;
            }
        }
        if(!strcmp(ins->op,"UNIT")) {
            if(!is_value_variable(ins->result) || strchr(ins->result,'.') || strcmp(ins->operand1,"_") || strcmp(ins->operand2,"_")) {
                error_set(err,ERR_SEMANTIC,0,0,"invalid native unit constant at IR record %zu",i+2); return false;
            }
            if(!collect_operand(current,ins->result,err)) return false;
            continue;
        }
        if(!strcmp(ins->op,"TRAP")) {
            if(strcmp(ins->result,"101") || strcmp(ins->operand1,"_") || strcmp(ins->operand2,"_")) {
                error_set(err,ERR_SEMANTIC,0,0,"invalid native trap at IR record %zu",i+2); return false;
            }
            continue;
        }
		if (strcmp(ins->op, "LABEL") == 0 || strcmp(ins->op, "JUMP") == 0 ||
			strcmp(ins->op, "EXPORT") == 0 || strcmp(ins->op, "NOP") == 0) continue;
		if (strcmp(ins->op, "JUMP_IF_FALSE") == 0) {
			if (!collect_operand(current, ins->operand1, err)) return false;
			continue;
		}
		if (strcmp(ins->op, "ARRAY_NEW") == 0) {
			if (!seed_array_new_valid(ins->operand1, ins->operand2)) {
				error_set(err, ERR_SEMANTIC, 0, 0, "invalid ARRAY_NEW type or length");
				return false;
			}
			if (!collect_operand(current, ins->result, err)) return false;
			continue;
		}
		if (strcmp(ins->op, "CALL") == 0) {
			if (!collect_operand(current, ins->result, err)) return false;
			continue;
		}
		if (strcmp(ins->op, "READ") == 0) {
			char index_value[STANDALONE_TEXT_CAP];
			if (!parse_index_projection(ins->operand2, index_value, sizeof(index_value))) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unsupported standalone READ projection %s", ins->operand2);
				return false;
			}
			if (!collect_operand(current, ins->result, err) ||
				!collect_operand(current, ins->operand1, err) ||
				!collect_operand(current, index_value, err)) return false;
			continue;
		}
		if (strcmp(ins->op, "ARG") == 0 || strcmp(ins->op, "RET") == 0 || strcmp(ins->op, "PARAM") == 0) {
			if (!collect_operand(current, ins->result, err)) return false;
			continue;
		}
		if (!collect_operand(current, ins->result, err) ||
			!collect_operand(current, ins->operand1, err) ||
			!collect_operand(current, ins->operand2, err)) return false;
	}
	if (current) {
		error_set(err, ERR_SEMANTIC, 0, 0, "unterminated standalone function: %s", current->name);
		return false;
	}
	return module->func_count > 0 && standalone_validate_borrows(module, err) && standalone_validate_record_contracts(module, err) && standalone_order_globals(module,err);
}
static int find_literal(const standalone_module *module, const char *encoded) {
	size_t i;
	for (i = 0; i < module->literal_count; i++) {
		if (strcmp(module->literals[i].encoded, encoded) == 0) return (int)i;
	}
	return -1;
}
static bool is_array_literal(const char *value) {
	size_t length;
	if (!value) return false;
	length = strlen(value);
	return length >= 2 && value[0] == '[' && value[length - 1] == ']';
}
static bool emit_load(FILE *out, standalone_module *module, standalone_function *fn,
	const char *value, const char *reg, compile_error *err);
static bool emit_array_literal(FILE *out, standalone_module *module, standalone_function *fn,
	const char *value, const char *reg, compile_error *err) {
	const char *p;
	const char *start;
	const char *end = value + strlen(value) - 1;
	char item[STANDALONE_TEXT_CAP];
	char *trim_end;
	int count = 0;
	int depth;
	int in_string;
	long tagged_length;

	for (p = value + 1, start = p, depth = 0, in_string = 0; p <= end; p++) {
		int separator = p == end || (*p == ',' && !in_string && depth == 0);
		if (*p == '"' && (p == value + 1 || p[-1] != '\\')) in_string = !in_string;
		if (*p == '[' && !in_string) depth++;
		if (*p == ']' && !in_string && depth > 0) depth--;
		if (!separator) continue;
		if (p - start >= (long)sizeof(item)) {
			error_set(err, ERR_SEMANTIC, 0, 0, "array literal item too long in %s", fn->name);
			return false;
		}
		memcpy(item, start, (size_t)(p - start));
		item[p - start] = '\0';
		trim_end = item + strlen(item);
		while (trim_end > item && isspace((unsigned char)trim_end[-1])) *--trim_end = '\0';
		memmove(item, item + strspn(item, " \t\r\n"), strlen(item) + 1);
		if (item[0] != '\0') count++;
		start = p + 1;
	}

	tagged_length = (long)count * 2 + 1;
	fprintf(out, "    mov $%ld, %%rdi\n    call s_array_new\n", tagged_length);
	for (p = value + 1, start = p, depth = 0, in_string = 0, count = 0; p <= end; p++) {
		int separator = p == end || (*p == ',' && !in_string && depth == 0);
		if (*p == '"' && (p == value + 1 || p[-1] != '\\')) in_string = !in_string;
		if (*p == '[' && !in_string) depth++;
		if (*p == ']' && !in_string && depth > 0) depth--;
		if (!separator) continue;
		memcpy(item, start, (size_t)(p - start));
		item[p - start] = '\0';
		trim_end = item + strlen(item);
		while (trim_end > item && isspace((unsigned char)trim_end[-1])) *--trim_end = '\0';
		memmove(item, item + strspn(item, " \t\r\n"), strlen(item) + 1);
		if (item[0] != '\0') {
			if (is_string_literal(item) && literal_index(module, item, err) < 0) return false;
			fprintf(out, "    push %%rax\n");
			if (!emit_load(out, module, fn, item, "%rdx", err)) return false;
			fprintf(out, "    pop %%rax\n    mov %%rdx, %d(%%rax)\n", 16 + count * 8);
			count++;
		}
		start = p + 1;
	}
	if (strcmp(reg, "%rax") != 0) fprintf(out, "    mov %%rax, %s\n", reg);
	return true;
}
static const char *record_saved_regs[] = {"%rax", "%rcx", "%rdx", "%rsi", "%rdi", "%r8", "%r9", "%r10", "%r11"};
static void emit_record_save(FILE *out) {
    size_t i;
    for (i = 0; i < 9; i++) fprintf(out, "    push %s\n", record_saved_regs[i]);
    fprintf(out, "    mov %%rsp, %%r11\n    and $-16, %%rsp\n    sub $16, %%rsp\n    mov %%r11, (%%rsp)\n");
}
static bool emit_record_restore(FILE *out, const char *result_reg, compile_error *err) {
    int index = -1, i;
    if (result_reg) {
        for (i = 0; i < 9; i++) if (!strcmp(result_reg, record_saved_regs[i])) index = i;
        if (index < 0) { error_set(err, ERR_SEMANTIC, 0, 0, "invalid record result register: %s", result_reg); return false; }
        fprintf(out, "    mov (%%rsp), %%r11\n    mov %%rax, %d(%%r11)\n", (8-index)*8);
    }
    fprintf(out, "    mov (%%rsp), %%rsp\n");
    for (i = 8; i >= 0; i--) fprintf(out, "    pop %s\n", record_saved_regs[i]);
    return true;
}
static void emit_record_status(FILE *out) {
    /* Numeric local labels may be repeated safely in each helper sequence. */
    fprintf(out, "    test %%rdx, %%rdx\n    jz 1f\n    mov %%rdx, %%rdi\n    call s_record_error\n1:\n");
}
static bool emit_record_projection(FILE *out, standalone_module *m, standalone_function *fn,
    const char *path, const char *reg, bool store, compile_error *err) {
    char root[STANDALONE_TEXT_CAP], key[STANDALONE_TEXT_CAP];
    const char *dot = strchr(path, '.');
    size_t n = (size_t)(dot - path);
    memcpy(root, path, n); root[n] = 0;
    int slot = slot_index(fn, root, false);
    if (slot < 0 && standalone_global_index(m,root)<0) return false;
    int saved = -1, k;
    for (k = 0; k < 9; k++) if (!strcmp(reg, record_saved_regs[k])) saved = k;
    if (saved < 0) return false;
    emit_record_save(out);
    if(!emit_load(out,m,fn,root,"%rdi",err)) return false;
    const char *start = dot + 1;
    for (;;) {
        const char *next = strchr(start, '.');
        n = next ? (size_t)(next - start) : strlen(start);
        if (!n || n >= sizeof(key)) return false;
        memcpy(key, start, n); key[n] = 0;
        int literal = standalone_record_literal(m, key, err);
        if (literal < 0) return false;
        fprintf(out, "    lea .Ls_literal_%d(%%rip), %%rsi\n", literal);
        if (store && !next) {
            fprintf(out, "    mov (%%rsp), %%r11\n    mov %d(%%r11), %%rdx\n    call s_record_set\n", (8-saved)*8);
        } else fprintf(out, "    call s_record_get\n");
        emit_record_status(out);
        if (!next) break;
        fprintf(out, "    mov %%rax, %%rdi\n");
        start = next + 1;
    }
    return emit_record_restore(out, store ? NULL : reg, err);
}
static bool record_local_projection(standalone_module *m,standalone_function *fn, const char *path) {
    const char *dot = strchr(path, '.');
    char root[STANDALONE_TEXT_CAP];
    if (!dot || dot == path || (size_t)(dot-path) >= sizeof(root)) return false;
    memcpy(root, path, (size_t)(dot-path)); root[dot-path] = 0;
    return slot_index(fn, root, false) >= 0 || standalone_global_index(m,root)>=0;
}
static bool emit_load(FILE *out, standalone_module *module, standalone_function *fn,
	const char *value, const char *reg, compile_error *err) {
	int slot;
    int global=standalone_global_index(module,value);
    if(global>=0) { fprintf(out,"    mov .Ls_global_%d(%%rip), %s\n",global,reg); return true; }
	const char *dot;
	if (record_local_projection(module,fn, value)) return emit_record_projection(out, module, fn, value, reg, false, err);
	if (!value || !*value || strcmp(value, "_") == 0) {
		fprintf(out, "    mov $1, %s\n", reg);
		return true;
	}
	if (strcmp(value, "true") == 0) {
		fprintf(out, "    mov $3, %s\n", reg);
		return true;
	}
	if (strcmp(value, "false") == 0) {
		fprintf(out, "    mov $1, %s\n", reg);
		return true;
	}
	if (is_array_literal(value)) return emit_array_literal(out, module, fn, value, reg, err);
	if (is_integer(value)) {
		long long raw = strtoll(value, NULL, standalone_integer_base(value));
		fprintf(out, "    mov $%lld, %s\n", raw * 2 + 1, reg);
		return true;
	}
	if (is_string_literal(value)) {
		int literal = find_literal(module, value);
		if (literal < 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "missing standalone literal: %s", value);
			return false;
		}
		fprintf(out, "    lea .Ls_literal_%d(%%rip), %s\n", literal, reg);
		return true;
	}
	/* Struct and enum projections are lowered by the Seed IR as ordinary
	 * named slots (for example `result.__variant` and `result.value`).  The
	 * standalone backend must use those slots when they were collected.  A
	 * projection is not a pointer dereference: struct literals currently use
	 * the same flattened slot representation. */
	dot = strrchr(value, '.');
	if (dot != NULL && dot[1] != '\0') {
		slot = slot_index(fn, value, false);
		if (slot >= 0) {
			if (fn->slots[slot].reg[0] != '\0') fprintf(out, "    mov %s, %s\n", fn->slots[slot].reg, reg);
			else fprintf(out, "    mov %d(%%rbp), %s\n", fn->slots[slot].offset, reg);
			return true;
		}
		char base[STANDALONE_TEXT_CAP];
		size_t base_len = (size_t)(dot - value);
		if (base_len < sizeof(base)) {
			memcpy(base, value, base_len);
			base[base_len] = '\0';
			if (slot_index(fn, base, false) >= 0) {
				long offset = (strcmp(dot + 1, "__variant") == 0) ? 0 : 8;
				if (!emit_load(out, module, fn, base, "%r11", err)) return false;
				fprintf(out, "    mov %ld(%%r11), %s\n", offset, reg);
				return true;
			}
		}
	}
	slot = slot_index(fn, value, false);
	if (slot < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "unknown standalone value %s in %s", value, fn->name);
		return false;
	}
	if (fn->slots[slot].reg[0] != '\0') fprintf(out, "    mov %s, %s\n", fn->slots[slot].reg, reg);
	else fprintf(out, "    mov %d(%%rbp), %s\n", fn->slots[slot].offset, reg);
	return true;
}
static bool emit_store(FILE *out, standalone_module *module, standalone_function *fn, const char *name, const char *reg, compile_error *err) {
	int slot;
	if (!name || !*name || strcmp(name, "_") == 0) return true;
	int global=standalone_global_index(module,name);
    if(global>=0) { fprintf(out,"    mov %s, .Ls_global_%d(%%rip)\n",reg,global); return true; }
	if (record_local_projection(module,fn, name)) return emit_record_projection(out, module, fn, name, reg, true, err);
	slot = slot_index(fn, name, false);
	if (slot < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "unknown standalone destination %s in %s", name, fn->name);
		return false;
	}
	if (fn->slots[slot].reg[0] != '\0') fprintf(out, "    mov %s, %s\n", reg, fn->slots[slot].reg);
	else fprintf(out, "    mov %s, %d(%%rbp)\n", reg, fn->slots[slot].offset);
	return true;
}
static const char *runtime_callee(const char *name) {
    /* Keep validation and emission on the same intrinsic resolution path. */
    if (strstr(name, "env_get") != NULL) return "s_runtime_env_get";
	if (strstr(name, "env_get") != NULL) return "s_runtime_env_get";
	if (strstr(name, "__host_run_argv") != NULL) return "s_host_run_argv";
	const char *tail = strrchr(name, '.');
	if (tail != NULL) name = tail + 1;
	if (strcmp(name, "len") == 0 || strcmp(name, "__string_len") == 0 || strcmp(name, "__vec_len") == 0) return "s_value_len";
	if (strcmp(name, "host_args") == 0) return "s_host_args_value";
	if (strcmp(name, "__host_println") == 0) return "s_println_value";
	if (strcmp(name, "eprintln") == 0 || strcmp(name, "__host_eprintln") == 0) return "s_eprintln_value";
	if (strcmp(name, "char_at") == 0 || strcmp(name, "__host_char_at") == 0) return "s_string_char_at";
	if (strcmp(name, "byte_at") == 0 || strcmp(name, "__host_byte_at") == 0) return "s_string_byte_at";
	if (strcmp(name, "slice") == 0 || strcmp(name, "__host_slice") == 0) return "s_string_slice";
	if (strcmp(name, "__string_slice") == 0 || strcmp(name, "prelude_slice") == 0) return "s_string_slice";
	if (strcmp(name, "to_string") == 0) return "s_int_text";
	if (strcmp(name, "__host_byte_string") == 0) return "s_byte_string_value";
	if (strcmp(name, "__index_get") == 0) return "s_index_get";
	if (strcmp(name, "append") == 0 || strcmp(name, "__vec_push") == 0) return "s_array_append";
	if (strcmp(name, "__vec_set") == 0) return "s_index_set";
	if (strcmp(name, "__host_read_to_string") == 0) return "s_read_file_value";
	if (strcmp(name, "__host_read_source") == 0) return "s_read_source_value";
	if (strcmp(name, "__host_read_to_string_with_error") == 0) return "s_read_result";
	if (strcmp(name, "__host_write_text_file") == 0) return "s_write_file_value";
	if (strcmp(name, "__host_write_text_file_with_error") == 0) return "s_write_result";
	if (strcmp(name, "__host_make_temp_dir_with_error") == 0) return "s_temp_result";
	if (strcmp(name, "__host_make_executable") == 0) return "s_make_executable_value";
	if (strcmp(name, "runtime_env_get") == 0) return "s_runtime_env_get";
	if (strcmp(name, "env_get") == 0) return "s_runtime_env_get";
	if (strcmp(name, "buildcfg_goarch") == 0) return "s_buildcfg_goarch";
	if (strcmp(name, "__host_make_temp_dir_in") == 0) return "s_make_temp_dir_value";
	if (strcmp(name, "__host_same_file") == 0) return "s_host_same_file";
	if (strcmp(name, "__host_rename_file") == 0) return "s_host_rename_file";
	if (strcmp(name, "string") == 0) return "s_value_to_string";
	if (strcmp(name, "contains_text") == 0) return "s_contains_text";
	if (strcmp(name, "make") == 0) return "s_make_generic";
	return NULL;
}
static const char *defined_function_name(const standalone_module *module, const char *name) {
	const char *candidate = NULL;
	char suffix[STANDALONE_TEXT_CAP];
	char normalized[STANDALONE_TEXT_CAP];
	const char *p;
	const char *cursor;
	size_t i;
	for (i = 0; i < module->func_count; i++) {
		if (strcmp(module->funcs[i].name, name) == 0) return module->funcs[i].name;
	}
	/* Calls may use dotted package names while FUNC_BEGIN uses the
	 * assembler-safe spelling.  Compare the canonical symbol spelling too. */
	symbol_text(name, normalized, sizeof(normalized));
	for (i = 0; i < module->func_count; i++) {
		char fn_symbol[STANDALONE_TEXT_CAP];
		symbol_text(module->funcs[i].name, fn_symbol, sizeof(fn_symbol));
		if (strcmp(fn_symbol, normalized) == 0) return module->funcs[i].name;
	}
	/* Some compile-unit calls carry a package path, while the local
	 * declaration is intentionally unqualified.  Bind the basename only
	 * when it is unique. */
	{
		const char *base = strrchr(name, '.');
		if (base != NULL && base[1] != '\0') {
			candidate = NULL;
			for (i = 0; i < module->func_count; i++) {
				if (strcmp(module->funcs[i].name, base + 1) == 0) {
					if (candidate != NULL) return NULL;
					candidate = module->funcs[i].name;
				}
			}
			if (candidate != NULL) return candidate;
		}
	}
	/* Frontend calls may retain a package prefix while FUNC_BEGIN uses the local name. */
	cursor = name;
	while ((p = strchr(cursor, '_')) != NULL) {
		cursor = p + 1;
		if (*cursor != '\0' && strlen(cursor) < sizeof(suffix)) {
			copy_text(suffix, sizeof(suffix), cursor);
			candidate = NULL;
			for (i = 0; i < module->func_count; i++) {
				if (strcmp(module->funcs[i].name, suffix) == 0) {
					if (candidate) return NULL;
					candidate = module->funcs[i].name;
				}
			}
			if (candidate) return candidate;
		}
	}
	if (strcmp(name, "__result_is_ok") == 0) return "result[t,e]*.is_ok";
	if (strstr(name, "build_pipeline_from_text")) return "build_pipeline";
	if (strstr(name, "build_ssa_pipeline_with_graph_hints_and_margin")) return "build_pipeline_with_graph_hints_and_margin";
	if (strstr(name, "dump_ssa_pipeline")) return "dump_pipeline";
	if (strstr(name, "dump_ssa_debug_map")) return "dump_debug_map";
	if (strcmp(name, "__result_is_err") == 0) return "result[t,e]*.is_err";
	if (strstr(name, "_is_none") || strstr(name, ".is_none")) return "option[t]*.is_none";
	if (strstr(name, "_is_some") || strstr(name, ".is_some")) return "option[t]*.is_some";
	if (strstr(name, "_unwrap_err") || strstr(name, ".unwrap_err")) return "result[t,e]*.unwrap_err";
	if (strstr(name, "_unwrap") || strstr(name, ".unwrap"))
		return strstr(name, "result") ? "result[t,e]*.unwrap" : "option[t]*.unwrap";
	return NULL;
}
/* Runtime intrinsics reload operands at CALL emission. Their ARG snapshots
 * are unused, except vector item/index snapshots and generic stack arguments.
 * Match pending ARGs exactly as emit_function does, including nested calls. */
static void standalone_analyze_snapshot_uses(standalone_module *m) {
    for(size_t f=0;f<m->func_count;f++) {
        standalone_function *fn=&m->funcs[f];
        size_t pending[STANDALONE_MAX_PENDING_ARGS],count=0;
        for(size_t i=fn->begin;i<fn->end;i++) {
            standalone_ins *x=&m->ir.ins[i];
            if(!strcmp(x->op,"ARG")) {
                if(count<STANDALONE_MAX_PENDING_ARGS) pending[count++]=i;
                continue;
            }
            if(strcmp(x->op,"CALL")) continue;
            char *end; long argc=strtol(x->operand2,&end,10);
            if(*end || argc<0 || (size_t)argc>count) { count=0; continue; }
            size_t first=count-(size_t)argc;
            if(runtime_callee(x->operand1)) for(size_t a=0;a<(size_t)argc;a++) {
                bool consumed=a>=STANDALONE_MAX_ARGS;
                if(!strcmp(x->operand1,"__vec_push") && argc==2) consumed=a==1;
                if(!strcmp(x->operand1,"__vec_set") && argc==3) consumed=a!=0;
                m->ir.ins[pending[first+a]].discard_snapshot=!consumed;
            }
            count=first;
        }
    }
}
/* Regions may promote returned values and replaced global roots. In-place
 * writes into older globals and borrowed owners remain ineligible: evacuating
 * a root alone cannot repair a young edge inside an older object. */
static standalone_ins *standalone_arg_call(standalone_module *m,standalone_function *fn,size_t at) {
    size_t pending=1;
    for(size_t i=at+1;i<fn->end;i++) {
        standalone_ins *x=&m->ir.ins[i];
        if(!strcmp(x->op,"ARG")) pending++;
        if(strcmp(x->op,"CALL")) continue;
        char *end=NULL; long count=strtol(x->operand2,&end,10);
        if(!end || *end || count<0) return NULL;
        if((size_t)count>=pending) return x;
        pending-=(size_t)count;
    }
    return NULL;
}
static bool standalone_global_alias(standalone_module *m,standalone_function *fn,
                                    const bool *aliases,const char *place) {
    /* Inline array operands retain their elements' identity. A global inside
     * [global] is just as old as a bare global; quoted strings name no graph. */
    const char *p=place;
    while(*p) {
        if(*p=='"') {
            p++;
            while(*p && *p!='"') { if(*p=='\\' && p[1]) p++; p++; }
            if(*p) p++;
            continue;
        }
        if(!isalpha((unsigned char)*p) && *p!='_' && *p!='$') { p++; continue; }
        const char *start=p++;
        while(isalnum((unsigned char)*p) || *p=='_' || *p=='$' || *p=='.') p++;
        size_t length=(size_t)(p-start);
        for(size_t g=0;g<m->global_count;g++) {
            size_t n=strlen(m->globals[g].name);
            if(n<=length && !strncmp(start,m->globals[g].name,n) && (n==length || start[n]=='.')) return true;
        }
        for(size_t s=0;s<fn->slot_count;s++) if(aliases[s]) {
            size_t n=strlen(fn->slots[s].name);
            if(n<=length && !strncmp(start,fn->slots[s].name,n) && (n==length || start[n]=='.')) return true;
        }
    }
    return false;
}
static void standalone_analyze_regions(standalone_module *m) {
    for(size_t f=0;f<m->func_count;f++) {
        standalone_function *fn=&m->funcs[f];
        fn->region_safe=fn->borrow_mask==0;
        fn->region_globals=false;
        fn->region_loop_safe=true;
        /* READ exposes an element without snapshotting. Follow those aliases
         * conservatively so loop evacuation never strands a younger value in
         * an older parameter object. MOV, by contrast, snapshots aggregates. */
        bool older[STANDALONE_MAX_SLOTS]={false};
        bool global_aliases[STANDALONE_MAX_SLOTS]={false};
        for(size_t p=fn->begin;p<fn->end && !strcmp(m->ir.ins[p].op,"PARAM");p++) {
            int slot=slot_index(fn,m->ir.ins[p].result,false);
            if(slot>=0) older[slot]=true;
        }
        bool aliases_changed;
        do {
            aliases_changed=false;
            const char *pending[STANDALONE_MAX_PENDING_ARGS]; size_t pending_count=0;
            for(size_t i=fn->begin;i<fn->end;i++) {
                standalone_ins *x=&m->ir.ins[i];
                bool source_older=false, target_older=false;
                bool global_source=standalone_global_alias(m,fn,global_aliases,x->operand1);
                if(!strcmp(x->op,"ARG")) {
                    if(pending_count==STANDALONE_MAX_PENDING_ARGS) fn->region_safe=false;
                    else pending[pending_count++]=x->result;
                }
                if(!strcmp(x->op,"CALL")) {
                    char *end=NULL; long count=strtol(x->operand2,&end,10);
                    if(!end || *end || count<0 || (size_t)count>pending_count) { fn->region_safe=false; pending_count=0; }
                    else {
                        size_t first=pending_count-(size_t)count;
                        const char *runtime=runtime_callee(x->operand1);
                        if(count && runtime && !strcmp(runtime,"s_index_get")) global_source=standalone_global_alias(m,fn,global_aliases,pending[first]);
                        if(runtime && !strcmp(runtime,"s_array_append")) {
                            for(size_t a=first;a<pending_count;a++)
                                global_source|=standalone_global_alias(m,fn,global_aliases,pending[a]);
                        }
                        if(count && runtime && !strcmp(runtime,"s_index_set") && standalone_global_alias(m,fn,global_aliases,pending[first])) fn->region_safe=false;
                        pending_count=first;
                    }
                }
                if(global_source && (!strcmp(x->op,"READ") || !strcmp(x->op,"INDEX_GET") ||
                   (!strcmp(x->op,"CALL") && runtime_callee(x->operand1) &&
                    (!strcmp(runtime_callee(x->operand1),"s_index_get") || !strcmp(runtime_callee(x->operand1),"s_array_append"))))) {
                    int slot=slot_index(fn,x->result,false);
                    if(slot>=0 && !global_aliases[slot]) { global_aliases[slot]=true; aliases_changed=true; }
                }
                if(standalone_global_alias(m,fn,global_aliases,x->result) &&
                   ((!strcmp(x->op,"MOV") && strchr(x->result,'.')) || !strcmp(x->op,"INDEX_SET"))) fn->region_safe=false;
                /* Vector methods encode their receiver as quoted slot text,
                 * then mutate that slot without an explicit INDEX_SET/MOV. */
                standalone_literal receiver;
                const char *receiver_path=NULL;
                compile_error ignored;
                if(!strcmp(x->op,"ARG") && is_string_literal(x->result) &&
                   decode_literal(x->result,&receiver,&ignored) && receiver.len<sizeof(receiver.bytes)) {
                    receiver.bytes[receiver.len]=0;
                    receiver_path=(char *)receiver.bytes;
                    if(standalone_global_alias(m,fn,global_aliases,receiver_path) && standalone_global_index(m,receiver_path)<0) fn->region_safe=false;
                    for(size_t g=0;g<m->global_count;g++) {
                        size_t n=strlen(m->globals[g].name);
                        if(!strncmp(receiver_path,m->globals[g].name,n) &&
                           (!receiver_path[n] || receiver_path[n]=='.')) {
                            fn->region_globals=true;
                            standalone_ins *call=standalone_arg_call(m,fn,i);
                            if(receiver_path[n] || !call ||
                               (strcmp(call->operand1,"__vec_push") && strcmp(call->operand1,"__vec_len")))
                                fn->region_safe=false;
                        }
                    }
                }
                for(size_t v=0;v<fn->slot_count;v++) if(older[v]) {
                    size_t n=strlen(fn->slots[v].name);
                    if(receiver_path && !strncmp(receiver_path,fn->slots[v].name,n) &&
                       (!receiver_path[n] || receiver_path[n]=='.')) fn->region_loop_safe=false;
                    if(!strncmp(x->operand1,fn->slots[v].name,n) &&
                       (!x->operand1[n] || x->operand1[n]=='.')) source_older=true;
                    if(!strncmp(x->result,fn->slots[v].name,n) &&
                       (!x->result[n] || x->result[n]=='.')) target_older=true;
                }
                if((!strcmp(x->op,"READ") || !strcmp(x->op,"INDEX_GET")) && source_older) {
                    int slot=slot_index(fn,x->result,false);
                    if(slot>=0 && !older[slot]) { older[slot]=true; aliases_changed=true; }
                }
                if(target_older && ((!strcmp(x->op,"MOV") && strchr(x->result,'.')) ||
                                    !strcmp(x->op,"INDEX_SET"))) fn->region_loop_safe=false;
            }
        } while(aliases_changed);
        for(size_t s=0;s<fn->slot_count;s++)
            if(standalone_global_index(m,fn->slots[s].name)>=0) fn->region_globals=true;
        for(size_t i=fn->begin;i<fn->end;i++) {
            standalone_ins *x=&m->ir.ins[i];
            for(size_t g=0;g<m->global_count;g++) {
                size_t n=strlen(m->globals[g].name);
                if(!strncmp(x->result,m->globals[g].name,n) && (!x->result[n] || x->result[n]=='.') &&
                   ((!strcmp(x->op,"MOV") && x->result[n]=='.') || !strcmp(x->op,"INDEX_SET"))) fn->region_safe=false;
            }
            if(!strcmp(x->op,"ARG") && !strcmp(x->operand1,"mutable_borrow")) fn->region_safe=false;
            if(!strcmp(x->op,"CALL") && !runtime_callee(x->operand1) &&
               !defined_function_name(m,x->operand1)) fn->region_safe=false;
        }
    }
    bool changed;
    do {
        changed=false;
        for(size_t f=0;f<m->func_count;f++) {
            standalone_function *fn=&m->funcs[f];
            if(!fn->region_safe) continue;
            for(size_t i=fn->begin;i<fn->end;i++) {
                standalone_ins *x=&m->ir.ins[i];
                if(strcmp(x->op,"CALL") || runtime_callee(x->operand1)) continue;
                const char *target=defined_function_name(m,x->operand1);
                for(size_t c=0;target && c<m->func_count;c++)
                    if(!strcmp(m->funcs[c].name,target) && !m->funcs[c].region_safe) {
                        fn->region_safe=false; changed=true; break;
                    }
                    else if(!strcmp(m->funcs[c].name,target) && m->funcs[c].region_globals && !fn->region_globals) {
                        fn->region_globals=true; changed=true;
                    }
                if(!fn->region_safe) break;
            }
        }
    } while(changed);
}
#include "standalone_liveness.h"
#include "standalone_readonly.h"
/* Evacuate only slots live at the jump target. Array defaults clear dead
 * slots when reloaded, so discarded snapshots cannot become dangling roots. */
static void emit_region_loop(FILE *out,standalone_module *module,standalone_function *fn,const char *symbol,size_t at,size_t target) {
    size_t globals=fn->region_globals?module->global_count:0;
    fprintf(out,"    mov s_heap_current(%%rip), %%rax\n");
    fprintf(out,"    cmp -%d(%%rbp), %%rax\n    jb .Ls_%s_region_%zu\n",fn->frame_size-8,symbol,at);
    fprintf(out,"    mov $%zu, %%rdi\n    call s_array_new\n    test %%rax, %%rax\n    jnz 1f\n    mov $1, %%edi\n    call s_record_error\n1:\n",(fn->slot_count+globals)*2+1);
    size_t words=(fn->slot_count+63)/64;
    for(size_t s=0;s<fn->slot_count;s++) {
        if(standalone_global_index(module,fn->slots[s].name)>=0) continue;
        if(fn->live_in && !(fn->live_in[(target-fn->begin)*words+s/64] & (1ULL<<(s%64)))) continue;
        if(fn->slots[s].reg[0]) fprintf(out,"    mov %s, %%rcx\n",fn->slots[s].reg);
        else fprintf(out,"    mov %d(%%rbp), %%rcx\n",fn->slots[s].offset);
        fprintf(out,"    mov %%rcx, %zu(%%rax)\n",16+s*8);
    }
    for(size_t g=0;g<globals;g++)
        fprintf(out,"    mov .Ls_global_%zu(%%rip), %%rcx\n    mov %%rcx, %zu(%%rax)\n",g,16+(fn->slot_count+g)*8);
    fprintf(out,"    mov %%rax, %%rdi\n    mov -%d(%%rbp), %%rsi\n    call s_region_return\n",fn->frame_size);
    for(size_t g=0;g<globals;g++)
        fprintf(out,"    mov %zu(%%rax), %%rcx\n    mov %%rcx, .Ls_global_%zu(%%rip)\n",16+(fn->slot_count+g)*8,g);
    for(size_t s=0;s<fn->slot_count;s++) {
        if(standalone_global_index(module,fn->slots[s].name)>=0) continue;
        fprintf(out,"    mov %zu(%%rax), %%rcx\n",16+s*8);
        if(fn->slots[s].reg[0]) fprintf(out,"    mov %%rcx, %s\n",fn->slots[s].reg);
        else fprintf(out,"    mov %%rcx, %d(%%rbp)\n",fn->slots[s].offset);
    }
    /* Amortize evacuation against live size: a large retained graph must not
     * force another evacuation on every iteration. */
    fprintf(out,"    mov s_heap_current(%%rip), %%rcx\n    sub -%d(%%rbp), %%rcx\n    cmp $65536, %%rcx\n    jae 1f\n    mov $65536, %%ecx\n1:\n    add s_heap_current(%%rip), %%rcx\n    mov %%rcx, -%d(%%rbp)\n",fn->frame_size,fn->frame_size-8);
    fprintf(out,".Ls_%s_region_%zu:\n",symbol,at);
}
/* A region-proved callee may consume contiguous by-value ARG snapshots.
 * Stop at any intervening computation/effect or borrowed argument; snapshots
 * for pending outer calls remain outside the callee's region. */
static bool standalone_final_arg_region(standalone_module *module,
                                        standalone_function *caller,
                                        size_t at, size_t pending_after) {
    if(at+1>=caller->end) return false;
    size_t next=at+1;
    if(!strcmp(module->ir.ins[at].operand1,"mutable_borrow")) return false;
    while(next<caller->end && !strcmp(module->ir.ins[next].op,"ARG")) {
        if(!strcmp(module->ir.ins[next].operand1,"mutable_borrow")) return false;
        next++;
    }
    if(next==caller->end) return false;
    standalone_ins *call=&module->ir.ins[next];
    if(strcmp(call->op,"CALL") || runtime_callee(call->operand1)) return false;
    char *end=NULL;
    long count=strtol(call->operand2,&end,10);
    if(!end || *end || count<=0 || (size_t)count>pending_after+next-at-1 || (size_t)count<next-at) return false;
    const char *defined=defined_function_name(module,call->operand1);
    if(!defined) return false;
    for(size_t f=0;f<module->func_count;f++)
        if(!strcmp(module->funcs[f].name,defined)) return module->funcs[f].region_safe;
    return false;
}
static size_t standalone_arg_region_offset(standalone_function *fn,size_t argument) {
    return (fn->slot_count+4+STANDALONE_MAX_PENDING_ARGS+argument+1)*8;
}
static bool emit_function(FILE *out, standalone_module *module, standalone_function *fn, compile_error *err) {
    if(!standalone_analyze_liveness(module,fn,err)) return false;
	static const char *arg_regs[STANDALONE_MAX_ARGS] = {"%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9"};
	const char *pending[STANDALONE_MAX_PENDING_ARGS];
	bool pending_region[STANDALONE_MAX_PENDING_ARGS]={false};
	size_t pending_count = 0;
	size_t param_count = 0;
	size_t i;
	char symbol[STANDALONE_TEXT_CAP];
	symbol_text(fn->name, symbol, sizeof(symbol));
	/* Keep parsed production sources in the unit, but let the linker discard
	 * functions outside the executable's call graph. Unused experimental
	 * subsystems must not require implementations of their external services. */
	fprintf(out, ".section .text.s_fn_%s,\"ax\",@progbits\n", symbol);
	fprintf(out, ".global s_fn_%s\n.type s_fn_%s, @function\ns_fn_%s:\n", symbol, symbol, symbol);
	fprintf(out, "    push %%rbp\n    mov %%rsp, %%rbp\n");
	if (fn->slot_count > 0) fprintf(out, "    push %%r12\n    push %%r13\n    push %%r14\n    push %%r15\n");
	if (fn->frame_size > 0) fprintf(out, "    sub $%d, %%rsp\n", fn->frame_size);
    if(fn->region_safe) {
        /* R10 is private to the defined-S call ABI. Save it before the
         * runtime helper: s_region_begin may initialize the heap and clobber
         * caller-saved registers. Zero selects its ordinary local checkpoint. */
        fprintf(out,"    mov %%r10, -%d(%%rbp)\n    call s_region_begin\n    mov -%d(%%rbp), %%r10\n    test %%r10, %%r10\n    cmovnz %%r10, %%rax\n    mov %%rax, -%d(%%rbp)\n    add $65536, %%rax\n    mov %%rax, -%d(%%rbp)\n", fn->frame_size,fn->frame_size,fn->frame_size,fn->frame_size-8);
        if(fn->region_loop_safe) for(size_t s=0;s<fn->slot_count;s++) {
            if(standalone_global_index(module,fn->slots[s].name)>=0) continue;
            if(fn->slots[s].reg[0]) fprintf(out,"    xor %s, %s\n",fn->slots[s].reg,fn->slots[s].reg);
            else fprintf(out,"    movq $0, %d(%%rbp)\n",fn->slots[s].offset);
        }
    }
	for (i = fn->begin; i < fn->end; i++) {
		standalone_ins *ins = &module->ir.ins[i];
		if (strcmp(ins->op, "PARAM") == 0) {
			if (param_count < STANDALONE_MAX_ARGS) {
				if (!emit_store(out, module, fn, ins->result, arg_regs[param_count], err)) return false;
			} else {
				/* SysV AMD64: the first stack argument is 16(%rbp). */
				fprintf(out, "    mov %zu(%%rbp), %%rax\n", 16 + (param_count - STANDALONE_MAX_ARGS) * 8);
				if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
			}
			param_count++;
		} else if (strcmp(ins->op, "ARG") == 0) {
			if (pending_count >= STANDALONE_MAX_PENDING_ARGS) {
				error_set(err, ERR_SEMANTIC, 0, 0, "too many pending call arguments in %s", fn->name);
				return false;
			}
            if (!emit_load(out, module, fn, ins->result, "%rdi", err)) return false;
            pending_region[pending_count]=!ins->discard_snapshot &&
                strcmp(ins->operand1,"mutable_borrow") &&
                standalone_final_arg_region(module,fn,i,pending_count+1);
            if(pending_region[pending_count])
                fprintf(out,"    mov s_heap_current(%%rip), %%rax\n    mov %%rax, -%zu(%%rbp)\n",standalone_arg_region_offset(fn,pending_count));
            if (ins->discard_snapshot || !strcmp(ins->operand1,"mutable_borrow") || standalone_readonly_argument(module,fn,i)) fprintf(out,"    mov %%rdi, %%rax\n");
            else fprintf(out,"    call s_value_snapshot\n");
            fprintf(out, "    mov %%rax, -%zu(%%rbp)\n", (fn->slot_count + 4 + pending_count + 1)*8);
            pending[pending_count++] = ins->result;
		} else if (strcmp(ins->op, "CALL") == 0) {
			const char *callee = runtime_callee(ins->operand1);
            char fs_callee[64]; int fs_kind=standalone_fs_bridge_kind(callee);
            if(fs_kind>=0 && standalone_fs_bridge_schema(module,fs_kind,err)>=0) {
                snprintf(fs_callee,sizeof(fs_callee),".Ls_fs_bridge_%d",fs_kind);
                callee=fs_callee; module->fs_bridges[fs_kind]=true;
            }
			const char *defined = NULL;
			char local_callee[STANDALONE_TEXT_CAP];
			char *count_end = NULL;
			long call_arg_count = strtol(ins->operand2, &count_end, 10);
			size_t first_arg;
			size_t arg;
			if (!count_end || *count_end != '\0' || call_arg_count < 0 ||
				(size_t)call_arg_count > pending_count) {
				error_set(err, ERR_SEMANTIC, 0, 0, "invalid argument count for call to %s in %s", ins->operand1, fn->name);
				return false;
			}
			first_arg = pending_count - (size_t)call_arg_count;
			/* The Seed frontend lowers make(T, n) as a normal call.  For the
			 * standalone runtime, array construction is already represented by
			 * the tagged array allocator; preserve the length argument and avoid
			 * inventing a global make ABI. */
            /* Hosted vector methods carry a quoted slot name. Native code
             * passes the actual array value rather than the name string. */
            if (!strcmp(ins->operand1,"__vec_len") && call_arg_count==1) {
                standalone_literal path;
                if(!decode_literal(pending[first_arg],&path,err) || memchr(path.bytes,0,path.len)) return false;
                path.bytes[path.len]=0;
                if(!emit_load(out,module,fn,(char*)path.bytes,"%rdi",err)) return false;
                fprintf(out,"    call s_value_len\n");
                if(!emit_store(out,module,fn,ins->result,"%rax",err)) return false;
                pending_count=first_arg;
                continue;
            }
            if (!strcmp(ins->operand1,"__vec_set") && call_arg_count==3) {
                standalone_literal path;
                if(!decode_literal(pending[first_arg],&path,err) || memchr(path.bytes,0,path.len)) return false;
                path.bytes[path.len]=0;
                if(!emit_load(out,module,fn,(char*)path.bytes,"%rdi",err)) return false;
                fprintf(out,"    mov -%zu(%%rbp), %%rsi\n    mov -%zu(%%rbp), %%rdx\n    call s_index_set\n    mov $1, %%rax\n",
                    (fn->slot_count+4+first_arg+2)*8,(fn->slot_count+4+first_arg+3)*8);
                if(!emit_store(out,module,fn,ins->result,"%rax",err)) return false;
                pending_count=first_arg;
                continue;
            }
            if (!strcmp(ins->operand1,"__vec_push") && call_arg_count==2) {
                standalone_literal path;
                if(!decode_literal(pending[first_arg],&path,err) || memchr(path.bytes,0,path.len)) return false;
                path.bytes[path.len]=0;
                if(!emit_load(out,module,fn,(char*)path.bytes,"%rdi",err)) return false;
                /* ARG already evaluated and snapshotted the item. Reloading a
                 * literal here could allocate and clobber the receiver in rdi. */
                fprintf(out,"    mov -%zu(%%rbp), %%rsi\n    call s_array_append\n",(fn->slot_count+4+first_arg+2)*8);
                if(!emit_store(out,module,fn,(char*)path.bytes,"%rax",err) || !emit_store(out,module,fn,ins->result,"%rax",err)) return false;
                pending_count=first_arg;
                continue;
            }
			if (strcmp(ins->operand1, "make") == 0 && call_arg_count == 2) {
				if (!emit_load(out, module, fn, pending[first_arg + 1], "%rdi", err)) return false;
				fprintf(out, "    call s_array_new\n");
                standalone_literal array_type;
                if(!decode_literal(pending[first_arg],&array_type,err)) return false;
                char element_type[STANDALONE_TEXT_CAP];
                if(array_type.len >= sizeof(array_type.bytes)) return false;
                array_type.bytes[array_type.len]=0;
                if (seed_array_element((char*)array_type.bytes,element_type,sizeof(element_type)) && (!strcmp(element_type,"()") || !strcmp(element_type,"unit"))) {
                    fprintf(out,"    xor %%ecx, %%ecx\n.Lunit_array_%zu:\n    cmp 8(%%rax), %%rcx\n    jae .Lunit_array_done_%zu\n    movq $0, 16(%%rax,%%rcx,8)\n    inc %%rcx\n    jmp .Lunit_array_%zu\n.Lunit_array_done_%zu:\n",i,i,i,i);
                }

				if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
				pending_count = first_arg;
				continue;
			}
			if (call_arg_count > STANDALONE_MAX_ARGS) {
				size_t stack_args = (size_t)call_arg_count - STANDALONE_MAX_ARGS;
				size_t stack_bytes = ((stack_args * 8 + 15) / 16) * 16;
				fprintf(out, "    sub $%zu, %%rsp\n", stack_bytes);
				for (arg = STANDALONE_MAX_ARGS; arg < (size_t)call_arg_count; arg++) {
					if (callee) {
                    if (!emit_load(out, module, fn, pending[first_arg + arg], "%rax", err)) return false;
                } else fprintf(out, "    mov -%zu(%%rbp), %%rax\n", (fn->slot_count + 4 + first_arg + arg + 1)*8);
					fprintf(out, "    mov %%rax, %zu(%%rsp)\n", (arg - STANDALONE_MAX_ARGS) * 8);
				}
			}
			for (arg = 0; arg < (size_t)call_arg_count; arg++) {
				if (arg >= STANDALONE_MAX_ARGS) break;
				if (callee) {
                    if (!emit_load(out, module, fn, pending[first_arg + arg], arg_regs[arg], err)) return false;
                } else fprintf(out, "    mov -%zu(%%rbp), %s\n", (fn->slot_count + 4 + first_arg + arg + 1)*8, arg_regs[arg]);
			}
			if (!callee) defined = defined_function_name(module, ins->operand1);
            /* Set the hidden argument only after all ordinary argument loads,
             * which may themselves call runtime helpers. Unknown/other defined
             * functions always receive zero, never a stale runtime register. */
            if(!callee) {
                size_t region=pending_count;
                if(defined) for(size_t a=first_arg;a<pending_count;a++) if(pending_region[a]) { region=a; break; }
                if(region<pending_count) fprintf(out,"    mov -%zu(%%rbp), %%r10\n",standalone_arg_region_offset(fn,region));
                else fprintf(out,"    xor %%r10d, %%r10d\n");
            }
			if (!callee && !defined) {
				symbol_text(ins->operand1, local_callee, sizeof(local_callee));
				fprintf(out, "    call s_fn_%s\n", local_callee);
			} else if (!callee) {
				symbol_text(defined, local_callee, sizeof(local_callee));
				fprintf(out, "    call s_fn_%s\n", local_callee);
			} else {
				fprintf(out, "    call %s\n", callee);
			}
			if (call_arg_count > STANDALONE_MAX_ARGS) {
				size_t stack_args = (size_t)call_arg_count - STANDALONE_MAX_ARGS;
				size_t stack_bytes = ((stack_args * 8 + 15) / 16) * 16;
				fprintf(out, "    add $%zu, %%rsp\n", stack_bytes);
			}
			if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
			pending_count = first_arg;
		} else if (strcmp(ins->op, "ARRAY_NEW") == 0) {
			/* Tagged zero length. The runtime uses its existing array layout. */
			fprintf(out, "    mov $1, %%rdi\n    call s_array_new\n");
			if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "MOV") == 0) {
            bool constructor = false;
            if (i + 1 < fn->end && is_string_literal(ins->operand1)) {
                standalone_ins *tag = &module->ir.ins[i + 1];
                char type_field[STANDALONE_TEXT_CAP];
                if (snprintf(type_field, sizeof(type_field), "%s.__type", ins->result) < (int)sizeof(type_field) &&
                    !strcmp(tag->op, "MOV") && !strcmp(tag->result, type_field) && is_string_literal(tag->operand1)) {
                    standalone_literal type;
                    if (!decode_literal(tag->operand1, &type, err)) return false;
                    type.bytes[type.len] = 0;
                    int schema = standalone_record_index(module, (char *)type.bytes);
                    if (schema >= 0) {
                        fprintf(out, "    lea .Ls_record_schema_%d(%%rip), %%rdi\n    call s_record_new\n", schema);
                        emit_record_status(out);
                        if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
                        i++; constructor = true;
                    }
                }
            }
            if (!constructor) {
                if (!emit_load(out, module, fn, ins->operand1, "%rdi", err)) return false;
                fprintf(out, "    call s_value_snapshot\n");
                if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
            }
		} else if (strcmp(ins->op, "ADD") == 0) {
			const char *store_name = ins->result;
			if (!emit_load(out, module, fn, ins->operand1, "%rdi", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rsi", err)) return false;
			if (fn->integer_only) {
				fprintf(out, "    lea -1(%%rdi,%%rsi), %%rax\n");
			} else {
				fprintf(out, "    test $1, %%rdi\n    jz .Ls_%s_add_slow_%zu\n", symbol, i);
				fprintf(out, "    test $1, %%rsi\n    jz .Ls_%s_add_slow_%zu\n", symbol, i);
				fprintf(out, "    lea -1(%%rdi,%%rsi), %%rax\n    jmp .Ls_%s_add_done_%zu\n", symbol, i);
				fprintf(out, ".Ls_%s_add_slow_%zu:\n    call s_value_add\n", symbol, i);
				fprintf(out, ".Ls_%s_add_done_%zu:\n", symbol, i);
			}
			if (i + 1 < fn->end && strcmp(module->ir.ins[i + 1].op, "MOV") == 0 &&
				strcmp(module->ir.ins[i + 1].operand1, ins->result) == 0) {
				store_name = module->ir.ins[i + 1].result;
				i++;
			}
			if (!emit_store(out, module, fn, store_name, "%rax", err)) return false;
		} else if (strcmp(ins->op, "SUB") == 0 || strcmp(ins->op, "MUL") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rcx", err)) return false;
			fprintf(out, "    sar $1, %%rax\n    sar $1, %%rcx\n");
			fprintf(out, strcmp(ins->op, "SUB") == 0 ? "    sub %%rcx, %%rax\n" : "    imul %%rcx, %%rax\n");
			fprintf(out, "    lea 1(%%rax,%%rax), %%rax\n");
			if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "DIV") == 0 || strcmp(ins->op, "MOD") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rcx", err)) return false;
			fprintf(out, "    sar $1, %%rax\n    sar $1, %%rcx\n    cqo\n    idiv %%rcx\n");
			if (strcmp(ins->op, "MOD") == 0) fprintf(out, "    mov %%rdx, %%rax\n");
			fprintf(out, "    lea 1(%%rax,%%rax), %%rax\n");
			if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "BOR") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rcx", err)) return false;
			fprintf(out, "    sar $1, %%rax\n    sar $1, %%rcx\n    or %%rcx, %%rax\n    lea 1(%%rax,%%rax), %%rax\n");
			if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "BXOR") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rcx", err)) return false;
			fprintf(out, "    sar $1, %%rax\n    sar $1, %%rcx\n    xor %%rcx, %%rax\n    lea 1(%%rax,%%rax), %%rax\n");
			if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
		} else if (strcmp(ins->op, "BAND") == 0 || strcmp(ins->op, "SHL") == 0 ||
			strcmp(ins->op, "SHR") == 0) {
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rcx", err)) return false;
			fprintf(out, "    sar $1, %%rax\n    sar $1, %%rcx\n");
			if (strcmp(ins->op, "BAND") == 0) fprintf(out, "    and %%rcx, %%rax\n");
			else if (strcmp(ins->op, "SHL") == 0) fprintf(out, "    shl %%cl, %%rax\n");
			else fprintf(out, "    sar %%cl, %%rax\n");
			fprintf(out, "    lea 1(%%rax,%%rax), %%rax\n");
			if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
		} else if (strncmp(ins->op, "CMP_", 4) == 0) {
			const char *store_name = ins->result;
			const char *setcc = "sete";
			const char *falsecc = "jne";
			if (strcmp(ins->op, "CMP_NE") == 0) setcc = "setne";
			else if (strcmp(ins->op, "CMP_LT") == 0) setcc = "setl";
			else if (strcmp(ins->op, "CMP_LE") == 0) setcc = "setle";
			else if (strcmp(ins->op, "CMP_GT") == 0) setcc = "setg";
			else if (strcmp(ins->op, "CMP_GE") == 0) setcc = "setge";
			if (strcmp(ins->op, "CMP_NE") == 0) falsecc = "je";
			else if (strcmp(ins->op, "CMP_LT") == 0) falsecc = "jge";
			else if (strcmp(ins->op, "CMP_LE") == 0) falsecc = "jg";
			else if (strcmp(ins->op, "CMP_GT") == 0) falsecc = "jle";
			else if (strcmp(ins->op, "CMP_GE") == 0) falsecc = "jl";
			if (!emit_load(out, module, fn, ins->operand1, "%rdi", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rsi", err)) return false;
			if (i + 1 < fn->end && strcmp(module->ir.ins[i + 1].op, "JUMP_IF_FALSE") == 0 &&
				strcmp(module->ir.ins[i + 1].operand1, ins->result) == 0) {
				char label[STANDALONE_TEXT_CAP];
				symbol_text(module->ir.ins[i + 1].result, label, sizeof(label));
				if (fn->integer_only) {
					fprintf(out, "    cmp %%rsi, %%rdi\n    %s .Ls_%s_%s\n", falsecc, symbol, label);
				} else {
					fprintf(out, "    test $1, %%rdi\n    jz .Ls_%s_cmp_branch_slow_%zu\n", symbol, i);
					fprintf(out, "    test $1, %%rsi\n    jz .Ls_%s_cmp_branch_slow_%zu\n", symbol, i);
					fprintf(out, "    cmp %%rsi, %%rdi\n    %s .Ls_%s_%s\n    jmp .Ls_%s_cmp_branch_done_%zu\n", falsecc, symbol, label, symbol, i);
					fprintf(out, ".Ls_%s_cmp_branch_slow_%zu:\n    call s_value_cmp\n    cmp $0, %%rax\n    %s %%al\n    movzbq %%al, %%rax\n    lea 1(%%rax,%%rax), %%rax\n    cmp $1, %%rax\n    je .Ls_%s_%s\n", symbol, i, setcc, symbol, label);
					fprintf(out, ".Ls_%s_cmp_branch_done_%zu:\n", symbol, i);
				}
				i++;
				continue;
			}
			if (fn->integer_only) {
				fprintf(out, "    cmp %%rsi, %%rdi\n    %s %%al\n    movzbq %%al, %%rax\n    lea 1(%%rax,%%rax), %%rax\n", setcc);
			} else {
				fprintf(out, "    test $1, %%rdi\n    jz .Ls_%s_cmp_slow_%zu\n", symbol, i);
				fprintf(out, "    test $1, %%rsi\n    jz .Ls_%s_cmp_slow_%zu\n", symbol, i);
				fprintf(out, "    cmp %%rsi, %%rdi\n    %s %%al\n    movzbq %%al, %%rax\n    lea 1(%%rax,%%rax), %%rax\n    jmp .Ls_%s_cmp_done_%zu\n", setcc, symbol, i);
				fprintf(out, ".Ls_%s_cmp_slow_%zu:\n    call s_value_cmp\n    cmp $0, %%rax\n    %s %%al\n    movzbq %%al, %%rax\n    lea 1(%%rax,%%rax), %%rax\n", symbol, i, setcc);
				fprintf(out, ".Ls_%s_cmp_done_%zu:\n", symbol, i);
			}
			if (i + 1 < fn->end && strcmp(module->ir.ins[i + 1].op, "MOV") == 0 &&
				strcmp(module->ir.ins[i + 1].operand1, ins->result) == 0) {
				store_name = module->ir.ins[i + 1].result;
				i++;
			}
			if (!emit_store(out, module, fn, store_name, "%rax", err)) return false;
		} else if (strcmp(ins->op, "JUMP_IF_FALSE") == 0) {
			char label[STANDALONE_TEXT_CAP];
			symbol_text(ins->result, label, sizeof(label));
			if (!emit_load(out, module, fn, ins->operand1, "%rax", err)) return false;
			fprintf(out, "    cmp $1, %%rax\n    je .Ls_%s_%s\n", symbol, label);
		} else if (strcmp(ins->op, "JUMP") == 0) {
            if(fn->region_safe && fn->region_loop_safe && !fn->integer_only && !pending_count) {
                for(size_t j=fn->begin;j<i;j++)
                    if(!strcmp(module->ir.ins[j].op,"LABEL") && !strcmp(module->ir.ins[j].result,ins->result)) {
                        emit_region_loop(out,module,fn,symbol,i,j); break;
                    }
            }
			char label[STANDALONE_TEXT_CAP];
			symbol_text(ins->result, label, sizeof(label));
			fprintf(out, "    jmp .Ls_%s_%s\n", symbol, label);
		} else if (strcmp(ins->op, "LABEL") == 0) {
			char label[STANDALONE_TEXT_CAP];
			symbol_text(ins->result, label, sizeof(label));
			fprintf(out, ".Ls_%s_%s:\n", symbol, label);
		} else if (strcmp(ins->op, "INDEX_SET") == 0) {
			if (!emit_load(out, module, fn, ins->result, "%rdi", err) ||
				!emit_load(out, module, fn, ins->operand1, "%rsi", err) ||
				!emit_load(out, module, fn, ins->operand2, "%rdx", err)) return false;
			fprintf(out, "    call s_index_set\n");
		} else if (strcmp(ins->op, "READ") == 0) {
			char index_value[STANDALONE_TEXT_CAP];
			if (!parse_index_projection(ins->operand2, index_value, sizeof(index_value))) {
				error_set(err, ERR_SEMANTIC, 0, 0, "unsupported standalone READ projection %s", ins->operand2);
				return false;
			}
			if (!emit_load(out, module, fn, ins->operand1, "%rdi", err) ||
				!emit_load(out, module, fn, index_value, "%rsi", err)) return false;
			fprintf(out, "    call s_index_get\n");
			if (!emit_store(out, module, fn, ins->result, "%rax", err)) return false;
		} else if(!strcmp(ins->op,"UNIT")) {
            fprintf(out,"    xor %%eax, %%eax\n");
            if(!emit_store(out,module,fn,ins->result,"%rax",err)) return false;
		} else if(!strcmp(ins->op,"TRAP")) {
            fprintf(out,"    mov $101, %%edi\n    mov $60, %%eax\n    syscall\n    ud2\n");
		} else if (strcmp(ins->op, "RET") == 0) {
            if (!emit_load(out, module, fn, ins->result, "%rdi", err)) return false;
            fprintf(out, "    call s_value_snapshot\n    jmp .Ls_%s_return\n", symbol);
		} else if (strcmp(ins->op, "NOP") != 0 && strcmp(ins->op, "EXPORT") != 0) {
			error_set(err, ERR_SEMANTIC, 0, 0, "unsupported standalone opcode %s", ins->op);
			return false;
		}
	}
	fprintf(out, "    mov $1, %%rax\n.Ls_%s_return:\n", symbol);
    if(fn->region_safe && fn->region_globals && module->global_count) {
        fprintf(out,"    push %%rax\n    sub $8, %%rsp\n    mov $%zu, %%edi\n    call s_array_new\n    add $8, %%rsp\n    pop %%rcx\n    test %%rax, %%rax\n    jnz 1f\n    mov $1, %%edi\n    call s_record_error\n1:\n    mov %%rcx, 16(%%rax)\n",(module->global_count+1)*2+1);
        for(size_t g=0;g<module->global_count;g++)
            fprintf(out,"    mov .Ls_global_%zu(%%rip), %%rcx\n    mov %%rcx, %zu(%%rax)\n",g,24+g*8);
        fprintf(out,"    mov %%rax, %%rdi\n    mov -%d(%%rbp), %%rsi\n    call s_region_return\n",fn->frame_size);
        for(size_t g=0;g<module->global_count;g++)
            fprintf(out,"    mov %zu(%%rax), %%rcx\n    mov %%rcx, .Ls_global_%zu(%%rip)\n",24+g*8,g);
        fprintf(out,"    mov 16(%%rax), %%rax\n");
    } else if(fn->region_safe) fprintf(out,"    mov %%rax, %%rdi\n    mov -%d(%%rbp), %%rsi\n    call s_region_return\n", fn->frame_size);
	if (fn->frame_size > 0) fprintf(out, "    add $%d, %%rsp\n", fn->frame_size);
	if (fn->slot_count > 0) fprintf(out, "    pop %%r15\n    pop %%r14\n    pop %%r13\n    pop %%r12\n");
	fprintf(out, "    leave\n    ret\n.size s_fn_%s, .-s_fn_%s\n\n", symbol, symbol);
	return true;
}
static bool emit_fs_bridges(FILE *out,standalone_module *m,compile_error *err) {
    const char *services[]={"s_read_file_value","s_write_file_value","s_make_temp_dir_value"};
    for(int kind=0;kind<3;kind++) {
        if(!m->fs_bridges[kind]) continue;
        int schema=standalone_fs_bridge_schema(m,kind,err);
        int variant=standalone_record_literal(m,"__variant",err),ok=standalone_record_literal(m,"__payload_ok",err);
        int failure=standalone_record_literal(m,"__payload_err",err),message=standalone_record_literal(m,"message",err);
        int text=standalone_record_literal(m,"native filesystem operation failed",err);
        if(schema<0 || variant<0 || ok<0 || failure<0 || message<0 || text<0) return false;
        fprintf(out,".section .text.s_fs_bridge_%d,\"ax\",@progbits\n.Ls_fs_bridge_%d:\n    push %%r12\n    push %%r13\n    push %%r14\n    call %s\n    mov %%rax, %%r12\n    lea .Ls_record_schema_%d(%%rip), %%rdi\n    call s_record_new\n",kind,kind,services[kind],schema);
        emit_record_status(out);
        fprintf(out,"    mov %%rax, %%r13\n");
        if(kind==1) fprintf(out,"    cmp $1, %%r12\n    jne .Ls_fs_failed_%d\n",kind);
        else fprintf(out,"    test %%r12, %%r12\n    jz .Ls_fs_failed_%d\n",kind);
        if(kind==2) fprintf(out,"    cmpq $0, 8(%%r12)\n    je .Ls_fs_failed_%d\n",kind);
        if(kind!=1) {
            fprintf(out,"    mov %%r13, %%rdi\n    lea .Ls_literal_%d(%%rip), %%rsi\n    mov %%r12, %%rdx\n    call s_record_set\n",ok);
            emit_record_status(out);
        }
        fprintf(out,"    jmp .Ls_fs_done_%d\n.Ls_fs_failed_%d:\n    mov %%r13, %%rdi\n    lea .Ls_literal_%d(%%rip), %%rsi\n    mov $3, %%rdx\n    call s_record_set\n",kind,kind,variant);
        emit_record_status(out);
        fprintf(out,"    mov %%r13, %%rdi\n    lea .Ls_literal_%d(%%rip), %%rsi\n    call s_record_get\n",failure);
        emit_record_status(out);
        fprintf(out,"    mov %%rax, %%rdi\n    lea .Ls_literal_%d(%%rip), %%rsi\n    lea .Ls_literal_%d(%%rip), %%rdx\n    call s_record_set\n",message,text);
        emit_record_status(out);
        fprintf(out,".Ls_fs_done_%d:\n    mov %%r13, %%rax\n    pop %%r14\n    pop %%r13\n    pop %%r12\n    ret\n",kind);
    }
    return true;
}
static bool emit_assembly(FILE *out, standalone_module *module, compile_error *err) {
	size_t i;
    standalone_analyze_regions(module);
    standalone_analyze_readonly(module);
    standalone_analyze_snapshot_uses(module);
	fprintf(out, ".section .text\n.global s_main\n.type s_main, @function\ns_main:\n");
    if(module->global_count) {
        /* Preserve the startup argc/argv ABI and keep SysV call alignment. */
        fprintf(out,"    push %%rdi\n    push %%rsi\n    sub $8, %%rsp\n");
        for(size_t order=0;order<module->global_order_count;order++) {
            size_t g=module->global_order[order];
            char init[STANDALONE_TEXT_CAP]; symbol_text(module->globals[g].initializer,init,sizeof(init));
            fprintf(out,"    xor %%r10d, %%r10d\n    call s_fn_%s\n    mov %%rax, .Ls_global_%zu(%%rip)\n",init,g);
        }
        fprintf(out,"    add $8, %%rsp\n    pop %%rsi\n    pop %%rdi\n");
    }
    fprintf(out,"    xor %%r10d, %%r10d\n    jmp s_fn_main\n.size s_main, .-s_main\n");
    for(size_t g=0;g<module->global_count;g++) fprintf(out,".section .bss\n.p2align 3\n.Ls_global_%zu: .zero 8\n",g);
	for (i = 0; i < module->func_count; i++) {
		if (!emit_function(out, module, &module->funcs[i], err)) return false;
	}
    if(!emit_fs_bridges(out,module,err)) return false;
    for (i = 0; i < module->record_count; i++) {
        standalone_record_schema *r = &module->records[i];
        size_t j;
        if (r->state != 2) continue;
        fprintf(out, ".section .rodata.s_record_%zu,\"a\",@progbits\n.balign 8\n.Ls_record_schema_%zu:\n    .quad .Ls_literal_%d\n    .quad %zu\n", i, i, r->type_literal, r->count);
        for (j = 0; j < r->count; j++) {
            standalone_record_field *f = &r->fields[j];
            fprintf(out, "    .quad .Ls_literal_%d\n    .quad %d\n", f->name_literal, f->kind);
            if (f->kind == 3) fprintf(out, "    .quad .Ls_record_schema_%d\n", f->nested);
            else fprintf(out, "    .quad 0\n");
        }
    }
	for (i = 0; i < module->literal_count; i++) {
		size_t j;
		standalone_literal *lit = &module->literals[i];
		fprintf(out, ".section .rodata.s_literal_%zu,\"a\",@progbits\n", i);
		fprintf(out, ".balign 8\n.Ls_literal_%zu:\n    .quad 2\n    .quad %zu\n    .byte ", i, lit->len);
		for (j = 0; j < lit->len; j++) fprintf(out, "%s%u", j ? "," : "", (unsigned)lit->bytes[j]);
		fprintf(out, "%s0\n", lit->len ? "," : "");
	}
	fprintf(out, ".section .note.GNU-stack,\"\",@progbits\n");
	return !ferror(out);
}
static bool run_tool(char *const argv[], compile_error *err) {
	pid_t pid = fork();
	int status;
	if (pid < 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to fork %s", argv[0]);
		return false;
	}
	if (pid == 0) {
		execvp(argv[0], argv);
		_exit(127);
	}
	if (waitpid(pid, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		error_set(err, ERR_SEMANTIC, 0, 0, "standalone tool failed: %s", argv[0]);
		return false;
	}
	return true;
}
static void standalone_free_module(standalone_module *module) {
	if (!module) return;
	for (size_t i = 0; i < module->func_count; i++) {
        free(module->funcs[i].slots);
        free(module->funcs[i].live_in);
    }
	free(module->globals);
	free(module->transfer_index);
	standalone_free_record_schemas(module);
	free(module);
}
bool emit_standalone_amd64_assembly_from_ir_file(const char *input_ir_path, const char *output_assembly_path, compile_error *err) {
	standalone_module *module = NULL;
	FILE *out = NULL;
	bool ok = false;
	error_clear(err);
	if (!input_ir_path || !output_assembly_path) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid standalone assembly backend input");
		return false;
	}
	module = (standalone_module *)calloc(1, sizeof(*module));
	if (!module) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		return false;
	}
	if (!load_ir(input_ir_path, &module->ir, err) || !analyze_module(module, err)) goto done;
	out = fopen(output_assembly_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create standalone assembly output");
		goto done;
	}
	if (!emit_assembly(out, module, err)) goto done;
	if (fclose(out) != 0) {
		out = NULL;
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close standalone assembly output");
		goto done;
	}
	out = NULL;
	ok = true;
done:
	if (out) fclose(out);
	standalone_free_module(module);
	return ok;
}
bool emit_standalone_amd64_from_ir_file(const char *input_ir_path, const char *output_binary_path, compile_error *err) {
	standalone_module *module = NULL;
	char temp_dir[] = "/tmp/s_standalone-XXXXXX";
	char asm_path[256];
	char obj_path[256];
	char runtime_obj_path[256];
	char runtime_source[1024];
	char linker_script[1024];
	const char *root = getenv("S_SOURCE_ROOT");
	const char *assembler = getenv("S_BOOTSTRAP_AS");
	const char *linker = getenv("S_BOOTSTRAP_LD");
	FILE *out = NULL;
	bool ok = false;
	char *as_program[] = {(char *)(assembler && *assembler ? assembler : "as"), "--64", "-o", obj_path, asm_path, NULL};
	char *as_runtime[] = {(char *)(assembler && *assembler ? assembler : "as"), "--64", "-o", runtime_obj_path, runtime_source, NULL};
	char *ld_program[] = {(char *)(linker && *linker ? linker : "ld"), "-static", "--gc-sections", "-T", linker_script, "-o", (char *)output_binary_path, runtime_obj_path, obj_path, NULL};
	error_clear(err);
	if (!input_ir_path || !output_binary_path) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid standalone backend input");
		return false;
	}
	if (!root || !*root) root = ".";
	if (!mkdtemp(temp_dir)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create standalone temporary directory: %s", strerror(errno));
		return false;
	}
	snprintf(asm_path, sizeof(asm_path), "%s/program.s", temp_dir);
	snprintf(obj_path, sizeof(obj_path), "%s/program.o", temp_dir);
	snprintf(runtime_obj_path, sizeof(runtime_obj_path), "%s/runtime.o", temp_dir);
	snprintf(runtime_source, sizeof(runtime_source), "%s/src/runtime/selfhost_linux_amd64.S", root);
	snprintf(linker_script, sizeof(linker_script), "%s/src/runtime/linker/nostdlib.ld", root);
	module = (standalone_module *)calloc(1, sizeof(*module));
	if (!module) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		goto done;
	}
	if (!load_ir(input_ir_path, &module->ir, err) || !analyze_module(module, err)) goto done;
	out = fopen(asm_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create standalone assembly");
		goto done;
	}
	if (!emit_assembly(out, module, err)) goto done;
	if (fclose(out) != 0) {
		out = NULL;
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close standalone assembly");
		goto done;
	}
	out = NULL;
	if (!run_tool(as_runtime, err) || !run_tool(as_program, err) || !run_tool(ld_program, err)) goto done;
	ok = true;
done:
	if (out) fclose(out);
	unlink(asm_path);
	unlink(obj_path);
	unlink(runtime_obj_path);
	rmdir(temp_dir);
	standalone_free_module(module);
	return ok;
}
bool emit_standalone_amd64_object_from_ir_file(const char *input_ir_path, const char *output_object_path, compile_error *err) {
	standalone_module *module = NULL;
	char temp_dir[] = "/tmp/s_standalone_obj-XXXXXX";
	char asm_path[256];
	const char *assembler = getenv("S_BOOTSTRAP_AS");
	FILE *out = NULL;
	bool ok = false;
	char *as_program[] = {(char *)(assembler && *assembler ? assembler : "as"), "--64", "-o", (char *)output_object_path, asm_path, NULL};
	error_clear(err);
	if (!input_ir_path || !output_object_path) {
		error_set(err, ERR_SEMANTIC, 0, 0, "invalid standalone object backend input");
		return false;
	}
	if (!mkdtemp(temp_dir)) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create standalone object temporary directory: %s", strerror(errno));
		return false;
	}
	snprintf(asm_path, sizeof(asm_path), "%s/program.s", temp_dir);
	module = (standalone_module *)calloc(1, sizeof(*module));
	if (!module) {
		error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "out of memory");
		goto done;
	}
	if (!load_ir(input_ir_path, &module->ir, err) || !analyze_module(module, err)) goto done;
	out = fopen(asm_path, "wb");
	if (!out) {
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to create standalone object assembly");
		goto done;
	}
	if (!emit_assembly(out, module, err)) goto done;
	if (fclose(out) != 0) {
		out = NULL;
		error_set(err, ERR_SEMANTIC, 0, 0, "failed to close standalone object assembly");
		goto done;
	}
	out = NULL;
	if (!run_tool(as_program, err)) goto done;
	ok = true;
done:
	if (out) fclose(out);
	unlink(asm_path);
	rmdir(temp_dir);
	standalone_free_module(module);
	return ok;
}
