-- LocalizeClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: LocalizeClient)
-- 로블록스 자동 번역(크리에이터 허브 > 로컬라이제이션)으로 만든 번역 표를, 코드로 글자를 바꿔 넣는 UI에도 적용한다.
-- 이유: 이 게임의 UI 글자는 거의 전부 스크립트가 나중에 Text 에 넣는다. 로블록스 자동 적용(AutoLocalize)은 글자가 바뀔 때 다시 적용되지 않는 경우가 있어서,
--       문서가 권하는 방법대로 Translator:Translate 로 직접 번역해서 넣는다 (GetTranslatorForPlayerAsync + Translate).
-- 플레이어의 로블록스 언어가 영어(원본 언어)이면 아무것도 하지 않는다. 번역 표에 없는 글자는 영어 그대로 둔다.
-- (KoreanClient 의 옛 사전 번역과는 별개다: 그쪽은 ENABLED=false 로 꺼 두었다.)

local Players = game:GetService("Players")
local LocalizationService = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ok, translator = pcall(function() return LocalizationService:GetTranslatorForPlayerAsync(player) end)
if not ok or not translator then
	warn("[LocalizeClient] 번역기를 못 불러왔습니다: " .. tostring(translator))
	return
end
local localeId = string.lower(tostring(translator.LocaleId))
-- (실제 앱에서도 한 줄 찍는다: F9 개발자 콘솔 > Client 탭에서 확인. 번역기 언어가 뭔지 알아야 안 될 때 원인을 찾는다)
print(string.format("[LocalizeClient] 번역기 언어 %s · RobloxLocaleId %s · SystemLocaleId %s · 플레이어 LocaleId %s",
	localeId, tostring(LocalizationService.RobloxLocaleId), tostring(LocalizationService.SystemLocaleId), tostring(player.LocaleId)))
if string.sub(localeId, 1, 2) == "en" then return end -- 원본 언어(영어)이면 번역할 게 없다

local memo = {}
local function translatePiece(obj, piece)
	if piece == "" or not string.find(piece, "%a%a%a") then return nil end -- (영어 단어가 없는 글자는 번역할 게 없다)
	local cached = memo[piece]
	if cached ~= nil then return cached or nil end
	local result
	local okT, translated = pcall(function() return translator:Translate(obj, piece) end)
	if okT and translated and translated ~= piece then result = translated end
	if not result then
		local okG, generic = pcall(function() return translator:Translate(game, piece) end)
		if okG and generic and generic ~= piece then result = generic end
	end
	if #piece < 200 then memo[piece] = result or false end -- (긴 글은 캐시에 쌓지 않는다)
	return result
end

-- 통째로 찾고, 없으면 <태그> / 줄바꿈 사이 조각마다 번역한다
local function translateText(obj, text)
	local whole = translatePiece(obj, text)
	if whole then return whole end
	local out, changed, position = {}, false, 1
	while position <= #text do
		local tagStart, tagEnd = string.find(text, "<[^>]*>", position)
		local newline = string.find(text, "\n", position, true)
		local cutStart, cutEnd
		if tagStart and (not newline or tagStart < newline) then
			cutStart, cutEnd = tagStart, tagEnd
		elseif newline then
			cutStart, cutEnd = newline, newline
		end
		local piece = string.sub(text, position, (cutStart or #text + 1) - 1)
		if piece ~= "" then
			local ko = translatePiece(obj, piece)
			if ko then changed = true end
			table.insert(out, ko or piece)
		end
		if not cutStart then break end
		table.insert(out, string.sub(text, cutStart, cutEnd))
		position = cutEnd + 1
	end
	return changed and table.concat(out) or nil
end

local record = setmetatable({}, { __mode = "k" }) -- [글자 객체] = 우리가 넣은 번역
local function apply(obj)
	local text = obj.Text
	if text == "" or record[obj] == text then return end
	local translated = translateText(obj, text)
	if translated and translated ~= text then
		record[obj] = translated
		obj.Text = translated
	end
end

local watched = setmetatable({}, { __mode = "k" })
local function watch(obj)
	if watched[obj] or not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
	watched[obj] = true
	apply(obj)
	obj:GetPropertyChangedSignal("Text"):Connect(function()
		if record[obj] == obj.Text then return end -- 우리가 넣은 번역
		apply(obj)
	end)
end

local function watchTree(root)
	for _, obj in ipairs(root:GetDescendants()) do watch(obj) end
	root.DescendantAdded:Connect(watch)
end

for _, gui in ipairs(playerGui:GetChildren()) do watchTree(gui) end
playerGui.ChildAdded:Connect(watchTree)
workspace.DescendantAdded:Connect(function(obj) -- 월드 안의 이름표 / 간판 (BillboardGui / SurfaceGui)
	if obj:IsA("TextLabel") or obj:IsA("TextButton") then
		if obj:FindFirstAncestorWhichIsA("BillboardGui") or obj:FindFirstAncestorWhichIsA("SurfaceGui") then watch(obj) end
	end
end)
for _, obj in ipairs(workspace:GetDescendants()) do
	if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and (obj:FindFirstAncestorWhichIsA("BillboardGui") or obj:FindFirstAncestorWhichIsA("SurfaceGui")) then watch(obj) end
end

-- (진단) 번역기가 실제로 번역을 돌려주는지 / 화면 글자를 몇 개나 번역했는지 8초 뒤에 한 번 찍는다 (실제 앱 포함)
do
	task.delay(8, function()
		local tests = { "Gear", "Weapon", "Settings", "Dash", "First Aid", "Death Lotus", "Auto-Attack", "Power Ranking" }
		for _, word in ipairs(tests) do
			local okA, withContext = pcall(function() return translator:Translate(playerGui, word) end)
			local okB, generic = pcall(function() return translator:Translate(game, word) end)
			print(string.format("[LocalizeClient 진단] %q -> 컨텍스트 있음: %s · 없음: %s", word, okA and tostring(withContext) or "오류", okB and tostring(generic) or "오류"))
		end
		local total, changed = 0, 0
		for obj in pairs(watched) do
			total += 1
			if record[obj] ~= nil then changed += 1 end
		end
		print(string.format("[LocalizeClient 진단] 지켜보는 글자 %d개 중 번역해서 바꾼 글자 %d개", total, changed))
	end)
end
