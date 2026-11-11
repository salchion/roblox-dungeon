-- BountyClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: BountyClient)
-- 필드 현상금(엘리트 무리)이 내 구역에 떠 있는 동안: 화면 위쪽(월드 보스 표시 아래)에 작은 줄 하나
--   "🎯 Bounty · 2 left · 120m ↗ · 1:42"  (방향 화살표는 카메라 기준으로 그쪽을 가리킨다)
-- 값은 서버(FieldService)가 내 Attribute 로 알려 준다: BountyEnd(서버 시각) / BountyLeft / BountyPos(Vector3)

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "BountyGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 330, 0, 30)
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 152)
panel.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 205, 90)
stroke.Thickness = 1.5
stroke.Transparency = 0.2
stroke.Parent = panel

local text = Instance.new("TextLabel")
text.Size = UDim2.new(1, -16, 1, 0)
text.Position = UDim2.new(0, 8, 0, 0)
text.BackgroundTransparency = 1
text.Font = Enum.Font.GothamBold
text.TextSize = 14
text.TextColor3 = Color3.fromRGB(255, 226, 150)
text.RichText = true
text.Parent = panel

local ARROWS = { "→", "↘", "↓", "↙", "←", "↖", "↑", "↗" }

task.spawn(function()
	while true do
		local endAt = player:GetAttribute("BountyEnd")
		local left = player:GetAttribute("BountyLeft")
		local pos = player:GetAttribute("BountyPos")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if type(endAt) == "number" and type(left) == "number" and typeof(pos) == "Vector3" and root and not player:GetAttribute("ModalOpen") then
			gui.Enabled = true
			local seconds = math.ceil(math.max(0, endAt - workspace:GetServerTimeNow()))
			local flat = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
			local dist = flat.Magnitude
			local arrow = ""
			local camera = workspace.CurrentCamera
			if camera and dist > 12 then -- 화면 기준 방향: 카메라 앞 = ↑
				local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
				if look.Magnitude > 0.01 then
					look = look.Unit
					local right = Vector3.new(-look.Z, 0, look.X)
					local angle = math.atan2(flat.Unit:Dot(look), flat.Unit:Dot(right)) -- 0 = 오른쪽, pi/2 = 앞
					local index = math.floor(((-angle) % (2 * math.pi)) / (math.pi / 4) + 0.5) % 8 + 1
					arrow = " " .. ARROWS[index]
				end
			end
			text.Text = string.format("🎯 Bounty · %d left · %dm%s · %d:%02d", left, math.floor(dist), arrow, seconds // 60, seconds % 60)
		else
			gui.Enabled = false
		end
		task.wait(0.2)
	end
end)
