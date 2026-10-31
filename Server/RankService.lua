-- RankService (ServerScriptService > Modules 안의 ModuleScript, 이름: RankService)
-- 전투력 랭킹. 로비 광장에 랭킹판을 세우고, 메뉴(B) 랭킹 탭에도 같은 목록을 보내준다.
--   * 전 서버 통합 랭킹: OrderedDataStore 를 쓴다 (Studio에서 API 접근을 켜야 동작)
--   * DataStore 를 쓸 수 없으면 지금 서버에 있는 플레이어끼리의 랭킹으로 대신한다

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local Rank = {}

local TOP_COUNT = 20 -- (마을 벽 랭킹판에 20명)
local REFRESH_SECONDS = 45

local okStore, store = pcall(function()
	return DataStoreService:GetOrderedDataStore("PowerRank_v1")
end)
if not okStore then
	store = nil
end

local rankList = {}      -- { { Name, Power }... } 가장 최근에 계산한 TOP
local nameCache = {}     -- [userId] = 이름
local boardLabel = nil

local function nameOf(userId)
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return online.DisplayName
	end
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = ok and name or ("Player" .. userId)
	return nameCache[userId]
end

-- 지금 서버 플레이어 기준 랭킹 (DataStore 를 못 쓸 때 / 아직 데이터가 없을 때)
local function onlineList()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(list, { Name = player.DisplayName, Power = player:GetAttribute("Power") or 0 })
	end
	table.sort(list, function(a, b) return a.Power > b.Power end)
	while #list > TOP_COUNT do
		table.remove(list)
	end
	return list
end

local function comma(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- 마을 동쪽 성벽(사냥터 입구 오른쪽, 마을 쪽 면)에 붙인 큰 랭킹판: 왼쪽 열 1~10위, 오른쪽 열 11~20위
local wallRows = {}
local function buildWallBoard()
	if workspace:FindFirstChild("RankWall") then workspace.RankWall:Destroy() end
	local board = Instance.new("Part")
	board.Name = "RankWall"
	board.Anchored, board.CanCollide, board.CanQuery, board.CanTouch, board.CastShadow = true, false, false, false, false
	board.Size = Vector3.new(1, 32, 46)
	board.Position = Vector3.new(126.6, 22, 52) -- (동쪽 성벽 x=130 안쪽 면에 붙인다. 사냥터 입구(z -22 ~ 22) 오른쪽)
	board.Color = Color3.fromRGB(28, 22, 44)
	board.Material = Enum.Material.SmoothPlastic
	board.Parent = workspace
	local frame = Instance.new("Part") -- 금테
	frame.Name = "RankWallFrame"
	frame.Anchored, frame.CanCollide, frame.CanQuery, frame.CanTouch, frame.CastShadow = true, false, false, false, false
	frame.Size = Vector3.new(0.8, 33.6, 47.6)
	frame.Position = board.Position + Vector3.new(0.3, 0, 0)
	frame.Color = Color3.fromRGB(214, 170, 80)
	frame.Material = Enum.Material.Metal
	frame.Parent = board
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Left
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Range = 14
	light.Brightness = 0.8
	light.Parent = board

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left -- (서쪽 = 마을 쪽을 본다)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 22
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.MaxDistance = 260
	gui.Parent = board
	local function label(props, parent)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.5
		l.TextScaled = true
		for k, v in pairs(props) do l[k] = v end
		l.Parent = parent
		return l
	end
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(24, 18, 40)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(70, 46, 110), Color3.fromRGB(18, 14, 30))
	grad.Rotation = 90
	grad.Parent = bg
	label({ Size = UDim2.new(1, 0, 0.12, 0), Position = UDim2.new(0, 0, 0.02, 0), Text = "🏆 POWER RANKING  TOP 20", TextColor3 = Color3.fromRGB(255, 217, 102), TextStrokeColor3 = Color3.fromRGB(60, 30, 0), TextStrokeTransparency = 0 }, bg)
	label({ Size = UDim2.new(1, 0, 0.04, 0), Position = UDim2.new(0, 0, 0.14, 0), Text = "All servers · updates every 45s", Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 180, 220) }, bg)
	local medalColors = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(215, 222, 235), Color3.fromRGB(225, 150, 90) }
	table.clear(wallRows)
	for i = 1, TOP_COUNT do
		local col, row = (i - 1) // 10, (i - 1) % 10
		local rowFrame = Instance.new("Frame")
		rowFrame.Size = UDim2.new(0.47, 0, 0.073, 0)
		rowFrame.Position = UDim2.new(0.02 + col * 0.49, 0, 0.2 + row * 0.078, 0)
		rowFrame.BackgroundColor3 = i <= 3 and medalColors[i]:Lerp(Color3.fromRGB(30, 24, 50), 0.6) or (row % 2 == 0 and Color3.fromRGB(44, 36, 70) or Color3.fromRGB(36, 30, 58))
		rowFrame.BorderSizePixel = 0
		rowFrame.Parent = bg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = rowFrame
		local rankText = label({ Size = UDim2.new(0.14, 0, 0.8, 0), Position = UDim2.new(0.02, 0, 0.1, 0), Text = i <= 3 and ({ "🥇", "🥈", "🥉" })[i] or tostring(i), TextColor3 = i <= 3 and medalColors[i] or Color3.fromRGB(200, 195, 225) }, rowFrame)
		local nameText = label({ Size = UDim2.new(0.5, 0, 0.66, 0), Position = UDim2.new(0.17, 0, 0.17, 0), Text = "-", Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, AutoLocalize = false }, rowFrame)
		local powerText = label({ Size = UDim2.new(0.32, 0, 0.66, 0), Position = UDim2.new(0.66, 0, 0.17, 0), Text = "", TextColor3 = Color3.fromRGB(255, 225, 110), TextXAlignment = Enum.TextXAlignment.Right, AutoLocalize = false }, rowFrame)
		wallRows[i] = { Rank = rankText, Name = nameText, Power = powerText }
	end
	boardLabel = board
end

local function renderBoard()
	if not boardLabel then return end
	for i, row in ipairs(wallRows) do
		local entry = rankList[i]
		row.Name.Text = entry and entry.Name or "-"
		row.Power.Text = entry and ("⚡" .. comma(entry.Power)) or ""
	end
end

local lastWritten = setmetatable({}, { __mode = "k" }) -- 마지막으로 저장한 전투력
local function refresh()
	-- 1) 내 점수 올리기
	if store then
		for _, player in ipairs(Players:GetPlayers()) do
			local power = player:GetAttribute("Power") or 0
			if power > 0 and lastWritten[player] ~= power then -- 바뀐 사람만 쓴다 (저장소 쓰기 횟수 절약)
				local ok = pcall(function()
					store:SetAsync(tostring(player.UserId), power)
				end)
				if ok then lastWritten[player] = power end
			end
		end
	end

	-- 2) TOP 가져오기
	local list
	if store then
		local ok, page = pcall(function()
			return store:GetSortedAsync(false, TOP_COUNT):GetCurrentPage()
		end)
		if ok and page then
			list = {}
			for _, entry in ipairs(page) do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(list, { Name = nameOf(userId), Power = entry.value })
				end
			end
		end
	end
	if not list or #list == 0 then
		list = onlineList()
	end

	rankList = list
	renderBoard()
	Remotes.Rank:FireAllClients("List", rankList)
end

-- 랭킹 집계를 시작한다 (cframe 은 예전 호환용으로 받기만 한다)
function Rank.Init(cframe)
	-- 마을 동쪽 성벽에 큰 랭킹판 (20명). 화면 오른쪽 작은 패널 / 메뉴 랭킹 탭 / 명예의 전당도 그대로
	local okBoard, errBoard = pcall(buildWallBoard)
	if not okBoard then warn("[RankService] 벽 랭킹판 만들기 실패: " .. tostring(errBoard)) end
	task.spawn(function()
		task.wait(5) -- 접속한 플레이어의 전투력이 계산된 뒤 첫 집계
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

Remotes.Rank.OnServerEvent:Connect(function(player, action)
	if action == "Request" then
		Remotes.Rank:FireClient(player, "List", #rankList > 0 and rankList or onlineList())
	end
end)

return Rank
