-- PhotoModeClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: PhotoModeClient)
-- 운영자 전용 사진 모드: 게임 홍보용 스크린샷 / 썸네일을 깔끔하게 찍는다. 내 화면에서만 바뀐다.
--   F7 = 화면 글자만 숨기고 평소처럼 싸운다 (이동 / 사격 / 스킬 그대로, 줌을 더 멀리까지 뺄 수 있다) -> 싸우는 장면을 찍을 때
--   F8 = 자유 카메라: 캐릭터는 멈추고 카메라만 날린다 -> 구도를 잡은 풍경 / 정지 장면을 찍을 때
--        WASD 이동 · Space / X 위아래 · 오른쪽 마우스 누른 채 끌기 = 둘러보기 · Shift 빠르게 · Ctrl 느리게 · 마우스 휠 = 확대 / 축소
--   두 모드 공통: [ / ] = 시간대(아침 ~ 밤) · G = 배경 흐림(심도) · N = 색감 진하게. 같은 키를 다시 누르면 원래대로.
--   (Q / C / F / V / Z / R 은 게임 스킬 키라서 쓰지 않는다)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local uiHidden = false
local freeCam = false
local hidden = {}          -- 숨긴 ScreenGui 들 (다시 켤 때 되돌린다)
local saved = {}           -- 바꾸기 전 카메라 / 조명 / 줌 값
local yaw, pitch = 0, 0
local fov = 70
local rotating = false
local dof, grade
local hint

local function showHint(text)
	if hint and hint.Parent then hint:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PhotoModeHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 600, 0, 92)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 20)
	label.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextWrapped = true
	label.AutoLocalize = false
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	task.delay(3, function() if gui.Parent then gui:Destroy() end end)
	hint = gui
end

------------------------------------------------------------
-- 화면 글자 숨기기 / 되돌리기
------------------------------------------------------------
local function hideUi()
	if uiHidden then return end
	uiHidden = true
	table.clear(hidden)
	for _, gui in ipairs(player.PlayerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "PhotoModeHint" then
			gui.Enabled = false
			table.insert(hidden, gui)
		end
	end
	-- (로블록스 기본 UI 는 하나씩 원래 상태를 기억했다가 그대로 되돌린다: 게임이 일부러 꺼 둔 아이템 칸(Backpack)이 다시 켜지지 않게)
	saved.Core = {}
	for _, coreType in ipairs(Enum.CoreGuiType:GetEnumItems()) do
		if coreType ~= Enum.CoreGuiType.All then
			local okGet, on = pcall(function() return StarterGui:GetCoreGuiEnabled(coreType) end)
			if okGet then saved.Core[coreType] = on end
		end
	end
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	saved.ClockTime = Lighting.ClockTime
	saved.MaxZoom = player.CameraMaxZoomDistance
	player.CameraMaxZoomDistance = math.max(saved.MaxZoom, 160) -- (싸우는 장면도 멀리서 넓게 찍을 수 있게)
end

local function showUi()
	if not uiHidden then return end
	uiHidden = false
	for _, gui in ipairs(hidden) do
		if gui.Parent then gui.Enabled = true end
	end
	table.clear(hidden)
	for coreType, on in pairs(saved.Core or {}) do
		pcall(function() StarterGui:SetCoreGuiEnabled(coreType, on) end)
	end
	if saved.ClockTime then Lighting.ClockTime = saved.ClockTime end
	if saved.MaxZoom then player.CameraMaxZoomDistance = saved.MaxZoom end
	if dof then dof:Destroy() dof = nil end
	if grade then grade:Destroy() grade = nil end
	if hint and hint.Parent then hint:Destroy() end
end

------------------------------------------------------------
-- 자유 카메라 켜기 / 끄기
------------------------------------------------------------
local function camOn()
	if freeCam then return end
	freeCam = true
	saved.CameraType = camera.CameraType
	saved.FieldOfView = camera.FieldOfView
	saved.MouseBehavior = UserInputService.MouseBehavior
	camera.CameraType = Enum.CameraType.Scriptable
	local look = camera.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -1, 1))
	fov = camera.FieldOfView
	-- 캐릭터가 움직이지 않게 (WASD 는 카메라가 쓴다)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		saved.WalkSpeed, saved.JumpPower, saved.JumpHeight = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight
		humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 0, 0, 0
		saved.Humanoid = humanoid
	end
end

local function camOff()
	if not freeCam then return end
	freeCam = false
	camera.CameraType = saved.CameraType or Enum.CameraType.Custom
	camera.FieldOfView = saved.FieldOfView or 70
	UserInputService.MouseBehavior = saved.MouseBehavior or Enum.MouseBehavior.Default
	if saved.Humanoid and saved.Humanoid.Parent then
		saved.Humanoid.WalkSpeed, saved.Humanoid.JumpPower, saved.Humanoid.JumpHeight = saved.WalkSpeed or 16, saved.JumpPower or 50, saved.JumpHeight or 7.2
	end
	saved.Humanoid = nil
	rotating = false
end

local HINT_UI = "📷 사진 모드: 화면 글자만 숨김 (F7 끄기 · F8 자유 카메라)\n평소처럼 싸우세요. 줌을 더 멀리 뺄 수 있어요\n[ ] = 시간대 · G = 배경 흐림 · N = 색감 · 이 안내는 3초 뒤 사라져요"
local HINT_CAM = "🎥 자유 카메라 (F8 끄기 · F7 = 싸우는 모드로)\nWASD 이동 · Space/X 위아래 · 오른쪽 마우스 끌기 = 둘러보기 · Shift 빠르게 · Ctrl 느리게 · 휠 = 확대\n[ ] = 시간대 · G = 배경 흐림 · N = 색감 · 이 안내는 3초 뒤 사라져요"

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.F7 or input.KeyCode == Enum.KeyCode.F8 then
		if not player:GetAttribute("IsAdmin") then return end
		if input.KeyCode == Enum.KeyCode.F7 then
			if freeCam then -- 자유 카메라 -> 싸우는 모드
				camOff()
				showHint(HINT_UI)
			elseif uiHidden then
				showUi()
			else
				hideUi()
				showHint(HINT_UI)
			end
		else
			if freeCam then
				camOff()
				showUi()
			else
				hideUi()
				camOn()
				showHint(HINT_CAM)
			end
		end
		return
	end
	if not uiHidden then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 and freeCam then
		rotating = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	elseif processed then
		return
	elseif input.KeyCode == Enum.KeyCode.LeftBracket then
		Lighting.ClockTime = (Lighting.ClockTime - 1) % 24
	elseif input.KeyCode == Enum.KeyCode.RightBracket then
		Lighting.ClockTime = (Lighting.ClockTime + 1) % 24
	elseif input.KeyCode == Enum.KeyCode.G then -- 배경 흐림: 캐릭터에 초점
		if dof then
			dof:Destroy()
			dof = nil
		else
			dof = Instance.new("DepthOfFieldEffect")
			dof.FarIntensity = 0.6
			dof.NearIntensity = 0.3
			dof.InFocusRadius = 18
			dof.Parent = camera
		end
	elseif input.KeyCode == Enum.KeyCode.N then -- 색감 진하게
		if grade then
			grade:Destroy()
			grade = nil
		else
			grade = Instance.new("ColorCorrectionEffect")
			grade.Saturation = 0.25
			grade.Contrast = 0.12
			grade.Brightness = 0.03
			grade.Parent = camera
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and freeCam then
		rotating = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not freeCam then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement and rotating then
		yaw -= input.Delta.X * 0.004
		pitch = math.clamp(pitch - input.Delta.Y * 0.004, -1.45, 1.45)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		fov = math.clamp(fov - input.Position.Z * 4, 10, 110)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not uiHidden then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if dof then -- 초점은 내 캐릭터까지의 거리
		dof.FocusDistance = root and (root.Position - camera.CFrame.Position).Magnitude or 30
	end
	if not freeCam then return end
	if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end -- (다른 스크립트가 카메라를 되돌려도 자유 카메라 유지)
	local speed = 40
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then speed = 140 end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then speed = 8 end
	local move = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += Vector3.new(0, 0, -1) end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then move += Vector3.new(0, 0, 1) end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then move += Vector3.new(-1, 0, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += Vector3.new(1, 0, 0) end
	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local position = camera.CFrame.Position + rotation:VectorToWorldSpace(move) * speed * dt
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then position += Vector3.new(0, speed * dt, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.X) then position -= Vector3.new(0, speed * dt, 0) end
	camera.CFrame = CFrame.new(position) * rotation
	camera.FieldOfView = fov
end)
