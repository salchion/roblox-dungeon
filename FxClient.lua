-- FxClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: FxClient)
-- 전투 시각 효과를 내 화면에서만 그린다: 총알 궤적 / 폭발 입자 / 피해 숫자 / 떠오르는 글자 / 적 탄 / 적중 번쩍임.
-- 서버는 "무엇이 어디서 일어났는지"만 한 덩어리(배치)로 보내고, 부품은 여기서 만들고 (풀링으로) 재사용한다.
--   -> 서버가 매 총알마다 부품 / 트레일 / 입자를 만들고 위치를 복제하던 부담이 사라진다.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ClientFx"
fxFolder.Parent = workspace

local WHITE = Color3.new(1, 1, 1)
local MAX_ACTIVE_SHOTS = 90
local activeShots = 0

------------------------------------------------------------
-- 풀: 폭발 입자 / 떠오르는 글자 / 피해 숫자는 부품을 돌려 쓴다
------------------------------------------------------------
local burstPool, textPool = {}, {}

local function getBurst()
	local entry = table.remove(burstPool)
	if entry then return entry end
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(12, 24)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.LightEmission = 1
	emitter.Parent = anchor
	return { Part = anchor, Emitter = emitter }
end

local function burst(position, color, count)
	local entry = getBurst()
	entry.Part.Position = position
	entry.Part.Parent = fxFolder
	entry.Emitter.Color = ColorSequence.new(color)
	entry.Emitter:Emit(math.min(count or 40, 120))
	task.delay(1.4, function()
		entry.Part.Parent = nil
		if #burstPool < 40 then table.insert(burstPool, entry) else entry.Part:Destroy() end
	end)
end

local function getText()
	local entry = table.remove(textPool)
	if entry then return entry end
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	local gui = Instance.new("BillboardGui")
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.Parent = gui
	return { Part = anchor, Gui = gui, Label = label }
end

local function showText(position, text, color, size, lifetime, rise)
	local entry = getText()
	entry.Gui.Size = size
	entry.Label.Text = text
	entry.Label.TextColor3 = color
	entry.Part.Position = position
	entry.Part.Parent = fxFolder
	if rise then
		TweenService:Create(entry.Part, TweenInfo.new(lifetime), { Position = position + Vector3.new(0, rise, 0) }):Play()
	end
	task.delay(lifetime, function()
		entry.Part.Parent = nil
		if #textPool < 60 then table.insert(textPool, entry) else entry.Part:Destroy() end
	end)
end

------------------------------------------------------------
-- 총알 (서버 Effects.Shot 과 같은 모양)
------------------------------------------------------------
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 100)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 90, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 255)),
})
local FIRE = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 120)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 20)) })
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
local RATE_ERA = { Orb = 40, Cannon = 25, Fire = 90, Rocket = 110, Rainbow = 80 }
local RATE_STYLE = { Orb = 40, Cannon = 25, Fire = 90, Rocket = 110 }

-- event = { "S", from, to, size, speed, impact, style, length, color, rainbow, class, era }
local function playShot(event)
	if activeShots >= MAX_ACTIVE_SHOTS then return end
	local from, to = event[2], event[3]
	local size, speed, impact, eraStyle, length = event[4], event[5], event[6], event[7], event[8]
	local color, rainbow, class, era = event[9], event[10], event[11], event[12] or 1
	local distance = (to - from).Magnitude
	if distance < 0.5 then return end
	local style = eraStyle
	local look = class and CLASS_LOOK[class]
	if look then
		style = look.Style or style
		length = look.Length or length or 3
		size *= look.SizeMul or 1
		impact = look.Impact or impact
		color = look.Color or color
	end
	activeShots += 1

	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Material = Enum.Material.Neon
	part.Color = color
	if look and look.Transparency then part.Transparency = look.Transparency end
	if style == "Bolt" or style == "Rocket" then
		part.Size = Vector3.new(size, size, length or 3)
	else
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(size, size, size)
	end
	part.CFrame = CFrame.lookAt(from, to)

	local colorSeq = rainbow and RAINBOW or ColorSequence.new(color)
	if style == "Fire" or style == "Rocket" or eraStyle == "Fire" or eraStyle == "Rocket" then
		colorSeq = rainbow and RAINBOW or FIRE
	end
	local trailWidth = size * (1 + 0.12 * era)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, trailWidth / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -trailWidth / 2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = math.min(0.55, (style == "Ball" and 0.08 or 0.14) + 0.03 * era)
	trail.Color = colorSeq
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = part

	local rate = RATE_ERA[eraStyle] or RATE_STYLE[style]
	if not rate and era >= 2 then rate = 6 + era * 4 end
	if rate then
		rate = rate * (0.6 + 0.1 * era)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = rate
		emitter.Lifetime = NumberRange.new(0.3, 0.6)
		emitter.Speed = NumberRange.new(1, (style == "Fire" or style == "Rocket") and 6 or 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, 0) })
		emitter.LightEmission = 1
		emitter.Color = colorSeq
		emitter.Parent = part
	end
	if era >= 3 then
		local light = Instance.new("PointLight")
		light.Range, light.Brightness, light.Color = 5 + era * 2, 0.7 + 0.1 * era, color
		light.Parent = part
	end
	part.Parent = fxFolder
	if era >= 2 then burst(from, color, 2 + era) end

	local duration = math.clamp(distance / speed, 0.03, 1.2)
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(to, to + (to - from)) })
	tween.Completed:Connect(function()
		part.Transparency = 1
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("ParticleEmitter") then child.Enabled = false end
		end
		if impact and impact > 0 then burst(to, color, impact) end
		activeShots -= 1
		Debris:AddItem(part, 0.5)
	end)
	tween:Play()
end

------------------------------------------------------------
-- 적 탄: 서버는 숫자로만 움직이고, 여기서는 시작 / 끝 두 점 사이를 부드럽게 날아가게만 그린다
------------------------------------------------------------
local projectiles = {} -- [id] = { Part, Tween }

local function spawnProjectile(event)
	-- { "P", id, origin, direction, speed, size, color, style, life }
	local id, origin, direction, speed, size, color, style, life = event[2], event[3], event[4], event[5], event[6], event[7], event[8], event[9]
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255, 120, 30)
	local look = CFrame.lookAt(origin, origin + direction)
	if style == "Spear" then
		part.Size = Vector3.new(size * 0.45, size * 0.45, size * 3.6)
		part.CFrame = look
		part.Color = part.Color:Lerp(WHITE, 0.35)
	elseif style == "Dart" then
		part.Size = Vector3.new(size * 0.3, size * 0.3, size * 2.4)
		part.CFrame = look
	elseif style == "Shard" then
		part.Size = Vector3.new(size * 0.9, size * 0.9, size * 1.9)
		part.CFrame = look * CFrame.Angles(0, 0, math.rad(45))
	else
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(size, size, size)
		part.Position = origin
	end
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 8, 1.2, part.Color
	light.Parent = part
	part.Parent = fxFolder
	local endCFrame = part.CFrame + direction * speed * life
	local tween = TweenService:Create(part, TweenInfo.new(life, Enum.EasingStyle.Linear), { CFrame = endCFrame })
	tween:Play()
	projectiles[id] = { Part = part, Tween = tween }
	Debris:AddItem(part, life + 0.3)
	task.delay(life + 0.3, function() projectiles[id] = nil end)
end

local function removeProjectile(id)
	local entry = projectiles[id]
	if entry then
		projectiles[id] = nil
		entry.Tween:Cancel()
		entry.Part:Destroy()
	end
end

------------------------------------------------------------
-- 나머지
------------------------------------------------------------
local function flash(part)
	if not part or not part.Parent or part.Color == WHITE then return end
	local original = part.Color
	part.Color = WHITE
	task.delay(0.06, function()
		if part.Parent and part.Color == WHITE then part.Color = original end
	end)
end

local function tracer(event)
	-- { "T", from, to, color, thickness }
	local from, to = event[2], event[3]
	local distance = (to - from).Magnitude
	if distance < 0.1 then return end
	local beam = Instance.new("Part")
	beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch = true, false, false, false
	beam.Material = Enum.Material.Neon
	beam.Color = event[4] or Color3.fromRGB(255, 255, 150)
	beam.Size = Vector3.new(event[5] or 0.15, event[5] or 0.15, distance)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -distance / 2)
	beam.Parent = fxFolder
	Debris:AddItem(beam, 0.08)
end

-- 총소리 { "G", 위치, 무기 종류, 높낮이, 크기, 세대 }: 소리 이름이 "GunShot" 이면 PlayerClient 가 내 설정 볼륨을 곱한다
local function gunSound(event)
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = event[2]
	anchor.Parent = fxFolder
	Debris:AddItem(anchor, 3.5)
	local played = SoundBank.Play(anchor, "Shot_" .. tostring(event[3]), { Pitch = event[4], Volume = event[5], Name = "GunShot" })
	if not played and Config.Audio.Shot and Config.Audio.Shot ~= 0 then -- 무기 종류별 소리가 없으면 기본 총소리를 가공해서
		local sound = Instance.new("Sound")
		sound.Name = "GunShot"
		sound.SoundId = "rbxassetid://" .. Config.Audio.Shot
		sound.Volume = Config.Audio.ShotVolume * (event[5] or 1)
		sound.PlaybackSpeed = math.max(0.5, 1.25 - 0.08 * ((event[6] or 1) - 1)) * ((event[4] or 1) / math.max(0.8, 1.08 - 0.03 * ((event[6] or 1) - 1)))
		sound.RollOffMaxDistance = 90
		sound.Parent = anchor
		sound:Play()
	end
end

------------------------------------------------------------
-- 세트 효과 연출: 고리 / 번개 / 미사일 / 불길 / 유성 / 회전 칼날 (서버는 위치와 피해만 계산한다)
------------------------------------------------------------
local RunService = game:GetService("RunService")

local function neonPart(size, color, transparency, shape)
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0
	if shape then part.Shape = shape end
	part.Size = size
	return part
end

local function ring(event) -- { "R", 위치, 반지름, 색 }
	local position, radius, color = event[2], event[3], event[4]
	local part = neonPart(Vector3.new(0.5, 2, 2), color, 0.25, Enum.PartType.Cylinder)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = fxFolder
	TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.5, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(part, 0.5)
end

local function bolt(event) -- { "Z", 위, 아래 }
	local top, bottom = event[2], event[3]
	local length = (top - bottom).Magnitude
	local part = neonPart(Vector3.new(1.4, 1.4, length), Color3.fromRGB(255, 245, 140), 0)
	part.CFrame = CFrame.lookAt((top + bottom) / 2, bottom)
	part.Parent = fxFolder
	TweenService:Create(part, TweenInfo.new(0.3), { Transparency = 1, Size = Vector3.new(0.2, 0.2, length) }):Play()
	Debris:AddItem(part, 0.35)
	burst(bottom, Color3.fromRGB(255, 240, 120), 24)
end

local missiles = {}
local function missile(event) -- { "M", 출발, 대상 부품, 중간점, 시간 }
	local from, target, mid, duration = event[2], event[3], event[4], event[5]
	local ball = neonPart(Vector3.new(1.6, 1.6, 1.6), Color3.fromRGB(255, 160, 70), 0, Enum.PartType.Ball)
	ball.Position = from
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 0.6, 0), Vector3.new(0, -0.6, 0)
	a0.Parent, a1.Parent = ball, ball
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.35
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 80, 40))
	trail.Transparency = NumberSequence.new(0, 1)
	trail.LightEmission = 1
	trail.Parent = ball
	ball.Parent = fxFolder
	table.insert(missiles, { Ball = ball, From = from, Target = target, Last = event[3] and event[3].Parent and event[3].Position or from, Mid = mid, Duration = duration, Started = os.clock() })
end

local function flame(event) -- { "L", 위치, 반지름, 초 }
	local position, radius, seconds = event[2], event[3], event[4]
	local pad = neonPart(Vector3.new(0.4, radius * 2, radius * 2), Color3.fromRGB(255, 120, 40), 0.55, Enum.PartType.Cylinder)
	pad.CFrame = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local fire = Instance.new("Fire")
	fire.Size = math.max(6, radius)
	fire.Heat = 8
	fire.Parent = pad
	pad.Parent = fxFolder
	task.delay(seconds, function()
		TweenService:Create(pad, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		Debris:AddItem(pad, 0.5)
		fire.Enabled = false
	end)
end

local function meteor(event) -- { "E", 위치, 반지름, 낙하 시간 }
	local position, radius, fall = event[2], event[3], event[4]
	local warnDisk = neonPart(Vector3.new(0.3, radius * 2, radius * 2), Color3.fromRGB(255, 80, 50), 0.6, Enum.PartType.Cylinder)
	warnDisk.CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	warnDisk.Parent = fxFolder
	local rock = neonPart(Vector3.new(7, 7, 7), Color3.fromRGB(255, 150, 60), 0, Enum.PartType.Ball)
	rock.Position = position + Vector3.new(14, 90, 10)
	local fire = Instance.new("Fire")
	fire.Size = 14
	fire.Parent = rock
	rock.Parent = fxFolder
	TweenService:Create(rock, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = position + Vector3.new(0, 3, 0) }):Play()
	task.delay(fall, function()
		warnDisk:Destroy()
		rock:Destroy()
		ring({ "R", position, radius, Color3.fromRGB(255, 150, 60) })
		burst(position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 160, 60), 70)
	end)
end

-- 회전 칼날: 칼날은 이 화면에서 서버 시각(GetServerTimeNow) 기준으로 돌아서, 서버가 계산한 피해 위치와 같은 곳에 보인다
local orbiters = {} -- [userId] = { Parts, Count, Radius, Spin, Expire }
local function orbit(event) -- { "O", userId, 개수(0이면 끔), 반지름, 속도 }
	local userId, count = event[2], event[3]
	local entry = orbiters[userId]
	if not count or count <= 0 then
		if entry then
			for _, part in ipairs(entry.Parts) do part:Destroy() end
			orbiters[userId] = nil
		end
		return
	end
	if entry and entry.Count ~= count then
		for _, part in ipairs(entry.Parts) do part:Destroy() end
		entry = nil
	end
	if not entry then
		entry = { Parts = {}, Count = count }
		for _ = 1, count do
			local blade = neonPart(Vector3.new(0.7, 0.4, 5), Color3.fromRGB(120, 235, 255), 0)
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Position, a1.Position = Vector3.new(0, 0, -2.5), Vector3.new(0, 0, 2.5)
			a0.Parent, a1.Parent = blade, blade
			local trail = Instance.new("Trail")
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.Lifetime = 0.25
			trail.Color = ColorSequence.new(Color3.fromRGB(170, 245, 255))
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.LightEmission = 1
			trail.Parent = blade
			blade.Parent = fxFolder
			table.insert(entry.Parts, blade)
		end
		orbiters[userId] = entry
	end
	entry.Radius, entry.Spin = event[4] or 9, event[5] or 5
	entry.Expire = os.clock() + 8 -- 서버가 3초마다 다시 알린다: 끊기면 저절로 사라진다
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	-- 미사일
	for i = #missiles, 1, -1 do
		local m = missiles[i]
		local t = (now - m.Started) / m.Duration
		if m.Target and m.Target.Parent then m.Last = m.Target.Position end
		if t >= 1 or not m.Ball.Parent then
			burst(m.Last, Color3.fromRGB(255, 150, 60), 22)
			m.Ball:Destroy()
			table.remove(missiles, i)
		else
			m.Ball.Position = m.From:Lerp(m.Mid, t):Lerp(m.Mid:Lerp(m.Last, t), t) -- 2차 곡선
		end
	end
	-- 회전 칼날
	local serverNow = workspace:GetServerTimeNow()
	for userId, entry in pairs(orbiters) do
		local owner = Players:GetPlayerByUserId(userId)
		local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		if now > entry.Expire or not root then
			for _, part in ipairs(entry.Parts) do part:Destroy() end
			orbiters[userId] = nil
		else
			for index, blade in ipairs(entry.Parts) do
				local angle = serverNow * entry.Spin + index * (2 * math.pi / entry.Count)
				local p = root.Position + Vector3.new(math.cos(angle) * entry.Radius, 0.5, math.sin(angle) * entry.Radius)
				blade.CFrame = CFrame.new(p, p + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
			end
		end
	end
end)

local FLOAT_SIZE, DAMAGE_SIZE = UDim2.new(0, 140, 0, 36), UDim2.new(0, 90, 0, 40)
local HANDLERS = {
	S = playShot,
	P = spawnProjectile,
	X = function(event) removeProjectile(event[2]) end,
	T = tracer,
	B = function(event) burst(event[2], event[3], event[4]) end,
	F = function(event) showText(event[2], event[3], event[4], FLOAT_SIZE, 0.7, 3) end,
	D = function(event) -- { "D", position, amount, isCrit }
		showText(event[2], event[4] and (tostring(event[3]) .. "!") or tostring(event[3]), event[4] and Color3.fromRGB(255, 220, 60) or WHITE, DAMAGE_SIZE, 0.5, nil)
	end,
	H = function(event) flash(event[2]) end,
	G = gunSound,
	R = ring, Z = bolt, M = missile, L = flame, E = meteor, O = orbit,
}

Remotes.Fx.OnClientEvent:Connect(function(batch)
	if typeof(batch) ~= "table" then return end
	for _, event in ipairs(batch) do
		local handler = HANDLERS[event[1]]
		if handler then
			local ok, err = pcall(handler, event)
			if not ok and game:GetService("RunService"):IsStudio() then warn("[Fx] " .. tostring(err)) end
		end
	end
end)
