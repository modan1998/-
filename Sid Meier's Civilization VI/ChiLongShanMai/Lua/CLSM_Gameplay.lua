-- 赤龙山脉 v2：奇观刷龙神 + 神刀 + 多段攻击 + 破城占领
print("CLSM: gameplay script loaded v2")

local WONDER = "BUILDING_CHI_LONG_SHAN_MAI"
local UNIT = "UNIT_CLSM_ORSTED"
local PROP_SPAWNED = "CLSM_ORSTED_SPAWNED"
local PROP_ATK_USED = "CLSM_ATK_USED"
local PROP_LEVEL = "CLSM_LEVEL_CACHE"
local PROMOS = {
	"PROMOTION_CLSM_LV2",
	"PROMOTION_CLSM_LV3",
	"PROMOTION_CLSM_LV4",
	"PROMOTION_CLSM_LV5",
	"PROMOTION_CLSM_LV6",
	"PROMOTION_CLSM_LV7",
}

local function GetWonderIndex()
	local info = GameInfo.Buildings[WONDER]
	return info and info.Index or -1
end

local function GetUnitIndex()
	local info = GameInfo.Units[UNIT]
	return info and info.Index or -1
end

local function IsOrsted(pUnit)
	if pUnit == nil then return false end
	local idx = GetUnitIndex()
	if idx < 0 then return false end
	return pUnit:GetType() == idx
end

-- Level = 1 + number of CLSM promotions. Attacks per turn = Level (Lv1=1 … Lv7=7).
local function CountOrstedPromotions(pUnit)
	if pUnit == nil then return 0 end
	local n = 0
	local ok, experience = pcall(function() return pUnit:GetExperience() end)
	if not ok or experience == nil then return 0 end
	for _, promoType in ipairs(PROMOS) do
		local info = GameInfo.UnitPromotions[promoType]
		if info ~= nil then
			local has = false
			pcall(function()
				if experience.HasPromotion and experience:HasPromotion(info.Index) then
					has = true
				end
			end)
			if has then n = n + 1 end
		end
	end
	return n
end

local function GetOrstedLevel(pUnit)
	return 1 + CountOrstedPromotions(pUnit)
end

local function GetMaxAttacks(pUnit)
	return GetOrstedLevel(pUnit)
end

local function RefreshOrstedUnit(pUnit)
	if not IsOrsted(pUnit) then return end
	local level = GetOrstedLevel(pUnit)
	pUnit:SetProperty(PROP_LEVEL, level)
	-- Ensure promotion-granted NUM_ATTACKS apply; also cache for Lua multi-attack restore.
	print(string.format("CLSM: refresh Orsted id=%s level=%d maxAttacks=%d (promos grant +1 atk each; Lv1 base=1)",
		tostring(pUnit:GetID()), level, level))
end

local function RefreshAllOrsteds(reason)
	print("CLSM: RefreshAllOrsteds via " .. tostring(reason))
	for pid = 0, 63 do
		local pPlayer = Players[pid]
		if pPlayer ~= nil and pPlayer:IsAlive() then
			local pUnits = pPlayer:GetUnits()
			if pUnits ~= nil then
				for _, pUnit in pUnits:Members() do
					if IsOrsted(pUnit) then
						RefreshOrstedUnit(pUnit)
						pUnit:SetProperty(PROP_ATK_USED, 0)
					end
				end
			end
		end
	end
end

local function SpawnOrsted(playerID, plotID)
	local unitIdx = GetUnitIndex()
	if unitIdx < 0 then
		print("CLSM: UNIT_CLSM_ORSTED missing from DB")
		return
	end
	local pPlayer = Players[playerID]
	if pPlayer == nil then return end

	local pPlot = Map.GetPlotByIndex(plotID)
	if pPlot == nil then
		print("CLSM: invalid plot " .. tostring(plotID))
		return
	end

	if pPlot:GetProperty(PROP_SPAWNED) == 1 then
		print("CLSM: already spawned on plot " .. tostring(plotID))
		return
	end

	local x, y = pPlot:GetX(), pPlot:GetY()
	local pUnit = pPlayer:GetUnits():Create(unitIdx, x, y)
	if pUnit == nil then
		for dir = 0, 5 do
			local adj = Map.GetAdjacentPlot(x, y, dir)
			if adj ~= nil then
				pUnit = pPlayer:GetUnits():Create(unitIdx, adj:GetX(), adj:GetY())
				if pUnit ~= nil then break end
			end
		end
	end

	if pUnit ~= nil then
		pPlot:SetProperty(PROP_SPAWNED, 1)
		RefreshOrstedUnit(pUnit)
		pUnit:SetProperty(PROP_ATK_USED, 0)
		print("CLSM: spawned Orsted for player " .. tostring(playerID) .. " at " .. x .. "," .. y)
		local msg = Locale.Lookup("LOC_UNIT_CLSM_ORSTED_NAME")
		if playerID == Game.GetLocalPlayer() then
			pcall(function()
				NotificationManager.SendNotification(playerID, NotificationTypes.USER_DEFINED_2, msg)
			end)
		end
	else
		print("CLSM: FAILED to spawn Orsted")
	end
end

function OnBuildingConstructed(playerID, cityID, buildingID, plotID, bOriginalConstruction)
	if not bOriginalConstruction then return end
	local wonderIdx = GetWonderIndex()
	if wonderIdx < 0 then return end
	if buildingID == wonderIdx then
		print("CLSM: wonder constructed by " .. tostring(playerID))
		SpawnOrsted(playerID, plotID)
	end
end
GameEvents.BuildingConstructed.Add(OnBuildingConstructed)

-- 神刀：击杀单位；城防打满并尝试近战占领（含城邦）
local function GodBladeFinishUnit(ePlayer, eUnit)
	local pUnit = UnitManager.GetUnit(ePlayer, eUnit)
	if pUnit == nil then return end
	UnitManager.Kill(pUnit)
	print("CLSM: GodBlade killed unit " .. tostring(ePlayer) .. "/" .. tostring(eUnit))
end

local function GetCityDamage(pCity)
	local dmg = 0
	pcall(function()
		if pCity.GetDamage then dmg = pCity:GetDamage() end
	end)
	return dmg or 0
end

local function GetCityMaxHP(pCity)
	local maxHP = 200
	pcall(function()
		if pCity.GetMaxHitPoints then maxHP = pCity:GetMaxHitPoints() end
	end)
	return maxHP or 200
end

local function ForceCityMaxDamage(pCity)
	if pCity == nil then return end
	local maxHP = GetCityMaxHP(pCity)
	pcall(function() pCity:SetDamage(maxHP) end)
	pcall(function() pCity:ChangeDamage(maxHP) end)
	-- District outer defenses
	pcall(function()
		local pDistrict = pCity:GetDistricts():GetDistrict(GameInfo.Districts["DISTRICT_CITY_CENTER"].Index)
		if pDistrict ~= nil then
			local dmax = 200
			if pDistrict.GetMaxDamage then dmax = pDistrict:GetMaxDamage(0) or dmax end
			if pDistrict.SetDamage then pDistrict:SetDamage(0, dmax) end
			if pDistrict.ChangeDamage then pDistrict:ChangeDamage(0, dmax) end
		end
	end)
end

local function TryCaptureCityWithOrsted(pOrsted, pCity)
	if pOrsted == nil or pCity == nil then return false end
	local attackerID = pOrsted:GetOwner()
	if pCity:GetOwner() == attackerID then return false end

	-- Ensure at war (needed for city-states / civs)
	pcall(function()
		local dip = Players[attackerID]:GetDiplomacy()
		if dip ~= nil and not dip:IsAtWarWith(pCity:GetOwner()) then
			dip:DeclareWarOn(pCity:GetOwner(), WarTypes.FORMAL_WAR, true)
			print("CLSM: auto-declared war on " .. tostring(pCity:GetOwner()) .. " for capture")
		end
	end)

	ForceCityMaxDamage(pCity)
	local cx, cy = pCity:GetX(), pCity:GetY()
	local beforeOwner = pCity:GetOwner()

	-- Melee capture: place Orsted on city center (Range=0 unit)
	local placed = false
	pcall(function()
		UnitManager.PlaceUnit(pOrsted, cx, cy)
		placed = true
	end)
	if not placed then
		pcall(function()
			UnitManager.MoveUnit(pOrsted, cx, cy)
			placed = true
		end)
	end

	-- Re-read city ownership
	local pCity2 = Cities.GetCityInPlot(cx, cy)
	local afterOwner = pCity2 and pCity2:GetOwner() or beforeOwner
	local ok = (afterOwner == attackerID)
	print(string.format("CLSM: capture attempt city(%d,%d) beforeOwner=%s afterOwner=%s placed=%s ok=%s",
		cx, cy, tostring(beforeOwner), tostring(afterOwner), tostring(placed), tostring(ok)))
	return ok
end

local function GodBladeSmashCity(pCity, attackerID, pOrsted)
	if pCity == nil then return end
	if pCity:GetOwner() == attackerID then return end
	ForceCityMaxDamage(pCity)
	print("CLSM: GodBlade smashed city defenses owner=" .. tostring(pCity:GetOwner())
		.. " dmg=" .. tostring(GetCityDamage(pCity)) .. "/" .. tostring(GetCityMaxHP(pCity)))
	if pOrsted ~= nil then
		TryCaptureCityWithOrsted(pOrsted, pCity)
	end
end

local function OrstedAdjacentTo(pOrsted, x, y)
	local ox, oy = pOrsted:GetX(), pOrsted:GetY()
	if ox == x and oy == y then return true end
	for dir = 0, 5 do
		local adj = Map.GetAdjacentPlot(ox, oy, dir)
		if adj ~= nil and adj:GetX() == x and adj:GetY() == y then
			return true
		end
	end
	return false
end

local function FindAdjacentOrsted(victimOwner, x, y)
	for pid = 0, 63 do
		local pPlayer = Players[pid]
		if pPlayer ~= nil and pPlayer:IsAlive() and pid ~= victimOwner then
			local pUnits = pPlayer:GetUnits()
			if pUnits ~= nil then
				for _, pUnit in pUnits:Members() do
					if IsOrsted(pUnit) and OrstedAdjacentTo(pUnit, x, y) then
						return pUnit
					end
				end
			end
		end
	end
	return nil
end

function OnUnitDamageChanged(playerID, unitID, newDamage, oldDamage)
	if newDamage == nil or oldDamage == nil then return end
	if newDamage <= oldDamage then return end
	local pUnit = UnitManager.GetUnit(playerID, unitID)
	if pUnit == nil then return end
	if IsOrsted(pUnit) then return end
	local x, y = pUnit:GetX(), pUnit:GetY()
	local pOrsted = FindAdjacentOrsted(playerID, x, y)
	if pOrsted ~= nil then
		GodBladeFinishUnit(playerID, unitID)
	end
end
Events.UnitDamageChanged.Add(OnUnitDamageChanged)

function OnDistrictDamageChanged(playerID, districtID, damage, prevDamage)
	if damage == nil or prevDamage == nil then return end
	if damage <= prevDamage then return end
	local pPlayer = Players[playerID]
	if pPlayer == nil then return end
	local pDistrict = pPlayer:GetDistricts():FindID(districtID)
	if pDistrict == nil then return end
	local x, y = pDistrict:GetX(), pDistrict:GetY()
	local pOrsted = FindAdjacentOrsted(playerID, x, y)
	if pOrsted == nil then return end
	local pCity = Cities.GetCityInPlot(x, y)
	if pCity == nil then
		pCity = pDistrict:GetCity()
	end
	GodBladeSmashCity(pCity, pOrsted:GetOwner(), pOrsted)
end
Events.DistrictDamageChanged.Add(OnDistrictDamageChanged)

-- ===== Multi-attack: after Orsted attacks, restore moves/attacks until Level budget exhausted =====
local function RestoreOrstedForNextAttack(pUnit, reason)
	if not IsOrsted(pUnit) then return end
	local maxAtk = GetMaxAttacks(pUnit)
	local used = pUnit:GetProperty(PROP_ATK_USED) or 0
	if used >= maxAtk then
		print(string.format("CLSM: multi-attack budget exhausted used=%d max=%d (%s)", used, maxAtk, tostring(reason)))
		return
	end
	-- Restore movement so melee can attack again this turn
	pcall(function() UnitManager.RestoreMovement(pUnit) end)
	pcall(function() UnitManager.RestoreUnitAttacks(pUnit) end)
	pcall(function()
		if pUnit.SetMovesRemaining then
			local maxMoves = 10
			pcall(function() maxMoves = pUnit:GetMaxMoves() or maxMoves end)
			pUnit:SetMovesRemaining(maxMoves)
		end
	end)
	pcall(function()
		if pUnit.ChangeMovesRemaining then pUnit:ChangeMovesRemaining(10) end
	end)
	print(string.format("CLSM: multi-attack restore after %s used=%d/%d level=%d",
		tostring(reason), used, maxAtk, GetOrstedLevel(pUnit)))
end

local function OnCombat(combatResult)
	if combatResult == nil then return end
	local attacker = combatResult[CombatResultParameters.ATTACKER]
	if attacker == nil then return end
	local attackerID = attacker[CombatResultParameters.ID]
	if attackerID == nil then return end
	local pUnit = UnitManager.GetUnit(attackerID.player, attackerID.id)
	if not IsOrsted(pUnit) then return end

	local used = (pUnit:GetProperty(PROP_ATK_USED) or 0) + 1
	pUnit:SetProperty(PROP_ATK_USED, used)
	local maxAtk = GetMaxAttacks(pUnit)
	print(string.format("CLSM: Orsted combat resolved attack #%d/%d", used, maxAtk))

	-- GodBlade city capture assist if defender was a district/city
	local defender = combatResult[CombatResultParameters.DEFENDER]
	if defender ~= nil then
		local defID = defender[CombatResultParameters.ID]
		if defID ~= nil then
			-- city/district damage path already handled; try capture if city center adjacent
			local x = pUnit:GetX()
			local y = pUnit:GetY()
			for dir = 0, 5 do
				local adj = Map.GetAdjacentPlot(x, y, dir)
				if adj ~= nil then
					local pCity = Cities.GetCityInPlot(adj:GetX(), adj:GetY())
					if pCity ~= nil and pCity:GetOwner() ~= pUnit:GetOwner() then
						GodBladeSmashCity(pCity, pUnit:GetOwner(), pUnit)
					end
				end
			end
			local here = Cities.GetCityInPlot(x, y)
			if here ~= nil and here:GetOwner() ~= pUnit:GetOwner() then
				GodBladeSmashCity(here, pUnit:GetOwner(), pUnit)
			end
		end
	end

	if used < maxAtk then
		RestoreOrstedForNextAttack(pUnit, "combat")
	end
end
Events.Combat.Add(OnCombat)

function OnUnitMoved(playerID, unitID, x, y)
	local pUnit = UnitManager.GetUnit(playerID, unitID)
	if not IsOrsted(pUnit) then return end
	-- Do not auto-smash merely by walking; capture/smash stays combat-driven to avoid accidents.
end
Events.UnitMoved.Add(OnUnitMoved)

function OnUnitPromoted(playerID, unitID)
	local pUnit = UnitManager.GetUnit(playerID, unitID)
	if IsOrsted(pUnit) then
		RefreshOrstedUnit(pUnit)
		-- Fresh promotion mid-turn: allow remaining multi-attacks to use new budget
		RestoreOrstedForNextAttack(pUnit, "promoted")
	end
end
Events.UnitPromoted.Add(OnUnitPromoted)

function OnPlayerTurnActivated(playerID, isFirstTime)
	local pPlayer = Players[playerID]
	if pPlayer == nil then return end
	local pUnits = pPlayer:GetUnits()
	if pUnits == nil then return end
	for _, pUnit in pUnits:Members() do
		if IsOrsted(pUnit) then
			RefreshOrstedUnit(pUnit)
			pUnit:SetProperty(PROP_ATK_USED, 0)
			-- Ensure full moves at turn start
			pcall(function() UnitManager.RestoreMovement(pUnit) end)
			pcall(function() UnitManager.RestoreUnitAttacks(pUnit) end)
		end
	end
end
Events.PlayerTurnActivated.Add(OnPlayerTurnActivated)

function OnLoadScreenClose()
	RefreshAllOrsteds("LoadScreenClose")
end
Events.LoadScreenClose.Add(OnLoadScreenClose)

function OnLoadGameViewStateDone()
	RefreshAllOrsteds("LoadGameViewStateDone")
end
Events.LoadGameViewStateDone.Add(OnLoadGameViewStateDone)

print("CLSM: handlers registered v2 (multi-attack + city capture)")

-- immediate_refresh_after_register (load events may already have fired)
print("CLSM: immediate refresh after register")
pcall(function() RefreshAllOrsteds("immediate_after_register") end)