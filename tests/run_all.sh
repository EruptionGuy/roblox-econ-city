#!/bin/sh
# chạy hết test. Cần Lua 5.3+ (macOS: brew install lua, Linux: apt install lua5.4 hoặc dùng texlua)
cd "$(dirname "$0")/.." || exit 1
LUA=${LUA:-$(command -v lua5.4 || command -v lua5.3 || command -v lua || command -v texlua)}
if [ -z "$LUA" ]; then echo "Không tìm thấy Lua. Cài bằng: brew install lua"; exit 1; fi
set -e
echo "== Cú pháp";            $LUA tests/syntax_check.lua
echo "== Bộ máy mô phỏng";    $LUA tests/engine_spec.lua
echo "== Logic server";       $LUA tests/server_spec.lua
echo "== Chạy thử toàn game"; $LUA tests/e2e_sim.lua | tail -3
echo "== Cân bằng (bot trên lưới, so với bản JS)"; $LUA tests/balance_sim.lua | tail -4
