-- OpsLog (ServerScriptService > Modules 안의 ModuleScript, 이름: OpsLog)
-- 실제 서비스(라이브)용 운영 로그. Creator Hub > 체험 > 서버 로그(또는 Studio 출력창)에서 "[OPS]" 로 검색한다.
--   접속 / 퇴장(플레이 시간, 레벨·골드 증감) / 구매. 한 줄에 한 사건, 값은 모두 숫자나 짧은 글자라 로그가 가볍다.
--   Studio 에서는 접속·퇴장 줄을 찍지 않는다(구매는 테스트 확인용으로 찍는다).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STUDIO = RunService:IsStudio()
local OpsLog = {}

local joined = setmetatable({}, { __mode = "k" })

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

function OpsLog.Purchase(player, productKey, robux)
	line("BUY", player, string.format("%s %sR$ | %s", tostring(productKey), tostring(robux or "?"), describe(snap(player))))
end

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
