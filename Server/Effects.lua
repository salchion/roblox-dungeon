-- Effects (ServerScriptService > Modules 안의 ModuleScript, 이름: Effects)
-- 총알 궤적, 데미지 숫자, 강화 버스트 같은 짧은 시각 효과

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local Effects = {}

------------------------------------------------------------
-- 시각 효과는 서버가 부품을 만들지 않는다: 근처 플레이어에게 "무엇이 어디서" 만 한 프레임에 한 덩어리로 보내고,
-- 클라이언트(FxClient)가 자기 화면에서만 그린다. (복제되는 부품 / 트레일 / 입자가 사라져 서버 / 네트워크 부담이 크게 줄어든다)
------------------------------------------------------------
local FX_RANGE = 280   -- 이 거리 안에 있는 플레이어에게만 보낸다
local FX_BATCH_MAX = 160
local queues = setmetatable({}, { __mode = "k" }) -- [player] = { event... }

-- 플레이어 위치는 프레임당 한 번만 읽는다 (emit 이 한 프레임에 수백 번 불려도 FindFirstChild 는 플레이어당 1번)
local rootCache, rootCacheAt = {}, -1
local function refreshRoots()
	local now = os.clock()
	if now - rootCacheAt < 0.016 then return end
	rootCacheAt = now
	table.clear(rootCache)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then rootCache[player] = root.Position end
	end
end

local function emit(position, event)
	refreshRoots()
	for player, rootPos in pairs(rootCache) do
		if not position or (rootPos - position).Magnitude <= FX_RANGE then
			local queue = queues[player]
			if not queue then
				queue = {}
				queues[player] = queue
			end
			if #queue < FX_BATCH_MAX then
				queue[#queue + 1] = event
			end
		end
	end
end

RunService.Heartbeat:Connect(function()
	for player, queue in pairs(queues) do
		queues[player] = nil
		if player.Parent and #queue > 0 then
			Remotes.Fx:FireClient(player, queue)
		end
	end
end)

local nextProjectileId = 0

function Effects.Tracer(from, to, color, thickness)
	emit(from, { "T", from, to, color, thickness })
end

-- 적 탄: 서버는 숫자(위치)로만 움직이고 부품은 만들지 않는다. 반환값은 { Position, Destroy() } 인 가벼운 표.
-- 서버가 Position 을 옮기며 충돌을 계산하고, 클라이언트는 시작 / 끝 두 점 사이를 날아가는 모양만 그린다 (끝나기 전에 Destroy 하면 "X" 로 지운다).
-- path (선택): 직선이 아닌 움직임을 클라이언트가 같은 식으로 그리게 하는 설명 { "sine", 진폭, 빈도 } / { "curve", 각속도 } / { "lob", 착지점, 높이 } / { "home" }
-- Destroy(pop): pop 이 true 면 클라이언트가 사라지는 자리에 작은 터짐을 그린다 ("X" 의 3번째 값)
function Effects.SpawnProjectile(origin, direction, speed, size, color, style, life, path)
	nextProjectileId += 1
	local id = nextProjectileId
	local proxy = { Position = origin, Id = id }
	function proxy:Destroy(pop)
		emit(self.Position, { "X", id, pop and 1 or nil })
	end
	emit(origin, { "P", id, origin, direction.Unit, speed, size, color, style, life or 5, path })
	return proxy
end

------------------------------------------------------------
-- 적 탄의 특수 움직임: 유도 / 포물선 / 뱀(사인파) / 휘어지는 초승달 / 갈라지는 탄.
-- 필드와 던전이 같이 쓴다: 서비스는 MakeShot 으로 탄 데이터를 만들고, 매 프레임 Kind 가 있는 탄만 StepShot 으로 움직인다.
-- 서버는 숫자만 계산한다. 뱀 / 곡선 / 포물선은 닫힌 식이라 클라이언트가 같은 식으로 그리고, 유도탄만 0.2초마다 "Q" 로 새 방향을 알린다.
------------------------------------------------------------
Effects.HomingCap = 6 -- 한 판(던전) / 필드 전체에서 동시에 날아다닐 수 있는 유도탄 수

function Effects.CountKind(list, kind)
	local n = 0
	for i = 1, #list do
		if list[i].Kind == kind then n += 1 end
	end
	return n
end

-- opts: { Kind = "sine"|"curve"|"lob"|"homing"|"split", ... } (없으면 직선탄)
--   sine   : Amp(진폭 studs, 음수면 반대 위상), Freq(rad/s)
--   curve  : W(rad/s, 양수 = rotateY(+) 방향으로 휘어진다)
--   lob    : Target(착지점 Vector3), Dur(비행 초), Height(포물선 높이), AoE(폭발 반지름)
--   homing : Turn(rad/s), Life(초)
--   split  : SplitTime(초), Child = { Count, Spread(도), Speed, Damage, Size, Color, Style }
-- list: 이 서비스의 탄 목록 (유도탄 상한 확인용). 돌려주는 값: 목록에 넣을 탄 데이터
function Effects.MakeShot(list, origin, direction, speed, damage, size, color, style, opts)
	local now = os.clock()
	local dir = direction.Magnitude > 0.001 and direction.Unit or Vector3.new(0, 0, -1)
	local kind = opts and opts.Kind
	if kind == "homing" and Effects.CountKind(list, "homing") >= Effects.HomingCap then
		kind, opts = nil, nil -- 상한: 평범한 직선 구슬로 바꾼다
		style = "Orb"
	end
	local life = 5
	local entry = { Direction = dir, Speed = speed, Damage = damage, Radius = size / 2 }
	local path
	if kind then
		entry.Kind, entry.Origin, entry.Dir0, entry.T0 = kind, origin, dir, now
		life = opts.Life or life -- 수명(초): 휘어 도는 탄이 필드를 오래 떠돌지 않게
		if kind == "sine" then
			local side = Vector3.new(-dir.Z, 0, dir.X)
			entry.Side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
			entry.Amp, entry.Freq = opts.Amp or 7, opts.Freq or 3.4
			path = { "sine", entry.Amp, entry.Freq }
		elseif kind == "curve" then
			entry.W = (opts.W and opts.W ~= 0) and opts.W or 0.8
			path = { "curve", entry.W }
		elseif kind == "lob" then
			entry.Target, entry.Dur, entry.Height, entry.AoE, entry.Color = opts.Target, opts.Dur or 1.8, opts.Height or 16, opts.AoE or 8, color
			entry.Flies = true -- 날아가는 동안은 벽 / 플레이어에 닿지 않는다 (착지할 때만 피해)
			life = entry.Dur + 0.05
			path = { "lob", entry.Target, entry.Height }
		elseif kind == "homing" then
			entry.Turn, entry.NextQ, entry.NextPick = opts.Turn or 1.75, now + 0.2, 0
			life = opts.Life or 3.5
			path = { "home" }
		elseif kind == "split" then
			entry.SplitAt, entry.Child = now + (opts.SplitTime or 0.6), opts.Child
			life = (opts.SplitTime or 0.6) + 0.4
		end
	end
	entry.Expire = now + life
	entry.Part = Effects.SpawnProjectile(origin, dir, speed, size, color, style, life, path)
	return entry
end

-- 특수 탄 한 프레임: 위치를 갱신한다. 돌려주는 값: ended, pop (ended 면 호출한 쪽이 목록에서 지우고 Part:Destroy(pop) 한다)
-- targets: 살아 있는 플레이어 목록 { Root, Humanoid, Player/Member } (호출한 쪽이 프레임마다 한 번 만든 것을 그대로 쓴다)
-- queue: 갈라지는 탄이 낳은 새 탄을 담는 표 { origin, direction, speed, damage, size, color, style } - 반복이 끝난 뒤에 호출한 쪽이 쏜다
function Effects.StepShot(p, dt, now, targets, queue)
	local kind = p.Kind
	local proxy = p.Part
	if kind == "sine" then
		local t = now - p.T0
		proxy.Position = p.Origin + p.Dir0 * (p.Speed * t) + p.Side * (p.Amp * math.sin(p.Freq * t))
	elseif kind == "curve" then
		local t, w, d = now - p.T0, p.W, p.Dir0
		local fx, fz = d.X, d.Z
		local k = p.Speed / w
		local s, c = math.sin(w * t), 1 - math.cos(w * t)
		proxy.Position = Vector3.new(p.Origin.X + (fx * s + fz * c) * k, p.Origin.Y + d.Y * p.Speed * t, p.Origin.Z + (fz * s - fx * c) * k)
	elseif kind == "homing" then
		local pos = proxy.Position
		if now > p.Expire then -- 수명이 끝나면 그 자리에서 터진다
			Effects.Burst(pos, Color3.fromRGB(255, 170, 90), 14)
			return true, true
		end
		if now >= p.NextPick then -- 가장 가까운 플레이어를 0.4초마다 다시 고른다 (전체 검색 없이 이미 만든 목록만 훑는다)
			p.NextPick = now + 0.4
			local best, bestDist = nil, math.huge
			for i = 1, #targets do
				local entry = targets[i]
				if entry.Humanoid.Health > 0 then
					local dist = (entry.Root.Position - pos).Magnitude
					if dist < bestDist then best, bestDist = entry, dist end
				end
			end
			p.Target = best
		end
		local target = p.Target
		if target and target.Root.Parent then
			local to = target.Root.Position - pos
			local dist = to.Magnitude
			if dist > 8 then -- 바로 앞까지 오면 더 꺾지 않는다: 옆으로 피할 수 있다
				local desired = to / dist
				local dir = p.Direction
				local angle = math.acos(math.clamp(dir:Dot(desired), -1, 1))
				local maxStep = p.Turn * dt
				local turned = angle <= maxStep and desired or (dir + (desired - dir) * (maxStep / angle))
				if turned.Magnitude > 0.001 then p.Direction = turned.Unit end
			end
		end
		proxy.Position = pos + p.Direction * p.Speed * dt
		if now >= p.NextQ then
			p.NextQ = now + 0.2
			emit(proxy.Position, { "Q", proxy.Id, proxy.Position, p.Direction, p.Speed })
		end
	elseif kind == "lob" then
		local u = (now - p.T0) / p.Dur
		if u >= 1 then
			local ground = p.Target
			proxy.Position = ground
			local aoe = p.AoE
			for i = 1, #targets do
				local entry = targets[i]
				if entry.Humanoid.Health > 0 then
					local rp = entry.Root.Position
					if Vector3.new(rp.X - ground.X, 0, rp.Z - ground.Z).Magnitude <= aoe and rp.Y - ground.Y < 8 then
						local who = entry.Player or entry.Member
						entry.Humanoid:TakeDamage((who and who:GetAttribute("TutorialDoom")) and math.max(1, math.floor(p.Damage * 0.5)) or p.Damage)
					end
				end
			end
			local color = p.Color or Color3.fromRGB(255, 160, 80)
			Effects.Burst(ground + Vector3.new(0, 1.5, 0), color, 26)
			emit(ground, { "R", ground, aoe, color })
			return true, false
		end
		proxy.Position = p.Origin:Lerp(p.Target, u) + Vector3.new(0, p.Height * 4 * u * (1 - u), 0)
	elseif kind == "split" then
		local pos = proxy.Position + p.Direction * p.Speed * dt
		proxy.Position = pos
		if now >= p.SplitAt then
			local child = p.Child
			local n = child.Count
			for i = 1, n do
				queue[#queue + 1] = {
					pos, CFrame.Angles(0, math.rad((i - (n + 1) / 2) * child.Spread), 0):VectorToWorldSpace(p.Direction),
					child.Speed, child.Damage, child.Size, child.Color, child.Style,
				}
			end
			return true, true
		end
	else
		proxy.Position += p.Direction * p.Speed * dt
	end
	return false, false
end

-- 땅 위 경고 표시 { "W", 위치, 반지름, 지속 초, 색 }: 착탄 지점 / 위험 구역을 클라이언트가 그린다
function Effects.Warn(position, radius, duration, color)
	emit(position, { "W", position, radius, duration, color })
end

-- 거대한 군주 외형(뿔 / 날개 / 꼬리 / 눈). 던전 보스와 필드 구역 보스가 같이 쓴다
-- 거신(필드 월드 보스): 이끼 낀 거대한 돌 거인. 몸통 구체가 판정이고, 머리 / 어깨 / 팔 / 가슴의 용암 핵은 장식(맞지 않는다).
function Effects.DecorateGolem(part, size, glow)
	local stone = Color3.fromRGB(108, 100, 94)
	part.Material = Enum.Material.Slate
	part.Color = stone
	local function piece(shape, sx, sy, sz, x, y, z, color, material, rx, ry, rz, transparency)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
		p.Shape = shape
		p.Size = Vector3.new(math.max(0.1, sx), math.max(0.1, sy), math.max(0.1, sz))
		p.Color = color
		p.Material = material
		p.Transparency = transparency or 0
		p.CFrame = part.CFrame * CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = p
		weld.Parent = p
		p.Parent = part
		return p
	end
	local S = size
	local Ball, Block = Enum.PartType.Ball, Enum.PartType.Block
	local Neon, Slate, Grass = Enum.Material.Neon, Enum.Material.Slate, Enum.Material.Grass
	local darkStone = stone:Lerp(Color3.new(0, 0, 0), 0.25)
	local moss = Color3.fromRGB(80, 120, 60)
	-- 머리: 네모난 돌덩이 + 용암 눈 + 이끼 + 돌 왕관
	piece(Block, S * 0.5, S * 0.4, S * 0.46, 0, S * 0.66, -S * 0.1, darkStone, Slate)
	piece(Block, S * 0.52, S * 0.08, S * 0.48, 0, S * 0.88, -S * 0.1, moss, Grass)
	for _, side in ipairs({ -1, 1 }) do
		piece(Block, S * 0.11, S * 0.07, S * 0.05, side * S * 0.12, S * 0.68, -S * 0.34, glow, Neon)
		piece(Ball, S * 0.56, S * 0.56, S * 0.56, side * S * 0.66, S * 0.26, 0, darkStone, Slate) -- 어깨 바위
		piece(Block, S * 0.1, S * 0.3, S * 0.1, side * S * 0.66, S * 0.62, 0, stone:Lerp(Color3.new(1, 1, 1), 0.2), Slate, 0, 0, side * 12) -- 어깨 뾰족 돌
		piece(Block, S * 0.3, S * 0.78, S * 0.3, side * S * 0.74, -S * 0.2, 0, stone, Slate, 0, 0, side * -6) -- 팔
		piece(Ball, S * 0.46, S * 0.46, S * 0.46, side * S * 0.78, -S * 0.66, 0, darkStone, Slate) -- 주먹
		piece(Block, S * 0.08, S * 0.5, S * 0.06, side * S * 0.74, -S * 0.2, -S * 0.15, glow, Neon, 0, 0, 0, 0.35) -- 팔의 용암 균열
	end
	-- 가슴의 용암 핵 + 갈라진 균열
	piece(Ball, S * 0.3, S * 0.3, S * 0.3, 0, S * 0.12, -S * 0.46, glow, Neon)
	piece(Block, S * 0.06, S * 0.7, S * 0.05, S * 0.18, 0, -S * 0.46, glow, Neon, 0, 0, 22, 0.3)
	piece(Block, S * 0.06, S * 0.6, S * 0.05, -S * 0.2, -S * 0.05, -S * 0.46, glow, Neon, 0, 0, -28, 0.3)
	-- 등과 몸의 이끼 바위
	for _, spot in ipairs({ { 0.2, 0.5, 0.3 }, { -0.3, 0.45, 0.2 }, { 0.05, 0.1, 0.5 }, { -0.1, -0.3, 0.42 } }) do
		piece(Block, S * 0.2, S * 0.16, S * 0.2, S * spot[1], S * spot[2], S * spot[3], moss, Grass, 15, 25, 10)
	end
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = S * 1.6
	light.Brightness = 2
	light.Parent = part
end

function Effects.DecorateBoss(part, size, glow)
	local dark = part.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	part.Material = Enum.Material.Slate
	part.Color = dark
	local function piece(shape, sx, sy, sz, x, y, z, color, material, rx, ry, rz, transparency)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
		p.Shape = shape
		p.Size = Vector3.new(math.max(0.1, sx), math.max(0.1, sy), math.max(0.1, sz))
		p.Color = color
		p.Material = material
		p.Transparency = transparency or 0
		p.CFrame = part.CFrame * CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = p
		weld.Parent = p
		p.Parent = part
		return p
	end
	local S = size
	local Ball, Block = Enum.PartType.Ball, Enum.PartType.Block
	local Neon, Metal, Slate = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Slate
	local bone = Color3.fromRGB(215, 205, 185)
	-- 눈 / 가슴 룬 / 이마의 보석
	for _, side in ipairs({ -1, 1 }) do
		piece(Ball, S * 0.13, S * 0.13, S * 0.13, side * S * 0.2, S * 0.18, -S * 0.45, Color3.fromRGB(255, 240, 120), Neon)
		-- 뿔 (휘어진 두 마디)
		piece(Block, S * 0.1, S * 0.42, S * 0.1, side * S * 0.28, S * 0.52, -S * 0.08, bone, Slate, 0, 0, side * -22)
		piece(Block, S * 0.08, S * 0.3, S * 0.08, side * S * 0.42, S * 0.8, -S * 0.12, bone, Slate, -15, 0, side * -48)
		-- 어깨 갑옷
		piece(Ball, S * 0.34, S * 0.34, S * 0.34, side * S * 0.52, S * 0.2, 0, dark:Lerp(Color3.new(1, 1, 1), 0.12), Metal)
		-- 날개 (뼈대 + 빛나는 막)
		piece(Block, S * 1.0, S * 0.07, S * 0.09, side * S * 0.95, S * 0.52, S * 0.28, bone, Slate, 0, 0, side * 28)
		piece(Block, S * 0.95, S * 0.04, S * 0.65, side * S * 0.92, S * 0.4, S * 0.4, glow, Neon, 0, 0, side * 28, 0.4)
		piece(Block, S * 0.7, S * 0.04, S * 0.5, side * S * 0.78, S * 0.14, S * 0.62, glow, Neon, 0, 0, side * 20, 0.5)
	end
	piece(Ball, S * 0.24, S * 0.24, S * 0.24, 0, S * 0.02, -S * 0.5, glow, Neon)
	piece(Ball, S * 0.12, S * 0.12, S * 0.12, 0, S * 0.36, -S * 0.42, Color3.fromRGB(255, 70, 90), Neon)
	-- 등 가시
	for i = 0, 4 do
		piece(Block, S * 0.09, S * (0.34 - i * 0.04), S * 0.09, 0, S * (0.5 - i * 0.07), S * (0.05 + i * 0.12), bone, Slate, 25 + i * 8, 0, 0)
	end
	-- 꼬리 (뒤쪽으로 점점 가늘어지는 구슬 + 끝의 불꽃)
	for i = 1, 4 do
		piece(Ball, S * (0.32 - i * 0.05), S * (0.32 - i * 0.05), S * (0.32 - i * 0.05), 0, -S * 0.1 * i, S * (0.45 + i * 0.22), dark, Slate)
	end
	local tip = piece(Ball, S * 0.22, S * 0.22, S * 0.22, 0, -S * 0.5, S * 1.45, glow, Neon)
	local fire = Instance.new("ParticleEmitter")
	fire.Rate = 40
	fire.Lifetime = NumberRange.new(0.4, 0.9)
	fire.Speed = NumberRange.new(3, 8)
	fire.SpreadAngle = Vector2.new(35, 35)
	fire.LightEmission = 1
	fire.Color = ColorSequence.new(glow, Color3.fromRGB(255, 240, 160))
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, S * 0.12), NumberSequenceKeypoint.new(1, 0) })
	fire.Parent = tip
	local halo = Instance.new("PointLight")
	halo.Range = S * 1.6
	halo.Brightness = 2
	halo.Color = glow
	halo.Parent = part
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 100)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 255)),
})
local FIRE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 120)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 20)),
})

-- 무기 등급별로 모양이 다른 발사체가 날아가는 연출 (판정은 이미 서버에서 끝난 상태, 보이기만 하는 것)
-- shot = Config.Weapon.Tiers[n].Shot
-- 무기 종류별 탄 모양: 이름과 어울리게 (화염방사기는 불길, 레일건은 가늘고 긴 빛줄기, 로켓은 꼬리 달린 로켓 ...)
local CLASS_LOOK = {
	Flamer = { Style = "Fire", SizeMul = 2.0, Color = Color3.fromRGB(255, 150, 50), Transparency = 0.4, Impact = 2 },
	Rocket = { Style = "Rocket", Length = 4.5, Impact = 20 },
	Cannon = { Style = "Orb", SizeMul = 1.25 },
	Rail = { Style = "Bolt", Length = 16, SizeMul = 0.7, Color = Color3.fromRGB(150, 230, 255), Impact = 8 },
	Sniper = { Style = "Bolt", Length = 8, SizeMul = 0.8, Impact = 6 },
	Rifle = { Style = "Bolt", Length = 3.5 },
	Smg = { Style = "Bolt", Length = 2 },
	Shotgun = { Style = "Ball", SizeMul = 0.9 },
}

function Effects.Shot(from, to, shot, color, rainbow, class, era)
	if (to - from).Magnitude < 0.5 then return end
	emit(from, { "S", from, to, shot.Size, shot.Speed, shot.Impact or 0, shot.Style, shot.Length, color, rainbow == true, class, era or 1 })
end

-- 타격감: 맞은 몬스터가 하얗게 번쩍이고, 쏜 사람에게는 적중 표시(Hit)를 보낸다 (치명타 / 처치는 더 크게)
function Effects.Hit(player, part, isCrit, killed)
	if player and player.Parent then
		Remotes.Hit:FireClient(player, isCrit == true, killed == true)
	end
	if killed or not part or not part.Parent then return end
	emit(part.Position, { "H", part }) -- 하얗게 번쩍이는 건 각자 화면에서 (서버가 색을 바꿨다 되돌리지 않는다)
end

-- 소리 한 번 재생 (soundId 가 0 이면 아무것도 안 함)
function Effects.PlaySound(parent, soundId, volume, pitch)
	if not soundId or soundId == 0 then return end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. soundId
	sound.Volume = volume or 0.8
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 90
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 5)
end

-- 그 밖의 연출(미사일 / 고리 / 번개 / 불길 / 유성 / 회전 칼날 ...)도 같은 묶음으로 보낸다. position 이 nil 이면 모두에게.
function Effects.Raw(position, event)
	emit(position, event)
end

-- 총소리: 소리 부품도 서버가 만들지 않고, 쏜 위치 / 무기 종류 / 높낮이 / 크기만 보낸다 (각자 화면에서 재생)
function Effects.GunSound(position, class, pitch, volume, era)
	emit(position, { "G", position, class, pitch, volume, era })
end

-- 임의 색의 떠오르는 글자 (골드 획득 등)
function Effects.FloatText(position, text, color)
	emit(position, { "F", position, text, color })
end

function Effects.DamageNumber(position, amount, isCrit)
	emit(position, { "D", position, amount, isCrit == true })
end

-- 강화 성공 시 캐릭터 주변에 터지는 빛 입자
function Effects.Burst(position, color, count)
	emit(position, { "B", position, color, count or 40 })
end

-- 약점 구슬 표시 / 숨김 (약점이 "노출"되는 동안에는 구슬이 사라진다)
function Effects.SetWeakVisible(orb, visible)
	if not orb then return end
	for _, item in ipairs(orb:GetDescendants()) do
		if item:IsA("BasePart") then
			if item:GetAttribute("T0") == nil then item:SetAttribute("T0", item.Transparency) end
			item.Transparency = visible and item:GetAttribute("T0") or 1
		elseif item:IsA("BillboardGui") or item:IsA("PointLight") or item:IsA("ParticleEmitter") then
			item.Enabled = visible
		end
	end
	if orb:IsA("BasePart") then
		if orb:GetAttribute("T0") == nil then orb:SetAttribute("T0", orb.Transparency) end
		orb.Transparency = visible and orb:GetAttribute("T0") or 1
		orb.CanQuery = visible -- 숨은 동안에는 조준 / 판정에 잡히지 않는다
	end
end

-- 약점 노출: duration 초 동안 보스가 받는 피해가 x3 (data.ExposedUntil 을 각 서비스의 피해 계산이 읽는다). 보스에 노란 윤곽 + 글자.
function Effects.ExposeBoss(part, data, duration)
	data.ExposedUntil = os.clock() + duration
	if data.WeakPart then
		data.WeakHidden = true
		Effects.SetWeakVisible(data.WeakPart, false)
	end
	-- 이미 노출 중에 또 맞히면 (표시를 새로 만들지 않고) 시간만 늘린다
	for _, old in ipairs(part:GetChildren()) do
		if old.Name == "ExposedOutline" or old.Name == "ExposedBar" then old:Destroy() end
	end
	local outline = Instance.new("Highlight")
	outline.Name = "ExposedOutline"
	outline.Adornee = part
	outline.FillColor = Color3.fromRGB(255, 220, 60)
	outline.FillTransparency = 0.45
	outline.OutlineColor = Color3.fromRGB(255, 240, 120)
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = part
	-- 갑옷이 깨져 속이 번쩍이는 느낌: 채움 색이 천천히 맥박친다
	TweenService:Create(outline, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { FillTransparency = 0.8 }):Play()
	-- 보스 머리 위: 남은 시간 막대 (줄어드는 노란 막대) + 글자
	local gui = Instance.new("BillboardGui")
	gui.Name = "ExposedBar"
	gui.Size = UDim2.new(0, 200, 0, 38)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 9, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 260
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 240, 90)
	label.TextStrokeTransparency = 0
	label.Text = "💥 약점 적중!  피해 x3"
	label.Parent = gui
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, -20, 0, 8)
	back.Position = UDim2.new(0, 10, 0, 26)
	back.BackgroundColor3 = Color3.fromRGB(40, 32, 10)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
	fill.BorderSizePixel = 0
	fill.Parent = back
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 1, 0) }):Play()
	-- 맞은 순간: 보스 둘레로 금빛 충격 고리 + 파편 + 큰 글자
	Effects.Raw(part.Position, { "R", part.Position, math.max(10, part.Size.X * 0.9), Color3.fromRGB(255, 225, 80) })
	Effects.Burst(part.Position, Color3.fromRGB(255, 225, 80), 40)
	Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 12, 0), string.format("💥 약점 적중! %.1f초간 피해 x3", duration), Color3.fromRGB(255, 240, 90))
	task.delay(duration, function()
		if outline.Parent and data.ExposedUntil and os.clock() >= data.ExposedUntil - 0.05 then
			outline:Destroy()
			gui:Destroy()
			if data.WeakPart and data.WeakPart.Parent then
				data.WeakHidden = nil
				Effects.SetWeakVisible(data.WeakPart, true)
			end
		end
	end)
end

-- 몬스터 사망 연출: 조각이 흩어지고 영혼 연기가 피어오른다 (그리는 건 FxClient 의 "K"). 종류별 색 / 모양은 typeKey 로 정한다
-- data: 던전 / 필드의 몬스터 데이터 (TypeKey / BaseColor / Stats.Size 를 읽는다. 없어도 안전)
function Effects.MonsterDeath(part, data)
	if not part then return end
	local stats = data and data.Stats
	local size = (stats and stats.Size) or part.Size.Y
	emit(part.Position, { "K", part.Position, (data and data.BaseColor) or part.Color, size, data and data.TypeKey })
end

return Effects
