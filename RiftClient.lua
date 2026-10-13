-- RiftClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: RiftClient)
-- 보스러쉬 UI: 포탈 패널(내 기록 / 남은 횟수 / 입장 / 주간 순위표) + 도전 중 점수·시간 HUD + 결과 카드.
-- 서버(RiftService / DungeonService)가 주는 Remote 와 Attribute(RiftScore, RiftLeft)만 보고 동작한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makePanel, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makePanel, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer
local R = Config.Rift

local gui = create("ScreenGui", { Name = "RiftHUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 65 }, player:WaitForChild("PlayerGui"))
local uiScale = create("UIScale", {}, gui)
local function fit()
	local viewport = workspace.CurrentCamera.ViewportSize
	uiScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 720), 0.55, 1)
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

local function comma(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- 큰 수는 줄여서 보여 준다 (점수 = 초 x 피해라 금방 커진다)
local function short(n)
	n = math.floor(n)
	local units = { { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, unit in ipairs(units) do
		if n >= unit[1] then return string.format("%.2f%s", n / unit[1], unit[2]) end
	end
	return tostring(n)
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

------------------------------------------------------------
-- 포탈 패널
------------------------------------------------------------
local panel = makePanel({
	Size = UDim2.new(0, 560, 0, 560), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.52, 0),
	BackgroundColor3 = Color3.fromRGB(20, 18, 34), BackgroundTransparency = 0.03, Visible = false, ZIndex = 10,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(230, 100, 180), Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)

makeLabel({ Size = UDim2.new(1, -90, 0, 40), Position = UDim2.new(0, 18, 0, 10), Text = "👹 Boss Rush", Font = Enum.Font.GothamBlack, TextSize = 24,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 170, 225), ZIndex = 11 }, panel)
makeButton({ Size = UDim2.new(0, 64, 0, 30), Position = UDim2.new(1, -78, 0, 14), Text = "Close", BackgroundColor3 = Color3.fromRGB(54, 58, 82), ZIndex = 11 }, panel, function()
	panel.Visible = false
end)
makeLabel({ Size = UDim2.new(1, -36, 0, 44), Position = UDim2.new(0, 18, 0, 52), TextSize = 14, ZIndex = 11, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = string.format("A boss arrives every %d~%ds, and they pile up if you don't take them down. Score = seconds survived x damage dealt. The run ends when you fall (max %d min).",
		R.IntervalMin, R.IntervalStart, R.Duration // 60) }, panel)

local state = nil
local weekLabel = makeLabel({ Size = UDim2.new(1, -36, 0, 22), Position = UDim2.new(0, 18, 0, 100), TextSize = 13, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Text = "" }, panel)
local bestLabel = makeLabel({ Size = UDim2.new(1, -36, 0, 26), Position = UDim2.new(0, 18, 0, 124), TextSize = 16, Font = Enum.Font.GothamBlack, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Text = "" }, panel)
local recordLabel = makeLabel({ Size = UDim2.new(1, -36, 0, 22), Position = UDim2.new(0, 18, 0, 152), TextSize = 13, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Text = "" }, panel)
local leftLabel = makeLabel({ Size = UDim2.new(1, -36, 0, 22), Position = UDim2.new(0, 18, 0, 176), TextSize = 14, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Text = "" }, panel)

-- 주간 순위표
makeLabel({ Size = UDim2.new(1, -36, 0, 20), Position = UDim2.new(0, 18, 0, 204), TextSize = 14, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11,
	TextColor3 = Color3.fromRGB(255, 225, 110), Text = "🏆 Weekly Ranking" }, panel)
local boardFrame = create("Frame", { Size = UDim2.new(1, -36, 0, 150), Position = UDim2.new(0, 18, 0, 226), BackgroundColor3 = Color3.fromRGB(38, 24, 58), BorderSizePixel = 0, ZIndex = 11 }, panel)
rounded(boardFrame, 10)
local boardLines = {}
for index = 1, R.RankShown do
	local column = (index - 1) // 5
	local row = (index - 1) % 5
	boardLines[index] = makeLabel({
		Size = UDim2.new(0.5, -14, 0, 26), Position = UDim2.new(column * 0.5, 10, 0, 6 + row * 28), TextSize = 12, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Text = "",
	}, boardFrame)
end
local boardNote = makeLabel({ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 1, -24), TextSize = 11, TextColor3 = Color3.fromRGB(170, 176, 208), ZIndex = 12, Text = "" }, boardFrame)

-- 등급 보상 (쓰러뜨린 보스 수 기준)
local tierText = {}
for _, tier in ipairs(R.Tiers) do
	table.insert(tierText, string.format("%s %d+", tier.Icon, tier.Min))
end
makeLabel({ Size = UDim2.new(1, -36, 0, 36), Position = UDim2.new(0, 18, 0, 384), TextSize = 12, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 11,
	Text = "Tier rewards by bosses defeated (gold · tickets · time skip):\n" .. table.concat(tierText, "   ") }, panel)
local tierRewardLabel = makeLabel({ Size = UDim2.new(1, -36, 0, 22), Position = UDim2.new(0, 18, 0, 424), TextSize = 12, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Text = "" }, panel)

local startButton = makeButton({
	Size = UDim2.new(1, -36, 0, 56), Position = UDim2.new(0, 18, 0, 458), Text = "⚔ Enter the Boss Rush", TextSize = 17, Font = Enum.Font.GothamBlack,
	BackgroundColor3 = Color3.fromRGB(230, 70, 150), ZIndex = 11,
}, panel, function()
	Remotes.Rift:FireServer("Start")
	panel.Visible = false
end)
makeLabel({ Size = UDim2.new(1, -36, 0, 30), Position = UDim2.new(0, 18, 0, 520), TextSize = 11, TextColor3 = Color3.fromRGB(190, 190, 215), ZIndex = 11,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "💡 Boss HP follows your own damage. Dash through shots for NEAR MISS, and aim at the yellow weak-spot orb (x3 damage)." }, panel)

local function refresh()
	if not state then return end
	local days = math.floor(state.WeekEndsIn / 86400)
	local hours = math.floor((state.WeekEndsIn % 86400) / 3600)
	weekLabel.Text = string.format("Ranking resets in <font color='#ffe16e'>%dd %dh</font> · rewards: tier by bosses defeated", days, hours)
	bestLabel.Text = state.WeekBest > 0 and string.format("This week's best  <font color='#ffe16e'>%s pts</font>", short(state.WeekBest)) or "This week's best  ❔ None yet"
	recordLabel.Text = string.format("<font color='#aab0d0'>All-time best %s pts · most bosses %d · longest %s</font>", short(state.Best), state.BestBoss, clock(state.BestTime))
	leftLabel.Text = string.format("Runs left today  <font color='#%s'>%d / %d</font>", state.Left > 0 and "78ff8c" or "ff8c8c", state.Left, state.Max)
	startButton.BackgroundColor3 = state.Left > 0 and Color3.fromRGB(230, 70, 150) or Color3.fromRGB(80, 60, 80)
	for index, line in ipairs(boardLines) do
		local entry = state.Board and state.Board[index]
		if entry then
			local mine = entry.UserId == player.UserId
			line.Text = string.format("<font color='%s'>%d. %s</font>  <font color='#ffe16e'>%s</font>", mine and "#9dffb4" or "#ffffff", entry.Rank, entry.Name, short(entry.Score))
		else
			line.Text = string.format("<font color='#6c7194'>%d. -</font>", index)
		end
	end
	boardNote.Text = state.BoardOk and "" or "Ranking unavailable right now (in Studio, enable API Services)"
	local mine = Config.GetRiftTier(state.BestBoss)
	tierRewardLabel.Text = string.format("Your best tier: %s %s  <font color='#aab0d0'>(%d bosses)</font>", mine.Icon, mine.Name, state.BestBoss)
end

Remotes.Rift.OnClientEvent:Connect(function(action, data)
	if action == "Open" or action == "State" then
		state = data
		refresh()
		if action == "Open" then
			panel.Visible = true
		end
	end
end)

------------------------------------------------------------
-- 도전 중 HUD: 점수 + 남은 시간
------------------------------------------------------------
local hud = makePanel({
	Name = "RiftScore", Size = UDim2.new(0, 330, 0, 64), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
	BackgroundColor3 = Color3.fromRGB(20, 18, 34), BackgroundTransparency = 0.1, Visible = false, ZIndex = 5,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(230, 100, 180), Thickness = 1.5, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hud)
local scoreLabel = makeLabel({ Size = UDim2.new(0.62, 0, 0, 34), Position = UDim2.new(0, 12, 0, 2), TextSize = 22, Font = Enum.Font.GothamBlack, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 110), ZIndex = 6, Text = "0" }, hud)
local timeLabel = makeLabel({ Size = UDim2.new(0.38, -12, 0, 34), Position = UDim2.new(0.62, 0, 0, 2), TextSize = 22, Font = Enum.Font.GothamBlack,
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6, Text = "" }, hud)
local subLabel = makeLabel({ Size = UDim2.new(1, -24, 0, 22), Position = UDim2.new(0, 12, 0, 36), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(205, 210, 235), ZIndex = 6, Text = "" }, hud)
local shownScore = 0
RunService.RenderStepped:Connect(function(dt)
	local left = player:GetAttribute("RiftLeft") or 0
	local active = player:GetAttribute("Zone") == "Dungeon" and left > 0
	hud.Visible = active
	if not active then
		shownScore = 0
		return
	end
	local score = player:GetAttribute("RiftScore") or 0
	shownScore += (score - shownScore) * math.min(1, dt * 10) -- 점수가 촤르륵 올라간다
	scoreLabel.Text = string.format("👹 %s", short(shownScore + 0.5))
	local elapsed = R.Duration - left
	timeLabel.Text = clock(elapsed)
	timeLabel.TextColor3 = left <= 30 and Color3.fromRGB(255, 190, 110) or Color3.new(1, 1, 1)
	local nextIn = player:GetAttribute("RiftNext") or 0
	subLabel.Text = string.format("Bosses %d · Damage %s · Next boss %ds", player:GetAttribute("RiftBosses") or 0, short(player:GetAttribute("RiftDealt") or 0), nextIn)
end)

------------------------------------------------------------
-- 결과 카드
------------------------------------------------------------
Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action ~= "Result" or typeof(data) ~= "table" or not data.Rift then return end
	local info = data.Rift
	local old = gui:FindFirstChild("RiftResult")
	if old then old:Destroy() end
	local card = makePanel({
		Name = "RiftResult", Size = UDim2.new(0, 480, 0, 340), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0),
		BackgroundColor3 = Color3.fromRGB(20, 18, 34), BackgroundTransparency = 0.02, ZIndex = 30,
	}, gui)
	create("UIStroke", { Color = info.NewWeekBest and Color3.fromRGB(255, 225, 90) or Color3.fromRGB(255, 90, 180), Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 12), Text = "👹 Boss Rush Results", Font = Enum.Font.GothamBlack, TextSize = 22, ZIndex = 31 }, card)
	local scoreText = makeLabel({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0, 52), Text = "0", Font = Enum.Font.GothamBlack, TextSize = 44,
		TextColor3 = Color3.fromRGB(255, 225, 110), ZIndex = 31 }, card)
	makeLabel({ Size = UDim2.new(1, -30, 0, 26), Position = UDim2.new(0, 15, 0, 120), TextSize = 15, ZIndex = 31,
		Text = string.format("⏱ %s survived  ×  💥 %s damage", clock(info.Seconds or 0), short(info.Dealt or 0)) }, card)
	makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 150), Text = string.format("%s %s Tier · %d bosses defeated", info.TierIcon or "", info.Tier or "", info.Bosses or 0), Font = Enum.Font.GothamBlack,
		TextSize = 18, ZIndex = 31 }, card)
	if info.NewWeekBest then
		makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 184), Text = "🏆 NEW WEEKLY BEST! Ranking updated", Font = Enum.Font.GothamBlack, TextSize = 17,
			TextColor3 = Color3.fromRGB(255, 240, 120), ZIndex = 31 }, card)
	else
		makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 184), Text = string.format("Weekly best: %s pts", short(info.WeekBest or 0)), TextSize = 15, ZIndex = 31 }, card)
	end
	local rewardParts = { string.format("💰 %s G", comma(data.Gold or 0)) }
	if (data.Tickets or 0) > 0 then table.insert(rewardParts, string.format("🎫 %d", data.Tickets)) end
	if (info.TimeSkip or 0) > 0 then table.insert(rewardParts, string.format("⏱ %dm", info.TimeSkip // 60)) end
	makeLabel({ Size = UDim2.new(1, -30, 0, 30), Position = UDim2.new(0, 15, 0, 226), Text = "Reward  " .. table.concat(rewardParts, "  ·  "), TextSize = 15, ZIndex = 31 }, card)
	makeButton({ Size = UDim2.new(0, 150, 0, 40), Position = UDim2.new(0.5, -75, 1, -54), Text = "OK", ZIndex = 31 }, card, function()
		card:Destroy()
	end)
	-- 점수가 촤르륵 올라간다
	task.spawn(function()
		local started = os.clock()
		while card.Parent and os.clock() - started < 1.2 do
			local t = (os.clock() - started) / 1.2
			scoreText.Text = short((info.Score or 0) * (1 - (1 - t) ^ 3))
			task.wait()
		end
		if card.Parent then scoreText.Text = short(info.Score or 0) end
	end)
	task.delay((data.ReturnDelay or 6) + 8, function()
		if card.Parent then card:Destroy() end
	end)
end)
