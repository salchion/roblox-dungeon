-- StatusService (ServerScriptService > Modules 안의 ModuleScript, 이름: StatusService)
-- 공격 중 상태이상 (11-24): 강공격(T3)에 맞으면 플레이어에게 걸린다. 화상 / 둔화 / 감전.
--   대시·무빙으로 피해야 할 이유를 만드는 것이 목적이라 세기는 작게, 표시는 확실하게 잡았다.
--   * 화상 🔥 : 4초 동안 그 공격 피해의 6%를 나눠 받는다 (0.5초 x 8틱, 내 최대 체력이 아니라 적 공격력 기준.
--     11-24 종태 님: "대미지에 퍼센트 개념은 없었으면 좋겠어" — 예전 "초당 최대 체력 1.2%"와 세기가 같다)
--   * 둔화 🐌 : 2.5초 이동 -35%. 대시 속도에는 걸지 않는다 (둔화 상태에서도 대시로 빠져나가는 맛이 핵심)
--   * 감전 ⚡ : 1초 공격 속도 -25% (이동이 아니라 공격이 느려진다: 둔화와 겹치지 않게)
--   같은 상태이상은 Immune(1.5초) 안에 다시 걸리지 않는다. 100마리 필드에서 계속 걸리면 답이 없기 때문.
-- 클라이언트(PlayerFX)가 Attributes 를 읽어 이모지 칩 + 남은 시간으로 보여 준다 (새 문구 없음).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Guard = require(script.Parent:WaitForChild("DamageGuard"))

local Status = {}
local lastAt = setmetatable({}, { __mode = "k" }) -- [player] = { [kind] = os.clock() }

local function humanoidOf(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- kind: "Burn" / "Slow" / "Shock" (Config.Threat.Status.Kind 표가 공격 -> 상태이상을 정한다)
-- hit: 이 상태를 건 공격의 피해량 (화상은 그 비율만큼 8틱으로 나눠 받는다)
function Status.Apply(player, kind, hit)
	local S = Config.Threat and Config.Threat.Status
	local spec = S and S[kind]
	if not player or not player.Parent or not spec then return end
	local now = os.clock()
	local mine = lastAt[player]
	if not mine then mine = {} lastAt[player] = mine end
	if now - (mine[kind] or -99) < S.Immune then return end
	mine[kind] = now
	local untilAt = workspace:GetServerTimeNow() + spec.Duration
	if kind == "Burn" then
		-- 한 틱 = 공격 피해 x HitShare / 8 (4초 / 0.5초). 최소 1 이라 약한 공격에도 0 이 되지 않는다
		local perTick = math.max(1, math.floor((hit or 0) * (spec.HitShare or 0) / 8 + 0.5))
		player:SetAttribute("StatusBurnTick", perTick)
		player:SetAttribute("StatusBurnUntil", untilAt)
	elseif kind == "Slow" then
		player:SetAttribute("StatusSlowPct", spec.Amount)
		player:SetAttribute("StatusSlowUntil", untilAt)
	elseif kind == "Shock" then
		player:SetAttribute("StatusShockPct", spec.Amount)
		player:SetAttribute("StatusShockUntil", untilAt)
	end
	pcall(function() require(script.Parent:WaitForChild("BalanceLog")).Count(player, "Status_" .. kind, 1) end) -- (Studio 밸런스 로그)
end

-- 화상 도트: 0.5초마다 걸릴 때 계산해 둔 고정 피해(StatusBurnTick)를 준다. Guard.Take 라서 방어 / 방벽이 똑같이 적용된다
task.spawn(function()
	while true do
		task.wait(0.5)
		local now = workspace:GetServerTimeNow()
		for _, player in ipairs(Players:GetPlayers()) do
			if (player:GetAttribute("StatusBurnUntil") or 0) > now then
				local humanoid = humanoidOf(player)
				local tick = player:GetAttribute("StatusBurnTick") or 0
				if humanoid and humanoid.Health > 0 and tick > 0 then
					Guard.Take(humanoid, tick)
				end
			end
		end
	end
end)

return Status
