<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# C-ORBIT-08 repro: enum-in-tuple miscompile (crash) + `[N]UInt8` element cast sign-extension

**Compiler:** v0.64.3 (Windows shadow `xiom.new.0643`; WSL `~/.local/bin/xiom`) -- both parts reproduce on both platforms.
**Found by:** the ORBITDB M5.1 typed-values codec (`src/storage/tuple.xi`, 2026-10-11).

## A. `Result[(Enum, Int)]` miscompiles -- hard crash or silently skipped match arms

`repro_enum_tuple.xi` -- `fn pick(c: Color) -> Result[(Color, Int), Int]`
with a payload enum. The compiler warns:

```
xiom: warning: unknown type 'Tuple__Color__Int' -- defaulting to i64.
      This may produce incorrect code.
```

Observed (expected: `n=5`, `custom=5`, `done`):

```
Windows: exit code -2147483645 (0x80000003 STATUS_BREAKPOINT); no output.
WSL:     exit -1 / 255; no output.
```

In the ORBITDB codec the same shape (`DbResult[(TValue, Int)]`) was even
quieter: `Ok` match arms simply did not execute (no crash, no output from
either arm), which is how it was found. The v1 codec is unaffected (no
enum-in-tuple anywhere).

Workaround applied: never put an enum in a tuple. `tuple2_read_value`
returns `DbResult[TValue]` alone, and the caller advances by
`tuple2_value_len(v)` (no position tuple).

## B. Fixed-size `[N]UInt8` element `as Int` sign-extends

`repro_u8_cast.xi`:

```
[8]UInt8 array element `as Int`  ->  -8   (0xF8 sign-extended through i8)
Vec[UInt8] element `as Int`      ->  248  (correct zero-extension)
```

Same on both platforms. The storage byte convention is 0..255, so code
reading bytes through fixed-size arrays must mask: `(b[i] as Int) & 0xFF`
(applied in `tuple2_push_f64_le`). `Vec[UInt8]` readers (`byte_io`, block
store) are unaffected -- the bug is specific to fixed-size array element
reads.

Suggested fix: zero-extend `UInt8 -> Int` casts for `[N]UInt8` element
reads to match the `Vec[UInt8]` behavior.

## Files

- `repro_enum_tuple.xi` -- part A (payload enum in a tuple result).
- `repro_u8_cast.xi` -- part B (array vs vec element casts).
