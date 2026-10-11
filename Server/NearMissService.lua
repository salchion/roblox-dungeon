-- NearMissService (ServerScriptService > Modules 안의 ModuleScript, 이름: NearMissService)
-- 아슬아슬한 회피(NEAR MISS)를 필드 / 던전이 같이 쓰는 한 곳.
--   * 스택(최대 Config.NearMiss.MaxStacks): 한 번 피할 때마다 +1, 스택마다 공격력 +DamagePerStack
--   * 끊겨도 한 번에 0이 되지 않는다: 마지막으로 피한 뒤 Duration 초가 지나면 DecayStep 초마다 스택이 1개씩 줄어든다.
--     "기운 집중" 스킬 레벨이 높을수록 줄어들다 멈추는 바닥(최대 레벨에서 최대 스택의 절반)이 생긴다.
--   * 투사체만이 아니라 돌진 / 폭발 / 메테오 / 충격파 / 레이저 / 경고 원을 아슬아슬하게 피해도 인정한다 (몬스터 종류와 상관없이 기회가 생긴다)
-- 속성: NearMissStacks / NearMissStreak(공격력 계산이 읽음) / NearMissUntil / NearMissEnd / NearMissLen (클라이언트 오라 / 막대)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Meta = require(script.Parent:WaitForChild("MetaService"))

local NearMiss = {}

local states = setmetatable({}, { __mode = "k" }) -- [player] = { Stacks, LastAt, NextDecay }
local dashSeenAt = setmetatable({}, { __mode = "k" })

-- 대시 중이거나 방금(0.6초 안에) 대시했으면 인정한다 (후한 판정). 속도는 0.1초마다 따로 훑어서 기록한다.
local function sampleDash(player, root)
	local v = root.AssemblyLinearVelocity
	if Vector3.new(v.X, 0, v.Z).Magnitude > 50 then
		dashSeenAt[player] = os.clock()
	end
end

function NearMiss.IsDashing(player, root)
	if root then sampleDash(player, root) end
	return os.clock() - (dashSeenAt[player] or -10) < 0.6
end

local function apply(player, st)
	local now = os.clock()
	local active = st.Stacks > 0
	player:SetAttribute("NearMissStacks", st.Stacks)
	player:SetAttribute("NearMissStreak", st.Stacks)
	player:SetAttribute("NearMissUntil", active and now + 3600 or 0) -- 스택이 있는 동안은 보너스가 계속 적용된다 (줄어드는 건 아래 반복이 맡는다)
	local len = Config.GetNearMissDuration(player)
	player:SetAttribute("NearMissLen", len)
	player:SetAttribute("NearMissEnd", active and (workspace:GetServerTimeNow() + math.max(0, st.NextDecay - now)) or 0)
end

-- 피한 것으로 인정: root 의 주인에게 스택 +1. scoreFn(스택) 은 심연 점수 같은 추가 보상용 (선택)
function NearMiss.Award(player, root, scoreFn)
	if not player or not player.Parent or not root then return end
	local now = os.clock()
	local st = states[player]
	if not st then st = { Stacks = 0, LastAt = 0, NextDecay = 0 } states[player] = st end
	if now - st.LastAt < 0.7 then return end -- 한 번에 여러 번 인정되지 않게
	st.LastAt = now
	st.Stacks = math.min(Config.NearMiss.MaxStacks, st.Stacks + 1)
	st.NextDecay = now + Config.GetNearMissDuration(player)
	apply(player, st)
	player:SetAttribute("UltCharge", math.min(Config.Skills.Ult.Cost, (player:GetAttribute("UltCharge") or 0) + 10 + math.min(st.Stacks, 4) * 3))
	if scoreFn then scoreFn(st.Stacks) end
	local rift = Meta.GetRift(player) -- 처음 한 번만 NEAR MISS 설명 카드를 띄운다 (저장됨)
	local firstTime = rift ~= nil and not rift.Tip
	if rift then rift.Tip = true end
	Effects.FloatText(root.Position + Vector3.new(0, 4, 0), st.Stacks > 1 and string.format("NEAR MISS! x%d", st.Stacks) or "NEAR MISS!", Color3.fromRGB(120, 255, 255))
	Remotes.Banner:FireClient(player, "NearMiss", { Streak = st.Stacks, First = firstTime })
end

-- 캐릭터 몸(root)만 아는 곳(몬스터 AI)에서 부르는 입구. 대시 중일 때만 인정한다.
function NearMiss.AwardRoot(root, scoreFn)
	local player = root and root.Parent and Players:GetPlayerFromCharacter(root.Parent)
	if player and NearMiss.IsDashing(player, root) then
		NearMiss.Award(player, root, scoreFn)
	end
end

function NearMiss.Clear(player)
	local st = states[player]
	if st then st.Stacks = 0 apply(player, st) end
end

-- 줄어듦: 마지막 회피 뒤 Duration 이 지나면 DecayStep 초마다 1개씩 (바닥 아래로는 내려가지 않는다)
task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then sampleDash(player, root) end
			local st = states[player]
			if st and st.Stacks > 0 then
				local zone = player:GetAttribute("Zone")
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if zone == "Lobby" or (humanoid and humanoid.Health <= 0) then
					st.Stacks = 0
					apply(player, st)
				elseif now >= st.NextDecay then
					local floor = Config.GetNearMissFloor(player)
					if st.Stacks > floor then
						st.Stacks -= 1
						st.NextDecay = now + Config.NearMiss.DecayStep
					else
						st.NextDecay = now + Config.NearMiss.DecayStep
					end
					apply(player, st)
				else
					player:SetAttribute("NearMissEnd", workspace:GetServerTimeNow() + (st.NextDecay - now))
				end
			end
		end
	end
end)

return NearMiss
