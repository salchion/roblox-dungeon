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

local function makeLabel(parent, offsetY)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = parent.Position + Vector3.new(0, offsetY, 0)
	part.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 190, 0, 62)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 40 -- 가까이 와야 읽힌다 (멀리서 다른 글자와 겹치는 것 방지)
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

function Showcase.Init(boardCFrame)
	folder = Instance.new("Folder")
	folder.Name = "Showcase"
	folder.Parent = workspace:FindFirstChild("Lobby") or workspace

	local look = Vector3.new(boardCFrame.LookVector.X, 0, boardCFrame.LookVector.Z).Unit
	local right = look:Cross(Vector3.yAxis)
	local base = Vector3.new(boardCFrame.Position.X, 0, boardCFrame.Position.Z) + look * 16

	-- 가운데가 1등, 좌우가 2등 / 3등 (2등이 왼쪽)
	local offsets = { 0, -10, 10 }
	local heights = { 4.5, 3.2, 2.4 }
	for rank = 1, 3 do
		local position = base + right * offsets[rank]
		local ground = groundAt(position)
		local pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal" .. rank
		pedestal.Anchored = true
		pedestal.Size = Vector3.new(7, heights[rank], 7)
		pedestal.Position = Vector3.new(position.X, ground + heights[rank] / 2, position.Z)
		pedestal.Color = MEDAL_COLORS[rank]
		pedestal.Material = Enum.Material.Marble
		pedestal.Parent = folder
		local glow = Instance.new("PointLight")
		glow.Range = 18
		glow.Brightness = 1.2
		glow.Color = MEDAL_COLORS[rank]
		glow.Parent = pedestal

		slots[rank] = {
			Pedestal = pedestal, Look = look, Key = nil, Model = nil, Weapon = nil,
			Label = makeLabel(pedestal, heights[rank] / 2 + 15), -- 아바타 머리 위로 높이 띄운다
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

	local top = slot.Pedestal.Position + Vector3.new(0, slot.Pedestal.Size.Y / 2, 0)

	-- 무기 모형 (진화 단계 미리보기 모델 복제)
	local previews = ReplicatedStorage:FindFirstChild("WeaponPreviews")
	local source = previews and previews:FindFirstChild("W" .. Config.GetWeaponTierIndex(level))
	if source then
		local weapon = source:Clone()
		weapon:PivotTo(CFrame.lookAt(top + Vector3.new(0, 7, 0) + slot.Look * 0, top + Vector3.new(0, 7, 0) + slot.Look) * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, 0, 0))
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
		model:PivotTo(CFrame.lookAt(top + Vector3.new(0, 3.2, 0), top + Vector3.new(0, 3.2, 0) + slot.Look))
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
