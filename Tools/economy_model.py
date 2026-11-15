#!/usr/bin/env python3
"""경제 모델 (Config 의 실제 공식 그대로): 무기 진화 시간 · 벽 · 골드 수급 표를 뽑는다.

사용: python3 Tools/economy_model.py
Config.lua 의 값을 바꾸면 아래 상수도 같이 바꿔서 다시 돌린다 (ECONOMY.md 의 표가 이 출력이다).

Config 와 맞춘 것
  Config.Weapon.WeaponCount = 50 / LevelScale = 326 / 1055
  Config.Weapon.StepsFor : 1~5번째 15단계, 6~10번째 20, 11~30번째 24, 31~50번째 20 (총 1,055단계 · 마지막 단계 번호 1,054)
  Config.Economy : IncomeBase 1500, StepMinutesEarly 0.2, StepMinutesLate 1.4, LateLevel 600, FieldGoldMult 2.6
  Config.GetEnhanceCost : IncomeBase x 공격력 배율 x 걸리는 분 x PriceMult(단계)
  Config.GetEnhanceChance : max(50%, 95% - 0.15% x 단계 x LevelScale)  (실패해도 단계는 안 내려가고 골드만 쓴다)
  Config.GetDamageMultiplier : (1 + 0.04e + 0.00012e^2) x 1.4^(시대-1),  e = 단계 x LevelScale
  Config.Idle : Fraction 0.22, OfflineEfficiency 0.6
  Config.Dummy.ManualFraction = 0 (직접 쏘는 골드는 없앴다: 방치 수입만 있다)
  Config.Field : 몬스터 레벨 = 1 + 3 x (구역-1), ZoneDanger.Reward, FieldGoldMult / 던전 = 필드 x 0.6, 깊이마다 x1.15
"""
LS = 326 / 1055                 # Config.Weapon.LevelScale
WEAPON_COUNT = 50               # Config.Weapon.WeaponCount
INCOME_BASE, EARLY, LATE, LATE_LEVEL = 1500, 0.2, 1.4, 600
IDLE_FRACTION, OFFLINE_EFF = 0.22, 0.6
ERAS_PER_LEVEL = 1.4

ZONE_REWARD = [1, 1.5, 2.2, 7.2, 9.2, 14.3, 21.6, 33.8]   # Config.Field.ZoneDanger.Reward
FIELD_GOLD_MULT = 2.6                                     # Config.Economy.FieldGoldMult
DUNGEON_GOLD_MULT = 0.6                                   # Config.Economy.DungeonGoldMult
DUNGEON_DEPTH_GOLD = 1.15                                 # Config.Dungeon.Depth.GoldGrowth
# 구역 -> 그 구역에서 싸우는 대략의 무기 (로그 2점: 존 4 = 무기 192단계쯤(tier 11), 끝판 = 50번째 무기)
ZONE_TIER = {1: 1, 2: 2, 3: 6, 4: 11, 5: 14, 6: 18, 7: 24, 8: 34}


def steps_for(index):
    if index <= 5:
        return 15
    if index <= 10:
        return 20
    if index <= 30:
        return 24
    return 20


def era_of(index):
    return (index - 1) // 5 + 1


def price_mult(level):
    """Config.PriceMult: 중반(60~200)에 최대 x5까지 올라갔다가 끝에서 x1 로 돌아온다."""
    max_level = TOTAL_STEPS - 1

    def lerp(a, b, t):
        return a + (b - a) * min(1.0, max(0.0, t))

    if level <= 60:
        return 1.0
    if level <= 200:
        return lerp(1, 5, (level - 60) / 140)
    if level <= 700:
        return lerp(5, 3, (level - 200) / 500)
    return lerp(3, 1, (level - 700) / max(1, max_level - 700))


def dm(level, era):
    e = level * LS
    return (1 + 0.04 * e + 0.00012 * e * e) * ERAS_PER_LEVEL ** (era - 1)


def step_cost(level, era):
    minutes = EARLY + (LATE - EARLY) * min(1, level / LATE_LEVEL)
    return int(INCOME_BASE * dm(level, era) * minutes * price_mult(level))


def success(level):
    return max(0.5, 0.95 - 0.0015 * level * LS)


TOTAL_STEPS = sum(steps_for(i) for i in range(1, WEAPON_COUNT + 1))

tiers, total = [], 0
for i in range(1, WEAPON_COUNT + 1):
    steps = steps_for(i)
    tiers.append((i, total, steps, era_of(i)))
    total += steps


def tier_of(level):
    """그 단계가 속한 무기 번호 (1~50)."""
    found = tiers[0]
    for t in tiers:
        if t[1] <= level:
            found = t
        else:
            break
    return found


def era_for(level):
    return tier_of(level)[3]


def exp_step(level):
    """한 단계를 성공시킬 때까지 쓰는 기대 골드 (실패 포함)."""
    return step_cost(level, era_for(level)) / success(level)


def minutes_per_step(level):
    return exp_step(level) / (INCOME_BASE * dm(level, era_for(level)))


# ---------------------------------------------------------------- 무기별 진화 표
print(f"무기 수 {WEAPON_COUNT}종 · 총 강화 단계 {TOTAL_STEPS:,} (마지막 단계 번호 {TOTAL_STEPS - 1:,})")
print(f"성공 확률 {success(0):.0%} (1단계) ~ {success(TOTAL_STEPS - 1):.0%} (마지막 단계)")
print()
print(f"{'무기':>4} {'시대':>4} {'시작단계':>8} {'단계수':>5} {'진화비용(기대)':>16} {'활동수입/분':>12} "
      f"{'진화(활동)':>10} {'방치/분':>10} {'진화(방치만)':>12} {'오프라인/분':>11}")
cum = 0.0
cum_attempts = 0.0
active_minutes_total = 0.0
idle_minutes_total = 0.0
for i, mn, steps, era in tiers:
    # 마지막 무기의 끝은 MaxLevel(1,054) 도달 지점이라 그 위로 올리는 강화는 없다
    last = min(mn + steps, TOTAL_STEPS - 1)
    cost = sum(step_cost(l, era) / success(l) for l in range(mn, last))  # 실패로 다시 긁는 골드까지
    attempts = sum(1 / success(l) for l in range(mn, last))
    cum += cost
    cum_attempts += attempts
    mid = mn + steps // 2
    active = INCOME_BASE * dm(mid, era)      # 활동 수입(분당) = IncomeBase x 공격력 배율
    idle = IDLE_FRACTION * active            # 방치(분당, 배율 x1)
    offline = idle * OFFLINE_EFF
    active_minutes_total += cost / active
    idle_minutes_total += cost / idle
    if i in (1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50):
        print(f"{i:>4} {era:>4} {mn:>8,} {steps:>5} {cost:>16,.0f} {active:>12,.0f} "
              f"{cost / active:>8.1f}분 {idle:>10,.0f} {cost / idle / 60:>10.1f}시간 {offline:>11,.0f}")
print()
print(f"누적 비용(50종 전부) {cum:,.0f} G · 강화 시도 약 {cum_attempts:,.0f}번")
print(f"활동만으로 전부 올리면 약 {active_minutes_total / 60:,.1f}시간 (기준표 수입 기준)")
print(f"방치만으로 전부 올리면 약 {idle_minutes_total / 60:,.0f}시간 (방치 배율 x1) · 오프라인(효율 0.6)만이면 약 {idle_minutes_total / OFFLINE_EFF / 60:,.0f}시간")
print("참고: 실제 필드/던전 수입은 이 기준표보다 크다 (아래 '구역별 필드 골드').")
print("      그래서 위 시간은 '무기만 올렸을 때'의 기준값이고, 실제로는 장비 / 훈련 / 세트 효과가 같이 붙어 더 짧다.")

# ---------------------------------------------------------------- 레벨 밴드 / 벽
BANDS = [(0, 60), (60, 200), (200, 400), (400, 600), (600, 700), (700, 970), (970, 1054)]

print()
print("== 레벨 밴드: 어디에 골드가 몰리고 어디가 느린가 (기준표 수입) ==")
print(f"{'밴드':>12} {'골드':>16} {'비중':>7} {'기준표 시간':>10} {'단계당 분':>14}")
grand = sum(exp_step(l) for l in range(0, TOTAL_STEPS - 1))
for a, b in BANDS:
    gold = sum(exp_step(l) for l in range(a, b))
    hours = sum(exp_step(l) / (INCOME_BASE * dm(l, era_for(l))) for l in range(a, b)) / 60
    print(f"{a:>5,}~{b:<6,} {gold:>16,.0f} {gold / grand * 100:>6.1f}% {hours:>9.1f}h "
          f"{minutes_per_step(a):>6.2f}~{minutes_per_step(b - 1):>5.2f}분")
print(f"합계 {grand:,.0f} G")

slowest = max(range(0, TOTAL_STEPS - 1), key=minutes_per_step)
print()
print(f"가장 느린 단계: {slowest:,}단계 — 한 단계에 {minutes_per_step(slowest):.2f}분 "
      f"(0단계 {minutes_per_step(0):.2f}분, 마지막 {minutes_per_step(TOTAL_STEPS - 2):.2f}분)")
print(f"성공 확률이 바닥(50%)에 닿는 단계: {next(l for l in range(0, TOTAL_STEPS) if success(l) <= 0.5):,}단계")

# ---------------------------------------------------------------- 구역별 골드 수급
print()
print("== 구역별 필드 골드 (몬스터 레벨 = 1 + 3 x (구역-1), x 구역 보상표 x 2.6) ==")
print(f"{'구역':>4} {'몬스터 렙':>8} {'골드/마리':>12} {'분당(100마리)':>15} {'기준표 대비':>12}")
for zone in range(1, 9):
    level = 1 + 3 * (zone - 1)
    per_kill = (8 + 4 * level) * ZONE_REWARD[zone - 1] * FIELD_GOLD_MULT
    tier = ZONE_TIER[zone]
    ref = INCOME_BASE * dm(tiers[tier - 1][1], era_of(tier))
    print(f"{zone:>4} {level:>8} {per_kill:>12,.0f} {per_kill * 100:>15,.0f} {per_kill * 100 / ref:>11.1f}x")

print()
print("== 방치 / 오프라인 (분당) ==")
for level in (0, 60, 200, 400, 700, 1054):
    ref = INCOME_BASE * dm(level, era_for(level))
    print(f"{level:>5,}단계: 기준 {ref:>12,.0f} · 방치 {IDLE_FRACTION * ref:>11,.0f} · 오프라인 {IDLE_FRACTION * OFFLINE_EFF * ref:>10,.0f}")

print()
print("== 던전 깊이별 골드/마리 (던전 = 필드 골드 x 0.6, 깊이마다 x1.15) ==")
base = (8 + 4 * 10) * ZONE_REWARD[3] * FIELD_GOLD_MULT  # 4구역 몬스터 기준
for depth in (1, 5, 10, 25, 50):
    per_kill = base * DUNGEON_GOLD_MULT * DUNGEON_DEPTH_GOLD ** (depth - 1)
    print(f"깊이 {depth:>3}: {per_kill:>12,.0f} / 마리 · 분당(100마리) {per_kill * 100:>14,.0f}")
