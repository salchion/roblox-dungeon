-- ComboService (ServerScriptService > Modules 안의 ModuleScript, 이름: ComboService)
-- 연속 처치 콤보: 몬스터를 잡을 때마다 +1, 4초 안에 다음 처치가 없으면 0으로 돌아간다.
--   콤보 1개당 공격력 +1% (최대 +50%) / 처치마다 궁극기 게이지 +4
-- Combo / ComboUntil Attribute 로 클라이언트가 HUD 를 그린다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local C = Config.Combo

local Combo = {}

function Combo.Kill(player)
	local now = os.clock()
	local count = (player:GetAttribute("Combo") or 0) + 1
	player:SetAttribute("Combo", count)
	player:SetAttribute("ComboUntil", now + C.Window)
	if player:GetAttribute("Zone") ~= "Lobby" then
		player:SetAttribute("UltCharge", math.min(Config.Skills.Ult.Cost, (player:GetAttribute("UltCharge") or 0) + C.UltPerKill))
	end
end

-- 공격력 배율 (ComputeDamage 에서 곱한다)
function Combo.GetDamageMult(player)
	return 1 + math.min(C.MaxStacks, player:GetAttribute("Combo") or 0) * C.DamagePerStack
end

task.spawn(function()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			if (player:GetAttribute("Combo") or 0) > 0 and now > (player:GetAttribute("ComboUntil") or 0) then
				player:SetAttribute("Combo", 0)
			end
		end
	end
end)

return Combo
