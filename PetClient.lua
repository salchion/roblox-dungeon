-- PetClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: PetClient)
-- 펫 창 (P 키 / 캐릭터 칸의 펫 칸 / 메뉴 > 펫): 골드로 펫 기능 열기 -> 레벨업(기능이 하나씩 늘어남) -> 외형 / 색 고르기.
-- 상태는 서버(MetaService)가 Remotes.Meta "State" 로 보내 준다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local P = Config.Pet

local gui = Instance.new("ScreenGui")
gui.Name = "PetGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 13
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 14
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

local function button(props, parent, callback)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 14
	props.AutoButtonColor = true
	local b = make("TextButton", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	b.Activated:Connect(callback)
	return b
end

local function comma(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local state = nil -- { Pet = { Unlocked, Level, Look, Color }, UnlockedLooks = { [키] = bool } }

local panel = make("Frame", {
	Size = UDim2.new(0, 480, 0, 540), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(26, 28, 42), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIStroke", { Color = Color3.fromRGB(255, 200, 100), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
make("UISizeConstraint", { MaxSize = Vector2.new(480, 540) }, panel)

label({ Size = UDim2.new(1, -90, 0, 30), Position = UDim2.new(0, 16, 0, 10), Text = "🐾 펫", TextSize = 22 }, panel)
button({ Size = UDim2.new(0, 60, 0, 28), Position = UDim2.new(1, -72, 0, 10), BackgroundColor3 = Color3.fromRGB(70, 70, 90), Text = "닫기", TextSize = 13 }, panel, function() panel.Visible = false end)

local scroll = make("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -54), Position = UDim2.new(0, 10, 0, 46), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

local order = 0
local function row(height, color)
	order += 1
	local f = make("Frame", { Size = UDim2.new(1, -6, 0, height), BackgroundColor3 = color or Color3.fromRGB(36, 39, 58), BorderSizePixel = 0, LayoutOrder = order }, scroll)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, f)
	return f
end

local function rebuild()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	order = 0
	local pet = state and state.Pet
	local gold = player:GetAttribute("Gold") or 0

	-- 1) 상태 / 열기 / 레벨업
	local head = row(98, Color3.fromRGB(44, 40, 30))
	if not pet or not pet.Unlocked then
		label({ Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 0, 8), Text = "펫 기능을 열면 펫이 따라다니며 도와줘요.\n골드로 레벨을 올릴 때마다 새 기능이 생겨요!", TextSize = 13, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, head)
		button({ Size = UDim2.new(0, 220, 0, 36), Position = UDim2.new(0, 12, 1, -46), BackgroundColor3 = gold >= P.UnlockCost and Color3.fromRGB(60, 130, 80) or Color3.fromRGB(95, 60, 62),
			Text = string.format("🐾 펫 기능 열기  💰 %s G", comma(P.UnlockCost)), TextSize = 15 }, head, function()
			Remotes.Meta:FireServer("PetUnlock")
		end)
	else
		local look = P.Looks[pet.Look] or P.Looks.Orb
		label({ Size = UDim2.new(0, 60, 0, 52), Position = UDim2.new(0, 10, 0, 8), Text = look.Icon, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center }, head)
		label({ Size = UDim2.new(1, -90, 0, 24), Position = UDim2.new(0, 72, 0, 10), Text = string.format("%s  <font color='#ffd966'>Lv.%d / %d</font>", look.Name, pet.Level, P.MaxLevel), TextSize = 18, RichText = true }, head)
		local nextFn
		for _, fn in ipairs(P.Functions) do
			if fn.Level > pet.Level then nextFn = fn break end
		end
		label({ Size = UDim2.new(1, -90, 0, 18), Position = UDim2.new(0, 72, 0, 36), Text = nextFn and string.format("다음 기능: Lv.%d %s %s", nextFn.Level, nextFn.Icon, nextFn.Name) or "모든 기능이 열렸어요!", TextSize = 12, TextColor3 = Color3.fromRGB(190, 200, 235) }, head)
		if pet.Level < P.MaxLevel then
			local cost = Config.GetPetLevelCost(pet.Level)
			button({ Size = UDim2.new(0, 230, 0, 34), Position = UDim2.new(0, 12, 1, -42), BackgroundColor3 = gold >= cost and Color3.fromRGB(60, 130, 80) or Color3.fromRGB(95, 60, 62),
				Text = string.format("⬆ 레벨업  💰 %s G", comma(cost)), TextSize = 15 }, head, function()
				Remotes.Meta:FireServer("PetLevel")
			end)
		end
	end

	-- 2) 기능 목록 (레벨별로 열린다)
	label({ Size = UDim2.new(1, 0, 0, 22), Text = "  ⚙ 기능 (레벨이 오를수록 늘어나요)", TextSize = 14, TextColor3 = Color3.fromRGB(255, 225, 140), LayoutOrder = (function() order += 1 return order end)() }, scroll)
	local level = pet and pet.Unlocked and pet.Level or 0
	for _, fn in ipairs(P.Functions) do
		local open = level >= fn.Level
		local r = row(40, open and Color3.fromRGB(34, 52, 44) or Color3.fromRGB(32, 34, 48))
		label({ Size = UDim2.new(0, 56, 1, 0), Position = UDim2.new(0, 8, 0, 0), Text = string.format("Lv.%d", fn.Level), TextSize = 14, TextColor3 = open and Color3.fromRGB(130, 255, 170) or Color3.fromRGB(150, 155, 185) }, r)
		label({ Size = UDim2.new(1, -76, 0, 20), Position = UDim2.new(0, 66, 0, 3), Text = string.format("%s %s", fn.Icon, fn.Name), TextSize = 14, TextColor3 = open and Color3.new(1, 1, 1) or Color3.fromRGB(165, 170, 195) }, r)
		label({ Size = UDim2.new(1, -76, 0, 16), Position = UDim2.new(0, 66, 0, 21), Text = fn.Desc, TextSize = 11, TextColor3 = open and Color3.fromRGB(190, 235, 205) or Color3.fromRGB(130, 135, 165), TextTruncate = Enum.TextTruncate.AtEnd }, r)
	end

	-- 3) 외형 (군주를 쓰러뜨리거나 칭호를 따면 열린다. 능력과는 상관없다)
	label({ Size = UDim2.new(1, 0, 0, 22), Text = "  🎨 외형 (능력과 상관없는 꾸미기)", TextSize = 14, TextColor3 = Color3.fromRGB(255, 225, 140), LayoutOrder = (function() order += 1 return order end)() }, scroll)
	local lookRow = row(200)
	make("UIGridLayout", { CellSize = UDim2.new(0, 140, 0, 60), CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, lookRow)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8) }, lookRow)
	for index, key in ipairs(P.LookOrder) do
		local look = P.Looks[key]
		local unlocked = state and state.UnlockedLooks and state.UnlockedLooks[key] == true
		local selected = pet and pet.Look == key
		local b = button({
			LayoutOrder = index, Text = "", BackgroundColor3 = selected and Color3.fromRGB(70, 62, 30) or Color3.fromRGB(40, 43, 64),
		}, lookRow, function()
			if unlocked and pet and pet.Unlocked then
				Remotes.Meta:FireServer("PetLook", key)
			elseif not (pet and pet.Unlocked) then
			end
		end)
		make("UIStroke", { Color = selected and Color3.fromRGB(255, 215, 100) or Color3.fromRGB(80, 85, 120), Thickness = selected and 2.5 or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		label({ Size = UDim2.new(0, 36, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = unlocked and look.Icon or "🔒", TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center }, b)
		label({ Size = UDim2.new(1, -48, 0, 22), Position = UDim2.new(0, 44, 0, 8), Text = look.Name, TextSize = 13, TextColor3 = unlocked and Color3.new(1, 1, 1) or Color3.fromRGB(150, 155, 185) }, b)
		label({ Size = UDim2.new(1, -48, 0, 22), Position = UDim2.new(0, 44, 0, 30), Text = unlocked and (selected and "사용 중" or "") or look.Hint, TextSize = 10, TextColor3 = unlocked and Color3.fromRGB(255, 225, 110) or Color3.fromRGB(150, 155, 185), TextWrapped = true }, b)
	end

	-- 4) 색
	label({ Size = UDim2.new(1, 0, 0, 22), Text = "  🖌 색", TextSize = 14, TextColor3 = Color3.fromRGB(255, 225, 140), LayoutOrder = (function() order += 1 return order end)() }, scroll)
	local colorRow = row(52)
	for index, color in ipairs(P.Colors) do
		local selected = pet and pet.Color == index
		local swatch = button({ Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0, 10 + (index - 1) * 52, 0.5, -20), BackgroundColor3 = color, Text = "" }, colorRow, function()
			Remotes.Meta:FireServer("PetColor", index)
		end)
		make("UIStroke", { Color = selected and Color3.new(1, 1, 1) or Color3.fromRGB(70, 75, 100), Thickness = selected and 3 or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, swatch)
	end
end

Remotes.Meta.OnClientEvent:Connect(function(action, data)
	if action == "State" and data and data.Pet then
		state = data
		if panel.Visible then rebuild() end
	end
end)
player:GetAttributeChangedSignal("Gold"):Connect(function()
	if panel.Visible then rebuild() end -- 골드가 모이면 버튼이 초록색으로
end)

local function toggle(open)
	if open == nil then open = not panel.Visible end
	panel.Visible = open
	if open then
		Remotes.Meta:FireServer("Request")
		rebuild()
	end
end

player:GetAttributeChangedSignal("OpenPet"):Connect(function() toggle(true) end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then toggle() end
end)
