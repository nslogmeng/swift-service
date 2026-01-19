# Scripts

<div align="center">
    <a href="./README.md"><strong>English</strong></a> | <strong>简体中文</strong>
</div>
<br/>

本目录包含项目的构建和开发脚本。

## build-docc.sh

构建 DocC 文档的脚本，支持多语言构建。

### 快速开始

```bash
# 构建所有语言
./scripts/build-docc.sh --all

# 启动本地预览服务器
python3 -m http.server 8000 --directory .build/docs

# 打开浏览器访问：http://localhost:8000/documentation/service/
```

### 可用选项

| 选项 | 说明 |
|------|------|
| `--all` | 构建所有语言并合并输出 |
| `--lang <lang>` | 构建单个语言（如 `en`、`zh-Hans`） |
| `--output <path>` | 自定义输出目录 |
| `--skip-build` | 跳过编译，复用已有的 symbol graph |
| `-h, --help` | 显示帮助信息 |

### 示例

```bash
# 快速迭代：修改文档后跳过编译重新生成
./scripts/build-docc.sh --all --skip-build

# 构建单个语言
./scripts/build-docc.sh --lang zh-Hans

# 自定义输出目录
./scripts/build-docc.sh --all --output ./docs
```
