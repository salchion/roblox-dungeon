-- DpsPanelClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: DpsPanelClient)
-- 대미지 미터기만 그린다 (허수아비 전용 작은 패널은 미터기와 겹쳐서 없앴다).

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "DpsPanelGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

------------------------------------------------------------
-- 대미지 미터기 (필드 / 던전 / 허수아비): 총과 세트 효과가 각각 얼마나 피해를 줬는지 나눠서 보여 준다
-- 서버(DamageMeter)가 1초마다 Attribute "DmgMeter" (JSON) 를 갱신한다. 15초 동안 피해가 없으면 사라진다.
-- 머리줄을 누르면 접고 편다 (폰은 접힌 채로 시작: DPS 한 줄만). Reset 버튼은 0 부터 다시 센다. 큰 창이 열려 있으면 숨는다.
------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local COMPACT = UserInputService.TouchEnabled and not UserInputService.MouseEnabled and not Config.PhonePcStyle
local MAX_ROWS = 6
local ROW_H = 20
local HEAD_H = 50
local WIDTH = 232
local collapsed = COMPACT or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) -- 폰: 머리줄 한 줄로 접어서 시작 (스킬 버튼과 겹치지 않게)

local meter = Instance.new("Frame")
meter.Name = "DamageMeter"
if COMPACT then
	meter.Position = UDim2.new(0, 16, 0.47, 0) -- 폰: 왼쪽 가운데 (접힌 한 줄)
else
	-- PC: 오른쪽 가운데 아래. 왼쪽은 미션 카드 + 오늘의 퀘스트가 길게 내려와서 겹쳤다
	meter.AnchorPoint = Vector2.new(1, 0)
	meter.Position = UDim2.new(1, -16, 0.5, 0)
end
meter.Size = UDim2.new(0, WIDTH, 0, HEAD_H)
meter.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
meter.BackgroundTransparency = 0.12
meter.BorderSizePixel = 0
meter.Visible = false
meter.ClipsDescendants = true
meter.Parent = gui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = meter
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(110, 130, 220)
	st.Thickness = 1.5
	st.Transparency = 0.45
	st.Parent = meter
	local accent = Instance.new("Frame") -- 왼쪽 세로 강조선
	accent.Size = UDim2.new(0, 3, 0, HEAD_H - 16)
	accent.Position = UDim2.new(0, 0, 0, 8)
	accent.BackgroundColor3 = Color3.fromRGB(255, 217, 102)
	accent.BorderSizePixel = 0
	accent.Parent = meter
end
local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 12
	l.TextColor3 = Color3.fromRGB(230, 232, 245)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.RichText = true
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end
local header = Instance.new("TextButton") -- 머리줄 전체가 접기 / 펴기 버튼
header.BackgroundTransparency = 1
header.Text = ""
header.Size = UDim2.new(1, 0, 0, HEAD_H)
header.Parent = meter
local meterTitle = text(meter, { Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -92, 0, 14), TextSize = 11, TextColor3 = Color3.fromRGB(150, 158, 190) })
local meterDps = text(meter, { Position = UDim2.new(0, 12, 0, 20), Size = UDim2.new(1, -40, 0, 26), TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 217, 102) })
local toggleIcon = text(meter, { Position = UDim2.new(1, -30, 0, 13), Size = UDim2.new(0, 24, 0, 24), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(170, 180, 215) })
-- Reset 버튼: 지금까지 센 피해를 지우고 0 부터 다시 센다 (머리줄 접기 버튼보다 위에 놓아 눌리게)
local resetButton = Instance.new("TextButton")
resetButton.Name = "Reset"
resetButton.Size = UDim2.new(0, 44, 0, 24)
resetButton.Position = UDim2.new(1, -78, 0, 13)
resetButton.BackgroundColor3 = Color3.fromRGB(54, 58, 82)
resetButton.BackgroundTransparency = 0.2
resetButton.AutoButtonColor = true
resetButton.Font = Enum.Font.GothamBold
resetButton.TextSize = 11
resetButton.TextColor3 = Color3.fromRGB(200, 205, 230)
resetButton.Text = "Reset" -- (↺ / ▸ 같은 기호는 로블록스 글꼴에 없어 네모로 보였다: 글자로 쓴다)
resetButton.ZIndex = 3
resetButton.Parent = meter
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = resetButton
end
resetButton.Activated:Connect(function()
	local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local remote = remotes and remotes:FindFirstChild("Meter")
	if remote then remote:FireServer("Reset") end
end)
local rows = {}
for i = 1, MAX_ROWS do
	local y = HEAD_H + 2 + (i - 1) * ROW_H
	local track = Instance.new("Frame")
	track.BackgroundColor3 = Color3.fromRGB(30, 32, 48)
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 10, 0, y + 15)
	track.Size = UDim2.new(1, -20, 0, 3)
	track.Parent = meter
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track
	local name = text(meter, { Position = UDim2.new(0, 12, 0, y), Size = UDim2.new(1, -110, 0, 15) })
	local value = text(meter, { Position = UDim2.new(1, -96, 0, y), Size = UDim2.new(0, 86, 0, 15), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(200, 205, 230) })
	rows[i] = { Track = track, Fill = fill, Name = name, Value = value }
end

local function sourceName(source)
	if source == "Gun" then return "🔫 Gun" end
	local fixed = { Ult = "🎯 Deadeye", Blast = "💥 Shockwave", Spirit = "🧚 Spirits", Bounce = "🔁 Ricochet", Pierce = "➳ Piercing Beam", PerkBoom = "💥 Explosive Shot", PerkChain = "⚡ Chain Lightning", Other = "❔ Other" }
	if fixed[source] then return fixed[source] end
	if typeof(source) == "string" and string.sub(source, 1, 2) == "U_" then
		local unique = Config.Uniques[string.sub(source, 3)]
		return "✨ " .. (unique and unique.Name or string.sub(source, 3))
	end
	local info = Config.AugInfo[source]
	if info then return info.Icon .. " " .. info.Name end
	return tostring(source)
end
local function short(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local shownRows = 0
local function layout()
	toggleIcon.Text = collapsed and "+" or "-"
	for i, row in ipairs(rows) do
		local on = not collapsed and i <= shownRows
		row.Track.Visible, row.Name.Visible, row.Value.Visible = on, on, on
	end
	meter.Size = UDim2.new(0, WIDTH, 0, collapsed and HEAD_H or (HEAD_H + 6 + shownRows * ROW_H))
end
header.Activated:Connect(function()
	collapsed = not collapsed
	layout()
end)

local meterToken = 0
player:GetAttributeChangedSignal("DmgMeter"):Connect(function()
	local ok, data = pcall(function() return HttpService:JSONDecode(player:GetAttribute("DmgMeter") or "") end)
	if not ok or typeof(data) ~= "table" then return end
	local list = data.Src or {}
	local total = math.max(1, data.Total or 1)
	meterTitle.Text = string.format("DAMAGE · %ds · %s", data.Time or 0, short(total))
	meterDps.Text = short(data.Dps or 0) .. " <font size='12' color='#9aa2c6'>DPS</font>"
	shownRows = 0
	for i, row in ipairs(rows) do
		local entry = list[i]
		if entry then
			shownRows = i
			local share = (entry[2] or 0) / total
			row.Name.Text = sourceName(entry[1])
			row.Value.Text = string.format("%s  <font color='#8c93b8'>%d%%</font>", short(entry[2] or 0), math.floor(share * 100 + 0.5))
			row.Fill.Size = UDim2.new(math.clamp(share, 0, 1), 0, 1, 0)
			local info = Config.AugInfo[entry[1]]
			row.Fill.BackgroundColor3 = info and info.Color:Lerp(Color3.fromRGB(70, 70, 90), 0.2) or Color3.fromRGB(255, 217, 102)
		end
	end
	layout()
	meter.Visible = not player:GetAttribute("ModalOpen")
	meterToken += 1
	local mine = meterToken
	task.delay(15, function()
		if meterToken == mine then meter.Visible = false end
	end)
end)
player:GetAttributeChangedSignal("ModalOpen"):Connect(function()
	if player:GetAttribute("ModalOpen") then meter.Visible = false end
end)
