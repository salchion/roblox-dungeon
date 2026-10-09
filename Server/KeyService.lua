-- KeyService (ServerScriptService > Modules 안의 ModuleScript, 이름: KeyService)
-- 던전 열쇠: 던전 입장 제한. 시간이 지나면 자동으로 차오르므로 숙제처럼 매일 접속할 필요가 없다 (최대치에서 멈춤).
--   * 플레이어 Attribute: Keys(보유), KeyNext(다음 열쇠가 생기는 시각 os.time, 가득 차면 0)
--   * 최대 보유 수 / 회복 속도는 BM(VIP 등)이 KeyCapBonus / KeyRegenBonus Attribute 로 늘려준다
--   * 접속하지 않은 동안에도 시간이 흐른 만큼 회복 (오프라인 회복)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Keys = {}

local bases = {}   -- [player] = 열쇠 회복 시간을 세기 시작한 시각 (os.time)

local function maxKeys(player)
	return Config.Keys.Max + (player:GetAttribute("KeyCapBonus") or 0)
end

local function regenSeconds(player)
	return Config.Keys.RegenSeconds / (1 + (player:GetAttribute("KeyRegenBonus") or 0))
end

local function refreshNext(player)
	if (player:GetAttribute("Keys") or 0) >= maxKeys(player) then
		player:SetAttribute("KeyNext", 0)
	else
		player:SetAttribute("KeyNext", bases[player] + regenSeconds(player))
	end
end

local function tick(player)
	if not bases[player] then return end
	if Config.Keys.RegenSeconds <= 0 then -- 시간 회복 없음 (필드 군주 드랍 / 보상으로만 늘어난다)
		player:SetAttribute("KeyNext", 0)
		return
	end
	local keys = player:GetAttribute("Keys") or 0
	local cap = maxKeys(player)
	local now = os.time()

	if keys >= cap then
		bases[player] = now
	else
		local regen = regenSeconds(player)
		while keys < cap and now - bases[player] >= regen do
			keys += 1
			bases[player] += regen
		end
		if keys >= cap then
			bases[player] = now
		end
		player:SetAttribute("Keys", keys)
	end
	refreshNext(player)
end

-- savedKeys 가 nil 이면 처음 접속한 플레이어: 시작 열쇠를 준다
function Keys.Load(player, savedKeys, savedBase)
	local keys = savedKeys == nil and Config.Keys.Start or math.max(0, math.floor(tonumber(savedKeys) or 0))
	bases[player] = tonumber(savedBase) or os.time()
	player:SetAttribute("Keys", keys)
	tick(player) -- 접속하지 않은 동안 쌓인 만큼 회복
end

function Keys.Serialize(player)
	return { Keys = player:GetAttribute("Keys") or 0, Base = bases[player] or os.time() }
end

function Keys.Has(player, amount)
	return (player:GetAttribute("Keys") or 0) >= amount
end

function Keys.Spend(player, amount)
	local keys = player:GetAttribute("Keys") or 0
	if keys < amount then return false end
	if keys >= maxKeys(player) then
		bases[player] = os.time() -- 가득 찬 상태에서 쓰면 이때부터 회복 시작
	end
	player:SetAttribute("Keys", keys - amount)
	refreshNext(player)
	return true
end

-- 보상 / 상품으로 열쇠 추가 (최대치를 넘어도 괜찮다. 최대치 아래로 내려가야 다시 자동 회복)
function Keys.Add(player, amount)
	player:SetAttribute("Keys", (player:GetAttribute("Keys") or 0) + amount)
	refreshNext(player)
end

function Keys.Forget(player)
	bases[player] = nil
end

task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do
			tick(player)
		end
	end
end)

return Keys
