-- EventService (ServerScriptService > Modules 안의 ModuleScript, 이름: EventService)
-- 서버 전체 알림(Announce): 무기 진화 / 심연 기록 같은 자랑거리를 모두에게 알린다.

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

-- (예전의 주기적 골든 타임은 밸런스를 잡기 어려워서 없앴다. 알림만 남아 있다)
function Event.Start() end

return Event
