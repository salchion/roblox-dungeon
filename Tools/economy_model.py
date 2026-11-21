#!/usr/bin/env python3
"""경제 모델 (Config 의 실제 공식 그대로): 무기 진화 시간 · 벽 · 골드 수급 표를 뽑는다.

사용: python3 Tools/economy_model.py
Config.lua 의 값을 바꾸면 아래 상수도 같이 바꿔서 다시 돌린다 (ECONOMY.md 의 표가 이 출력이다).

Config 와 맞춘 것
  Config.Weapon.WeaponCount = 50 / LevelScale = 326 / 1055
  Config.Weapon.StepsFor : 1~5번째 15단계, 6~10번째 20, 11~30번째 24, 31~50번째 20 (총 1,055단계 · 마지막 단계 번호 1,054)
  Config.Economy : IncomeBase 1500, StepMinutesEarly 0.2, StepMinutesLate 1.2, LateLevel 600, FieldGoldMult 2.6
  Config.GetEnhanceCost : IncomeBase x 공격력 배율 x 걸리는 분 x PriceMult(단계)
  Config.GetEnhanceChance : max(50%, 95% - 0.15% x 단계 x LevelScale)  (실패해도 단계는 안 내려가고 골드만 쓴다)
  Config.GetDamageMultiplier : (1 + 0.04e + 0.00012e^2) x 1.4^(시대-1),  e = 단계 x LevelScale
  Config.Idle : Fraction 0.22, OfflineEfficiency 0.6, 기준 = 그 구역 필드 실수입(FieldIncomePerMin, 분당 100마리)
  Config.Dummy.ManualFraction = 0 (직접 쏘는 골드는 없앴다: 방치 수입만 있다)
  Config.Field : 몬스터 레벨 = 1 + 3 x (구역-1), ZoneDanger.Reward, FieldGoldMult / 던전 = 필드 x 0.6, 깊이마다 x1.15
"""
LS = 326 / 1055                 # Config.Weapon.LevelScale
WEAPON_COUNT = 50               # Config.Weapon.WeaponCount
INCOME_BASE, EARLY, LATE, LATE_LEVEL = 1500, 0.2, 1.2, 600
IDLE_FRACTION, OFFLINE_EFF = 0.22, 0.6
KILLS_PER_MIN = [120, 100, 70, 27, 27, 27, 27, 27]   # Config.Idle.KillsPerMin (구역 1~8, 필드 수입 기준 · 5~8구역은 잠정)
ERAS_PER_LEVEL = 1.4

ZONE_REWARD = [1, 1.5, 2.2, 7.2, 9.2, 14.3, 21.6, 33.8]   # Config.Field.ZoneDanger.Reward
FIELD_GOLD_MULT = 2.6                                     # Config.Economy.FieldGoldMult
DUNGEON_GOLD_MULT = 0.6                                   # Config.Economy.DungeonGoldMult
DUNGEON_DEPTH_GOLD = 1.15                                 # Config.Dungeon.Depth.GoldGrowth
# 구역 -> 그 구역에서 싸우는 대략의 무기 (로그 2점: 존 4 = 무기 192단계쯤(tier 11), 끝판 = 50번째 무기)
ZONE_TIER = {1: 1, 2: 2, 3: 6, 4: 11, 5: 14, 6: 18, 7: 24, 8: 34}


def field_income(zone, kills=None):
    """그 구역에서 1분에 버는 필드 골드 (Config.Idle.FieldIncomePerMin 과 같은 식). kills 를 안 주면 그 구역의 분당 처치 수."""
    if kills is None:
        kills = KILLS_PER_MIN[zone - 1]
    level = 1 + 3 * (zone - 1)
    return (8 + 4 * level) * ZONE_REWARD[zone - 1] * FIELD_GOLD_MULT * kills


def zone_for_tier(index):
    """그 무기를 주로 쓰는 구역 (방치 / 오프라인 수입을 계산할 때 쓴다)."""
    best = 1
    for zone in sorted(ZONE_TIER):
        if index >= ZONE_TIER[zone]:
            best = zone
    return best


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
    """Config.PriceMult (11-15 보수안): 175단계까지 x1 -> 215 x5 (존 4 입구 첫 벽) -> 300 x3 -> 400 x2.5 -> 700 x2.2 -> 끝 x1.5."""
    max_level = TOTAL_STEPS - 1

    def lerp(a, b, t):
        return a + (b - a) * min(1.0, max(0.0, t))

    if level <= 175:
        return 1.0
    if level <= 215:
        return lerp(1, 5, (level - 175) / 40)
    if level <= 300:
        return lerp(5, 3, (level - 215) / 85)
    if level <= 400:
        return lerp(3, 2.5, (level - 300) / 100)
    if level <= 700:
        return lerp(2.5, 2.2, (level - 400) / 300)
    return lerp(2.2, 1.5, (level - 700) / max(1, max_level - 700))


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


# ================================================================
# 제안안 비교 (python3 Tools/economy_model.py --compare)
#   Config 값을 바꿨을 때 존별로 얼마나 걸리는지를 현재 값과 나란히 본다.
#   * 존 z 의 시간 = "그 존에서 다음 존으로 넘어가기까지 필요한 무기 티어(WEAPONS_FOR_ZONE)를
#     모두 강화하는 기대 골드 / 그 존의 필드 수입(분당)"  (분당 100마리 처치 기준)
#   * Config.GetEnhanceCost 는 단계 비용을 "지금까지의 최댓값"으로 올린다(Config.lua 의 마지막 do 블록).
#     그래서 가격 곡선이 내려가도 실제 비용은 내려가지 않는다 -> 여기서도 그렇게 계산한다.
#   * 바꾸는 값: PriceMult(단계) / StepMinutesEarly·Late·LateLevel / Field.ZoneDanger.Reward / StepsFor
# ================================================================
import sys as _sys

WEAPONS_FOR_ZONE = {1: 1, 2: 2, 3: 6, 4: 11, 5: 14, 6: 18, 7: 24, 8: 34}  # 그 존에서 주로 쓰는 무기 번호

SCENARIOS = {
    # 지금 값 (11-15 통합 패치 적용 후 = 보수안)
    "현재":   dict(steps_late=20, price=[(0, 1.0), (175, 1.0), (215, 5.0), (300, 3.0), (400, 2.5), (700, 2.2), (1054, 1.5)],
                   early=0.2, late=1.2, late_level=600, reward=list(ZONE_REWARD)),
    # 이전 값 (9908e06): 60~200단계에서 x1 -> x5 로 4배 넘게 뛰고, 그 구간이 존 3 전체라 존 3 > 존 4 역전
    "이전":   dict(steps_late=20, price=[(0, 1.0), (60, 1.0), (200, 5.0), (700, 3.0), (1054, 1.0)],
                   early=0.2, late=1.4, late_level=600, reward=list(ZONE_REWARD)),
    # 적극안 (다음 후보): 후반 무기 단계를 20 -> 14 (총 1,055 -> 935), 가격 / 단계 분도 함께 낮춘다
    "적극안": dict(steps_late=14, price=[(0, 1.0), (150, 1.0), (200, 4.2), (300, 2.8), (560, 2.0), (760, 1.5), (935, 1.0)],
                   early=0.2, late=1.0, late_level=560, reward=[1, 1.5, 2.2, 5.0, 7.5, 14.3, 21.6, 42.0]),
}


def _interp(points, level):
    """[(단계, 배수), ...] 를 선형으로 잇는다 (Config.PriceMult 와 같은 방식)."""
    if level <= points[0][0]:
        return points[0][1]
    for (a, va), (b, vb) in zip(points, points[1:]):
        if level <= b:
            return va + (vb - va) * (level - a) / (b - a)
    return points[-1][1]


class _Plan:
    """한 시나리오의 무기 사다리 / 가격 / 존 수입을 계산한다."""

    def __init__(self, name, spec):
        self.name = name
        self.spec = spec
        late = spec["steps_late"]

        def steps_of(index):
            if index <= 5:
                return 15
            if index <= 10:
                return 20
            if index <= 30:
                return 24
            return late

        self.steps = [steps_of(i) for i in range(1, WEAPON_COUNT + 1)]
        self.total = sum(self.steps)
        self.scale = 326 / self.total            # Config.Weapon.LevelScale (최대 위력은 그대로 두고 비율만 바꾼다)
        self.start = []
        acc = 0
        for s in self.steps:
            self.start.append(acc)
            acc += s

    def tier_index(self, level):
        index = 0
        for i, first in enumerate(self.start):
            if level >= first:
                index = i
        return index

    def damage(self, level):
        era = self.tier_index(level) // 5 + 1
        e = level * self.scale
        return (1 + 0.04 * e + 0.00012 * e * e) * ERAS_PER_LEVEL ** (era - 1)

    def price(self, level):
        return _interp(self.spec["price"], level)

    def step_chance(self, level):
        return max(0.5, 0.95 - 0.0015 * level * self.scale)

    def step_gold(self, level):
        minutes = self.spec["early"] + (self.spec["late"] - self.spec["early"]) * min(1, level / self.spec["late_level"])
        return INCOME_BASE * self.damage(level) * minutes * self.price(level) / self.step_chance(level)

    def cost_table(self):
        """Config.GetEnhanceCost 처럼 '지금까지의 최댓값'으로 올린 표."""
        table, best = [], 0
        for level in range(0, self.total):
            raw = self.step_gold(level if level < self.total - 1 else self.total - 2)
            best = max(best, raw)
            table.append(best)
        return table

    def zone_income(self, zone):
        level = 1 + 3 * (zone - 1)                     # Config.Field.GetZoneLevel
        return (8 + 4 * level) * self.spec["reward"][zone - 1] * FIELD_GOLD_MULT * 100

    def zone_steps(self, zone):
        first = WEAPONS_FOR_ZONE[zone]
        last = WEAPONS_FOR_ZONE.get(zone + 1, WEAPON_COUNT + 1)
        lo = self.start[first - 1]
        hi = self.start[last - 1] if last <= WEAPON_COUNT else self.total - 1
        return lo, hi

    def zone_minutes(self):
        table = self.cost_table()
        out = []
        for zone in range(1, 9):
            lo, hi = self.zone_steps(zone)
            cost = sum(table[level] for level in range(lo, hi))
            income = self.zone_income(zone)
            out.append((zone, lo, hi - 1, cost, income, cost / income))
        return out

    def band_share(self):
        table = self.cost_table()
        grand = sum(table[0:self.total - 1])
        edges = [0, 60, 200, 400, 600, 700, 970, self.total - 1]
        share = {}
        for a, b in zip(edges, edges[1:]):
            share[(a, b)] = sum(table[a:min(b, self.total - 1)]) / grand * 100
        return share, grand

    def slowest(self):
        """한 단계에 걸리는 시간(설계 분/단계, 가격 배수 포함)이 가장 긴 단계."""
        best = (0, 0.0)
        for level in range(0, self.total - 1):
            early, late = self.spec["early"], self.spec["late"]
            minutes = early + (late - early) * min(1, level / self.spec["late_level"])
            value = minutes * self.price(level)
            if value > best[1]:
                best = (level, value)
        return best


def compare_scenarios():
    plans = [_Plan(name, spec) for name, spec in SCENARIOS.items()]
    print("== 제안안 비교: 존별 '다음 존까지' 소요 시간 (무기 강화만 · 분당 100마리)")
    print(f"{'':>10}" + "".join(f"{('z%d' % z):>8}" for z in range(1, 9)) + f"{'합계':>9}")
    for plan in plans:
        rows = plan.zone_minutes()
        total = sum(r[5] for r in rows)
        print(f"{plan.name:>10}" + "".join(f"{r[5]:>7.1f}분" for r in rows) + f"{total / 60:>8.2f}h")
    print()
    for plan in plans:
        rows = plan.zone_minutes()
        share, grand = plan.band_share()
        slow_level, slow_value = plan.slowest()
        late = share[(700, 970)] + share[(970, plan.total - 1)]
        table = plan.cost_table()
        print(f"--- {plan.name} (총 {plan.total:,}단계 · LevelScale {plan.scale:.4f})")
        for zone, lo, hi, cost, income, minutes in rows:
            first = table[lo] / income
            last = table[hi] / income
            print(f"    존 {zone}: {lo:>4}~{hi:<4} 단계 · 필요 골드 {cost:>14,.0f} · 수입 {income:>10,.0f}/분"
                  f" · {minutes:>7.1f}분 · 단계당 {first:.2f}~{last:.2f}분")
        print(f"    가장 느린 단계(설계): {slow_level:,}단계 {slow_value:.2f}분 · 700단계 이후 골드 비중 {late:.1f}% · 전체 필요 골드 {grand:,.0f}")
        print("    바꾸는 값: PriceMult " + " → ".join(f"{a}×{v:g}" for a, v in plan.spec["price"])
              + f" / StepMinutes {plan.spec['early']}→{plan.spec['late']} (LateLevel {plan.spec['late_level']})"
              + " / Reward " + str(plan.spec["reward"]))
    print()
    print("읽는 법: 존에서 나오는 골드로 그 존의 무기 강화를 다 하는 시간이다. 1~3존이 짧고 4~5존에서 확 늘어나면 설계 의도(첫 떡벽)와 맞다.")
    print("          한 존 안에서 '단계당 분'이 시작 → 끝으로 크게 오르면, 그 존에 오래 머물수록 느려진다는 뜻이다(필드 수입은 고정인데 강화 비용은 내 무기 단계를 따라 오르기 때문).")


if "--compare" in _sys.argv:
    compare_scenarios()
    raise SystemExit(0)


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
    active = INCOME_BASE * dm(mid, era)      # 기준표 활동 수입(분당) = IncomeBase x 공격력 배율
    zone = zone_for_tier(i)
    idle = IDLE_FRACTION * field_income(zone)  # 방치(분당) = 그 구역 필드 실수입의 22% (배율 x1)
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
print("== 방치 / 오프라인 (분당): 기준 = 그 구역 필드 실수입 (Config.Idle.FieldIncomePerMin) ==")
for zone in range(1, 9):
    field_gold = field_income(zone)
    print(f"존 {zone}: 필드 {field_gold:>11,.0f}/분 · 방치 {IDLE_FRACTION * field_gold:>10,.0f}/분 (필드의 22%)"
          f" · 오프라인 {IDLE_FRACTION * OFFLINE_EFF * field_gold:>10,.0f}/분 (필드의 13.2%)")
print("      (예전에는 방치 = IncomeBase 기준표 x 0.22 라서, 같은 구역이라도 무기 단계가 낮을 때 오프라인이 필드의 1~6%밖에 안 됐다)")

print()
print("== 던전 깊이별 골드/마리 (던전 = 필드 골드 x 0.6, 깊이마다 x1.15) ==")
base = (8 + 4 * 10) * ZONE_REWARD[3] * FIELD_GOLD_MULT  # 4구역 몬스터 기준
for depth in (1, 5, 10, 25, 50):
    per_kill = base * DUNGEON_GOLD_MULT * DUNGEON_DEPTH_GOLD ** (depth - 1)
    print(f"깊이 {depth:>3}: {per_kill:>12,.0f} / 마리 · 분당(100마리) {per_kill * 100:>14,.0f}")

# ---------------------------------------------------------------- 세트 효과 가격 (E1: 가격 기준 = max(세트 구역, MaxZone))
#   Config.Sets.AugCost(zone, level, maxZone) 그대로: 기준 구역 = AugPriceZone(zone, maxZone) = max(세트 구역, 내 MaxZone)
#   (11-15 E1 확정: 위력은 안 건드리고 "가격 기준"만 올린다 -> 1구역 세트를 1.6만 G 로 풀강해 끝까지 쓰는 길이 막힌다)
ZONE_COUNT = 8                  # Config.Field.ZoneCount
AUG_MULT = [1, 2.5, 6]          # Config.Sets.AugCostMult (1 / 2 / 3단계)


def price_mult_ref(level):
    """Config.PriceMultRef (장비 / 스킬 / 펫 / 세트 / 훈련 가격표의 기준 수입 곡선)."""
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


def ref_income(f):
    """Config.RefIncome(f): 세트 효과 가격표의 기준 분당 수입 (Config.Weapon.MaxLevel = 마지막 단계 번호 1,054)."""
    level = int(f * (TOTAL_STEPS - 1))
    return INCOME_BASE * dm(level, era_for(level)) * price_mult_ref(level)


def _progressive(f):
    return 0.3 + 0.7 * f


def _ease(f):
    return 0.5 + 0.5 * min(1.0, max(0.0, f) / 0.5)


_AUG_SUM = sum(_progressive((z - 1) / (ZONE_COUNT - 1)) * m for z in range(1, ZONE_COUNT + 1) for m in AUG_MULT)
AUG_K = 600 / _AUG_SUM * 0.6    # Config.SinkMinutes 600 · 세트는 다른 성장보다 40% 싸게


def aug_price_zone(zone, max_zone=0):
    return max(min(max(zone, 1), ZONE_COUNT), min(max(max_zone, 0), ZONE_COUNT))


def aug_cost(zone, level, max_zone=0):
    f = (aug_price_zone(zone, max_zone) - 1) / (ZONE_COUNT - 1)
    mult = AUG_MULT[level - 1] if 0 < level <= len(AUG_MULT) else 8
    return max(1, int(ref_income(f) * AUG_K * _progressive(f) * _ease(f) * mult))


AUG_OWN = {z: sum(aug_cost(z, lv) for lv in (1, 2, 3)) for z in range(1, ZONE_COUNT + 1)}

print()
print("== 세트 효과 가격 (E1: 가격 기준 구역 = max(세트 구역, 내 MaxZone)) ==")
print(f"{'구역':>4} {'Lv1':>13} {'Lv2':>13} {'Lv3':>13} {'1~3단계 합':>15}")
for zone in range(1, ZONE_COUNT + 1):
    c = [aug_cost(zone, lv) for lv in (1, 2, 3)]
    print(f"{zone:>4} {c[0]:>13,} {c[1]:>13,} {c[2]:>13,} {sum(c):>15,}")
print(f"  (내 구역 그대로 올릴 때 8세트 전부 합계 {sum(AUG_OWN.values()):,} G · 같은 조건 3칸(AugSlotZones 0/4/7)만 쓰면 "
      f"{sum(sorted(AUG_OWN.values())[-3:]):,} G)")
print()
print(f"{'내 MaxZone':>10} {'8세트 전부':>16} {'그 구역 수입/분':>15} {'필드 사냥 시간':>12} {'3칸(셋)만':>14}")
for mz in range(1, ZONE_COUNT + 1):
    total = sum(aug_cost(z, 1, mz) + aug_cost(z, 2, mz) + aug_cost(z, 3, mz) for z in range(1, ZONE_COUNT + 1))
    cheapest3 = sum(sorted(aug_cost(z, 1, mz) + aug_cost(z, 2, mz) + aug_cost(z, 3, mz) for z in range(1, ZONE_COUNT + 1))[:3])
    income = field_income(mz)
    print(f"{mz:>10} {total:>16,} {income:>15,.0f} {total / income / 60:>10.2f}시간 {cheapest3:>14,}")
print("      (자기 구역 이상의 세트 = 가격 그대로 -> 신규 유저가 자기 구역 세트를 올리는 값은 안 오른다.")
print("       오르는 것은 이미 지나온 낮은 구역 세트를 더 올릴 때뿐이고, 그 값은 \"그 구역 가격\"과 같아진다 = \"1구역 세트 하나로 끝까지\"가 막힌다)")
