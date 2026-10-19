import { test } from "node:test"
import assert from "node:assert/strict"
import { attachmentProblems, MAX_ATTACHMENT_BYTES } from "./attachments.ts"

const file = (name: string, type: string, size = 1000) => ({ name, type, size })

test("allowed files pass", () => {
  assert.deepEqual(attachmentProblems([file("a.png", "image/png"), file("b.pdf", "application/pdf"), file("c.csv", "application/vnd.ms-excel")]), [])
})

test("files over 10 MB are refused", () => {
  assert.deepEqual(attachmentProblems([file("big.zip", "application/zip", MAX_ATTACHMENT_BYTES + 1)]), [{ kind: "tooLarge", name: "big.zip" }])
  assert.deepEqual(attachmentProblems([file("ok.zip", "application/zip", MAX_ATTACHMENT_BYTES)]), [])
})

test("other types are refused", () => {
  assert.deepEqual(attachmentProblems([file("run.exe", "application/x-msdownload"), file("page.html", "text/html")]), [
    { kind: "type", name: "run.exe" },
    { kind: "type", name: "page.html" },
  ])
})

test("at most ten files", () => {
  assert.deepEqual(attachmentProblems(Array.from({ length: 11 }, (_, i) => file(`${i}.txt`, "text/plain"))), [{ kind: "tooMany", count: 10 }])
})
