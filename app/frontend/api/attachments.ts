// Mirrors Comment::ATTACHMENT_POLICY and MAX_ATTACHMENTS so people learn about
// a refused file before uploading it. The server checks the real file type.
export const MAX_ATTACHMENTS = 10
export const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
const TYPES = ["image/png", "image/jpeg", "image/gif", "image/webp", "application/pdf", "text/plain", "text/csv", "application/zip"]
// Some systems report other types for CSV and ZIP files; the extension decides then.
const EXTENSIONS = ["png", "jpg", "jpeg", "gif", "webp", "pdf", "txt", "csv", "zip"]
export const ACCEPT = [...TYPES, ...EXTENSIONS.map((ext) => `.${ext}`)].join(",")

export type AttachmentProblem =
  | { kind: "tooMany"; count: number }
  | { kind: "tooLarge"; name: string }
  | { kind: "type"; name: string }

export function attachmentProblems(files: readonly { name: string; size: number; type: string }[]): AttachmentProblem[] {
  const problems: AttachmentProblem[] = []
  if (files.length > MAX_ATTACHMENTS) problems.push({ kind: "tooMany", count: MAX_ATTACHMENTS })
  for (const file of files) {
    const extension = file.name.split(".").pop()?.toLowerCase() ?? ""
    if (!TYPES.includes(file.type) && !EXTENSIONS.includes(extension)) problems.push({ kind: "type", name: file.name })
    else if (file.size > MAX_ATTACHMENT_BYTES) problems.push({ kind: "tooLarge", name: file.name })
  }
  return problems
}
