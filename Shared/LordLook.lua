-- LordLook (ReplicatedStorage 안의 ModuleScript, 이름: LordLook)
-- 최후의 군주 모양: 오프닝(IntroClient)과 실제 결투(DoomScene)가 같이 쓴다. 각진 상자 대신 둥근 갑옷 / 휜 뿔 / 관절이 있는 네 팔 / 뼈대 날개.
--   LordLook.Build(add) -> { Body, Eyes = { 왼쪽 눈, 오른쪽 눈 }, Core }
--   add(size, rel, color, material, transparency, shape) -> 부품 (size / rel 위치는 군주 크기 S 의 배수. 호출하는 쪽이 S 를 곱한다)
-- 몸(Body)이 맞는 부분이고 나머지는 장식이다. 이름 "Crown" / "Cape" / "Halo" / "HaloOuter" 는 결투 3단계에서 색이 바뀐다 (DoomScene).

local LordLook = {}

local function V(x, y, z) return Vector3.new(x, y, z) end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local BALL, CYL = Enum.PartType.Ball, Enum.PartType.Cylinder
local METAL, NEON, PLASTIC, FABRIC = Enum.Material.Metal, Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.Fabric

function LordLook.Build(add)
	local dark, plate, steel, red = rgb(26, 12, 22), rgb(42, 28, 50), rgb(66, 58, 78), rgb(255, 50, 60)
	local bone, gold, cloak, ember = rgb(232, 222, 206), rgb(160, 124, 64), rgb(70, 14, 26), rgb(255, 150, 60)

	-- 두 점 사이를 잇는 원기둥 (팔다리 / 뿔 / 뼈)
	local function seg(a, b, r, color, material, transparency)
		local dir = b - a
		local len = dir.Magnitude
		if len < 0.001 then return nil end
		local x = dir.Unit
		local up = (math.abs(x.Y) > 0.95) and V(0, 0, 1) or V(0, 1, 0)
		local z = x:Cross(up).Unit
		local y = z:Cross(x)
		return add(V(len, r * 2, r * 2), CFrame.fromMatrix((a + b) * 0.5, x, y, z), color, material or METAL, transparency, CYL)
	end
	local function ball(p, sx, sy, sz, color, material, transparency)
		return add(V(sx, sy, sz), CFrame.new(p), color, material or METAL, transparency, BALL)
	end
	-- 관절이 둥근 사슬: 점 목록을 따라 반지름이 변한다
	local function chain(points, radii, color, material)
		for i = 1, #points - 1 do
			seg(points[i], points[i + 1], (radii[i] + radii[i + 1]) / 2, color, material)
			ball(points[i + 1], radii[i + 1] * 2, radii[i + 1] * 2, radii[i + 1] * 2, color, material)
		end
	end

	-- 몸통: 둥근 몸 + 가슴 장갑 두 쪽 + 복부 마디 + 골반
	local body = add(V(12, 20, 7), CFrame.new(0, 0, 0), dark, METAL, 0, BALL)
	body.Name = "Body"
	for _, side in ipairs({ -1, 1 }) do
		ball(V(side * 3.7, 5.2, -1.4), 6.6, 8.2, 6.4, plate, METAL)             -- 가슴 장갑
		ball(V(side * 4.3, 9.2, -0.6), 4.6, 2.4, 5, steel, METAL)               -- 쇄골 판
		ball(V(side * 4, -13.5, -1.2), 5.2, 6.4, 4.8, plate, METAL)             -- 엉덩이 장갑
	end
	for k = 0, 2 do ball(V(0, -2 - k * 3.8, -1.2), 9 - k * 1.2, 4.4, 5.4 - k * 0.3, steel, METAL) end -- 복부 마디
	ball(V(0, -14, 0), 9, 6, 6, dark, METAL)                                    -- 골반
	for k = 0, 4 do ball(V(0, 10 - k * 4.4, 3.6), 2.2, 2.4, 2.4, steel, METAL) end -- 등뼈 마디
	-- 가슴 코어 + 갈비 장갑 (코어를 둘러싼 휜 뼈 세 쌍)
	local core = ball(V(0, 4.2, -4.6), 5.4, 5.4, 5.4, red, NEON)
	ball(V(0, 4.2, -4.6), 8, 8, 8, red, NEON, 0.7)
	for k = 0, 2 do
		local y = 8.4 - k * 2.9
		for _, side in ipairs({ -1, 1 }) do
			chain({ V(side * 5.6, y, -0.6), V(side * 4.2, y - 0.2, -3.2), V(side * 1.6, y - 0.9, -4.7) }, { 0.7, 0.55, 0.45 }, bone, PLASTIC)
		end
	end

	-- 머리: 둥근 투구 + 턱 + 눈 + 이마 보석 + 휜 뿔 두 쌍 + 왕관
	ball(V(0, 14, 0), 7, 7.4, 7, rgb(20, 10, 18), METAL)
	ball(V(0, 11.8, -1.4), 5.6, 3.4, 5, plate, METAL)                           -- 턱
	local eyes = {}
	for _, side in ipairs({ -1, 1 }) do
		eyes[#eyes + 1] = add(V(3, 0.9, 0.6), CFrame.new(side * 1.7, 14.6, -3.5) * CFrame.Angles(0, 0, math.rad(side * 18)), rgb(255, 230, 90), NEON)
		for k = -1, 1 do ball(V(side * 0.9 + k * 0.7, 11.5, -3.6), 0.5, 1.4, 0.5, bone, PLASTIC) end -- 송곳니
		chain({ V(side * 3.1, 16.8, 0.2), V(side * 5.8, 19.8, 0.6), V(side * 7.2, 24.6, 1.2), V(side * 5.8, 30, 2.2) }, { 1.7, 1.4, 1.1, 0.35 }, bone, PLASTIC) -- 큰 뿔
		chain({ V(side * 3.8, 13.2, 1), V(side * 7.4, 14.6, 2.2), V(side * 9.4, 18.4, 3) }, { 1.1, 0.8, 0.3 }, bone, PLASTIC) -- 작은 뿔
	end
	ball(V(0, 16.2, -3.3), 1.4, 1.8, 1, red, NEON)                              -- 이마 보석
	local crown = add(V(1.2, 8, 8), CFrame.new(0, 17.8, 0) * CFrame.Angles(0, 0, math.rad(90)), gold, METAL, 0, CYL)
	crown.Name = "Crown"
	for k = 0, 9 do
		local angle = k / 10 * math.pi * 2
		local tall = 3 + (k % 2) * 1.8
		seg(V(math.cos(angle) * 3.6, 18.2, math.sin(angle) * 3.6), V(math.cos(angle) * 3.9, 18.2 + tall, math.sin(angle) * 3.9), 0.38, gold, METAL)
	end

	-- 어깨 + 팔 둘 (위쪽: 거대한 주먹 / 아래쪽: 작고 앞으로 뻗은 팔)
	for _, side in ipairs({ -1, 1 }) do
		ball(V(side * 9.8, 9, 0), 8.6, 6, 8.6, steel, METAL)                    -- 어깨 갑옷
		for k = 0, 2 do                                                         -- 어깨 가시 (붉은 빛)
			seg(V(side * (7.6 + k * 2.4), 11.2 + k * 0.7, 0), V(side * (9.6 + k * 3.7), 17 + k * 3.4, 0.4), 0.55, red, NEON)
		end
		seg(V(side * 11.6, 11.4, 0.3), V(side * 13.8, 21.5, 0.6), 0.8, bone, PLASTIC) -- 어깨 뼈 가시
		-- 위쪽 팔: 윗팔 -> 팔꿈치 -> 아래팔 -> 손목 -> 주먹 + 손톱
		chain({ V(side * 10.6, 7, 0), V(side * 13.4, -1.6, -1.2), V(side * 13, -8.6, -2.8) }, { 2.3, 2.1, 1.8 }, dark, METAL)
		seg(V(side * 13.6, -1.2, -1.4), V(side * 15.6, 1.4, -1.4), 0.6, bone, PLASTIC)  -- 팔꿈치 가시
		add(V(1, 5.4, 5.4), CFrame.new(side * 13, -9.2, -2.8) * CFrame.Angles(0, 0, math.rad(90)), red, NEON, 0, CYL)  -- 손목 불꽃 고리
		ball(V(side * 13, -13, -3.4), 8, 7.6, 8, steel, METAL)                  -- 거대한 주먹
		for k = -1, 1 do seg(V(side * 13 + k * 2.4, -15.6, -6.4), V(side * 13 + k * 2.8, -19.6, -8.2), 0.5, gold, METAL) end -- 손톱
		for k = 0, 3 do ball(V(side * 13 + (k - 1.5) * 1.9, -10.6, -6.6), 1.5, 1.5, 1.5, plate, METAL) end                  -- 주먹 마디
		-- 아래쪽 작은 팔
		chain({ V(side * 6.6, 2, -3), V(side * 10.2, -3.4, -6.4), V(side * 9, -8.6, -9.6) }, { 1.5, 1.3, 1.1 }, plate, METAL)
		ball(V(side * 8.8, -10.2, -10.4), 4.4, 4.4, 4.4, steel, METAL)
		for k = -1, 1 do seg(V(side * 8.8 + k * 1.2, -11.8, -11.8), V(side * 9 + k * 1.5, -15, -12.8), 0.32, gold, METAL) end
	end

	-- 날개: 어깨에서 뻗은 두 마디 뼈 + 아래로 부채처럼 펼쳐진 칼날 막 (붉은 빛줄)
	for _, side in ipairs({ -1, 1 }) do
		local root, elbow, wrist = V(side * 5, 10, 4.6), V(side * 15, 19.5, 8), V(side * 27, 16, 11.5)
		chain({ root, elbow, wrist }, { 1.1, 0.95, 0.75 }, bone, PLASTIC)
		local tips = { V(side * 35, 4, 12), V(side * 31, -7, 11), V(side * 24, -14, 9.5), V(side * 15, -17, 7.5) }
		for k, tip in ipairs(tips) do
			seg(wrist, tip, 0.5, bone, PLASTIC)                                  -- 날개 뼈 (손가락)
			local mid = (wrist + tip) * 0.5
			local dir = (tip - wrist).Unit
			local len = (tip - wrist).Magnitude
			local x = dir
			local z = x:Cross(V(0, 0, 1)).Unit
			local y = z:Cross(x)
			add(V(len, 0.35, 5 - k * 0.5), CFrame.fromMatrix(mid + V(0, 0, -0.6), x, y, z), rgb(90, 20, 40), METAL)       -- 칼날 막
			add(V(len * 0.96, 0.2, 0.7), CFrame.fromMatrix(mid + V(0, 0, -1), x, y, z), red, NEON, 0.15)                   -- 붉은 빛줄
		end
		seg(root, V(side * 8, -9, 7.2), 0.5, bone, PLASTIC)                      -- 몸에 닿는 뼈
	end

	-- 찢어진 망토 세 갈래 + 허리 갑옷 판
	for k = -1, 1 do
		add(V(5.5, 26 - math.abs(k) * 4, 0.5), CFrame.new(k * 5, -4 - math.abs(k) * 2, 5.8) * CFrame.Angles(math.rad(12), 0, math.rad(k * 8)), cloak, FABRIC).Name = "Cape"
		add(V(2.6, 5, 0.5), CFrame.new(k * 5.2, -18 - math.abs(k) * 1.6, 6.8) * CFrame.Angles(math.rad(16), 0, math.rad(k * 14)), cloak, FABRIC).Name = "Cape"
	end
	for k = -1, 1 do
		add(V(3.6, 6, 0.8), CFrame.new(k * 3.6, -14, -3.4) * CFrame.Angles(math.rad(-10), 0, math.rad(k * -6)), steel, METAL)
	end

	-- 머리 뒤 후광 (고리 두 겹)
	add(V(0.7, 30, 30), CFrame.new(0, 15, 8) * CFrame.Angles(0, math.rad(90), 0), red, NEON, 0.25, CYL).Name = "Halo"
	add(V(0.5, 38, 38), CFrame.new(0, 15, 9) * CFrame.Angles(0, math.rad(90), 0), ember, NEON, 0.5, CYL).Name = "HaloOuter"

	return { Body = body, Eyes = eyes, Core = core }
end

return LordLook
