// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pluteus"
import topbar from "../vendor/topbar"

// spec-10 §17.7's focus obligations. LiveView protects only a focused form input from a
// patch, so the focused element's identity is recorded here and restored after a patch, a
// route change and a reconnection.
//
// Where the element is gone, focus moves to the nearest surviving sibling in document
// order, failing that its container, failing that the surface's first focusable, in the
// order §17.7 fixes.
const focusable = "a[href], button, input, select, textarea, [tabindex]:not([tabindex='-1'])"

const Focus = {
  mounted() {
    this.remembered = null
    this.el.addEventListener("focusin", (event) => {
      this.remembered = event.target.id || null
      this.order = this.remembered ? [...this.el.querySelectorAll(focusable)].map((e) => e.id) : null
    })
    this.restore()
  },

  updated() {
    this.restore()
  },

  reconnected() {
    this.restore()
  },

  restore() {
    if (!this.remembered) return
    const held = this.el.querySelector(`#${CSS.escape(this.remembered)}`)
    if (held) return held.focus()

    const survivor = (this.order || [])
      .slice((this.order || []).indexOf(this.remembered) + 1)
      .map((id) => id && this.el.querySelector(`#${CSS.escape(id)}`))
      .find((element) => element)

    const target = survivor || this.el.querySelector(focusable)
    if (target) target.focus()
    else if (this.el.tabIndex >= 0) this.el.focus()
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Focus},
})

// Show progress bar on live navigation and form submits.
//
// topbar paints a canvas, so it needs a resolved colour rather than a variable, and
// the colour is read again on each show because a theme change between two
// navigations would otherwise leave the bar in the previous theme. No shadow: A.6
// makes a shadow decorative and it does not survive forced colours, so there is
// nothing to spend a hardcoded colour on.
const ring = () =>
  getComputedStyle(document.documentElement).getPropertyValue("--sys-color-focus-ring").trim()

window.addEventListener("phx:page-loading-start", _info => {
  topbar.config({barColors: {0: ring()}})
  topbar.show(300)
})
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

