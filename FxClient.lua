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

local MAX_ACTIVE_BURSTS, MAX_ACTIVE_TEXTS = 70, 110
local activeBursts, activeTexts = 0, 0

local function burst(position, color, count)
	if activeBursts >= MAX_ACTIVE_BURSTS then return end -- 동시 폭발 상한: 넘치면 새 것을 건너뛴다
	activeBursts += 1
	local entry = getBurst()
	entry.Part.Position = position
	entry.Part.Parent = fxFolder
	entry.Emitter.Color = ColorSequence.new(color)
	entry.Emitter:Emit(math.min(count or 40, 120))
	task.delay(1.4, function()
		activeBursts -= 1
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
	if activeTexts >= MAX_ACTIVE_TEXTS then return end
	activeTexts += 1
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
		activeTexts -= 1
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
	Pistol = { SizeMul = 1.0, Muzzle = 2.4 }, -- 총구에 작은 고리
	Revolver = { Style = "Ball", SizeMul = 1.35, Impact = 10, Muzzle = 3.6 }, -- 묵직한 한 발 + 큰 총구 고리
	Smg = { Style = "Bolt", Length = 2.2, SizeMul = 0.55, Mini = true }, -- 가늘고 짧은 연사 탄 (시대 효과는 최소)
	Rifle = { Style = "Bolt", Length = 3.5 },
	Shotgun = { Style = "Ball", SizeMul = 0.55, Mini = true, Puff = true }, -- 작은 산탄 알갱이 + 총구 원뿔 연기
}
-- 로켓 / 레일건 / 저격총 / 캐논 / 화염방사기는 아래 SPECIAL 이 따로 그린다
local RATE_ERA = { Orb = 40, Cannon = 25, Fire = 90, Rocket = 110, Rainbow = 80 }
local RATE_STYLE = { Orb = 40, Cannon = 25, Fire = 90, Rocket = 110 }


------------------------------------------------------------
-- 무기 종류별 전용 탄 (로켓은 진짜 로켓, 레일건은 빔, 저격총은 긴 줄기, 캐논은 플라즈마 구, 화염방사기는 불덩이)
------------------------------------------------------------
local function solid(parent, size, color, material, offset, transparency, shape)
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, false, true
	part.Material = material or Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0
	if shape then part.Shape = shape end
	part.Size = size
	part.CFrame = parent.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = parent, part
	weld.Parent = part
	part.Parent = parent
	return part
end

local function rootPart(cf, size, color, material, shape, transparency)
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Material = material or Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 0
	if shape then part.Shape = shape end
	part.Size = size
	part.CFrame = cf
	part.Parent = fxFolder
	return part
end

local function addEmitter(part, color, rate, size, lifetime, speed, transparencyEnd)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Speed = NumberRange.new(0, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, transparencyEnd or 1) })
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = part
	return emitter
end

local function fly(part, from, to, speed, minTime, onDone)
	local distance = (to - from).Magnitude
	local duration = math.clamp(distance / speed, minTime or 0.03, 1.2)
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(to, to + (to - from)) })
	tween.Completed:Connect(function()
		onDone()
		activeShots -= 1
	end)
	tween:Play()
end

local SPECIAL = {}

-- 로켓: 몸통 + 빨간 머리 + 꼬리 날개 + 불꽃 분사 + 연기 꼬리, 닿으면 큰 폭발
SPECIAL.Rocket = function(from, to, size, speed, color, era)
	local s = math.clamp(size, 0.8, 2.0)
	local cf = CFrame.lookAt(from, to)
	local body = rootPart(cf, Vector3.new(s * 0.55, s * 0.55, s * 2.6), Color3.fromRGB(205, 208, 215), Enum.Material.Metal)
	solid(body, Vector3.new(s * 0.5, s * 0.5, s * 0.9), Color3.fromRGB(215, 60, 50), Enum.Material.Metal, CFrame.new(0, 0, -s * 1.6))
	solid(body, Vector3.new(s * 0.12, s * 1.3, s * 0.7), color, Enum.Material.Neon, CFrame.new(0, 0, s * 1.0))
	solid(body, Vector3.new(s * 1.3, s * 0.12, s * 0.7), color, Enum.Material.Neon, CFrame.new(0, 0, s * 1.0))
	local flame = solid(body, Vector3.new(s * 0.5, s * 0.5, s * 1.4), Color3.fromRGB(255, 170, 60), Enum.Material.Neon, CFrame.new(0, 0, s * 2.0), 0.15)
	local smoke = addEmitter(flame, Color3.fromRGB(190, 190, 195), 55, s * 0.9, 0.7, 1.5, 1)
	smoke.LightEmission = 0.1
	addEmitter(flame, Color3.fromRGB(255, 140, 40), 40, s * 0.55, 0.25, 3)
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 9 + era, 1.4, Color3.fromRGB(255, 160, 70)
	light.Parent = flame
	burst(from, Color3.fromRGB(190, 190, 195), 6) -- 발사 연기
	fly(body, from, to, speed, 0.05, function()
		burst(to, Color3.fromRGB(255, 150, 50), 36)
		burst(to, color, 14)
		local blast = rootPart(CFrame.new(to), Vector3.new(2, 2, 2), Color3.fromRGB(255, 190, 90), Enum.Material.Neon, Enum.PartType.Ball, 0.2)
		TweenService:Create(blast, TweenInfo.new(0.3), { Size = Vector3.new(12, 12, 12), Transparency = 1 }):Play()
		Debris:AddItem(blast, 0.4)
		body:Destroy()
	end)
end

-- 레일건: 순식간에 지나가는 얇은 빔 (남았다가 사라진다) + 도착점 충격 고리
SPECIAL.Rail = function(from, to, size, _, color)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, to)
	local core = rootPart(cf, Vector3.new(size * 0.3, size * 0.3, length), Color3.fromRGB(235, 250, 255), Enum.Material.Neon)
	local aura = rootPart(cf, Vector3.new(size * 1.1, size * 1.1, length), color, Enum.Material.Neon, nil, 0.65)
	TweenService:Create(core, TweenInfo.new(0.28), { Size = Vector3.new(0.05, 0.05, length), Transparency = 1 }):Play()
	TweenService:Create(aura, TweenInfo.new(0.35), { Size = Vector3.new(size * 0.1, size * 0.1, length), Transparency = 1 }):Play()
	Debris:AddItem(core, 0.4)
	Debris:AddItem(aura, 0.45)
	burst(from, color, 5)
	burst(to, color, 12)
	local ringPart = rootPart(CFrame.new(to) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.2, 1, 1), color, Enum.Material.Neon, Enum.PartType.Cylinder, 0.2)
	TweenService:Create(ringPart, TweenInfo.new(0.25), { Size = Vector3.new(0.2, 9, 9), Transparency = 1 }):Play()
	Debris:AddItem(ringPart, 0.3)
	activeShots += 1
	task.delay(0.35, function() activeShots -= 1 end)
end

-- 저격총: 아주 빠른 흰 줄기 + 지나간 자리에 남는 가는 궤적선
SPECIAL.Sniper = function(from, to, size, speed, color)
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt(from, to)
	local slug = rootPart(cf, Vector3.new(size * 0.4, size * 0.4, 9), Color3.fromRGB(245, 250, 255), Enum.Material.Neon)
	local line = rootPart(CFrame.lookAt((from + to) / 2, to), Vector3.new(size * 0.18, size * 0.18, length), color, Enum.Material.Neon, nil, 0.4)
	TweenService:Create(line, TweenInfo.new(0.4), { Size = Vector3.new(0.03, 0.03, length), Transparency = 1 }):Play()
	Debris:AddItem(line, 0.45)
	burst(from, color, 3)
	fly(slug, from, to, math.max(speed, 700), 0.03, function()
		burst(to, color, 10)
		slug:Destroy()
	end)
end

-- 캐논: 속이 환한 플라즈마 구 (바깥 막이 펄럭이며 입자를 흘린다), 닿으면 커다란 섬광
SPECIAL.Cannon = function(from, to, size, speed, color, era)
	local s = math.clamp(size, 1.2, 4.5)
	local core = rootPart(CFrame.lookAt(from, to), Vector3.new(s, s, s), Color3.fromRGB(255, 255, 255):Lerp(color, 0.35), Enum.Material.Neon, Enum.PartType.Ball)
	local shell = solid(core, Vector3.new(s * 1.8, s * 1.8, s * 1.8), color, Enum.Material.Neon, CFrame.identity, 0.62, Enum.PartType.Ball)
	addEmitter(core, color, 45, s * 0.7, 0.45, 3)
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 10 + era * 2, 1.5, color
	light.Parent = core
	TweenService:Create(shell, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = Vector3.new(s * 2.3, s * 2.3, s * 2.3) }):Play()
	burst(from, color, 6)
	fly(core, from, to, speed, 0.05, function()
		burst(to, color, 28)
		local blast = rootPart(CFrame.new(to), Vector3.new(s, s, s), color, Enum.Material.Neon, Enum.PartType.Ball, 0.3)
		TweenService:Create(blast, TweenInfo.new(0.28), { Size = Vector3.new(s * 5, s * 5, s * 5), Transparency = 1 }):Play()
		Debris:AddItem(blast, 0.35)
		core:Destroy()
	end)
end

-- 화염방사기: 날아가며 점점 커지는 불덩이 (멀리까지 가지 않고 가까운 곳에서 꺼진다)
SPECIAL.Flamer = function(from, to, size, speed, color)
	local reach = math.min((to - from).Magnitude, 62)
	local stop = from + (to - from).Unit * reach
	local s = math.clamp(size, 1.0, 3.5)
	local fire = rootPart(CFrame.lookAt(from, to), Vector3.new(s * 0.8, s * 0.8, s * 0.8), Color3.fromRGB(255, 190, 70), Enum.Material.Neon, Enum.PartType.Ball, 0.25)
	addEmitter(fire, Color3.fromRGB(255, 120, 30), 70, s * 0.9, 0.5, 4)
	local duration = math.clamp(reach / math.max(speed, 60), 0.12, 0.8)
	TweenService:Create(fire, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = Vector3.new(s * 3.4, s * 3.4, s * 3.4), Transparency = 0.8, Color = Color3.fromRGB(255, 70, 20) }):Play()
	fly(fire, from, stop, speed, 0.12, function()
		burst(stop, Color3.fromRGB(255, 130, 40), 6)
		fire:Destroy()
	end)
end

------------------------------------------------------------
-- 시대(era)별 탄 서명: 무기 종류 모양 위에 얹는다 (탄 하나당 추가 부품/입자 3개 이하, 기관단총/샷건은 1개)
------------------------------------------------------------
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local ERA_TINT = { -- 탄 색을 시대 느낌으로 덮어쓴다
	[1] = Color3.fromRGB(150, 130, 105), [2] = Color3.fromRGB(205, 230, 255), [4] = Color3.fromRGB(255, 205, 70),
	[5] = Color3.fromRGB(255, 140, 45), [6] = Color3.fromRGB(170, 235, 255), [7] = Color3.fromRGB(255, 245, 110),
	[8] = Color3.fromRGB(135, 75, 220), [9] = Color3.fromRGB(255, 95, 35),
}
local ERA_CORE = { [8] = Color3.fromRGB(35, 15, 60) } -- 암흑: 몸통은 검보라, 꼬리 / 폭발은 보라 빛
local DRAGON = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 60)), ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 30, 15)) })
local ERA_TRAIL = { [5] = FIRE, [9] = DRAGON }

local function sigEmitter(part, colorSeq, rate, size, life, speed, accel, texture, emission)
	local e = Instance.new("ParticleEmitter")
	e.Rate = rate
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(speed * 0.3, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = emission or 1
	e.Color = colorSeq
	if accel then e.Acceleration = accel end
	if texture then e.Texture = texture end
	e.Parent = part
	return e
end

local lastRing, lastPuff = 0, 0
local function eraRing(pos, color, d0, d1, dur, facing)
	local now = os.clock()
	if now - lastRing < 0.04 then return end -- 연사 때 고리가 쌓이지 않게
	lastRing = now
	local cf = facing and (CFrame.lookAt(pos, pos + facing) * CFrame.Angles(0, math.rad(90), 0)) or (CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)))
	local p = rootPart(cf, Vector3.new(0.2, d0, d0), color, Enum.Material.Neon, Enum.PartType.Cylinder, 0.35)
	TweenService:Create(p, TweenInfo.new(dur), { Size = Vector3.new(0.2, d1, d1), Transparency = 1 }):Play()
	Debris:AddItem(p, dur + 0.05)
end

-- c = { size, back(머리에서 꼬리쪽 거리), color, mini }. 돌려주는 함수는 탄이 끝날 때 부른다 (반복 트윈 정리)
local ERA_SIG = {}
ERA_SIG[1] = function(part, c) -- 녹슨: 탁한 회갈색 탄 + 작은 먼지
	sigEmitter(part, ColorSequence.new(Color3.fromRGB(125, 108, 90)), c.mini and 10 or 16, math.max(c.size * 0.7, 0.3), 0.45, 2, nil, SMOKE, 0)
end
ERA_SIG[2] = function(part, c) -- 강철: 말끔한 흰청 줄기 + 짧은 불꽃 틱
	sigEmitter(part, ColorSequence.new(Color3.fromRGB(230, 245, 255)), c.mini and 14 or 24, 0.2, 0.18, 12)
end
ERA_SIG[3] = function(part, c) -- 마력: 보라 구슬 + 돌아가는 알갱이 2개 + 별 꼬리
	if not c.mini then
		local r = c.size * 0.8 + 0.4
		for _, sx in ipairs({ -1, 1 }) do
			solid(part, Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(235, 200, 255), Enum.Material.Neon, CFrame.new(sx * r, 0, 0), 0, Enum.PartType.Ball)
		end
		c.roll = math.rad(170) -- 날아가는 동안 반 바퀴 돌아 알갱이가 궤도를 도는 것처럼 보인다
	end
	sigEmitter(part, ColorSequence.new(Color3.fromRGB(215, 160, 255)), c.mini and 14 or 24, math.max(c.size * 0.5, 0.35), 0.5, 1.5, nil, SPARKLE)
end
ERA_SIG[4] = function(part, c) -- 황금: 금빛 혜성 (꼬리 덩어리) + 반짝이
	if not c.mini then
		local len = c.size * 2.6
		solid(part, Vector3.new(c.size * 0.55, c.size * 0.55, len), Color3.fromRGB(255, 225, 120), Enum.Material.Neon, CFrame.new(0, 0, c.back + len * 0.5), 0.45)
	end
	sigEmitter(part, ColorSequence.new(Color3.fromRGB(255, 240, 150)), c.mini and 16 or 30, math.max(c.size * 0.45, 0.3), 0.6, 2.5, nil, SPARKLE)
end
ERA_SIG[5] = function(part, c) -- 불꽃: 불꽃 물방울 (머리 + 뾰족 꼬리) + 위로 오르는 불씨
	if not c.mini then
		local len = c.size * 2.4
		solid(part, Vector3.new(c.size * 0.55, c.size * 0.55, len), Color3.fromRGB(255, 90, 25), Enum.Material.Neon, CFrame.new(0, 0, c.back + len * 0.5), 0.3)
	end
	sigEmitter(part, FIRE, c.mini and 16 or 30, math.max(c.size * 0.35, 0.28), 0.6, 3, Vector3.new(0, 6, 0))
end
ERA_SIG[6] = function(part, c) -- 빙결: 옅은 하늘색 결정 조각 + 눈송이 안개
	if not c.mini then
		local s = c.size * 0.9
		solid(part, Vector3.new(s, s, s), Color3.fromRGB(215, 245, 255), Enum.Material.Neon, CFrame.Angles(math.rad(45), math.rad(45), 0), 0.15)
	end
	sigEmitter(part, ColorSequence.new(Color3.fromRGB(220, 242, 255)), c.mini and 14 or 22, math.max(c.size * 0.5, 0.35), 0.8, 1.5, Vector3.new(0, -3, 0), SPARKLE)
end
ERA_SIG[7] = function(part, c) -- 번개: 지그재그 가는 마디 3개 (하나는 깜빡임)
	local count = c.mini and 1 or 3
	local segLen = math.max(c.size * 2.2, 1.4)
	local first
	for i = 1, count do
		local sign = (i % 2 == 0) and 1 or -1
		local seg = solid(part, Vector3.new(0.14, 0.14, segLen * 1.15), Color3.fromRGB(255, 250, 170), Enum.Material.Neon,
			CFrame.new(sign * 0.55, 0, c.back + (i - 0.5) * segLen) * CFrame.Angles(0, sign * 0.75, 0))
		first = first or seg
	end
	if c.mini then return end
	local flicker = TweenService:Create(first, TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.75 })
	flicker:Play()
	return function() flicker:Cancel() end
end
ERA_SIG[8] = function(part, c) -- 암흑: 검보라 구 + 보랏빛 막 + 연기 꼬리
	if not c.mini then
		local s = c.size * 1.7
		solid(part, Vector3.new(s, s, s), c.color, Enum.Material.Neon, CFrame.identity, 0.55, Enum.PartType.Ball)
	end
	sigEmitter(part, ColorSequence.new(Color3.fromRGB(70, 30, 115)), c.mini and 14 or 28, math.max(c.size * 0.9, 0.5), 0.7, 1.5, nil, SMOKE, 0)
end
ERA_SIG[9] = function(part, c) -- 용: 주황 불덩이 + S자로 굽은 긴 꼬리 2마디 + 용의 불씨
	if not c.mini then
		local len = c.size * 2.2
		for i = 1, 2 do
			local sign = (i == 1) and 1 or -1
			solid(part, Vector3.new(c.size * (0.85 - 0.3 * i), c.size * (0.85 - 0.3 * i), len), (i == 1) and Color3.fromRGB(255, 120, 40) or Color3.fromRGB(200, 40, 20),
				Enum.Material.Neon, CFrame.new(sign * c.size * 0.45, 0, c.back + (i - 0.5) * len) * CFrame.Angles(0, sign * 0.35, 0), 0.25)
		end
	end
	sigEmitter(part, DRAGON, c.mini and 16 or 36, math.max(c.size * 0.4, 0.3), 0.5, 3, Vector3.new(0, 3, 0))
end
ERA_SIG[10] = function(part, c) -- 신화: 무지개 리본 (가로로 한 줄 더) + 별가루
	if not c.mini then
		local w = c.size * 1.2 + 0.3
		local b0 = Instance.new("Attachment")
		b0.Position = Vector3.new(w, 0, 0)
		b0.Parent = part
		local b1 = Instance.new("Attachment")
		b1.Position = Vector3.new(-w, 0, 0)
		b1.Parent = part
		local ribbon = Instance.new("Trail")
		ribbon.Attachment0, ribbon.Attachment1 = b0, b1
		ribbon.Lifetime = 0.35
		ribbon.Color = RAINBOW
		ribbon.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		ribbon.LightEmission = 1
		ribbon.FaceCamera = true
		ribbon.Parent = part
	end
	sigEmitter(part, RAINBOW, c.mini and 16 or 34, math.max(c.size * 0.45, 0.3), 0.6, 2, nil, SPARKLE)
end

-- 시대별 착탄 모양 (burst / ring 재사용, 눈부신 큰 번쩍임은 없다)
local ERA_IMPACT = {}
ERA_IMPACT[1] = function(to, _, n) burst(to, Color3.fromRGB(125, 108, 90), n) end -- 먼지
ERA_IMPACT[2] = function(to, color, n) burst(to, color, n) burst(to, WHITE, 4) end -- 불꽃 틱
ERA_IMPACT[3] = function(to, color, n) burst(to, color, n) eraRing(to, color, 1, 6, 0.25) end -- 마력 고리
ERA_IMPACT[4] = function(to, color, n) burst(to, color, n) burst(to, Color3.fromRGB(255, 250, 200), math.floor(n * 0.4)) end -- 금가루
ERA_IMPACT[5] = function(to, _, n) burst(to, Color3.fromRGB(255, 100, 30), n) burst(to, Color3.fromRGB(255, 220, 90), math.floor(n * 0.4)) end -- 불꽃 + 불씨
ERA_IMPACT[6] = function(to, color, n) burst(to, color, n) burst(to, WHITE, 10) eraRing(to, Color3.fromRGB(190, 240, 255), 1, 7, 0.2) end -- 얼음 파편
ERA_IMPACT[7] = function(to, color, n) burst(to, color, n) burst(to, WHITE, 8) end -- 스파크
ERA_IMPACT[8] = function(to, color, n) -- 공허 파문: 퍼지는 고리 + 빨려드는 고리
	burst(to, Color3.fromRGB(90, 40, 150), n)
	eraRing(to, color, 1, 9, 0.4)
	eraRing(to, Color3.fromRGB(60, 25, 110), 10, 1, 0.3)
end
ERA_IMPACT[9] = function(to, _, n) -- 용의 불길
	burst(to, Color3.fromRGB(255, 120, 40), n)
	burst(to, Color3.fromRGB(200, 40, 20), math.floor(n * 0.5))
	eraRing(to, Color3.fromRGB(255, 140, 50), 1, 10, 0.3)
end
ERA_IMPACT[10] = function(to, _, n) -- 별 터짐: 세 빛깔 + 흰 고리
	local m = math.max(math.floor(n * 0.4), 6)
	burst(to, Color3.fromRGB(255, 90, 120), m)
	burst(to, Color3.fromRGB(255, 230, 90), m)
	burst(to, Color3.fromRGB(90, 210, 255), m)
	eraRing(to, WHITE, 1, 9, 0.3)
end

-- event = { "S", from, to, size, speed, impact, style, length, color, rainbow, class, era }
local function playShot(event)
	if activeShots >= MAX_ACTIVE_SHOTS then return end
	local from, to = event[2], event[3]
	local size, speed, impact, eraStyle, length = event[4], event[5], event[6], event[7], event[8]
	local color, rainbow, class, era = event[9], event[10], event[11], event[12] or 1
	if Players.LocalPlayer:GetAttribute("InDoomArena") then color = color:Lerp(WHITE, 0.6) end -- 최후의 군주 결투장: 바닥이 붉어도 내 탄이 또렷하게
	local distance = (to - from).Magnitude
	if distance < 0.5 then return end
	local style = eraStyle
	local special = class and SPECIAL[class]
	if special then
		activeShots += 1 -- (fly 가 끝나면 스스로 줄인다)
		special(from, to, size, speed, color, era)
		return
	end
	local look = class and CLASS_LOOK[class]
	if look then
		style = look.Style or style
		length = look.Length or length or 3
		size *= look.SizeMul or 1
		impact = look.Impact or impact
		color = look.Color or color
	end
	local mini = look ~= nil and look.Mini == true -- 기관단총 / 샷건: 연사가 많아 시대 효과를 최소로
	if not rainbow and ERA_TINT[era] then color = ERA_TINT[era] end
	size = math.max(size, mini and 0.2 or 0.3) -- 뒤에서 봐도 보이게 바닥 굵기
	activeShots += 1

	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Material = Enum.Material.Neon
	part.Color = (not rainbow and ERA_CORE[era]) or color
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
	if not rainbow and ERA_TRAIL[era] then colorSeq = ERA_TRAIL[era] end
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

	local sig = ERA_SIG[era]
	local sigCleanup, roll
	if sig then
		local isBolt = style == "Bolt" or style == "Rocket"
		local ctx = { size = size, back = (isBolt and (length or 3) or size) / 2, color = color, mini = mini }
		sigCleanup = sig(part, ctx)
		roll = ctx.roll
	end
	local rate = (not sig) and (RATE_ERA[eraStyle] or RATE_STYLE[style]) or nil
	if not sig and not rate and era >= 2 then rate = 6 + era * 4 end
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
	if era >= 7 and not mini then -- 점 조명은 번개 이상 + 연사 무기 제외
		local light = Instance.new("PointLight")
		light.Range, light.Brightness, light.Color = 5 + era * 2, 0.7 + 0.1 * era, color
		light.Parent = part
	end
	part.Parent = fxFolder
	Debris:AddItem(part, 3) -- 안전장치: 어떤 이유로든 도착 처리가 안 돼도 탄이 화면에 남지 않게
	local dir = (to - from).Unit
	if look and look.Muzzle then -- 권총 / 리볼버: 총구 고리 (총구 앞쪽에서 퍼지며 사라진다)
		eraRing(from + dir * 0.8, color, 0.6, look.Muzzle, 0.14, dir)
	elseif look and look.Puff then -- 샷건: 총구 원뿔 연기 (펠릿마다 만들지 않고 간격을 둔다)
		local now = os.clock()
		if now - lastPuff > 0.08 then
			lastPuff = now
			burst(from + dir * 1.2, Color3.fromRGB(215, 215, 220):Lerp(color, 0.25), 5)
		end
	elseif era >= 2 and not mini then
		burst(from, color, 2 + era)
	end

	local duration = math.clamp(distance / speed, 0.03, 1.2)
	local goal = CFrame.lookAt(to, to + (to - from))
	if roll then goal = goal * CFrame.Angles(0, 0, roll) end
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = goal })
	tween.Completed:Connect(function()
		part.Transparency = 1
		if sigCleanup then sigCleanup() end
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("ParticleEmitter") then child.Enabled = false
			elseif child:IsA("BasePart") then child.Transparency = 1 end
		end
		local onImpact = ERA_IMPACT[era]
		if mini then -- 연사 무기: 착탄은 한 번의 작은 입자만
			burst(to, color, math.min(math.max(impact or 0, 4), 8))
		elseif onImpact then
			onImpact(to, color, math.clamp(math.max(impact or 0, 6), 6, 70))
		elseif impact and impact > 0 then
			burst(to, color, impact)
		end
		activeShots -= 1
		Debris:AddItem(part, 0.5)
	end)
	tween:Play()
end

------------------------------------------------------------
-- 적 탄: 서버는 숫자로만 움직이고, 여기서는 시작 / 끝 두 점 사이를 부드럽게 날아가게만 그린다
------------------------------------------------------------
local projectiles = {} -- [id] = { Part, Tween, Mover, Pop }
local movers = {}      -- 직선이 아닌 탄(뱀 / 곡선 / 포물선 / 유도): 서버와 같은 식으로 매 프레임 위치를 그린다
local MAX_MOVERS = 70

-- 모양별 기본색 (채도를 낮춘 차분한 색 하나). 서버가 색을 정해 보내면 그 색을 쓴다.
local STYLE_COLOR = {
	Crescent = Color3.fromRGB(180, 150, 225), Halo = Color3.fromRGB(110, 215, 185), Crystal = Color3.fromRGB(125, 200, 225),
	Skull = Color3.fromRGB(225, 220, 200), Needle = Color3.fromRGB(200, 160, 230), Bomb = Color3.fromRGB(235, 140, 70),
	Missile = Color3.fromRGB(235, 165, 95), Seeker = Color3.fromRGB(135, 190, 235), Snake = Color3.fromRGB(165, 205, 90),
}

-- 메인 부품에 용접되어 같이 움직이는 덧붙임 부품 (한 탄이 1~3개 부품으로 이루어진다)
local function addPiece(main, shape, size, offset, color, material, transparency)
	local piece = Instance.new("Part")
	piece.Anchored, piece.CanCollide, piece.CanQuery, piece.CanTouch, piece.Massless = false, false, false, false, true
	if shape then piece.Shape = shape end
	piece.Material = material or Enum.Material.Neon
	piece.Color = color
	piece.Transparency = transparency or 0
	piece.Size = size
	piece.CFrame = main.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = main, piece
	weld.Parent = piece
	piece.Parent = main
	return piece
end

-- 꼬리 불꽃 입자 (유도탄에만 붙인다)
local function addFlame(onPart, size, c1, c2)
	local flame = Instance.new("ParticleEmitter")
	flame.Rate = 28
	flame.Lifetime = NumberRange.new(0.25, 0.45)
	flame.Speed = NumberRange.new(3, 6)
	flame.SpreadAngle = Vector2.new(12, 12)
	flame.EmissionDirection = Enum.NormalId.Back
	flame.LightEmission = 0.8
	flame.Color = ColorSequence.new(c1, c2)
	flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, 0) })
	flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	flame.Parent = onPart
end

local BALL, BLOCK, CYLINDER = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local PLASTIC, METAL = Enum.Material.SmoothPlastic, Enum.Material.Metal

local function spawnProjectile(event)
	-- { "P", id, origin, direction, speed, size, color, style, life, path }
	-- path: nil(직선) / { "sine", 진폭, 빈도 } / { "curve", 각속도 } / { "lob", 착지점, 높이 } / { "home" }
	local id, origin, direction, speed, size, color, style, life, path = event[2], event[3], event[4], event[5], event[6], event[7], event[8], event[9], event[10]
	life = life or 5
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Material = Enum.Material.Neon
	part.Color = color or STYLE_COLOR[style] or Color3.fromRGB(255, 120, 30)
	local look = CFrame.lookAt(origin, origin + direction)
	local baseColor = part.Color
	local pieces -- 메인 부품이 자리 잡고 workspace 에 들어간 뒤에 붙일 덧붙임 부품들
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
	elseif style == "Crescent" then -- 초승달 칼날: 앞이 뾰족한 ㅅ자 (가운데 + 양 날개 부품)
		local k = size * 1.5
		part.Size = Vector3.new(k * 0.4, k * 0.2, k * 0.55)
		part.CFrame = look
		pieces = function()
			for _, side in ipairs({ -1, 1 }) do
				addPiece(part, BLOCK, Vector3.new(k * 0.26, k * 0.18, k * 1.6), CFrame.new(side * k * 0.6, 0, k * 0.5) * CFrame.Angles(0, math.rad(side * 50), 0), baseColor:Lerp(WHITE, 0.2))
			end
		end
	elseif style == "Halo" then -- 후광 고리: 빛나는 원판 + 어두운 속 + 밝은 핵
		local k = size * 1.2
		part.Shape = CYLINDER
		part.Size = Vector3.new(k * 0.25, k * 2, k * 2)
		part.CFrame = look * CFrame.Angles(0, math.rad(90), 0)
		pieces = function()
			addPiece(part, CYLINDER, Vector3.new(k * 0.4, k * 1.2, k * 1.2), CFrame.identity, Color3.fromRGB(18, 30, 36), PLASTIC)
			addPiece(part, BALL, Vector3.new(k * 0.5, k * 0.5, k * 0.5), CFrame.identity, baseColor:Lerp(WHITE, 0.5))
		end
	elseif style == "Crystal" then -- 수정: 서로 엇갈린 두 마름모
		part.Size = Vector3.new(size * 0.65, size * 0.65, size * 1.8)
		part.CFrame = look * CFrame.Angles(0, 0, math.rad(45))
		part.Color = baseColor:Lerp(WHITE, 0.2)
		part.Transparency = 0.1
		pieces = function()
			addPiece(part, BLOCK, Vector3.new(size * 0.65, size * 0.65, size * 1.3), CFrame.Angles(0, 0, math.rad(-45)), baseColor, Enum.Material.Neon, 0.3)
		end
	elseif style == "Skull" then -- 해골 구슬: 뼈색 공 + 검은 눈 두 개
		part.Shape = BALL
		part.Size = Vector3.new(size * 1.1, size * 1.1, size * 1.1)
		part.CFrame = look
		pieces = function()
			for _, side in ipairs({ -1, 1 }) do
				addPiece(part, BALL, Vector3.new(size * 0.24, size * 0.28, size * 0.2), CFrame.new(side * size * 0.2, size * 0.1, -size * 0.45), Color3.fromRGB(25, 22, 28), PLASTIC)
			end
		end
	elseif style == "Needle" then -- 가시 묶음: 가는 바늘 세 개
		local k = size
		part.Size = Vector3.new(k * 0.2, k * 0.2, k * 2.8)
		part.CFrame = look
		pieces = function()
			for _, side in ipairs({ -1, 1 }) do
				addPiece(part, BLOCK, Vector3.new(k * 0.15, k * 0.15, k * 2.0), CFrame.new(side * k * 0.3, 0, k * 0.4) * CFrame.Angles(0, math.rad(side * 7), 0), baseColor:Lerp(WHITE, 0.25))
			end
		end
	elseif style == "Bomb" then -- 폭탄: 어두운 쇠공 + 심지 + 타는 불꽃
		part.Shape = BALL
		part.Size = Vector3.new(size, size, size)
		part.CFrame = look
		part.Material = METAL
		part.Color = Color3.fromRGB(62, 64, 72)
		pieces = function()
			addPiece(part, BLOCK, Vector3.new(size * 0.1, size * 0.34, size * 0.1), CFrame.new(0, size * 0.55, 0), Color3.fromRGB(150, 120, 80), PLASTIC)
			addPiece(part, BALL, Vector3.new(size * 0.3, size * 0.3, size * 0.3), CFrame.new(0, size * 0.78, 0), baseColor)
		end
	elseif style == "Missile" then -- 미사일: 몸통 + 코 + 꼬리날개 + 불꽃 (유도탄)
		local k = size
		part.Size = Vector3.new(k * 0.5, k * 0.5, k * 1.7)
		part.CFrame = look
		part.Material = PLASTIC
		part.Color = baseColor:Lerp(Color3.fromRGB(70, 72, 80), 0.55)
		pieces = function()
			addPiece(part, BALL, Vector3.new(k * 0.55, k * 0.55, k * 0.7), CFrame.new(0, 0, -k * 0.85), baseColor)
			addPiece(part, BLOCK, Vector3.new(k * 1.4, k * 0.1, k * 0.55), CFrame.new(0, 0, k * 0.6), baseColor:Lerp(Color3.fromRGB(70, 72, 80), 0.3), PLASTIC)
			local core = addPiece(part, BALL, Vector3.new(k * 0.4, k * 0.4, k * 0.4), CFrame.new(0, 0, k * 0.95), Color3.fromRGB(255, 205, 120))
			addFlame(core, k, Color3.fromRGB(255, 200, 110), Color3.fromRGB(140, 120, 110))
		end
	elseif style == "Seeker" then -- 유도 구슬: 빛나는 구슬 + 흐릿한 꼬리 + 꼬리 불꽃
		part.Shape = BALL
		part.Size = Vector3.new(size, size, size)
		part.CFrame = look
		pieces = function()
			local tail = addPiece(part, BALL, Vector3.new(size * 0.6, size * 0.6, size * 0.6), CFrame.new(0, 0, size * 0.75), baseColor, Enum.Material.Neon, 0.35)
			addFlame(tail, size * 0.9, baseColor:Lerp(WHITE, 0.5), baseColor)
		end
	elseif style == "Snake" then -- 뱀: 머리 + 점점 작아지는 몸 두 마디
		part.Shape = BALL
		part.Size = Vector3.new(size, size, size)
		part.CFrame = look
		pieces = function()
			addPiece(part, BALL, Vector3.new(size * 0.75, size * 0.75, size * 0.75), CFrame.new(0, 0, size * 0.85), baseColor, Enum.Material.Neon, 0.15)
			addPiece(part, BALL, Vector3.new(size * 0.55, size * 0.55, size * 0.55), CFrame.new(0, 0, size * 1.55), baseColor, Enum.Material.Neon, 0.3)
		end
	else
		part.Shape = BALL
		part.Size = Vector3.new(size, size, size)
		part.Position = origin
	end
	part.Color = part.Color:Lerp(Color3.fromRGB(128, 128, 140), 0.3) -- 너무 쨍하지 않게 살짝 가라앉힌다 (특히 보스 탄)
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 6, 0.5, part.Color
	light.Shadows = false
	light.Parent = part
	part.Parent = fxFolder
	Debris:AddItem(part, (life or 5) + 0.6) -- 가장 먼저 수명을 걸어 둔다: 아래에서 오류가 나도 탄이 남아 있지 않게
	if pieces then
		local ok = pcall(pieces)
		if not ok then part:Destroy() return end
	end

	local entry = { Part = part, Pop = (style == "Missile" or style == "Seeker") }
	local pathKind = path and path[1]
	if pathKind and #movers < MAX_MOVERS then
		-- 직선이 아닌 탄: 부품 모양을 진행 방향에 맞춰 돌릴 때 쓸 "처음 자세 대비 회전" 을 기억한다
		local mover = { Part = part, Kind = pathKind, Origin = origin, Dir = direction, Speed = speed, T0 = os.clock(), End = os.clock() + life + 0.3, Rel = look:ToObjectSpace(part.CFrame) }
		mover.Rel = mover.Rel.Rotation
		if pathKind == "sine" then
			local side = Vector3.new(-direction.Z, 0, direction.X)
			mover.Side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
			mover.Amp, mover.Freq = path[2], path[3]
		elseif pathKind == "curve" then
			mover.W = path[2]
		elseif pathKind == "lob" then
			mover.Target, mover.Height, mover.Dur = path[2], path[3], life
		elseif pathKind == "home" then
			mover.Pos, mover.TargetDir = origin, direction
		end
		entry.Mover = mover
		table.insert(movers, mover)
	else
		local endCFrame = part.CFrame + direction * speed * life
		entry.Tween = TweenService:Create(part, TweenInfo.new(life, Enum.EasingStyle.Linear), { CFrame = endCFrame })
		entry.Tween:Play()
	end
	projectiles[id] = entry
	Debris:AddItem(part, life + 0.3)
	task.delay(life + 0.3, function() projectiles[id] = nil end)
end

local function removeProjectile(id, pop)
	local entry = projectiles[id]
	if entry then
		projectiles[id] = nil
		if entry.Tween then entry.Tween:Cancel() end
		if entry.Mover then entry.Mover.Dead = true end
		if pop or entry.Pop then burst(entry.Part.Position, entry.Part.Color, 8) end -- 작은 터짐 (유도탄 명중 / 갈라짐)
		entry.Part:Destroy()
	end
end

-- 유도탄 새 방향 { "Q", id, 위치, 방향, 속도 }: 서버가 0.2초마다 알린다. 클라이언트는 방향을 부드럽게 돌리고 위치는 살짝만 보정한다.
local function reaimProjectile(event)
	local entry = projectiles[event[2]]
	local mover = entry and entry.Mover
	if not mover or mover.Kind ~= "home" then return end
	local predicted = event[3] + event[4] * event[5] * 0.06
	mover.Pos = ((mover.Pos - predicted).Magnitude > 20) and predicted or mover.Pos:Lerp(predicted, 0.5)
	mover.TargetDir, mover.Speed = event[4], event[5]
end

-- 땅 위 경고 { "W", 위치, 반지름, 지속 초, 색 }: 착탄 지점에 흐린 원이 나타나고 안쪽에서 차오른다
local activeWarns = 0
local function groundWarn(event)
	if activeWarns >= 12 then return end
	local position, radius, duration, color = event[2], event[3], math.clamp(event[4] or 1.5, 0.3, 4), event[5] or Color3.fromRGB(235, 110, 90)
	activeWarns += 1
	local cframe = CFrame.new(position + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local base = Instance.new("Part")
	base.Anchored, base.CanCollide, base.CanQuery, base.CanTouch = true, false, false, false
	base.Shape, base.Material, base.Color, base.Transparency = CYLINDER, Enum.Material.Neon, color, 0.8
	base.Size = Vector3.new(0.2, radius * 2, radius * 2)
	base.CFrame = cframe
	base.Parent = fxFolder
	local fill = base:Clone()
	fill.Transparency = 0.5
	fill.Size = Vector3.new(0.25, 1, 1)
	fill.Parent = fxFolder
	TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.25, radius * 2, radius * 2), Transparency = 0.3 }):Play()
	Debris:AddItem(base, duration + 0.1)
	Debris:AddItem(fill, duration + 0.1)
	task.delay(duration + 0.1, function() activeWarns -= 1 end)
end

game:GetService("RunService").RenderStepped:Connect(function(dt)
	if #movers == 0 then return end
	local now = os.clock()
	for i = #movers, 1, -1 do
		local m = movers[i]
		local part = m.Part
		if m.Dead or not part.Parent or now > m.End then
			table.remove(movers, i)
		else
			local kind, t = m.Kind, now - m.T0
			local position, velocity
			if kind == "sine" then
				local phase = m.Freq * t
				position = m.Origin + m.Dir * (m.Speed * t) + m.Side * (m.Amp * math.sin(phase))
				velocity = m.Dir * m.Speed + m.Side * (m.Amp * m.Freq * math.cos(phase))
			elseif kind == "curve" then
				local w, d = m.W, m.Dir
				local k = m.Speed / w
				local s, c = math.sin(w * t), 1 - math.cos(w * t)
				position = Vector3.new(m.Origin.X + (d.X * s + d.Z * c) * k, m.Origin.Y + d.Y * m.Speed * t, m.Origin.Z + (d.Z * s - d.X * c) * k)
				local cs, sn = math.cos(w * t), math.sin(w * t)
				velocity = Vector3.new((d.X * cs + d.Z * sn) * m.Speed, d.Y * m.Speed, (d.Z * cs - d.X * sn) * m.Speed)
			elseif kind == "lob" then
				local u = math.min(t / m.Dur, 1)
				position = m.Origin:Lerp(m.Target, u) + Vector3.new(0, m.Height * 4 * u * (1 - u), 0)
				velocity = (m.Target - m.Origin) / m.Dur + Vector3.new(0, m.Height * 4 * (1 - 2 * u) / m.Dur, 0)
			else -- home
				local dir = m.Dir + (m.TargetDir - m.Dir) * math.min(1, dt * 8)
				if dir.Magnitude > 0.01 then m.Dir = dir.Unit end
				m.Pos += m.Dir * m.Speed * dt
				position, velocity = m.Pos, m.Dir
			end
			if velocity.Magnitude > 0.01 then
				part.CFrame = CFrame.lookAt(position, position + velocity) * m.Rel
			end
		end
	end
end)

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
local function gunSoundNow(event)
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
local function gunSound(event) -- 발사음 간격이 기계처럼 일정하지 않게 아주 조금씩 어긋난다 (다른 효과 처리를 막지 않게 따로 띄운다)
	task.delay(math.random() * 0.035, gunSoundNow, event)
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

local debrisFx -- 파편 (아래 "K" 사망 연출이 정해지면 채워진다)
local CYL = Enum.PartType.Cylinder

-- 점선 고리: 속이 빈 고리를 부품 몇 개로 흉내 낸다 (풀링). 퍼지는 파동 / 칼날 궤도 표시에 쓴다.
local dashPool = {}
local function makeDashes(n, color, thick, length, transparency)
	local list = table.create(n)
	for i = 1, n do
		local part = table.remove(dashPool)
		if not part then
			part = neonPart(Vector3.one, color, 0)
			part.CastShadow = false
		end
		part.Color, part.Size, part.Transparency = color, Vector3.new(thick, thick * 0.5, length), transparency or 0.2
		part.Parent = fxFolder
		list[i] = part
	end
	return list
end
local function releaseDashes(list)
	for _, part in ipairs(list) do
		part.Parent = nil
		if #dashPool < 160 then table.insert(dashPool, part) else part:Destroy() end
	end
end
local function placeDashes(list, center, radius, spin)
	local n = #list
	for i, part in ipairs(list) do
		local a = spin + i * (2 * math.pi / n)
		local c, s = math.cos(a), math.sin(a)
		local p = center + Vector3.new(c * radius, 0, s * radius)
		part.CFrame = CFrame.lookAt(p, p + Vector3.new(-s, 0, c))
	end
end

-- 퍼지는 파동: 가운데에서 바깥으로 퍼지며 옅어지는 점선 고리 (동시에 8개까지)
local waves = {}
local function ringWave(center, radius, color, dur, n, thick)
	if #waves >= 8 then return end
	n = n or math.clamp(math.floor(radius * 1.1), 14, 26)
	local length = math.max(1.6, 2 * math.pi * radius / n * 0.6)
	table.insert(waves, { List = makeDashes(n, color, thick or (0.9 + radius * 0.04), length), Center = center + Vector3.new(0, 0.5, 0), Radius = radius, Dur = dur or 0.5, T0 = os.clock() })
end

local activeRings = 0
local function ring(event) -- { "R", 위치, 반지름, 색 }
	if activeRings >= 36 then return end
	activeRings += 1
	task.delay(0.6, function() activeRings -= 1 end)
	local position, radius, color = event[2], event[3], event[4]
	local base = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local part = neonPart(Vector3.new(0.6, 2, 2), color, 0.3, CYL)
	part.CFrame = base
	part.Parent = fxFolder
	TweenService:Create(part, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.6, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(part, 0.6)
	if radius >= 8 then -- 큰 고리는 안쪽에 더 밝고 빠른 속 고리가 하나 더
		local core = neonPart(Vector3.new(0.5, 2, 2), color:Lerp(WHITE, 0.6), 0.35, CYL)
		core.CFrame = base
		core.Parent = fxFolder
		TweenService:Create(core, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.5, radius * 1.3, radius * 1.3), Transparency = 1 }):Play()
		Debris:AddItem(core, 0.35)
	end
end

-- 바닥에 남는 그을음 (어두운 원이 천천히 사라진다)
local function scorch(position, radius, seconds)
	local part = neonPart(Vector3.new(0.12, radius * 2, radius * 2), Color3.fromRGB(28, 20, 16), 0.4, CYL)
	part.Material = Enum.Material.SmoothPlastic
	part.CastShadow = false
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = fxFolder
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(part, seconds + 0.1)
end

local function bolt(event) -- { "Z", 위, 아래 }: 굵은 지그재그 번개 + 하얀 심지 + 바닥 그을음 / 고리 / 불꽃
	local top, bottom = event[2], event[3]
	local yellow = Color3.fromRGB(255, 240, 110)
	local points = { top }
	for i = 1, 2 do
		table.insert(points, top:Lerp(bottom, i / 3) + Vector3.new((math.random() - 0.5) * 10, 0, (math.random() - 0.5) * 10))
	end
	table.insert(points, bottom)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local part = neonPart(Vector3.new(2.6, 2.6, length), yellow, 0.05)
		part.CFrame = CFrame.lookAt((a + b) / 2, b)
		part.Parent = fxFolder
		TweenService:Create(part, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(0.4, 0.4, length) }):Play()
		Debris:AddItem(part, 0.45)
	end
	local length = (top - bottom).Magnitude
	local core = neonPart(Vector3.new(1, 1, length), Color3.fromRGB(255, 255, 240), 0)
	core.CFrame = CFrame.lookAt((top + bottom) / 2, bottom)
	core.Parent = fxFolder
	TweenService:Create(core, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(0.15, 0.15, length) }):Play()
	Debris:AddItem(core, 0.3)
	scorch(bottom, 5, 1.6)
	ring({ "R", bottom, 8, yellow })
	burst(bottom, yellow, 36)
	burst(bottom + Vector3.new(0, 1, 0), WHITE, 14)
end

local missiles = {}
local function missile(event) -- { "M", 출발, 대상 부품, 중간점, 시간 }: 빛나는 큰 미사일 + 불꽃 / 연기 꼬리
	local from, target, mid, duration = event[2], event[3], event[4], event[5]
	local ball = neonPart(Vector3.new(2.4, 2.4, 2.4), Color3.fromRGB(255, 190, 90), 0, Enum.PartType.Ball)
	ball.Position = from
	local function pair(half)
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, half, 0), Vector3.new(0, -half, 0)
		a0.Parent, a1.Parent = ball, ball
		return a0, a1
	end
	local a0, a1 = pair(0.9)
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.5
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 235, 140), Color3.fromRGB(255, 70, 30))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = 1
	trail.Parent = ball
	local s0, s1 = pair(1.5)
	local smoke = Instance.new("Trail")
	smoke.Attachment0, smoke.Attachment1 = s0, s1
	smoke.Lifetime = 0.9
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 140, 70), Color3.fromRGB(70, 70, 75))
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.WidthScale = NumberSequence.new(0.7, 1.5)
	smoke.LightEmission = 0.1
	smoke.Parent = ball
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(255, 150, 70), 12, 2
	light.Parent = ball
	ball.Parent = fxFolder
	table.insert(missiles, { Ball = ball, From = from, Target = target, Last = event[3] and event[3].Parent and event[3].Position or from, Mid = mid, Duration = duration, Started = os.clock() })
end

local function flame(event) -- { "L", 위치, 반지름, 초 }: 큰 불길 지대 + 안쪽 밝은 불씨 판 + 튀는 불똥
	local position, radius, seconds = event[2], event[3], event[4]
	local flat = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local pad = neonPart(Vector3.new(0.4, radius * 2, radius * 2), Color3.fromRGB(255, 95, 30), 0.5, CYL)
	pad.CFrame = flat
	local inner = neonPart(Vector3.new(0.5, radius * 1.2, radius * 1.2), Color3.fromRGB(255, 190, 70), 0.4, CYL)
	inner.CFrame = flat
	local fire = Instance.new("Fire")
	fire.Size = math.clamp(radius * 1.3, 8, 30)
	fire.Heat = 10
	fire.Parent = pad
	local embers = Instance.new("ParticleEmitter")
	embers.Rate = 16
	embers.Lifetime = NumberRange.new(1, 1.8)
	embers.Speed = NumberRange.new(6, 14)
	embers.SpreadAngle = Vector2.new(30, 30)
	embers.EmissionDirection = Enum.NormalId.Right -- (판을 눕혀 놓았으므로 로컬 오른쪽 = 위)
	embers.Acceleration = Vector3.new(0, 5, 0)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 110), Color3.fromRGB(255, 80, 30))
	embers.LightEmission = 1
	embers.Parent = inner
	pad.Parent, inner.Parent = fxFolder, fxFolder
	scorch(position, radius * 0.9, seconds + 1)
	task.delay(seconds, function()
		TweenService:Create(pad, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		TweenService:Create(inner, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		fire.Enabled = false
		embers.Enabled = false
		Debris:AddItem(pad, 1.6)
		Debris:AddItem(inner, 1.6)
	end)
end

local function meteor(event) -- { "E", 위치, 반지름, 낙하 시간 }: 큰 경고 원 + 차오르는 원 + 불꼬리 유성 -> 착탄 고리 / 구덩이 / 파편
	local position, radius, fall = event[2], event[3], event[4]
	local flat = CFrame.new(position + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local warnDisk = neonPart(Vector3.new(0.3, radius * 2, radius * 2), Color3.fromRGB(255, 70, 40), 0.65, CYL)
	warnDisk.CFrame = flat
	warnDisk.Parent = fxFolder
	local fill = neonPart(Vector3.new(0.35, 1, 1), Color3.fromRGB(255, 150, 70), 0.45, CYL)
	fill.CFrame = flat
	fill.Parent = fxFolder
	TweenService:Create(fill, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.35, radius * 2, radius * 2), Transparency = 0.25 }):Play()
	local rim = makeDashes(22, Color3.fromRGB(255, 120, 60), 1.2, 2 * math.pi * radius / 22 * 0.6, 0.1)
	placeDashes(rim, position + Vector3.new(0, 0.6, 0), radius, 0)
	local rock = neonPart(Vector3.new(10, 10, 10), Color3.fromRGB(255, 140, 50), 0, Enum.PartType.Ball)
	rock.Position = position + Vector3.new(18, 110, 14)
	local fire = Instance.new("Fire")
	fire.Size = 22
	fire.Parent = rock
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 5, 0), Vector3.new(0, -5, 0)
	a0.Parent, a1.Parent = rock, rock
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.8
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 60, 20))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.LightEmission = 1
	trail.Parent = rock
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(255, 150, 70), 28, 3
	light.Parent = rock
	rock.Parent = fxFolder
	TweenService:Create(rock, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = position + Vector3.new(0, 3, 0) }):Play()
	task.delay(fall, function()
		warnDisk:Destroy()
		fill:Destroy()
		rock:Destroy()
		releaseDashes(rim)
		local orange = Color3.fromRGB(255, 150, 60)
		ring({ "R", position, radius, orange })
		ringWave(position, radius * 1.1, Color3.fromRGB(255, 200, 110), 0.6, 24, 1.4)
		scorch(position, radius * 0.7, 3.5) -- 구덩이 자국
		burst(position + Vector3.new(0, 3, 0), orange, 100)
		burst(position + Vector3.new(0, 2, 0), WHITE, 30)
		if debrisFx then debrisFx({ "K", position + Vector3.new(0, 2, 0), Color3.fromRGB(110, 85, 65), 9 }) end
	end)
end

-- 회전 칼날: 칼날은 이 화면에서 서버 시각(GetServerTimeNow) 기준으로 돌아서, 서버가 계산한 피해 위치와 같은 곳에 보인다
local orbiters = {} -- [userId] = { Parts, Ring, Count, Radius, Spin, Expire }
local function killOrbiter(entry)
	for _, part in ipairs(entry.Parts) do part:Destroy() end
	if entry.Ring then releaseDashes(entry.Ring) end
end
local function orbit(event) -- { "O", userId, 개수(0이면 끔), 반지름, 속도 }
	local userId, count = event[2], event[3]
	local entry = orbiters[userId]
	if not count or count <= 0 then
		if entry then
			killOrbiter(entry)
			orbiters[userId] = nil
		end
		return
	end
	if entry and entry.Count ~= count then
		killOrbiter(entry)
		entry = nil
	end
	if not entry then
		entry = { Parts = {}, Count = count }
		entry.Ring = makeDashes(16, Color3.fromRGB(120, 235, 255), 0.5, 2 * math.pi * (event[4] or 9) / 16 * 0.5, 0.55) -- 칼날이 도는 반지름 표시
		for _ = 1, count do
			local blade = neonPart(Vector3.new(1, 0.5, 6.5), Color3.fromRGB(170, 248, 255), 0)
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Position, a1.Position = Vector3.new(0, 0, -3.2), Vector3.new(0, 0, 3.2)
			a0.Parent, a1.Parent = blade, blade
			local trail = Instance.new("Trail")
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.Lifetime = 0.45
			trail.Color = ColorSequence.new(Color3.fromRGB(200, 250, 255), Color3.fromRGB(60, 170, 255))
			trail.Transparency = NumberSequence.new(0.1, 1)
			trail.LightEmission = 1
			trail.Parent = blade
			local light = Instance.new("PointLight")
			light.Color, light.Range, light.Brightness = Color3.fromRGB(120, 235, 255), 9, 1.5
			light.Parent = blade
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
			local orange = Color3.fromRGB(255, 150, 60)
			burst(m.Last, orange, 36)
			burst(m.Last, WHITE, 10)
			ring({ "R", m.Last - Vector3.new(0, 1, 0), 7, orange })
			m.Ball:Destroy()
			table.remove(missiles, i)
		else
			m.Ball.Position = m.From:Lerp(m.Mid, t):Lerp(m.Mid:Lerp(m.Last, t), t) -- 2차 곡선
		end
	end
	-- 퍼지는 파동
	for i = #waves, 1, -1 do
		local w = waves[i]
		local t = (now - w.T0) / w.Dur
		if t >= 1 then
			releaseDashes(w.List)
			table.remove(waves, i)
		else
			placeDashes(w.List, w.Center, math.max(1, w.Radius * (1 - (1 - t) ^ 3)), 0)
			local transparency = 0.15 + 0.85 * t * t
			for _, part in ipairs(w.List) do part.Transparency = transparency end
		end
	end
	-- 회전 칼날
	local serverNow = workspace:GetServerTimeNow()
	for userId, entry in pairs(orbiters) do
		local owner = Players:GetPlayerByUserId(userId)
		local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		if now > entry.Expire or not root then
			killOrbiter(entry)
			orbiters[userId] = nil
		else
			for index, blade in ipairs(entry.Parts) do
				local angle = serverNow * entry.Spin + index * (2 * math.pi / entry.Count)
				local p = root.Position + Vector3.new(math.cos(angle) * entry.Radius, 0.5, math.sin(angle) * entry.Radius)
				blade.CFrame = CFrame.new(p, p + Vector3.new(-math.sin(angle), 0, math.cos(angle)))
			end
			placeDashes(entry.Ring, root.Position - Vector3.new(0, 2.4, 0), entry.Radius, serverNow * 0.5)
		end
	end
end)

local FLOAT_SIZE, DAMAGE_SIZE = UDim2.new(0, 140, 0, 36), UDim2.new(0, 90, 0, 40)
local HANDLERS = {
	S = playShot,
	P = spawnProjectile,
	X = function(event) removeProjectile(event[2], event[3]) end,
	Q = reaimProjectile, W = groundWarn,
	T = tracer,
	B = function(event) burst(event[2], event[3], event[4]) end,
	F = function(event) -- { "F", 위치, 글자, 색, (폭), (초) }: 폭이 있으면 배너처럼 크고 오래 뜬다
		local width = event[5]
		if width then
			width = math.clamp(width, 120, 420)
			showText(event[2], event[3], event[4], UDim2.new(0, width, 0, math.floor(width * 0.16)), math.clamp(event[6] or 1.4, 0.5, 3), 5)
		else
			showText(event[2], event[3], event[4], FLOAT_SIZE, 0.7, 3)
		end
	end,
	D = function(event) -- { "D", position, amount, isCrit }
		showText(event[2], event[4] and (tostring(event[3]) .. "!") or tostring(event[3]), event[4] and Color3.fromRGB(255, 220, 60) or WHITE, DAMAGE_SIZE, 0.5, nil)
	end,
	H = function(event) flash(event[2]) end,
	G = gunSound,
	R = ring, Z = bolt, M = missile, L = flame, E = meteor, O = orbit,
}

-- 한 배치(한 프레임)에서 종류별로 그릴 수 있는 최대 개수: 넘치는 것은 건너뛴다 (지우기 "X" / 끄기 "O" / 번쩍임 "H" 는 제한 없음)
local BATCH_LIMIT = { G = 10, T = 48, R = 16, Z = 8, M = 12, L = 8, E = 8, U = 6, N = 6, V = 8, K = 14, P = 100, Q = 40, W = 10, S = 100, B = 60 }
Remotes.Fx.OnClientEvent:Connect(function(batch)
	if typeof(batch) ~= "table" then return end
	local used = {}
	for _, event in ipairs(batch) do
		local kind = event[1]
		local handler = HANDLERS[kind]
		local limit = BATCH_LIMIT[kind]
		if limit then
			local n = (used[kind] or 0) + 1
			used[kind] = n
			if n > limit then handler = nil end
		end
		if handler then
			local ok, err = pcall(handler, event)
			if not ok and game:GetService("RunService"):IsStudio() then warn("[Fx] " .. tostring(err)) end
		end
	end
end)

------------------------------------------------------------
-- 몬스터 사망 연출 ("K"): 조각이 튀며 흩어지고 영혼 연기가 피어오른다. 조각은 풀링 + 동시 개수 상한.
------------------------------------------------------------
local MAX_SHARDS = 90
local shardPool, shards = {}, {}
-- 종류별 영혼 색 / 조각 모양 / 재질 (표에 없으면 몸 색 + 네모 조각)
local DEATH_LOOK = {
	Slime = { Soul = Color3.fromRGB(150, 255, 140), Round = true, Material = Enum.Material.Glass },
	Spitter = { Soul = Color3.fromRGB(210, 150, 255), Round = false, Material = Enum.Material.SmoothPlastic },
	Bat = { Soul = Color3.fromRGB(170, 130, 230), Round = false, Material = Enum.Material.SmoothPlastic },
	Mage = { Soul = Color3.fromRGB(170, 240, 255), Round = true, Material = Enum.Material.Neon },
	Golem = { Soul = Color3.fromRGB(255, 170, 90), Round = false, Material = Enum.Material.Slate, Heavy = true },
	Charger = { Soul = Color3.fromRGB(255, 160, 110), Round = false, Material = Enum.Material.Wood },
	Bomber = { Soul = Color3.fromRGB(255, 190, 90), Round = true, Material = Enum.Material.Metal },
	Imp = { Soul = Color3.fromRGB(255, 110, 140), Round = false, Material = Enum.Material.SmoothPlastic },
	Knight = { Soul = Color3.fromRGB(200, 220, 255), Round = false, Material = Enum.Material.Metal, Heavy = true },
	Turret = { Soul = Color3.fromRGB(180, 150, 255), Round = false, Material = Enum.Material.Metal },
	Spider = { Soul = Color3.fromRGB(255, 100, 100), Round = false, Material = Enum.Material.SmoothPlastic },
	Wisp = { Soul = Color3.fromRGB(150, 255, 220), Round = true, Material = Enum.Material.Neon },
	Healer = { Soul = Color3.fromRGB(170, 255, 200), Round = true, Material = Enum.Material.Neon },
	Totem = { Soul = Color3.fromRGB(255, 130, 110), Round = false, Material = Enum.Material.Wood, Heavy = true },
}

local function getShard()
	local part = table.remove(shardPool)
	if part then return part end
	part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.CastShadow = false
	return part
end

local function deathBurst(event) -- { "K", position, color, size, typeKey }
	local position, color, size = event[2], event[3], math.clamp(event[4] or 4, 1, 40)
	local look = DEATH_LOOK[event[5]] or {}
	color = typeof(color) == "Color3" and color or WHITE
	local soul = look.Soul or color:Lerp(WHITE, 0.5)
	local count = math.clamp(math.floor(5 + size * 1.2), 6, 16)
	for _ = 1, count do
		if #shards >= MAX_SHARDS then break end
		local part = getShard()
		local s = size * (0.1 + math.random() * 0.14)
		part.Shape = look.Round and Enum.PartType.Ball or Enum.PartType.Block
		part.Material = look.Material or Enum.Material.SmoothPlastic
		part.Color = color
		part.Transparency = 0
		part.Size = Vector3.new(s, s * (look.Round and 1 or 0.7), s)
		local spread = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * size * 0.4
		part.CFrame = CFrame.new(position + spread) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		part.Parent = fxFolder
		local speed = (look.Heavy and 9 or 15) + math.random() * 10
		local angle = math.random() * math.pi * 2
		table.insert(shards, {
			Part = part, Size = part.Size, Born = os.clock(), Life = 0.7 + math.random() * 0.4,
			Velocity = Vector3.new(math.cos(angle) * speed, 10 + math.random() * 12, math.sin(angle) * speed),
			Spin = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5),
			FloorY = position.Y - size * 0.45,
		})
	end
	-- 영혼 연기 (풀링된 입자 재사용)
	burst(position + Vector3.new(0, size * 0.3, 0), soul, math.clamp(math.floor(size * 3), 10, 40))
end

game:GetService("RunService").RenderStepped:Connect(function(dt)
	if #shards == 0 then return end
	local now = os.clock()
	for i = #shards, 1, -1 do
		local shard = shards[i]
		local age = now - shard.Born
		local part = shard.Part
		if age >= shard.Life then
			part.Parent = nil
			if #shardPool < 60 then table.insert(shardPool, part) else part:Destroy() end
			table.remove(shards, i)
		else
			local velocity = shard.Velocity - Vector3.new(0, 55 * dt, 0)
			local nextPosition = part.Position + velocity * dt
			if nextPosition.Y < shard.FloorY then -- 바닥에 닿으면 통통 튀고 속도가 줄어든다
				nextPosition = Vector3.new(nextPosition.X, shard.FloorY, nextPosition.Z)
				velocity = Vector3.new(velocity.X * 0.6, math.abs(velocity.Y) * 0.35, velocity.Z * 0.6)
			end
			shard.Velocity = velocity
			part.Size = shard.Size * math.max(0.15, 1 - age / shard.Life) -- 점점 작아지며 사라진다
			part.CFrame = CFrame.new(nextPosition) * (part.CFrame - part.Position) * CFrame.Angles(shard.Spin.X * dt, shard.Spin.Y * dt, shard.Spin.Z * dt)
		end
	end
end)

HANDLERS.K = deathBurst

------------------------------------------------------------
-- 처형 해골 "U" { 위치(머리 위), 몸 높이 } / 처치 폭발 "N" { 위치, 반지름, 색 } / 퍼지는 파동 "V" { 위치, 반지름, 색, 초 }
------------------------------------------------------------
debrisFx = deathBurst

local activeSkulls = 0
local function skull(event)
	if activeSkulls >= 8 or activeTexts >= MAX_ACTIVE_TEXTS then return end
	activeSkulls += 1
	activeTexts += 1
	local position = event[2]
	local center = position - Vector3.new(0, (event[3] or 4) / 2 + 1.5, 0)
	local entry = getText()
	local label = entry.Label
	entry.Gui.Size = UDim2.new(0, 40, 0, 40)
	label.Text = "💀"
	label.TextColor3 = Color3.fromRGB(225, 140, 255)
	label.TextTransparency, label.TextStrokeTransparency = 0, 0
	entry.Part.Position = position
	entry.Part.Parent = fxFolder
	TweenService:Create(entry.Gui, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 150, 0, 150) }):Play()
	TweenService:Create(entry.Part, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = position + Vector3.new(0, 9, 0) }):Play()
	task.delay(0.65, function() TweenService:Create(label, TweenInfo.new(0.45), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end)
	task.delay(1.15, function()
		activeSkulls -= 1
		activeTexts -= 1
		entry.Part.Parent = nil
		label.TextTransparency, label.TextStrokeTransparency = 0, 0
		if #textPool < 60 then table.insert(textPool, entry) else entry.Part:Destroy() end
	end)
	local purple = Color3.fromRGB(165, 70, 235)
	burst(position, purple, 45)
	burst(center, Color3.fromRGB(45, 12, 70), 22)
	ring({ "R", center, 8, purple })
	local camera = workspace.CurrentCamera
	if camera then -- 보라 베기 두 줄 (X 자)
		for i, tilt in ipairs({ 35, -35 }) do
			task.delay((i - 1) * 0.06, function()
				local slash = neonPart(Vector3.new(10, 0.35, 0.35), Color3.fromRGB(210, 120, 255), 0)
				slash.CFrame = CFrame.lookAt(center, camera.CFrame.Position) * CFrame.Angles(0, 0, math.rad(tilt))
				slash.Parent = fxFolder
				TweenService:Create(slash, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(16, 0.1, 0.1), Transparency = 1 }):Play()
				Debris:AddItem(slash, 0.25)
			end)
		end
	end
end

local function novaFx(event)
	local position, radius, color = event[2], event[3], event[4]
	local center = position + Vector3.new(0, 1.5, 0)
	ringWave(position, radius, color, 0.45, 18, 1.1)
	ring({ "R", position, radius * 0.8, color })
	local glow = neonPart(Vector3.new(2, 2, 2), color:Lerp(WHITE, 0.4), 0.5, Enum.PartType.Ball) -- 부드러운 빛구 (화면 번쩍임 없음)
	glow.CastShadow = false
	glow.Position = center
	glow.Parent = fxFolder
	TweenService:Create(glow, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 1.1, Transparency = 1 }):Play()
	Debris:AddItem(glow, 0.32)
	burst(center, color, 45)
	burst(center, color:Lerp(WHITE, 0.7), 18)
	deathBurst({ "K", center, color:Lerp(Color3.fromRGB(70, 50, 40), 0.5), 5 })
end

HANDLERS.U = skull
HANDLERS.N = novaFx
HANDLERS.V = function(event) ringWave(event[2], event[3], event[4], event[5] or 0.7, math.clamp(math.floor(event[3] * 1.3), 16, 30), 1.3) end
