-- tiny RGBA image lib (float 0..1 channels, premultiplied=false)
local M = {}
function M.new(w, h) local im = { w = w, h = h, p = {} } for i = 1, w*h*4 do im.p[i] = 0 end return im end
function M.loadblp(path)
  local d = io.open(path, "rb"):read("*a")
  local function u32(o) local a,b,c,e=d:byte(o+1,o+4) return a+b*256+c*65536+e*16777216 end
  local w, h, off = u32(12), u32(16), u32(20)
  local im = M.new(w, h)
  for i = 0, w*h-1 do
    local b,g,r,a = d:byte(off+i*4+1, off+i*4+4)
    im.p[i*4+1], im.p[i*4+2], im.p[i*4+3], im.p[i*4+4] = r/255, g/255, b/255, a/255
  end
  return im
end
function M.get(im, x, y) local i = (y*im.w + x)*4 return im.p[i+1], im.p[i+2], im.p[i+3], im.p[i+4] end
function M.set(im, x, y, r, g, b, a) local i = (y*im.w + x)*4 im.p[i+1], im.p[i+2], im.p[i+3], im.p[i+4] = r, g, b, a end
function M.crop(im, x0, y0, w, h)
  local o = M.new(w, h)
  for y = 0, h-1 do for x = 0, w-1 do M.set(o, x, y, M.get(im, x0+x, y0+y)) end end
  return o
end
-- "over" composite src onto dst at (dx,dy)
function M.over(dst, src, dx, dy, alpha)
  alpha = alpha or 1
  for y = 0, src.h-1 do for x = 0, src.w-1 do
    local X, Y = dx+x, dy+y
    if X >= 0 and Y >= 0 and X < dst.w and Y < dst.h then
      local sr, sg, sb, sa = M.get(src, x, y); sa = sa * alpha
      local dr, dg, db, da = M.get(dst, X, Y)
      local oa = sa + da*(1-sa)
      if oa > 0 then
        M.set(dst, X, Y, (sr*sa + dr*da*(1-sa))/oa, (sg*sa + dg*da*(1-sa))/oa, (sb*sa + db*da*(1-sa))/oa, oa)
      end
    end
  end end
end
function M.add(dst, src, dx, dy, alpha)
  for y = 0, src.h-1 do for x = 0, src.w-1 do
    local X, Y = dx+x, dy+y
    if X >= 0 and Y >= 0 and X < dst.w and Y < dst.h then
      local sr, sg, sb, sa = M.get(src, x, y); local k = sa*(alpha or 1)
      local dr, dg, db, da = M.get(dst, X, Y)
      M.set(dst, X, Y, math.min(1, dr+sr*k), math.min(1, dg+sg*k), math.min(1, db+sb*k), da)
    end
  end end
end
function M.fill(im, r, g, b, a) for y = 0, im.h-1 do for x = 0, im.w-1 do M.set(im, x, y, r, g, b, a) end end end
function M.scale(im, k)  -- nearest
  local o = M.new(im.w*k, im.h*k)
  for y = 0, o.h-1 do for x = 0, o.w-1 do M.set(o, x, y, M.get(im, math.floor(x/k), math.floor(y/k))) end end
  return o
end
function M.downsample(im, k)  -- box filter, premultiplied
  local o = M.new(math.floor(im.w/k), math.floor(im.h/k))
  for y = 0, o.h-1 do for x = 0, o.w-1 do
    local r, g, b, a = 0, 0, 0, 0
    for j = 0, k-1 do for i = 0, k-1 do
      local sr, sg, sb, sa = M.get(im, x*k+i, y*k+j)
      r, g, b, a = r+sr*sa, g+sg*sa, b+sb*sa, a+sa
    end end
    if a > 0 then M.set(o, x, y, r/a, g/a, b/a, a/(k*k)) end
  end end
  return o
end
local function le(n, bytes) local t={} for i=1,bytes do t[i]=string.char(n%256); n=math.floor(n/256) end return table.concat(t) end
local function c8(v) v = math.floor(v*255+0.5) return string.char(v < 0 and 0 or v > 255 and 255 or v) end
function M.savebmp(im, path) -- opaque, top-down BGRA
  local t = {}
  for y = 0, im.h-1 do for x = 0, im.w-1 do local r,g,b,a = M.get(im,x,y) t[#t+1] = c8(b)..c8(g)..c8(r)..c8(a) end end
  local data = table.concat(t)
  local hdr = "BM"..le(54+#data,4)..le(0,4)..le(54,4)..le(40,4)..le(im.w,4)..le(2^32-im.h,4)..le(1,2)..le(32,2)..le(0,4)..le(#data,4)..le(2835,4)..le(2835,4)..le(0,4)..le(0,4)
  local f = io.open(path, "wb") f:write(hdr, data) f:close()
end
function M.savetga(im, path) -- 32-bit uncompressed, top-left origin
  local t = {}
  for y = 0, im.h-1 do for x = 0, im.w-1 do local r,g,b,a = M.get(im,x,y) t[#t+1] = c8(b)..c8(g)..c8(r)..c8(a) end end
  local hdr = string.char(0,0,2, 0,0,0,0,0, 0,0,0,0) .. le(im.w,2) .. le(im.h,2) .. string.char(32, 8 + 32)
  local f = io.open(path, "wb") f:write(hdr, table.concat(t)) f:close()
end
return M
