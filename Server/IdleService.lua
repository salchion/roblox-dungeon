-- IdleService (ServerScriptService > Modules 안의 ModuleScript, 이름: IdleService)
-- 방치 수입: 허수아비 훈련장 원 안에 서 있으면 자동으로 쏘며 골드가 쌓이고(접속 중), 접속을 끊어도 일정 시간까지 쌓인다(오프라인 적립).
--   방치 골드/초 = Config.Idle.GoldPerDamage x 무기 초당 피해량(기대값) x 방치 배율
--   방치 배율 = 1 + 영구 보너스(IdleMultBonus: 상품 단계 + VIP) + 부스터 활성 시 BoostBonus
--   오프라인 적립 한도 = BaseCapHours + 상품(IdleCapHours) , 효율 = OfflineEfficiency
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
local Dungeon = require(script.Parent:WaitForChild("DungeonService"))

local I = Config.Idle
local Idle = {}

local dummyCenter = nil
local remainder = {}   -- [player] = 아직 지급하지 못한 소수점 골드
local pending = {}     -- [player] = { Gold, Since } 3초 모아서 한 번에 글자로 보여준다

-- 방치 배율 (영구 + VIP + 부스터)
function Idle.Multiplier(player)
	local mult = 1 + (player:GetAttribute("IdleMultBonus") or 0)
	if (player:GetAttribute("IdleBoostUntil") or 0) > os.time() then
		mult += I.BoostBonus
	end
	return mult
end

-- 무기 초당 피해량(기대값): 한 발 기대 피해 x 탄 수(산탄 / 화염은 60%) / 공격 간격
local function damagePerSecond(player)
	local weaponType = Config.GetPlayerWeapon(player)
	local pellets = weaponType.Pellets > 1 and weaponType.Pellets * 0.6 or 1
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	local cooldown = Config.Player.BaseCooldown * weaponType.Cooldown / (1 + speedPoints * Config.Player.SpeedPerPoint)
	return Dungeon.ExpectedShotDamage(player) * pellets / math.max(0.05, cooldown)
end

-- 초당 방치 골드 (배율 포함)
function Idle.Rate(player)
	return I.GoldPerDamage * damagePerSecond(player) * Idle.Multiplier(player)
end

local function capSeconds(player)
	return ((I.BaseCapHours or 2) + (player:GetAttribute("IdleCapBonusHours") or 0)) * 3600
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
				if isActive then
					local owed = (remainder[player] or 0) + rate
					local gold = math.floor(owed)
					remainder[player] = owed - gold
					if gold > 0 then
						player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
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
		local gold = math.floor(seconds * Idle.Rate(player) * I.OfflineEfficiency)
		if gold < 1 then return end
		player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
		local hours = seconds / 3600
		local text = string.format("%.1f시간 동안 방치 골드 %d G가 쌓였어요!", hours, gold)
		if capped then
			text ..= string.format("\n(최대 %d시간까지 쌓여요. 한도는 상점에서 늘릴 수 있어요)", math.floor(capSeconds(player) / 3600))
		end
		Remotes.Tutorial:FireClient(player, "Prompt", { Key = "🌙", Title = "자리를 비운 동안…", Text = text, Duration = 8 })
		Remotes.Notify:FireClient(player, string.format("🌙 방치 보상 +%d G", gold))
	end)
end

function Idle.Forget(player)
	remainder[player] = nil
	pending[player] = nil
end

if RunService:IsStudio() then
	-- Studio 확인용: 1분마다 현재 방치 수입을 출력 (골드 밸런스를 맞출 때 쓴다)
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				print(string.format("[방치] %s 초당 %.1f G (분당 %d G) · 배율 x%.2f · 무기 단계 %d", player.Name, Idle.Rate(player), math.floor(Idle.Rate(player) * 60), Idle.Multiplier(player), player:GetAttribute("WeaponLevel") or 0))
			end
		end
	end)
end

return Idle
