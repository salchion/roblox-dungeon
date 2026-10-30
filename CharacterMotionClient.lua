-- CharacterMotionClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: CharacterMotionClient)
-- 내 캐릭터의 몸놀림: 달리는 방향으로 기울고, 맞힐 때 반동으로 살짝 젖혀지고, 대시 때 숙이고, 착지하면 낮아졌다 올라온다.
-- 허리 관절(Waist, R6 는 RootJoint)의 C0 에 작은 회전만 곱한다 (애니메이션 / 부품은 건드리지 않아서 부담이 없다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local player = Players.LocalPlayer

local joint, baseC0, humanoid, root
local pitch, roll = 0, 0 -- 지금 적용 중인 기울임 (부드럽게 따라간다)
local recoil, landing, dashUntil = 0, 0, 0

local function release()
	if joint and joint.Parent and baseC0 then joint.C0 = baseC0 end
	joint, baseC0, humanoid, root = nil, nil, nil, nil
	pitch, roll, recoil, landing, dashUntil = 0, 0, 0, 0, 0
end

local function bind(character)
	release()
	humanoid = character:WaitForChild("Humanoid", 10)
	root = character:WaitForChild("HumanoidRootPart", 10)
	local upper = character:WaitForChild("UpperTorso", 3)
	joint = upper and upper:FindFirstChild("Waist")
	if not joint then
		joint = root and root:FindFirstChild("RootJoint") -- R6
		if not joint then
			local torso = character:FindFirstChild("Torso")
			joint = torso and torso:FindFirstChild("RootJoint")
		end
	end
	baseC0 = joint and joint.C0
	if not (humanoid and root and joint) then
		release()
		return
	end
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then landing = 0.35 end
	end)
	root.ChildAdded:Connect(function(child)
		if child:IsA("LinearVelocity") then dashUntil = os.clock() + 0.28 end -- 대시는 이 속도 장치로 구현돼 있다
	end)
end

Remotes.Hit.OnClientEvent:Connect(function(isCrit, killed)
	recoil = math.max(recoil, killed and 0.2 or (isCrit and 0.15 or 0.08))
end)

RunService.RenderStepped:Connect(function(dt)
	if not joint or not joint.Parent or not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local forward = velocity:Dot(root.CFrame.LookVector)
	local side = velocity:Dot(root.CFrame.RightVector)
	-- X 회전: 음수 = 앞으로 숙임 / 양수 = 뒤로 젖힘, Z 회전: 음수 = 오른쪽으로 기움
	local targetPitch = -math.clamp(forward / 16, -0.6, 1.2) * 0.14
	local targetRoll = -math.clamp(side / 16, -1, 1) * 0.12
	if os.clock() < dashUntil then targetPitch = -0.5 end
	targetPitch += recoil - landing
	recoil = math.max(0, recoil - dt * 0.7)
	landing = math.max(0, landing - dt * 1.4)
	local k = math.min(1, dt * 12)
	pitch += (targetPitch - pitch) * k
	roll += (targetRoll - roll) * k
	if humanoid:GetState() == Enum.HumanoidStateType.Seated then return end
	joint.C0 = baseC0 * CFrame.Angles(pitch, 0, roll)
end)

player.CharacterAdded:Connect(bind)
if player.Character then task.spawn(bind, player.Character) end
