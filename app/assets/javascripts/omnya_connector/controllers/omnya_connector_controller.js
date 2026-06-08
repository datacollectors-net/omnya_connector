import { Controller } from "@hotwired/stimulus"

const REFRESH_INTERVAL_MS = 4 * 60 * 1000
const REFRESH_WAIT_TIMEOUT_MS = 5000
const CONTEXT_SYNC_FINGERPRINT_KEY = "omnya_connector_context_sync_fingerprint"
const CONTEXT_PREVIOUS_FINGERPRINT_HEADER = "X-Omnya-Context-Previous-Fingerprint"

// If the engine is mounted at a prefix (e.g. mount OmnyaConnector::Engine => "/my_prefix"),
// adjust this path accordingly (e.g. "/my_prefix/module_context").
const MODULE_CONTEXT_PATH = "/module_context"

export default class extends Controller {
  static values = {
    moduleKey: String,
    hostOrigins: Array,
    autonomousUserGuid: String,
    autonomousTenantId: String
  }

  static targets = [
    "connectionStatus",
    "contextStatus",
    "userLogin",
    "tenantName",
    "errorStatus"
  ]

  connect() {
    this.token = null
    this.contextEndpoint = null
    this.retryAfterUnauthorized = false
    this.hostConnected = false
    this.activeHostOrigin = this.initialHostOrigin()
    this.refreshTimer = null
    this.refreshResolver = null
    this.refreshTimeoutId = null
    this.contextSyncFingerprint = this.readContextSyncFingerprint()

    this.boundMessageHandler = this.handleMessage.bind(this)
    this.boundContextUpdated = this.handleContextUpdatedEvent.bind(this)
    this.boundContextUnavailable = this.handleContextUnavailableEvent.bind(this)
    this.boundHostConnected = this.handleHostConnectedEvent.bind(this)
    this.boundTurboLoad = this.handleTurboLoad.bind(this)
    this.boundPopstate = this.handlePopstate.bind(this)
    this.boundHashChange = this.handleHashChange.bind(this)
    this.boundBeforeFetchRequest = this.handleBeforeFetchRequest.bind(this)

    window.addEventListener("message", this.boundMessageHandler)
    document.addEventListener("turbo:load", this.boundTurboLoad)
    document.addEventListener("turbo:before-fetch-request", this.boundBeforeFetchRequest)
    window.addEventListener("popstate", this.boundPopstate)
    window.addEventListener("hashchange", this.boundHashChange)
    this.element.addEventListener("module:context-updated", this.boundContextUpdated)
    this.element.addEventListener("module:context-unavailable", this.boundContextUnavailable)
    this.element.addEventListener("module:host-connected", this.boundHostConnected)

    this.resetPanel()
    if (!this.embeddedInIframe()) {
      this.connectionStatusTarget.textContent = "Standalone mode (no host iframe)"
      this.contextStatusTarget.textContent = "Autonomous context active"
      this.userLoginTarget.textContent = this.autonomousLabel(this.autonomousUserGuidValue)
      this.tenantNameTarget.textContent = this.autonomousLabel(this.autonomousTenantIdValue)
      return
    }

    this.postToParent("external-module:ready")
    this.postToParent("external-module:request-context")
    this.postToParent("external-module:request-theme")
    this.startRefreshTimer()
  }

  disconnect() {
    window.removeEventListener("message", this.boundMessageHandler)
    document.removeEventListener("turbo:load", this.boundTurboLoad)
    document.removeEventListener("turbo:before-fetch-request", this.boundBeforeFetchRequest)
    window.removeEventListener("popstate", this.boundPopstate)
    window.removeEventListener("hashchange", this.boundHashChange)
    this.element.removeEventListener("module:context-updated", this.boundContextUpdated)
    this.element.removeEventListener("module:context-unavailable", this.boundContextUnavailable)
    this.element.removeEventListener("module:host-connected", this.boundHostConnected)

    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = null
    }

    if (this.refreshTimeoutId) {
      clearTimeout(this.refreshTimeoutId)
      this.refreshTimeoutId = null
    }

    this.resolveRefresh(false)
  }

  handleMessage(event) {
    if (!this.originAllowed(event.origin)) {
      return
    }

    const payload = event.data
    if (!payload) return

    if (payload.moduleKey !== this.moduleKeyValue) return

    if (payload.type === "external-module:theme") {
      this.applyHostTheme(payload)
      return
    }

    if (payload.type === "external-module:navigate") {
      this.handleHostNavigate(payload)
      return
    }

    if (payload.type !== "external-module:context") {
      return
    }

    this.activeHostOrigin = event.origin
    this.token = payload.token
    this.contextEndpoint = payload.contextEndpoint

    if (!this.hostConnected) {
      this.hostConnected = true
      this.dispatchEvent("module:host-connected", {})
    }

    this.resolveRefresh(true)
    this.fetchHostContext({ canRetryOnUnauthorized: true })
  }

  async fetchHostContext({ canRetryOnUnauthorized }) {
    if (!this.token || !this.contextEndpoint) {
      this.dispatchEvent("module:context-unavailable", {
        message: "Host context is unavailable."
      })
      return
    }

    try {
      const response = await fetch(this.contextEndpoint, {
        method: "GET",
        headers: {
          Authorization: `Bearer ${this.token}`,
          Accept: "application/json"
        },
        cache: "no-store",
        credentials: "omit"
      })

      if (response.status === 401) {
        if (canRetryOnUnauthorized && !this.retryAfterUnauthorized) {
          this.retryAfterUnauthorized = true
          const refreshed = await this.requestRefreshAndWait()

          if (refreshed) {
            return this.fetchHostContext({ canRetryOnUnauthorized: false })
          }
        }

        this.dispatchEvent("module:context-unavailable", {
          message: "Authentication is temporarily unavailable."
        })
        return
      }

      if (!response.ok) {
        this.dispatchEvent("module:context-unavailable", {
          message: "Host context request failed."
        })
        return
      }

      const context = await response.json()
      const persisted = await this.persistContextSession()
      if (!persisted.ok) {
        this.dispatchEvent("module:context-unavailable", {
          message: "Host context sync failed."
        })
        return
      }

      this.retryAfterUnauthorized = false
      this.dispatchEvent("module:context-updated", { context })
      this.reloadAfterContextSyncIfNeeded(context, persisted.contextChanged)
    } catch (_error) {
      this.dispatchEvent("module:context-unavailable", {
        message: "Host connection is unavailable."
      })
    }
  }

  async requestRefreshAndWait() {
    this.postToParent("external-module:refresh-context")

    return new Promise((resolve) => {
      this.refreshResolver = resolve

      this.refreshTimeoutId = setTimeout(() => {
        this.resolveRefresh(false)
      }, REFRESH_WAIT_TIMEOUT_MS)
    })
  }

  // Injects X-Omnya-Embedded-Host-Origin into every Turbo-driven fetch request when
  // the active host origin is known and trusted. The server uses this header to bypass
  // CSRF verification for embedded write actions (DELETE/POST/PATCH) when the module's
  // own Origin header is non-actionable (e.g. same-origin or absent due to cookie restrictions).
  handleBeforeFetchRequest(event) {
    if (!this.activeHostOrigin || !this.originAllowed(this.activeHostOrigin)) return
    event.detail.fetchOptions.headers["X-Omnya-Embedded-Host-Origin"] = this.activeHostOrigin
  }

  startRefreshTimer() {
    this.refreshTimer = setInterval(() => {
      if (!this.hostConnected) {
        return
      }

      this.postToParent("external-module:refresh-context")
    }, REFRESH_INTERVAL_MS)
  }

  originAllowed(origin) {
    return this.hostOriginsValue.includes(origin)
  }

  postToParent(type, extra = {}) {
    if (!this.embeddedInIframe() || !this.hasModuleKeyValue || !this.moduleKeyValue) {
      return
    }

    const payload = {
      type,
      moduleKey: this.moduleKeyValue,
      ...extra
    }

    // [2026-05-28 11:20] Post only once to the resolved host origin to avoid target-origin mismatch errors from origin fan-out.
    // [2026-05-28 11:20] Use "*" only during the initial handshake when the exact parent origin is unknown.
    const targetOrigin = this.postMessageOrigin(type)

    try {
      window.parent.postMessage(payload, targetOrigin)
    } catch (_error) {
      if (targetOrigin !== "*") {
        try {
          window.parent.postMessage(payload, "*")
          return
        } catch (_innerError) {
          // Ignore postMessage errors and wait for the next host/module handshake message.
        }
      }

      // Ignore postMessage errors and wait for the next host/module handshake message.
    }
  }

  embeddedInIframe() {
    try {
      return window.parent && window.parent !== window
    } catch (_error) {
      return false
    }
  }

  initialHostOrigin() {
    try {
      const referrerOrigin = new URL(document.referrer).origin
      return this.originAllowed(referrerOrigin) ? referrerOrigin : null
    } catch (_error) {
      return null
    }
  }

  postMessageOrigin(type) {
    // During the initial handshake the inferred referrer origin can be stale
    // (for example when environments are switched). Use wildcard until the host
    // has explicitly identified itself via a trusted context message.
    if (!this.hostConnected && this.handshakeMessageType(type)) {
      return "*"
    }

    if (this.activeHostOrigin && this.originAllowed(this.activeHostOrigin)) {
      return this.activeHostOrigin
    }

    const inferredOrigin = this.initialHostOrigin()
    if (inferredOrigin) {
      this.activeHostOrigin = inferredOrigin
      return inferredOrigin
    }

    // During the initial iframe handshake the parent origin might not be inferable
    // (for example due to strict referrer policy), so use wildcard once until host replies.
    return "*"
  }

  handshakeMessageType(type) {
    return [
      "external-module:ready",
      "external-module:request-context",
      "external-module:request-theme"
    ].includes(type)
  }

  autonomousLabel(value) {
    return value && value.length > 0 ? `autonomous:${value}` : "autonomous:unset"
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  async persistContextSession() {
    try {
      const embeddedHostHeaders = (this.activeHostOrigin && this.originAllowed(this.activeHostOrigin))
        ? { "X-Omnya-Embedded-Host-Origin": this.activeHostOrigin }
        : {}
      const previousFingerprint = this.previousContextFingerprint()

      const response = await fetch(MODULE_CONTEXT_PATH, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken(),
          ...(previousFingerprint ? { [CONTEXT_PREVIOUS_FINGERPRINT_HEADER]: previousFingerprint } : {}),
          ...embeddedHostHeaders
        },
        credentials: "same-origin",
        body: JSON.stringify({
          module_context: {
            token: this.token,
            context_endpoint: this.contextEndpoint,
            module_key: this.moduleKeyValue
          }
        })
      })

      return {
        ok: response.ok,
        contextChanged: response.ok && this.contextChangedFromResponse(response)
      }
    } catch (_error) {
      return {
        ok: false,
        contextChanged: false
      }
    }
  }

  contextChangedFromResponse(response) {
    const value = String(response.headers.get("X-Omnya-Context-Changed") || "").trim().toLowerCase()
    return value === "1" || value === "true"
  }

  dispatchEvent(name, detail) {
    this.element.dispatchEvent(
      new CustomEvent(name, {
        bubbles: true,
        detail
      })
    )
  }

  resolveRefresh(result) {
    if (this.refreshTimeoutId) {
      clearTimeout(this.refreshTimeoutId)
      this.refreshTimeoutId = null
    }

    if (this.refreshResolver) {
      this.refreshResolver(result)
      this.refreshResolver = null
    }
  }

  resetPanel() {
    this.connectionStatusTarget.textContent = "Waiting for host handshake"
    this.contextStatusTarget.textContent = "Context not loaded yet"
    this.userLoginTarget.textContent = "unknown"
    this.tenantNameTarget.textContent = "unknown"
    this.errorStatusTarget.classList.add("hidden")
    this.errorStatusTarget.textContent = ""
  }

  handleHostConnectedEvent() {
    this.connectionStatusTarget.textContent = "Connected to host"
    this.reportCurrentNavigationToHost()
  }

  handleTurboLoad() {
    this.reportCurrentNavigationToHost()
  }

  handlePopstate() {
    this.reportCurrentNavigationToHost()
  }

  handleHashChange() {
    this.reportCurrentNavigationToHost()
  }

  reportCurrentNavigationToHost() {
    if (!this.hostConnected) return

    const modulePath = this.currentModulePath()
    if (!modulePath.startsWith("/")) return

    this.postToParent("external-module:navigate", { modulePath })
  }

  currentModulePath() {
    return `${window.location.pathname}${window.location.search}${window.location.hash}`
  }

  handleHostNavigate(payload) {
    const modulePath = String(payload.modulePath || "").trim()
    if (!modulePath.startsWith("/")) return

    this.dispatchEvent("module:navigate", { modulePath })
  }

  handleContextUpdatedEvent(event) {
    const context = event.detail.context || {}
    const userLogin = context.user?.login || "unknown"
    const tenantName = context.tenant?.name || "unknown"
    const userGuid = context.user?.guid
    const tenantId = context.tenant?.id

    this.contextStatusTarget.textContent = "Context loaded"
    this.userLoginTarget.textContent = this.appendIdLabel(userLogin, userGuid)
    this.tenantNameTarget.textContent = this.appendIdLabel(tenantName, tenantId)
    this.errorStatusTarget.classList.add("hidden")
    this.errorStatusTarget.textContent = ""
  }

  appendIdLabel(label, id) {
    return id ? `${label} [${id}]` : label
  }

  reloadAfterContextSyncIfNeeded(context, contextChanged = false) {
    const nextFingerprint = this.contextFingerprint(context)
    if (contextChanged) {
      if (nextFingerprint) {
        this.contextSyncFingerprint = nextFingerprint
        this.writeContextSyncFingerprint(nextFingerprint)
      }

      this.refreshModuleView()
      return
    }

    if (!nextFingerprint) {
      return
    }

    if (this.contextSyncFingerprint === nextFingerprint) {
      return
    }

    this.contextSyncFingerprint = nextFingerprint
    this.writeContextSyncFingerprint(nextFingerprint)
    this.refreshModuleView()
  }

  refreshModuleView() {
    const modulePath = this.currentModulePath()
    if (window.Turbo && typeof window.Turbo.visit === "function") {
      if (typeof window.Turbo.clearCache === "function") {
        window.Turbo.clearCache()
      }
      window.Turbo.visit(modulePath, { action: "replace" })
      return
    }

    window.location.reload()
  }

  contextFingerprint(context) {
    const userGuid = String(context?.user?.guid || "").trim()
    const tenantId = String(context?.tenant?.id || "").trim()
    return userGuid && tenantId ? `${userGuid}:${tenantId}` : null
  }

  readContextSyncFingerprint() {
    try {
      return window.sessionStorage.getItem(CONTEXT_SYNC_FINGERPRINT_KEY)
    } catch (_error) {
      return null
    }
  }

  writeContextSyncFingerprint(value) {
    try {
      window.sessionStorage.setItem(CONTEXT_SYNC_FINGERPRINT_KEY, value)
    } catch (_error) {
      // Ignore storage limitations and continue without persisted reload state.
    }
  }

  previousContextFingerprint() {
    const value = String(this.contextSyncFingerprint || "").trim()
    return value.length > 0 ? value : null
  }

  handleContextUnavailableEvent(event) {
    this.contextStatusTarget.textContent = "Context unavailable"
    this.errorStatusTarget.classList.remove("hidden")
    this.errorStatusTarget.textContent = event.detail.message || "Authentication is unavailable."
  }

  applyHostTheme(payload) {
    if (!payload || payload.type !== "external-module:theme") return
    if (!["light", "dark", "system"].includes(String(payload.preference || ""))) return
    if (!["light", "dark"].includes(String(payload.effectiveMode || ""))) return

    document.documentElement.dataset.hostThemePreference = payload.preference
    document.documentElement.classList.toggle("dark", payload.effectiveMode === "dark")
    this.dispatchEvent("module:theme-updated", { preference: payload.preference, effectiveMode: payload.effectiveMode })
  }
}
