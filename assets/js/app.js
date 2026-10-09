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

// A waveform artefact is a peak array rather than a picture, so band 3 draws it. The ink
// comes from the computed colour, which follows the theme and survives forced colours.
const Waveform = {
  mounted() { this.draw() },
  updated() { this.draw() },

  draw() {
    fetch(this.el.dataset.src)
      .then((response) => {
        if (!response.ok) throw new Error(`the waveform was not served: ${response.status}`)
        return response.json()
      })
      .then(({peaks}) => {
        const canvas = this.el
        const width = canvas.clientWidth
        if (!width || !peaks.length) return

        canvas.width = width
        const context = canvas.getContext("2d")
        const middle = canvas.height / 2
        const step = Math.max(width / peaks.length, 1)

        context.clearRect(0, 0, width, canvas.height)

        // spec-10 §10.2: where a link named a region, the region is shown on the medium.
        // The band is drawn under the peaks so it reads as the ground they stand on.
        const {from, to} = canvas.dataset
        if (from !== undefined && to !== undefined) {
          const left = parseFloat(from) * width
          const span = Math.max((parseFloat(to) - parseFloat(from)) * width, 2)
          context.fillStyle = getComputedStyle(canvas).getPropertyValue("--sys-color-fill-subtle-strong")
          context.fillRect(left, 0, span, canvas.height)
        }

        context.fillStyle = getComputedStyle(canvas).color

        peaks.forEach((peak, index) => {
          const half = (peak / 255) * middle
          context.fillRect((index / peaks.length) * width, middle - half, step, half * 2)
        })
      })
  }
}

// spec-10 §12.3's transport. The server owns the queue, the current entry and the
// position; this drives the media element to follow them and reports back where it got to.
//
// A holding in several files is one sequence and a position is against the whole, so the
// part carrying a position is arithmetic over the parts' own lengths. A holding in one
// file reports its own length, which is why its single part carries none.
//
// A track of a release held in one file is a region of that file: the element is given
// the whole and told where to begin and end, which is what makes playing track four a
// range-limited play rather than a second stream.
// The hook is on the bar rather than on the element, because §12.3's controls act on the
// element and a control bound to nothing is §17.3's lie: available and doing nothing.
const MediaSession = {
  mounted() {
    this.reportedAt = 0

    this.bind()
    this.follow()
  },

  updated() {
    this.bind()
    this.follow()
  },

  medium() {
    return this.el.querySelector("#transport-medium")
  },

  // Bound once per element, because `updated` runs on every patch and the element
  // survives them. A listener added twice reports twice.
  bind() {
    const medium = this.medium()

    if (medium && !medium.dataset.bound) {
      medium.dataset.bound = "true"
      medium.addEventListener("timeupdate", () => this.advanced())
      medium.addEventListener("ended", () => this.finished())
    }

    if (this.bound) return
    this.bound = true

    this.on("#transport-position", "input", (control) => this.seek(parseInt(control.value, 10)))
    this.on("#transport-back", "click", () => this.nudge(-this.step()))
    this.on("#transport-forward", "click", () => this.nudge(this.step()))
    this.on("#transport-volume", "input", (control) => this.setVolume(control))
    this.on("#transport-mute", "click", (control) => this.toggleMute(control))

    // A toolbar is one tab stop its arrow keys move within (A.9.3). The sliders stay
    // outside it, so the keys it navigates with are not the keys they consume.
    this.roving()
  },

  on(selector, event, handle) {
    const control = this.el.querySelector(selector)
    if (control) control.addEventListener(event, () => handle(control))
  },

  step() {
    return parseInt(this.el.dataset.step, 10)
  },

  // Where in the sequence, which is what the slider and the server both speak in.
  elapsed() {
    const {from} = this.state()

    return this.medium().currentTime * 1000 - from
  },

  seek(elapsed) {
    const {from, parts} = this.state()
    const {part, offset} = this.within(parts, elapsed)
    const medium = this.medium()

    if (medium.src !== new URL(part.src, window.location.href).href) {
      medium.src = part.src
      medium.addEventListener("loadedmetadata", () => (medium.currentTime = (from + offset) / 1000), {once: true})
    } else {
      medium.currentTime = (from + offset) / 1000
    }

    this.reportedAt = elapsed
    this.pushEvent("transport-position", {res: this.state().res, position_ms: Math.floor(elapsed)})
  },

  nudge(by) {
    const control = this.el.querySelector("#transport-position")
    const bounded = Math.min(Math.max(this.elapsed() + by, 0), parseInt(control.max, 10))

    control.value = bounded
    control.setAttribute("aria-valuetext", control.getAttribute("aria-valuetext"))
    this.seek(bounded)
  },

  setVolume(control) {
    const per_cent = parseInt(control.value, 10)

    this.medium().volume = per_cent / 100
    control.setAttribute("aria-valuetext", `${per_cent} per cent`)

    const mute = this.el.querySelector("#transport-mute")
    if (mute) mute.setAttribute("aria-pressed", per_cent === 0 ? "true" : "false")
  },

  // The name states the action it will perform (§12.3), so it reads Unmute while muted.
  toggleMute(control) {
    const medium = this.medium()
    medium.muted = !medium.muted

    control.setAttribute("aria-pressed", medium.muted ? "true" : "false")
    control.setAttribute("aria-label", medium.muted ? "Unmute" : "Mute")
  },

  roving() {
    const toolbar = this.el.querySelector("#transport-controls")
    if (!toolbar) return

    const stops = () => [...toolbar.querySelectorAll("button:not([disabled])")]

    toolbar.addEventListener("keydown", (event) => {
      const moves = {ArrowRight: 1, ArrowLeft: -1}
      if (!(event.key in moves)) return

      const here = stops().indexOf(document.activeElement)
      if (here < 0) return

      event.preventDefault()
      const all = stops()
      all[(here + moves[event.key] + all.length) % all.length].focus()
    })
  },

  // The parts, the bounds and where the server says the person is.
  state() {
    const {parts, from, to, position, interval, res} = this.medium().dataset

    return {
      parts: JSON.parse(parts),
      from: from === undefined || from === "" ? 0 : parseInt(from, 10),
      to: to === undefined || to === "" ? null : parseInt(to, 10),
      position: parseInt(position, 10),
      interval: parseInt(interval, 10),
      res,
      playing: this.medium().dataset.playing === "true"
    }
  },

  // Which part holds a position in the sequence, and how far into that part it is. A
  // position past every part is one the sequence does not contain, which is a fact about
  // the caller and not a place to start from, so it is refused rather than clamped.
  within(parts, position) {
    let remaining = position

    for (let index = 0; index < parts.length; index++) {
      const length = parts[index].duration_ms

      // The last part, or the only one, absorbs whatever is left: a holding in one file
      // knows its own length and the server did not have to state it.
      if (length === null || index === parts.length - 1 || remaining < length) {
        return {part: parts[index], offset: remaining}
      }

      remaining -= length
    }

    throw new Error(`position ${position} is past every part of this holding`)
  },

  follow() {
    const {parts, from, position, playing} = this.state()
    if (!parts.length) return

    const medium = this.medium()
    const {part, offset} = this.within(parts, position)

    if (medium.src !== new URL(part.src, window.location.href).href) {
      medium.src = part.src
      this.seekTo = from + offset
    } else if (Math.abs(medium.currentTime * 1000 - (from + offset)) > 2000) {
      this.seekTo = from + offset
    }

    if (this.seekTo !== undefined) {
      const target = this.seekTo
      this.seekTo = undefined

      const seek = () => {
        medium.currentTime = target / 1000
      }

      if (medium.readyState > 0) seek()
      else medium.addEventListener("loadedmetadata", seek, {once: true})
    }

    // The rejection says what went wrong — a gesture refused, a source unsupported, a
    // decode that failed — and guessing one of them for all of them would report a cause
    // nobody established.
    if (playing) medium.play().catch((cause) => this.pushEvent("transport-refused", {why: `${cause}`}))
    else medium.pause()
  },

  advanced() {
    const {from, to, interval, res} = this.state()
    const at = this.medium().currentTime * 1000

    // The end of the region is the end of this entry, which the element does not know:
    // the file goes on past it.
    if (to !== null && at >= to) {
      this.medium().pause()
      return this.finished()
    }

    const elapsed = at - from
    if (elapsed - this.reportedAt < interval) return

    this.reportedAt = elapsed
    this.pushEvent("transport-position", {res: res, position_ms: Math.floor(elapsed)})
  },

  finished() {
    this.reportedAt = 0
    this.pushEvent("transport-finished", {res: this.state().res})
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Focus, MediaSession, Waveform},
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

