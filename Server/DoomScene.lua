-- DoomScene (ServerScriptService > Modules 안의 ModuleScript, 이름: DoomScene)
-- 튜토리얼 연출: 첫 구역 군주가 떨어뜨린 열쇠 -> 던전으로 추락(startTutorialRift) / 던전 보스 뒤에 나타나는 최후의 군주 결투 장면(doomWave).
-- FieldService 가 너무 커져서(Studio 스크립트 한도 200,000 바이트) 분리했다. FieldService 의 몬스터 표 / 알림 함수 등은 Init 으로 받는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Guard = require(script.Parent:WaitForChild("DamageGuard"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))

local DoomScene = {}

-- FieldService 가 Init 으로 넘겨 주는 것들
local getAliveParts, notify, playSfx, createHealthBar, isDashing, awardNearMiss
local monsters, getMonstersFolder, SoundBank

function DoomScene.Init(deps)
	getAliveParts, notify, playSfx = deps.getAliveParts, deps.notify, deps.playSfx
	createHealthBar, isDashing, awardNearMiss = deps.createHealthBar, deps.isDashing, deps.awardNearMiss
	monsters, getMonstersFolder, SoundBank = deps.monsters, deps.getMonstersFolder, deps.SoundBank
end

-- 최후의 군주 모델: 갑옷 몸통 + 뿔 달린 머리 + 후광 + 칼날 날개 + 거대한 주먹 + 가슴 코어. 몸통(Body)만 맞는다(나머지는 장식).
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local function shakeScreen(player, strength)
	player:SetAttribute("ShakeStrength", strength)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
end

local function buildDoomLord(parent)
	local S = 1.7
	local model = Instance.new("Model")
	model.Name = "DoomLord"
	model.Parent = parent
	local parts = {} -- { Part, Rel }
	local function add(size, rel, color, material, transparency, shape)
		local part = Instance.new("Part")
		part.Size = size * S
		part.Color = color
		part.Material = material or Enum.Material.Metal
		part.Transparency = transparency or 0
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		if shape then part.Shape = shape end
		part.Parent = model
		table.insert(parts, { Part = part, Rel = CFrame.new(rel.Position * S) * (rel - rel.Position) })
		return part
	end
	local red = rgb(255, 50, 60)
	local look = require(game:GetService("ReplicatedStorage"):WaitForChild("LordLook")).Build(add) -- 모양은 오프닝과 같은 모듈 (LordLook)
	local body = look.Body
	body.CanQuery = true
	-- 주변을 도는 칼날 4개
	local orbit = {}
	for k = 1, 4 do
		local blade = add(Vector3.new(1.2, 8, 2.4), CFrame.new(), red, Enum.Material.Neon, 0.1)
		table.insert(orbit, blade)
	end

	local core = body
	local aura = Instance.new("ParticleEmitter")
	aura.Rate = 40
	aura.Lifetime = NumberRange.new(1, 2)
	aura.Speed = NumberRange.new(4, 10)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.LightEmission = 1
	aura.Color = ColorSequence.new(rgb(255, 70, 60), rgb(255, 170, 60))
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	aura.Name = "LordAura"
	aura.Parent = core
	local light = Instance.new("PointLight")
	light.Name = "LordLight"
	light.Color = red
	light.Range = 60
	light.Brightness = 3
	light.Parent = core

	-- 장식 부품은 몸통에 용접한다: 몸통 하나만 움직이면 되므로 매 프레임 50개 넘는 부품의 위치를 클라이언트로 보내지 않는다 (예전엔 이것 때문에 걸을 때 뚝뚝 끊겼다)
	local isBlade = {}
	for _, blade in ipairs(orbit) do isBlade[blade] = true end
	for _, entry in ipairs(parts) do
		if entry.Part ~= body and not isBlade[entry.Part] then
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1, weld.C0 = body, entry.Part, entry.Rel
			weld.Parent = entry.Part
			entry.Part.Anchored = false
			entry.Part.Massless = true
			entry.Part.CFrame = body.CFrame * entry.Rel
		end
	end

	local function place(base, t)
		body.CFrame = base
		for k, blade in ipairs(orbit) do
			local angle = t * 1.8 + k * math.pi / 2
			blade.CFrame = base * CFrame.new(math.cos(angle) * 16 * S, 4 * S + math.sin(angle * 2) * 3, math.sin(angle) * 8 * S) * CFrame.Angles(0, -angle, math.rad(20))
		end
	end
	return model, body, place
end

-- 소환 결투: 먼 하늘 위 심연 무대로 끌려가 최후의 군주와 1:1 (약 8초). 공격할 수 있지만 쓰러뜨릴 수는 없고, 바닥 경고를 보고 피할 수 있는 공격을 받다가 마지막 일격에 쓰러진다.
-- 튜토리얼: 첫 구역 군주를 쓰러뜨리면 군주가 던전 열쇠를 떨어뜨린다 -> 땅이 울리며 임시 던전 문이 솟아오르고 -> 열쇠가 문으로 날아가 -> 문 안으로 빨려 들어간다
local function buildTempGate(position, faceTo)
	local base = CFrame.lookAt(position, Vector3.new(faceTo.X, position.Y, faceTo.Z)) -- 앞면(-Z)이 플레이어를 본다
	local items = {} -- { Part, Rel, Final }
	local function add(name, shape, size, rel, color, material, final)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Color = color
		p.Material = material
		p.Transparency = 1
		p.Parent = workspace
		table.insert(items, { Part = p, Rel = rel, Final = final or 0 })
		return items[#items]
	end
	local B, stone = Enum.PartType.Block, Color3.fromRGB(60, 56, 72)
	for _, side in ipairs({ -1, 1 }) do -- 돌기둥
		add("GatePillar", B, Vector3.new(3.2, 24, 3.2), CFrame.new(side * 12.5, 12, 0), stone, Enum.Material.Slate)
		add("GateRune", B, Vector3.new(0.5, 14, 0.5), CFrame.new(side * 12.5, 12, -1.8), Color3.fromRGB(232, 150, 80), Enum.Material.Neon, 0.25)
	end
	add("GateLintel", B, Vector3.new(29, 3.4, 3.4), CFrame.new(0, 25.2, 0), stone, Enum.Material.Slate)
	add("GateKeystone", B, Vector3.new(3, 3, 3.6), CFrame.new(0, 28, 0), Color3.fromRGB(232, 150, 80), Enum.Material.Neon, 0.2)
	local segments = 20
	for index = 0, segments - 1 do -- 문 가장자리 고리
		local angle = index / segments * math.pi * 2
		add("GateRing", B, Vector3.new(3, 2.2, 1.6), CFrame.new(math.cos(angle) * 9.2, 12 + math.sin(angle) * 9.2, 0) * CFrame.Angles(0, 0, angle), Color3.fromRGB(190, 120, 70), Enum.Material.Neon, 0.3)
	end
	local disc = add("GateDisc", Enum.PartType.Cylinder, Vector3.new(0.5, 17, 17), CFrame.new(0, 12, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(44, 24, 68), Enum.Material.Neon, 0.15)
	local swirlA = add("GateSwirl", Enum.PartType.Cylinder, Vector3.new(0.3, 13, 13), CFrame.new(0, 12, -0.5) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(232, 150, 80), Enum.Material.Neon, 0.45)
	local swirlB = add("GateSwirl", Enum.PartType.Cylinder, Vector3.new(0.3, 8, 8), CFrame.new(0, 12, -0.8) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(150, 100, 210), Enum.Material.Neon, 0.35)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(230, 150, 90)
	light.Range = 40
	light.Brightness = 0
	light.Parent = disc.Part
	local gate = { Base = base, Items = items, Center = (base * CFrame.new(0, 12, 0)).Position, Light = light }
	-- progress: 0..1 로 땅에서 솟아오르며 나타난다. spin: 안쪽 고리가 돈다
	function gate.Set(progress, spin)
		local rise = progress * progress * (3 - 2 * progress)
		for _, item in ipairs(items) do
			local rel = item.Rel
			if item == swirlA then rel = rel * CFrame.Angles(spin * 2.2, 0, 0) elseif item == swirlB then rel = rel * CFrame.Angles(-spin * 3.4, 0, 0) end
			item.Part.CFrame = base * CFrame.new(0, -28 * (1 - rise), 0) * rel
			item.Part.Transparency = item.Final + (1 - item.Final) * (1 - rise)
		end
		light.Brightness = rise * 1.5
	end
	function gate.Destroy()
		for _, item in ipairs(items) do item.Part:Destroy() end
	end
	gate.Set(0, 0)
	return gate
end

local function startTutorialRift(player, at)
	if player:GetAttribute("TutorialRiftBusy") then return end
	player:SetAttribute("TutorialRiftBusy", true)
	local key, gate
	local ok, err = pcall(function()
		local root = getAliveParts(player)
		if not root then print("[튜토리얼 열쇠] 중단: 캐릭터 없음") return end
		print(string.format("[튜토리얼 열쇠] %s 시작", player.Name))
		-- 열쇠 장면 동안은 무적 (보이지 않는 방패): 열쇠를 주우러 가는 사이 주변 몬스터에게 쓰러져 마을로 돌아가던 문제
		local keyShield = Instance.new("ForceField")
		keyShield.Name = "TutorialKeyShield"
		keyShield.Visible = false
		keyShield.Parent = player.Character
		game:GetService("Debris"):AddItem(keyShield, 40)
		notify(player, "🗝 The Lord dropped a dungeon key!")
		Remotes.Tutorial:FireClient(player, "WaypointClear")
		-- 열쇠: 군주가 쓰러진 자리 위에 크게 떠올라 천천히 돈다. 흰색으로 날아가 보이지 않게 진한 주황빛 금색 + 큰 후광 + 바닥 고리 + 불꽃 + 굵은 빛기둥으로 멀리서도 눈에 띄게 한다
		local groundHit = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0))
		local groundY = groundHit and groundHit.Position.Y or (at.Y - 9)
		local keyY = groundY + 11
		local GOLD = Color3.fromRGB(255, 150, 30)
		local function glowPart(name, shape, size, color, transparency)
			local glow = Instance.new("Part")
			glow.Name = name
			glow.Shape = shape
			glow.Size = size
			glow.Color = color
			glow.Material = Enum.Material.Neon
			glow.Transparency = transparency
			glow.Anchored, glow.CanCollide, glow.CanQuery, glow.CanTouch, glow.CastShadow = true, false, false, false, false
			return glow
		end
		key = glowPart("TutorialKey", Enum.PartType.Block, Vector3.new(4, 10, 1.6), GOLD, 0)
		key.CFrame = CFrame.new(at.X, keyY, at.Z)
		key.Parent = workspace
		local aura = glowPart("TutorialKeyAura", Enum.PartType.Ball, Vector3.new(20, 20, 20), Color3.fromRGB(255, 170, 60), 0.78)
		aura.Parent = key
		local ring = glowPart("TutorialKeyRing", Enum.PartType.Cylinder, Vector3.new(0.3, 22, 22), Color3.fromRGB(255, 150, 40), 0.6)
		ring.CFrame = CFrame.new(at.X, groundY + 0.3, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = key
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 160, 70)
		light.Range = 40
		light.Brightness = 2
		light.Parent = key
		local sparks = Instance.new("ParticleEmitter")
		sparks.Rate = 28
		sparks.Lifetime = NumberRange.new(1.2, 2)
		sparks.Speed = NumberRange.new(4, 9)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.LightEmission = 1
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 120, 30))
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
		sparks.Parent = key
		local beam = glowPart("TutorialKeyBeam", Enum.PartType.Cylinder, Vector3.new(170, 6, 6), GOLD, 0.5) -- 멀리서도 보이는 굵은 빛기둥
		beam.CFrame = CFrame.new(at.X, groundY + 85, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		beam.Parent = key
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.new(0, 340, 0, 54)
		tag.StudsOffset = Vector3.new(0, 9, 0)
		tag.AlwaysOnTop = true
		tag.MaxDistance = 600
		tag.Parent = key
		local tagText = Instance.new("TextLabel")
		tagText.Size = UDim2.new(1, 0, 1, 0)
		tagText.BackgroundTransparency = 1
		tagText.Font = Enum.Font.GothamBlack
		tagText.TextSize = 28
		tagText.TextColor3 = Color3.fromRGB(255, 196, 80)
		tagText.TextStrokeColor3 = Color3.fromRGB(60, 24, 0)
		tagText.TextStrokeTransparency = 0
		tagText.Text = "🗝 Lord's Key — go close and pick it up!"
		tagText.Parent = tag
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🗝", Title = "A key dropped!", Text = "A big key fell where the Lord went down. Walk up and grab it!", Duration = 6, Top = true })
		-- 플레이어가 가까이 갈 때까지 기다린다 (제자리에서 천천히 돌며 떠 있다). 너무 오래 안 주우면 열쇠가 스스로 날아온다
		local waitStart, hover = os.clock(), 0
		while true do
			root = getAliveParts(player)
			if not root then return end
			hover += 1 / 60
			key.CFrame = CFrame.new(at.X, keyY + math.sin(hover * 3) * 1.2, at.Z) * CFrame.Angles(0, hover * 2, 0)
			aura.CFrame = key.CFrame
			ring.Transparency = 0.6 + 0.2 * math.sin(hover * 4)
			local near = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude
			if near <= 8 or os.clock() - waitStart > 12 then break end -- (12초 안에 안 주우면 열쇠가 스스로 날아온다: 예전 45초)
			task.wait()
		end
		beam:Destroy()
		tag:Destroy()
		aura:Destroy()
		ring:Destroy()
		sparks.Rate = 0
		-- 주웠다: 열쇠가 손으로 날아온다
		root = getAliveParts(player)
		if not root then return end
		do
			local pickFrom = key.Position
			local pickStart = os.clock()
			while os.clock() - pickStart < 0.5 do
				local t = (os.clock() - pickStart) / 0.5
				root = getAliveParts(player)
				if not root then return end
				key.CFrame = CFrame.new(pickFrom:Lerp(root.Position + Vector3.new(0, 3, 0), t * t)) * CFrame.Angles(0, t * 12, 0)
				task.wait()
			end
		end
		Effects.Burst(key.Position, Color3.fromRGB(255, 210, 130), 40)
		Effects.FloatText(key.Position + Vector3.new(0, 4, 0), "🗝 Got the Lord's Key!", Color3.fromRGB(255, 220, 150))
		notify(player, "🗝 You got the Lord's Key! The key begins to resonate...")
		key:Destroy()
		key = nil
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🗝", Title = "The key glows", Text = "Reacting to the key, a dungeon gate is about to open somewhere...", Duration = 4, Top = true })
		task.wait(0.8)
		root = getAliveParts(player)
		if not root then return end
		-- 땅이 울린다: 점점 세지는 진동 (갑자기 뭔가 나타나지 않게 먼저 알린다)
		for step = 1, 4 do
			shakeScreen(player, 0.15 + step * 0.12)
			task.wait(0.3)
		end
		-- 임시 던전 문이 플레이어 앞에서 땅을 뚫고 솟아오른다
		root = getAliveParts(player)
		if not root then return end
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if look.Magnitude < 0.1 then look = Vector3.new(1, 0, 0) end
		local gatePos = Vector3.new(root.Position.X, root.Position.Y - 3, root.Position.Z) + look.Unit * 34
		gate = buildTempGate(gatePos, root.Position)
		notify(player, "⚠ A dungeon gate bursts up through the ground!")
		local riseStart = os.clock()
		while os.clock() - riseStart < 1.6 do
			local t = (os.clock() - riseStart) / 1.6
			gate.Set(t, os.clock() - riseStart)
			shakeScreen(player, 0.45)
			task.wait(0.05)
		end
		gate.Set(1, 0)
		-- 문이 밝게 열린다 (잠깐 숨을 고르며 문을 보여 준다: 무엇에 끌려가는지 알 수 있게)
		Effects.Burst(gate.Center, Color3.fromRGB(255, 200, 120), 60)
		notify(player, "🌀 The dungeon gate opened — it pulls you in!")
		local openStart = os.clock()
		while os.clock() - openStart < 1.2 do
			gate.Set(1, os.clock() - riseStart)
			task.wait(0.05)
		end
		shakeScreen(player, 0.8)
		-- 빨려 들어간다: 몸을 고정하고 문 쪽으로 점점 빠르게 끌려간다 (제자리에서 흔들리다가 휙)
		root = getAliveParts(player)
		if not root then return end
		root.Anchored = true
		player:SetAttribute("CombatLocked", true) -- 끌려가는 동안은 공격이 나가지 않는다
		local shield = Instance.new("ForceField") -- 무적 (방패 모양은 숨긴다)
		shield.Visible = false
		shield.Parent = player.Character
		local startCF = root.CFrame
		local pullStart = os.clock()
		local pullTime = 3.4
		local blackSent = false
		while os.clock() - pullStart < pullTime do
			local t = (os.clock() - pullStart) / pullTime
			root = getAliveParts(player)
			if not root then break end
			local eased = t * t
			local shakeOffset = Vector3.new(math.sin(os.clock() * 55), math.cos(os.clock() * 47), math.sin(os.clock() * 61)) * (1 - t) * 0.9
			root.CFrame = CFrame.lookAt(startCF.Position:Lerp(gate.Center, eased) + shakeOffset, gate.Center)
			gate.Set(1, os.clock() - riseStart)
			shakeScreen(player, 0.4 + t * 0.5)
			if t > 0.92 and not blackSent then -- 화면은 마지막 순간에만 어두워진다 (그 전에는 문이 다가오는 것이 보이게)
				blackSent = true
				Remotes.Tutorial:FireClient(player, "Cinema", "Black")
			end
			task.wait()
		end
		gate.Destroy()
		gate = nil
		root = getAliveParts(player)
		if root then root.Anchored = false end
		shield:Destroy()
		local leftShield = player.Character and player.Character:FindFirstChild("TutorialKeyShield")
		if leftShield then leftShield:Destroy() end
		player:SetAttribute("CombatLocked", nil)
		print(string.format("[튜토리얼 열쇠] %s 던전 입장 시도 (Zone=%s, TutorialDungeonRun=%s)", player.Name, tostring(player:GetAttribute("Zone")), tostring(player:GetAttribute("TutorialDungeonRun"))))
		Dungeon.Start(player, "Cave", "Easy", nil, nil, true)
		if player:GetAttribute("Zone") ~= "Dungeon" then
			warn("[튜토리얼 열쇠] 던전 입장 실패: Zone=" .. tostring(player:GetAttribute("Zone")) .. " TutorialDungeonLocked=" .. tostring(player:GetAttribute("TutorialDungeonLocked")))
			notify(player, "The dungeon is not open yet. You can enter from the Dungeon Gates in the north of town")
		end
		task.wait(0.5)
		Remotes.Tutorial:FireClient(player, "Cinema", "End")
	end)
	if not ok then
		warn("[튜토리얼 열쇠] 오류: " .. tostring(err))
		if key then key:Destroy() end
		if gate then gate.Destroy() end
		player:SetAttribute("CombatLocked", nil)
		local root = getAliveParts(player)
		if root then
			root.Anchored = false
			for _, child in ipairs(root.Parent:GetChildren()) do
				if child:IsA("ForceField") then child:Destroy() end
			end
		end
		Remotes.Tutorial:FireClient(player, "Cinema", "End")
	end
	player:SetAttribute("TutorialRiftBusy", nil)
end

local doomSlots = {} -- [칸 번호] = true : 동시에 여러 명이 끌려가도 결투장이 겹치지 않게 사람마다 옆으로 떨어뜨린다
local function doomWaveInner(player, zone, center, real)
	local root, humanoid = getAliveParts(player)
	if not root then return end
	player:SetAttribute("InDoomArena", true) -- 납치 연출로 높이 올라가도 "필드 밖으로 튕김" / 구역 판별에 걸리지 않게 처음부터 켠다
	notify(player, real and "⚠⚠ The portal pulls you in... the Final Lord awaits!!" or "⚠⚠ An overwhelming presence... something is calling you!!")
	playSfx(player, "Lord_Voice") -- 낮게 깔리는 군주의 목소리
	-- 끌려가기 전: 땅 / 하늘이 먼저 울린다 (점점 세지는 진동 2.5초). 갑자기 빨려 올라가지 않게 몸도 잠깐 굳는다
	do
		local shakeRoot = getAliveParts(player)
		if shakeRoot then
			shakeRoot.Anchored = true
			player:SetAttribute("CombatLocked", true)
			local shield = Instance.new("ForceField")
			shield.Name = "DoomShield"
			shield.Visible = false
			shield.Parent = player.Character
		end
		for step = 1, 8 do
			player:SetAttribute("ShakeStrength", 0.15 + step * 0.1)
			player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
			task.wait(0.3)
		end
	end
	Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "The Final Lord", Text = real and "...You have conquered all eight lands. Come. This time, I will not hold back." or "...You defeated my servants. Impressive. Now I shall face you myself.", Duration = 5, Top = true })
	player:SetAttribute("ShakeStrength", 0.9)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	local TweenService = game:GetService("TweenService")
	local RunService = game:GetService("RunService")

	-- 연출: 하늘이 어두워지며 거대한 비행체가 나타나 빛줄기로 플레이어를 끌어올린다 (UFO 납치)
	do
		local origin = root.Position
		local abduction = Instance.new("Folder")
		abduction.Name = "DoomAbduction"
		abduction.Parent = workspace
		local function cyl(name, size, cf, color, material, transparency)
			local part = Instance.new("Part")
			part.Name = name
			part.Shape = Enum.PartType.Cylinder
			part.Size = size
			part.CFrame = cf
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.Color = color
			part.Material = material
			part.Transparency = transparency
			part.Parent = abduction
			return part
		end
		local shipCenter = origin + Vector3.new(0, 120, 0)
		local hull = cyl("Hull", Vector3.new(10, 90, 90), CFrame.new(shipCenter) * CFrame.Angles(0, 0, math.rad(90)), rgb(30, 22, 40), Enum.Material.Metal, 1)
		local dome = cyl("Dome", Vector3.new(14, 40, 40), CFrame.new(shipCenter + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(120, 20, 40), Enum.Material.Neon, 1)
		local rim = cyl("Rim", Vector3.new(2, 96, 96), CFrame.new(shipCenter + Vector3.new(0, -4, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 60, 70), Enum.Material.Neon, 1)
		local column = cyl("Beam", Vector3.new(120, 12, 12), CFrame.new(origin + Vector3.new(0, 55, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 120, 130), Enum.Material.Neon, 1)
		local groundRing = cyl("GroundRing", Vector3.new(0.4, 60, 60), CFrame.new(origin + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 80, 90), Enum.Material.Neon, 1)
		for _, part in ipairs({ hull, dome, rim }) do
			TweenService:Create(part, TweenInfo.new(1.2), { Transparency = part == hull and 0 or 0.1 }):Play()
		end
		notify(player, "⚠ Something huge descends from the sky...!")
		shakeScreen(player, 0.5)
		task.wait(1.0)
		TweenService:Create(column, TweenInfo.new(0.5), { Transparency = 0.45, Size = Vector3.new(120, 16, 16) }):Play()
		TweenService:Create(groundRing, TweenInfo.new(1.2), { Transparency = 0.3, Size = Vector3.new(0.4, 18, 18) }):Play()
		local pull = Instance.new("ParticleEmitter") -- 빛줄기 안에서 위로 빨려 올라가는 입자
		pull.Rate = 60
		pull.Lifetime = NumberRange.new(1, 1.6)
		pull.Speed = NumberRange.new(14, 22)
		pull.EmissionDirection = Enum.NormalId.Top
		pull.SpreadAngle = Vector2.new(15, 15)
		pull.LightEmission = 1
		pull.Color = ColorSequence.new(rgb(255, 140, 150))
		pull.Size = NumberSequence.new(1.2, 0)
		pull.Parent = column
		local r0, h0 = getAliveParts(player)
		if r0 and h0.Health > 0 then
			r0.Anchored = true
			r0.AssemblyLinearVelocity = Vector3.zero
			local started = os.clock()
			local duration = 2.0
			while os.clock() - started < duration do
				local t = (os.clock() - started) / duration
				local rr = getAliveParts(player)
				if not rr then break end
				local eased = t * t * (3 - 2 * t)
				rr.CFrame = CFrame.new(origin + Vector3.new(0, 4 + eased * 78, 0)) * CFrame.Angles(math.rad(eased * 25), math.rad(t * 540), 0)
				task.wait()
			end
		end
		shakeScreen(player, 0.9)
		Effects.Burst(origin + Vector3.new(0, 82, 0), rgb(255, 120, 130), 120)
		task.wait(0.25)
		abduction:Destroy()
	end
	root, humanoid = getAliveParts(player)
	local function unlockCombat() -- 납치되는 동안의 공격 불가 / 무적을 푼다 (결투장에 도착하면 공격할 수 있다)
		player:SetAttribute("CombatLocked", nil)
		local shield = player.Character and player.Character:FindFirstChild("DoomShield")
		if shield then shield:Destroy() end
	end
	if not root or humanoid.Health <= 0 then
		player:SetAttribute("InDoomArena", nil)
		unlockCombat()
		return
	end
	root.Anchored = false
	unlockCombat()
	local arena = Instance.new("Folder")
	arena.Name = "DoomArena"
	arena.Parent = workspace
	local function disc(name, diameter, height, y, color, material, transparency)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(height, diameter, diameter)
		part.CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Anchored = true
		part.CanCollide = name == "DoomFloor"
		part.Color = color
		part.Material = material
		part.Transparency = transparency or 0
		part.Parent = arena
		return part
	end
	disc("DoomFloor", 150, 2, 0, rgb(34, 36, 52), Enum.Material.Slate) -- 어두운 청회색 바닥: 붉은 경고 원과 내 탄이 또렷하게 보이게 (밝은 바닥은 붉은 조명을 받아 온통 붉게 보였다)
	-- 가장자리 붉은 띠: (예전에는 154짜리 원판 하나가 바닥 전체를 붉게 덮고 있었다) 붉은 원판 위에 바닥색 원판을 덮어 테두리 띠만 남긴다
	disc("DoomRim", 154, 0.4, 1.1, rgb(255, 60, 60), Enum.Material.Neon, 0.4)
	disc("DoomRimCover", 148, 0.5, 1.15, rgb(34, 36, 52), Enum.Material.Slate)
	disc("DoomRune", 90, 0.2, 1.2, rgb(60, 50, 90), Enum.Material.SmoothPlastic, 0.55)
	disc("DoomRuneInner", 46, 0.2, 1.3, rgb(120, 110, 150), Enum.Material.SmoothPlastic, 0.5)

	-- 둘레 보이지 않는 높은 벽 (뛰어내릴 수 없게) + 둘레를 둘러싼 검은 첨탑과 불꽃 + 하늘의 붉은 달
	for index = 0, 23 do
		local angle = index / 24 * math.pi * 2
		local at = center + Vector3.new(math.cos(angle) * 78, 0, math.sin(angle) * 78)
		local wall = Instance.new("Part")
		wall.Name = "DoomWall"
		wall.Size = Vector3.new(26, 160, 4)
		wall.CFrame = CFrame.lookAt(at + Vector3.new(0, 70, 0), center + Vector3.new(0, 70, 0))
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.Parent = arena
		local height = 26 + (index % 3) * 14
		local spire = Instance.new("Part")
		spire.Name = "DoomSpire"
		spire.Size = Vector3.new(6, height, 6)
		spire.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 84, height / 2 - 2, math.sin(angle) * 84)) * CFrame.Angles(math.rad((index % 2) * 6), angle, math.rad(((index + 1) % 3) * 4))
		spire.Anchored = true
		spire.CanCollide = false
		spire.CanQuery = false
		spire.Color = rgb(22, 12, 24)
		spire.Material = Enum.Material.Slate
		spire.Parent = arena
		if index % 2 == 0 then
			local flame = Instance.new("Part")
			flame.Shape = Enum.PartType.Ball
			flame.Size = Vector3.new(3, 3, 3)
			flame.Position = spire.Position + Vector3.new(0, height / 2 + 2, 0)
			flame.Anchored = true
			flame.CanCollide = false
			flame.CanQuery = false
			flame.Color = rgb(255, 90, 50)
			flame.Material = Enum.Material.Neon
			flame.Parent = arena
			if index % 4 == 0 then -- (불꽃 / 조명은 4개에 하나만: 화면이 무거워 걸을 때 끊기던 원인 후보)
				local fire = Instance.new("Fire")
				fire.Size = 10
				fire.Heat = 8
				fire.Color = rgb(255, 120, 50)
				fire.SecondaryColor = rgb(160, 20, 30)
				fire.Parent = flame
				local lamp = Instance.new("PointLight")
				lamp.Color = rgb(255, 100, 60)
				lamp.Range = 40
				lamp.Brightness = 2
				lamp.Parent = flame
			end
		end
	end
	local moon = Instance.new("Part")
	moon.Name = "DoomMoon"
	moon.Shape = Enum.PartType.Ball
	moon.Size = Vector3.new(260, 260, 260)
	moon.Position = center + Vector3.new(0, 260, -520)
	moon.Anchored = true
	moon.CanCollide = false
	moon.CanQuery = false
	moon.Color = rgb(200, 25, 40)
	moon.Material = Enum.Material.Neon
	moon.Parent = arena
	for index = 1, 14 do -- 떠다니는 바위 조각
		local rock = Instance.new("Part")
		rock.Name = "DoomRock"
		local size = 6 + (index * 7) % 14
		rock.Size = Vector3.new(size, size * 0.8, size)
		local angle = index * 2.4
		rock.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * (110 + index * 6), 20 + (index * 13) % 70, math.sin(angle) * (110 + index * 6))) * CFrame.Angles(angle, angle * 2, 0)
		rock.Anchored = true
		rock.CanCollide = false
		rock.CanQuery = false
		rock.Color = rgb(30, 18, 30)
		rock.Material = Enum.Material.Basalt
		rock.Parent = arena
	end

	-- (보강) 결투장 꾸밈: 가장자리 부서진 기둥 / 하늘에 떠 있는 거대한 돌 고리 / 군주 뒤 왕좌. 전부 충돌 없음, 빛나지 않음
	do
		local function slab(name, size, cf, color, material)
			local part = Instance.new("Part")
			part.Name = name
			part.Size = size
			part.CFrame = cf
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
			part.Color = color
			part.Material = material
			part.Parent = arena
			return part
		end
		local rngA = Random.new(4242)
		for index = 0, 7 do -- 가장자리 부서진 기둥 (반지름 72)
			local angle = (index + 0.5) / 8 * math.pi * 2
			local h = rngA:NextNumber(6, 16)
			local at = center + Vector3.new(math.cos(angle) * 72, 1 + h / 2, math.sin(angle) * 72)
			slab("DoomPillar", Vector3.new(4.5, h, 4.5), CFrame.new(at) * CFrame.Angles(rngA:NextNumber(-0.08, 0.08), angle, rngA:NextNumber(-0.12, 0.12)), rgb(38, 30, 44), Enum.Material.Slate)
			slab("DoomPillarTop", Vector3.new(5.4, 1.2, 5.4), CFrame.new(at + Vector3.new(0, h / 2 + 0.4, 0)) * CFrame.Angles(rngA:NextNumber(-0.25, 0.25), angle, rngA:NextNumber(-0.25, 0.25)), rgb(30, 24, 36), Enum.Material.Slate)
		end
		for index = 0, 17 do -- 하늘의 거대한 돌 고리 (군주 머리 위로 비스듬히): 끊어진 조각들
			if index % 6 ~= 5 then
				local angle = index / 18 * math.pi * 2
				local ringCenter = center + Vector3.new(0, 78, -40)
				local at = ringCenter + CFrame.Angles(math.rad(70), 0, 0):VectorToWorldSpace(Vector3.new(math.cos(angle) * 70, 0, math.sin(angle) * 70))
				slab("DoomSkyRing", Vector3.new(22, 5, 7), CFrame.lookAt(at, ringCenter) * CFrame.Angles(0, math.rad(90), 0), rgb(32, 22, 36), Enum.Material.Basalt)
			end
		end
		-- 군주 뒤 왕좌 (등받이 + 팔걸이)
		local throne = center + Vector3.new(0, 0, -74)
		slab("DoomThroneBack", Vector3.new(30, 52, 6), CFrame.new(throne + Vector3.new(0, 26, 0)), rgb(28, 18, 30), Enum.Material.Slate)
		for _, side in ipairs({ -1, 1 }) do
			slab("DoomThroneSpike", Vector3.new(4, 30, 4), CFrame.new(throne + Vector3.new(side * 13, 60, 0)) * CFrame.Angles(0, 0, math.rad(side * -12)), rgb(40, 26, 40), Enum.Material.Slate)
			slab("DoomThroneArm", Vector3.new(6, 14, 16), CFrame.new(throne + Vector3.new(side * 18, 7, 6)), rgb(34, 22, 36), Enum.Material.Slate)
		end
	end

	local model, body, place = buildDoomLord(arena)
	for _, item in ipairs(arena:GetDescendants()) do -- 그림자 계산이 가장 무겁다: 결투장 장식은 전부 그림자를 끈다
		if item:IsA("BasePart") then item.CastShadow = false end
	end
	local bossPos = center + Vector3.new(0, 34, -48)
	place(CFrame.lookAt(bossPos, bossPos + Vector3.new(0, 0, 1)), 0)

	-- 맞출 수 있는 몬스터로 등록한다 (체력이 바닥나지 않게 8% 밑으로는 안 떨어진다)
	local fill = createHealthBar(body, real and "💀 The Final Lord" or "💀 Lv.???  ???", 360, rgb(255, 90, 90))
	local function lordSfx(key) -- 군주가 기를 모을 때 / 쏠 때 나는 웅장한 소리 (군주 몸에서 난다)
		if body.Parent and SoundBank.Has(key) then SoundBank.Play(body, key) end
	end
	body.Parent = getMonstersFolder() -- 필드 몬스터 폴더에 두어야 총알 판정 / 자동 조준이 잡는다 (장식 부품은 모델에 남는다)
	CollectionService:AddTag(body, "Monster")
	CollectionService:AddTag(body, "RadarBoss")
	local data = {
		Static = true, Invincible = true, Doom = true, Zone = 1, Aggro = true, Goblin = false,
		Health = 1e9, MaxHealth = 1e9, HealthFill = fill, Contrib = {}, Level = 1, XpLevel = 1,
		Stats = { Size = 20, MaxHealth = 1e9, Speed = 0, ShotDamage = 0, ShotInterval = 99, ShotSpeed = 0, Gold = 0 },
		Home = bossPos, BossLike = true, Kind = "DoomLord",
	}
	monsters[body] = data

	player.Character:PivotTo(CFrame.lookAt(center + Vector3.new(0, 4, 36), center + Vector3.new(0, 4, -48)))
	root.AssemblyLinearVelocity = Vector3.zero
	player:SetAttribute("InDoomArena", true)
	player:SetAttribute("UltCharge", Config.Skills.Ult.Cost) -- 궁극기(V)를 써볼 수 있게 게이지를 가득 채워 둔다
	notify(player, real and "💀 The Final Lord! This time your attacks count — dodge the warnings and bring him down!" or "💀 You face the Final Lord! Your attacks land, but... you cannot defeat him. Dodge the red warnings on the floor, and try your V ultimate too!")
	Effects.Burst(bossPos, rgb(255, 70, 60), 100)

	-- 진짜 결전: 화면 위쪽에 군주 체력바를 고정해서 보여 준다 (머리 위 체력바는 높이 떠 있어서 화면 밖으로 나간다)
	local hudGui, hudFill, hudText
	local playerGui = real and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		hudGui = Instance.new("ScreenGui")
		hudGui.Name = "LordBarHUD"
		hudGui.ResetOnSpawn = false
		hudGui.DisplayOrder = 40
		local frame = Instance.new("Frame")
		frame.AnchorPoint, frame.Position, frame.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 20), UDim2.new(0.5, 0, 0, 30)
		frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = rgb(20, 12, 22), 0.15, 0
		frame.Parent = hudGui
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize, limit.MinSize = Vector2.new(620, 30), Vector2.new(260, 30)
		limit.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color, stroke.Thickness = rgb(255, 90, 90), 1.5
		stroke.Parent = frame
		hudFill = Instance.new("Frame")
		hudFill.Size, hudFill.BackgroundColor3, hudFill.BorderSizePixel = UDim2.new(1, 0, 1, 0), rgb(220, 50, 60), 0
		hudFill.Parent = frame
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 8)
		fillCorner.Parent = hudFill
		hudText = Instance.new("TextLabel")
		hudText.Size, hudText.BackgroundTransparency, hudText.ZIndex = UDim2.new(1, 0, 1, 0), 1, 3
		hudText.Font, hudText.TextSize, hudText.TextColor3 = Enum.Font.GothamBlack, 15, Color3.new(1, 1, 1)
		hudText.TextStrokeTransparency = 0.4
		hudText.Text = "💀 The Final Lord"
		hudText.Parent = frame
		hudGui.Parent = playerGui
	end
	local fightChar = player.Character -- (쓰러져 마을에서 다시 태어난 몸은 "살아 있음"으로 치지 않는다: 패턴이 마을까지 이어지지 않게)
	local alive = function()
		local r, h = getAliveParts(player)
		return r ~= nil and h.Health > 0 and player.Character == fightChar
	end
	local running, clock = true, 0
	local diagAt, diagFrames = 0, 0
	local ownerCheckAt = 0
	local approach = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if clock - ownerCheckAt >= 1 then -- 결투장에서 내 캐릭터의 물리 소유권이 서버로 넘어가 있으면(서버 속도 16 으로 움직여 느리고 끊긴다) 다시 내 것으로 돌려준다
			ownerCheckAt = clock
			local r = getAliveParts(player)
			if r and not r.Anchored then
				local okOwner, who = pcall(function() return r:GetNetworkOwner() end)
				if okOwner and who ~= player then
					local okSet, err = pcall(function() r:SetNetworkOwner(player) end)
					if not okSet then warn("[군주전] 네트워크 소유권 복구 실패: " .. tostring(err)) end
				end
			end
		end
		if RunService:IsStudio() then -- 진단 (Studio 전용): 군주전에서 이동이 느리고 끊기는 원인을 찾기 위한 출력. 3초마다 한 줄
			diagFrames += 1
			if clock - diagAt >= 3 then
				local r, h = getAliveParts(player)
				local owner = "?"
				if r then
					local okOwner, who = pcall(function() return r:GetNetworkOwner() end)
					owner = okOwner and (who and who.Name or "SERVER") or "n/a"
				end
				print(string.format("[군주전 진단] 서버 FPS %.0f · 부품 %d · 네트워크 소유자 %s · 속도 %.1f · WalkSpeed(서버값) %s · Anchored %s",
					diagFrames / (clock - diagAt), #arena:GetDescendants(), owner, r and r.AssemblyLinearVelocity.Magnitude or -1, h and tostring(h.WalkSpeed) or "-", r and tostring(r.Anchored) or "-"))
				diagAt, diagFrames = clock, 0
			end
		end
		if not running or not body.Parent then
			if hudGui then hudGui:Destroy() end
			connection:Disconnect()
			return
		end
		if hudFill and data.MaxHealth > 1e6 and data.MaxHealth < 1e9 then -- (진짜 결전에서만: 체력이 정해지면 표시)
			local ratio = math.clamp(data.Health / data.MaxHealth, 0, 1)
			hudFill.Size = UDim2.new(ratio, 0, 1, 0)
			hudText.Text = string.format("💀 The Final Lord  %d%%", math.ceil(ratio * 100))
		end
		approach = math.min(1, approach + dt / 16)
		local target = alive() and select(1, getAliveParts(player)).Position or center
		local pos = bossPos:Lerp(center + Vector3.new(0, 30, -26), approach) + Vector3.new(0, math.sin(clock * 1.6) * 2.5, 0)
		local flat = Vector3.new(target.X, pos.Y, target.Z)
		place(CFrame.lookAt(pos, flat), clock)
		data.Home = pos
		if not data.Scratched and (data.DoomHits or 0) >= 6 and alive() then -- 내 공격이 닿았다: 군주가 잠깐 반응한다
			data.Scratched = true
			Effects.Burst(body.Position + Vector3.new(0, 6, -8), rgb(255, 235, 170), 60)
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "The Final Lord", Text = "...How dare you.", Duration = 2.5, Top = true })
			player:SetAttribute("ShakeStrength", 0.5)
			player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
		end
	end)

	local function beam(from, to, thickness, duration, color)
		local length = (to - from).Magnitude
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = Enum.Material.Neon
		part.Color = color or rgb(255, 80, 60)
		part.Size = Vector3.new(thickness, thickness, length)
		part.CFrame = CFrame.lookAt((from + to) / 2, to)
		part.Parent = arena
		TweenService:Create(part, TweenInfo.new(duration), { Transparency = 1, Size = Vector3.new(0.1, 0.1, length) }):Play()
	end
	local function ring(at, radius, color, duration)
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.4, 2, 2)
		part.CFrame = CFrame.new(at.X, center.Y + 1.4, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Transparency = 0.2
		part.Parent = arena
		TweenService:Create(part, TweenInfo.new(duration), { Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 1 }):Play()
	end
	local function shake(strength)
		player:SetAttribute("ShakeStrength", strength)
		player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	end

	-- 하늘에서 내리꽂히는 붉은 기둥 (겉은 짙은 진홍, 속은 주황빛) + 바닥에 남는 그을음. 눈이 부시지 않게 흰색은 쓰지 않는다.
	local function pillar(at, radius)
		local function column(width, color, transparency, duration)
			local part = Instance.new("Part")
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(320, width, width)
			part.CFrame = CFrame.new(at.X, center.Y + 160, at.Z) * CFrame.Angles(0, 0, math.rad(90))
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			part.Material = Enum.Material.Neon
			part.Color = color
			part.Transparency = transparency
			part.Parent = arena
			TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad), { Transparency = 1, Size = Vector3.new(320, width * 0.15, width * 0.15) }):Play()
		end
		column(radius * 1.7, rgb(190, 40, 52), 0.25, 0.6)
		column(radius * 0.8, rgb(255, 150, 100), 0.1, 0.45)
		local scorch = Instance.new("Part")
		scorch.Shape = Enum.PartType.Cylinder
		scorch.Size = Vector3.new(0.3, radius * 2, radius * 2)
		scorch.CFrame = CFrame.new(at.X, center.Y + 1.2, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		scorch.Anchored = true
		scorch.CanCollide = false
		scorch.CanQuery = false
		scorch.CastShadow = false
		scorch.Material = Enum.Material.Neon
		scorch.Color = rgb(150, 30, 36)
		scorch.Transparency = 0.45
		scorch.Parent = arena
		TweenService:Create(scorch, TweenInfo.new(2, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
		task.delay(2.1, function() scorch:Destroy() end)
	end

	-- 한 번의 폭격: 바닥에 붉은 경고 원 -> 시간이 지나면 군주의 광선이 내리꽂힌다 (맞으면 최대 체력의 일부, 죽지는 않는다)
	local function strike(at, radius, telegraph, percent, lethal)
		-- 경고는 클라이언트가 그린다 (Effects.Warn): 가장자리 원 + 안쪽에서 차오르는 원. 다 차는 순간 광선이 내리꽂힌다
		Effects.Warn(Vector3.new(at.X, center.Y + 1.3, at.Z), radius, telegraph, rgb(255, 60, 50))
		lordSfx("Lord_Charge")
		task.delay(telegraph, function()
			if not arena.Parent then return end
			lordSfx("Lord_Blast")
			beam(body.Position + Vector3.new(0, 4, -6), at + Vector3.new(0, 1, 0), radius * 0.28, 0.35)
			pillar(at, radius)
			ring(at, radius * 1.1, rgb(255, 120, 60), 0.6)
			task.delay(0.12, function() if arena.Parent then ring(at, radius * 1.9, rgb(200, 50, 60), 0.8) end end)
			Effects.Burst(at + Vector3.new(0, 2, 0), rgb(255, 90, 60), 60)
			Effects.Burst(at + Vector3.new(0, 14, 0), rgb(255, 170, 110), 30)
			shake(0.6)
			local r2, h2 = getAliveParts(player)
			if r2 and h2.Health > 0 and data.Health > 0 and alive() then -- (군주가 쓰러진 뒤 남은 폭격에 맞아 승리가 패배로 바뀌지 않게)
				local gap = (Vector3.new(r2.Position.X, center.Y, r2.Position.Z) - at).Magnitude
				if gap <= radius then
					local dmg = lethal and (h2.MaxHealth * percent) or math.min(h2.MaxHealth * percent, h2.Health - 1) -- (진짜 결전에서는 죽을 수 있다)
					if dmg > 0 then Guard.Take(h2, dmg) end
				elseif gap <= radius + 16 and isDashing(r2, player) then
					awardNearMiss(player, r2) -- 경고 원 바로 밖으로 대시로 빠져나갔다
				end
			end
		end)
	end
	local function playerAt()
		local r = select(1, getAliveParts(player))
		return r and Vector3.new(r.Position.X, center.Y, r.Position.Z) or center
	end

	-- ================= 진짜 결전 (8구역 이후 포탈): 체력이 실제로 줄고, 단계마다 패턴이 늘어난다 =================
	if real then
		local FL = Config.FinalLord
		local maxHealth = FL.Health
		data.Invincible, data.Doom, data.Kind, data.Ambush, data.Zone = false, false, "FinalLord", true, 8 -- (Ambush: 쓰러져도 다시 나타나지 않는다)
		data.Health, data.MaxHealth = maxHealth, maxHealth
		data.Stats.MaxHealth = maxHealth
		data.HealthFill.Size = UDim2.new(1, 0, 1, 0)
		local function bossAlive() return body.Parent ~= nil and data.Health > 0 end
		local function fraction() return math.max(0, data.Health) / maxHealth end
		local function flat(v) return Vector3.new(v.X, 0, v.Z) end
		local dmgMult = 1 -- 3단계 / 격노(4분 경과)에서 커진다
		local function hurt(percent, text)
			if not bossAlive() then return end -- (군주가 쓰러진 뒤에는 남은 패턴이 피해를 주지 않는다)
			local r2, h2 = getAliveParts(player)
			if r2 and h2.Health > 0 and alive() then
				Guard.Take(h2, h2.MaxHealth * percent * dmgMult)
				if text then notify(player, text) end
			end
		end
		local function distToSegment(p, a, b)
			local ab, ap = flat(b - a), flat(p - a)
			local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 0.001), 0, 1)
			return (ap - ab * t).Magnitude
		end
		local function floorPart(size, cframe, color, transparency)
			local part = Instance.new("Part")
			part.Size = size
			part.CFrame = cframe
			part.Anchored, part.CanCollide, part.CanQuery, part.CastShadow = true, false, false, false
			part.Material = Enum.Material.Neon
			part.Color = color
			part.Transparency = transparency
			part.Parent = arena
			return part
		end
		local floorY = center.Y + 1.35
		local phaseNow = 1

		-- 패턴 1) 좁은 간격의 3연 폭격 (플레이어 주변)
		local function tripleStrike()
			for k = 1, 3 do
				if not alive() then return end
				strike(playerAt() + Vector3.new((k - 2) * 20, 0, 0), 13, 1.1, 0.2, true)
				task.wait(0.32)
			end
			task.wait(1.4)
		end

		-- 패턴 2) 플레이어를 둘러싼 고리 (한 군데는 비어 있다) + 한가운데 큰 일격
		local function ringOfRuin()
			shake(0.5)
			local around = playerAt()
			local gap = math.random(7)
			for k = 1, 7 do
				if k ~= gap then
					local angle = k / 7 * math.pi * 2
					strike(around + Vector3.new(math.cos(angle) * 34, 0, math.sin(angle) * 34), 13, 1.1, 0.17, true)
				end
				task.wait(0.12)
			end
			task.wait(0.5)
			if alive() then strike(around, 21, 1.0, 0.28, true) end
			task.wait(1.6)
		end

		-- 패턴 3) 회전하는 두 갈래 광선 (바닥에 경고 -> 광선이 되어 반원을 훑는다)
		local function sweepBeam()
			local pivot = Vector3.new(center.X, floorY, center.Z)
			local length, width = 82, 7
			local base = math.random() * math.pi
			local sign = math.random() < 0.5 and 1 or -1
			local arms = {}
			for _ = 1, 2 do arms[#arms + 1] = floorPart(Vector3.new(width, 0.4, length), CFrame.new(pivot), rgb(255, 60, 50), 0.65) end
			local function place(angle)
				for index, arm in ipairs(arms) do
					local dir = Vector3.new(math.cos(angle + (index - 1) * math.pi), 0, math.sin(angle + (index - 1) * math.pi))
					arm.CFrame = CFrame.lookAt(pivot + dir * (length / 2), pivot + dir * length)
				end
			end
			place(base)
			for _, arm in ipairs(arms) do TweenService:Create(arm, TweenInfo.new(1.3), { Transparency = 0.15 }):Play() end
			lordSfx("Lord_Charge")
			task.wait(1.4)
			for _, arm in ipairs(arms) do arm.Color, arm.Transparency = rgb(255, 170, 70), 0.05 end
			lordSfx("Lord_Blast")
			local started, duration, hitAt = os.clock(), 3.0, 0
			while os.clock() - started < duration and alive() and bossAlive() do
				local t = (os.clock() - started) / duration
				local angle = base + sign * t * math.pi * 1.1
				place(angle)
				local r2 = select(1, getAliveParts(player))
				if r2 and os.clock() - hitAt > 0.8 then
					for index = 1, 2 do
						local dir = Vector3.new(math.cos(angle + (index - 1) * math.pi), 0, math.sin(angle + (index - 1) * math.pi))
						if distToSegment(r2.Position, pivot, pivot + dir * length) <= width / 2 + 1.5 then
							hitAt = os.clock()
							hurt(0.3, "💥 Caught by the beam!")
							shake(0.6)
							break
						end
					end
				end
				if math.floor(t * 10) ~= math.floor((t - 0.02) * 10) then Effects.Burst(pivot + Vector3.new(math.cos(angle) * 40, 2, math.sin(angle) * 40), rgb(255, 150, 80), 10) end
				task.wait()
			end
			for _, arm in ipairs(arms) do
				TweenService:Create(arm, TweenInfo.new(0.35), { Transparency = 1 }):Play()
				task.delay(0.4, function() arm:Destroy() end)
			end
			task.wait(0.8)
		end

		-- 패턴 4) 유성 폭풍 (아레나 곳곳에 경고 원이 줄줄이)
		local function meteorStorm()
			shake(0.4)
			for _ = 1, 14 do
				if not alive() or not bossAlive() then return end
				local angle, distance = math.random() * math.pi * 2, math.random() * 58
				local at = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
				if math.random() < 0.4 then at = playerAt() + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8)) end -- 일부는 내 쪽으로
				strike(at, 10, 1.35, 0.14, true)
				task.wait(0.22)
			end
			task.wait(1.8)
		end

		-- 패턴 5) 가로 / 세로 띠 (다섯 줄 중 한 줄만 비어 있다)
		local function lanes()
			local vertical = math.random() < 0.5
			local safe = math.random(5)
			local bands = {}
			for lane = 1, 5 do
				local offset = (lane - 3) * 26
				local size = vertical and Vector3.new(16, 0.4, 150) or Vector3.new(150, 0.4, 16)
				local at = center + (vertical and Vector3.new(offset, 0, 0) or Vector3.new(0, 0, offset))
				if lane ~= safe then
					local band = floorPart(size, CFrame.new(at.X, floorY, at.Z), rgb(255, 60, 50), 0.7)
					TweenService:Create(band, TweenInfo.new(1.6), { Transparency = 0.12 }):Play()
					bands[#bands + 1] = { Part = band, Offset = offset }
				else
				end
			end
			lordSfx("Lord_Charge")
			task.wait(1.7)
			if not arena.Parent then return end
			lordSfx("Lord_Blast")
			shake(0.7)
			local r2 = alive() and select(1, getAliveParts(player))
			for _, band in ipairs(bands) do
				band.Part.Color = rgb(255, 170, 70)
				band.Part.Transparency = 0.02
				TweenService:Create(band.Part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				task.delay(0.65, function() band.Part:Destroy() end)
				for step = -2, 2 do
					local along = step * 30
					local at = center + (vertical and Vector3.new(band.Offset, 0, along) or Vector3.new(along, 0, band.Offset))
					Effects.Burst(at + Vector3.new(0, 3, 0), rgb(255, 120, 60), 24)
				end
				if r2 then
					local local1 = vertical and (r2.Position.X - center.X) or (r2.Position.Z - center.Z)
					if math.abs(local1 - band.Offset) <= 8 then
						hurt(0.28, "💥 Burned by the wall of fire!")
						r2 = nil -- (한 번에 한 줄만 맞는다)
					end
				end
			end
			task.wait(1.4)
		end

		-- 패턴 6) 쫓아오는 불덩이 (느리게 따라온다: 맞으면 사라진다)
		local function orbBarrage()
			local orbs = {}
			for index = 1, 9 do
				local angle = index / 9 * math.pi * 2
				local orb = floorPart(Vector3.new(4, 4, 4), CFrame.new(body.Position + Vector3.new(math.cos(angle) * 8, -4, math.sin(angle) * 8)), rgb(255, 80, 60), 0.05)
				orb.Shape = Enum.PartType.Ball
				orbs[#orbs + 1] = orb
			end
			lordSfx("Lord_Charge")
			local started = os.clock()
			local last = started
			while os.clock() - started < 5.5 and alive() and bossAlive() do
				local now = os.clock()
				local dt = now - last
				last = now
				local r2 = select(1, getAliveParts(player))
				for index = #orbs, 1, -1 do
					local orb = orbs[index]
					if r2 then
						local to = Vector3.new(r2.Position.X, floorY + 3, r2.Position.Z) - orb.Position
						local speed = 24 + (now - started) * 2.5
						if to.Magnitude < 4 then
							Effects.Burst(orb.Position, rgb(255, 90, 60), 40)
							hurt(0.14, "💥 A fireball hit you!")
							orb:Destroy()
							table.remove(orbs, index)
						elseif now - started > 0.6 then
							orb.Position += to.Unit * math.min(to.Magnitude, speed * dt)
						else
							orb.Position += Vector3.new(0, 7 * dt, 0) + (orb.Position - body.Position).Unit * 6 * dt
						end
					end
				end
				task.wait()
			end
			for _, orb in ipairs(orbs) do
				Effects.Burst(orb.Position, rgb(255, 120, 70), 14)
				orb:Destroy()
			end
			task.wait(0.8)
		end

		-- 패턴 7) 최후의 심판 (3단계): 아레나가 붉게 물든다. 초록 원 안에 들어가 있어야 산다
		local function judgement()
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "The Final Lord", Text = "Perish.", Duration = 2.5, Top = true })
			shake(0.7)
			lordSfx("Lord_Charge")
			local flood = floorPart(Vector3.new(0.4, 150, 150), CFrame.new(center.X, floorY + 0.05, center.Z) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 30, 30), 0.88)
			flood.Shape = Enum.PartType.Cylinder
			local safes = {}
			for _ = 1, 3 do
				local at
				for _ = 1, 20 do
					local angle, distance = math.random() * math.pi * 2, 14 + math.random() * 40
					at = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
					local clear = true
					for _, other in ipairs(safes) do
						if (other - at).Magnitude < 32 then clear = false end
					end
					if clear then break end
				end
				safes[#safes + 1] = at
				local ringPart = floorPart(Vector3.new(0.5, 30, 30), CFrame.new(at.X, floorY + 0.1, at.Z) * CFrame.Angles(0, 0, math.rad(90)), rgb(110, 255, 170), 0.5)
				ringPart.Shape = Enum.PartType.Cylinder
				task.delay(3.4, function() ringPart:Destroy() end)
			end
			TweenService:Create(flood, TweenInfo.new(3.2), { Transparency = 0.7 }):Play()
			task.wait(3.2)
			if not arena.Parent then flood:Destroy() return end
			lordSfx("Lord_Blast")
			shake(1)
			local r2 = alive() and select(1, getAliveParts(player))
			local safeNow = false
			if r2 then
				for _, at in ipairs(safes) do
					if (flat(r2.Position) - flat(at)).Magnitude <= 15 then safeNow = true end
				end
			end
			for _, at in ipairs(safes) do ring(at, 22, rgb(110, 255, 170), 0.8) end
			ring(center, 80, rgb(255, 90, 60), 1.0)
			Effects.Burst(center + Vector3.new(0, 10, 0), rgb(255, 120, 80), 140)
			if r2 and not safeNow then hurt(0.75, "💥 Judgement struck you down!") elseif r2 then notify(player, "✅ Survived the judgement!") end
			TweenService:Create(flood, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			task.delay(0.6, function() flood:Destroy() end)
			task.wait(1.4)
		end

		-- 패턴 8) 충격파 고리: 군주 발밑에서 바닥 고리가 3번 퍼져 나온다. 고리가 지나갈 때 대시로 넘어야 한다 (대시 중이면 안 맞는다)
		local function shockwaves()
			lordSfx("Lord_Charge")
			shake(0.5)
			local origin = Vector3.new(body.Position.X, floorY, body.Position.Z)
			task.wait(1.0)
			for wave = 1, 3 do
				if not alive() or not bossAlive() then return end
				lordSfx("Lord_Blast")
				local ringPart = floorPart(Vector3.new(1.2, 2, 2), CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 110, 60), 0.2)
				ringPart.Shape = Enum.PartType.Cylinder
				local inner = floorPart(Vector3.new(1.3, 1, 1), CFrame.new(origin + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(40, 14, 22), 0)
				inner.Shape = Enum.PartType.Cylinder
				local speed, band = 38 + wave * 6, 4.5
				local started, hit = os.clock(), false
				while os.clock() - started < 2.6 and alive() do
					local radius = (os.clock() - started) * speed
					ringPart.Size = Vector3.new(1.2, radius * 2 + band, radius * 2 + band)
					inner.Size = Vector3.new(1.3, math.max(0.5, radius * 2 - band), math.max(0.5, radius * 2 - band))
					local r2 = select(1, getAliveParts(player))
					if r2 and not hit then
						local d = (flat(r2.Position) - flat(origin)).Magnitude
						if math.abs(d - radius) <= band / 2 + 1.2 then
							if isDashing(r2, player) then
								awardNearMiss(player, r2)
							else
								hit = true
								hurt(0.22, "💥 The shockwave knocked you down! (Dash through it)")
								shake(0.7)
							end
						end
					end
					task.wait()
				end
				ringPart:Destroy()
				inner:Destroy()
				task.wait(0.35)
			end
			task.wait(1.0)
		end

		-- 패턴 9) 십자 광선 (2단계부터): 네 갈래 광선이 돌다가 한 번 방향을 바꾼다
		local function crossBeams()
			local pivot = Vector3.new(center.X, floorY, center.Z)
			local length, width = 82, 6
			local base = math.random() * math.pi
			local arms = {}
			for _ = 1, 4 do arms[#arms + 1] = floorPart(Vector3.new(width, 0.4, length), CFrame.new(pivot), rgb(255, 60, 50), 0.65) end
			local function place(angle)
				for index, arm in ipairs(arms) do
					local a = angle + (index - 1) * math.pi / 2
					local dir = Vector3.new(math.cos(a), 0, math.sin(a))
					arm.CFrame = CFrame.lookAt(pivot + dir * (length / 2), pivot + dir * length)
				end
			end
			place(base)
			for _, arm in ipairs(arms) do TweenService:Create(arm, TweenInfo.new(1.2), { Transparency = 0.15 }):Play() end
			lordSfx("Lord_Charge")
			task.wait(1.3)
			for _, arm in ipairs(arms) do arm.Color, arm.Transparency = rgb(255, 170, 70), 0.05 end
			lordSfx("Lord_Blast")
			local started, duration, hitAt = os.clock(), 4.2, 0
			local sign = math.random() < 0.5 and 1 or -1
			while os.clock() - started < duration and alive() and bossAlive() do
				local t = os.clock() - started
				local turn = t < duration / 2 and t or (duration / 2 - (t - duration / 2)) -- 절반이 지나면 거꾸로 돈다
				local angle = base + sign * turn * 0.7
				place(angle)
				local r2 = select(1, getAliveParts(player))
				if r2 and os.clock() - hitAt > 0.8 then
					for index = 1, 4 do
						local a = angle + (index - 1) * math.pi / 2
						local dir = Vector3.new(math.cos(a), 0, math.sin(a))
						if distToSegment(r2.Position, pivot, pivot + dir * length) <= width / 2 + 1.5 then
							hitAt = os.clock()
							hurt(0.24, "💥 Caught by the cross beams!")
							shake(0.6)
							break
						end
					end
				end
				task.wait()
			end
			for _, arm in ipairs(arms) do
				TweenService:Create(arm, TweenInfo.new(0.35), { Transparency = 1 }):Play()
				task.delay(0.4, function() arm:Destroy() end)
			end
			task.wait(0.8)
		end

		-- 단계별 외형 변화: 2단계 날개가 불타오르고, 3단계 후광이 검붉게 변하며 기운이 짙어진다
		local function phaseLook(phase)
			for _, item in ipairs(model:GetDescendants()) do
				if item:IsA("BasePart") then
					if item.Name == "WingEdge" then item.Color = phase >= 3 and rgb(170, 30, 60) or rgb(255, 130, 60) end
					if item.Name == "Halo" and phase >= 3 then item.Color = rgb(120, 10, 30) end
					if item.Name == "HaloOuter" and phase >= 3 then item.Color = rgb(150, 40, 90) end
					if item.Name == "Cape" and phase >= 3 then item.Color = rgb(40, 8, 20) end
				end
			end
			local aura = body:FindFirstChild("LordAura")
			if aura then
				aura.Rate = phase >= 3 and 70 or 55
				if phase >= 3 then aura.Color = ColorSequence.new(rgb(170, 30, 70), rgb(80, 10, 40)) end
			end
		end

		-- 단계 안내
		local function phaseBanner(text, sub)
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "The Final Lord", Text = sub, Duration = 3, Top = true })
			shake(0.9)
			Effects.Burst(body.Position, rgb(255, 120, 90), 140)
			lordSfx("Lord_Blast")
		end

		task.wait(1.5)
		local order = 0
		local lastPattern
		local fightStart = os.clock()
		local enraged = false
		while alive() and bossAlive() do
			local fractionNow = fraction()
			local newPhase = fractionNow <= FL.Phase3 and 3 or (fractionNow <= FL.Phase2 and 2 or 1)
			if newPhase > phaseNow then
				phaseNow = newPhase
				phaseLook(phaseNow)
				if phaseNow == 2 then phaseBanner("🔥 PHASE 2 — The Lord's fury grows!", "...Not bad. But I am only getting started.")
				else
					dmgMult = math.max(dmgMult, 1.15)
					phaseBanner("☠ PHASE 3 — Final form! Attacks now come TWO at a time!", "Now... witness true despair.")
				end
				task.wait(1.8)
			end
			if not enraged and os.clock() - fightStart > 240 then -- 4분이 넘으면 격노: 더 아프고 더 빨라진다 (질질 끌 수 없게)
				enraged = true
				dmgMult = 1.35
				phaseBanner("💢 ENRAGED — The Lord grows impatient!", "Enough games.")
			end
			local pool = { tripleStrike, ringOfRuin, sweepBeam, shockwaves }
			if phaseNow >= 2 then table.insert(pool, meteorStorm) table.insert(pool, lanes) table.insert(pool, crossBeams) end
			if phaseNow >= 3 then table.insert(pool, orbBarrage) table.insert(pool, judgement) end
			order += 1
			local pick
			if phaseNow >= 3 and order % 3 == 0 then
				pick = judgement
			else
				for _ = 1, 6 do
					pick = pool[math.random(#pool)]
					if pick ~= lastPattern then break end
				end
			end
			lastPattern = pick
			-- 3단계: 두 패턴이 겹쳐 온다 (바닥 폭격 계열 하나를 같이 깐다). 심판 중에는 겹치지 않는다
			if phaseNow >= 3 and pick ~= judgement then
				local partner = ({ tripleStrike, meteorStorm, ringOfRuin })[math.random(3)]
				if partner ~= pick then task.spawn(partner) end
			end
			pick()
			if not alive() or not bossAlive() then break end
			local rest = phaseNow == 1 and 1.2 or (phaseNow == 2 and 0.9 or 0.6)
			task.wait(enraged and rest * 0.6 or rest)
		end

		running = false
		local won = not bossAlive() and alive()
		monsters[body] = nil
		if body.Parent then body:Destroy() end
		if won then
			local bossPoint = center + Vector3.new(0, 30, -26)
			for k = 1, 6 do
				task.delay(k * 0.18, function()
					if arena.Parent then
						Effects.Burst(bossPoint + Vector3.new(math.random(-12, 12), math.random(-6, 10), math.random(-8, 8)), rgb(255, 200, 120), 120)
						ring(bossPoint, 40 + k * 14, rgb(255, 140, 80), 1.0)
						shake(0.9)
					end
				end)
			end
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👑", Title = "The Final Lord", Text = "...Impossible. You... have surpassed me. The world is yours.", Duration = 6, Top = true })
			notify(player, string.format("🏆 You defeated the Final Lord!  +%d gold  +%d tickets", FL.RewardGold, FL.RewardTickets))
			player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + FL.RewardGold)
			player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + FL.RewardTickets)
			-- 주간 보상: 이번 주 첫 처치면 "세트 + 유니크 확정 신화" 1개 (매주 다시 도전할 이유)
			pcall(function()
				local Meta = require(script.Parent:WaitForChild("MetaService"))
				local Inventory = require(script.Parent:WaitForChild("InventoryService"))
				local rift = Meta.GetRift(player)
				local week = math.floor(os.time() / 604800)
				if rift and (rift.LordWeek or 0) ~= week then
					rift.LordWeek = week
					local item = Inventory.GrantMythic(player, { Unique = true, Set = true })
					local def = item.Unique and Config.Uniques[item.Unique]
					local setDef = item.Set and Config.Sets[item.Set]
					notify(player, string.format("👑 Weekly Final Lord reward: Mythic %s · %s Set · ✦ %s!", item.Slot, setDef and setDef.Name or "?", def and def.Name or "?"))
				else
					notify(player, "👑 Weekly Final Lord reward already claimed this week (resets Thursday).")
				end
			end)
			Remotes.Notify:FireAllClients(string.format("📢 %s defeated the Final Lord!", player.DisplayName))
			task.wait(4.5)
			-- 이어지는 연출: 군주의 마지막 말 -> 하늘에 보랏빛 균열이 열린다 -> 마을로 돌아가 보스러쉬 포탈로 안내
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🌀", Title = "The Final Lord", Text = "...Listen. Beneath this world, a rift is opening. The seals I held are breaking. Bosses will come, one after another... Show me how long you can stand.", Duration = 7, Top = true })
			local riftAt = center + Vector3.new(0, 70, -10)
			local orb = Instance.new("Part")
			orb.Shape = Enum.PartType.Ball
			orb.Size = Vector3.new(4, 4, 4)
			orb.Position = riftAt
			orb.Anchored, orb.CanCollide, orb.CanQuery, orb.CastShadow = true, false, false, false
			orb.Material, orb.Color, orb.Transparency = Enum.Material.Neon, rgb(200, 70, 220), 0.1
			orb.Parent = arena
			TweenService:Create(orb, TweenInfo.new(4.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(150, 150, 150), Transparency = 0.55 }):Play()
			for k = 1, 5 do
				task.delay(k * 0.9, function()
					if arena.Parent then
						ring(riftAt - Vector3.new(0, 68, 0), 30 + k * 12, rgb(210, 90, 230), 1.4)
						Effects.Burst(riftAt, rgb(220, 110, 240), 90)
						shake(0.4 + k * 0.1)
					end
				end)
			end
			task.wait(5)
			Remotes.Notify:FireClient(player, "🌀 A rift opens... you are pulled back to town.")
			task.wait(2)
		else
			task.wait(4)
		end
		player:SetAttribute("InDoomArena", nil)
		arena:Destroy()
		if won and player.Parent then
			player:LoadCharacter() -- 이긴 사람은 마을로 돌아간다 (진 사람은 쓰러져서 자동으로 마을로)
			task.delay(2.5, function() -- 마을에 도착하면: 보스러쉬 포탈이 열렸다고 알려 주고 포탈로 길을 안내한다
				if not player.Parent then return end
				Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👹", Title = "The Boss Rush is open!", Text = "Follow the purple light to the portal in town. Bosses arrive one by one - survive as long as you can. Score = seconds survived x damage dealt, ranked weekly!", Duration = 9 })
				local okJourney, Journey = pcall(function() return require(script.Parent:WaitForChild("JourneyService")) end)
				if okJourney and Journey.PointToRift then Journey.PointToRift(player) end
			end)
		end
		return
	end

	task.wait(1.0)
	-- 1) 좁은 간격의 3연 폭격 (플레이어 주변)
	if alive() then
		for k = 1, 3 do
			local offset = Vector3.new((k - 2) * 20, 0, 0)
			strike(playerAt() + offset, 13, 1.2, 0.15)
			task.wait(0.35)
		end
		task.wait(1.4)
	end
	-- 2) 플레이어를 둘러싼 고리가 시계 방향으로 하나씩 내리꽂히고, 마지막에 한가운데로 큰 일격
	if alive() then
		shake(0.5)
		local around = playerAt()
		local gap = math.random(6) -- 한 군데는 비워 둔다: 그쪽으로 빠져나가면 맞지 않는다
		for k = 1, 6 do
			if k ~= gap then
				local angle = k / 6 * math.pi * 2
				strike(around + Vector3.new(math.cos(angle) * 34, 0, math.sin(angle) * 34), 14, 1.1, 0.12)
			end
			task.wait(0.14)
		end
		task.wait(0.5)
		if alive() then
			strike(around, 22, 1.0, 0.2)
		end
		task.wait(1.5)
	end
	-- 마지막: 아레나 전체가 붉게 물든다 — 어디에도 안전한 곳이 없다
	if alive() then
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "The Final Lord",
			Text = (data.DoomHits or 0) >= 6 and "...You scratched me. But it is not enough." or "That power is still not enough.", Duration = 3, Top = true })
		Remotes.Tutorial:FireClient(player, "Cinema", "Start")
		shake(0.9)
		local flood = Instance.new("Part")
		flood.Shape = Enum.PartType.Cylinder
		flood.Size = Vector3.new(0.4, 160, 160)
		flood.CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		flood.Anchored = true
		flood.CanCollide = false
		flood.CanQuery = false
		flood.Material = Enum.Material.Neon
		flood.Color = rgb(255, 30, 30)
		flood.Transparency = 0.9
		flood.Parent = arena
		TweenService:Create(flood, TweenInfo.new(2.4, Enum.EasingStyle.Quad), { Transparency = 0.86 }):Play() -- (바닥이 온통 붉어 내 총알이 안 보이던 문제: 덜 진하게)
		lordSfx("Lord_Charge")
		local charge = Instance.new("Part")
		charge.Shape = Enum.PartType.Ball
		charge.Anchored = true
		charge.CanCollide = false
		charge.CanQuery = false
		charge.Material = Enum.Material.Neon
		charge.Color = rgb(255, 230, 120)
		charge.Transparency = 0.2
		charge.Size = Vector3.new(4, 4, 4)
		charge.Position = body.Position + Vector3.new(0, 4, -10)
		charge.Parent = arena
		TweenService:Create(charge, TweenInfo.new(2.4, Enum.EasingStyle.Quad), { Size = Vector3.new(60, 60, 60), Transparency = 0.05 }):Play()
		local halos = {} -- 충전구 둘레를 도는 세 개의 고리 (자이로스코프처럼 서로 다른 방향으로 돈다)
		for index, diameter in ipairs({ 40, 56, 72 }) do
			local halo = Instance.new("Part")
			halo.Shape = Enum.PartType.Cylinder
			halo.Size = Vector3.new(1.2, diameter, diameter)
			halo.Anchored = true
			halo.CanCollide = false
			halo.CanQuery = false
			halo.CastShadow = false
			halo.Material = Enum.Material.Neon
			halo.Color = index == 2 and rgb(255, 150, 100) or rgb(200, 50, 60)
			halo.Transparency = 1
			halo.Parent = arena
			TweenService:Create(halo, TweenInfo.new(1.2), { Transparency = 0.35 }):Play()
			halos[index] = halo
		end
		local chargeStart, nextStream = os.clock(), 0
		while os.clock() - chargeStart < 2.4 do
			local t = os.clock() - chargeStart
			for index, halo in ipairs(halos) do
				halo.CFrame = CFrame.new(charge.Position) * CFrame.Angles(t * (0.9 + index * 0.5), t * (1.4 - index * 0.3), t * 0.7 * index)
			end
			if t >= nextStream then -- 아레나 가장자리에서 에너지가 충전구로 빨려든다
				nextStream = t + 0.1
				local angle = math.random() * math.pi * 2
				local from = center + Vector3.new(math.cos(angle) * 78, math.random(4, 40), math.sin(angle) * 78)
				beam(from, charge.Position, 1.4, 0.35, rgb(255, 120, 90))
			end
			if math.floor(t * 2) ~= math.floor((t - 0.03) * 2) and t > 0.2 then shake(0.6 + t * 0.15) end
			task.wait()
		end
		for _, halo in ipairs(halos) do halo:Destroy() end
		local r = alive() and select(1, getAliveParts(player))
		if r then
			lordSfx("Lord_Blast")
			beam(charge.Position, r.Position, 26, 0.9, rgb(255, 240, 150))
			ring(center, 90, rgb(255, 90, 60), 1.0)
			for k = 1, 2 do
				task.delay(0.15 * k, function() if arena.Parent then ring(center, 90 + 30 * k, rgb(200, 50, 60), 1.0) end end)
			end
			Effects.Burst(r.Position, rgb(255, 80, 60), 160)
			Effects.Burst(r.Position + Vector3.new(0, 10, 0), rgb(255, 170, 110), 80)
			shake(1)
			Remotes.Tutorial:FireClient(player, "Cinema", "Blast")
			task.wait(0.35)
			local _, h = getAliveParts(player)
			if h then
				Remotes.Tutorial:FireClient(player, "Cinema", "Black")
				task.wait(0.5)
				h.Health = 0
			end
		end
		charge:Destroy()
		flood:Destroy()
	end

	running = false
	monsters[body] = nil
	body:Destroy()
	task.delay(4.5, function()
		player:SetAttribute("InDoomArena", nil)
		arena:Destroy()
		Remotes.Tutorial:FireClient(player, "Cinema", "End")
		task.wait(2)
		if player.Parent then -- 쓰러진 직후: 지금 강해질 수 있는 방법을 한눈에 알려준다
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "\"I will wait at the end of the 8th land\"",
				Text = "The Lord vanished after saying only that. You fell, but you kept the loot (4000 gold / 10 tickets)!\n🎰 10-pull gacha → 🔨 Upgrade (evolve) — that is how you get stronger. Head to the gacha machine first!", Duration = 10 })
		end
	end)
end

local function doomWave(player, zone, real)
	local slot = 0
	while doomSlots[slot] do slot += 1 end
	doomSlots[slot] = true
	local ok, err = pcall(doomWaveInner, player, zone, Vector3.new(slot * 450, 420, 1500), real)
	task.delay(8, function() doomSlots[slot] = nil end) -- 결투장이 치워지는 시간(약 4.5초)이 지난 뒤에 칸을 비운다
	if not ok then error(err, 0) end
end

-- 튜토리얼 던전의 보스를 쓰러뜨리면 (DungeonService.finish) 그 자리에서 최후의 군주 장면으로 이어진다
Dungeon.OnTutorialHandoff = function(player, lootLines, gold)
	player:SetAttribute("InDoomArena", true) -- 던전 좌표에서 시작해도 "필드 밖으로 튕김" 에 걸리지 않게 먼저 켠다
	player:SetAttribute("Zone", "Field") -- 군주 결투장은 필드 규칙(필드 사격 / 쓰러지면 마을 귀환)으로 진행된다
	task.spawn(function()
		print(string.format("[튜토리얼 군주] %s 군주 장면 시작", player.Name))
		task.wait(2.5) -- 보스가 쓰러지는 여운
		if not getAliveParts(player) then
			print("[튜토리얼 군주] 중단: 캐릭터 없음")
			player:SetAttribute("InDoomArena", nil)
			return
		end
		notify(player, "⚠ The sky grows dark...")
		local ok, err = pcall(doomWave, player, 1)
		if not ok then
			warn("[튜토리얼 군주] 오류: " .. tostring(err))
			player:SetAttribute("InDoomArena", nil)
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if r then r.Anchored = false end
		end
		task.delay(10, function() -- 쓰러져 마을로 돌아온 뒤: 던전에서 받은 전리품을 알려 준다
			if player.Parent and #lootLines > 0 then
				local names = {}
				for _, line in ipairs(lootLines) do table.insert(names, typeof(line) == "table" and tostring(line.Text) or tostring(line)) end
				notify(player, "🎁 Dungeon loot: " .. table.concat(names, ", "))
			end
		end)
	end)
end


-- 8구역 끝에 서 있는 최후의 군주 포탈: 8구역 군주를 쓰러뜨린 사람만 들어갈 수 있다. 들어가면 튜토리얼 때와 같은 납치 연출로 결투장에 끌려가 진짜 결전이 시작된다.
local portalLast = setmetatable({}, { __mode = "k" })
function DoomScene.BuildPortal(deps)
	local zoneCount = deps.ZoneCount or 8
	local x = deps.ZoneEnd(zoneCount) - 24
	local base = Vector3.new(x, deps.FloorAt(x), 0)
	local folder = Instance.new("Folder")
	folder.Name = "FinalLordPortal"
	folder.Parent = workspace
	local function part(size, position, color, material, transparency, shape)
		local p = Instance.new("Part")
		p.Size = size
		p.Position = position
		p.Anchored, p.CanCollide, p.CanQuery, p.CastShadow = true, false, false, false
		p.Color, p.Material, p.Transparency = color, material, transparency or 0
		if shape then p.Shape = shape end
		p.Parent = folder
		return p
	end
	for _, side in ipairs({ -1, 1 }) do
		part(Vector3.new(7, 38, 7), base + Vector3.new(0, 19, side * 20), rgb(24, 14, 28), Enum.Material.Slate)
		part(Vector3.new(3, 10, 3), base + Vector3.new(0, 42, side * 20), rgb(255, 70, 60), Enum.Material.Neon, 0.15)
	end
	part(Vector3.new(7, 5, 47), base + Vector3.new(0, 40, 0), rgb(24, 14, 28), Enum.Material.Slate)
	local outer = part(Vector3.new(2.4, 40, 40), base + Vector3.new(0, 21, 0), rgb(255, 60, 60), Enum.Material.Neon, 0.25, Enum.PartType.Cylinder)
	local swirl = part(Vector3.new(1, 34, 34), base + Vector3.new(0, 21, 0), rgb(130, 40, 170), Enum.Material.Neon, 0.35, Enum.PartType.Cylinder)
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = rgb(255, 80, 90), 60, 3
	glow.Parent = swirl
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 40
	sparks.Lifetime = NumberRange.new(1.2, 2)
	sparks.Speed = NumberRange.new(4, 10)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 0.8
	sparks.Color = ColorSequence.new(rgb(255, 120, 130), rgb(150, 50, 200))
	sparks.Size = NumberSequence.new(1.6, 0)
	sparks.Parent = swirl
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(300, 50)
	sign.StudsOffset = Vector3.new(0, 30, 0)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 220
	sign.Parent = swirl
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "☠ The Final Lord's Portal"
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = rgb(255, 120, 130)
	text.TextStrokeTransparency = 0.3
	text.Parent = sign
	TweenService:Create(outer, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.5 }):Play()
	TweenService:Create(swirl, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 }):Play()

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Enter the Final Lord's realm"
	prompt.ObjectText = "Portal"
	prompt.HoldDuration = 1.2
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	-- 소용돌이 중심은 땅에서 21 스터드 위라서 거기에 붙이면 땅에 선 사람에게 프롬프트가 안 보인다 -> 바닥 높이의 투명 부품에 붙인다
	local anchor = part(Vector3.new(6, 6, 6), base + Vector3.new(0, 3, 0), rgb(0, 0, 0), Enum.Material.SmoothPlastic, 1)
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		if player:GetAttribute("InDoomArena") or player:GetAttribute("Zone") ~= "Field" or not getAliveParts(player) then return end
		local beaten = player:GetAttribute("AugOpenZ_" .. zoneCount) == true or (player:GetAttribute("ClearedZone") or 0) >= zoneCount
		if not beaten then
			notify(player, string.format("🔒 Defeat the Lord of Zone %d first — only then will the portal open for you.", zoneCount))
			return
		end
		local wait = Config.FinalLord.PortalCooldown - (os.clock() - (portalLast[player] or -1e9))
		if wait > 0 then
			notify(player, string.format("⏳ The portal is still recovering (%d s).", math.ceil(wait)))
			return
		end
		portalLast[player] = os.clock()
		task.spawn(function()
			local ok, err = pcall(doomWave, player, zoneCount, true)
			if not ok then
				warn("[최후의 군주 결전] 오류: " .. tostring(err))
				player:SetAttribute("InDoomArena", nil)
				player:SetAttribute("CombatLocked", nil)
				local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if r then r.Anchored = false end
			end
		end)
	end)
end

DoomScene.Wave = doomWave
DoomScene.StartRift = startTutorialRift

return DoomScene
