# 变更记录规则

`CHANGELOG/` 是 Arclume 的追加式变更历史，不使用单一、反复改写的 `CHANGELOG.md`。

## 规则

1. 每个逻辑改动（一个 PR 或一个直接提交）必须新增一个文件到 `unreleased/`。
2. 文件名使用 `YYYY-MM-DD-HHMMSS-简短-kebab-case.md`；同一时刻冲突时追加序号。
3. 已合并或已发布的记录不可覆盖、重命名或删除。更正必须新增记录并链接旧记录。
4. Release 时将对应记录移动到 `released/<app-version>/`，保留文件内容和 Git 历史。
5. 文档、CI、资源、Runtime、迁移和依赖变化也必须记录。

## 模板

```md
# 简短标题

- 时间：2026-08-20T17:30:00+08:00
- 类型：feature | fix | docs | ci | runtime | release | security
- 范围：App | Runtime | 文档 | CI
- PR / 提交：#123 或 abcdef0

## 改动

- …

## 用户影响与兼容性

- …

## 验证

- 命令或手工步骤：结果

## 后续

- 无，或明确待办。
```

`released/` 中的记录是面向版本的历史索引；完整 Release 二进制和校验和仍以 GitHub Release 为准。
