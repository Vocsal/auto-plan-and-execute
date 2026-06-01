# 使用指南

## 设计原理

### 为什么要分四个阶段

软件开发中，方案讨论和动手实施是两种不同的思维模式。混在一起会导致：

- **过早实现**：方案没想清就开始改代码，发现走错路再回退成本极高
- **审查盲区**：自己写的方案/实现，自己审查会有盲区
- **Context 污染**：写方案时的上下文会让审查带有偏见

解法：

| 阶段 | 角色 | Context | 产出 |
|---|---|---|---|
| 1. plan-write | 方案设计者 | 背景需求 + 项目代码 + 上轮审查 | 计划方案文档 |
| 2. plan-review | 独立评审人 | 背景需求 + 计划方案 + 项目代码 | 审查报告（含 STATUS） |
| 3. execute-plan | 实施工程师 | 背景需求 + 定稿计划 + 上轮审查 + 代码库 | 代码改动 + 实施日志 |
| 4. execution-review | 独立评审人 | 背景需求 + 计划 + git diff + 关键文件 | 审查报告（含 STATUS） |

每个阶段都是 **独立 Session**，通过 `claude -p` 启动，自然隔离 Context。

### 为什么要 A + B 双重收敛

仅靠"轮数封顶"：可能方案没成熟就强行进入实施，浪费实施轮数
仅靠"STATUS 通过"：审查可能永远挑得出问题，无法收敛

A + B 组合：
- **A（语义判断）**：审查报告必须以 `STATUS: PASS` / `STATUS: NEEDS_REVISION` 结尾，脚本 grep 判断
- **B（轮数兜底）**：每阶段最多 N 轮（默认 3），达到上限强制进入下阶段

### 为什么人工确认点放在"开始实施前"

- 计划阶段产物是文档，迭代成本低，可全自动
- 实施阶段会动代码，错误代价高，必须人工把关一次
- 实施审查→修补：基于审查报告的修补改动可控，可自动跑

## 完整工作流示例

### Step 1：准备需求

可以是文档 `requirements.md`：

```markdown
# 登录接口加限流

## 业务背景
近期检测到 /api/login 接口被刷，日均 5w+ 失败请求。

## 需求详情
- 同一 IP 1 分钟内失败超过 5 次，临时封禁 15 分钟
- 同一账号 1 小时内失败超过 10 次，临时封禁 1 小时
- 封禁期间返回 429，并返回 Retry-After 头
- 解封后自动恢复

## 技术约束
- 不引入新依赖（项目已有 Redis）
- 配置项要支持热更新

## 验收标准
- 单元测试覆盖 IP/账号双维度限流逻辑
- 集成测试模拟暴力破解场景
```

也可以是命令行字符串。

### Step 2：启动

```bash
cd /path/to/your-project
.claude/skills/auto-plan-and-execute/auto-flow.sh ./requirements.md
```

或：

```bash
.claude/skills/auto-plan-and-execute/auto-flow.sh "给登录接口加 IP+账号 双维度限流..."
```

终端显示：

```
[auto-flow] 已创建流程实例: login-rate-limit-a3f2c8d1
[auto-flow]   - 工作目录: .auto-flow/login-rate-limit-a3f2c8d1
[auto-flow]   - 输入类型: 文档(./requirements.md)
[auto-flow] ═══ 计划阶段 第 1/3 轮 ═══
[auto-flow] [1/2] 生成计划方案 .auto-flow/login-rate-limit-a3f2c8d1/plan-v1.md
[auto-flow] → 调用 claude (独立 Session)...
...
```

### Step 3：计划迭代

如果第 1 轮审查 `STATUS: NEEDS_REVISION`，自动进入第 2 轮，直到 `PASS` 或达 3 轮上限。

通过后，脚本会把最终通过版**复制为 `plan.md`**（无版本后缀）：

```
[auto-flow] ✅ 计划审查 STATUS: PASS，计划阶段完成
[auto-flow] 已将定稿计划复制为 .auto-flow/login-rate-limit-a3f2c8d1/plan.md
```

### Step 4：人工确认

```
[auto-flow] ═══ 人工确认点 ═══
[auto-flow] 计划已定稿: .auto-flow/login-rate-limit-a3f2c8d1/plan.md
[auto-flow] 请在另一个终端打开审阅。

是否继续进入实施阶段? [y/n/e=编辑后再确认]:
```

- `y` → 进入实施
- `n` → 终止，稍后用 `--resume` 续跑
- `e` → 编辑文件后再回来确认

### Step 5：实施 → 审查

Claude 会按 `plan.md` 改代码、跑测试，输出 `execution-log-v1.md`。
然后 `execution-review` 看 `git diff`，输出 `execution-review-v1.md`。

如有 P0/P1 问题则进入修补轮，最多 3 轮。

### Step 6：最终总结

```
[auto-flow] ═══ 生成最终总结 ═══
[auto-flow] ✅ 流程完成！最终交付:
[auto-flow]     - 计划方案: .auto-flow/login-rate-limit-a3f2c8d1/plan.md
[auto-flow]     - 实施总结: .auto-flow/login-rate-limit-a3f2c8d1/final-summary.md
[auto-flow]     - 工作目录: .auto-flow/login-rate-limit-a3f2c8d1
```

## 命令对照

| 命令 | 作用 |
|---|---|
| `auto-flow.sh "<文本>"` | 用需求文本启动 |
| `auto-flow.sh ./req.md` | 用需求文档启动 |
| `auto-flow.sh --resume <名称>` | 按名称恢复（多个匹配会列出） |
| `auto-flow.sh --resume <uuid>` | 按 uuid 精确恢复 |
| `auto-flow.sh --resume <名称-uuid>` | 按完整 instance 恢复 |
| `auto-flow.sh --status <名称\|uuid>` | 查看状态 |
| `auto-flow.sh --list` | 列出所有流程实例 |
| `auto-flow.sh --help` | 帮助 |

## 常见场景

### 调高迭代轮数

```bash
MAX_PLAN_ITER=5 MAX_EXEC_ITER=5 auto-flow.sh "..."
```

### 跳过人工确认（仅 CI）

```bash
SKIP_CONFIRM=1 auto-flow.sh ./req.md
```

### Claude Code 内手动单跑某阶段

不想跑完整 auto-flow，只想用 skill 跑某一个阶段时，在 Claude Code 里说：

> 用 auto-plan-and-execute skill 的 plan-write 角色帮我写计划，需求在 ./req.md，输出到 plans/my-plan.md

Claude 会读取 `agents/plan-write.md` 作为角色 prompt，按规范产出。

### 修复中间步骤后重跑

假设第 2 轮计划审查后，你想手动改一下 `plan-v2.md` 再继续：

1. 编辑 `plan-v2.md`
2. 删除 `plan-review-v2.md`（让脚本重新审查）
3. `auto-flow.sh --resume <名称>`

### 完全重做

```bash
rm -rf .auto-flow/<名称>-<uuid>
auto-flow.sh ./req.md
```

## 故障排除

### "审查报告末尾缺少 STATUS 标记"

skill 没按规范输出 STATUS 行。处理方式：

1. 手动打开报告，在末尾加 `STATUS: PASS` 或 `STATUS: NEEDS_REVISION`
2. `auto-flow.sh --resume <名称>` 继续

### "未产出 plan-vN.md"

可能原因：
- Claude 没识别到 skill — 检查 `.claude/skills/auto-plan-and-execute` 是否存在
- Claude 写到了别的路径 — 看一下工作目录里有没有同名文件
- Claude CLI 报错 — 重跑看完整输出

### 实施阶段改坏了代码

中止脚本后用 git 回退：

```bash
git stash       # 或 git reset --hard HEAD
```

然后修一下计划或审查报告，再 `--resume`。

### 多个 instance 同名

可能在不同时间为同一个需求多次启动 auto-flow。每次会有不同 UUID，互不冲突。用 `--list` 查看，用 `--status <完整名-uuid>` 精确查询。

## 文档命名规则

| 文件 | 含义 | 是否带版本后缀 |
|---|---|---|
| `plan-v1.md`, `plan-v2.md`, ... | 计划迭代版本 | 是 |
| `plan.md` | 通过审查后定稿的计划 | **否** |
| `plan-review-v1.md`, ... | 计划审查报告 | 是 |
| `execution-log-v1.md`, ... | 实施日志 | 是 |
| `execution-review-v1.md`, ... | 实施审查报告 | 是 |
| `final-summary.md` | 最终交付总结 | 否 |

实施阶段和总结阶段统一引用 `plan.md`，下游不用关心定稿了第几版。

## 进阶用法

### 集成 CI/CD

```yaml
# .github/workflows/auto-flow.yml
on:
  workflow_dispatch:
    inputs:
      requirements: { required: true }

jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: curl -fsSL https://raw.githubusercontent.com/Vocsal/auto-plan-and-execute/main/install.sh | bash
      - run: SKIP_CONFIRM=1 .claude/skills/auto-plan-and-execute/auto-flow.sh "${{ inputs.requirements }}"
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 自定义 STATUS 解析逻辑

修改 `scripts/auto-flow.sh` 中 `check_status` 函数，可以加入：
- 检查报告中"P0 数量"是否为 0
- 检查问题清单中是否含特定关键词
- 调用其他工具做额外校验

## 设计取舍

| 取舍点 | 选择 | 原因 |
|---|---|---|
| Context 隔离 | 每阶段独立 `claude -p` | 简单可靠，无需复杂 IPC |
| 状态持久化 | JSON 文件 | 易调试、易手动修改 |
| 人工确认点 | 仅在实施前 | 平衡自动化与安全 |
| 单 skill vs 多 skill | 单 skill | 集中调度，触发率高，避免命名冲突 |
| 定稿计划命名 | `plan.md`（无后缀） | 下游引用稳定 |
| 实例命名 | `name-uuid` | name 易读，uuid 防冲突 |
| install 策略 | 双份完整拷贝 | 简单可靠，跨平台兼容 |
