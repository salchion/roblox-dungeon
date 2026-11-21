-- CharacterMotionClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: CharacterMotionClient)
-- 내 캐릭터의 몸놀림: 달리는 방향으로 기울고, 맞힐 때 반동으로 살짝 젖혀지고, 대시 때 숙이고, 착지하면 낮아졌다 올라온다.
-- 허리 관절(Waist, R6 는 RootJoint)의 Transform 에 작은 회전만 준다 (C0 는 읽기 전용이라 쓰면 오류가 났다) (애니메이션 / 부품은 건드리지 않아서 부담이 없다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local AimShare = require(script.Parent:WaitForChild("AimShare"))
local player = Players.LocalPlayer

-- 이동 중 사격: 몸은 이동 방향(AutoRotate), 상체만 조준점 쪽으로 돈다. 마지막 사격 뒤 AIM_HOLD 초가 지나면 0 으로 돌아온다
--   R15: Waist(상체만) ±70° / R6: RootJoint 가 다리까지 돌려서 ±35° 로 작게 (어색하면 스트레이프 방식으로 바꿀 후보)
local AIM_HOLD = 0.6
local isR6, rigLogged = false, false
local yaw = 0

local joint, humanoid, root
local pitch, roll = 0, 0 -- 지금 적용 중인 기울임 (부드럽게 따라간다)
local recoil, landing, dashUntil = 0, 0, 0

local function release()
	if joint and joint.Parent then pcall(function() joint.Transform = CFrame.identity end) end
	joint, humanoid, root = nil, nil, nil
	pitch, roll, recoil, landing, dashUntil = 0, 0, 0, 0, 0
	yaw = 0
end

local function bind(character)
	release()
	humanoid = character:WaitForChild("Humanoid", 10)
	root = character:WaitForChild("HumanoidRootPart", 10)
	local upper = character:WaitForChild("UpperTorso", 3)
	joint = upper and upper:FindFirstChild("Waist")
	isR6 = joint == nil
	if not joint then
		joint = root and root:FindFirstChild("RootJoint") -- R6
		if not joint then
			local torso = character:FindFirstChild("Torso")
			joint = torso and torso:FindFirstChild("RootJoint")
		end
	end
	if not (humanoid and root and joint and joint:IsA("Motor6D")) then
		release()
		return
	end
	if RunService:IsStudio() and not rigLogged then
		rigLogged = true
		print("[Rig] " .. (isR6 and "R6" or "R15") .. " · 이동 중 사격 상체 회전 ±" .. (isR6 and "35" or "70") .. "°")
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
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Seated then return end
	-- 조준 회전 (정지 중에는 PlayerClient.fireAt 이 몸 전체를 돌리므로 여기 각도는 거의 0 이 된다)
	local targetYaw = 0
	local point = AimShare.Point
	if point and os.clock() - AimShare.At < AIM_HOLD and os.clock() >= dashUntil
		and state ~= Enum.HumanoidStateType.PlatformStanding and state ~= Enum.HumanoidStateType.Physics then
		local rel = root.CFrame:VectorToObjectSpace(Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z))
		if rel.Magnitude > 1 then
			local limit = math.rad(isR6 and 35 or 70)
			targetYaw = math.clamp(math.atan2(-rel.X, -rel.Z), -limit, limit)
		end
	end
	yaw += (targetYaw - yaw) * math.min(1, dt * 14)
	-- Transform 은 C0 좌표 기준이라, 몸의 위쪽 축을 C0 좌표로 옮겨 그 축으로 돌린다 (R15 Waist / R6 RootJoint 같은 식)
	--   오른손 법칙: 위쪽 축으로 + 회전 = 앞(-Z)이 왼쪽으로. 오른쪽 조준이면 atan2(-x, -z) < 0 이라 오른쪽으로 돈다
	local upLocal = joint.C0:VectorToObjectSpace(Vector3.new(0, 1, 0))
	local turn = CFrame.fromAxisAngle(upLocal, yaw)
	local ok = pcall(function() joint.Transform = CFrame.Angles(pitch, 0, roll) * turn end)
	if not ok then joint = nil end -- 쓸 수 없는 관절이면 한 번만 실패하고 멈춘다 (출력창에 오류가 반복되지 않게)
end)

player.CharacterAdded:Connect(bind)
if player.Character then task.spawn(bind, player.Character) end
