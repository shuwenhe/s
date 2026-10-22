/* Private to standalone_amd64_backend.c. No hosted execution or C fallback. */
static int standalone_record_index(const standalone_module *m, const char *name) {
    size_t i;
    for (i = 0; i < m->record_count; i++) if (strcmp(m->records[i].name, name) == 0) return (int)i;
    return -1;
}
static int standalone_record_literal(standalone_module *m, const char *name, compile_error *err) {
    char encoded[STANDALONE_TEXT_CAP];
    if (strchr(name, '"') || strchr(name, '\\') ||
        snprintf(encoded, sizeof(encoded), "\"%s\"", name) >= (int)sizeof(encoded)) {
        error_set(err, ERR_SEMANTIC, 0, 0, "invalid record metadata name"); return -1;
    }
    return literal_index(m, encoded, err);
}
static void standalone_free_record_schemas(standalone_module *m) {
    size_t i;
    if (!m) return;
    for (i = 0; i < m->record_count; i++) free(m->records[i].fields);
    free(m->records);
}
static bool standalone_collect_record_schemas(standalone_module *m, compile_error *err) {
    size_t i;
    for (i = 0; i < m->ir.len; i++) {
        standalone_ins *ins = &m->ir.ins[i];
        if (strcmp(ins->op, "NOP") || strncmp(ins->result, "record-type:", 12)) continue;
        const char *name = ins->result + 12;
        if (!*name || standalone_record_index(m, name) >= 0) {
            error_set(err, ERR_SEMANTIC, 0, 0, "duplicate or empty record schema at IR record %zu", i + 2); return false;
        }
        standalone_record_schema *next = realloc(m->records, (m->record_count + 1) * sizeof(*next));
        if (!next) { error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "record schema allocation failed"); return false; }
        m->records = next;
        standalone_record_schema *r = &m->records[m->record_count++];
        memset(r, 0, sizeof(*r));
        copy_text(r->name, sizeof(r->name), name);
        r->type_literal = standalone_record_literal(m, name, err);
        if (r->type_literal < 0) return false;
    }
    for (i = 0; i < m->ir.len; i++) {
        standalone_ins *ins = &m->ir.ins[i];
        if (strcmp(ins->op, "NOP") || strncmp(ins->result, "record-field:", 13)) continue;
        int index = standalone_record_index(m, ins->result + 13);
        if (index < 0 || !*ins->operand1 || !strcmp(ins->operand1, "_") || !*ins->operand2 || !strcmp(ins->operand2, "_")) {
            error_set(err, ERR_SEMANTIC, 0, 0, "invalid record field metadata at IR record %zu", i + 2); return false;
        }
        standalone_record_schema *r = &m->records[index];
        size_t j;
        for (j = 0; j < r->count; j++) if (!strcmp(r->fields[j].name, ins->operand1)) {
            error_set(err, ERR_SEMANTIC, 0, 0, "duplicate record field %s.%s", r->name, ins->operand1); return false;
        }
        standalone_record_field *next = realloc(r->fields, (r->count + 1) * sizeof(*next));
        if (!next) { error_set(err, ERR_OUT_OF_MEMORY, 0, 0, "record field allocation failed"); return false; }
        r->fields = next;
        standalone_record_field *f = &r->fields[r->count++];
        memset(f, 0, sizeof(*f)); f->kind = -1; f->nested = -1;
        copy_text(f->name, sizeof(f->name), ins->operand1);
        copy_text(f->type, sizeof(f->type), ins->operand2);
        f->name_literal = standalone_record_literal(m, f->name, err);
        if (f->name_literal < 0) return false;
    }
    return true;
}
static bool standalone_validate_record_schema(standalone_module *m, int index, compile_error *err) {
    standalone_record_schema *r = &m->records[index];
    size_t i;
    if (r->state == 2) return true;
    if (r->state == 1) return true; /* Eligibility cycles may cross an array. */
    r->state = 1;
    for (i = 0; i < r->count; i++) {
        standalone_record_field *f = &r->fields[i];
        const char *t = f->type;
        if (!strcmp(t, "int") || !strcmp(t, "bool") || !strcmp(t, "byte") ||
            !strcmp(t, "int64") || !strcmp(t, "uint64") || !strcmp(t, "uint")) f->kind = 0;
        else if (!strcmp(t, "string")) f->kind = 1;
        else if (strchr(t, '*') || strchr(t, '&') || !strncmp(t, "own ", 4) || !strcmp(t, "box") || !strncmp(t, "box[", 4) || !strncmp(t, "ref ", 4) || !strncmp(t, "mutref ", 7)) {
            error_set(err, ERR_SEMANTIC, 0, 0, "native record transfer unsupported_owner or unproven borrow: %s.%s (%s)", r->name, f->name, t); return false;
        } else {
            char base[STANDALONE_TEXT_CAP], qualified[STANDALONE_TEXT_CAP];
            size_t n = strlen(t);
            bool array = n >= 2 && !strcmp(t + n - 2, "[]");
            copy_text(base, sizeof(base), t);
            if (array) base[n - 2] = '\0';
            f->nested = standalone_record_index(m, base);
            const char *dot = strrchr(r->name, '.');
            if (f->nested < 0 && dot && !strchr(base, '.')) {
                if (snprintf(qualified, sizeof(qualified), "%.*s.%s", (int)(dot - r->name), r->name, base) < (int)sizeof(qualified))
                    f->nested = standalone_record_index(m, qualified);
            }
            if (array) {
                if (f->nested < 0 && strcmp(base, "int") && strcmp(base, "bool") && strcmp(base, "string") && strcmp(base, "byte")) {
                    error_set(err, ERR_SEMANTIC, 0, 0, "unknown native array transfer type: %s", t); return false;
                }
                f->kind = 2;
                if (f->nested >= 0 && m->records[f->nested].state != 1 && !standalone_validate_record_schema(m, f->nested, err)) return false;
            } else if (f->nested >= 0) {
                f->kind = 3;
                if (!standalone_validate_record_schema(m, f->nested, err)) return false;
            } else {
                error_set(err, ERR_SEMANTIC, 0, 0, "unknown native record transfer type: %s.%s (%s)", r->name, f->name, t); return false;
            }
        }
    }
    r->state = 2;
    return true;
}
/* Empty arrays stop default construction; only direct record edges can
 * create an infinitely sized by-value default. Check independently of the
 * ownership traversal, whose path may contain arrays. */
static bool standalone_validate_record_defaults(standalone_module *m, int index, compile_error *err) {
    standalone_record_schema *r = &m->records[index];
    if (r->default_state == 2) return true;
    if (r->default_state == 1) {
        error_set(err, ERR_SEMANTIC, 0, 0, "recursive by-value record schema: %s", r->name); return false;
    }
    r->default_state = 1;
    for (size_t i = 0; i < r->count; i++)
        if (r->fields[i].kind == 3 && !standalone_validate_record_defaults(m, r->fields[i].nested, err)) return false;
    r->default_state = 2;
    return true;
}
static bool standalone_validate_record_contracts(standalone_module *m, compile_error *err) {
    size_t i;
    bool in_function = false;
    for (i = 0; i < m->ir.len; i++) {
        standalone_ins *ins = &m->ir.ins[i];
        if (!strcmp(ins->op, "NOP") &&
            (!strncmp(ins->result, "param-transfer:", 15) || !strncmp(ins->result, "return-transfer:", 16))) {
            const char *t = ins->operand2;
            if (strchr(t, '*') || strchr(t, '&') || !strcmp(t, "box") || !strncmp(t, "own ", 4) ||
                !strncmp(t, "ref ", 4) || !strncmp(t, "mutref ", 7)) {
                error_set(err, ERR_SEMANTIC, 0, 0, "native record transfer unsupported_owner or unproven borrow at IR record %zu: %s", i+2, t); return false;
            }
        }
        if (!strcmp(ins->op, "FUNC_BEGIN")) in_function = true;
        if (!strcmp(ins->op, "FUNC_END")) in_function = false;
        if (!in_function || strcmp(ins->op, "MOV")) continue;
        size_t n = strlen(ins->result);
        if (n < 7 || strcmp(ins->result + n - 7, ".__type") || !is_string_literal(ins->operand1)) continue;
        standalone_literal type;
        if (!decode_literal(ins->operand1, &type, err)) return false;
        type.bytes[type.len] = 0;
        int index = standalone_record_index(m, (char *)type.bytes);
        if (index < 0) {
            /* Typed array construction and legacy enum/result objects are
             * separate existing representations, not guessed record schemas. */
            if (strchr((char *)type.bytes, '[')) continue;
            error_set(err, ERR_SEMANTIC, 0, 0, "missing native record schema: %s at IR record %zu", type.bytes, i + 2); return false;
        }
        if (!standalone_validate_record_schema(m, index, err)) return false;
    }
    for (i = 0; i < m->record_count; i++)
        if (m->records[i].state == 2 && !standalone_validate_record_defaults(m, (int)i, err)) return false;
    return true;
}
