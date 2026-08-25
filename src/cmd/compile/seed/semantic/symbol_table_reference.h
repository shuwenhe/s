#ifndef SYMBOL_TABLE_H
#define SYMBOL_TABLE_H

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

typedef struct symbol symbol;

typedef struct symbol_entry {
    symbol *value;
    struct symbol_entry *next;  
} symbol_entry;

typedef struct {
    symbol_entry **buckets;     
    size_t capacity;             
    size_t size;                 
    symbol *last_found;          
    char last_found_name[256];   

    size_t entry_pool_capacity;
    symbol_entry *entry_pool;
    size_t entry_pool_pos;
} symbol_table;

static inline uint32_t hash_string(const char *str) {
    uint32_t hash = 2166136261u;
    const unsigned char *p = (const unsigned char *)str;
    while (*p) {
        hash ^= *p++;
        hash *= 16777619u;
    }
    return hash;
}

symbol_table *symbol_table_new(size_t initial_capacity);

void symbol_table_free(symbol_table *table);

bool symbol_table_insert(symbol_table *table, const char *name, symbol *sym);

symbol *symbol_table_lookup(symbol_table *table, const char *name);

bool symbol_table_remove(symbol_table *table, const char *name);

void symbol_table_clear(symbol_table *table);

static inline float symbol_table_load_factor(symbol_table *table) {
    return (float)table->size / table->capacity;
}

#endif
