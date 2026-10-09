-- MonetizationService (ServerScriptService > Modules 안의 ModuleScript, 이름: MonetizationService)
-- BM(유료 상품)을 나중에 붙일 수 있게 미리 만들어 둔 구조.
--
-- 설계 원칙: "시간을 돈으로 산다". 모든 성장은 돈을 안 써도 시간만 들이면 도달할 수 있고, 돈은 그 시간을 줄여준다.
--   시간 단축권(훈련소 / 돌파 대기) / 훈련 슬롯 / 열쇠(던전 횟수) / 경험치·행운 부스터 / 가방 칸 / 티켓 / VIP 패스 -> 성장 속도(전투력)에 영향
--   오라(꾸미기)는 능력치가 없다. PvE 전용이라 다른 플레이어를 해치지 않는다.
--   필드 파밍으로 좋은 장비를 직접 얻는 재미(과시)는 돈으로 건너뛸 수 없다 (장비 자체를 팔지 않음).
--
-- 사용 방법: Config.Shop 의 ProductId / PassId 를 실제 Roblox ID 로 바꾸면 판매가 켜진다 (0 이면 "준비 중").
--   Studio 에서는 ID 가 0 이어도 [테스트 지급]이 되어 효과를 미리 확인할 수 있다 (실서비스에서는 막힘).
--   * 소모성 상품(Developer Product): ProcessReceipt 로 지급 + 영수증 중복 방지 + 저장 성공 후에만 완료 처리
--   * 패스(Game Pass): 접속 시 보유 여부 확인 + 구매 즉시 반영
-- 효과는 플레이어 Attribute 로 반영돼서 다른 시스템이 읽는다:
--   Vip, BagBonus(가방 칸), KeyCapBonus / KeyRegenBonus(열쇠), TrainSlotBonus(훈련 슬롯), XpBoostUntil / LuckBoostUntil(부스터 만료 시각), Aura

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Keys = require(script.Parent:WaitForChild("KeyService"))
local Quest = require(script.Parent:WaitForChild("QuestService"))
local Growth = require(script.Parent:WaitForChild("GrowthService"))
local Cosmetics = require(ReplicatedStorage:WaitForChild("Cosmetics"))

local S = Config.Shop

local Monetization = {}

-- GameServer 가 DataService 의 저장 함수를 넣어준다 (영수증 처리 때 "저장 성공"을 확인하려고). 서로 require 하지 않기 위함.
Monetization.SaveHook = nil

local states = {}   -- [player] = { Bag, XpBoostUntil, LuckBoostUntil, AuraUnlocked, Aura, Receipts, Passes }

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

------------------------------------------------------------
-- 오라 / Attribute 반영
------------------------------------------------------------
-- 꾸미기 종류별 설정표 / 해금 기록의 키 (오라는 예전 저장 형식 그대로 key 만, 깃발 / 탈것은 "Banner_Key" 형태)
local COSMETIC_TABLE = { Aura = Config.Auras, Banner = Config.Banners, Mount = Config.Mounts }
local function unlockKey(kind, key)
	return kind == "Aura" and key or (kind .. "_" .. key)
end

local function isCosmeticOwned(player, state, kind, key)
	local aura = COSMETIC_TABLE[kind] and COSMETIC_TABLE[kind][key]
	if not aura or key == "Order" then return false end
	local unlock = aura.Unlock
	if unlock == "Free" then return true end
	if state.AuraUnlocked[unlockKey(kind, key)] then return true end
	if typeof(unlock) == "table" then
		if unlock.Ach then return Quest.IsDone(player, unlock.Ach) end
		if unlock.Pass then return state.Passes[unlock.Pass] == true end
	end
	return false
end

local function isAuraOwned(player, state, key)
	return isCosmeticOwned(player, state, "Aura", key)
end

local function applyAttributes(player, state)
	local vip = state.Passes.VIP == true
	player:SetAttribute("Vip", vip)
	player:SetAttribute("BagBonus", state.Bag + (vip and S.Vip.Bag or 0))
	player:SetAttribute("KeyCapBonus", vip and S.Vip.KeyCap or 0)
	player:SetAttribute("KeyRegenBonus", vip and S.Vip.KeyRegen or 0)
	player:SetAttribute("TrainSlotBonus", state.TrainSlot + (vip and S.Vip.TrainSlots or 0))
	player:SetAttribute("XpBoostUntil", state.XpBoostUntil)
	player:SetAttribute("LuckBoostUntil", state.LuckBoostUntil)
	player:SetAttribute("IdleBoostUntil", state.IdleBoostUntil)
	local idleTier = state.IdleMultTier > 0 and Config.Idle.MultTiers[math.min(state.IdleMultTier, #Config.Idle.MultTiers)] or 0
	player:SetAttribute("IdleMultBonus", idleTier + (vip and Config.Idle.VipBonus or 0))
	player:SetAttribute("IdleCapBonusHours", state.IdleCapTier > 0 and Config.Idle.CapTiers[math.min(state.IdleCapTier, #Config.Idle.CapTiers)] or 0)

	for _, key in ipairs(Config.Auras.Order) do
		player:SetAttribute("AuraOwned_" .. key, isAuraOwned(player, state, key))
	end
	if state.Aura ~= "" and not isAuraOwned(player, state, state.Aura) then
		state.Aura = ""
	end
	player:SetAttribute("Aura", state.Aura)

	for _, kind in ipairs({ "Banner", "Mount" }) do
		for _, key in ipairs(COSMETIC_TABLE[kind].Order) do
			player:SetAttribute(kind .. "Owned_" .. key, isCosmeticOwned(player, state, kind, key))
		end
		if state[kind] ~= "" and not isCosmeticOwned(player, state, kind, state[kind]) then
			state[kind] = ""
		end
		player:SetAttribute(kind, state[kind])
	end
end

-- 캐릭터에 오라 효과를 붙인다 (다른 플레이어에게도 보임 = 꾸미기/과시). 캐릭터 생성 / 오라 변경 때 호출.
function Monetization.ApplyAura(player)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	for _, kind in ipairs({ "Aura", "Banner", "Mount" }) do
		local key = player:GetAttribute(kind) or ""
		if COSMETIC_TABLE[kind][key] and key ~= "Order" then
			Cosmetics.Build(kind, key, character)
		else
			Cosmetics.Clear(character, kind)
		end
	end
end

------------------------------------------------------------
-- 지급
------------------------------------------------------------
-- grant: Config.Shop 의 Grant 테이블 (Keys / Tickets / XpBoost / LuckBoost / Bag / Aura)
function Monetization.Grant(player, grant)
	local state = states[player]
	if not state then return end

	if grant.Keys then
		Keys.Add(player, grant.Keys)
	end
	if grant.Tickets then
		player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + grant.Tickets)
	end
	if grant.XpBoost then
		state.XpBoostUntil = math.max(os.time(), state.XpBoostUntil) + grant.XpBoost
	end
	if grant.LuckBoost then
		state.LuckBoostUntil = math.max(os.time(), state.LuckBoostUntil) + grant.LuckBoost
	end
	if grant.IdleBoost then
		state.IdleBoostUntil = math.max(os.time(), state.IdleBoostUntil) + grant.IdleBoost
	end
	if grant.IdleMult then
		state.IdleMultTier = math.max(state.IdleMultTier, grant.IdleMult) -- 높은 단계 하나만 적용 (덮어쓰기)
	end
	if grant.IdleCap then
		state.IdleCapTier = math.max(state.IdleCapTier, grant.IdleCap)
	end
	if grant.Bag then
		state.Bag += grant.Bag
	end
	if grant.TrainSlot then
		state.TrainSlot += grant.TrainSlot
	end
	if grant.TimeSkip then
		Growth.AddTimeSkip(player, grant.TimeSkip)
	end
	if grant.Aura then
		state.AuraUnlocked[grant.Aura] = true
	end
	if grant.Banner then
		state.AuraUnlocked["Banner_" .. grant.Banner] = true
	end
	if grant.Mount then
		state.AuraUnlocked["Mount_" .. grant.Mount] = true
	end
	applyAttributes(player, state)
end

------------------------------------------------------------
-- 저장 / 불러오기
------------------------------------------------------------
function Monetization.Load(player, saved)
	local state = { Bag = 0, TrainSlot = 0, XpBoostUntil = 0, LuckBoostUntil = 0, IdleBoostUntil = 0, IdleMultTier = 0, IdleCapTier = 0, AuraUnlocked = {}, Aura = "", Banner = "", Mount = "", Receipts = {}, Passes = {} }
	if typeof(saved) == "table" then
		state.Bag = math.max(0, math.floor(tonumber(saved.Bag) or 0))
		state.TrainSlot = math.max(0, math.floor(tonumber(saved.TrainSlot) or 0))
		state.XpBoostUntil = tonumber(saved.XpBoostUntil) or 0
		state.LuckBoostUntil = tonumber(saved.LuckBoostUntil) or 0
		state.IdleBoostUntil = tonumber(saved.IdleBoostUntil) or 0
		state.IdleMultTier = math.clamp(math.floor(tonumber(saved.IdleMultTier) or 0), 0, #Config.Idle.MultTiers)
		state.IdleCapTier = math.clamp(math.floor(tonumber(saved.IdleCapTier) or 0), 0, #Config.Idle.CapTiers)
		if typeof(saved.AuraUnlocked) == "table" then state.AuraUnlocked = saved.AuraUnlocked end
		if typeof(saved.Aura) == "string" then state.Aura = saved.Aura end
		if typeof(saved.Banner) == "string" then state.Banner = saved.Banner end
		if typeof(saved.Mount) == "string" then state.Mount = saved.Mount end
		if typeof(saved.Receipts) == "table" then state.Receipts = saved.Receipts end
	end
	states[player] = state

	-- 패스 보유 여부 (ID 가 설정된 패스만 확인)
	for key, def in pairs(S.Passes) do
		if def.PassId > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.PassId)
			end)
			if ok and owns then
				state.Passes[key] = true
			end
		end
	end
	applyAttributes(player, state)
end

function Monetization.Serialize(player)
	local state = states[player]
	if not state then return nil end
	return {
		Bag = state.Bag, TrainSlot = state.TrainSlot, XpBoostUntil = state.XpBoostUntil, LuckBoostUntil = state.LuckBoostUntil,
		IdleBoostUntil = state.IdleBoostUntil, IdleMultTier = state.IdleMultTier, IdleCapTier = state.IdleCapTier,
		AuraUnlocked = state.AuraUnlocked, Aura = state.Aura, Banner = state.Banner, Mount = state.Mount, Receipts = state.Receipts,
	}
end

function Monetization.Forget(player)
	states[player] = nil
end

------------------------------------------------------------
-- 구매 요청 (클라이언트 상점 탭)
------------------------------------------------------------
local lastRequest = setmetatable({}, { __mode = "k" })

Remotes.Shop.OnServerEvent:Connect(function(player, action, kind, key)
	local state = states[player]
	if not state then return end

	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.3 then return end
	lastRequest[player] = now

	if action == "Aura" then
		-- 두 번째 인자(kind) 자리에 오라 이름("" 이면 해제)이 온다
		local auraKey = kind
		if auraKey == "" or auraKey == nil then
			state.Aura = ""
		elseif typeof(auraKey) == "string" and isAuraOwned(player, state, auraKey) then
			state.Aura = auraKey
		else
			notify(player, "⚠ 아직 얻지 못한 오라예요.")
			return
		end
		applyAttributes(player, state)
		Monetization.ApplyAura(player)
		return
	end

	if action == "Cosmetic" then
		-- kind = "Banner" | "Mount" (오라는 위의 "Aura" 동작), key = 이름 ("" 이면 해제)
		if (kind ~= "Banner" and kind ~= "Mount") or typeof(key) ~= "string" then return end
		if key == "" then
			state[kind] = ""
		elseif isCosmeticOwned(player, state, kind, key) then
			state[kind] = key
		else
			notify(player, "⚠ 아직 얻지 못한 꾸미기예요.")
			return
		end
		applyAttributes(player, state)
		Monetization.ApplyAura(player)
		return
	end

	if action ~= "Buy" or typeof(kind) ~= "string" or typeof(key) ~= "string" then return end
	local isPass = kind == "Pass"
	local def = (isPass and S.Passes or S.Products)[key]
	if not def or (kind ~= "Pass" and kind ~= "Product") then return end

	if isPass and state.Passes[key] then
		notify(player, "이미 가지고 있는 패스예요!")
		return
	end

	local id = isPass and def.PassId or def.ProductId
	if id > 0 then
		if isPass then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	elseif RunService:IsStudio() then
		-- Studio 테스트 전용: ID 없이 효과만 확인
		if isPass then
			state.Passes[key] = true
			applyAttributes(player, state)
		else
			Monetization.Grant(player, def.Grant)
		end
		notify(player, "🧪 [Studio 테스트 지급] " .. def.Name)
	else
		notify(player, "아직 준비 중인 상품이에요.")
	end
end)

-- 패스 구매 직후 바로 반영
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	local state = states[player]
	if not state or not purchased then return end
	for key, def in pairs(S.Passes) do
		if def.PassId > 0 and def.PassId == passId then
			state.Passes[key] = true
			applyAttributes(player, state)
			notify(player, "🎉 " .. def.Name .. " 적용 완료!")
		end
	end
end)

-- 소모성 상품 영수증 처리: 같은 영수증이 다시 와도 두 번 지급하지 않고, 저장이 성공한 뒤에만 완료로 돌려준다
MarketplaceService.ProcessReceipt = function(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local state = player and states[player]
	if not state then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptKey = tostring(info.PurchaseId)
	if state.Receipts[receiptKey] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local product
	for _, def in pairs(S.Products) do
		if def.ProductId > 0 and def.ProductId == info.ProductId then
			product = def
		end
	end
	if not product then
		warn("[Shop] 알 수 없는 상품 ID:", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Monetization.Grant(player, product.Grant)
	state.Receipts[receiptKey] = os.time()

	-- 오래된 영수증은 정리 (최대 200개 보관)
	local count, oldestKey, oldestTime = 0, nil, math.huge
	for key, time in pairs(state.Receipts) do
		count += 1
		if time < oldestTime then
			oldestKey, oldestTime = key, time
		end
	end
	if count > 200 and oldestKey then
		state.Receipts[oldestKey] = nil
	end

	if Monetization.SaveHook and not Monetization.SaveHook(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- 저장 실패: Roblox 가 나중에 다시 시도 (영수증으로 중복 지급은 막힘)
	end
	notify(player, "🛍 구매 완료: " .. product.Name)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- 업적으로 해금되는 오라 등이 바뀌는 걸 반영 (5초마다)
task.spawn(function()
	while true do
		task.wait(5)
		for player, state in pairs(states) do
			if player.Parent then
				applyAttributes(player, state)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

return Monetization
