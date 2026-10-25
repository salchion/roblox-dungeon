-- KoreanClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: KoreanClient)
-- 설정 창의 "Language" 버튼(Attribute UiLang = "ko" / "en")에 맞춰, 화면에 보이는 글자를 한국어로 바꿔 보여 준다.
-- 방식: 화면 글자가 사전과 똑같으면 한국어로 바꾼다. 사전은 둘이다:
--   1) 이 파일의 DICT / PATTERNS: 설정 창처럼 손으로 적은 짧은 문장
--   2) Shared/KoData1.lua, KoData2.lua ... : 게임 안 문장 약 2000개 (Tools/ko_pairs.json 에서 Tools/build_ko.py 가 자동으로 만든다)
--      숫자가 들어가는 문장은 패턴(%d / %s 자리)으로 맞추고, <font> 태그나 줄바꿈이 있는 글은 조각 단위로 번역한다.
-- 영어로 돌아가면 원래 글자로 되돌린다. 사전에 없는 문장은 영어 그대로 보인다: ko_pairs.json 에 줄을 추가하고 build_ko.py 를 다시 돌리면 늘어난다.
-- 기본값: Roblox 언어 설정이 한국어면 "ko", 아니면 "en".

local Players = game:GetService("Players")
local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DICT = {
	-- 메뉴 / 탭
	["Character"] = "캐릭터", ["Skills·Growth"] = "스킬·성장", ["Quests"] = "퀘스트", ["Ranking"] = "랭킹",
	["🛡 Gear"] = "🛡 장비", ["🔫 Weapon"] = "🔫 무기", ["📊 Info"] = "📊 정보",
	["Gear"] = "장비", ["Weapon"] = "무기", ["Growth"] = "성장", ["Pets"] = "펫", ["Shop"] = "상점", ["Settings"] = "설정",
	["📋 Menu(B)"] = "📋 메뉴(B)", ["☰ Menu"] = "☰ 메뉴", ["📋 Menu"] = "📋 메뉴", ["⚙ Settings(H)"] = "⚙ 설정(H)", ["✨ Stats (T)"] = "✨ 스탯 (T)",
	["⚙ Settings / ❓ Help"] = "⚙ 설정 / ❓ 도움말", ["✨ Level Stats"] = "✨ 레벨 스탯",
	["Close"] = "닫기", ["Close (B)"] = "닫기 (B)", ["Close (H)"] = "닫기 (H)", ["Close (J)"] = "닫기 (J)",
	["🎁 Shop"] = "🎁 상점", ["📖 Codex"] = "📖 도감", ["🐾 Pet"] = "🐾 펫", ["🏆 Power Ranking"] = "🏆 전투력 랭킹", ["🏆 Weekly Ranking"] = "🏆 주간 랭킹",
	["🏆 Ranking"] = "🏆 랭킹", ["🎒 Gear"] = "🎒 장비",
	-- 자주 보이는 버튼
	["OK"] = "확인", ["Accept"] = "수락", ["Decline"] = "거절", ["Enter"] = "입장", ["Back to Lobby"] = "로비로", ["Leave Dungeon"] = "던전 나가기",
	["Leave Party"] = "파티 나가기", ["Invite"] = "초대", ["Kick"] = "추방", ["In party"] = "파티 중", ["Upgrade"] = "강화", ["MAX"] = "최대", ["Max"] = "최대",
	["Reset"] = "초기화", ["Reset All (Free)"] = "전체 초기화 (무료)", ["Start Training"] = "훈련 시작", ["Start Breakthrough"] = "돌파 시작",
	["Dash"] = "대시", ["Tallying..."] = "집계 중...", ["Loading..."] = "불러오는 중...", ["Rolling"] = "뽑는 중",
	["⛺ Warp"] = "⛺ 이동", ["✔ Unlocked"] = "✔ 해금됨", ["▶ Next!"] = "▶ 다음!", ["SUCCESS!"] = "성공!", ["FAIL"] = "실패", ["BOSS"] = "보스",
	["🔨 Weapon Upgrade"] = "🔨 무기 강화", ["🔫 Fight with this weapon"] = "🔫 이 무기로 싸우기", ["👀 Preview"] = "👀 미리보기",
	["⬆ Auto-equip stronger gear"] = "⬆ 더 좋은 장비 자동 장착",
	["⚔ Select Dungeon"] = "⚔ 던전 선택", ["🏰 Dungeon"] = "🏰 던전", ["⚔ Enter the Boss Rush"] = "⚔ 보스 러시 입장", ["👹 Boss Rush"] = "👹 보스 러시",
	["👹 Boss Rush Results"] = "👹 보스 러시 결과", ["Difficulty"] = "난이도", ["Lobby Players (Invite)"] = "로비 유저 (초대)",
	["🛡 Gear · Gacha"] = "🛡 장비 · 뽑기", ["📊 Chest Odds"] = "📊 상자 확률", ["📊 Odds"] = "📊 확률", ["📊 Full odds table"] = "📊 전체 확률표",
	["🎯 Dummy DPS"] = "🎯 허수아비 DPS", ["Perks (this dungeon only)"] = "특성 (이번 던전 한정)", ["A special room!"] = "특별한 방!",
	["A random buff was applied"] = "무작위 강화가 적용되었습니다", ["Got it, let's get stronger!"] = "알겠어요, 강해지러 가요!",
	["Follow the sky-blue light beam"] = "하늘색 빛줄기를 따라가세요", ["🏆 NEW WEEKLY BEST! Ranking updated"] = "🏆 주간 신기록! 랭킹이 갱신되었습니다",
	["✦ MYTHIC ✦"] = "✦ 신화 ✦", ["◎ DEADEYE ◎"] = "◎ 데드아이 ◎", ["🎁 Bonus triggered!"] = "🎁 보너스 발동!",
	["⏱ Use Time Skip"] = "⏱ 시간 건너뛰기 사용", ["⚙ Features (more unlock as you level up)"] = "⚙ 기능 (레벨이 오르면 더 열려요)",
	["🎨 Looks (cosmetic only)"] = "🎨 외형 (꾸미기 전용)", ["🖌 Color"] = "🖌 색상",
	-- 스킬 / 전투
	["Gale Sweep"] = "돌풍", ["First Aid"] = "응급 치료", ["Deadeye"] = "데드아이", ["Auto-Attack"] = "자동 공격",
	["🌪"] = "🌪", ["Dungeon Lord"] = "던전 군주",
	-- 설정 창 안내 (줄 단위가 아니라 통째로 쓰는 문장만)
	["Auto-Attack ON"] = "자동 공격 켜짐", ["Auto-Attack OFF"] = "자동 공격 꺼짐",
}

-- 숫자 등이 들어가는 문장: { 영어 패턴, 한국어 서식 } (영어 패턴의 (캡처)가 한국어 서식의 %s 자리에 순서대로 들어간다)
local PATTERNS = {
	{ "^Upgrade (%d+) G$", "강화 %s G" },
	{ "^Lv%.(%d+)$", "Lv.%s" },
	{ "^Depth (%d+)$", "깊이 %s" },
	{ "^🔊 Music Volume: (%d+)%%$", "🔊 음악 볼륨: %s%%" },
	{ "^🔫 Gunshot Volume: (%d+)%%$", "🔫 총소리 볼륨: %s%%" },
	{ "^📳 Screen Shake: ON$", "📳 화면 흔들림: 켜짐" }, { "^📳 Screen Shake: OFF$", "📳 화면 흔들림: 꺼짐" },
	{ "^📡 Radar: ON$", "📡 레이더: 켜짐" }, { "^📡 Radar: OFF$", "📡 레이더: 꺼짐" },
	{ "^🖥 Low%-spec mode %(less lag%): ON$", "🖥 저사양 모드 (렉 줄이기): 켜짐" }, { "^🖥 Low%-spec mode %(less lag%): OFF$", "🖥 저사양 모드 (렉 줄이기): 꺼짐" },
	{ "^👕 Hide gear look %(weapon stays%): ON$", "👕 장비 외형 숨기기 (무기는 유지): 켜짐" }, { "^👕 Hide gear look %(weapon stays%): OFF$", "👕 장비 외형 숨기기 (무기는 유지): 꺼짐" },
	{ "^🔍 UI Size: Small %(PC%)$", "🔍 UI 크기: 작게 (PC)" }, { "^🔍 UI Size: Normal %(PC%)$", "🔍 UI 크기: 보통 (PC)" },
	{ "^🔍 UI Size: Large %(PC%)$", "🔍 UI 크기: 크게 (PC)" }, { "^🔍 UI Size: X%-Large %(PC%)$", "🔍 UI 크기: 아주 크게 (PC)" },
	{ "^🌐 Language: English$", "🌐 언어: English" }, { "^🌐 Language: 한국어$", "🌐 언어: 한국어" },
}

local lang = player:GetAttribute("UiLang")
if lang ~= "ko" and lang ~= "en" then
	local ok, id = pcall(function() return LocalizationService.RobloxLocaleId end)
	lang = (ok and type(id) == "string" and string.sub(id, 1, 2) == "ko") and "ko" or "en"
	player:SetAttribute("UiLang", lang)
end

-- 자동 생성 사전 (KoData1, KoData2 ...): exact = { [영어] = 한국어 }, pats = { { 영어 패턴, 한국어 서식, 꼭 들어 있는 글자, 점수 }, ... } (점수가 낮은 패턴부터 맞춰 본다)
local data = { exact = {}, pats = {} }
local function loadData()
	local first = ReplicatedStorage:WaitForChild("KoData1", 10)
	local index = 1
	local module = first
	while module do
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			for en, ko in pairs(result.exact or {}) do data.exact[en] = ko end
			for _, entry in ipairs(result.pats or {}) do table.insert(data.pats, entry) end
		else
			warn("[KoreanClient] " .. module.Name .. " load failed: " .. tostring(result))
		end
		index += 1
		module = ReplicatedStorage:WaitForChild("KoData" .. index, 3)
	end
	-- 패턴 앞뒤의 "고정 글자"를 미리 뽑아 둔다: 글자가 그 앞뒤로 시작 / 끝나지 않으면 비싼 패턴 맞추기를 아예 건너뛴다 (화면 글자가 많을 때 멈추지 않게)
	local function literalEnds(pat)
		local body = string.sub(pat, 2, -2) -- ^ 와 $ 제거
		local firstOpen, lastClose, i = nil, nil, 1
		while i <= #body do
			local c = string.sub(body, i, i)
			if c == "%" then
				i += 2
			else
				if c == "(" and not firstOpen then firstOpen = i end
				if c == ")" then lastClose = i end
				i += 1
			end
		end
		local prefix = firstOpen and string.sub(body, 1, firstOpen - 1) or ""
		local suffix = lastClose and string.sub(body, lastClose + 1) or ""
		return (string.gsub(prefix, "%%(.)", "%1")), (string.gsub(suffix, "%%(.)", "%1"))
	end
	local kept = {}
	for _, entry in ipairs(data.pats) do
		local prefix, suffix = literalEnds(entry[1])
		entry[5], entry[6] = prefix, suffix
		if not (prefix == "" and suffix == "" and (entry[3] or "") == "") then table.insert(kept, entry) end
	end
	data.pats = kept
	table.sort(data.pats, function(a, b) return (a[4] or 0) < (b[4] or 0) end)
end

local memo, memoCount = {}, 0
local function remember(text, result)
	if memoCount > 6000 then memo, memoCount = {}, 0 end
	memo[text] = result
	memoCount += 1
	return result
end

-- 조각 하나(태그 / 줄바꿈이 없는 글자)를 번역한다. 못 찾으면 nil
local function lookup(piece)
	local direct = DICT[piece] or data.exact[piece]
	if direct then return direct end
	for _, entry in ipairs(PATTERNS) do
		local captures = { string.match(piece, entry[1]) }
		if #captures > 0 or string.find(piece, entry[1]) then
			local ok, result = pcall(string.format, entry[2], table.unpack(captures))
			if ok then return result end
		end
	end
	if #piece > 300 then return nil end -- (긴 글은 패턴으로 맞추지 않는다: 와일드카드가 여러 개인 패턴은 긴 글에서 아주 느려질 수 있다)
	for _, entry in ipairs(data.pats) do
		local anchor, prefix, suffix = entry[3], entry[5] or "", entry[6] or ""
		if (prefix == "" or string.sub(piece, 1, #prefix) == prefix) and (suffix == "" or string.sub(piece, -#suffix) == suffix)
			and (anchor == "" or string.find(piece, anchor, 1, true)) then
			local captures = { string.match(piece, entry[1]) }
			if #captures > 0 then
				local ok, result = pcall(string.format, entry[2], table.unpack(captures))
				if ok then return result end
			end
		end
	end
	return nil
end

-- 앞뒤 공백은 그대로 두고 가운데만 번역한다
local function lookupTrimmed(piece)
	local found = lookup(piece)
	if found then return found end
	local lead, core, trail = string.match(piece, "^(%s*)(.-)(%s*)$")
	if core and core ~= "" and (lead ~= "" or trail ~= "") then
		local ko = lookup(core)
		if ko then return lead .. ko .. trail end
	end
	return nil
end

local function translate(text)
	local cached = memo[text]
	if cached ~= nil then return cached or nil end
	local whole = lookupTrimmed(text)
	if whole then return remember(text, whole) end
	-- <태그> 와 줄바꿈 사이의 글자 조각마다 번역한다
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
			local ko = lookupTrimmed(piece)
			if ko then changed = true end
			table.insert(out, ko or piece)
		end
		if not cutStart then break end
		table.insert(out, string.sub(text, cutStart, cutEnd))
		position = cutEnd + 1
	end
	return remember(text, changed and table.concat(out) or false)
end

local originals = setmetatable({}, { __mode = "k" }) -- [글자 객체] = 원래(영어) 글자

local applying = false
local function apply(obj)
	if lang ~= "ko" then return end
	local text = obj.Text
	if text == "" then return end
	local ko = translate(text)
	if ko and ko ~= text then
		applying = true
		originals[obj] = text
		obj.Text = ko
		applying = false
	end
end

local watched = setmetatable({}, { __mode = "k" })
local function watch(obj)
	if watched[obj] then return end
	if not (obj:IsA("TextLabel") or obj:IsA("TextButton")) then return end
	watched[obj] = true
	apply(obj)
	obj:GetPropertyChangedSignal("Text"):Connect(function()
		if applying then return end
		originals[obj] = nil -- 게임이 새 글자를 넣었다 (영어로 온다): 다시 번역한다
		apply(obj)
	end)
end

local function watchTree(root)
	for _, obj in ipairs(root:GetDescendants()) do watch(obj) end
	root.DescendantAdded:Connect(watch)
end

local function refreshAll()
	if lang ~= "ko" then
		for obj, english in pairs(originals) do
			if obj.Parent then
				applying = true
				obj.Text = english
				applying = false
			end
		end
		originals = setmetatable({}, { __mode = "k" })
		return
	end
	-- 글자가 많아도 화면이 멈추지 않게 200개씩 나눠서 바꾼다
	local list = {}
	for obj in pairs(watched) do table.insert(list, obj) end -- (돌다가 새 글자가 생겨도 안전하게 복사해서 돈다)
	local batch = 0
	for _, obj in ipairs(list) do
		if obj.Parent then apply(obj) end
		batch += 1
		if batch >= 200 then
			batch = 0
			task.wait()
		end
	end
end

player:GetAttributeChangedSignal("UiLang"):Connect(function()
	local want = player:GetAttribute("UiLang")
	if want ~= "ko" and want ~= "en" then return end
	lang = want
	refreshAll()
end)

for _, gui in ipairs(playerGui:GetChildren()) do
	if gui:IsA("ScreenGui") then watchTree(gui) end
end
playerGui.ChildAdded:Connect(function(gui)
	if gui:IsA("ScreenGui") then task.defer(watchTree, gui) end
end)

task.spawn(function()
	loadData()
	memo, memoCount = {}, 0
	refreshAll()
end)
