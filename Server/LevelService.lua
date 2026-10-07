-- LevelService (ServerScriptService > Modules 안의 ModuleScript, 이름: LevelService)
-- 캐릭터 레벨 / 경험치(XP).
--   * 몬스터를 잡거나 던전 웨이브를 깨면 Level.AddXP(player, amount)
--   * 레벨이 오르면: 최대 체력 + 공격력 증가(다른 서비스가 Level Attribute 를 읽어 반영), 체력 완전 회복, 축하 연출
--   * 플레이어 Attribute: Level, XP(현재 경험치), XPNeeded(다음 레벨까지 필요한 양)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local Level = {}

local function setLevel(player, level, xp)
	player:SetAttribute("XP", xp)
	player:SetAttribute("XPNeeded", Config.GetXpNeeded(level))
	player:SetAttribute("Level", level)
end

function Level.Load(player, level, xp)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, Config.Level.Max)
	xp = math.max(0, math.floor(tonumber(xp) or 0))
	if level >= Config.Level.Max then
		xp = 0
	end
	setLevel(player, level, xp)
end

-- 경험치 배율: 장비 옵션(경험치 획득) + VIP 보너스, 경험치 부스터가 켜져 있으면 x2
local function xpMultiplier(player)
	local mult = 1 + (player:GetAttribute("GearXp") or 0)
	if player:GetAttribute("Vip") then
		mult += Config.Shop.Vip.XpBonus
	end
	if (player:GetAttribute("XpBoostUntil") or 0) > os.time() then
		mult *= Config.Shop.XpBoostMult
	end
	return mult
end

function Level.AddXP(player, amount)
	amount = math.floor(amount * xpMultiplier(player) + 0.5)
	if amount <= 0 then return end

	local level = player:GetAttribute("Level") or 1
	if level >= Config.Level.Max then return end
	local xp = (player:GetAttribute("XP") or 0) + amount

	-- 돌파가 필요한 레벨(Config.Growth.Gates)에서는 더 오르지 못하고 경험치 막대만 가득 찬 채 기다린다
	local cap = Config.GetLevelCap(player:GetAttribute("GatePassed") or 0)

	local gained = 0
	while level < cap and xp >= Config.GetXpNeeded(level) do
		xp -= Config.GetXpNeeded(level)
		level += 1
		gained += 1
	end
	if level >= Config.Level.Max then
		xp = 0
	elseif level >= cap then
		xp = math.min(xp, Config.GetXpNeeded(level))
		if not player:GetAttribute("GateBlocked") then
			player:SetAttribute("GateBlocked", true)
			Remotes.Notify:FireClient(player, string.format("🚧 레벨 %d 에서 막혔어요! 메뉴(I) → 성장 탭에서 돌파를 진행하세요.", level))
		end
	end
	if gained > 0 then
		player:SetAttribute("GateBlocked", false)
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		Effects.FloatText(root.Position + Vector3.new(0, 5, 0), string.format("+%d XP", amount), Color3.fromRGB(130, 220, 255))
	end

	setLevel(player, level, xp)

	if gained > 0 then
		Remotes.Notify:FireClient(player, string.format("🎉 레벨 업! Lv.%d  (최대 체력 +%d, 공격력 +%d%%)",
			level, Config.Level.HealthPerLevel * gained, math.floor(Config.Level.DamagePerLevel * 100 * gained + 0.5)))
		if root then
			Effects.Burst(root.Position, Color3.fromRGB(255, 225, 110), 60)
		end
	end
end

return Level
