function defaultPortForScheme(scheme) {
  if (scheme === "https") return "443"
  if (scheme === "http") return "80"
  return null
}

function effectivePort(parsed) {
  if (parsed.port && parsed.port.length > 0) return parsed.port

  const scheme = parsed.protocol.replace(/:$/, "").toLowerCase()
  return defaultPortForScheme(scheme)
}

function defaultPort(parsed) {
  const scheme = parsed.protocol.replace(/:$/, "").toLowerCase()
  const port = effectivePort(parsed)
  const schemeDefaultPort = defaultPortForScheme(scheme)

  return schemeDefaultPort !== null && port === schemeDefaultPort
}

export function normalizeOrigin(origin) {
  const rawOrigin = String(origin || "").trim()
  if (rawOrigin.length === 0) return null

  let parsed
  try {
    parsed = new URL(rawOrigin)
  } catch (_error) {
    return null
  }

  if (!parsed.protocol || !parsed.hostname) return null

  const scheme = parsed.protocol.replace(/:$/, "").toLowerCase()
  const host = parsed.hostname.toLowerCase()
  const port = effectivePort(parsed)
  const includePort = port && !defaultPort(parsed)

  return includePort ? `${scheme}://${host}:${port}` : `${scheme}://${host}`
}

export function wildcardRuleMatches(normalizedOrigin, wildcardRule) {
  const wildcardMatch = String(wildcardRule || "").trim().match(/^https:\/\/\*\.([a-z0-9.-]+)(?::(\d+))?$/i)
  if (!wildcardMatch) return false

  let originUrl
  try {
    originUrl = new URL(normalizedOrigin)
  } catch (_error) {
    return false
  }

  const wildcardHost = wildcardMatch[1].toLowerCase()
  const wildcardPort = wildcardMatch[2]
  const originHost = (originUrl.hostname || "").toLowerCase()

  // Wildcards only match subdomains, never the apex domain.
  if (!originHost.endsWith(`.${wildcardHost}`)) return false

  if (!wildcardPort) return defaultPort(originUrl)

  const originPort = effectivePort(originUrl)
  return originPort === wildcardPort
}

export function wildcardRule(originRule) {
  return String(originRule || "").includes("*")
}

export function originRuleMatches(normalizedOrigin, allowedOrigin) {
  const rule = String(allowedOrigin || "").trim()
  if (rule.length === 0) return false

  if (wildcardRule(rule)) {
    return wildcardRuleMatches(normalizedOrigin, rule)
  }

  return normalizeOrigin(rule) === normalizedOrigin
}

export function originAllowed(origin, allowedOrigins) {
  const normalizedOrigin = normalizeOrigin(origin)
  if (!normalizedOrigin) return false

  return Array.from(allowedOrigins || []).some((allowedOrigin) => {
    return originRuleMatches(normalizedOrigin, allowedOrigin)
  })
}