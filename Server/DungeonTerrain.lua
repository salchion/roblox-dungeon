-- DungeonTerrain (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonTerrain)
-- 로그라이크식 던전 지형: 들어갈 때마다 "배치 유형"과 모양이 무작위로 새로 만들어진다.
--   동굴 군락  : 크고 작은 방이 구불구불 이어진 동굴 (방마다 모양이 다름)
--   협곡 길    : 좁은 길이 길게 꺾이며 이어지고 양 끝에 넓은 방 (한쪽 끝 = 입구, 반대쪽 끝 = 보스방)
--   (모두 입구에서 보스방까지 "앞으로 쭉" 이어지는 한 줄 구조)
-- 원리: 거대한 암반 덩어리(Terrain)를 먼저 채우고, 원기둥 모양 빈 공간을 이어 붙여 길과 방을 파낸다.
--       위가 뚫린 절벽 지형이라 사방이 가려지고, 안에 언덕(올라가기)과 구덩이(떨어지기)가 흩어진다.

local Terrain = workspace.Terrain
local AIR = Enum.Material.Air

local DungeonTerrain = {}

local WALL_HEIGHT = 90 -- 절벽 높이

local function polar(angle, distance)
	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

------------------------------------------------------------
-- 배치 유형: 원(중심, 반지름) 목록으로 길과 방을 표현한다 (좌표는 아레나 중심 기준 상대값)
-- 반환: { Circles = {{Pos, R}}, Start = Vector3, Boss = Vector3, Name = "..." }
------------------------------------------------------------
local function chain(circles, from, to, radius, rng)
	local distance = (to - from).Magnitude
	local steps = math.max(1, math.floor(distance / 7))
	for i = 0, steps do
		local p = from:Lerp(to, i / steps)
		table.insert(circles, { Pos = p, R = radius + rng:NextNumber(-1.5, 2) })
	end
end

local layouts = {}

-- 모든 배치는 +X 방향으로 "쭉 나아가는" 긴 띠 모양이다: 시작방(x=0) -> ... -> 보스방(x=length).
-- length 만큼 앞으로 이어지고, 좌우(Z)로는 완만하게만 흔들린다.

-- 동굴 군락: 크고 작은 방 8~10개가 통로로 이어진다 (방마다 크기 / 좌우 위치가 다름)
layouts.Cavern = function(rng, length, sway)
	local circles = {}
	local rooms = {}
	local count = rng:NextInteger(6, 7)
	local spacing = length / (count - 1)
	local z = 0
	local previous, start, boss
	for i = 1, count do
		local r = (i == 1 and 40) or (i == count and 80) or rng:NextNumber(42, 54)
		z = math.clamp(z + rng:NextNumber(-sway * 0.45, sway * 0.45), -sway * 0.7, sway * 0.7)
		if i == 1 or i == count then z = 0 end
		local pos = Vector3.new((i - 1) * spacing + (i > 1 and i < count and rng:NextNumber(-12, 12) or 0), 0, z)
		if previous then
			chain(circles, previous, pos, 26, rng) -- 방 사이 통로 (넓게: 피하기 쉽도록)
		end
		table.insert(circles, { Pos = pos, R = r })
		table.insert(rooms, { Pos = pos, R = r })
		if i == 1 then start = pos end
		if i == count then boss = pos end
		previous = pos
	end
	return { Circles = circles, Rooms = rooms, Start = start, Boss = boss, Name = "동굴 군락" }
end

-- 협곡 길: 사인 곡선으로 굽이치는 긴 길 + 길 중간중간 넓은 방
layouts.Canyon = function(rng, length, sway)
	local circles = {}
	local startPos = Vector3.new(0, 0, 0)
	local bossPos = Vector3.new(length, 0, 0)
	local waves = rng:NextInteger(2, 3)
	local amplitude = sway * rng:NextNumber(0.4, 0.7) * (rng:NextNumber() < 0.5 and 1 or -1)
	local function at(t)
		return Vector3.new(length * t, 0, math.sin(t * math.pi * waves) * amplitude * math.sin(t * math.pi))
	end
	local steps = math.floor(length / 7)
	for i = 0, steps do
		table.insert(circles, { Pos = at(i / steps), R = 26 + rng:NextNumber(-1.5, 2.5) })
	end
	table.insert(circles, { Pos = startPos, R = 40 })
	table.insert(circles, { Pos = bossPos, R = 80 })
	local rooms = { { Pos = startPos, R = 40 } }
	for _, t in ipairs({ 0.2, 0.4, 0.6, 0.78 }) do -- 중간 넓은 방 (전투 / 이벤트가 열리는 곳)
		local p = at(t)
		local r = rng:NextNumber(42, 52)
		table.insert(circles, { Pos = p, R = r })
		table.insert(rooms, { Pos = p, R = r })
	end
	table.insert(rooms, { Pos = bossPos, R = 80 })
	return { Circles = circles, Rooms = rooms, Start = startPos, Boss = bossPos, Name = "구불구불한 협곡 길" }
end

local LAYOUT_ORDER = { "Cavern", "Canyon" } -- 모두 입구에서 보스방까지 한 줄로 이어지는 길

------------------------------------------------------------
-- 지형 만들기
-- run: { Origin, Id }, theme: Config.Dungeon.Types[..] (Terrain.Ground / Mountain / Accent), D: Config.Dungeon, folder: 장식용 Folder
-- 반환: { SpawnPoints, GroundY, StartPos, BossPos, LayoutName }
------------------------------------------------------------
function DungeonTerrain.Build(run, theme, D, folder)
	local origin = run.Origin
	local length = D.ArenaLength   -- 시작방 -> 보스방 거리 (+X 방향으로 쭉)
	local halfWidth = D.ArenaWidth / 2
	local mats = theme.Terrain
	local rng = Random.new(run.Id * 7919 + math.floor(os.clock() * 1000) % 99991)
	local y0 = origin.Y

	local layout = layouts[LAYOUT_ORDER[rng:NextInteger(1, #LAYOUT_ORDER)]](rng, length, halfWidth - 70)
	local function world(relative)
		return Vector3.new(origin.X + relative.X, y0, origin.Z + relative.Z)
	end

	-- 1) 암반 덩어리: 바닥 아래부터 절벽 높이까지 가득 채운다
	Terrain:FillBlock(CFrame.new(origin.X + length / 2, y0 + (WALL_HEIGHT - 12) / 2, origin.Z), Vector3.new(length + 160, WALL_HEIGHT + 12, D.ArenaWidth), mats.Mountain)
	-- 일부 구간은 보조 재질로 (절벽에 얼룩무늬)
	for _ = 1, 24 do
		local p = world(Vector3.new(rng:NextNumber(-40, length + 40), 0, rng:NextNumber(-halfWidth, halfWidth)))
		Terrain:FillBall(Vector3.new(p.X, y0 + rng:NextNumber(5, 50), p.Z), rng:NextNumber(12, 22), mats.Accent)
	end

	-- 2) 길과 방 파내기 (위가 뚫린 원기둥 빈 공간)
	for _, circle in ipairs(layout.Circles) do
		local p = world(circle.Pos)
		Terrain:FillCylinder(CFrame.new(p.X, y0 + WALL_HEIGHT / 2 + 2, p.Z), WALL_HEIGHT + 4, circle.R, AIR)
	end
	-- 3) 바닥 재질 (파낸 곳마다 얇게 덮는다)
	for _, circle in ipairs(layout.Circles) do
		local p = world(circle.Pos)
		Terrain:FillCylinder(CFrame.new(p.X, y0 - 2, p.Z), 4, circle.R, mats.Ground)
	end

	local startPos = world(layout.Start)
	local bossPos = world(layout.Boss)
	local function protected(p, margin)
		return (Vector3.new(p.X, 0, p.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude < 32 + margin
			or (Vector3.new(p.X, 0, p.Z) - Vector3.new(bossPos.X, 0, bossPos.Z)).Magnitude < 34 + margin
	end

	-- 4) (비활성) 방 안의 언덕 / 구덩이: 지형을 단순하게 하려고 만들지 않는다
	local rooms = {}
	for _, circle in ipairs(layout.Circles) do
		if circle.R >= 22 then
			table.insert(rooms, circle)
		end
	end
	for _, circle in ipairs({}) do -- (단순한 지형을 위해 언덕 / 구덩이는 만들지 않는다)
		for _ = 1, 2 do
			local p = world(circle.Pos) + polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, circle.R * 0.55))
			local r = rng:NextNumber(8, 14)
			if not protected(p, r) then
				if rng:NextNumber() < 0.6 then
					Terrain:FillBall(Vector3.new(p.X, y0 - r * 0.35, p.Z), r, rng:NextNumber() < 0.3 and mats.Accent or mats.Ground) -- 언덕
				else
					Terrain:FillBall(Vector3.new(p.X, y0 + 3, p.Z), r * 0.9, AIR) -- 구덩이
				end
			end
		end
	end

	-- 5) 조명 수정 (방마다 하나씩)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Terrain }
	for _, circle in ipairs(rooms) do
		local p = world(circle.Pos) + polar(rng:NextNumber(0, math.pi * 2), circle.R * 0.6)
		local result = workspace:Raycast(Vector3.new(p.X, y0 + 40, p.Z), Vector3.new(0, -100, 0), params)
		if result and result.Normal.Y > 0.8 then
			local crystal = Instance.new("Part")
			crystal.Name = "Crystal"
			crystal.Anchored = true
			crystal.CanCollide = false
			crystal.Size = Vector3.new(2.2, 6, 2.2)
			crystal.CFrame = CFrame.new(result.Position + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(rng:NextNumber(-14, 14)))
			crystal.Color = theme.Torch
			crystal.Material = Enum.Material.Neon
			crystal.Parent = folder
			local light = Instance.new("PointLight")
			light.Range = 44
			light.Brightness = 2
			light.Color = theme.Torch
			light.Parent = crystal
		end
	end

	-- 6) 보이지 않는 외벽 (절벽 위로 넘어가는 걸 막는 안전장치): 긴 상자 둘레 4면
	local function invisibleWall(size, position)
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Size = size
		wall.Position = position
		wall.Parent = folder
	end
	local cx = origin.X + length / 2
	invisibleWall(Vector3.new(length + 200, 260, 4), Vector3.new(cx, y0 + 100, origin.Z + halfWidth + 2))
	invisibleWall(Vector3.new(length + 200, 260, 4), Vector3.new(cx, y0 + 100, origin.Z - halfWidth - 2))
	invisibleWall(Vector3.new(4, 260, D.ArenaWidth + 8), Vector3.new(origin.X - 82, y0 + 100, origin.Z))
	invisibleWall(Vector3.new(4, 260, D.ArenaWidth + 8), Vector3.new(origin.X + length + 82, y0 + 100, origin.Z))

	local function groundY(x, z, fromY)
		local result = workspace:Raycast(Vector3.new(x, (fromY or (y0 + 6)) + 8, z), Vector3.new(0, -80, 0), params)
		-- 바닥 근처 높이만 인정 (절벽 위 / 암반 속에서 잘못 잡힌 높이는 무시 -> 몬스터가 절벽 위로 떠오르지 않게)
		if result and result.Position.Y > y0 - 14 and result.Position.Y < y0 + 18 then
			return result.Position.Y
		end
		return nil
	end

	-- 7) 몬스터 출현 지점: 방과 길 안의 평평한 땅 (입구 근처는 제외)
	-- 방마다 출현 지점 (방 순서대로 진행하며 그 방에서만 몬스터가 나온다)
	local roomData = {}
	for _, room in ipairs(layout.Rooms) do
		local entry = { Pos = world(room.Pos), R = room.R, Spawns = {} }
		for _ = 1, 40 do
			if #entry.Spawns >= 14 then break end
			local p = entry.Pos + polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(room.R * 0.15, room.R * 0.8))
			local result = workspace:Raycast(Vector3.new(p.X, y0 + 14, p.Z), Vector3.new(0, -50, 0), params)
			if result and result.Normal.Y > 0.9 and result.Position.Y > y0 - 1.5 and result.Position.Y < y0 + 14 then
				table.insert(entry.Spawns, result.Position)
			end
		end
		table.insert(roomData, entry)
	end

	local spawnPoints = {}
	local tries = 0
	while #spawnPoints < 48 and tries < 600 do
		tries += 1
		local circle = layout.Circles[rng:NextInteger(1, #layout.Circles)]
		local p = world(circle.Pos) + polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, circle.R * 0.8))
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude > 38 then
			local result = workspace:Raycast(Vector3.new(p.X, y0 + 14, p.Z), Vector3.new(0, -50, 0), params)
			if result and result.Normal.Y > 0.9 and result.Position.Y > y0 - 1.5 and result.Position.Y < y0 + 14 then
				table.insert(spawnPoints, result.Position)
			end
		end
	end

	local worldCircles = {}
	for _, circle in ipairs(layout.Circles) do
		local p = world(circle.Pos)
		table.insert(worldCircles, { X = p.X, Z = p.Z, R = circle.R })
	end

	return {
		Circles = worldCircles, SpawnPoints = spawnPoints, Rooms = roomData, GroundY = groundY, StartPos = startPos, BossPos = bossPos, LayoutName = layout.Name,
	}
end


------------------------------------------------------------
-- 콜로세움: 둥근 투기장 하나. 중앙에서 버티며 사방의 문에서 쏟아져 나오는 몬스터를 막아 낸다 (뱀서 느낌).
--   바닥 지름 약 220 / 돌벽 + 관중석 + 8개의 출입문 + 횃불 / 가운데 제단. 길 / 방 / 언덕 없이 한 판의 평평한 모래 바닥이라 몬스터가 안 보이거나 막히는 일이 없다.
-- 반환 형식은 Build 와 같다 (Circles 는 걸을 수 있는 원 하나).
------------------------------------------------------------
function DungeonTerrain.BuildColosseum(run, theme, D, folder)
	local origin = run.Origin
	local mats = theme.Terrain
	local y0 = origin.Y
	local R = 110
	local center = Vector3.new(origin.X + 140, y0, origin.Z)
	local rng = Random.new(run.Id * 7919 + math.floor(os.clock() * 1000) % 99991)

	-- 1) 암반 덩어리를 채우고 둥근 투기장을 파낸 뒤 바닥을 깐다
	Terrain:FillBlock(CFrame.new(center.X, y0 + (WALL_HEIGHT - 12) / 2, center.Z), Vector3.new(R * 2 + 140, WALL_HEIGHT + 12, R * 2 + 140), mats.Mountain)
	Terrain:FillCylinder(CFrame.new(center.X, y0 + WALL_HEIGHT / 2 + 2, center.Z), WALL_HEIGHT + 4, R + 2, AIR)
	Terrain:FillCylinder(CFrame.new(center.X, y0 - 2, center.Z), 4, R + 2, mats.Ground)

	local stone = Color3.fromRGB(122, 116, 108):Lerp(theme.MonsterColor or Color3.new(1, 1, 1), 0.12)
	local dark = stone:Lerp(Color3.new(0, 0, 0), 0.45)
	local function part(name, size, cframe, color, material, props)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material or Enum.Material.Slate
		for key, value in pairs(props or {}) do
			p[key] = value
		end
		p.Parent = folder
		return p
	end

	-- 2) 돌벽 (바깥으로 점점 높아지는 관중석 3단) + 8개의 출입문 + 횃불
	local SEGMENTS = 48
	local gateEvery = SEGMENTS / 8
	local segmentWidth = 2 * math.pi * (R + 3) / SEGMENTS + 0.6
	for i = 0, SEGMENTS - 1 do
		local angle = (i / SEGMENTS) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local isGate = i % gateEvery == 0
		for tier = 1, 3 do
			local radius = R + 3 + (tier - 1) * 7
			local height = isGate and tier == 1 and 10 or (14 + tier * 12)
			local position = center + radial * radius + Vector3.new(0, height / 2, 0)
			part("Stand" .. tier, Vector3.new(segmentWidth, height, 7), CFrame.lookAt(position, position + radial) , tier == 1 and stone or stone:Lerp(dark, 0.25 * tier), tier == 1 and Enum.Material.Brick or Enum.Material.Slate)
		end
		if isGate then
			-- 출입문: 어두운 아치 + 테마색 테두리 (여기서 몬스터가 나온다)
			local gatePos = center + radial * (R + 1.5)
			part("GateDark", Vector3.new(segmentWidth * 0.7, 16, 2), CFrame.lookAt(gatePos + Vector3.new(0, 8, 0), gatePos + Vector3.new(0, 8, 0) + radial), Color3.fromRGB(12, 10, 14), Enum.Material.SmoothPlastic, { CanCollide = false })
			local frame = part("GateGlow", Vector3.new(segmentWidth * 0.85, 1, 2.4), CFrame.lookAt(gatePos + Vector3.new(0, 16.5, 0), gatePos + Vector3.new(0, 16.5, 0) + radial), theme.Torch, Enum.Material.Neon, { CanCollide = false })
			local light = Instance.new("PointLight")
			light.Range = 34
			light.Brightness = 1.6
			light.Color = theme.Torch
			light.Parent = frame
		elseif i % 3 == 1 then
			-- 횃불 기둥
			local base = center + radial * (R - 1.5)
			part("TorchPost", Vector3.new(1.6, 9, 1.6), CFrame.new(base + Vector3.new(0, 4.5, 0)), dark, Enum.Material.Metal, { CanCollide = false })
			local flame = part("Torch", Vector3.new(2, 2, 2), CFrame.new(base + Vector3.new(0, 10, 0)), theme.Torch, Enum.Material.Neon, { CanCollide = false, Shape = Enum.PartType.Ball })
			local light = Instance.new("PointLight")
			light.Range = 40
			light.Brightness = 2
			light.Color = theme.Torch
			light.Parent = flame
			local fire = Instance.new("ParticleEmitter")
			fire.Rate = 18
			fire.Lifetime = NumberRange.new(0.5, 1)
			fire.Speed = NumberRange.new(2, 5)
			fire.SpreadAngle = Vector2.new(20, 20)
			fire.EmissionDirection = Enum.NormalId.Top
			fire.LightEmission = 1
			fire.Color = ColorSequence.new(theme.Torch, Color3.fromRGB(255, 240, 170))
			fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
			fire.Parent = flame
		end
	end

	-- 3) 보이지 않는 높은 벽 (돌벽 위로 넘어가지 못하게)
	for i = 0, 23 do
		local angle = (i / 24) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = center + radial * (R + 2) + Vector3.new(0, 130, 0)
		part("Barrier", Vector3.new(2 * math.pi * (R + 2) / 24 + 1, 260, 3), CFrame.lookAt(position, position + radial), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, CanQuery = false })
	end

	-- 4) 바닥 장식: 테마색 동심원 고리 + 가운데 제단(밟고 서는 곳) + 방사형 문양
	for index, radius in ipairs({ 30, 62, 94 }) do
		part("FloorRing", Vector3.new(0.3, radius * 2, radius * 2), CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), theme.Torch:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, Transparency = 0.82 - index * 0.04, CanQuery = false })
	end
	part("Dais", Vector3.new(0.5, 26, 26), CFrame.new(center + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90)), stone, Enum.Material.Marble, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false })
	local glow = part("DaisGlow", Vector3.new(0.6, 20, 20), CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), theme.Torch, Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, Transparency = 0.55, CanQuery = false })
	local daisLight = Instance.new("PointLight")
	daisLight.Range = 50
	daisLight.Brightness = 1.2
	daisLight.Color = theme.Torch
	daisLight.Parent = glow
	for i = 0, 7 do
		local angle = (i / 8) * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		part("FloorSpoke", Vector3.new(0.25, 3, R - 40), CFrame.lookAt(center + dir * ((R + 6) / 2 + 12) + Vector3.new(0, 0.25, 0), center + dir * 200 + Vector3.new(0, 0.25, 0)), theme.Torch:Lerp(Color3.new(0, 0, 0), 0.4), Enum.Material.Neon, { CanCollide = false, Transparency = 0.8, CanQuery = false })
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Terrain }
	local function groundY(x, z, fromY)
		local result = workspace:Raycast(Vector3.new(x, (fromY or (y0 + 6)) + 8, z), Vector3.new(0, -80, 0), params)
		if result and result.Position.Y > y0 - 14 and result.Position.Y < y0 + 18 then
			return result.Position.Y
		end
		return nil
	end

	-- 5) 몬스터 출현 지점: 가장자리 안쪽의 고리 (출입문 앞) / 보스는 동쪽 큰 문 앞
	local spawnPoints = {}
	for i = 0, 47 do
		local angle = (i / 48) * math.pi * 2
		local radius = R - 14 + rng:NextNumber(-4, 4)
		table.insert(spawnPoints, Vector3.new(center.X + math.cos(angle) * radius, y0, center.Z + math.sin(angle) * radius))
	end
	local startPos = center + Vector3.new(0, 0, 0)
	local bossPos = center + Vector3.new(R - 34, 0, 0)

	return {
		Circles = { { X = center.X, Z = center.Z, R = R - 1 } },
		SpawnPoints = spawnPoints,
		Rooms = nil,
		GroundY = groundY,
		StartPos = startPos,
		BossPos = bossPos,
		LayoutName = "콜로세움 (중앙에서 버티세요!)",
		Center = center,
	}
end

-- 판이 끝나면 지형을 지운다 (아레나가 차지한 상자를 통째로 비움)
function DungeonTerrain.Clear(run, D)
	-- 콜로세움(원형, 중심이 Origin + 140) 과 예전 긴 길 지형 둘 다 지운다
	Terrain:FillBlock(CFrame.new(run.Origin.X + 140, run.Origin.Y + 40, run.Origin.Z), Vector3.new(420, 200, 420), AIR)
	Terrain:FillBlock(CFrame.new(run.Origin.X + D.ArenaLength / 2, run.Origin.Y + 40, run.Origin.Z), Vector3.new(D.ArenaLength + 240, 200, D.ArenaWidth + 60), AIR)
end

return DungeonTerrain
