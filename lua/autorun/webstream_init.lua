include("webstream/main.lua")
AddCSLuaFile("webstream/main.lua")

local files = file.Find("webstream/overrides/*", "LUA")
for _, f in pairs(files) do
    include("webstream/overrides/" .. f)
    AddCSLuaFile("webstream/overrides/" .. f)
end