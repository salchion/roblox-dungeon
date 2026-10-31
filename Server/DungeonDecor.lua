-- DungeonDecor (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonDecor)
-- 던전 종류별 테마 장식: 콜로세움 가장자리(벽 아래 띠)와 벽면, 바닥 위 얇은 무늬에만 놓는다.
--   고블린 동굴 : 종유석 / 석순 / 이끼 바위 / 나무 비계 / 횃불 / 깃발 / 뼈 / 항아리 / 발광 버섯
--   얼음 성채   : 얼음 결정 / 첨탑 / 고드름 / 눈더미 / 바닥 얼음 무늬 / 느린 눈발
--   화염 신전   : 용암 웅덩이 / 용암 줄기 / 흑요석 기둥 / 가시 / 화로 / 불씨 / 바닥 균열 빛
-- 규칙: 전부 CanCollide / CanQuery / CanTouch = false (이동 / 총알 / 투사체에 영향 없음), run.Folder 아래 "Decor" 폴더에 담겨 판이 끝나면 함께 지워진다.
--       걸어 다니는 한가운데 / 문 앞 / 보스 자리는 피하고, 조명은 약하고 부드럽게 (눈 편하게). 매 프레임 서버 코드 없음.
-- 한도: 파트 약 480 / PointLight 10 / ParticleEmitter 4 (아래 상수)

local DungeonDecor = {}

local MAX_PARTS = 800 -- (480 -> 800: 모든 테마 공통 층 — 문 아치 / 깃발 / 바닥 모자이크 / 암벽 위 수호상 — 약 300개)
local MAX_LIGHTS = 12
local MAX_EMITTERS = 4

local RADIUS = 110 -- DungeonTerrain.BuildColosseum 의 R 과 같은 값 (바닥 반지름)
local WALL_TOP = 25.5 -- 1단 돌벽 윗면 높이 (바닥 기준)

local Shape = Enum.PartType
local Mat = Enum.Material

------------------------------------------------------------
-- 한 번의 장식 작업에 쓰는 상태 / 도우미
------------------------------------------------------------
local function newContext(run, folder)
	local ctx = {}
	local center = run.ArenaCenter or (run.Origin + Vector3.new(140, 0, 0))
	local rng = Random.new((run.Id or 1) * 104729 + 17)
	local parts, lights, emitters = 0, 0, 0

	local deco = Instance.new("Folder")
	deco.Name = "Decor"
	deco.Parent = folder

	ctx.Center = center
	ctx.Rng = rng
	ctx.Folder = deco

	-- 장식 파트 하나 (한도를 넘으면 nil)
	function ctx.Part(name, size, cframe, color, material, props)
		if parts >= MAX_PARTS then
			return nil
		end
		parts += 1
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material or Mat.Slate
		for key, value in pairs(props or {}) do
			p[key] = value
		end
		p.Parent = deco
		return p
	end

	function ctx.Light(part, color, range, brightness)
		if not part or lights >= MAX_LIGHTS then
			return nil
		end
		lights += 1
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = math.min(brightness, 0.8)
		light.Shadows = false
		light.Parent = part
		return light
	end

	function ctx.Emitter(part)
		if not part or emitters >= MAX_EMITTERS then
			return nil
		end
		emitters += 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Parent = part
		return emitter
	end

	-- 아레나 중심 기준 극좌표 -> 월드 좌표 (y 는 바닥 위 높이)
	function ctx.Polar(angle, distance, height)
		return Vector3.new(center.X + math.cos(angle) * distance, center.Y + (height or 0), center.Z + math.sin(angle) * distance)
	end

	-- 문(45도 간격)과 보스 쪽(0도)을 피한 가장자리 각도
	function ctx.RimAngle(avoidBoss)
		local angle = 0
		for _ = 1, 12 do
			angle = rng:NextNumber(0, math.pi * 2)
			local deg = math.deg(angle) % 45
			local fromGate = math.min(deg, 45 - deg)
			local bossDeg = math.deg(angle) % 360
			local nearBoss = math.min(bossDeg, 360 - bossDeg) < 20
			if fromGate > 8 and not (avoidBoss and nearBoss) then
				return angle
			end
		end
		return angle
	end

	-- 뾰족한 가시: 아래에서 위로(또는 위에서 아래로) 점점 가늘어지는 블록 쌓기 (3파트)
	function ctx.Spike(name, base, height, width, color, material, hanging, props)
		local segs = 3
		local segH = height / segs
		for k = 1, segs do
			local w = math.max(0.25, width * (1 - (k - 1) / segs * 0.85))
			local offset = segH * (k - 0.5) * (hanging and -1 or 1)
			ctx.Part(name, Vector3.new(w, segH, w), CFrame.new(base + Vector3.new(0, offset, 0)) * CFrame.Angles(0, k * 0.7, 0), color, material, props)
		end
	end

	-- 바닥에 눕힌 얇은 원판 (지름 diameter)
	function ctx.Disc(name, position, diameter, thickness, color, material, props)
		local all = { Shape = Shape.Cylinder }
		for key, value in pairs(props or {}) do
			all[key] = value
		end
		return ctx.Part(name, Vector3.new(thickness, diameter, diameter), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, material, all)
	end

	-- 벽에 붙은 횃불 기둥 + 약한 불빛. 불꽃 파트를 돌려준다
	function ctx.Torch(angle, flameColor, postColor, lightRange, lightBrightness)
		local base = ctx.Polar(angle, RADIUS - 2.5)
		ctx.Part("TorchPost", Vector3.new(1, 6, 1), CFrame.new(base + Vector3.new(0, 3, 0)), postColor, Mat.Wood)
		local flame = ctx.Part("TorchFlame", Vector3.new(1.3, 1.6, 1.3), CFrame.new(base + Vector3.new(0, 6.6, 0)), flameColor, Mat.Neon, { Transparency = 0.2, Shape = Shape.Ball })
		ctx.Light(flame, flameColor, lightRange, lightBrightness)
		return flame
	end

	-- 보스 자리 강조: 바닥의 옅은 고리 + 양옆 기둥(가장자리) + 은은한 불빛
	function ctx.BossEmphasis(run, ringColor, pillarColor, pillarMaterial, topColor)
		local boss = run.BossPos or ctx.Polar(0, RADIUS - 34)
		local ring = ctx.Disc("BossRing", Vector3.new(boss.X, center.Y + 0.4, boss.Z), 26, 0.12, ringColor, Mat.Neon, { Transparency = 0.8 })
		ctx.Disc("BossRingInner", Vector3.new(boss.X, center.Y + 0.42, boss.Z), 17, 0.12, ringColor, Mat.Neon, { Transparency = 0.86 })
		ctx.Light(ring, ringColor, 30, 0.5)
		for _, side in ipairs({ -1, 1 }) do
			local angle = math.rad(15) * side
			local base = ctx.Polar(angle, RADIUS - 5)
			ctx.Part("BossPillar", Vector3.new(4, 20, 4), CFrame.new(base + Vector3.new(0, 10, 0)), pillarColor, pillarMaterial)
			ctx.Part("BossPillarCap", Vector3.new(5.4, 1.6, 5.4), CFrame.new(base + Vector3.new(0, 20.8, 0)), pillarColor:Lerp(Color3.new(0, 0, 0), 0.2), pillarMaterial)
			ctx.Part("BossPillarGem", Vector3.new(1.4, 1.4, 1.4), CFrame.new(base + Vector3.new(0, 22.4, 0)) * CFrame.Angles(0.6, 0.6, 0), topColor, Mat.Neon, { Transparency = 0.25 })
		end
	end

	return ctx
end

------------------------------------------------------------
-- 고블린 동굴
------------------------------------------------------------
local function decorateCave(run, ctx)
	local rng = ctx.Rng
	local rock = Color3.fromRGB(96, 86, 76)
	local rockDark = Color3.fromRGB(70, 62, 56)
	local moss = Color3.fromRGB(88, 112, 62)
	local wood = Color3.fromRGB(112, 82, 52)
	local woodDark = Color3.fromRGB(80, 58, 38)
	local bone = Color3.fromRGB(214, 206, 188)
	local torchColor = Color3.fromRGB(255, 170, 90)

	-- 석순 (바닥 가장자리에서 솟음)
	for _ = 1, 22 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(2, 8))
		ctx.Spike("Stalagmite", base, rng:NextNumber(3.5, 9), rng:NextNumber(1.6, 3), rng:NextNumber() < 0.5 and rock or rockDark, Mat.Rock, false)
	end
	-- 종유석 (돌벽 윗단에서 늘어짐)
	for _ = 1, 20 do
		local base = ctx.Polar(ctx.RimAngle(false), RADIUS - 1.4, WALL_TOP)
		ctx.Spike("Stalactite", base, rng:NextNumber(3, 8), rng:NextNumber(1.4, 2.6), rockDark, Mat.Rock, true)
	end
	-- 이끼 낀 바위
	for _ = 1, 16 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(3, 9), 0.8)
		local s = rng:NextNumber(2.5, 5)
		ctx.Part("MossRock", Vector3.new(s, s * 0.7, s * 1.2), CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber() < 0.6 and moss:Lerp(rock, 0.35) or rock, Mat.Rock, { Shape = Shape.Ball })
	end
	-- 나무 비계 (벽에 기댄 작은 망루 모양)
	for i = 1, 4 do
		local angle = math.rad(22.5 + (i - 1) * 90 + rng:NextNumber(-4, 4))
		local base = ctx.Polar(angle, RADIUS - 3.2)
		local yaw = CFrame.lookAt(base, Vector3.new(ctx.Center.X, base.Y, ctx.Center.Z)).Rotation
		for _, side in ipairs({ -1, 1 }) do
			local post = base + yaw.RightVector * (3.2 * side)
			ctx.Part("ScaffoldPost", Vector3.new(0.9, 11, 0.9), CFrame.new(post + Vector3.new(0, 5.5, 0)), woodDark, Mat.Wood)
		end
		ctx.Part("ScaffoldDeck", Vector3.new(8, 0.6, 3.4), CFrame.new(base + Vector3.new(0, 8, 0)) * yaw, wood, Mat.WoodPlanks)
		ctx.Part("ScaffoldBrace", Vector3.new(0.5, 8, 0.5), CFrame.new(base + Vector3.new(0, 4, 0)) * yaw * CFrame.Angles(0, 0, math.rad(40)), woodDark, Mat.Wood)
		ctx.Part("ScaffoldRail", Vector3.new(8, 0.4, 0.4), CFrame.new(base + yaw.LookVector * 1.5 + Vector3.new(0, 9.4, 0)) * yaw, woodDark, Mat.Wood)
	end
	-- 횃불 (따뜻하고 어두운 불빛 5개)
	for i = 1, 5 do
		ctx.Torch(math.rad(22.5 + (i - 1) * 72 + 14), torchColor, woodDark, 24, 0.6)
	end
	-- 고블린 깃발
	for _ = 1, 6 do
		local angle = ctx.RimAngle(true)
		local pole = ctx.Polar(angle, RADIUS - 1.4, 7)
		ctx.Part("BannerPole", Vector3.new(0.5, 14, 0.5), CFrame.new(pole), woodDark, Mat.Wood)
		local face = CFrame.lookAt(pole, ctx.Polar(angle, RADIUS - 20, 7))
		ctx.Part("Banner", Vector3.new(3, 6, 0.2), face * CFrame.new(0, 3, -0.4), rng:NextNumber() < 0.5 and Color3.fromRGB(110, 40, 36) or Color3.fromRGB(70, 96, 48), Mat.Fabric)
		ctx.Part("BannerMark", Vector3.new(1.2, 1.2, 0.22), face * CFrame.new(0, 3.5, -0.5), bone, Mat.Fabric, { Shape = Shape.Ball })
	end
	-- 뼈 / 해골
	for _ = 1, 12 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(3, 9), 0.4)
		if rng:NextNumber() < 0.35 then
			ctx.Part("Skull", Vector3.new(1.6, 1.4, 1.6), CFrame.new(base + Vector3.new(0, 0.5, 0)), bone, Mat.Limestone, { Shape = Shape.Ball })
		else
			ctx.Part("Bone", Vector3.new(0.5, 0.5, rng:NextNumber(2, 4)), CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), bone, Mat.Limestone)
			ctx.Part("Bone", Vector3.new(0.5, 0.5, 2.4), CFrame.new(base + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), bone, Mat.Limestone)
		end
	end
	-- 항아리
	for _ = 1, 8 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(3, 8), 1.4)
		ctx.Part("Pot", Vector3.new(2.6, 2.8, 2.6), CFrame.new(base), Color3.fromRGB(140, 96, 64), Mat.Mud, { Shape = Shape.Ball })
		ctx.Part("PotNeck", Vector3.new(1.2, 0.9, 1.2), CFrame.new(base + Vector3.new(0, 1.5, 0)), Color3.fromRGB(120, 80, 54), Mat.Mud)
	end
	-- 발광 버섯 (작게, 두 무더기만 약한 불빛)
	for i = 1, 10 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(2.5, 7))
		local h = rng:NextNumber(1.2, 2.4)
		ctx.Part("MushroomStem", Vector3.new(0.4, h, 0.4), CFrame.new(base + Vector3.new(0, h / 2, 0)), Color3.fromRGB(200, 210, 190), Mat.SmoothPlastic)
		local cap = ctx.Part("MushroomCap", Vector3.new(h * 1.3, h * 0.7, h * 1.3), CFrame.new(base + Vector3.new(0, h, 0)), Color3.fromRGB(110, 210, 170), Mat.Neon, { Shape = Shape.Ball, Transparency = 0.3 })
		if i <= 2 then
			ctx.Light(cap, Color3.fromRGB(110, 210, 170), 14, 0.4)
		end
	end

	ctx.BossEmphasis(run, Color3.fromRGB(150, 190, 90), woodDark, Mat.Wood, Color3.fromRGB(170, 220, 100))
end

------------------------------------------------------------
-- 얼음 성채
------------------------------------------------------------
local function decorateIce(run, ctx)
	local rng = ctx.Rng
	local ice = Color3.fromRGB(170, 215, 240)
	local iceDeep = Color3.fromRGB(120, 175, 220)
	local snow = Color3.fromRGB(236, 244, 250)
	local glow = Color3.fromRGB(150, 205, 255)

	-- 얼음 결정 무더기 (기울어진 기둥 2~3개)
	for i = 1, 22 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(2, 8))
		for k = 1, rng:NextInteger(2, 3) do
			local h = rng:NextNumber(3, 8)
			local w = rng:NextNumber(0.9, 1.8)
			local c = ctx.Part("IceCrystal", Vector3.new(w, h, w), CFrame.new(base + Vector3.new(rng:NextNumber(-1.2, 1.2), h / 2 - 0.3, rng:NextNumber(-1.2, 1.2))) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 6), rng:NextNumber(-0.35, 0.35)), rng:NextNumber() < 0.5 and ice or iceDeep, Mat.Ice, { Transparency = 0.25, Reflectance = 0.1 })
			if i <= 4 and k == 1 then
				ctx.Light(c, glow, 24, 0.5)
			end
		end
	end
	-- 얼음 첨탑 (높고 뾰족)
	for _ = 1, 8 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(3, 7))
		ctx.Spike("IceSpire", base, rng:NextNumber(12, 20), rng:NextNumber(3, 4.5), ice, Mat.Ice, false, { Transparency = 0.2, Reflectance = 0.1 })
	end
	-- 얼어붙은 고드름 (돌벽에서 늘어짐)
	for _ = 1, 20 do
		local base = ctx.Polar(ctx.RimAngle(false), RADIUS - 1.4, WALL_TOP)
		ctx.Spike("Icicle", base, rng:NextNumber(3, 9), rng:NextNumber(1.2, 2.4), ice, Mat.Ice, true, { Transparency = 0.2 })
	end
	-- 눈더미
	for _ = 1, 16 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(3, 9), 0.4)
		local s = rng:NextNumber(4, 8)
		ctx.Part("SnowDrift", Vector3.new(s, s * 0.35, s * 0.7), CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), snow, Mat.Snow, { Shape = Shape.Ball })
	end
	-- 바닥의 얼음 무늬 (얇고 투명, 한가운데 제단 주변은 피함)
	for _ = 1, 10 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local pos = ctx.Polar(angle, rng:NextNumber(24, 92), 0.5)
		local d = rng:NextNumber(8, 18)
		ctx.Disc("IcePatch", pos, d, 0.1, Color3.fromRGB(190, 230, 250), Mat.Glass, { Transparency = 0.7, Reflectance = 0.15 })
	end
	-- 눈발: 아레나 위쪽에서 천천히 내림 (이미터 하나)
	local sky = ctx.Part("SnowEmitter", Vector3.new(150, 1, 150), CFrame.new(ctx.Center + Vector3.new(0, 48, 0)), snow, Mat.SmoothPlastic, { Transparency = 1 })
	local flakes = ctx.Emitter(sky)
	if flakes then
		flakes.Rate = 22
		flakes.Lifetime = NumberRange.new(9, 11)
		flakes.Speed = NumberRange.new(4, 6)
		flakes.EmissionDirection = Enum.NormalId.Bottom
		flakes.SpreadAngle = Vector2.new(15, 15)
		flakes.Size = NumberSequence.new(0.35)
		flakes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.3), NumberSequenceKeypoint.new(0.9, 0.3), NumberSequenceKeypoint.new(1, 1) })
		flakes.Color = ColorSequence.new(snow)
		flakes.LightEmission = 0.15
		flakes.RotSpeed = NumberRange.new(-40, 40)
		flakes.Shape = Enum.ParticleEmitterShape.Box
	end

	ctx.BossEmphasis(run, glow, ice, Mat.Ice, Color3.fromRGB(190, 230, 255))
end

------------------------------------------------------------
-- 화염 신전
------------------------------------------------------------
local function decorateFire(run, ctx)
	local rng = ctx.Rng
	local obsidian = Color3.fromRGB(42, 34, 46)
	local obsidianLight = Color3.fromRGB(64, 52, 70)
	local lava = Color3.fromRGB(210, 84, 36)
	local lavaDim = Color3.fromRGB(170, 62, 30)
	local flameColor = Color3.fromRGB(255, 130, 60)

	-- 용암 웅덩이 (가장자리 쪽, 약한 네온)
	for i = 1, 6 do
		local pos = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(5, 9), 0.35)
		local d = rng:NextNumber(6, 11)
		local pool = ctx.Disc("LavaPool", pos, d, 0.2, lava, Mat.Neon, { Transparency = 0.2 })
		ctx.Disc("LavaRim", pos - Vector3.new(0, 0.1, 0), d + 1.8, 0.15, obsidian, Mat.Basalt)
		if i == 1 then
			ctx.Light(pool, lava, 22, 0.5)
		end
	end
	-- 용암 줄기 (벽에서 안쪽으로 흘러내린 지그재그)
	for _ = 1, 6 do
		local angle = ctx.RimAngle(true)
		for k = 0, 5 do
			local a = angle + math.sin(k * 1.3) * 0.015
			local pos = ctx.Polar(a, RADIUS - 1.5 - k * 2.4, 0.3)
			ctx.Part("LavaStream", Vector3.new(1.8 - k * 0.15, 0.15, 3), CFrame.lookAt(pos, ctx.Polar(angle, RADIUS - 20, 0.3)), k % 2 == 0 and lava or lavaDim, Mat.Neon, { Transparency = 0.25 })
		end
	end
	-- 흑요석 기둥
	for _ = 1, 10 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(3, 8))
		local h = rng:NextNumber(8, 15)
		ctx.Part("ObsidianPillar", Vector3.new(2.6, h, 2.6), CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), obsidian, Mat.Slate, { Reflectance = 0.1 })
		ctx.Part("ObsidianShard", Vector3.new(1.8, h * 0.45, 1.8), CFrame.new(base + Vector3.new(1.2, h * 0.22, 0.8)) * CFrame.Angles(0.1, 0.5, 0.3), obsidianLight, Mat.Slate, { Reflectance = 0.1 })
	end
	-- 흑요석 가시
	for _ = 1, 20 do
		local base = ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(2, 8))
		ctx.Spike("ObsidianSpike", base, rng:NextNumber(3, 8), rng:NextNumber(1.4, 2.6), rng:NextNumber() < 0.5 and obsidian or obsidianLight, Mat.Slate, false, { Reflectance = 0.1 })
	end
	-- 화로 (약한 불빛 5개, 불씨 이미터 2개)
	for i = 1, 5 do
		local angle = math.rad(22.5 + (i - 1) * 72 + 14)
		local base = ctx.Polar(angle, RADIUS - 3)
		ctx.Part("BrazierStand", Vector3.new(1.2, 4, 1.2), CFrame.new(base + Vector3.new(0, 2, 0)), obsidian, Mat.Metal)
		ctx.Part("BrazierBowl", Vector3.new(1.2, 3.4, 3.4), CFrame.new(base + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), obsidianLight, Mat.Metal, { Shape = Shape.Cylinder })
		local flame = ctx.Part("BrazierFlame", Vector3.new(1.8, 1.8, 1.8), CFrame.new(base + Vector3.new(0, 5.6, 0)), flameColor, Mat.Neon, { Transparency = 0.3, Shape = Shape.Ball })
		ctx.Light(flame, flameColor, 24, 0.6)
		if i <= 2 then
			local fire = ctx.Emitter(flame)
			if fire then
				fire.Rate = 6
				fire.Lifetime = NumberRange.new(1.2, 2)
				fire.Speed = NumberRange.new(3, 5)
				fire.SpreadAngle = Vector2.new(25, 25)
				fire.EmissionDirection = Enum.NormalId.Top
				fire.LightEmission = 0.6
				fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
				fire.Color = ColorSequence.new(flameColor, Color3.fromRGB(255, 200, 120))
			end
		end
	end
	-- 바닥 균열 빛 (얇은 지그재그 선)
	for _ = 1, 14 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local pos = ctx.Polar(angle, rng:NextNumber(26, 92), 0.45)
		local dir = rng:NextNumber(0, 6)
		for k = 1, 3 do
			local len = rng:NextNumber(4, 7)
			dir += rng:NextNumber(-0.8, 0.8)
			local forward = Vector3.new(math.cos(dir), 0, math.sin(dir))
			ctx.Part("FloorCrack", Vector3.new(0.4, 0.08, len), CFrame.lookAt(pos + forward * (len / 2), pos + forward * len), lavaDim, Mat.Neon, { Transparency = 0.45 })
			pos += forward * len
		end
	end
	-- 떠오르는 불씨 (아레나 한가운데 위쪽, 아주 느리게)
	local base = ctx.Part("EmberEmitter", Vector3.new(120, 1, 120), CFrame.new(ctx.Center + Vector3.new(0, 1, 0)), lava, Mat.SmoothPlastic, { Transparency = 1 })
	local embers = ctx.Emitter(base)
	if embers then
		embers.Rate = 8
		embers.Lifetime = NumberRange.new(5, 7)
		embers.Speed = NumberRange.new(2, 4)
		embers.EmissionDirection = Enum.NormalId.Top
		embers.SpreadAngle = Vector2.new(20, 20)
		embers.Size = NumberSequence.new(0.25)
		embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.4), NumberSequenceKeypoint.new(1, 1) })
		embers.Color = ColorSequence.new(flameColor)
		embers.LightEmission = 0.5
		embers.Shape = Enum.ParticleEmitterShape.Box
	end

	ctx.BossEmphasis(run, lava, obsidian, Mat.Slate, flameColor)
end

------------------------------------------------------------
-- 보스러쉬 (심연): 공중에 뜬 부서진 바위 / 보랏빛 결정 / 바닥의 별자리 문양 (은은하게)
------------------------------------------------------------
local function decorateRift(run, ctx)
	local rng = ctx.Rng
	local rock = Color3.fromRGB(56, 44, 72)
	local violet = Color3.fromRGB(150, 110, 200)
	local center = ctx.Center
	-- 가장자리 위로 떠 있는 바위 조각들
	for _ = 1, 22 do
		local angle = ctx.RimAngle(false)
		local s = rng:NextNumber(3, 8)
		local pos = ctx.Polar(angle, RADIUS + rng:NextNumber(4, 30), WALL_TOP + rng:NextNumber(6, 30))
		ctx.Part("VoidRock", Vector3.new(s, s * rng:NextNumber(0.6, 1.1), s * rng:NextNumber(0.8, 1.3)), CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)), rock:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.2)), Mat.Slate)
	end
	-- 벽 아래 보랏빛 결정 무리
	for _ = 1, 10 do
		local angle = ctx.RimAngle(true)
		local base = ctx.Polar(angle, RADIUS - 4)
		for _ = 1, 3 do
			local h = rng:NextNumber(3, 8)
			ctx.Part("VoidCrystal", Vector3.new(rng:NextNumber(1, 2), h, rng:NextNumber(1, 2)), CFrame.new(base + Vector3.new(rng:NextNumber(-2, 2), h / 2 - 0.3, rng:NextNumber(-2, 2))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), violet:Lerp(rock, rng:NextNumber(0.2, 0.5)), Mat.Glass, { Transparency = 0.2 })
		end
	end
	-- 바닥 별자리: 작은 점 + 잇는 선 (아주 옅게)
	local stars = {}
	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dist = rng:NextNumber(36, 88)
		local pos = Vector3.new(center.X + math.cos(angle) * dist, center.Y + 0.32, center.Z + math.sin(angle) * dist)
		table.insert(stars, pos)
		ctx.Disc("StarDot", pos, 2.2, 0.08, violet, Mat.Neon, { Transparency = 0.6 })
	end
	for i = 1, #stars do
		local a, b = stars[i], stars[i % #stars + 1]
		local mid = (a + b) / 2
		ctx.Part("StarLine", Vector3.new(0.3, 0.06, (b - a).Magnitude), CFrame.lookAt(mid, b), violet, Mat.Neon, { Transparency = 0.82 })
	end
	ctx.BossEmphasis(run, violet, rock, Mat.Slate, violet)
end

------------------------------------------------------------
-- 모든 테마 공통: 투기장을 웅장하게 (판정 없음)
--   문 8개: 돌 아치 + 빛나는 쐐기돌 + 반쯤 올린 창살 / 벽 아랫단: 테마색 깃발 8장 / 보스 문 위: 큰 문장
--   바닥: 테마색 모자이크 고리(24칸) + 제단 둘레 룬 8개 / 암벽 꼭대기(높이 90): 투기장을 내려다보는 거대 수호상 4개
------------------------------------------------------------
local ARENA_STYLE = {
	Cave = { Stone = Color3.fromRGB(104, 90, 74), Mat = Mat.Rock, Cloth = Color3.fromRGB(120, 44, 38), Accent = Color3.fromRGB(150, 200, 90), Metal = Color3.fromRGB(70, 60, 52) },
	Ice = { Stone = Color3.fromRGB(150, 180, 205), Mat = Mat.Glacier, Cloth = Color3.fromRGB(60, 100, 160), Accent = Color3.fromRGB(150, 220, 255), Metal = Color3.fromRGB(110, 130, 160) },
	Fire = { Stone = Color3.fromRGB(62, 48, 48), Mat = Mat.Basalt, Cloth = Color3.fromRGB(140, 40, 26), Accent = Color3.fromRGB(255, 120, 40), Metal = Color3.fromRGB(52, 40, 40) },
	Rift = { Stone = Color3.fromRGB(70, 56, 96), Mat = Mat.Slate, Cloth = Color3.fromRGB(80, 50, 130), Accent = Color3.fromRGB(190, 130, 255), Metal = Color3.fromRGB(60, 50, 80) },
	Fever = { Stone = Color3.fromRGB(196, 160, 90), Mat = Mat.Marble, Cloth = Color3.fromRGB(170, 40, 50), Accent = Color3.fromRGB(255, 210, 80), Metal = Color3.fromRGB(230, 185, 70) }, -- 피버 타임: 황금 투기장
}
local ARENA_ROCK_TOP = 90 -- DungeonTerrain 의 WALL_HEIGHT (암벽 윗면)

local function decorateArena(run, ctx, typeKey)
	local style = ARENA_STYLE[typeKey]
	if not style then return end
	local rng = ctx.Rng
	local center = ctx.Center
	local stoneDark = style.Stone:Lerp(Color3.new(0, 0, 0), 0.3)
	local function faceIn(position)
		return CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
	end

	-- 1) 문 8개: 아치 돌 7개 + 쐐기돌 + 반쯤 올린 창살
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-radial.Z, 0, radial.X)
		local base = ctx.Polar(angle, RADIUS - 0.6)
		local archCenter = base + Vector3.new(0, 16, 0)
		local big = i == 0 -- 동쪽 보스 문은 더 크다
		local archR = big and 8.5 or 6.6
		for k = 0, 6 do
			local t = math.pi * k / 6
			local pos = archCenter + tangent * math.cos(t) * archR + Vector3.new(0, math.sin(t) * archR * 0.7, 0)
			ctx.Part("GateArch", Vector3.new(2.4, 2.2, 3.2), faceIn(pos) * CFrame.Angles(0, 0, t - math.pi / 2), k % 2 == 0 and style.Stone or stoneDark, style.Mat)
		end
		local key = ctx.Part("GateKeystone", Vector3.new(2, 2.8, 1.2), faceIn(archCenter + Vector3.new(0, archR * 0.7 + 1.2, 0) - radial * 1.2), style.Accent, Mat.Neon, { Transparency = 0.15 })
		if big then ctx.Light(key, style.Accent, 30, 0.6) end
		for k = -2, 2 do -- 창살 (윗부분만: 반쯤 올린 문)
			ctx.Part("Portcullis", Vector3.new(0.4, 6, 0.4), CFrame.new(base + tangent * k * 1.9 + Vector3.new(0, 13.5, 0) - radial * 0.4), style.Metal, Mat.Metal)
		end
		ctx.Part("PortcullisBar", Vector3.new(9.6, 0.5, 0.5), faceIn(base + Vector3.new(0, 11, 0) - radial * 0.4), style.Metal, Mat.Metal)
	end

	-- 2) 벽 아랫단에 걸린 깃발 (문 사이 8곳): 천 + 가장자리 띠 + 문장 + 아래 술
	for i = 0, 7 do
		local angle = (i + 0.5) / 8 * math.pi * 2
		local top = ctx.Polar(angle, RADIUS - 0.4, WALL_TOP - 0.6)
		local face = faceIn(top)
		ctx.Part("BannerRod", Vector3.new(6, 0.5, 0.5), face, style.Metal, Mat.Metal)
		ctx.Part("BannerCloth", Vector3.new(5, 12, 0.2), face * CFrame.new(0, -6.2, -0.3), style.Cloth, Mat.Fabric)
		ctx.Part("BannerTrim", Vector3.new(5.2, 0.6, 0.25), face * CFrame.new(0, -1.2, -0.35), style.Accent:Lerp(style.Cloth, 0.3), Mat.Fabric)
		ctx.Part("BannerEmblem", Vector3.new(2.2, 2.2, 0.25), face * CFrame.new(0, -6, -0.45) * CFrame.Angles(0, 0, math.rad(45)), style.Accent, Mat.Neon, { Transparency = 0.25 })
		ctx.Part("BannerTail", Vector3.new(3.6, 3.6, 0.2), face * CFrame.new(0, -12, -0.3) * CFrame.Angles(0, 0, math.rad(45)), style.Cloth, Mat.Fabric)
	end

	-- 3) 보스 문 위의 큰 문장 (원판 + 테두리 빛)
	local crest = ctx.Polar(0, RADIUS - 0.3, 32)
	ctx.Part("BossCrest", Vector3.new(0.6, 12, 12), faceIn(crest) * CFrame.Angles(0, math.rad(90), 0), stoneDark, style.Mat, { Shape = Shape.Cylinder })
	ctx.Part("BossCrestGlow", Vector3.new(0.5, 13.4, 13.4), faceIn(crest + (crest - Vector3.new(center.X, crest.Y, center.Z)).Unit * 0.2) * CFrame.Angles(0, math.rad(90), 0), style.Accent, Mat.Neon, { Shape = Shape.Cylinder, Transparency = 0.45 })
	ctx.Part("BossCrestMark", Vector3.new(4, 4, 0.4), faceIn(crest - (crest - Vector3.new(center.X, crest.Y, center.Z)).Unit * 0.5) * CFrame.Angles(0, 0, math.rad(45)), style.Accent, Mat.Neon, { Transparency = 0.1 })

	-- 4) 바닥 모자이크: 반지름 36 ~ 56 사이 24칸 (테마색 / 돌색 번갈아, 옅게) + 제단 둘레 룬 8개
	for i = 0, 23 do
		local angle = (i + 0.5) / 24 * math.pi * 2
		local pos = ctx.Polar(angle, 46, 0.32)
		ctx.Part("FloorTile", Vector3.new(10.6, 0.08, 18), CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)), i % 2 == 0 and style.Accent:Lerp(style.Stone, 0.55) or stoneDark, i % 2 == 0 and Mat.Neon or style.Mat, { Transparency = i % 2 == 0 and 0.78 or 0.35 })
	end
	for i = 0, 7 do
		local angle = (i + 0.5) / 8 * math.pi * 2
		local pos = ctx.Polar(angle, 18, 0.45)
		ctx.Part("FloorRune", Vector3.new(2.4, 0.1, 2.4), CFrame.new(pos) * CFrame.Angles(0, angle + math.rad(45), 0), style.Accent, Mat.Neon, { Transparency = 0.4 })
	end

	-- 5) 암벽 꼭대기의 거대 수호상 4개 (대각선 방향, 투기장을 내려다본다): 받침 + 다리 + 몸 + 어깨 + 머리 + 빛나는 눈 + 칼
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90 + rng:NextNumber(-6, 6))
		local foot = ctx.Polar(angle, RADIUS + 14, ARENA_ROCK_TOP)
		local face = faceIn(foot)
		local function at(x, y, z) return face * CFrame.new(x, y, z) end
		ctx.Part("StatueBase", Vector3.new(14, 5, 14), at(0, 2.5, 0), stoneDark, style.Mat)
		for _, side in ipairs({ -1, 1 }) do
			ctx.Part("StatueLeg", Vector3.new(4.2, 13, 4.6), at(side * 3, 11.5, 0), style.Stone, style.Mat)
			ctx.Part("StatueShoulder", Vector3.new(7, 6, 7), at(side * 7.5, 34, 0), stoneDark, style.Mat, { Shape = Shape.Ball })
			ctx.Part("StatueArm", Vector3.new(3.4, 12, 3.4), at(side * 8, 27, -1.5) * CFrame.Angles(math.rad(-12), 0, 0), style.Stone, style.Mat)
			ctx.Part("StatueEye", Vector3.new(1.1, 0.8, 0.5), at(side * 1.4, 40.5, -3.3), style.Accent, Mat.Neon)
		end
		ctx.Part("StatueBody", Vector3.new(12, 16, 7), at(0, 26, 0), style.Stone, style.Mat)
		ctx.Part("StatueHead", Vector3.new(7, 7, 7), at(0, 40, 0), stoneDark, style.Mat, { Shape = Shape.Ball })
		ctx.Part("StatueHelmCrest", Vector3.new(1.4, 4, 7), at(0, 44, 0.4), style.Stone, style.Mat)
		ctx.Part("StatueSword", Vector3.new(2, 26, 0.8), at(0, 14, -5.2), style.Metal, Mat.Metal) -- 두 손을 모아 칼끝을 땅에 꽂았다
		ctx.Part("StatueGuard", Vector3.new(7, 1.2, 1.2), at(0, 25.5, -5.2), stoneDark, style.Mat)
	end
end

-- 피버 타임: 황금 동전 무더기 + 금빛 불씨 (공통 층은 황금색으로)
local function decorateFever(run, ctx)
	-- 피버 투기장: "돈이 쏟아지는 보물 창고" 느낌. 바닥 / 벽을 금빛으로 물들이고, 금화 더미 / 금괴 / 보물 상자 / 거대 금화를 깐다
	local rng = ctx.Rng
	local center = ctx.Center
	local gold, goldDark, goldLight = Color3.fromRGB(255, 205, 70), Color3.fromRGB(200, 150, 50), Color3.fromRGB(255, 232, 140)
	local wood, woodDark = Color3.fromRGB(120, 72, 38), Color3.fromRGB(80, 46, 24)
	local y0 = center.Y

	-- 1) 기존 지형(바닥 / 벽 / 기둥)을 금빛으로 물들인다: 일반 던전과 한눈에 달라 보이게
	for _, obj in ipairs(run.Folder:GetDescendants()) do
		if obj:IsA("BasePart") and not obj:IsDescendantOf(ctx.Folder) and obj.Transparency < 0.9 then
			obj.Color = obj.Color:Lerp(gold, obj.Material == Mat.Neon and 0.3 or 0.5)
			if obj.Size.Y < 3 and obj.Size.X > 20 then obj.Material = Mat.Marble end -- (넓고 얇은 판 = 바닥: 반들반들한 대리석)
		end
	end
	-- 바닥 가운데 금빛 고리 무늬
	ctx.Disc("FeverRing", Vector3.new(center.X, y0 + 0.35, center.Z), 70, 0.12, gold, Mat.Neon, { Transparency = 0.75 })
	ctx.Disc("FeverRingInner", Vector3.new(center.X, y0 + 0.37, center.Z), 40, 0.12, goldLight, Mat.Neon, { Transparency = 0.82 })

	local function coinPile(base, coins, spread)
		for k = 1, coins do
			local s = rng:NextNumber(1.2, 2.4)
			ctx.Part("CoinPile", Vector3.new(0.35, s * 1.6, s * 1.6),
				CFrame.new(base + Vector3.new(rng:NextNumber(-spread, spread), 0.2 + k * 0.32, rng:NextNumber(-spread, spread)))
					* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 6), math.rad(90) + rng:NextNumber(-0.35, 0.35)),
				k % 3 == 0 and goldLight or (k % 2 == 0 and gold or goldDark), Mat.Metal, { Shape = Shape.Cylinder, Reflectance = 0.25 })
		end
	end
	-- 2) 가장자리: 큰 금화 산
	for _ = 1, 22 do
		coinPile(ctx.Polar(ctx.RimAngle(true), RADIUS - rng:NextNumber(4, 12), 0), rng:NextInteger(6, 10), 2.2)
	end
	-- 3) 바닥 곳곳에 흩어진 금화 (누워 있는 동전)
	for _ = 1, 60 do
		local angle, dist = rng:NextNumber(0, math.pi * 2), rng:NextNumber(18, RADIUS - 14)
		local base = ctx.Polar(angle, dist, 0.2)
		ctx.Part("Coin", Vector3.new(0.25, 1.6, 1.6), CFrame.new(base) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(90)), rng:NextNumber() < 0.5 and gold or goldLight, Mat.Metal, { Shape = Shape.Cylinder, Reflectance = 0.3 })
	end
	-- 4) 금괴 더미 (피라미드처럼 쌓기)
	for _ = 1, 8 do
		local angle = ctx.RimAngle(true)
		local base = ctx.Polar(angle, RADIUS - rng:NextNumber(14, 22), 0)
		local facing = CFrame.lookAt(base, Vector3.new(center.X, base.Y, center.Z))
		for row = 0, 2 do
			for col = 0, 2 - row do
				local offset = Vector3.new((col - (2 - row) / 2) * 2.3, 0.55 + row * 1.0, 0)
				ctx.Part("GoldBar", Vector3.new(2.1, 0.9, 1.1), facing * CFrame.new(offset), row == 2 and goldLight or gold, Mat.Metal, { Reflectance = 0.3 })
			end
		end
	end
	-- 5) 열린 보물 상자 (안에서 금빛이 새어 나온다)
	for n = 1, 6 do
		local angle = ctx.RimAngle(true)
		local base = ctx.Polar(angle, RADIUS - rng:NextNumber(10, 18), 0)
		local facing = CFrame.lookAt(base, Vector3.new(center.X, base.Y, center.Z))
		ctx.Part("ChestBody", Vector3.new(6, 3.4, 4), facing * CFrame.new(0, 1.7, 0), wood, Mat.Wood)
		ctx.Part("ChestBand", Vector3.new(6.2, 0.5, 4.2), facing * CFrame.new(0, 1.2, 0), goldDark, Mat.Metal)
		ctx.Part("ChestBand", Vector3.new(0.6, 3.5, 4.2), facing * CFrame.new(-2.2, 1.7, 0), goldDark, Mat.Metal)
		ctx.Part("ChestBand", Vector3.new(0.6, 3.5, 4.2), facing * CFrame.new(2.2, 1.7, 0), goldDark, Mat.Metal)
		ctx.Part("ChestLid", Vector3.new(6, 0.8, 4), facing * CFrame.new(0, 4.6, 1.8) * CFrame.Angles(math.rad(-70), 0, 0), woodDark, Mat.Wood)
		local glow = ctx.Part("ChestGold", Vector3.new(5.4, 0.9, 3.4), facing * CFrame.new(0, 3.5, 0), goldLight, Mat.Neon, { Transparency = 0.1 })
		if n <= 4 then ctx.Light(glow, gold, 18, 0.8) end
		coinPile(facing * Vector3.new(0, 0, -4), 5, 1.8) -- 상자 앞으로 흘러넘친 금화
	end
	-- 6) 벽 쪽에 세운 거대 금화 (멀리서도 보이는 상징)
	for i = 1, 4 do
		local angle = (i - 0.5) / 4 * math.pi * 2 + 0.3
		local base = ctx.Polar(angle, RADIUS - 6, 0)
		local facing = CFrame.lookAt(base, Vector3.new(center.X, base.Y, center.Z))
		local coin = ctx.Part("GiantCoin", Vector3.new(1.6, 16, 16), facing * CFrame.new(0, 9, 0) * CFrame.Angles(0, math.rad(90), 0), gold, Mat.Metal, { Shape = Shape.Cylinder, Reflectance = 0.35 })
		ctx.Part("GiantCoinFace", Vector3.new(1.7, 11, 11), facing * CFrame.new(0, 9, 0) * CFrame.Angles(0, math.rad(90), 0), goldLight, Mat.Neon, { Shape = Shape.Cylinder, Transparency = 0.55 })
		ctx.Part("GiantCoinBase", Vector3.new(6, 1.4, 4), facing * CFrame.new(0, 0.7, 0), goldDark, Mat.Metal)
		if i <= 2 then ctx.Light(coin, gold, 26, 0.7) end
	end
	-- 7) 공중에서 반짝이는 금가루
	local sky = ctx.Part("GoldSparkle", Vector3.new(200, 1, 200), CFrame.new(center + Vector3.new(0, 2, 0)), gold, Mat.SmoothPlastic, { Transparency = 1 })
	local sparkle = ctx.Emitter(sky)
	if sparkle then
		sparkle.Rate = 30
		sparkle.Lifetime = NumberRange.new(3, 5)
		sparkle.Speed = NumberRange.new(2, 5)
		sparkle.EmissionDirection = Enum.NormalId.Top
		sparkle.Size = NumberSequence.new(0.35)
		sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.15), NumberSequenceKeypoint.new(1, 1) })
		sparkle.Color = ColorSequence.new(gold, goldLight)
		sparkle.LightEmission = 0.9
		sparkle.Shape = Enum.ParticleEmitterShape.Box
	end
end

local DECORATORS = {
	Fever = decorateFever,
	Cave = decorateCave,
	Ice = decorateIce,
	Fire = decorateFire,
	Rift = decorateRift,
}

-- 아레나가 만들어진 직후 한 번 호출한다. typeKey: "Cave" / "Ice" / "Fire" (다른 종류면 아무것도 안 함)
-- helpers: 예약 인자 (지금은 사용 안 함)
function DungeonDecor.Decorate(run, typeKey, helpers)
	local decorate = DECORATORS[typeKey]
	if not decorate or not run or not run.Folder then
		return
	end
	local ctx = newContext(run, run.Folder)
	-- 장식 실패가 던전 시작을 막지 않도록 보호 호출
	local okArena, errArena = pcall(decorateArena, run, ctx, typeKey) -- 모든 테마 공통 층 (먼저: 부품 한도 안에 확실히 들어가게)
	if not okArena then warn("[DungeonDecor] arena layer failed: " .. tostring(errArena)) end
	local ok, err = pcall(decorate, run, ctx)
	if not ok then
		warn("[DungeonDecor] decoration failed: " .. tostring(err))
	end
end

return DungeonDecor
