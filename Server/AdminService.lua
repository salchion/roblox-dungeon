-- AdminService (ServerScriptService > Modules 안의 ModuleScript, 이름: AdminService)
-- 운영자 전용 읽기 화면: 지금 이 서버에 있는 유저의 레벨 / 전투력 / 골드 / 티켓 / 구역을 보여 준다. (보기만 한다 - 값을 바꾸는 기능은 없다)
--   * 운영자 확인은 서버에서만 한다: 체험 소유자(game.CreatorId)이거나, 그룹 소유 체험이면 그룹 소유자(랭크 255).
--     클라이언트 화면(AdminClient)을 숨기는 건 편의일 뿐이고, 요청이 와도 서버가 운영자가 아니면 아무 응답도 하지 않는다.
--   * 다른 서버에 있는 유저는 보이지 않는다 (이 서버 안만). 전체 기록은 OpsLog 의 [OPS] 로그를 본다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextService = game:GetService("TextService")

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

local armedAt = setmetatable({}, { __mode = "k" }) -- [player] = 저장 초기화 확인 단계를 연 시각
local lastAction = setmetatable({}, { __mode = "k" })

local GRANT_MAX = { Gold = 1000000000, Tickets = 10000, Keys = 30 }

local function note(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function module(name)
	local ok, result = pcall(function() return require(script.Parent:FindFirstChild(name)) end)
	return ok and result or nil
end

local function log(player, text)
	local ops = module("OpsLog")
	if ops and ops.Admin then ops.Admin(player, text) else print("[OPS] ADMIN " .. player.Name .. " " .. text) end
end

local function grant(admin, targetUserId, kind, amount)
	local limit = GRANT_MAX[kind]
	if not limit or typeof(targetUserId) ~= "number" or typeof(amount) ~= "number" or amount ~= amount then return end
	amount = math.clamp(math.floor(amount), 1, limit)
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then note(admin, "That player is not in this server.") return end
	if kind == "Keys" then
		local keys = module("KeyService")
		if not keys then return end
		keys.Add(target, amount)
	else
		target:SetAttribute(kind, (target:GetAttribute(kind) or 0) + amount)
	end
	log(admin, string.format("GRANT %s +%d -> %s(%d)", kind, amount, target.Name, target.UserId))
	note(admin, string.format("Gave %s +%d %s.", target.Name, amount, kind))
	if target ~= admin then note(target, string.format("🎁 You received +%d %s!", amount, kind)) end
end

local function announce(admin, text)
	if typeof(text) ~= "string" then return end
	text = string.gsub(string.sub(text, 1, 100), "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if #text == 0 then return end
	local ok, filtered = pcall(function() -- 모두에게 보이는 글이므로 Roblox 필터를 거친다
		return TextService:FilterStringAsync(text, admin.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(filtered) ~= "string" or #filtered == 0 then note(admin, "Could not send the announcement.") return end
	log(admin, "ANNOUNCE " .. filtered)
	for _, other in ipairs(Players:GetPlayers()) do
		note(other, "📢 " .. filtered)
	end
end

Remotes.Admin.OnServerEvent:Connect(function(player, action, a, b, c)
	if not isAdmin(player) then return end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.3 and action ~= "List" then return end
	if action ~= "List" then lastAction[player] = now end

	if action == "RestartTutorial" then -- 내 튜토리얼 진행만 처음으로 (레벨 / 장비 / 골드는 그대로)
		local tutorial = module("TutorialService")
		if tutorial and tutorial.Restart and tutorial.Restart(player) then
			note(player, "Tutorial restarted from the first mission.")
		end
	elseif action == "Grant" then
		grant(player, a, b, c)
	elseif action == "Announce" then
		announce(player, a)
	elseif action == "HallRemove" then -- 명예의 전당 a 번째 기록을 지우고 그 유저가 다시 올라오지 못하게 막는다 (이상한 점수 대응)
		local showcase = module("ShowcaseService")
		if typeof(a) == "number" and showcase and showcase.RemoveHall then
			local ok, info = showcase.RemoveHall(a)
			log(player, string.format("HALL REMOVE rank %d -> %s %s", a, tostring(ok), tostring(info)))
			note(player, ok and ("Removed " .. tostring(info) .. " from the Hall of Fame.") or ("Could not remove: " .. tostring(info)))
		end
	elseif action == "ResetArm" then -- 저장 초기화는 두 단계: 먼저 확인을 열고, 30초 안에 한 번 더 눌러야 실행된다
		armedAt[player] = now
		Remotes.Admin:FireClient(player, "ResetArmed")
	elseif action == "ResetConfirm" then
		local armed = armedAt[player]
		armedAt[player] = nil
		if not armed or now - armed > 30 then note(player, "Reset expired. Start again.") return end
		local data = module("DataService")
		log(player, "RESET own save")
		if data and data.Wipe and data.Wipe(player) then
			player:Kick("Your save was reset. Rejoin to start fresh.")
		else
			note(player, "Reset failed (DataStore unavailable). Nothing was changed.")
		end
	elseif action == "List" then
		if now - (lastRequest[player] or 0) < 1 then return end
		lastRequest[player] = now
		Remotes.Admin:FireClient(player, "List", { Players = listPlayers(), JobId = string.sub(game.JobId, 1, 8), Count = #Players:GetPlayers() })
	end
end)

return Admin
