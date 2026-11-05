-- OfflineRewardClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: OfflineRewardClient)
-- 자리를 비운 동안 쌓인 방치 골드를 접속하면 눈에 띄는 카드로 보여 준다 (예전엔 작은 안내 글 한 줄이라 못 보고 지나갔다).
-- 서버(IdleService.OnJoin)가 이미 골드를 지급했고, Attribute OfflineReward* 만 알려 준다. 여기서는 보여 주기만 한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local create, rounded, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 220, 110)

local gui = create("ScreenGui", { Name = "OfflineRewardGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60, Enabled = false }, player:WaitForChild("PlayerGui"))
local panel = create("Frame", { Size = UDim2.new(0, 400, 0, 290), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.46, 0), BackgroundColor3 = Color3.fromRGB(22, 20, 38), BackgroundTransparency = 0.02, BorderSizePixel = 0 }, gui)
rounded(panel, 18)
create("UIStroke", { Color = GOLD, Thickness = 2.5, Transparency = 0.15 }, panel)
create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 190)) }, panel)
local scale = create("UIScale", { Scale = 0.8 }, panel)
Kit.medal(panel, { Size = 70, Position = UDim2.new(0.5, -35, 0, 14), Color = GOLD, Icon = "🌙", TextSize = 34, Tier = 4, ZIndex = 3 })
makeLabel({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 90), Text = "🌙 Welcome back!", TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 236, 180), ZIndex = 3 }, panel)
local awayLabel = makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 120), Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(190, 196, 225), ZIndex = 3 }, panel)
local goldLabel = makeLabel({ Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 142), Text = "+0 G", TextSize = 40, Font = Enum.Font.GothamBlack, TextColor3 = GOLD, TextStrokeTransparency = 0.5, ZIndex = 3 }, panel)
local noteLabel = makeLabel({ Size = UDim2.new(1, -40, 0, 34), Position = UDim2.new(0, 20, 0, 202), Text = "", TextSize = 12, RichText = true, TextColor3 = Color3.fromRGB(150, 160, 190), ZIndex = 3 }, panel)
local closeButton = makeButton({ Size = UDim2.new(0, 180, 0, 38), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Text = "OK", TextSize = 15, BackgroundColor3 = Color3.fromRGB(58, 160, 90), ZIndex = 3 }, panel, nil)

local token = 0
local function close()
	token += 1
	gui.Enabled = false
end
closeButton.Activated:Connect(close)

local function commaText(n)
	return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function show()
	local gold = player:GetAttribute("OfflineRewardGold") or 0
	if gold <= 0 then return end
	token += 1
	local mine = token
	awayLabel.Text = "⏱ " .. Config.FormatDuration(player:GetAttribute("OfflineRewardSeconds") or 0)
	local lines = { "Offline income is 60% of resting income, up to the cap" }
	if player:GetAttribute("OfflineRewardBoost") then table.insert(lines, "✨ Idle Booster applied") end
	if player:GetAttribute("OfflineRewardCapped") then table.insert(lines, "<font color='#ff9a6e'>⚠ Cap reached — raise it in the Shop</font>") end
	noteLabel.Text = table.concat(lines, "\n")
	goldLabel.Text = "+0 G"
	scale.Scale = 0.8
	gui.Enabled = true
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	pcall(SoundBank.Play, game:GetService("SoundService"), "Rare_Drop")
	task.spawn(function() -- 골드 숫자가 올라간다
		local started = os.clock()
		while token == mine and os.clock() - started < 1.3 do
			local t = (os.clock() - started) / 1.3
			goldLabel.Text = "+" .. commaText(gold * (1 - (1 - t) ^ 3)) .. " G"
			task.wait()
		end
		if token == mine then goldLabel.Text = "+" .. commaText(gold) .. " G" end
	end)
	task.delay(12, function() if token == mine then close() end end)
end

player:GetAttributeChangedSignal("OfflineRewardTick"):Connect(show)
task.defer(function()
	if (player:GetAttribute("OfflineRewardTick") or 0) > 0 then show() end -- (스크립트가 늦게 켜졌을 때)
end)
