-- Read visible labels/selected states from Dictionary Audio's actual Lua dialog.
local repo=assert(arg[1], 'Pass the Dictionary Audio checkout path')
local captured,lookup={},{ }
local Widget={};function Widget:extend(o) return setmetatable(o or {},{__index=self}) end
package.preload['ui/widget/container/widgetcontainer']=function() return Widget end
package.preload['ui/widget/notification']=function() return {new=function(_,o)return o end}end
package.preload['ui/widget/buttondialog']=function() return {new=function(_,o)return o end}end
package.preload['ui/uimanager']=function()return {show=function(_,o)captured=o end,close=function()end}end
package.preload['datastorage']=function()return {getDataDir=function()return '/preview' end}end
package.preload['device']=function()return {isAndroid=function()return true end,screen={getWidth=function()return 1000 end}}end
package.preload['gettext']=function()return function(s)return s end end
package.preload['android']=function()return {}end
package.preload['ffi']=function()return {}end
G_reader_settings={readSetting=function()end,saveSetting=function()end}
local Audio=dofile(repo..'/dictionary-audio.koplugin/main.lua')
local a=Audio:extend{ui={menu={registerToMainMenu=function()end},dictionary={addToDictButtons=function(_,o)lookup[#lookup+1]=o.text end}}}
a:init();a:showSettings()
local rows={}
for _,row in ipairs(captured.buttons)do local r={};for _,b in ipairs(row)do r[#r+1]={text=b.text,enabled=b.enabled~=false}end;rows[#rows+1]=r end
local function json(v)
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')..'"' end
 if type(v)=='boolean'or type(v)=='number'then return tostring(v)end
 local out={};if #v>0 then for _,o in ipairs(v)do out[#out+1]=json(o)end;return '['..table.concat(out,',')..']'end
 local keys={};for k in pairs(v)do keys[#keys+1]=k end;table.sort(keys);for _,k in ipairs(keys)do out[#out+1]=json(k)..':'..json(v[k])end;return '{'..table.concat(out,',')..'}'
end
local f=assert(io.open('media-demo/src/audio-ui.json','w'));f:write(json({title=captured.title,rows=rows,lookup=lookup}));f:close()
