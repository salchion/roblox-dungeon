-- IdleService (ServerScriptService > Modules 안의 ModuleScript, 이름: IdleService)
-- 방치 수입: 휴식 구역 원 안에 서 있으면 골드가 쌓이고(접속 중), 접속을 끊어도 일정 시간까지 쌓인다(오프라인 적립).
--   기준 수입 = "내가 가장 멀리 간 구역(MaxZone)의 필드 실수입" (Config.Idle.FieldIncomePerMin: 분당 100마리 기준)
--   방치 골드/분 = 기준 수입 x Config.Idle.Fraction x 방치 배율
--   방치 배율 = 1 + 영구 보너스(IdleMultBonus: 상품 단계 + VIP) + 부스터 활성 시 BoostBonus
--   오프라인 골드/분 = 기준 수입 x Fraction x OfflineEfficiency x 방치 배율
--   오프라인 적립 한도 = BaseCapHours + 상품(IdleCapHours)
-- 예전에는 IncomeBase 기준표를 기준으로 썼는데, 실제 필드 수입은 그 기준표의 2~10배라서
--   존 4~8에서 오프라인이 필드의 1.3~6% 밖에 안 됐다 ("받았는데 강화를 1~2번밖에 못 누른다"). 지금은 필드 100% / 방치 22% / 오프라인 13.2% 비율이 모든 구역에서 같다.
-- 원칙: 돈은 "방치 효율 / 쌓이는 시간"만 늘려 준다 (안 써도 도달 가능). 직접 쏘는 수입은 방치의 약 1/3 (DummyService).
-- 속성: IdleActive(훈련장에서 방치 중) / IdleRate(초당 골드) / IdleMultTotal(현재 배율)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Dummy = require(script.Parent:WaitForChild("DummyService"))
local Meta = require(script.Parent:WaitForChild("MetaService"))

local I = Config.Idle
local Idle = {}

local dummyCenter = nil
local remainder = setmetatable({}, { __mode = "k" })   -- [player] = 아직 지급하지 못한 소수점 골드
local pending = setmetatable({}, { __mode = "k" })     -- [player] = { Gold, Since } 3초 모아서 한 번에 글자로 보여준다

-- 방치 배율 (영구 + VIP + 부스터)
function Idle.Multiplier(player)
	local mult = 1 + (player:GetAttribute("IdleMultBonus") or 0)
	if (player:GetAttribute("IdleBoostUntil") or 0) > os.time() then
		mult += I.BoostBonus
	end
	return mult
end

-- 방치 기준 구역: 내가 가장 멀리 간 구역 (필드에서 x좌표로 기록되는 MaxZone). 아직 없으면 1구역
function Idle.Zone(player)
	return math.clamp(math.floor(player:GetAttribute("MaxZone") or 0), 1, Config.Field.ZoneCount)
end

-- 초당 방치 골드 = (내 최고 구역의 필드 실수입) x Fraction x 방치 배율. 구역 안에서 내 무기 단계가 올라가도 필드 수입은 그대로라서, 기준을 "내 레벨"이 아니라 "그 구역"에 둔다.
function Idle.Rate(player)
	return Config.Idle.FieldIncomePerMin(Idle.Zone(player)) * I.Fraction / 60 * Idle.Multiplier(player)
end

local function capSeconds(player)
	return ((I.BaseCapHours or 2) + (player:GetAttribute("IdleCapBonusHours") or 0)) * 3600
end

-- 초당 오프라인 골드 (방치 배율 제외, OfflineEfficiency 포함): 자리를 비운 동안 한 초에 쌓이는 값
function Idle.OfflineRate(player)
	return Config.Idle.FieldIncomePerMin(Idle.Zone(player)) * I.Fraction * I.OfflineEfficiency / 60
end

local function active(player)
	if player:GetAttribute("Zone") ~= "Lobby" or not dummyCenter then return false end
	if player:GetAttribute("TutorialActive") and not player:GetAttribute("QuestHud") then return false end -- 튜토리얼 초반에는 직접 쏘는 미션이 먼저
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	local flat = Vector3.new(root.Position.X - dummyCenter.X, 0, root.Position.Z - dummyCenter.Z).Magnitude
	return flat <= I.Radius
end

function Idle.Init(center)
	dummyCenter = center
	task.spawn(function()
		local seenTick = 0
		while true do
			task.wait(1)
			seenTick += 1
			for _, player in ipairs(Players:GetPlayers()) do
				local isActive = active(player)
				if player:GetAttribute("IdleActive") ~= isActive then
					player:SetAttribute("IdleActive", isActive)
				end
				local rate = Idle.Rate(player)
				player:SetAttribute("IdleRate", math.floor(rate * 10) / 10)
				player:SetAttribute("IdleMultTotal", Idle.Multiplier(player))
				local capHours = capSeconds(player) / 3600
				player:SetAttribute("IdleCapHours", capHours) -- 자리를 비웠을 때 쌓이는 최대 시간
				player:SetAttribute("IdleFullGold", math.floor(capSeconds(player) * Idle.OfflineRate(player) * Idle.Multiplier(player))) -- 한도까지 가득 찼을 때 받는 골드
				if isActive then
					player:SetAttribute("IdleSeconds", (player:GetAttribute("IdleSeconds") or 0) + 1) -- 게이지: 이번 접속에서 방치한 시간 / 받은 골드
					local owed = (remainder[player] or 0) + rate
					local gold = math.floor(owed)
					remainder[player] = owed - gold
					if gold > 0 then
						player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
						player:SetAttribute("IdleEarned", (player:GetAttribute("IdleEarned") or 0) + gold)
						pcall(function() require(script.Parent:WaitForChild("BalanceLog")).Gold(player, "방치", gold) end) -- (Studio 밸런스 로그)
						local bucket = pending[player] or { Gold = 0, Since = os.clock() }
						bucket.Gold += gold
						pending[player] = bucket
						Dummy.IdleHit(player) -- 허수아비가 번쩍인다
						if os.clock() - bucket.Since >= 3 then
							Effects.FloatText(dummyCenter + Vector3.new(0, 14, 0), string.format("💤 +%d G", bucket.Gold), Color3.fromRGB(255, 220, 90))
							pending[player] = nil
						end
					end
				end
				if seenTick % 15 == 0 then -- 마지막으로 접속해 있던 시각 (오프라인 적립 계산용, 저장됨)
					local rift = Meta.GetRift(player)
					if rift then rift.IdleSeen = os.time() end
				end
			end
		end
	end)
end

-- 접속했을 때: 자리를 비운 시간만큼(한도까지) 골드를 준다
function Idle.OnJoin(player)
	local rift = Meta.GetRift(player)
	if not rift then return end
	local last = rift.IdleSeen or 0
	rift.IdleSeen = os.time()
	if last <= 0 then return end
	local away = os.time() - last
	if away < 90 or (player:GetAttribute("Level") or 1) < 2 then return end
	local capped = away > capSeconds(player)
	local seconds = math.min(away, capSeconds(player))
	task.delay(3, function() -- 장비 / 훈련 능력치가 다 반영된 뒤에 계산한다
		if not player.Parent then return end
		-- 방치 부스터: 자리를 비운 시간 중 부스터가 켜져 있던 구간만 x2 (접속 순간에 이미 끝났어도 그 구간은 인정한다)
		local baseMult = 1 + (player:GetAttribute("IdleMultBonus") or 0)
		local perSecondBase = Idle.OfflineRate(player) -- 초당 오프라인 골드 (방치 배율 제외)
		local windowEnd = last + seconds
		local boosted = math.max(0, math.min(player:GetAttribute("IdleBoostUntil") or 0, windowEnd) - last)
		local gold = math.floor(perSecondBase * (baseMult * (seconds - boosted) + (baseMult + I.BoostBonus) * boosted))
		if gold < 1 then return end
		player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
		local hours = seconds / 3600
		local text = string.format("%.1f hours of idle gold (%d G) piled up!", hours, gold)
		if boosted > 60 then
			text ..= string.format("\n(Idle Booster applied for %d min)", math.floor(boosted / 60))
		end
		if (player:GetAttribute("IdleMultBonus") or 0) > 0 then
			text ..= string.format("\n(Idle income bonus +%d%% active)", math.floor((player:GetAttribute("IdleMultBonus") or 0) * 100 + 0.5))
		end
		if capped then
			text ..= string.format("\n⚠ The %d-hour cap was reached, so %.1f hours' worth couldn't be saved. You can raise the cap in the Shop", math.floor(capSeconds(player) / 3600), (away - capSeconds(player)) / 3600)
		end
		-- 큰 "돌아오셨어요" 카드는 클라이언트(OfflineRewardClient)가 이 값들을 보고 띄운다 (골드 숫자가 올라가는 연출)
		player:SetAttribute("OfflineRewardGold", gold)
		player:SetAttribute("OfflineRewardSeconds", seconds)
		player:SetAttribute("OfflineRewardCapped", capped)
		player:SetAttribute("OfflineRewardBoost", boosted > 60)
		player:SetAttribute("OfflineRewardTick", (player:GetAttribute("OfflineRewardTick") or 0) + 1)
		Remotes.Notify:FireClient(player, string.format("🌙 Idle reward +%d G", gold))
	end)
end

function Idle.Forget(player)
	remainder[player] = nil
	pending[player] = nil
end

if RunService:IsStudio() then
	-- Studio 확인용 골드 장부: 1분마다 "들어온 골드 / 쓴 골드"와 이론상 방치 수입을 출력한다 (경제 기준표 ECONOMY.md 와 비교해서 계수를 맞출 때 쓴다)
	local ledger = {}
	local function track(player)
		local last = player:GetAttribute("Gold") or 0
		ledger[player] = { In = 0, Out = 0 }
		player:GetAttributeChangedSignal("Gold"):Connect(function()
			local now = player:GetAttribute("Gold") or 0
			local delta = now - last
			last = now
			local entry = ledger[player]
			if not entry then return end
			if delta > 0 then entry.In += delta else entry.Out -= delta end
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in ipairs(Players:GetPlayers()) do track(player) end
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				local entry = ledger[player]
				if entry then
					print(string.format("[Gold ledger] %s · last 1 min income %d G / spent %d G · theoretical idle %d G/min (mult x%.2f) · attack mult x%.2f · next upgrade cost %d G",
						player.Name, entry.In, entry.Out, math.floor(Idle.Rate(player) * 60), Idle.Multiplier(player),
						Config.GetDamageMultiplier(player:GetAttribute("WeaponLevel") or 0), Config.GetEnhanceCost(player:GetAttribute("WeaponLevel") or 0)))
					print(string.format("[Damage parts] %s · weapon x%.1f · level x%.2f · gear x%.2f · training x%.2f · pet x%.2f (all multiplied)", player.Name, -- 무기 비중 점검용
						Config.GetWeaponPower(player:GetAttribute("WeaponLevel") or 0), Config.GetLevelDamageMult(player:GetAttribute("Level") or 1),
						1 + (player:GetAttribute("GearDamage") or 0), 1 + (player:GetAttribute("TrainDamage") or 0), 1 + (player:GetAttribute("PetDamage") or 0)))
					entry.In, entry.Out = 0, 0
				end
			end
		end
	end)
end

return Idle
