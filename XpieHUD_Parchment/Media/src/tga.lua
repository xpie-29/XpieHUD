-- Alpha-shape TGA writer for the masks (RGB = A, so a MaskTexture works
-- whichever channel the client samples). RLE (type 10) keeps them small.
-- Dev-time only (masks.lua); not loaded by WoW.
local M = {}
local function c8(v) v = math.floor(v * 255 + 0.5) return v < 0 and 0 or v > 255 and 255 or v end
function M.resample(a, w, h, W, H)
  local o = {}
  for y = 0, H - 1 do
    local fy = (y + 0.5) * h / H - 0.5; local y0 = math.max(0, math.min(h - 1, math.floor(fy))); local y1 = math.min(h - 1, y0 + 1); local ty = math.max(0, math.min(1, fy - y0))
    for x = 0, W - 1 do
      local fx = (x + 0.5) * w / W - 0.5; local x0 = math.max(0, math.min(w - 1, math.floor(fx))); local x1 = math.min(w - 1, x0 + 1); local tx = math.max(0, math.min(1, fx - x0))
      local v = (a[y0 * w + x0] * (1 - tx) + a[y0 * w + x1] * tx) * (1 - ty) + (a[y1 * w + x0] * (1 - tx) + a[y1 * w + x1] * tx) * ty
      o[y * W + x] = v
    end
  end
  return o
end
local function le16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
function M.save(a, W, H, path, rle)
  local out = { string.char(0, 0, rle and 10 or 2, 0, 0, 0, 0, 0, 0, 0, 0, 0) .. le16(W) .. le16(H) .. string.char(32, 8 + 32) }
  for y = 0, H - 1 do
    local row = {}
    for x = 0, W - 1 do local v = c8(a[y * W + x]) row[x + 1] = string.char(v, v, v, v) end
    if not rle then out[#out + 1] = table.concat(row)
    else
      local x = 1
      while x <= W do
        local run = 1
        while x + run <= W and run < 128 and row[x + run] == row[x] do run = run + 1 end
        if run > 1 then out[#out + 1] = string.char(0x80 + run - 1) .. row[x]; x = x + run
        else
          local s = x
          while x <= W and x - s < 128 and not (x + 1 <= W and row[x + 1] == row[x]) do x = x + 1 end
          if x == s then x = x + 1 end
          out[#out + 1] = string.char(x - s - 1) .. table.concat(row, "", s, x - 1)
        end
      end
    end
  end
  local f = assert(io.open(path, "wb")) f:write(table.concat(out)) f:close()
end
return M
