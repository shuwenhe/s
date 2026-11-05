# std.string

Development byte-string API, Linux/amd64 native and standalone seed. Import `"std.string"`. Strings are immutable S values; byte indices do not imply Unicode character boundaries. ASCII case/space operations leave other bytes unchanged.

| API | Contract |
|---|---|
| `byte_at(string,int)` | `(int,string_error)`; index must address an existing byte |
| `from_byte(int)` | `(string,string_error)`; accepts 0–255, including NUL |
| `slice(string,int start,int end)` | `(string,string_error)`; half-open, 0 <= start <= end <= length |
| `compare(string,string)` | -1, 0, 1; unsigned lexicographic byte order |
| `index_of(string text,string needle)` | first byte index or -1; empty needle returns 0 |
| `find_from(string,string,int start)` | `(int,string_error)`; start 0–length; empty needle returns start |
| `contains`, `starts_with`, `ends_with` | boolean comparisons; empty needle/prefix/suffix matches |
| `split(string,string separator)` | `(string[],string_error)`; nonoverlapping matches; keeps leading/trailing/adjacent empty fields; empty separator rejects |
| `join(string[],string separator)` | joins fields, empty array produces empty string |
| `replace(string,string old,string replacement)` | `(string,string_error)`; replaces all nonoverlapping matches; empty old rejects |
| `trim_ascii(string)` | trims bytes 9–13 and 32 from both ends |
| `lower_ascii`, `upper_ascii` | ASCII-only case conversion |
| `parse_int(string)` | `(int,string_error)`; optional single sign, then decimal digits; exact signed int64 bounds |
| `format_int(int)` | existing runtime signed decimal formatting |

Error code zero is success, EINVAL 22 indicates invalid arguments/decimal spelling, ERANGE 34 indicates integer overflow. Parsing stops at the first invalid/overflow condition; it does not accept whitespace, prefixes or separators. Returned arrays use normal snapshot semantics. Allocation exhaustion follows the runtime's fatal allocation policy rather than a recoverable typed error. Helpers beginning with `_` and intrinsic declarations are implementation details.

Search uses critical factorization and constant-space Two-Way matching, avoiding quadratic prefix-table copies under current array semantics. Split counts fields, then builds a balanced tree using a narrowly typed immutable string-array concatenation bridge; output assembly copies O(k log k) array elements for k fields. Join and case conversion also use balanced assembly, with bounded 64-byte case-conversion leaves. None of these operations claims zero-copy slicing or Unicode normalization.

`python3 test/stdlib-native/test_string.py -v` compiles and executes the API fixture with both compilers, checks integer/binary/boundary behavior, exhaustive small binary strings, a 32 KiB repetitive needle and 16,385-field split, plus 100 deterministic Python search/split/replace oracle cases. Performance observations and final acceptance are recorded after execution; final self-hosted stage certification is separate.
