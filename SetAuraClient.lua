-- SetAuraClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: SetAuraClient)
-- 구역 장비 세트(2부위 / 3부위)를 맞춘 플레이어 주변에 세트별 오라를 그린다. 몸 전체를 칠하지 않고 아바타 외형은 그대로 둔다.
--   발밑 룬 서클(SurfaceGui 선) + 천천히 도는 모티프 3~6개 + 가벼운 입자 2개 + (3부위) 머리 위 왕관 / 등 뒤 후광 + 아주 약한 빛
-- 서버가 이미 쓰는 Attribute 만 읽는다: Gear_<부위>_Set (장착 세트 키, 예 "Zone3") / AugAuraColor (세트 효과가 켜졌는지)
-- 모든 오라는 RenderStepped 하나로 움직이고, 오라가 없으면 루프도 꺼진다. 가까운 순 최대 6명, 120 스터드 안만.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local MAX_AURAS = 6
local RANGE = 120
local RESELECT = 0.4

------------------------------------------------------------
-- 세트별 디자인 (Zone1 ~ Zone8, Config.Sets.ZoneKeys 순서)
--   motes: n(3 ~ 6) shape size color material trans mode radius h0 h1 speed spin(회전 속도) dir
--   mode: orbit(원 궤도) drift(낙엽처럼 흔들림) firefly(반딧불 유영) rise(솟아오름) fall(눈처럼 내림) face(바깥을 바라보며 공전)
--   ringFx: 발밑 입자  backFx: 등 뒤 흔적(이동하면 뒤에 길게 남는다)  crown: halo / sun / orb
------------------------------------------------------------
local SETS = {
	[1] = { -- 초원의 수호: 떠도는 나뭇잎 + 연두 반짝임
		color = Color3.fromRGB(135, 205, 115), accent = Color3.fromRGB(215, 240, 160), style = "circle", ticks = 6, crown = "halo",
		motes = { n = 5, shape = Enum.PartType.Block, size = Vector3.new(0.5, 0.06, 0.3), color = Color3.fromRGB(120, 195, 95), material = Enum.Material.SmoothPlastic,
			trans = 0.2, mode = "drift", radius = 3.3, h0 = 0.8, h1 = 5.2, speed = 0.55, spin = 2.4 },
		ringFx = { rate = 5, life = 1.6, speed = 1.6, size = 0.35, trans = 0.45, light = 0.3, grav = 0 },
		backFx = { rate = 5, life = 1.3, speed = 0.6, size = 0.4, trans = 0.55, light = 0.15, grav = -0.5 },
	},
	[2] = { -- 숲의 축복: 반딧불
		color = Color3.fromRGB(95, 200, 125), accent = Color3.fromRGB(215, 245, 120), style = "circle", ticks = 5, crown = "halo",
		motes = { n = 6, shape = Enum.PartType.Ball, size = Vector3.new(0.26, 0.26, 0.26), color = Color3.fromRGB(215, 245, 120), material = Enum.Material.Neon,
			trans = 0.2, mode = "firefly", radius = 3.8, h0 = 0.8, h1 = 5.4, speed = 0.7, spin = 0, pulse = true },
		ringFx = { rate = 4, life = 2.2, speed = 1, size = 0.3, trans = 0.5, light = 0.5, grav = 0 },
		backFx = { rate = 4, life = 1.6, speed = 0.4, size = 0.3, trans = 0.55, light = 0.5, grav = 0 },
	},
	[3] = { -- 폐허의 의지: 공전하는 룬 석판
		color = Color3.fromRGB(205, 175, 125), accent = Color3.fromRGB(240, 215, 160), style = "diamond", ticks = 4, crown = "halo",
		motes = { n = 4, shape = Enum.PartType.Block, size = Vector3.new(0.55, 0.8, 0.14), color = Color3.fromRGB(150, 135, 115), material = Enum.Material.Slate,
			trans = 0.05, mode = "face", radius = 3.4, h0 = 2.2, h1 = 3.4, speed = 0.4, spin = 0, glow = Color3.fromRGB(240, 215, 160) },
		ringFx = { rate = 5, life = 1.8, speed = 1.2, size = 0.3, trans = 0.55, light = 0.1, grav = 0 },
		backFx = { rate = 4, life = 1.4, speed = 0.5, size = 0.5, trans = 0.7, light = 0, grav = 0.3 },
	},
	[4] = { -- 사막의 태양: 모래 소용돌이 + 등 뒤 태양 후광
		color = Color3.fromRGB(240, 195, 95), accent = Color3.fromRGB(255, 230, 150), style = "circle", ticks = 8, crown = "sun",
		motes = { n = 6, shape = Enum.PartType.Ball, size = Vector3.new(0.22, 0.22, 0.22), color = Color3.fromRGB(235, 205, 140), material = Enum.Material.SmoothPlastic,
			trans = 0.1, mode = "rise", radius = 3.0, h0 = 0.3, h1 = 5.6, speed = 0.28, spin = 0 },
		ringFx = { rate = 6, life = 1.4, speed = 2.2, size = 0.3, trans = 0.55, light = 0.2, grav = 0 },
		backFx = { rate = 5, life = 1.2, speed = 0.8, size = 0.4, trans = 0.6, light = 0.25, grav = 0.2 },
	},
	[5] = { -- 서리의 숨결: 눈송이 + 얼음 조각
		color = Color3.fromRGB(150, 220, 250), accent = Color3.fromRGB(235, 248, 255), style = "diamond", ticks = 6, crown = "halo",
		motes = { n = 6, shape = Enum.PartType.Ball, size = Vector3.new(0.2, 0.2, 0.2), color = Color3.fromRGB(240, 250, 255), material = Enum.Material.SmoothPlastic,
			trans = 0.1, mode = "fall", radius = 3.2, h0 = 0.3, h1 = 5.8, speed = 0.22, spin = 0,
			shards = 2, shardColor = Color3.fromRGB(165, 225, 250), shardSize = Vector3.new(0.18, 0.7, 0.18) },
		ringFx = { rate = 4, life = 1.8, speed = 1, size = 0.28, trans = 0.45, light = 0.3, grav = 0 },
		backFx = { rate = 5, life = 1.5, speed = 0.5, size = 0.3, trans = 0.5, light = 0.3, grav = 0.6 },
	},
	[6] = { -- 용암의 심장: 솟는 불씨 + 용암 룬 링
		color = Color3.fromRGB(235, 105, 55), accent = Color3.fromRGB(255, 175, 90), style = "diamond", ticks = 6, crown = "halo",
		motes = { n = 6, shape = Enum.PartType.Ball, size = Vector3.new(0.24, 0.24, 0.24), color = Color3.fromRGB(255, 140, 60), material = Enum.Material.Neon,
			trans = 0.1, mode = "rise", radius = 2.9, h0 = 0.3, h1 = 6.0, speed = 0.35, spin = 0 },
		ringFx = { rate = 7, life = 1.4, speed = 3.2, size = 0.3, trans = 0.35, light = 0.5, grav = 0 },
		backFx = { rate = 6, life = 1.1, speed = 1.2, size = 0.35, trans = 0.45, light = 0.5, grav = -1.5 },
	},
	[7] = { -- 암흑의 서약: 그림자 위스프 + 옅은 어둠 안개
		color = Color3.fromRGB(165, 105, 235), accent = Color3.fromRGB(95, 55, 150), style = "diamond", ticks = 4, crown = "halo",
		motes = { n = 4, shape = Enum.PartType.Ball, size = Vector3.new(0.55, 0.55, 0.55), color = Color3.fromRGB(70, 40, 110), material = Enum.Material.SmoothPlastic,
			trans = 0.5, mode = "drift", radius = 3.0, h0 = 0.8, h1 = 4.2, speed = 0.45, spin = 0 },
		ringFx = { rate = 5, life = 2.2, speed = 0.8, size = 1.6, trans = 0.75, light = 0, grav = 0, dark = true },
		backFx = { rate = 5, life = 1.8, speed = 0.4, size = 1.8, trans = 0.75, light = 0, grav = 0, dark = true },
	},
	[8] = { -- 심연의 지배: 공허 오브 고리 + 분홍 코어
		color = Color3.fromRGB(235, 85, 150), accent = Color3.fromRGB(120, 50, 120), style = "circle", ticks = 5, crown = "orb",
		motes = { n = 5, shape = Enum.PartType.Ball, size = Vector3.new(0.4, 0.4, 0.4), color = Color3.fromRGB(95, 35, 105), material = Enum.Material.Glass,
			trans = 0.15, mode = "orbit", radius = 3.3, h0 = 2.3, h1 = 3.5, speed = 0.65, spin = 0, glow = Color3.fromRGB(235, 85, 150) },
		ringFx = { rate = 4, life = 1.8, speed = 1.4, size = 0.35, trans = 0.45, light = 0.35, grav = 0 },
		backFx = { rate = 4, life = 1.4, speed = 0.5, size = 0.4, trans = 0.5, light = 0.35, grav = 0 },
	},
}

------------------------------------------------------------
-- 상태
------------------------------------------------------------
local folder = Instance.new("Folder")
folder.Name = "SetAuraFx"
folder.Parent = workspace

local candidates = {} -- [Player] = { Zone, Tier }  (세트 효과가 켜진 플레이어)
local active = {}     -- [Player] = aura  (실제로 그려지는 것, 최대 6)
local conns = {}      -- [Player] = RBXScriptConnection
local loopConn = nil
local nextSelect = 0
local bulkParts, bulkCFs = {}, {}

------------------------------------------------------------
-- 세트 판별: Gear_<부위>_Set 에서 가장 많이 맞춘 구역 세트 (동률이면 높은 구역), 2부위 이상 + AugAuraColor 가 켜져 있어야 한다
------------------------------------------------------------
local function computeCandidate(plr)
	if typeof(plr:GetAttribute("AugAuraColor")) ~= "Color3" then return nil end
	local counts = {}
	for name, value in pairs(plr:GetAttributes()) do
		if type(value) == "string" and value ~= "" and name:match("^Gear_.+_Set$") then
			local zone = tonumber(value:match("^Zone(%d+)$"))
			if zone and SETS[zone] then counts[zone] = (counts[zone] or 0) + 1 end
		end
	end
	local bestZone, bestCount = nil, 1
	for zone, count in pairs(counts) do
		if count > bestCount or (count == bestCount and bestZone and zone > bestZone) then bestZone, bestCount = zone, count end
	end
	if not bestZone then return nil end
	return { Zone = bestZone, Tier = bestCount >= 3 and 3 or 2 }
end

------------------------------------------------------------
-- 생성
------------------------------------------------------------
local function newPart(name, size, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if shape then part.Shape = shape end
	return part
end

local function circleFrame(parent, scale, thickness, strokeTrans, color, round)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(scale, -6, scale, -6)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Transparency = strokeTrans
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

-- 룬 서클: 바깥 원 + 안쪽 원(또는 마름모) + 눈금. 파트 자체는 투명하고 선만 보인다.
local function addRuneGui(part, face, def, tier)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(256, 256)
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.AlwaysOnTop = false
	gui.Parent = part
	circleFrame(gui, 1, 3, 0.35, def.color, true)
	local inner = circleFrame(gui, 0.72, 2, 0.5, def.accent, def.style == "circle")
	if def.style == "diamond" then inner.Rotation = 45 end
	if tier >= 3 then circleFrame(gui, 0.46, 1.5, 0.55, def.color, true) end
	local ticks = def.ticks + (tier >= 3 and 2 or 0)
	for i = 1, ticks do
		local a = (i / ticks) * math.pi * 2
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Size = UDim2.fromOffset(10, 10)
		tick.Position = UDim2.new(0.5, math.cos(a) * 110, 0.5, math.sin(a) * 110)
		tick.Rotation = math.deg(a) + 45
		tick.BackgroundColor3 = def.accent
		tick.BackgroundTransparency = 0.3
		tick.BorderSizePixel = 0
		tick.Parent = gui
	end
end

local function makeEmitter(parent, spec, color, accent, scale, direction)
	local fx = Instance.new("ParticleEmitter")
	fx.Rate = spec.rate * scale
	fx.Lifetime = NumberRange.new(spec.life * 0.8, spec.life * 1.2)
	fx.Speed = NumberRange.new(spec.speed * 0.6, spec.speed)
	fx.SpreadAngle = Vector2.new(25, 25)
	fx.EmissionDirection = direction
	fx.Acceleration = Vector3.new(0, spec.grav, 0)
	fx.LightEmission = spec.light
	fx.LightInfluence = spec.dark and 1 or 0
	fx.Color = ColorSequence.new(spec.dark and accent or color, spec.dark and accent or accent)
	fx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, spec.trans),
		NumberSequenceKeypoint.new(1, 1) })
	fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.size), NumberSequenceKeypoint.new(1, spec.size * (spec.dark and 1.8 or 0.3)) })
	fx.Rotation = NumberRange.new(0, 360)
	fx.RotSpeed = NumberRange.new(-40, 40)
	fx.Parent = parent
	return fx
end

local function buildAura(plr, zone, tier)
	local character = plr.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and hum) then return nil end
	local def = SETS[zone]
	local scale = tier >= 3 and 1 or 0.6
	local model = Instance.new("Folder")
	model.Name = "Aura_" .. plr.UserId
	local foot = hum.RigType == Enum.HumanoidRigType.R6 and 3 or (hum.HipHeight + root.Size.Y / 2)

	local aura = { Plr = plr, Char = character, Root = root, Hum = hum, Def = def, Zone = zone, Tier = tier, Folder = model, Foot = foot, Motes = {}, Shards = {} }

	-- 발밑 룬 서클 + 솟는 입자
	local ringSize = tier >= 3 and 7 or 5.6
	aura.Ring = newPart("Ring", Vector3.new(ringSize, 0.05, ringSize))
	aura.Ring.Transparency = 1
	addRuneGui(aura.Ring, Enum.NormalId.Top, def, tier)
	makeEmitter(aura.Ring, def.ringFx, def.color, def.accent, scale, Enum.NormalId.Top)
	aura.Ring.Parent = model

	-- 등 뒤 흔적 (+ 3부위면 아주 약한 빛)
	aura.Back = newPart("Back", Vector3.new(1.2, 1.6, 0.3))
	aura.Back.Transparency = 1
	makeEmitter(aura.Back, def.backFx, def.color, def.accent, scale, Enum.NormalId.Back)
	if tier >= 3 then
		local light = Instance.new("PointLight")
		light.Color = def.color
		light.Brightness = 0.45
		light.Range = 9
		light.Shadows = false
		light.Parent = aura.Back
	end
	aura.Back.Parent = model

	-- 모티프
	local m = def.motes
	local count = math.max(3, math.ceil(m.n * scale))
	local shardCount = m.shards and math.max(1, math.ceil(m.shards * scale)) or 0
	for i = 1, count do
		local part = newPart("Mote", m.size, m.shape)
		part.Color = m.color
		part.Material = m.material
		part.Transparency = m.trans
		if m.glow then -- 룬 석판 / 공허 오브: 안쪽에 옅은 빛 테두리
			local sel = Instance.new("SelectionBox")
			sel.Adornee = part
			sel.Color3 = m.glow
			sel.LineThickness = 0.02
			sel.Transparency = 0.4
			sel.SurfaceTransparency = 1
			sel.Parent = part
		end
		part.Parent = model
		aura.Motes[i] = part
	end
	for i = 1, shardCount do
		local part = newPart("Shard", m.shardSize)
		part.Color = m.shardColor
		part.Material = Enum.Material.Glass
		part.Transparency = 0.25
		part.Parent = model
		aura.Shards[i] = part
	end

	-- 3부위: 머리 위 후광 / 등 뒤 태양 / 분홍 코어
	if tier >= 3 then
		if def.crown == "halo" then
			aura.Crown = newPart("Crown", Vector3.new(2.6, 0.05, 2.6))
			aura.Crown.Transparency = 1
			addRuneGui(aura.Crown, Enum.NormalId.Top, def, 2)
			addRuneGui(aura.Crown, Enum.NormalId.Bottom, def, 2)
		elseif def.crown == "sun" then
			aura.Crown = newPart("Crown", Vector3.new(0.08, 5, 5), Enum.PartType.Cylinder)
			aura.Crown.Color = def.color
			aura.Crown.Material = Enum.Material.Neon
			aura.Crown.Transparency = 0.84
		else -- orb
			aura.Crown = newPart("Crown", Vector3.new(0.85, 0.85, 0.85), Enum.PartType.Ball)
			aura.Crown.Color = def.color
			aura.Crown.Material = Enum.Material.Neon
			aura.Crown.Transparency = 0.25
		end
		aura.Crown.Parent = model
	end

	model.Parent = folder
	return aura
end

local function destroyAura(aura)
	if aura.Folder then aura.Folder:Destroy() end
end

------------------------------------------------------------
-- 프레임 갱신 (모든 오라를 한 루프에서)
------------------------------------------------------------
local TAU = math.pi * 2

local function motePosition(mode, i, n, t, m)
	local sp = m.speed
	local h0, h1 = m.h0, m.h1
	local frac = (i - 1) / n
	if mode == "orbit" or mode == "face" then
		local a = t * sp + frac * TAU
		local y = h0 + (h1 - h0) * (0.5 + 0.5 * math.sin(t * 0.9 + i * 1.7))
		return math.cos(a) * m.radius, y, math.sin(a) * m.radius, a, 1
	elseif mode == "drift" then
		local a = t * sp + frac * TAU
		local r = m.radius * (0.85 + 0.2 * math.sin(t * 0.8 + i * 2.1))
		local y = h0 + (h1 - h0) * (0.5 + 0.5 * math.sin(t * 0.6 + i * 1.3))
		return math.cos(a) * r, y, math.sin(a) * r, a, 1
	elseif mode == "firefly" then
		local a = t * sp * 0.6 + i * 2.4
		local r = m.radius * (0.55 + 0.45 * math.sin(t * 0.7 + i * 3.1))
		local y = h0 + (h1 - h0) * (0.5 + 0.5 * math.sin(t * 0.8 + i * 1.9))
		return math.cos(a) * r, y, math.sin(a) * r, a, 1
	elseif mode == "rise" then
		local u = (t * sp + frac) % 1
		local a = t * 1.4 + frac * TAU
		local r = m.radius * (1 - 0.45 * u)
		return math.cos(a) * r, h0 + (h1 - h0) * u, math.sin(a) * r, a, 1 - math.min(1, math.min(u * 6, (1 - u) * 3)) -- 끝에서 흐려진다
	else -- fall
		local u = 1 - ((t * sp + frac) % 1)
		local a = t * 0.5 + frac * TAU + math.sin(t + i) * 0.4
		local r = m.radius * (0.7 + 0.3 * math.sin(i * 2.3 + t * 0.5))
		return math.cos(a) * r, h0 + (h1 - h0) * u, math.sin(a) * r, a, 1 - math.min(1, math.min(u * 6, (1 - u) * 3))
	end
end

local function pushMove(part, cf)
	local k = #bulkParts + 1
	bulkParts[k], bulkCFs[k] = part, cf
end

local function stepAura(aura, t)
	local root = aura.Root
	if aura.Plr.Character ~= aura.Char or not root.Parent or aura.Hum.Health <= 0 then return false end
	local rcf = root.CFrame
	local pos = rcf.Position
	local feet = Vector3.new(pos.X, pos.Y - aura.Foot, pos.Z)
	local def, m = aura.Def, aura.Def.motes
	local spinning = CFrame.Angles(0, t * 0.5, 0)

	pushMove(aura.Ring, CFrame.new(feet + Vector3.new(0, 0.12, 0)) * spinning)
	pushMove(aura.Back, rcf * CFrame.new(0, 0.3, 1.1))

	local n = #aura.Motes
	for i, part in ipairs(aura.Motes) do
		local x, y, z, a, fade = motePosition(m.mode, i, n, t, m)
		local p = feet + Vector3.new(x, y, z)
		local cf
		if m.mode == "face" then
			cf = CFrame.lookAt(p, p + Vector3.new(x, 0, z))
		elseif m.spin > 0 then
			cf = CFrame.new(p) * CFrame.Angles(t * m.spin + i, t * m.spin * 0.7, i * 1.3)
		else
			cf = CFrame.new(p)
		end
		pushMove(part, cf)
		if m.pulse then
			part.Transparency = 0.15 + 0.6 * (0.5 + 0.5 * math.sin(t * 2.2 + i * 2.7))
		elseif m.mode == "rise" or m.mode == "fall" then
			part.Transparency = m.trans + (1 - m.trans) * fade
		end
	end
	for i, part in ipairs(aura.Shards) do -- 얼음 조각: 몸 가까이서 천천히 공전
		local a = t * 0.45 + (i - 1) / #aura.Shards * TAU + 1
		local p = feet + Vector3.new(math.cos(a) * 3.0, 2.6 + math.sin(t * 0.9 + i) * 0.5, math.sin(a) * 3.0)
		pushMove(part, CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0.6, math.sin(a))) * CFrame.Angles(math.pi / 2, 0, 0))
	end

	local crown = aura.Crown
	if crown then
		if def.crown == "halo" then
			pushMove(crown, CFrame.new(feet + Vector3.new(0, 6 + math.sin(t * 1.3) * 0.15, 0)) * CFrame.Angles(0, -t * 0.7, 0))
		elseif def.crown == "sun" then
			local pulse = 1 + math.sin(t * 1.5) * 0.04
			crown.Size = Vector3.new(0.08, 5 * pulse, 5 * pulse)
			pushMove(crown, rcf * CFrame.new(0, 0.9, 1.7) * CFrame.Angles(0, math.pi / 2, 0))
		else
			pushMove(crown, CFrame.new(feet + Vector3.new(0, 6.4 + math.sin(t * 1.6) * 0.2, 0)))
			crown.Transparency = 0.2 + 0.15 * math.sin(t * 2.4)
		end
	end
	return true
end

local reselect

local function onFrame()
	local t = os.clock()
	if t >= nextSelect then
		nextSelect = t + RESELECT
		reselect()
	end
	if next(active) == nil then
		if next(candidates) == nil and loopConn then
			loopConn:Disconnect()
			loopConn = nil
		end
		return
	end
	table.clear(bulkParts)
	table.clear(bulkCFs)
	for plr, aura in pairs(active) do
		if not stepAura(aura, t) then
			destroyAura(aura)
			active[plr] = nil
		end
	end
	if #bulkParts > 0 then
		workspace:BulkMoveTo(bulkParts, bulkCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function ensureLoop()
	if not loopConn then
		loopConn = RunService.RenderStepped:Connect(onFrame)
		nextSelect = 0
	end
end

------------------------------------------------------------
-- 선택: 120 스터드 안에서 가까운 6명 (내 캐릭터는 항상 우선)
------------------------------------------------------------
reselect = function()
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local origin = myRoot and myRoot.Position or (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position) or Vector3.zero
	local list = {}
	for plr, info in pairs(candidates) do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local d = plr == player and -1 or (root.Position - origin).Magnitude
			if d <= RANGE then list[#list + 1] = { Plr = plr, Dist = d, Info = info } end
		end
	end
	table.sort(list, function(a, b) return a.Dist < b.Dist end)
	local keep = {}
	for i = 1, math.min(MAX_AURAS, #list) do
		local entry = list[i]
		local plr, info = entry.Plr, entry.Info
		keep[plr] = true
		local aura = active[plr]
		if aura and (aura.Zone ~= info.Zone or aura.Tier ~= info.Tier or aura.Char ~= plr.Character) then
			destroyAura(aura)
			active[plr] = nil
			aura = nil
		end
		if not aura then active[plr] = buildAura(plr, info.Zone, info.Tier) end
	end
	for plr, aura in pairs(active) do
		if not keep[plr] then
			destroyAura(aura)
			active[plr] = nil
		end
	end
end

local function refresh(plr)
	local info = computeCandidate(plr)
	candidates[plr] = info
	if info then
		ensureLoop()
		nextSelect = 0
	end
end

local function track(plr)
	if conns[plr] then return end
	conns[plr] = plr.AttributeChanged:Connect(function(name)
		if name == "AugAuraColor" or name:sub(1, 5) == "Gear_" then refresh(plr) end
	end)
	refresh(plr)
end

Players.PlayerAdded:Connect(track)
for _, plr in ipairs(Players:GetPlayers()) do track(plr) end

Players.PlayerRemoving:Connect(function(plr)
	if conns[plr] then conns[plr]:Disconnect() conns[plr] = nil end
	candidates[plr] = nil
	if active[plr] then
		destroyAura(active[plr])
		active[plr] = nil
	end
end)
