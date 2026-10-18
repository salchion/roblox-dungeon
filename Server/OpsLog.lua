-- OpsLog (ServerScriptService > Modules 안의 ModuleScript, 이름: OpsLog)
-- 실제 서비스(라이브)용 운영 로그. Creator Hub > 체험 > 서버 로그(또는 Studio 출력창)에서 "[OPS]" 로 검색한다.
--   접속 / 퇴장(플레이 시간, 레벨·골드 증감) / 구매. 한 줄에 한 사건, 값은 모두 숫자나 짧은 글자라 로그가 가볍다.
--   Studio 에서는 접속·퇴장 줄을 찍지 않는다(구매는 테스트 확인용으로 찍는다).
--   이상치 경고: 30초마다 골드·티켓·레벨 증가량을 보고, 한계를 넘으면 "[OPS][WARN]" 한 줄을 남긴다(경고만 한다 - 자동 제재는 하지 않는다).
--   한계값은 아래 LIMIT 에서 조정한다. 구매 직후 3분은 정상 지급이므로 건너뛴다. 처음 값은 추측이니 로그를 보며 고친다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STUDIO = RunService:IsStudio()
local OpsLog = {}

local joined = setmetatable({}, { __mode = "k" })

local CHECK_EVERY = 30 -- 초
local BUY_GRACE = 180 -- 구매 직후 이 시간(초) 동안은 검사하지 않는다
local WARN_EVERY = 120 -- 같은 종류 경고는 이 시간(초)에 한 번만
local LIMIT = {
	Gold = 3000000, -- 30초 동안 늘어난 골드
	Tickets = 150, -- 30초 동안 늘어난 티켓
	Level = 5, -- 30초 동안 오른 레벨
}

local function snap(player)
	return {
		Level = player:GetAttribute("Level") or 1,
		Power = player:GetAttribute("Power") or 0,
		Gold = player:GetAttribute("Gold") or 0,
		Tickets = player:GetAttribute("Tickets") or 0,
		Zone = player:GetAttribute("MaxZone") or 0,
	}
end

local function line(kind, player, text)
	print(string.format("[OPS] %s %s(%d) %s", kind, player.Name, player.UserId, text))
end

local function describe(s)
	return string.format("Lv%d Power%d Gold%d Tickets%d MaxZone%d", s.Level, s.Power, s.Gold, s.Tickets, s.Zone)
end

-- 운영자 작업 기록 (지급 / 공지 / 저장 초기화): 누가 무엇을 했는지 남긴다
function OpsLog.Admin(player, text)
	line("ADMIN", player, text)
end

function OpsLog.Purchase(player, productKey, robux)
	local entry = joined[player]
	if entry then entry.BuyAt = os.clock() end
	line("BUY", player, string.format("%s %sR$ | %s", tostring(productKey), tostring(robux or "?"), describe(snap(player))))
end

local function warnOnce(player, entry, kind, text)
	entry.Warned = entry.Warned or {}
	if os.clock() - (entry.Warned[kind] or -1e9) < WARN_EVERY then return end
	entry.Warned[kind] = os.clock()
	line("WARN", player, kind .. " " .. text)
end

task.spawn(function()
	while true do
		task.wait(CHECK_EVERY)
		for player, entry in pairs(joined) do
			if player.Parent and entry.Last then
				local now = snap(player)
				local last = entry.Last
				entry.Last = now
				if not (entry.BuyAt and os.clock() - entry.BuyAt < BUY_GRACE) then
					local text = string.format("%s | dGold%+d dTickets%+d dLv%+d in %ds", describe(now), now.Gold - last.Gold, now.Tickets - last.Tickets, now.Level - last.Level, CHECK_EVERY)
					if now.Gold - last.Gold > LIMIT.Gold then warnOnce(player, entry, "GOLD_JUMP", text) end
					if now.Tickets - last.Tickets > LIMIT.Tickets then warnOnce(player, entry, "TICKET_JUMP", text) end
					if now.Level - last.Level >= LIMIT.Level then warnOnce(player, entry, "LEVEL_JUMP", text) end
				end
			elseif player.Parent and player:GetAttribute("Level") then
				entry.Last = snap(player) -- 데이터가 불러와진 뒤부터 기준을 잡는다 (불러오는 순간의 증가는 경고하지 않는다)
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	joined[player] = { At = os.clock() }
	if STUDIO then return end
	-- 데이터가 불러와질 때까지 잠깐 기다린 뒤 한 번 찍는다 (최대 20초)
	task.spawn(function()
		local waited = 0
		while player.Parent and not player:GetAttribute("Level") and waited < 20 do
			task.wait(1)
			waited += 1
		end
		if not player.Parent then return end
		local entry = joined[player]
		if entry then entry.Start = snap(player) end
		line("JOIN", player, describe(snap(player)))
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local entry = joined[player]
	joined[player] = nil
	if STUDIO or not entry or not entry.Start then return end
	local now = snap(player)
	line("LEAVE", player, string.format("%dmin | %s | dLv%+d dGold%+d dTickets%+d", math.floor((os.clock() - entry.At) / 60), describe(now),
		now.Level - entry.Start.Level, now.Gold - entry.Start.Gold, now.Tickets - entry.Start.Tickets))
end)

return OpsLog
