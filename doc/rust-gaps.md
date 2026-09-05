# Rust 对照：S 的优先补齐项

本次对照以本地 Rust 标准库、借用检查测试和 S 的可执行 no-GC 编译路径为依据。
不是全仓库功能穷举。S 已有 `src/option`、`src/result`、`src/vec` 等源码；
不能把同名包存在等同于这些能力已进入无 GC 编译路径，也不能说 S 完全没有这些包。

| 优先级 | 能力 | 当前 S no-GC 路径 | 价值 |
| --- | --- | --- | --- |
| 1 | 跨函数所有权传递、返回值和参数借用 | 仅支持 `main` | 将单函数示例扩展成可复用的实际程序 |
| 2 | 聚合类型、字段移动和自动析构 | 仅拥有 `box[int]` | 支持结构体、字符串及动态容器的资源管理 |
| 3 | 引用复制及重借用 | 本次实现共享复制和词法重借用 | 在保持独占写入检查的前提下复用引用，为参数借用提供基础 |
| 4 | 循环数据流与非词法生命周期 | 循环保守限制，借用到作用域结束或显式 drop | 减少对安全程序的拒绝 |
| 5 | 完整原生后端及自举闭环 | no-GC 编译器由 seed 构建，输出 C11 | 消除当前工具链边界并扩大可验证的平台覆盖 |

第 1、2 项的收益最大，但都需要扩展类型、调用约定和清理规则。
本次落地第 3 项，所有借用分析及代码生成更改均在 S 源码中。
并未实现跨函数生命周期、Rust NLL 或全语言内存安全。

## 本次实现

`src/cmd/compile/nogc/compiler.s` 增加子借用的父引用记录，并持续记录原始所有者。
共享引用复制保留相同的父引用关系；结束单个别名不会解除其他别名的限制。
可变子借用阻止父引用读写，共享子借用阻止父引用写入；子借用结束后恢复访问。

```s
package example
func main() int {
    owner := box(20);
    parent := &mut owner;
    {
        child := &mut *parent;
        *child = *child + 22;
    }
    shared := &*parent;
    copy := shared;
    drop(shared);
    assert(*copy == 42);
    drop(copy);
    *parent = 42;
    return *parent;
}
```

运行 `make nogc-check` 构建 S 编译器并执行带 ASan/UBSan 的运行用例、
编译拒绝用例、算术异常及应用链接符号检查。支持范围详见 [nogc.md](nogc.md)。

## 本地对照入口

- Rust：`../rust/library/core/src/clone.rs` 中共享引用与可变引用的 Clone 实现。
- Rust：`../rust/tests/ui/borrowck/` 中重借用检查用例。
- S：`src/cmd/compile/nogc/compiler.s`、`test/nogc/check.py`。
- S：`readme.md` 中原生后端与自举状态。
