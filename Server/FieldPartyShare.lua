-- FieldPartyShare (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldPartyShare)
-- 필드에서 파티로 사냥할 때의 나눔 규칙 (FieldService 가 일반 몬스터 / 엘리트를 처치할 때 부른다):
--   * 경험치: 처치한 사람 + 근처(160 스터드)에 살아 있는 파티원이 똑같이 나눠 가진다 (총량은 혼자 잡을 때와 같다).
--   * 전리품: 근처 파티원마다 각자 따로 드랍이 나온다 (개인 전리품: 각자 자기 것만 보이고 자기만 줍는다).
--   * 골드 / 퀘스트 처치 수 / 엘리트 티켓은 막타를 친 사람에게만 간다 (예전 그대로).
--   * 파티가 아니면 예전과 똑같다 (막타 친 사람 혼자). 구역 군주 / 황금 고블린 / 월드 보스는 따로 정해진 방식이라 건드리지 않는다.

local Party = require(script.Parent:WaitForChild("PartyService"))
local Level = require(script.Parent:WaitForChild("LevelService"))
local Loot = require(script.Parent:WaitForChild("LootService"))

local Share = {}

local RANGE = 160

-- 처치한 사람 + 같은 파티의 근처 파티원 (필드에 있고 살아 있는 사람만)
local function nearbyMembers(killer, position)
	local party = Party.GetParty(killer)
	if not party then return { killer } end
	local list = {}
	for _, member in ipairs(party.Members) do
		if member == killer then
			table.insert(list, member)
		elseif member.Parent and member:GetAttribute("Zone") == "Field" then
			local character = member.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and (root.Position - position).Magnitude <= RANGE then
				table.insert(list, member)
			end
		end
	end
	return list
end

function Share.Xp(killer, position, xp)
	local members = nearbyMembers(killer, position)
	local each = xp / #members
	for _, member in ipairs(members) do
		Level.AddXP(member, each)
	end
end

-- 막타를 친 사람의 드랍은 FieldService 가 그대로 처리한다. 여기서는 나머지 근처 파티원의 몫만 굴린다.
function Share.Drops(killer, position, kind, zone)
	for _, member in ipairs(nearbyMembers(killer, position)) do
		if member ~= killer then
			Loot.DropFor(member, position, kind, zone)
		end
	end
end

return Share
