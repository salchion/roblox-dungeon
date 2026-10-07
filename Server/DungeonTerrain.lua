-- DungeonTerrain (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonTerrain)
-- 던전 아레나를 평평한 원판 대신 "지형"으로 만든다:
--   바깥 산맥(절벽, 넘을 수 없음) / 안쪽 언덕(올라가서 넘기) / 구덩이(떨어지기) /
--   구불구불한 협곡 / 산맥 안으로 파고든 동굴(터널 + 방) / 빛나는 수정(조명)
-- Roblox Terrain 의 FillBall / FillBlock / FillCylinder 로 만들어서 곡선이고 부드럽다.
-- 판마다 무작위로 달라진다 (같은 던전도 매번 다른 모양).

local Terrain = workspace.Terrain
local AIR = Enum.Material.Air

local DungeonTerrain = {}

local function polar(origin, angle, distance, y)
	return Vector3.new(origin.X + math.cos(angle) * distance, y, origin.Z + math.sin(angle) * distance)
end

-- run: { Origin, Id }, theme: Config.Dungeon.Types[..] (Terrain.Ground / Mountain / Accent), D: Config.Dungeon, folder: 장식용 Folder
-- 반환: { SpawnPoints = {Vector3...}, GroundY = function(x, z, fromY) }
function DungeonTerrain.Build(run, theme, D, folder)
	local origin = run.Origin
	local radius = D.ArenaRadius
	local mats = theme.Terrain
	local rng = Random.new(run.Id * 7919 + math.floor(os.clock() * 1000) % 9973)
	local y0 = origin.Y

	local clearings = { -- 지형을 만들지 않는 평지: 시작 지점 / 보스가 서는 곳
		{ Pos = Vector3.new(origin.X, y0, origin.Z), Radius = 28 },
		{ Pos = Vector3.new(origin.X, y0, origin.Z - D.SpawnRadius), Radius = 30 },
	}
	local function inClearing(position, margin)
		for _, c in ipairs(clearings) do
			local flat = Vector3.new(position.X - c.Pos.X, 0, position.Z - c.Pos.Z)
			if flat.Magnitude < c.Radius + (margin or 0) then
				return true
			end
		end
		return false
	end

	-- 1) 바닥: 두꺼운 원기둥 (윗면 = y0)
	Terrain:FillCylinder(CFrame.new(origin.X, y0 - 12, origin.Z), 24, radius + 20, mats.Ground)

	-- 2) 안쪽 언덕: 반쯤 묻힌 공 (완만해서 올라갈 수 있다)
	for _ = 1, 9 do
		for _ = 1, 8 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = rng:NextNumber(32, radius - 40)
			local r = rng:NextNumber(11, 22)
			local center = polar(origin, angle, dist, y0 - r * 0.35)
			if not inClearing(center, r) then
				Terrain:FillBall(center, r, rng:NextNumber() < 0.3 and mats.Accent or mats.Ground)
				break
			end
		end
	end

	-- 3) 구덩이: 떨어졌다가 비탈로 기어 올라와야 한다
	local pits = {}
	for _ = 1, 3 do
		for _ = 1, 8 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = rng:NextNumber(36, radius - 45)
			local r = rng:NextNumber(11, 15)
			local center = polar(origin, angle, dist, y0 + 3)
			if not inClearing(center, r) then
				Terrain:FillBall(center, r, AIR)
				table.insert(pits, center)
				break
			end
		end
	end

	-- 4) 구불구불한 협곡: 사인 곡선을 따라 공을 이어서 파낸다 (한쪽 끝에서 반대쪽 끝까지 휘어짐)
	do
		local startAngle = rng:NextNumber(0, math.pi * 2)
		local sweep = rng:NextNumber(1.4, 2.2) * (rng:NextNumber() < 0.5 and -1 or 1)
		local wobble = rng:NextNumber(10, 18)
		for step = 0, 28 do
			local t = step / 28
			local angle = startAngle + sweep * t
			local dist = 55 + math.sin(t * math.pi * 3) * wobble
			local center = polar(origin, angle, dist, y0 + 1)
			if not inClearing(center, 6) then
				Terrain:FillBall(center, 7.5, AIR)
			end
		end
	end

	-- 5) 바깥 산맥: 지면 위로 불룩한 큰 공들이 이어진 절벽 (바깥이 안 보이고 넘을 수 없다)
	local mountainCount = 26
	for i = 1, mountainCount do
		local angle = (i / mountainCount) * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local r = rng:NextNumber(30, 42)
		local center = polar(origin, angle, radius - 2 + rng:NextNumber(-4, 6), y0 + rng:NextNumber(6, 18))
		Terrain:FillBall(center, r, mats.Mountain)
		if i % 3 == 0 then -- 높은 봉우리
			Terrain:FillBall(polar(origin, angle, radius + 10, y0 + rng:NextNumber(24, 36)), rng:NextNumber(26, 34), mats.Mountain)
		end
	end

	-- 6) 동굴: 산맥 안쪽으로 파고든 터널 + 넓은 방
	local caves = {}
	for index = 1, 3 do
		local angle = (index / 3) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local mouth = polar(origin, angle, radius - 40, y0)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local length = 40
		local center = mouth + direction * (length / 2 - 4)
		-- 터널 (넓이 14, 높이 11)
		Terrain:FillBlock(CFrame.lookAt(center + Vector3.new(0, 5.5, 0), center + direction + Vector3.new(0, 5.5, 0)), Vector3.new(14, 11, length), AIR)
		-- 안쪽 방
		local room = mouth + direction * (length - 2)
		Terrain:FillBall(room + Vector3.new(0, 6, 0), 17, AIR)
		table.insert(caves, { Mouth = mouth, Room = room })

		-- 동굴 속 빛나는 수정
		local crystal = Instance.new("Part")
		crystal.Name = "CaveCrystal"
		crystal.Anchored = true
		crystal.CanCollide = false
		crystal.Size = Vector3.new(2.5, 6, 2.5)
		crystal.CFrame = CFrame.new(room + Vector3.new(0, 3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(rng:NextNumber(-12, 12)))
		crystal.Color = theme.Torch
		crystal.Material = Enum.Material.Neon
		crystal.Parent = folder
		local light = Instance.new("PointLight")
		light.Range = 40
		light.Brightness = 2
		light.Color = theme.Torch
		light.Parent = crystal
	end

	-- 7) 지형 위 조명 수정 몇 개 + 눈에 띄는 랜드마크
	for _ = 1, 9 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(20, radius - 40)
		local position = polar(origin, angle, dist, y0 + 100)
		local result = workspace:Raycast(position, Vector3.new(0, -160, 0))
		if result and result.Instance == Terrain and result.Position.Y > y0 - 2 then
			local crystal = Instance.new("Part")
			crystal.Name = "Crystal"
			crystal.Anchored = true
			crystal.CanCollide = false
			crystal.Size = Vector3.new(1.8, 5, 1.8)
			crystal.CFrame = CFrame.new(result.Position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(rng:NextNumber(-15, 15)))
			crystal.Color = theme.Torch
			crystal.Material = Enum.Material.Neon
			crystal.Parent = folder
			local light = Instance.new("PointLight")
			light.Range = 34
			light.Brightness = 1.6
			light.Color = theme.Torch
			light.Parent = crystal
		end
	end

	-- 8) 보이지 않는 외벽: 산 위로 넘어 나가지 못하게 (바깥 세계는 어차피 안 보임)
	local segments = 24
	local width = 2 * (radius + 12) * math.tan(math.pi / segments) * 1.06
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Size = Vector3.new(width, 220, 4)
		local position = polar(origin, angle, radius + 12, y0 + 90)
		wall.CFrame = CFrame.lookAt(position, Vector3.new(origin.X, y0 + 90, origin.Z))
		wall.Parent = folder
	end

	-- 땅 높이 조회: fromY(대개 현재 높이 + 여유) 에서 아래로 쏜다 (동굴 안 / 산 위 구분을 위해 위에서 쏘지 않는다)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Terrain }
	local function groundY(x, z, fromY)
		local result = workspace:Raycast(Vector3.new(x, (fromY or (y0 + 6)) + 8, z), Vector3.new(0, -80, 0), params)
		return result and result.Position.Y or nil
	end

	-- 9) 몬스터 출현 지점: 평평한 땅에서 무작위로 (구덩이 안 / 산 위는 제외, 동굴 안은 포함)
	local spawnPoints = {}
	local tries = 0
	while #spawnPoints < 40 and tries < 400 do
		tries += 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(40, radius - 36)
		local x = origin.X + math.cos(angle) * dist
		local z = origin.Z + math.sin(angle) * dist
		local result = workspace:Raycast(Vector3.new(x, y0 + 14, z), Vector3.new(0, -50, 0), params)
		if result and result.Normal.Y > 0.9 and result.Position.Y > y0 - 1.5 and result.Position.Y < y0 + 14 then
			table.insert(spawnPoints, result.Position)
		end
	end
	for _, cave in ipairs(caves) do -- 동굴 방에서도 몬스터가 나온다
		for k = 1, 3 do
			table.insert(spawnPoints, cave.Room + Vector3.new(rng:NextNumber(-6, 6), 0.5, rng:NextNumber(-6, 6)))
		end
	end

	return { SpawnPoints = spawnPoints, GroundY = groundY }
end

-- 판이 끝나면 지형을 지운다 (아레나가 차지한 상자를 통째로 비움)
function DungeonTerrain.Clear(run, D)
	local size = (D.ArenaRadius + 60) * 2
	Terrain:FillBlock(CFrame.new(run.Origin.X, run.Origin.Y + 30, run.Origin.Z), Vector3.new(size, 190, size), AIR)
end

return DungeonTerrain
