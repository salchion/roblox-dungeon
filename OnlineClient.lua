-- OnlineClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: OnlineClient)
-- "이 서버에 나 말고 누가 있는지" 보여 준다 (Roblox 기본 플레이어 목록은 다른 화면과 겹쳐서 꺼 두었다).
--   * 화면 위 가운데 작은 알약: 👥 접속 중 N명 (누르면 이 서버 유저의 이름 / 레벨 / 전투력이 펼쳐진다)
--   * 누가 들어오면 / 나가면 위쪽에 짧은 한 줄 알림 (내가 막 들어왔을 때 이미 있던 사람은 알리지 않는다)
--   마을(Lobby)에서는 위 가운데, 필드(Field)에서는 오른쪽 위 (필드의 오른쪽 위는 비어 있다). 던전은 위쪽을 웨이브 표시 / 보스 체력바가 쓰므로 보이지 않는다.
--   서버 부하는 없다: 클라이언트가 Players 서비스와 유저 Attribute(Level / Power)만 읽는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makeLabel = Kit.create, Kit.rounded, Kit.makeLabel

local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local COMPACT = UserInputService.TouchEnabled and not UserInputService.MouseEnabled -- 폰 / 태블릿: 알약을 작게 (숫자만), 눌러서 열고 닫는다
local MAX_ROWS = 12

local gui = create("ScreenGui", { Name = "OnlineGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4 }, player:WaitForChild("PlayerGui"))

local pill, listFrame, toast -- 아래에서 만든다 (위치를 구역에 따라 바꾸려고 먼저 선언)
local function place()
	local zone = player:GetAttribute("Zone")
	gui.Enabled = zone == "Lobby" or zone == "Field"
	if not pill then return end
	local atRight = zone == "Field"
	local anchor = atRight and Vector2.new(1, 0) or Vector2.new(0.5, 0)
	local x = atRight and UDim2.new(1, -16, 0, 0) or UDim2.new(0.5, 0, 0, 0)
	pill.AnchorPoint, listFrame.AnchorPoint, toast.AnchorPoint = anchor, anchor, anchor
	pill.Position = UDim2.new(x.X.Scale, x.X.Offset, 0, 8)
	listFrame.Position = UDim2.new(x.X.Scale, x.X.Offset, 0, 44)
	toast.Position = UDim2.new(x.X.Scale, x.X.Offset, 0, 44)
	toast.TextXAlignment = atRight and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center
end

pill = create("TextButton", {
	Size = COMPACT and UDim2.new(0, 64, 0, 28) or UDim2.new(0, 150, 0, 30), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
	BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.25, BorderSizePixel = 0, AutoButtonColor = true,
	Text = "", ZIndex = 5,
}, gui)
rounded(pill, 15)
create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.2, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
local pillText = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 13, Font = Enum.Font.GothamBold, ZIndex = 6 }, pill)

listFrame = create("Frame", {
	Size = UDim2.new(0, 260, 0, 10), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44),
	BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.1, BorderSizePixel = 0, Visible = false, ZIndex = 5,
}, gui)
rounded(listFrame, 10)
create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.2, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, listFrame)
local listText = makeLabel({
	Size = UDim2.new(1, -16, 1, -12), Position = UDim2.new(0, 8, 0, 6), RichText = true, TextSize = 13, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6, Text = "",
}, listFrame)

local function refreshList()
	local rows = {}
	local all = Players:GetPlayers()
	table.sort(all, function(a, b) return (a:GetAttribute("Power") or 0) > (b:GetAttribute("Power") or 0) end)
	for index, other in ipairs(all) do
		if index > MAX_ROWS then
			table.insert(rows, string.format("<font color='#9aa0c0'>… and %d more</font>", #all - MAX_ROWS))
			break
		end
		table.insert(rows, string.format("%s<b>%s</b>  <font color='#9aa0c0'>Lv %d · ⚡%d</font>",
			other == player and "⭐ " or "", other.DisplayName, other:GetAttribute("Level") or 1, other:GetAttribute("Power") or 0))
	end
	listText.Text = table.concat(rows, "\n")
	listFrame.Size = UDim2.new(0, 260, 0, 18 + 18 * math.min(#all, MAX_ROWS + 1))
end

local function refresh()
	local count = #Players:GetPlayers()
	if COMPACT then
		pillText.Text = "👥 " .. count
	else
		pillText.Text = count <= 1 and "👥 Online: just you" or string.format("👥 Online: %d players", count)
	end
	if listFrame.Visible then refreshList() end
end

local openToken = 0
local function setOpen(open)
	openToken += 1
	listFrame.Visible = open
	if open then
		refreshList()
		local mine = openToken
		task.delay(12, function() -- 열어 둔 채 잊어버려도 12초 뒤 저절로 닫힌다
			if openToken == mine then listFrame.Visible = false end
		end)
	end
end
pill.Activated:Connect(function()
	setOpen(not listFrame.Visible)
end)

-- 들어오고 나가는 한 줄 알림
local toastToken = 0
toast = makeLabel({
	Size = UDim2.new(0, 320, 0, 24), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Text = "", TextSize = 13,
	Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(200, 210, 255), TextTransparency = 1, ZIndex = 5,
}, gui)
local function announce(text)
	toastToken += 1
	local mine = toastToken
	toast.Text = text
	toast.TextTransparency = 0
	toast.Position = UDim2.new(toast.Position.X.Scale, toast.Position.X.Offset, 0, listFrame.Visible and (listFrame.AbsoluteSize.Y + 52) or 44)
	task.delay(3, function()
		if toastToken == mine then
			TweenService:Create(toast, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		end
	end)
end

player:GetAttributeChangedSignal("Zone"):Connect(place)
place()

local ready = false
task.delay(4, function() ready = true end) -- 내가 막 들어왔을 때 이미 있던 사람들은 알리지 않는다
Players.PlayerAdded:Connect(function(other)
	refresh()
	if ready and other ~= player then announce("👋 " .. other.DisplayName .. " joined") end
end)
Players.PlayerRemoving:Connect(function(other)
	task.defer(refresh)
	if other ~= player then announce(other.DisplayName .. " left") end
end)
refresh()
task.spawn(function()
	while true do
		task.wait(5)
		if listFrame.Visible then refreshList() end
	end
end)
