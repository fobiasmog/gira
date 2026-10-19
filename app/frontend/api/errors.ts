import { ApiError } from "./client.ts"
import { t } from "../i18n/index.ts"

// A short, generic message for an API failure; raw payloads are never shown.
export function errorMessage(error: ApiError): string {
  switch (error.code) {
    case "network":
    case "timeout":
      return t("errors.network")
    case "rate_limited":
      return t("errors.rateLimited")
    case "forbidden":
      return t("errors.forbidden")
    case "not_found":
      return t("errors.notFound")
    case "validation_failed":
      return t("errors.validation")
    default:
      return t("errors.generic")
  }
}

export function isNotFound(error: unknown): boolean {
  return error instanceof ApiError && error.status === 404
}
