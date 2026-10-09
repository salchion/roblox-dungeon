-- FieldService (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldService)
-- 로비 동쪽으로 길게 이어진 직선 사냥 필드. 모든 플레이어가 함께 쓰는 열린 공간이다.
--   * 8개 구역(초원 -> 숲 -> 황무지 -> 사막 -> 설원 -> 화산 -> 암흑 지대 -> 심연), 동쪽으로 갈수록 몬스터가 강해짐
--   * 구역 하나하나가 아주 넓다 (Config.Field.ZoneLength x Width). 구역마다 일반 몬스터 + 엘리트(★) 여러 마리
--   * 몬스터가 장비 아이템을 떨어뜨린다 (개인 전리품, LootService). 구역이 깊을수록 높은 등급
--   * 구역마다 입구에 캠프: 안전지대 + 워프 + 죽었을 때 부활 지점
--   * 공개 이벤트: 일정 시간마다 침공 보스가 나타나고, 같이 싸운 사람은 전리품을 받는다
--   * 맨 끝에 필드 보스 (처치하면 주변 플레이어에게 티켓 + 전리품)
--   * 어디까지 갔는지(MaxZone)가 머리 위 이름표에 남아 강함을 과시할 수 있다
-- 플레이어의 Zone Attribute 는 x좌표로 "Lobby" / "Field" 가 자동 전환된다 (던전 안에 있는 사람은 건드리지 않음).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Effects = require(script.Parent:WaitForChild("Effects"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))
local Meta = require(script.Parent:WaitForChild("MetaService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Level = require(script.Parent:WaitForChild("LevelService"))
local MonsterTypes = require(script.Parent:WaitForChild("MonsterTypes"))
local Combo = require(script.Parent:WaitForChild("ComboService"))
local Loot = require(script.Parent:WaitForChild("LootService"))
local Inventory = require(script.Parent:WaitForChild("InventoryService"))

local F = Config.Field
local TOP = 0.05

local Field = {}

local monsters = {}      -- [Part] = 몬스터 데이터
local baffleXs = {}      -- 시선을 막는 "꺾임 벽"의 x 위치 (몬스터가 벽 속에 나타나지 않게 피하는 용도)
local baffleRects = {}   -- 꺾임 벽이 차지한 사각형 { X0, X1, Z0, Z1 } (몬스터 / 탄 / 사격이 벽을 통과하지 못하게 하는 용도)

-- 걸을 수 있는 곳인가 (꺾임 벽 안쪽이 아닌 곳)
local function walkableAt(x, z, pad)
	pad = pad or 0 -- 덩치가 큰 몬스터(보스)는 몸 반지름만큼 벽에서 떨어져 있어야 한다
	for _, rect in ipairs(baffleRects) do
		if x >= rect.X0 - 1.5 - pad and x <= rect.X1 + 1.5 + pad and z >= rect.Z0 - pad and z <= rect.Z1 + pad then
			return false
		end
	end
	return true
end

-- a -> b 선분이 벽에 막히는가. 막히지 않으면 true, 막히면 false 와 마지막으로 열려 있던 지점
local function segmentClear(a, b)
	local delta = b - a
	local steps = math.ceil(delta.Magnitude / 4)
	local lastOpen = a
	for i = 1, steps do
		local p = a + delta * (i / steps)
		if not walkableAt(p.X, p.Z) then
			return false, lastOpen
		end
		lastOpen = p
	end
	return true, b
end

-- x 범위 안에서 꺾임 벽 위가 아닌 곳을 무작위로 고른다
local function freeX(minX, maxX)
	for _ = 1, 12 do
		local x = math.random(minX, maxX)
		local blocked = false
		for _, wallX in ipairs(baffleXs) do
			if math.abs(x - wallX) < 18 then
				blocked = true
				break
			end
		end
		if not blocked then
			return x
		end
	end
	return math.random(minX, maxX)
end
local projectiles = {}
local worldFolder, monstersFolder
local campCFrames = {}      -- [zone] = 캠프 부활/워프 위치
local lobbySpawn = CFrame.new(0, 33, 112)
local activeEvent = nil     -- { Part, Data }

------------------------------------------------------------
-- 유틸
------------------------------------------------------------
local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function getAliveParts(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil
end

-- 각 구역 입구의 캠프 주변 / 로비 쪽은 안전지대: 몬스터가 노리지 않고 탄도 맞지 않는다
local function isSafe(position)
	local relative = position.X - F.StartX
	if relative < 0 then return true end
	return relative % F.ZoneLength < F.CampSafe
end

local function nearestFieldPlayer(position)
	local nearest, nearestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" then
			local root = getAliveParts(player)
			if root and not isSafe(root.Position) then
				local dist = (root.Position - position).Magnitude
				if dist < nearestDist then
					nearest, nearestDist = root, dist
				end
			end
		end
	end
	return nearest, nearestDist
end

local function zoneBounds(zone)
	local x0 = F.StartX + (zone - 1) * F.ZoneLength
	return x0, x0 + F.ZoneLength
end

local function zoneOfX(x)
	return math.clamp(math.floor((x - F.StartX) / F.ZoneLength) + 1, 1, F.ZoneCount)
end

-- 관문을 열지 않은 구역의 몬스터는 관문 너머에서 때릴 수 없다 (자동공격 / 스킬로 벽 너머를 잡는 것 방지)
local function canHitZone(player, x)
	local allowed = math.min(F.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1)
	return zoneOfX(x) <= allowed
end

-- 구역마다 넓은 계단으로 층을 올라갔다 내려온다 (구역 입구 / 캠프는 항상 0층). 계단은 맵 폭 전체라 좁은 길이 없다.
-- 계단 대신 완만한 "경사로": 작은 단차를 오르내릴 때 캐릭터가 위로 튕겨 나가는 문제를 없앴다 (경사가 약 14~22도라서 부드럽게 걷는다)
-- 세 번 연달아 올라 정상(+48)까지 간 뒤, 긴 내리막으로 다시 내려온다 (계속 올라가는 느낌). 구역 입구 / 캠프는 항상 0층.
local STAIRS = {
	{ At = 110, Rise = 16, Run = 56 },
	{ At = 250, Rise = 16, Run = 56 },
	{ At = 390, Rise = 16, Run = 56 },
	{ At = 520, Rise = -48, Run = 120 },
}
local FLOOR_SEGMENTS = {}   -- { A = 구역 안 x 시작, B = 끝, H = 높이, Kind = "Floor" | "Step"(경사로), Stair = 경사로 정보 }
do
	local height, cursor = 0, 0
	for _, stair in ipairs(STAIRS) do
		table.insert(FLOOR_SEGMENTS, { A = cursor, B = stair.At, H = height, Kind = "Floor" })
		stair.From = height
		stair.Hi = math.max(height, height + stair.Rise)
		table.insert(FLOOR_SEGMENTS, { A = stair.At, B = stair.At + stair.Run, H = height, Kind = "Step", Stair = stair, First = true })
		height += stair.Rise
		cursor = stair.At + stair.Run
		stair.Top = height
	end
	table.insert(FLOOR_SEGMENTS, { A = cursor, B = F.ZoneLength, H = height, Kind = "Floor" })
end
local function floorAt(x)
	local offset = (x - F.StartX) % F.ZoneLength
	for _, segment in ipairs(FLOOR_SEGMENTS) do
		if offset < segment.B then
			if segment.Kind == "Step" then
				local stair = segment.Stair
				local t = math.clamp((offset - stair.At) / stair.Run, 0, 1)
				return TOP + stair.From + stair.Rise * t -- 경사로 위의 높이 (몬스터 / 전리품이 경사를 따라간다)
			end
			return TOP + segment.H
		end
	end
	return TOP
end

local function makePart(props, parent)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	part.Parent = parent
	return part
end

------------------------------------------------------------
-- 맵 생성
------------------------------------------------------------
local function makeSign(part, text, color, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 400, 0, 130)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 160
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
end

-- ===== 구역 꾸미기 (구역마다 완전히 다른 지형지물 + 그 구역의 랜드마크 하나) =====
-- 장식은 대부분 충돌이 없거나 작아서 길을 막지 않는다. 경사로 / 꺾임 벽 / 캠프 근처에는 놓지 않는다.
local function propBlocked(offset)
	for _, stair in ipairs(STAIRS) do
		if offset > stair.At - 10 and offset < stair.At + stair.Run + 10 then return true end
	end
	for _, wall in ipairs({ 230, 400, 570 }) do
		if math.abs(offset - wall) < 20 then return true end
	end
	return false
end

local function decorateZone(zone, rng)
	local x0, x1 = zoneBounds(zone)
	local half = F.Width / 2
	local function P(props) return makePart(props, worldFolder) end
	local function R(a, b) return rng:NextNumber(a, b) end
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	local function glow(part, color, range, brightness)
		local light = Instance.new("PointLight")
		light.Range = range
		light.Brightness = brightness or 1.2
		light.Color = color
		light.Parent = part
	end
	local function emit(part, color, rate, size, speed, lifetime, upward)
		local e = Instance.new("ParticleEmitter")
		e.Rate = rate
		e.Lifetime = NumberRange.new(lifetime or 1, (lifetime or 1) * 1.6)
		e.Speed = NumberRange.new(speed * 0.5, speed)
		e.SpreadAngle = Vector2.new(25, 25)
		e.LightEmission = 1
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
		if upward then e.EmissionDirection = Enum.NormalId.Top end
		e.Parent = part
	end
	local function tilt(pos, rx, ry, rz) return CFrame.new(pos) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0)) end

	-- ---- 부품 모음 ----
	local function oak(pos, scale, dark)
		local h = R(8, 13) * scale
		P({ Name = "Trunk", Size = Vector3.new(2 * scale, h, 2 * scale), CFrame = tilt(pos + Vector3.new(0, h / 2, 0), R(-4, 4), R(0, 360), R(-4, 4)), Color = rgb(88, 60, 38), Material = Enum.Material.Wood })
		for i = 1, 3 do
			local leaf = R(8, 13) * scale
			local g = dark and rgb(R(25, 45), R(85, 115), R(40, 60)) or rgb(R(55, 85), R(135, 175), R(55, 85))
			P({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(leaf, leaf * 0.85, leaf), Position = pos + Vector3.new(R(-3, 3), h + R(-1, 4), R(-3, 3)), Color = g, Material = Enum.Material.Grass, CanCollide = false })
		end
	end
	local function pine(pos, scale, snowy)
		local h = R(14, 22) * scale
		P({ Name = "Trunk", Size = Vector3.new(1.6 * scale, h * 0.5, 1.6 * scale), Position = pos + Vector3.new(0, h * 0.25, 0), Color = rgb(80, 56, 40), Material = Enum.Material.Wood })
		for i = 0, 3 do
			local w = (10 - i * 2.1) * scale
			P({ Name = "Pine", Shape = Enum.PartType.Ball, Size = Vector3.new(w, w * 0.8, w), Position = pos + Vector3.new(0, h * 0.35 + i * h * 0.17, 0), Color = snowy and (i == 3 and rgb(240, 248, 252) or rgb(60, 105, 80)) or rgb(35, 90, 55), Material = snowy and Enum.Material.Snow or Enum.Material.Grass, CanCollide = false })
		end
	end
	local function flowers(pos)
		local palette = { rgb(255, 120, 150), rgb(255, 220, 90), rgb(190, 130, 255), rgb(255, 255, 255), rgb(255, 150, 60) }
		for _ = 1, 9 do
			local fx, fz = R(-5, 5), R(-5, 5)
			local sh = R(1.2, 2.2)
			P({ Name = "Stem", Size = Vector3.new(0.15, sh, 0.15), Position = pos + Vector3.new(fx, sh / 2, fz), Color = rgb(60, 130, 55), Material = Enum.Material.Grass, CanCollide = false })
			P({ Name = "Bloom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), Position = pos + Vector3.new(fx, sh + 0.2, fz), Color = palette[rng:NextInteger(1, #palette)], Material = Enum.Material.SmoothPlastic, CanCollide = false })
		end
	end
	local function mushroom(pos, big, cap)
		local sh = (big and R(6, 10) or R(2, 4))
		local cw = big and R(9, 14) or R(3, 5)
		P({ Name = "Stem", Size = Vector3.new(cw * 0.28, sh, cw * 0.28), Position = pos + Vector3.new(0, sh / 2, 0), Color = rgb(235, 225, 205), Material = Enum.Material.SmoothPlastic })
		local cap_ = P({ Name = "Cap", Shape = Enum.PartType.Ball, Size = Vector3.new(cw, cw * 0.55, cw), Position = pos + Vector3.new(0, sh, 0), Color = cap, Material = Enum.Material.SmoothPlastic, CanCollide = false })
		for _ = 1, big and 5 or 2 do
			local ang = R(0, 6.28)
			P({ Name = "Dot", Shape = Enum.PartType.Ball, Size = Vector3.new(cw * 0.14, cw * 0.14, cw * 0.14), Position = pos + Vector3.new(math.cos(ang) * cw * 0.28, sh + cw * 0.2, math.sin(ang) * cw * 0.28), Color = rgb(255, 255, 230), Material = Enum.Material.Neon, CanCollide = false })
		end
		if big then glow(cap_, cap, 24, 0.9) end
	end
	local function rocks(pos, color, mat, count)
		for _ = 1, count or 4 do
			local sz = R(2.5, 7)
			P({ Name = "Rock", Size = Vector3.new(sz, sz * R(0.6, 1), sz * R(0.9, 1.3)), CFrame = tilt(pos + Vector3.new(R(-5, 5), sz * 0.25, R(-5, 5)), R(-12, 12), R(0, 360), R(-12, 12)), Color = color:Lerp(Color3.new(0, 0, 0), R(0, 0.25)), Material = mat or Enum.Material.Slate })
		end
	end
	local function logs(pos)
		local len = R(7, 12)
		P({ Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, 2.2, 2.2), CFrame = tilt(pos + Vector3.new(0, 1.1, 0), 0, R(0, 360), R(-4, 4)), Color = rgb(95, 66, 42), Material = Enum.Material.Wood })
		P({ Name = "Stump", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 3.4, 3.4), CFrame = tilt(pos + Vector3.new(R(6, 9), 1.2, R(-3, 3)), 0, 0, 90), Color = rgb(110, 78, 50), Material = Enum.Material.Wood })
	end
	local function pond(pos, color, radius)
		local r = radius or R(8, 13)
		P({ Name = "Pond", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, r * 2, r * 2), CFrame = tilt(pos + Vector3.new(0, 0.2, 0), 0, 0, 90), Color = color, Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false })
		for i = 1, 9 do
			local a = i / 9 * 6.28
			local sz = R(1.5, 3)
			P({ Name = "PondRock", Size = Vector3.new(sz, sz * 0.7, sz), Position = pos + Vector3.new(math.cos(a) * (r + 0.5), sz * 0.3, math.sin(a) * (r + 0.5)), Color = rgb(120, 118, 112), Material = Enum.Material.Slate })
		end
	end
	local function deadTree(pos, color, glowColor)
		local h = R(8, 14)
		local trunk = P({ Name = "DeadTrunk", Size = Vector3.new(1.6, h, 1.6), CFrame = tilt(pos + Vector3.new(0, h / 2, 0), R(-6, 6), R(0, 360), R(-6, 6)), Color = color, Material = Enum.Material.Wood })
		for i = 1, 3 do
			local bl = R(3, 6)
			P({ Name = "Branch", Size = Vector3.new(0.7, bl, 0.7), CFrame = tilt(pos + Vector3.new(R(-1.5, 1.5), h * (0.45 + i * 0.15), R(-1.5, 1.5)), R(-60, 60), R(0, 360), R(30, 70)), Color = color, Material = Enum.Material.Wood, CanCollide = false })
		end
		if glowColor then glow(trunk, glowColor, 14, 0.8) end
	end
	local function bones(pos)
		for _ = 1, 7 do
			local bl = R(2.5, 5)
			P({ Name = "Bone", Size = Vector3.new(0.5, 0.5, bl), CFrame = tilt(pos + Vector3.new(R(-4, 4), 0.3, R(-4, 4)), R(-10, 10), R(0, 360), 0), Color = rgb(228, 220, 200), Material = Enum.Material.SmoothPlastic, CanCollide = false })
		end
		P({ Name = "Skull", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2, 2.2), Position = pos + Vector3.new(R(-2, 2), 1, R(-2, 2)), Color = rgb(235, 228, 210), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	local function pillar(pos, stone)
		local h = R(6, 14)
		P({ Name = "PillarBase", Size = Vector3.new(4.4, 1, 4.4), Position = pos + Vector3.new(0, 0.5, 0), Color = stone, Material = Enum.Material.Cobblestone })
		P({ Name = "Pillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 3, 3), CFrame = tilt(pos + Vector3.new(0, 1 + h / 2, 0), 0, 0, 90), Color = stone, Material = Enum.Material.Marble })
		P({ Name = "Fallen", Shape = Enum.PartType.Cylinder, Size = Vector3.new(R(4, 7), 2.8, 2.8), CFrame = tilt(pos + Vector3.new(R(4, 6), 1.4, R(-3, 3)), 0, R(0, 90), 0), Color = stone, Material = Enum.Material.Marble })
	end
	local function arch(pos, stone)
		local gap = R(8, 11)
		for _, side in ipairs({ -1, 1 }) do
			P({ Name = "ArchLeg", Size = Vector3.new(3, 15, 3.4), Position = pos + Vector3.new(side * gap / 2, 7.5, 0), Color = stone, Material = Enum.Material.Cobblestone })
		end
		P({ Name = "ArchTop", Size = Vector3.new(gap + 5, 3, 3.6), CFrame = tilt(pos + Vector3.new(0, 16, 0), 0, 0, R(-3, 3)), Color = stone, Material = Enum.Material.Cobblestone })
	end
	local function cactus(pos)
		local h = R(6, 12)
		P({ Name = "Cactus", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 2.2, 2.2), CFrame = tilt(pos + Vector3.new(0, h / 2, 0), 0, 0, 90), Color = rgb(72, 140, 72), Material = Enum.Material.Grass })
		for _, side in ipairs({ -1, 1 }) do
			if rng:NextNumber() < 0.7 then
				local ah = R(2.5, 4.5)
				P({ Name = "CactusArm", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8, 1.4, 1.4), CFrame = tilt(pos + Vector3.new(side * 1.8, h * 0.45, 0), 0, 0, 0), Color = rgb(72, 140, 72), Material = Enum.Material.Grass, CanCollide = false })
				P({ Name = "CactusArmUp", Shape = Enum.PartType.Cylinder, Size = Vector3.new(ah, 1.4, 1.4), CFrame = tilt(pos + Vector3.new(side * 2.6, h * 0.45 + ah / 2, 0), 0, 0, 90), Color = rgb(72, 140, 72), Material = Enum.Material.Grass, CanCollide = false })
			end
		end
		P({ Name = "CactusFlower", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Position = pos + Vector3.new(0, h + 0.5, 0), Color = rgb(255, 110, 160), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	local function dune(pos, color)
		local w = R(26, 44)
		P({ Name = "Dune", Shape = Enum.PartType.Ball, Size = Vector3.new(w, R(8, 14), w * R(0.6, 1)), CFrame = tilt(pos + Vector3.new(0, -2, 0), 0, R(0, 360), 0), Color = color, Material = Enum.Material.Sand, CanCollide = false })
	end
	local function palm(pos)
		local h = R(9, 13)
		P({ Name = "PalmTrunk", Size = Vector3.new(1.3, h, 1.3), CFrame = tilt(pos + Vector3.new(0, h / 2, 0), R(-8, 8), R(0, 360), R(-10, 10)), Color = rgb(150, 112, 70), Material = Enum.Material.Wood })
		for i = 1, 5 do
			P({ Name = "Frond", Size = Vector3.new(0.4, 0.3, 7), CFrame = tilt(pos + Vector3.new(0, h + 0.5, 0), R(15, 35), i * 72, 0) * CFrame.new(0, 0, -3), Color = rgb(60, 150, 70), Material = Enum.Material.Grass, CanCollide = false })
		end
	end
	local function iceSpire(pos)
		for _ = 1, 3 do
			local h = R(7, 16)
			P({ Name = "Ice", Size = Vector3.new(R(2, 3.5), h, R(2, 3.5)), CFrame = tilt(pos + Vector3.new(R(-3, 3), h / 2 - 1, R(-3, 3)), R(-12, 12), R(0, 360), R(-12, 12)), Color = rgb(175, 225, 255), Material = Enum.Material.Ice, Transparency = 0.12 })
		end
	end
	local function snowman(pos)
		P({ Name = "SnowBody", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = pos + Vector3.new(0, 2.5, 0), Color = rgb(245, 250, 252), Material = Enum.Material.Snow })
		P({ Name = "SnowBody", Shape = Enum.PartType.Ball, Size = Vector3.new(3.6, 3.6, 3.6), Position = pos + Vector3.new(0, 6, 0), Color = rgb(245, 250, 252), Material = Enum.Material.Snow, CanCollide = false })
		P({ Name = "SnowHead", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), Position = pos + Vector3.new(0, 8.6, 0), Color = rgb(245, 250, 252), Material = Enum.Material.Snow, CanCollide = false })
		P({ Name = "Nose", Size = Vector3.new(0.4, 0.4, 1.4), Position = pos + Vector3.new(0, 8.6, -1.6), Color = rgb(255, 140, 40), Material = Enum.Material.SmoothPlastic, CanCollide = false })
		P({ Name = "Hat", Size = Vector3.new(2, 1.6, 2), Position = pos + Vector3.new(0, 10.3, 0), Color = rgb(40, 40, 55), Material = Enum.Material.Fabric, CanCollide = false })
	end
	local function frozenLake(pos)
		local r = R(11, 17)
		P({ Name = "FrozenLake", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, r * 2, r * 2), CFrame = tilt(pos + Vector3.new(0, 0.25, 0), 0, 0, 90), Color = rgb(190, 232, 250), Material = Enum.Material.Ice, Transparency = 0.1 })
	end
	local function lava(pos)
		local r = R(7, 13)
		local pool = P({ Name = "Lava", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, r * 2, r * 2), CFrame = tilt(pos + Vector3.new(0, 0.25, 0), 0, 0, 90), Color = rgb(255, 100, 30), Material = Enum.Material.Neon, CanCollide = false })
		glow(pool, rgb(255, 110, 40), 34, 1.8)
		emit(pool, rgb(255, 170, 70), 8, 1.6, 4, 1.2, true)
		for i = 1, 8 do
			local a = i / 8 * 6.28
			local sz = R(2, 4)
			P({ Name = "LavaRim", Size = Vector3.new(sz, sz * 0.8, sz), Position = pos + Vector3.new(math.cos(a) * (r + 0.8), sz * 0.3, math.sin(a) * (r + 0.8)), Color = rgb(35, 30, 32), Material = Enum.Material.Basalt })
		end
	end
	local function obsidian(pos, tint)
		for _ = 1, 2 do
			local h = R(8, 20)
			P({ Name = "Obsidian", Size = Vector3.new(R(2, 4), h, R(2, 4)), CFrame = tilt(pos + Vector3.new(R(-3, 3), h / 2 - 1, R(-3, 3)), R(-14, 14), R(0, 360), R(-14, 14)), Color = tint or rgb(28, 24, 34), Material = Enum.Material.Glass })
		end
	end
	local function vent(pos)
		P({ Name = "Vent", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 5, 5), CFrame = tilt(pos + Vector3.new(0, 1, 0), 0, 0, 90), Color = rgb(40, 34, 36), Material = Enum.Material.Basalt })
		local ember = P({ Name = "VentGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 1, 2.4), Position = pos + Vector3.new(0, 2.1, 0), Color = rgb(255, 120, 40), Material = Enum.Material.Neon, CanCollide = false })
		emit(ember, rgb(255, 150, 60), 24, 2.2, 8, 1, true)
		glow(ember, rgb(255, 120, 40), 22, 1.4)
	end
	local function crystals(pos, color)
		for _ = 1, rng:NextInteger(3, 6) do
			local h = R(4, 14)
			local c = P({ Name = "Crystal", Size = Vector3.new(R(1.4, 2.8), h, R(1.4, 2.8)), CFrame = tilt(pos + Vector3.new(R(-4, 4), h / 2 - 0.5, R(-4, 4)), R(-18, 18), R(0, 360), R(-18, 18)), Color = color, Material = Enum.Material.Neon, Transparency = 0.08 })
			if rng:NextNumber() < 0.4 then glow(c, color, 20, 1.1) end
		end
	end
	local function floating(pos, color)
		local lift = R(16, 30)
		local w = R(12, 20)
		local top = pos + Vector3.new(0, lift, 0)
		P({ Name = "IslandTop", Shape = Enum.PartType.Ball, Size = Vector3.new(w, w * 0.35, w), Position = top, Color = rgb(70, 62, 85), Material = Enum.Material.Slate, CanCollide = false })
		P({ Name = "IslandUnder", Size = Vector3.new(w * 0.35, w * 0.7, w * 0.35), CFrame = tilt(top + Vector3.new(0, -w * 0.45, 0), 0, R(0, 360), 0) * CFrame.Angles(math.rad(180), 0, 0), Color = rgb(55, 48, 68), Material = Enum.Material.Slate, CanCollide = false })
		local gem = P({ Name = "IslandGem", Size = Vector3.new(1.6, 4.5, 1.6), CFrame = tilt(top + Vector3.new(0, w * 0.3, 0), R(-10, 10), R(0, 360), R(-10, 10)), Color = color, Material = Enum.Material.Neon, CanCollide = false })
		glow(gem, color, 30, 1.3)
	end
	local function obelisk(pos, color)
		local h = R(14, 24)
		P({ Name = "Obelisk", Size = Vector3.new(3.6, h, 3.6), CFrame = tilt(pos + Vector3.new(0, h / 2, 0), R(-3, 3), R(0, 360), R(-3, 3)), Color = rgb(34, 30, 44), Material = Enum.Material.Slate })
		for k = 1, 3 do
			local rune = P({ Name = "Rune", Size = Vector3.new(3.9, 0.7, 3.9), Position = pos + Vector3.new(0, h * (0.2 + k * 0.2), 0), Color = color, Material = Enum.Material.Neon, CanCollide = false })
			if k == 2 then glow(rune, color, 26, 1.2) end
		end
	end
	local function orb(pos, color)
		local o = P({ Name = "VoidOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), Position = pos + Vector3.new(0, R(5, 11), 0), Color = color, Material = Enum.Material.Neon, CanCollide = false })
		glow(o, color, 28, 1.5)
		emit(o, color, 12, 1.2, 3, 1, false)
	end
	local function tentacle(pos, color, tip)
		local segs = rng:NextInteger(7, 10)
		local sway = R(-0.8, 0.8)
		for i = 1, segs do
			local d = 4.2 - i * 0.3
			P({ Name = "Tentacle", Shape = Enum.PartType.Ball, Size = Vector3.new(d, d, d), Position = pos + Vector3.new(math.sin(i * 0.55) * 3.2 * sway * i * 0.4, i * 2.2, math.cos(i * 0.45) * 2 * i * 0.15), Color = i == segs and tip or color, Material = i == segs and Enum.Material.Neon or Enum.Material.SmoothPlastic, CanCollide = i < 3 })
		end
	end
	local function eyeMonolith(pos, tipColor)
		local h = R(20, 30)
		P({ Name = "Monolith", Size = Vector3.new(6, h, 3), CFrame = tilt(pos + Vector3.new(0, h / 2, 0), 0, R(0, 360), 0), Color = rgb(20, 16, 28), Material = Enum.Material.Slate })
		local eye = P({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 2), Position = pos + Vector3.new(0, h * 0.7, 1.9), Color = tipColor, Material = Enum.Material.Neon, CanCollide = false })
		glow(eye, tipColor, 34, 1.6)
		P({ Name = "Pupil", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 3.2, 1), Position = pos + Vector3.new(0, h * 0.7, 2.5), Color = rgb(10, 5, 15), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	local function patch(pos, color, mat, size)
		P({ Name = "GroundPatch", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, size, size), CFrame = tilt(pos + Vector3.new(0, 0.1, 0), 0, 0, 90), Color = color, Material = mat, CanCollide = false })
	end

	-- ---- 구역별 구성 ----
	local stoneColor = rgb(150, 144, 135)
	local ZONE = {
		[1] = { -- 초원: 푸른 나무 / 꽃밭 / 바위 / 작은 연못 / 통나무
			{ 5, function(p) oak(p, R(0.9, 1.3), false) end }, { 4, flowers }, { 2, function(p) rocks(p, rgb(130, 128, 120), Enum.Material.Slate, 3) end },
			{ 1, logs }, { 0.7, function(p) pond(p, rgb(90, 170, 220), nil) end }, { 1.5, function(p) patch(p, rgb(120, 160, 70), Enum.Material.Grass, R(14, 26)) end },
		},
		[2] = { -- 숲: 어두운 큰 나무 / 거대 버섯 / 반딧불 연못 / 통나무
			{ 6, function(p) oak(p, R(1.1, 1.6), true) end }, { 3, function(p) mushroom(p, true, rgb(R(150, 220), 60, R(90, 190))) end }, { 3, function(p) mushroom(p, false, rgb(230, 90, 90)) end },
			{ 2, logs }, { 1.2, function(p) pond(p, rgb(70, 190, 160), nil) end }, { 1, flowers }, { 1.2, function(p) patch(p, rgb(40, 75, 40), Enum.Material.Grass, R(14, 24)) end },
		},
		[3] = { -- 황무지: 죽은 나무 / 부서진 기둥과 아치 / 뼈 / 바위 무더기
			{ 4, function(p) deadTree(p, rgb(70, 58, 48), nil) end }, { 3, function(p) rocks(p, rgb(120, 104, 90), Enum.Material.Slate, 5) end }, { 2, bones },
			{ 2.5, function(p) pillar(p, stoneColor) end }, { 1.2, function(p) arch(p, stoneColor) end }, { 2, function(p) patch(p, rgb(105, 88, 70), Enum.Material.Ground, R(14, 28)) end },
		},
		[4] = { -- 사막: 선인장 / 모래 언덕 / 모래색 바위 / 뼈 / 오아시스
			{ 4, cactus }, { 3.5, function(p) dune(p, rgb(222, 196, 130)) end }, { 1.5, function(p) rocks(p, rgb(196, 160, 110), Enum.Material.Sandstone, 4) end },
			{ 1, bones }, { 1, function(p) arch(p, rgb(205, 175, 125)) end }, { 0.8, function(p) pond(p, rgb(70, 170, 210), 9); palm(p + Vector3.new(11, 0, 4)); palm(p + Vector3.new(-10, 0, -5)) end },
		},
		[5] = { -- 설원: 눈 덮인 소나무 / 얼음 기둥 / 눈사람 / 얼어붙은 호수
			{ 6, function(p) pine(p, R(0.9, 1.4), true) end }, { 3, iceSpire }, { 1, snowman }, { 1, frozenLake },
			{ 2, function(p) rocks(p, rgb(205, 215, 225), Enum.Material.Marble, 3) end }, { 2, function(p) patch(p, rgb(245, 250, 253), Enum.Material.Snow, R(16, 28)) end },
		},
		[6] = { -- 화산: 용암 웅덩이 / 흑요석 가시 / 분화구 연기 / 불탄 나무
			{ 3, lava }, { 4, function(p) obsidian(p, nil) end }, { 3, vent }, { 2, function(p) rocks(p, rgb(55, 46, 46), Enum.Material.Basalt, 4) end },
			{ 1, function(p) deadTree(p, rgb(40, 32, 30), rgb(255, 110, 40)) end }, { 2, function(p) patch(p, rgb(60, 30, 26), Enum.Material.Basalt, R(14, 26)) end },
		},
		[7] = { -- 암흑 지대: 보라 결정 / 빛나는 죽은 나무 / 떠 있는 섬 / 룬 오벨리스크 / 공허 구슬
			{ 4, function(p) crystals(p, rgb(150, 80, 255)) end }, { 2, function(p) deadTree(p, rgb(40, 34, 52), rgb(150, 80, 255)) end }, { 2, function(p) floating(p, rgb(160, 90, 255)) end },
			{ 2, function(p) obelisk(p, rgb(170, 100, 255)) end }, { 1.5, function(p) orb(p, rgb(190, 120, 255)) end }, { 1.5, function(p) patch(p, rgb(45, 36, 66), Enum.Material.Slate, R(14, 26)) end },
		},
		[8] = { -- 심연: 촉수 / 눈 모놀리스 / 공허 구슬 / 분홍 결정 / 떠 있는 섬
			{ 3, function(p) tentacle(p, rgb(50, 24, 66), rgb(255, 70, 140)) end }, { 1.5, function(p) eyeMonolith(p, rgb(255, 60, 120)) end }, { 3, function(p) orb(p, rgb(255, 80, 150)) end },
			{ 3, function(p) crystals(p, rgb(255, 60, 130)) end }, { 1.5, function(p) floating(p, rgb(255, 80, 150)) end }, { 1.5, function(p) obsidian(p, rgb(30, 14, 36)) end },
			{ 1.5, function(p) patch(p, rgb(28, 20, 40), Enum.Material.Slate, R(14, 26)) end },
		},
	}
	local entries = ZONE[zone]
	local total = 0
	for _, entry in ipairs(entries) do total += entry[1] end
	local function pickProp()
		local roll = rng:NextNumber() * total
		for _, entry in ipairs(entries) do
			roll -= entry[1]
			if roll <= 0 then return entry[2] end
		end
		return entries[1][2]
	end
	local function place(builder, cx, cz)
		if propBlocked(cx - x0) then return false end
		builder(Vector3.new(cx, floorAt(cx), cz))
		return true
	end

	-- 군락: 비슷한 것끼리 모여 있어서 "숲 속 빈터", "바위 군락" 같은 장면이 생긴다
	for _ = 1, 18 do
		local cx = rng:NextNumber(x0 + F.CampSafe + 16, x1 - 18)
		local cz = rng:NextNumber(-half + 22, half - 22)
		local builder = pickProp()
		for _ = 1, rng:NextInteger(3, 5) do
			place(builder, cx + rng:NextNumber(-16, 16), math.clamp(cz + rng:NextNumber(-16, 16), -half + 8, half - 8))
		end
	end
	-- 흩어진 낱개
	for _ = 1, 45 do
		place(pickProp(), rng:NextNumber(x0 + F.CampSafe + 10, x1 - 12), rng:NextNumber(-half + 8, half - 8))
	end

	-- 랜드마크: 구역마다 멀리서도 보이는 큰 구조물 하나 (길에서 벗어난 가장자리 쪽)
	local lx = x0 + 318 + rng:NextNumber(-8, 8)
	local side = zone % 2 == 0 and 1 or -1
	local lz = side * (half * 0.55)
	local lp = Vector3.new(lx, floorAt(lx), lz)
	if zone == 1 then -- 거대한 고목 + 돌 원형 제단
		oak(lp, 3.2, false)
		for i = 1, 8 do
			local a = i / 8 * 6.28
			P({ Name = "StoneCircle", Size = Vector3.new(2.4, R(5, 8), 2.4), Position = lp + Vector3.new(math.cos(a) * 17, 3, math.sin(a) * 17), Color = stoneColor, Material = Enum.Material.Marble })
		end
	elseif zone == 2 then -- 거대 버섯 고리 + 빛나는 연못
		pond(lp, rgb(70, 220, 180), 14)
		for i = 1, 6 do
			local a = i / 6 * 6.28
			mushroom(lp + Vector3.new(math.cos(a) * 24, 0, math.sin(a) * 24), true, rgb(180, 70, 200))
		end
	elseif zone == 3 then -- 무너진 망루
		for level = 0, 3 do
			local w = 16 - level * 2
			P({ Name = "TowerRuin", Size = Vector3.new(w, 9, w), Position = lp + Vector3.new(0, 4.5 + level * 9, 0), Color = stoneColor:Lerp(Color3.new(0, 0, 0), level * 0.08), Material = Enum.Material.Cobblestone })
		end
		pillar(lp + Vector3.new(20, 0, 6), stoneColor)
		pillar(lp + Vector3.new(-20, 0, -6), stoneColor)
		arch(lp + Vector3.new(0, 0, 24), stoneColor)
	elseif zone == 4 then -- 피라미드 + 오아시스
		for level = 0, 7 do
			local w = 44 - level * 5
			P({ Name = "Pyramid", Size = Vector3.new(w, 5, w), Position = lp + Vector3.new(0, 2.5 + level * 5, 0), Color = rgb(222, 196, 130):Lerp(Color3.new(0, 0, 0), level * 0.02), Material = Enum.Material.Sandstone })
		end
		local cap = P({ Name = "PyramidTop", Size = Vector3.new(3, 3, 3), Position = lp + Vector3.new(0, 42, 0), Color = rgb(255, 215, 90), Material = Enum.Material.Neon, CanCollide = false })
		glow(cap, rgb(255, 215, 90), 40, 1.5)
		pond(lp + Vector3.new(36, 0, 22), rgb(70, 175, 215), 10)
		palm(lp + Vector3.new(44, 0, 22)); palm(lp + Vector3.new(30, 0, 28))
	elseif zone == 5 then -- 얼음 성의 첨탑들
		for i = 1, 5 do
			local h = R(22, 44)
			local a = i / 5 * 6.28
			P({ Name = "IceTower", Size = Vector3.new(R(5, 8), h, R(5, 8)), CFrame = tilt(lp + Vector3.new(math.cos(a) * 12, h / 2, math.sin(a) * 12), R(-4, 4), R(0, 360), R(-4, 4)), Color = rgb(170, 220, 250), Material = Enum.Material.Ice, Transparency = 0.1 })
		end
		local core = P({ Name = "IceCore", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), Position = lp + Vector3.new(0, 20, 0), Color = rgb(150, 230, 255), Material = Enum.Material.Neon, CanCollide = false })
		glow(core, rgb(150, 230, 255), 50, 1.5)
		frozenLake(lp + Vector3.new(0, 0, 0))
	elseif zone == 6 then -- 화산
		for level = 0, 5 do
			local r = 30 - level * 4
			P({ Name = "Volcano", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, r * 2, r * 2), CFrame = tilt(lp + Vector3.new(0, 3.5 + level * 7, 0), 0, 0, 90), Color = rgb(58, 46, 46):Lerp(rgb(110, 40, 30), level * 0.12), Material = Enum.Material.Basalt })
		end
		local top = P({ Name = "VolcanoLava", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 16, 16), CFrame = tilt(lp + Vector3.new(0, 42.2, 0), 0, 0, 90), Color = rgb(255, 110, 30), Material = Enum.Material.Neon, CanCollide = false })
		glow(top, rgb(255, 110, 30), 70, 2.2)
		emit(top, rgb(255, 160, 60), 40, 4, 14, 2, true)
	elseif zone == 7 then -- 떠 있는 오벨리스크 군도
		for i = 1, 4 do
			local a = i / 4 * 6.28
			floating(lp + Vector3.new(math.cos(a) * 20, R(8, 20), math.sin(a) * 20), rgb(170, 100, 255))
			obelisk(lp + Vector3.new(math.cos(a + 0.7) * 11, 0, math.sin(a + 0.7) * 11), rgb(170, 100, 255))
		end
		orb(lp, rgb(200, 130, 255))
	else -- 심연: 거대한 눈 + 촉수
		eyeMonolith(lp, rgb(255, 60, 120))
		P({ Name = "AbyssEye", Shape = Enum.PartType.Ball, Size = Vector3.new(16, 16, 6), Position = lp + Vector3.new(0, 44, 4), Color = rgb(255, 50, 110), Material = Enum.Material.Neon, CanCollide = false })
		glow(P({ Name = "AbyssEyeLight", Size = Vector3.new(1, 1, 1), Position = lp + Vector3.new(0, 44, 4), Transparency = 1, CanCollide = false }), rgb(255, 60, 120), 80, 2)
		for i = 1, 7 do
			local a = i / 7 * 6.28
			tentacle(lp + Vector3.new(math.cos(a) * 15, 0, math.sin(a) * 15), rgb(50, 24, 66), rgb(255, 70, 140))
		end
	end
end

local function buildCanyon(rng, totalLength, half)
	local endX = F.StartX + totalLength

	-- 뒤에 깔아두는 끊김 없는 절벽 벽 (절벽 덩어리 사이로 바깥이 비치지 않게)
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "CanyonBack", Size = Vector3.new(totalLength + 120, 240, 8),
			Position = Vector3.new(F.StartX + totalLength / 2, 120, side * (half + 34)),
			Color = Color3.fromRGB(55, 50, 58), Material = Enum.Material.Slate,
		}, worldFolder)

		-- 구역 색을 띤 크고 울퉁불퉁한 절벽 덩어리들
		local x = F.StartX - 10
		while x < endX + 20 do
			local zone = zoneOfX(math.clamp(x, F.StartX, endX - 1))
			local width = rng:NextNumber(34, 52)
			local height = rng:NextNumber(120, 200)
			local depth = rng:NextNumber(18, 30)
			local inner = half + rng:NextNumber(-4, 4)
			makePart({
				Name = "Cliff", Size = Vector3.new(width, height, depth),
				CFrame = CFrame.new(x, height / 2 - 2, side * (inner + depth / 2)) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0),
				Color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(70, 65, 72), 0.55),
				Material = Enum.Material.Slate,
			}, worldFolder)
			x += width * 0.8
		end
	end

	-- 필드 끝 / 로비에서 들어오는 통로 양옆도 절벽으로 막는다
	makePart({
		Name = "CanyonEnd", Size = Vector3.new(40, 240, F.Width + 90),
		Position = Vector3.new(endX + 20, 120, 0), Color = Color3.fromRGB(35, 30, 45), Material = Enum.Material.Slate,
	}, worldFolder)
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "CanyonGate", Size = Vector3.new(34, 80, 50),
			Position = Vector3.new(F.StartX - 16, 40, side * (21 + 25)),
			Color = Color3.fromRGB(95, 110, 85), Material = Enum.Material.Slate,
		}, worldFolder)
	end
end

-- 구역 입구 캠프: 안전지대 + 워프 비콘 + 부활 지점
local function buildCamp(zone, x0)
	local center = Vector3.new(x0 + 40, TOP, 0)
	local accent = F.ZoneColors[zone]:Lerp(Color3.fromRGB(255, 255, 255), 0.35)

	makePart({
		Name = "CampFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 64, 64),
		CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 112, 100), Material = Enum.Material.Cobblestone,
	}, worldFolder)

	local beacon = makePart({
		Name = "CampBeacon", Size = Vector3.new(3, 26, 3), Position = center + Vector3.new(0, 13, 0),
		Color = accent, Material = Enum.Material.Neon,
	}, worldFolder)
	local light = Instance.new("PointLight")
	light.Range = 45
	light.Brightness = 1.6
	light.Color = accent
	light.Parent = beacon
	makeSign(beacon, "⛺ 캠프 · 워프", Color3.fromRGB(255, 240, 200), 18)

	for index = 0, 3 do
		local angle = math.rad(index * 90 + 45)
		local post = center + Vector3.new(math.cos(angle) * 24, 0, math.sin(angle) * 24)
		makePart({ Name = "CampPost", Size = Vector3.new(1, 8, 1), Position = post + Vector3.new(0, 4, 0), Color = Color3.fromRGB(70, 50, 38), Material = Enum.Material.Wood }, worldFolder)
		local flame = makePart({
			Name = "CampFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = post + Vector3.new(0, 9, 0),
			Color = Color3.fromRGB(255, 150, 60), Material = Enum.Material.Neon, CanCollide = false,
		}, worldFolder)
		local flameLight = Instance.new("PointLight")
		flameLight.Range = 26
		flameLight.Color = Color3.fromRGB(255, 170, 90)
		flameLight.Parent = flame
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "워프 / 캠프"
	prompt.ObjectText = string.format("구역 %d 캠프", zone)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = beacon
	prompt.Triggered:Connect(function(player)
		Remotes.Warp:FireClient(player, "Open")
	end)

	campCFrames[zone] = CFrame.new(x0 + 40, TOP + 4, 16)
end

-- 구역 관문: 구역마다 컨셉이 다른 성문 / 입구. 문은 활짝 열려 있고, 이름 / 컨셉 / 몬스터 레벨이 위에 걸려 있다.
--   1 초원 목책 문 · 2 숲속 고성 정문 · 3 무너진 요새 · 4 사막 신전 · 5 얼음 궁전 · 6 용암 요새 · 7 암흑 성 · 8 심연의 문
local GATE_THEMES = {
	{ Tag = "🌾 모험의 시작", Wall = Color3.fromRGB(140, 105, 70), Mat = Enum.Material.Wood, Accent = Color3.fromRGB(255, 205, 90), Height = 24, Crenel = false },
	{ Tag = "🏰 숲속 고성 정문", Wall = Color3.fromRGB(105, 125, 105), Mat = Enum.Material.Brick, Accent = Color3.fromRGB(120, 230, 130), Height = 34, Crenel = true },
	{ Tag = "🏚 무너진 요새 관문", Wall = Color3.fromRGB(120, 105, 90), Mat = Enum.Material.Cobblestone, Accent = Color3.fromRGB(255, 170, 80), Height = 30, Crenel = true },
	{ Tag = "🏜 사막 신전 입구", Wall = Color3.fromRGB(205, 175, 110), Mat = Enum.Material.Sandstone, Accent = Color3.fromRGB(255, 215, 70), Height = 32, Crenel = false },
	{ Tag = "❄ 얼음 궁전 성문", Wall = Color3.fromRGB(180, 215, 235), Mat = Enum.Material.Ice, Accent = Color3.fromRGB(130, 220, 255), Height = 34, Crenel = true },
	{ Tag = "🌋 용암 요새 관문", Wall = Color3.fromRGB(70, 45, 42), Mat = Enum.Material.Basalt, Accent = Color3.fromRGB(255, 110, 40), Height = 34, Crenel = true },
	{ Tag = "🦇 암흑 성 정문", Wall = Color3.fromRGB(45, 38, 62), Mat = Enum.Material.Slate, Accent = Color3.fromRGB(170, 100, 255), Height = 40, Crenel = true },
	{ Tag = "🌀 심연의 문", Wall = Color3.fromRGB(28, 24, 40), Mat = Enum.Material.Slate, Accent = Color3.fromRGB(255, 70, 130), Height = 40, Crenel = false },
}

local function buildGateway(zone, x0)
	local theme = GATE_THEMES[zone]
	local half = F.Width / 2
	local open = 56            -- 열린 통로 폭 (로비 쪽 통로 40보다 넓게)
	local H = theme.Height + (zone - 1) * 5 -- 동쪽으로 갈수록 관문이 점점 거대해진다
	local thick = 8
	local accent = theme.Accent

	local function part(name, size, position, color, material, extra)
		local props = { Name = name, Size = size, Position = position, Color = color or theme.Wall, Material = material or theme.Mat }
		for key, value in pairs(extra or {}) do
			props[key] = value
		end
		if props.CFrame then
			props.Position = nil -- CFrame 이 위치를 정한다 (둘 다 있으면 적용 순서가 불확실)
		end
		return makePart(props, worldFolder)
	end
	local function torch(position)
		local flame = part("GateFlame", Vector3.new(2.4, 2.4, 2.4), position, accent, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		local light = Instance.new("PointLight")
		light.Range = 36
		light.Brightness = 1.6
		light.Color = accent
		light.Parent = flame
	end

	for _, side in ipairs({ -1, 1 }) do
		-- 성벽 + 흉벽
		local length = half - open / 2
		local zc = side * (open / 2 + length / 2)
		part("GateWall", Vector3.new(thick, H, length), Vector3.new(x0 + 2, H / 2, zc))
		if theme.Crenel then
			for z = open / 2 + 8, half - 4, 12 do
				part("Crenel", Vector3.new(thick, 4, 6), Vector3.new(x0 + 2, H + 2, side * z))
			end
		end

		-- 문루(탑) + 지붕 띠 + 창
		local towerZ = side * (open / 2 + 8)
		part("GateTower", Vector3.new(16, H + 14, 16), Vector3.new(x0 + 2, (H + 14) / 2, towerZ))
		part("TowerCap", Vector3.new(19, 3, 19), Vector3.new(x0 + 2, H + 15.5, towerZ), accent, Enum.Material.Neon)
		part("TowerWindow", Vector3.new(1, 7, 3.5), Vector3.new(x0 + 10.4, H * 0.72, towerZ), accent, Enum.Material.Neon, { CanCollide = false })
		part("TowerWindow", Vector3.new(1, 7, 3.5), Vector3.new(x0 - 6.4, H * 0.72, towerZ), accent, Enum.Material.Neon, { CanCollide = false })
		torch(Vector3.new(x0 + 11, 15, side * (open / 2 - 1)))

		-- 활짝 열린 문짝: 통로 가장자리에 경첩을 두고 안쪽(+x)으로 거의 활짝 젖혀 놓는다
		if zone ~= 8 then
			local hinge = Vector3.new(x0 + 2, 0, side * (open / 2 - 0.5))
			local angle = math.rad(78)
			local doorLength = 26
			local vector = Vector3.new(math.sin(angle), 0, -side * math.cos(angle)) * doorLength
			local center = hinge + vector / 2 + Vector3.new(0, H * 0.45, 0)
			part("GateDoor", Vector3.new(2, H * 0.9, doorLength), center, theme.Wall:Lerp(Color3.fromRGB(60, 45, 35), 0.5), Enum.Material.Wood,
				{ CFrame = CFrame.lookAt(center, center + vector) })
			-- 문짝 장식 띠
			part("DoorBand", Vector3.new(2.2, 2, doorLength), center + Vector3.new(0, H * 0.25, 0), accent, Enum.Material.Neon,
				{ CFrame = CFrame.lookAt(center + Vector3.new(0, H * 0.25, 0), center + Vector3.new(0, H * 0.25, 0) + vector), CanCollide = false })
		end
	end

	-- 상인방(문 위 가로보) + 컨셉 장식
	if zone ~= 8 then
		part("GateLintel", Vector3.new(thick, 7, open + 2), Vector3.new(x0 + 2, H - 0.5, 0))
		part("LintelGlow", Vector3.new(thick + 0.4, 1.2, open + 2.4), Vector3.new(x0 + 2, H - 4.5, 0), accent, Enum.Material.Neon, { CanCollide = false })
	end

	if zone == 1 then -- 목책: 문 앞뒤로 말뚝 울타리 + 깃발
		for _, side in ipairs({ -1, 1 }) do
			for index = 0, 5 do
				part("Fence", Vector3.new(1.4, 6, 1.4), Vector3.new(x0 + 14 + index * 7, 3, side * (open / 2 + 14)))
			end
			part("FenceRail", Vector3.new(42, 1, 0.8), Vector3.new(x0 + 35, 4.5, side * (open / 2 + 14)))
			part("Banner", Vector3.new(0.4, 9, 5), Vector3.new(x0 + 2, H + 6, side * (open / 2 + 8)), Color3.fromRGB(210, 70, 60), Enum.Material.Fabric, { CanCollide = false })
		end
	elseif zone == 2 then -- 이끼 낀 성: 덩굴 + 녹색 깃발
		for _, side in ipairs({ -1, 1 }) do
			part("Banner", Vector3.new(0.4, 14, 6), Vector3.new(x0 + 11, H - 4, side * (open / 2 + 8)), Color3.fromRGB(50, 130, 70), Enum.Material.Fabric, { CanCollide = false })
			part("Moss", Vector3.new(thick + 0.3, 6, 22), Vector3.new(x0 + 2, H - 3, side * (open / 2 + 30)), Color3.fromRGB(60, 120, 60), Enum.Material.Grass, { CanCollide = false })
		end
	elseif zone == 3 then -- 폐허: 부러진 기둥 + 잔해
		for _, side in ipairs({ -1, 1 }) do
			part("BrokenPillar", Vector3.new(5, 16, 5), Vector3.new(x0 - 8, 8, side * (open / 2 + 28)), nil, nil, { CFrame = CFrame.new(x0 - 8, 8, side * (open / 2 + 28)) * CFrame.Angles(0, 0.4, math.rad(side * 14)) })
			part("Rubble", Vector3.new(7, 3.5, 6), Vector3.new(x0 + 16, 1.7, side * (open / 2 + 6)), nil, nil, { CFrame = CFrame.new(x0 + 16, 1.7, side * (open / 2 + 6)) * CFrame.Angles(0.2, 0.8, 0.1) })
		end
	elseif zone == 4 then -- 사막 신전: 오벨리스크
		for _, side in ipairs({ -1, 1 }) do
			part("Obelisk", Vector3.new(6, 42, 6), Vector3.new(x0 - 12, 21, side * (open / 2 + 34)))
			part("ObeliskTip", Vector3.new(4, 6, 4), Vector3.new(x0 - 12, 45, side * (open / 2 + 34)), accent, Enum.Material.Neon)
		end
	elseif zone == 5 then -- 얼음 궁전: 기울어진 얼음 첨탑
		for _, side in ipairs({ -1, 1 }) do
			for index = 1, 3 do
				local z = side * (open / 2 + 18 + index * 9)
				local height = 14 + index * 4
				part("IceSpike", Vector3.new(4, height, 4), Vector3.new(x0 + 6, height / 2, z), Color3.fromRGB(190, 230, 250), Enum.Material.Ice,
					{ CFrame = CFrame.new(x0 + 6, height / 2, z) * CFrame.Angles(0, 0, math.rad(side * -10)), Transparency = 0.25 })
			end
		end
	elseif zone == 6 then -- 용암 요새: 바닥 용암 줄기 + 불기둥
		for _, side in ipairs({ -1, 1 }) do
			part("LavaStream", Vector3.new(30, 0.4, 7), Vector3.new(x0 + 22, 0.25, side * (open / 2 + 5)), accent, Enum.Material.Neon, { CanCollide = false })
			torch(Vector3.new(x0 - 6, 22, side * (open / 2 + 20)))
		end
	elseif zone == 7 then -- 암흑 성: 보랏빛 룬과 박쥐 깃발
		for _, side in ipairs({ -1, 1 }) do
			part("Banner", Vector3.new(0.4, 18, 6), Vector3.new(x0 + 11, H - 2, side * (open / 2 + 8)), Color3.fromRGB(60, 25, 90), Enum.Material.Fabric, { CanCollide = false })
			part("FloatRune", Vector3.new(4, 4, 4), Vector3.new(x0 + 6, H + 26, side * 16), accent, Enum.Material.Neon, { CanCollide = false, CFrame = CFrame.new(x0 + 6, H + 26, side * 16) * CFrame.Angles(0.8, 0.6, 0.3) })
		end
	elseif zone == 8 then -- 심연의 문: 거대한 고리 + 빛나는 막
		local segments = 18
		local radius = 30
		for index = 0, segments - 1 do
			local angle = index / segments * math.pi * 2
			local position = Vector3.new(x0 + 2, 32 + math.sin(angle) * radius, math.cos(angle) * radius)
			part("PortalRing", Vector3.new(4, 7, 7), position, accent, Enum.Material.Neon, { CanCollide = false,
				CFrame = CFrame.new(position) * CFrame.Angles(angle, 0, 0) })
		end
		part("PortalVeil", Vector3.new(1, 50, 56), Vector3.new(x0 + 2, 27, 0), accent, Enum.Material.Neon, { Transparency = 0.85, CanCollide = false, CanQuery = false })
	end

	-- 관문 봉인막: 구역 2부터. 보이는 모습은 클라이언트(GoalClient)가 내 진행도에 맞춰 열고 닫는다 (서버는 위치로 막는다)
	if zone >= 2 then
		local seal = part("GateSeal", Vector3.new(1, H - 4, open), Vector3.new(x0 - 1, (H - 4) / 2, 0), accent, Enum.Material.Neon,
			{ Transparency = 0.45, CanCollide = false, CanQuery = false })
		seal:SetAttribute("SealZone", zone)
		CollectionService:AddTag(seal, "ZoneSeal")
		local gui = Instance.new("BillboardGui")
		gui.Name = "SealGui"
		gui.Size = UDim2.new(0, 340, 0, 90)
		gui.StudsOffset = Vector3.new(-6, 0, 0)
		gui.MaxDistance = 140
		gui.Parent = seal
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Text = "🔒"
		label.Parent = gui
	end

	-- 동쪽으로 갈수록 극적으로: 구역마다 더 높고 더 넓고 더 진한 하늘 빛기둥 (멀리서도 "저 너머가 점점 위험하다"가 보인다) + 바닥 경고 줄무늬
	do
		local beamHeight = 90 + zone * 55
		local beamWidth = 7 + zone * 1.6
		local beacon = part("GateBeacon", Vector3.new(beamWidth, beamHeight, beamWidth), Vector3.new(x0 + 2, beamHeight / 2, 0), accent, Enum.Material.Neon,
			{ Transparency = math.max(0.72, 0.9 - zone * 0.025), CanCollide = false, CanQuery = false })
		local glow = Instance.new("PointLight")
		glow.Range = 60 + zone * 8
		glow.Brightness = 1.2 + zone * 0.15
		glow.Color = accent
		glow.Parent = beacon
		for stripe = 1, zone do -- 구역 번호만큼 줄무늬: 위험도가 눈에 보인다
			part("GateWarnStripe", Vector3.new(1.6, 0.25, open + 8), Vector3.new(x0 - 4 - stripe * 4, TOP + 0.2, 0), accent, Enum.Material.Neon,
				{ Transparency = 0.25 + 0.05 * (stripe % 2), CanCollide = false, CanQuery = false })
		end
	end

	-- 간판: 구역 이름 + 컨셉 + 몬스터 레벨
	local signPart = part("GateSign", Vector3.new(1, 1, 1), Vector3.new(x0 + 2, H + 24, 0), accent, Enum.Material.Neon, { Transparency = 1, CanCollide = false, CanQuery = false })
	local zoneSet = Config.Sets[Config.Sets.ZoneKeys[zone]]
	makeSign(signPart, string.format("구역 %d · %s\n%s · 몬스터 Lv.%d\n위험도 %s\n%s 여기서만 드랍: %s 세트", zone, F.ZoneNames[zone], theme.Tag, F.GetZoneLevel(zone), string.rep("☠", zone), zoneSet.Icon, zoneSet.Name), Color3.fromRGB(255, 240, 190), 0)
end

local function buildWorld()
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "Field"
	worldFolder.Parent = workspace

	monstersFolder = Instance.new("Folder")
	monstersFolder.Name = "FieldMonsters"
	monstersFolder.Parent = workspace

	local half = F.Width / 2
	local totalLength = F.ZoneLength * F.ZoneCount
	local rng = Random.new(77)

	for zone = 1, F.ZoneCount do
		local x0 = zoneBounds(zone)
		-- 바닥: 평지(층) 블록 + 좁은 계단통(양옆은 높은 벽, 가운데 폭 14 계단). 높은 층일수록 살짝 밝아져서 "층"이 구분된다
		for _, segment in ipairs(FLOOR_SEGMENTS) do
			local top = TOP + segment.H
			local tint = F.ZoneColors[zone]:Lerp(Color3.new(1, 1, 1), 0.08 * segment.H / 24)
			if segment.Kind == "Floor" then
				makePart({
					Name = "Ground" .. zone, Size = Vector3.new(segment.B - segment.A, top + 1.95, F.Width),
					Position = Vector3.new(x0 + (segment.A + segment.B) / 2, (top - 1.95) / 2, 0), Color = tint, Material = F.ZoneMaterials[zone],
				}, worldFolder)
			else
				local stair = segment.Stair
				-- 경사로: 비스듬한 두꺼운 판 + 아래쪽을 받치는 바닥 덩어리 (표면은 시작 / 끝 높이에 딱 맞는다)
				local startY, endY = TOP + stair.From, TOP + stair.From + stair.Rise
				local length = math.sqrt(stair.Run * stair.Run + stair.Rise * stair.Rise)
				local angle = math.atan2(stair.Rise, stair.Run)
				local thickness = 6
				local midX, midY = x0 + stair.At + stair.Run / 2, (startY + endY) / 2
				-- 표면에서 두께의 절반만큼 아래(법선 반대 방향)로 중심을 내린다
				local center = Vector3.new(midX + math.sin(angle) * thickness / 2, midY - math.cos(angle) * thickness / 2, 0)
				makePart({
					Name = "Ramp" .. zone, Size = Vector3.new(length, thickness, F.Width),
					CFrame = CFrame.new(center) * CFrame.Angles(0, 0, angle),
					Color = Color3.fromRGB(205, 195, 180):Lerp(F.ZoneColors[zone], 0.3), Material = Enum.Material.Cobblestone,
				}, worldFolder)
				local lowY = math.min(startY, endY)
				makePart({
					Name = "RampBase" .. zone, Size = Vector3.new(stair.Run, math.max(0.5, lowY - thickness + 1.95), F.Width),
					Position = Vector3.new(midX, (lowY - thickness - 1.95) / 2, 0), Color = F.ZoneColors[zone], Material = F.ZoneMaterials[zone],
				}, worldFolder)
				for dx = 0, stair.Run, 14 do
					table.insert(baffleXs, x0 + stair.At + dx)
				end
			end
		end
		buildGateway(zone, x0)

		decorateZone(zone, rng)
		buildCamp(zone, x0)
	end

	-- 꺾임 벽: 구역마다 벽 3개가 길을 가로막고, 틈이 위쪽 / 아래쪽 가장자리에 번갈아 뚫려 있다.
	-- 길이 ㄹ 자로 꺾이는 느낌이 나고, 멀리 있는 몬스터가 한눈에 다 보이지 않는다.
	do
		local gapSize = 130
		local side = 1
		for zone = 1, F.ZoneCount do
			local x0 = zoneBounds(zone)
			for _, offset in ipairs({ 230, 400, 570 }) do
				local wallLength = F.Width - gapSize
				local height = 110
				makePart({
					Name = "Baffle", Size = Vector3.new(22, height, wallLength),
					Position = Vector3.new(x0 + offset, height / 2 - 2, -side * gapSize / 2),
					Color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(70, 65, 72), 0.5), Material = Enum.Material.Slate,
				}, worldFolder)
				table.insert(baffleXs, x0 + offset)
				local zCenter = -side * gapSize / 2
				table.insert(baffleRects, { X0 = x0 + offset - 11, X1 = x0 + offset + 11, Z0 = zCenter - wallLength / 2, Z1 = zCenter + wallLength / 2 })
				side = -side
			end
		end
	end

	buildCanyon(rng, totalLength, half)

	-- 필드 가장자리 보이지 않는 벽 (옆면 / 끝 / 로비 쪽 입구 통로)
	local function wall(size, position)
		makePart({ Name = "Wall", Size = size, Position = position, Transparency = 1 }, worldFolder)
	end
	local centerX = F.StartX + totalLength / 2
	wall(Vector3.new(totalLength + 4, 240, 2), Vector3.new(centerX, 120, half + 1))
	wall(Vector3.new(totalLength + 4, 240, 2), Vector3.new(centerX, 120, -half - 1))
	wall(Vector3.new(2, 240, F.Width), Vector3.new(F.StartX + totalLength + 1, 120, 0))
	wall(Vector3.new(2, 50, half - 20), Vector3.new(F.StartX - 1, 25, (half + 20) / 2))
	wall(Vector3.new(2, 50, half - 20), Vector3.new(F.StartX - 1, 25, -(half + 20) / 2))
	wall(Vector3.new(26, 50, 2), Vector3.new(F.StartX - 14, 25, 21))
	wall(Vector3.new(26, 50, 2), Vector3.new(F.StartX - 14, 25, -21))
end

------------------------------------------------------------
-- 몬스터
------------------------------------------------------------
local function createHealthBar(part, text, width, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, width, 0, 28)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 110 -- 멀리 있는 몬스터 체력바가 다 보이지 않게
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui

	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0.4, 0)
	back.Position = UDim2.new(0, 0, 0.6, 0)
	back.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	back.BorderSizePixel = 0
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(230, 60, 60)
	fill.BorderSizePixel = 0
	fill.Parent = back

	return fill
end

-- kind: "Normal" / "Elite" / "Boss"
local function spawnMonster(zone, kind, at, ambush)
	local stats, text, color, barWidth
	local level = F.GetZoneLevel(zone)
	local typeKey, def, xpLevel

	if kind == "Boss" then
		-- 구역마다 하나씩 있는 구역 보스: 그 구역 몬스터 레벨 기준으로 체력 / 공격력이 훨씬 세고 크다. 관문을 열려면 이 보스를 쓰러뜨려야 한다.
		local boss = F.Boss
		local bossLevel = level + 3
		local base = Config.Monster.GetStats(bossLevel)
		local danger = F.ZoneDanger
		stats = {
			Size = 16 + zone * 2,
			MaxHealth = math.floor(base.MaxHealth * 60 * danger.Health[zone]),
			Speed = boss.Speed * danger.Speed[zone],
			ShotDamage = math.max(10, math.floor(base.ShotDamage * 1.5 * danger.Damage[zone])),
			ShotInterval = math.max(0.9, boss.ShotInterval - zone * 0.05),
			ShotSpeed = boss.ShotSpeed,
			Gold = math.floor(boss.Gold * danger.Reward[zone]),
		}
		xpLevel = bossLevel
		text, color, barWidth = string.format("👑 %s의 군주 (구역 %d) · 권장 ⚡%d", F.ZoneNames[zone], zone, F.BossPower[zone] or 0), Color3.fromRGB(255, 120, 120), 360
	else
		-- 구역마다 나오는 몬스터 종류가 다르다 (Config.Field.ZonePools)
		typeKey = MonsterTypes.Pick(F.ZonePools[zone])
		def = MonsterTypes.Defs[typeKey]
		if kind == "Elite" then
			xpLevel = level + 2
			stats = Config.Monster.GetStats(xpLevel)
			MonsterTypes.ApplyDef(typeKey, stats)
			stats.MaxHealth = math.floor(stats.MaxHealth * F.EliteMultiplier)
			stats.Size = stats.Size * 1.5
			stats.Gold *= 4
			text, color, barWidth = string.format("★ 엘리트 Lv.%d %s", xpLevel, def.Name), Color3.fromRGB(255, 220, 90), 190
		else
			xpLevel = level
			stats = Config.Monster.GetStats(level)
			MonsterTypes.ApplyDef(typeKey, stats)
			text, color, barWidth = string.format("Lv.%d %s", level, def.Name), Color3.new(1, 1, 1), 140
		end
		-- 구역 난이도 배율: 구역이 넘어가면 몬스터가 확 강해진다 (체력 / 공격력 / 속도) 대신 보상도 크게 오른다
		local danger = F.ZoneDanger
		stats.MaxHealth = math.floor(stats.MaxHealth * danger.Health[zone])
		stats.ShotDamage = math.max(1, math.floor(stats.ShotDamage * danger.Damage[zone]))
		stats.Speed *= danger.Speed[zone]
		stats.Gold = math.floor(stats.Gold * danger.Reward[zone])
	end

	local x0, x1 = zoneBounds(zone)
	local position
	if kind == "Boss" then
		position = Vector3.new(x1 - 45, floorAt(x1 - 45) + stats.Size / 2, 0)
		if at then -- 튜토리얼 "압도적인 존재": 플레이어 눈앞에서 나타난다
			position = Vector3.new(at.X, floorAt(at.X) + stats.Size / 2, at.Z)
		end
	else
		local spawnX = freeX(math.floor(x0 + F.CampSafe + 40), math.floor(x1 - 25))
		position = Vector3.new(spawnX, floorAt(spawnX) + stats.Size / 2, math.random(-F.Width / 2 + 25, F.Width / 2 - 25))
		if at then -- 습격: 플레이어 주변에 바로 나타난다
			position = Vector3.new(at.X, floorAt(at.X) + stats.Size / 2, at.Z)
		end
	end

	local part
	local weakOrb
	if kind == "Boss" then
		part = Instance.new("Part")
		part.Name = "FieldBoss"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
		part.Anchored = true
		part.CanCollide = false
		part.Position = position
		part.Color = F.ZoneColors[zone]:Lerp(Color3.fromRGB(150, 25, 45), 0.55)
		part.Material = Enum.Material.Neon
		part.Parent = monstersFolder
		Effects.DecorateBoss(part, stats.Size, F.ZoneColors[zone]:Lerp(Color3.fromRGB(255, 120, 70), 0.6))
		-- 약점 구슬: 보스 주위를 도는 노란 구슬. 직접 조준해서 맞히면 3배 치명타 (자동 조준은 몸통을 노린다)
		weakOrb = Instance.new("Part")
		weakOrb.Name = "WeakPoint"
		weakOrb.Shape = Enum.PartType.Ball
		weakOrb.Size = Vector3.new(4.2, 4.2, 4.2)
		weakOrb.Anchored = true
		weakOrb.CanCollide = false
		weakOrb.CanQuery = false
		weakOrb.CanTouch = false
		weakOrb.Color = Color3.fromRGB(255, 235, 80)
		weakOrb.Material = Enum.Material.Neon
		weakOrb.Position = part.Position
		weakOrb.Parent = part
		local orbLight = Instance.new("PointLight")
		orbLight.Color = Color3.fromRGB(255, 235, 80)
		orbLight.Range = 22
		orbLight.Brightness = 2.5
		orbLight.Parent = weakOrb
		local orbGui = Instance.new("BillboardGui")
		orbGui.Size = UDim2.new(0, 70, 0, 28)
		orbGui.StudsOffset = Vector3.new(0, 3.4, 0)
		orbGui.MaxDistance = 120
		orbGui.Parent = weakOrb
		local orbText = Instance.new("TextLabel")
		orbText.Size = UDim2.new(1, 0, 1, 0)
		orbText.BackgroundTransparency = 1
		orbText.Font = Enum.Font.GothamBlack
		orbText.TextScaled = true
		orbText.TextColor3 = Color3.fromRGB(255, 240, 120)
		orbText.TextStrokeTransparency = 0
		orbText.Text = "🎯 약점"
		orbText.Parent = orbGui
		CollectionService:AddTag(part, "Monster")
		CollectionService:AddTag(part, "RadarBoss")
	else
		local baseColor = def.Color:Lerp(F.ZoneColors[zone], 0.2)
		if kind == "Elite" then
			baseColor = def.Color:Lerp(Color3.fromRGB(240, 190, 50), 0.45)
		end
		part = MonsterTypes.Build(typeKey, stats.Size, baseColor, position, monstersFolder)
		part.Name = "FieldMonster"
		if kind == "Elite" then
			CollectionService:AddTag(part, "RadarElite")
		end
	end

	local newData = {
		BossLike = kind == "Boss",
		Zone = zone,
		Kind = kind,
		Level = level,
		XpLevel = xpLevel,
		TypeKey = typeKey,
		Def = def,
		Phase = math.random() * math.pi * 2,
		Stats = stats,
		Health = stats.MaxHealth,
		MaxHealth = stats.MaxHealth,
		HealthFill = createHealthBar(part, text, barWidth, color),
		Home = position,
		NextAttack = os.clock() + stats.ShotInterval,
		NextShot = os.clock() + stats.ShotInterval,
		NextRing = os.clock() + 7,
		BaseColor = part.Color,
		Aggro = false,
		Ambush = ambush == true,
		LastHit = ambush and os.clock() or nil, -- 습격으로 나온 몬스터는 처음부터 플레이어를 노린다
	}
	newData.WeakPart = weakOrb
	monsters[part] = newData
	return part, newData
end

local function fireProjectile(origin, direction, speed, damage, size, color, style)
	local ball = Effects.MakeProjectile(origin, direction, size, color, style)
	ball.Parent = worldFolder

	table.insert(projectiles, {
		Part = ball, Direction = direction.Unit, Speed = speed, Damage = damage,
		Radius = size / 2, Expire = os.clock() + 5,
	})
end

local function rotateY(vector, degrees)
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(vector)
end

local function telegraph(part, data, color, delay, action)
	part.Color = color
	task.delay(delay, function()
		if monsters[part] ~= data then return end
		part.Color = data.BaseColor
		action()
	end)
end

local function dropPosition(part)
	return Vector3.new(part.Position.X, floorAt(part.Position.X), part.Position.Z)
end

-- 공개 이벤트 보스 보상: 충분히 싸운(체력의 3% 이상 피해) 참가자 모두에게 골드 / 경험치 / 티켓 / 전리품
local function rewardEvent(data, part)
	local position = dropPosition(part)
	local rewarded = 0
	for player, damage in pairs(data.Contrib) do
		if player.Parent and damage >= data.MaxHealth * Config.Events.ContribMin then
			rewarded += 1
			player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + data.Stats.Gold)
			player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + 1)
			Level.AddXP(player, Config.Xp.FieldBoss * 1.5)
			Quest.Add(player, "BossKills", 1)
			Quest.Add(player, "Kills", 1)
			Loot.DropFor(player, position, "Event", data.Zone)
			Inventory.AddShards(player, data.Zone, Config.Sets.Imprint.DropEvent)
			notify(player, string.format("⚔ 공개 이벤트 승리! 전리품이 떨어졌어요 (+%d G, 🎫 +1)", data.Stats.Gold))
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		notify(other, string.format("🏆 침공 사령관 격파! (참여 %d명)", rewarded))
	end
end

-- 황금 고블린: 잡으면 골드 대박 + 전리품 3개
local function rewardGoblin(player, data, part)
	local gold = data.Stats.Gold
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	Effects.FloatText(part.Position + Vector3.new(0, 4, 0), string.format("💰 +%d G", gold), Color3.fromRGB(255, 225, 80))
	Effects.Burst(part.Position, Color3.fromRGB(255, 215, 60), 90)
	Level.AddXP(player, Config.Xp.FieldPerMonsterLevel * data.XpLevel * 6)
	local position = dropPosition(part)
	for _ = 1, 3 do
		Loot.DropFor(player, position, "Elite", data.Zone)
	end
	Inventory.AddShards(player, data.Zone, Config.Sets.Imprint.DropGoblin)
	Quest.Add(player, "Kills", 1)
	Quest.Add(player, "GoblinKills", 1)
	notify(player, string.format("💰 황금 고블린 처치! +%d G, 전리품 3개!", gold))
end

-- 구역 관문: 지금 막 열어야 하는 구역(ClearedZone+1)에서 몬스터를 처치하면 진행도가 오르고, 다 채우면 다음 구역이 열린다
local function gateProgress(player, data)
	local cleared = player:GetAttribute("ClearedZone") or 0
	local frontier = cleared + 1
	local needed = F.Gate.KillsNeeded[frontier]
	if not needed or data.Zone ~= frontier then return end
	local weight = data.Kind == "Elite" and F.Gate.EliteWeight or (data.Kind == "Boss" and F.Gate.BossWeight or 1)
	local kills = (player:GetAttribute("GateKills") or 0) + weight
	if data.Kind == "Boss" then
		player:SetAttribute("GateBossDone", true)
	end
	if kills < needed or not player:GetAttribute("GateBossDone") then
		-- 처치 수를 채워도 구역 보스를 쓰러뜨리지 않으면 관문이 안 열린다
		local capped = math.min(kills, needed)
		if kills >= needed and not player:GetAttribute("GateBossDone") and (player:GetAttribute("GateKills") or 0) < needed then
			notify(player, string.format("👑 처치 수를 채웠어요! 이제 구역 %d의 군주를 쓰러뜨리면 관문이 열려요!", frontier))
		end
		player:SetAttribute("GateKills", capped)
		return
	end
	player:SetAttribute("GateBossDone", false)
	player:SetAttribute("GateKills", 0)
	player:SetAttribute("ClearedZone", frontier)
	local gold = F.Gate.RewardGold * frontier
	local tickets = F.Gate.RewardTickets + (frontier >= 3 and 1 or 0)
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + tickets)
	local nextSet = Config.Sets[Config.Sets.ZoneKeys[frontier + 1]]
	notify(player, string.format("🔓 구역 %d 관문 개방! 보상 💰%d G · 🎫%d장  — %s · %s 에서만 %s %s 세트 장비가 나와요!", frontier + 1, gold, tickets, F.ZoneNames[frontier + 1], F.ZoneNames[frontier + 1], nextSet.Icon, nextSet.Name))
	local root = getAliveParts(player)
	if root then
		Effects.Burst(root.Position, Color3.fromRGB(255, 225, 100), 60)
	end
end

local function reward(player, data, part)
	if data.Kind == "Goblin" then
		rewardGoblin(player, data, part)
		return
	end
	if data.Kind == "Event" then
		rewardEvent(data, part)
		return
	end

	local gold = math.floor(data.Stats.Gold * (Config.IsGoldenTime() and Config.Golden.GoldMult or 1) + 0.5)
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2, 0), string.format("+%d G", gold), Color3.fromRGB(255, 220, 90))

	local xp
	if data.Kind == "Boss" then
		xp = Config.Xp.FieldBoss
	else
		xp = Config.Xp.FieldPerMonsterLevel * data.XpLevel * (data.Kind == "Elite" and Config.Xp.EliteMult or 1)
	end
	Level.AddXP(player, xp)

	gateProgress(player, data)
	Quest.Add(player, "Kills", 1)
	if data.Kind == "Elite" then
		Quest.Add(player, "EliteKills", 1)
	elseif data.Kind == "Boss" then
		Quest.Add(player, "BossKills", 1)
	else
		Quest.Add(player, "FieldKills", 1)
	end

	-- 세트 조각: 그 구역 몬스터에게서만 나온다 (뽑기 장비를 세트 장비로 바꾸는 재료)
	do
		local imprint = Config.Sets.Imprint
		local amount = 0
		if data.Kind == "Boss" then
			amount = imprint.DropBoss
		elseif data.Kind == "Elite" then
			amount = math.random(imprint.DropElite[1], imprint.DropElite[2])
		elseif math.random() < imprint.DropNormal then
			amount = 1
		end
		if amount > 0 then
			Inventory.AddShards(player, data.Zone, amount)
			Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0), string.format("🔹 세트 조각 +%d", amount), Color3.fromRGB(150, 220, 255))
		end
	end

	-- 장비 전리품 (개인 전리품: 처치한 본인에게만 보임)
	if data.Kind ~= "Boss" then
		Loot.DropFor(player, dropPosition(part), data.Kind, data.Zone)
	end

	if data.Kind == "Elite" and math.random() < F.EliteTicketChance then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + 1)
		notify(player, "🎫 엘리트에게서 장비 뽑기 티켓을 얻었어요!")
	elseif data.Kind == "Boss" then
		local bossPosition = part.Position
		for _, other in ipairs(Players:GetPlayers()) do
			local root = getAliveParts(other)
			if other:GetAttribute("Zone") == "Field" and root and (root.Position - bossPosition).Magnitude <= 160 then
				other:SetAttribute("Tickets", (other:GetAttribute("Tickets") or 0) + F.BossTickets)
				Loot.DropFor(other, dropPosition(part), "Boss", data.Zone)
				if other ~= player then
					Quest.Add(other, "BossKills", 1)
					Level.AddXP(other, Config.Xp.FieldBoss)
				end
				notify(other, string.format("👑 필드 보스 처치! 티켓 +%d, 전리품이 떨어졌어요", F.BossTickets))
			end
		end
	end
end

local function killMonster(player, part, data)
	monsters[part] = nil
	Effects.Burst(part.Position, part.Color, data.Kind == "Boss" and 80 or 22)
	part:Destroy()
	Combo.Kill(player)
	reward(player, data, part)
	-- 처치 연출: 금화가 사방으로 튄다
	Effects.Burst(part.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 215, 90), data.Kind == "Boss" and 60 or 14)

	local zone, kind = data.Zone, data.Kind
	if data.Ambush then return end -- 습격 몬스터는 다시 생기지 않는다
	if kind == "Goblin" then return end -- 다시 나타나지 않는다 (다음 출현은 타이머)
	if kind == "Event" then
		activeEvent = nil -- 이벤트 보스는 다시 나타나지 않는다
		return
	end
	task.delay(kind == "Boss" and F.BossRespawn or F.RespawnTime, function()
		spawnMonster(zone, kind)
	end)
end

------------------------------------------------------------
-- 플레이어 공격 (판정은 서버에서). 필드 밖이면 nil
------------------------------------------------------------
-- 범위 피해 (스킬용). 맞은 위치 목록 반환
function Field.TargetsIn(player, center, radius, limit)
	if player:GetAttribute("Zone") ~= "Field" then return nil end
	local list = {}
	for part in pairs(monsters) do
		if part.Parent and (part.Position - center).Magnitude <= radius + part.Size.X / 2 and canHitZone(player, part.Position.X) then
			table.insert(list, part)
		end
	end
	table.sort(list, function(a, b) return (a.Position - center).Magnitude < (b.Position - center).Magnitude end)
	while #list > (limit or 12) do table.remove(list) end
	return list
end

function Field.HitPart(player, part, damage)
	local data = monsters[part]
	if not data or not part.Parent then return false end
	if not canHitZone(player, part.Position.X) then return false end
	if data.Invincible then damage = 1 end
	data.Health -= damage
	if data.Invincible then data.Health = math.max(data.Health, data.MaxHealth * 0.08) end
	data.LastHit = os.clock()
	if data.Contrib then
		data.Contrib[player] = (data.Contrib[player] or 0) + damage
	end
	data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
	Effects.DamageNumber(part.Position, damage, false)
	if data.Health <= 0 then
		killMonster(player, part, data)
	end
	return true
end

function Field.AreaDamage(player, center, radius, damage)
	if player:GetAttribute("Zone") ~= "Field" then return nil end
	local targets = {}
	for part, data in pairs(monsters) do
		if part.Parent and (part.Position - center).Magnitude <= radius + part.Size.X / 2 and canHitZone(player, part.Position.X) then
			table.insert(targets, { Part = part, Data = data })
		end
	end
	local positions = {}
	for _, target in ipairs(targets) do
		local data = target.Data
		if monsters[target.Part] == data then
			table.insert(positions, target.Part.Position)
			if data.Invincible then damage = 1 end
			data.Health -= damage
			if data.Invincible then data.Health = math.max(data.Health, data.MaxHealth * 0.08) end
			data.LastHit = os.clock()
			if data.Contrib then
				data.Contrib[player] = (data.Contrib[player] or 0) + damage
			end
			data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
			Effects.DamageNumber(target.Part.Position, damage, false)
			if data.Health <= 0 then
				killMonster(player, target.Part, data)
			end
		end
	end
	return positions
end

function Field.Shoot(player, origin, direction)
	if player:GetAttribute("Zone") ~= "Field" or not monstersFolder then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { monstersFolder }

	local range = Config.GetPlayerWeapon(player).Range
	local result = workspace:Raycast(origin, direction * range, params)
	local endPosition = result and result.Position or (origin + direction * range)
	-- 도중에 벽이 있으면 거기서 멈추고 맞히지 못한다
	local clear, stopAt = segmentClear(origin, endPosition)
	if not clear then
		return stopAt
	end

	local data = result and monsters[result.Instance]
	if data and not canHitZone(player, result.Instance.Position.X) then
		return endPosition -- 닫힌 관문 너머: 탄이 벽에 막힌다
	end
	if data then
		player:SetAttribute("HitTick", (player:GetAttribute("HitTick") or 0) + 1) -- 궁극기 게이지는 실제로 맞혔을 때만 찬다
		local damage, isCrit = Dungeon.ComputeDamage(player)
		if data.Invincible then damage, isCrit = 1, false end -- 최후의 군주: 맞는 느낌만 (피해는 1)
		-- 약점 구슬: 탄이 지나간 선이 구슬에 닿으면 3배 치명타 + 데드아이 게이지
		if data.WeakPart and data.WeakPart.Parent and not data.Invincible then
			local ab = result.Position - origin
			local t = math.clamp((data.WeakPart.Position - origin):Dot(ab) / math.max(ab:Dot(ab), 0.001), 0, 1)
			if (origin + ab * t - data.WeakPart.Position).Magnitude <= data.WeakPart.Size.X * 0.8 then
				damage = math.floor(damage * 3)
				isCrit = true
				player:SetAttribute("UltCharge", math.min(Config.Skills.Ult.Cost, (player:GetAttribute("UltCharge") or 0) + 6))
				Effects.FloatText(data.WeakPart.Position + Vector3.new(0, 3, 0), "🎯 약점 명중!", Color3.fromRGB(255, 240, 90))
				Effects.Burst(data.WeakPart.Position, Color3.fromRGB(255, 235, 80), 24)
			end
		end
		-- 로켓 런처 / 플라즈마 캐논: 맞은 곳 주변 적에게도 피해
		local splash = Config.GetPlayerWeapon(player).Splash
		if splash then
			for otherPart, otherData in pairs(monsters) do
				if otherPart ~= result.Instance and otherPart.Parent and not otherData.Goblin
					and (otherPart.Position - result.Position).Magnitude <= splash + otherPart.Size.X / 2 then
					local splashDamage = math.max(1, math.floor(damage * 0.5))
					otherData.Health -= splashDamage
					otherData.LastHit = os.clock()
					if otherData.Contrib then
						otherData.Contrib[player] = (otherData.Contrib[player] or 0) + splashDamage
					end
					otherData.HealthFill.Size = UDim2.new(math.max(otherData.Health, 0) / otherData.MaxHealth, 0, 1, 0)
					Effects.DamageNumber(otherPart.Position, splashDamage, false)
					if otherData.Health <= 0 then
						killMonster(player, otherPart, otherData)
					end
				end
			end
			Effects.Burst(result.Position, Color3.fromRGB(255, 160, 60), 40)
		end
		-- 무리 어그로: 처음 맞은 몬스터 주변 몬스터들이 같이 달려든다 (한 마리 건드리면 떼로 몰려온다)
		if not data.LastHit or os.clock() - data.LastHit > 8 then
			local woken = 0
			for otherPart, otherData in pairs(monsters) do
				if woken >= 8 then break end
				if otherData ~= data and otherPart.Parent and not otherData.BossLike and (otherPart.Position - result.Instance.Position).Magnitude < 38 then
					otherData.LastHit = os.clock()
					woken += 1
				end
			end
		end
		-- 타격감: 맞으면 살짝 뒤로 밀린다
		if not data.BossLike and data.Kind ~= "Event" then
			local away = Vector3.new(result.Instance.Position.X - origin.X, 0, result.Instance.Position.Z - origin.Z)
			if away.Magnitude > 0.1 then
				local pushed = result.Instance.Position + away.Unit * 1.3
				if walkableAt(pushed.X, pushed.Z) then
					result.Instance.Position = pushed
				end
			end
		end
		data.Health -= damage
		data.LastHit = os.clock() -- 맞은 몬스터는 멀리서 맞아도 깨어나 반응하고, 한동안 체력을 되찾지 않는다
		if data.Contrib then
			data.Contrib[player] = (data.Contrib[player] or 0) + damage
		end
		data.HealthFill.Size = UDim2.new(math.max(data.Health, 0) / data.MaxHealth, 0, 1, 0)
		Effects.DamageNumber(result.Position, damage, isCrit)
		Effects.Hit(player, result.Instance, isCrit, data.Health <= 0)
		if data.Health <= 0 then
			killMonster(player, result.Instance, data)
		end
	end
	return endPosition
end

------------------------------------------------------------
-- 매 프레임: 몬스터 AI / 투사체 / 구역 갱신
------------------------------------------------------------
-- 몬스터 AI(MonsterTypes)가 필드 환경을 다루는 데 쓰는 함수들
local fieldCtx = {
	FloorY = TOP,
	GroundY = function(x) return floorAt(x) end, -- 층 지형에 맞춰 몬스터 높이를 잡는다
	Walkable = walkableAt,
	LineOfSight = function(a, b)
		return (segmentClear(a, b))
	end,
	-- 꺾임 벽이 막고 있으면 그 벽의 틈(위 / 아래 가장자리)을 먼저 지나가도록 안내한다
	NextStep = function(_, from, to)
		local clear, blockedAt = segmentClear(from, to)
		if clear then return nil end
		local half = F.Width / 2
		for _, rect in ipairs(baffleRects) do
			if not rect.Solid and blockedAt.X >= rect.X0 - 6 and blockedAt.X <= rect.X1 + 6 then
				local gapZ
				if rect.Z1 < half - 1 then
					gapZ = (rect.Z1 + half) / 2 -- 벽 위쪽 끝에 틈
				else
					gapZ = (-half + rect.Z0) / 2 -- 벽 아래쪽 끝에 틈
				end
				return Vector3.new((rect.X0 + rect.X1) / 2, from.Y, gapZ)
			end
		end
		return nil
	end,
	GetTarget = nearestFieldPlayer,
	Fire = function(origin, direction, speed, damage, size, color, style)
		fireProjectile(origin, direction, speed, damage, size, color, style)
	end,
	Players = function()
		local list = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				local root, humanoid = getAliveParts(player)
				if root and not isSafe(root.Position) then
					table.insert(list, { Root = root, Humanoid = humanoid })
				end
			end
		end
		return list
	end,
	Alive = function(part, data)
		return monsters[part] == data
	end,
	Kill = function(part, data) -- 자폭 등 보상 없이 사라짐 (다시 나타남)
		if monsters[part] ~= data then return end
		monsters[part] = nil
		part:Destroy()
		task.delay(F.RespawnTime, function()
			spawnMonster(data.Zone, data.Kind)
		end)
	end,
}

-- 황금 고블린 소환: 구역 하나에 나타나 플레이어에게서 도망친다. 일정 시간이 지나면 사라진다.
local function spawnGoblin(zone)
	local level = F.GetZoneLevel(zone)
	local base = Config.Monster.GetStats(level)
	local stats = {
		Size = 7, MaxHealth = base.MaxHealth * 7, Speed = 26, ShotDamage = 0, ShotInterval = 99, ShotSpeed = 0,
		Gold = base.Gold * 40,
	}
	local x0, x1 = zoneBounds(zone)
	local goblinX = freeX(math.floor(x0 + F.CampSafe + 60), math.floor(x1 - 40))
	local position = Vector3.new(goblinX, floorAt(goblinX) + stats.Size / 2, math.random(-F.Width / 2 + 30, F.Width / 2 - 30))
	local part = Instance.new("Part")
	part.Name = "GoldenGoblin"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part.Color = Color3.fromRGB(255, 205, 40)
	part.Material = Enum.Material.Neon
	part.Parent = monstersFolder
	CollectionService:AddTag(part, "Monster")
	CollectionService:AddTag(part, "RadarGold")
	local light = Instance.new("PointLight")
	light.Range = 48
	light.Brightness = 3.5
	light.Color = part.Color
	light.Parent = part

	-- 눈에 확 띄게: 하늘까지 닿는 금빛 기둥 + 금화 / 반짝이 입자 + 왕관 + 눈 + 돈자루 + 어디서든 보이는 큰 이름표
	local function piece(shape, size, offset, color, material)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = material
		p.CFrame = part.CFrame * CFrame.new(offset)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = p
		weld.Parent = p
		p.Parent = part
		return p
	end
	local gold = Color3.fromRGB(255, 215, 60)
	local beacon = piece(Enum.PartType.Block, Vector3.new(3, 220, 3), Vector3.new(0, 110, 0), gold, Enum.Material.Neon)
	beacon.Transparency = 0.55
	for i = -1, 1 do
		piece(Enum.PartType.Block, Vector3.new(0.8, 2.6, 0.8), Vector3.new(i * 1.5, stats.Size / 2 + 1, 0), gold, Enum.Material.Neon) -- 왕관 뿔
	end
	piece(Enum.PartType.Block, Vector3.new(4.6, 0.8, 4.6), Vector3.new(0, stats.Size / 2 - 0.2, 0), Color3.fromRGB(255, 240, 150), Enum.Material.Neon) -- 왕관 띠
	for _, side in ipairs({ -1, 1 }) do
		piece(Enum.PartType.Ball, Vector3.new(1.1, 1.1, 1.1), Vector3.new(side * 1.2, 0.6, -stats.Size / 2 + 0.3), Color3.fromRGB(30, 20, 10), Enum.Material.SmoothPlastic)
	end
	piece(Enum.PartType.Ball, Vector3.new(4.2, 4.2, 4.2), Vector3.new(0, -0.5, stats.Size / 2 + 1), Color3.fromRGB(150, 100, 40), Enum.Material.Fabric) -- 돈자루
	local coins = Instance.new("ParticleEmitter")
	coins.Rate = 28
	coins.Lifetime = NumberRange.new(0.8, 1.6)
	coins.Speed = NumberRange.new(4, 9)
	coins.SpreadAngle = Vector2.new(180, 180)
	coins.LightEmission = 1
	coins.Color = ColorSequence.new(gold, Color3.fromRGB(255, 250, 200))
	coins.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	coins.Parent = part
	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(280, 64)
	label.StudsOffset = Vector3.new(0, stats.Size / 2 + 8, 0)
	label.AlwaysOnTop = true
	label.MaxDistance = 700
	label.Parent = part
	local labelText = Instance.new("TextLabel")
	labelText.Size = UDim2.fromScale(1, 1)
	labelText.BackgroundTransparency = 1
	labelText.Text = "💰 황금 고블린!"
	labelText.Font = Enum.Font.GothamBlack
	labelText.TextScaled = true
	labelText.TextColor3 = Color3.fromRGB(255, 232, 100)
	labelText.TextStrokeTransparency = 0
	labelText.Parent = label

	local data = {
		Zone = zone, Kind = "Goblin", Goblin = true, Level = level, XpLevel = level + 2, Stats = stats,
		Health = stats.MaxHealth, MaxHealth = stats.MaxHealth, Contrib = {},
		HealthFill = createHealthBar(part, "💰 황금 고블린", 200, Color3.fromRGB(255, 225, 80)),
		Home = position, Expire = os.clock() + 75, NextShot = math.huge, NextAttack = math.huge, NextRing = math.huge,
		BaseColor = part.Color, Aggro = false, Phase = math.random() * 6,
	}
	monsters[part] = data
	return part, data
end

-- 고블린 이동: 가까운 플레이어에게서 도망 (좌우로 흔들리며)
local function stepGoblin(part, data, dt, now)
	if now > data.Expire then
		monsters[part] = nil
		part:Destroy()
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				notify(player, "💨 황금 고블린이 도망쳐 버렸어요...")
			end
		end
		return
	end
	local target, distance = nearestFieldPlayer(part.Position)
	local flee = Vector3.zero
	if target and distance < 80 then
		local away = Vector3.new(part.Position.X - target.Position.X, 0, part.Position.Z - target.Position.Z)
		if away.Magnitude > 0.1 then
			local side = Vector3.new(-away.Unit.Z, 0, away.Unit.X)
			flee = (away.Unit + side * math.sin(now * 3 + data.Phase) * 0.6).Unit * data.Stats.Speed * dt
		end
	end
	local x0, x1 = zoneBounds(data.Zone)
	local function clampPosition(p)
		local cx = math.clamp(p.X, x0 + F.CampSafe + 10, x1 - 10)
		return Vector3.new(cx, floorAt(cx) + data.Stats.Size / 2 + math.abs(math.sin(now * 6)) * 1.2, math.clamp(p.Z, -F.Width / 2 + 12, F.Width / 2 - 12))
	end
	-- 벽(꺾임 벽 / 절벽 / 경사로 옆)을 뚫지 않는다: 가려는 방향이 막혀 있으면 옆으로 미끄러지거나 다른 방향을 고른다
	local function passable(a, b)
		return walkableAt(b.X, b.Z) and (segmentClear(Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)))
	end
	local position = clampPosition(part.Position + flee)
	if flee.Magnitude > 0 and not passable(part.Position, position) then
		local chosen
		for _, angle in ipairs({ 55, -55, 100, -100, 150, -150 }) do
			local rotated = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(flee)
			local candidate = clampPosition(part.Position + rotated)
			if passable(part.Position, candidate) then
				chosen = candidate
				break
			end
		end
		position = chosen or part.Position
	end
	part.Position = position
end

-- 구역 군주 패턴 (기본 부채꼴 사격 + 전방위 탄막에 더해서 돌려 쓴다): 내려찍기 / 돌진 / 나선 탄막.
-- 체력이 절반 아래면 "격노": 패턴 간격이 짧아지고 한 번에 두 개씩 나온다.
local function playersNear(position, radius)
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" then
			local root, humanoid = getAliveParts(player)
			if root and humanoid.Health > 0 and not isSafe(root.Position) then
				local flat = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
				if flat.Magnitude <= radius then
					table.insert(list, { Root = root, Humanoid = humanoid })
				end
			end
		end
	end
	return list
end

local function bossCue(part, text, color)
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 4, 0), text, color)
end

local function bossSlam(part, data)
	local target = nearestFieldPlayer(part.Position)
	if not target then return end
	bossCue(part, "⚠ 내려찍기!", Color3.fromRGB(255, 120, 80))
	local spots = { Vector3.new(target.Position.X, 0, target.Position.Z) }
	if data.Enraged then
		table.insert(spots, spots[1] + Vector3.new(16, 0, 10))
		table.insert(spots, spots[1] + Vector3.new(-16, 0, -10))
	end
	for _, spot in ipairs(spots) do
		local radius = 12
		local warn = Instance.new("Part")
		warn.Shape = Enum.PartType.Cylinder
		warn.Size = Vector3.new(0.3, radius * 2, radius * 2)
		warn.CFrame = CFrame.new(spot.X, floorAt(spot.X) + 0.3, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
		warn.Anchored = true
		warn.CanCollide = false
		warn.CanQuery = false
		warn.Material = Enum.Material.Neon
		warn.Color = Color3.fromRGB(255, 50, 50)
		warn.Transparency = 0.55
		warn.Parent = worldFolder
		TweenService:Create(warn, TweenInfo.new(1.2), { Transparency = 0.1 }):Play()
		task.delay(1.2, function()
			warn:Destroy()
			if monsters[part] ~= data then return end
			Effects.Burst(Vector3.new(spot.X, floorAt(spot.X) + 2, spot.Z), Color3.fromRGB(255, 140, 70), 60)
			for _, entry in ipairs(playersNear(spot, radius)) do
				entry.Humanoid:TakeDamage(math.floor(data.Stats.ShotDamage * 1.4))
			end
		end)
	end
end

local function bossCharge(part, data)
	local target = nearestFieldPlayer(part.Position)
	if not target then return end
	local direction = Vector3.new(target.Position.X - part.Position.X, 0, target.Position.Z - part.Position.Z)
	if direction.Magnitude < 1 then return end
	direction = direction.Unit
	bossCue(part, "⚠ 돌진!", Color3.fromRGB(255, 200, 70))
	local length = 64
	local warn = Instance.new("Part")
	warn.Size = Vector3.new(10, 0.3, length)
	warn.CFrame = CFrame.lookAt(Vector3.new(part.Position.X, floorAt(part.Position.X) + 0.3, part.Position.Z) + direction * (length / 2), Vector3.new(part.Position.X, floorAt(part.Position.X) + 0.3, part.Position.Z) + direction * length)
	warn.Anchored = true
	warn.CanCollide = false
	warn.CanQuery = false
	warn.Material = Enum.Material.Neon
	warn.Color = Color3.fromRGB(255, 70, 40)
	warn.Transparency = 0.55
	warn.Parent = worldFolder
	TweenService:Create(warn, TweenInfo.new(1.0), { Transparency = 0.1 }):Play()
	data.BusyUntil = os.clock() + 2.0
	task.delay(1.0, function()
		warn:Destroy()
		if monsters[part] ~= data then return end
		local hitOnce = {}
		local radius = data.Stats.Size / 2 + 2
		for _ = 1, 12 do -- 약 0.5초 동안 돌진 (64칸)
			if monsters[part] ~= data then return end
			local nx, nz = part.Position.X + direction.X * length / 12, part.Position.Z + direction.Z * length / 12
			local zx0, zx1 = zoneBounds(data.Zone)
			if not walkableAt(nx, nz, radius) or nx < zx0 + F.CampSafe + radius or nx > zx1 - radius - 4 or math.abs(nz) > F.Width / 2 - radius - 4 then break end
			part.CFrame = CFrame.lookAt(Vector3.new(nx, floorAt(nx) + data.Stats.Size / 2, nz), Vector3.new(nx + direction.X, floorAt(nx) + data.Stats.Size / 2, nz + direction.Z))
			for _, entry in ipairs(playersNear(part.Position, radius + 4)) do
				if not hitOnce[entry.Humanoid] then
					hitOnce[entry.Humanoid] = true
					entry.Humanoid:TakeDamage(math.floor(data.Stats.ShotDamage * 1.6))
					Effects.Burst(entry.Root.Position, Color3.fromRGB(255, 200, 90), 30)
				end
			end
			task.wait(0.04)
		end
	end)
end

local function bossSpiral(part, data)
	bossCue(part, "⚠ 나선 탄막!", Color3.fromRGB(255, 160, 255))
	data.BusyUntil = os.clock() + 0.4
	task.spawn(function()
		local started = os.clock()
		local arms = data.Enraged and 3 or 2
		while os.clock() - started < 2.6 and monsters[part] == data do
			local t = os.clock() - started
			for arm = 0, arms - 1 do
				local angle = t * 3.4 + arm * (math.pi * 2 / arms)
				local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
				fireProjectile(Vector3.new(part.Position.X, floorAt(part.Position.X) + 3, part.Position.Z) + direction * (part.Size.X / 2 + 1), direction, 24, math.floor(data.Stats.ShotDamage * 0.5), 2.2, Color3.fromRGB(255, 120, 220))
			end
			task.wait(0.08)
		end
	end)
end

local bossPatterns = { { Fn = bossSlam, Weight = 3, Name = "slam" }, { Fn = bossCharge, Weight = 2, Name = "charge" }, { Fn = bossSpiral, Weight = 2, Name = "spiral" } }
local function pickBossPattern(data)
	local total = 0
	for _, entry in ipairs(bossPatterns) do
		if entry.Name ~= data.LastPattern then total += entry.Weight end
	end
	local roll = math.random() * total
	for _, entry in ipairs(bossPatterns) do
		if entry.Name ~= data.LastPattern then
			roll -= entry.Weight
			if roll <= 0 then
				return entry
			end
		end
	end
	return bossPatterns[1]
end

local function stepMonsters(dt)
	local now = os.clock()
	for part, data in pairs(monsters) do
		if data.WeakPart and data.WeakPart.Parent then -- 약점 구슬: 보스 몸 주위를 돌며 위아래로 흔들린다
			local radius = part.Size.X / 2 + 3
			local angle = now * 1.5 + data.Phase
			data.WeakPart.Position = part.Position + Vector3.new(math.cos(angle) * radius, math.sin(now * 0.9) * radius * 0.35, math.sin(angle) * radius)
		end
		if data.Static then continue end -- 소환 결투의 군주: 제자리에서 연출만 한다
		if data.Falling then
			-- 공습 낙하병: 낙하산을 펴고 하늘에서 내려온다. 땅에 닿으면 충격으로 주변이 피해를 입고 그때부터 싸운다
			local landY = floorAt(part.Position.X) + data.Stats.Size / 2
			local newY = math.max(landY, part.Position.Y - 48 * dt)
			part.Position = Vector3.new(part.Position.X, newY, part.Position.Z)
			if newY <= landY + 0.01 then
				data.Falling = nil
				local chute = part:FindFirstChild("Chute")
				if chute then chute:Destroy() end
				local at = Vector3.new(part.Position.X, landY, part.Position.Z)
				Effects.Burst(at, Color3.fromRGB(230, 210, 170), 24)
				for _, other in ipairs(Players:GetPlayers()) do
					local otherRoot, humanoid = getAliveParts(other)
					if otherRoot and other:GetAttribute("Zone") == "Field" and not isSafe(otherRoot.Position)
						and (Vector3.new(otherRoot.Position.X, 0, otherRoot.Position.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude < 8 then
						humanoid:TakeDamage(math.max(3, math.floor(data.Stats.ShotDamage * 0.8)))
					end
				end
			end
			continue
		end
		if data.Goblin then
			stepGoblin(part, data, dt, now)
			continue
		end
		local target, distance = nearestFieldPlayer(part.Position)
		local range = data.Aggro and F.LeashRange or F.AggroRange
		local fromHome = (part.Position - data.Home).Magnitude
		-- 최근에 맞았으면(저격 / 장거리 사격 포함) 거리와 상관없이 깨어나서 반응한다
		local recentlyHit = data.LastHit ~= nil and now - data.LastHit < 8

		if target and (distance <= range or recentlyHit) and fromHome <= F.LeashRange * 1.5 then
			data.Aggro = true

			if not data.BossLike then
				-- 일반 몬스터 / 엘리트: 종류별 움직임과 공격
				MonsterTypes.Update(fieldCtx, part, data, dt, now)
			else
				local keepDistance = data.Stats.Size / 2 + 16
				if distance > keepDistance and now >= (data.BusyUntil or 0) then
					local flatTarget = Vector3.new(target.Position.X, part.Position.Y, target.Position.Z)
					local move = flatTarget - part.Position
					if move.Magnitude > 0.1 then
						local step = move.Unit * data.Stats.Speed * dt
						local radius = data.Stats.Size / 2 + 2
						local zx0, zx1 = zoneBounds(data.Zone)
						local nx = math.clamp(part.Position.X + step.X, zx0 + F.CampSafe + radius, zx1 - radius - 4) -- 구역 끝 벽 / 옆 절벽에도 몸이 끼지 않게
						local nz = math.clamp(part.Position.Z + step.Z, -F.Width / 2 + radius + 4, F.Width / 2 - radius - 4)
						if walkableAt(nx, nz, radius) then
							local newPos = Vector3.new(nx, floorAt(nx) + data.Stats.Size / 2, nz)
							part.CFrame = CFrame.lookAt(newPos, Vector3.new(target.Position.X, newPos.Y, target.Position.Z)) -- 항상 플레이어를 바라본다
						end
					end
				end

				if now >= data.NextShot then
					data.NextShot = now + data.Stats.ShotInterval
					telegraph(part, data, Color3.fromRGB(255, 220, 80), 0.4, function()
						local current = nearestFieldPlayer(part.Position)
						if not current then return end
						local direction = current.Position - part.Position
						for _, angle in ipairs({ -20, -10, 0, 10, 20 }) do
							fireProjectile(part.Position, rotateY(direction.Unit, angle), data.Stats.ShotSpeed, data.Stats.ShotDamage, 3, Color3.fromRGB(255, 80, 60))
						end
					end)
				end

				-- 보스: 주기적으로 전방위 탄막
				if now >= data.NextRing then
					data.NextRing = now + 7
					telegraph(part, data, Color3.new(1, 1, 1), 0.8, function()
						for i = 0, 15 do
							local angle = (i / 16) * math.pi * 2
							local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
							fireProjectile(Vector3.new(part.Position.X, floorAt(part.Position.X) + 3, part.Position.Z) + direction * (part.Size.X / 2 + 1), direction, 30, math.floor(data.Stats.ShotDamage * 0.7), 2.4, Color3.fromRGB(255, 180, 60))
						end
					end)
				end

				-- 체력이 절반 아래면 격노
				if not data.Enraged and data.Health / data.MaxHealth <= 0.5 then
					data.Enraged = true
					Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 6, 0), "😡 격노!", Color3.fromRGB(255, 70, 70))
					Effects.Burst(part.Position, Color3.fromRGB(255, 70, 70), 80)
				end
				-- 다양한 패턴: 내려찍기 / 돌진 / 나선 탄막을 번갈아 (격노하면 더 자주, 두 개씩)
				if now >= (data.NextPattern or now + 3) and now >= (data.BusyUntil or 0) then
					data.NextPattern = now + (data.Enraged and 4.2 or 6.5)
					local entry = pickBossPattern(data)
					data.LastPattern = entry.Name
					entry.Fn(part, data)
					if data.Enraged then
						task.delay(1.0, function()
							if monsters[part] == data then
								local second = pickBossPattern(data)
								if second.Name ~= "charge" then second.Fn(part, data) end
							end
						end)
					end
				end
			end
		elseif recentlyHit then
			-- 너무 멀리 끌려 나왔지만 아직 맞고 있는 중: 체력을 회복하지 않고 가만히 있는다
			data.Aggro = true
		else
			-- 목표가 없거나 멀어지면 제자리로 돌아가서 체력을 회복
			data.Aggro = false
			local toHome = Vector3.new(data.Home.X - part.Position.X, 0, data.Home.Z - part.Position.Z)
			if toHome.Magnitude > 1 then
				part.Position += toHome.Unit * data.Stats.Speed * 1.5 * dt
				-- 돌아가는 길에도 층 높이를 따라간다 (경사를 오르내릴 때 땅에 파묻히거나 허공에 뜨지 않게)
				part.Position = Vector3.new(part.Position.X, floorAt(part.Position.X) + data.Stats.Size / 2, part.Position.Z)
			elseif data.Health < data.MaxHealth then
				data.Health = data.MaxHealth
				data.HealthFill.Size = UDim2.new(1, 0, 1, 0)
			end
		end
	end
end

-- 아슬아슬한 회피(NEAR MISS): 대시 중에 탄 / 폭격이 몸 바로 옆을 스치면 보상 - 데드아이 게이지 + 잠깐 동안 공격이 전부 치명타
local nearMissAt = {}
local dashSeenAt = {}
local function isDashing(root, player)
	-- 대시 중이거나 방금(0.6초 안에) 대시했으면 인정한다: 탄이 스치는 순간 대시가 막 끝났어도 NEAR MISS (후한 판정)
	local v = root.AssemblyLinearVelocity
	local now = os.clock()
	if Vector3.new(v.X, 0, v.Z).Magnitude > 50 then
		dashSeenAt[player] = now
	end
	return now - (dashSeenAt[player] or -10) < 0.6
end
local function awardNearMiss(player, root)
	local now = os.clock()
	if now - (nearMissAt[player] or 0) < 0.7 then return end
	local streak = (now - (nearMissAt[player] or 0) < 6) and ((player:GetAttribute("NearMissStreak") or 0) + 1) or 1
	nearMissAt[player] = now
	player:SetAttribute("NearMissStreak", streak)
	local charge = player:GetAttribute("UltCharge") or 0
	player:SetAttribute("UltCharge", math.min(Config.Skills.Ult.Cost, charge + 10 + math.min(streak, 4) * 3))
	player:SetAttribute("NearMissUntil", now + 4) -- 4초 동안 공격이 전부 치명타 (DungeonService.ComputeDamage 가 읽는다)
	local rift = Meta.GetRift(player) -- 처음 한 번만 NEAR MISS 설명 카드를 띄운다 (저장됨)
	local firstTime = rift ~= nil and not rift.Tip
	if rift then rift.Tip = true end
	Effects.FloatText(root.Position + Vector3.new(0, 4, 0), streak > 1 and string.format("NEAR MISS! x%d", streak) or "NEAR MISS!", Color3.fromRGB(120, 255, 255))
	Remotes.Banner:FireClient(player, "NearMiss", { Streak = streak, First = firstTime })
end

local function stepProjectiles(dt)
	local now = os.clock()
	for i = #projectiles, 1, -1 do
		local projectile = projectiles[i]
		projectile.Part.Position += projectile.Direction * projectile.Speed * dt

		local hit = not walkableAt(projectile.Part.Position.X, projectile.Part.Position.Z) -- 벽에 닿은 탄은 사라진다
		for _, player in ipairs(Players:GetPlayers()) do
			if hit then break end
			if player:GetAttribute("Zone") == "Field" then
				local root, humanoid = getAliveParts(player)
				if root and not isSafe(root.Position) then
					local gap = (root.Position - projectile.Part.Position).Magnitude
					if gap < projectile.Radius + 2 then
						humanoid:TakeDamage(projectile.Damage)
						hit = true
						break
					elseif gap < projectile.Radius + 14 and isDashing(root, player) then -- 닿지는 않았지만 아슬아슬하게 스치며 대시
						projectile.NearMissed = projectile.NearMissed or {}
						if not projectile.NearMissed[player] then
							projectile.NearMissed[player] = true
							awardNearMiss(player, root)
						end
					end
				end
			end
		end

		if hit or now > projectile.Expire then
			projectile.Part:Destroy()
			table.remove(projectiles, i)
		end
	end
end

-- x좌표로 로비 / 필드 구역을 판별하고, 가장 멀리 간 구역(MaxZone)을 기록
local lastGateNotice = {}
local lastZoneSeen = {}
local function updateZones()
	for _, player in ipairs(Players:GetPlayers()) do
		local zone = player:GetAttribute("Zone")
		if (zone == "Lobby" or zone == "Field") and not player:GetAttribute("InDoomArena") then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local inField = root.Position.X >= F.StartX - 5 and root.Position.X < F.StartX + F.ZoneLength * F.ZoneCount + 20
				local newZone = inField and "Field" or "Lobby"
				if newZone ~= zone then
					player:SetAttribute("Zone", newZone)
					if newZone == "Field" then
						notify(player, "필드 입장! 동쪽으로 갈수록 몬스터가 강해져요.")
					end
				end

				if inField then
					local fieldZone = zoneOfX(root.Position.X)
					-- 관문이 잠긴 구역에는 못 들어간다: 관문 앞으로 되돌려 보낸다
					local allowed = math.min(F.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1)
					if fieldZone > allowed then
						local lockedX = zoneBounds(allowed + 1)
						player.Character:PivotTo(CFrame.new(lockedX - 12, TOP + 4, root.Position.Z))
						root.AssemblyLinearVelocity = Vector3.zero
						if os.clock() - (lastGateNotice[player] or 0) > 3 then
							lastGateNotice[player] = os.clock()
							notify(player, string.format("🔒 관문이 닫혀 있어요! 구역 %d 몬스터 %d/%d 처치 + 구역의 군주 격파%s",
								allowed, player:GetAttribute("GateKills") or 0, F.Gate.KillsNeeded[allowed] or 0, player:GetAttribute("GateBossDone") and " (군주 ✔)" or ""))
						end
						fieldZone = allowed
					end
					-- 새 구역에 들어서면 큰 경고 배너 (난이도가 얼마나 뛰는지 숫자로 보여준다)
					if fieldZone ~= lastZoneSeen[player] then
						local previous = lastZoneSeen[player] or 0
						lastZoneSeen[player] = fieldZone
						if fieldZone >= 2 and fieldZone > previous then
							local danger = F.ZoneDanger
							Remotes.Banner:FireClient(player, "Zone", {
								Zone = fieldZone, Name = F.ZoneNames[fieldZone], Level = F.GetZoneLevel(fieldZone), Stars = fieldZone,
								HealthMult = danger.Health[fieldZone] / danger.Health[fieldZone - 1], DamageMult = danger.Damage[fieldZone] / danger.Damage[fieldZone - 1],
								RewardMult = danger.Reward[fieldZone] / danger.Reward[fieldZone - 1],
							})
						end
					end
					if fieldZone > (player:GetAttribute("MaxZone") or 0) then
						player:SetAttribute("MaxZone", fieldZone)
						notify(player, string.format("🏔 구역 %d · %s 돌파!", fieldZone, F.ZoneNames[fieldZone]))
					end
				end
			end
		end
	end
end

------------------------------------------------------------
-- 워프 / 부활 (캠프)
------------------------------------------------------------
function Field.ZoneOf(player)
	if player:GetAttribute("Zone") ~= "Field" then return 0 end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and zoneOfX(root.Position.X) or 0
end

-- 필드에서 죽으면 가장 가까웠던 구역의 캠프에서 부활 (로비로 돌아가 다시 걸어오지 않아도 됨)
function Field.RespawnAtCamp(player, character, zone)
	local camp = campCFrames[zone]
	if not camp then return end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root then
		character:PivotTo(camp)
		player:SetAttribute("Zone", "Field")
	end
end

local lastWarp = {}

-- 필드 밖으로 튕겨 나간 플레이어(대시 / 물리 버그로 벽 밖이나 허공)를 마을로 되돌린다
local function rescueOutOfBounds()
	local half = F.Width / 2
	local endX = F.StartX + F.ZoneLength * F.ZoneCount + 60
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" and not player:GetAttribute("InDoomArena") then
			local root = getAliveParts(player)
			if root then
				local p = root.Position
				if p.Y > TOP + 95 or p.Y < TOP - 40 or math.abs(p.Z) > half + 30 or p.X > endX then
					root.AssemblyLinearVelocity = Vector3.zero
					player.Character:PivotTo(lobbySpawn)
					player:SetAttribute("Zone", "Lobby")
					notify(player, "필드 밖으로 튕겨 나가서 마을로 돌아왔어요.")
				end
			end
		end
	end
end

-- zone 0 = 로비, 1~8 = 해당 구역 캠프 (도달한 구역까지만)
local function warp(player, zone)
	local now = os.clock()
	if now - (lastWarp[player] or 0) < 3 then return end
	if typeof(zone) ~= "number" or zone % 1 ~= 0 or zone < 0 or zone > F.ZoneCount then return end
	if player:GetAttribute("Zone") == "Dungeon" then
		notify(player, "던전 안에서는 워프할 수 없어요.")
		return
	end
	local root = getAliveParts(player)
	if not root then return end

	if zone >= 1 and zone > math.max(1, math.min(player:GetAttribute("MaxZone") or 0, (player:GetAttribute("ClearedZone") or 0) + 1)) then
		notify(player, "아직 도달하지 않은 구역이에요. 걸어서 먼저 가보세요!")
		return
	end

	lastWarp[player] = now
	if zone == 0 then
		player.Character:PivotTo(lobbySpawn)
		player:SetAttribute("Zone", "Lobby")
		notify(player, "마을로 돌아왔어요.")
	else
		player.Character:PivotTo(campCFrames[zone])
		player:SetAttribute("Zone", "Field")
		notify(player, string.format("⛺ 구역 %d · %s 캠프로 이동!", zone, F.ZoneNames[zone]))
	end
end

Remotes.Warp.OnServerEvent:Connect(function(player, action, zone)
	if action == "Go" then
		warp(player, zone)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastWarp[player] = nil
end)

------------------------------------------------------------
-- 공개 이벤트: 침공 사령관
------------------------------------------------------------
local function spawnEvent(zone)
	local level = F.GetZoneLevel(zone) + 3
	local base = Config.Monster.GetStats(level)
	local stats = {
		Size = 15, MaxHealth = base.MaxHealth * 80, Speed = 7, ShotDamage = math.floor(base.ShotDamage * 1.3),
		ShotInterval = 1.4, ShotSpeed = 55, Gold = base.Gold * 30,
	}

	local x0, x1 = zoneBounds(zone)
	local eventX = freeX(math.floor(x0 + 200), math.floor(x1 - 80))
	local position = Vector3.new(eventX, floorAt(eventX) + stats.Size / 2, math.random(-F.Width / 2 + 70, F.Width / 2 - 70))

	local part = Instance.new("Part")
	part.Name = "EventBoss"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(stats.Size, stats.Size, stats.Size)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part.Color = Color3.fromRGB(190, 60, 255)
	part.Material = Enum.Material.Neon
	part.Parent = monstersFolder
	CollectionService:AddTag(part, "Monster")
	CollectionService:AddTag(part, "RadarBoss")

	-- 멀리서도 보이는 하늘로 솟는 빛기둥 (보스에 붙어서 같이 움직임)
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(3, 420, 3)
	beam.Color = Color3.fromRGB(200, 90, 255)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.45
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Massless = true
	beam.CFrame = part.CFrame * CFrame.new(0, 210, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = beam
	weld.Parent = beam
	beam.Parent = part

	local data = {
		BossLike = true,
		Kind = "Event",
		Zone = zone,
		Level = level,
		XpLevel = level,
		Stats = stats,
		Health = stats.MaxHealth,
		MaxHealth = stats.MaxHealth,
		HealthFill = createHealthBar(part, string.format("⚔ %s (구역 %d)", Config.Events.Name, zone), 320, Color3.fromRGB(230, 150, 255)),
		Home = position,
		NextAttack = os.clock() + 3,
		NextShot = os.clock() + 3,
		NextRing = os.clock() + 6,
		BaseColor = part.Color,
		Aggro = false,
		Contrib = {},
	}
	monsters[part] = data
	return part, data
end

local function runEvents()
	task.wait(Config.Events.FirstDelay)
	while true do
		-- 필드에 사람이 있을 때만 이벤트를 연다 (도달한 구역 중에서 무작위)
		local maxZone, anyone = 1, false
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				anyone = true
				maxZone = math.max(maxZone, player:GetAttribute("MaxZone") or 1)
			end
		end

		if anyone then
			local zone = math.random(1, math.min(maxZone, F.ZoneCount))
			local part, data = spawnEvent(zone)
			activeEvent = { Part = part, Data = data }
			for _, player in ipairs(Players:GetPlayers()) do
				notify(player, string.format("⚔ [공개 이벤트] 구역 %d · %s 에 %s 출현! 하늘의 보라색 빛기둥을 따라가세요!", zone, F.ZoneNames[zone], Config.Events.Name))
			end

			local expire = os.clock() + Config.Events.Lifetime
			while monsters[part] == data and os.clock() < expire do
				task.wait(1)
			end
			if monsters[part] == data then
				monsters[part] = nil
				part:Destroy()
				activeEvent = nil
				for _, player in ipairs(Players:GetPlayers()) do
					notify(player, "침공 사령관이 사라졌어요...")
				end
			end
		end

		task.wait(math.random(Config.Events.MinInterval, Config.Events.MaxInterval))
	end
end

-- 황금 고블린 출현 타이머: 필드에 누군가 있으면 몇 분마다 한 마리
local function runGoblins()
	task.wait(90)
	while true do
		local maxZone, anyone = 1, false
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				anyone = true
				maxZone = math.max(maxZone, player:GetAttribute("MaxZone") or 1)
			end
		end
		if anyone then
			local zone = math.random(1, math.min(maxZone, F.ZoneCount))
			local part, data = spawnGoblin(zone)
			for _, player in ipairs(Players:GetPlayers()) do
				if player:GetAttribute("Zone") == "Field" then
					notify(player, string.format("💰 구역 %d · %s 에 황금 고블린 출현! 잡으면 대박! (75초)", zone, F.ZoneNames[zone]))
				end
			end
			while monsters[part] == data do
				task.wait(1)
			end
		end
		task.wait(math.random(150, 300))
	end
end

-- 공습: 경보가 울리고 하늘을 가로지르는 폭격기가 지나가며 폭탄을 떨어뜨린다. 바닥에 붉은 원이 먼저 나타나니 그 밖으로 피한다.
local function airRaid(player, zone)
	local root = getAliveParts(player)
	if not root then return end
	notify(player, "🚨 공습 경보! 하늘의 폭격기를 보세요 — 바닥의 붉은 원에서 벗어나세요!")
	player:SetAttribute("ShakeStrength", 0.35)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))

	local level = F.GetZoneLevel(zone)
	local stats = Config.Monster.GetStats(level)
	local damage = math.max(5, math.floor(stats.ShotDamage * F.ZoneDanger.Damage[zone] * 1.8))
	local center = root.Position
	local heading = math.random() < 0.5 and 1 or -1
	local axis = Vector3.new(math.random() < 0.5 and 1 or 0, 0, 0)
	if axis.Magnitude == 0 then axis = Vector3.new(0, 0, 1) end
	axis *= heading
	local lateral = Vector3.new(-axis.Z, 0, axis.X)
	local altitude = 85
	local startPos = Vector3.new(center.X, center.Y + altitude, center.Z) - axis * 170
	local speed = 95

	-- 폭격기: 어두운 몸체 + 날개 + 깜빡이는 붉은 등
	local plane = Instance.new("Model")
	plane.Name = "RaidBomber"
	local function body(size, offset, color, material)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.CFrame = CFrame.lookAt(startPos, startPos + axis) * CFrame.new(offset)
		p.Parent = plane
		return p
	end
	local hull = body(Vector3.new(5, 4, 22), Vector3.zero, Color3.fromRGB(45, 48, 58))
	body(Vector3.new(30, 0.8, 7), Vector3.new(0, 0, 2), Color3.fromRGB(55, 58, 70))
	body(Vector3.new(10, 0.8, 4), Vector3.new(0, 1.2, 10), Color3.fromRGB(55, 58, 70))
	body(Vector3.new(0.8, 5, 4), Vector3.new(0, 2.5, 10), Color3.fromRGB(55, 58, 70))
	for _, side in ipairs({ -1, 1 }) do
		local light = body(Vector3.new(1.2, 1.2, 1.2), Vector3.new(side * 14.5, 0.6, 1), Color3.fromRGB(255, 60, 50), Enum.Material.Neon)
		local glow = Instance.new("PointLight")
		glow.Range = 30
		glow.Color = Color3.fromRGB(255, 60, 50)
		glow.Brightness = 3
		glow.Parent = light
	end
	plane.PrimaryPart = hull
	plane.Parent = workspace
	Debris:AddItem(plane, 8)

	-- 폭격기가 지나가는 중간에 낙하산 부대가 투하된다: 플레이어 주변 하늘에서 몬스터가 내려온다
	task.delay(1.3, function()
		local target = getAliveParts(player)
		if not target then return end
		local count = 3 + math.min(4, zone // 2 + 1)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local distance = 16 + math.random() * 30
			local at = target.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			if walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == zone then
				local part, data = spawnMonster(zone, "Normal", at, true)
				if part and data then
					data.Falling = true
					local drop = floorAt(at.X) + 90
					part.Position = Vector3.new(at.X, drop, at.Z)
					local canopy = Instance.new("Part")
					canopy.Name = "Chute"
					canopy.Anchored, canopy.CanCollide, canopy.CanQuery, canopy.CanTouch, canopy.Massless = false, false, false, false, true
					canopy.Shape = Enum.PartType.Ball
					canopy.Size = Vector3.new(data.Stats.Size * 2.4, data.Stats.Size * 1.2, data.Stats.Size * 2.4)
					canopy.Color = Color3.fromRGB(235, 90, 70)
					canopy.Material = Enum.Material.Fabric
					canopy.CFrame = part.CFrame * CFrame.new(0, data.Stats.Size * 1.6, 0)
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = part
					weld.Part1 = canopy
					weld.Parent = canopy
					canopy.Parent = part
				end
			end
		end
	end)

	local started = os.clock()
	local travel = 340 / speed
	local bombs = 8 + math.min(6, zone)
	local dropped = 0
	task.spawn(function()
		while os.clock() - started < travel and plane.Parent do
			local t = (os.clock() - started) / travel
			plane:PivotTo(CFrame.lookAt(startPos + axis * 340 * t, startPos + axis * 340 * t + axis))
			-- 비행 구간의 가운데 부분에서 폭탄을 떨어뜨린다
			local due = math.floor(math.clamp((t - 0.25) / 0.5, 0, 1) * bombs + 0.001)
			while dropped < due do
				dropped += 1
				local planePos = startPos + axis * 340 * t
				local lateralOffset = (math.random() - 0.5) * 70
				local spot = Vector3.new(planePos.X, 0, planePos.Z) + lateral * lateralOffset + axis * 18
				if dropped % 3 == 1 then -- 세 발에 한 발은 플레이어 위치를 노린다
					local target = getAliveParts(player)
					if target then spot = Vector3.new(target.Position.X, 0, target.Position.Z) end
				end
				local ground = floorAt(spot.X)
				local radius = 11
				local marker = Instance.new("Part")
				marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch = true, false, false, false
				marker.Shape = Enum.PartType.Cylinder
				marker.Material = Enum.Material.Neon
				marker.Color = Color3.fromRGB(255, 50, 40)
				marker.Transparency = 0.55
				marker.Size = Vector3.new(0.4, radius * 2, radius * 2)
				marker.CFrame = CFrame.new(spot.X, ground + 0.4, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
				marker.Parent = workspace
				local fuse = 1.5
				local bomb = Instance.new("Part")
				bomb.Anchored, bomb.CanCollide, bomb.CanQuery, bomb.CanTouch = true, false, false, false
				bomb.Shape = Enum.PartType.Ball
				bomb.Material = Enum.Material.Neon
				bomb.Color = Color3.fromRGB(255, 140, 50)
				bomb.Size = Vector3.new(3.2, 3.2, 3.2)
				bomb.Position = planePos - Vector3.new(0, 2, 0)
				bomb.Parent = workspace
				TweenService:Create(bomb, TweenInfo.new(fuse, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = Vector3.new(spot.X, ground + 1.5, spot.Z) }):Play()
				local trail = Instance.new("ParticleEmitter")
				trail.Rate = 40
				trail.Lifetime = NumberRange.new(0.3, 0.6)
				trail.Speed = NumberRange.new(0, 2)
				trail.LightEmission = 1
				trail.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 80, 30))
				trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0) })
				trail.Parent = bomb
				task.delay(fuse, function()
					bomb:Destroy()
					marker:Destroy()
					local at = Vector3.new(spot.X, ground, spot.Z)
					Effects.Burst(at + Vector3.new(0, 2, 0), Color3.fromRGB(255, 140, 50), 36)
					local boom = Instance.new("Part")
					boom.Anchored, boom.CanCollide, boom.CanQuery, boom.CanTouch = true, false, false, false
					boom.Shape = Enum.PartType.Ball
					boom.Material = Enum.Material.Neon
					boom.Color = Color3.fromRGB(255, 170, 70)
					boom.Transparency = 0.3
					boom.Size = Vector3.new(2, 2, 2)
					boom.Position = at + Vector3.new(0, 2, 0)
					boom.Parent = workspace
					TweenService:Create(boom, TweenInfo.new(0.4), { Size = Vector3.new(radius * 2.2, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
					Debris:AddItem(boom, 0.5)
					SoundBank.Play(boom, "Boom", { Volume = 0.9 })
					for _, other in ipairs(Players:GetPlayers()) do
						local otherRoot, humanoid = getAliveParts(other)
						if otherRoot and other:GetAttribute("Zone") == "Field" and not isSafe(otherRoot.Position) then
							local flat = Vector3.new(otherRoot.Position.X - at.X, 0, otherRoot.Position.Z - at.Z)
							if flat.Magnitude <= radius and otherRoot.Position.Y - ground < 8 then
								humanoid:TakeDamage(damage)
							end
						end
					end
				end)
			end
			task.wait(0.03)
		end
		plane:Destroy()
	end)
end

-- 보스(구역 군주 / 이벤트 보스)가 나를 노리고 있으면 BossFight 가 켜진다 -> 클라이언트가 음악을 던전(전투) 곡으로 바꾼다
local powerWarnedAt = {}
local weakTipShown = {}
local function updateBossFight()
	for _, player in ipairs(Players:GetPlayers()) do
		local fighting = false
		local bossZone
		if player:GetAttribute("Zone") == "Field" then
			local root = getAliveParts(player)
			if root then
				for part, data in pairs(monsters) do
					if data.BossLike and not data.Static and data.Aggro and part.Parent and (part.Position - root.Position).Magnitude < 150 then
						fighting = true
						bossZone = data.Zone
						break
					end
				end
			end
		end
		if player:GetAttribute("BossFight") ~= fighting then
			player:SetAttribute("BossFight", fighting)
			if fighting and bossZone and not player:GetAttribute("TutorialActive") then
				-- 군주를 만나면: 전투력이 모자라면 무기 강화를 권하고(골드 사용처), 처음이면 약점 구슬 사용법을 알려준다
				local recommended = F.BossPower[bossZone] or 0
				local power = player:GetAttribute("Power") or 0
				if power < recommended * 0.85 and os.clock() - (powerWarnedAt[player] or -999) > 90 then
					powerWarnedAt[player] = os.clock()
					Remotes.Tutorial:FireClient(player, "Prompt", { Key = "⚒", Title = string.format("전투력 부족! (내 %d / 권장 %d)", power, recommended),
						Text = "마을 대장간에서 골드로 무기를 강화하면 전투력이 올라요. 강화하고 다시 도전하면 훨씬 쉬워요!", Duration = 9 })
				elseif not weakTipShown[player] then
					weakTipShown[player] = true
					Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🎯", Title = "약점을 노려라!",
						Text = "보스 주위를 도는 노란 구슬을 직접 조준해서 맞히면 3배 치명타 + 데드아이 게이지!", Duration = 8 })
				end
			end
		end
	end
end

-- 시체 청소: 몬스터 표(monsters)에 없는데 필드에 남은 몬스터 부품(죽었는데 안 지워진 것)을 지운다
local function cleanOrphans()
	if not monstersFolder then return end
	for _, child in ipairs(monstersFolder:GetChildren()) do
		if child:IsA("BasePart") and not monsters[child] then
			child:Destroy()
		end
	end
end

-- 튜토리얼 "압도적인 습격": 첫 필드 방문 때 잠깐 싸우게 한 뒤, 사방에서 훨씬 강한 몬스터 떼가 몰려와 필연적으로 쓰러지게 한다.
-- (쓰러지면 마을로 돌아가고, 다음 미션이 "훈련 -> 던전 -> 10연 뽑기 -> 다시 필드(이제 쉽다)" 로 이어진다)
local doomTimers = {}
-- 최후의 군주 모델: 갑옷 몸통 + 뿔 달린 머리 + 후광 + 칼날 날개 + 거대한 주먹 + 가슴 코어. 몸통(Body)만 맞는다(나머지는 장식).
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local function shakeScreen(player, strength)
	player:SetAttribute("ShakeStrength", strength)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
end

local function buildDoomLord(parent)
	local S = 1.7
	local model = Instance.new("Model")
	model.Name = "DoomLord"
	model.Parent = parent
	local parts = {} -- { Part, Rel }
	local function add(size, rel, color, material, transparency, shape)
		local part = Instance.new("Part")
		part.Size = size * S
		part.Color = color
		part.Material = material or Enum.Material.Metal
		part.Transparency = transparency or 0
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		if shape then part.Shape = shape end
		part.Parent = model
		table.insert(parts, { Part = part, Rel = CFrame.new(rel.Position * S) * (rel - rel.Position) })
		return part
	end
	local dark, steel, red = rgb(26, 12, 22), rgb(60, 52, 70), rgb(255, 50, 60)
	local body = add(Vector3.new(12, 20, 7), CFrame.new(0, 0, 0), dark, Enum.Material.Metal)
	body.CanQuery = true
	body.Name = "Body"
	add(Vector3.new(8, 6, 5), CFrame.new(0, -12, 0), dark) -- 허리 아래로 좁아지는 하체
	add(Vector3.new(4, 7, 3), CFrame.new(0, -18, 0), steel)
	add(Vector3.new(5, 5, 5), CFrame.new(0, 4, -4.2) * CFrame.Angles(math.rad(45), math.rad(45), 0), red, Enum.Material.Neon) -- 가슴 코어
	add(Vector3.new(11, 1, 1), CFrame.new(0, 9, -3.8), steel)
	add(Vector3.new(11, 1, 1), CFrame.new(0, -3, -3.8), steel)
	-- 머리 + 눈 + 뿔 + 왕관
	add(Vector3.new(6.5, 6.5, 6.5), CFrame.new(0, 14, 0), rgb(18, 8, 16))
	for _, side in ipairs({ -1, 1 }) do
		add(Vector3.new(3, 0.9, 0.6), CFrame.new(side * 1.7, 14.6, -3.3) * CFrame.Angles(0, 0, math.rad(side * 18)), rgb(255, 230, 90), Enum.Material.Neon)
		add(Vector3.new(1.4, 13, 1.4), CFrame.new(side * 4.2, 21, 0) * CFrame.Angles(0, 0, math.rad(side * -28)), rgb(230, 220, 205), Enum.Material.SmoothPlastic)
		add(Vector3.new(1.2, 7, 1.2), CFrame.new(side * 9, 27, 0) * CFrame.Angles(0, 0, math.rad(side * -58)), rgb(230, 220, 205), Enum.Material.SmoothPlastic)
		-- 어깨 갑옷 + 가시
		add(Vector3.new(8, 4, 8), CFrame.new(side * 9.5, 9, 0), steel)
		for k = 0, 2 do
			add(Vector3.new(1.4, 8 - k * 1.5, 1.4), CFrame.new(side * (7.5 + k * 2.2), 13 + k * 0.8, 0) * CFrame.Angles(0, 0, math.rad(side * (-15 - k * 14))), red, Enum.Material.Neon)
		end
		-- 팔 + 거대한 주먹 + 손목 불꽃줄
		add(Vector3.new(4, 16, 4), CFrame.new(side * 12, -1, 0), dark)
		add(Vector3.new(7.5, 7.5, 7.5), CFrame.new(side * 12, -11, -1), steel)
		add(Vector3.new(8, 0.8, 8), CFrame.new(side * 12, -8, -1), red, Enum.Material.Neon)
		-- 칼날 날개 (등 뒤로 부챗살)
		for k = 0, 3 do
			add(Vector3.new(1, 22 - k * 3, 5), CFrame.new(side * (8 + k * 3.4), 6 + k * 0.5, 7) * CFrame.Angles(math.rad(-10), math.rad(side * -12), math.rad(side * (-22 - k * 14))), rgb(90, 20, 40), Enum.Material.Metal)
			add(Vector3.new(0.4, 20 - k * 3, 1.2), CFrame.new(side * (8 + k * 3.4), 6 + k * 0.5, 4.6) * CFrame.Angles(math.rad(-10), math.rad(side * -12), math.rad(side * (-22 - k * 14))), red, Enum.Material.Neon, 0.15)
		end
	end
	-- 후광 (머리 뒤 큰 고리 두 겹)
	add(Vector3.new(0.7, 30, 30), CFrame.new(0, 15, 8) * CFrame.Angles(0, math.rad(90), 0), red, Enum.Material.Neon, 0.25, Enum.PartType.Cylinder)
	add(Vector3.new(0.5, 38, 38), CFrame.new(0, 15, 9) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 150, 60), Enum.Material.Neon, 0.5, Enum.PartType.Cylinder)
	-- 주변을 도는 칼날 4개
	local orbit = {}
	for k = 1, 4 do
		local blade = add(Vector3.new(1.2, 8, 2.4), CFrame.new(), red, Enum.Material.Neon, 0.1)
		table.insert(orbit, blade)
	end

	local core = body
	local aura = Instance.new("ParticleEmitter")
	aura.Rate = 40
	aura.Lifetime = NumberRange.new(1, 2)
	aura.Speed = NumberRange.new(4, 10)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.LightEmission = 1
	aura.Color = ColorSequence.new(rgb(255, 70, 60), rgb(255, 170, 60))
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	aura.Parent = core
	local light = Instance.new("PointLight")
	light.Color = red
	light.Range = 60
	light.Brightness = 3
	light.Parent = core

	local function place(base, t)
		for _, entry in ipairs(parts) do
			entry.Part.CFrame = base * entry.Rel
		end
		for k, blade in ipairs(orbit) do
			local angle = t * 1.8 + k * math.pi / 2
			blade.CFrame = base * CFrame.new(math.cos(angle) * 16 * S, 4 * S + math.sin(angle * 2) * 3, math.sin(angle) * 8 * S) * CFrame.Angles(0, -angle, math.rad(20))
		end
	end
	return model, body, place
end

-- 소환 결투: 먼 하늘 위 심연 무대로 끌려가 최후의 군주와 1:1 (약 8초). 공격할 수 있지만 쓰러뜨릴 수는 없고, 바닥 경고를 보고 피할 수 있는 공격을 받다가 마지막 일격에 쓰러진다.
local function doomWave(player, zone)
	local root, humanoid = getAliveParts(player)
	if not root then return end
	-- 끌려가기 직전: 데드아이(궁극기)를 100% 채워 주고 한번 써볼 기회를 준다 (주변에 몬스터가 있을 때 V!)
	player:SetAttribute("UltCharge", Config.Skills.Ult.Cost)
	Remotes.Tutorial:FireClient(player, "Prompt", { Key = "V", Title = "궁극기 데드아이!", Text = "게이지가 가득 찼어요! V 키를 눌러 써보세요", Duration = 9 })
	notify(player, "⚠ 불길한 기운이 짙어진다... 그 전에 V 키로 궁극기를 써보세요!")
	do
		local waited, usedAt = 0, nil
		while waited < 9 do
			task.wait(0.25)
			waited += 0.25
			if player:GetAttribute("DeadeyeActive") and not usedAt then usedAt = waited end
			if usedAt and waited - usedAt >= 3.5 then break end
			if not getAliveParts(player) then return end
		end
	end
	root, humanoid = getAliveParts(player)
	if not root or humanoid.Health <= 0 then return end
	player:SetAttribute("InDoomArena", true) -- 납치 연출로 높이 올라가도 "필드 밖으로 튕김" / 구역 판별에 걸리지 않게 처음부터 켠다
	notify(player, "⚠⚠ 압도적인 기운... 무언가가 당신을 부른다!!")
	player:SetAttribute("ShakeStrength", 0.9)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	local TweenService = game:GetService("TweenService")
	local RunService = game:GetService("RunService")

	-- 연출: 하늘이 어두워지며 거대한 비행체가 나타나 빛줄기로 플레이어를 끌어올린다 (UFO 납치)
	do
		local origin = root.Position
		local abduction = Instance.new("Folder")
		abduction.Name = "DoomAbduction"
		abduction.Parent = workspace
		local function cyl(name, size, cf, color, material, transparency)
			local part = Instance.new("Part")
			part.Name = name
			part.Shape = Enum.PartType.Cylinder
			part.Size = size
			part.CFrame = cf
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.Color = color
			part.Material = material
			part.Transparency = transparency
			part.Parent = abduction
			return part
		end
		local shipCenter = origin + Vector3.new(0, 120, 0)
		local hull = cyl("Hull", Vector3.new(10, 90, 90), CFrame.new(shipCenter) * CFrame.Angles(0, 0, math.rad(90)), rgb(30, 22, 40), Enum.Material.Metal, 1)
		local dome = cyl("Dome", Vector3.new(14, 40, 40), CFrame.new(shipCenter + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(120, 20, 40), Enum.Material.Neon, 1)
		local rim = cyl("Rim", Vector3.new(2, 96, 96), CFrame.new(shipCenter + Vector3.new(0, -4, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 60, 70), Enum.Material.Neon, 1)
		local column = cyl("Beam", Vector3.new(120, 12, 12), CFrame.new(origin + Vector3.new(0, 55, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 120, 130), Enum.Material.Neon, 1)
		local groundRing = cyl("GroundRing", Vector3.new(0.4, 60, 60), CFrame.new(origin + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 80, 90), Enum.Material.Neon, 1)
		for _, part in ipairs({ hull, dome, rim }) do
			TweenService:Create(part, TweenInfo.new(1.2), { Transparency = part == hull and 0 or 0.1 }):Play()
		end
		notify(player, "⚠ 하늘에서 거대한 무언가가 내려온다...!")
		shakeScreen(player, 0.5)
		task.wait(1.3)
		TweenService:Create(column, TweenInfo.new(0.5), { Transparency = 0.45, Size = Vector3.new(120, 16, 16) }):Play()
		TweenService:Create(groundRing, TweenInfo.new(1.2), { Transparency = 0.3, Size = Vector3.new(0.4, 18, 18) }):Play()
		local pull = Instance.new("ParticleEmitter") -- 빛줄기 안에서 위로 빨려 올라가는 입자
		pull.Rate = 60
		pull.Lifetime = NumberRange.new(1, 1.6)
		pull.Speed = NumberRange.new(14, 22)
		pull.EmissionDirection = Enum.NormalId.Top
		pull.SpreadAngle = Vector2.new(15, 15)
		pull.LightEmission = 1
		pull.Color = ColorSequence.new(rgb(255, 140, 150))
		pull.Size = NumberSequence.new(1.2, 0)
		pull.Parent = column
		local r0, h0 = getAliveParts(player)
		if r0 and h0.Health > 0 then
			r0.Anchored = true
			r0.AssemblyLinearVelocity = Vector3.zero
			local started = os.clock()
			local duration = 2.6
			while os.clock() - started < duration do
				local t = (os.clock() - started) / duration
				local rr = getAliveParts(player)
				if not rr then break end
				local eased = t * t * (3 - 2 * t)
				rr.CFrame = CFrame.new(origin + Vector3.new(0, 4 + eased * 78, 0)) * CFrame.Angles(math.rad(eased * 25), math.rad(t * 540), 0)
				task.wait()
			end
		end
		shakeScreen(player, 0.9)
		Effects.Burst(origin + Vector3.new(0, 82, 0), rgb(255, 120, 130), 120)
		task.wait(0.25)
		abduction:Destroy()
	end
	root, humanoid = getAliveParts(player)
	if not root or humanoid.Health <= 0 then
		player:SetAttribute("InDoomArena", nil)
		return
	end
	root.Anchored = false
	local center = Vector3.new(0, 420, 1500)
	local arena = Instance.new("Folder")
	arena.Name = "DoomArena"
	arena.Parent = workspace
	local function disc(name, diameter, height, y, color, material, transparency)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(height, diameter, diameter)
		part.CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Anchored = true
		part.CanCollide = name == "DoomFloor"
		part.Color = color
		part.Material = material
		part.Transparency = transparency or 0
		part.Parent = arena
		return part
	end
	disc("DoomFloor", 150, 2, 0, rgb(196, 190, 208), Enum.Material.Marble) -- 밝은 대리석: 붉은 경고 원이 또렷하게 보이게
	disc("DoomRim", 154, 0.4, 1.1, rgb(255, 60, 60), Enum.Material.Neon, 0.4)
	disc("DoomRune", 90, 0.2, 1.2, rgb(60, 50, 90), Enum.Material.SmoothPlastic, 0.55)
	disc("DoomRuneInner", 46, 0.2, 1.3, rgb(120, 110, 150), Enum.Material.SmoothPlastic, 0.5)

	-- 둘레 보이지 않는 높은 벽 (뛰어내릴 수 없게) + 둘레를 둘러싼 검은 첨탑과 불꽃 + 하늘의 붉은 달
	for index = 0, 23 do
		local angle = index / 24 * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * 78, 0, math.sin(angle) * 78)
		local wall = Instance.new("Part")
		wall.Name = "DoomWall"
		wall.Size = Vector3.new(26, 160, 4)
		wall.CFrame = CFrame.lookAt(at + Vector3.new(0, 70, 0), center + Vector3.new(0, 70, 0))
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Parent = arena
		local height = 26 + (index % 3) * 14
		local spire = Instance.new("Part")
		spire.Name = "DoomSpire"
		spire.Size = Vector3.new(6, height, 6)
		spire.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 84, height / 2 - 2, math.sin(angle) * 84)) * CFrame.Angles(math.rad((index % 2) * 6), angle, math.rad(((index + 1) % 3) * 4))
		spire.Anchored = true
		spire.CanCollide = false
		spire.CanQuery = false
		spire.Color = rgb(22, 12, 24)
		spire.Material = Enum.Material.Slate
		spire.Parent = arena
		if index % 2 == 0 then
			local flame = Instance.new("Part")
			flame.Shape = Enum.PartType.Ball
			flame.Size = Vector3.new(3, 3, 3)
			flame.Position = spire.Position + Vector3.new(0, height / 2 + 2, 0)
			flame.Anchored = true
			flame.CanCollide = false
			flame.CanQuery = false
			flame.Color = rgb(255, 90, 50)
			flame.Material = Enum.Material.Neon
			flame.Parent = arena
			local fire = Instance.new("Fire")
			fire.Size = 14
			fire.Heat = 12
			fire.Color = rgb(255, 120, 50)
			fire.SecondaryColor = rgb(160, 20, 30)
			fire.Parent = flame
			local lamp = Instance.new("PointLight")
			lamp.Color = rgb(255, 100, 60)
			lamp.Range = 40
			lamp.Brightness = 2
			lamp.Parent = flame
		end
	end
	local moon = Instance.new("Part")
	moon.Name = "DoomMoon"
	moon.Shape = Enum.PartType.Ball
	moon.Size = Vector3.new(260, 260, 260)
	moon.Position = center + Vector3.new(0, 260, -520)
	moon.Anchored = true
	moon.CanCollide = false
	moon.CanQuery = false
	moon.Color = rgb(200, 25, 40)
	moon.Material = Enum.Material.Neon
	moon.Parent = arena
	for index = 1, 14 do -- 떠다니는 바위 조각
		local rock = Instance.new("Part")
		rock.Name = "DoomRock"
		local size = 6 + (index * 7) % 14
		rock.Size = Vector3.new(size, size * 0.8, size)
		local angle = index * 2.4
		rock.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * (110 + index * 6), 20 + (index * 13) % 70, math.sin(angle) * (110 + index * 6))) * CFrame.Angles(angle, angle * 2, 0)
		rock.Anchored = true
		rock.CanCollide = false
		rock.CanQuery = false
		rock.Color = rgb(30, 18, 30)
		rock.Material = Enum.Material.Basalt
		rock.Parent = arena
	end

	local model, body, place = buildDoomLord(arena)
	local bossPos = center + Vector3.new(0, 34, -48)
	place(CFrame.lookAt(bossPos, bossPos + Vector3.new(0, 0, 1)), 0)

	-- 맞출 수 있는 몬스터로 등록한다 (체력이 바닥나지 않게 8% 밑으로는 안 떨어진다)
	local fill = createHealthBar(body, "💀 Lv.???  ???", 360, rgb(255, 90, 90))
	body.Parent = monstersFolder -- 필드 몬스터 폴더에 두어야 총알 판정 / 자동 조준이 잡는다 (장식 부품은 모델에 남는다)
	CollectionService:AddTag(body, "Monster")
	CollectionService:AddTag(body, "RadarBoss")
	local data = {
		Static = true, Invincible = true, Doom = true, Zone = 1, Aggro = true, Goblin = false,
		Health = 1e9, MaxHealth = 1e9, HealthFill = fill, Contrib = {}, Level = 1, XpLevel = 1,
		Stats = { Size = 20, MaxHealth = 1e9, Speed = 0, ShotDamage = 0, ShotInterval = 99, ShotSpeed = 0, Gold = 0 },
		Home = bossPos, BossLike = true, Kind = "DoomLord",
	}
	monsters[body] = data

	player.Character:PivotTo(CFrame.lookAt(center + Vector3.new(0, 4, 36), center + Vector3.new(0, 4, -48)))
	root.AssemblyLinearVelocity = Vector3.zero
	player:SetAttribute("InDoomArena", true)
	notify(player, "💀 최후의 군주와 마주했다! 공격은 통하지만... 쓰러뜨릴 수는 없다. 바닥의 붉은 경고를 피해 버텨라!")
	Effects.Burst(bossPos, rgb(255, 70, 60), 100)

	local alive = function()
		local r, h = getAliveParts(player)
		return r ~= nil and h.Health > 0
	end
	local running, clock = true, 0
	local approach = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if not running or not body.Parent then connection:Disconnect() return end
		approach = math.min(1, approach + dt / 16)
		local target = alive() and select(1, getAliveParts(player)).Position or center
		local pos = bossPos:Lerp(center + Vector3.new(0, 30, -26), approach) + Vector3.new(0, math.sin(clock * 1.6) * 2.5, 0)
		local flat = Vector3.new(target.X, pos.Y, target.Z)
		place(CFrame.lookAt(pos, flat), clock)
		data.Home = pos
	end)

	local function beam(from, to, thickness, duration, color)
		local length = (to - from).Magnitude
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = Enum.Material.Neon
		part.Color = color or rgb(255, 80, 60)
		part.Size = Vector3.new(thickness, thickness, length)
		part.CFrame = CFrame.lookAt((from + to) / 2, to)
		part.Parent = arena
		TweenService:Create(part, TweenInfo.new(duration), { Transparency = 1, Size = Vector3.new(0.1, 0.1, length) }):Play()
	end
	local function ring(at, radius, color, duration)
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.4, 2, 2)
		part.CFrame = CFrame.new(at.X, center.Y + 1.4, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 0.2
		part.Parent = arena
		TweenService:Create(part, TweenInfo.new(duration), { Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 1 }):Play()
	end
	local function shake(strength)
		player:SetAttribute("ShakeStrength", strength)
		player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	end

	-- 한 번의 폭격: 바닥에 붉은 경고 원 -> 시간이 지나면 군주의 광선이 내리꽂힌다 (맞으면 최대 체력의 일부, 죽지는 않는다)
	local function strike(at, radius, telegraph, percent)
		local warn = Instance.new("Part")
		warn.Shape = Enum.PartType.Cylinder
		warn.Size = Vector3.new(0.3, radius * 2, radius * 2)
		warn.CFrame = CFrame.new(at.X, center.Y + 1.3, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		warn.Anchored = true
		warn.CanCollide = false
		warn.CanQuery = false
		warn.Material = Enum.Material.Neon
		warn.Color = rgb(255, 40, 40)
		warn.Transparency = 0.6
		warn.Parent = arena
		TweenService:Create(warn, TweenInfo.new(telegraph), { Transparency = 0.05 }):Play()
		task.delay(telegraph, function()
			warn:Destroy()
			if not arena.Parent then return end
			beam(body.Position + Vector3.new(0, 4, -6), at + Vector3.new(0, 1, 0), radius * 0.28, 0.35)
			ring(at, radius * 1.1, rgb(255, 120, 60), 0.6)
			Effects.Burst(at + Vector3.new(0, 2, 0), rgb(255, 90, 60), 60)
			shake(0.6)
			local r2, h2 = getAliveParts(player)
			if r2 and h2.Health > 0 then
				local gap = (Vector3.new(r2.Position.X, center.Y, r2.Position.Z) - at).Magnitude
				if gap <= radius then
					local dmg = math.min(h2.MaxHealth * percent, h2.Health - 1)
					if dmg > 0 then h2:TakeDamage(dmg) end
					notify(player, "💥 군주의 공격에 맞았다!")
				elseif gap <= radius + 16 and isDashing(r2, player) then
					awardNearMiss(player, r2) -- 경고 원 바로 밖으로 대시로 빠져나갔다
				end
			end
		end)
	end
	local function playerAt()
		local r = select(1, getAliveParts(player))
		return r and Vector3.new(r.Position.X, center.Y, r.Position.Z) or center
	end

	task.wait(1.0)
	-- 1) 좁은 간격의 3연 폭격 (플레이어 주변)
	if alive() then
		notify(player, "⚠ 군주가 손을 들어올렸다!")
		for k = 1, 3 do
			local offset = Vector3.new((k - 2) * 20, 0, 0)
			strike(playerAt() + offset, 13, 1.2, 0.15)
			task.wait(0.35)
		end
		task.wait(1.6)
	end
	-- 2) 가로로 넓게 퍼진 세 줄기 광선 (군주 쪽에서 뒤쪽 끝까지) : 줄 사이 빈 곳으로 피해야 한다
	if alive() then
		notify(player, "⚠⚠ 군주의 눈이 붉게 빛난다 — 광선이 온다!")
		local lanes = { -42, -4, 36 }
		local warnLanes = {}
		for _, x in ipairs(lanes) do
			local lane = Instance.new("Part")
			lane.Size = Vector3.new(16, 0.3, 140)
			lane.CFrame = CFrame.new(center + Vector3.new(x, 1.3, 0))
			lane.Anchored = true
			lane.CanCollide = false
			lane.CanQuery = false
			lane.Material = Enum.Material.Neon
			lane.Color = rgb(255, 40, 40)
			lane.Transparency = 0.65
			lane.Parent = arena
			TweenService:Create(lane, TweenInfo.new(1.6), { Transparency = 0.05 }):Play()
			table.insert(warnLanes, lane)
		end
		task.wait(1.6)
		for _, lane in ipairs(warnLanes) do
			lane:Destroy()
		end
		for _, x in ipairs(lanes) do
			beam(center + Vector3.new(x, 30, -60), center + Vector3.new(x, 1, 70), 12, 0.6, rgb(255, 120, 80))
			ring(center + Vector3.new(x, 0, 0), 20, rgb(255, 100, 60), 0.5)
		end
		shake(0.8)
		local r2, h2 = getAliveParts(player)
		if r2 and h2.Health > 0 then
			for _, x in ipairs(lanes) do
				if math.abs(r2.Position.X - (center.X + x)) <= 8 then
					local dmg = math.min(h2.MaxHealth * 0.22, h2.Health - 1)
					if dmg > 0 then h2:TakeDamage(dmg) end
					notify(player, "💥 광선에 휩쓸렸다!")
					break
				end
			end
		end
		task.wait(1.0)
	end
	-- 3) 융단 폭격: 아레나 전체에 연달아 떨어진다 (점점 빨라지고 피할 곳이 줄어든다)
	if alive() then
		notify(player, "⚠⚠⚠ 사방이 붉게 물든다 — 융단 폭격!!")
		for k = 1, 16 do
			if not alive() then break end
			local angle = math.random() * math.pi * 2
			local dist = math.random() * 55
			local at = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
			if k % 3 == 0 then at = playerAt() end -- 세 번에 한 번은 플레이어를 정확히 노린다
			strike(at, 11, 0.9, 0.12)
			task.wait(math.max(0.18, 0.5 - k * 0.02))
		end
		task.wait(1.5)
	end

	-- 마지막: 아레나 전체가 붉게 물든다 — 어디에도 안전한 곳이 없다
	if alive() then
		notify(player, "💀 군주가 모든 힘을 모은다... 피할 곳이 없다!!")
		Remotes.Tutorial:FireClient(player, "Cinema", "Start")
		shake(0.9)
		local flood = Instance.new("Part")
		flood.Shape = Enum.PartType.Cylinder
		flood.Size = Vector3.new(0.4, 160, 160)
		flood.CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		flood.Anchored = true
		flood.CanCollide = false
		flood.CanQuery = false
		flood.Material = Enum.Material.Neon
		flood.Color = rgb(255, 30, 30)
		flood.Transparency = 0.9
		flood.Parent = arena
		TweenService:Create(flood, TweenInfo.new(2.4, Enum.EasingStyle.Quad), { Transparency = 0.2 }):Play()
		local charge = Instance.new("Part")
		charge.Shape = Enum.PartType.Ball
		charge.Anchored = true
		charge.CanCollide = false
		charge.CanQuery = false
		charge.Material = Enum.Material.Neon
		charge.Color = rgb(255, 230, 120)
		charge.Transparency = 0.2
		charge.Size = Vector3.new(4, 4, 4)
		charge.Position = body.Position + Vector3.new(0, 4, -10)
		charge.Parent = arena
		TweenService:Create(charge, TweenInfo.new(2.4, Enum.EasingStyle.Quad), { Size = Vector3.new(60, 60, 60), Transparency = 0.05 }):Play()
		for _ = 1, 4 do
			shake(0.7)
			task.wait(0.6)
		end
		local r = alive() and select(1, getAliveParts(player))
		if r then
			beam(charge.Position, r.Position, 26, 0.9, rgb(255, 240, 150))
			ring(center, 90, rgb(255, 90, 60), 1.0)
			Effects.Burst(r.Position, rgb(255, 80, 60), 160)
			shake(1)
			Remotes.Tutorial:FireClient(player, "Cinema", "Blast")
			task.wait(0.35)
			local _, h = getAliveParts(player)
			if h then
				Remotes.Tutorial:FireClient(player, "Cinema", "Black")
				task.wait(0.5)
				h.Health = 0
			end
		end
		charge:Destroy()
		flood:Destroy()
	end

	running = false
	monsters[body] = nil
	body:Destroy()
	task.delay(4.5, function()
		player:SetAttribute("InDoomArena", nil)
		arena:Destroy()
		Remotes.Tutorial:FireClient(player, "Cinema", "End")
	end)
end

local function updateDoom()
	local anyDoom = false
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InDoomArena") then
			anyDoom = true -- 소환 결투 중에는 군주 / 연출을 건드리지 않는다
		elseif player:GetAttribute("TutorialDoom") and player:GetAttribute("Zone") == "Field" then
			local root, humanoid = getAliveParts(player)
			if root and not isSafe(root.Position) then
				anyDoom = true
				local state = doomTimers[player]
				if not state then
					state = { Since = os.clock() }
					doomTimers[player] = state
				end
				if not state.Fired and os.clock() - state.Since >= 9 then
					state.Fired = true
					state.FiredAt = os.clock()
					local doomZone = zoneOfX(root.Position.X)
					task.spawn(function() -- 오래 걸리는 연출이라 필드 업데이트 루프를 막지 않게 따로 돌린다
						local ok, err = pcall(doomWave, player, doomZone)
						if not ok then
							warn("[Doom] 소환 결투 오류: " .. tostring(err))
							player:SetAttribute("InDoomArena", nil)
							local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
							if r then r.Anchored = false end
						end
					end)
				end
				if state.Fired and os.clock() - state.FiredAt >= 70 and humanoid.Health > 0 then
					notify(player, "💀 압도적인 힘에 쓰러졌어요...")
					humanoid.Health = 0
				end
			else
				doomTimers[player] = nil
			end
		else
			doomTimers[player] = nil
		end
	end
	if not anyDoom then
		for part, data in pairs(monsters) do
			if data.Doom then
				monsters[part] = nil
				part:Destroy()
			end
		end
	end
end

-- 습격 / 공습: 필드에서 싸우는 플레이어에게 일정 시간마다 갑자기 닥친다 (가만히 있으면 위험하다)
--   습격 = 사방에서 몬스터 떼가 몰려온다 / 공습 = 하늘에서 폭격기가 폭탄을 떨어뜨린다
local function runAmbush()
	task.wait(20)
	while true do
		task.wait(math.random(18, 32))
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Zone") == "Field" then
				local root = getAliveParts(player)
				if root and not isSafe(root.Position) then
					local zone = zoneOfX(root.Position.X)
					local allowed = zone <= math.min(F.ZoneCount, (player:GetAttribute("ClearedZone") or 0) + 1)
					if allowed and zone >= 1 then
						if math.random() < 0.4 then
							task.spawn(airRaid, player, zone)
						else
							local alive = 0
							for _, data in pairs(monsters) do
								if data.Ambush then alive += 1 end
							end
							if alive <= 14 then
								notify(player, "⚠ 습격! 사방에서 몬스터 떼가 몰려온다!")
								player:SetAttribute("ShakeStrength", 0.5)
								player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
								local count = 6 + math.min(6, zone)
								local spawned = 0
								for _ = 1, count * 3 do
									if spawned >= count then break end
									local angle = math.random() * math.pi * 2
									local distance = 42 + math.random() * 16
									local at = root.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
									if walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == zone then
										spawnMonster(zone, "Normal", at, true)
										spawned += 1
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

function Field.Init(lobbySpawnCFrame)
	lobbySpawn = lobbySpawnCFrame or lobbySpawn
	buildWorld()

	for zone = 1, F.ZoneCount do
		local countMult = F.ZoneCountMult and F.ZoneCountMult[zone] or 1 -- 구역이 올라갈수록 몬스터가 더 많다
		for _ = 1, math.floor(F.MonstersPerZone * countMult + 0.5) do
			spawnMonster(zone, "Normal")
		end
		for _ = 1, math.floor(F.ElitesPerZone * countMult + 0.5) do
			spawnMonster(zone, "Elite")
		end
	end
	for bossZone = 1, F.ZoneCount do
		spawnMonster(bossZone, "Boss") -- 구역마다 군주 한 마리 (다음 구역으로 가려면 쓰러뜨려야 한다)
	end

	local zoneTimer = 0
	local orphanTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		stepMonsters(dt)
		stepProjectiles(dt)
		zoneTimer += dt
		if zoneTimer >= 0.4 then
			zoneTimer = 0
			updateZones()
			rescueOutOfBounds()
			updateBossFight()
			updateDoom()
			orphanTimer += 0.4
			if orphanTimer >= 2 then
				orphanTimer = 0
				cleanOrphans()
			end
		end
	end)

	task.spawn(runEvents)
	task.spawn(runGoblins)
	task.spawn(runAmbush)
end

return Field
