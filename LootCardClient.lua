-- LootCardClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: LootCardClient)
-- 영웅 이상 장비를 얻으면 화면 오른쪽에 "획득 카드"가 뜬다:
--   등급 / 이름 -> 기본 능력치 -> 옵션 줄(◆)이 하나씩 "착, 착" 튀어나온다 -> 유니크 / 세트 -> 지금 장비보다 좋으면 "▲ 점수 +N"
-- 높은 등급일수록 옵션 줄이 많아서(영웅 2 · 전설 3 · 신화 4) "스탯이 쏟아지는" 느낌이 난다. 여러 개를 얻으면 차례대로 보여 준다.
-- 서버: InventoryService.Add 가 Remotes.Inventory "Got" 을 보낸다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local okSound, SoundBank = pcall(function() return require(ReplicatedStorage:WaitForChild("SoundBank", 10)) end)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "LootCardGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function new(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do object[key] = value end
	object.Parent = parent
	return object
end
local function sound(key, opts)
	if okSound and SoundBank.Has and SoundBank.Has(key) then pcall(SoundBank.Play, game:GetService("SoundService"), key, opts) end
end
local function hex(color)
	return color:ToHex()
end

local queue, showing = {}, false

local function line(card, y, text, size, color)
	local label = new("TextLabel", {
		Size = UDim2.new(1, -24, 0, size + 8), Position = UDim2.new(0, 34, 0, y), BackgroundTransparency = 1, RichText = true, Text = text,
		TextSize = size, Font = Enum.Font.GothamBold, TextColor3 = color or Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1, TextStrokeTransparency = 0.6, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3,
	}, card)
	-- 오른쪽에서 튀어 들어오며 나타난다
	TweenService:Create(label, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 14, 0, y), TextTransparency = 0 }):Play()
	return label
end

local function show(data)
	local color = Config.Gear.RarityColors[data.Rarity] or Color3.new(1, 1, 1)
	local lines = 2 + #(data.Affixes or {}) + (data.Unique and 1 or 0) + (data.Set and 1 or 0) + 1
	local height = 64 + lines * 22
	local card = new("Frame", {
		Size = UDim2.new(0, 300, 0, height), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 340, 0.55, 0),
		BackgroundColor3 = Color3.fromRGB(18, 18, 30), BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 2,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 14) }, card)
	local stroke = new("UIStroke", { Color = color, Thickness = data.Rarity >= 5 and 3 or 2 }, card)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(Color3.fromRGB(18, 18, 30), 0.55), Color3.fromRGB(18, 18, 30)) }, card)
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(1, -18, 0.55, 0) }):Play()
	if data.Rarity >= 5 then -- 신화: 테두리 무지개
		local rainbow = new("UIGradient", { Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 120)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 200, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
		}) }, stroke)
		TweenService:Create(rainbow, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
	end
	sound(data.Rarity >= 4 and "Rare_Drop" or "Pickup", { Volume = 0.9 })

	local slot = Config.GetGearSlot(data.Slot)
	local name = Config.ItemDisplayName(data)
	new("TextLabel", {
		Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 14, 0, 10), BackgroundTransparency = 1, RichText = true, ZIndex = 3,
		Text = string.format("<font color='#%s'><b>%s</b></font>  <font color='#aab0cc'>%s</font>", hex(color), Config.Gear.RarityNames[data.Rarity], slot and slot.Name or ""),
		TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	new("TextLabel", {
		Size = UDim2.new(1, -24, 0, 24), Position = UDim2.new(0, 14, 0, 28), BackgroundTransparency = 1, Text = name, ZIndex = 3,
		TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, card)

	task.wait(0.3)
	local y = 60
	line(card, y, Config.FormatGearStat(data.Slot, Config.GetGearStat(data.Slot, data.Rarity, data.Level or 0)), 14, Color3.fromRGB(235, 235, 245))
	y += 22
	for i, affix in ipairs(data.Affixes or {}) do -- 옵션 줄: 하나씩 "착"
		task.wait(0.16)
		line(card, y, "◆ " .. Config.FormatAffix(affix.Stat, affix.Value), 14, Color3.fromRGB(150, 215, 255))
		sound("UI_Click", { Pitch = 1 + i * 0.12, Volume = 0.8 })
		y += 22
	end
	if data.Unique and Config.Uniques[data.Unique] then
		task.wait(0.25)
		line(card, y, "✦ " .. Config.Uniques[data.Unique].Name, 15, Color3.fromRGB(255, 184, 77))
		sound("Aug_Get", { Volume = 0.6 })
		y += 22
	end
	if data.Set and Config.Sets[data.Set] then
		task.wait(0.12)
		local def = Config.Sets[data.Set]
		line(card, y, (def.Icon or "✦") .. " " .. def.Name, 13, def.Color)
		y += 22
	end
	task.wait(0.15)
	local diff = (data.Score or 0) - (data.WornScore or 0)
	if diff > 0 then
		line(card, y, string.format("▲ Better than equipped  +%d", diff), 13, Color3.fromRGB(120, 255, 150))
	else
		line(card, y, "Stored in your bag", 12, Color3.fromRGB(150, 156, 180))
	end

	task.wait(2.2 + data.Rarity * 0.3)
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1, 340, 0.55, 0) }):Play()
	task.wait(0.32)
	card:Destroy()
end

local function pump()
	if showing then return end
	showing = true
	task.spawn(function()
		while #queue > 0 do
			local data = table.remove(queue, 1)
			local ok, err = pcall(show, data)
			if not ok then warn("[LootCard] " .. tostring(err)) end
		end
		showing = false
	end)
end

Remotes.Inventory.OnClientEvent:Connect(function(action, data)
	if action ~= "Got" or typeof(data) ~= "table" then return end
	if player:GetAttribute("TutorialActive") and (data.Rarity or 0) < 5 then return end -- 튜토리얼 중에는 신화만 (화면이 복잡하지 않게)
	if #queue >= 4 then table.remove(queue, 1) end -- (한꺼번에 많이 얻으면 오래된 것부터 건너뛴다)
	table.insert(queue, data)
	pump()
end)
