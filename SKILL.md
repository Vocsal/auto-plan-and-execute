---
name: auto-plan-and-execute
description: 用四阶段循环（编写计划 → 审查计划 → 实施 → 审查实施）严格、可追溯地完成软件项目需求；每阶段在独立 Claude Session 中运行实现 Context 隔离，阶段间通过文档传递，最终输出一份可交付的实施总结。当用户提到"按计划走"、"先写方案再实施"、"严格规划再落地"、"自动化计划与执行"、"plan-and-execute"、"auto-plan-and-execute"、"四阶段流程"、"先评审方案"、或调用 /auto-plan-and-execute 时，必须使用本 skill。即使用户没明确说"四阶段"，只要他们想要"先有方案、再有审查、再动手"的严肃开发流程，都用本 skill 统一处理。
---

# auto-plan-and-execute

把 **编写计划 → 审查计划 → 实施 → 审查实施** 四阶段闭环封装成可重复执行的流程。每阶段在独立的 Claude Session 中运行，自然实现 Context 隔离；阶段间通过文档传递信息，最终输出一份可交付的实施总结。

本 skill 有两种使用方式：
1. **全自动化**：运行 `scripts/auto-flow.sh`，由编排脚本驱动整个流程（推荐）
2. **手动按阶段**：用户希望只跑某一个阶段时，按下面"手动调用"章节的指引完成

## 何时触发

- 用户输入 `/auto-plan-and-execute`
- 用户提到"自动化计划-执行"、"四阶段流程"、"先写方案再实施"、"严格规划再落地"
- 用户给了一段需求描述（文本或文档），希望走"方案 → 审查 → 实施 → 复核"完整流程
- 用户在 auto-flow 流程中途，需要恢复或单跑某阶段

## 完整流程总览

整体时序与每阶段的输入输出，**必读** `references/workflow-overview.md`。

四个阶段使用的角色 prompt：
- 阶段 1（编写计划）→ `agents/plan-write.md`
- 阶段 2（审查计划）→ `agents/plan-review.md`
- 阶段 3（实施）→ `agents/execute-plan.md`
- 阶段 4（审查实施）→ `agents/execution-review.md`

收敛标记规范（PASS / NEEDS_REVISION）→ **必读** `references/status-protocol.md`

各阶段产出的文档模板 → **必读** `references/document-templates.md`

## 工作目录约定

所有产出都放在执行目录的 `.auto-flow/{需求名称}-{uuid}/` 下：

```
.auto-flow/{name}-{uuid}/
├── context.md                  # 需求背景（脚本初始化时生成）
├── state.json                  # 当前阶段、轮数、定稿计划路径
├── plan-v1.md, plan-v2.md, ... # 计划迭代版本
├── plan-review-v1.md, ...      # 计划审查报告
├── plan.md                     # 定稿计划（无版本后缀；脚本在通过时从最终版复制而来）
├── execution-log-v1.md, ...    # 实施日志
├── execution-review-v1.md, ... # 实施审查报告
└── final-summary.md            # 最终交付总结
```

## 全自动化用法（推荐）

启动新流程：

```bash
# 输入可以是需求文本（用引号包起来）
scripts/auto-flow.sh "为登录接口加 IP+账号 双维度限流，..."

# 也可以是需求文档路径
scripts/auto-flow.sh ./requirements.md
```

脚本自动：
1. **检测输入类型**：是已存在的文件 → 视为需求文档；否则视为需求文本
2. **自动命名**：从需求 H1 标题（文档输入）或前几十字（文本输入）slug 化推断名称
3. **生成短 UUID（8 位）** 并创建 `.auto-flow/{name}-{uuid}/`
4. **初始化 context.md**
5. **跑计划循环**（最多 `MAX_PLAN_ITER` 轮，默认 3）
6. **复制定稿计划为 `plan.md`**
7. **停下来等人工确认** y/n/e
8. **跑实施循环**（最多 `MAX_EXEC_ITER` 轮，默认 3）
9. **生成 `final-summary.md`**

中断恢复：

```bash
scripts/auto-flow.sh --resume <名称 或 uuid 或 名称-uuid>
```

查看状态：

```bash
scripts/auto-flow.sh --status <名称 或 uuid>
scripts/auto-flow.sh --list             # 列出所有进行中/完成的流程
```

## 手动单阶段调用

如果用户**不**想跑完整流程，只想跑某一个阶段，按以下步骤：

### 阶段 1：编写计划
1. 读取 `agents/plan-write.md` 作为角色 prompt
2. 读取 `references/document-templates.md` 中的"计划方案文档"模板
3. 按 prompt 指引产出 `plan-v{N}.md`

### 阶段 2：审查计划
1. 读取 `agents/plan-review.md`
2. 读取 `references/status-protocol.md` 严格按格式输出 STATUS
3. 按"计划审查报告"模板产出 `plan-review-v{N}.md`

### 阶段 3：实施
1. 读取 `agents/execute-plan.md`
2. 按"实施日志"模板，在改完代码后产出 `execution-log-v{N}.md`

### 阶段 4：审查实施
1. 读取 `agents/execution-review.md`
2. 读取 `references/status-protocol.md`
3. 看 `git diff` + 计划 + 实施日志，产出 `execution-review-v{N}.md`

如果用户在对话中提供了背景、需求和上下文，**直接**按以上指引完成对应阶段的产出，**不要**强制要求他们用 `auto-flow.sh`。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `MAX_PLAN_ITER` | 3 | 计划阶段最大轮数 |
| `MAX_EXEC_ITER` | 3 | 实施阶段最大轮数 |
| `CLAUDE_BIN` | `claude` | Claude CLI 命令 |
| `AUTO_FLOW_DIR` | `.auto-flow` | 工作目录 |
| `SKIP_CONFIRM` | `0` | 设为 `1` 跳过实施前人工确认（仅 CI） |

## 重要约束

- **Context 隔离不可破坏**：审查类角色（plan-review、execution-review）必须严格独立，不要参考实施者的解释、合理化或借口
- **STATUS 标记是契约**：审查报告末尾的 STATUS 行格式不能改变，否则脚本会报错
- **定稿计划名为 `plan.md`**：实施和最终总结阶段统一引用 `plan.md`，不要去找 `plan-v{N}.md`
- **不要写迭代痕迹**：方案文档和总结文档都不要出现"v2 相比 v1..."、"采纳了审查建议..."这种对话痕迹
