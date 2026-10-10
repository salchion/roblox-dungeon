-- RestPoseClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: RestPoseClient)
-- 휴식 구역(IdleActive)에서 가만히 서 있으면 캐릭터가 자리에 앉아 쉬고(머리 위에 💤), 움직이거나 점프하면 일어난다.
-- 서버는 IdleActive Attribute 만 알려 주고, 앉는 동작은 내 화면(내 캐릭터)에서만 처리한다 (Humanoid.Sit 은 모두에게 복제된다).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local STILL_SECONDS = 2.2 -- 이 시간 동안 가만히 있으면 앉는다

local stillFor = 0
local sitting = false
local bubble

local function removeBubble()
	if bubble then
		bubble:Destroy()
		bubble = nil
	end
end

local function addBubble(head)
	removeBubble()
	local gui = Instance.new("BillboardGui")
	gui.Name = "RestZzz"
	gui.Size = UDim2.new(0, 70, 0, 40)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 60
	gui.Adornee = head
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(190, 215, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = "💤"
	label.Parent = gui
	-- 천천히 위아래로 둥실
	TweenService:Create(gui, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { StudsOffset = Vector3.new(0, 3.8, 0) }):Play()
	bubble = gui
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.15 then return end
	local step = acc
	acc = 0
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not humanoid or not head or humanoid.Health <= 0 then
		stillFor, sitting = 0, false
		removeBubble()
		return
	end
	local resting = player:GetAttribute("IdleActive") == true and player:GetAttribute("Zone") == "Lobby"
	if not resting then
		if sitting then
			humanoid.Sit = false
			sitting = false
			removeBubble()
		end
		stillFor = 0
		return
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	if sitting then
		-- 앉아 있다가 걸으려 하면 (또는 점프로 이미 일어났으면) 일어난다
		if moving or not humanoid.Sit then
			humanoid.Sit = false
			sitting = false
			stillFor = 0
			removeBubble()
		end
		return
	end
	if moving or humanoid.Jump then
		stillFor = 0
		return
	end
	stillFor += step
	if stillFor >= STILL_SECONDS and humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid.Sit = true
		sitting = true
		addBubble(head)
	end
end)
