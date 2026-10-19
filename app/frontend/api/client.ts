import type { ErrorEnvelope, FieldErrors } from "./types.ts"

export const TIMEOUT_MS = 15_000
export const UPLOAD_TIMEOUT_MS = 120_000

// code is the API's error code, or "network" / "timeout" when no response
// arrived. status is 0 in those two cases.
export class ApiError extends Error {
  readonly status: number
  readonly code: string
  readonly fields: FieldErrors

  constructor(status: number, code: string, fields: FieldErrors = {}) {
    super(`API error ${status} ${code}`)
    this.name = "ApiError"
    this.status = status
    this.code = code
    this.fields = fields
  }
}

type Method = "GET" | "POST" | "PUT" | "PATCH" | "DELETE"
export type Query = Record<string, string | number | boolean | null | undefined>

export interface RequestOptions {
  query?: Query
  body?: unknown
  signal?: AbortSignal
  timeout?: number
}

function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ""
}

function url(path: string, query?: Query): string {
  const params = new URLSearchParams()
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== null) params.set(key, String(value))
  }
  const search = params.toString()
  return `/api${path}${search ? `?${search}` : ""}`
}

async function errorFrom(response: Response): Promise<ApiError> {
  const envelope = await response.json().catch(() => null) as ErrorEnvelope | null
  const error = envelope?.error
  return new ApiError(response.status, typeof error?.code === "string" ? error.code : "internal_error", error?.fields ?? {})
}

export async function request<T>(method: Method, path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: "application/json" }
  let body: BodyInit | undefined
  if (options.body instanceof FormData) {
    body = options.body
  } else if (options.body !== undefined) {
    headers["Content-Type"] = "application/json"
    body = JSON.stringify(options.body)
  }
  if (method !== "GET") headers["X-CSRF-Token"] = csrfToken()

  const timeout = AbortSignal.timeout(options.timeout ?? TIMEOUT_MS)
  const signal = options.signal ? AbortSignal.any([options.signal, timeout]) : timeout

  let response: Response
  try {
    response = await fetch(url(path, options.query), { method, headers, body, signal, credentials: "same-origin" })
  } catch (error) {
    if (options.signal?.aborted) throw error
    throw new ApiError(0, timeout.aborted ? "timeout" : "network")
  }

  if (response.status === 401) {
    // The server remembers this URL, sends the user to sign-in, and brings them
    // back here afterwards. The page unloads, so the caller never resumes.
    location.assign(location.href)
    return new Promise<never>(() => {})
  }
  if (!response.ok) throw await errorFrom(response)
  if (response.status === 204 || response.headers.get("Content-Length") === "0") return undefined as T

  const text = await response.text()
  return (text ? JSON.parse(text) : undefined) as T
}

export const api = {
  get: <T>(path: string, query?: Query, signal?: AbortSignal) => request<T>("GET", path, { query, signal }),
  post: <T>(path: string, body?: unknown) => request<T>("POST", path, { body }),
  put: <T>(path: string, body?: unknown) => request<T>("PUT", path, { body }),
  patch: <T>(path: string, body?: unknown) => request<T>("PATCH", path, { body }),
  delete: <T = void>(path: string, body?: unknown) => request<T>("DELETE", path, { body }),
}
