-- Direct toolbar: each tool activates on its first tap; no pending selection.
-- Render into a bounded private buffer. Never pass fractional pixel coordinates
-- to BlitBuffer's pixel primitives (fractional rows can corrupt screen offsets).
local BB=require("ffi/blitbuffer")
local Device=require("device")
local Font=require("ui/font")
local Geom=require("ui/geometry")
local TextWidget=require("ui/widget/textwidget")
local UIManager=require("ui/uimanager")
local WidgetContainer=require("ui/widget/container/widgetcontainer")
local _=require("gettext")
local Screen=Device.screen
local Colors=require("ink_colors")
local InkBar=WidgetContainer:extend{side="right"}
local INPUT={onGesture=true,onKeyPress=true,onKeyRepeat=true,onKeyRelease=true}
local floor=math.floor
local function round(x) return floor(x+.5) end
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function copy(d) return {x=d.x,y=d.y,w=d.w,h=d.h} end
local function union(a,b)
    local x,y=math.min(a.x,b.x),math.min(a.y,b.y)
    return Geom:new{x=x,y=y,w=math.max(a.x+a.w,b.x+b.w)-x,h=math.max(a.y+a.h,b.y+b.h)-y}
end
local function rgb(r,g,b) return {r,g or r,b or r} end
local THEMES={
    color={shell=rgb(245,247,251),panel=rgb(255),ink=rgb(23,36,59),muted=rgb(73,90,113),
        line=rgb(163,177,197),soft=rgb(234,240,249),white=rgb(255),
        pen=rgb(35,88,184),highlight=rgb(148,99,0),eraser=rgb(183,68,55),read=rgb(5,111,111),action=rgb(35,88,184)},
    mono={shell=rgb(255),panel=rgb(255),ink=rgb(0),muted=rgb(0),line=rgb(0),soft=rgb(255),
        white=rgb(255),pen=rgb(0),highlight=rgb(0),eraser=rgb(0),read=rgb(0),action=rgb(0)},
}
local NAMES={read=_("Read"),pen=_("Pen"),highlight=_("Marker"),eraser=_("Erase")}
function InkBar:displayInfo()
    local p,id=self.plugin,self:activeId()
    local mode=p.input_mode or (p.stylus_only and "pen_only" or "select")
    local input=mode=="pen_only" and _("Pen only") or mode=="finger_draw" and _("Finger draws") or _("Finger selects text")
    local width=tostring(id=="highlight" and (p.highlighter_width or 24) or p.pen_width or 4).." px"
    local help={read=_("Turn pages or hold a word to look it up."),
        pen=_("Write directly on the book page."),
        highlight=_("Draw a broad highlight over the page."),
        eraser=_("Touch handwriting to erase a whole stroke.")}
    local detail=id=="read" and _("Writing off") or (id=="eraser" and input or width.." · "..input)
    return {id=id,name=NAMES[id],status=NAMES[id].._(" active"),detail=detail,help=help[id]}
end
function InkBar:canUndo()
    local p=self.plugin
    if not p.store or not p.currentPage then return false end
    local ink=p.store:get(p:currentPage())
    return ink~=nil and #ink>0
end
function InkBar:color(value)
    local key=value[1]*65536+value[2]*256+value[3]
    if not self.color_cache[key] then
        self.color_cache[key]=self.color_mode and BB.ColorRGB32(value[1],value[2],value[3],255)
            or (BB.Color8 and BB.Color8(value[1]) or (value[1]<128 and BB.COLOR_BLACK or BB.COLOR_WHITE))
    end
    return self.color_cache[key]
end
function InkBar:rect(bb,x,y,w,h,value,radius)
    local c=self:color(value)
    if radius then
        if self.color_mode then bb:paintRoundedRectRGB32(x,y,w,h,c,radius) else bb:paintRoundedRect(x,y,w,h,c,radius) end
    elseif self.color_mode then bb:paintRectRGB32(x,y,w,h,c)
    else bb:paintRect(x,y,w,h,c) end
end
-- TextWidget's usual glyph blit converts colors to gray. Bind only its local
-- drawing target to the RGB blitter; never patch a shared/global buffer.
function InkBar:textTarget(bb)
    if not self.color_mode or not bb.colorblitFromRGB32 then return bb end
    return setmetatable({},{__index=function(_,key)
        local member=key=="colorblitFrom" and bb.colorblitFromRGB32 or bb[key]
        if type(member)=="function" then return function(_,...) return member(bb,...) end end
        return member
    end})
end

function InkBar:init()
    self.base_scale=Screen:scaleBySize(100)/100
    self.compact_scale=math.min(self.base_scale,1.5)
    self.expanded_scale=math.min(self.base_scale,(Screen:getWidth()-8)/540,(Screen:getHeight()-8)/176)
    self.scale=self.compact_scale
    self.tools={"read","pen","highlight","eraser"}
    self.color_mode=not not (Device.hasColorScreen and Device:hasColorScreen() and BB.ColorRGB32 and BB.TYPE_BBRGB32)
    self.palette=THEMES[self.color_mode and "color" or "mono"];self.color_cache={}
    self.expanded=false;self.labels={}
    self.hub_w,self.hub_h=self:S(54),self:S(54)
    local default_x=self.side=="left" and 8 or Screen:getWidth()-self.hub_w-8
    local default_y=round((Screen:getHeight()-self.hub_h)/2)
    -- Move the previous bottom-edge default above the reader's progress bar.
    -- Keep custom placements elsewhere exactly as the user saved them.
    local old_default=self.position
        and math.abs(self.position.y-(Screen:getHeight()-self.hub_h-8))<=4
        and (math.abs(self.position.x-8)<=4
            or math.abs(self.position.x-(Screen:getWidth()-self.hub_w-8))<=4)
    if not self.position or old_default then
        self.position={x=default_x,y=default_y}
        if old_default then self.plugin:setBarPosition(default_x,default_y) end
    end
    self:layout();self:update(false)
end
function InkBar:S(value) return math.max(1,round(value*self.scale)) end
function InkBar:activeId()
    local p=self.plugin
    return not p.drawing and "read" or p.eraser and "eraser" or p.highlighter and "highlight" or "pen"
end
function InkBar:traySize()
    return self.expanded and self:S(540) or self.hub_w,
        self.expanded and self:S(self:activeId()=="read" and 48 or self:activeId()=="eraser" and 92 or 176) or self.hub_h
end
function InkBar:clampPosition(x,y)
    local w,h=self:traySize()
    return round(clamp(x,2,Screen:getWidth()-w-2)),round(clamp(y,2,Screen:getHeight()-h-2))
end
function InkBar:layout()
    self.scale=self.expanded and self.expanded_scale or self.compact_scale
    local x,y=self:clampPosition(self.position.x,self.position.y)
    local w,h=self:traySize()
    self.dimen=Geom:new{x=x,y=y,w=w,h=h}
    self.cx,self.cy=x+round(w/2),y+round(h/2)
end
function InkBar:getVisibleDimen() return self.dimen end
function InkBar:getSize() return self.dimen end
function InkBar:contains(x,y)
    local d=self.dimen
    if not self.expanded then
        local dx,dy=x-(d.x+d.w/2),y-(d.y+d.h/2)
        return dx*dx+dy*dy<=(d.w/2)^2
    end
    return x>=d.x and y>=d.y and x<d.x+d.w and y<d.y+d.h
end
function InkBar:setExpanded(on)
    on=on and true or false
    if on==self.expanded then return end
    if self.drag_start then self:finishDrag() end
    local old=copy(self.dimen)
    self.expanded=on
    if on then self.plugin:abortStroke() end
    self:layout();self:update(false)
    -- Refresh both the old and the new bounds; closing performs a clean eink
    -- refresh so the reader under the panel cannot retain toolbar outlines.
    local damage=union(old,self.dimen)
    UIManager:setDirty(self.plugin.ui,on and "ui" or "full",damage)
    UIManager:setDirty(self,"ui",damage)
end
function InkBar:freeSurface()
    if self.surface then self.surface:free();self.surface=nil end
end
function InkBar:update(refresh)
    local old=self.dimen and copy(self.dimen)
    local info=self:displayInfo()
    self.state=info.name;self.subtitle=info.detail;self.active_label=info.status
    self:layout()
    for _,label in pairs(self.labels) do label:free() end
    self.labels={};self:freeSurface()
    if refresh then
        local damage=old and union(old,self.dimen) or self.dimen
        if old and (old.x~=self.dimen.x or old.y~=self.dimen.y or old.h~=self.dimen.h) then
            UIManager:setDirty(self.plugin.ui,"ui",damage)
        end
        UIManager:setDirty(self,"ui",damage)
    end
end
-- Every glyph is measured and centered inside its own box at the actual DPI.
function InkBar:text(bb,key,text,size,bold,color,x,y,w,h,align)
    local face_size=size*self.scale/self.base_scale
    local t=TextWidget:new{text=text,face=Font:getFace("smallinfofont",face_size),bold=bold,
        fgcolor=color,max_width=w}
    local dim=t:getSize()
    while dim.h>h and face_size>5 do
        t:free();face_size=face_size-1
        t=TextWidget:new{text=text,face=Font:getFace("smallinfofont",face_size),bold=bold,fgcolor=color,max_width=w}
        dim=t:getSize()
    end
    self.labels[key]=t
    local tx=align=="left" and x or x+round((w-dim.w)/2)
    local ty=y+round((h-dim.h)/2)
    t:paintTo(bb,round(tx),round(ty))
end
-- All rendered buttons and hit targets use the same geometry.
function InkBar:buttons()
    local active,p=self:activeId(),self.plugin
    local list={}
    local function add(id,label,x,y,w,h,selected,enabled)
        list[#list+1]={id=id,label=label,x=x,y=y,w=w,h=h,selected=selected,enabled=enabled~=false}
    end
    if not self.expanded then return list end
    add("read",_("Read"),28,4,56,40,active=="read")
    add("pen",_("Pen"),86,4,56,40,active=="pen")
    add("highlight",_("Marker"),144,4,88,40,active=="highlight")
    add("eraser",_("Erase"),234,4,62,40,active=="eraser")
    add("undo",_("Undo"),298,4,52,40,false,self:canUndo())
    add("note",_("Notes"),352,4,58,40)
    if p.ui.dictionary_audio and p.ui.dictionary_audio.showSettings then
        add("audio",_("Audio"),412,4,64,40)
    end
    add("collapse","×",508,4,28,28)
    if active~="read" then
        local widths=active=="highlight" and {12,24,36} or {2,4,7,9,10,12}
        if active~="eraser" then
            local current=active=="highlight" and (p.highlighter_width or 24) or p.pen_width
            local step=288/#widths
            for i,w in ipairs(widths) do add("width_"..w,tostring(w).." px",54+(i-1)*step,52,step-2,36,current==w) end
        end
        local mode=p.input_mode or (p.stylus_only and "pen_only" or "select")
        local y=active=="eraser" and 52 or 96
        add("select",_("Pen writes · Finger selects"),4,y,232,34,mode=="select")
        add("pen_only",_("Pen only"),238,y,118,34,mode=="pen_only",Device.input and Device.input.registerStylusCallback~=nil)
        add("finger_draw",_("Finger draws"),358,y,178,34,mode=="finger_draw")
    end
    if active=="pen" or active=="highlight" then
        local selected=active=="highlight" and (p.highlighter_color or "yellow") or (p.pen_color or "black")
        for i,entry in ipairs(Colors.list) do
            add("color_"..entry.id,entry.name,4+(i-1)*67,138,65,34,selected==entry.id)
        end
    end
    return list
end
-- Draw the launcher as a pen nib and handwriting, without font glyphs/assets.
function InkBar:handwritingIcon(bb,color)
    local function line(ax,ay,bx,by)
        local x,y,ex,ey=self:S(3+ax*1.15),self:S(10+ay*1.15),self:S(3+bx*1.15),self:S(10+by*1.15)
        local dx,dy=math.abs(ex-x),-math.abs(ey-y)
        local sx,sy=x<ex and 1 or -1,y<ey and 1 or -1
        local err=dx+dy
        while true do
            self:rect(bb,x,y,self:S(1),self:S(1),color)
            if x==ex and y==ey then break end
            local twice=2*err
            if twice>=dy then err=err+dy;x=x+sx end
            if twice<=dx then err=err+dx;y=y+sy end
        end
    end
    local nib={{24,6},{29,11},{18,22},{12,24},{14,18},{24,6}}
    for i=2,#nib do line(nib[i-1][1],nib[i-1][2],nib[i][1],nib[i][2]) end
    line(21,9,26,14);line(14,18,18,22)
    local writing={{7,25},{11,25},{14,23},{17,25},{23,25},{27,22},{30,25},{39,25}}
    for i=2,#writing do line(writing[i-1][1],writing[i-1][2],writing[i][1],writing[i][2]) end
end

function InkBar:render()
    local d,p,info=self.dimen,self.palette,self:displayInfo()
    self.info=info;self.undo_available=self:canUndo()
    local bb=BB.new(d.w,d.h,self.color_mode and BB.TYPE_BBRGB32 or Screen.bb:getType());self.surface=bb
    -- Initialize every pixel, including corners outside rounded shapes.
    self:rect(bb,0,0,d.w,d.h,p.shell)
    self:rect(bb,0,0,d.w,d.h,p.line,self.expanded and self:S(5) or floor(math.min(d.w,d.h)/2))
    local edge=self:S(1)
    self:rect(bb,edge,edge,d.w-2*edge,d.h-2*edge,p.shell,
        self.expanded and self:S(4) or floor((math.min(d.w,d.h)-2*edge)/2))
    local function box(x,y,w,h,color,radius)
        self:rect(bb,self:S(x),self:S(y),self:S(w),self:S(h),color,radius and self:S(radius))
    end
    local function text(key,value,size,bold,color,x,y,w,h)
        self:text(self:textTarget(bb),key,value,size,bold,self:color(color),self:S(x),self:S(y),self:S(w),self:S(h))
    end
    local active=p[info.id]
    if not self.expanded then
        local inset=self:S(2)
        self:rect(bb,inset,inset,d.w-2*inset,d.h-2*inset,active,floor((math.min(d.w,d.h)-2*inset)/2))
        self:handwritingIcon(bb,p.white)
        return
    end
    text("drag","⠿",18,true,p.muted,3,4,22,40)
    if info.id~="read" then
        box(4,48,532,1,p.line)
        text("context",info.id=="eraser" and _("Stroke") or info.name,11,true,active,4,52,48,36)
    end
    for _,button in ipairs(self:buttons()) do
        local color_id=button.id:match("^color_(.+)")
        local palette_color=color_id and Colors.get(color_id).rgb
        local color=palette_color and self.color_mode and palette_color or p[button.id] or active
        box(button.x,button.y,button.w,button.h,button.selected and color or p.line,3)
        if not button.selected then box(button.x+1,button.y+1,button.w-2,button.h-2,button.enabled and p.panel or p.soft,2) end
        if palette_color then
            -- Named chips remain understandable on monochrome screens.
            local swatch=self.color_mode and palette_color or p.ink
            box(button.x+3,button.y+4,button.w-6,3,swatch)
        end
        local label=(button.selected and "✓ " or "")..button.label
        local size=button.id=="collapse" and 18 or color_id and 10 or button.id:match("^width_") and 10.5 or button.id=="select" and 11 or 12
        local ink=button.selected and p.white or p.ink
        if button.selected and palette_color and self.color_mode
            and palette_color[1]*0.299+palette_color[2]*0.587+palette_color[3]*0.114>140 then ink=p.ink end
        text(button.id,label,size,button.selected,
            ink,button.x+2,button.y+1,button.w-4,button.h-2)
    end
end

function InkBar:paintTo(bb)
    if self.surface and self.undo_available~=self:canUndo() then self:update(false) end
    if not self.surface then self:render() end
    local d=self.dimen
    if self.expanded then
        bb:blitFrom(self.surface,d.x,d.y,0,0,d.w,d.h)
    else
        -- Copy only the circular button. Page text outside it stays untouched.
        local radius=d.w/2
        for row=0,d.h-1 do
            local dy=row+.5-d.h/2
            local extent=math.sqrt(math.max(0,radius*radius-dy*dy))
            local left=math.max(0,math.ceil(radius-extent-.5))
            local right=math.min(d.w-1,floor(radius+extent-.5))
            if right>=left then bb:blitFrom(self.surface,d.x+left,d.y+row,left,row,right-left+1,1) end
        end
    end
end
function InkBar:activate(id)
    local p=self.plugin
    if id=="collapse" then self:setExpanded(false)
    elseif id=="undo" then if self:canUndo() then p:onFingerInkUndo();self:update(true) end
    elseif id=="note" then self:setExpanded(false);p:openNotes()
    elseif id=="audio" then
        self:setExpanded(false)
        if p.ui.dictionary_audio then p.ui.dictionary_audio:showSettings()
        else p:notify(_("Enable Dictionary audio in the plugin manager, then restart KOReader.")) end
    elseif id=="select" or id=="pen_only" or id=="finger_draw" then p:setInputMode(id)
    elseif id:match("^color_") then p:setInkColor(self:activeId(),id:match("^color_(.+)"))
    elseif id:match("^width_") then
        local width=tonumber(id:match("%d+"))
        if self:activeId()=="highlight" then p:setHighlighterWidth(width) else p:setPenWidth(width) end
        self:update(true)
    elseif id=="read" then p:setDrawing(false)
    else p:setTool(id) end
end
function InkBar:buttonAt(x,y)
    for _,button in ipairs(self:buttons()) do
        local left,top=self.dimen.x+self:S(button.x),self.dimen.y+self:S(button.y)
        if x>=left and x<left+self:S(button.w) and y>=top and y<top+self:S(button.h) then return button end
    end
end
function InkBar:finishDrag(pos)
    local drag=self.drag_start
    if not drag then return end
    if pos then self:moveDrag(pos) end
    self.drag_start=nil
    UIManager:setDirty(self.plugin.ui,"full",union(drag.origin,self.dimen))
    self.plugin:setBarPosition(self.dimen.x,self.dimen.y)
end
function InkBar:moveDrag(pos)
    local s=self.drag_start
    local old=copy(self.dimen)
    local x,y=self:clampPosition(s.px+pos.x-s.x,s.py+pos.y-s.y)
    self.position={x=x,y=y};self:layout()
    -- Moving reuses the cached tray pixels. Restore the old page footprint.
    local damage=union(old,self.dimen)
    UIManager:setDirty(self.plugin.ui,"ui",damage);UIManager:setDirty(self,"ui",damage)
end
function InkBar:onGesture(ges)
    local pos,kind=ges.pos,ges.ges
    -- A fresh contact/tap cannot belong to a previous drag. Recover even if a
    -- platform dropped its terminal event, without swallowing this new tap.
    if (kind=="touch" or kind=="tap") and self.drag_start then self:finishDrag() end
    if not pos then return end
    local inside=self:contains(pos.x,pos.y)
    if kind=="hold" and inside then
        if self.drag_start then self:finishDrag() end
        self.drag_start={x=pos.x,y=pos.y,px=self.dimen.x,py=self.dimen.y,origin=copy(self.dimen)};return true
    end
    if kind=="pan" or kind=="hold_pan" then
        if not self.drag_start then
            local start=ges.start_pos
            if not start or not self:contains(start.x,start.y) then return inside or nil end
            self.drag_start={x=start.x,y=start.y,px=self.dimen.x,py=self.dimen.y,origin=copy(self.dimen)}
        end
        self:moveDrag(pos);return true
    end
    if kind=="swipe" or kind=="multiswipe" then
        -- Swipes report their start in pos, and their lift point in end_pos.
        if not self.drag_start and inside and ges.end_pos then
            self.drag_start={x=pos.x,y=pos.y,px=self.dimen.x,py=self.dimen.y,origin=copy(self.dimen)}
        end
        if self.drag_start then self:finishDrag(ges.end_pos);return true end
    end
    if (kind=="pan_release" or kind=="hold_release") and self.drag_start then
        self:finishDrag(pos);return true
    end
    if self.drag_start then return true end
    if kind~="tap" then return inside or nil end
    if not inside then
        if self.expanded then self:setExpanded(false);return true end
        return
    end
    if not self.expanded then self:setExpanded(true);return true end
    local button=self:buttonAt(pos.x,pos.y)
    if button and button.enabled then self:activate(button.id) end
    return true
end
function InkBar:windowBelow()
    for i=#UIManager._window_stack,1,-1 do local w=UIManager._window_stack[i].widget;if w~=self and not w.toast then return w end end
end
function InkBar:handleEvent(event)
    if WidgetContainer.handleEvent(self,event) then return true end
    if INPUT[event.handler] then local below=self:windowBelow();if below then return below:handleEvent(event) end end
end
function InkBar:onCloseWidget()
    for _,label in pairs(self.labels) do label:free() end
    self.labels={};self:freeSurface()
end
return InkBar
