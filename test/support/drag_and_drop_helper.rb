# Native drag and drop driven by dispatching DragEvents that share one
# DataTransfer, as a browser does (WebDriver's HTML5 drag simulation is
# unreliable).
module DragAndDropHelper
  DRAG_SCRIPT = <<~JS
    const [handle, container, before, drop] = arguments
    const data = new DataTransfer()
    const point = (el, corner) => {
      const r = el.getBoundingClientRect()
      return corner === "start" ? { x: r.left + 2, y: r.top + 2 } : { x: r.right - 2, y: r.bottom - 2 }
    }
    const fire = (el, type, p) =>
      el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: data, clientX: p.x, clientY: p.y }))
    const target = before ? point(before, "start") : point(container, "end")
    fire(handle, "dragstart", point(handle, "start"))
    fire(container, "dragenter", target)
    fire(container, "dragover", target)
    if (drop) fire(container, "drop", target)
    fire(handle, "dragend", target)
  JS

  # Drags by `handle` and drops into `container`: just before the element
  # `before` (inside the container), or at the container's end.
  def drag_and_drop(handle, container, before: nil)
    execute_script(DRAG_SCRIPT, handle, container, before, true)
  end

  # Starts a drag and ends it without a drop, as pressing Escape does.
  def drag_and_cancel(handle, container)
    execute_script(DRAG_SCRIPT, handle, container, nil, false)
  end

  # Drops something that did not start on the page (a link from another tab)
  # and returns whether the page cancelled the browser's default action.
  def drop_foreign_link(container, url)
    evaluate_script(<<~JS, container, url)
      (() => {
        const [container, url] = arguments
        const data = new DataTransfer()
        data.setData("text/uri-list", url)
        data.setData("text/plain", url)
        const r = container.getBoundingClientRect()
        const init = { bubbles: true, cancelable: true, dataTransfer: data, clientX: r.left + 5, clientY: r.top + 5 }
        container.dispatchEvent(new DragEvent("dragenter", init))
        const over = new DragEvent("dragover", init)
        container.dispatchEvent(over)
        const drop = new DragEvent("drop", init)
        container.dispatchEvent(drop)
        return over.defaultPrevented && drop.defaultPrevented
      })()
    JS
  end

  # Counts (or fails) the requests the page makes to URLs containing `fragment`.
  def watch_requests(fragment, fail: false)
    execute_script(<<~JS, fragment, fail)
      const [fragment, fail] = arguments
      const original = window.fetch
      window.__requests = 0
      window.fetch = (url, init) => {
        if (!String(url).includes(fragment)) return original(url, init)
        window.__requests++
        return fail ? Promise.reject(new TypeError("Failed to fetch")) : original(url, init)
      }
    JS
  end

  def watched_requests
    evaluate_script("window.__requests")
  end
end
