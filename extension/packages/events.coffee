utils                           = require 'utils'
keyUtils                        = require 'key-utils'
{ getCommand }                  = require 'commands'
{ Vim }                         = require 'vim'
{ getPref }                     = require 'prefs'
{ setWindowBlacklisted }        = require 'button'

{ interfaces: Ci } = Components

vimBucket = new utils.Bucket utils.getWindowId, (obj) -> new Vim obj

suppressEvent = (event) ->
  event.preventDefault()
  event.stopPropagation()

# *************************
# NB! TODO! All this shit needs to be redone!!
# *************************

keyStrFromEvent = (event) ->

  { ctrlKey: ctrl, metaKey: meta, altKey: alt, shiftKey: shift } = event 

  if !meta and !alt
    if keyChar = keyUtils.keyCharFromCode(event.keyCode, shift)
      keyStr = keyUtils.applyModifiers(keyChar, ctrl, alt, meta)

  return keyStr

# Returns true if VimFx should handle a keypress or keydown event based on
# general criteria.
shouldHandleKeyEvent = (vim, keyStr, isEditable) ->
  if not isEditable
    return true
  if keyStr == 'Esc'
    return true
  if vim.focusInput.isEnabled() and (keyStr == 'Tab' or keyStr == 'Shift-Tab')
    return true
  return false

# The following listeners are installed on every top level Chrome window
windowsListener = 
  'keydown': (event) ->

    if getPref 'disabled'
      return

    try
      isEditable = utils.isElementEditable event.originalTarget
      keyStr = keyStrFromEvent(event)
      window = utils.getCurrentTabWindow event
      vim = vimBucket.get(window) if window?
      return if not vim?

      # We only handle the key if it's recognized by `keyCharFromCode` and
      # meets the general criteria.
      if keyStr and shouldHandleKeyEvent(vim, keyStr, isEditable)
        # No action if blacklisted
        if vim.blacklisted
          return

        if vim.handleKeyDown(event, keyStr) and keyStr != 'Esc'
          suppressEvent event
    catch err
      console.log err, 'keydown'
      console.stacktrace()

  'keypress': (event) ->

    if getPref 'disabled'
      return

    try
      isEditable = utils.isElementEditable event.originalTarget

      # Try to execute keys that were accumulated so far.
      # Suppress event if there is a matching command.
      window = utils.getCurrentTabWindow event
      vim = vimBucket.get(window) if window?
      return if not vim?

      # No action on blacklisted locations
      if vim.blacklisted
        return

      # Blur from any active element on Esc. Calling before `handleKeyPress`
      # because `vim.keys` will be reset afterwards`
      blur_on_esc = vim.lastKeyStr == 'Esc' and getPref 'blur_on_esc'

      if shouldHandleKeyEvent vim, vim.lastKeyStr, isEditable
        result = vim.handleKeyPress event

      # If there was some processing done then suppress the eveng
      # unless it's the Esc key
      if result and vim.lastKeyStr != 'Esc'
        suppressEvent event

      # Calling after the command has been executed
      if blur_on_esc
        cb = -> event.originalTarget?.ownerDocument?.activeElement?.blur()
        window.setTimeout cb, 0

    catch err
      console.log err, 'keypress'
      console.stacktrace()

  'keyup': (event) ->
    if window = utils.getCurrentTabWindow event
      if vim = vimBucket.get(window)
        if vim.lastKeyStr and vim.lastKeyStr != 'Esc'
          suppressEvent event

        vim.lastKeyStr = null

  # When the top level window closes we should release all Vims that were 
  # associated with tabs in this window
  'DOMWindowClose': (event) ->
    if gBrowser = event.originalTarget.gBrowser
      for tab in gBrowser.tabs
        if browser = gBrowser.getBrowserForTab tab
          vimBucket.forget browser.contentWindow

  'TabClose': (event) ->
    if gBrowser = utils.getEventTabBrowser event
      if browser = gBrowser.getBrowserForTab event.originalTarget
        vimBucket.forget browser.contentWindow

  # Update the toolbar button icon to reflect the blacklisted state
  'TabSelect': (event) ->
    if vim = vimBucket.get event.originalTarget?.linkedBrowser?.contentDocument?.defaultView
      if rootWindow = utils.getRootWindow vim.window
        setWindowBlacklisted rootWindow, vim.blacklisted

# This listener works on individual tabs within Chrome Window
# User for: listening for location changes and disabling the extension
# on black listed urls
tabsListener = 
  onLocationChange: (browser, webProgress, request, location) ->
    blacklisted = utils.isBlacklisted location.spec, getPref 'black_list'
    if vim = vimBucket.get(browser.contentWindow)
      vim.blacklisted = blacklisted
      if rootWindow = utils.getRootWindow vim.window
        setWindowBlacklisted rootWindow, vim.blacklisted

addEventListeners = (window) ->
  for name, listener of windowsListener
    window.addEventListener name, listener, true

  # Install onLocationChange listener
  window.gBrowser.addTabsProgressListener tabsListener

  removeEventListeners = ->
    for name, listener of windowsListener
      window.removeEventListener name, listener, true

  unload -> 
    removeEventListeners window
    window.gBrowser.removeTabsProgressListener tabsListener

exports.addEventListeners = addEventListeners
