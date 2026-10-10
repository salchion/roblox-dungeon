-- RiftClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: RiftClient)
-- 심연 도전 UI: 포탈 패널(최고 기록 / 남은 횟수 / 도전 / 소탕) + 도전 중 점수·시간 HUD + 결과 카드.
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

------------------------------------------------------------
-- 포탈 패널
------------------------------------------------------------
local panel = makePanel({
	Size = UDim2.new(0, 560, 0, 540), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.52, 0),
	BackgroundColor3 = Color3.fromRGB(20, 18, 34), BackgroundTransparency = 0.03, Visible = false, ZIndex = 10,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(230, 100, 180), Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)

makeLabel({ Size = UDim2.new(1, -90, 0, 40), Position = UDim2.new(0, 18, 0, 10), Text = "🌀 심연 도전", Font = Enum.Font.GothamBlack, TextSize = 28,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 170, 225), ZIndex = 11 }, panel)
makeButton({ Size = UDim2.new(0, 64, 0, 30), Position = UDim2.new(1, -78, 0, 14), Text = "닫기", BackgroundColor3 = Color3.fromRGB(54, 58, 82), ZIndex = 11 }, panel, function()
	panel.Visible = false
end)
makeLabel({ Size = UDim2.new(1, -36, 0, 44), Position = UDim2.new(0, 18, 0, 54), TextSize = 16, ZIndex = 11, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = string.format("%d초 동안 버티며 점수를 쌓아요. 처치 + 콤보 + 대시로 아슬아슬하게 피하기(NEAR MISS)가 점수예요!", R.Duration) }, panel)

local state = nil
-- 심연 깊이 선택: 필드를 밀면 8까지 열리고, 그 뒤는 골드 등급 이상을 기록하면 다음 깊이가 열린다 (끝없는 후반 목표)
local depthLabel = makeLabel({ Size = UDim2.new(1, -150, 0, 34), Position = UDim2.new(0, 75, 0, 100), TextSize = 22, Font = Enum.Font.GothamBlack, RichText = true, ZIndex = 11, Text = "" }, panel)
local depthPrev = makeButton({ Size = UDim2.new(0, 44, 0, 34), Position = UDim2.new(0, 18, 0, 100), Text = "◀", TextSize = 20, BackgroundColor3 = Color3.fromRGB(80, 60, 110), ZIndex = 11 }, panel, function()
	if state and state.Depth > 1 then Remotes.Rift:FireServer("SetDepth", state.Depth - 1) end
end)
local depthNext = makeButton({ Size = UDim2.new(0, 44, 0, 34), Position = UDim2.new(1, -62, 0, 100), Text = "▶", TextSize = 20, BackgroundColor3 = Color3.fromRGB(80, 60, 110), ZIndex = 11 }, panel, function()
	if state and state.Depth < state.Unlocked then Remotes.Rift:FireServer("SetDepth", state.Depth + 1) end
end)
local depthInfo = makeLabel({ Size = UDim2.new(1, -36, 0, 22), Position = UDim2.new(0, 18, 0, 136), TextSize = 14, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Text = "" }, panel)

local bestLabel = makeLabel({ Size = UDim2.new(1, -36, 0, 34), Position = UDim2.new(0, 18, 0, 164), TextSize = 22, Font = Enum.Font.GothamBlack, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Text = "" }, panel)
local leftLabel = makeLabel({ Size = UDim2.new(1, -36, 0, 26), Position = UDim2.new(0, 18, 0, 196), TextSize = 17, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Text = "" }, panel)

local tierList = create("Frame", { Size = UDim2.new(1, -36, 0, 150), Position = UDim2.new(0, 18, 0, 228), BackgroundColor3 = Color3.fromRGB(38, 24, 58), BorderSizePixel = 0, ZIndex = 11 }, panel)
rounded(tierList, 10)
local tierLines = {}
for index, tier in ipairs(R.Tiers) do
	local reward = string.format("%d G", tier.Gold)
	if tier.Tickets > 0 then reward ..= string.format(" · 🎫%d", tier.Tickets) end
	if tier.TimeSkip > 0 then reward ..= string.format(" · ⏱%d분", tier.TimeSkip // 60) end
	tierLines[index] = makeLabel({
		Size = UDim2.new(1, -20, 0, 23), Position = UDim2.new(0, 12, 0, 5 + (index - 1) * 24), TextSize = 15, RichText = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12,
		Text = string.format("%s %s  <font color='#aab0d0'>%s점~</font>  →  %s", tier.Icon, tier.Name, comma(tier.Min), reward),
	}, tierList)
end

local startButton = makeButton({
	Size = UDim2.new(0.5, -24, 0, 56), Position = UDim2.new(0, 18, 0, 392), Text = string.format("⚔ 도전 시작\n(%d초)", R.Duration), TextSize = 18, Font = Enum.Font.GothamBlack,
	BackgroundColor3 = Color3.fromRGB(230, 70, 150), ZIndex = 11,
}, panel, function()
	Remotes.Rift:FireServer("Start")
	panel.Visible = false
end)
local sweepButton = makeButton({
	Size = UDim2.new(0.5, -24, 0, 56), Position = UDim2.new(0.5, 6, 0, 392), Text = string.format("⚡ 소탕\n(최고 등급 보상의 %d%%)", math.floor(R.SweepRate * 100)), TextSize = 17, Font = Enum.Font.GothamBlack,
	BackgroundColor3 = Color3.fromRGB(70, 120, 230), ZIndex = 11,
}, panel, function()
	Remotes.Rift:FireServer("Sweep")
end)
makeLabel({ Size = UDim2.new(1, -36, 0, 50), Position = UDim2.new(0, 18, 0, 460), TextSize = 14, TextColor3 = Color3.fromRGB(190, 190, 215), ZIndex = 11,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "💡 도전과 소탕은 하루 횟수를 함께 써요 (매일 초기화). 직접 최고 점수를 올릴수록 소탕 보상도 커져요!" }, panel)

local function refresh()
	if not state then return end
	depthLabel.Text = string.format("🌀 심연 깊이 <font color='#ffe16e'>%d</font>", state.Depth)
	depthPrev.BackgroundColor3 = state.Depth > 1 and Color3.fromRGB(110, 80, 150) or Color3.fromRGB(55, 45, 70)
	depthNext.BackgroundColor3 = state.Depth < state.Unlocked and Color3.fromRGB(110, 80, 150) or Color3.fromRGB(55, 45, 70)
	local unlockHint
	if state.Unlocked <= state.ClearedZone + 1 and state.Unlocked < 9 then
		unlockHint = string.format("다음 깊이: 필드 관문을 더 열면 깊이 %d 까지", state.Unlocked + 1)
	else
		unlockHint = string.format("다음 깊이 %d: 깊이 %d 에서 🥇골드 등급 이상 달성하면 열려요", state.Unlocked + 1, state.Unlocked)
	end
	depthInfo.Text = string.format("보상 <font color='#78ff8c'>x%.1f</font>  ·  열린 깊이 %d  ·  <font color='#aab0d0'>%s</font>", state.Reward, state.Unlocked, state.Unlocked >= state.MaxDepth and "최대 깊이!" or unlockHint)
	bestLabel.Text = state.Best > 0 and string.format("내 최고 기록  %s %s  <font color='#ffe16e'>%s점</font>", state.TierIcon, state.TierName, comma(state.Best)) or "내 최고 기록  ❔ 아직 없어요"
	leftLabel.Text = string.format("오늘 남은 횟수  <font color='#%s'>%d / %d</font>", state.Left > 0 and "78ff8c" or "ff8c8c", state.Left, state.Max)
	startButton.BackgroundColor3 = state.Left > 0 and Color3.fromRGB(230, 70, 150) or Color3.fromRGB(80, 60, 80)
	sweepButton.BackgroundColor3 = (state.Left > 0 and state.Best > 0) and Color3.fromRGB(70, 120, 230) or Color3.fromRGB(60, 66, 90)
	local mine = Config.GetRiftTier(state.Best)
	for index, tier in ipairs(R.Tiers) do
		tierLines[index].TextTransparency = 0
		tierLines[index].TextColor3 = (state.Best > 0 and tier == mine) and Color3.fromRGB(255, 240, 150) or Color3.new(1, 1, 1)
	end
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
local scoreLabel = makeLabel({ Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0, 12, 0, 0), TextSize = 26, Font = Enum.Font.GothamBlack, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 110), ZIndex = 6, Text = "0" }, hud)
local timeLabel = makeLabel({ Size = UDim2.new(0.4, -12, 1, 0), Position = UDim2.new(0.6, 0, 0, 0), TextSize = 26, Font = Enum.Font.GothamBlack,
	TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6, Text = "" }, hud)
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
	scoreLabel.Text = string.format("🌀 %s", comma(shownScore + 0.5))
	timeLabel.Text = string.format("%d:%02d", math.floor(left / 60), left % 60)
	timeLabel.TextColor3 = left <= 10 and Color3.fromRGB(255, 110, 110) or Color3.new(1, 1, 1)
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
		Name = "RiftResult", Size = UDim2.new(0, 480, 0, 300), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0),
		BackgroundColor3 = Color3.fromRGB(20, 18, 34), BackgroundTransparency = 0.02, ZIndex = 30,
	}, gui)
	create("UIStroke", { Color = info.NewBest and Color3.fromRGB(255, 225, 90) or Color3.fromRGB(255, 90, 180), Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 12), Text = string.format("🌀 심연 깊이 %d 결과", info.Depth or 1), Font = Enum.Font.GothamBlack, TextSize = 26, ZIndex = 31 }, card)
	local scoreText = makeLabel({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0, 56), Text = "0", Font = Enum.Font.GothamBlack, TextSize = 56,
		TextColor3 = Color3.fromRGB(255, 225, 110), ZIndex = 31 }, card)
	makeLabel({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 128), Text = string.format("%s %s 등급", info.TierIcon or "", info.Tier or ""), Font = Enum.Font.GothamBlack,
		TextSize = 24, ZIndex = 31 }, card)
	if info.NewBest then
		makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 164), Text = "🏆 NEW BEST! 소탕 보상도 올라갔어요", Font = Enum.Font.GothamBlack, TextSize = 20,
			TextColor3 = Color3.fromRGB(255, 240, 120), ZIndex = 31 }, card)
	else
		makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 164), Text = string.format("내 최고 %s점", comma(info.Best or 0)), TextSize = 18, ZIndex = 31 }, card)
	end
	local rewardParts = { string.format("💰 %s G", comma(data.Gold or 0)) }
	if (data.Tickets or 0) > 0 then table.insert(rewardParts, string.format("🎫 %d", data.Tickets)) end
	if (info.TimeSkip or 0) > 0 then table.insert(rewardParts, string.format("⏱ %d분", info.TimeSkip // 60)) end
	makeLabel({ Size = UDim2.new(1, -30, 0, 30), Position = UDim2.new(0, 15, 0, 204), Text = "보상  " .. table.concat(rewardParts, "  ·  "), TextSize = 18, ZIndex = 31 }, card)
	if info.UnlockedNext then
		makeLabel({ Size = UDim2.new(1, -30, 0, 30), Position = UDim2.new(0, 15, 0, 238), Text = string.format("🔓 심연 깊이 %d 이(가) 열렸어요!", info.UnlockedNext), Font = Enum.Font.GothamBlack, TextSize = 20,
			TextColor3 = Color3.fromRGB(150, 255, 190), ZIndex = 31 }, card)
	end
	makeButton({ Size = UDim2.new(0, 150, 0, 40), Position = UDim2.new(0.5, -75, 1, -54), Text = "확인", ZIndex = 31 }, card, function()
		card:Destroy()
	end)
	-- 점수가 촤르륵 올라간다
	task.spawn(function()
		local started = os.clock()
		while card.Parent and os.clock() - started < 1.2 do
			local t = (os.clock() - started) / 1.2
			scoreText.Text = comma((info.Score or 0) * (1 - (1 - t) ^ 3))
			task.wait()
		end
		if card.Parent then scoreText.Text = comma(info.Score or 0) end
	end)
	task.delay((data.ReturnDelay or 6) + 8, function()
		if card.Parent then card:Destroy() end
	end)
end)
