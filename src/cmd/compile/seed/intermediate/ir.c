#include "ir.h"
#include "array_type.h"
#include "../syntax/enum_type.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct ir_builder {
	IR *ir;
	ast_node *root;
	compile_error *err;
	const char *package_name;
	int record_depth;
    unsigned constant_depth;
    const char *locals[4096];
    size_t local_count;
	int temp_counter;
	int label_counter;
	char break_labels[64][IR_OPERAND_CAP];
	char continue_labels[64][IR_OPERAND_CAP];
	int loop_depth;
	ast_node *externs[128];
	size_t extern_count;
	ast_node *constants[128];
	size_t constant_count;
	const char *current_func_return_type;  /* For context when lowering expressions */
} ir_builder;
static bool ir_bind_local(ir_builder *b,const char *name,source_pos pos) {
    if(b->local_count==4096) { error_set(b->err,ERR_SEMANTIC,pos.line,pos.column,"too many IR local bindings"); return false; }
    b->locals[b->local_count++]=name; return true;
}
static bool ir_local_root(ir_builder *b,const char *name) {
    if(b->constant_depth) return false; /* Initializers use declaration scope. */
    size_t length=strcspn(name,".");
    for(size_t i=b->local_count;i>0;i--)
        if(strlen(b->locals[i-1])==length && !strncmp(b->locals[i-1],name,length)) return true;
    return false;
}
/* Resolve constants by declaration identity, never by a unit-global short
 * name (different imported packages may declare the same constant). */
static ast_node *find_constant(ir_builder *b, const char *name, const char **declaration_package) {
    const char *pkg="";
    if(ir_local_root(b,name)) return NULL;
    if(!b->root || b->root->kind!=AST_PROGRAM) return NULL;
    for(size_t i=0;i<b->root->as.program.statements.len;i++) {
        ast_node *n=b->root->as.program.statements.data[i];
        if(n->kind==AST_PACKAGE_DECL) pkg=n->as.package_decl.name;
        if(n->kind!=AST_CONST_DECL) continue;
        char full[IR_OPERAND_CAP];
        if(snprintf(full,sizeof(full),"%s%s%s",pkg,*pkg?".":"",n->as.var_decl.name)>=(int)sizeof(full)) continue;
        if(!strcmp(full,name) || (!strcmp(pkg,b->package_name) && !strcmp(n->as.var_decl.name,name)))
            { *declaration_package=pkg; return n->as.var_decl.value; }
    }
    return NULL;
}
static ast_node *find_extern(ir_builder *b, const char *name) {
	size_t i;
	for (i = 0; i < b->extern_count; i++) {
		if (strcmp(b->externs[i]->as.extern_decl.name, name) == 0) return b->externs[i];
	}
	return NULL;
}
static int ffi_callee_name(ast_node *decl, char out[IR_OPERAND_CAP]) {
	size_t i;
	const char *abi = decl->as.extern_decl.abi;
	const char *symbol = decl->as.extern_decl.name;
	int n;
	if (strncmp(abi, "libc:", 5) == 0) {
		symbol = abi + 5;
		abi = "libc";
	}
	n = snprintf(out, IR_OPERAND_CAP, "__ffi_%s$%s$%s$", abi, symbol, decl->as.extern_decl.return_type);
	size_t used;
	if (n < 0 || n >= IR_OPERAND_CAP) return 0;
	used = (size_t)n;
	for (i = 0; i < decl->as.extern_decl.param_count; i++) {
		n = snprintf(out + used, IR_OPERAND_CAP - used, "%s%s", i ? "," : "", decl->as.extern_decl.param_types[i]);
		if (n < 0 || (size_t)n >= IR_OPERAND_CAP - used) return 0;
		used += (size_t)n;
	}
	return 1;
}
static void copy_str(char dst[IR_OPERAND_CAP], const char *src) {
	if (!src) {
		dst[0] = '\0';
		return;
	}
	snprintf(dst, IR_OPERAND_CAP, "%s", src);
}
void ir_init(IR *ir) {
	ir->instructions = NULL;
	ir->instruction_count = 0;
	ir->capacity = 0;
}
void ir_free(IR *ir) {
	free(ir->instructions);
	ir->instructions = NULL;
	ir->instruction_count = 0;
	ir->capacity = 0;
}
bool ir_emit(IR *ir, ir_op type, const char *result, const char *operand1, const char *operand2) {
	IRInstruction *ins;
	if (ir->instruction_count == ir->capacity) {
		int next_cap = (ir->capacity == 0) ? 32 : ir->capacity * 2;
		IRInstruction *next = (IRInstruction *)realloc(ir->instructions, (size_t)next_cap * sizeof(IRInstruction));
		if (!next) {
			return false;
		}
		ir->instructions = next;
		ir->capacity = next_cap;
	}
	ins = &ir->instructions[ir->instruction_count++];
	ins->type = type;
	copy_str(ins->result, result);
	copy_str(ins->operand1, operand1);
	copy_str(ins->operand2, operand2);
	return true;
}
const char *ir_op_name(ir_op op) {
	switch (op) {
		case IR_ARRAY_NEW: return "ARRAY_NEW";
        case IR_TRAP: return "TRAP";
        case IR_UNIT: return "UNIT";
	case IR_NOP: return "NOP";
		case IR_EXPORT: return "EXPORT";
		case IR_FUNC_BEGIN: return "FUNC_BEGIN";
		case IR_FUNC_END: return "FUNC_END";
		case IR_LABEL: return "LABEL";
		case IR_JUMP: return "JUMP";
		case IR_JUMP_IF_FALSE: return "JUMP_IF_FALSE";
		case IR_PARAM: return "PARAM";
		case IR_ARG: return "ARG";
		case IR_CALL: return "CALL";
		case IR_READ: return "READ";
		case IR_SROUTINE: return "SROUTINE";
		case IR_MOV: return "MOV";
		case IR_ADD: return "ADD";
		case IR_SUB: return "SUB";
		case IR_MUL: return "MUL";
		case IR_DIV: return "DIV";
		case IR_MOD: return "MOD";
		case IR_BAND: return "BAND";
		case IR_BOR: return "BOR";
		case IR_BXOR: return "BXOR";
		case IR_SHL: return "SHL";
		case IR_SHR: return "SHR";
		case IR_CMP_EQ: return "CMP_EQ";
		case IR_CMP_NE: return "CMP_NE";
		case IR_CMP_LT: return "CMP_LT";
		case IR_CMP_LE: return "CMP_LE";
		case IR_CMP_GT: return "CMP_GT";
		case IR_CMP_GE: return "CMP_GE";
		case IR_INDEX_SET: return "INDEX_SET";
		case IR_RET: return "RET";
	}
	return "UNKNOWN";
}
static bool emit_ins(ir_builder *b, ir_op type, const char *result, const char *op1, const char *op2, source_pos pos) {
	if (!ir_emit(b->ir, type, result, op1, op2)) {
		error_set(b->err, ERR_OUT_OF_MEMORY, pos.line, pos.column, "out of memory while emitting IR");
		return false;
	}
	return true;
}
static void next_temp(ir_builder *b, char out[IR_OPERAND_CAP]) {
	snprintf(out, IR_OPERAND_CAP, "t%d", b->temp_counter++);
}
static void next_label(ir_builder *b, char out[IR_OPERAND_CAP]) {
	snprintf(out, IR_OPERAND_CAP, "L%d", b->label_counter++);
}
static int push_loop(ir_builder *b, const char *break_label, const char *continue_label) {
	if (b->loop_depth >= 64) {
		return 0;
	}
	copy_str(b->break_labels[b->loop_depth], break_label);
	copy_str(b->continue_labels[b->loop_depth], continue_label);
	b->loop_depth++;
	return 1;
}
static void pop_loop(ir_builder *b) {
	if (b->loop_depth > 0) {
		b->loop_depth--;
	}
}
static const char *current_break_label(ir_builder *b) {
	if (b->loop_depth <= 0) {
		return NULL;
	}
	return b->break_labels[b->loop_depth - 1];
}
static const char *current_continue_label(ir_builder *b) {
	if (b->loop_depth <= 0) {
		return NULL;
	}
	return b->continue_labels[b->loop_depth - 1];
}
static bool lower_expr(ir_builder *b, ast_node *expr, char out[IR_OPERAND_CAP]);
static bool lower_constant(ir_builder *b,ast_node *value,const char *package,char out[IR_OPERAND_CAP]) {
    if(b->constant_depth>=128) {
        error_set(b->err,ERR_SEMANTIC,value->pos.line,value->pos.column,"cyclic or excessively nested constant initializer"); return false;
    }
    const char *saved=b->package_name; b->package_name=package; b->constant_depth++;
    bool ok=lower_expr(b,value,out);
    b->constant_depth--; b->package_name=saved; return ok;
}

static bool lower_place_assignment(ir_builder *b, ast_node *target, const char *value, char out[IR_OPERAND_CAP]);
/* Record declarations are parsed as `let name:struct = struct-expression`.
 * Preserve their type information as deterministic NOP metadata; the hosted
 * executor keeps its existing value behavior while native lowering uses it. */
static bool record_declaration(ast_node *node) {
    return node && node->kind == AST_LET_STMT && node->as.let_stmt.type_name &&
        strcmp(node->as.let_stmt.type_name, "struct") == 0 &&
        node->as.let_stmt.value && node->as.let_stmt.value->kind == AST_STRUCT_EXPR;
}
static bool record_type_name(ir_builder *b, const char *raw, char out[IR_OPERAND_CAP]) {
    const char *pkg = "";
    size_t i, length;
    if (!raw) raw = "";
    length=strlen(raw);
    /* Qualify a local record base while retaining pointer/array suffixes. */
    for (;;) {
        if(length>=2 && raw[length-2]=='[' && raw[length-1]==']') length-=2;
        else if(length && raw[length-1]=='*') length--;
        else break;
    }
    for (i = 0; b->root->kind == AST_PROGRAM && i < b->root->as.program.statements.len; i++) {
        ast_node *n = b->root->as.program.statements.data[i];
        if (n->kind == AST_PACKAGE_DECL) pkg = n->as.package_decl.name;
        if (record_declaration(n) && strlen(n->as.let_stmt.name)==length &&
            !strncmp(n->as.let_stmt.name,raw,length) && !strcmp(pkg,b->package_name)) {
            return snprintf(out,IR_OPERAND_CAP,"%s%s%s",pkg,*pkg?".":"",raw)<IR_OPERAND_CAP;
        }
    }
    /* Payload-free enum values already lower to integer tags. Their field,
     * array and transfer metadata must use that same runtime representation. */
    if(length<IR_OPERAND_CAP && !memchr(raw,'[',length) && !strchr(raw+length,'*')) {
        char base[IR_OPERAND_CAP],qualified[IR_OPERAND_CAP];
        memcpy(base,raw,length); base[length]=0;
        ast_node *decl=NULL;
        if(!strchr(base,'.') && *b->package_name &&
           snprintf(qualified,sizeof(qualified),"%s.%s",b->package_name,base)<(int)sizeof(qualified))
            decl=seed_find_enum(b->root,qualified);
        if(!decl) decl=seed_find_enum(b->root,base);
        if(decl && !decl->as.enum_decl.generic_count && !seed_enum_has_payload(decl))
            return snprintf(out,IR_OPERAND_CAP,"int%s",raw+length)<IR_OPERAND_CAP;
    }
    return snprintf(out, IR_OPERAND_CAP, "%s", raw) < IR_OPERAND_CAP;
}
static bool emit_record_schemas(ir_builder *b) {
    size_t i, f;
    if (b->root->kind != AST_PROGRAM) return true;
    for (i = 0; i < b->root->as.program.statements.len; i++) {
        ast_node *decl = b->root->as.program.statements.data[i];
        char key[IR_OPERAND_CAP], name[IR_OPERAND_CAP];
        if (decl->kind == AST_PACKAGE_DECL) b->package_name = decl->as.package_decl.name;
        if (!record_declaration(decl)) continue;
        if (decl->native_template) {
            if (snprintf(key,sizeof(key),"generic-record:%s",decl->as.let_stmt.name)>=(int)sizeof(key) ||
                !emit_ins(b,IR_NOP,key,decl->generic_parameters,"",decl->pos)) return false;
            continue;
        }
        if (!record_type_name(b, decl->as.let_stmt.name, name) ||
            snprintf(key, sizeof(key), "record-type:%s", name) >= (int)sizeof(key) ||
            !emit_ins(b, IR_NOP, key, "", "", decl->pos)) return false;
        if (snprintf(key, sizeof(key), "record-field:%s", name) >= (int)sizeof(key)) return false;
        ast_node *body = decl->as.let_stmt.value;
        for (f = 0; f < body->as.struct_expr.field_count; f++) {
            char field_type[IR_OPERAND_CAP];
            ast_node *t = body->as.struct_expr.field_values.data[f];
            if (t->kind != AST_STRING_EXPR || !record_type_name(b, t->as.string_expr.literal, field_type) ||
                !emit_ins(b, IR_NOP, key, body->as.struct_expr.field_names[f], field_type, decl->pos)) return false;
        }
    }
    b->package_name = "";
    return true;
}
static bool lower_struct_literal(ir_builder *b, ast_node *expr, char out[IR_OPERAND_CAP]);
static ast_node *record_find_declaration(ir_builder *b, const char *type) {
    const char *pkg = "";
    size_t i;
    char full[IR_OPERAND_CAP], wanted[IR_OPERAND_CAP];
    if (!record_type_name(b, type, wanted)) return NULL;
    for (i = 0; b->root->kind == AST_PROGRAM && i < b->root->as.program.statements.len; i++) {
        ast_node *n = b->root->as.program.statements.data[i];
        if (n->kind == AST_PACKAGE_DECL) pkg = n->as.package_decl.name;
        if (record_declaration(n) && snprintf(full, sizeof(full), "%s%s%s", pkg, *pkg ? "." : "", n->as.let_stmt.name) < (int)sizeof(full) && !strcmp(full, wanted)) return n;
    }
    return NULL;
}
static bool lower_record_defaults_impl(ir_builder *b, ast_node *expr, const char *root) {
    ast_node *decl = record_find_declaration(b, expr->as.struct_expr.type_name);
    size_t f, j;
    if (!decl) return true;
    ast_node *schema = decl->as.let_stmt.value;
    for (f = 0; f < schema->as.struct_expr.field_count; f++) {
        const char *name = schema->as.struct_expr.field_names[f];
        for (j = 0; j < expr->as.struct_expr.field_count; j++) if (!strcmp(name, expr->as.struct_expr.field_names[j])) break;
        if (j < expr->as.struct_expr.field_count) continue;
        const char *type = schema->as.struct_expr.field_values.data[f]->as.string_expr.literal;
        char dest[IR_OPERAND_CAP], value[IR_OPERAND_CAP];
        if (snprintf(dest, sizeof(dest), "%s.%s", root, name) >= (int)sizeof(dest)) return false;
        if(!strcmp(type,"()") || !strcmp(type,"unit")) {
            next_temp(b,value);
            if(!emit_ins(b,IR_UNIT,value,"","",expr->pos)) return false;
        }
        else if (!strcmp(type, "string")) copy_str(value, "\"\"");
        else if (strlen(type) >= 2 && !strcmp(type + strlen(type) - 2, "[]")) {
            char array_type[IR_OPERAND_CAP];
            next_temp(b, value);
            if (!record_type_name(b,type,array_type) || !emit_ins(b, IR_ARRAY_NEW, value, array_type, "0", expr->pos)) return false;
        } else if (record_find_declaration(b, type)) {
            ast_node nested;
            memset(&nested, 0, sizeof(nested)); nested.kind = AST_STRUCT_EXPR;
            nested.pos = expr->pos; nested.as.struct_expr.type_name = (char *)type;
            if (b->record_depth >= 64) { error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "recursive by-value record defaults"); return false; }
            b->record_depth++;
            bool ok = lower_struct_literal(b, &nested, value);
            b->record_depth--;
            if (!ok) return false;
        } else copy_str(value, "0");
        if (!emit_ins(b, IR_MOV, dest, value, "", expr->pos)) return false;
    }
    return true;
}
static bool lower_record_defaults(ir_builder *b, ast_node *expr, const char *root) {
    ast_node *decl = record_find_declaration(b, expr->as.struct_expr.type_name);
    const char *saved_package = b->package_name;
    const char *pkg = "";
    for (size_t i = 0; decl && i < b->root->as.program.statements.len; i++) {
        ast_node *n = b->root->as.program.statements.data[i];
        if (n->kind == AST_PACKAGE_DECL) pkg = n->as.package_decl.name;
        if (n == decl) { b->package_name = pkg; break; }
    }
    /* Resolve both the declaration and its nested field types in its own
     * package; the caller's import context must not redefine those names. */
    bool ok = lower_record_defaults_impl(b, expr, root);
    b->package_name = saved_package;
    return ok;
}
static bool lower_struct_literal(ir_builder *b, ast_node *expr, char out[IR_OPERAND_CAP]) {
	size_t i;
	char alias_literal[IR_OPERAND_CAP];
	next_temp(b, out);
	if (snprintf(alias_literal, sizeof(alias_literal), "\"%s\"", out) >= (int)sizeof(alias_literal)) {
		error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "struct alias too long for IR operand");
		return false;
	}
	if (!emit_ins(b, IR_MOV, out, alias_literal, "", expr->pos)) {
		return false;
	}
	{
		char type_field[IR_OPERAND_CAP];
		char type_literal[IR_OPERAND_CAP];
		char qualified_type[IR_OPERAND_CAP];
		if (!record_type_name(b, expr->as.struct_expr.type_name, qualified_type)) return false;
		if (snprintf(type_field, sizeof(type_field), "%s.__type", out) >= (int)sizeof(type_field) ||
			snprintf(type_literal, sizeof(type_literal), "\"%s\"", qualified_type) >= (int)sizeof(type_literal) ||
			!emit_ins(b, IR_MOV, type_field, type_literal, "", expr->pos)) {
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "struct type tag too long for IR operand");
			return false;
		}
	}
	if (!lower_record_defaults(b, expr, out)) return false;
	for (i = 0; i < expr->as.struct_expr.field_count; i++) {
		char field_value[IR_OPERAND_CAP];
		char field_name[IR_OPERAND_CAP];
		if (!lower_expr(b, expr->as.struct_expr.field_values.data[i], field_value)) {
			return false;
		}
		if (snprintf(field_name, sizeof(field_name), "%s.%s", out, expr->as.struct_expr.field_names[i]) >= (int)sizeof(field_name)) {
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "struct field name too long for IR operand");
			return false;
		}
		if (!emit_ins(b, IR_MOV, field_name, field_value, "", expr->pos)) {
			return false;
		}
	}
	return true;
}
static bool lower_stmt(ir_builder *b, ast_node *stmt);
static bool lower_enum_construct(ir_builder *b, ast_node *decl, ast_enum_variant *variant,
	ast_node *payload, source_pos pos, char out[IR_OPERAND_CAP], const char *resolved_enum_type) {
	char tag[IR_OPERAND_CAP];
	snprintf(tag, sizeof(tag), "%lld", (long long)variant->resolved_value);
	if (!seed_enum_has_payload(decl)) {
		copy_str(out, tag);
		return true;
	}
	{
		char alias[IR_OPERAND_CAP], field[IR_OPERAND_CAP], value[IR_OPERAND_CAP];
		next_temp(b, out);
		snprintf(alias, sizeof(alias), "\"%s\"", out);
		if (!emit_ins(b, IR_MOV, out, alias, "", pos)) return false;
		if (snprintf(field, sizeof(field), "%s.__type", out) >= (int)sizeof(field)) return false;
		/* Use resolved_enum_type if provided (for generic instantiations), otherwise use base name */
		const char *type_name = resolved_enum_type ? resolved_enum_type : decl->as.enum_decl.name;
		/* If type_name is just the base name and we have a current function return type that's parameterized,
		 * check if it matches this enum and use the full parameterized type */
		if (b->current_func_return_type && type_name && !strchr(type_name, '[')) {
			/* Check if return type starts with this type name */
			size_t type_len = strlen(type_name);
			if (strncmp(b->current_func_return_type, type_name, type_len) == 0 &&
				(b->current_func_return_type[type_len] == '[' || b->current_func_return_type[type_len] == '.' || b->current_func_return_type[type_len] == 0)) {
				type_name = b->current_func_return_type;
			}
		}
		snprintf(value, sizeof(value), "\"%s\"", type_name);
		if (!emit_ins(b, IR_MOV, field, value, "", pos)) return false;
		if (snprintf(field, sizeof(field), "%s.__variant", out) >= (int)sizeof(field) ||
			!emit_ins(b, IR_MOV, field, tag, "", pos)) return false;
		if (payload) {
			if (!lower_expr(b, payload, value)) return false;
			if (snprintf(field, sizeof(field), "%s.value", out) >= (int)sizeof(field)) return false;
			if (!emit_ins(b, IR_MOV, field, value, "", pos)) return false;
		}
	}
	return true;
}
static bool lower_value_branch(ir_builder *,ast_node *,char [IR_OPERAND_CAP],bool *);
static bool lower_value_branch_inner(ir_builder *b, ast_node *node, char out[IR_OPERAND_CAP], bool *has_value) {
	size_t i;
	*has_value = false;
	if (!node) return true;
	if (node->kind == AST_BLOCK) {
		for (i = 0; i < node->as.block.statements.len; i++) {
			ast_node *child = node->as.block.statements.data[i];
			if (i + 1 == node->as.block.statements.len)
				return lower_value_branch(b, child, out, has_value);
			if (!lower_stmt(b, child)) return false;
		}
		return true;
	}
	if (node->kind == AST_RETURN_STMT || node->kind == AST_BREAK_STMT ||
		node->kind == AST_CONTINUE_STMT) return lower_stmt(b, node);
	if (node->kind == AST_EXPR_STMT) node = node->as.expr_stmt.expr;
    if(node->kind==AST_TRAP_STMT) return emit_ins(b,IR_TRAP,"101","","",node->pos);
	if(b->root->native_unit && node->kind==AST_CALL_EXPR && node->as.call_expr.resolved_return_type &&
	   !strcmp(node->as.call_expr.resolved_return_type,"never")) return lower_expr(b,node,out);
	if (!lower_expr(b, node, out)) return false;
	*has_value = !(b->root->native_unit && node->kind==AST_IF_STMT && !strcmp(out,"0"));
	return true;
}

static bool lower_value_branch(ir_builder *b,ast_node *node,char out[IR_OPERAND_CAP],bool *has_value) {
    size_t saved=b->local_count;
    bool ok=lower_value_branch_inner(b,node,out,has_value);
    if(node && node->kind==AST_BLOCK && !node->as.block.transparent_scope) b->local_count=saved;
    return ok;
}

static bool lower_if_value(ir_builder *b, ast_node *node, char out[IR_OPERAND_CAP]) {
	ast_node *arm = node;
	char subject[IR_OPERAND_CAP] = "";
	char end_label[IR_OPERAND_CAP];
	bool value_join=false;
	/* A statement switch evaluates its arms for effects only. Do not invent
	 * a result join between discarded values of unrelated types. */
	if (out) next_temp(b, out);
	next_label(b, end_label);
	if (node->as.if_stmt.is_switch_arm) {
		char value[IR_OPERAND_CAP];
		if (!lower_expr(b, node->as.if_stmt.pattern_subject, value)) return false;
		/* Snapshot the subject, even when it is a mutable variable. */
        if(node->as.if_stmt.native_variant_field) copy_str(subject,value);
        else {
            next_temp(b,subject);
            if(!emit_ins(b,IR_MOV,subject,value,"",node->pos)) return false;
        }
	}
	while (arm && arm->kind == AST_IF_STMT) {
		char cond[IR_OPERAND_CAP] = "1";
		char next_arm[IR_OPERAND_CAP];
		char value[IR_OPERAND_CAP];
		bool has_value;
		next_label(b, next_arm);
		if (arm->as.if_stmt.is_pattern_arm) {
			if (arm->as.if_stmt.pattern_kind == PATTERN_VARIANT) {
				ast_node *decl = seed_find_enum(b->root, arm->as.if_stmt.variant_owner);
				ast_enum_variant *variant = seed_find_variant(decl, arm->as.if_stmt.variant_name);
				char tag[IR_OPERAND_CAP], field[IR_OPERAND_CAP];
				if (!variant) {
					error_set(b->err, ERR_SEMANTIC, arm->pos.line, arm->pos.column, "unknown enum variant in pattern");
					return false;
				}
				snprintf(tag, sizeof(tag), "%lld", (long long)(arm->as.if_stmt.native_variant_field?arm->as.if_stmt.native_variant_tag:variant->resolved_value));
				if (snprintf(field, sizeof(field), "%s%s", subject,
					seed_enum_has_payload(decl) ? ".__variant" : "") >= (int)sizeof(field)) return false;
				next_temp(b, cond);
				if (!emit_ins(b, IR_CMP_EQ, cond, field, tag, arm->pos)) return false;
			}
		} else if (arm->as.if_stmt.condition) {
			if (arm->as.if_stmt.is_switch_arm) {
				if (!lower_expr(b, arm->as.if_stmt.condition->as.binary_expr.right, value)) return false;
				next_temp(b, cond);
				if (!emit_ins(b, IR_CMP_EQ, cond, subject, value, arm->pos)) return false;
			} else if (!lower_expr(b, arm->as.if_stmt.condition, cond)) return false;
		}
		/* Default/wildcard arms have no false edge. Manufacturing one makes
		 * their result appear undefined at the join to independent CFG proofs. */
		if (strcmp(cond, "1") && !emit_ins(b, IR_JUMP_IF_FALSE, next_arm, cond, "", arm->pos)) return false;
		if (arm->as.if_stmt.payload_binding_name) {
			char field[IR_OPERAND_CAP];
			if (snprintf(field, sizeof(field), "%s.%s", subject,arm->as.if_stmt.native_variant_field?arm->as.if_stmt.native_variant_field:"value") >= (int)sizeof(field)) return false;
            if(arm->as.if_stmt.native_variant_array) {
                if(!emit_ins(b,IR_ARG,field,"","",arm->pos) || !emit_ins(b,IR_ARG,"0","","",arm->pos) ||
                   !emit_ins(b,IR_CALL,arm->as.if_stmt.payload_binding_name,"__index_get","2",arm->pos)) return false;
            } else if(!emit_ins(b,IR_MOV,arm->as.if_stmt.payload_binding_name,field,"",arm->pos)) return false;
		}
		if (arm->as.if_stmt.binding_name &&
			!emit_ins(b, IR_MOV, arm->as.if_stmt.binding_name, subject, "", arm->pos)) return false;
		if (out) {
			if (!lower_value_branch(b, arm->as.if_stmt.then_branch, value, &has_value)) return false;
			value_join=value_join || has_value;
			if (has_value && !emit_ins(b, IR_MOV, out, value, "", arm->pos)) return false;
		} else if (!lower_stmt(b, arm->as.if_stmt.then_branch)) return false;
		if (!emit_ins(b, IR_JUMP, end_label, "", "", arm->pos) ||
			!emit_ins(b, IR_LABEL, next_arm, "", "", arm->pos)) return false;
		arm = arm->as.if_stmt.else_branch;
	}
	if (arm) {
		char value[IR_OPERAND_CAP];
		bool has_value;
		if (out) {
			if (!lower_value_branch(b, arm, value, &has_value)) return false;
			value_join=value_join || has_value;
			if (has_value && !emit_ins(b, IR_MOV, out, value, "", arm->pos)) return false;
		} else if (!lower_stmt(b, arm)) return false;
	}
	if(!emit_ins(b, IR_LABEL, end_label, "", "", node->pos)) return false;
    if(b->root->native_unit && out && !value_join) {
        copy_str(out,"0");
        return emit_ins(b,IR_TRAP,"101","","",node->pos);
    }
    return true;
}

static bool lower_array_literal(ir_builder *b, ast_node *expr, char out[IR_OPERAND_CAP]) {
	size_t i;
	int written;
	size_t used = 0;
	if (!expr || expr->kind != AST_ARRAY_EXPR) {
		return false;
	}
	if (used + 1 >= IR_OPERAND_CAP) {
		error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "array literal too long for IR operand");
		return false;
	}
	out[used++] = '[';
	for (i = 0; i < expr->as.array_expr.items.len; i++) {
		ast_node *item = expr->as.array_expr.items.data[i];
		char item_text[IR_OPERAND_CAP];
		if (!item) {
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "invalid array literal item");
			return false;
		}
		switch (item->kind) {
			case AST_NUMBER_EXPR:
				snprintf(item_text, sizeof(item_text), "%s", item->as.number_expr.literal);
				break;
			case AST_BOOL_EXPR:
				snprintf(item_text, sizeof(item_text), "%s", item->as.bool_expr.value ? "true" : "false");
				break;
			case AST_STRING_EXPR:
				snprintf(item_text, sizeof(item_text), "\"%s\"", item->as.string_expr.literal);
				break;
			case AST_IDENT_EXPR:
				snprintf(item_text, sizeof(item_text), "%s", item->as.ident_expr.name);
				break;
			default:
                if(expr->native_enum) {
                    if(!lower_expr(b,item,item_text)) return false;
                    break;
                }
				error_set(b->err, ERR_SEMANTIC, item->pos.line, item->pos.column,
					"array literal currently supports number/bool/string/identifier items in IR lowering");
				return false;
		}
		written = snprintf(out + used, IR_OPERAND_CAP - used, "%s%s", (i == 0) ? "" : ", ", item_text);
		if (written < 0 || (size_t)written >= IR_OPERAND_CAP - used) {
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "array literal too long for IR operand");
			return false;
		}
		used += (size_t)written;
	}
	if (used + 1 >= IR_OPERAND_CAP) {
		error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "array literal too long for IR operand");
		return false;
	}
	out[used++] = ']';
	out[used] = '\0';
	return true;
}
static bool is_non_unit_return_type(const char *return_type) {
	return return_type && return_type[0] != '\0' && strcmp(return_type, "()") != 0 && strcmp(return_type,"unit") != 0;
}
static const char *fallback_return_literal(const char *return_type) {
	if (!return_type) {
		return "0";
	}
	if (strcmp(return_type, "string") == 0) {
		return "\"\"";
	}
	if (strcmp(return_type, "bool") == 0) {
		return "0";
	}
	if (strcmp(return_type, "int") == 0) {
		return "0";
	}
	return "0";
}
static bool lower_binary(ir_builder *b, ast_node *expr, char out[IR_OPERAND_CAP]) {
	char lhs[IR_OPERAND_CAP];
	char rhs[IR_OPERAND_CAP];
	ir_op op;
	if (!lower_expr(b, expr->as.binary_expr.left, lhs)) {
		return false;
	}
	if (expr->as.binary_expr.op == TOKEN_OR_OR || expr->as.binary_expr.op == TOKEN_AND_AND) {
		char lhs_bool[IR_OPERAND_CAP];
		char rhs_bool[IR_OPERAND_CAP];
		char eval_rhs_label[IR_OPERAND_CAP];
		char false_label[IR_OPERAND_CAP];
		char end_label[IR_OPERAND_CAP];
		next_temp(b, lhs_bool);
		next_temp(b, rhs_bool);
		next_temp(b, out);
		next_label(b, eval_rhs_label);
		next_label(b, false_label);
		next_label(b, end_label);
		if (!emit_ins(b, IR_CMP_NE, lhs_bool, lhs, "0", expr->pos)) {
			return false;
		}
		if (expr->as.binary_expr.op == TOKEN_OR_OR) {
			if (!emit_ins(b, IR_JUMP_IF_FALSE, eval_rhs_label, lhs_bool, "", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_MOV, out, "1", "", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_JUMP, end_label, "", "", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_LABEL, eval_rhs_label, "", "", expr->pos)) {
				return false;
			}
			if (!lower_expr(b, expr->as.binary_expr.right, rhs)) {
				return false;
			}
			if (!emit_ins(b, IR_CMP_NE, rhs_bool, rhs, "0", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_MOV, out, rhs_bool, "", expr->pos)) {
				return false;
			}
			return emit_ins(b, IR_LABEL, end_label, "", "", expr->pos);
		}
		if (!emit_ins(b, IR_JUMP_IF_FALSE, false_label, lhs_bool, "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_JUMP, eval_rhs_label, "", "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_LABEL, eval_rhs_label, "", "", expr->pos)) {
			return false;
		}
		if (!lower_expr(b, expr->as.binary_expr.right, rhs)) {
			return false;
		}
		if (!emit_ins(b, IR_CMP_NE, rhs_bool, rhs, "0", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_MOV, out, rhs_bool, "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_JUMP, end_label, "", "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_LABEL, false_label, "", "", expr->pos)) {
			return false;
		}
		if (!emit_ins(b, IR_MOV, out, "0", "", expr->pos)) {
			return false;
		}
		return emit_ins(b, IR_LABEL, end_label, "", "", expr->pos);
	}
	if (!lower_expr(b, expr->as.binary_expr.right, rhs)) {
		return false;
	}
	switch (expr->as.binary_expr.op) {
		case TOKEN_PLUS: op = IR_ADD; break;
		case TOKEN_MINUS: op = IR_SUB; break;
		case TOKEN_STAR: op = IR_MUL; break;
		case TOKEN_SLASH: op = IR_DIV; break;
		case TOKEN_PERCENT: op = IR_MOD; break;
		case TOKEN_AMP: op = IR_BAND; break;
		case TOKEN_PIPE: op = IR_BOR; break;
		case TOKEN_XOR: op = IR_BXOR; break;
		case TOKEN_SHL: op = IR_SHL; break;
		case TOKEN_SHR: op = IR_SHR; break;
		case TOKEN_EQ: op = IR_CMP_EQ; break;
		case TOKEN_NE: op = IR_CMP_NE; break;
		case TOKEN_LT: op = IR_CMP_LT; break;
		case TOKEN_LE: op = IR_CMP_LE; break;
		case TOKEN_GT: op = IR_CMP_GT; break;
		case TOKEN_GE: op = IR_CMP_GE; break;
		default:
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "unsupported binary operator for IR");
			return false;
	}
	next_temp(b, out);
	return emit_ins(b, op, out, lhs, rhs, expr->pos);
}
static bool lower_place_assignment(ir_builder *b, ast_node *target, const char *value, char out[IR_OPERAND_CAP]) {
	if (!target) return false;
	if (target->kind == AST_IDENT_EXPR) {
		if (!emit_ins(b, IR_MOV, target->as.ident_expr.name, value, "", target->pos)) {
			return false;
		}
		snprintf(out, IR_OPERAND_CAP, "%s", target->as.ident_expr.name);
		return true;
	}
	if (target->kind == AST_MEMBER_EXPR) {
		ast_node *object = target->as.member_expr.object;
		char place[IR_OPERAND_CAP];
		if (object && object->kind == AST_INDEX_EXPR) {
			char array_name[IR_OPERAND_CAP];
			char index_name[IR_OPERAND_CAP];
			char element_name[IR_OPERAND_CAP];
			char field_name[IR_OPERAND_CAP];
			if (!lower_expr(b, object->as.index_expr.object, array_name)) {
				return false;
			}
			if (!lower_expr(b, object->as.index_expr.index, index_name)) {
				return false;
			}
			if (!emit_ins(b, IR_ARG, array_name, "", "", object->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_ARG, index_name, "", "", object->pos)) {
				return false;
			}
			next_temp(b, element_name);
			if (!emit_ins(b, IR_CALL, element_name, "__index_get", "2", object->pos)) {
				return false;
			}
			if (snprintf(field_name, IR_OPERAND_CAP, "%s.%s", element_name, target->as.member_expr.member) >= IR_OPERAND_CAP) {
				error_set(b->err, ERR_SEMANTIC, target->pos.line, target->pos.column, "member assignment target too long for IR operand");
				return false;
			}
			if (!emit_ins(b, IR_MOV, field_name, value, "", target->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_INDEX_SET, array_name, index_name, element_name, target->pos)) {
				return false;
			}
			snprintf(out, IR_OPERAND_CAP, "%s", field_name);
			return true;
		}
		if (!lower_expr(b, target, place)) {
			return false;
		}
		if (!emit_ins(b, IR_MOV, place, value, "", target->pos)) {
			return false;
		}
		snprintf(out, IR_OPERAND_CAP, "%s", place);
		return true;
	}
	if (target->kind == AST_INDEX_EXPR) {
		char object_name[IR_OPERAND_CAP];
		char index_name[IR_OPERAND_CAP];
		if (!lower_expr(b, target->as.index_expr.object, object_name)) {
			return false;
		}
		if (!lower_expr(b, target->as.index_expr.index, index_name)) {
			return false;
		}
		if (!emit_ins(b, IR_INDEX_SET, object_name, index_name, value, target->pos)) {
			return false;
		}
		snprintf(out, IR_OPERAND_CAP, "%s", object_name);
		return true;
	}
	error_set(b->err, ERR_SEMANTIC, target->pos.line, target->pos.column, "computed assignment target is not supported for IR");
	return false;
}
static bool lower_expr(ir_builder *b, ast_node *expr, char out[IR_OPERAND_CAP]) {
	if (!expr) {
		out[0] = '\0';
		return true;
	}
	switch (expr->kind) {
        case AST_UNIT_EXPR:
            next_temp(b,out); return emit_ins(b,IR_UNIT,out,"","",expr->pos);
        case AST_TRAP_STMT: copy_str(out,"0"); return emit_ins(b,IR_TRAP,"101","","",expr->pos);
		case AST_IF_STMT:
			return lower_if_value(b, expr, out);
		case AST_NUMBER_EXPR:
			snprintf(out, IR_OPERAND_CAP, "%s", expr->as.number_expr.literal);
			return true;
		case AST_BOOL_EXPR:
			snprintf(out, IR_OPERAND_CAP, "%d", expr->as.bool_expr.value ? 1 : 0);
			return true;
		case AST_STRING_EXPR:
			if (expr->as.string_expr.is_type_name) {
                char type[IR_OPERAND_CAP];
                if (!record_type_name(b,expr->as.string_expr.literal,type)) return false;
                if (snprintf(out,IR_OPERAND_CAP,"\"%s\"",type)>=IR_OPERAND_CAP) {
                    error_set(b->err,ERR_SEMANTIC,expr->pos.line,expr->pos.column,"qualified type argument is too long"); return false;
                }
                return true;
            }
			snprintf(out, IR_OPERAND_CAP, "\"%s\"", expr->as.string_expr.literal);
			return true;
		case AST_ARRAY_EXPR:
            if(!expr->as.array_expr.items.len && expr->as.array_expr.explicit_type) {
                next_temp(b,out); return emit_ins(b,IR_ARRAY_NEW,out,expr->as.array_expr.explicit_type,"0",expr->pos);
            }
			return lower_array_literal(b, expr, out);
		case AST_STRUCT_EXPR:
			return lower_struct_literal(b, expr, out);
		case AST_IDENT_EXPR:
			{
				const char *package="";
                ast_node *constant_value = find_constant(b, expr->as.ident_expr.name,&package);
				if (constant_value) return lower_constant(b,constant_value,package,out);
			}
			snprintf(out, IR_OPERAND_CAP, "%s", expr->as.ident_expr.name);
			return true;
		case AST_MEMBER_EXPR: {
			char object_name[IR_OPERAND_CAP],constant_name[IR_OPERAND_CAP];
            if(seed_enum_owner_name(expr,constant_name,sizeof(constant_name))) {
                const char *package="";
                ast_node *constant=find_constant(b,constant_name,&package);
                if(constant) return lower_constant(b,constant,package,out);
            }
			if (expr->as.member_expr.resolved_enum_type &&
				seed_enum_owner_name(expr->as.member_expr.object, object_name, sizeof(object_name))) {
				ast_node *decl = seed_find_enum(b->root, expr->as.member_expr.resolved_enum_type);
				ast_enum_variant *variant = seed_find_variant(decl, expr->as.member_expr.member);
				if (variant && !variant->payload_type)
					return lower_enum_construct(b, decl, variant, NULL, expr->pos, out, expr->as.member_expr.resolved_enum_type);
			}
			if (!lower_expr(b, expr->as.member_expr.object, object_name)) {
				return false;
			}
			if (snprintf(out, IR_OPERAND_CAP, "%s.%s", object_name, expr->as.member_expr.member) >= IR_OPERAND_CAP) {
				error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "member expression too long for IR operand");
				return false;
			}
			return true;
		}
		case AST_INDEX_EXPR: {
			char object_name[IR_OPERAND_CAP];
			char index_name[IR_OPERAND_CAP];
			if (!lower_expr(b, expr->as.index_expr.object, object_name)) {
				return false;
			}
			if (!lower_expr(b, expr->as.index_expr.index, index_name)) {
				return false;
			}
			if (!emit_ins(b, IR_ARG, object_name, "", "", expr->pos)) {
				return false;
			}
			if (!emit_ins(b, IR_ARG, index_name, "", "", expr->pos)) {
				return false;
			}
			next_temp(b, out);
			return emit_ins(b, IR_CALL, out, "__index_get", "2", expr->pos);
		}
		case AST_UNARY_EXPR: {
			char rhs[IR_OPERAND_CAP];
			if (!lower_expr(b, expr->as.unary_expr.operand, rhs)) {
				return false;
			}


			if (expr->as.unary_expr.op == TOKEN_STAR) {
				snprintf(out, IR_OPERAND_CAP, "%s", rhs);
				return true;
			}
			next_temp(b, out);
			if (expr->as.unary_expr.op == TOKEN_MINUS) {
				return emit_ins(b, IR_SUB, out, "0", rhs, expr->pos);
			}
			if (expr->as.unary_expr.op == TOKEN_BANG) {
				return emit_ins(b, IR_CMP_EQ, out, rhs, "0", expr->pos);
			}
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "unsupported unary operator for IR");
			return false;
		}
		case AST_BINARY_EXPR:
			return lower_binary(b, expr, out);
		case AST_ASSIGN_EXPR:
			if (expr->as.assign_expr.target_expr) {
				if (!lower_expr(b, expr->as.assign_expr.value, out)) {
					return false;
				}
				return lower_place_assignment(b, expr->as.assign_expr.target_expr, out, out);
			}
			if (expr->as.assign_expr.target_object && expr->as.assign_expr.target_index) {
				char object_name[IR_OPERAND_CAP];
				char index_name[IR_OPERAND_CAP];
				if (!lower_expr(b, expr->as.assign_expr.value, out)) {
					return false;
				}
				if (!lower_expr(b, expr->as.assign_expr.target_object, object_name)) {
					return false;
				}
				if (!lower_expr(b, expr->as.assign_expr.target_index, index_name)) {
					return false;
				}
				return emit_ins(b, IR_INDEX_SET, object_name, index_name, out, expr->pos);
			}
			if (!lower_expr(b, expr->as.assign_expr.value, out)) {
				return false;
			}
			if (!emit_ins(b, IR_MOV, expr->as.assign_expr.name, out, "", expr->pos)) {
				return false;
			}
			snprintf(out, IR_OPERAND_CAP, "%s", expr->as.assign_expr.name);
			return true;
		case AST_CALL_EXPR: {
			size_t i;
            if(b->root->native_unit && expr->as.call_expr.resolved_return_type &&
               !strcmp(expr->as.call_expr.resolved_return_type,"never") &&
               expr->as.call_expr.callee && expr->as.call_expr.callee->kind==AST_IDENT_EXPR &&
               !strcmp(expr->as.call_expr.callee->as.ident_expr.name,"panic")) {
                for(i=0;i<expr->as.call_expr.args.len;i++) {
                    char ignored[IR_OPERAND_CAP];
                    if(!lower_expr(b,expr->as.call_expr.args.data[i],ignored)) return false;
                }
                copy_str(out,"0");
                return emit_ins(b,IR_TRAP,"101","","",expr->pos);
            }
			size_t argc = expr->as.call_expr.args.len;
			char callee[IR_OPERAND_CAP] = "call";
			char argc_text[IR_OPERAND_CAP];
			ast_node *member = expr->as.call_expr.callee;
			if (member && member->kind == AST_MEMBER_EXPR && member->as.member_expr.resolved_enum_type &&
				seed_enum_owner_name(member->as.member_expr.object, callee, sizeof(callee))) {
				ast_node *decl = seed_find_enum(b->root, member->as.member_expr.resolved_enum_type);
				ast_enum_variant *variant = seed_find_variant(decl, member->as.member_expr.member);
				if (variant) return lower_enum_construct(b, decl, variant,
						expr->as.call_expr.args.len ? expr->as.call_expr.args.data[0] : NULL, expr->pos, out,
						member->as.member_expr.resolved_enum_type);
			}
			if (expr->as.call_expr.resolved_array_type) {
                char array_type[IR_OPERAND_CAP];
				if (!seed_array_new_valid(expr->as.call_expr.resolved_array_type, "0")) {
					error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "invalid resolved array constructor type");
					return false;
				}
				next_temp(b, out);
				return record_type_name(b,expr->as.call_expr.resolved_array_type,array_type) &&
                    emit_ins(b, IR_ARRAY_NEW, out, array_type, "0", expr->pos);
			}
			if (expr->as.call_expr.callee && expr->as.call_expr.callee->kind == AST_INDEX_EXPR &&
				!expr->as.call_expr.callee->as.index_expr.index) {
				error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column,
					"array constructor requires semantic type resolution");
				return false;
			}
			if (expr->as.call_expr.callee && expr->as.call_expr.callee->kind == AST_INDEX_EXPR &&
				expr->as.call_expr.callee->as.index_expr.object &&
				expr->as.call_expr.callee->as.index_expr.object->kind == AST_IDENT_EXPR &&
				strcmp(expr->as.call_expr.callee->as.index_expr.object->as.ident_expr.name, "vec") == 0) {
				next_temp(b, out);
				return emit_ins(b, IR_CALL, out, "__vec_make", "0", expr->pos);
			}
			if (expr->as.call_expr.callee && expr->as.call_expr.callee->kind == AST_MEMBER_EXPR &&
				expr->as.call_expr.callee->as.member_expr.resolved_method) {
				char receiver[IR_OPERAND_CAP];
				char receiver_arg[IR_OPERAND_CAP];
				char qualified_name[IR_OPERAND_CAP];
				bool static_qualified_call = false;
				if (!lower_expr(b, expr->as.call_expr.callee->as.member_expr.object, receiver)) {
					return false;
				}
				if (snprintf(qualified_name, sizeof(qualified_name), "%s.%s",
					receiver, expr->as.call_expr.callee->as.member_expr.member) >= (int)sizeof(qualified_name)) {
					error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "qualified call name is too long");
					return false;
				}
				static_qualified_call = strcmp(expr->as.call_expr.callee->as.member_expr.resolved_method, qualified_name) == 0;
				if (!static_qualified_call) {
					if (strncmp(expr->as.call_expr.callee->as.member_expr.resolved_method, "__vec_", 6) == 0) {
						if (snprintf(receiver_arg, sizeof(receiver_arg), "\"%s\"", receiver) >= (int)sizeof(receiver_arg)) {
							error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "vector receiver is too long");
							return false;
						}
					} else {
						snprintf(receiver_arg, sizeof(receiver_arg), "%s", receiver);
					}
					if (!emit_ins(b, IR_ARG, receiver_arg, "", "", expr->pos)) return false;
					argc++;
				}
				snprintf(callee, sizeof(callee), "%s", expr->as.call_expr.callee->as.member_expr.resolved_method);
			}
			for (i = 0; i < expr->as.call_expr.args.len; i++) {
				char arg_tmp[IR_OPERAND_CAP];
				if (!lower_expr(b, expr->as.call_expr.args.data[i], arg_tmp)) {
					return false;
				}
				if (!emit_ins(b, IR_ARG, arg_tmp, i < 64 && (expr->as.call_expr.native_borrow_mask & (1ULL << i)) ? "mutable_borrow" : "", "", expr->pos)) {
					return false;
				}
			}
			if (expr->as.call_expr.callee && expr->as.call_expr.callee->kind == AST_IDENT_EXPR) {
				snprintf(callee, sizeof(callee), "%s", expr->as.call_expr.callee->as.ident_expr.name);
				{
					ast_node *decl = find_extern(b, callee);
					if (decl && strncmp(decl->as.extern_decl.abi, "libc", 4) == 0 && !ffi_callee_name(decl, callee)) {
						error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "extern signature too long");
						return false;
					}
				}
			} else if (expr->as.call_expr.callee && expr->as.call_expr.callee->kind == AST_MEMBER_EXPR &&
				!expr->as.call_expr.callee->as.member_expr.resolved_method) {
				if (!lower_expr(b, expr->as.call_expr.callee, callee)) {
					return false;
				}
			}
			snprintf(argc_text, sizeof(argc_text), "%zu", argc);
			next_temp(b, out);
			return emit_ins(b, IR_CALL, out, callee, argc_text, expr->pos);
		}
		default:
			error_set(b->err, ERR_SEMANTIC, expr->pos.line, expr->pos.column, "unsupported expression in IR lowering");
			return false;
	}
}
static bool lower_block(ir_builder *b, ast_node *block) {
    size_t saved=b->local_count;
	size_t i;
	for (i = 0; i < block->as.block.statements.len; i++) {
		if (!lower_stmt(b, block->as.block.statements.data[i])) {
			return false;
		}
	}
    if(!block->as.block.transparent_scope) b->local_count=saved;
	return true;
}
static bool lower_if(ir_builder *b, ast_node *stmt) {
	char cond[IR_OPERAND_CAP];
	char else_label[IR_OPERAND_CAP];
	char end_label[IR_OPERAND_CAP];
	if (!lower_expr(b, stmt->as.if_stmt.condition, cond)) {
		return false;
	}
	next_label(b, else_label);
	next_label(b, end_label);
	if (!emit_ins(b, IR_JUMP_IF_FALSE, else_label, cond, "", stmt->pos)) {
		return false;
	}
	if (!lower_stmt(b, stmt->as.if_stmt.then_branch)) {
		return false;
	}
	if (!emit_ins(b, IR_JUMP, end_label, "", "", stmt->pos)) {
		return false;
	}
	if (!emit_ins(b, IR_LABEL, else_label, "", "", stmt->pos)) {
		return false;
	}
	if (stmt->as.if_stmt.else_branch && !lower_stmt(b, stmt->as.if_stmt.else_branch)) {
		return false;
	}
	return emit_ins(b, IR_LABEL, end_label, "", "", stmt->pos);
}
static bool lower_while(ir_builder *b, ast_node *stmt) {
	char start_label[IR_OPERAND_CAP];
	char end_label[IR_OPERAND_CAP];
	char cond[IR_OPERAND_CAP];
	next_label(b, start_label);
	next_label(b, end_label);
	if (!emit_ins(b, IR_LABEL, start_label, "", "", stmt->pos)) {
		return false;
	}
	if (!lower_expr(b, stmt->as.while_stmt.condition, cond)) {
		return false;
	}
	if (!emit_ins(b, IR_JUMP_IF_FALSE, end_label, cond, "", stmt->pos)) {
		return false;
	}
	if (!push_loop(b, end_label, start_label)) {
		error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "loop nesting too deep");
		return false;
	}
	if (!lower_stmt(b, stmt->as.while_stmt.body)) {
		pop_loop(b);
		return false;
	}
	pop_loop(b);
	if (!emit_ins(b, IR_JUMP, start_label, "", "", stmt->pos)) {
		return false;
	}
	return emit_ins(b, IR_LABEL, end_label, "", "", stmt->pos);
}
static bool lower_for(ir_builder *b, ast_node *stmt) {
    size_t saved=b->local_count;
	char start_label[IR_OPERAND_CAP];
	char post_label[IR_OPERAND_CAP];
	char end_label[IR_OPERAND_CAP];
	char cond[IR_OPERAND_CAP];
    char iterable[IR_OPERAND_CAP], index[IR_OPERAND_CAP], length[IR_OPERAND_CAP], shadow[IR_OPERAND_CAP]="";
    if(stmt->as.for_stmt.iterable) {
        char value[IR_OPERAND_CAP];
        if(!lower_expr(b,stmt->as.for_stmt.iterable,value)) return false;
        /* The loop binding has lexical scope even though IR uses flat slots.
         * Preserve an outer value on both the empty and break exit paths. */
        if(ir_local_root(b,stmt->as.for_stmt.iter_name)) {
            next_temp(b,shadow);
            if(!emit_ins(b,IR_MOV,shadow,stmt->as.for_stmt.iter_name,"",stmt->pos)) return false;
        }
        next_temp(b,iterable); next_temp(b,index); next_temp(b,length);
        if(!emit_ins(b,IR_MOV,iterable,value,"",stmt->pos) ||
           !emit_ins(b,IR_MOV,index,"0","",stmt->pos) ||
           !emit_ins(b,IR_ARG,iterable,"","",stmt->pos) ||
           !emit_ins(b,IR_CALL,length,"len","1",stmt->pos) ||
           !ir_bind_local(b,stmt->as.for_stmt.iter_name,stmt->pos)) return false;
    }
	if (stmt->as.for_stmt.init && !lower_stmt(b, stmt->as.for_stmt.init)) {
		return false;
	}
	next_label(b, start_label);
	next_label(b, post_label);
	next_label(b, end_label);
	if (!emit_ins(b, IR_LABEL, start_label, "", "", stmt->pos)) {
		return false;
	}
    if(stmt->as.for_stmt.iterable) {
        next_temp(b,cond);
        if(!emit_ins(b,IR_CMP_LT,cond,index,length,stmt->pos) ||
           !emit_ins(b,IR_JUMP_IF_FALSE,end_label,cond,"",stmt->pos) ||
           !emit_ins(b,IR_ARG,iterable,"","",stmt->pos) ||
           !emit_ins(b,IR_ARG,index,"","",stmt->pos) ||
           !emit_ins(b,IR_CALL,stmt->as.for_stmt.iter_name,"__index_get","2",stmt->pos)) return false;
    }
	if (stmt->as.for_stmt.condition) {
		if (!lower_expr(b, stmt->as.for_stmt.condition, cond)) {
			return false;
		}
		if (!emit_ins(b, IR_JUMP_IF_FALSE, end_label, cond, "", stmt->pos)) {
			return false;
		}
	}
	if (!push_loop(b, end_label, post_label)) {
		error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "loop nesting too deep");
		return false;
	}
	if (!lower_stmt(b, stmt->as.for_stmt.body)) {
		pop_loop(b);
		return false;
	}
	pop_loop(b);
	if (!emit_ins(b, IR_LABEL, post_label, "", "", stmt->pos)) {
		return false;
	}
    if(stmt->as.for_stmt.iterable && !emit_ins(b,IR_ADD,index,index,"1",stmt->pos)) return false;
	if (stmt->as.for_stmt.post) {
		if (stmt->as.for_stmt.post->kind == AST_ASSIGN_STMT) {
			if (!lower_stmt(b, stmt->as.for_stmt.post)) {
				return false;
			}
		} else {
			char unused[IR_OPERAND_CAP];
			if (!lower_expr(b, stmt->as.for_stmt.post, unused)) {
				return false;
			}
		}
	}
	if (!emit_ins(b, IR_JUMP, start_label, "", "", stmt->pos)) {
			return false;
		}
    if(!emit_ins(b,IR_LABEL,end_label,"","",stmt->pos)) return false;
    if(shadow[0] && !emit_ins(b,IR_MOV,stmt->as.for_stmt.iter_name,shadow,"",stmt->pos)) return false;
    b->local_count=saved;
    return true;
}
static bool lower_fn(ir_builder *b, ast_node *stmt) {
    if(stmt->native_template) {
        char name[IR_OPERAND_CAP];
        if(snprintf(name,sizeof(name),"generic-function:%s",stmt->as.fn_stmt.name)>=(int)sizeof(name)) return false;
        return emit_ins(b,IR_NOP,name,stmt->generic_parameters,stmt->as.fn_stmt.return_type,stmt->pos);
    }
    b->local_count=0;
    for(size_t param=0;param<stmt->as.fn_stmt.param_count;param++) {
        if(!ir_bind_local(b,stmt->as.fn_stmt.params[param],stmt->pos)) return false;
    }
	size_t i;
	char signature[IR_OPERAND_CAP];
	size_t used = 0;
	int has_tail_expr_return = 0;
	int non_unit = is_non_unit_return_type(stmt->as.fn_stmt.return_type);
	if (stmt->as.fn_stmt.export_symbol) {
		const char *ret = stmt->as.fn_stmt.return_type ? stmt->as.fn_stmt.return_type : "()";
		int n = snprintf(signature, sizeof(signature), "%s", ret);
		if (n < 0 || (size_t)n >= sizeof(signature)) {
			error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "C ABI export signature is too long");
			return false;
		}
		used = (size_t)n;
		for (i = 0; i < stmt->as.fn_stmt.param_count; i++) {
			n = snprintf(signature + used, sizeof(signature) - used, ",%s", stmt->as.fn_stmt.param_types[i]);
			if (n < 0 || (size_t)n >= sizeof(signature) - used) {
				error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "C ABI export signature is too long");
				return false;
			}
			used += (size_t)n;
		}
		if (!emit_ins(b, IR_EXPORT, stmt->as.fn_stmt.name, stmt->as.fn_stmt.export_symbol, signature, stmt->pos)) {
			return false;
		}
	}
    {
        char key[IR_OPERAND_CAP], transfer[IR_OPERAND_CAP];
        if (!record_type_name(b,stmt->as.fn_stmt.return_type?stmt->as.fn_stmt.return_type:"()",transfer) ||
            snprintf(key, sizeof(key), "return-transfer:%s", stmt->as.fn_stmt.name) >= (int)sizeof(key) ||
            !emit_ins(b, IR_NOP, key, "", transfer, stmt->pos)) return false;
        for (i = 0; i < stmt->as.fn_stmt.param_count; i++) {
            if (i < 64 && (stmt->as.fn_stmt.native_borrow_mask & (1ULL << i))) {
                char base[IR_OPERAND_CAP], qualified[IR_OPERAND_CAP];
                size_t n=strlen(stmt->as.fn_stmt.param_types[i]);
                if(n<2 || n>=sizeof(base)) return false;
                memcpy(base,stmt->as.fn_stmt.param_types[i],n-1); base[n-1]=0;
                if(!record_type_name(b,base,qualified) || snprintf(key,sizeof(key),"borrow-param:%s",stmt->as.fn_stmt.name)>=(int)sizeof(key) ||
                    !emit_ins(b,IR_NOP,key,stmt->as.fn_stmt.params[i],qualified,stmt->pos)) return false;
            }
            if (!record_type_name(b,stmt->as.fn_stmt.param_types[i],transfer) ||
                snprintf(key, sizeof(key), "param-transfer:%s", stmt->as.fn_stmt.name) >= (int)sizeof(key) ||
                !emit_ins(b, IR_NOP, key, stmt->as.fn_stmt.params[i], transfer, stmt->pos)) return false;
        }
    }
    /* PARAM records stay contiguous for the existing hosted function loader. */
    if (!emit_ins(b, IR_FUNC_BEGIN, stmt->as.fn_stmt.name, "", "", stmt->pos)) return false;
    /* Store the function's return type so enum constructors within it can access it */
    b->current_func_return_type = stmt->as.fn_stmt.return_type ? stmt->as.fn_stmt.return_type : "()";
    for (i = 0; i < stmt->as.fn_stmt.param_count; i++) {
        if (!emit_ins(b, IR_PARAM, stmt->as.fn_stmt.params[i], i < 64 && (stmt->as.fn_stmt.native_borrow_mask & (1ULL << i)) ? "mutable_borrow" : "", "", stmt->pos)) return false;
    }
	if (stmt->as.fn_stmt.body && stmt->as.fn_stmt.body->kind == AST_BLOCK) {
		size_t n = stmt->as.fn_stmt.body->as.block.statements.len;
		for (i = 0; i < n; i++) {
			ast_node *child = stmt->as.fn_stmt.body->as.block.statements.data[i];
			if (non_unit && i + 1 == n && child &&
				(child->kind == AST_EXPR_STMT ||
				 (child->kind == AST_IF_STMT && child->as.if_stmt.is_switch_arm))) {
				char ret_value[IR_OPERAND_CAP];
				if (!lower_expr(b, child->kind == AST_EXPR_STMT ? child->as.expr_stmt.expr : child, ret_value)) {
					return false;
				}
				if (!emit_ins(b, IR_RET, ret_value, "", "", child->pos)) {
					return false;
				}
				has_tail_expr_return = 1;
				continue;
			}
			if (!lower_stmt(b, child)) {
				return false;
			}
		}
	} else {
		if (!lower_stmt(b, stmt->as.fn_stmt.body)) {
			return false;
		}
	}
	if (non_unit && !has_tail_expr_return) {
		if (!emit_ins(b, IR_RET, fallback_return_literal(stmt->as.fn_stmt.return_type), "", "", stmt->pos)) {
			return false;
		}
	}
    if(!non_unit) {
        char unit[IR_OPERAND_CAP]; next_temp(b,unit);
        if(!emit_ins(b,IR_UNIT,unit,"","",stmt->pos) || !emit_ins(b,IR_RET,unit,"","",stmt->pos)) return false;
    }
    b->local_count=0;
    b->current_func_return_type = NULL;  /* Clear function context after processing */
	return emit_ins(b, IR_FUNC_END, stmt->as.fn_stmt.name, "", "", stmt->pos);
}
static bool lower_stmt(ir_builder *b, ast_node *stmt) {
	char value[IR_OPERAND_CAP];
	if (!stmt) {
		return true;
	}
	switch (stmt->kind) {
        case AST_TRAP_STMT: return emit_ins(b,IR_TRAP,"101","","",stmt->pos);
		case AST_PACKAGE_DECL:
			b->package_name = stmt->as.package_decl.name;
			return true;
		case AST_USE_DECL:
		case AST_EXTERN_DECL:
		case AST_VAR_DECL:
		case AST_CONST_DECL:
		case AST_TRAIT_DECL:
		case AST_ENUM_DECL:
			return true;
		case AST_BLOCK:
			return lower_block(b, stmt);
		case AST_LET_STMT:
            if(stmt->native_template) return true;
			if (!lower_expr(b, stmt->as.let_stmt.value, value)) {
				return false;
			}
            if(!ir_bind_local(b,stmt->as.let_stmt.name,stmt->pos)) return false;
			return emit_ins(b, IR_MOV, stmt->as.let_stmt.name, value, "", stmt->pos);
		case AST_ASSIGN_STMT:
			if (!lower_expr(b, stmt->as.assign_stmt.value, value)) {
				return false;
			}
			return emit_ins(b, IR_MOV, stmt->as.assign_stmt.name, value, "", stmt->pos);
		case AST_RETURN_STMT:
            if(!stmt->as.return_stmt.value) {
                next_temp(b,value);
                return emit_ins(b,IR_UNIT,value,"","",stmt->pos) && emit_ins(b,IR_RET,value,"","",stmt->pos);
            }
			if (!lower_expr(b, stmt->as.return_stmt.value, value)) {
				return false;
			}
			return emit_ins(b, IR_RET, value, "", "", stmt->pos);
		case AST_BREAK_STMT: {
			const char *break_label = current_break_label(b);
			if (!break_label) {
				error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "break outside loop");
				return false;
			}
			return emit_ins(b, IR_JUMP, break_label, "", "", stmt->pos);
		}
		case AST_CONTINUE_STMT: {
			const char *continue_label = current_continue_label(b);
			if (!continue_label) {
				error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "continue outside loop");
				return false;
			}
			return emit_ins(b, IR_JUMP, continue_label, "", "", stmt->pos);
		}
		case AST_EXPR_STMT:
			return lower_expr(b, stmt->as.expr_stmt.expr, value);
		case AST_SROUTINE_STMT: {
			ast_node *call = stmt->as.sroutine_stmt.call;
			size_t i;
			char argc_text[IR_OPERAND_CAP];
			const char *callee = call->as.call_expr.callee->as.ident_expr.name;
			for (i = 0; i < call->as.call_expr.args.len; i++) {
				char arg_tmp[IR_OPERAND_CAP];
				if (!lower_expr(b, call->as.call_expr.args.data[i], arg_tmp) ||
					!emit_ins(b, IR_ARG, arg_tmp, "", "", stmt->pos)) return false;
			}
			snprintf(argc_text, sizeof(argc_text), "%zu", call->as.call_expr.args.len);
			return emit_ins(b, IR_SROUTINE, callee, argc_text, "", stmt->pos);
		}
		case AST_IF_STMT:
			if (stmt->as.if_stmt.is_switch_arm) return lower_if_value(b, stmt, NULL);
			return lower_if(b, stmt);
		case AST_WHILE_STMT:
			return lower_while(b, stmt);
		case AST_FOR_STMT:
			return lower_for(b, stmt);
		case AST_FN_STMT:
			return lower_fn(b, stmt);
		case AST_PROGRAM: {
			size_t i;
			for (i = 0; i < stmt->as.program.statements.len; i++) {
				if (!lower_stmt(b, stmt->as.program.statements.data[i])) {
					return false;
				}
			}
			return true;
		}
		case AST_BINARY_EXPR: case AST_ASSIGN_EXPR: case AST_UNARY_EXPR:
		case AST_IDENT_EXPR: case AST_MEMBER_EXPR: case AST_INDEX_EXPR:
		case AST_CALL_EXPR: case AST_SLICE_EXPR: case AST_NUMBER_EXPR:
		case AST_BOOL_EXPR: case AST_STRING_EXPR: case AST_ARRAY_EXPR: case AST_STRUCT_EXPR:
        case AST_UNIT_EXPR:
			return lower_expr(b, stmt, value);
		default:
			error_set(b->err, ERR_SEMANTIC, stmt->pos.line, stmt->pos.column, "unsupported statement in IR lowering");
			return false;
	}
}
bool ir_generate_from_ast(ast_node *root, IR *ir, compile_error *err) {
	ir_builder b;
	if (!root || !ir || !err) {
		return false;
	}
	error_clear(err);
	b.ir = ir;
	b.root = root;
	b.err = err;
	b.package_name = "";
	b.record_depth = 0;
    b.constant_depth = 0;
    b.local_count = 0;
	b.temp_counter = 0;
	b.label_counter = 0;
	b.loop_depth = 0;
	b.extern_count = 0;
	b.constant_count = 0;
	if (root->kind == AST_PROGRAM) {
		size_t i;
		for (i = 0; i < root->as.program.statements.len; i++) {
			ast_node *decl = root->as.program.statements.data[i];
			if (decl->kind == AST_EXTERN_DECL && b.extern_count < 128) b.externs[b.extern_count++] = decl;
			if (decl->kind == AST_CONST_DECL && b.constant_count < 128) b.constants[b.constant_count++] = decl;
		}
	}
	if (!emit_record_schemas(&b)) return false;
	return lower_stmt(&b, root);
}
