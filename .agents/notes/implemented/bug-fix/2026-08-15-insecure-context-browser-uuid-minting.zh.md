# Agent Note: 浏览器 wire 客户端在非安全上下文中生成 UUID

Status: implemented

[English](2026-08-15-insecure-context-browser-uuid-minting.md) | 中文

## Problem

Web UI 在局域网部署时通过纯 HTTP 提供服务（`http://<主机IP>:3080`），这正是 Docker 打包所面向的形态。浏览器只在安全上下文——HTTPS 页面或 `http://localhost`——暴露 `crypto.randomUUID()`，因此在这样的页面上该函数是 undefined，每一条 RPC wire 调用都在到达服务器之前失败：Models 页面报错 `Loading the provider directory failed: crypto.randomUUID is not a function`，输入框的图片草稿附件也以同样的方式生成 id。开发环境正常只是因为 `http://localhost` 属于安全上下文，这正是该缺陷从未在本地出现的原因。

## Decision

浏览器 wire 路径改用 `crypto.getRandomValues()` 生成 id，浏览器在非安全源上也暴露该 API。`randomUuid()`——一个已在 connection 包 fixture 代码中验证过的 RFC 4122 v4 生成器——现在放在 apiproxy fetch 层，即 bundle-purity 门禁会内联进每个客户端的浏览器安全 wire 基座。三个消费方共享它：

- `AbstractApiClient.mintRpcId()` 使用它，因此每条 unary/respond/stream 信封在纯 HTTP 上都携带可用的 id。
- connection 包的 `random-uuid.ts` 重新导出它，其 fixture 与通用 RPC 通道保持同一实现。
- 对话输入框用它为草稿附件生成 id。

宿主侧生成（fetch handler 与 api-proxy 中的 `node:crypto` `randomUUID`）不变。

## Alternatives considered

- **在每个消费方复制该 helper。** 约 7 行的函数体会触发 jscpd 门禁，且三份拷贝会漂移；在 wire 层保留单一实现可保持格式统一。
- **把安全上下文作为文档要求（HTTPS 或 localhost 隧道）。** NAS 部署没有 TLS，且仓库早已钉住了相反的意图：connection 客户端测试断言只 stub `getRandomValues` 时 RPC 调用仍然工作。
- **保留 connection 包的 helper 并由 apiproxy 导入它。** 依赖方向不允许：apiproxy 是 connection 的基座，因此共享实现必须放在 apiproxy 或更底层。

## Consequences

wire 调用与草稿附件在纯 HTTP 局域网页面上正常工作；localhost 与 HTTPS 部署不受影响，因为安全上下文同样有 `getRandomValues`。apiproxy 的 `./client` 子路径导出——即已文档化的浏览器安全通道——现在也向任何需要 id 的消费方提供 `randomUuid`。包依赖记录了从 `dsh-client-ui-conversation` 到 `dsh-host-apiproxy` 的新增 value import。

## Testing

fetch-carrier 测试将 `globalThis.crypto` stub 为仅含 `getRandomValues`，断言一次 unary 调用生成的 id 为固定的 RFC 4122 v4 值 `00000000-0000-4000-8000-000000000000`；既有 connection 测试 "carries RPC calls without requiring secure-context randomUUID" 继续端到端钉住同一保证。
