local old_exit,old_print=os.exit,print;os.exit=function(code) if code~=0 then error('Plugin regressions failed') end end;print=function() end;dofile('test.lua');os.exit,print=old_exit,old_print
local BB=require('ffi/blitbuffer')
local Screen=require('device').screen
Screen.bb={getType=function() return 1 end}
local function escape(s) return s:gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;') end
BB.Color8=function(v) return string.format('#%02x%02x%02x',v,v,v) end
BB.ColorRGB32=function(r,g,b,a) return string.format('#%02x%02x%02x',r,g,b) end
BB.TYPE_BBRGB32=99
require('device').hasColorScreen=function() return arg[1]=='color' end
BB.new=function(w,h)
 local b={w=w,h=h,svg={}}
 function b:fill(c) self.svg[#self.svg+1]=string.format('<rect width="%d" height="%d" fill="%s"/>',self.w,self.h,c) end
 function b:paintRect(x,y,rw,rh,c)
  assert(x%1==0 and y%1==0 and rw%1==0 and rh%1==0)
  self.svg[#self.svg+1]=string.format('<rect x="%d" y="%d" width="%d" height="%d" fill="%s"/>',x,y,rw,rh,c)
 end
 function b:paintRoundedRect(x,y,rw,rh,c,r)
  self.svg[#self.svg+1]=string.format('<rect x="%d" y="%d" width="%d" height="%d" rx="%d" fill="%s"/>',x,y,rw,rh,r,c)
 end
 b.paintRectRGB32=b.paintRect;b.paintRoundedRectRGB32=b.paintRoundedRect
 function b:free() end
 return b
end
local Text=require('ui/widget/textwidget')
Text.new=function(_,o)
 o.getSize=function()
  return {w=math.min(o.max_width or 10000,utf8.len(o.text)*o.face.size*.55),h=math.ceil(o.face.size*1.35)}
 end
 o.free=function() end
 o.paintTo=function(self,bb,x,y)
  local h=self:getSize().h
  bb.svg[#bb.svg+1]=string.format('<text x="%g" y="%g" font-family="Inter,Arial,sans-serif" font-size="%g" fill="%s" font-weight="%s">%s</text>',x,y+h*.78,self.face.size,self.fgcolor,self.bold and 'bold' or 'normal',escape(self.text))
 end
 return o
end
package.loaded['ink_bar']=nil
local state=arg[2] or 'pen'
local p={drawing=state~='read',eraser=state=='erase',highlighter=state=='marker',
 pen_width=4,highlighter_width=24,pen_color='blue',highlighter_color='yellow',
 stylus_only=false,input_mode='select',ui={dictionary_audio={showSettings=function() end}},
 abortStroke=function() end,store={get=function() return {{n=1}} end},currentPage=function() return 1 end}
local bar=require('ink_bar'):new{plugin=p}
bar:setExpanded(state~='launcher');bar:update(false);bar:render()
local out=assert(io.open('media-demo/public/ui/'..(arg[1] or 'mono')..'-'..state..'.svg','w'))
out:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">',bar.dimen.w,bar.dimen.h,bar.dimen.w,bar.dimen.h))
if state=='launcher' then out:write(string.format('<defs><clipPath id="round"><circle cx="%g" cy="%g" r="%g"/></clipPath></defs><g clip-path="url(#round)">',bar.dimen.w/2,bar.dimen.h/2,bar.dimen.w/2)) end
out:write(table.concat(bar.surface.svg,'\n'));if state=='launcher' then out:write('</g>') end;out:write('</svg>');out:close()
