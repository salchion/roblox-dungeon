-- ShowcaseService (ServerScriptService > Modules 안의 ModuleScript, 이름: ShowcaseService)
-- 로비 "명예의 전당": 지금 서버에서 전투력이 가장 높은 3명을 랭킹판 앞 전시대에 세워 보여준다.
--   아바타 모형 + 그 사람의 무기 모양(진화 단계) + 이름 / 전투력 / 무기 이름
--   -> 남의 강한 장비가 눈에 띄어야 "나도 저렇게 되고 싶다"가 생긴다.
-- 전시대는 한 번만 만들고, 1순위~3순위가 바뀔 때만 모형을 새로 만든다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Showcase = {}

local slots = {}   -- [1..3] = { Pedestal, Label, Key, Model, Weapon }
local folder

local MEDAL = { "🥇", "🥈", "🥉" }
local MEDAL_COLORS = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(205, 210, 220), Color3.fromRGB(205, 140, 80) }

local function makeLabel(parent, offsetY, maxDistance)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = parent.Position + Vector3.new(0, offsetY, 0)
	part.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 260, 0, 84)
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 40
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	return label
end

-- 북쪽 성벽의 "명예의 전당": 던전 게이트들 바로 위, 성벽 안쪽 면에 순위별 벽감(받침대 + 뒷판)이 튀어나와 있고
-- 랭커 아바타가 광장 쪽을 보고 크게 서 있다. 게이트로 걸어가다 보면 자연스럽게 눈에 들어온다.
-- 이름 / 전투력 / 무기가 머리 위에 보인다. (성벽 높이는 LobbyService 에서 북쪽만 높게 만든다)
local WALL_FACE_Z = -127 -- 북쪽 성벽 안쪽 면

function Showcase.Init(_boardCFrame)
	folder = Instance.new("Folder")
	folder.Name = "Showcase"
	folder.Parent = workspace:FindFirstChild("Lobby") or workspace

	local look = Vector3.new(0, 0, 1) -- 광장(남쪽)을 바라본다
	-- 가운데가 1등(가장 높음), 좌우가 2등(왼쪽) / 3등(오른쪽)
	local spots = {
		Vector3.new(0, 52, WALL_FACE_Z + 5), -- 게이트 위 장식(높이 약 40)과 겹치지 않게 높이 올렸다 (뒷판 아래 끝이 49 / 43)
		Vector3.new(-42, 46, WALL_FACE_Z + 5),
		Vector3.new(42, 46, WALL_FACE_Z + 5),
	}
	for rank = 1, 3 do
		local spot = spots[rank]
		local color = MEDAL_COLORS[rank]

		-- 벽에 붙은 뒷판 (어두운 판 + 순위 색 테두리)
		local backdrop = Instance.new("Part")
		backdrop.Name = "Backdrop" .. rank
		backdrop.Anchored = true
		backdrop.Size = Vector3.new(26, 30, 1)
		backdrop.Position = Vector3.new(spot.X, spot.Y + 12, WALL_FACE_Z + 0.5)
		backdrop.Color = Color3.fromRGB(26, 24, 40)
		backdrop.Material = Enum.Material.Slate
		backdrop.Parent = folder
		for _, edge in ipairs({
			{ Vector3.new(26.6, 0.8, 1.4), Vector3.new(0, 15, 0) },
			{ Vector3.new(26.6, 0.8, 1.4), Vector3.new(0, -15, 0) },
			{ Vector3.new(0.8, 30, 1.4), Vector3.new(-13, 0, 0) },
			{ Vector3.new(0.8, 30, 1.4), Vector3.new(13, 0, 0) },
		}) do
			local trim = Instance.new("Part")
			trim.Anchored = true
			trim.CanCollide = false
			trim.Size = edge[1]
			trim.Position = backdrop.Position + edge[2]
			trim.Color = color
			trim.Material = Enum.Material.Neon
			trim.Parent = folder
		end

		-- 장식: 양옆 돌기둥(순위 색 머리) + 위쪽 박공 + 아래로 늘어진 깃발 -> 신전 벽감 느낌
		for _, side in ipairs({ -1, 1 }) do
			local pillar = Instance.new("Part")
			pillar.Anchored = true
			pillar.CanCollide = false
			pillar.Size = Vector3.new(2.2, 32, 2.2)
			pillar.Position = backdrop.Position + Vector3.new(side * 14.6, 0, 1.2)
			pillar.Color = Color3.fromRGB(78, 74, 92)
			pillar.Material = Enum.Material.Granite
			pillar.Parent = folder
			local cap = Instance.new("Part")
			cap.Anchored = true
			cap.CanCollide = false
			cap.Size = Vector3.new(3.2, 1.2, 3.2)
			cap.Position = pillar.Position + Vector3.new(0, 16.6, 0)
			cap.Color = color
			cap.Material = Enum.Material.Metal
			cap.Parent = folder
			local banner = Instance.new("Part")
			banner.Anchored = true
			banner.CanCollide = false
			banner.Size = Vector3.new(3, 10, 0.3)
			banner.Position = pillar.Position + Vector3.new(side * 0.2, -9, 1.6)
			banner.Color = color:Lerp(Color3.fromRGB(40, 20, 50), 0.55)
			banner.Material = Enum.Material.Fabric
			banner.Parent = folder
		end
		local cornice = Instance.new("Part") -- 뒷판 위쪽 돌 처마 (순위 색 줄 포함)
		cornice.Anchored = true
		cornice.CanCollide = false
		cornice.Size = Vector3.new(31, 1.6, 2.4)
		cornice.Position = backdrop.Position + Vector3.new(0, 16.4, 0.5)
		cornice.Color = Color3.fromRGB(78, 74, 92)
		cornice.Material = Enum.Material.Granite
		cornice.Parent = folder

		-- 아바타가 서는 받침대 (벽에서 튀어나온 돌 선반)
		local platform = Instance.new("Part")
		platform.Name = "Ledge" .. rank
		platform.Anchored = true
		platform.Size = Vector3.new(18, 2, 10)
		platform.Position = Vector3.new(spot.X, spot.Y - 1, WALL_FACE_Z + 5)
		platform.Color = Color3.fromRGB(70, 66, 84)
		platform.Material = Enum.Material.Granite
		platform.Parent = folder
		local lip = Instance.new("Part")
		lip.Anchored = true
		lip.CanCollide = false
		lip.Size = Vector3.new(18.4, 0.4, 0.5)
		lip.Position = platform.Position + Vector3.new(0, 0.9, 5)
		lip.Color = color
		lip.Material = Enum.Material.Neon
		lip.Parent = folder
		-- 스포트라이트: 받침대 위로 쏟아지는 은은한 빛기둥 + 반짝이는 금가루 ("저 자리에 서고 싶다")
		local beam = Instance.new("Part")
		beam.Name = "Spotlight" .. rank
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.CastShadow = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.9
		beam.Size = Vector3.new(15, 36, 9)
		beam.Position = platform.Position + Vector3.new(0, 18 + 1, 0)
		beam.Parent = folder
		local halo = Instance.new("Part") -- 받침대 바닥 후광 (납작한 원판)
		halo.Anchored = true
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CastShadow = false
		halo.Shape = Enum.PartType.Cylinder
		halo.Material = Enum.Material.Neon
		halo.Color = color
		halo.Transparency = 0.55
		halo.Size = Vector3.new(0.2, 15, 15)
		halo.CFrame = CFrame.new(platform.Position + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		halo.Parent = folder
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		dust.Rate = rank == 1 and 14 or 8
		dust.Lifetime = NumberRange.new(2.5, 4)
		dust.Speed = NumberRange.new(1.5, 3.5)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.SpreadAngle = Vector2.new(25, 25)
		dust.LightEmission = 0.8
		dust.Color = ColorSequence.new(color)
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		dust.Parent = halo
		local glow = Instance.new("PointLight")
		glow.Range = 45
		glow.Brightness = 2
		glow.Color = color
		glow.Parent = backdrop

		slots[rank] = {
			Platform = platform, Top = spot, Scale = 2.8, Look = look, Key = nil, Model = nil, Weapon = nil,
			Label = makeLabel(platform, 27, 75),
		}
		slots[rank].Label.Text = MEDAL[rank] .. " 이 자리의 주인공은?\n<font size='14'>전투력을 올려 서 보세요!</font>"
	end

	local header = makeLabel(slots[1].Platform, 34, 160) -- 1등 뒷판 위의 큰 머리글
	header.Text = "🏆 명예의 전당 🏆"
	header.TextColor3 = Color3.fromRGB(255, 226, 120)

	task.spawn(function()
		task.wait(8)
		while true do
			Showcase.Refresh()
			task.wait(20)
		end
	end)
end

local function clearSlot(slot)
	if slot.Model then
		slot.Model:Destroy()
		slot.Model = nil
	end
	if slot.Weapon then
		slot.Weapon:Destroy()
		slot.Weapon = nil
	end
	slot.Key = nil
end

local function buildSlot(rank, player)
	local slot = slots[rank]
	clearSlot(slot)
	local typeKey = player:GetAttribute("WeaponType") or "Pistol"
	local level = player:GetAttribute("WeaponLevel") or 0
	local power = player:GetAttribute("Power") or 0
	slot.Key = string.format("%d_%d_%s_%d", player.UserId, power // 25, typeKey, level)

	local prestige = player:GetAttribute("Prestige") or 0
	slot.Label.Text = string.format("%s %s%s\n<font color='#ffe16e'>⚡ %d</font> Lv.%d\n<font color='#9ad7ff'>%s</font>",
		MEDAL[rank], prestige > 0 and ("🌟" .. prestige .. " ") or "", player.DisplayName, power, player:GetAttribute("Level") or 1,
		Config.FormatWeapon(level))

	local top = slot.Top

	-- 무기 모형 (진화 단계 미리보기 모델 복제)
	local previews = ReplicatedStorage:FindFirstChild("WeaponPreviews")
	local source = previews and previews:FindFirstChild("W" .. Config.GetWeaponTierIndex(level))
	if source then
		local weapon = source:Clone()
		weapon:ScaleTo(slot.Scale)
		local weaponSpot = top + Vector3.new(0, 9, 0) + Vector3.new(11, 0, 0) -- 아바타 옆에 크게 떠 있다
		weapon:PivotTo(CFrame.lookAt(weaponSpot, weaponSpot + slot.Look) * CFrame.Angles(0, math.rad(90), 0))
		for _, descendant in ipairs(weapon:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
		weapon.Parent = folder
		slot.Weapon = weapon
	end

	-- 아바타 모형 (실패하면 무기만 보여준다)
	task.spawn(function()
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromUserId(player.UserId)
		end)
		if not ok or not model or slot.Key == nil then return end
		local expected = slot.Key
		task.wait()
		if slot.Key ~= expected then
			model:Destroy()
			return
		end
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
			end
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		model.Name = "ShowcaseAvatar"
		model.Parent = folder
		model:ScaleTo(slot.Scale)
		local standAt = top + Vector3.new(0, 3.2 * slot.Scale, 1)
		model:PivotTo(CFrame.lookAt(standAt, standAt + slot.Look))
		slot.Model = model
	end)
end

function Showcase.Refresh()
	local ranking = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(ranking, { Player = player, Power = player:GetAttribute("Power") or 0 })
	end
	table.sort(ranking, function(a, b) return a.Power > b.Power end)

	for rank = 1, 3 do
		local entry = ranking[rank]
		local slot = slots[rank]
		if entry and entry.Power > 0 then
			local player = entry.Player
			local key = string.format("%d_%d_%s_%d", player.UserId, entry.Power // 25, player:GetAttribute("WeaponType") or "Pistol", player:GetAttribute("WeaponLevel") or 0)
			if slot.Key ~= key then
				buildSlot(rank, player)
			end
		elseif slot.Key ~= nil then
			clearSlot(slot)
			slot.Label.Text = MEDAL[rank] .. " 이 자리의 주인공은?\n<font size='14'>전투력을 올려 서 보세요!</font>"
		end
	end
end

return Showcase
