-- EventService (ServerScriptService > Modules 안의 ModuleScript, 이름: EventService)
-- 주기적인 "골든 타임": 몇 분 동안 경험치/골드 보너스. 다 같이 접속해서 달리는 시간을 만든다 (희소성 + 시간 압박).
-- workspace Attribute "GoldenUntil"(os.time) 이 미래면 진행 중. Config.IsGoldenTime() 으로 어디서든 확인한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local Event = {}

local function announce(text)
	for _, player in ipairs(Players:GetPlayers()) do
		Remotes.Notify:FireClient(player, text)
	end
end

-- 전체 서버에 한 줄 알림 (무기 진화, 전설 펫 같은 자랑거리용)
function Event.Announce(text)
	announce(text)
end

function Event.Start()
	task.spawn(function()
		workspace:SetAttribute("GoldenNext", os.time() + Config.Golden.FirstDelay) -- 클라이언트의 "다음 골든 타임까지" 표시용
		task.wait(Config.Golden.FirstDelay)
		while true do
			if #Players:GetPlayers() > 0 then
				workspace:SetAttribute("GoldenUntil", os.time() + Config.Golden.Duration)
				announce(string.format("🌟 골든 타임 시작! %d분 동안 경험치 x%d, 골드 x%.1f!", Config.Golden.Duration / 60, Config.Golden.XpMult, Config.Golden.GoldMult))
				task.wait(Config.Golden.Duration)
				announce("골든 타임이 끝났어요. 다음 골든 타임을 기대해주세요!")
			end
			workspace:SetAttribute("GoldenNext", os.time() + Config.Golden.Interval)
			task.wait(Config.Golden.Interval)
		end
	end)
end

return Event
