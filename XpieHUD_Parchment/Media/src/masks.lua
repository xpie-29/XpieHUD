-- Builds the torn-edge masks for Blizzard's quest parchments (not loaded by WoW).
--
-- Blizzard's QuestBG art is opaque: its torn edges are painted onto a dark
-- backing meant to sit inside the quest frame. For each theme this flood-fills
-- that backing in from the border, feathers the edge, and writes two 512x512
-- RLE TGAs into ../masks (outline only; no Blizzard pixels):
--   <atlas>_mask.tga    alpha = the parchment's shape  (MaskTexture on the art)
--   <atlas>_shadow.tga  the shape padded by SHADOW_PAD art px and blurred
--
-- Inputs: the atlas files as <fileID>.blp in a folder, e.g. from
--   curl -L -o 3813080.blp "https://wago.tools/api/casc/3813080?download"
-- Usage (from this folder):  luajit masks.lua <folder with the .blp files>
-- Atlas coordinates: UiTextureAtlasMember (wago.tools/db2), 12.1.5.

local BLP = dofile("blp.lua")
local TGA = dofile("tga.lua")

local SHADOW_PAD = 12     -- art px; the addon pads the shadow texture by the same
local SIZE = 512
local THEMES = {          -- atlas (lowercase), fileID, x, y (299x407 each)
    { "questbg-parchment", 3813080, 1, 1 },
    { "questbg-horde",     1412268, 1, 410 },
    { "questbg-alliance",  1412268, 1, 1 },
}
local W, H = 299, 407
local TOLERANCE = 0.075   -- how far from the backing's brightness still counts as backing

local function lum(r, g, b) return r * 0.299 + g * 0.587 + b * 0.114 end

local function boxblur(a, w, h, r)
    local function pass(src, horiz)
        local out = {}
        for y = 0, h - 1 do for x = 0, w - 1 do
            local s = 0
            for k = -r, r do
                local xx, yy = horiz and x + k or x, horiz and y or y + k
                if xx >= 0 and yy >= 0 and xx < w and yy < h then s = s + src[yy * w + xx] end
            end
            out[y * w + x] = s / (2 * r + 1)
        end end
        return out
    end
    return pass(pass(a, true), false)
end

local function build(dir, atlas, fileID, x0, y0)
    local img = BLP.load(dir .. "/" .. fileID .. ".blp")
    local function L(x, y) return lum(img.get(x0 + x, y0 + y)) end
    -- the backing: the darkest corner
    local back = math.min(L(0, 0), L(W - 1, 0), L(0, H - 1), L(W - 1, H - 1))
    local outside, stack = {}, {}
    local function push(x, y)
        if x < 0 or y < 0 or x >= W or y >= H then return end
        local i = y * W + x
        if outside[i] or math.abs(L(x, y) - back) > TOLERANCE then return end
        outside[i] = true; stack[#stack + 1] = i
    end
    for x = 0, W - 1 do push(x, 0); push(x, H - 1) end
    for y = 0, H - 1 do push(0, y); push(W - 1, y) end
    while #stack > 0 do
        local i = table.remove(stack); local x, y = i % W, math.floor(i / W)
        push(x + 1, y); push(x - 1, y); push(x, y + 1); push(x, y - 1)
    end
    local a = {}
    for i = 0, W * H - 1 do a[i] = outside[i] and 0 or 1 end
    a = boxblur(a, W, H, 1)
    TGA.save(TGA.resample(a, W, H, SIZE, SIZE), SIZE, SIZE, "../masks/" .. atlas .. "_mask.tga", true)

    local P = SHADOW_PAD; local sw, sh = W + 2 * P, H + 2 * P
    local s = {}
    for y = 0, sh - 1 do for x = 0, sw - 1 do
        local sx, sy = x - P, y - P
        s[y * sw + x] = (sx >= 0 and sy >= 0 and sx < W and sy < H) and a[sy * W + sx] or 0
    end end
    s = boxblur(boxblur(s, sw, sh, 3), sw, sh, 3)
    for i = 0, sw * sh - 1 do s[i] = math.min(1, s[i] * 1.6) end
    TGA.save(TGA.resample(s, sw, sh, SIZE, SIZE), SIZE, SIZE, "../masks/" .. atlas .. "_shadow.tga", true)
    print(atlas, string.format("backing %.3f", back))
end

local dir = assert(arg[1], "usage: luajit masks.lua <folder with <fileID>.blp files>")
for _, t in ipairs(THEMES) do build(dir, t[1], t[2], t[3], t[4]) end
