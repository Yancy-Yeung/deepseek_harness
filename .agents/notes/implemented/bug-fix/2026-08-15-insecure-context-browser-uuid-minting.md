# Agent Note: Browser wire clients mint UUIDs without a secure context

Status: implemented

English | [中文](2026-08-15-insecure-context-browser-uuid-minting.zh.md)

## Problem

The web UI is served over plain HTTP on LAN deployments (`http://<host-ip>:3080`), the posture the Docker packaging targets. Browsers expose `crypto.randomUUID()` only on secure contexts — HTTPS pages or `http://localhost` — so on such a page the function is undefined and every RPC wire call fails before it reaches the server: the Models page reported `Loading the provider directory failed: crypto.randomUUID is not a function`, and the composer's image draft attachments minted ids the same way. Development worked only because `http://localhost` counts as a secure context, which is why the defect never showed locally.

## Decision

The browser wire path mints ids with `crypto.getRandomValues()`, which browsers expose on insecure origins. `randomUuid()` — an RFC 4122 v4 generator already proven in the connection package's fixture code — now lives in the apiproxy fetch layer, the browser-safe wire base that the bundle-purity gate inlines into every client. The three consumers share it:

- `AbstractApiClient.mintRpcId()` uses it, so every unary/respond/stream envelope carries a working id on plain HTTP.
- The connection package's `random-uuid.ts` re-exports it, so its fixture and generic RPC channels keep one implementation.
- The conversation composer mints draft attachment ids with it.

Host-side minting (`node:crypto`'s `randomUUID` in the fetch handler and api-proxy) is unchanged.

## Alternatives considered

- **Duplicating the helper into each consumer.** The ~7-line body trips the jscpd gate, and three copies drift; one implementation in the wire layer keeps the format uniform.
- **Documenting a secure-context requirement (HTTPS or localhost tunneling).** The NAS deployment has no TLS, and the repo already pinned the opposite intent: the connection client test asserts RPC calls work with only `getRandomValues` stubbed.
- **Keeping the connection package's helper and importing it from apiproxy.** Dependency direction forbids it: apiproxy is a base of connection, so the shared implementation must live in apiproxy or below.

## Consequences

Wire calls and draft attachments work on plain-HTTP LAN pages; localhost and HTTPS deployments are unaffected, since `getRandomValues` is available on secure contexts too. The apiproxy `./client` subpath — already the documented browser-safe channel — now also carries `randomUuid` for any consumer that needs an id. The package dependencies record the new value import from `dsh-client-ui-conversation` to `dsh-host-apiproxy`.

## Testing

A fetch-carrier test stubs `globalThis.crypto` with only `getRandomValues` and asserts a unary call mints the fixed RFC 4122 v4 id `00000000-0000-4000-8000-000000000000`; the existing connection test "carries RPC calls without requiring secure-context randomUUID" continues to pin the same guarantee end to end.
