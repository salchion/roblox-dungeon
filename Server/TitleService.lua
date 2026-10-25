-- TitleService (ServerScriptService > Modules 안의 ModuleScript, 이름: TitleService)
-- 캐릭터 머리 위에 짧은 칭호 한 줄을 띄운다 (다른 유저 눈에도 보인다).
--   우선순위 (높은 것 하나만): 보스 러쉬 이번 주 1~3위 > 명예의 전당(전투력 TOP 3) > 던전 최고 깊이(10 이상)
--   칭호 값은 서버가 정하고, 머리 위 글자(BillboardGui)도 서버가 붙인다. 10초마다 바뀐 것만 갱신한다 (부하가 작다).
--   순위는 ShowcaseService 가 알고 있는 값(HallRank / WeeklyRank)을 읽는다. 운영자가 지운 기록은 거기서 같이 사라진다.

local Players = game:GetService("Players")

local Showcase = require(script.Parent:WaitForChild("ShowcaseService"))

local Titles = {}

local CHECK_EVERY = 10
local MIN_DEPTH = 10 -- 이 깊이부터 "Depth N" 칭호
local MEDAL_COLORS = { Color3.fromRGB(255, 215, 60), Color3.fromRGB(205, 210, 220), Color3.fromRGB(205, 140, 80) }

local current = setmetatable({}, { __mode = "k" }) -- [player] = 지금 붙어 있는 칭호 글자

local function titleOf(player)
	local week = Showcase.WeeklyRank(player.UserId)
	if week == 1 then return "👑 Weekly Champion", MEDAL_COLORS[1] end
	if week == 2 then return "🥈 Boss Rush #2", MEDAL_COLORS[2] end
	if week == 3 then return "🥉 Boss Rush #3", MEDAL_COLORS[3] end
	local hall = Showcase.HallRank(player.UserId)
	if hall then return "🏆 Hall of Fame #" .. hall, MEDAL_COLORS[hall] end
	local depth = player:GetAttribute("DepthBest_All") or 0
	if depth >= MIN_DEPTH then
		return "⛏ Depth " .. depth, Color3.fromRGB(255, 220, 110):Lerp(Color3.fromRGB(255, 120, 110), math.clamp(depth / 40, 0, 1))
	end
	return nil
end

local function apply(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	local text, color = titleOf(player)
	local gui = head:FindFirstChild("TitleTag")
	if not text then
		if gui then gui:Destroy() end
		current[player] = nil
		return
	end
	if gui and current[player] == text then return end
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "TitleTag"
		gui.Adornee = head
		gui.Size = UDim2.new(0, 150, 0, 17) -- (예전 220x26: 화면 가운데를 크게 가렸다)
		gui.StudsOffset = Vector3.new(0, 3.1, 0)
		gui.MaxDistance = 60
		gui.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextStrokeTransparency = 0.35
		label.Parent = gui
		gui.Parent = head
	end
	local label = gui:FindFirstChild("Label")
	if label then
		label.Text = text
		label.TextColor3 = color
	end
	current[player] = text
end

function Titles.Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.delay(1, function() apply(player) end)
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, player in ipairs(Players:GetPlayers()) do
				apply(player)
			end
		end
	end)
end

return Titles
