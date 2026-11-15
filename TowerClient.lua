-- 무한의 탑 입장 창: 최고 층 / 다음 층(최고 + 1)의 제약 / 10·50층 보상 안내 / 입장. 메뉴 도크의 🗼 버튼(OpenTower) 으로 연다
--   오프닝 / 큰 창(ModalOpen) 중에는 열리지 않는다. 화면(ScreenGui)은 열 때만 켜고 닫으면 끈다. 작은 화면은 UIScale 로 줄인다
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local gui = Instance.new("ScreenGui")
gui.Name = "TowerGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 25
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local W, H = 440, 360
local panel = make("Frame", { Name = "TowerPanel", Size = UDim2.new(0, W, 0, H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(22, 20, 36), BorderSizePixel = 0 }, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Color = Color3.fromRGB(190, 150, 255), Thickness = 2, Transparency = 0.2 }, panel)
local fit = make("UIScale", {}, panel)
local function refit()
	local size = gui.AbsoluteSize
	if size.X > 0 then fit.Scale = math.min(1, (size.X - 24) / W, (size.Y - 24) / H) end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)

make("TextLabel", { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 16, 0, 12), BackgroundTransparency = 1, Text = "🗼 Infinite Tower", TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(220, 200, 255), TextXAlignment = Enum.TextXAlignment.Left }, panel)
local bestLabel = make("TextLabel", { Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 46), BackgroundTransparency = 1, RichText = true, Text = "", TextSize = 15, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 217, 102), TextXAlignment = Enum.TextXAlignment.Left }, panel)
local body = make("TextLabel", { Size = UDim2.new(1, -32, 0, 196), Position = UDim2.new(0, 16, 0, 74), BackgroundTransparency = 1, RichText = true, Text = "", TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(215, 210, 235), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, panel)
local enter = make("TextButton", { Size = UDim2.new(0.6, -20, 0, 48), Position = UDim2.new(0, 16, 1, -64), BackgroundColor3 = Color3.fromRGB(120, 80, 200), Text = "", TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1) }, panel)
make("UICorner", { CornerRadius = UDim.new(0, 24) }, enter)
local closeBtn = make("TextButton", { Size = UDim2.new(0.4, -20, 0, 48), Position = UDim2.new(0.6, 4, 1, -64), BackgroundColor3 = Color3.fromRGB(58, 60, 82), Text = "Close", TextSize = 15, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1) }, panel)
make("UICorner", { CornerRadius = UDim.new(0, 24) }, closeBtn)

local function nextFloor() return (player:GetAttribute("TowerBest") or 0) + 1 end
local function paint()
	local T = Config.Tower
	local best, floor = player:GetAttribute("TowerBest") or 0, nextFloor()
	bestLabel.Text = string.format("Best floor %d", best) -- (숫자를 따로 색칠하면 번역 조각이 갈라져서 한 덩어리로)
	local lines = {}
	if floor > T.MaxFloor then
		table.insert(lines, "<font color='#78ff8c'><b>All floors cleared!</b></font>")
	else
		table.insert(lines, string.format("<font size='15'><b>Next: floor %d</b></font>", floor))
		for _, c in ipairs(Config.TowerConstraints(floor)) do
			table.insert(lines, string.format("%s <b>%s</b> <font color='#a8a2c8'>%s</font>", c.Icon, c.Name, c.Desc))
		end
	end
	table.insert(lines, "")
	table.insert(lines, string.format("<font color='#ff9ad8'>🌈 Every %d floors: guaranteed Mythic gear</font>", T.MythicEvery))
	table.insert(lines, string.format("<font color='#c9a6ff'>🗼 Floor %d+: tower title above your head</font>", T.TitleEvery))
	table.insert(lines, "<font size='11' color='#a8a2c8'>Solo · no key · fail = try the same floor again</font>")
	body.Text = table.concat(lines, "\n")
	local inTown = player:GetAttribute("Zone") == "Lobby"
	local can = inTown and floor <= T.MaxFloor
	enter.Text = inTown and string.format("Enter floor %d", math.min(floor, T.MaxFloor)) or "Enter from town"
	enter.AutoButtonColor = can
	enter.BackgroundColor3 = can and Color3.fromRGB(120, 80, 200) or Color3.fromRGB(62, 58, 78)
end

local function close() gui.Enabled = false end
local function open()
	if player:GetAttribute("IntroPlaying") or player:GetAttribute("ModalOpen") then return end
	paint()
	refit()
	panel.Visible = true -- (다른 창 버튼이 창을 숨겼을 수 있다: 열 때 다시 보이게)
	gui.Enabled = true
end
enter.Activated:Connect(function()
	if player:GetAttribute("Zone") ~= "Lobby" or nextFloor() > Config.Tower.MaxFloor then return end
	Remotes.Dungeon:FireServer("TowerEnter", nextFloor())
	close()
end)
closeBtn.Activated:Connect(close)
player:GetAttributeChangedSignal("OpenTower"):Connect(function()
	if gui.Enabled and panel.Visible then close() else open() end
end)
for _, name in ipairs({ "TowerBest", "Zone" }) do
	player:GetAttributeChangedSignal(name):Connect(function() if gui.Enabled then paint() end end)
end
player:GetAttributeChangedSignal("IntroPlaying"):Connect(function() if player:GetAttribute("IntroPlaying") then close() end end)
