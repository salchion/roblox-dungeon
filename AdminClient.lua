-- AdminClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: AdminClient)
-- 운영자 전용 화면 (F6 으로 열고 닫는다). 운영자가 아니면 아무것도 하지 않는다. 진짜 확인은 서버(AdminService)가 한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, makePanel, makeLabel, makeButton = Kit.create, Kit.makePanel, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer

local function start()
	local gui = create("ScreenGui", { Name = "AdminGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 90 }, player:WaitForChild("PlayerGui"))
	local panel = makePanel({
		Size = UDim2.new(0, 620, 0, 420), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.02, Visible = false, ZIndex = 10,
	}, gui)
	makeLabel({ Size = UDim2.new(1, -290, 0, 36), Position = UDim2.new(0, 16, 0, 8), Text = "Admin (F6)", Font = Enum.Font.GothamBlack, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, panel)
	makeButton({ Size = UDim2.new(0, 72, 0, 28), Position = UDim2.new(1, -86, 0, 12), Text = "Close", BackgroundColor3 = Color3.fromRGB(54, 58, 82), ZIndex = 11 }, panel, function()
		panel.Visible = false
	end)
	makeButton({ Size = UDim2.new(0, 170, 0, 28), Position = UDim2.new(1, -266, 0, 12), Text = "Restart my tutorial", TextSize = 12, BackgroundColor3 = Color3.fromRGB(110, 70, 70), ZIndex = 11 }, panel, function()
		Remotes.Admin:FireServer("RestartTutorial")
		panel.Visible = false
	end)
	local scroll = create("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -56), Position = UDim2.new(0, 12, 0, 48), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 11,
	}, panel)
	local body = makeLabel({
		Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextSize = 13, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12, Text = "Loading...",
	}, scroll)

	Remotes.Admin.OnClientEvent:Connect(function(action, data)
		if action ~= "List" then return end
		local lines = { string.format("<b>Server %s · %d player(s)</b>  (only this server is shown)", data.JobId, data.Count) }
		for _, row in ipairs(data.Players) do
			table.insert(lines, string.format("<b>%s</b> (%d) · Lv %d · Power %d · Gold %d · Tickets %d · %s · MaxZone %d",
				row.Name, row.UserId, row.Level, row.Power, row.Gold, row.Tickets, tostring(row.Zone), row.MaxZone))
		end
		body.Text = table.concat(lines, "\n")
	end)

	local function refreshLoop()
		while panel.Visible do
			Remotes.Admin:FireServer("List")
			task.wait(3)
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.F6 then return end
		panel.Visible = not panel.Visible
		if panel.Visible then task.spawn(refreshLoop) end
	end)
end

if player:GetAttribute("IsAdmin") then
	start()
else
	local connection
	connection = player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
		if player:GetAttribute("IsAdmin") then
			connection:Disconnect()
			start()
		end
	end)
end
