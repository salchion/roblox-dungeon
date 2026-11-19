-- DungeonBossUnique (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonBossUnique)
-- 던전 군주마다 다른 고유 패턴 (고블린 왕: 돌진 / 금화 폭격, 서리 군주: 얼음 가시 줄기, 화염 군주: 급강하 / 불씨 폭격)
--   DungeonService.lua 가 크기 한도(200,000자)에 닿아 따로 뺐다 (11-19 분할). 함수 몸통은 그대로 옮겼다.
--   DungeonService 의 지역 함수는 Make(ctx) 로 받는다 (FieldBossPatterns 와 같은 방식): ctx = { GetNearestTarget, GroundAt, Walkable, BossAlive, GetAliveParts }
--   돌려주는 표의 키는 DungeonService 의 BOSS_PATTERNS 이름 그대로 (Rush / CoinRain / EmberFall / SpikeLines / Dive)
local Effects = require(script.Parent:WaitForChild("Effects"))
local Guard = require(script.Parent:WaitForChild("DamageGuard"))

local M = {}

function M.Make(ctx)
local getNearestTarget, groundAt, walkable, bossAlive, getAliveParts = ctx.GetNearestTarget, ctx.GroundAt, ctx.Walkable, ctx.BossAlive, ctx.GetAliveParts

local function groundMarker(run, center, radius, color, transparency)
	local marker = Instance.new("Part")
	marker.Shape = Enum.PartType.Cylinder
	marker.Anchored = true
	marker.CanCollide, marker.CanQuery, marker.CanTouch = false, false, false
	marker.Material = Enum.Material.Neon
	marker.Color = color
	marker.Transparency = transparency or 0.55
	marker.Size = Vector3.new(0.4, radius * 2, radius * 2)
	marker.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	marker.Parent = run.Folder
	return marker
end

local function hurtInRadius(run, center, radius, damage, burstColor)
	for _, member in ipairs(run.Members) do
		local root, humanoid = getAliveParts(member)
		if root and Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z).Magnitude <= radius then
			Guard.Take(humanoid, damage)
		end
	end
	Effects.Burst(center + Vector3.new(0, 2, 0), burstColor, 36)
end

-- 고블린 왕 돌진: 앞에 붉은 길이 예고된 뒤 곤봉을 들고 곧장 달려든다 (길 옆으로 피하면 안 맞는다)
local function bossRush(run, part, data)
	local target = getNearestTarget(run, part.Position)
	if not target then return end
	local dir = Vector3.new(target.Position.X - part.Position.X, 0, target.Position.Z - part.Position.Z)
	if dir.Magnitude < 1 then return end
	dir = dir.Unit
	local length = 85
	local base = Vector3.new(part.Position.X, groundAt(run, part.Position.X, part.Position.Z, part.Position.Y) + 0.3, part.Position.Z)
	local warn = Instance.new("Part")
	warn.Anchored, warn.CanCollide, warn.CanQuery, warn.CanTouch = true, false, false, false
	warn.Material, warn.Color, warn.Transparency = Enum.Material.Neon, Color3.fromRGB(255, 70, 40), 0.55
	warn.Size = Vector3.new(part.Size.X * 0.8, 0.4, length)
	warn.CFrame = CFrame.lookAt(base, base + dir) * CFrame.new(0, 0, -length / 2)
	warn.Parent = run.Folder
	data.NoMove = true
	part.CFrame = CFrame.lookAt(part.Position, part.Position + dir)
	task.wait(1.0)
	warn:Destroy()
	local hit = {}
	for _ = 1, 16 do
		if not bossAlive(run, part, data) then break end
		local nx, nz = part.Position.X + dir.X * length / 16, part.Position.Z + dir.Z * length / 16
		if not walkable(run, nx, nz) then break end
		local ny = groundAt(run, nx, nz, part.Position.Y) + data.Stats.Size / 2
		part.CFrame = CFrame.lookAt(Vector3.new(nx, ny, nz), Vector3.new(nx + dir.X, ny, nz + dir.Z))
		for _, member in ipairs(run.Members) do
			local root, humanoid = getAliveParts(member)
			if root and not hit[member] and Vector3.new(root.Position.X - nx, 0, root.Position.Z - nz).Magnitude <= data.Stats.Size / 2 + 3 then
				hit[member] = true
				Guard.Take(humanoid, math.floor(data.Stats.ShotDamage * 1.6))
				Effects.Burst(root.Position, Color3.fromRGB(255, 200, 90), 26)
			end
		end
		task.wait(0.035)
	end
	data.NoMove = false
	Effects.Burst(part.Position, Color3.fromRGB(255, 220, 120), 40)
end

-- 여러 곳에 작은 폭격: 바닥에 원이 예고된 뒤 한꺼번에 터진다 (고블린 왕 = 금화, 화염 군주 = 불씨)
local function bossRain(run, part, data, count, radius, color, delay, damageMult)
	local markers = {}
	for _, member in ipairs(run.Members) do
		local root = getAliveParts(member)
		if root then
			for i = 1, count do
				local jx, jz = i == 1 and 0 or math.random(-34, 34), i == 1 and 0 or math.random(-34, 34)
				local x, z = root.Position.X + jx, root.Position.Z + jz
				if walkable(run, x, z) then
					local center = Vector3.new(x, groundAt(run, x, z, root.Position.Y) + 0.3, z)
					table.insert(markers, { Part = groundMarker(run, center, radius, color), Center = center })
				end
			end
		end
	end
	task.wait(delay)
	if bossAlive(run, part, data) then
		for _, marker in ipairs(markers) do
			hurtInRadius(run, marker.Center, radius, math.floor(data.Stats.ShotDamage * damageMult), color)
		end
	end
	for _, marker in ipairs(markers) do marker.Part:Destroy() end
end
local function bossCoinRain(run, part, data) bossRain(run, part, data, data.Enraged and 7 or 5, 6, Color3.fromRGB(255, 205, 60), 1.3, 1.3) end
local function bossEmberFall(run, part, data) bossRain(run, part, data, data.Enraged and 9 or 6, 7, Color3.fromRGB(255, 120, 40), 1.4, 1.4) end

-- 서리 군주 얼음 가시 줄기: 보스에서 사방으로 가시가 차례로 솟는다 (줄기 사이로 피한다). 두 번째는 줄기가 어긋난다
local function bossSpikeLines(run, part, data)
	local center = Vector3.new(part.Position.X, groundAt(run, part.Position.X, part.Position.Z, part.Position.Y), part.Position.Z)
	local lines = data.Enraged and 10 or 8
	for wave = 0, 1 do
		if not bossAlive(run, part, data) then return end
		local markers = {}
		for i = 0, lines - 1 do
			local angle = (i / lines) * math.pi * 2 + wave * (math.pi / lines)
			for step = 1, 6 do
				local dist = part.Size.X / 2 + step * 11
				local x, z = center.X + math.cos(angle) * dist, center.Z + math.sin(angle) * dist
				if walkable(run, x, z) then
					local at = Vector3.new(x, groundAt(run, x, z, center.Y) + 0.3, z)
					table.insert(markers, { Part = groundMarker(run, at, 4.5, Color3.fromRGB(120, 210, 255), 0.5), Center = at, Delay = step * 0.1 })
				end
			end
		end
		task.wait(0.9)
		local started = os.clock()
		local pending = #markers
		while pending > 0 and bossAlive(run, part, data) do
			local elapsed = os.clock() - started
			for _, marker in ipairs(markers) do
				if marker.Part and elapsed >= marker.Delay then
					hurtInRadius(run, marker.Center, 4.5, math.floor(data.Stats.ShotDamage * 1.2), Color3.fromRGB(170, 235, 255))
					marker.Part:Destroy()
					marker.Part = nil
					pending -= 1
				end
			end
			task.wait(0.03)
		end
		for _, marker in ipairs(markers) do if marker.Part then marker.Part:Destroy() end end
		task.wait(0.35)
	end
end

-- 화염 군주 급강하: 하늘로 날아올랐다가 플레이어가 있던 자리로 내리꽂는다 (큰 붉은 원 밖으로 피한다)
local function bossDive(run, part, data)
	local target = getNearestTarget(run, part.Position)
	if not target then return end
	local radius = 15
	local spot = Vector3.new(target.Position.X, groundAt(run, target.Position.X, target.Position.Z, target.Position.Y), target.Position.Z)
	local marker = groundMarker(run, spot + Vector3.new(0, 0.3, 0), radius, Color3.fromRGB(255, 70, 40), 0.55)
	data.NoMove = true
	local start = part.Position
	for i = 1, 12 do
		if not bossAlive(run, part, data) then break end
		part.CFrame = CFrame.new(start + Vector3.new(0, i * 4, 0)) * (part.CFrame - part.CFrame.Position)
		task.wait(0.05)
	end
	task.wait(0.7)
	if bossAlive(run, part, data) then
		local y = groundAt(run, spot.X, spot.Z, spot.Y) + data.Stats.Size / 2
		part.CFrame = CFrame.new(Vector3.new(spot.X, y, spot.Z)) * (part.CFrame - part.CFrame.Position)
		hurtInRadius(run, spot, radius, math.floor(data.Stats.ShotDamage * 1.9), Color3.fromRGB(255, 120, 40))
		Effects.Burst(spot + Vector3.new(0, 3, 0), Color3.fromRGB(255, 200, 90), 70)
		task.wait(0.5)
	end
	marker:Destroy()
	data.NoMove = false
end

return { Rush = bossRush, CoinRain = bossCoinRain, EmberFall = bossEmberFall, SpikeLines = bossSpikeLines, Dive = bossDive }
end

return M
