/** Browser-safe UUID generation for client-side wire correlation. */

/**
 * Shared implementation from the apiproxy wire layer (the browser-safe
 * `./client` channel): every browser channel mints ids from the same
 * `crypto.getRandomValues`-backed function. The declaring JSDoc lives on
 * `@deepseek-ai/dsh-host-apiproxy/client`'s `randomUuid`.
 */
export { randomUuid } from '@deepseek-ai/dsh-host-apiproxy/client'
