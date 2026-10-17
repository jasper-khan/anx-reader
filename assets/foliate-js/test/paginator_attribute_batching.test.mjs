import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

class EventTargetStub {
  constructor() { this.listeners = new Map() }
  addEventListener(name, callback) { this.listeners.set(name, callback) }
  removeEventListener(name, callback) {
    if (this.listeners.get(name) === callback) this.listeners.delete(name)
  }
}

class ElementStub extends EventTargetStub {
  constructor() {
    super()
    this.style = { setProperty: (name, value) => { this.style[name] = value } }
    this.classList = { toggle() {} }
  }
  append() {}
  removeChild() {}
}

class ShadowRootStub extends ElementStub {
  constructor() {
    super()
    this.elements = new Map([
      ['top', new ElementStub()],
      ['background', new ElementStub()],
      ['container', new ElementStub()],
    ])
  }
  set innerHTML(_) {}
  getElementById(id) { return this.elements.get(id) }
}

class HTMLElementStub extends EventTargetStub {
  constructor() {
    super()
    this.attributes = new Map()
  }
  attachShadow() {
    this.shadowRoot = new ShadowRootStub()
    return this.shadowRoot
  }
  getAttribute(name) { return this.attributes.get(name) ?? null }
  hasAttribute(name) { return this.attributes.has(name) }
  setAttribute(name, value) {
    const next = String(value)
    const old = this.getAttribute(name)
    this.attributes.set(name, next)
    if (this.constructor.observedAttributes?.includes(name))
      this.attributeChangedCallback(name, old, next)
  }
  removeAttribute(name) {
    const old = this.getAttribute(name)
    this.attributes.delete(name)
    if (old != null && this.constructor.observedAttributes?.includes(name))
      this.attributeChangedCallback(name, old, null)
  }
}

globalThis.HTMLElement = HTMLElementStub
globalThis.ResizeObserver = class {
  static instances = []
  constructor(callback) {
    this.callback = callback
    ResizeObserver.instances.push(this)
  }
  observe(target) { this.observed = target }
  unobserve(target) { this.unobserved = target }
}
globalThis.matchMedia = () => new EventTargetStub()
globalThis.NodeFilter = {
  SHOW_ELEMENT: 1,
  SHOW_TEXT: 4,
  SHOW_CDATA_SECTION: 8,
  FILTER_ACCEPT: 1,
  FILTER_REJECT: 2,
  FILTER_SKIP: 3,
}
globalThis.document = { createElement: () => new ElementStub() }
globalThis.customElements = { define() {} }

const { Paginator } = await import('../src/paginator.js')

const makePaginator = () => {
  const paginator = new Paginator()
  let renderCount = 0
  paginator.render = () => { renderCount++ }
  return { paginator, get renderCount() { return renderCount } }
}

const initialAttributes = {
  flow: 'scrolled',
  'top-margin': '10px',
  'bottom-margin': '20px',
  gap: '5%',
  'background-color': '#fff',
  'max-column-count': '2',
  'column-threshold': '720px',
  'bgimg-url': 'none',
  'bgimg-blur': '0',
  'bgimg-opacity': '1',
  'bgimg-fit': 'cover',
  animated: 'true',
}

{
  const test = makePaginator()
  test.paginator.setAttributes(initialAttributes)
  assert.equal(test.renderCount, 1, 'a batch of layout attributes renders once')

  test.paginator.setAttributes(initialAttributes)
  assert.equal(test.renderCount, 1, 'unchanged values do not render')

  test.paginator.setAttributes({ 'top-margin': '30px' })
  assert.equal(test.renderCount, 2, 'top-margin-only changes render')
  test.paginator.setAttributes({ 'top-margin': '30px' })
  assert.equal(test.renderCount, 2, 'unchanged top-margin does not render')

  test.paginator.setAttribute('gap', '6%')
  assert.equal(test.renderCount, 3, 'standalone attribute changes still render')
  test.paginator.setAttribute('gap', '6%')
  assert.equal(test.renderCount, 3, 'standalone unchanged values do not render')
}

const baseStyle = {
  pageTurnStyle: 'slide', topMargin: 10, bottomMargin: 10, sideMargin: 5,
  backgroundColor: '#fff', maxColumnCount: 2, columnThreshold: 720,
  bgimgBlur: 0, bgimgOpacity: 1, bgimgFit: 'cover', backgroundImage: 'none',
  fontSize: 1, fontName: 'system', fontPath: '', fontWeight: 400,
  letterSpacing: 0, spacing: 1.5, paragraphSpacing: 0, textIndent: 0,
  fontColor: '#000', justify: false, textAlign: 'auto', hyphenate: false,
  writingMode: 'horizontal-tb', customCSS: '', customCSSEnabled: false,
  useBookStyles: true, headingFontSize: 1,
}

{
  const test = makePaginator()
  let styleCount = 0
  let refreshCount = 0
  test.paginator.setStyles = () => { styleCount++ }
  const context = {
    style: baseStyle,
    reader: { view: { renderer: test.paginator } },
    getCSS: value => JSON.stringify(value),
    fixHeadingColor() {},
    refreshLayout: () => { refreshCount++ },
  }
  const source = fs.readFileSync(new URL('../src/book.js', import.meta.url), 'utf8')
  const start = source.indexOf('const setStyle =')
  const end = source.indexOf('\nconst refreshLayout', start)
  vm.runInNewContext(
    `${source.slice(start, end)}; globalThis.setStyle = setStyle`,
    context,
  )

  context.setStyle(null)
  assert.equal(test.renderCount, 1, 'initial style batch renders once')
  assert.equal(styleCount, 1, 'initial style still applies CSS')

  context.style = { ...baseStyle, fontSize: 1.1 }
  context.setStyle(baseStyle)
  assert.equal(test.renderCount, 1, 'CSS-only change does not re-render layout')
  assert.equal(styleCount, 2, 'CSS-only change still applies CSS')

  context.style = { ...baseStyle, pageTurnStyle: 'scroll' }
  context.setStyle(baseStyle)
  assert.equal(test.renderCount, 2, 'flow switch renders once')
  assert.equal(test.paginator.getAttribute('flow'), 'scrolled')
  assert.equal(refreshCount, 1, 'flow switch keeps refreshLayout behavior')
}

{
  const { paginator } = makePaginator()
  const container = paginator.shadowRoot.elements.get('container')
  const observer = ResizeObserver.instances.at(-1)
  assert.equal(observer.observed, container,
    'constructor observes the container with the resize observer')
  assert.equal(container.listeners.has('scroll'), true,
    'constructor registers the container scroll listener')
  assert.equal(paginator.listeners.has('touchstart'), true,
    'constructor registers host touch listeners')
  assert.equal(paginator.listeners.has('load'), true,
    'constructor registers the host load listener')

  paginator.sections = []
  paginator.destroy()

  assert.equal(observer.unobserved, container,
    'destroy unobserves the container (not the host element)')
  assert.equal(container.listeners.has('scroll'), false,
    'destroy removes the container scroll listener')
  assert.equal(paginator.listeners.has('touchstart'), false,
    'destroy removes host touch listeners')
  assert.equal(paginator.listeners.has('touchend'), false,
    'destroy removes all host touch listeners')
  assert.equal(paginator.listeners.has('load'), false,
    'destroy removes the host load listener')
}

console.log('paginator attribute batching: ok')
