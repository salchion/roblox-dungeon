-- 던전 3택 카드: 보너스 때 서버가 강화 3장을 보내면(RunChoice) 하나를 고른다. Seconds 안에 안 고르면 서버가 첫 장을 준다
--   오프닝 / 큰 창(ModalOpen) 중에는 띄우지 않는다 (서버가 알아서 첫 장). 이 화면은 보일 때만 켜고 닫으면 끈다
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local gui = Instance.new("ScreenGui")
gui.Name = "RunChoiceGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local W, H = 600, 236
local panel = make("Frame", { Size = UDim2.new(0, W, 0, H), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), BackgroundTransparency = 1 }, gui)
local fit = make("UIScale", {}, panel)
local function refit()
	local size = gui.AbsoluteSize
	if size.X > 0 then fit.Scale = math.min(1, (size.X - 24) / W, (size.Y * 0.5) / H) end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
local title = make("TextLabel", { Size = UDim2.new(1, -120, 0, 26), BackgroundTransparency = 1, Text = "🎁 Pick a boon", TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 130), TextStrokeTransparency = 0.4, TextXAlignment = Enum.TextXAlignment.Left }, panel)
local autoBtn = make("TextButton", { Size = UDim2.new(0, 110, 0, 24), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(40, 42, 62), Text = "", TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true }, panel)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, autoBtn)
local function paintAuto() autoBtn.Text = player:GetAttribute("RunChoiceAuto") == true and "🤖 Auto-pick: ON" or "🤖 Auto-pick: OFF" end
paintAuto()
player:GetAttributeChangedSignal("RunChoiceAuto"):Connect(paintAuto)
autoBtn.Activated:Connect(function() Remotes.Dungeon:FireServer("RunChoiceAuto", player:GetAttribute("RunChoiceAuto") ~= true) end)
local timeBack = make("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(20, 20, 32), BorderSizePixel = 0 }, panel)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, timeBack)
local timeFill = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 205, 110), BorderSizePixel = 0 }, timeBack)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, timeFill)

local current -- { Id, Buttons, Tween }
local function close()
	if current then
		if current.Tween then current.Tween:Cancel() end
		for _, b in ipairs(current.Buttons) do b:Destroy() end
		current = nil
	end
	gui.Enabled = false
end

local function show(data)
	if player:GetAttribute("IntroPlaying") or player:GetAttribute("ModalOpen") then return end -- (서버가 시간 뒤 첫 장을 준다)
	close()
	local buttons = {}
	-- 드래프트(입장 직후 덱 만들기): 제목에 라운드, 위에 지금까지 고른 덱 아이콘
	if data.Draft then
		title.Text = string.format("🃏 Draft %d/%d", data.Draft.Round or 1, data.Draft.Rounds or 8)
		local strip = make("TextLabel", { Size = UDim2.new(1, -120, 0, 20), Position = UDim2.new(0, 160, 0, 3), BackgroundTransparency = 1, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left,
			Text = table.concat(data.Draft.Deck or {}, " ") .. string.rep(" ▫", math.max(0, (data.Draft.Rounds or 8) - #(data.Draft.Deck or {}))) }, panel)
		table.insert(buttons, strip) -- (닫을 때 같이 지운다)
	else
		title.Text = "🎁 Pick a boon"
	end
	local n = #data.Options
	local cw, gap = 190, 15
	local startX = (W - (n * cw + (n - 1) * gap)) / 2
	for i, o in ipairs(data.Options) do
		local color = o.Color or (o.Special and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(120, 200, 255))
		local b = make("TextButton", { Size = UDim2.new(0, cw, 0, 186), Position = UDim2.new(0, startX + (i - 1) * (cw + gap), 0, 46), BackgroundColor3 = Color3.fromRGB(26, 24, 42), Text = "", AutoButtonColor = true }, panel)
		make("UICorner", { CornerRadius = UDim.new(0, 14) }, b)
		make("UIStroke", { Color = color, Thickness = o.Special and 3 or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		make("Frame", { Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = color, BorderSizePixel = 0 }, b)
		make("TextLabel", { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 12), BackgroundTransparency = 1, Text = o.Icon or "✨", TextSize = 38 }, b)
		make("TextLabel", { Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 0, 70), BackgroundTransparency = 1, Text = o.Name or "", TextSize = 15, Font = Enum.Font.GothamBlack, TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.4), TextWrapped = true }, b)
		make("TextLabel", { Size = UDim2.new(1, -16, 0, 64), Position = UDim2.new(0, 8, 0, 112), BackgroundTransparency = 1, Text = o.Desc or "", TextSize = 12, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(205, 200, 230), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, b)
		local id = data.Id
		b.Activated:Connect(function()
			if not current or current.Id ~= id then return end
			Remotes.Dungeon:FireServer("ChooseRunBuff", id, i)
			close()
		end)
		table.insert(buttons, b)
	end
	timeFill.Size = UDim2.new(1, 0, 1, 0)
	local tween = TweenService:Create(timeFill, TweenInfo.new(math.max(0.5, (data.Seconds or 8) - 0.3), Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 1, 0) })
	current = { Id = data.Id, Buttons = buttons, Tween = tween }
	refit()
	gui.Enabled = true
	tween:Play()
	local id = data.Id
	task.delay(data.Seconds or 8, function() if current and current.Id == id then close() end end)
end

Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action == "RunChoice" and type(data) == "table" and data.Options then
		show(data)
	elseif action == "Result" then
		close()
	end
end)
player:GetAttributeChangedSignal("Zone"):Connect(function() if player:GetAttribute("Zone") ~= "Dungeon" then close() end end)
player:GetAttributeChangedSignal("IntroPlaying"):Connect(function() if player:GetAttribute("IntroPlaying") then close() end end)
