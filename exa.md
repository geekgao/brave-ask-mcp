在 Go 语言（Golang）中调用 Python 3，可以通过绑定 Python C API 的第三方库实现。最常用的方案是使用 `github.com/datadog/go-python3`，它是 `go-python` 的 Python 3 支持版本（原 `sbinet/go-python` 仅支持 Python 2.7）。

以下是使用 `go-python3` 调用 Python 3 的完整步骤和示例。

## 1. 安装依赖

首先安装 `go-python3` 包：

```
go get github.com/datadog/go-python3
   
```

确保系统已安装 Python 3 开发库。例如在 Ubuntu 上：

```
sudo apt-get install python3-dev
   
```

在 macOS 上，如果使用 Homebrew 安装 Python，通常已包含头文件。

## 2. 初始化 Python 解释器

在 Go 程序中，必须先初始化 Python 解释器，并在程序结束时释放资源。

```
package main

import (
    "fmt"
    "github.com/datadog/go-python3"
)

func init() {
    err := python3.Py_Initialize()
    if err != nil {
        panic("Failed to initialize Python")
    }
    // 建议使用 defer 在 main 中调用 Py_Finalize()
}

func main() {
    defer python3.Py_Finalize()

    // 后续调用 Python 代码
}
   
```

## 3. 调用 Python 函数示例

假设你有一个 Python 脚本 `hello.py`：

```
# hello.py
def greet(name):
    return f"Hello, {name}!"

a = 100

def add(x, y):
    return x + y
   
```

在 Go 中调用：

```
package main

import (
    "fmt"
    "github.com/datadog/go-python3"
)

func main() {
    python3.Py_Initialize()
    defer python3.Py_Finalize()

    // 添加当前目录到 Python 路径
    sysModule := python3.PyImport_ImportModule("sys")
    sysPath := sysModule.GetAttrString("path")
    python3.PyList_Insert(sysPath, 0, python3.PyUnicode_FromString("."))

    // 导入 hello 模块
    helloModule := python3.PyImport_ImportModule("hello")
    if helloModule == nil {
        panic("Failed to import hello module")
    }
    defer helloModule.DecRef()

    // 调用 greet 函数
    greetFunc := helloModule.GetAttrString("greet")
    if greetFunc == nil {
        panic("greet function not found")
    }
    defer greetFunc.DecRef()

    args := python3.PyTuple_New(1)
    python3.PyTuple_SetItem(args, 0, python3.PyUnicode_FromString("Go"))
    result := greetFunc.Call(args, python3.Py_None)
    if result == nil {
        python3.PyErr_Print()
        panic("Call failed")
    }
    defer result.DecRef()

    greeting := python3.PyUnicode_AsUTF8(result)
    fmt.Println("From Python:", greeting) // 输出: From Python: Hello, Go!

    // 获取变量 a
    a := helloModule.GetAttrString("a")
    defer a.DecRef()
    aValue := python3.PyLong_AsLong(a)
    fmt.Println("a =", aValue) // 输出: a = 100
}
   
```

## 4. 处理第三方库（如 sklearn）

你也可以调用 Python 第三方库，例如 `sklearn`：

```
sklearn := helloModule.GetAttrString("sklearn")
if sklearn != nil {
    defer sklearn.DecRef()
    version := sklearn.GetAttrString("__version__")
    defer version.DecRef()
    verStr := python3.PyUnicode_AsUTF8(version.Repr())
    fmt.Println("sklearn version:", verStr)
}
   
```

## 5. 注意事项

- **引用计数**：所有 `*python3.PyObject` 对象使用后应调用 `DecRef()`，避免内存泄漏。
- **路径问题**：确保 Python 能找到你的模块，必要时修改 `sys.path`。
- **线程安全**：Python GIL 未自动处理，多线程调用需手动管理。
- **错误处理**：使用 `python3.PyErr_Occurred()` 或 `PyErr_Print()` 检查 Python 错误。
