-- Hình học lưới 12x12, server (spawn) và client (vẽ, chọn ô) dùng chung.
-- ô i: cột (i-1) % 12 + 1, hàng floor((i-1)/12) + 1. Hàng 12 nằm phía +Z (gần camera), cổng ở hàng này

local Config = require(script.Parent.Config)

local N = Config.GRID_SIZE

local CityLayout = {}

CityLayout.ORIGIN = { x = 0, y = 0, z = 0 } -- tâm thành phố (mặt đất y = 0)
CityLayout.CELL = 14 -- cạnh ô, stud
CityLayout.HALF_EXTENT = CityLayout.CELL * N / 2 -- 84

function CityLayout.cellXY(i)
	return (i - 1) % N + 1, math.floor((i - 1) / N) + 1
end

function CityLayout.cellCenter(i)
	local col, row = CityLayout.cellXY(i)
	return CityLayout.ORIGIN.x + (col - (N + 1) / 2) * CityLayout.CELL, CityLayout.ORIGIN.z + (row - (N + 1) / 2) * CityLayout.CELL
end

-- ô chứa điểm (x, z) trên mặt đất, ngoài lưới thì nil
function CityLayout.cellAt(x, z)
	local col = math.floor((x - CityLayout.ORIGIN.x + CityLayout.HALF_EXTENT) / CityLayout.CELL) + 1
	local row = math.floor((z - CityLayout.ORIGIN.z + CityLayout.HALF_EXTENT) / CityLayout.CELL) + 1
	if col < 1 or col > N or row < 1 or row > N then
		return nil
	end
	return (row - 1) * N + col
end

-- spawn trên đường dẫn vào cổng, ngay ngoài mép lưới
CityLayout.SPAWN = { x = (CityLayout.cellCenter(Config.GATE_INDEX)), y = 0, z = CityLayout.HALF_EXTENT + 20 }

return CityLayout
