-- FeverResultClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: FeverResultClient)
-- 피버 타임 결과 카드: 황금빛 테두리가 돌고, 번 골드가 0 부터 차오르며, 금화가 위에서 쏟아진다.
-- 서버(DungeonService)의 Remotes.Dungeon "Result" 에 Fever 정보가 있을 때만 그린다 (일반 던전 결과 카드는 PlayerClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local okSound, SoundBank = pcall(function() return require(ReplicatedStorage:WaitForChild("SoundBank", 10)) end)
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(255, 205, 70)

local function new(class, props, parent)
	local obj = Instance.new(class)
	for key, value in pairs(props) do obj[key] = value end
	obj.Parent = parent
	return obj
end
local function label(props, parent)
	local base = { BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, RichText = true }
	for key, value in pairs(props) do base[key] = value end
	return new("TextLabel", base, parent)
end

local function show(result)
	local fever = result.Fever
	local old = playerGui:FindFirstChild("FeverResult")
	if old then old:Destroy() end
	local gui = new("ScreenGui", { Name = "FeverResult", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 45 }, playerGui)
	local dim = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()

	local card = new("Frame", { Size = UDim2.fromOffset(420, 300), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(40, 28, 16), BorderSizePixel = 0 }, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 18) }, card)
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(120, 80, 30), Color3.fromRGB(36, 24, 14)), Rotation = 90 }, card)
	local stroke = new("UIStroke", { Color = GOLD, Thickness = 4 }, card)
	local shine = new("UIGradient", { Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 170)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 130, 30)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 170)),
	}) }, stroke)
	local scale = new("UIScale", { Scale = 0.5 }, card)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	label({ Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 14), Text = "🌟 FEVER TIME!", TextSize = 34, TextColor3 = GOLD }, card)
	label({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 62), Text = "Gold earned", TextSize = 14, TextColor3 = Color3.fromRGB(240, 220, 170), Font = Enum.Font.GothamBold }, card)
	local goldText = label({ Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 84), Text = "💰 0 G", TextSize = 44, TextColor3 = Color3.fromRGB(255, 225, 110) }, card)
	label({ Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 152), Text = string.format("⚔ Kills  <font color='#ffe16e'>%d</font>", fever.Kills or 0), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left }, card)
	label({ Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 182), Text = string.format("🔥 Best combo  <font color='#ffe16e'>%d</font>", fever.BestCombo or 0), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left }, card)
	if (result.Tickets or 0) > 0 then
		label({ Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 212), Text = string.format("🎫 Tickets  <font color='#d9a6ff'>+%d</font>", result.Tickets), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left }, card)
	end
	local footer = label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -34), Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(220, 210, 190), Font = Enum.Font.GothamBold }, card)

	-- 골드가 0 부터 차오른다 (1.2초)
	local total = math.max(0, math.floor(result.Gold or 0))
	task.spawn(function()
		local started = os.clock()
		local lastTick = 0
		while gui.Parent do
			local t = math.min(1, (os.clock() - started) / 1.2)
			goldText.Text = string.format("💰 %d G", math.floor(total * (1 - (1 - t) ^ 3)))
			if okSound and os.clock() - lastTick > 0.08 and t < 1 then
				lastTick = os.clock()
				pcall(function() SoundBank.Play(game:GetService("SoundService"), "Gacha_Tick", { Pitch = 1 + t * 0.8, Volume = 0.5 }) end)
			end
			if t >= 1 then break end
			task.wait()
		end
		if okSound then pcall(function() SoundBank.Play(game:GetService("SoundService"), "Enh_Success", { Volume = 0.7 }) end) end
	end)
	-- 테두리 빛이 돌고, 금화가 위에서 쏟아진다
	task.spawn(function()
		local spawnUntil = os.clock() + 1.6
		while gui.Parent do
			shine.Rotation = (shine.Rotation + 4) % 360
			if os.clock() < spawnUntil and math.random() < 0.6 then
				local coin = label({ Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(math.random(), 0, -0.05, 0), Text = "🪙", TextSize = 22 + math.random(0, 10) }, gui)
				TweenService:Create(coin, TweenInfo.new(1.1 + math.random() * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(coin.Position.X.Scale + (math.random() - 0.5) * 0.1, 0, 1.08, 0), Rotation = math.random(-200, 200) }):Play()
				game:GetService("Debris"):AddItem(coin, 1.9)
			end
			task.wait(0.03)
		end
	end)
	-- 돌아가기 카운트다운
	task.spawn(function()
		for remaining = result.ReturnDelay or 6, 1, -1 do
			if not gui.Parent then return end
			footer.Text = string.format("Returning to the field in %ds", remaining)
			task.wait(1)
		end
		TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0.85 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.delay(0.25, function() gui:Destroy() end)
	end)
end

Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action == "Result" and type(data) == "table" and type(data.Fever) == "table" then
		show(data)
	end
end)
