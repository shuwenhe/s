# s language

S-language is the native language of Artificial Intelligence.S is a draft programming language for systems software, infrastructure, and high-performance services.

it aims to take the most valuable parts of c, go, rust, and c++, while avoiding the parts that most often drag down engineering experience:

- from c: hardware-level control, predictable layout, and abi friendliness
- from go: a unified toolchain, simple syntax, and efficient engineering workflows
- from rust: safety by default, explicit unsafe boundaries, and robust error modeling
- from c++: raii, zero-cost abstractions, and expressive value semantics

s is not trying to become a loose mixture of four languages. the goal is a modern systems language that is safe by default, direct to read, and backed by a complete toolchain.

## design statement

s is trying to answer a practical question:

why do we always have to choose one side of the same trade-offs when building systems software?

- if we want performance, we often lose safety
- if we want safety, we often lose predictability
- if we want abstraction, we often lose compile speed and readability
- if we want engineering efficiency, we often lose low-level control

s answers with:

- safety by default, without giving up low-level control
- value semantics first, with explicit references and controlled sharing
- abstractions that should be close to zero cost instead of relying on runtime magic
- a single official toolchain instead of ecosystem fragmentation
- dangerous capabilities that exist, but are explicitly isolated behind `unsafe`

in one line:

> s = c's control + go's tooling experience + rust's safety boundaries + c++'s zero-cost abstractions

## language positioning

s is intended for:

- server-side infrastructure
- network services and gateways
- data processing and storage engines
- compilers, runtimes, and middleware
- embedded and system components
- high-performance modules that need c abi interoperability

s is not currently trying to be:

- a business scripting language centered on gc
- a research language centered on metaprogramming
- an academic language centered on extreme type-level tricks

## core principles

### 1. safety by default

ordinary s code should not allow obvious sources of undefined behavior by default:

- dangling references
- double free
- out-of-bounds access
- data races

raw pointers, manual memory management, and unsafe ffi must live inside explicit `unsafe` boundaries.

### 2. value semantics first

s encourages:

- passing small objects by value
- releasing resources automatically when scopes end
- making ownership flow explicit

references and sharing are not the default. they are explicit choices.

### 3. predictable performance

s should not encourage implicit heap allocation, and it should not depend on gc for normal programming.

developers should be able to answer questions like:

- will this code allocate?
- will this function call copy values?
- when is this object released?
- does this concurrent path require synchronization?

### 4. engineering over cleverness

s values:

- readability
- learnability
- maintainability
- compile speed
- deployability

the language should not force people to "defeat the language" with tricks.

### 5. one official toolchain

s is intended to ship with a unified set of tools:

- `s build`
- `s run`
- `s test`
- `s fmt`
- `s lint`
- `s doc`
- `s pkg`

language tooling, package management, testing, formatting, documentation, and builds should feel like one coherent experience.

## syntax draft

s aims for syntax that is close to go in clarity, while still keeping the explicitness expected from a systems language.

### hello world

```s
package main

func main() {
    println("hello, world")
}
```

### variables and constants

```s
var x = 42
f64 price = 12.5
var count = 0
const max_conn = 1024
```

conventions:

- `var` means an immutable binding by default
- `var` means a mutable binding
- `const` means a compile-time constant

### primitive types

```s
bool
i8 i16 int32 i64 isize
u8 u16 u32 u64 usize
f32 f64
char
str
```

notes:

- `str` is a utf-8 string slice view
- growable heap strings use `string`
- byte sequences use `[]u8`

### control flow

```s
if score > 90 {
    grade = "a"
} else if score > 80 {
    grade = "b"
} else {
    grade = "c"
}

for item in items {
    println(item)
}

for i in 0..10 {
    println(i)
}

while running {
    tick()
}
```

### functions

```s
func add(int32 a, int32 b) int32 {
    a + b
}

func openfile(str path) result<file, ioerror> {
    ...
}
```

default rules:

- function signatures must be explicit
- return values use ` `
- a single-expression body may implicitly return its final expression
- visibility follows a go-style rule: uppercase exports, lowercase stays module-local, without relying on `pub`

### structs and methods

```s
struct user {
    u64 id
    string name
    bool active
}

impl user {
    func activate(mut self self) {
        self.active = true
    }

    func displayname(self self) str {
        self.name.as_str()
    }
}
```

### enums and pattern matching

```s
enum option[t] {
    some(t)
    none
}

enum result[t, e] {
    ok(t)
    err(e)
}

match result {
    ok(value) => println(value),
    err(err) => eprintln(err.message()),
}
```

### generics

```s
func max[t: ord](t a, t b) t {
    if a > b { a } else { b }
}
```

s supports generics, but only to the degree that they stay practical, readable, and compilable. it is not aiming for template-metaprogramming complexity.

## type system

s uses a statically typed, strongly typed system. type inference is supported, but unclear implicit conversions are intentionally rejected.

### type system goals

- friendly to newcomers
- strong enough for systems programming
- able to surface mistakes early
- controlled enough for compiler implementation

### design points

#### 1. no implicit numeric conversion by default

```s
int32 a = 1
i64 b = 2
var c = a as i64 + b
```

this is slightly stricter, but it avoids a large class of boundary bugs in systems code.

#### 2. algebraic data types

s should support:

- `enum`
- `option[t]`
- `result[t, e]`
- pattern matching

that makes error handling, state modeling, and protocol modeling much more natural.

#### 3. trait-style constraints

```s
trait writer {
    func write(mut self self, []u8 data) result[usize, ioerror]
}
```

use cases:

- behavior abstraction
- generic constraints
- avoiding complex inheritance trees

#### 4. clear distinction between values, borrows, and ownership

s does not need to expose rust-level lifetime complexity everywhere, but it should still preserve the core semantics:

- values have a single clear owner
- temporary borrows are scope-bound
- mutable borrows must be unique at any moment

a more engineering-oriented borrow-lite approach is possible:

- most lifetimes are inferred by the compiler
- explicit annotation is only needed in more complex cross-function borrowed return paths

### suggested reference model

```s
func len(&str s) usize
func push(&mut vec[int32] v, int32 value)
func consume(buf buf) result[(), error]
```

meaning:

- `t` means an owned value
- `&t` means an immutable borrow
- `&mut t` means a mutable borrow

this keeps the precision expected from a systems language without losing all familiarity.

## memory and resource management

this is one of the core pillars of s.

### main path: raii + move semantics

s uses scope-based resource release by default.

```s
func main() result[(), ioerror] {
    var file = file::open("a.txt")?
    var data = file.read_all()?
    println(data)
    ok(())
}
```

when `file` leaves scope, its resources are released automatically.

### not gc-first

s does not treat garbage collection as the default assumption. that helps preserve:

- steadier latency
- more predictable memory behavior
- better fit for system components and high-performance services

### layered memory model

s should support three layers of memory capability:

#### 1. safe default layer

- stack objects
- raii resource objects
- standard containers

#### 2. high-performance control layer

- arena allocation
- pool allocators
- custom allocators

#### 3. dangerous capability layer

- raw pointers
- manual deallocation
- unmanaged memory

these capabilities should be exposed through `unsafe`.

### unsafe boundaries

```s
unsafe {
    *mut u8 p = alloc(1024)
    raw_write(p, 0xff)
    free(p)
}
```

principles:

- `unsafe` is a capability switch, not a performance switch
- safe code may call well-encapsulated unsafe libraries
- unsafe implementations should be kept in a small number of modules

## error handling

s uses `result[t, e]` as the primary error model. exceptions are not intended to be the default mechanism.

### basic form

```s
func parse_port(str s) result[u16, parseerror] {
    ...
}
```

### propagation operator

```s
func run() result[(), error] {
    var cfg = load_config("app.conf")?
    var conn = connect(cfg.addr)?
    conn.start()?
    ok(())
}
```

### unrecoverable errors

for truly unrecoverable situations, the language may provide:

- `panic`
- `assert`
- `unreachable`

but those should not replace normal error modeling.

### error design principles

- errors should compose
- errors should carry context
- error printing should be friendly
- the standard library should provide a unified error trait

for example:

```s
trait error {
    func message(self) str
    func source(self) option[&error]
}
```

## concurrency model

the concurrency model of s should learn from both go and rust:

- syntax should remain simple
- data safety should remain strong

### suggested main model: structured concurrency

```s
func main() result[(), error] {
    task::scope(|scope| {
        var a = scope.spawn(|| fetch_price("btc-usdt"))
        var b = scope.spawn(|| fetch_price("eth-usdt"))

        var pa = a.join()?
        var pb = b.join()?
        println(pa, pb)
    })
}
```

properties:

- child task lifetimes are bound to the parent scope
- goroutine-leak-style problems are reduced
- this is a better fit for server-side engineering

### channel communication

```s
var (tx, rx) = channel[job](1024)

spawn || {
    tx.send(job)?
}

var item = rx.recv()?
```

### concurrency safety constraints

s can borrow the rust idea in a lighter form:

- only `send` types may move across threads
- only `sync` types may be shared by reference across threads

```s
trait send
trait sync
```

### shared mutable state should not be the default

preferred patterns:

- message passing
- scoped tasks
- explicit `mutex` / `rwlock` / `atomic`

not unrestricted shared mutation by default.

## modules and packages

s should not use the c/c++ header model.

### modules

```s
package net.http

struct request { ... }

func parse_header(...) header { ... }
```

suggested rules:

- one file belongs to one module
- one directory forms one package
- uppercase controls export
- lowercase stays module-local

### imports

```s
use net.http.request
use io.{reader, writer}
use math as m
```

### package management

each project should have a clear manifest:

```toml
[package]
name = "demo"
version = "0.1.0"
edition = "2026"

[dependencies]
http = "1.2"
json = "0.8"
```

### versioning and builds

s should support:

- lock files
- reproducible builds
- workspaces
- monorepo-friendly workflows

## standard library direction

the standard library should be small and stable at the core, with layered packages around it.

at minimum it should include:

- core types and containers
- strings and utf-8
- files and io
- networking
- concurrency primitives
- time
- serialization interfaces
- a test framework
- ffi support

## ffi and system capabilities

if s wants to become a real systems language, c abi interoperability has to be a first-class priority.

### c ffi example

```s
extern "c" func puts(*const u8 s) int32
```

design goals:

- import c functions
- export s functions to c
- control struct layout
- make calling conventions explicit

if c ffi is weak, s will struggle to become a practical systems language.

## trade-offs against c / go / rust / c++

### what to learn from c

- simplicity
- predictable layout
- hardware closeness
- ffi friendliness

### what not to learn from c

- raw pointers by default
- macros standing in for language mechanisms
- widespread undefined behavior

### what to learn from go

- unified tooling
- a consistent build experience
- built-in package management and testing
- simple syntax

### what not to learn from go

- deep dependence on gc
- error patterns that become repetitive boilerplate

### what to learn from rust

- safety by default
- `option` / `result`
- trait abstractions
- pattern matching
- `unsafe` boundaries

### what not to learn from rust

- exposing all complexity directly to users
- forcing simple programs to drown in lifetime syntax

### what to learn from c++

- raii
- move semantics
- zero-cost abstractions
- strong library expressiveness

### what not to learn from c++

- excessive historical baggage
- rule explosion
- catastrophic template errors

## a possible minimal language subset

the first usable version of s does not need to solve everything at once.

a practical minimal subset could include only:

- primitive types
- `struct`
- `enum`
- `func`
- `var / var / const`
- `if / for / while / match`
- `result` / `option`
- `&` / `&mut`
- `impl` / `trait`
- `package` / `use`
- `unsafe`
- a minimal standard library
- `s build` / `s run` / `s test` / `s fmt`

that is already enough to build:

- cli tools
- simple network services
- file-processing programs
- small systems components

## roadmap

### phase 0: vision and specification

goals:

- make the language positioning explicit
- freeze the core syntax direction
- define the memory and error models

deliverables:

- language manifesto
- syntax draft
- type system draft
- minimal standard library checklist

### phase 1: minimal compiler

goals:

- compile a minimal executable program
- support basic types, functions, control flow, and modules

priority work:

- lexer
- parser
- ast
- type checker
- simple ir
- llvm backend or a custom minimal backend

### phase 2: resource and error model

goals:

- implement `result`
- implement raii
- implement the basics of move and borrow rules

priority work:

- scope-based destruction
- ownership transfer
- the `?` operator
- pattern matching

### phase 3: standard library and toolchain

goals:

- make the language usable for real small projects

priority work:

- `string`
- `vec`
- `map`
- io
- filesystem
- testing framework
- formatter
- package manager

### phase 4: concurrency and runtime

goals:

- support server-side workloads

priority work:

- task runtime
- channels
- timers
- socket apis
- structured concurrency

### phase 5: ffi and ecosystem integration

goals:

- coexist with the c ecosystem
- build system modules and high-performance services

priority work:

- c abi
- shared/static library output
- allocator apis
- profiling hooks

## success criteria

if s is successful, it should satisfy the following:

- an engineer familiar with go can become productive in a few days
- an engineer familiar with rust does not feel it is too unsafe to use
- an engineer familiar with c/c++ does not feel that it has lost control
- a medium-sized service can be built naturally without depending on gc
- the toolchain experience is more unified than in traditional systems languages

## current status

s is still in the design-draft stage in this repository.

at the same time, self-hosting work has already started. the first s_arm64 compiler skeleton lives in:

- [selfhost.md](/app/s/doc/selfhost.md)
- [ast.s](/app/s/src/s/ast.s)
- [tokens.s](/app/s/src/s/tokens.s)
- [main.s](/app/s/src/cmd/compile/internal/main.s)
- [backend_elf64.s](/app/s/src/cmd/compile/internal/backend_elf64.s)
- [s.s](/app/s/src/cmd/s/main.s)
- [backend_elf64.md](/app/s/doc/backend_elf64.md)
- [self_hosting.md](/app/s/doc/self_hosting.md)

the most valuable next steps are:

1. write a formal syntax draft
2. define precise borrow-lite rules
3. design the `trait` and generic instantiation strategy
4. design the minimal standard-library api
5. decide on the compiler implementation path and ir strategy

## license and collaboration direction

discussion and iteration are especially welcome around:

- whether the syntax is simple enough
- whether the ownership model is practical enough
- whether concurrency should lean more toward go or rust
- where the standard library boundary should sit
- whether an edition mechanism is needed for future evolution

s is not trying to reinvent everything. it is trying to recombine modern systems-language ideas that have already proven valuable into something more unified, more learnable, and better suited to real engineering work.

## mainline smoke test (current closure)

To verify the current S toolchain closure, run:

```bash
./bin/scripts/mainline_smoketest.sh
```

This will:
- Check misc/examples/s/hello.s
- Compile misc/examples/s/hello.s to IR
- Emit a native artifact from IR and validate outputs exist

This script is suitable for CI as the current minimal closure acceptance.

## how to compile

current minimal compile flow uses the repo-local wrapper:

```bash
./bin/s check misc/examples/s/hello.s
./bin/s ir misc/examples/s/hello.s -o /tmp/hello.ir
./bin/s emit-bin /tmp/hello.ir -o /tmp/s_compiler_from_hello
```

expected result:
- `check` prints `ok: misc/examples/s/hello.s`
- `ir` writes `/tmp/hello.ir`
- `emit-bin` writes `/tmp/s_compiler_from_hello`

## how to run

current native output from `emit-bin` is a compiler artifact, so run mode is:

```bash
/tmp/s_compiler_from_hello --help
```

for one-command closure verification, run:

```bash
./bin/scripts/mainline_smoketest.sh
```

## example program

the minimal example is:

```s
package main

func main() {
    println("hello, world")
}
```

source file:
- `misc/examples/s/hello.s`

quick check command:

```bash
./bin/s check misc/examples/s/hello.s
```

## local run example (/app/test/main.s)

example source:

```s
package main

func main() {
    println("hello, world")
}
```

run command:

```bash
cd /app/test
s run main.s
```

expected output:

```text
hello, world
```

## how to test

`s test` now supports two modes:

- smoke mode (default): stable green subset for day-to-day checks
- full mode (`--all`): full fixture sweep for capability tracking

### smoke mode (default)

command:

```bash
s test
```

example output:

```text
running smoke fixture suite: /app/s/src/cmd/compile/internal/tests/fixtures
ok: /app/s/src/cmd/compile/internal/tests/fixtures/binary_sample.s
ok (expected fail): /app/s/src/cmd/compile/internal/tests/fixtures/borrow_fail.s
ok (expected fail): /app/s/src/cmd/compile/internal/tests/fixtures/branch_move_fail.s
ok: /app/s/src/cmd/compile/internal/tests/fixtures/builtin_field_ok.s
ok (expected fail): /app/s/src/cmd/compile/internal/tests/fixtures/check_fail.s
ok (expected fail): /app/s/src/cmd/compile/internal/tests/fixtures/generic_bound_fail.s
ok (expected fail): /app/s/src/cmd/compile/internal/tests/fixtures/method_conflict_fail.s
test summary: total=7 passed=7 failed=0
```

### full mode (capability tracking)

command:

```bash
s test --all
```

example output:

```text
running full fixture suite: /app/s/src/cmd/compile/internal/tests/fixtures
ok: /app/s/src/cmd/compile/internal/tests/fixtures/binary_sample.s
ok (expected fail): /app/s/src/cmd/compile/internal/tests/fixtures/borrow_fail.s
ok (expected fail): /app/s/src/cmd/compile/internal/tests/fixtures/branch_move_fail.s
ok: /app/s/src/cmd/compile/internal/tests/fixtures/builtin_field_ok.s
FAIL (unexpected error): /app/s/src/cmd/compile/internal/tests/fixtures/cfor_sample.s
ok (expected fail): /app/s/src/cmd/compile/internal/tests/fixtures/check_fail.s
...
test summary: total=15 passed=7 failed=8
```

you can also pass a custom fixtures root:

```bash
s test /app/s/src/cmd/compile/internal/tests/fixtures
s test --all /app/s/src/cmd/compile/internal/tests/fixtures
```
