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

local function groundAt(position)
	local result = workspace:Raycast(Vector3.new(position.X, 60, position.Z), Vector3.new(0, -120, 0))
	return result and result.Position.Y or position.Y
end

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

-- 공중에 떠 있는 "하늘의 명예의 전당": 광장 북쪽 하늘에 순위별 떠 있는 발판 위에 랭커 아바타가 크게 서 있고
-- 이름 / 전투력 / 무기가 머리 위에 보인다. 어디서든 올려다보면 보인다.
function Showcase.Init(_boardCFrame)
	folder = Instance.new("Folder")
	folder.Name = "Showcase"
	folder.Parent = workspace:FindFirstChild("Lobby") or workspace

	local look = Vector3.new(0, 0, 1) -- 광장(남쪽)을 바라본다
	-- 가운데가 1등(가장 높음), 좌우가 2등(왼쪽) / 3등(오른쪽)
	local spots = {
		Vector3.new(0, 58, 34),
		Vector3.new(-32, 47, 38),
		Vector3.new(32, 47, 38),
	}
	for rank = 1, 3 do
		local spot = spots[rank]
		local ground = groundAt(spot)
		local platform = Instance.new("Part")
		platform.Name = "SkyPlatform" .. rank
		platform.Shape = Enum.PartType.Cylinder
		platform.Anchored = true
		platform.Size = Vector3.new(2, 18, 18)
		platform.CFrame = CFrame.new(spot) * CFrame.Angles(0, 0, math.rad(90))
		platform.Color = MEDAL_COLORS[rank]
		platform.Material = Enum.Material.Neon
		platform.Parent = folder
		local glow = Instance.new("PointLight")
		glow.Range = 40
		glow.Brightness = 1.6
		glow.Color = MEDAL_COLORS[rank]
		glow.Parent = platform
		-- 발판 아래로 내려오는 빛줄기 (지상에서도 어디에 떠 있는지 보인다)
		local beamLength = spot.Y - ground
		local beam = Instance.new("Part")
		beam.Name = "SkyBeam" .. rank
		beam.Shape = Enum.PartType.Cylinder
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.Size = Vector3.new(beamLength, 5, 5)
		beam.CFrame = CFrame.new(spot.X, ground + beamLength / 2, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
		beam.Color = MEDAL_COLORS[rank]
		beam.Material = Enum.Material.Neon
		beam.Transparency = 0.86
		beam.Parent = folder

		slots[rank] = {
			Platform = platform, Top = spot + Vector3.new(0, 1, 0), Scale = 2.4, Look = look, Key = nil, Model = nil, Weapon = nil,
			Label = makeLabel(platform, 22, 420),
		}
		slots[rank].Label.Text = MEDAL[rank] .. " 비어 있음"
	end

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
		local weaponSpot = top + Vector3.new(11, 8, 0) -- 아바타 옆 허공에 크게 떠 있다
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
		local standAt = top + Vector3.new(0, 3.2 * slot.Scale, 0)
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
			slot.Label.Text = MEDAL[rank] .. " 비어 있음"
		end
	end
end

return Showcase
