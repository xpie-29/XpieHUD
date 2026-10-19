-- Minimal BLP2 reader (mip 0): uncompressed BGRA and DXT1/3/5. Dev-time only
-- (masks.lua); not loaded by WoW. Returns { w, h, get(x, y) -> r, g, b, a }.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local function c565(v) return band(rshift(v, 11), 31) / 31, band(rshift(v, 5), 63) / 63, band(v, 31) / 31 end

local function load(path)
    local d = assert(io.open(path, "rb")):read("*a")
    assert(d:sub(1, 4) == "BLP2", path .. ": not a BLP2 file")
    local function u32(o) local a, b, c, e = d:byte(o + 1, o + 4) return a + b * 256 + c * 65536 + e * 16777216 end
    local w, h, off = u32(12), u32(16), u32(20)
    local px = {}   -- [i*4+1..4] = r, g, b, a (0..1)
    if d:byte(9) == 3 then
        for i = 0, w * h - 1 do
            local b, g, r, a = d:byte(off + i * 4 + 1, off + i * 4 + 4)
            px[i * 4 + 1], px[i * 4 + 2], px[i * 4 + 3], px[i * 4 + 4] = r / 255, g / 255, b / 255, a / 255
        end
    else
        local atype, p = d:byte(11), off
        for by = 0, h / 4 - 1 do for bx = 0, w / 4 - 1 do
            local alpha = {}
            if atype == 7 then          -- DXT5
                local a0, a1 = d:byte(p + 1), d:byte(p + 2)
                local pal = { a0, a1 }
                if a0 > a1 then for i = 1, 6 do pal[i + 2] = ((7 - i) * a0 + i * a1) / 7 end
                else for i = 1, 4 do pal[i + 2] = ((5 - i) * a0 + i * a1) / 5 end pal[7], pal[8] = 0, 255 end
                local bits = 0
                for i = 0, 5 do bits = bits + d:byte(p + 3 + i) * 2 ^ (8 * i) end
                for i = 0, 15 do alpha[i] = pal[math.floor(bits / 2 ^ (3 * i)) % 8 + 1] / 255 end
                p = p + 8
            elseif atype == 1 then      -- DXT3
                for i = 0, 15 do local b = d:byte(p + 1 + math.floor(i / 2)); alpha[i] = ((i % 2 == 0) and b % 16 or math.floor(b / 16)) / 15 end
                p = p + 8
            end
            local c0 = d:byte(p + 1) + d:byte(p + 2) * 256
            local c1 = d:byte(p + 3) + d:byte(p + 4) * 256
            local r0, g0, b0 = c565(c0); local r1, g1, b1 = c565(c1)
            local cols = { { r0, g0, b0, 1 }, { r1, g1, b1, 1 } }
            if c0 > c1 or atype ~= 0 then
                cols[3] = { (2 * r0 + r1) / 3, (2 * g0 + g1) / 3, (2 * b0 + b1) / 3, 1 }
                cols[4] = { (r0 + 2 * r1) / 3, (g0 + 2 * g1) / 3, (b0 + 2 * b1) / 3, 1 }
            else
                cols[3] = { (r0 + r1) / 2, (g0 + g1) / 2, (b0 + b1) / 2, 1 }; cols[4] = { 0, 0, 0, 0 }
            end
            local idx = d:byte(p + 5) + d:byte(p + 6) * 256 + d:byte(p + 7) * 65536 + d:byte(p + 8) * 16777216
            for i = 0, 15 do
                local c = cols[math.floor(idx / 4 ^ i) % 4 + 1]
                local x, y = bx * 4 + i % 4, by * 4 + math.floor(i / 4)
                local j = (y * w + x) * 4
                px[j + 1], px[j + 2], px[j + 3], px[j + 4] = c[1], c[2], c[3], alpha[i] or c[4]
            end
            p = p + 8
        end end
    end
    return { w = w, h = h, get = function(x, y) local j = (y * w + x) * 4 return px[j + 1], px[j + 2], px[j + 3], px[j + 4] end }
end

return { load = load }
