-- AugClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: AugClient)
-- ✨ 세트 효과 창 (Y 키 또는 "세트" 버튼): 구역 군주를 잡으면 그 구역 효과가 열리고, 골드로 활성화 / 1~3단계 강화한다.
-- 동시에 켤 수 있는 칸(AugSlots)은 처음 1개이고 구역을 클리어할수록 늘어난다. 값은 서버가 정하는 Attribute 에서 읽는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local ZONES = Config.Field.ZoneCount

local gui = Instance.new("ScreenGui")
gui.Name = "AugGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
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

local function commas(n)
	return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- 왼쪽 상태 카드 아래, "스탯" 버튼 옆
local pill = button({
	Size = UDim2.new(0, 78, 0, 32), Position = UDim2.new(0, 264, 0, 244),
	BackgroundColor3 = Color3.fromRGB(34, 38, 60), Text = "🌟 세트(Y)", TextSize = 12, Visible = false,
}, gui, function() end)
make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
local badge = label({
	Size = UDim2.new(0, 24, 0, 24), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 2),
	BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(255, 80, 80), Text = "!", TextSize = 13, Visible = false, ZIndex = 5,
}, pill)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)

local panel = make("Frame", {
	Size = UDim2.new(0, 480, 0, 470), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(26, 28, 42), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 2 }, panel)
make("UISizeConstraint", { MaxSize = Vector2.new(480, 470) }, panel)

label({ Size = UDim2.new(1, -90, 0, 30), Position = UDim2.new(0, 16, 0, 10), Text = "🌟 세트 효과", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left }, panel)
local slotLabel = label({ Size = UDim2.new(1, -32, 0, 20), Position = UDim2.new(0, 16, 0, 40), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 110) }, panel)
label({ Size = UDim2.new(1, -32, 0, 32), Position = UDim2.new(0, 16, 0, 60), Text = "구역 군주를 잡으면 그 구역의 효과가 열려요. 골드로 활성화하고 강화하면 내 탄이 눈에 띄게 달라져요. 구역을 클리어할수록 동시에 켤 수 있는 칸이 늘어요.", TextSize = 12, TextColor3 = Color3.fromRGB(170, 175, 205), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true }, panel)
button({ Size = UDim2.new(0, 60, 0, 28), Position = UDim2.new(1, -72, 0, 10), BackgroundColor3 = Color3.fromRGB(70, 70, 90), Text = "닫기", TextSize = 13 }, panel, function() panel.Visible = false end)

local list = make("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -104), Position = UDim2.new(0, 12, 0, 94), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local rows = {}
for zone = 1, ZONES do
	local attr = Config.Sets.ZoneAug[zone]
	local info = Config.AugInfo[attr]
	local row = make("Frame", { Size = UDim2.new(1, -8, 0, 62), BackgroundColor3 = Color3.fromRGB(36, 39, 58), BorderSizePixel = 0, LayoutOrder = zone }, list)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
	label({ Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = info.Icon, TextSize = 24 }, row)
	local title = label({ Size = UDim2.new(1, -230, 0, 20), Position = UDim2.new(0, 44, 0, 5), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
	local desc = label({ Size = UDim2.new(1, -230, 0, 32), Position = UDim2.new(0, 44, 0, 25), Text = info.Desc, TextSize = 11, TextColor3 = Color3.fromRGB(170, 215, 190), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true }, row)
	local toggle = button({ Size = UDim2.new(0, 64, 0, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), BackgroundColor3 = Color3.fromRGB(60, 120, 80), Text = "켜기", TextSize = 12 }, row, function()
		Remotes.Aug:FireServer("Toggle", zone)
	end)
	local buy = button({ Size = UDim2.new(0, 150, 0, 26), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -6), BackgroundColor3 = Color3.fromRGB(140, 104, 40), Text = "", TextSize = 12 }, row, function()
		Remotes.Aug:FireServer("Buy", zone)
	end)
	rows[zone] = { Title = title, Toggle = toggle, Buy = buy, Row = row }
end

local function refresh()
	local gold = player:GetAttribute("Gold") or 0
	local slots = player:GetAttribute("AugSlots") or 1
	local used, affordable = 0, 0
	local anyOpen = false
	for zone = 1, ZONES do
		local open = player:GetAttribute("AugOpenZ_" .. zone) == true
		local level = player:GetAttribute("AugLvZ_" .. zone) or 0
		local on = player:GetAttribute("AugOnZ_" .. zone) == true
		local r = rows[zone]
		anyOpen = anyOpen or open
		if on then used += 1 end
		local info = Config.AugInfo[Config.Sets.ZoneAug[zone]]
		r.Title.Text = string.format("%d구역 · %s  %s", zone, info.Name, level > 0 and ("<" .. level .. "단계>") or "")
		r.Title.TextColor3 = open and Color3.fromRGB(255, 240, 200) or Color3.fromRGB(130, 134, 156)
		r.Toggle.Visible = level > 0
		r.Toggle.Text = on and "끄기" or "켜기"
		r.Toggle.BackgroundColor3 = on and Color3.fromRGB(120, 70, 70) or Color3.fromRGB(60, 120, 80)
		r.Row.BackgroundColor3 = on and Color3.fromRGB(50, 52, 74) or Color3.fromRGB(36, 39, 58)
		if not open then
			r.Buy.Text = string.format("🔒 %d구역 군주를 잡으세요", zone)
			r.Buy.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
		elseif level >= 3 then
			r.Buy.Text = "최대 단계"
			r.Buy.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
		else
			local cost = Config.Sets.AugCost(zone, level + 1)
			r.Buy.Text = string.format("%s %s G", level == 0 and "활성화" or "강화", commas(cost))
			r.Buy.BackgroundColor3 = gold >= cost and Color3.fromRGB(150, 110, 40) or Color3.fromRGB(80, 74, 66)
			if gold >= cost and level == 0 then affordable += 1 end
		end
	end
	slotLabel.Text = string.format("켜진 효과 %d / %d칸   (보유 💰 %s G)", used, slots, commas(gold))
	pill.Visible = anyOpen and not player:GetAttribute("TutorialActive")
	badge.Visible = affordable > 0 and used < slots
end

for _, name in ipairs({ "Gold", "AugSlots", "TutorialActive" }) do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
for zone = 1, ZONES do
	for _, prefix in ipairs({ "AugOpenZ_", "AugLvZ_", "AugOnZ_" }) do
		player:GetAttributeChangedSignal(prefix .. zone):Connect(refresh)
	end
end
refresh()

pill.Activated:Connect(function() panel.Visible = not panel.Visible end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Y then panel.Visible = not panel.Visible end
end)
