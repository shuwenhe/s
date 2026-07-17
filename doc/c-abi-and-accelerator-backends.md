# C ABI 与加速器后端

Seed 编译器支持把标记过的 S 函数导出为动态库中的稳定 C 符号。第一阶段 ABI 只接受 S `int`，并固定映射为 C `int64_t`，避免不同平台的 C `long` 宽度差异。

```s
export "c:neurx_add" func add(int a, int b) int {
    return a + b
}
```

```sh
./bin/s_seed input.s output.ir
S_SOURCE_ROOT="$PWD" ./bin/s_seed --emit-shared output.ir libs_model.dylib
```

Linux 输出通常使用 `.so`。动态库还导出 `const char *s_abi_last_error(void)`，其结果为当前线程最近一次 ABI 调用的错误文本，成功时为空字符串。

`make seed-c-abi-test` 会执行 S 源码编译、动态库生成、符号加载和真实 C 调用的完整验收。

编译器目标注册表已包含 `native`、`c-abi`、`cuda` 和 `cann`。可用以下命令检查本机工具链：

```sh
./bin/s_seed --probe-backend cuda
./bin/s_seed --probe-backend cann
```

CUDA 探测 `nvcc`，CANN 探测 `ccec_compiler`、`ASCEND_HOME_PATH` 或 `CANN_HOME`。探测成功只表示工具链可用，不代表当前阶段已经完成 GPU/NPU Kernel 代码生成。后续实现应在统一目标接口下增加设备 IR、地址空间和线程模型、Kernel 启动 ABI、CUDA/CANN 代码生成器，以及真实硬件回归测试。
