-- Rebuilds Media/icon.tga from icon.lua (not loaded by WoW).
-- Run from this folder:  luajit build.lua
local I = dofile("img.lua")
local icons = dofile("icon.lua")
local sheet = I.new(256, 128)   -- cells 64x82 at x = 0, 64, 128, 192
for i, state in ipairs({ "up", "mouseover", "down", "disabled" }) do I.over(sheet, icons[state], (i - 1) * 64, 0) end
I.savetga(sheet, "../icon.tga")
print("wrote ../icon.tga")
