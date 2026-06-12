import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const thisDir = path.dirname(fileURLToPath(import.meta.url))
const matcherPath = path.resolve(
  thisDir,
  "../../app/assets/javascripts/omnya_connector/controllers/origin_matcher.js"
)

const matcherSource = await readFile(matcherPath, "utf8")
const matcherModuleUrl = `data:text/javascript;base64,${Buffer.from(matcherSource).toString("base64")}`
const matcher = await import(matcherModuleUrl)

test("originAllowed matches exact origin", () => {
  assert.equal(
    matcher.originAllowed("https://host.example.com", [ "https://host.example.com" ]),
    true
  )
})

test("originAllowed normalizes default https port", () => {
  assert.equal(
    matcher.originAllowed("https://host.example.com:443", [ "https://host.example.com" ]),
    true
  )
})

test("originAllowed rejects non-default exact-origin port mismatch", () => {
  assert.equal(
    matcher.originAllowed("https://host.example.com:8443", [ "https://host.example.com" ]),
    false
  )
})

test("originAllowed matches wildcard subdomain", () => {
  assert.equal(
    matcher.originAllowed("https://tenant-a.omnya-app.com", [ "https://*.omnya-app.com" ]),
    true
  )
})

test("originAllowed rejects wildcard apex domain", () => {
  assert.equal(
    matcher.originAllowed("https://omnya-app.com", [ "https://*.omnya-app.com" ]),
    false
  )
})

test("originAllowed rejects wildcard lookalike suffix", () => {
  assert.equal(
    matcher.originAllowed("https://tenant-a.omnya-app.com.evil.example", [ "https://*.omnya-app.com" ]),
    false
  )
})

test("originAllowed matches wildcard with explicit port", () => {
  assert.equal(
    matcher.originAllowed("https://tenant-a.omnya-app.com:3443", [ "https://*.omnya-app.com:3443" ]),
    true
  )
})

test("originAllowed rejects wildcard with different explicit port", () => {
  assert.equal(
    matcher.originAllowed("https://tenant-a.omnya-app.com", [ "https://*.omnya-app.com:3443" ]),
    false
  )
})

test("originAllowed rejects blank or invalid origin", () => {
  assert.equal(matcher.originAllowed("", [ "https://host.example.com" ]), false)
  assert.equal(matcher.originAllowed("not a valid origin", [ "https://host.example.com" ]), false)
})