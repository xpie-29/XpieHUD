-- Procedural chest icon for the main button, in the style of Blizzard's micro
-- menu icons (UI-HUD-MicroMenu-*, interface/hud/uimicromenu2x): painted
-- gradients, dark outline, soft drop shadow; Mouseover lighter, Down darker,
-- Disabled grey. Cell 64x82 as in Blizzard's 2x sheet. Used by build.lua.
local I = dofile("img.lua")
local SS = 6                     -- supersampling
local W, H = 64, 82
local abs, max, min, sqrt, floor = math.abs, math.max, math.min, math.sqrt, math.floor

-- signed distance helpers (negative inside)
local function box(px, py, x0, y0, x1, y1, r)
  r = r or 0
  local cx, cy = (x0+x1)/2, (y0+y1)/2
  local hx, hy = (x1-x0)/2 - r, (y1-y0)/2 - r
  local dx, dy = abs(px-cx) - hx, abs(py-cy) - hy
  local ox, oy = max(dx,0), max(dy,0)
  return sqrt(ox*ox+oy*oy) + min(max(dx,dy),0) - r
end
local function ellipse(px, py, cx, cy, rx, ry)  -- approximate
  local k = sqrt(((px-cx)/rx)^2 + ((py-cy)/ry)^2)
  return (k - 1) * min(rx, ry)
end
local function union(a, b) return min(a, b) end
local function inter(a, b) return max(a, b) end
local function lerp(a, b, t) return a + (b-a)*t end
local function mix3(c1, c2, t) return { lerp(c1[1],c2[1],t), lerp(c1[2],c2[2],t), lerp(c1[3],c2[3],t) } end
local function clamp(t) return max(0, min(1, t)) end

-- Geometry (cell px)
local L, R = 11, 53            -- chest left/right
local LID_TOP, LID_SEAM = 17, 36
local BODY_BOT = 61
local CX = 32

local function lidShape(x, y)
  local rect = box(x, y, L, 25, R, LID_SEAM, 0)
  local dome = ellipse(x, y, CX, 26, (R-L)/2, 9)
  return inter(union(rect, dome), box(x, y, L, LID_TOP, R, LID_SEAM, 0))
end
local function bodyShape(x, y) return box(x, y, L, LID_SEAM, R, BODY_BOT, 3) end
local function chestShape(x, y) return union(lidShape(x, y), bodyShape(x, y)) end
local function bands(x, y)     -- gold straps + rim, clipped to the chest
  local straps = union(box(x, y, 16, 0, 21, 99, 0.5), box(x, y, 43, 0, 48, 99, 0.5))
  local rim = box(x, y, L, LID_SEAM-2.5, R, LID_SEAM+2.5, 0)
  local foot = box(x, y, L, BODY_BOT-4, R, BODY_BOT, 0)
  return inter(union(union(straps, rim), foot), chestShape(x, y) + 0.0)
end
local function lockPlate(x, y) return box(x, y, CX-6, LID_SEAM-4, CX+6, LID_SEAM+10, 2.5) end
local function keyhole(x, y)
  return union(ellipse(x, y, CX, LID_SEAM+3.5, 1.9, 1.9), box(x, y, CX-1, LID_SEAM+3.5, CX+1, LID_SEAM+7.5, 0.4))
end

-- Palette
local WOOD_TOP, WOOD_BOT = { 0.70, 0.40, 0.19 }, { 0.36, 0.17, 0.07 }
local LID_TOP_C, LID_BOT_C = { 0.80, 0.48, 0.23 }, { 0.50, 0.26, 0.10 }
local GOLD_TOP, GOLD_BOT = { 1.00, 0.90, 0.45 }, { 0.78, 0.47, 0.08 }
local OUTLINE = { 0.12, 0.06, 0.02 }

local function shade(x, y)
  -- returns r,g,b,a for one sample (premultiplied-free), outline included
  local dc = min(chestShape(x, y), lockPlate(x, y))
  local outlineW = 1.6
  if dc > outlineW then return nil end
  if dc > 0 then return OUTLINE[1], OUTLINE[2], OUTLINE[3], 1 end
  local c
  local dk = keyhole(x, y)
  local dl = lockPlate(x, y)
  local db = bands(x, y)
  if dk < 0 then
    c = { 0.08, 0.04, 0.02 }
  elseif dl < 0 then
    c = mix3(GOLD_TOP, GOLD_BOT, clamp((y - (LID_SEAM-4)) / 14))
    if dl > -1.1 then c = mix3(c, { 0.45, 0.25, 0.04 }, 0.7) end           -- plate edge
    if y < LID_SEAM-2 and dl < -1.1 then c = mix3(c, { 1, 1, 0.85 }, 0.35) end -- top shine
  elseif db < 0 then
    c = mix3(GOLD_TOP, GOLD_BOT, clamp((y - LID_TOP) / (BODY_BOT - LID_TOP)))
    if db > -0.9 then c = mix3(c, { 0.42, 0.22, 0.03 }, 0.65) end          -- band edge
    -- rivets
    for _, rx in ipairs({ 18.5, 45.5 }) do
      for _, ry in ipairs({ 29, 47, 55 }) do
        local d = ellipse(x, y, rx, ry, 1.3, 1.3)
        if d < 0 then c = mix3({ 1, 0.97, 0.75 }, { 0.55, 0.33, 0.05 }, clamp((y - ry + 1.3) / 2.6)) end
      end
    end
  elseif lidShape(x, y) < 0 then
    c = mix3(LID_TOP_C, LID_BOT_C, clamp((y - LID_TOP) / (LID_SEAM - LID_TOP)))
    -- curved highlight across the lid
    local hl = ellipse(x, y, CX - 4, 23, 15, 4)
    if hl < 0 then c = mix3(c, { 1, 0.80, 0.55 }, 0.30 * clamp(-hl / 2)) end
  else
    c = mix3(WOOD_TOP, WOOD_BOT, clamp((y - LID_SEAM) / (BODY_BOT - LID_SEAM)))
    -- plank seams
    for _, py in ipairs({ 45.5, 52.5 }) do
      if abs(y - py) < 0.7 then c = mix3(c, { 0.18, 0.08, 0.03 }, 0.6) end
    end
    -- shadow under the rim
    if y < LID_SEAM + 5 then c = mix3(c, { 0.15, 0.07, 0.02 }, 0.45 * (1 - (y - LID_SEAM) / 5)) end
  end
  -- inner rim light on the left/top edges, dark on the right
  if dc > -1.2 then
    if x < CX then c = mix3(c, { 1, 0.9, 0.7 }, 0.12) else c = mix3(c, { 0, 0, 0 }, 0.18) end
  end
  return c[1], c[2], c[3], 1
end

local STATES = {
  up        = function(r, g, b) return r, g, b end,
  mouseover = function(r, g, b) return min(1, r*1.22 + 0.04), min(1, g*1.22 + 0.04), min(1, b*1.12 + 0.02) end,
  down      = function(r, g, b) return r*0.55, g*0.50, b*0.45 end,
  disabled  = function(r, g, b) local l = (r*0.3 + g*0.59 + b*0.11) * 0.75 return l, l, l end,
}

local SCALE, CY = 0.86, 40
local function render(state, dy)
  dy = dy or 0
  local big = I.new(W*SS, H*SS)
  local f = STATES[state]
  for Y = 0, H*SS-1 do
    local y = CY + ((Y + 0.5) / SS - dy - CY) / SCALE
    for X = 0, W*SS-1 do
      local x = CX + ((X + 0.5) / SS - CX) / SCALE
      local r, g, b, a = shade(x, y)
      if r then
        r, g, b = f(r, g, b)
        I.set(big, X, Y, r, g, b, a)
      else
        -- soft drop shadow (below the chest)
        local d = min(chestShape(x, y - 2.2), lockPlate(x, y - 2.2)) - 1.6
        local s = clamp(1 - d / 3.5) * 0.55
        if s > 0 then I.set(big, X, Y, 0, 0, 0, s) end
      end
    end
  end
  return I.downsample(big, SS)
end

local out = {}
for _, st in ipairs({ "up", "mouseover", "down", "disabled" }) do out[st] = render(st) end
return out
