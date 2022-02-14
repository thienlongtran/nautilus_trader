# Rust

The [Rust](https://www.rust-lang.org/learn) programming language is an ideal fit for implementing the mission-critical core of the
platform and systems. This is because Rust will ensure that it is free of memory errors and
data race conditions, being 'correct by construction' through its formal specification of types, ownership
and lifetimes at compile time. 

Also, because of the lack of a built-in runtime and garbage collector, and because
the language itself can access the lowest level primitives, we can expect the eventual implementations
to be highly performant. This combination of correctness and performance is highly valued for a HFT platform.

## Python Binding
Interoperating between Python and Rust can be achieved by binding a C-ABI compatible interface from the Rust FFI with
Cython. This approach is to aid a smooth transition to greater amounts
of Rust in the codebase, and reducing amounts of Cython (which will eventually be eliminated). 
In the future [PyO3](https://github.com/PyO3/PyO3) will be used.

## Unsafe Rust
It will be necessary to write `unsafe` Rust code to be able to achieve the value
of interoperating between Python and Rust. The ability to step outside the boundaries of safe Rust is what makes it possible to
implement many of the most fundamental features of the Rust language itself, just as C and C++ are used to implement
their own standard libraries.

Great care will be taken with the use of Rusts `unsafe` facility (which just enables a small set of additional language features), thereby changing
the contract between code and caller, shifting some responsibility for guaranteeing correctness
from the Rust compiler, and onto us. The goal is to realize the advantages of the `unsafe` facility, whilst avoiding _any_ undefined behaviour.
The definition for what the Rust language designers consider undefined behaviour can be found in the [language reference](https://doc.rust-lang.org/stable/reference/behavior-considered-undefined.html).

## Safety Policy
To maintain the high standards of correctness the project strives for, it is necessary to specify a reasonable policy
to adhere to when implementing unsafe functionality. 
- Always clearly document the assumptions of an `unsafe` code block or function definition, so that callers know how to meet their obligations in the contract.
- All `unsafe` code blocks must be completely covered by unit tests within the same source file.
- TBD...

## Resources
- [The Rustonomicon](https://doc.rust-lang.org/nomicon/) - The Dark Arts of Unsafe Rust
- [The Rust Reference - Unsafety](https://doc.rust-lang.org/stable/reference/unsafety.html)