-- FieldBossPatterns (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldBossPatterns)
-- 필드 구역 군주(2~8구역)마다 하나씩 있는 "고유 패턴". 기본 패턴(내려찍기 / 돌진 / 나선)에 더해 FieldService 의 군주 패턴 뽑기에 섞인다.
--   2구역 뿔 질주(Stampede) / 3구역 바위 소나기 / 4구역 독 웅덩이 / 5구역 얼음 가시줄 / 6구역 유성우 / 7구역 순간이동 베기 / 8구역 심연 광선
-- 모든 패턴은 "경고 표시 -> 잠깐 뒤 피해" 순서라 피할 수 있다. 부품은 잠깐 쓰고 지운다(서버 부담을 줄이려고 개수를 작게 유지).
-- FieldService 가 Init(ctx) 로 필요한 함수들을 넘겨준다 (FieldService 파일이 Studio 한계(200KB)에 가까워 따로 뺐다).

local TweenService = game:GetService("TweenService")

local P = {}

local ctx
local function worldFolder() return ctx.GetWorldFolder() end

local function alive(part, data) return ctx.Monsters[part] == data end

-- 바닥에 원 경고 -> delay 뒤 폭발 (반지름 안의 플레이어에게 피해)
local function disc(part, data, spot, radius, delay, damage, color)
	local warn = Instance.new("Part")
	warn.Shape = Enum.PartType.Cylinder
	warn.Size = Vector3.new(0.3, radius * 2, radius * 2)
	warn.CFrame = CFrame.new(spot.X, ctx.FloorAt(spot.X) + 0.3, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
	warn.Anchored, warn.CanCollide, warn.CanQuery = true, false, false
	warn.Material = Enum.Material.Neon
	warn.Color = color or Color3.fromRGB(255, 90, 60)
	warn.Transparency = 0.6
	warn.Parent = worldFolder()
	TweenService:Create(warn, TweenInfo.new(delay), { Transparency = 0.15 }):Play()
	task.delay(delay, function()
		warn:Destroy()
		if not alive(part, data) then return end
		ctx.Effects.Burst(Vector3.new(spot.X, ctx.FloorAt(spot.X) + 2, spot.Z), color or Color3.fromRGB(255, 140, 70), 40)
		for _, entry in ipairs(ctx.PlayersNear(spot, radius)) do
			ctx.Guard.Take(entry.Humanoid, damage)
		end
	end)
end

-- 바닥에 길쭉한 띠 경고 -> delay 뒤 띠 안의 플레이어에게 피해 (origin 에서 dir 방향으로 length, 너비 width)
local function strip(part, data, origin, dir, length, width, delay, damage, color)
	local base = Vector3.new(origin.X, ctx.FloorAt(origin.X) + 0.3, origin.Z)
	local warn = Instance.new("Part")
	warn.Size = Vector3.new(width, 0.3, length)
	warn.CFrame = CFrame.lookAt(base + dir * (length / 2), base + dir * length)
	warn.Anchored, warn.CanCollide, warn.CanQuery = true, false, false
	warn.Material = Enum.Material.Neon
	warn.Color = color or Color3.fromRGB(255, 90, 60)
	warn.Transparency = 0.6
	warn.Parent = worldFolder()
	TweenService:Create(warn, TweenInfo.new(delay), { Transparency = 0.15 }):Play()
	task.delay(delay, function()
		warn:Destroy()
		if not alive(part, data) then return end
		ctx.Effects.Burst(base + dir * (length / 2), color or Color3.fromRGB(255, 140, 70), 25)
		for _, entry in ipairs(ctx.PlayersNear(base + dir * (length / 2), length / 2 + width)) do
			local rel = entry.Root.Position - origin
			local along = rel.X * dir.X + rel.Z * dir.Z
			local side = math.abs(rel.X * dir.Z - rel.Z * dir.X)
			if along >= 0 and along <= length and side <= width / 2 + 1 then
				ctx.Guard.Take(entry.Humanoid, damage)
			end
		end
	end)
end

local function flatDir(from, to)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude < 0.5 then return nil end
	return d.Unit
end

local function cue(part, text, color)
	ctx.Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 4, 0), text, color)
end

local function rand(a, b) return a + math.random() * (b - a) end

-- 2구역: 뿔 질주 - 나란한 띠 여러 줄이 한꺼번에 쓸고 간다 (띠 사이로 빠지면 안전)
P[2] = { Name = "stampede", Fn = function(part, data)
	local target = ctx.NearestFieldPlayer(part.Position)
	if not target then return end
	local dir = flatDir(part.Position, target.Position)
	if not dir then return end
	cue(part, "⚠ Stampede!", Color3.fromRGB(255, 200, 70))
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local lanes = data.Enraged and 5 or 3
	for i = 1, lanes do
		local offset = (i - (lanes + 1) / 2) * 15
		strip(part, data, part.Position + side * offset, dir, 78, 8, 1.2, math.floor(data.Stats.ShotDamage * 1.4), Color3.fromRGB(255, 190, 80))
	end
end }

-- 3구역: 바위 소나기 - 플레이어 주변에 시간차로 바위가 떨어진다 (계속 움직이면 피한다)
P[3] = { Name = "boulders", Fn = function(part, data)
	local target = ctx.NearestFieldPlayer(part.Position)
	if not target then return end
	cue(part, "⚠ Boulder Rain!", Color3.fromRGB(220, 190, 140))
	local count = data.Enraged and 9 or 6
	data.BusyUntil = os.clock() + 0.6
	task.spawn(function()
		for _ = 1, count do
			if not alive(part, data) then return end
			local angle, dist = rand(0, math.pi * 2), rand(0, 20)
			local spot = Vector3.new(target.Position.X + math.cos(angle) * dist, 0, target.Position.Z + math.sin(angle) * dist)
			disc(part, data, spot, 7, 1.0, math.floor(data.Stats.ShotDamage * 1.2), Color3.fromRGB(230, 190, 120))
			task.wait(0.22)
		end
	end)
end }

-- 4구역: 독 웅덩이 - 잠깐 뒤 웅덩이가 생기고 6초 동안 밟고 있으면 계속 아프다 (자리를 비켜 줘야 한다)
P[4] = { Name = "poison", Fn = function(part, data)
	local target = ctx.NearestFieldPlayer(part.Position)
	if not target then return end
	cue(part, "⚠ Poison Pools!", Color3.fromRGB(150, 255, 120))
	local pools = data.Enraged and 5 or 4
	for i = 1, pools do
		local angle = (i / pools) * math.pi * 2 + rand(0, 0.6)
		local spot = Vector3.new(target.Position.X + math.cos(angle) * 12, 0, target.Position.Z + math.sin(angle) * 12)
		task.delay(0.9, function()
			if not alive(part, data) then return end
			local pool = Instance.new("Part")
			pool.Shape = Enum.PartType.Cylinder
			pool.Size = Vector3.new(0.3, 18, 18)
			pool.CFrame = CFrame.new(spot.X, ctx.FloorAt(spot.X) + 0.3, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
			pool.Anchored, pool.CanCollide, pool.CanQuery = true, false, false
			pool.Material = Enum.Material.Neon
			pool.Color = Color3.fromRGB(120, 230, 100)
			pool.Transparency = 0.5
			pool.Parent = worldFolder()
			task.spawn(function()
				local started = os.clock()
				while os.clock() - started < 6 and alive(part, data) do
					for _, entry in ipairs(ctx.PlayersNear(spot, 9)) do
						ctx.Guard.Take(entry.Humanoid, math.max(1, math.floor(data.Stats.ShotDamage * 0.3)))
					end
					task.wait(0.5)
				end
				pool:Destroy()
			end)
		end)
	end
end }

-- 5구역: 얼음 가시줄 - 보스에서 사방으로 가시줄이 뻗고, 격노하면 사이를 메우는 두 번째 줄이 이어서 나온다
P[5] = { Name = "icelines", Fn = function(part, data)
	cue(part, "⚠ Ice Spikes!", Color3.fromRGB(150, 220, 255))
	local lines = 8
	local offset = rand(0, math.pi * 2)
	local origin = part.Position
	local function wave(extra)
		for i = 0, lines - 1 do
			local angle = offset + extra + (i / lines) * math.pi * 2
			strip(part, data, origin, Vector3.new(math.cos(angle), 0, math.sin(angle)), 62, 6, 1.2, math.floor(data.Stats.ShotDamage * 1.3), Color3.fromRGB(150, 215, 255))
		end
	end
	wave(0)
	if data.Enraged then
		task.delay(0.9, function()
			if alive(part, data) then wave(math.pi / lines) end
		end)
	end
end }

-- 6구역: 유성우 - 플레이어 근처에 유성이 시간차로 연달아 떨어진다
P[6] = { Name = "meteors", Fn = function(part, data)
	local target = ctx.NearestFieldPlayer(part.Position)
	if not target then return end
	cue(part, "⚠ Meteor Shower!", Color3.fromRGB(255, 150, 70))
	local count = data.Enraged and 10 or 7
	data.BusyUntil = os.clock() + 0.6
	task.spawn(function()
		for _ = 1, count do
			if not alive(part, data) then return end
			local current = ctx.NearestFieldPlayer(part.Position) or target
			local angle, dist = rand(0, math.pi * 2), rand(3, 22)
			local spot = Vector3.new(current.Position.X + math.cos(angle) * dist, 0, current.Position.Z + math.sin(angle) * dist)
			disc(part, data, spot, 8, 1.0, math.floor(data.Stats.ShotDamage * 1.3), Color3.fromRGB(255, 130, 50))
			task.wait(0.18)
		end
	end)
end }

-- 7구역: 순간이동 베기 - 플레이어 자리에 경고가 뜨고, 보스가 그 자리로 순간이동해서 크게 휘두른다
P[7] = { Name = "blink", Fn = function(part, data)
	local target = ctx.NearestFieldPlayer(part.Position)
	if not target then return end
	cue(part, "⚠ Reaper's Blink!", Color3.fromRGB(190, 120, 255))
	local spot = Vector3.new(target.Position.X, 0, target.Position.Z)
	data.BusyUntil = os.clock() + 1.8
	disc(part, data, spot, 12, 1.1, math.floor(data.Stats.ShotDamage * 1.5), Color3.fromRGB(190, 110, 255))
	task.delay(1.0, function()
		if not alive(part, data) then return end
		local radius = data.Stats.Size / 2 + 2
		if ctx.WalkableAt(spot.X, spot.Z, radius) then
			part.CFrame = CFrame.new(spot.X, ctx.FloorAt(spot.X) + data.Stats.Size / 2, spot.Z)
		end
	end)
end }

-- 8구역: 심연 광선 - 보스를 중심으로 광선이 돌아간다 (돌아가는 방향을 보고 사이로 빠져나간다)
P[8] = { Name = "beam", Fn = function(part, data)
	cue(part, "⚠ Abyss Beam!", Color3.fromRGB(255, 100, 170))
	local beams = data.Enraged and 3 or 2
	local origin = part.Position
	local base = rand(0, math.pi * 2)
	local length = 70
	data.BusyUntil = os.clock() + 3.6
	task.spawn(function()
		local parts = {}
		for i = 1, beams do
			local b = Instance.new("Part")
			b.Size = Vector3.new(3, 0.6, length)
			b.Anchored, b.CanCollide, b.CanQuery = true, false, false
			b.Material = Enum.Material.Neon
			b.Color = Color3.fromRGB(255, 90, 165)
			b.Transparency = 0.7 -- 처음 0.9초는 흐릿한 경고선 (피해 없음)
			b.Parent = worldFolder()
			parts[i] = b
		end
		local started = os.clock()
		local lastHit = {}
		while os.clock() - started < 3.4 and alive(part, data) do
			local t = os.clock() - started
			local active = t >= 0.9
			for i, b in ipairs(parts) do
				local angle = base + (active and (t - 0.9) * 0.9 or 0) + (i - 1) * (math.pi * 2 / beams)
				local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local from = Vector3.new(origin.X, ctx.FloorAt(origin.X) + 1, origin.Z)
				b.CFrame = CFrame.lookAt(from + dir * (length / 2), from + dir * length)
				b.Transparency = active and 0.1 or 0.7
				if active then
					for _, entry in ipairs(ctx.PlayersNear(origin, length)) do
						local rel = entry.Root.Position - origin
						local along = rel.X * dir.X + rel.Z * dir.Z
						local side = math.abs(rel.X * dir.Z - rel.Z * dir.X)
						if along >= 0 and along <= length and side <= 3.2 and os.clock() - (lastHit[entry.Humanoid] or 0) > 0.5 then
							lastHit[entry.Humanoid] = os.clock()
							ctx.Guard.Take(entry.Humanoid, math.floor(data.Stats.ShotDamage * 0.9))
						end
					end
				end
			end
			task.wait(0.06)
		end
		for _, b in ipairs(parts) do b:Destroy() end
	end)
end }

for zone, entry in pairs(P) do
	entry.Zone = zone
	entry.Skip = zone == 7 or zone == 8 -- 격노해도 두 번째로 겹쳐 쓰지 않는다 (순간이동 / 긴 광선)
end

-- FieldService 가 필요한 도구를 넘겨준다: Monsters, GetWorldFolder, FloorAt, NearestFieldPlayer, PlayersNear, WalkableAt, Effects, Guard
function P.Init(context)
	ctx = context
	return P
end

return P
