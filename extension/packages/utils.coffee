{ interfaces: Ci, classes: Cc, utils: Cu } = Components

HTMLInputElement    = Ci.nsIDOMHTMLInputElement
HTMLTextAreaElement = Ci.nsIDOMHTMLTextAreaElement
HTMLSelectElement   = Ci.nsIDOMHTMLSelectElement
XULDocument         = Ci.nsIDOMXULDocument
XULElement          = Ci.nsIDOMXULElement
HTMLDocument        = Ci.nsIDOMHTMLDocument
HTMLElement         = Ci.nsIDOMHTMLElement
Window              = Ci.nsIDOMWindow
ChromeWindow        = Ci.nsIDOMChromeWindow
XPathResult         = Ci.nsIDOMXPathResult

_sss  = Cc["@mozilla.org/content/style-sheet-service;1"].getService(Ci.nsIStyleSheetService)
_clip = Cc["@mozilla.org/widget/clipboard;1"].getService(Ci.nsIClipboard)

{ getPref } = require 'prefs'

class Bucket
  constructor: (@idFunc, @newFunc) ->
    @bucket = {}

  get: (obj) ->
    id = @idFunc obj
    if container = @bucket[id]
      return container
    else
      return @bucket[id] = @newFunc obj

  forget: (obj) ->
    delete @bucket[id] if id = @idFunc obj

# Returns the `window` from the currently active tab.
getCurrentTabWindow = (event) ->
  if window = getEventWindow event
    if rootWindow = getRootWindow window
      return rootWindow.gBrowser.selectedTab.linkedBrowser.contentWindow

# Returns the window associated with the event
getEventWindow = (event) ->
  if event.originalTarget instanceof Window
    return event.originalTarget
  else 
    doc = event.originalTarget.ownerDocument or event.originalTarget
    if doc instanceof HTMLDocument or doc instanceof XULDocument
      return doc.defaultView 

getEventRootWindow = (event) ->
  if window = getEventWindow event
    return getRootWindow window

getEventTabBrowser = (event) -> 
  cw.gBrowser if cw = getEventRootWindow event

getRootWindow = (window) ->
  return window.QueryInterface(Ci.nsIInterfaceRequestor)
               .getInterface(Ci.nsIWebNavigation)
               .QueryInterface(Ci.nsIDocShellTreeItem)
               .rootTreeItem
               .QueryInterface(Ci.nsIInterfaceRequestor)
               .getInterface(Window); 

isElementEditable = (element) ->
  return element.isContentEditable or \
         element instanceof HTMLInputElement or \
         element instanceof HTMLTextAreaElement or \
         element instanceof HTMLSelectElement or \
         element.getAttribute('g_editable') == 'true' or \
         element.getAttribute('contenteditable')?.toLowerCase() == 'true' or \
         element.ownerDocument?.designMode?.toLowerCase() == 'on'

getWindowId = (window) ->
  return window.QueryInterface(Components.interfaces.nsIInterfaceRequestor)
               .getInterface(Components.interfaces.nsIDOMWindowUtils)
               .outerWindowID

getSessionStore = ->
  Cc["@mozilla.org/browser/sessionstore;1"].getService(Ci.nsISessionStore);

# Function that returns a URI to the css file that's part of the extension
cssUri = do () ->
  (name) ->
    baseURI = Services.io.newURI __SCRIPT_URI_SPEC__, null, null
    uri = Services.io.newURI "resources/#{ name }.css", null, baseURI
    return uri

# Loads the css identified by the name in the StyleSheetService as User Stylesheet
# The stylesheet is then appended to every document, but it can be overwritten by
# any user css
loadCss = (name) ->
  uri = cssUri(name)
  if !_sss.sheetRegistered(uri, _sss.AGENT_SHEET)
    _sss.loadAndRegisterSheet(uri, _sss.AGENT_SHEET)

  unload -> 
    _sss.unregisterSheet(uri, _sss.AGENT_SHEET)

# Simulate mouse click with full chain of event
# Copied from Vimium codebase
simulateClick = (element, modifiers) ->
  document = element.ownerDocument
  window = document.defaultView
  modifiers ||= {}

  eventSequence = ["mouseover", "mousedown", "mouseup", "click"]
  for event in eventSequence
    mouseEvent = document.createEvent("MouseEvents")
    mouseEvent.initMouseEvent(event, true, true, window, 1, 0, 0, 0, 0, modifiers.ctrlKey, false, false,
        modifiers.metaKey, 0, null)
    # Debugging note: Firefox will not execute the element's default action if we dispatch this click event,
    # but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
    element.dispatchEvent(mouseEvent)

# Write a string into system clipboard
writeToClipboard = (window, text) ->
  str = Cc["@mozilla.org/supports-string;1"].createInstance(Ci.nsISupportsString);
  str.data = text

  trans = Cc["@mozilla.org/widget/transferable;1"].createInstance(Ci.nsITransferable);

  if trans.init
    privacyContext = window.QueryInterface(Ci.nsIInterfaceRequestor)
      .getInterface(Ci.nsIWebNavigation)
      .QueryInterface(Ci.nsILoadContext);
    trans.init(privacyContext);

  trans.addDataFlavor("text/unicode");
  trans.setTransferData("text/unicode", str, text.length * 2);

  _clip.setData trans, null, Ci.nsIClipboard.kGlobalClipboard
  #
# Write a string into system clipboard
readFromClipboard = (window) ->
  trans = Cc["@mozilla.org/widget/transferable;1"].createInstance(Ci.nsITransferable);

  if trans.init 
    privacyContext = window.QueryInterface(Ci.nsIInterfaceRequestor)
      .getInterface(Ci.nsIWebNavigation)
      .QueryInterface(Ci.nsILoadContext);
    trans.init(privacyContext);

  trans.addDataFlavor("text/unicode");

  _clip.getData trans, Ci.nsIClipboard.kGlobalClipboard

  str = {}
  strLength = {}

  trans.getTransferData("text/unicode", str, strLength)

  if str
    str = str.value.QueryInterface(Ci.nsISupportsString);
    return str.data.substring 0, strLength.value / 2

  return undefined

# Executes function `func` and mearues how much time it took
timeIt = (func, msg) ->
  start = new Date().getTime()
  result = func()
  end = new Date().getTime()

  console.log msg, end - start
  return result

# Checks if the string provided matches one of the black list entries
# `blackList`: comma/space separated list of URLs with wildcards (* and !)
isBlacklisted = (str, blackList) ->
  for rule in blackList.split(/[\s,]+/)
    rule = rule.replace(/\*/g, '.*').replace(/\!/g, '.') 
    if str.match new RegExp("^#{ rule }$")
      return true

  return false

# Gets VimFx verions. AddonManager only provides async API to access addon data, so it's a bit tricky...
getVersion = do ->
  version = null

  if version == null
    scope = {}
    addonId = getPref 'addon_id'
    Cu.import("resource://gre/modules/AddonManager.jsm", scope);
    scope.AddonManager.getAddonByID addonId, ((addon) -> version = addon.version)

  -> version

# Simulate smooth scrolling
smoothScroll = (window, dx, dy, msecs) ->
  if msecs <= 0 || !Services.prefs.getBoolPref 'general.smoothScroll'
    window.scrollBy dx, dy
  else
    # Callback
    fn = (_x, _y) -> 
      window.scrollBy(_x, _y)
    # Number of steps
    delta = 10
    l = Math.round(msecs / delta)
    while l > 0
      x = Math.round(dx / l)
      y = Math.round(dy / l)
      dx -= x
      dy -= y

      l -= 1
      window.setTimeout fn, l * delta, x, y

parseHTML = (document, html) ->
  parser = Cc["@mozilla.org/parserutils;1"].getService(Ci.nsIParserUtils)
  flags = parser.SanitizerAllowStyle
  return parser.parseFragment(html, flags, false, null, document.documentElement)

# Uses nsIIOService to parse a string as a URL and find out if it is a URL
isURL = (str) ->
  try
    url = Cc["@mozilla.org/network/io-service;1"]
      .getService(Ci.nsIIOService)
      .newURI(str, null, null)
      .QueryInterface(Ci.nsIURL)
    return true
  catch err
    return false

# Use Firefox services to search for a given string
browserSearchSubmission = (str) ->
  ss = Cc["@mozilla.org/browser/search-service;1"]
    .getService(Ci.nsIBrowserSearchService)

  engine = ss.currentEngine or ss.defaultEngine
  return engine.getSubmission(str, null)

# via vimium.
xpath =
  # Takes an array of XPath selectors, adds the necessary namespaces (currently only XHTML), and applies them
  # to the document root. The namespaceResolver in evaluateXPath should be kept in sync with the namespaces
  # here.
  makeXPath: (elementArray) ->
    xpathArr = []
    for i of elementArray
      xpathArr.push("//" + elementArray[i], "//xhtml:" + elementArray[i])
    xpathArr.join(" | ")

  evaluateXPath: (vim, xpathStr, resultType) ->
    namespaceResolver = (namespace) ->
      if (namespace == "xhtml") then "http://www.w3.org/1999/xhtml" else null
    vim.window.document.evaluate(xpathStr, vim.window.document.documentElement, namespaceResolver, resultType, null)

# The XPath for the the types in <input type="..."> that we consider for the focusInputCharHandler
# function. Should we include the HTML5 date pickers here?
xpath.textInputXPath = (->
  textInputTypes = ["text", "search", "email", "url", "number", "password"]
  inputElements = ["input[" +
    "(" + textInputTypes.map((type) -> '@type="' + type + '"').join(" or ") + "or not(@type))" +
    " and not(@disabled or @readonly)]",
    "textarea", "*[@contenteditable='' or translate(@contenteditable, 'TRUE', 'true')='true']"]
  xpath.makeXPath(inputElements)
)()

# Returns the first visible clientRect of an element if it exists. Otherwise it returns null.
# via vimium.
getVisibleClientRect = (vim, element) ->
  # Note: this call will be expensive if we modify the DOM in between calls.
  clientRects = element.getClientRects()

  for clientRect in clientRects
    if (clientRect.top < -2 || clientRect.top >= vim.window.innerHeight - 4 ||
        clientRect.left < -2 || clientRect.left  >= vim.window.innerWidth - 4)
      continue

    if (clientRect.width < 3 || clientRect.height < 3)
      continue

    # eliminate invisible elements (see test_harnesses/visibility_test.html)
    computedStyle = vim.window.getComputedStyle(element, null)
    if (computedStyle.getPropertyValue('visibility') != 'visible' ||
        computedStyle.getPropertyValue('display') == 'none' ||
        computedStyle.getPropertyValue('opacity') == '0')
      continue

    return clientRect

  for clientRect in clientRects
    # If the link has zero dimensions, it may be wrapping visible
    # but floated elements. Check for this.
    if (clientRect.width == 0 || clientRect.height == 0)
      # TODO: Should this be clientRect.children?
      for child in element.children
        computedStyle = vim.window.getComputedStyle(child, null)
        # Ignore child elements which are not floated and not absolutely positioned for parent elements with
        # zero width/height
        continue if (computedStyle.getPropertyValue('float') == 'none' &&
          computedStyle.getPropertyValue('position') != 'absolute')
        childClientRect = @getVisibleClientRect(vim, child)
        continue if (childClientRect == null)
        return childClientRect
  null

# Returns a list of all visible <input> elements on the screen.
# via vimium.
getVisibleInputs = (vim) ->
  resultSet = xpath.evaluateXPath(vim, xpath.textInputXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE)
  return visibleInputs =
      for i in [0...resultSet.snapshotLength] by 1
        element = resultSet.snapshotItem(i)
        rect = getVisibleClientRect(vim, element)
        continue if rect == null
        { element: element, rect: rect }

exports.Bucket                  = Bucket
exports.getCurrentTabWindow     = getCurrentTabWindow
exports.getEventWindow          = getEventWindow
exports.getEventRootWindow      = getEventRootWindow
exports.getEventTabBrowser      = getEventTabBrowser

exports.getWindowId             = getWindowId
exports.getRootWindow           = getRootWindow
exports.isElementEditable       = isElementEditable
exports.getSessionStore         = getSessionStore

exports.loadCss                 = loadCss

exports.simulateClick           = simulateClick
exports.smoothScroll            = smoothScroll
exports.readFromClipboard       = readFromClipboard
exports.writeToClipboard        = writeToClipboard
exports.timeIt                  = timeIt
exports.isBlacklisted           = isBlacklisted
exports.getVersion              = getVersion
exports.parseHTML               = parseHTML
exports.isURL                   = isURL
exports.browserSearchSubmission = browserSearchSubmission
exports.xpath                   = xpath
exports.getVisibleClientRect    = getVisibleClientRect
exports.getVisibleInputs        = getVisibleInputs
