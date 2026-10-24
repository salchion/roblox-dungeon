-- FunnelLog (ServerScriptService > Modules 안의 ModuleScript, 이름: FunnelLog)
-- "사람들이 어디서 막히고 언제 그만두는지" 를 Roblox 기본 분석(AnalyticsService)에 기록한다.
--   결과 보는 곳: Creator Hub > 체험 > 애널리틱스 > 퍼널(Funnels) / 커스텀 이벤트(Custom Events). 보통 하루 정도 뒤에 그래프로 나온다.
--   * 온보딩 퍼널: 새 유저가 튜토리얼 미션을 몇 번째까지 끝냈는지 (단계별로 몇 %가 남았는지 그래프가 나온다)
--   * 이정표: 레벨 5 / 10 / 20 / 30 / 50 도달, 필드 구역 2 ~ 8 첫 도달, 던전 / 보스러쉬 입장
--   * 접속을 끝낼 때 요약: 플레이한 분, 그 동안 처치 / 강화 / 던전 클리어 / 사망 수, 어디서 나갔는지(마을 / 필드 / 던전)
--   기록은 한 사람당 몇 번뿐이라 서버 부담은 거의 없다. 실패해도 게임에는 영향이 없다 (pcall).
--   라이브 서버 로그에서도 "[FUNNEL]" 로 검색하면 같은 내용이 한 줄씩 보인다.

local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local STUDIO = RunService:IsStudio()
local FunnelLog = {}

local LEVEL_MARKS = { 5, 10, 20, 30, 50, 80, 120 }
local SESSION_STATS = { "Kills", "Enhances", "DungeonClears", "FieldDeaths", "Rolls", "BossKills" }

local sessions = setmetatable({}, { __mode = "k" }) -- [player] = { Start, Stats, Level0 }

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and STUDIO then warn("[FUNNEL] " .. tostring(err)) end
end

local function custom(player, name, value)
	if not STUDIO then print(string.format("[FUNNEL] %s · %s = %s", player.Name, name, tostring(value or 1))) end
	safe(function() AnalyticsService:LogCustomEvent(player, name, value or 1) end)
end

-- 튜토리얼: step 1 = 새로 시작, step k+1 = k번째 미션 완료
function FunnelLog.Onboarding(player, step, name)
	if not STUDIO then print(string.format("[FUNNEL] %s · onboarding %d %s", player.Name, step, name)) end
	safe(function() AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name) end)
end

function FunnelLog.Event(player, name, value)
	custom(player, name, value)
end

local function track(player)
	local session = { Start = os.clock(), Stats = {}, Level0 = player:GetAttribute("Level") or 1 }
	sessions[player] = session
	-- 처음 값은 저장된 데이터가 다 불러와진 뒤 기준으로 잡는다 (불러오는 순간 값이 바뀌는 걸 "도달" 로 세지 않게)
	task.spawn(function()
		local waited = 0
		while player.Parent and player:GetAttribute("DataReady") ~= true and waited < 30 do
			task.wait(0.5)
			waited += 0.5
		end
		if not player.Parent then return end
		local lastLevel = player:GetAttribute("Level") or 1
		local lastZone = player:GetAttribute("MaxZone") or 0
		session.Level0 = lastLevel
		player:GetAttributeChangedSignal("Level"):Connect(function()
			local level = player:GetAttribute("Level") or 1
			for _, mark in ipairs(LEVEL_MARKS) do
				if lastLevel < mark and level >= mark then custom(player, "ReachedLevel" .. mark) end
			end
			lastLevel = math.max(lastLevel, level)
		end)
		player:GetAttributeChangedSignal("MaxZone"):Connect(function()
			local zone = player:GetAttribute("MaxZone") or 0
			if zone > lastZone then
				for z = lastZone + 1, zone do
					if z >= 2 then custom(player, "ReachedZone" .. z) end
				end
				lastZone = zone
			end
		end)
		player:GetAttributeChangedSignal("Zone"):Connect(function()
			if player:GetAttribute("Zone") == "Dungeon" then
				task.delay(1, function() -- (던전 종류 표시가 정해진 뒤)
					if player.Parent and player:GetAttribute("Zone") == "Dungeon" then
						custom(player, player:GetAttribute("DungeonTypeKey") == "Rift" and "BossRushEnter" or "DungeonEnter")
					end
				end)
			end
		end)
	end)
end

function FunnelLog.Start(quest)
	if quest and quest.Listeners then
		table.insert(quest.Listeners, function(player, stat, amount)
			local session = sessions[player]
			if session then session.Stats[stat] = (session.Stats[stat] or 0) + (amount or 1) end
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in ipairs(Players:GetPlayers()) do track(player) end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if not session then return end
		sessions[player] = nil
		local minutes = math.floor((os.clock() - session.Start) / 60 + 0.5)
		custom(player, "SessionMinutes", minutes)
		custom(player, "LeftIn_" .. tostring(player:GetAttribute("Zone") or "Unknown"))
		custom(player, "SessionLevelsGained", math.max(0, (player:GetAttribute("Level") or 1) - session.Level0))
		for _, stat in ipairs(SESSION_STATS) do
			local value = session.Stats[stat]
			if value and value > 0 then custom(player, "Session" .. stat, value) end
		end
	end)
end

return FunnelLog
