-- DungeonTerrain (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonTerrain)
-- 로그라이크식 던전 지형: 들어갈 때마다 "배치 유형"과 모양이 무작위로 새로 만들어진다.
--   동굴 군락  : 크고 작은 방이 구불구불 이어진 동굴 (방마다 모양이 다름)
--   협곡 길    : 좁은 길이 길게 꺾이며 이어지고 양 끝에 넓은 방 (한쪽 끝 = 입구, 반대쪽 끝 = 보스방)
--   허브와 갈래: 가운데 광장에서 여러 갈래 길이 뻗어 각각 방으로 이어짐
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

-- 동굴 군락: 방 5~6개가 이어진다
layouts.Cavern = function(rng, limit)
	local circles = {}
	local count = rng:NextInteger(6, 8)
	local rooms = {}
	local angle = rng:NextNumber(0, math.pi * 2)
	local pos = polar(angle + math.pi, limit * 0.7)
	local heading = angle + rng:NextNumber(-0.5, 0.5)
	local previousR, start, boss
	for i = 1, count do
		local r = (i == 1 and 34) or (i == count and 46) or rng:NextNumber(24, 40)
		if previousR then
			local step = (r + previousR) * 0.62
			heading += rng:NextNumber(-1.1, 1.1)
			local candidate = pos + polar(heading, step)
			if candidate.Magnitude > limit then -- 가장자리로 벗어나면 중심 쪽으로 방향 보정
				heading = math.atan2(-pos.Z, -pos.X) + rng:NextNumber(-0.5, 0.5)
				candidate = pos + polar(heading, step)
			end
			chain(circles, pos, candidate, 11, rng) -- 방 사이 통로
			pos = candidate
		end
		table.insert(circles, { Pos = pos, R = r })
		table.insert(rooms, { Pos = pos, R = r })
		if i == 1 then start = pos end
		if i == count then boss = pos end
		previousR = r
	end
	return { Circles = circles, Rooms = rooms, Start = start, Boss = boss, Name = "동굴 군락" }
end

-- 협곡 길: 한쪽에서 반대쪽까지 사인 곡선으로 휘어진 긴 길
layouts.Canyon = function(rng, limit)
	local circles = {}
	local angle = rng:NextNumber(0, math.pi * 2)
	local startPos = polar(angle, limit * 0.78)
	local bossPos = polar(angle + math.pi + rng:NextNumber(-0.4, 0.4), limit * 0.78)
	local along = bossPos - startPos
	local side = Vector3.new(-along.Z, 0, along.X).Unit
	local waves = rng:NextInteger(2, 3)
	local amplitude = rng:NextNumber(30, 48) * (rng:NextNumber() < 0.5 and 1 or -1)
	local steps = math.floor(along.Magnitude / 7)
	for i = 0, steps do
		local t = i / steps
		local p = startPos:Lerp(bossPos, t) + side * math.sin(t * math.pi * waves) * amplitude * math.sin(t * math.pi)
		table.insert(circles, { Pos = p, R = 11 + rng:NextNumber(-1.5, 2.5) })
	end
	table.insert(circles, { Pos = startPos, R = 34 })
	table.insert(circles, { Pos = bossPos, R = 46 })
	local rooms = { { Pos = startPos, R = 34 } }
	for _, t in ipairs({ 0.2, 0.4, 0.6, 0.8 }) do -- 중간 넓은 방 (전투 / 이벤트가 열리는 곳)
		local p = startPos:Lerp(bossPos, t) + side * math.sin(t * math.pi * waves) * amplitude * math.sin(t * math.pi)
		local r = rng:NextNumber(22, 30)
		table.insert(circles, { Pos = p, R = r })
		table.insert(rooms, { Pos = p, R = r })
	end
	table.insert(rooms, { Pos = bossPos, R = 46 })
	return { Circles = circles, Rooms = rooms, Start = startPos, Boss = bossPos, Name = "구불구불한 협곡 길" }
end

-- 허브와 갈래: 가운데 광장 + 방사형 길 3~4개 (각 끝에 방, 그중 하나가 보스방)
layouts.Hub = function(rng, limit)
	local circles = {}
	local hub = Vector3.zero
	table.insert(circles, { Pos = hub, R = 38 })
	local arms = rng:NextInteger(3, 4)
	local offset = rng:NextNumber(0, math.pi * 2)
	local bossArm = rng:NextInteger(1, arms)
	local boss
	local rooms = { { Pos = hub, R = 38 } }
	local bossRoom
	for i = 1, arms do
		local angle = offset + (i / arms) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local distance = limit * rng:NextNumber(0.62, 0.74)
		local roomPos = polar(angle, distance)
		chain(circles, polar(angle, 30), roomPos, 11, rng)
		local r = i == bossArm and 44 or rng:NextNumber(24, 32)
		table.insert(circles, { Pos = roomPos, R = r })
		if i == bossArm then
			boss = roomPos
			bossRoom = { Pos = roomPos, R = r }
		else
			table.insert(rooms, { Pos = roomPos, R = r })
		end
	end
	table.insert(rooms, bossRoom) -- 보스방이 마지막
	return { Circles = circles, Rooms = rooms, Start = hub, Boss = boss, Name = "허브와 갈래 길" }
end

local LAYOUT_ORDER = { "Cavern", "Canyon", "Hub" }

------------------------------------------------------------
-- 지형 만들기
-- run: { Origin, Id }, theme: Config.Dungeon.Types[..] (Terrain.Ground / Mountain / Accent), D: Config.Dungeon, folder: 장식용 Folder
-- 반환: { SpawnPoints, GroundY, StartPos, BossPos, LayoutName }
------------------------------------------------------------
function DungeonTerrain.Build(run, theme, D, folder)
	local origin = run.Origin
	local radius = D.ArenaRadius
	local mats = theme.Terrain
	local rng = Random.new(run.Id * 7919 + math.floor(os.clock() * 1000) % 99991)
	local y0 = origin.Y
	local limit = radius - 38 -- 방 중심이 놓일 수 있는 최대 거리

	local layout = layouts[LAYOUT_ORDER[rng:NextInteger(1, #LAYOUT_ORDER)]](rng, limit)
	local function world(relative)
		return Vector3.new(origin.X + relative.X, y0, origin.Z + relative.Z)
	end

	-- 1) 암반 덩어리: 바닥 아래부터 절벽 높이까지 가득 채운다
	Terrain:FillCylinder(CFrame.new(origin.X, y0 + (WALL_HEIGHT - 12) / 2, origin.Z), WALL_HEIGHT + 12, radius + 20, mats.Mountain)
	-- 일부 구간은 보조 재질로 (절벽에 얼룩무늬)
	for _ = 1, 10 do
		local p = world(polar(rng:NextNumber(0, math.pi * 2), rng:NextNumber(radius * 0.5, radius)))
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

	-- 4) 방 안의 언덕(올라가기) / 구덩이(떨어지기): 큰 방에만, 입구와 보스방 중앙은 비워둔다
	local rooms = {}
	for _, circle in ipairs(layout.Circles) do
		if circle.R >= 22 then
			table.insert(rooms, circle)
		end
	end
	for _, circle in ipairs(rooms) do
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

	-- 6) 보이지 않는 외벽 (절벽 위로 넘어가는 걸 막는 안전장치)
	local segments = 24
	local width = 2 * (radius + 14) * math.tan(math.pi / segments) * 1.06
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Size = Vector3.new(width, 260, 4)
		local position = origin + polar(angle, radius + 14) + Vector3.new(0, 100, 0)
		wall.CFrame = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z))
		wall.Parent = folder
	end

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

	return {
		SpawnPoints = spawnPoints, Rooms = roomData, GroundY = groundY, StartPos = startPos, BossPos = bossPos, LayoutName = layout.Name,
	}
end

-- 판이 끝나면 지형을 지운다 (아레나가 차지한 상자를 통째로 비움)
function DungeonTerrain.Clear(run, D)
	local size = (D.ArenaRadius + 60) * 2
	Terrain:FillBlock(CFrame.new(run.Origin.X, run.Origin.Y + 40, run.Origin.Z), Vector3.new(size, 200, size), AIR)
end

return DungeonTerrain
