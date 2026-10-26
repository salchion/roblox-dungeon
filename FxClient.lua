-- FxClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: FxClient)
-- 전투 시각 효과를 내 화면에서만 그린다: 총알 궤적 / 폭발 입자 / 피해 숫자 / 떠오르는 글자 / 적 탄 / 적중 번쩍임.
-- 서버는 "무엇이 어디서 일어났는지"만 한 덩어리(배치)로 보내고, 부품은 여기서 만들고 (풀링으로) 재사용한다.
--   -> 서버가 매 총알마다 부품 / 트레일 / 입자를 만들고 위치를 복제하던 부담이 사라진다.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
-- 동시 탄 수 세기: 탄 하나를 "정해진 시간 뒤 자동으로 빠지는" 방식으로 센다.
-- (예전에는 탄이 끝날 때 직접 1 을 뺐는데, 중간에 오류가 나거나 레일건처럼 두 번 더하는 경로가 있으면 숫자가 계속 쌓여서
--  상한(90)에 닿는 순간부터 내 탄이 전부 안 보이는 문제가 생겼다)
local function claimShot(seconds)
	activeShots += 1
	task.delay(seconds, function() activeShots = math.max(0, activeShots - 1) end)
end

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

local lootTicker
local DEFAULT_STROKE = 0
local function showText(position, text, color, size, lifetime, rise, transparency)
	if activeTexts >= MAX_ACTIVE_TEXTS then return end
	activeTexts += 1
	local entry = getText()
	entry.Gui.Size = size
	entry.Label.Text = text
	entry.Label.TextColor3 = color
	entry.Label.TextTransparency = transparency or 0 -- (획득 글자는 흐리게)
	entry.Label.TextStrokeTransparency = transparency and math.min(1, transparency + 0.3) or DEFAULT_STROKE
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
	Shotgun = { Style = "Ball", SizeMul = 0.55, Mini = true, Puff = true }, -- 샷건: 작은 산탄 알갱이 + 총구 원뿔 연기
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
	end)
	tween:Play()
end

-- 시대(원소)별 색: 무기 이름의 원소(녹슨 / 강철 / 마력 / 황금 / 불꽃 / 빙결 / 번개 / 암흑 / 용 / 신화)가 로켓 불꽃 / 화염방사 불덩이 / 저격 줄기 / 캐논 구 / 레일 빔에도 그대로 나타나게 한다.
-- (이전에는 로켓 / 화염방사기 / 저격총이 어느 시대든 주황 불꽃 / 흰 줄기라서 "빙결 미사일"도 불꽃을 뿜었다)
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local ELEMENT = {
	[1] = { Core = rgb(160, 135, 105), Flame = rgb(185, 140, 85), Tip = rgb(120, 100, 85), Smoke = rgb(140, 125, 110), Hot = rgb(215, 185, 140) },
	[2] = { Core = rgb(170, 205, 245), Flame = rgb(150, 195, 255), Tip = rgb(140, 170, 210), Smoke = rgb(200, 210, 225), Hot = rgb(235, 245, 255) },
	[3] = { Core = rgb(185, 125, 250), Flame = rgb(165, 95, 245), Tip = rgb(150, 100, 215), Smoke = rgb(160, 130, 210), Hot = rgb(230, 210, 255) },
	[4] = { Core = rgb(255, 210, 85), Flame = rgb(255, 195, 65), Tip = rgb(235, 175, 50), Smoke = rgb(225, 210, 165), Hot = rgb(255, 242, 190) },
	[5] = { Core = rgb(255, 140, 45), Flame = rgb(255, 110, 30), Tip = rgb(215, 60, 45), Smoke = rgb(190, 190, 195), Hot = rgb(255, 205, 100) },
	[6] = { Core = rgb(165, 230, 250), Flame = rgb(125, 205, 255), Tip = rgb(185, 235, 255), Smoke = rgb(215, 238, 248), Hot = rgb(238, 250, 255) },
	[7] = { Core = rgb(250, 238, 105), Flame = rgb(255, 230, 85), Tip = rgb(240, 225, 130), Smoke = rgb(225, 225, 195), Hot = rgb(255, 252, 225) },
	[8] = { Core = rgb(135, 80, 215), Flame = rgb(115, 60, 195), Tip = rgb(70, 35, 110), Smoke = rgb(80, 62, 110), Hot = rgb(185, 150, 250) },
	[9] = { Core = rgb(255, 100, 40), Flame = rgb(255, 125, 40), Tip = rgb(190, 40, 25), Smoke = rgb(120, 100, 95), Hot = rgb(255, 195, 80) },
	[10] = { Core = rgb(240, 240, 255), Flame = rgb(255, 200, 255), Tip = rgb(190, 215, 255), Smoke = rgb(220, 225, 245), Hot = rgb(255, 255, 255) },
}
local function elementOf(era) return ELEMENT[era] or ELEMENT[5] end

local SPECIAL = {}

-- 로켓: 몸통 + 빨간 머리 + 꼬리 날개 + 불꽃 분사 + 연기 꼬리, 닿으면 큰 폭발
SPECIAL.Rocket = function(from, to, size, speed, color, era)
	local s = math.clamp(size, 0.8, 2.0)
	local cf = CFrame.lookAt(from, to)
	local body = rootPart(cf, Vector3.new(s * 0.55, s * 0.55, s * 2.6), Color3.fromRGB(205, 208, 215), Enum.Material.Metal)
	local E = elementOf(era)
	solid(body, Vector3.new(s * 0.5, s * 0.5, s * 0.9), E.Tip, Enum.Material.Metal, CFrame.new(0, 0, -s * 1.6))
	solid(body, Vector3.new(s * 0.12, s * 1.3, s * 0.7), color, Enum.Material.Neon, CFrame.new(0, 0, s * 1.0))
	solid(body, Vector3.new(s * 1.3, s * 0.12, s * 0.7), color, Enum.Material.Neon, CFrame.new(0, 0, s * 1.0))
	local flame = solid(body, Vector3.new(s * 0.5, s * 0.5, s * 1.4), E.Hot, Enum.Material.Neon, CFrame.new(0, 0, s * 2.0), 0.15)
	local smoke = addEmitter(flame, E.Smoke, 55, s * 0.9, 0.7, 1.5, 1)
	smoke.LightEmission = 0.1
	addEmitter(flame, E.Flame, 40, s * 0.55, 0.25, 3)
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 9 + era, 1.0, E.Flame
	light.Parent = flame
	burst(from, E.Smoke, 6) -- 발사 연기
	fly(body, from, to, speed, 0.05, function()
		burst(to, E.Flame, 36)
		burst(to, color, 14)
		local blast = rootPart(CFrame.new(to), Vector3.new(2, 2, 2), E.Hot, Enum.Material.Neon, Enum.PartType.Ball, 0.3)
		TweenService:Create(blast, TweenInfo.new(0.3), { Size = Vector3.new(12, 12, 12), Transparency = 1 }):Play()
		Debris:AddItem(blast, 0.4)
		body:Destroy()
	end)
end





------------------------------------------------------------
-- 시대(era)별 탄 서명: 무기 종류 모양 위에 얹는다 (탄 하나당 추가 부품/입자 3개 이하, 기관단총/샷건은 1개)
------------------------------------------------------------
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local ERA_TINT = { -- 탄 색을 시대 느낌으로 덮어쓴다 (예전에는 연한 색이 많아 전부 흰 줄기처럼 보였다: 시대마다 확실히 다른 진한 색)
	[1] = Color3.fromRGB(190, 120, 60), [2] = Color3.fromRGB(70, 140, 255), [3] = Color3.fromRGB(170, 70, 255), [4] = Color3.fromRGB(255, 185, 30),
	[5] = Color3.fromRGB(255, 100, 25), [6] = Color3.fromRGB(40, 195, 255), [7] = Color3.fromRGB(255, 230, 40),
	[8] = Color3.fromRGB(135, 75, 220), [9] = Color3.fromRGB(255, 70, 30),
}
local ERA_CORE = { [8] = Color3.fromRGB(35, 15, 60) } -- 암흑: 몸통은 검보라, 꼬리 / 폭발은 보라 빛
local DRAGON = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 60)), ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 30, 15)) })
local ERA_TRAIL = { [5] = FIRE, [9] = DRAGON }

local function sigEmitter(part, colorSeq, rate, size, life, speed, accel, texture, emission)
	local e = Instance.new("ParticleEmitter")
	e.Rate = rate * 0.7
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(speed * 0.3, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = math.min(emission or 1, 0.6) -- (번쩍임 톤 다운)
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

-- 저사양 모드(설정 창)면 아래 "드라마틱" 추가 연출은 건너뛴다
local function lowSpecOn()
	return Players.LocalPlayer:GetAttribute("LowSpec") == true
end

-- 총구 연출: 시대마다 다른 모양 (모든 무기 종류에 붙는다). 같은 시대 안에서 번호가 오르면(inEra 0~1) 더 크다. 연사 무기(mini)는 작게 / 간격을 둔다
local lastMuzzle = 0
local function eraMuzzle(from, dir, era, color, inEra, mini)
	if era < 2 or lowSpecOn() then return end
	local now = os.clock()
	if now - lastMuzzle < (mini and 0.09 or 0.03) then return end
	lastMuzzle = now
	local E = elementOf(era)
	local power = mini and 0.5 or (1 + (inEra or 0.5))
	local front = from + dir * 1.2
	if era == 2 then
		burst(front, E.Hot, math.floor(4 * power)) -- 불꽃 틱
	elseif era == 3 then
		eraRing(front, E.Core, 0.5, 4 * power, 0.2, dir) -- 마법진 고리
		burst(front, E.Hot, math.floor(4 * power))
	elseif era == 4 then
		burst(front, E.Hot, math.floor(8 * power)) -- 금가루
	elseif era == 5 then
		burst(front, E.Flame, math.floor(8 * power)) -- 불꽃 + 연기
		burst(front, E.Smoke, 3)
	elseif era == 6 then
		burst(front, E.Hot, math.floor(7 * power)) -- 서리 입김 + 얼음 고리
		eraRing(front, E.Core, 0.5, 3.5 * power, 0.18, dir)
	elseif era == 7 then
		burst(front, WHITE, math.floor(6 * power)) -- 번쩍 스파크 + 얇은 충격 고리
		eraRing(front, E.Core, 0.4, 5 * power, 0.12, dir)
	elseif era == 8 then
		eraRing(front + dir * 3, E.Core, 6 * power, 0.8, 0.22, dir) -- 앞에서 총구로 빨려드는 고리
	elseif era == 9 then
		burst(front, E.Flame, math.floor(12 * power)) -- 불 내뿜기
		burst(front + dir * 2, E.Hot, 5)
	else
		burst(front, E.Hot, math.floor(8 * power)) -- 별 터짐
		eraRing(front, WHITE, 0.5, 5 * power, 0.2, dir)
	end
end

-- 번개 시대: 발사하는 순간 총구에서 맞는 곳까지 지그재그 번개가 번쩍 지나간다 (한 번에 부품 3~9개, 0.14초 뒤 사라진다)
local lastPath = 0
local function pathLightning(from, to, color, width, jitterSize)
	if lowSpecOn() then return end
	local now = os.clock()
	if now - lastPath < 0.06 then return end
	lastPath = now
	local total = to - from
	local distance = total.Magnitude
	if distance < 6 then return end
	local dir = total.Unit
	local right = dir:Cross(Vector3.new(0, 1, 0))
	if right.Magnitude < 0.1 then right = Vector3.new(1, 0, 0) end
	right = right.Unit
	local up = right:Cross(dir)
	local count = math.clamp(math.floor(distance / 12), 3, 9)
	local points = { from }
	for i = 1, count - 1 do
		local base = from + dir * (distance * i / count)
		local jitter = jitterSize or 2.2
		table.insert(points, base + right * (math.random() - 0.5) * 2 * jitter + up * (math.random() - 0.5) * 2 * jitter)
	end
	table.insert(points, to)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		if len > 0.2 then
			local bolt = rootPart(CFrame.lookAt((a + b) / 2, b), Vector3.new(width, width, len), color, Enum.Material.Neon, nil, 0.1)
			TweenService:Create(bolt, TweenInfo.new(0.14), { Transparency = 1, Size = Vector3.new(width * 0.3, width * 0.3, len) }):Play()
			Debris:AddItem(bolt, 0.18)
		end
	end
end

-- 무기 종류마다 눈에 확 띄게 다른 "발사 연출" (쨍하지 않게: 색은 회색 쪽으로 가라앉히고 고리 / 줄은 반투명, 한 번에 부품 몇 개만, 종류마다 간격을 둔다)
--   권총: 작은 팝 고리 / 리볼버: 묵직한 충격 고리 + 먼지 / SMG: 아주 얇은 줄 하나 / 소총: 길고 가는 궤적이 잠깐 남는다 /
--   샷건: 부채꼴 줄 + 연기 / 저격: 지나가는 길을 따라 퍼지는 고리 여러 개(증기) / 레일건: 크고 느슨한 고리 물결 / 로켓: 뒤로 뿜는 연기 /
--   캐논: 총구로 빨려드는 충전 고리 / 화염방사기: 불씨 부채꼴
local lastFlourish = {}
local FLOURISH_GAP = { Pistol = 0.06, Revolver = 0.05, Smg = 0.09, Rifle = 0.09, Shotgun = 0.05, Sniper = 0.05, Rocket = 0.05, Rail = 0.05, Cannon = 0.05, Flamer = 0.12 }
local function soft(color) return color:Lerp(Color3.fromRGB(135, 140, 150), 0.3) end

local function ringAt(position, dir, color, d0, d1, dur, transparency, delay)
	local cf = CFrame.lookAt(position, position + dir) * CFrame.Angles(0, math.rad(90), 0)
	local make = function()
		local ring = rootPart(cf, Vector3.new(0.15, d0, d0), color, Enum.Material.Neon, Enum.PartType.Cylinder, transparency)
		TweenService:Create(ring, TweenInfo.new(dur), { Size = Vector3.new(0.15, d1, d1), Transparency = 1 }):Play()
		Debris:AddItem(ring, dur + 0.05)
	end
	if delay and delay > 0 then task.delay(delay, make) else make() end
end

local function fanLines(front, dir, color, count, spreadDeg, len, dur)
	local up = Vector3.new(0, 1, 0)
	for i = 1, count do
		local t = count == 1 and 0 or (i - 1) / (count - 1) - 0.5
		local rotated = (CFrame.fromAxisAngle(up, math.rad(spreadDeg * t)) * CFrame.new(dir * 10)).Position.Unit
		local line = rootPart(CFrame.lookAt(front, front + rotated) * CFrame.new(0, 0, -len / 2), Vector3.new(0.16, 0.16, len), color, Enum.Material.Neon, nil, 0.35)
		TweenService:Create(line, TweenInfo.new(dur), { Transparency = 1, Size = Vector3.new(0.05, 0.05, len * 1.6) }):Play()
		Debris:AddItem(line, dur + 0.05)
	end
end

local function classFlourish(class, from, to, size, color, era, richness)
	if lowSpecOn() or not class then return end
	local gap = FLOURISH_GAP[class]
	if not gap then return end
	local now = os.clock()
	if now - (lastFlourish[class] or 0) < gap then return end
	lastFlourish[class] = now
	local total = to - from
	local distance = total.Magnitude
	if distance < 2 then return end
	local dir = total.Unit
	local front = from + dir * 1.4
	local tone = soft(elementOf(era).Core)
	local smokeColor = Color3.fromRGB(150, 150, 158)
	local grow = 1 + richness -- 번호가 높을수록 조금 더 크다

	if class == "Pistol" then -- 저격총 모양 라이플: 궤적을 따라 퍼지는 고리들
		local count = math.clamp(math.floor(distance / 40), 3, 7)
		for i = 1, count do
			ringAt(from + dir * (distance * i / (count + 1)), dir, tone, 0.8, 4 + 3 * richness, 0.4, 0.7, i * 0.02)
		end
		ringAt(front, dir, tone, 1, 7 * grow, 0.2, 0.45)
	elseif class == "Revolver" then -- 폭탄: 던지는 연기 한 번
		burst(front, smokeColor, 4)
	elseif class == "Rifle" then -- 활: 시위가 튕기는 작은 고리
		ringAt(front, dir, tone, 0.4, 1.8 * grow, 0.1, 0.6)
	elseif class == "Shotgun" then
		fanLines(front, dir, tone, 5, 34, 7 * grow, 0.12)
		burst(front + dir * 1.5, smokeColor, 6)
	elseif class == "Sniper" then -- 석궁: 묵직한 한 번의 고리
		ringAt(front, dir, tone, 0.8, 5 * grow, 0.18, 0.5)
	elseif class == "Rail" then
		local count = math.clamp(math.floor(distance / 55), 3, 6)
		for i = 1, count do
			ringAt(from + dir * (distance * i / (count + 1)), dir, tone, 1.2, 9 + 4 * richness, 0.35, 0.6, i * 0.03)
		end
	elseif class == "Rocket" then
		burst(from - dir * 2.5, smokeColor, 10) -- 뒤로 뿜는 연기
		ringAt(front, dir, smokeColor, 1.5, 7 * grow, 0.3, 0.6)
	elseif class == "Cannon" then -- 박격포: 포구에서 뿜는 연기 + 고리
		burst(from, smokeColor, 10)
		ringAt(front, dir, smokeColor, 1.2, 6 * grow, 0.26, 0.55)
	elseif class == "Flamer" then
		fanLines(front, dir, soft(elementOf(era).Flame), 4, 40, 5 * grow, 0.14)
		burst(front + dir * 2, elementOf(era).Smoke, 3)
	end
end

-- c = { size, back(머리에서 꼬리쪽 거리), color, mini, inEra(같은 시대 안 번호 0~1), low(저사양) }. 돌려주는 함수는 탄이 끝날 때 부른다 (반복 트윈 정리)
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
ERA_SIG[4] = function(part, c) -- 황금: 금빛 혜성 + 빙글 도는 4갈래 금별 날 (번호가 오를수록 커진다) + 반짝이
	if not c.mini then
		local len = c.size * 2.6
		solid(part, Vector3.new(c.size * 0.55, c.size * 0.55, len), Color3.fromRGB(255, 225, 120), Enum.Material.Neon, CFrame.new(0, 0, c.back + len * 0.5), 0.45)
		if not c.low then
			local blade = c.size * (1.6 + (c.inEra or 0.5)) + 0.5
			for _, rot in ipairs({ 45, 135 }) do
				solid(part, Vector3.new(blade, 0.12, 0.5), Color3.fromRGB(255, 232, 140), Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(rot)), 0.1)
			end
			c.roll = math.rad(170) -- 날아가는 동안 반 바퀴 돈다 (트윈은 180 도를 넘는 회전을 짧은 쪽으로 돌려서 170 도로 둔다)
		end
	end
	sigEmitter(part, ColorSequence.new(Color3.fromRGB(255, 240, 150)), c.mini and 16 or 30, math.max(c.size * 0.45, 0.3), 0.6, 2.5, nil, SPARKLE)
end
ERA_SIG[5] = function(part, c) -- 불꽃: 불꽃 물방울 + 일렁이는 불길 (길이가 출렁인다) + 위로 오르는 불씨
	local flicker
	if not c.mini then
		local len = c.size * 2.4
		solid(part, Vector3.new(c.size * 0.55, c.size * 0.55, len), Color3.fromRGB(255, 90, 25), Enum.Material.Neon, CFrame.new(0, 0, c.back + len * 0.5), 0.3)
		if not c.low then
			local flameLen = c.size * (3 + 2 * (c.inEra or 0.5))
			local flame = solid(part, Vector3.new(c.size * 0.9, c.size * 0.9, flameLen), Color3.fromRGB(255, 170, 60), Enum.Material.Neon, CFrame.new(0, 0, c.back + flameLen * 0.5), 0.55)
			flicker = TweenService:Create(flame, TweenInfo.new(0.07, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), { Size = Vector3.new(c.size * 0.5, c.size * 0.5, flameLen * 1.3), Transparency = 0.75 })
			flicker:Play()
		end
	end
	sigEmitter(part, FIRE, c.mini and 16 or 30, math.max(c.size * 0.35, 0.28), 0.6, 3, Vector3.new(0, 6, 0))
	if flicker then return function() flicker:Cancel() end end
end
ERA_SIG[6] = function(part, c) -- 빙결: 결정 + 바깥으로 뻗은 얼음 가시 세 개 (천천히 돈다) + 눈송이 안개
	if not c.mini then
		local s = c.size * 0.9
		solid(part, Vector3.new(s, s, s), Color3.fromRGB(215, 245, 255), Enum.Material.Neon, CFrame.Angles(math.rad(45), math.rad(45), 0), 0.15)
		if not c.low then
			local r = c.size * 0.9 + 0.5
			local len = c.size * (1.4 + (c.inEra or 0.5)) + 0.6
			for i = 0, 2 do
				local a = math.rad(i * 120)
				solid(part, Vector3.new(0.22, 0.22, len), Color3.fromRGB(215, 245, 255), Enum.Material.Neon,
					CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(math.sin(a) * 0.35, -math.cos(a) * 0.35, 0), 0.1)
			end
			c.roll = math.rad(170)
		end
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
ERA_SIG[8] = function(part, c) -- 암흑: 검보라 구 + 몸을 감싼 어두운 고리 + 주변에서 빨려 들어오는 보랏빛 입자 + 연기 꼬리
	if not c.mini then
		local s = c.size * 1.7
		solid(part, Vector3.new(s, s, s), c.color, Enum.Material.Neon, CFrame.identity, 0.55, Enum.PartType.Ball)
		if not c.low then
			local d = c.size * 2.6 + 0.8
			solid(part, Vector3.new(0.15, d, d), Color3.fromRGB(110, 55, 190), Enum.Material.Neon, CFrame.Angles(0, math.rad(90), 0), 0.5, Enum.PartType.Cylinder)
		end
	end
	if not c.low then
		local pull = Instance.new("ParticleEmitter") -- 바깥에서 가운데로 빨려드는 입자 (지원하지 않는 환경이면 그냥 퍼지는 입자가 된다)
		pull.Rate = c.mini and 10 or 30
		pull.Lifetime = NumberRange.new(0.25, 0.45)
		pull.Speed = NumberRange.new(4, 8)
		pull.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.max(c.size * 0.5, 0.3)), NumberSequenceKeypoint.new(1, 0) })
		pull.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		pull.Color = ColorSequence.new(Color3.fromRGB(150, 80, 240))
		pull.LightEmission = 0.4
		pcall(function()
			pull.Shape = Enum.ParticleEmitterShape.Sphere
			pull.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
			pull.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		end)
		pull.Parent = part
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

------------------------------------------------------------
-- 무기 종류별 전용 탄 (활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서). 로켓은 위쪽 SPECIAL.Rocket.
-- 종류 이름(Rifle 등)은 저장 / 설정에 쓰이는 옛 이름 그대로이고, 화면에 보이는 이름은 Config.WeaponTypes 의 Name 이다:
--   Pistol=라이플 · Smg=저격총 · Rifle=활 · Sniper=석궁 · Shotgun=수리검 · Revolver=폭탄 · Cannon=박격포 · Rail=지팡이 · Flamer=마도서
-- 탄 색은 시대 색(ERA_TINT)을 그대로 써서 흰 줄기처럼 보이지 않게 한다.
------------------------------------------------------------
local function tintOf(color, era) return ERA_TINT[era] or color end

local function addTrail(part, color, width, life)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = life
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = 0.5
	trail.FaceCamera = true
	trail.Parent = part
	return trail
end

-- 곡선으로 날아가는 탄: height 만큼 솟았다 내려온다 (피해는 서버가 이미 계산했고, 이건 보이는 연출뿐이다). spin = 비행 방향 축 회전(라디안/초)
local function arcFly(part, from, to, speed, height, spin, onDone, minTime)
	local duration = math.clamp((to - from).Magnitude / math.max(speed, 1), minTime or 0.05, 1.2)
	local startAt = os.clock()
	local up = Vector3.new(0, 1, 0)
	local last = from
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not part.Parent then connection:Disconnect() return end
		local alpha = math.min((os.clock() - startAt) / duration, 1)
		local position = from:Lerp(to, alpha) + up * (height * 4 * alpha * (1 - alpha))
		local heading = position - last
		if heading.Magnitude > 0.01 then
			part.CFrame = CFrame.lookAt(position, position + heading) * CFrame.Angles(0, 0, spin * (os.clock() - startAt))
		else
			part.Position = position
		end
		last = position
		if alpha >= 1 then
			connection:Disconnect()
			onDone()
		end
	end)
end

-- 저격총 모양 라이플 (Pistol = 저격총 외형): 아주 빠른 줄기 + 지나간 자리에 남는 가는 궤적선
SPECIAL.Pistol = function(from, to, size, speed, color, era)
	local E = elementOf(era)
	color = E.Core
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt(from, to)
	local slugWidth, lineWidth = math.max(0.7, size * 0.6), math.max(0.4, size * 0.3)
	local slug = rootPart(cf, Vector3.new(slugWidth, slugWidth, 12), E.Hot, Enum.Material.Neon)
	local line = rootPart(CFrame.lookAt((from + to) / 2, to), Vector3.new(lineWidth, lineWidth, length), color, Enum.Material.Neon, nil, 0.3)
	TweenService:Create(line, TweenInfo.new(0.4), { Size = Vector3.new(0.03, 0.03, length), Transparency = 1 }):Play()
	Debris:AddItem(line, 0.45)
	burst(from, color, 3)
	fly(slug, from, to, math.max(speed, 700), 0.03, function()
		burst(to, color, 10)
		slug:Destroy()
	end)
end

-- 활: 나무 화살대 + 빛나는 화살촉 + 깃털, 살짝 호를 그리며 날아가 박힌다
SPECIAL.Rifle = function(from, to, size, speed, color, era)
	local tint = tintOf(color, era)
	local s = math.clamp(size, 0.5, 1.1)
	local arrow = rootPart(CFrame.lookAt(from, to), Vector3.new(s * 0.22, s * 0.22, 5.2), Color3.fromRGB(150, 112, 72), Enum.Material.Wood)
	solid(arrow, Vector3.new(s * 0.5, s * 0.5, 1.0), tint, Enum.Material.Neon, CFrame.new(0, 0, -2.9))
	if not lowSpecOn() then
		for i = 0, 1 do
			solid(arrow, Vector3.new(0.06, s * 0.95, 1.1), tint:Lerp(WHITE, 0.35), Enum.Material.Neon, CFrame.new(0, 0, 2.2) * CFrame.Angles(0, 0, math.rad(i * 90)), 0.1)
		end
		addTrail(arrow, tint, s * 0.6, 0.18)
	end
	arcFly(arrow, from, to, math.max(speed, 260), math.min(6, (to - from).Magnitude * 0.04), 0, function()
		burst(to, tint, 8)
		Debris:AddItem(arrow, 0.3) -- 맞은 자리에 잠깐 꽂혀 있다 사라진다
	end)
end

-- 석궁: 짧고 굵은 철제 볼트 + 빛나는 촉, 아주 빠르게 곧장 날아가 "쿵"
SPECIAL.Sniper = function(from, to, size, speed, color, era)
	local tint = tintOf(color, era)
	local s = math.clamp(size, 0.6, 1.5)
	local bolt = rootPart(CFrame.lookAt(from, to), Vector3.new(s * 0.34, s * 0.34, 3.4), Color3.fromRGB(70, 74, 88), Enum.Material.Metal)
	solid(bolt, Vector3.new(s * 0.5, s * 0.5, 0.9), tint, Enum.Material.Neon, CFrame.new(0, 0, -2.1))
	addTrail(bolt, tint, s * 0.9, 0.22)
	local length = (to - from).Magnitude
	local line = rootPart(CFrame.lookAt((from + to) / 2, to), Vector3.new(s * 0.2, s * 0.2, length), tint, Enum.Material.Neon, nil, 0.45)
	TweenService:Create(line, TweenInfo.new(0.3), { Size = Vector3.new(0.03, 0.03, length), Transparency = 1 }):Play()
	Debris:AddItem(line, 0.35)
	fly(bolt, from, to, math.max(speed, 620), 0.03, function()
		burst(to, tint, 12)
		eraRing(to, tint, 1, 5, 0.18)
		bolt:Destroy()
	end)
end

-- 수리검: 앞을 보고 빙글빙글 도는 네 갈래 별 (부채꼴로 여러 장)
SPECIAL.Shotgun = function(from, to, size, speed, color, era)
	local tint = tintOf(color, era)
	local s = math.clamp(size * 1.7, 1.0, 1.9)
	local star = rootPart(CFrame.lookAt(from, to), Vector3.new(s, s * 0.3, 0.12), Color3.fromRGB(205, 210, 222), Enum.Material.Metal)
	if not lowSpecOn() then
		solid(star, Vector3.new(s * 0.3, s, 0.12), Color3.fromRGB(205, 210, 222), Enum.Material.Metal, CFrame.identity)
		addTrail(star, tint, s * 0.5, 0.12)
	end
	solid(star, Vector3.new(s * 0.34, s * 0.34, 0.2), tint, Enum.Material.Neon, CFrame.identity, 0, Enum.PartType.Ball)
	arcFly(star, from, to, math.max(speed, 150), 0, 32, function()
		burst(to, tint, 4)
		star:Destroy()
	end, 0.04)
end

-- 폭탄: 퓨즈가 타는 쇠공을 포물선으로 던진다. 떨어지면 불꽃과 충격 고리
SPECIAL.Revolver = function(from, to, size, speed, color, era)
	local tint = tintOf(color, era)
	local E = elementOf(era)
	local s = math.clamp(size * 1.2, 1.1, 2.6)
	local bomb = rootPart(CFrame.lookAt(from, to), Vector3.new(s, s, s), Color3.fromRGB(46, 48, 60), Enum.Material.Metal, Enum.PartType.Ball)
	solid(bomb, Vector3.new(s * 1.04, s * 0.22, s * 1.04), tint, Enum.Material.Neon, CFrame.identity, 0.1, Enum.PartType.Cylinder)
	local fuse = solid(bomb, Vector3.new(0.2, 0.2, 0.2), Color3.fromRGB(255, 190, 80), Enum.Material.Neon, CFrame.new(0, s * 0.58, 0), 0, Enum.PartType.Ball)
	if not lowSpecOn() then addEmitter(fuse, Color3.fromRGB(255, 170, 70), 40, 0.35, 0.3, 4) end
	local distance = (to - from).Magnitude
	arcFly(bomb, from, to, math.max(speed * 0.5, 90), math.clamp(distance * 0.2, 4, 22), 7, function()
		burst(to, tint, 26)
		burst(to, E.Flame, 10)
		local blast = rootPart(CFrame.new(to), Vector3.new(2, 2, 2), tint, Enum.Material.Neon, Enum.PartType.Ball, 0.35)
		TweenService:Create(blast, TweenInfo.new(0.28), { Size = Vector3.new(11, 11, 11), Transparency = 1 }):Play()
		Debris:AddItem(blast, 0.35)
		eraRing(to, tint, 1, 11, 0.3)
		bomb:Destroy()
	end, 0.1)
end

-- 박격포: 큰 포탄이 높이 솟았다가 내리꽂힌다. 연기 꼬리, 떨어지면 먼지와 큰 충격 고리
SPECIAL.Cannon = function(from, to, size, speed, color, era)
	local tint = tintOf(color, era)
	local s = math.clamp(size, 1.2, 3.2)
	local shell = rootPart(CFrame.lookAt(from, to), Vector3.new(s * 0.9, s * 0.9, s * 2.0), Color3.fromRGB(64, 66, 78), Enum.Material.Metal)
	solid(shell, Vector3.new(s * 0.9, s * 0.9, s * 0.9), tint, Enum.Material.Neon, CFrame.new(0, 0, -s * 1.15), 0.1, Enum.PartType.Ball)
	solid(shell, Vector3.new(s * 0.98, s * 0.98, s * 0.25), tint, Enum.Material.Neon, CFrame.new(0, 0, s * 0.4), 0.2)
	if not lowSpecOn() then
		local smoke = addEmitter(shell, Color3.fromRGB(180, 180, 188), 40, s * 0.8, 0.7, 1.5, 1)
		smoke.Texture = SMOKE
		smoke.LightEmission = 0.05
	end
	burst(from, Color3.fromRGB(150, 150, 158), 8)
	local distance = (to - from).Magnitude
	arcFly(shell, from, to, math.max(speed * 0.6, 80), math.clamp(distance * 0.45, 10, 50), 0, function()
		burst(to, tint, 28)
		burst(to, Color3.fromRGB(150, 140, 125), 12)
		local blast = rootPart(CFrame.new(to), Vector3.new(s, s, s), tint, Enum.Material.Neon, Enum.PartType.Ball, 0.35)
		TweenService:Create(blast, TweenInfo.new(0.3), { Size = Vector3.new(s * 5, s * 5, s * 5), Transparency = 1 }):Play()
		Debris:AddItem(blast, 0.35)
		eraRing(to, tint, 1, 4 + s * 3, 0.3)
		shell:Destroy()
	end, 0.15)
end


-- 레일건: 순식간에 지나가는 얇은 빔 (남았다가 사라진다) + 도착점 충격 고리
SPECIAL.Rail = function(from, to, size, _, color, era)
	local E = elementOf(era)
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, to)
	local coreWidth, auraWidth = math.max(0.8, size * 0.8), math.max(2.6, size * 2.6) -- (예전엔 가늘어서 거의 안 보였다)
	local core = rootPart(cf, Vector3.new(coreWidth, coreWidth, length), E.Hot, Enum.Material.Neon)
	local aura = rootPart(cf, Vector3.new(auraWidth, auraWidth, length), E.Core, Enum.Material.Neon, nil, 0.5)
	TweenService:Create(core, TweenInfo.new(0.34), { Size = Vector3.new(0.1, 0.1, length), Transparency = 1 }):Play()
	TweenService:Create(aura, TweenInfo.new(0.45), { Size = Vector3.new(0.3, 0.3, length), Transparency = 1 }):Play()
	Debris:AddItem(core, 0.4)
	Debris:AddItem(aura, 0.45)
	burst(from, color, 5)
	burst(to, color, 12)
	local ringPart = rootPart(CFrame.new(to) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.2, 1, 1), color, Enum.Material.Neon, Enum.PartType.Cylinder, 0.2)
	TweenService:Create(ringPart, TweenInfo.new(0.25), { Size = Vector3.new(0.2, 9, 9), Transparency = 1 }):Play()
	Debris:AddItem(ringPart, 0.3)
end

-- 마법책 (Flamer = 마법책): 이글거리는 화염구 한 발. 날아가며 불씨와 연기를 흘리고, 닿으면 작은 폭발 (시대 색)
SPECIAL.Flamer = function(from, to, size, speed, color, era)
	local tint = tintOf(color, era)
	local E = elementOf(era)
	local s = math.clamp(size * 1.3, 1.4, 3.2)
	local ball = rootPart(CFrame.lookAt(from, to), Vector3.new(s, s, s), tint:Lerp(WHITE, 0.25), Enum.Material.Neon, Enum.PartType.Ball)
	solid(ball, Vector3.new(s * 1.9, s * 1.9, s * 1.9), tint, Enum.Material.Neon, CFrame.identity, 0.55, Enum.PartType.Ball) -- 불꽃 겉껍질
	if not lowSpecOn() then
		addEmitter(ball, tint, 70, s * 0.9, 0.5, 4)
		local embers = addEmitter(ball, E.Hot, 22, s * 0.35, 0.7, 6)
		embers.Texture = SPARKLE
		local smoke = addEmitter(ball, Color3.fromRGB(80, 70, 75), 24, s * 0.8, 0.8, 1.5, 1)
		smoke.Texture = SMOKE
		smoke.LightEmission = 0
	end
	addTrail(ball, tint, s * 1.2, 0.25)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = tint, 11, 1.4
	light.Parent = ball
	burst(from, tint, 8) -- 책 앞에서 불꽃이 피어난다
	TweenService:Create(ball, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(s * 1.15, s * 1.15, s * 1.15) }):Play() -- 커지며 튀어나간다
	fly(ball, from, to, math.max(speed, 150), 0.06, function()
		burst(to, tint, 30)
		burst(to, E.Hot, 10)
		local blast = rootPart(CFrame.new(to), Vector3.new(s, s, s), tint, Enum.Material.Neon, Enum.PartType.Ball, 0.35)
		TweenService:Create(blast, TweenInfo.new(0.28), { Size = Vector3.new(s * 5, s * 5, s * 5), Transparency = 1 }):Play()
		Debris:AddItem(blast, 0.35)
		eraRing(to, tint, 1, 4 + s * 3, 0.26)
		ball:Destroy()
	end)
end

-- event = { "S", from, to, size, speed, impact, style, length, color, rainbow, class, era }
-- 내 캐릭터에서 나가는 투사체는 "지금 내 화면의 총구"에서 출발하게 한다.
-- (서버가 보낸 출발점은 통신 지연만큼 예전 위치라, 움직이며 쏘면 탄 / 미사일이 내 몸 뒤쪽 허공에서 나가는 것처럼 보였다)
local function snapToMe(pos, maxDistance, body)
	if typeof(pos) ~= "Vector3" then return pos end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (pos - root.Position).Magnitude > (maxDistance or 12) then return pos end
	if body then -- 세트 효과 / 스킬 투사체: 총구가 아니라 등 뒤 어깨 위에서 솟아오른다 (몸에서 뿜어져 나가는 느낌)
		return (root.CFrame * CFrame.new(0, 3.2, 1.2)).Position
	end
	local tool = character:FindFirstChild("Weapon")
	local barrel = tool and tool:FindFirstChild("Barrel")
	local tip = barrel and barrel:FindFirstChild("Tip")
	if tip and tip:IsA("Attachment") then return tip.WorldPosition end
	return root.Position + Vector3.new(0, 3, 0)
end

local function playShot(event)
	if activeShots >= MAX_ACTIVE_SHOTS then return end
	local from, to = snapToMe(event[2], 10), event[3]
	local size, speed, impact, eraStyle, length = event[4], event[5], event[6], event[7], event[8]
	local color, rainbow, class, era = event[9], event[10], event[11], event[12] or 1
	local vt = event[13] or 1 -- 무기 진행도 (1 ~ 100): 높을수록 탄이 꾸준히 더 화려해진다 (후광 / 꼬리 / 착탄 고리)
	local richness = math.clamp(vt / 100, 0, 1)
	local inEra = ((math.floor(vt) - 1) % 10) / 9 -- 같은 시대 안에서 몇 번째 무기인가 (0 ~ 1): 번호가 오르면 시대 연출이 더 커진다
	if Players.LocalPlayer:GetAttribute("InDoomArena") then color = color:Lerp(WHITE, 0.6) end -- 최후의 군주 결투장: 바닥이 붉어도 내 탄이 또렷하게
	local distance = (to - from).Magnitude
	if distance < 0.5 then return end
	local style = eraStyle
	local special = class and SPECIAL[class]
	if special then
		claimShot(1.4) -- (가장 긴 비행 1.2초 + 여유: 시간이 지나면 저절로 빠진다)
		if class ~= "Flamer" then eraMuzzle(from, (to - from).Unit, era, color, inEra, false) end -- (총구 섬광은 총 종류만: 마법책은 총처럼 번쩍이지 않는다)
		classFlourish(class, from, to, size, color, era, richness)
		if era == 7 and (class == "Rail" or class == "Sniper") then pathLightning(from, to, Color3.fromRGB(255, 245, 140), 0.28, 3) end
		special(from, to, size, speed, color, era)
		if vt >= 6 then -- 로켓 / 레일건 / 저격 / 캐논 / 화염방사도 번호가 오를수록 착탄 고리가 커진다
			task.delay(math.clamp(distance / speed, 0.03, 1.2), function()
				eraRing(to, color, 1, 3 + 6 * richness, 0.18 + 0.1 * richness)
			end)
		end
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
	if not rainbow then color = color:Lerp(Color3.fromRGB(120, 125, 135), 0.08) end -- 너무 쨍하지 않게 아주 살짝만 가라앉힌다
	if mini then size *= 1 + 0.7 * richness end -- 연사 무기도 번호가 오르면 탄이 굵고 밝아진다 (앞 무기보다 초라해지지 않게)
	size = math.max(size, mini and 0.45 or 0.5) -- 뒤에서 봐도 보이게 바닥 굵기 (연사 / 산탄 탄이 너무 가늘어 안 보인다는 말이 있어 키웠다)
	claimShot(1.4)

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
	local trailWidth = size * (1 + 0.12 * era) * (1 + 0.5 * richness)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, trailWidth / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -trailWidth / 2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = math.min(0.65, (style == "Ball" and 0.08 or 0.14) + 0.03 * era + 0.12 * richness)
	trail.Color = colorSeq
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Parent = part

	local sig = ERA_SIG[era]
	local sigCleanup, roll
	if sig then
		local isBolt = style == "Bolt" or style == "Rocket"
		local ctx = { size = size, back = (isBolt and (length or 3) or size) / 2, color = color, mini = mini, inEra = inEra, low = lowSpecOn() }
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
	-- 탄의 몸체: 번호가 오를수록 탄 자체의 "생김새"가 복잡해진다 (번쩍임이 아니라 구조: 뾰족한 촉 -> 꼬리 날개 -> 테두리 -> 띠 -> 가시 관). 빛나지 않는 금속 재질이라 눈이 편하다.
	-- 연사 무기(mini)는 촉만 붙여서 부담을 줄인다.
	if vt >= 3 and class ~= "Rocket" then
		local isBolt = style == "Bolt" or style == "Rocket"
		local half = (isBolt and (length or 3) or size) / 2
		local steel = color:Lerp(Color3.fromRGB(190, 195, 205), 0.55)
		local function bodyPart(shape, partSize, offset, material, tint, transparency)
			local p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, false, true
			p.Shape = shape
			p.Material = material
			p.Color = tint
			p.Transparency = transparency or 0
			p.Size = partSize
			p.CFrame = part.CFrame * offset
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = part, p
			w.Parent = p
			p.Parent = part
			return p
		end
		bodyPart(Enum.PartType.Ball, Vector3.new(size * 0.7, size * 0.7, size * 0.7), CFrame.new(0, 0, -half), Enum.Material.Metal, steel) -- 촉
		if not mini then
			if vt >= 12 then -- 꼬리 날개 두 장
				bodyPart(Enum.PartType.Block, Vector3.new(size * 1.5, size * 0.12, size * 0.9), CFrame.new(0, 0, half * 0.8), Enum.Material.Metal, steel:Lerp(color, 0.3))
				bodyPart(Enum.PartType.Block, Vector3.new(size * 0.12, size * 1.5, size * 0.9), CFrame.new(0, 0, half * 0.8), Enum.Material.Metal, steel:Lerp(color, 0.3))
			end
			if vt >= 25 then -- 몸통 테두리
				bodyPart(Enum.PartType.Cylinder, Vector3.new(size * 0.18, size * 1.25, size * 1.25), CFrame.new(0, 0, -half * 0.3) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Metal, steel)
			end
			if vt >= 45 then -- 은은하게 빛나는 띠 (한 줄)
				bodyPart(Enum.PartType.Cylinder, Vector3.new(size * 0.1, size * 1.35, size * 1.35), CFrame.new(0, 0, half * 0.25) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Neon, color, 0.35)
			end
			if vt >= 70 then -- 촉 둘레의 작은 가시 관
				for i = 0, 3 do
					local a = i * math.pi / 2
					bodyPart(Enum.PartType.Block, Vector3.new(size * 0.1, size * 0.1, size * 0.55), CFrame.new(math.cos(a) * size * 0.45, math.sin(a) * size * 0.45, -half * 0.85) * CFrame.Angles(math.sin(a) * 0.4, -math.cos(a) * 0.4, 0), Enum.Material.Metal, steel)
				end
			end
		end
	end
	part.Parent = fxFolder
	Debris:AddItem(part, 3) -- 안전장치: 어떤 이유로든 도착 처리가 안 돼도 탄이 화면에 남지 않게
	local dir = (to - from).Unit
	eraMuzzle(from, dir, era, color, inEra, mini)
	classFlourish(class or "Pistol", from, to, size, color, era, richness)
	if era == 7 and not mini then pathLightning(from, to, color, 0.2, 2.2) end
	if look and look.Muzzle then -- 권총 / 리볼버: 총구 고리 (총구 앞쪽에서 퍼지며 사라진다)
		eraRing(from + dir * 0.8, color, 0.6, look.Muzzle, 0.14, dir)
	elseif look and look.Puff then -- 샷건: 총구 원뿔 연기 (펠릿마다 만들지 않고 간격을 둔다)
		local now = os.clock()
		if now - lastPuff > 0.08 then
			lastPuff = now
			burst(from + dir * 1.2, Color3.fromRGB(215, 215, 220):Lerp(color, 0.25), 5)
		end
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
		-- 착탄 고리: 번호가 오를수록 조금씩 커진다 (은은하게: 흰 섬광 없음). 중반부터 두 겹.
		if vt >= 6 then
			eraRing(to, color, 1, 3 + 6 * richness, 0.18 + 0.1 * richness)
			if vt >= 50 and not mini then eraRing(to + Vector3.new(0, 0.5, 0), color, 0.6, 2 + 4 * richness, 0.14) end
		end
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
	if activeWarns >= 24 then return end -- (보스 패턴의 경고 원이 한꺼번에 여러 개 뜬다)
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
		local part = neonPart(Vector3.new(5, 5, length), yellow, 0.05)
		part.CFrame = CFrame.lookAt((a + b) / 2, b)
		part.Parent = fxFolder
		TweenService:Create(part, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(0.4, 0.4, length) }):Play()
		Debris:AddItem(part, 0.45)
	end
	local length = (top - bottom).Magnitude
	local core = neonPart(Vector3.new(2, 2, length), Color3.fromRGB(255, 255, 240), 0)
	core.CFrame = CFrame.lookAt((top + bottom) / 2, bottom)
	core.Parent = fxFolder
	TweenService:Create(core, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(0.15, 0.15, length) }):Play()
	Debris:AddItem(core, 0.3)
	scorch(bottom, 9, 1.6)
	ring({ "R", bottom, 16, yellow })
	ring({ "R", bottom, 9, WHITE })
	local flash = neonPart(Vector3.new(3, 3, 3), Color3.fromRGB(255, 250, 200), 0.2, Enum.PartType.Ball)
	flash.Position = bottom + Vector3.new(0, 2, 0)
	flash.Parent = fxFolder
	TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(15, 15, 15), Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.35)
	burst(bottom, yellow, 70)
	burst(bottom + Vector3.new(0, 1, 0), WHITE, 28)
end

local missiles = {}
local function missile(event) -- { "M", 출발, 대상 부품, 중간점, 시간, 크기, 모양, 색 }: 날아가 폭발하는 투사체. 모양: icbm(솟았다 급강하) / rocket(꼬리 불꽃 미사일) / blade(회전 표창) / orb(에너지 구체) / 없으면 노란 큰 구
	local from, target, mid, duration = event[2], event[3], event[4], event[5]
	local scale = event[6] or 1
	if scale >= 1 then -- (펫이 쏘는 작은 구슬은 펫에서 나가므로 제외)
		local snapped = snapToMe(from, 12, true)
		if snapped ~= from and typeof(mid) == "Vector3" then mid += (snapped - from) * 0.5 end -- 곡선 중간점도 같이 옮긴다
		from = snapped
	end
	local style = event[7]
	local tint = event[8] -- (선택) 불꽃 / 폭발 색
	if tint then tint = tint:Lerp(Color3.fromRGB(120, 125, 135), 0.14) end -- 너무 쨍하지 않게
	local icbm = style == "icbm"
	local long = icbm or style == "rocket" -- 길쭉한 몸체 (비행 방향을 향한다)
	local white = Color3.fromRGB(215, 225, 235)
	local ball
	if icbm then
		ball = neonPart(Vector3.new(0.7, 0.7, 3.6) * scale, white, 0)
	elseif style == "rocket" then
		ball = neonPart(Vector3.new(0.6, 0.6, 2.8) * scale, white:Lerp(tint or white, 0.35), 0)
	elseif style == "blade" then
		ball = neonPart(Vector3.new(3.8, 0.12, 1.1) * scale, white:Lerp(tint or white, 0.4), 0) -- 납작한 칼날: 빙글빙글 돈다
	elseif style == "orb" then
		ball = neonPart(Vector3.new(2, 2, 2) * scale, white:Lerp(tint or white, 0.5), 0.05, Enum.PartType.Ball)
	else
		ball = neonPart(Vector3.new(2.4, 2.4, 2.4) * scale, Color3.fromRGB(255, 190, 90), 0, Enum.PartType.Ball)
	end
	ball.Position = from
	local function pair(half)
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		if long then
			a0.Position, a1.Position = Vector3.new(half, 0, 1.4 * scale), Vector3.new(-half, 0, 1.4 * scale) -- 꼬리 쪽(뒤) 에 붙인다
		elseif style == "blade" then
			a0.Position, a1.Position = Vector3.new(1.9 * scale, 0, 0), Vector3.new(-1.9 * scale, 0, 0) -- 칼날 양 끝: 돌면서 빛띠가 소용돌이처럼 남는다
		else
			a0.Position, a1.Position = Vector3.new(0, half, 0), Vector3.new(0, -half, 0)
		end
		a0.Parent, a1.Parent = ball, ball
		return a0, a1
	end
	local a0, a1 = pair((long and 0.55 or 0.9) * scale)
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = icbm and 0.7 or (style == "blade" and 0.35 or 0.5)
	trail.Color = tint and ColorSequence.new(white, tint) or ColorSequence.new(Color3.fromRGB(255, 235, 140), Color3.fromRGB(255, 70, 30))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 1) })
	trail.LightEmission = 0.7
	trail.Parent = ball
	if style ~= "blade" and style ~= "orb" then
		local s0, s1 = pair(1.3 * scale)
		local smoke = Instance.new("Trail")
		smoke.Attachment0, smoke.Attachment1 = s0, s1
		smoke.Lifetime = icbm and 1.5 or 0.9 -- 솟아오른 자리에 연기 기둥이 길게 남는다
		smoke.Color = long and ColorSequence.new(Color3.fromRGB(240, 245, 250), Color3.fromRGB(95, 100, 112)) or ColorSequence.new(Color3.fromRGB(255, 140, 70), Color3.fromRGB(70, 70, 75))
		smoke.Transparency = NumberSequence.new(0.5, 1)
		smoke.WidthScale = NumberSequence.new(0.7, 1.5)
		smoke.LightEmission = 0.1
		smoke.Parent = ball
	end
	if style == "orb" or style == "blade" then -- 지나간 자리에 반짝이는 불씨
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 70
		sparks.Lifetime = NumberRange.new(0.25, 0.5)
		sparks.Speed = NumberRange.new(1, 5)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * scale), NumberSequenceKeypoint.new(1, 0) })
		sparks.Color = ColorSequence.new(white, tint or white)
		sparks.LightEmission = 0.6
		sparks.Parent = ball
	end
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = tint or Color3.fromRGB(255, 150, 70), 12, 2
	light.Parent = ball
	ball.Parent = fxFolder
	table.insert(missiles, { Ball = ball, From = from, Target = target, Last = event[3] and event[3].Parent and event[3].Position or from, Mid = mid, Duration = duration, Started = os.clock(), Scale = scale, Icbm = icbm, Style = style, Tint = tint, Prev = from })
end

local function flame(event) -- { "L", 위치, 반지름, 초 }: 큰 불길 지대 + 안쪽 밝은 불씨 판 + 튀는 불똥
	local position, radius, seconds = event[2], event[3], event[4]
	local flat = CFrame.new(position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local pad = neonPart(Vector3.new(0.4, radius * 2, radius * 2), Color3.fromRGB(255, 95, 30), 0.5, CYL)
	pad.CFrame = flat
	local inner = neonPart(Vector3.new(0.5, radius * 1.2, radius * 1.2), Color3.fromRGB(255, 190, 70), 0.4, CYL)
	inner.CFrame = flat
	local fire = Instance.new("Fire")
	fire.Size = math.clamp(radius * 1.8, 12, 42)
	fire.Heat = 10
	fire.Parent = pad
	local embers = Instance.new("ParticleEmitter")
	embers.Rate = 34
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
	local rock = neonPart(Vector3.new(16, 16, 16), Color3.fromRGB(255, 140, 50), 0, Enum.PartType.Ball)
	rock.Position = position + Vector3.new(18, 110, 14)
	local fire = Instance.new("Fire")
	fire.Size = 34
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
		ring({ "R", position, radius * 1.15, orange })
		ring({ "R", position, radius * 0.6, WHITE })
		ringWave(position, radius * 1.2, Color3.fromRGB(255, 200, 110), 0.65, 28, 2.6)
		scorch(position, radius * 0.7, 3.5) -- 구덩이 자국
		burst(position + Vector3.new(0, 3, 0), orange, 170)
		burst(position + Vector3.new(0, 2, 0), WHITE, 50)
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
			local orange = m.Tint or Color3.fromRGB(255, 150, 60)
			if m.Icbm then -- 데드아이: 크게 터지고 충격 고리가 두 겹으로 퍼진다
				burst(m.Last, orange, 50)
				burst(m.Last, WHITE, 18)
				ring({ "R", m.Last - Vector3.new(0, 1, 0), 13, orange })
				ring({ "R", m.Last - Vector3.new(0, 1, 0), 7, WHITE })
			else
				burst(m.Last, orange, math.floor(36 * m.Scale))
				burst(m.Last, WHITE, math.floor(10 * m.Scale))
				ring({ "R", m.Last - Vector3.new(0, 1, 0), 7 * m.Scale + 1, orange })
			end
			m.Ball:Destroy()
			table.remove(missiles, i)
		else
			local pos
			if m.Icbm then
				-- 1) 앞 55%: 천천히 솟는다 (점점 빨라지며 꼭대기에서 잠깐 머뭇) 2) 뒤 45%: 목표를 향해 꺾어 급가속으로 내리꽂는다
				if t < 0.55 then
					local u = t / 0.55
					pos = m.From:Lerp(m.Mid, math.sin(u * math.pi / 2) * 0.35 + u * 0.65)
				else
					local v = (t - 0.55) / 0.45
					pos = m.Mid:Lerp(m.Last, v ^ 2.4)
				end
			else
				local k = m.Style == "blade" and t or t * t * 0.4 + t * 0.6 -- 미사일 / 구체: 갈수록 빨라진다
				pos = m.From:Lerp(m.Mid, k):Lerp(m.Mid:Lerp(m.Last, k), k) -- 2차 곡선
			end
			if m.Style == "blade" then
				m.Ball.CFrame = CFrame.new(pos) * CFrame.Angles(0, now * 38, 0) -- 표창처럼 빙글빙글
			elseif m.Icbm or m.Style == "rocket" then
				local dir = pos - m.Prev
				if dir.Magnitude > 0.01 then
					m.Ball.CFrame = CFrame.lookAt(pos, pos + dir)
				else
					m.Ball.Position = pos
				end
			else
				m.Ball.Position = pos
			end
			m.Prev = pos
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

------------------------------------------------------------
-- 빛의 정령 (F 스킬): 소환한 사람 주위를 도는 작은 빛의 구슬 몇 마리. 모습은 각자 화면에서 그린다 (서버는 "Y" 로 시작 / 끝, "J" 로 쏘는 순간만 알린다).
--   "Y" { userId, 개수(0이면 끝), 남은 초 }  /  "J" { userId, 번호, 맞은 위치 }
------------------------------------------------------------
local spirits = {} -- [userId] = { Parts = { { Orb, Lunge, LungeDir } }, Count, Expire }
local SPIRIT_TINT = Color3.fromRGB(190, 235, 255)
local function killSpirits(entry, withBurst)
	for _, sp in ipairs(entry.Parts) do
		if withBurst and sp.Orb.Parent then burst(sp.Orb.Position, SPIRIT_TINT, 8) end
		sp.Orb:Destroy()
	end
end
local function spiritEvent(event)
	local userId, count = event[2], event[3]
	local entry = spirits[userId]
	if not count or count <= 0 then
		if entry then
			killSpirits(entry, true)
			spirits[userId] = nil
		end
		return
	end
	if entry and entry.Count ~= count then
		killSpirits(entry, false)
		entry = nil
	end
	if not entry then
		local owners = 0
		for _ in pairs(spirits) do owners += 1 end
		if owners >= 6 then return end -- (화면에 정령이 너무 많아지지 않게: 동시에 6명까지)
		entry = { Parts = {}, Count = count }
		for index = 1, count do
			local orb = neonPart(Vector3.new(1.5, 1.5, 1.5), Color3.fromRGB(225, 248, 255), 0, Enum.PartType.Ball)
			if not lowSpecOn() then
				solid(orb, Vector3.new(2.8, 2.8, 2.8), Color3.fromRGB(150, 215, 255), Enum.Material.Neon, CFrame.identity, 0.62, Enum.PartType.Ball) -- 은은한 빛무리
				for side = -1, 1, 2 do -- 작은 날개 한 쌍
					solid(orb, Vector3.new(1.7, 0.1, 0.9), Color3.fromRGB(235, 250, 255), Enum.Material.Neon, CFrame.new(side * 1.05, 0.2, 0.1) * CFrame.Angles(0, 0, math.rad(side * -22)), 0.3)
				end
				local sparks = addEmitter(orb, SPIRIT_TINT, 14, 0.6, 0.6, 2)
				sparks.Texture = SPARKLE
			end
			local light = Instance.new("PointLight")
			light.Color, light.Range, light.Brightness = SPIRIT_TINT, 9, 1.2
			light.Parent = orb
			orb.Parent = fxFolder
			table.insert(entry.Parts, { Orb = orb })
		end
		spirits[userId] = entry
		local owner = Players:GetPlayerByUserId(userId)
		local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		if root then burst(root.Position + Vector3.new(0, 3, 0), SPIRIT_TINT, 24) end -- 나타날 때 한 번 빛이 터진다
	end
	entry.Expire = os.clock() + (event[4] or 10) + 1.5 -- 서버가 3초마다 다시 알린다: 끊기면 저절로 사라진다
end
local function spiritHit(event)
	local entry = spirits[event[1 + 1]]
	local sp = entry and entry.Parts[event[3]]
	local target = event[4]
	if not sp or not sp.Orb.Parent or typeof(target) ~= "Vector3" then return end
	local from = sp.Orb.Position
	local length = (target - from).Magnitude
	if length < 1 then return end
	sp.Lunge, sp.LungeDir = os.clock() + 0.12, (target - from).Unit -- 쏠 때 살짝 앞으로 튄다
	local beam = rootPart(CFrame.lookAt((from + target) / 2, target), Vector3.new(0.45, 0.45, length), SPIRIT_TINT, Enum.Material.Neon, nil, 0.15)
	TweenService:Create(beam, TweenInfo.new(0.22), { Size = Vector3.new(0.05, 0.05, length), Transparency = 1 }):Play()
	Debris:AddItem(beam, 0.3)
	burst(target, SPIRIT_TINT, 5)
end
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for userId, entry in pairs(spirits) do
		local owner = Players:GetPlayerByUserId(userId)
		local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		if now > entry.Expire or not root then
			killSpirits(entry, false)
			spirits[userId] = nil
		else
			for index, sp in ipairs(entry.Parts) do
				local angle = now * 1.5 + index * (2 * math.pi / entry.Count)
				local pos = root.Position + Vector3.new(math.cos(angle) * 5.5, 3.4 + math.sin(now * 3 + index * 1.7) * 0.7, math.sin(angle) * 5.5)
				if sp.Lunge and now < sp.Lunge then pos += sp.LungeDir * 1.6 end
				sp.Orb.CFrame = CFrame.new(pos)
			end
		end
	end
end)


-- 마법책: 머리 위에 원소(불 / 얼음 / 번개)를 1.5초 모았다가 "파파파팍" 줄지어 쏟아 낸다. 이벤트 { "A", 쏜 사람 UserId, 모으는 시간, { { 대상 위치, 원소(1 불 / 2 얼음 / 3 번개) } ... }, 발 사이 간격 }
local TOME_COLORS = { Color3.fromRGB(255, 150, 60), Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 240, 120) }
local function tomeBolt(from, target, element, delay)
	task.delay(delay, function()
		local color = TOME_COLORS[element]
		if element == 3 then -- 번개: 곧바로 꺾이는 번쩍임
			local last = from
			for step = 1, 4 do
				local point = step == 4 and target or from:Lerp(target, step / 4) + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
				local length = (point - last).Magnitude
				if length > 0.1 then
					local seg = rootPart(CFrame.lookAt((last + point) / 2, point), Vector3.new(0.35, 0.35, length), color, Enum.Material.Neon, nil, 0.05)
					TweenService:Create(seg, TweenInfo.new(0.25), { Size = Vector3.new(0.05, 0.05, length), Transparency = 1 }):Play()
					Debris:AddItem(seg, 0.3)
				end
				last = point
			end
			burst(target, color, 14)
		else
			local size = element == 1 and Vector3.new(1.3, 1.3, 1.3) or Vector3.new(0.5, 0.5, 2.4)
			local missile = rootPart(CFrame.lookAt(from, target), size, color, Enum.Material.Neon, element == 1 and Enum.PartType.Ball or nil, 0.05)
			addTrail(missile, color, 0.9, 0.25)
			local flight = TweenService:Create(missile, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.lookAt(target, target + (target - from)) })
			flight.Completed:Connect(function()
				missile:Destroy()
				burst(target, color, element == 1 and 22 or 16)
			end)
			flight:Play()
			Debris:AddItem(missile, 1)
		end
	end)
end
local function tomeCast(event)
	local owner = Players:GetPlayerByUserId(event[2])
	local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
	local bolts = event[4]
	if not root or typeof(bolts) ~= "table" then return end
	local charge = math.clamp(event[3] or 1.5, 0.3, 3)
	local gap = math.clamp(event[5] or 0.09, 0.03, 0.3)
	local started = os.clock()
	local core = rootPart(CFrame.new(root.Position + Vector3.new(0, 5.4, 0)), Vector3.new(0.4, 0.4, 0.4), TOME_COLORS[1], Enum.Material.Neon, Enum.PartType.Ball, 0.1)
	local orbs = {}
	for index = 1, 9 do -- 세 원소 구슬이 번갈아 돌며 모여든다
		orbs[index] = rootPart(core.CFrame, Vector3.new(0.6, 0.6, 0.6), TOME_COLORS[(index - 1) % 3 + 1], Enum.Material.Neon, Enum.PartType.Ball, 0.2)
	end
	task.spawn(function()
		while true do
			local t = (os.clock() - started) / charge
			if t >= 1 or not core.Parent or not root.Parent then break end
			local top = root.Position + Vector3.new(0, 5.4, 0)
			core.Size = Vector3.one * (0.4 + 2.4 * t)
			core.CFrame = CFrame.new(top)
			core.Color = TOME_COLORS[math.floor(os.clock() * 5) % 3 + 1] -- 불 -> 얼음 -> 번개 색이 빠르게 번갈아 번쩍인다
			local radius = 5.5 * (1 - t) + 0.6
			for index, orb in ipairs(orbs) do
				local angle = os.clock() * (4 + 6 * t) + index * (2 * math.pi / #orbs)
				orb.CFrame = CFrame.new(top + Vector3.new(math.cos(angle) * radius, math.sin(os.clock() * 4 + index) * 0.7 * (1 - t), math.sin(angle) * radius))
			end
			RunService.RenderStepped:Wait()
		end
		for _, orb in ipairs(orbs) do orb:Destroy() end
		local from = core.Parent and core.Position or (root.Parent and root.Position + Vector3.new(0, 5.4, 0))
		if core.Parent then
			burst(core.Position, Color3.new(1, 1, 1), 20)
			core:Destroy()
		end
		if not from then return end
		for index, bolt in ipairs(bolts) do
			if typeof(bolt) == "table" and typeof(bolt[1]) == "Vector3" then
				tomeBolt(from + Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 1.5, bolt[1], math.clamp(bolt[2] or 1, 1, 3), (index - 1) * gap)
			end
		end
	end)
end

-- 연쇄 번개 한 칸: { "C", 시작, 끝, 첫 타인가 }: 푸른 빛 번개 한 줄기(겉 빛 + 노란 몸통 + 하얀 심지)가 지그재그로 꺾이며 뻗고, 곁가지가 갈라지고, 한 번 더 지직 하고 떨리며, 맞은 곳에서 번쩍 터진다 ("Z" 는 하늘에서 내리꽂는 굵은 번개)
local BOLT_BLUE, BOLT_YELLOW, BOLT_WHITE = Color3.fromRGB(110, 150, 255), Color3.fromRGB(255, 240, 130), Color3.fromRGB(255, 255, 245)
local function boltPoints(a, b, segments, jitter)
	local points = { a }
	for i = 1, segments - 1 do
		local fade = math.sin(math.pi * i / segments) -- 양 끝은 덜 흔들리고 가운데가 크게 꺾인다
		table.insert(points, a:Lerp(b, i / segments) + Vector3.new((math.random() - 0.5) * jitter * fade * 2, (math.random() - 0.5) * jitter * fade * 1.2, (math.random() - 0.5) * jitter * fade * 2))
	end
	table.insert(points, b)
	return points
end
local function drawBolt(points, width, color, transparency, life)
	for i = 1, #points - 1 do
		local p0, p1 = points[i], points[i + 1]
		local length = (p1 - p0).Magnitude
		if length > 0.1 then
			local part = neonPart(Vector3.new(width, width, length + width * 0.5), color, transparency)
			part.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
			part.Parent = fxFolder
			TweenService:Create(part, TweenInfo.new(life), { Transparency = 1, Size = Vector3.new(width * 0.15, width * 0.15, length) }):Play()
			Debris:AddItem(part, life + 0.05)
		end
	end
end
local function chainHop(event)
	local a, b = event[2], event[3]
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then return end
	local first = event[4] == true
	local thick = first and 1.5 or 1
	local length = (b - a).Magnitude
	local main = boltPoints(a, b, math.clamp(math.floor(length / 5) + 3, 4, 7), math.clamp(length * 0.18, 1.5, 5))
	drawBolt(main, 3.4 * thick, BOLT_BLUE, 0.55, 0.38) -- 겉 빛
	drawBolt(main, 1.5 * thick, BOLT_YELLOW, 0.1, 0.3) -- 몸통
	drawBolt(main, 0.6 * thick, BOLT_WHITE, 0, 0.22) -- 하얀 심지
	for _ = 1, 2 do -- 곁가지: 줄기 중간에서 옆으로 갈라지는 짧은 번개
		local at = main[math.random(2, #main - 1)]
		local tip = at + Vector3.new((math.random() - 0.5) * 14, (math.random() - 0.3) * 6, (math.random() - 0.5) * 14)
		drawBolt(boltPoints(at, tip, 3, 2), 0.7, BOLT_YELLOW, 0.2, 0.25)
	end
	task.delay(0.07, function() -- 지직: 같은 길이 살짝 다르게 한 번 더 번쩍
		drawBolt(boltPoints(a, b, #main - 1, math.clamp(length * 0.2, 2, 6)), 1.1 * thick, BOLT_WHITE, 0.1, 0.2)
	end)
	-- 맞은 곳: 번쩍 + 불꽃 + 고리 + 그을음
	burst(b, BOLT_YELLOW, first and 28 or 18)
	burst(b, BOLT_WHITE, 8)
	ring({ "R", b, first and 12 or 8, BOLT_BLUE })
	if scorch then scorch(b, first and 5 or 3, 1.2) end
	local glow = rootPart(CFrame.new(b), Vector3.new(0.5, 0.5, 0.5), BOLT_WHITE, Enum.Material.Neon, Enum.PartType.Ball, 0.2)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = BOLT_YELLOW, first and 26 or 18, 4
	light.Parent = glow
	TweenService:Create(glow, TweenInfo.new(0.25), { Size = Vector3.one * (first and 7 or 4.5), Transparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 0 }):Play()
	Debris:AddItem(glow, 0.3)
	if first then burst(a, BOLT_BLUE, 14) end -- 손끝에서 튀는 불꽃
end

local FLOAT_SIZE, DAMAGE_SIZE = UDim2.new(0, 140, 0, 36), UDim2.new(0, 90, 0, 40)
lootTicker = { G = { Pending = 0, Last = 0, Scheduled = false }, XP = { Pending = 0, Last = 0, Scheduled = false } } -- 골드 / 경험치 글자 합치기용
local HANDLERS = {
	S = playShot,
	P = spawnProjectile,
	X = function(event) removeProjectile(event[2], event[3]) end,
	Q = reaimProjectile, W = groundWarn,
	T = tracer,
	B = function(event) burst(event[2], event[3], event[4]) end,
	F = function(event) -- { "F", 위치, 글자, 색, (폭), (초) }: 폭이 있으면 배너처럼 크고 오래 뜬다
		-- 골드 / 경험치 획득 글자("+8 G", "+4 XP")는 작고 흐리게, 0.3초 안에 여러 개가 오면 합쳐서 한 번만 (화면 잡음 줄이기)
		local text = event[3]
		if not event[5] and typeof(text) == "string" then
			local amount, unit = string.match(text, "^%+(%d+) (G)$")
			if not amount then amount, unit = string.match(text, "^💰 %+(%d+) (G)$") end
			if not amount then amount, unit = string.match(text, "^%+(%d+) (XP)$") end
			if amount then
				local slot = lootTicker[unit]
				local now = os.clock()
				slot.Pending += tonumber(amount)
				slot.Position, slot.Color = event[2], event[4]
				if not slot.Scheduled then
					slot.Scheduled = true
					task.delay(math.max(0, slot.Last + 0.3 - now), function()
						slot.Scheduled = false
						slot.Last = os.clock()
						local total = slot.Pending
						slot.Pending = 0
						showText(slot.Position, string.format("+%d %s", total, unit), slot.Color, UDim2.new(0, 80, 0, 20), 0.55, 2, 0.45)
					end)
				end
				return
			end
		end
		local width = event[5]
		if width then
			width = math.clamp(width, 120, 420)
			showText(event[2], event[3], event[4], UDim2.new(0, width, 0, math.floor(width * 0.16)), math.clamp(event[6] or 1.4, 0.5, 3), 5)
		else
			showText(event[2], event[3], event[4], FLOAT_SIZE, 0.7, 3)
		end
	end,
	D = function(event) -- { "D", position, amount, isCrit, (색) }: 색이 있으면 세트 효과 / 데드아이 피해 -> 그 색으로 크게
		if event[5] then
			showText(event[2], tostring(event[3]), event[5]:Lerp(WHITE, 0.25), UDim2.new(0, 150, 0, 60), 0.75, 3)
		else
			showText(event[2], event[4] and (tostring(event[3]) .. "!") or tostring(event[3]), event[4] and Color3.fromRGB(255, 220, 60) or WHITE, DAMAGE_SIZE, 0.5, nil)
		end
	end,
	H = function(event) flash(event[2]) end,
	G = gunSound,
	R = ring, Z = bolt, M = missile, L = flame, E = meteor, O = orbit, Y = spiritEvent, J = spiritHit, A = tomeCast, C = chainHop,
}

-- 한 배치(한 프레임)에서 종류별로 그릴 수 있는 최대 개수: 넘치는 것은 건너뛴다 (지우기 "X" / 끄기 "O" / 번쩍임 "H" 는 제한 없음)
local BATCH_LIMIT = { C = 16, A = 6, Y = 8, J = 24, G = 10, T = 48, R = 16, Z = 8, M = 12, L = 8, E = 8, U = 6, N = 6, V = 8, K = 14, P = 100, Q = 40, W = 10, S = 100, B = 60 }
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
	ringWave(position, radius, color, 0.5, 26, 2.4)
	ring({ "R", position, radius * 0.9, color })
	ring({ "R", position, radius * 0.5, WHITE })
	local glow = neonPart(Vector3.new(2, 2, 2), color:Lerp(WHITE, 0.4), 0.3, Enum.PartType.Ball) -- 빛구 (화면 번쩍임 없음)
	glow.CastShadow = false
	glow.Position = center
	glow.Parent = fxFolder
	TweenService:Create(glow, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 1.7, Transparency = 1 }):Play()
	Debris:AddItem(glow, 0.32)
	burst(center, color, 85)
	burst(center, color:Lerp(WHITE, 0.7), 34)
	deathBurst({ "K", center, color:Lerp(Color3.fromRGB(70, 50, 40), 0.5), 5 })
end

HANDLERS.U = skull
HANDLERS.N = novaFx
HANDLERS.V = function(event) ringWave(event[2], event[3], event[4], event[5] or 0.7, math.clamp(math.floor(event[3] * 1.3), 16, 30), 1.3) end

-- 데드아이 마지막 대폭발: 화면이 "쿵" 하고 살짝 조여졌다가 풀린다 (시야각을 잠깐 좁힌다. 서버가 UltFinaleTick 을 올릴 때)
do
	local localPlayer = game:GetService("Players").LocalPlayer
	localPlayer:GetAttributeChangedSignal("UltFinaleTick"):Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local TweenService = game:GetService("TweenService")
		local base = camera.FieldOfView
		camera.FieldOfView = base - 9
		TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
	end)
end
