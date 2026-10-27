-- AdminClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: AdminClient)
-- 운영자 전용 화면 (F6 으로 열고 닫는다). 운영자가 아니면 아무것도 하지 않는다. 진짜 확인은 서버(AdminService)가 한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makePanel, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makePanel, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer

local function start()
	local gui = create("ScreenGui", { Name = "AdminGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 90 }, player:WaitForChild("PlayerGui"))
	local panel = makePanel({
		Size = UDim2.new(0, 640, 0, 708), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.02, Visible = false, ZIndex = 10,
	}, gui)
	local function text(props) props.ZIndex = 11 props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left return makeLabel(props, panel) end
	local function button(props, onClick) props.ZIndex = 11 return makeButton(props, panel, onClick) end
	local function box(props)
		props.ZIndex = 11
		props.BackgroundColor3 = Color3.fromRGB(38, 42, 64)
		props.TextColor3 = Color3.fromRGB(240, 242, 250)
		props.PlaceholderColor3 = Color3.fromRGB(140, 146, 175)
		props.Font = Enum.Font.GothamMedium
		props.TextSize = 14
		props.ClearTextOnFocus = false
		props.BorderSizePixel = 0
		local b = create("TextBox", props, panel)
		rounded(b, 6)
		return b
	end

	text({ Size = UDim2.new(0, 110, 0, 36), Position = UDim2.new(0, 16, 0, 8), Text = "Admin (F6)", Font = Enum.Font.GothamBlack, TextSize = 20 })
	button({ Size = UDim2.new(0, 200, 0, 28), Position = UDim2.new(0, 130, 0, 12), Text = "⭐ Max out my account (test)", TextSize = 12, BackgroundColor3 = Color3.fromRGB(58, 130, 90) }, function()
		Remotes.Admin:FireServer("MaxOut")
		panel.Visible = false
	end)
	button({ Size = UDim2.new(0, 170, 0, 28), Position = UDim2.new(1, -266, 0, 12), Text = "Restart my tutorial", TextSize = 12, BackgroundColor3 = Color3.fromRGB(110, 70, 70) }, function()
		Remotes.Admin:FireServer("RestartTutorial")
		panel.Visible = false
	end)
	button({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), TextSize = 12, Text = "Close", BackgroundColor3 = Color3.fromRGB(54, 58, 82) }, function()
		panel.Visible = false
	end)

	-- 1) 이 서버의 유저 목록
	local scroll = create("ScrollingFrame", {
		Size = UDim2.new(1, -24, 0, 150), Position = UDim2.new(0, 12, 0, 48), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 11,
	}, panel)
	local body = makeLabel({
		Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextSize = 13, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12, Text = "Loading...",
	}, scroll)

	-- 2) 지급: 대상(이 서버의 유저)을 ◀ ▶ 로 고르고, 수량을 적고, 종류 버튼을 누른다
	local targets, targetIndex = {}, 1
	text({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 208), Text = "<b>Give</b>  (players in this server only)", RichText = true, TextSize = 14, TextColor3 = Color3.fromRGB(255, 225, 130) })
	local targetLabel = text({ Size = UDim2.new(0, 300, 0, 32), Position = UDim2.new(0, 60, 0, 236), Text = "-", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center })
	local function showTarget()
		local row = targets[targetIndex]
		targetLabel.Text = row and string.format("%s  (Lv %d)", row.Name, row.Level) or "-"
	end
	button({ Size = UDim2.new(0, 38, 0, 32), Position = UDim2.new(0, 16, 0, 236), Text = "◀", TextSize = 14 }, function()
		if #targets == 0 then return end
		targetIndex = (targetIndex - 2) % #targets + 1
		showTarget()
	end)
	button({ Size = UDim2.new(0, 38, 0, 32), Position = UDim2.new(0, 366, 0, 236), Text = "▶", TextSize = 14 }, function()
		if #targets == 0 then return end
		targetIndex = targetIndex % #targets + 1
		showTarget()
	end)
	local amountBox = box({ Size = UDim2.new(0, 110, 0, 32), Position = UDim2.new(0, 416, 0, 236), PlaceholderText = "Amount", Text = "100" })
	local function giveButton(label, kind, x)
		button({ Size = UDim2.new(0, 120, 0, 34), Position = UDim2.new(0, x, 0, 278), Text = label, TextSize = 13, BackgroundColor3 = Color3.fromRGB(58, 130, 90) }, function()
			local row = targets[targetIndex]
			local amount = tonumber(amountBox.Text)
			if not row or not amount or amount < 1 then return end
			Remotes.Admin:FireServer("Grant", row.UserId, kind, amount)
		end)
	end
	giveButton("+ Gold", "Gold", 16)
	giveButton("+ Tickets", "Tickets", 146)
	giveButton("+ Keys", "Keys", 276)
	text({ Size = UDim2.new(0, 230, 0, 34), Position = UDim2.new(0, 406, 0, 278), Text = "max: Gold 1B · Tickets 10,000 · Keys 30", TextSize = 12, TextColor3 = Color3.fromRGB(160, 166, 195) })

	-- 3) 서버 공지
	text({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 332), Text = "<b>Announce</b>  (shown to everyone in this server)", RichText = true, TextSize = 14, TextColor3 = Color3.fromRGB(255, 225, 130) })
	local announceBox = box({ Size = UDim2.new(1, -150, 0, 34), Position = UDim2.new(0, 16, 0, 360), PlaceholderText = "e.g. Maintenance in 5 minutes", Text = "" })
	button({ Size = UDim2.new(0, 110, 0, 34), Position = UDim2.new(1, -126, 0, 360), Text = "Send", TextSize = 14, BackgroundColor3 = Color3.fromRGB(62, 96, 196) }, function()
		if announceBox.Text == "" then return end
		Remotes.Admin:FireServer("Announce", announceBox.Text)
		announceBox.Text = ""
	end)

	-- 4) 내 저장 초기화 (두 단계)
	text({ Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 0, 420), Text = "<b>Danger</b>", RichText = true, TextSize = 14, TextColor3 = Color3.fromRGB(255, 130, 130) })
	local resetNote = text({ Size = UDim2.new(1, -32, 0, 36), Position = UDim2.new(0, 16, 0, 446), Text = "Reset my save wipes YOUR level, gear and gold completely and kicks you. You start the tutorial again on rejoin.", TextSize = 12, TextColor3 = Color3.fromRGB(190, 195, 220) })
	local resetButton = button({ Size = UDim2.new(0, 210, 0, 36), Position = UDim2.new(0, 16, 0, 490), Text = "Reset my save...", TextSize = 13, BackgroundColor3 = Color3.fromRGB(150, 60, 60) }, function()
		Remotes.Admin:FireServer("ResetArm")
	end)
	local confirmButton = button({ Size = UDim2.new(0, 260, 0, 36), Position = UDim2.new(0, 236, 0, 490), Text = "⚠ Yes, wipe my save now", TextSize = 13, BackgroundColor3 = Color3.fromRGB(200, 40, 40), Visible = false }, function()
		Remotes.Admin:FireServer("ResetConfirm")
	end)
	local cancelButton
	cancelButton = button({ Size = UDim2.new(0, 110, 0, 36), Position = UDim2.new(0, 506, 0, 490), Text = "Cancel", TextSize = 13, BackgroundColor3 = Color3.fromRGB(54, 58, 82), Visible = false }, function()
		confirmButton.Visible, cancelButton.Visible = false, false
		resetNote.Text = "Cancelled."
	end)

	-- 4-2) 다른 사람(위 Give 에서 고른 유저)의 저장 초기화: 친구와 처음부터 테스트할 때. 두 단계 + 대상 확인
	local otherTarget = nil
	local otherConfirm, otherCancel
	local function otherReset()
		otherConfirm.Visible, otherCancel.Visible = false, false
		otherTarget = nil
	end
	button({ Size = UDim2.new(0, 230, 0, 36), Position = UDim2.new(0, 16, 0, 536), Text = "Reset selected player's save...", TextSize = 13, BackgroundColor3 = Color3.fromRGB(150, 60, 60) }, function()
		local row = targets[targetIndex]
		if not row then return end
		otherTarget = row
		Remotes.Admin:FireServer("ResetOtherArm", row.UserId)
		otherConfirm.Text = "⚠ Wipe " .. row.Name .. " now"
		otherConfirm.Visible, otherCancel.Visible = true, true
		task.delay(30, function()
			if otherTarget == row then otherReset() end
		end)
	end)
	otherConfirm = button({ Size = UDim2.new(0, 260, 0, 36), Position = UDim2.new(0, 252, 0, 536), Text = "", TextSize = 13, BackgroundColor3 = Color3.fromRGB(200, 40, 40), Visible = false }, function()
		if otherTarget then Remotes.Admin:FireServer("ResetOtherConfirm", otherTarget.UserId) end
		otherReset()
	end)
	otherCancel = button({ Size = UDim2.new(0, 100, 0, 36), Position = UDim2.new(0, 522, 0, 536), Text = "Cancel", TextSize = 13, BackgroundColor3 = Color3.fromRGB(54, 58, 82), Visible = false }, otherReset)

	-- 4-3) 접속하지 않은 유저(UserId)의 저장 초기화: 두 단계. 지금 다른 서버에서 접속 중이면 지워지지 않는다고 알려 준다.
	local userBox = box({ Size = UDim2.new(0, 190, 0, 34), Position = UDim2.new(0, 16, 0, 580), PlaceholderText = "UserId (offline too)", Text = "" })
	local userArmed = nil
	local userConfirm, userCancel
	local function userDisarm()
		userConfirm.Visible, userCancel.Visible = false, false
		userArmed = nil
	end
	button({ Size = UDim2.new(0, 190, 0, 34), Position = UDim2.new(0, 214, 0, 580), Text = "Reset by UserId...", TextSize = 13, BackgroundColor3 = Color3.fromRGB(150, 60, 60) }, function()
		local id = tonumber(userBox.Text)
		if not id then return end
		Remotes.Admin:FireServer("ResetUserArm", id)
	end)
	userConfirm = button({ Size = UDim2.new(0, 150, 0, 34), Position = UDim2.new(0, 412, 0, 580), Text = "", TextSize = 12, BackgroundColor3 = Color3.fromRGB(200, 40, 40), Visible = false }, function()
		if userArmed then Remotes.Admin:FireServer("ResetUserConfirm", userArmed) end
		userDisarm()
	end)
	userCancel = button({ Size = UDim2.new(0, 60, 0, 34), Position = UDim2.new(0, 566, 0, 580), Text = "Cancel", TextSize = 12, BackgroundColor3 = Color3.fromRGB(54, 58, 82), Visible = false }, userDisarm)

	text({ Size = UDim2.new(0, 230, 0, 22), Position = UDim2.new(0, 16, 0, 638), Text = "Hall of Fame: remove an entry (all servers)", TextSize = 12, TextColor3 = Color3.fromRGB(190, 195, 220) })
	for rank = 1, 3 do
		button({ Size = UDim2.new(0, 120, 0, 30), Position = UDim2.new(0, 16 + (rank - 1) * 130, 0, 664), Text = "Remove #" .. rank, TextSize = 12, BackgroundColor3 = Color3.fromRGB(110, 70, 70) }, function()
			Remotes.Admin:FireServer("HallRemove", rank)
		end)
	end

	Remotes.Admin.OnClientEvent:Connect(function(action, data, extra)
		if action == "ResetUserArmed" then
			userArmed = data
			userConfirm.Text = "⚠ Wipe " .. tostring(extra or data)
			userConfirm.Visible, userCancel.Visible = true, true
			task.delay(30, function() if userArmed == data then userDisarm() end end)
			return
		end
		if action == "ResetArmed" then
			confirmButton.Visible, cancelButton.Visible = true, true
			resetNote.Text = "Are you sure? This cannot be undone. Press the red button within 30 seconds."
			task.delay(30, function() confirmButton.Visible, cancelButton.Visible = false, false end)
			return
		end
		if action ~= "List" then return end
		local lines = { string.format("<b>Server %s · %d player(s)</b>  (only this server is shown)", data.JobId, data.Count) }
		for _, row in ipairs(data.Players) do
			table.insert(lines, string.format("<b>%s</b> (%d) · Lv %d · Power %d · Gold %d · Tickets %d · %s · MaxZone %d",
				row.Name, row.UserId, row.Level, row.Power, row.Gold, row.Tickets, tostring(row.Zone), row.MaxZone))
		end
		body.Text = table.concat(lines, "\n")
		local selected = targets[targetIndex] and targets[targetIndex].UserId
		targets = data.Players
		targetIndex = 1
		for index, row in ipairs(targets) do
			if row.UserId == selected then targetIndex = index end
		end
		showTarget()
	end)

	local function refreshLoop()
		while panel.Visible do
			Remotes.Admin:FireServer("List")
			task.wait(3)
		end
	end

	local function toggle()
		panel.Visible = not panel.Visible
		if panel.Visible then task.spawn(refreshLoop) end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.F6 then return end
		toggle()
	end)

	-- 폰 / 태블릿(키보드가 없는 기기): F6 키가 없으니 운영자에게만 작은 "Admin" 버튼을 보여 준다 (위쪽 가운데, 접속자 알약 옆). 창은 화면 크기에 맞게 줄인다.
	if UserInputService.TouchEnabled then
		local openButton = makeButton({
			Size = UDim2.new(0, 56, 0, 28), AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0.5, 44, 0, 6),
			Text = "Admin", TextSize = 12, BackgroundColor3 = Color3.fromRGB(70, 56, 110), ZIndex = 5,
		}, gui, toggle)
		openButton.Name = "AdminOpenButton"
		local closeButton = makeButton({
			Size = UDim2.new(0, 64, 0, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8),
			Text = "Close", TextSize = 13, BackgroundColor3 = Color3.fromRGB(120, 70, 70), ZIndex = 12,
		}, panel, toggle)
		closeButton.Name = "AdminCloseButton"
		local fit = Instance.new("UIScale")
		fit.Parent = panel
		local function refit()
			local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
			fit.Scale = math.clamp(math.min((view.X - 16) / 640, (view.Y - 16) / 708), 0.3, 1)
		end
		refit()
		if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit) end
	end
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
