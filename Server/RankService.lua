-- RankService (ServerScriptService > Modules 안의 ModuleScript, 이름: RankService)
-- 전투력 랭킹. 로비 광장에 랭킹판을 세우고, 메뉴(B) 랭킹 탭에도 같은 목록을 보내준다.
--   * 전 서버 통합 랭킹: OrderedDataStore 를 쓴다 (Studio에서 API 접근을 켜야 동작)
--   * DataStore 를 쓸 수 없으면 지금 서버에 있는 플레이어끼리의 랭킹으로 대신한다

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local Rank = {}

local TOP_COUNT = 10
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

local function renderBoard()
	if not boardLabel then return end
	local lines = { "🏆 전투력 랭킹 TOP " .. TOP_COUNT, "" }
	if #rankList == 0 then
		table.insert(lines, "아직 기록이 없어요")
	end
	for index, entry in ipairs(rankList) do
		local medal = index == 1 and "🥇" or index == 2 and "🥈" or index == 3 and "🥉" or string.format("%2d.", index)
		table.insert(lines, string.format("%s %s   ⚡%d", medal, entry.Name, entry.Power))
	end
	boardLabel.Text = table.concat(lines, "\n")
end

local function refresh()
	-- 1) 내 점수 올리기
	if store then
		for _, player in ipairs(Players:GetPlayers()) do
			local power = player:GetAttribute("Power") or 0
			if power > 0 then
				pcall(function()
					store:SetAsync(tostring(player.UserId), power)
				end)
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
	-- (3D 랭킹판은 없앴다: 랭킹은 화면 오른쪽 작은 패널과 메뉴 랭킹 탭, 하늘의 명예의 전당으로 보인다)
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
