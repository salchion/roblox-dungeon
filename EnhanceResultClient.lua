-- EnhanceResultClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: EnhanceResultClient)
-- 무기 강화 결과 카드: 강화 창(HUD.EnhancePanel) 위쪽에 "강화 성공 / 실패" 띠 + 무기 칸 + "+12 ➜ +13" + 공격력 변화를 크게 보여 준다.
--   * 창을 가리지 않게 위쪽 무대 자리에만 뜨고, 1.8초 뒤 스르륵 사라진다 (꾹 눌러 연속 강화해도 카드만 새로 바뀐다)
--   * 소리 / 강화 요청은 PlayerClient 가 그대로 한다. 이 스크립트는 결과(Remotes.Enhance)를 보고 그림만 그린다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local WEAPON_ICONS = { Pistol = "🔫", Smg = "🔭", Revolver = "💣", Rifle = "🏹", Shotgun = "✴", Flamer = "📖", Cannon = "🧨", Sniper = "🎯", Rocket = "🚀", Rail = "⚡" }
local GOLD = Color3.fromRGB(230, 196, 120)
local GREEN = Color3.fromRGB(120, 255, 150)
local RED = Color3.fromRGB(255, 120, 120)

local function new(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do object[key] = value end
	object.Parent = parent
	return object
end
local function label(props, parent)
	local base = { BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.35, RichText = true, TextScaled = false }
	for key, value in pairs(props) do base[key] = value end
	return new("TextLabel", base, parent)
end
local function tween(object, time, goal, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end
-- 가운데가 진하고 양끝이 사라지는 가로 띠 / 선 (리본 느낌)
local function fadeBar(props, parent, middle)
	local bar = new("Frame", props, parent)
	bar.BorderSizePixel = 0
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, middle or 0), NumberSequenceKeypoint.new(1, 1) }) }, bar)
	return bar
end

local panel
local token = 0

local function show(ok, summary)
	panel = panel or (player.PlayerGui:FindFirstChild("HUD") and player.PlayerGui.HUD:FindFirstChild("EnhancePanel"))
	if not panel or not panel.Visible then return end
	token += 1
	local mine = token
	local old = panel:FindFirstChild("EnhanceResultCard")
	if old then old:Destroy() end

	local level = player:GetAttribute("WeaponLevel") or 0
	local attempts = summary and summary.Attempts or 1
	local successes = summary and summary.Successes or (ok and 1 or 0)
	local before = math.max(0, level - successes)
	local typeKey = Config.ResolveWeaponType(level, player:GetAttribute("WeaponType"))
	local tier = Config.GetLookTier(level, typeKey)
	local color = tier.Rainbow and Color3.fromRGB(255, 120, 255) or tier.Color
	local success = successes > 0

	local card = new("Frame", {
		Name = "EnhanceResultCard", Size = UDim2.new(1, -24, 0, 236), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 84),
		BackgroundColor3 = Color3.fromRGB(14, 30, 44), BorderSizePixel = 0, ZIndex = 20, Active = false,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 14) }, card)
	new("UIGradient", { Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 18, 28)), ColorSequenceKeypoint.new(0.5, success and Color3.fromRGB(26, 70, 90) or Color3.fromRGB(70, 30, 36)), ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 18, 28)),
	}), Rotation = 90 }, card)
	new("UIStroke", { Color = GOLD, Thickness = 2, Transparency = 0.3 }, card)
	local scale = new("UIScale", { Scale = 0.85 }, card)
	tween(scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)

	-- 제목 띠: 위 / 아래 금선 + 가운데 진한 띠
	fadeBar({ Size = UDim2.new(0.9, 0, 0, 2), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundColor3 = GOLD, ZIndex = 21 }, card, 0)
	fadeBar({ Size = UDim2.new(1, 0, 0, 34), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 13), BackgroundColor3 = Color3.fromRGB(4, 8, 14), ZIndex = 21 }, card, 0.15)
	fadeBar({ Size = UDim2.new(0.9, 0, 0, 2), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), BackgroundColor3 = GOLD, ZIndex = 21 }, card, 0)
	local titleText
	if attempts > 1 then
		titleText = string.format("x%d · %d SUCCESS", attempts, successes)
	else
		titleText = success and "UPGRADE SUCCESS" or "UPGRADE FAILED"
	end
	local title = label({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 13), Text = titleText, TextSize = 26, TextColor3 = success and Color3.fromRGB(255, 240, 200) or RED, ZIndex = 22 }, card)
	title.TextTransparency = 1
	tween(title, 0.25, { TextTransparency = 0 })

	-- 무기 칸: 뒤에서 빛이 퍼지고, 칸 오른쪽 아래에 +강화 수치
	local tileY = 58
	local glow = new("Frame", { Size = UDim2.new(0, 70, 0, 70), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, tileY + 36), BackgroundColor3 = success and color or Color3.fromRGB(120, 60, 60), BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 21 }, card)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
	tween(glow, 0.5, { Size = UDim2.new(0, 150, 0, 110), BackgroundTransparency = 0.75 })
	local tile = new("Frame", { Size = UDim2.new(0, 72, 0, 72), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, tileY), BackgroundColor3 = Color3.fromRGB(30, 26, 44), BorderSizePixel = 0, ZIndex = 23 }, card)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, tile)
	new("UIStroke", { Color = success and color or Color3.fromRGB(150, 150, 170), Thickness = 3 }, tile)
	new("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 150)), Rotation = 90 }, tile)
	label({ Size = UDim2.new(1, 0, 1, -10), Text = WEAPON_ICONS[typeKey] or "🔫", TextSize = 38, ZIndex = 24, TextStrokeTransparency = 1 }, tile)
	label({ Size = UDim2.new(1, -6, 0, 18), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Text = "+" .. level, TextSize = 14, TextColor3 = success and GREEN or Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 24 }, tile)
	if success then -- 빛줄기가 칸을 한 번 쓸고 지나간다
		tile.ClipsDescendants = true
		local shine = new("Frame", { Size = UDim2.new(0, 20, 1.6, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -20, 0.5, 0), Rotation = 20, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 25 }, tile)
		tween(shine, 0.45, { Position = UDim2.new(1, 20, 0.5, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for i = 1, 10 do -- 반짝이 가루
			local angle = i / 10 * math.pi * 2
			local spark = new("Frame", { Size = UDim2.new(0, 6, 0, 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, tileY + 36), BackgroundColor3 = i % 2 == 0 and color or Color3.fromRGB(255, 240, 180), BorderSizePixel = 0, ZIndex = 22, Rotation = 45 }, card)
			tween(spark, 0.6, { Position = UDim2.new(0.5, math.cos(angle) * 90, 0, tileY + 36 + math.sin(angle) * 55), BackgroundTransparency = 1 })
			game:GetService("Debris"):AddItem(spark, 0.7)
		end
	else -- 실패: 칸이 좌우로 흔들린다
		task.spawn(function()
			for i = 1, 6 do
				tile.Position = UDim2.new(0.5, (i % 2 == 0 and 1 or -1) * (7 - i), 0, tileY)
				task.wait(0.035)
			end
			tile.Position = UDim2.new(0.5, 0, 0, tileY)
		end)
	end
	label({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, tileY + 76), Text = Config.GetWeaponName(typeKey, level), TextSize = 14, TextColor3 = color, ZIndex = 22 }, card)

	-- +이전 → +지금 (실패면 그대로 + "Level kept")
	local rowY = tileY + 96
	label({ Size = UDim2.new(0.38, 0, 0, 36), Position = UDim2.new(0, 0, 0, rowY), Text = "+" .. before, TextSize = 30, TextColor3 = Color3.fromRGB(235, 235, 245), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 22 }, card)
	local arrow = label({ Size = UDim2.new(0.24, 0, 0, 36), Position = UDim2.new(0.38, 0, 0, rowY), Text = "→", TextSize = 30, TextColor3 = success and Color3.fromRGB(110, 190, 255) or Color3.fromRGB(130, 130, 150), ZIndex = 22 }, card)
	local after = label({ Size = UDim2.new(0.38, 0, 0, 36), Position = UDim2.new(0.62, 0, 0, rowY), Text = "+" .. level, TextSize = 18, TextColor3 = success and GREEN or Color3.fromRGB(200, 200, 215), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 }, card)
	tween(after, 0.3, { TextSize = 30 }, Enum.EasingStyle.Back)
	if success then
		arrow.Position = UDim2.new(0.36, 0, 0, rowY)
		tween(arrow, 0.3, { Position = UDim2.new(0.38, 0, 0, rowY) }, Enum.EasingStyle.Back)
	end
	-- 공격력 배율 변화
	local now, prev = Config.GetDamageMultiplier(level), Config.GetDamageMultiplier(before)
	fadeBar({ Size = UDim2.new(0.8, 0, 0, 1), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, rowY + 40), BackgroundColor3 = Color3.fromRGB(150, 170, 200), ZIndex = 21 }, card, 0.3)
	local statText
	if success then
		statText = string.format("<font color='#9aa3b8'>⚔ x%.2f</font>    <b>x%.2f</b>    <font color='#78ff8c'>▲%.2f</font>", prev, now, now - prev)
	else
		statText = string.format("⚔ <b>x%.2f</b>    <font color='#9aa3b8'>Level kept</font>", now)
	end
	label({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, rowY + 44), Text = statText, TextSize = 15, Font = Enum.Font.GothamBold, ZIndex = 22 }, card)

	-- 잠시 보여 주고 사라진다 (다음 결과가 오면 새 카드로 바뀐다)
	task.delay(1.8, function()
		if token ~= mine or not card.Parent then return end
		tween(scale, 0.25, { Scale = 0.95 })
		for _, child in ipairs(card:GetDescendants()) do
			if child:IsA("TextLabel") then tween(child, 0.25, { TextTransparency = 1, TextStrokeTransparency = 1 })
			elseif child:IsA("Frame") then tween(child, 0.25, { BackgroundTransparency = 1 })
			elseif child:IsA("UIStroke") then tween(child, 0.25, { Transparency = 1 }) end
		end
		tween(card, 0.25, { BackgroundTransparency = 1 })
		game:GetService("Debris"):AddItem(card, 0.3)
	end)
end

Remotes.Enhance.OnClientEvent:Connect(function(ok, _message, summary)
	task.defer(show, ok, summary) -- (무기 레벨 Attribute 가 먼저 바뀐 다음에 읽게)
end)
