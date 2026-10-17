-- ChestOpenClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: ChestOpenClient)
-- 던전 보스를 쓰러뜨린 뒤 "상자를 여는" 연출: 상자가 흔들리다 터지고, 장비가 한 장씩 등급 색으로 펼쳐진다.
--   서버가 보내는 결과(Remotes.Dungeon "Result")의 Loot 목록을 그대로 보여 주기만 한다 (뽑기 / 확률은 서버가 이미 정했다).
--   연출 중에는 Attribute "ChestOpening" 이 켜져 있어서 결과 카드가 전리품 목록을 잠깐 가린다. 화면을 누르면 건너뛴다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makeLabel = Kit.create, Kit.rounded, Kit.makeLabel

local player = Players.LocalPlayer

local gui = create("ScreenGui", { Name = "ChestGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20, Enabled = false }, player:WaitForChild("PlayerGui"))
local dim = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, Text = "", AutoButtonColor = false, ZIndex = 30 }, gui)
local stage = create("Frame", { Size = UDim2.new(0, 560, 0, 300), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 31 }, gui)
local scale = create("UIScale", {}, stage)
local hint = makeLabel({ Size = UDim2.new(1, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Text = "Tap to skip", TextSize = 12, TextColor3 = Color3.fromRGB(190, 195, 220), ZIndex = 32 }, stage)

local function fit()
	local size = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(size.X / 640, size.Y / 380), 0.5, 1.2)
end
fit()

local token = 0
local function close()
	token += 1
	gui.Enabled = false
	player:SetAttribute("ChestOpening", nil)
	for _, child in ipairs(stage:GetChildren()) do
		if child:IsA("GuiObject") and child ~= hint then child:Destroy() end
	end
end
dim.MouseButton1Click:Connect(close)

local function tween(object, time, props, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- 터질 때 사방으로 퍼지는 반짝이
local function sparks(color, count)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.3
		local distance = math.random(120, 230)
		local dot = create("Frame", {
			Size = UDim2.new(0, 10, 0, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -10),
			BackgroundColor3 = color, BorderSizePixel = 0, Rotation = math.random(0, 90), ZIndex = 33,
		}, stage)
		rounded(dot, 3)
		tween(dot, 0.7, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance * 0.7 - 10),
			BackgroundTransparency = 1, Size = UDim2.new(0, 3, 0, 3),
		})
		task.delay(0.8, function() dot:Destroy() end)
	end
end

local function play(loot)
	token += 1
	local mine = token
	close()
	token = mine
	gui.Enabled = true
	player:SetAttribute("ChestOpening", true)
	fit()
	local function alive() return token == mine and gui.Enabled end

	local best = 1
	for _, entry in ipairs(loot) do best = math.max(best, entry.Rarity or 1) end
	local bestColor = Config.Gear.RarityColors[best] or Color3.fromRGB(255, 225, 120)

	-- 1) 상자가 흔들린다 (점점 세게)
	local chest = makeLabel({ Size = UDim2.new(0, 160, 0, 140), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -10), Text = "🎁", TextSize = 110, ZIndex = 33 }, stage)
	local glow = create("UIStroke", { Color = bestColor, Thickness = 0, Transparency = 0.2 }, chest)
	for i = 1, 6 do
		if not alive() then return end
		local amount = 6 + i * 3
		tween(chest, 0.08, { Rotation = (i % 2 == 0 and -amount or amount), Size = UDim2.new(0, 160 + i * 6, 0, 140 + i * 5) })
		task.wait(0.11)
	end
	if not alive() then return end

	-- 2) 터진다: 번쩍임 + 반짝이
	local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2, ZIndex = 34 }, gui)
	tween(flash, 0.35, { BackgroundTransparency = 1 })
	task.delay(0.4, function() flash:Destroy() end)
	tween(chest, 0.25, { Size = UDim2.new(0, 300, 0, 260), TextTransparency = 1, Rotation = 0 })
	sparks(bestColor, 18)
	pcall(SoundBank.Play, SoundService, "Dungeon_Clear")
	task.wait(0.35)
	chest:Destroy()

	-- 2) 장비가 한 장씩 펼쳐진다 (높은 등급일수록 크고 오래 머문다)
	local count = math.max(1, #loot)
	local cardWidth = math.clamp(math.floor(520 / count) - 12, 110, 170)
	for index, entry in ipairs(loot) do
		if not alive() then return end
		local rarity = entry.Rarity or 1
		local color = Config.Gear.RarityColors[rarity] or Color3.new(1, 1, 1)
		local x = (index - (count + 1) / 2) * (cardWidth + 12)
		local card = create("Frame", {
			Size = UDim2.new(0, cardWidth, 0, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, -10),
			BackgroundColor3 = Color3.fromRGB(26, 28, 44), BorderSizePixel = 0, ZIndex = 33, ClipsDescendants = true,
		}, stage)
		rounded(card, 10)
		create("UIStroke", { Color = color, Thickness = rarity >= 4 and 4 or 2, Transparency = 0 }, card)
		makeLabel({ Size = UDim2.new(1, -10, 0, 22), Position = UDim2.new(0, 5, 0, 12), Text = Config.Gear.RarityNames[rarity] or "", Font = Enum.Font.GothamBlack, TextSize = rarity >= 4 and 18 or 15, TextColor3 = color, ZIndex = 34 }, card)
		makeLabel({ Size = UDim2.new(1, -12, 1, -48), Position = UDim2.new(0, 6, 0, 42), Text = entry.Text or "", TextSize = 12, TextWrapped = true, TextColor3 = Color3.fromRGB(235, 238, 250), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 34 }, card)
		tween(card, 0.3, { Size = UDim2.new(0, cardWidth, 0, 150) }, Enum.EasingStyle.Back)
		if rarity >= 4 then
			sparks(color, rarity >= 5 and 22 or 12)
			pcall(SoundBank.Play, SoundService, "Rare_Drop")
		end
		task.wait(rarity >= 5 and 0.95 or (rarity >= 4 and 0.75 or 0.5))
	end
	task.wait(1.4)
	if token == mine then close() end
end

Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action ~= "Result" or typeof(data) ~= "table" or data.Victory ~= true then return end
	local loot = data.Loot
	if typeof(loot) ~= "table" or #loot == 0 then return end
	task.spawn(play, loot)
end)

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if player:GetAttribute("Zone") ~= "Dungeon" and gui.Enabled then close() end
end)
