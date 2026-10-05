-- PartyService (ServerScriptService > Modules 안의 ModuleScript, 이름: PartyService)
-- 로비 파티 (최대 4인). 파티장이 초대 -> 상대가 수락하면 결성.
-- 파티 인원이 1명만 남으면 파티는 자동 해산된다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local Party = {}

local parties = {}       -- [id] = { Id, Leader, Members = { player... } }
local playerParty = {}   -- [player] = party
local invites = {}       -- [target] = { [inviter] = 만료 시각 }
local nextId = 1

local function serialize(party)
	local members = {}
	for _, member in ipairs(party.Members) do
		table.insert(members, { UserId = member.UserId, Name = member.DisplayName })
	end
	return { Id = party.Id, Leader = party.Leader.UserId, Members = members }
end

local function broadcast(party)
	local data = serialize(party)
	for _, member in ipairs(party.Members) do
		Remotes.Party:FireClient(member, "State", data)
	end
end

local function clearPlayer(player)
	playerParty[player] = nil
	player:SetAttribute("PartyId", 0)
	if player.Parent then
		Remotes.Party:FireClient(player, "State", nil)
	end
end

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

function Party.GetParty(player)
	return playerParty[player]
end

local function disband(party)
	parties[party.Id] = nil
	for _, member in ipairs(party.Members) do
		clearPlayer(member)
	end
	party.Members = {}
end

local function removeMember(party, player)
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	clearPlayer(player)

	if #party.Members <= 1 then
		disband(party)
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1] -- 파티장이 나가면 다음 사람이 파티장
		notify(party.Leader, "당신이 새 파티장이 되었습니다.")
	end
	broadcast(party)
end

function Party.Invite(inviter, target)
	if not target or target == inviter or target.Parent ~= Players then return end
	if inviter:GetAttribute("Zone") ~= "Lobby" or target:GetAttribute("Zone") ~= "Lobby" then
		notify(inviter, "로비에 있는 플레이어만 초대할 수 있어요.")
		return
	end

	local party = playerParty[inviter]
	if party and party.Leader ~= inviter then
		notify(inviter, "파티장만 초대할 수 있어요.")
		return
	end
	if party and #party.Members >= Config.Party.MaxSize then
		notify(inviter, "파티가 가득 찼어요. (최대 " .. Config.Party.MaxSize .. "명)")
		return
	end
	if playerParty[target] then
		notify(inviter, target.DisplayName .. " 님은 이미 파티에 있어요.")
		return
	end

	invites[target] = invites[target] or {}
	invites[target][inviter] = os.clock() + Config.Party.InviteTimeout
	Remotes.Party:FireClient(target, "Invite", inviter.UserId, inviter.DisplayName)
	notify(inviter, target.DisplayName .. " 님에게 초대를 보냈어요.")
end

function Party.Accept(player, inviterUserId)
	local inviter = Players:GetPlayerByUserId(inviterUserId)
	local pending = invites[player]
	local expire = pending and inviter and pending[inviter]
	if not expire or os.clock() > expire then
		notify(player, "만료되었거나 유효하지 않은 초대예요.")
		return
	end
	pending[inviter] = nil

	if playerParty[player] then return end
	if inviter:GetAttribute("Zone") ~= "Lobby" or player:GetAttribute("Zone") ~= "Lobby" then return end

	local party = playerParty[inviter]
	if party and party.Leader ~= inviter then
		notify(player, "초대한 사람이 더 이상 파티장이 아니에요.")
		return
	end
	if party and #party.Members >= Config.Party.MaxSize then
		notify(player, "파티가 가득 찼어요.")
		return
	end

	if not party then
		party = { Id = nextId, Leader = inviter, Members = { inviter } }
		nextId += 1
		parties[party.Id] = party
		playerParty[inviter] = party
		inviter:SetAttribute("PartyId", party.Id)
	end

	table.insert(party.Members, player)
	playerParty[player] = party
	player:SetAttribute("PartyId", party.Id)
	broadcast(party)
end

function Party.Decline(player, inviterUserId)
	local inviter = Players:GetPlayerByUserId(inviterUserId)
	if inviter and invites[player] then
		invites[player][inviter] = nil
		notify(inviter, player.DisplayName .. " 님이 초대를 거절했어요.")
	end
end

function Party.Leave(player)
	local party = playerParty[player]
	if party then
		removeMember(party, player)
	end
end

function Party.Kick(leader, userId)
	local party = playerParty[leader]
	local target = Players:GetPlayerByUserId(userId)
	if not party or party.Leader ~= leader or not target or target == leader then return end
	if playerParty[target] ~= party then return end
	if target:GetAttribute("Zone") ~= "Lobby" then
		notify(leader, "던전 안에 있는 파티원은 추방할 수 없어요.")
		return
	end
	notify(target, "파티에서 추방되었어요.")
	removeMember(party, target)
end

function Party.OnPlayerRemoving(player)
	invites[player] = nil
	for _, pending in pairs(invites) do
		pending[player] = nil
	end
	Party.Leave(player)
end

Remotes.Party.OnServerEvent:Connect(function(player, action, arg)
	if action == "Invite" and typeof(arg) == "number" then
		Party.Invite(player, Players:GetPlayerByUserId(arg))
	elseif action == "Accept" and typeof(arg) == "number" then
		Party.Accept(player, arg)
	elseif action == "Decline" and typeof(arg) == "number" then
		Party.Decline(player, arg)
	elseif action == "Leave" then
		Party.Leave(player)
	elseif action == "Kick" and typeof(arg) == "number" then
		Party.Kick(player, arg)
	end
end)

return Party
