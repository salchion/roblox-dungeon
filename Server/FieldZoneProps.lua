-- FieldZoneProps (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldZoneProps)
-- 필드 구역 꾸미기: 구역마다 완전히 다른 지형지물 + 그 구역의 랜드마크 하나.
-- (FieldService 가 Studio 스크립트 한도(200KB)에 거의 닿아서 그대로 떼어 냈다. 내용은 FieldService 의 decorateZone 과 같다)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local F = Config.Field

local M = {}

-- deps: FieldService 안의 함수 / 폴더 { ZoneBounds, MakePart, FloorAt, PropBlocked, Folder }
function M.Decorate(zone, rng, deps)
	local zoneBounds, makePart, floorAt, propBlocked, worldFolder = deps.ZoneBounds, deps.MakePart, deps.FloorAt, deps.PropBlocked, deps.Folder
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
		if propBlocked(zone, cx - x0) then return false end
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

return M
