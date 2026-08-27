# S Bootstrap Ladder

This document records the current bootstrap frontier for the S compiler.

The ladder is intentionally incremental:

1. `slice1` proves the smallest runnable compiler slice.
2. `slice2` extends native expression, control flow, and locals.
3. `slice3` extends calls, loops, strings, arrays, multicalls, and copy.
4. `slice4` extends function control, logical operators, typed locals, and large functions.
5. `slice5` extends multicall and argument passing.
6. `slice6` extends string comparison and branch-string assembly generation.

The current bootstrap driver still uses the trusted seed compiler to build each
slice candidate, but each slice is validated against a narrower frontier of
language or code-generation capability.

## Current Targets

### Slice 1

Validates the minimal compiler and executable generation path.

Recommended check:

```sh
make bootstrap-slice1-check
```

### Slice 2

Validates native expression, control, and locals.

Recommended check:

```sh
make bootstrap-slice2-check
```

### Slice 3

Validates call, loop, string, array, multicall, and copy frontiers.

Recommended check:

```sh
make bootstrap-slice3-check
```

### Slice 4

Validates function control, logical operators, typed locals, and large functions.

Recommended check:

```sh
make bootstrap-slice4-check
```

### Slice 5

Validates multicall and argument passing.

Recommended check:

```sh
make bootstrap-slice5-check
```

### Slice 6

Validates string comparison and branch-string assembly generation.

Recommended check:

```sh
make bootstrap-slice6-check
```

## Notes

The ladder is a work-in-progress. The later slices are useful because they make
the self-hosting boundary explicit, even when the full compiler is not yet able
to rebuild itself without the seed-assisted path.
