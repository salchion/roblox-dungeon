-- OnlineClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: OnlineClient)
-- "이 서버에 나 말고 누가 있는지" 보여 준다 (Roblox 기본 플레이어 목록은 다른 화면과 겹쳐서 꺼 두었다).
--   * 화면 위 가운데 작은 알약: 👥 접속 중 N명 (누르면 이 서버 유저의 이름 / 레벨 / 전투력이 펼쳐진다)
--   * 누가 들어오면 / 나가면 위쪽에 짧은 한 줄 알림 (내가 막 들어왔을 때 이미 있던 사람은 알리지 않는다)
--   마을(Lobby) / 필드(Field)에서만 보인다 (던전은 위쪽을 웨이브 표시 / 보스 체력바가 쓴다). 위치는 고정: 화면 맨 위, Roblox 기본 버튼들 바로 오른쪽.
--   서버 부하는 없다: 클라이언트가 Players 서비스와 유저 Attribute(Level / Power)만 읽는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makeLabel = Kit.create, Kit.rounded, Kit.makeLabel

local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local COMPACT = UserInputService.TouchEnabled and not UserInputService.MouseEnabled and not require(game:GetService("ReplicatedStorage"):WaitForChild("Config")).PhonePcStyle -- 폰 / 태블릿: 알약을 작게 (숫자만), 눌러서 열고 닫는다
local MAX_ROWS = 8 -- 목록은 상위 8명만 (전투력 순)
local TOAST_MAX_PLAYERS = 8 -- 서버 인원이 이보다 많으면 들어오고 나가는 알림은 끈다 (계속 뜨면 화면을 가린다)

local gui = create("ScreenGui", { Name = "OnlineGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4 }, player:WaitForChild("PlayerGui"))

local GuiService = game:GetService("GuiService")
local playerGui = player:WaitForChild("PlayerGui")
local pill, listFrame, toast -- 아래에서 만든다 (위치를 자동으로 잡으려고 먼저 선언)
local spot = nil -- 알약의 현재 위치 (화면 픽셀, 왼쪽 위 기준)
local collideSince = nil -- 지금 자리가 다른 UI 와 겹치기 시작한 시각

-- 자동 배치: 지금 화면에 보이는 다른 UI 들의 사각형을 모아서, 겹치지 않는 빈 자리를 찾는다 (폰마다 해상도 / 비율이 달라도 같은 방식).
--   후보 순서: 오른쪽 줄 위에서 아래로 -> 왼쪽 줄 위에서 아래로. 다 겹치면 오른쪽 위에 둔다. (위 가운데는 3D 이름표 / 명예의 전당 글자와 겹치므로 쓰지 않는다)
local function visibleChain(instance)
	local current = instance
	while current and current ~= playerGui do
		if current:IsA("GuiObject") and not current.Visible then return false end
		if current:IsA("ScreenGui") and not current.Enabled then return false end
		current = current.Parent
	end
	return true
end

local function collectRects(screen)
	local rects = {}
	local inset = GuiService:GetGuiInset().Y
	for _, instance in ipairs(playerGui:GetDescendants()) do
		if instance:IsA("GuiObject") and not instance:IsDescendantOf(gui) then
			local size = instance.AbsoluteSize
			if size.X > 4 and size.Y > 4 and size.X < screen.X * 0.7 and size.Y < screen.Y * 0.7 then -- 화면을 덮는 배경은 뺀다
				local visibleContent = instance.BackgroundTransparency < 0.9
					or ((instance:IsA("TextLabel") or instance:IsA("TextButton")) and instance.Text ~= "" and instance.TextTransparency < 0.9)
					or ((instance:IsA("ImageLabel") or instance:IsA("ImageButton")) and instance.ImageTransparency < 0.9)
				if visibleContent and visibleChain(instance) then
					local screenGui = instance:FindFirstAncestorOfClass("ScreenGui")
					local offsetY = (screenGui and not screenGui.IgnoreGuiInset) and inset or 0
					table.insert(rects, { X = instance.AbsolutePosition.X, Y = instance.AbsolutePosition.Y + offsetY, W = size.X, H = size.Y })
				end
			end
		end
	end
	return rects
end

local function hits(rects, x, y, w, h)
	local pad = 4
	for _, r in ipairs(rects) do
		if x < r.X + r.W + pad and x + w + pad > r.X and y < r.Y + r.H + pad and y + h + pad > r.Y then return true end
	end
	return false
end

local function findSpot()
	local screen = gui.AbsoluteSize
	local w, h = pill.AbsoluteSize.X, pill.AbsoluteSize.Y
	if screen.X < 50 or screen.Y < 50 or w < 1 then return spot or Vector2.new(12, 12) end
	local rects = collectRects(screen)
	local margin = 12
	local rightX = screen.X - w - margin
	for y = 8, screen.Y - h - margin, 8 do
		if not hits(rects, rightX, y, w, h) then return Vector2.new(rightX, y) end
	end
	for y = 8, screen.Y - h - margin, 8 do
		if not hits(rects, margin, y, w, h) then return Vector2.new(margin, y) end
	end
	return Vector2.new(rightX, 8)
end

-- 목록 / 알림은 알약 아래(자리가 모자라면 위)에 붙인다
local function layoutExtras()
	if not spot then return end
	local screen = gui.AbsoluteSize
	local w, h = pill.AbsoluteSize.X, pill.AbsoluteSize.Y
	local listW, listH = listFrame.AbsoluteSize.X, listFrame.AbsoluteSize.Y
	local lx = math.clamp(spot.X + w - listW, 8, math.max(8, screen.X - listW - 8))
	local below = spot.Y + h + 6 + listH <= screen.Y - 8
	listFrame.AnchorPoint = Vector2.new(0, below and 0 or 1)
	listFrame.Position = UDim2.fromOffset(lx, below and (spot.Y + h + 6) or (spot.Y - 6))
	local toastW = toast.AbsoluteSize.X
	local tx = math.clamp(spot.X + w / 2 - toastW / 2, 8, math.max(8, screen.X - toastW - 8))
	local toastY = spot.Y + h + 6
	if listFrame.Visible and below then toastY += listH + 6 end
	if not below then toastY = spot.Y - 6 - 24 - (listFrame.Visible and (listH + 6) or 0) end
	toast.AnchorPoint = Vector2.new(0, 0)
	toast.Position = UDim2.fromOffset(tx, toastY)
	toast.TextXAlignment = Enum.TextXAlignment.Center
end

local function place(force)
	local zone = player:GetAttribute("Zone")
	gui.Enabled = zone == "Lobby" or zone == "Field"
	if not pill or not gui.Enabled then return end
	local w, h = pill.AbsoluteSize.X, pill.AbsoluteSize.Y
	if w < 1 or gui.AbsoluteSize.X < 50 then return end -- 아직 화면 크기가 정해지지 않았다 (잠깐 뒤에 다시 부른다)
	-- 고정 자리: 화면 맨 위, Roblox 기본 버튼들(로고 / 채팅 등) 바로 오른쪽 빈칸. (예전의 빈자리 자동 찾기는 좌표 계산이 환경마다 어긋나 다른 버튼과 겹쳤다)
	local x, y = 210, 14
	local okInset, inset = pcall(function() return GuiService.TopbarInset end)
	if okInset and inset and inset.Width > 0 then
		x = inset.Min.X + 8
		y = inset.Min.Y + math.max(0, (inset.Height - h) / 2)
	end
	local uiScale = gui:FindFirstChild("MobileScale") -- 폰: 화면 전체가 줄어 있으면 실제 픽셀 좌표를 그 배율로 나눠야 Roblox 버튼 오른쪽에 놓인다
	if uiScale and uiScale:IsA("UIScale") and uiScale.Scale > 0 then
		x, y = x / uiScale.Scale, y / uiScale.Scale
	end
	spot = Vector2.new(x, y)
	pill.AnchorPoint = Vector2.new(0, 0)
	pill.Position = UDim2.fromOffset(x, y)
	layoutExtras()
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
	layoutExtras()
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
	layoutExtras()
	task.delay(3, function()
		if toastToken == mine then
			TweenService:Create(toast, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		end
	end)
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	task.delay(1.5, function() place(true) end) -- 구역이 바뀌면 화면 UI 가 다시 짜이므로 잠깐 뒤에 빈 자리를 다시 찾는다
	place(true)
end)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() place(true) end)
pcall(function() GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function() place(true) end) end)
place(true)
task.delay(2, function() place(true) end)

local ready = false
task.delay(4, function() ready = true end) -- 내가 막 들어왔을 때 이미 있던 사람들은 알리지 않는다
Players.PlayerAdded:Connect(function(other)
	refresh()
	if ready and other ~= player and #Players:GetPlayers() <= TOAST_MAX_PLAYERS then announce("👋 " .. other.DisplayName .. " joined") end
end)
Players.PlayerRemoving:Connect(function(other)
	task.defer(refresh)
	if other ~= player and #Players:GetPlayers() <= TOAST_MAX_PLAYERS then announce("🚪 " .. other.DisplayName .. " left") end
end)
refresh()
task.spawn(function()
	while true do
		task.wait(2)
		if listFrame.Visible then refreshList() end
	end
end)
