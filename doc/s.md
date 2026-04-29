# S 语言语法指南

## 关键字
- `func`：定义函数。
- `struct`：定义结构体。
- `use`：导入模块。
- `if` / `else`：条件语句。
- `for`：循环语句。
- `return`：返回值。

## 数据类型
- `int`：整数类型。
- `float`：浮点数类型。
- `bool`：布尔类型。
- `string`：字符串类型。
- `[]type`：数组类型。

## 变量定义
### 基本变量声明
```s
int x = 10
char y = 'a'
float z = 3.14
```

### 多变量声明
```s
int a = 1, b = 2, c = 3
```

### 未初始化变量
```s
int x  // x 的值是未定义的
```

### 常量声明
```s
const int x = 10  // x 是一个常量，不能被修改
```

## 函数定义
```s
func add(int a, int b) int {
    return a + b
}
```

## 条件语句
```s
if x > 10 {
    // 条件为真时执行
} else {
    // 条件为假时执行
}
```

## 循环语句
```s
for i in 0..10 {
    // 循环体
}
```

## 结构体定义
```s
struct Point {
    int x
    int y
}

func new_point(int x, int y) Point {
    Point {
        x: x,
        y: y,
    }
}
```

## 模块导入
```s
use mymodule.submodule
```

## 数组操作
```s
let arr = []int{1, 2, 3}
let mut dynamic_arr = []int{cap: 10}
dynamic_arr[0] = 42
```

## 错误处理
- 当前版本未支持显式错误处理。

## 注意事项
- S 语言是强类型语言，类型必须显式声明。
- 数组需要预分配容量以优化性能。

更多内容请参考官方文档。