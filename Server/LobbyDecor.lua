-- LobbyDecor: 로비(마을) 분위기 장식 - 상점 / 광장 / 언덕 / 문 / 길 / 화단 / 벤치 / 울타리 등
-- LobbyService.Build 끝에서 pcall 로 불러온다. 한 번만 만들고 끝 (프레임마다 도는 코드 없음).
-- 규칙: 전부 Anchored + CanCollide / CanQuery / CanTouch = false + CastShadow = false (이동 / 총알 / 상호작용 / 그림자 비용 없음),
--       Folder 로 묶음, 가로등 / 강한 네온 없음, 따뜻하고 차분한 색, 은은한 조명 4개 / 작은 입자 3개 이하.
-- 예산: 부품 MAX_PARTS 이하 (넘으면 뒤쪽 장식부터 생략).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local LobbyDecor = {}

local MAX_PARTS = 640
local MAX_LIGHTS = 4
local MAX_EMITTERS = 3

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- 색 / 재질 상수 (한 번만 만들어 재사용)
local STONE, STONE_DARK, STONE_LIGHT = rgb(150, 142, 130), rgb(116, 110, 104), rgb(184, 174, 156)
local WOOD, WOOD_DARK = rgb(120, 86, 56), rgb(84, 60, 42)
local SOIL = rgb(86, 64, 48)
local CREAM, RED, MUSTARD, SAGE, PLUM, TEAL = rgb(226, 212, 186), rgb(172, 82, 68), rgb(206, 160, 82), rgb(112, 150, 100), rgb(126, 92, 140), rgb(84, 140, 140)
local LEAF = { rgb(96, 142, 88), rgb(120, 156, 92), rgb(84, 126, 86) }
local FLOWERS = { rgb(230, 150, 162), rgb(240, 202, 112), rgb(200, 126, 172), rgb(236, 232, 222), rgb(240, 152, 94) }
local M = Enum.Material

function LobbyDecor.Build(parent, ctx)
	local TOP = ctx.Top
	local HILL_Z, HILL_H = ctx.HillZ, ctx.HillH
	local root = Instance.new("Folder")
	root.Name = "LobbyDecor"
	root.Parent = parent
	local current = root
	local count, lights, emitters = 0, 0, 0

	local function section(name)
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
		current = folder
	end

	local function add(name, size, cf, color, material, shape, transparency)
		if count >= MAX_PARTS then return nil end
		count += 1
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if shape then part.Shape = shape end
		part.Size = size
		part.CFrame = cf
		part.Color = color
		part.Material = material
		if transparency then part.Transparency = transparency end
		part.Parent = current
		return part
	end
	local function box(name, size, pos, color, material, yaw, transparency)
		return add(name, size, CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0), color, material, nil, transparency)
	end
	local function ball(name, d, pos, color, material, sy, sz)
		return add(name, Vector3.new(d, sy or d, sz or d), CFrame.new(pos), color, material, Enum.PartType.Ball)
	end
	-- 세운 원기둥 (base: 바닥 중심)
	local function vcyl(name, h, d, base, color, material)
		return add(name, Vector3.new(h, d, d), CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, material, Enum.PartType.Cylinder)
	end
	local function disc(name, d, thick, center, color, material)
		return vcyl(name, thick, d, center - Vector3.new(0, thick / 2, 0), color, material)
	end
	local function g(x, z, y)
		return Vector3.new(x, TOP + (y or 0), z)
	end
	-- 가게 같은 "앞이 -Z 인" 기준 좌표계 안의 부품
	local function lb(base, name, size, lx, ly, lz, color, material, rx, ry, rz, shape)
		return add(name, size, base * CFrame.new(lx, ly, lz) * CFrame.Angles(rx or 0, ry or 0, rz or 0), color, material, shape)
	end
	local function glow(part, color, range, brightness)
		if not part or lights >= MAX_LIGHTS then return end
		lights += 1
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = part
	end
	local function dust(part, color, rate, size, speed, lifetime)
		if not part or emitters >= MAX_EMITTERS then return end
		emitters += 1
		local e = Instance.new("ParticleEmitter")
		e.Rate = rate
		e.Lifetime = NumberRange.new(lifetime, lifetime * 1.4)
		e.Speed = NumberRange.new(speed * 0.4, speed)
		e.SpreadAngle = Vector2.new(40, 40)
		e.LightEmission = 0.3
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = part
	end
	local function label(part, text, color, offsetY, width, height, maxDistance)
		if not part then return end
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, width * 0.75, 0, height * 0.75)
		gui.StudsOffset = Vector3.new(0, offsetY, 0)
		gui.MaxDistance = maxDistance
		gui.Parent = part
		local text_ = Instance.new("TextLabel")
		text_.Size = UDim2.new(1, 0, 1, 0)
		text_.BackgroundTransparency = 1
		text_.Font = Enum.Font.GothamBlack
		text_.TextScaled = true
		text_.TextColor3 = color
		text_.TextStrokeTransparency = 0
		text_.Text = text
		text_.Parent = gui
	end
	local function anchorPart(name, pos)
		return add(name, Vector3.new(1, 1, 1), CFrame.new(pos), STONE, M.SmoothPlastic, nil, 1)
	end

	-- 자주 쓰는 소품 -------------------------------------------------
	local flowerCounter = 0
	local function nextFlower()
		flowerCounter += 1
		return FLOWERS[flowerCounter % #FLOWERS + 1]
	end
	local function planter(x, z, yaw, y)
		local base = g(x, z, y)
		box("PlanterStone", Vector3.new(4, 1.1, 2.2), base + Vector3.new(0, 0.55, 0), STONE, M.Cobblestone, yaw)
		box("PlanterSoil", Vector3.new(3.4, 0.2, 1.6), base + Vector3.new(0, 1.15, 0), SOIL, M.Ground, yaw)
		local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
		for i = -1, 1 do
			add("Flower", Vector3.new(0.9, 0.9, 0.9), cf * CFrame.new(i * 1.1, 1.55, 0), nextFlower(), M.SmoothPlastic, Enum.PartType.Ball)
		end
	end
	local function tree(x, z, h, y)
		local base = g(x, z, y)
		vcyl("TreeTrunk", h, 1.4, base, rgb(98, 70, 46), M.Wood)
		ball("TreeLeaves", 7 + h * 0.15, base + Vector3.new(0, h + 1.6, 0), LEAF[(flowerCounter + count) % 3 + 1], M.Grass, 5.6 + h * 0.1)
		ball("TreeLeaves", 4.6, base + Vector3.new(1.8, h + 0.4, 0.9), LEAF[(count + 1) % 3 + 1], M.Grass, 3.8)
	end
	local function bush(x, z, d, y)
		ball("Bush", d, g(x, z, (y or 0) + d * 0.3), LEAF[count % 3 + 1], M.Grass, d * 0.75)
	end
	local function bench(x, z, targetX, targetZ, y)
		local base = CFrame.lookAt(g(x, z, y), g(targetX, targetZ, y))
		for _, side in ipairs({ -1, 1 }) do
			lb(base, "BenchLeg", Vector3.new(0.4, 1.3, 1.2), side * 2, 0.65, 0, WOOD_DARK, M.Wood)
		end
		lb(base, "BenchSeat", Vector3.new(4.8, 0.35, 1.5), 0, 1.45, 0, WOOD, M.WoodPlanks)
		lb(base, "BenchBack", Vector3.new(4.8, 1.1, 0.25), 0, 2.15, 0.65, WOOD, M.WoodPlanks)
	end
	local function flag(x, z, h, color, y, facingZ)
		local base = g(x, z, y)
		vcyl("FlagPole", h, 0.3, base, WOOD_DARK, M.Wood)
		box("FlagCloth", Vector3.new(0.1, 2, 3.4), base + Vector3.new(0, h - 1.3, 1.9 * (facingZ or 1)), color, M.Fabric)
		ball("FlagTip", 0.6, base + Vector3.new(0, h + 0.3, 0), MUSTARD, M.Metal)
	end
	local function fenceRun(x1, z1, x2, z2, spacing, height, y)
		local a, b = g(x1, z1, y), g(x2, z2, y)
		local length = (b - a).Magnitude
		local steps = math.max(1, math.floor(length / spacing + 0.5))
		for i = 0, steps do
			vcyl("FencePost", height, 0.5, a:Lerp(b, i / steps), WOOD, M.Wood)
		end
		for _, rail in ipairs({ 0.4, 0.8 }) do
			add("FenceRail", Vector3.new(0.25, 0.3, length), CFrame.lookAt((a + b) / 2 + Vector3.new(0, height * rail, 0), b + Vector3.new(0, height * rail, 0)), WOOD_DARK, M.Wood)
		end
	end
	local function crateStack(x, z, yaw)
		box("Crate", Vector3.new(2.4, 2.4, 2.4), g(x, z, 1.2), WOOD, M.Wood, yaw)
		box("Crate", Vector3.new(1.8, 1.8, 1.8), g(x + 0.3, z, 3.3), WOOD_DARK, M.Wood, yaw + 0.5)
	end
	local function barrel(x, z)
		vcyl("Barrel", 2.6, 2.2, g(x, z), rgb(120, 86, 56), M.Wood)
	end

	--------------------------------------------------------------------
	-- 1) 대장간 / 뽑기 상점 (가게 본체는 LobbyService, 여기선 주변 소품만)
	--------------------------------------------------------------------
	section("Forge")
	do
		local fb = CFrame.lookAt(g(-44, 28), g(-43, 28))
		for _, side in ipairs({ -1, 1 }) do -- 처마 모서리 깃발
			lb(fb, "StallPennantPole", Vector3.new(0.25, 5, 0.25), side * 9.6, 14.6, -7.4, WOOD_DARK, M.Wood)
			lb(fb, "StallPennant", Vector3.new(0.1, 1.6, 3.2), side * 9.6, 16.4, -9, RED, M.Fabric)
		end
		-- 지붕 위 엠블럼: 둥근 판 + 엇갈린 망치와 칼
		lb(fb, "ForgeEmblem", Vector3.new(0.4, 7, 7), 0, 17, 6.6, WOOD_DARK, M.Wood, 0, math.pi / 2, 0, Enum.PartType.Cylinder)
		lb(fb, "ForgeSword", Vector3.new(0.5, 7, 0.15), 0, 17, 6.2, rgb(190, 194, 204), M.Metal, 0, 0, math.rad(-32))
		lb(fb, "ForgeHammerHandle", Vector3.new(0.5, 6, 0.5), 0, 17, 6.2, WOOD, M.Wood, 0, 0, math.rad(32))
		lb(fb, "ForgeHammerHead", Vector3.new(2.6, 1.6, 1.6), -1.6, 19.5, 6.2, rgb(110, 112, 124), M.Metal, 0, 0, math.rad(32))
		-- 오른쪽: 무기 걸이
		for _, lz in ipairs({ -1, 4 }) do
			lb(fb, "RackPost", Vector3.new(0.4, 5, 0.4), 13, 2.5, lz, WOOD_DARK, M.Wood)
		end
		for _, ly in ipairs({ 4.2, 1.8 }) do
			lb(fb, "RackBar", Vector3.new(0.3, 0.3, 5.4), 13, ly, 1.5, WOOD, M.Wood)
		end
		for i = 0, 2 do
			lb(fb, "RackBlade", Vector3.new(0.15, 4.2, 0.4), 13, 3.1, 0.2 + i * 1.3, rgb(196, 200, 210), M.Metal, 0, 0, math.rad(i - 1) * 6)
		end
		lb(fb, "RackShield", Vector3.new(0.3, 2.6, 2.6), 13.6, 1.6, 5.6, RED, M.Wood, 0, 0, 0, Enum.PartType.Cylinder)
		lb(fb, "RackShieldBoss", Vector3.new(0.5, 0.9, 0.9), 13.9, 1.6, 5.6, rgb(190, 170, 110), M.Metal, 0, 0, 0, Enum.PartType.Cylinder)
		-- 왼쪽: 숫돌 / 물통 / 석탄 더미
		for _, lz in ipairs({ 0.2, 3.2 }) do
			lb(fb, "GrindPost", Vector3.new(0.4, 2.4, 0.4), -13, 1.2, lz, WOOD_DARK, M.Wood)
		end
		lb(fb, "GrindStone", Vector3.new(0.7, 2.6, 2.6), -13, 2.4, 1.7, rgb(160, 156, 150), M.Slate, 0, math.pi / 2, 0, Enum.PartType.Cylinder)
		lb(fb, "GrindFoot", Vector3.new(1.4, 0.3, 4.2), -13, 0.15, 1.7, WOOD_DARK, M.Wood)
		lb(fb, "Trough", Vector3.new(3, 1.2, 1.6), -13, 0.6, -4, WOOD, M.Wood)
		lb(fb, "TroughWater", Vector3.new(2.6, 0.1, 1.2), -13, 1.2, -4, rgb(84, 130, 160), M.SmoothPlastic)
		for i = 0, 4 do
			lb(fb, "Coal", Vector3.new(1.1, 0.9, 1.1), -13 + (i % 3) * 0.9, 0.45 + (i > 2 and 0.6 or 0), 6.4 + (i % 2) * 0.8, rgb(42, 40, 44), M.Slate, 0, i, 0, Enum.PartType.Ball)
		end
		-- 카운터 위 쇠막대 / 화로 위 석탄 (작은 불씨)
		for i, ingot in ipairs({ { -6.2, 4.45 }, { -4.6, 4.45 }, { -5.4, 4.9 }, { 4.6, 4.45 }, { 6.2, 4.45 }, { 5.4, 4.9 } }) do
			lb(fb, "Ingot", Vector3.new(1.5, 0.45, 0.8), ingot[1], ingot[2], -6, i > 3 and rgb(196, 160, 84) or rgb(150, 152, 162), M.Metal)
		end
		local coal = lb(fb, "ForgeCoal", Vector3.new(1.1, 1.1, 1.1), 4.8, 5.0, 3.8, rgb(214, 104, 48), M.Neon, 0, 0, 0, Enum.PartType.Ball)
		lb(fb, "ForgeCoal", Vector3.new(0.9, 0.9, 0.9), 6.2, 5.0, 5, rgb(190, 90, 44), M.Neon, 0, 0, 0, Enum.PartType.Ball)
		lb(fb, "ForgeCoal", Vector3.new(0.9, 0.9, 0.9), 5.5, 5.3, 4.4, rgb(214, 104, 48), M.Neon, 0, 0, 0, Enum.PartType.Ball)
		glow(coal, rgb(255, 160, 90), 14, 0.5)
		dust(coal, rgb(255, 190, 110), 5, 0.35, 5, 1)
		-- 앞 보도 돌 무늬
		for row = 0, 1 do
			for i = 0, 4 do
				lb(fb, "StallTile", Vector3.new(3.6, 0.06, 3.4), -8.8 + i * 4.4, 0.42, -10.2 - row * 3.6, (i + row) % 2 == 0 and STONE_LIGHT or STONE, M.Cobblestone)
			end
		end
	end

	section("GachaShop")
	do
		local gb = CFrame.lookAt(g(44, 28), g(43, 28))
		for _, side in ipairs({ -1, 1 }) do
			lb(gb, "StallPennantPole", Vector3.new(0.25, 5, 0.25), side * 9.6, 14.6, -7.4, WOOD_DARK, M.Wood)
			lb(gb, "StallPennant", Vector3.new(0.1, 1.6, 3.2), side * 9.6, 16.4, -9, side < 0 and PLUM or MUSTARD, M.Fabric)
		end
		-- 지붕 위 커다란 캡슐 + 별
		local cap = gb * CFrame.new(0, 17.5, 6.2) * CFrame.Angles(0, 0, math.rad(20))
		add("GachaCapsule", Vector3.new(5.2, 5.2, 5.2), cap * CFrame.new(-1.9, 0, 0), rgb(214, 130, 160), M.SmoothPlastic, Enum.PartType.Ball)
		add("GachaCapsule", Vector3.new(5.2, 5.2, 5.2), cap * CFrame.new(1.9, 0, 0), CREAM, M.SmoothPlastic, Enum.PartType.Ball)
		add("GachaCapsule", Vector3.new(1.9, 5, 5), cap * CFrame.new(-0.95, 0, 0), rgb(214, 130, 160), M.SmoothPlastic, Enum.PartType.Cylinder)
		add("GachaCapsule", Vector3.new(1.9, 5, 5), cap * CFrame.new(0.95, 0, 0), CREAM, M.SmoothPlastic, Enum.PartType.Cylinder)
		for _, side in ipairs({ -1, 1 }) do
			lb(gb, "GachaStar", Vector3.new(1.5, 1.5, 0.3), side * 6.4, 17.6, 6, MUSTARD, M.Metal, 0, 0, math.rad(45))
			lb(gb, "GachaStar", Vector3.new(1.5, 1.5, 0.3), side * 6.4, 17.6, 6, MUSTARD, M.Metal)
		end
		-- 왼쪽: 경품 선반
		for _, lz in ipairs({ 1.5, 5.5 }) do
			lb(gb, "PrizePost", Vector3.new(0.4, 6.4, 0.4), -13, 3.2, lz, WOOD_DARK, M.Wood)
		end
		local prizeColors = { rgb(214, 130, 160), rgb(120, 168, 214), rgb(240, 202, 112), rgb(130, 190, 140), rgb(190, 150, 214), rgb(240, 152, 94) }
		for shelf = 0, 2 do
			local ly = 1.8 + shelf * 1.8
			lb(gb, "PrizeShelf", Vector3.new(1.6, 0.25, 5), -13, ly, 3.5, WOOD, M.WoodPlanks)
			lb(gb, "PrizeItem", Vector3.new(1.1, 1.1, 1.1), -13, ly + 0.7, 2.6, prizeColors[shelf * 2 + 1], M.SmoothPlastic, 0, 0, 0, shelf == 1 and Enum.PartType.Ball or nil)
			lb(gb, "PrizeItem", Vector3.new(1, 1.2, 1), -13, ly + 0.7, 4.4, prizeColors[shelf * 2 + 2], M.SmoothPlastic, 0, 0.5, 0, shelf == 0 and Enum.PartType.Ball or nil)
		end
		-- 오른쪽: 수정구슬
		vcyl("CrystalPedestal", 2.4, 2.4, (gb * CFrame.new(13, 0, 1)).Position, STONE, M.Marble)
		vcyl("CrystalRing", 0.25, 3.2, (gb * CFrame.new(13, 2.4, 1)).Position, MUSTARD, M.Metal)
		lb(gb, "CrystalBall", Vector3.new(3.4, 3.4, 3.4), 13, 4.4, 1, rgb(190, 176, 236), M.Glass, 0, 0, 0, Enum.PartType.Ball).Transparency = 0.35
		local core = lb(gb, "CrystalCore", Vector3.new(1.4, 1.4, 1.4), 13, 4.4, 1, rgb(206, 180, 255), M.Neon, 0, 0, 0, Enum.PartType.Ball)
		glow(core, rgb(210, 180, 255), 12, 0.45)
		dust(core, rgb(226, 206, 255), 4, 0.3, 3, 1.4)
		-- 캡슐 더미
		local capsuleColors = { rgb(214, 130, 160), rgb(120, 168, 214), rgb(240, 202, 112), rgb(130, 190, 140) }
		for i = 0, 7 do
			local layer = i >= 6 and 1 or 0
			lb(gb, "CapsuleBall", Vector3.new(1.3, 1.3, 1.3), 11.8 + (i % 3) * 1.4 - layer * 0.7, 0.65 + layer * 1, -4.2 - math.floor(i / 3) * 1.3 * (1 - layer), capsuleColors[i % 4 + 1], M.SmoothPlastic, 0, 0, 0, Enum.PartType.Ball)
		end
		for row = 0, 1 do
			for i = 0, 4 do
				lb(gb, "StallTile", Vector3.new(3.6, 0.06, 3.4), -8.8 + i * 4.4, 0.42, -10.2 - row * 3.6, (i + row) % 2 == 0 and rgb(190, 176, 200) or rgb(164, 150, 178), M.Cobblestone)
			end
		end
	end

	--------------------------------------------------------------------
	-- 2) 중앙 광장 (분수 + 화단 + 벤치 + 바닥 무늬)
	--------------------------------------------------------------------
	section("Plaza")
	do
		local cx, cz = 0, 70
		local c = g(cx, cz)
		disc("FountainBasin", 23, 1.9, c + Vector3.new(0, 0.95, 0), STONE, M.Cobblestone)
		for i = 0, 13 do
			local a = i / 14 * math.pi * 2
			box("FountainCoping", Vector3.new(5, 0.3, 1.6), c + Vector3.new(math.cos(a) * 10.8, 2.0, math.sin(a) * 10.8), i % 2 == 0 and STONE_LIGHT or STONE, M.Marble, -(a + math.pi / 2))
		end
		for i = 0, 5 do -- 연잎 + 꽃
			local a = i * 1.1
			local r = 3.4 + (i % 3) * 1.3
			local p = c + Vector3.new(math.cos(a) * r, 2.24, math.sin(a) * r)
			vcyl("LilyPad", 0.06, 1.8, p - Vector3.new(0, 0.03, 0), rgb(100, 154, 96), M.Grass)
			if i % 2 == 0 then
				ball("LilyFlower", 0.6, p + Vector3.new(0.3, 0.3, 0), i == 0 and FLOWERS[1] or FLOWERS[4], M.SmoothPlastic)
			end
		end
		for i = 0, 3 do
			local a = math.rad(45 + i * 90)
			planter(cx + math.cos(a) * 17, cz + math.sin(a) * 17, -(a + math.pi / 2), 0.2)
		end
		for i = 0, 19 do -- 바닥 돌 고리
			local a = i / 20 * math.pi * 2
			box("PlazaTile", Vector3.new(5.6, 0.07, 3.2), c + Vector3.new(math.cos(a) * 21.5, 0.3, math.sin(a) * 21.5), i % 2 == 0 and STONE_LIGHT or STONE, M.Cobblestone, -(a + math.pi / 2))
		end
		for _, deg in ipairs({ 35, 145, 215, 325 }) do
			local a = math.rad(deg)
			bench(cx + math.cos(a) * 31, cz + math.sin(a) * 31, cx, cz, 0.2)
		end
		for _, deg in ipairs({ 20, 160, 200, 340 }) do
			local a = math.rad(deg)
			local x, z = cx + math.cos(a) * 37, cz + math.sin(a) * 37
			bush(x, z, 3.6, 0.2)
			for k = 0, 2 do
				ball("Flower", 0.9, g(x + 2.2 + k * 0.8, z + (k % 2) * 1.2, 0.7), nextFlower(), M.SmoothPlastic)
			end
		end
		label(anchorPart("PlazaSignAnchor", g(cx, cz, 11)), "⛲ 마을 광장", rgb(255, 232, 170), 0, 240, 56, 50)
	end

	--------------------------------------------------------------------
	-- 3) 시작 언덕 전망대
	--------------------------------------------------------------------
	section("Hill")
	do
		local hy = HILL_H + 0.25
		local hc = Vector3.new(0, TOP + hy, HILL_Z)
		for deg = 195, 345, 10 do
			if deg ~= 265 and deg ~= 275 then -- 가운데는 비워 둔다 (뛰어내리는 자리)
				local a = math.rad(deg)
				box("HillWall", Vector3.new(3.3, 1.3, 1.0), hc + Vector3.new(math.cos(a) * 17.5, 0.65, math.sin(a) * 17.5), (deg // 10) % 2 == 0 and STONE or STONE_DARK, M.Cobblestone, -(a + math.pi / 2))
			end
		end
		for _, deg in ipairs({ 255, 285 }) do
			local a = math.rad(deg)
			box("HillWallPost", Vector3.new(1, 2.2, 1), hc + Vector3.new(math.cos(a) * 17.5, 1.1, math.sin(a) * 17.5), STONE_LIGHT, M.Marble, -(a + math.pi / 2))
		end
		flag(-12, HILL_Z - 8, 12, RED, hy, 1)
		disc("FlagBase", 2.6, 0.5, hc + Vector3.new(-12, 0.25, -8), STONE, M.Cobblestone)
		flag(12, HILL_Z - 8, 9, MUSTARD, hy, 1)
		-- 망원경 전망대
		box("ScopeStand", Vector3.new(2, 1, 2), hc + Vector3.new(7, 0.5, -13.5), STONE, M.Cobblestone)
		vcyl("ScopePole", 2.4, 0.3, hc + Vector3.new(7, 1, -13.5), rgb(84, 70, 56), M.Metal)
		add("ScopeTube", Vector3.new(0.7, 0.7, 3.2), CFrame.lookAt(hc + Vector3.new(7, 3.6, -13.5), hc + Vector3.new(7, 2.4, -30)), rgb(176, 140, 76), M.Metal)
		add("ScopeLens", Vector3.new(0.9, 0.9, 0.4), CFrame.lookAt(hc + Vector3.new(7, 3.5, -15), hc + Vector3.new(7, 2.4, -30)), rgb(150, 190, 214), M.Glass)
		bench(-9.5, HILL_Z - 12.5, -9.5, HILL_Z - 40, hy)
		bench(9.5, HILL_Z - 12.5, 9.5, HILL_Z - 40, hy)
		tree(-14, HILL_Z + 12.5, 8, hy)
		tree(14, HILL_Z + 12.5, 7, hy)
		for i = 0, 4 do
			local a = math.rad(55 + i * 17.5)
			bush(math.cos(a) * 16, HILL_Z + math.sin(a) * 16, 3 + (i % 2), hy)
		end
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2 + 0.3
			ball("Flower", 0.9, hc + Vector3.new(math.cos(a) * 11.5, 0.6, math.sin(a) * 11.5), nextFlower(), M.SmoothPlastic)
		end
		for i = 0, 7 do -- 언덕 옆면 이끼 / 덩굴
			local a = math.rad(212 + i * 17)
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local pos = Vector3.new(0, TOP, HILL_Z) + out * 20.2 + Vector3.new(0, 6 + (i * 7) % 15, 0)
			add("HillMoss", Vector3.new(3.8, 2.6, 1.2), CFrame.lookAt(pos, pos + out), LEAF[i % 3 + 1], M.Grass, Enum.PartType.Ball)
		end
		for i = 0, 4 do -- 언덕 아래 바위
			local a = math.rad(215 + i * 25)
			ball("HillBoulder", 4, Vector3.new(math.cos(a) * 23, TOP + 1.1, HILL_Z + math.sin(a) * 23), STONE_DARK, M.Slate, 2.6, 3.5)
		end
		label(anchorPart("HillSignAnchor", hc + Vector3.new(0, 8, -12)), "🌄 마을 전망대", rgb(255, 232, 170), 0, 240, 56, 50)
	end

	--------------------------------------------------------------------
	-- 4) 필드 입구: 포장 도로 + 울타리 + 망루 + 깃발 + 안내판
	--------------------------------------------------------------------
	section("FieldGate")
	do
		box("FieldRoad", Vector3.new(53, 0.06, 15), g(92.5, 0, 0.31), rgb(150, 140, 126), M.Cobblestone)
		for i = 0, 7 do
			box("FieldRoadJoint", Vector3.new(0.4, 0.08, 15), g(70 + i * 6.6, 0, 0.33), STONE_DARK, M.Slate)
		end
		for _, side in ipairs({ -1, 1 }) do
			box("FieldCurb", Vector3.new(53, 0.5, 0.8), g(92.5, side * 7.8, 0.3), STONE_LIGHT, M.Cobblestone)
			-- 말뚝 울타리 (길이 깔때기처럼 좁아지는 입구)
			for i = 0, 9 do
				vcyl("PalisadeLog", 6.5 + (i % 2) * 0.6, 1.1, g(100 + i * 2, side * 17), i % 2 == 0 and WOOD or WOOD_DARK, M.Wood)
			end
			box("PalisadeRail", Vector3.new(19, 0.4, 0.4), g(109, side * 17 + side * 0.6, 3), WOOD_DARK, M.Wood)
			-- 입구의 화로 (은은한 불)
			vcyl("RoadBrazierStand", 2.4, 1.2, g(100, side * 10.5), STONE_DARK, M.Slate)
			vcyl("RoadBrazierBowl", 0.8, 2.6, g(100, side * 10.5, 2.4), rgb(70, 66, 70), M.Metal)
			local ember = ball("RoadEmber", 1.2, g(100, side * 10.5, 3.5), rgb(210, 100, 46), M.Neon)
			glow(ember, rgb(255, 170, 100), 14, 0.5)
		end
		-- 탑 위 총안 (성가퀴)
		for _, tz in ipairs({ -24, 24 }) do
			for _, ox in ipairs({ -5, 5 }) do
				for _, oz in ipairs({ -5, 5 }) do
					box("TowerMerlon", Vector3.new(2.6, 2, 2.6), Vector3.new(124 + ox, TOP + 50, tz + oz), STONE_DARK, M.Cobblestone)
				end
			end
		end
		-- 가로보에 걸린 현수막
		for i, z in ipairs({ -15, -6, 6, 15 }) do
			box("FieldBanner", Vector3.new(0.2, 9, 3.6), Vector3.new(119.2, TOP + 31.5, z), i % 2 == 0 and MUSTARD or SAGE, M.Fabric)
		end
		-- 망루 (북쪽 길가)
		do
			local wx, wz = 108, -24
			for _, ox in ipairs({ -1.8, 1.8 }) do
				for _, oz in ipairs({ -1.8, 1.8 }) do
					vcyl("WatchLeg", 9, 0.7, g(wx + ox, wz + oz), WOOD, M.Wood)
				end
			end
			box("WatchFloor", Vector3.new(5.4, 0.4, 5.4), g(wx, wz, 9.2), WOOD, M.WoodPlanks)
			for _, o in ipairs({ { 0, -2.6, 0 }, { 0, 2.6, 0 }, { -2.6, 0, 1 }, { 2.6, 0, 1 } }) do
				box("WatchRail", Vector3.new(o[3] == 1 and 0.2 or 5.4, 1, o[3] == 1 and 5.4 or 0.2), g(wx + o[1], wz + o[2], 10), WOOD_DARK, M.Wood)
			end
			for _, side in ipairs({ -1, 1 }) do
				add("WatchRoof", Vector3.new(6.6, 0.3, 3.8), CFrame.new(g(wx, wz + side * 1.6, 12.8)) * CFrame.Angles(side * math.rad(-28), 0, 0), RED, M.Fabric)
			end
			for _, ox in ipairs({ -0.9, 0.9 }) do
				box("WatchLadder", Vector3.new(0.2, 9, 0.2), g(wx + ox, wz + 2.9, 4.5), WOOD_DARK, M.Wood)
			end
			for k = 1, 3 do
				box("WatchRung", Vector3.new(1.8, 0.15, 0.15), g(wx, wz + 2.9, k * 2.4), WOOD_DARK, M.Wood)
			end
			crateStack(wx + 5.5, wz + 1, 0.4)
			barrel(wx + 5.2, wz + 4)
		end
		-- 안내판: 구역 목록
		do
			local names = Config.Field.ZoneNames
			local lines = {}
			for index, name in ipairs(names) do
				lines[#lines + 1] = index .. " " .. name
			end
			local text = "🏔 사냥 필드 구역\n" .. table.concat(lines, " · ", 1, math.min(4, #lines)) .. "\n" .. table.concat(lines, " · ", math.min(5, #lines), #lines)
			vcyl("ZonePost", 9, 1, g(96, -13.5), WOOD_DARK, M.Wood)
			local board = box("ZoneBoard", Vector3.new(0.4, 5.6, 10), g(96, -13.5, 6.4), rgb(140, 102, 66), M.WoodPlanks)
			box("ZoneBoardCap", Vector3.new(0.9, 0.3, 10.6), g(96, -13.5, 9.4), WOOD_DARK, M.Wood)
			if board then
				local gui = Instance.new("SurfaceGui")
				gui.Face = Enum.NormalId.Left
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 40
				gui.LightInfluence = 0
				gui.Parent = board
				local t = Instance.new("TextLabel")
				t.Size = UDim2.new(1, 0, 1, 0)
				t.BackgroundTransparency = 1
				t.Font = Enum.Font.GothamBold
				t.TextScaled = true
				t.TextColor3 = rgb(255, 244, 214)
				t.TextStrokeTransparency = 0.3
				t.Text = text
				t.Parent = gui
			end
		end
		-- 입구 앞 화단 + 초소 소품 + 떠다니는 먼지
		planter(66, -10.8, 0, 0)
		planter(66, 10.8, 0, 0)
		do
			local fx, fz = 117, 14.5
			box("GuardRackPost", Vector3.new(0.4, 5, 0.4), g(fx, fz - 2, 2.5), WOOD_DARK, M.Wood)
			box("GuardRackPost", Vector3.new(0.4, 5, 0.4), g(fx, fz + 2, 2.5), WOOD_DARK, M.Wood)
			box("GuardRackBar", Vector3.new(0.3, 0.3, 4.4), g(fx, fz, 3.8), WOOD, M.Wood)
			for i = 0, 2 do
				box("GuardSpear", Vector3.new(0.2, 6, 0.2), g(fx - 0.5, fz - 1.2 + i * 1.2, 3), rgb(170, 160, 140), M.Wood)
			end
			barrel(fx + 2.5, fz + 3.5)
			barrel(fx + 2.5, fz - 3.5)
		end
		local mote = add("FieldMotes", Vector3.new(34, 1, 12), CFrame.new(g(98, 0, 8)), STONE, M.SmoothPlastic, nil, 1)
		dust(mote, rgb(255, 226, 170), 3, 0.35, 1.5, 6)
	end

	--------------------------------------------------------------------
	-- 5) 심연 포탈 제단 주변
	--------------------------------------------------------------------
	section("Rift")
	do
		local rc = g(78, 90)
		disc("RiftPlatform", 34, 0.2, rc + Vector3.new(0, 0.1, 0), rgb(60, 52, 76), M.Slate)
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			box("RiftTile", Vector3.new(4.4, 0.08, 2.4), rc + Vector3.new(math.cos(a) * 15.2, 0.3, math.sin(a) * 15.2), i % 2 == 0 and rgb(96, 82, 112) or rgb(80, 68, 98), M.Slate, -(a + math.pi / 2))
		end
		for i = 0, 5 do
			local a = math.rad(30 + i * 60)
			local p = rc + Vector3.new(math.cos(a) * 17.5, 0, math.sin(a) * 17.5)
			box("ObeliskBase", Vector3.new(1.8, 2.2, 1.8), p + Vector3.new(0, 1.1, 0), rgb(70, 62, 86), M.Slate, a)
			box("ObeliskShaft", Vector3.new(1.1, 4.5, 1.1), p + Vector3.new(0, 4.4, 0), rgb(84, 74, 102), M.Slate, a)
			box("ObeliskGem", Vector3.new(0.9, 1.6, 0.9), p + Vector3.new(0, 7.4, 0), rgb(150, 110, 180), M.SmoothPlastic, a + 0.785)
		end
		for i = 0, 7 do -- 광장에서 이어지는 징검돌
			local t = i / 7
			box("RiftStep", Vector3.new(3.2, 0.07, 2.6), g(38 + t * 21, 80 + t * 5.2, 0.3), i % 2 == 0 and STONE_LIGHT or STONE, M.Cobblestone, 0.25)
		end
		flag(66, 82, 8, PLUM, 0, 1)
		flag(66, 98, 8, PLUM, 0, 1)
	end

	--------------------------------------------------------------------
	-- 6) 던전 게이트 구역 입구 아치 + 안내판 + 화단
	--------------------------------------------------------------------
	section("GateArea")
	do
		local az = -84
		for _, side in ipairs({ -1, 1 }) do
			box("ArchBase", Vector3.new(4, 1.2, 4), g(side * 12, az, 0.6), STONE_DARK, M.Cobblestone)
			box("ArchPillar", Vector3.new(3, 13, 3), g(side * 12, az, 7.7), rgb(112, 104, 122), M.Granite)
			box("ArchCap", Vector3.new(4, 1, 4), g(side * 12, az, 14.2), STONE_DARK, M.Cobblestone)
			add("ArchRope", Vector3.new(0.15, 1.8, 0.15), CFrame.new(g(side * 4, az, 11.6)), CREAM, M.Fabric)
		end
		box("ArchBeam", Vector3.new(28, 2, 3.4), g(0, az, 13.4), rgb(112, 104, 122), M.Granite)
		local sign = box("ArchSign", Vector3.new(10, 2.6, 0.5), g(0, az, 10.4), rgb(70, 52, 44), M.Wood)
		label(sign, "⚔ 던전 게이트 구역", rgb(255, 220, 150), 3, 300, 60, 60)
		-- 안내 게시판 (벨 옆)
		for _, ox in ipairs({ -1.6, 1.6 }) do
			box("NoticePost", Vector3.new(0.4, 5, 0.4), g(-20 + ox, -84, 2.5), WOOD_DARK, M.Wood)
		end
		box("NoticeBoard", Vector3.new(4.2, 2.6, 0.3), g(-20, -84, 4), rgb(140, 102, 66), M.WoodPlanks)
		for i = 0, 2 do
			box("NoticePaper", Vector3.new(0.9, 1.1, 0.05), g(-21.2 + i * 1.2, -83.8, 4), CREAM, M.Fabric, 0.05 * i)
		end
		for _, x in ipairs({ -39, -13, 13, 39 }) do
			planter(x, -92, 0, 0)
		end
	end

	--------------------------------------------------------------------
	-- 7) 길가 화단 / 나무 / 사거리
	--------------------------------------------------------------------
	section("Paths")
	do
		for _, z in ipairs({ -72, -52, -32, -14 }) do
			planter(-13.4, z, math.pi / 2, 0)
			planter(13.4, z, math.pi / 2, 0)
		end
		for _, z in ipairs({ -62, -22 }) do
			tree(-19, z, 8, 0)
			tree(19, z, 7, 0)
		end
		for _, spot in ipairs({ { -60, 11 }, { -32, 11 }, { 32, 11 }, { 60, 11 }, { -90, -11 }, { -32, -11 } }) do
			planter(spot[1], spot[2], 0, 0)
		end
		for i = 0, 11 do -- 사거리 돌 고리
			local a = i / 12 * math.pi * 2
			box("CrossTile", Vector3.new(4.6, 0.07, 2.4), g(math.cos(a) * 11.5, math.sin(a) * 11.5, 0.3), i % 2 == 0 and STONE_LIGHT or STONE, M.Cobblestone, -(a + math.pi / 2))
		end
		flag(-13, -13, 9, SAGE, 0, 1)
		flag(13, -13, 9, MUSTARD, 0, 1)
		flag(-13, 13, 9, RED, 0, 1)
	end

	--------------------------------------------------------------------
	-- 8) 작업 광장 / 훈련장 둘레 / 휴식 구역 가는 길 / 작은 장터
	--------------------------------------------------------------------
	section("Workshop")
	do
		for _, sx in ipairs({ -19.5, 19.5 }) do
			planter(sx, 21, 0, 0)
			planter(sx, 35, 0, 0)
		end
		box("WorkshopWalk", Vector3.new(13, 0.06, 8), g(-22, 28, 0.31), rgb(160, 150, 134), M.Cobblestone)
		box("WorkshopWalk", Vector3.new(13, 0.06, 8), g(22, 28, 0.31), rgb(160, 150, 134), M.Cobblestone)
		for _, sx in ipairs({ -22, 22 }) do
			box("HayBale", Vector3.new(2.8, 1.8, 1.8), g(sx, 50, 0.9), rgb(206, 178, 104), M.Fabric, 0.3)
			box("HayBale", Vector3.new(2.8, 1.8, 1.8), g(sx, 8, 0.9), rgb(206, 178, 104), M.Fabric, -0.3)
			box("HayBale", Vector3.new(2.4, 1.6, 1.6), g(sx, 8, 2.6), rgb(196, 168, 96), M.Fabric, 0.4)
			barrel(sx > 0 and sx - 3 or sx + 3, 49)
			flag(sx / 2 - (sx > 0 and 0.5 or -0.5), 48, 8, sx > 0 and RED or TEAL, 0, 1)
		end
		for i = 0, 7 do -- 휴식 구역으로 가는 징검돌
			box("RestStep", Vector3.new(2.8, 0.07, 2.2), g(-37 - i * 3.6, 70 + (i % 2) * 0.9, 0.3), i % 2 == 0 and STONE_LIGHT or STONE, M.Cobblestone, 0.2 * (i % 3))
		end
	end

	section("Market")
	do
		local mx, mz = -70, -14
		local base = CFrame.lookAt(g(mx, mz), g(mx, mz + 5))
		lb(base, "MarketTable", Vector3.new(5, 0.4, 2), 0, 2.4, 0, WOOD, M.WoodPlanks)
		for _, side in ipairs({ -1, 1 }) do
			lb(base, "MarketLeg", Vector3.new(0.4, 2.2, 1.6), side * 2.2, 1.1, 0, WOOD_DARK, M.Wood)
		end
		lb(base, "ParasolPole", Vector3.new(0.3, 6, 0.3), 0, 3, 1.4, WOOD_DARK, M.Wood)
		lb(base, "ParasolTop", Vector3.new(0.3, 8, 8), 0, 6.2, 1.4, RED, M.Fabric, 0, 0, math.pi / 2, Enum.PartType.Cylinder)
		lb(base, "ParasolTop", Vector3.new(0.3, 5, 5), 0, 6.6, 1.4, CREAM, M.Fabric, 0, 0, math.pi / 2, Enum.PartType.Cylinder)
		local goods = { rgb(214, 96, 84), rgb(236, 190, 90), rgb(130, 180, 110), rgb(214, 96, 84) }
		for i = 0, 3 do
			lb(base, "MarketGood", Vector3.new(0.9, 0.9, 0.9), -1.8 + i * 1.2, 3.05, 0, goods[i + 1], M.SmoothPlastic, 0, 0, 0, Enum.PartType.Ball)
		end
		crateStack(mx + 4.5, mz - 1, 0.3)
		barrel(mx - 4.5, mz - 1)
		barrel(mx - 5, mz + 1.5)
		ball("MarketSack", 2, g(mx + 4.5, mz + 2, 0.9), rgb(196, 176, 134), M.Fabric, 1.8)
		label(anchorPart("MarketSignAnchor", g(mx, mz, 9)), "🛒 장터", rgb(255, 232, 170), 0, 160, 50, 40)
	end

	return { Parts = count, Lights = lights, Emitters = emitters }
end

return LobbyDecor
