-- DoomScene (ServerScriptService > Modules 안의 ModuleScript, 이름: DoomScene)
-- 튜토리얼 연출: 첫 구역 군주가 떨어뜨린 열쇠 -> 던전으로 추락(startTutorialRift) / 던전 보스 뒤에 나타나는 최후의 군주 결투 장면(doomWave).
-- FieldService 가 너무 커져서(Studio 스크립트 한도 200,000 바이트) 분리했다. FieldService 의 몬스터 표 / 알림 함수 등은 Init 으로 받는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
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
	local dark, steel, red = rgb(26, 12, 22), rgb(60, 52, 70), rgb(255, 50, 60)
	local body = add(Vector3.new(12, 20, 7), CFrame.new(0, 0, 0), dark, Enum.Material.Metal)
	body.CanQuery = true
	body.Name = "Body"
	add(Vector3.new(8, 6, 5), CFrame.new(0, -12, 0), dark) -- 허리 아래로 좁아지는 하체
	add(Vector3.new(4, 7, 3), CFrame.new(0, -18, 0), steel)
	add(Vector3.new(5, 5, 5), CFrame.new(0, 4, -4.2) * CFrame.Angles(math.rad(45), math.rad(45), 0), red, Enum.Material.Neon) -- 가슴 코어
	add(Vector3.new(11, 1, 1), CFrame.new(0, 9, -3.8), steel)
	add(Vector3.new(11, 1, 1), CFrame.new(0, -3, -3.8), steel)
	-- 머리 + 눈 + 뿔 + 왕관
	add(Vector3.new(6.5, 6.5, 6.5), CFrame.new(0, 14, 0), rgb(18, 8, 16))
	for _, side in ipairs({ -1, 1 }) do
		add(Vector3.new(3, 0.9, 0.6), CFrame.new(side * 1.7, 14.6, -3.3) * CFrame.Angles(0, 0, math.rad(side * 18)), rgb(255, 230, 90), Enum.Material.Neon)
		add(Vector3.new(1.4, 13, 1.4), CFrame.new(side * 4.2, 21, 0) * CFrame.Angles(0, 0, math.rad(side * -28)), rgb(230, 220, 205), Enum.Material.SmoothPlastic)
		add(Vector3.new(1.2, 7, 1.2), CFrame.new(side * 9, 27, 0) * CFrame.Angles(0, 0, math.rad(side * -58)), rgb(230, 220, 205), Enum.Material.SmoothPlastic)
		-- 어깨 갑옷 + 가시
		add(Vector3.new(8, 4, 8), CFrame.new(side * 9.5, 9, 0), steel)
		for k = 0, 2 do
			add(Vector3.new(1.4, 8 - k * 1.5, 1.4), CFrame.new(side * (7.5 + k * 2.2), 13 + k * 0.8, 0) * CFrame.Angles(0, 0, math.rad(side * (-15 - k * 14))), red, Enum.Material.Neon)
		end
		-- 팔 + 거대한 주먹 + 손목 불꽃줄
		add(Vector3.new(4, 16, 4), CFrame.new(side * 12, -1, 0), dark)
		add(Vector3.new(7.5, 7.5, 7.5), CFrame.new(side * 12, -11, -1), steel)
		add(Vector3.new(8, 0.8, 8), CFrame.new(side * 12, -8, -1), red, Enum.Material.Neon)
		-- 칼날 날개 (등 뒤로 부챗살)
		for k = 0, 3 do
			add(Vector3.new(1, 22 - k * 3, 5), CFrame.new(side * (8 + k * 3.4), 6 + k * 0.5, 7) * CFrame.Angles(math.rad(-10), math.rad(side * -12), math.rad(side * (-22 - k * 14))), rgb(90, 20, 40), Enum.Material.Metal)
			add(Vector3.new(0.4, 20 - k * 3, 1.2), CFrame.new(side * (8 + k * 3.4), 6 + k * 0.5, 4.6) * CFrame.Angles(math.rad(-10), math.rad(side * -12), math.rad(side * (-22 - k * 14))), red, Enum.Material.Neon, 0.15)
		end
	end
	-- 후광 (머리 뒤 큰 고리 두 겹)
	add(Vector3.new(0.7, 30, 30), CFrame.new(0, 15, 8) * CFrame.Angles(0, math.rad(90), 0), red, Enum.Material.Neon, 0.25, Enum.PartType.Cylinder)
	add(Vector3.new(0.5, 38, 38), CFrame.new(0, 15, 9) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 150, 60), Enum.Material.Neon, 0.5, Enum.PartType.Cylinder)
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
	aura.Parent = core
	local light = Instance.new("PointLight")
	light.Color = red
	light.Range = 60
	light.Brightness = 3
	light.Parent = core

	local function place(base, t)
		for _, entry in ipairs(parts) do
			entry.Part.CFrame = base * entry.Rel
		end
		for k, blade in ipairs(orbit) do
			local angle = t * 1.8 + k * math.pi / 2
			blade.CFrame = base * CFrame.new(math.cos(angle) * 16 * S, 4 * S + math.sin(angle * 2) * 3, math.sin(angle) * 8 * S) * CFrame.Angles(0, -angle, math.rad(20))
		end
	end
	return model, body, place
end

-- 소환 결투: 먼 하늘 위 심연 무대로 끌려가 최후의 군주와 1:1 (약 8초). 공격할 수 있지만 쓰러뜨릴 수는 없고, 바닥 경고를 보고 피할 수 있는 공격을 받다가 마지막 일격에 쓰러진다.
-- 튜토리얼: 첫 구역 군주를 쓰러뜨리면 군주가 던전 열쇠를 떨어뜨린다 -> 열쇠가 날아와 공명하고 -> 바닥이 갈라져 던전으로 떨어진다
local function startTutorialRift(player, at)
	if player:GetAttribute("TutorialRiftBusy") then return end
	player:SetAttribute("TutorialRiftBusy", true)
	local key
	local ok, err = pcall(function()
		local root = getAliveParts(player)
		if not root then print("[튜토리얼 열쇠] 중단: 캐릭터 없음") return end
		print(string.format("[튜토리얼 열쇠] %s 시작", player.Name))
		notify(player, "🗝 군주가 던전 열쇠를 떨어뜨렸다!")
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🗝", Title = "군주의 열쇠", Text = "필드 군주는 던전 열쇠를 떨어뜨려요. 열쇠가 공명하며 발밑이 갈라지기 시작해요...", Duration = 4, Top = true })
		Remotes.Tutorial:FireClient(player, "WaypointClear")
		task.wait(1.0)
		root = getAliveParts(player)
		if not root then return end
		-- 열쇠: 군주가 쓰러진 자리에서 떠올라 플레이어에게 날아온다 (눈이 아프지 않은 호박색)
		key = Instance.new("Part")
		key.Name = "TutorialKey"
		key.Size = Vector3.new(1.2, 3.2, 0.5)
		key.Color = rgb(232, 178, 90)
		key.Material = Enum.Material.Neon
		key.Anchored = true
		key.CanCollide = false
		key.CanQuery = false
		key.CastShadow = false
		key.CFrame = CFrame.new(at + Vector3.new(0, 3, 0))
		key.Parent = workspace
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 190, 110)
		light.Range = 18
		light.Brightness = 1.2
		light.Parent = key
		local from = key.Position
		local started = os.clock()
		while os.clock() - started < 1.3 do
			local t = (os.clock() - started) / 1.3
			local eased = t * t * (3 - 2 * t)
			root = getAliveParts(player)
			if not root then return end
			local target = root.Position + Vector3.new(0, 3.5, 0)
			key.CFrame = CFrame.new(from:Lerp(target, eased) + Vector3.new(0, math.sin(t * math.pi) * 6, 0)) * CFrame.Angles(0, t * 14, math.rad(15))
			task.wait()
		end
		Effects.Burst(key.Position, rgb(255, 200, 120), 40)
		shakeScreen(player, 0.5)
		task.wait(0.4)
		-- 바닥이 갈라진다: 발밑에서 사방으로 갈라진 틈이 번진다
		root = getAliveParts(player)
		if not root then return end
		local floorY = root.Position.Y - 3
		local cracks = {}
		for index = 1, 7 do
			local angle = index / 7 * math.pi * 2 + math.random() * 0.4
			local length = 16 + math.random() * 14
			local crack = Instance.new("Part")
			crack.Size = Vector3.new(0.9, 0.2, length)
			crack.CFrame = CFrame.new(root.Position.X, floorY + 0.15, root.Position.Z) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, length / 2)
			crack.Anchored = true
			crack.CanCollide = false
			crack.CanQuery = false
			crack.CastShadow = false
			crack.Material = Enum.Material.Neon
			crack.Color = rgb(232, 150, 80)
			crack.Transparency = 0.9
			crack.Parent = workspace
			TweenService:Create(crack, TweenInfo.new(0.7), { Transparency = 0.25 }):Play()
			table.insert(cracks, crack)
		end
		shakeScreen(player, 0.9)
		task.wait(0.9)
		-- 떨어진다: 몸을 고정하고 아래로 내려보내며 화면이 어두워진다
		root = getAliveParts(player)
		if not root then return end
		Remotes.Tutorial:FireClient(player, "Cinema", "Black")
		root.Anchored = true
		local base = root.CFrame
		local fall = os.clock()
		while os.clock() - fall < 0.8 do
			local t = (os.clock() - fall) / 0.8
			root = getAliveParts(player)
			if not root then break end
			root.CFrame = base - Vector3.new(0, 28 * t * t, 0)
			task.wait()
		end
		for _, crack in ipairs(cracks) do crack:Destroy() end
		key:Destroy()
		key = nil
		root = getAliveParts(player)
		if root then root.Anchored = false end
		print(string.format("[튜토리얼 열쇠] %s 던전 입장 시도 (Zone=%s, TutorialDungeonRun=%s)", player.Name, tostring(player:GetAttribute("Zone")), tostring(player:GetAttribute("TutorialDungeonRun"))))
		Dungeon.Start(player, "Cave", "Easy", nil, nil, true)
		if player:GetAttribute("Zone") ~= "Dungeon" then
			warn("[튜토리얼 열쇠] 던전 입장 실패: Zone=" .. tostring(player:GetAttribute("Zone")) .. " TutorialDungeonLocked=" .. tostring(player:GetAttribute("TutorialDungeonLocked")))
			notify(player, "던전이 아직 열리지 않았어요. 마을의 북쪽 던전 게이트에서 들어갈 수 있어요")
		end
		task.wait(0.5)
		Remotes.Tutorial:FireClient(player, "Cinema", "End")
	end)
	if not ok then
		warn("[튜토리얼 열쇠] 오류: " .. tostring(err))
		if key then key:Destroy() end
		local root = getAliveParts(player)
		if root then root.Anchored = false end
		Remotes.Tutorial:FireClient(player, "Cinema", "End")
	end
	player:SetAttribute("TutorialRiftBusy", nil)
end

local doomSlots = {} -- [칸 번호] = true : 동시에 여러 명이 끌려가도 결투장이 겹치지 않게 사람마다 옆으로 떨어뜨린다
local function doomWaveInner(player, zone, center)
	local root, humanoid = getAliveParts(player)
	if not root then return end
	player:SetAttribute("InDoomArena", true) -- 납치 연출로 높이 올라가도 "필드 밖으로 튕김" / 구역 판별에 걸리지 않게 처음부터 켠다
	notify(player, "⚠⚠ 압도적인 기운... 무언가가 당신을 부른다!!")
	playSfx(player, "Lord_Voice") -- 낮게 깔리는 군주의 목소리
	Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "최후의 군주", Text = "...내 수하들을 쓰러뜨리다니, 강하구나. 이제 내가 직접 상대해주마.", Duration = 5, Top = true })
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
		notify(player, "⚠ 하늘에서 거대한 무언가가 내려온다...!")
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
	if not root or humanoid.Health <= 0 then
		player:SetAttribute("InDoomArena", nil)
		return
	end
	root.Anchored = false
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
			local fire = Instance.new("Fire")
			fire.Size = 14
			fire.Heat = 12
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

	local model, body, place = buildDoomLord(arena)
	local bossPos = center + Vector3.new(0, 34, -48)
	place(CFrame.lookAt(bossPos, bossPos + Vector3.new(0, 0, 1)), 0)

	-- 맞출 수 있는 몬스터로 등록한다 (체력이 바닥나지 않게 8% 밑으로는 안 떨어진다)
	local fill = createHealthBar(body, "💀 Lv.???  ???", 360, rgb(255, 90, 90))
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
	notify(player, "💀 최후의 군주와 마주했다! 공격은 통하지만... 쓰러뜨릴 수는 없다. 바닥의 붉은 경고를 피하고, V 궁극기도 써보자!")
	Effects.Burst(bossPos, rgb(255, 70, 60), 100)

	local alive = function()
		local r, h = getAliveParts(player)
		return r ~= nil and h.Health > 0
	end
	local running, clock = true, 0
	local approach = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		clock += dt
		if not running or not body.Parent then connection:Disconnect() return end
		approach = math.min(1, approach + dt / 16)
		local target = alive() and select(1, getAliveParts(player)).Position or center
		local pos = bossPos:Lerp(center + Vector3.new(0, 30, -26), approach) + Vector3.new(0, math.sin(clock * 1.6) * 2.5, 0)
		local flat = Vector3.new(target.X, pos.Y, target.Z)
		place(CFrame.lookAt(pos, flat), clock)
		data.Home = pos
		if not data.Scratched and (data.DoomHits or 0) >= 6 and alive() then -- 내 공격이 닿았다: 군주가 잠깐 반응한다
			data.Scratched = true
			Effects.Burst(body.Position + Vector3.new(0, 6, -8), rgb(255, 235, 170), 60)
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "최후의 군주", Text = "...감히.", Duration = 2.5, Top = true })
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
	local function strike(at, radius, telegraph, percent)
		local warn = Instance.new("Part")
		warn.Shape = Enum.PartType.Cylinder
		warn.Size = Vector3.new(0.3, radius * 2, radius * 2)
		warn.CFrame = CFrame.new(at.X, center.Y + 1.3, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		warn.Anchored = true
		warn.CanCollide = false
		warn.CanQuery = false
		warn.Material = Enum.Material.Neon
		warn.Color = rgb(255, 40, 40)
		warn.Transparency = 0.6
		warn.Parent = arena
		lordSfx("Lord_Charge")
		TweenService:Create(warn, TweenInfo.new(telegraph), { Transparency = 0.05 }):Play()
		task.delay(telegraph, function()
			warn:Destroy()
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
			if r2 and h2.Health > 0 then
				local gap = (Vector3.new(r2.Position.X, center.Y, r2.Position.Z) - at).Magnitude
				if gap <= radius then
					local dmg = math.min(h2.MaxHealth * percent, h2.Health - 1)
					if dmg > 0 then h2:TakeDamage(dmg) end
					notify(player, "💥 군주의 공격에 맞았다!")
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

	task.wait(1.0)
	-- 1) 좁은 간격의 3연 폭격 (플레이어 주변)
	if alive() then
		notify(player, "⚠ 군주가 손을 들어올렸다!")
		for k = 1, 3 do
			local offset = Vector3.new((k - 2) * 20, 0, 0)
			strike(playerAt() + offset, 13, 1.2, 0.15)
			task.wait(0.35)
		end
		task.wait(1.4)
	end
	-- 2) 플레이어를 둘러싼 고리가 시계 방향으로 하나씩 내리꽂히고, 마지막에 한가운데로 큰 일격
	if alive() then
		notify(player, "⚠⚠ 사방이 붉게 물든다 — 빠져나갈 틈을 찾아라!")
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
		notify(player, "💀 군주가 모든 힘을 모은다... 피할 곳이 없다!!")
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "최후의 군주",
			Text = (data.DoomHits or 0) >= 6 and "...흠집을 냈구나. 하지만 아직 부족하다." or "그 힘으로는 아직 부족하다.", Duration = 3, Top = true })
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
			Remotes.Tutorial:FireClient(player, "Prompt", { Key = "👁", Title = "\"8번째 땅 끝에서 기다리마\"",
				Text = "군주는 그 말만 남기고 사라졌어요. 쓰러졌지만 전리품(골드 4000 / 티켓 10장)은 남았어요!\n🎰 뽑기 10연 → 🔨 강화(진화) 순서로 강해져 봐요. 먼저 뽑기 머신으로!", Duration = 10 })
		end
	end)
end

local function doomWave(player, zone)
	local slot = 0
	while doomSlots[slot] do slot += 1 end
	doomSlots[slot] = true
	local ok, err = pcall(doomWaveInner, player, zone, Vector3.new(slot * 450, 420, 1500))
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
		notify(player, "⚠ 하늘이 어두워진다...")
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
				notify(player, "🎁 던전 전리품: " .. table.concat(names, ", "))
			end
		end)
	end)
end


DoomScene.Wave = doomWave
DoomScene.StartRift = startTutorialRift

return DoomScene
