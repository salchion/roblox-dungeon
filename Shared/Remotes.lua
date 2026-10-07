-- Remotes (ReplicatedStorage 안의 ModuleScript, 이름: Remotes)
-- 서버에서 처음 require 하면 RemoteEvent들이 만들어지고, 클라이언트는 만들어질 때까지 기다렸다가 가져온다.
--
--   Attack       C->S  (aimPoint: Vector3)                     공격
--   Upgrade      C->S  (statName: "Crit"|"Speed"|"Health")     스탯 포인트 투자 (던전 안에서만)
--   Enhance      C->S  ()                                      무기 강화 요청
--                S->C  (ok, message)                           강화 결과
--   OpenEnhance  S->C  ()                                      모루(강화대) 사용 -> 강화창 열기
--   Party        C->S  ("Invite", userId) ("Accept", userId) ("Decline", userId) ("Leave") ("Kick", userId)
--                S->C  ("State", partyData|nil) ("Invite", inviterUserId, inviterName)
--   Dungeon      C->S  ("Ready") ("Leave") ("Start", typeKey, difficultyKey)
--                S->C  ("State", stateTable) ("Result", resultTable) ("OpenSelect")
--   Gear         C->S  ("Enhance", slotKey) ("Roll")                    장비 강화 / 티켓 뽑기
--                S->C  ("Result", { Ok, Message, Roll })             결과
--   OpenGear     S->C  ()                                      뽑기 머신 사용 -> 장비창 열기
--   Quest        C->S  ("Request") ("Claim", questId) ("ClaimAch", achievementId) ("Title", titleOrNil)
--                S->C  ("State", { Daily, Achievements, Titles, Equipped, Stats })
--   Rank         C->S  ("Request")   S->C  ("List", { { Name, Power }... })
--   Weapon       C->S  ("Equip", typeKey) ("Buy", typeKey)             무기 종류 장착 / 구매
--   Notify       S->C  (text)                                  화면 알림

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "Attack", "Upgrade", "Enhance", "OpenEnhance", "Party", "Dungeon", "Notify", "Gear", "OpenGear", "Quest", "Rank", "Weapon" }

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		for _, name in ipairs(NAMES) do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("RemoteEvents")
end

return setmetatable({}, {
	__index = function(_, name)
		return folder:WaitForChild(name)
	end,
})
