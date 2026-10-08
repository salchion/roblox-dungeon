-- AudioBank (ReplicatedStorage 안의 ModuleScript, 이름: AudioBank)
-- 항목별 효과음 ID 목록. 이 파일은 "던전 업데이트"로 갱신된다 (소리 ID 를 알려주면 여기에 적어서 올려 준다).
-- 0 이거나 없는 항목은 기본 소리를 가공해서 쓴다. 항목 이름과 설명은 Shared/SoundBank.lua 참고.
-- (ReplicatedStorage > AudioIds 의 Bank = { ... } 에 직접 적은 값이 있으면 그쪽이 우선한다.)

return {
	Shot_Smg = 133095953198600, -- 기관단총 발사
	Skill_Heal = 136612911524402, -- 응급 치료 스킬
	Hit = 3748776946,             -- 적중
	Kill = 98731043228812,        -- 적 처치 (enemy defeat)
	Enh_Success = 73627822697931, -- 강화 성공 (upgrade success)
	Enh_Hammer = 9125819216,      -- 강화 망치 (metal clang)
	Skill_Ult = 70952641415058,   -- 데드아이 발동 (power up charge)
	Dash = 90661028523798,        -- 대시 (dash whoosh)
	Pickup = 107673144903206,     -- 전리품 줍기 (loot pickup)
}
