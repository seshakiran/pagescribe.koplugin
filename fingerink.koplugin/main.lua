--[[--
PageScribe — write on book pages with a pen or finger.

The side toolbar is the control surface: it is a normal widget sitting above
ReaderUI, and the capture handler passes through any contact that starts inside
it, so controls stay reachable in every input mode. Native finger selection
passes through by default. Drawing always keeps the launcher visible.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"

local Event = require("ui/event")
local Notebook = require("ink_notebook")
local Capture = require("ink_capture")
local InkBar = require("ink_bar")
local InkPdf = require("ink_pdf")
local Render = require("ink_render")
local Colors = require("ink_colors")
local Refresh = require("ink_refresh")
local Store = require("ink_store")
local Transform = require("ink_transform")

local Screen = Device.screen
local INK = Blitbuffer.COLOR_BLACK

local PEN_THIN, PEN_MEDIUM, PEN_THICK = 2, 4, 7
local ERASER_RADIUS = 18
local SETTING_KEY = "fingerink_strokes"
local SUSPENDED = -1   -- draw_slot sentinel: ignore this contact until it lifts

local FingerInk = WidgetContainer:extend{
    name = "fingerink",
    is_doc_only = true,
}

local updater = dofile(plugin_dir .. "pluginupdater.lua").new{
    repository = "seshakiran/pagescribe.koplugin",
    branch = "main",
    folder = "fingerink.koplugin",
}

-- ---------------------------------------------------------------- lifecycle

function FingerInk:init()
    self.drawing = false
    self.eraser = false
    self.highlighter = false
    self.input_mode=G_reader_settings:readSetting("fingerink_input_mode")
    if self.input_mode~="pen_only" and self.input_mode~="finger_draw" then self.input_mode="select" end
    if self.input_mode=="pen_only" and not (Device.input and Device.input.registerStylusCallback) then self.input_mode="select" end
    self.stylus_only=self.input_mode=="pen_only"
    self.notes = self.ui.doc_settings:readSetting("fingerink_notes") or {}
    self.bar = nil
    self.refresh_hz = G_reader_settings:readSetting("fingerink_refresh_hz") or 30
    self.live_refresh = Refresh.new(UIManager, Screen, true, self.refresh_hz)
    self.pen_width = G_reader_settings:readSetting("fingerink_pen_width") or PEN_MEDIUM
    self.highlighter_width = G_reader_settings:readSetting("fingerink_highlighter_width") or 24
    self.pen_color = Colors.get(G_reader_settings:readSetting("fingerink_pen_color"),"black").id
    self.highlighter_color = Colors.get(G_reader_settings:readSetting("fingerink_highlighter_color"),"yellow").id
    self.live_fast = G_reader_settings:readSetting("fingerink_live_fast") ~= false
    self.bar_side = G_reader_settings:readSetting("fingerink_bar_side") or "right"
    self.bar_style = G_reader_settings:readSetting("fingerink_bar_style") == "icons"
        and "icons" or "text"
    self.bar_position = G_reader_settings:readSetting("fingerink_bar_position")

    self.contacts = {}
    self.n_contacts = 0
    self.passthrough = false
    self.draw_slot = nil
    self.stroke = nil

    self.store = Store.new(self.ui.doc_settings:readSetting(SETTING_KEY))

    self:registerDispatcher()
    self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("fingerink", self)

    UIManager:nextTick(function() self:setBarShown(true) end)
end

function FingerInk:registerDispatcher()
    Dispatcher:registerAction("fingerink_toggle", {
        category = "none", event = "FingerInkToggle", reader = true,
        title = _("PageScribe: toggle drawing"),
    })
    Dispatcher:registerAction("fingerink_eraser", {
        category = "none", event = "FingerInkEraser", reader = true,
        title = _("PageScribe: toggle eraser"),
    })
    Dispatcher:registerAction("fingerink_undo", {
        category = "none", event = "FingerInkUndo", reader = true,
        title = _("PageScribe: undo stroke"),
    })
    Dispatcher:registerAction("fingerink_bar", {
        category = "none", event = "FingerInkBar", reader = true,
        title = _("PageScribe: toggle toolbar"),
    })
end

function FingerInk:onCloseDocument()
    self:teardown()
end

function FingerInk:onCloseWidget()
    self:teardown()
end

function FingerInk:onSuspend()
    self:setDrawing(false)
end

function FingerInk:teardown()
    if self.live_refresh then self.live_refresh:cancel() end
    Capture:remove()
    self.drawing = false
    if self.bar then
        UIManager:close(self.bar)
        self.bar = nil
    end
end

function FingerInk:onSaveSettings()
    self.ui.doc_settings:saveSetting("fingerink_notes", self.notes)
    if self.store:isEmpty() then
        self.ui.doc_settings:delSetting(SETTING_KEY)
    else
        self.ui.doc_settings:saveSetting(SETTING_KEY, self.store.pages)
    end
    -- Refresh the disabled Undo state only when availability changes. Keep
    -- ordinary pen samples on the fast direct drawing path.
    if self.bar and self.bar.expanded and self.bar.canUndo
        and self.bar.undo_available~=self.bar:canUndo() then self.bar:update(true) end
end

--- Rotation and resize invalidate the bar's layout; rebuild it.
function FingerInk:rebuildBar()
    if not self.bar then return end
    UIManager:close(self.bar)
    self.bar = nil
    UIManager:nextTick(function() self:setBarShown(true) end)
end

function FingerInk:onScreenResize()
    self:abortStroke()
    self:rebuildBar()
end

function FingerInk:onSetRotationMode()
    self:abortStroke()
    self:rebuildBar()
end

-- ----------------------------------------------------------------- toolbar

function FingerInk:setBarShown(on)
    on = on and true or false
    G_reader_settings:saveSetting("fingerink_bar_shown", on)

    if on then
        if self.bar then return end
        self.bar = InkBar:new{
            plugin = self,
            side = self.bar_side,
            style = self.bar_style,
            position = self.bar_position,
        }
        UIManager:show(self.bar, "ui", self.bar.dimen)
    else
        -- Collapse instead of removing the only reachable way back in.
        if self.bar then self.bar:setExpanded(false) end
    end
end

function FingerInk:onFingerInkBar()
    if not self.bar then self:setBarShown(true) end
    self.bar:setExpanded(not self.bar.expanded)
    return true
end

function FingerInk:inBar(x, y)
    return self.bar ~= nil and self.bar:contains(x, y)
end

--[[--
True while a menu or dialog is open over the reader.

Modal dialogs receive normal touch gestures in all input modes, so selection
popups and note editors stay usable while the pen capture hook is installed.
]]
function FingerInk:dialogOnTop()
    local below = self.bar and self.bar:windowBelow()
    return below ~= nil and below ~= self.ui
end

-- ------------------------------------------------------------------- state

function FingerInk:notify(text)
    UIManager:show(Notification:new{ text = text })
end

function FingerInk:currentPage()
    return self.view.state.page or 1
end

--[[--
The screen-to-page mapping for `stroke`, plus the page it belongs to, or nil if
the stroke cannot be mapped safely.

`page = (screen + t) / t.z`, derived from ReaderView's position helpers.
Recorded with every stroke so that ink can be turned into PDF page coordinates
later on — whatever the view has been zoomed or panned to since, and for pages
other than the one on screen, whose zoom and offset differ. See ADR-11.

In continuous view, every point is checked because a stroke may cross a page
gap. Such a stroke is left unsaved rather than split or placed on the wrong
page. Reflowed and rotated pages remain unsupported.
]]
function FingerInk:pageTransform(stroke)
    local doc = self.ui.document
    if not doc.is_pdf or not self.ui.paging then return nil, nil, "mapping" end
    if doc.configurable and doc.configurable.text_wrap == 1 then
        return nil, nil, "reflow"
    end

    return Transform.fromStroke(self.view, stroke)
end

function FingerInk:setDrawing(on)
    on = on and true or false
    if on == self.drawing then return end

    if on then
        if not self.bar then self:setBarShown(true) end
        local ok = Capture:install(
            function(slots) return self:onTouchFrame(slots) end,
            function(slot) return self:onStylusEvent(slot) end)
        if not ok then
            logger.warn("FingerInk: no gesture_detector to hook")
            self:notify(_("PageScribe: cannot hook touch input"))
            return
        end
        self.drawing = true
    else
        self:abortStroke()
        Capture:remove()
        self:resetContacts()
        self.pen_down, self.pen_passthrough, self.stylus_tool = false, false, nil
        self.drawing = false
    end
    if self.bar then self.bar:update(true) end
end

function FingerInk:setEraser(on)
    self.highlighter = false
    self.eraser = on and true or false
    if self.eraser and not self.drawing then
        self:setDrawing(true)   -- also updates the bar
    elseif self.bar then
        self.bar:update(true)
    end
end

function FingerInk:setTool(tool)
    self:abortStroke()
    self.eraser, self.highlighter = tool == "eraser", tool == "highlight"
    self:setDrawing(true)
    if self.bar then self.bar:update(true) end
end

function FingerInk:cycleTool()
    if self.eraser then
        self.eraser, self.highlighter = false, false
    elseif self.highlighter then
        self:setEraser(true)
    else
        self.highlighter = true
    end
    if self.bar then self.bar:update(true) end
end

function FingerInk:resetContacts()
    for slot in pairs(self.contacts) do
        self.contacts[slot] = nil
    end
    self.n_contacts = 0
    self.passthrough = false
    self.draw_slot = nil
    self.selection_blocked = false
end

function FingerInk:onFingerInkToggle()
    self:setDrawing(not self.drawing)
    return true
end

function FingerInk:onFingerInkEraser()
    self:setEraser(not self.eraser)
    return true
end

-- ------------------------------------------------------------------- input

--[[--
Called on every touch frame while drawing mode is on, before GestureDetector
sees it. Returns true if the frame's gesture events should reach the app.
]]
-- Stylus-only mode keeps toolbar contacts usable and swallows all other
-- fingers, including multi-touch palms. Stop drawing to navigate normally.
function FingerInk:onPalmFrame(slots)
    if self:dialogOnTop() then return true end
    local emit = self.passthrough
    for _, ev in ipairs(slots) do
        local slot = ev.slot or 0
        if ev.id and ev.id >= 0 then
            if not self.contacts[slot] then
                if self.n_contacts == 0 and ev.x and ev.y then
                    local x, y = Capture.toScreen(ev.x, ev.y)
                    self.passthrough = self:inBar(x, y)
                end
                self.contacts[slot] = true
                self.n_contacts = self.n_contacts + 1
            end
            emit = emit or self.passthrough
        elseif self.contacts[slot] then
            self.contacts[slot] = nil
            self.n_contacts = self.n_contacts - 1
        end
    end
    if self.n_contacts == 0 then self.passthrough = false end
    return emit
end

function FingerInk:onStylusEvent(ev)
    if not self.drawing then return false end
    if self:dialogOnTop() then
        self:abortStroke()
        self.pen_down = false
        self.pen_passthrough = true
    end
    if not ev.id or ev.id < 0 then
        local emit = self.pen_passthrough
        if self.pen_down then self:endStroke() end
        self.pen_down, self.pen_passthrough, self.stylus_tool = false, false, nil
        return not emit
    end
    if self.pen_passthrough then return false end
    if not ev.x or not ev.y then return true end
    local x, y = Capture.toScreen(ev.x, ev.y)
    if not self.pen_down and self:inBar(x, y) then
        self.pen_passthrough = true
        return false
    end
    -- KOReader uses 0=finger, 1=pen, 2=eraser, 3=highlighter.
    -- A finger mirror in the dedicated pen slot must never create ink.
    if ev.tool == 0 then return true end
    if self.pen_down and ev.tool ~= self.stylus_tool then self:endStroke() end
    self.pen_down = true
    self.stylus_tool = ev.tool
    self.processing_stylus = true
    self:onContactPoint(ev.slot or 0, ev.x, ev.y)
    self.processing_stylus = false
    return true
end

function FingerInk:inputMode()
    return self.input_mode or (self.stylus_only and "pen_only" or "select")
end
-- Finger selection remains KOReader's own gesture stream: no ink or synthetic
-- highlights. Contacts that began while the pen was down stay palm-blocked.
function FingerInk:onSelectFrame(slots)
    local blocked=self.selection_blocked or self.pen_down
    if self.pen_down then self.selection_blocked=true end
    for _,ev in ipairs(slots) do
        local slot=ev.slot or 0
        if ev.id and ev.id>=0 then
            if not self.contacts[slot] then self.contacts[slot]=true;self.n_contacts=self.n_contacts+1 end
        elseif self.contacts[slot] then
            self.contacts[slot]=nil;self.n_contacts=self.n_contacts-1
        end
    end
    if self.n_contacts==0 then self.selection_blocked=false end
    return self:dialogOnTop() or not blocked
end

function FingerInk:onTouchFrame(slots)
    local mode=self:inputMode()
    if mode=="select" then return self:onSelectFrame(slots) end
    if mode=="pen_only" then return self:onPalmFrame(slots) end
    -- Finger mirrors must not end or cancel an active stylus stroke.
    if self.pen_down then return false end
    if not self.passthrough and self:dialogOnTop() then
        -- Latches for the whole contact sequence, and re-latches on the next
        -- one, so drawing resumes by itself once the dialog is gone.
        self.passthrough = true
        self:abortStroke()
    end

    local was_passthrough = self.passthrough

    for i = 1, #slots do
        local ev = slots[i]
        local slot = ev.slot or 0
        local id = ev.id

        if id and id >= 0 then
            if not self.contacts[slot] then
                self.contacts[slot] = true
                self.n_contacts = self.n_contacts + 1
                if self.n_contacts > 1 and not self.passthrough then
                    self.passthrough = true
                    self:abortStroke()
                end
            end
            if not self.passthrough and ev.x and ev.y then
                self:onContactPoint(slot, ev.x, ev.y)
            end
        else
            if self.contacts[slot] then
                self.contacts[slot] = nil
                self.n_contacts = self.n_contacts - 1
            end
            if self.n_contacts <= 0 then
                self.n_contacts = 0
                if not self.passthrough then
                    self:endStroke()
                end
                self.passthrough = false
                self.draw_slot = nil
            end
        end
    end

    return self.passthrough or was_passthrough
end

function FingerInk:onContactPoint(slot, raw_x, raw_y)
    local x, y = Capture.toScreen(raw_x, raw_y)

    if self.draw_slot == nil then
        if self:inBar(x, y) then
            -- Contact started on the toolbar: hand the whole sequence to
            -- GestureDetector so the button gets its tap.
            self.passthrough = true
            self:abortStroke()
            return
        end
        self.draw_slot = slot
    elseif self.draw_slot ~= slot then
        return
    end

    if self:inBar(x, y) then
        -- Dragged onto the toolbar. End the stroke at the edge rather than
        -- painting over the buttons.
        self:endStroke()
        self.draw_slot = SUSPENDED
        return
    end

    if self.eraser or (self.processing_stylus and self.stylus_tool == 2) then
        self:eraseAt(x, y)
    elseif self.stroke then
        self:addPoint(x, y)
    else
        self:startStroke(x, y)
    end
end

-- ------------------------------------------------------------------ stroke

function FingerInk:startStroke(x, y)
    self.stroke_page = self:currentPage()
    local highlight = self.highlighter or (self.processing_stylus and self.stylus_tool == 3)
    self.stroke = { n = 1, w = highlight and (self.highlighter_width or 24) or self.pen_width,
        tool = highlight and "highlight" or "pen",
        color = highlight and (self.highlighter_color or "yellow") or (self.pen_color or "black"),
        sw = Screen:getWidth(), sh = Screen:getHeight(), x, y }
    Render.stroke(Screen.bb, self.stroke, 0, 0, INK)
    self:refreshBox(x, y, x, y, self.stroke.w)
end

function FingerInk:addPoint(x, y)
    local s = self.stroke
    local i = s.n * 2
    local px, py = s[i - 1], s[i]
    if px == x and py == y then return end

    s[i + 1] = x
    s[i + 2] = y
    s.n = s.n + 1

    Render.segment(Screen.bb, px, py, x, y, s.w, Render.color(s,INK), s.tool == "highlight")
    self:refreshBox(px, py, x, y, s.w)
end

function FingerInk:endStroke()
    local s = self.stroke
    self.stroke = nil
    self.draw_slot = nil
    if not s then return end
    if self.stroke_page ~= self:currentPage() then self:repaint(); return end

    if self.live_refresh then self.live_refresh:flush() end
    local page
    s.t, page, s.pdf_block = self:pageTransform(s)
    self.store:add(page or self.stroke_page, s)
    self:onSaveSettings()
end

function FingerInk:abortStroke()
    if self.live_refresh then self.live_refresh:cancel() end
    if not self.stroke then
        self.draw_slot = nil
        return
    end
    self.stroke = nil
    self.draw_slot = nil
    self:repaint()
end

function FingerInk:eraseAt(x, y)
    local page = self:currentPage()
    local list = self.store:get(page)
    local idx = Store.hit(list, x, y, ERASER_RADIUS)
    if not idx then return end
    self.store:removeAt(page, idx)
    self:onSaveSettings()
    self:repaint()
end

-- ------------------------------------------------------------------ output

function FingerInk:paintTo(bb, x, y)
    local list = self.store:get(self:currentPage())
    if not list then return end
    for i = 1, #list do
        Render.stroke(bb, list[i], 0, 0, INK)
    end
end

function FingerInk:repaint(refresh)
    if self.live_refresh then self.live_refresh:cancel() end
    UIManager:setDirty(self.ui, refresh or "ui")
end

--- DU refresh over the padded bounding box of one segment, clamped to screen.
function FingerInk:refreshBox(x0, y0, x1, y1, w)
    local pad = w + 2
    local x = (x0 < x1 and x0 or x1) - pad
    local y = (y0 < y1 and y0 or y1) - pad
    local bw = (x0 < x1 and x1 - x0 or x0 - x1) + 2 * pad
    local bh = (y0 < y1 and y1 - y0 or y0 - y1) + 2 * pad

    if x < 0 then bw = bw + x; x = 0 end
    if y < 0 then bh = bh + y; y = 0 end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    if x + bw > sw then bw = sw - x end
    if y + bh > sh then bh = sh - y end
    if bw <= 0 or bh <= 0 then return end

    if not self.live_refresh then self.live_refresh = Refresh.new(UIManager, Screen, self.live_fast, self.refresh_hz or 30) end
    self.live_refresh.fast = self.live_fast and not (Device.hasColorScreen and Device:hasColorScreen())
    self.live_refresh:add(x, y, bw, bh)
end

-- -------------------------------------------------------------------- menu

function FingerInk:onFingerInkUndo()
    local page = self:currentPage()
    if not self.store:pop(page) then
        self:notify(_("Nothing to undo on this page"))
        return true
    end
    self:onSaveSettings()
    self:repaint()
    return true
end

--[[--
Hand the ink on `pages` to the PDF and say what happened.

Strokes drawn in a view that does not map onto a page are counted as skipped
and stay in the store, so nothing is silently lost.
]]
local function skippedInkMessage(reasons)
    local kinds, only = 0
    for reason in pairs(reasons or {}) do
        kinds = kinds + 1
        only = reason
    end
    if kinds == 1 then
        if only == "reflow" then
            return _("Ink drawn while PDF reflow was enabled cannot be placed accurately. Turn off reflow, then redraw those strokes.")
        elseif only == "rotation" then
            return _("Ink drawn on a rotated page cannot be placed accurately. Set page rotation to 0°, then redraw those strokes.")
        elseif only == "page_boundary" then
            return _("A stroke crossed the gap between pages in continuous view. Redraw it without crossing the page boundary.")
        elseif only == "legacy" then
            return _("This ink has no saved page-position data, usually because it was drawn with an older PageScribe version. Update the plugin, then redraw those strokes.")
        end
    end
    return _("Some ink could not be mapped safely to a PDF page. Use normal page view with reflow and rotation off, then redraw the skipped strokes without crossing a page boundary.")
end

function FingerInk:saveInk(pages)
    local written, skipped, reasons = InkPdf.save(self.ui, self.store, pages)
    if written == nil then
        self:notify(skipped)   -- on failure the second value is the reason
        return
    end
    if written == 0 then
        self:notify(skipped > 0
            and skippedInkMessage(reasons)
            or _("No ink to save"))
        return
    end

    self:onSaveSettings()
    -- The ink is drawn by MuPDF now, so the whole page has to come back.
    self:repaint("full")
    self:notify(skipped > 0
        and T(_("Saved %1 strokes into the PDF; %2 skipped. %3"),
              written, skipped, skippedInkMessage(reasons))
        or T(_("Saved %1 strokes into the PDF"), written))
end

function FingerInk:setPenWidth(w)
    self.pen_width = w
    G_reader_settings:saveSetting("fingerink_pen_width", w)
    if self.bar then self.bar:update(true) end
end

function FingerInk:setInkColor(tool,id)
    if (tool~="pen" and tool~="highlight") or not Colors.valid(id) then return end
    self:abortStroke()
    local field=tool=="highlight" and "highlighter_color" or "pen_color"
    self[field]=id
    G_reader_settings:saveSetting("fingerink_"..field,id)
    if self.bar then self.bar:update(true) end
end

function FingerInk:setHighlighterWidth(width)
    if width~=12 and width~=24 and width~=36 then return end
    self.highlighter_width=width
    G_reader_settings:saveSetting("fingerink_highlighter_width",width)
    if self.bar then self.bar:update(true) end
end
function FingerInk:setInputMode(mode)
    -- Keep compatibility with the previous boolean setter.
    if type(mode)=="boolean" then mode=mode and "pen_only" or "select" end
    if mode~="select" and mode~="pen_only" and mode~="finger_draw" then return end
    if mode=="pen_only" and not (Device.input and Device.input.registerStylusCallback) then return end
    self:abortStroke();self:resetContacts()
    self.input_mode=mode;self.stylus_only=mode=="pen_only"
    G_reader_settings:saveSetting("fingerink_input_mode",mode)
    G_reader_settings:saveSetting("fingerink_stylus_only",self.stylus_only)
    if self.bar then self.bar:update(true) end
end

function FingerInk:setBarStyle(style)
    self.bar_style = style == "icons" and "icons" or "text"
    G_reader_settings:saveSetting("fingerink_bar_style", self.bar_style)
    self:rebuildBar()
end

function FingerInk:setBarPosition(x, y)
    if not x or not y then return end
    self.bar_position = { x = x, y = y }
    G_reader_settings:saveSetting("fingerink_bar_position", self.bar_position)
end

function FingerInk:penItem(text, w)
    return {
        text = text,
        checked_func = function() return self.pen_width == w end,
        radio = true,
        callback = function() self:setPenWidth(w) end,
    }
end

function FingerInk:sideItem(text, side)
    return {
        text = text,
        checked_func = function() return self.bar_side == side end,
        radio = true,
        callback = function()
            if self.bar_side == side then return end
            self.bar_side = side
            G_reader_settings:saveSetting("fingerink_bar_side", side)
            -- An explicit side selection starts the bar at that edge again;
            -- a later long-press drag can establish a new custom position.
            self.bar_position = nil
            G_reader_settings:delSetting("fingerink_bar_position")
            self:rebuildBar()
        end,
    }
end

function FingerInk:styleItem(text, style)
    return {
        text = text,
        checked_func = function() return self.bar_style == style end,
        radio = true,
        callback = function()
            if self.bar_style == style then return end
            self:setBarStyle(style)
        end,
    }
end

function FingerInk:editNote(page)
    self:setDrawing(false)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = T(_("Note for page %1"), page),
        input = self.notes[page] or "", fullscreen = true,
        allow_newline = true, add_scroll_buttons = true,
        save_callback = function(content)
            self.notes[page] = content ~= "" and content or nil
            self:onSaveSettings()
        end,
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FingerInk:notebookItems()
    local items = {}
    for page_index, page in ipairs(Notebook.pages(self.store, self.notes)) do
        local page_number = page
        local count = #(self.store:get(page) or {})
        local title = (self.notes[page] or ""):match("[^\r\n]+")
        items[#items + 1] = {
            text = T(_("Page %1 · %2 strokes"), page, count)
                .. (title and (" · " .. title:sub(1, 80)) or ""),
            sub_item_table = {
                { text = _("Go to page"), callback = function()
                    self:setDrawing(false)
                    self.ui:handleEvent(Event:new("GotoPage", page_number))
                end },
                { text = _("Edit page note"), callback = function() self:editNote(page_number) end },
                { text = _("Delete page ink and note"), callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Delete ink and note on page %1?"), page_number),
                        ok_text = _("Delete"), ok_callback = function()
                            self.store:clearPage(page_number)
                            self.notes[page_number] = nil
                            self:onSaveSettings()
                            self:repaint()
                        end,
                    })
                end },
            },
        }
    end
    if #items == 0 then items[1] = { text = _("No notes in this book"), enabled = false } end
    return items
end

function FingerInk:exportNotebook()
    self:setDrawing(false)
    local path = self.ui.document.file .. ".fingerink.html"
    local ok, err = Notebook.export(path, self.ui.document.file, self.store, self.notes)
    self:notify(ok and T(_("Notebook saved to %1"), path)
        or T(_("Could not export notebook: %1"), tostring(err)))
end

-- Keep tool choices inline in the tray; no separate settings dialog.
function FingerInk:showToolbarSettings()
    if not self.bar then self:setBarShown(true) end
    self.bar:setExpanded(true)
end
function FingerInk:openNotes()
    local ButtonDialog=require("ui/widget/buttondialog")
    local dialog
    dialog=ButtonDialog:new{title=_("Book notes"),buttons={
        {{text=_("Add / edit this page note"),callback=function() UIManager:close(dialog);self:editNote(self:currentPage()) end}},
        {{text=_("Go to a noted page"),callback=function()
            UIManager:close(dialog)
            local items={}
            for _,page in ipairs(Notebook.pages(self.store,self.notes)) do
                local number=page
                local title=(self.notes[number] or ""):match("[^\r\n]+")
                items[#items+1]={text=T(_("Page %1"),number)..(title and " · "..title:sub(1,60) or ""),callback=function()
                    self:setDrawing(false);self.ui:handleEvent(Event:new("GotoPage",number))
                end}
            end
            if #items==0 then self:notify(_("No notes in this book"));return end
            UIManager:show(require("ui/widget/menu"):new{title=_("Noted pages"),item_table=items,
                width=math.floor(Screen:getWidth()*0.8)})
        end}},
        {{text=_("Export notebook (HTML)"),callback=function() UIManager:close(dialog);self:exportNotebook() end}},
        {{text=_("Back to tools"),callback=function() UIManager:close(dialog);if self.bar then self.bar:setExpanded(true) end end}},
    }}
    UIManager:show(dialog)
end

function FingerInk:addToMainMenu(menu_items)
    menu_items.fingerink = {
        text = _("PageScribe"),
        sorting_hint = "more_tools",
        sub_item_table = {
            { text=_("Input mode"),sub_item_table=(function()
                local choices={}
                for _,entry in ipairs({{"select",_("Pen writes · Finger selects")},{"pen_only",_("Pen only")},{"finger_draw",_("Finger draws")}}) do
                    local mode,label=entry[1],entry[2]
                    choices[#choices+1]={text=label,radio=true,
                        enabled_func=function() return mode~="pen_only" or (Device.input and Device.input.registerStylusCallback~=nil) end,
                        checked_func=function() return self:inputMode()==mode end,
                        callback=function() self:setInputMode(mode) end}
                end
                return choices
            end)()},
            { text = _("Book notebook"), sub_item_table_func = function() return self:notebookItems() end },
            { text = _("Add or edit this page note"), callback = function() self:editNote(self:currentPage()) end },
            { text = _("Export notebook (HTML with handwriting)"), callback = function() self:exportNotebook() end },
            { text = _("Select text / highlight"), callback = function() self:setDrawing(false) end,
                help_text = _("Stops drawing. Long-press and drag over text to use KOReader's searchable highlights and notes.") },
            {
                -- Close the menu before returning to the page and its chosen input mode.
                text = _("Start drawing"),
                enabled_func = function() return not self.drawing end,
                callback = function() self:setDrawing(true) end,
                help_text = _([[Tap the small status tab. Read, Pen, Marker, and Erase activate immediately. Width and input options appear inline below the selected tool. Drag anywhere on the tray to move it. Audio opens dictionary pronunciation settings; × closes the tray and its options; the handwriting icon reopens it.]]),
            },
            {
                text = _("Open toolbar"),
                checked_func = function() return self.bar and self.bar.expanded end,
                check_callback_updates_menu = true,
                callback = function(touchmenu_instance)
                    self:onFingerInkBar()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text = _("Toolbar side"),
                separator = true,
                sub_item_table = {
                    self:sideItem(_("Left"), "left"),
                    self:sideItem(_("Right"), "right"),
                },
            },
            {
                text = _("Display update rate"),
                sub_item_table = (function()
                    local items = {}
                    for _, hz in ipairs({20,30,60}) do
                        local rate = hz
                        items[#items+1] = { text = tostring(rate) .. " Hz", radio=true,
                            checked_func=function() return self.refresh_hz == rate end,
                            callback=function()
                                self.refresh_hz=rate
                                G_reader_settings:saveSetting("fingerink_refresh_hz",rate)
                                self.live_refresh:flush()
                                self.live_refresh.interval=1/rate
                            end }
                    end
                    return items
                end)(),
                help_text = _("30 Hz batches pen samples to reduce Android screen-copy overhead. Try 20 Hz if the device falls behind; 60 Hz posts more often. All stroke points are retained."),
            },
            {
                text = _("Pen width"),
                sub_item_table = {
                    self:penItem("2 px", 2), self:penItem("4 px", 4), self:penItem("7 px", 7),
                    self:penItem("9 px", 9), self:penItem("10 px", 10), self:penItem("12 px", 12),
                },
            },
            {
                text = _("Fast refresh while drawing"),
                checked_func = function() return self.live_fast end,
                callback = function()
                    self.live_fast = not self.live_fast
                    G_reader_settings:saveSetting("fingerink_live_fast", self.live_fast)
                end,
                help_text = _([[On: strokes appear with the DU waveform — quick, but grainy and it leaves ghosting until the next page turn. Off: slower, cleaner.]]),
                separator = true,
            },
            {
                text = _("Save this page into PDF"),
                keep_menu_open = true,
                callback = function()
                    self:saveInk({ self:currentPage() })
                end,
                help_text = _([[Writes the ink as a real PDF ink annotation, so it shows up in any PDF reader rather than only here. It stops being PageScribe's, so it can no longer be undone or erased with the eraser — clear it in a PDF editor instead.]]),
            },
            {
                text = _("Save whole document into PDF"),
                keep_menu_open = true,
                separator = true,
                callback = function()
                    local blocked = InkPdf.blocker(self.ui)
                    if blocked then
                        self:notify(blocked)
                        return
                    end
                    local pages = self.store:pageList()
                    if #pages == 0 then
                        self:notify(_("No ink in this document"))
                        return
                    end
                    UIManager:show(ConfirmBox:new{
                        text = _("Write all ink into the PDF? It becomes a normal annotation and can no longer be undone or erased here."),
                        ok_text = _("Save"),
                        ok_callback = function() self:saveInk(pages) end,
                    })
                end,
            },
            {
                text = _("Clear this page"),
                keep_menu_open = true,
                callback = function()
                    if self.store:clearPage(self:currentPage()) then
                        self:onSaveSettings()
                        self:repaint()
                    else
                        self:notify(_("No ink on this page"))
                    end
                end,
            },
            {
                text = _("Clear whole document"),
                keep_menu_open = true,
                callback = function()
                    if self.store:countPages() == 0 then
                        self:notify(_("No ink in this document"))
                        return
                    end
                    UIManager:show(ConfirmBox:new{
                        text = _("Delete all ink in this document?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            self.store:clearAll()
                            self:onSaveSettings()
                            self:repaint()
                        end,
                    })
                end,
            },
            updater:menuItem(),
        },
    }
end

return FingerInk
