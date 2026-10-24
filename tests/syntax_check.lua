-- check cú pháp mọi file .luau bằng Lua 5.3 (code chỉ dùng tập con chung Lua/Luau)
local failed = 0
local count = 0
local p = io.popen('find src -name "*.luau" | sort')
for file in p:lines() do
	count = count + 1
	local f = assert(io.open(file))
	local src = f:read("a")
	f:close()
	local fn, err = load(src, "@" .. file, "t")
	if not fn then
		failed = failed + 1
		print("✗ " .. err)
	end
	-- cấm cú pháp chỉ Lua 5.3 có, Luau không nhận: goto, //, toán tử bit
	local stripped = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""')
	for _, bad in ipairs({ "goto%s", "[^%-]//[^/]", "[^~]~[^=]", "<<", ">>" }) do
		if stripped:find(bad) then
			failed = failed + 1
			print("✗ " .. file .. ": cú pháp không hợp lệ trong Luau: " .. bad)
		end
	end
end
p:close()
print(string.format("%d file, %d lỗi", count, failed))
os.exit(failed == 0 and 0 or 1)
