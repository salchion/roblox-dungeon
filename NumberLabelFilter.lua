-- NumberLabelFilter (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: NumberLabelFilter)
-- 로블록스 자동 번역(현지화)이 "숫자만 계속 바뀌는 글자"(골드 / DPS / 체력 / 피해 숫자 ...)를 번역 표에 하나하나 모으지 않게 한다.
-- 숫자가 다르면 로블록스는 서로 다른 문장으로 모아서 번역 표가 불어나고 자동 번역 한도(월 55만 글자)를 빨리 쓰기 때문이다.
-- 방식: 글자에 영어 단어(알파벳 3글자 이상)가 없으면 그 글자 객체의 AutoLocalize 를 끈다. (단어가 있는 글자는 그대로 둔다.)

local Players = game:GetService("Players")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local IGNORED_WORDS = { DPS = true, XP = true }

local function hasWord(text)
	local bare = string.gsub(text, "<[^>]*>", " ")
	for word in string.gmatch(bare, "%a%a%a+") do
		if not IGNORED_WORDS[word] then return true end
	end
	return false
end

local watched = setmetatable({}, { __mode = "k" })
local function watch(obj)
	if watched[obj] or not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
	watched[obj] = true
	local function check()
		if not hasWord(obj.Text) then
			if obj.AutoLocalize then obj.AutoLocalize = false end
		end
	end
	check()
	obj:GetPropertyChangedSignal("Text"):Connect(check)
end

local function watchTree(root)
	for _, obj in ipairs(root:GetDescendants()) do watch(obj) end
	root.DescendantAdded:Connect(watch)
end

for _, gui in ipairs(playerGui:GetChildren()) do watchTree(gui) end
playerGui.ChildAdded:Connect(watchTree)
-- 월드 안의 이름표 / 피해 숫자 (BillboardGui)
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("TextLabel") then watch(obj) end
end)
