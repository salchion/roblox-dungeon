-- AdminService (ServerScriptService > Modules 안의 ModuleScript, 이름: AdminService)
-- 운영자 전용 읽기 화면: 지금 이 서버에 있는 유저의 레벨 / 전투력 / 골드 / 티켓 / 구역을 보여 준다. (보기만 한다 - 값을 바꾸는 기능은 없다)
--   * 운영자 확인은 서버에서만 한다: 체험 소유자(game.CreatorId)이거나, 그룹 소유 체험이면 그룹 소유자(랭크 255).
--     클라이언트 화면(AdminClient)을 숨기는 건 편의일 뿐이고, 요청이 와도 서버가 운영자가 아니면 아무 응답도 하지 않는다.
--   * 다른 서버에 있는 유저는 보이지 않는다 (이 서버 안만). 전체 기록은 OpsLog 의 [OPS] 로그를 본다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local Admin = {}

local cache = setmetatable({}, { __mode = "k" })
local lastRequest = setmetatable({}, { __mode = "k" })

local function isAdmin(player)
	local known = cache[player]
	if known ~= nil then return known end
	local result = false
	if game.CreatorId ~= 0 then
		if game.CreatorType == Enum.CreatorType.Group then
			local ok, rank = pcall(function() return player:GetRankInGroup(game.CreatorId) end)
			result = ok and rank == 255
		else
			result = player.UserId == game.CreatorId
		end
	elseif RunService:IsStudio() then
		result = true -- 저장되지 않은 Studio 장소(소유자 없음)에서만 허용
	end
	cache[player] = result
	return result
end

function Admin.IsAdmin(player)
	return isAdmin(player)
end

local function listPlayers()
	local rows = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(rows, {
			Name = p.Name, UserId = p.UserId,
			Level = p:GetAttribute("Level") or 0, Power = p:GetAttribute("Power") or 0,
			Gold = p:GetAttribute("Gold") or 0, Tickets = p:GetAttribute("Tickets") or 0,
			Zone = p:GetAttribute("Zone") or "?", MaxZone = p:GetAttribute("MaxZone") or 0,
		})
	end
	table.sort(rows, function(a, b) return a.Power > b.Power end)
	return rows
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		if isAdmin(player) then
			player:SetAttribute("IsAdmin", true) -- 클라이언트가 단축키를 켜는 용도일 뿐, 서버는 요청마다 다시 확인한다
		end
	end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		if isAdmin(player) then player:SetAttribute("IsAdmin", true) end
	end)
end

Remotes.Admin.OnServerEvent:Connect(function(player, action)
	if not isAdmin(player) then return end
	if action ~= "List" then return end
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 1 then return end
	lastRequest[player] = now
	Remotes.Admin:FireClient(player, "List", { Players = listPlayers(), JobId = string.sub(game.JobId, 1, 8), Count = #Players:GetPlayers() })
end)

return Admin
