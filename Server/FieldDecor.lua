-- FieldDecor: 필드 8구역 분위기 장식 (나무 / 선인장 / 얼음 / 용암 줄기 / 결정 등) + 구역별 바닥 무늬
-- 모든 장식은 앵커 + 충돌 / 질의 / 접촉 없음이라 길, 총알 판정, 몬스터 이동을 전혀 막지 않는다.
-- 캠프 안전지대, 구역 끝 보스 자리, 관문, 경사로 / 꺾임 벽 주변에는 놓지 않는다. 구역마다 고정 시드라 매번 똑같이 만들어진다.
-- 예산: 전체 약 1500 부품 이하 / PointLight 12 이하 / ParticleEmitter 10 이하 (낮은 Rate). 프레임마다 도는 코드 없음.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local F = Config.Field

local FieldDecor = {}

local MAX_PARTS_PER_ZONE = 185
local MAX_LIGHTS = 12
local MAX_EMITTERS = 10
local BOSS_CLEAR = 90 -- 구역 끝에서 이만큼은 비운다 (보스 자리는 끝 - 45)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- helpers: { FloorAt = function(x), ZoneBounds = function(zone) -> x0, x1, Width = number, Blocked = function(zone, offset) -> boolean }
function FieldDecor.Build(parentFolder: Instance, helpers: any)
	local folder = Instance.new("Folder")
	folder.Name = "FieldDecor"
	folder.Parent = parentFolder

	local floorAt = helpers.FloorAt
	local zoneBounds = helpers.ZoneBounds
	local half = (helpers.Width or F.Width) / 2
	local blocked = helpers.Blocked

	local lightCount, emitterCount, totalParts = 0, 0, 0

	for zone = 1, F.ZoneCount do
		local rng = Random.new(9100 + zone * 31)
		local x0, x1 = zoneBounds(zone)
		local minX = x0 + F.CampSafe + 10
		local maxX = x1 - BOSS_CLEAR
		local zoneParts = 0
		local patchLayer = 0

		local function R(a: number, b: number): number
			return rng:NextNumber(a, b)
		end

		-- 부품 하나 (예산이 다 차면 nil)
		local function add(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?, transparency: number?): Part?
			if zoneParts >= MAX_PARTS_PER_ZONE then return nil end
			zoneParts += 1
			totalParts += 1
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
			part.CFrame = cframe
			part.Color = color
			part.Material = material
			part.Transparency = transparency or 0
			part.Parent = folder
			return part
		end
		local function ball(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material, transparency: number?): Part?
			return add(name, size, CFrame.new(pos), color, material, Enum.PartType.Ball, transparency)
		end
		local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, transparency: number?): Part?
			return add(name, size, cframe, color, material, nil, transparency)
		end
		-- 세운 원기둥 (Roblox 원기둥은 X 축이 길이라 Z 로 90도 눕혀서 세운다)
		local function post(name: string, height: number, diameter: number, pos: Vector3, color: Color3, material: Enum.Material, tiltX: number?, tiltZ: number?): Part?
			local cf = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(math.rad(tiltX or 0), 0, math.rad((tiltZ or 0) + 90))
			return add(name, Vector3.new(height, diameter, diameter), cf, color, material, Enum.PartType.Cylinder)
		end
		local function glow(part: Part?, color: Color3, range: number, brightness: number)
			if not part or lightCount >= MAX_LIGHTS then return end
			lightCount += 1
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = range
			light.Brightness = brightness
			light.Shadows = false
			light.Parent = part
		end
		local function emit(part: Part?, color: Color3, rate: number, size: number, speed: number, lifetime: number, spread: number)
			if not part or emitterCount >= MAX_EMITTERS then return end
			emitterCount += 1
			local e = Instance.new("ParticleEmitter")
			e.Rate = rate
			e.Lifetime = NumberRange.new(lifetime, lifetime * 1.5)
			e.Speed = NumberRange.new(speed * 0.4, speed)
			e.SpreadAngle = Vector2.new(spread, spread)
			e.EmissionDirection = Enum.NormalId.Top
			e.LightEmission = 0.6
			e.LightInfluence = 0
			e.Color = ColorSequence.new(color)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			e.Parent = part
		end
		local function tint(color: Color3, amount: number): Color3 -- 색을 살짝 어둡게 / 밝게 흔든다
			return color:Lerp(amount > 0 and Color3.new(1, 1, 1) or Color3.new(0, 0, 0), math.abs(amount))
		end
		local function yaw(pos: Vector3, degrees: number?): CFrame
			return CFrame.new(pos) * CFrame.Angles(0, math.rad(degrees or R(0, 360)), 0)
		end
		local function lean(pos: Vector3, amount: number): CFrame
			return CFrame.new(pos) * CFrame.Angles(math.rad(R(-amount, amount)), math.rad(R(0, 360)), math.rad(R(-amount, amount)))
		end

		-- 놓을 수 있는 자리인가: 캠프 / 보스 자리 / 관문 / 경사로 / 꺾임 벽 밖
		local function okAt(x: number, z: number): boolean
			if x < minX or x > maxX or math.abs(z) > half - 8 then return false end
			if blocked and blocked(zone, x - x0) then return false end
			return true
		end
		-- count 번 시도해서 자리가 맞으면 builder 를 부른다 (builder 는 바닥 위 위치를 받는다)
		local function scatter(count: number, builder: (Vector3) -> ())
			for _ = 1, count do
				local x, z = R(minX, maxX), R(-half + 8, half - 8)
				if okAt(x, z) and zoneParts < MAX_PARTS_PER_ZONE then
					builder(Vector3.new(x, floorAt(x), z))
				end
			end
		end
		-- 바닥 무늬: 납작한 원판 (층마다 살짝 높여서 서로 겹쳐도 깜빡이지 않게)
		local function patch(pos: Vector3, color: Color3, material: Enum.Material, size: number)
			patchLayer += 1
			local y = pos.Y + 0.05 + (patchLayer % 7) * 0.012
			add("FloorPatch", Vector3.new(0.1, size, size * R(0.7, 1)), CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, math.rad(R(0, 360)), math.rad(90)), color, material, Enum.PartType.Cylinder)
		end

		------------------------------------------------------------
		-- 1 초원
		------------------------------------------------------------
		if zone == 1 then
			local bloomColors = { rgb(240, 150, 170), rgb(245, 220, 120), rgb(200, 170, 235), rgb(245, 240, 235) }
			scatter(14, function(p) -- 나무
				local h = R(8, 12)
				post("Trunk", h, R(1.6, 2.2), p, rgb(112, 82, 56), Enum.Material.Wood)
				for _ = 1, 2 do
					local s = R(7, 11)
					ball("Leaves", Vector3.new(s, s * 0.85, s), p + Vector3.new(R(-2, 2), h + R(-1, 2), R(-2, 2)), tint(rgb(98, 160, 84), R(-0.1, 0.12)), Enum.Material.Grass)
				end
			end)
			scatter(16, function(p) -- 덤불
				for _ = 1, 2 do
					local s = R(2.5, 4)
					ball("Bush", Vector3.new(s, s * 0.7, s), p + Vector3.new(R(-1.5, 1.5), s * 0.25, R(-1.5, 1.5)), tint(rgb(86, 150, 76), R(-0.12, 0.1)), Enum.Material.Grass)
				end
			end)
			scatter(11, function(p) -- 꽃밭
				for _ = 1, 5 do
					local s = R(0.6, 0.9)
					ball("Flower", Vector3.new(s, s, s), p + Vector3.new(R(-3, 3), 0.5, R(-3, 3)), bloomColors[rng:NextInteger(1, #bloomColors)], Enum.Material.SmoothPlastic)
				end
			end)
			scatter(10, function(p) -- 바위
				local s = R(2, 4.5)
				block("Rock", Vector3.new(s, s * 0.7, s * R(0.8, 1.2)), lean(p + Vector3.new(0, s * 0.2, 0), 10), tint(rgb(140, 138, 130), R(-0.12, 0.1)), Enum.Material.Slate)
			end)
			scatter(7, function(p)
				patch(p, tint(rgb(112, 168, 84), R(-0.1, 0.12)), rng:NextNumber() < 0.5 and Enum.Material.LeafyGrass or Enum.Material.Grass, R(16, 28))
			end)

		------------------------------------------------------------
		-- 2 숲
		------------------------------------------------------------
		elseif zone == 2 then
			scatter(26, function(p) -- 높고 빽빽한 나무
				local h = R(14, 22)
				post("Trunk", h, R(2, 3), p, rgb(84, 62, 46), Enum.Material.Wood)
				for i = 1, 3 do
					local s = R(8, 12) - i * 1.2
					ball("Canopy", Vector3.new(s, s * 0.8, s), p + Vector3.new(R(-1.5, 1.5), h - 2 + i * 2.5, R(-1.5, 1.5)), tint(rgb(52, 104, 62), R(-0.12, 0.1)), Enum.Material.Grass)
				end
			end)
			scatter(14, function(p) -- 덤불 / 고사리
				for _ = 1, 2 do
					local s = R(2, 3.4)
					ball("Fern", Vector3.new(s, s * 0.6, s), p + Vector3.new(R(-1.5, 1.5), s * 0.2, R(-1.5, 1.5)), tint(rgb(70, 128, 70), R(-0.1, 0.12)), Enum.Material.LeafyGrass)
				end
			end)
			local capColors = { rgb(190, 100, 110), rgb(200, 150, 90), rgb(150, 110, 170) }
			scatter(14, function(p) -- 버섯
				local h = R(1.8, 3.6)
				post("MushroomStem", h, 0.9, p, rgb(228, 220, 200), Enum.Material.SmoothPlastic)
				local w = R(3, 5)
				ball("MushroomCap", Vector3.new(w, w * 0.5, w), p + Vector3.new(0, h, 0), capColors[rng:NextInteger(1, #capColors)], Enum.Material.SmoothPlastic)
			end)
			scatter(7, function(p) -- 쓰러진 통나무
				local len = R(8, 13)
				add("Log", Vector3.new(len, 2.2, 2.2), CFrame.new(p + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(R(0, 360)), math.rad(R(-3, 3))), rgb(98, 72, 50), Enum.Material.Wood, Enum.PartType.Cylinder)
			end)
			local flies = 0 -- 반딧불: 보이지 않는 받침 위의 은은한 파티클 (2곳)
			scatter(30, function(p)
				if flies >= 2 then return end
				flies += 1
				local anchor = block("FireflyAnchor", Vector3.new(1, 1, 1), CFrame.new(p + Vector3.new(0, 4, 0)), rgb(200, 230, 140), Enum.Material.SmoothPlastic, 1)
				if anchor then
					emit(anchor, rgb(210, 235, 150), 3, 0.5, 1.5, 4, 180)
					glow(anchor, rgb(210, 235, 150), 14, 0.5)
				end
			end)
			scatter(8, function(p)
				patch(p, tint(rgb(52, 90, 52), R(-0.12, 0.1)), rng:NextNumber() < 0.5 and Enum.Material.Mud or Enum.Material.Grass, R(16, 28))
			end)

		------------------------------------------------------------
		-- 3 폐허
		------------------------------------------------------------
		elseif zone == 3 then
			local stone = rgb(158, 152, 142)
			scatter(11, function(p) -- 부러진 기둥
				post("PillarBase", 1, 4.4, p, stone, Enum.Material.Cobblestone)
				post("Pillar", R(5, 12), 3, p + Vector3.new(0, 1, 0), tint(stone, R(-0.1, 0.08)), Enum.Material.Marble, R(-3, 3), R(-3, 3))
			end)
			scatter(4, function(p) -- 아치
				local gap = R(8, 10)
				for _, side in ipairs({ -1, 1 }) do
					block("ArchLeg", Vector3.new(2.8, R(10, 14), 3), CFrame.new(p + Vector3.new(side * gap / 2, 6, 0)), stone, Enum.Material.Cobblestone)
				end
				block("ArchTop", Vector3.new(gap + 4, 2.6, 3.2), CFrame.new(p + Vector3.new(0, 13.5, 0)) * CFrame.Angles(0, 0, math.rad(R(-4, 4))), stone, Enum.Material.Cobblestone)
			end)
			scatter(16, function(p) -- 잔해 더미
				for _ = 1, 4 do
					local s = R(1.2, 3.2)
					block("Rubble", Vector3.new(s, s * R(0.5, 0.9), s * R(0.8, 1.3)), lean(p + Vector3.new(R(-3, 3), s * 0.25, R(-3, 3)), 15), tint(stone, R(-0.2, 0.1)), Enum.Material.Cobblestone)
				end
			end)
			scatter(11, function(p) -- 금 간 바닥 타일
				for _ = 1, 3 do
					block("CrackedTile", Vector3.new(R(4, 7), 0.12, R(4, 7)), CFrame.new(p.X + R(-4, 4), p.Y + 0.08, p.Z + R(-4, 4)) * CFrame.Angles(0, math.rad(R(0, 90)), 0), tint(rgb(128, 122, 114), R(-0.1, 0.1)), Enum.Material.Pavement)
				end
			end)
			scatter(7, function(p)
				patch(p, tint(rgb(122, 108, 92), R(-0.1, 0.1)), rng:NextNumber() < 0.5 and Enum.Material.Cobblestone or Enum.Material.Ground, R(16, 28))
			end)

		------------------------------------------------------------
		-- 4 사막
		------------------------------------------------------------
		elseif zone == 4 then
			local sand = rgb(226, 200, 142)
			scatter(15, function(p) -- 선인장
				local h = R(5, 10)
				local green = tint(rgb(100, 148, 90), R(-0.1, 0.08))
				post("Cactus", h, 2, p, green, Enum.Material.Grass)
				local side = rng:NextNumber() < 0.5 and -1 or 1
				local ah = R(2.5, 4)
				post("CactusArm", ah, 1.3, p + Vector3.new(side * 1.9, h * 0.4, 0), green, Enum.Material.Grass)
			end)
			scatter(13, function(p) -- 모래 언덕 (바닥에 반쯤 묻힌 납작한 공)
				local w = R(24, 40)
				local h = R(6, 10)
				add("Dune", Vector3.new(w, h, w * R(0.6, 0.9)), yaw(p + Vector3.new(0, -h * 0.28, 0)), tint(sand, R(-0.06, 0.05)), Enum.Material.Sand, Enum.PartType.Ball)
			end)
			scatter(6, function(p) -- 뼈
				block("Rib", Vector3.new(0.5, 0.5, R(3, 5)), lean(p + Vector3.new(0, 0.3, 0), 8), rgb(232, 224, 205), Enum.Material.SmoothPlastic)
				block("Rib", Vector3.new(0.5, 0.5, R(3, 5)), lean(p + Vector3.new(R(-2, 2), 0.3, R(-2, 2)), 8), rgb(232, 224, 205), Enum.Material.SmoothPlastic)
				ball("Skull", Vector3.new(2.2, 1.8, 2), p + Vector3.new(R(-2, 2), 0.9, R(-2, 2)), rgb(236, 230, 214), Enum.Material.SmoothPlastic)
			end)
			scatter(15, function(p) -- 하얗게 바랜 돌
				local s = R(1.8, 4)
				block("BleachedStone", Vector3.new(s, s * 0.6, s * R(0.8, 1.2)), lean(p + Vector3.new(0, s * 0.18, 0), 10), tint(rgb(222, 212, 192), R(-0.08, 0.05)), Enum.Material.Sandstone)
			end)
			scatter(7, function(p)
				patch(p, tint(rgb(212, 184, 126), R(-0.08, 0.06)), rng:NextNumber() < 0.5 and Enum.Material.Sandstone or Enum.Material.Salt, R(16, 30))
			end)

		------------------------------------------------------------
		-- 5 설원
		------------------------------------------------------------
		elseif zone == 5 then
			local iceColor = rgb(176, 220, 244)
			local crystalCount = 0
			scatter(11, function(p) -- 얼음 결정 무리
				for _ = 1, 3 do
					local h = R(4, 10)
					local c = block("IceCrystal", Vector3.new(R(1.4, 2.4), h, R(1.4, 2.4)), lean(p + Vector3.new(R(-2.5, 2.5), h / 2 - 0.5, R(-2.5, 2.5)), 14), iceColor, Enum.Material.Ice, 0.2)
					crystalCount += 1
					if c and crystalCount == 5 then glow(c, rgb(170, 215, 245), 18, 0.5) end
				end
			end)
			scatter(7, function(p) -- 얼음 기둥
				local h = R(9, 16)
				block("IcePillar", Vector3.new(R(3, 4.5), h, R(3, 4.5)), lean(p + Vector3.new(0, h / 2 - 0.5, 0), 5), tint(iceColor, 0.1), Enum.Material.Glacier, 0.12)
			end)
			scatter(19, function(p) -- 눈 더미
				local w = R(6, 12)
				add("SnowMound", Vector3.new(w, w * 0.4, w * R(0.7, 1)), yaw(p + Vector3.new(0, -0.5, 0)), rgb(244, 248, 252), Enum.Material.Snow, Enum.PartType.Ball)
			end)
			scatter(12, function(p) -- 얼어붙은 바위
				local s = R(2.5, 5)
				block("FrozenRock", Vector3.new(s, s * 0.7, s), lean(p + Vector3.new(0, s * 0.2, 0), 10), tint(rgb(170, 190, 210), R(-0.08, 0.1)), Enum.Material.Ice, 0.05)
			end)
			scatter(8, function(p)
				local pick = rng:NextInteger(1, 3)
				patch(p, pick == 1 and rgb(200, 228, 244) or rgb(238, 244, 250), pick == 1 and Enum.Material.Ice or (pick == 2 and Enum.Material.Glacier or Enum.Material.Snow), R(16, 30))
			end)

		------------------------------------------------------------
		-- 6 화산
		------------------------------------------------------------
		elseif zone == 6 then
			local lavaColor = rgb(224, 98, 44) -- 눈이 편한 주황 (너무 밝은 네온은 피한다)
			local streams = 0
			for _ = 1, 40 do -- 용암 줄기 3개: 비스듬한 납작한 띠 조각들 + 은은한 불빛
				if streams >= 3 then break end
				local sx, sz = R(minX + 10, maxX - 40), R(-half + 30, half - 30)
				local angle = R(-35, 35)
				local ok = true
				for step = 0, 5 do
					if not okAt(sx + math.cos(math.rad(angle)) * step * 7, sz + math.sin(math.rad(angle)) * step * 7) then ok = false; break end
				end
				if ok then
					streams += 1
					for step = 0, 5 do
						local x = sx + math.cos(math.rad(angle)) * step * 7
						local z = sz + math.sin(math.rad(angle)) * step * 7
						local seg = block("LavaStream", Vector3.new(8, 0.2, R(3, 4.5)), CFrame.new(x, floorAt(x) + 0.12, z) * CFrame.Angles(0, math.rad(-angle + R(-8, 8)), 0), lavaColor, Enum.Material.Neon)
						if step == 2 then
							glow(seg, rgb(255, 130, 60), 20, 0.5)
							if streams <= 2 then emit(seg, rgb(255, 160, 80), 3, 0.9, 3, 1.4, 20) end
						end
						if step % 2 == 1 then -- 줄기 가장자리의 검은 돌
							block("LavaRim", Vector3.new(R(1.5, 2.5), 1, R(1.5, 2.5)), lean(Vector3.new(x + R(-1, 1), floorAt(x) + 0.4, z + (step % 4 == 1 and 3.4 or -3.4)), 10), rgb(40, 34, 36), Enum.Material.Basalt)
						end
					end
				end
			end
			scatter(15, function(p) -- 흑요석 가시
				for _ = 1, rng:NextInteger(1, 2) do
					local h = R(6, 15)
					block("Obsidian", Vector3.new(R(1.6, 3), h, R(1.6, 3)), lean(p + Vector3.new(R(-2, 2), h / 2 - 0.5, R(-2, 2)), 14), rgb(34, 30, 40), Enum.Material.Glass, 0.05)
				end
			end)
			scatter(12, function(p) -- 불씨 자국: 어두운 붉은 판 + 아주 작은 불씨 점
				patch(p, rgb(88, 36, 28), Enum.Material.Basalt, R(10, 18))
				for _ = 1, 2 do
					ball("Ember", Vector3.new(0.5, 0.35, 0.5), Vector3.new(p.X + R(-3, 3), p.Y + 0.2, p.Z + R(-3, 3)), rgb(240, 120, 50), Enum.Material.Neon)
				end
			end)
			scatter(10, function(p)
				local s = R(2, 4.5)
				block("BasaltRock", Vector3.new(s, s * 0.7, s), lean(p + Vector3.new(0, s * 0.2, 0), 12), tint(rgb(62, 52, 52), R(-0.1, 0.1)), Enum.Material.Basalt)
			end)
			scatter(7, function(p)
				patch(p, tint(rgb(70, 40, 36), R(-0.1, 0.1)), rng:NextNumber() < 0.5 and Enum.Material.Slate or Enum.Material.Basalt, R(16, 28))
			end)

		------------------------------------------------------------
		-- 7 암흑 지대
		------------------------------------------------------------
		elseif zone == 7 then
			local wisp = rgb(176, 130, 235)
			scatter(11, function(p) -- 뒤틀린 죽은 나무
				local h = R(8, 14)
				local c = rgb(46, 40, 56)
				post("TwistedTrunk", h, R(1.4, 2), p, c, Enum.Material.Wood, R(-7, 7), R(-7, 7))
				for i = 1, 3 do
					block("Branch", Vector3.new(0.6, R(3, 6), 0.6), CFrame.new(p + Vector3.new(R(-1.5, 1.5), h * (0.4 + i * 0.16), R(-1.5, 1.5))) * CFrame.Angles(math.rad(R(-60, 60)), math.rad(R(0, 360)), math.rad(R(30, 70))), c, Enum.Material.Wood)
				end
			end)
			local wispIndex = 0
			scatter(14, function(p) -- 떠다니는 보라 도깨비불 (작은 네온 포인트)
				wispIndex += 1
				local w = ball("Wisp", Vector3.new(1.2, 1.2, 1.2), p + Vector3.new(0, R(4, 12), 0), wisp, Enum.Material.Neon, 0.25)
				if wispIndex == 3 or wispIndex == 8 then
					glow(w, wisp, 20, 0.6)
					emit(w, wisp, 3, 0.6, 2, 2.5, 180)
				end
			end)
			scatter(7, function(p) -- 보라 결정 무리
				for _ = 1, 3 do
					local h = R(3, 8)
					block("DarkCrystal", Vector3.new(R(1.2, 2.2), h, R(1.2, 2.2)), lean(p + Vector3.new(R(-2, 2), h / 2 - 0.4, R(-2, 2)), 16), rgb(118, 84, 176), Enum.Material.Glass, 0.2)
				end
				ball("CrystalCore", Vector3.new(0.7, 0.7, 0.7), p + Vector3.new(0, 1.2, 0), wisp, Enum.Material.Neon)
			end)
			scatter(14, function(p) -- 묘비
				local h = R(3, 5)
				block("TombBase", Vector3.new(3.2, 0.6, 1.8), yaw(p + Vector3.new(0, 0.3, 0), 0), rgb(70, 66, 80), Enum.Material.Slate)
				block("Tombstone", Vector3.new(2.4, h, 0.8), CFrame.new(p + Vector3.new(0, 0.6 + h / 2, 0)) * CFrame.Angles(math.rad(R(-6, 6)), 0, math.rad(R(-8, 8))), tint(rgb(92, 88, 104), R(-0.1, 0.08)), Enum.Material.Slate)
			end)
			scatter(8, function(p)
				patch(p, tint(rgb(50, 40, 70), R(-0.1, 0.12)), rng:NextNumber() < 0.5 and Enum.Material.Slate or Enum.Material.Cobblestone, R(16, 28))
			end)

		------------------------------------------------------------
		-- 8 심연
		------------------------------------------------------------
		else
			local pink = rgb(205, 100, 175)
			local violet = rgb(130, 90, 200)
			scatter(11, function(p) -- 떠 있는 공허 바위
				local w = R(6, 12)
				local top = p + Vector3.new(0, R(14, 28), 0)
				ball("VoidRock", Vector3.new(w, w * 0.45, w), top, rgb(58, 50, 76), Enum.Material.Slate)
				block("VoidRockTip", Vector3.new(w * 0.4, w * 0.6, w * 0.4), CFrame.new(top + Vector3.new(0, -w * 0.4, 0)) * CFrame.Angles(math.rad(180), 0, 0), rgb(46, 40, 62), Enum.Material.Slate)
			end)
			local clusters = 0
			scatter(12, function(p) -- 분홍보라 결정 무리
				clusters += 1
				local lit = nil
				for _ = 1, 4 do
					local h = R(4, 11)
					local c = block("AbyssCrystal", Vector3.new(R(1.2, 2.4), h, R(1.2, 2.4)), lean(p + Vector3.new(R(-2.5, 2.5), h / 2 - 0.4, R(-2.5, 2.5)), 18), rng:NextNumber() < 0.5 and pink or violet, Enum.Material.Glass, 0.18)
					lit = lit or c
				end
				if clusters == 4 or clusters == 9 then glow(lit, pink, 20, 0.55) end
			end)
			local rifts = 0
			scatter(14, function(p) -- 허공의 균열: 얇고 어두운 판 + 가는 빛줄기
				if rifts >= 4 then return end
				rifts += 1
				local h = R(10, 16)
				local cf = CFrame.new(p + Vector3.new(0, h / 2 + 1, 0)) * CFrame.Angles(0, math.rad(R(0, 360)), math.rad(R(-8, 8)))
				local slab = block("Rift", Vector3.new(0.3, h, R(3, 5)), cf, rgb(18, 10, 30), Enum.Material.SmoothPlastic, 0.2)
				block("RiftEdge", Vector3.new(0.35, h * 0.9, 0.35), cf * CFrame.new(0, 0, 0), pink, Enum.Material.Neon, 0.35)
				if rifts <= 2 then emit(slab, pink, 3, 0.7, 2, 2.5, 25) end
			end)
			scatter(16, function(p) -- 작은 떠다니는 파편
				local s = R(0.8, 1.8)
				block("Shard", Vector3.new(s, s * 1.6, s), lean(p + Vector3.new(0, R(3, 10), 0), 40), rng:NextNumber() < 0.5 and violet or pink, Enum.Material.Glass, 0.25)
			end)
			scatter(8, function(p)
				patch(p, tint(rgb(36, 28, 54), R(-0.1, 0.15)), rng:NextNumber() < 0.5 and Enum.Material.Slate or Enum.Material.Basalt, R(16, 30))
			end)
		end
	end

	return { Parts = totalParts, Lights = lightCount, Emitters = emitterCount }
end

return FieldDecor
