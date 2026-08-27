// S 语言 Slice 标准库
// 替代 Vector 的完整实现，基于 Go 的 Slice 机制
// 
// Package: std.slices
// 这是 S 语言的核心标准库，提供 Slice 的所有操作

package std.slices

// ============================================================================
// 1. 内置函数 (编译器支持，用户直接使用)
// ============================================================================

// len() - 获取 slice 长度
// 编译器内置函数，在编译时处理
// 用法: length := len(s)

// cap() - 获取 slice 容量
// 编译器内置函数
// 用法: capacity := cap(s)

// make() - 创建 slice
// 编译器内置函数
// 用法: s := make(int[], 10)           // length=10, capacity=10
//      s := make(int[], 3, 10)        // length=3, capacity=10

// append() - 追加元素
// 编译器内置函数
// 用法: s = append(s, 1)              // 单个元素
//      s = append(s, 1, 2, 3)        // 多个元素

// ============================================================================
// 2. 标准库函数 (用户可导入使用)
// ============================================================================

// 计算新容量 (Go 的增长策略)
func grow_capacity(int oldCap, int needed) int {
    if oldCap == 0 {
        return 4
    }
    
    if oldCap < 256 {
        // 小于 256 时倍增
        return oldCap * 2
    }
    
    // 大于 256 时增长 25%
    loop {
        oldCap = oldCap + oldCap / 4
        if oldCap >= needed {
            break
        }
    }
    
    oldCap
}

// Copy - 复制 slice 中的元素
// 参数: dst - 目标 slice, src - 源 slice
// 返回: 实际复制的元素个数
// 用法: n := copy(dst, src)
func copy[t](t[] dst, t[] src) int {
    copied := 0
    if len(src) > len(dst) {
        copied = len(dst)
    } else {
        copied = len(src)
    }
    
    if copied > 0 {
        // 循环复制元素（不使用底层指针操作）
        for i in 0..copied {
            dst[i] = src[i]
        }
    }
    
    copied
}

// Contains - 检查 slice 中是否包含某个值
// 用法: found := contains(s, value)
func contains[t](t[] s, t value) bool {
    for i in 0..len(s) {
        if s[i] == value {
            return true
        }
    }
    false
}

// Find - 查找第一个匹配的元素索引
// 返回: 元素索引，如果未找到返回 -1
// 用法: idx := find(s, value)
func find[t](t[] s, t value) int {
    for i in 0..len(s) {
        if s[i] == value {
            return i
        }
    }
    -1
}

// Clear - 清空 slice (设置长度为 0)
// 用法: s = clear(s)
func clear[t](t[] s) t[] {
    s.len = 0
    s
}

// Reverse - 反转 slice 中的元素
// 用法: s = reverse(s)
func reverse[t](t[] s) t[] {
    if len(s) <= 1 {
        return s
    }
    
    left := 0
    right := len(s) - 1
    
    loop {
        if left >= right {
            break
        }
        
        // 交换元素
        temp := s[left]
        s[left] = s[right]
        s[right] = temp
        
        left = left + 1
        right = right - 1
    }
    
    s
}

// Insert - 在指定位置插入元素
// 参数: s - 原 slice, idx - 插入位置, value - 要插入的值
// 返回: (新 slice, 错误信息)
// 用法: s, err := insert(s, 2, 99)
func insert[t](t[] s, int idx, t value) (t[], string) {
    if idx < 0 || idx > len(s) {
        return s, "index out of range"
    }
    
    // 使用 append 扩容
    s = append(s, value)  // 先添加到末尾
    
    // 从后向前移动元素，为插入位置腾出空间
    if idx < len(s) - 1 {
        for i := len(s) - 1; i > idx; i = i - 1 {
            s[i] = s[i - 1]
        }
    }
    
    // 设置新元素
    s[idx] = value
    
    return s, ""
}

// Remove - 移除指定位置的元素
// 返回: (新 slice, 错误信息)
// 用法: s, err := remove(s, 2)
func remove[t](t[] s, int idx) (t[], string) {
    if idx < 0 || idx >= len(s) {
        return s, "index out of range"
    }
    
    // 从 idx+1 向后的元素向前移动一位
    if idx < len(s) - 1 {
        for i := idx; i < len(s) - 1; i = i + 1 {
            s[i] = s[i + 1]
        }
    }
    
    // 减少长度
    s.len = s.len - 1
    
    return s, ""
}

// RemoveRange - 移除范围内的元素 [start, end)
// 用法: s, err := remove_range(s, 1, 3)
func remove_range[t](t[] s, int start, int end) (t[], string) {
    if start < 0 || end > len(s) || start > end {
        return s, "invalid range"
    }
    
    if start == end {
        return s, ""  // 范围为空，无需操作
    }
    
    removed_count := end - start
    
    // 将 end 之后的元素向前移动
    for i := start; i < len(s) - removed_count; i = i + 1 {
        s[i] = s[i + removed_count]
    }
    
    // 减少长度
    s.len = s.len - removed_count
    
    return s, ""
}

// Fill - 用指定值填充整个 slice
// 用法: s = fill(s, 0)
func fill[t](t[] s, t value) t[] {
    for i in 0..len(s) {
        s[i] = value
    }
    s
}

// Clone - 克隆 slice (创建完整副本)
// 返回: 新 slice
// 用法: s2 := clone(s1)
func clone[t](t[] s) t[] {
    if len(s) == 0 {
        return t[]{}
    }
    
    new_slice := make(t[], len(s))
    copy(new_slice, s)
    new_slice
}

// ============================================================================
// 3. 模块初始化信息
// ============================================================================

func slices_unit_name() string {
    "std.slices"
}

func slices_unit_ready() int {
    1  // 标记该单元已准备好
}
