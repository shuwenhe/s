# S Language

S is a draft programming language for systems software, infrastructure, and high-performance services.

It aims to take the most valuable parts of C, Go, Rust, and C++, while avoiding the parts that most often drag down engineering experience:

- From C: hardware-level control, predictable layout, and ABI friendliness
- From Go: a unified toolchain, simple syntax, and efficient engineering workflows
- From Rust: safety by default, explicit unsafe boundaries, and robust error modeling
- From C++: RAII, zero-cost abstractions, and expressive value semantics

S is not trying to become a loose mixture of four languages. The goal is a modern systems language that is safe by default, direct to read, and backed by a complete toolchain.

## Design Statement

S is trying to answer a practical question:

Why do we always have to choose one side of the same trade-offs when building systems software?

- If we want performance, we often lose safety
- If we want safety, we often lose predictability
- If we want abstraction, we often lose compile speed and readability
- If we want engineering efficiency, we often lose low-level control

S answers with:

- safety by default, without giving up low-level control
- value semantics first, with explicit references and controlled sharing
- abstractions that should be close to zero cost instead of relying on runtime magic
- a single official toolchain instead of ecosystem fragmentation
- dangerous capabilities that exist, but are explicitly isolated behind `unsafe`

In one line:

> S = C's control + Go's tooling experience + Rust's safety boundaries + C++'s zero-cost abstractions

## Language Positioning

S is intended for:

- server-side infrastructure
- network services and gateways
- data processing and storage engines
- compilers, runtimes, and middleware
- embedded and system components
- high-performance modules that need C ABI interoperability

S is not currently trying to be:

- a business scripting language centered on GC
- a research language centered on metaprogramming
- an academic language centered on extreme type-level tricks

## Core Principles

### 1. Safety By Default

Ordinary S code should not allow obvious sources of undefined behavior by default:

- dangling references
- double free
- out-of-bounds access
- data races

Raw pointers, manual memory management, and unsafe FFI must live inside explicit `unsafe` boundaries.

### 2. Value Semantics First

S encourages:

- passing small objects by value
- releasing resources automatically when scopes end
- making ownership flow explicit

References and sharing are not the default. They are explicit choices.

### 3. Predictable Performance

S should not encourage implicit heap allocation, and it should not depend on GC for normal programming.

Developers should be able to answer questions like:

- Will this code allocate?
- Will this function call copy values?
- When is this object released?
- Does this concurrent path require synchronization?

### 4. Engineering Over Cleverness

S values:

- readability
- learnability
- maintainability
- compile speed
- deployability

The language should not force people to "defeat the language" with tricks.

### 5. One Official Toolchain

S is intended to ship with a unified set of tools:

- `s build`
- `s run`
- `s test`
- `s fmt`
- `s lint`
- `s doc`
- `s pkg`

Language tooling, package management, testing, formatting, documentation, and builds should feel like one coherent experience.

## Syntax Draft

S aims for syntax that is close to Go in clarity, while still keeping the explicitness expected from a systems language.

### Hello World

```s
package main

func Main() {
    println("hello, world")
}
```

### Variables And Constants

```s
let x = 42
f64 price = 12.5
var count = 0
const max_conn = 1024
```

Conventions:

- `let` means an immutable binding by default
- `var` means a mutable binding
- `const` means a compile-time constant

### Primitive Types

```s
bool
i8 i16 i32 i64 isize
u8 u16 u32 u64 usize
f32 f64
char
str
```

Notes:

- `str` is a UTF-8 string slice view
- growable heap strings use `String`
- byte sequences use `[]u8`

### Control Flow

```s
if score > 90 {
    grade = "A"
} else if score > 80 {
    grade = "B"
} else {
    grade = "C"
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

### Functions

```s
func Add(i32 a, i32 b) -> i32 {
    a + b
}

func openFile(str path) -> Result<File, IoError> {
    ...
}
```

Default rules:

- function signatures must be explicit
- return values use `->`
- a single-expression body may implicitly return its final expression
- visibility follows a Go-style rule: uppercase exports, lowercase stays module-local, without relying on `pub`

### Structs And Methods

```s
struct User {
    u64 id
    String name
    bool active
}

impl User {
    func Activate(mut Self self) {
        self.active = true
    }

    func displayName(Self self) -> str {
        self.name.as_str()
    }
}
```

### Enums And Pattern Matching

```s
enum Option[T] {
    Some(T)
    None
}

enum Result[T, E] {
    Ok(T)
    Err(E)
}

match result {
    Ok(value) => println(value),
    Err(err) => eprintln(err.message()),
}
```

### Generics

```s
func max[T: Ord](T a, T b) -> T {
    if a > b { a } else { b }
}
```

S supports generics, but only to the degree that they stay practical, readable, and compilable. It is not aiming for template-metaprogramming complexity.

## Type System

S uses a statically typed, strongly typed system. Type inference is supported, but unclear implicit conversions are intentionally rejected.

### Type System Goals

- friendly to newcomers
- strong enough for systems programming
- able to surface mistakes early
- controlled enough for compiler implementation

### Design Points

#### 1. No Implicit Numeric Conversion By Default

```s
i32 a = 1
i64 b = 2
let c = a as i64 + b
```

This is slightly stricter, but it avoids a large class of boundary bugs in systems code.

#### 2. Algebraic Data Types

S should support:

- `enum`
- `Option[T]`
- `Result[T, E]`
- pattern matching

That makes error handling, state modeling, and protocol modeling much more natural.

#### 3. Trait-Style Constraints

```s
trait Writer {
    func write(mut Self self, []u8 data) -> Result[usize, IoError]
}
```

Use cases:

- behavior abstraction
- generic constraints
- avoiding complex inheritance trees

#### 4. Clear Distinction Between Values, Borrows, And Ownership

S does not need to expose Rust-level lifetime complexity everywhere, but it should still preserve the core semantics:

- values have a single clear owner
- temporary borrows are scope-bound
- mutable borrows must be unique at any moment

A more engineering-oriented borrow-lite approach is possible:

- most lifetimes are inferred by the compiler
- explicit annotation is only needed in more complex cross-function borrowed return paths

### Suggested Reference Model

```s
func len(&str s) -> usize
func push(&mut Vec[i32] v, i32 value)
func consume(Buf buf) -> Result[(), Error]
```

Meaning:

- `T` means an owned value
- `&T` means an immutable borrow
- `&mut T` means a mutable borrow

This keeps the precision expected from a systems language without losing all familiarity.

## Memory And Resource Management

This is one of the core pillars of S.

### Main Path: RAII + Move Semantics

S uses scope-based resource release by default.

```s
func main() -> Result[(), IoError] {
    let file = File::open("a.txt")?
    let data = file.read_all()?
    println(data)
    Ok(())
}
```

When `file` leaves scope, its resources are released automatically.

### Not GC-First

S does not treat garbage collection as the default assumption. That helps preserve:

- steadier latency
- more predictable memory behavior
- better fit for system components and high-performance services

### Layered Memory Model

S should support three layers of memory capability:

#### 1. Safe Default Layer

- stack objects
- RAII resource objects
- standard containers

#### 2. High-Performance Control Layer

- arena allocation
- pool allocators
- custom allocators

#### 3. Dangerous Capability Layer

- raw pointers
- manual deallocation
- unmanaged memory

These capabilities should be exposed through `unsafe`.

### Unsafe Boundaries

```s
unsafe {
    *mut u8 p = alloc(1024)
    raw_write(p, 0xff)
    free(p)
}
```

Principles:

- `unsafe` is a capability switch, not a performance switch
- safe code may call well-encapsulated unsafe libraries
- unsafe implementations should be kept in a small number of modules

## Error Handling

S uses `Result[T, E]` as the primary error model. Exceptions are not intended to be the default mechanism.

### Basic Form

```s
func parse_port(str s) -> Result[u16, ParseError] {
    ...
}
```

### Propagation Operator

```s
func run() -> Result[(), Error] {
    let cfg = load_config("app.conf")?
    let conn = connect(cfg.addr)?
    conn.start()?
    Ok(())
}
```

### Unrecoverable Errors

For truly unrecoverable situations, the language may provide:

- `panic`
- `assert`
- `unreachable`

But those should not replace normal error modeling.

### Error Design Principles

- errors should compose
- errors should carry context
- error printing should be friendly
- the standard library should provide a unified error trait

For example:

```s
trait Error {
    func message(self) -> str
    func source(self) -> Option[&Error]
}
```

## Concurrency Model

The concurrency model of S should learn from both Go and Rust:

- syntax should remain simple
- data safety should remain strong

### Suggested Main Model: Structured Concurrency

```s
func main() -> Result[(), Error] {
    task::scope(|scope| {
        let a = scope.spawn(|| fetch_price("BTC-USDT"))
        let b = scope.spawn(|| fetch_price("ETH-USDT"))

        let pa = a.join()?
        let pb = b.join()?
        println(pa, pb)
    })
}
```

Properties:

- child task lifetimes are bound to the parent scope
- goroutine-leak-style problems are reduced
- this is a better fit for server-side engineering

### Channel Communication

```s
let (tx, rx) = channel[Job](1024)

spawn || {
    tx.send(job)?
}

let item = rx.recv()?
```

### Concurrency Safety Constraints

S can borrow the Rust idea in a lighter form:

- only `Send` types may move across threads
- only `Sync` types may be shared by reference across threads

```s
trait Send
trait Sync
```

### Shared Mutable State Should Not Be The Default

Preferred patterns:

- message passing
- scoped tasks
- explicit `Mutex` / `RwLock` / `Atomic`

Not unrestricted shared mutation by default.

## Modules And Packages

S should not use the C/C++ header model.

### Modules

```s
package net.http

struct Request { ... }

func parse_header(...) -> Header { ... }
```

Suggested rules:

- one file belongs to one module
- one directory forms one package
- uppercase controls export
- lowercase stays module-local

### Imports

```s
use net.http.Request
use io.{Reader, Writer}
use math as m
```

### Package Management

Each project should have a clear manifest:

```toml
[package]
name = "demo"
version = "0.1.0"
edition = "2026"

[dependencies]
http = "1.2"
json = "0.8"
```

### Versioning And Builds

S should support:

- lock files
- reproducible builds
- workspaces
- monorepo-friendly workflows

## Standard Library Direction

The standard library should be small and stable at the core, with layered packages around it.

At minimum it should include:

- core types and containers
- strings and UTF-8
- files and IO
- networking
- concurrency primitives
- time
- serialization interfaces
- a test framework
- FFI support

## FFI And System Capabilities

If S wants to become a real systems language, C ABI interoperability has to be a first-class priority.

### C FFI Example

```s
extern "C" func puts(*const u8 s) -> i32
```

Design goals:

- import C functions
- export S functions to C
- control struct layout
- make calling conventions explicit

If C FFI is weak, S will struggle to become a practical systems language.

## Trade-Offs Against C / Go / Rust / C++

### What To Learn From C

- simplicity
- predictable layout
- hardware closeness
- FFI friendliness

### What Not To Learn From C

- raw pointers by default
- macros standing in for language mechanisms
- widespread undefined behavior

### What To Learn From Go

- unified tooling
- a consistent build experience
- built-in package management and testing
- simple syntax

### What Not To Learn From Go

- deep dependence on GC
- error patterns that become repetitive boilerplate

### What To Learn From Rust

- safety by default
- `Option` / `Result`
- trait abstractions
- pattern matching
- `unsafe` boundaries

### What Not To Learn From Rust

- exposing all complexity directly to users
- forcing simple programs to drown in lifetime syntax

### What To Learn From C++

- RAII
- move semantics
- zero-cost abstractions
- strong library expressiveness

### What Not To Learn From C++

- excessive historical baggage
- rule explosion
- catastrophic template errors

## A Possible Minimal Language Subset

The first usable version of S does not need to solve everything at once.

A practical minimal subset could include only:

- primitive types
- `struct`
- `enum`
- `func`
- `let / var / const`
- `if / for / while / match`
- `Result` / `Option`
- `&` / `&mut`
- `impl` / `trait`
- `package` / `use`
- `unsafe`
- a minimal standard library
- `s build` / `s run` / `s test` / `s fmt`

That is already enough to build:

- CLI tools
- simple network services
- file-processing programs
- small systems components

## Roadmap

### Phase 0: Vision And Specification

Goals:

- make the language positioning explicit
- freeze the core syntax direction
- define the memory and error models

Deliverables:

- language manifesto
- syntax draft
- type system draft
- minimal standard library checklist

### Phase 1: Minimal Compiler

Goals:

- compile a minimal executable program
- support basic types, functions, control flow, and modules

Priority work:

- lexer
- parser
- AST
- type checker
- simple IR
- LLVM backend or a custom minimal backend

### Phase 2: Resource And Error Model

Goals:

- implement `Result`
- implement RAII
- implement the basics of move and borrow rules

Priority work:

- scope-based destruction
- ownership transfer
- the `?` operator
- pattern matching

### Phase 3: Standard Library And Toolchain

Goals:

- make the language usable for real small projects

Priority work:

- `String`
- `Vec`
- `Map`
- IO
- filesystem
- testing framework
- formatter
- package manager

### Phase 4: Concurrency And Runtime

Goals:

- support server-side workloads

Priority work:

- task runtime
- channels
- timers
- socket APIs
- structured concurrency

### Phase 5: FFI And Ecosystem Integration

Goals:

- coexist with the C ecosystem
- build system modules and high-performance services

Priority work:

- C ABI
- shared/static library output
- allocator APIs
- profiling hooks

## Success Criteria

If S is successful, it should satisfy the following:

- an engineer familiar with Go can become productive in a few days
- an engineer familiar with Rust does not feel it is too unsafe to use
- an engineer familiar with C/C++ does not feel that it has lost control
- a medium-sized service can be built naturally without depending on GC
- the toolchain experience is more unified than in traditional systems languages

## Current Status

S is still in the design-draft stage in this repository.

At the same time, self-hosting work has already started. The first S-native compiler skeleton lives in:

- [selfhost.md](/app/s/doc/selfhost.md)
- [ast.s](/app/s/src/s/ast.s)
- [tokens.s](/app/s/src/s/tokens.s)
- [main.s](/app/s/src/cmd/compiler/main.s)
- [backend_elf64.s](/app/s/src/cmd/compiler/backend_elf64.s)
- [s.s](/app/s/src/cmd/s/main.s)
- [backend_elf64.md](/app/s/doc/backend_elf64.md)
- [self_hosting.md](/app/s/doc/self_hosting.md)

The most valuable next steps are:

1. write a formal syntax draft
2. define precise borrow-lite rules
3. design the `trait` and generic instantiation strategy
4. design the minimal standard-library API
5. decide on the compiler implementation path and IR strategy

## License And Collaboration Direction

Discussion and iteration are especially welcome around:

- whether the syntax is simple enough
- whether the ownership model is practical enough
- whether concurrency should lean more toward Go or Rust
- where the standard library boundary should sit
- whether an edition mechanism is needed for future evolution

S is not trying to reinvent everything. It is trying to recombine modern systems-language ideas that have already proven valuable into something more unified, more learnable, and better suited to real engineering work.
