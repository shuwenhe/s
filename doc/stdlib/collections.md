# std.collections

Development API for persistent collections on Linux/amd64. Ordered maps and sets accept **string keys**; map/vector/stack/queue values are generic. Constructors infer value types from ordinary typed arrays. No explicit type-argument call syntax or hidden raw pointer is required.

```s
package main
import "std.collections"
func main() int {
    values, error := std.collections.new_map(string[]{"answer"},int[]{42})
    if error.code != 0 { return error.code }
    return std.collections.map_get(values,"answer").unwrap_or(0)
}
```

| API | Result and behavior |
|---|---|
| `new_map(string[] keys,v[] values)` | `(ordered_map[v],collection_error)`; equal array lengths required; last duplicate wins |
| `map_get(ordered_map[v],string)` | `option[v]`; absent key is none, distinct from a stored false/zero/empty value |
| `map_put(ordered_map[v],string,v)` | `(ordered_map[v],collection_error)`; inserts or replaces |
| `map_remove(ordered_map[v],string)` | new map; missing key leaves the value unchanged |
| `new_set(string[])`, `set_add(set,string)` | `(set,collection_error)`; duplicate keys do not grow the set |
| `set_contains(set,string)`, `set_remove(set,string)` | boolean membership / new set |
| `new_vector(t[])` | `(vector[t],collection_error)`; indexed growable sequence |
| `vector_get(vector[t],int)` | option; invalid/negative index is none |
| `vector_push(vector[t],t)` | `(vector[t],collection_error)` |
| `vector_set(vector[t],int,t)` | `(vector[t],collection_error)`; invalid index preserves original value |
| `vector_pop(vector[t])` | `(vector[t],option[t])`; removes last element, none when empty |
| `new_stack(t[])`, `stack_push(stack[t],t)` | `(stack[t],collection_error)`; input array is bottom-to-top |
| `stack_pop(stack[t])` | `(stack[t],option[t])`; last-in-first-out |
| `new_queue(t[])`, `enqueue(queue[t],t)` | `(queue[t],collection_error)`; input order is FIFO |
| `dequeue(queue[t])` | `(queue[t],option[t])`; none when empty |
| `entries(ordered_map[v])` | snapshot iterator in ascending unsigned byte-string key order |
| `next_entry(iterator[v])` | `(iterator[v],option[entry[v]])`; entry has key/value; exhaustion stays none |

Error code zero is success; EINVAL 22 covers mismatched map constructor arrays and invalid vector updates. EOVERFLOW 75 prevents length growth past signed int64. Allocation exhaustion follows the runtime allocation policy and is not recoverable through these error values. Use constructors and functions; representation fields and helpers beginning `_` are implementation details and must not be forged or modified.

All updates return new S values. Retained collections and iterators preserve their previous contents. Retrieved array/record values follow ordinary S snapshot semantics; mutating them cannot change an older collection. Each container's `length` records its size; set size is its storage map's length, and stack size is its storage vector's length in this initial API.

The shared representation is an immutable AVL tree with zero/one-element child arrays, heights and subtree counts. Each update reconstructs a search path, sharing unchanged subtrees. Native map/vector/stack operations take O(log n) tree steps; string comparison also depends on key length. Vector indices use 19-byte zero-padded decimal keys, so numeric and lexical index ordering agree. This vector is an indexed persistent sequence, not contiguous mutable storage. Queue reversal costs O(n log n) when the front is empty, amortized O(log n) per operation. Iteration selects each next rank in O(log n) and retains the original map snapshot. No hash function, randomized balancing or new allocator intrinsic is introduced.

The Seed runtime performs more aggregate snapshots than the canonical native runtime. Seed functionality is tested, but native performance measurements must not be attributed to Seed or unverified self-hosted stages. Numeric/composite map keys, concurrent mutation, contiguous storage guarantees and final stage certification remain outside this increment.

Run `python3 test/stdlib-native/test_collections.py -v` for native ELF, Seed execution, randomized model/invariant checks, snapshot/invalid-input/type negatives and scaling measurements.
