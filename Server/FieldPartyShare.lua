-- FieldPartyShare (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldPartyShare)
-- 필드 일반 몬스터 / 엘리트의 보상 나눔 (FieldService 가 처치할 때 부른다). 막타가 아니라 "준 피해"로 나눈다.
--   * 몬스터는 누가 얼마나 때렸는지 data.Contrib 에 쌓는다. 막타를 친 사람의 피해는 남은 체력까지만 센다 (한 방에 죽여도 부풀려지지 않는다).
--   * 파티가 아닌 사람: 몬스터 체력의 MIN_SHARE(15%) 이상 준 사람만 보상을 받는다. 경험치 / 골드는 준 피해 비율로 나누고, 드랍은 각자 따로 굴린다.
--   * 파티: 파티를 하나로 보고 파티가 준 피해 몫을 파티원이 똑같이 나눈다. 15% 조건 없이 근처(RANGE) 파티원 모두 드랍을 따로 굴린다.
--     파티원이 늘면 경험치 / 골드가 PARTY_BONUS(+15%)씩 늘어난다 (인원수로 나누기 전의 총량).
--   * 아무도 15%를 못 채웠으면 막타를 친 사람(과 그 파티)이 전부 받는다. 구역 군주 / 황금 고블린 / 월드 보스는 따로 정해진 방식이라 건드리지 않는다.
--   * 엘리트 티켓 / 퀘스트 처치 수는 막타를 친 사람 그대로다.

local Party = require(script.Parent:WaitForChild("PartyService"))
local Level = require(script.Parent:WaitForChild("LevelService"))
local Loot = require(script.Parent:WaitForChild("LootService"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local BL = require(script.Parent:WaitForChild("BalanceLog"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Share = {}

local MIN_SHARE = 0.15
local PARTY_BONUS = 0.15
local RANGE = 160

local function inField(player)
	return player.Parent ~= nil and player:GetAttribute("Zone") == "Field"
end

local function alivePosition(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then return root.Position end
	return nil
end

-- 파티원 중 보상을 받을 사람: 피해를 준 사람 + 필드에서 살아 있고 몬스터 근처인 파티원
local function partyMembers(party, contributors, position)
	local set, list = {}, {}
	for member in pairs(contributors) do
		set[member] = true
		table.insert(list, member)
	end
	for _, member in ipairs(party.Members) do
		if not set[member] and inField(member) then
			local at = alivePosition(member)
			if at and (at - position).Magnitude <= RANGE then
				set[member] = true
				table.insert(list, member)
			end
		end
	end
	return list
end

-- 반환: 보상을 받은 사람 목록 (드랍을 굴릴 사람)
function Share.Distribute(killer, data, part, goldBase, xpBase)
	local position = part.Position
	local maxHealth = math.max(1, data.MaxHealth or 1)

	-- 1) 각자의 실제 준 피해 (막타가 아닌 사람 먼저, 막타는 남은 체력까지만)
	local eff, others = {}, 0
	for player, damage in pairs(data.Contrib or {}) do
		if typeof(player) == "Instance" and player ~= killer and inField(player) and damage > 0 then
			local e = math.min(damage, maxHealth)
			eff[player] = e
			others += e
		end
	end
	local killerDamage = (data.Contrib and data.Contrib[killer]) or maxHealth
	local killerEff = math.min(killerDamage, math.max(0, maxHealth - others))
	if killerEff > 0 and inField(killer) then eff[killer] = killerEff end

	-- 2) 파티는 하나의 덩어리로 묶는다
	local groups, order, total = {}, {}, 0
	for player, e in pairs(eff) do
		local party = Party.GetParty(player)
		local key = party or player
		local group = groups[key]
		if not group then
			group = { Party = party, Damage = 0, Contributors = {} }
			groups[key] = group
			table.insert(order, group)
		end
		group.Damage += e
		group.Contributors[player] = true
		total += e
	end

	-- 3) 15% 이상 준 쪽만 (아무도 못 채우면 막타 쪽이 전부)
	local qualified, qualTotal = {}, 0
	for _, group in ipairs(order) do
		if total > 0 and group.Damage / total >= MIN_SHARE then
			table.insert(qualified, group)
			qualTotal += group.Damage
		end
	end
	if #qualified == 0 then
		local party = Party.GetParty(killer)
		qualified = { { Party = party, Damage = 1, Contributors = { [killer] = true } } }
		qualTotal = 1
	end

	-- 4) 보상 (골드는 막타를 친 사람에게 +G 글자)
	local rewarded = {}
	for _, group in ipairs(qualified) do
		local share = group.Damage / qualTotal
		local members
		if group.Party then
			members = partyMembers(group.Party, group.Contributors, position)
		else
			members = {}
			for player in pairs(group.Contributors) do table.insert(members, player) end
		end
		local count = #members
		local bonus = 1 + PARTY_BONUS * (count - 1)
		for _, member in ipairs(members) do
			local goldGain = math.floor(goldBase * share * bonus / count * Config.GoldBonus(member) + 0.5)
			member:SetAttribute("Gold", (member:GetAttribute("Gold") or 0) + goldGain)
			pcall(BL.Gold, member, "Kills", goldGain)
			Level.AddXP(member, xpBase * share * bonus / count)
			if member == killer then
				Effects.FloatText(position + Vector3.new(0, part.Size.Y / 2, 0), string.format("+%d G", goldGain), Color3.fromRGB(255, 220, 90))
			end
			table.insert(rewarded, member)
		end
	end
	return rewarded
end

-- 보상을 받은 사람마다 각자 드랍을 굴린다 (개인 전리품)
function Share.DropFor(members, position, kind, zone)
	for _, member in ipairs(members) do
		Loot.DropFor(member, position, kind, zone)
	end
end

return Share
