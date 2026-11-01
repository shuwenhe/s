# Nominal scope frontier

These three valid source files must compile together and execute 42. The
same short record name in another package must not change `left.read`'s
parameter or field types.

The trusted seed accepts this control. The canonical S semantic checker
currently loses the defining package of the unqualified `token` parameter,
producing a semantic rejection. This is an explicit remaining RED, not a
passing selfhost regression or permission to ignore a declaration.

```sh
compiler --compile-unit program.sasm \
  test/selfhost/nominal-scope/main.s \
  test/selfhost/nominal-scope/left.s \
  test/selfhost/nominal-scope/right.s
compiler --emit-bin program.sasm program
./program # expected exit 42
```
