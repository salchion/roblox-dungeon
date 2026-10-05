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
--   Dungeon      C->S  ("Ready") ("Leave")
--                S->C  ("State", stateTable) ("Result", resultTable)
--   Notify       S->C  (text)                                  화면 알림

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "Attack", "Upgrade", "Enhance", "OpenEnhance", "Party", "Dungeon", "Notify" }

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in ipairs(NAMES) do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

return setmetatable({}, {
	__index = function(_, name)
		return folder:WaitForChild(name)
	end,
})
