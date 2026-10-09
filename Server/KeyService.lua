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

-- 열쇠는 3단계: Keys(쉬움) / KeysNormal(보통) / KeysHard(어려움)
local TIER_ATTRS = { "Keys", "KeysNormal", "KeysHard" }

-- savedKeys 가 nil 이면 처음 접속한 플레이어: 시작 열쇠를 준다. savedTable = 저장된 전체(보통 / 어려움 열쇠 포함)
function Keys.Load(player, savedKeys, savedBase, savedTable)
	local keys = savedKeys == nil and Config.Keys.Start or math.max(0, math.floor(tonumber(savedKeys) or 0))
	bases[player] = tonumber(savedBase) or os.time()
	player:SetAttribute("Keys", keys)
	player:SetAttribute("KeysNormal", typeof(savedTable) == "table" and math.max(0, math.floor(tonumber(savedTable.Normal) or 0)) or 0)
	player:SetAttribute("KeysHard", typeof(savedTable) == "table" and math.max(0, math.floor(tonumber(savedTable.Hard) or 0)) or 0)
	tick(player) -- 접속하지 않은 동안 쌓인 만큼 회복
end

function Keys.Serialize(player)
	return { Keys = player:GetAttribute("Keys") or 0, Base = bases[player] or os.time(), Normal = player:GetAttribute("KeysNormal") or 0, Hard = player:GetAttribute("KeysHard") or 0 }
end

-- 단계 열쇠: tier 이상의 열쇠 합이 amount 이상이면 입장 가능 (높은 열쇠는 낮은 난이도에도 쓸 수 있다)
function Keys.HasTier(player, tier, amount)
	local total = 0
	for t = tier, 3 do
		total += player:GetAttribute(TIER_ATTRS[t]) or 0
	end
	return total >= amount
end

-- 필요한 단계 이상 중 가장 낮은 열쇠부터 쓴다
function Keys.SpendTier(player, tier, amount)
	if not Keys.HasTier(player, tier, amount) then return false end
	for t = tier, 3 do
		local have = player:GetAttribute(TIER_ATTRS[t]) or 0
		local use = math.min(have, amount)
		if use > 0 then
			player:SetAttribute(TIER_ATTRS[t], have - use)
			amount -= use
		end
		if amount <= 0 then break end
	end
	return true
end

function Keys.AddTier(player, tier, amount)
	local attr = TIER_ATTRS[tier] or "Keys"
	player:SetAttribute(attr, (player:GetAttribute(attr) or 0) + amount)
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
