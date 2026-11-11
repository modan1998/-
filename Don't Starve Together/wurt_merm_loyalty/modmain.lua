local _G = GLOBAL

local function GetConfig(name, default)
    local val = GetModConfigData(name)
    if val == nil then
        return default
    end
    return val
end

local ONLY_WURT = GetConfig("only_wurt", true)
local INCLUDE_GUARDS = GetConfig("include_guards", true)

-- DST TILE_SCALE is 4 world units per tile (constants.lua).
local TILE_SCALE = _G.TILE_SCALE or 4
local SECOND_FEED_RANGE = 10 * TILE_SCALE -- 10 tiles = 40 units
local SECOND_FEED_RANGE_SQ = SECOND_FEED_RANGE * SECOND_FEED_RANGE

local HINTS = {
    no_king = "需要鱼人王存在，才能第二次喂食月亮碎片。",
    no_fortress = "需要先建造鱼人堡垒，才能第二次喂食月亮碎片。",
    too_far = "必须在鱼人王10个地皮范围内，才能第二次喂食月亮碎片。",
}

local function IsPlayerLeader(leader)
    return leader ~= nil and leader:IsValid() and leader:HasTag("player")
end

local function IsWurt(leader)
    return leader ~= nil and leader.prefab == "wurt"
end

local function ShouldKeepForever(inst)
    local follower = inst.components and inst.components.follower
    if follower == nil then
        return false
    end
    local leader = follower.leader or (follower.GetLeader ~= nil and follower:GetLeader()) or nil
    if not IsPlayerLeader(leader) then
        return false
    end
    if ONLY_WURT and not IsWurt(leader) then
        return false
    end
    return true
end

local function ApplyNeverExpire(inst)
    if not _G.TheWorld or not _G.TheWorld.ismastersim then
        return
    end
    local follower = inst.components and inst.components.follower
    if follower == nil then
        return
    end
    if ShouldKeepForever(inst) then
        follower.neverexpire = true
        follower.keepdeadleader = true
        if follower.KeepLeaderOnAttacked ~= nil then
            follower:KeepLeaderOnAttacked()
        end
        if follower.CancelLoyaltyTask ~= nil then
            follower:CancelLoyaltyTask()
        end
    end
end

local function IsGuardMerm(inst)
    return inst ~= nil and inst:IsValid() and (inst:HasTag("mermguard") or inst:HasTag("guard"))
end

local function IsLunarMerm(inst)
    return inst ~= nil and inst:IsValid() and (inst:HasTag("lunarminion") or inst.prefab == "merm_lunar")
end

local function GetFeedCount(inst)
    if inst == nil or not inst:IsValid() then
        return 0
    end
    local stored = inst.wurt_moonglass_feeds or 0
    -- Already lunar-mutated (vanilla first-feed or other mutation path) counts as first feed.
    if IsLunarMerm(inst) then
        return math.max(stored, 1)
    end
    return stored
end

local function SetFeedCount(inst, count)
    if inst ~= nil and inst:IsValid() then
        inst.wurt_moonglass_feeds = count
    end
end

local function HookPersistFeedCount(inst)
    if inst._wurt_feedcount_save_hooked then
        return
    end
    inst._wurt_feedcount_save_hooked = true

    local old_OnSave = inst.OnSave
    inst.OnSave = function(merm, data)
        if old_OnSave ~= nil then
            old_OnSave(merm, data)
        end
        if data ~= nil and merm.wurt_moonglass_feeds ~= nil and merm.wurt_moonglass_feeds > 0 then
            data.wurt_moonglass_feeds = merm.wurt_moonglass_feeds
        end
    end

    local old_OnPreLoad = inst.OnPreLoad
    inst.OnPreLoad = function(merm, data, ents)
        if data ~= nil and data.wurt_moonglass_feeds ~= nil then
            merm.wurt_moonglass_feeds = data.wurt_moonglass_feeds
        end
        if old_OnPreLoad ~= nil then
            old_OnPreLoad(merm, data, ents)
        end
    end
end

local function FindMermKing()
    local mgr = _G.TheWorld and _G.TheWorld.components and _G.TheWorld.components.mermkingmanager
    if mgr ~= nil then
        if mgr.HasKingLocal ~= nil and mgr:HasKingLocal() and mgr.GetKing ~= nil then
            local king = mgr:GetKing()
            if king ~= nil and king:IsValid() then
                return king
            end
        end
        if mgr.GetKing ~= nil then
            local king = mgr:GetKing()
            if king ~= nil and king:IsValid() then
                local health = king.components and king.components.health
                if health == nil or not health:IsDead() then
                    return king
                end
            end
        end
    end
    if _G.Ents ~= nil then
        for _, ent in pairs(_G.Ents) do
            if ent ~= nil and ent:IsValid() and ent.prefab == "mermking" then
                local health = ent.components and ent.components.health
                if health == nil or not health:IsDead() then
                    return ent
                end
            end
        end
    end
    return nil
end

local function FindFortress()
    if _G.Ents == nil then
        return nil
    end
    for _, ent in pairs(_G.Ents) do
        if ent ~= nil and ent:IsValid() and ent.prefab == "mermwatchtower" and not ent:HasTag("burnt") then
            return ent
        end
    end
    return nil
end

-- Returns ok, reason. Range is 10 tiles (TILE_SCALE 4 => 40 units) from the local Merm King.
local function CanSecondFeed(inst)
    local king = FindMermKing()
    if king == nil then
        return false, "no_king"
    end
    if FindFortress() == nil then
        return false, "no_fortress"
    end
    local dx, dy, dz = inst.Transform:GetWorldPosition()
    local kx, ky, kz = king.Transform:GetWorldPosition()
    local dsq = (dx - kx) * (dx - kx) + (dz - kz) * (dz - kz)
    if dsq > SECOND_FEED_RANGE_SQ then
        return false, "too_far"
    end
    return true, "ok"
end

local function HintSecondFeed(inst, giver, reason)
    local msg = HINTS[reason] or reason
    local talker = (giver ~= nil and giver.components and giver.components.talker)
        or (inst ~= nil and inst.components and inst.components.talker)
    if talker ~= nil and talker.Say ~= nil then
        talker:Say(msg)
    end
end

local function ReturnItemToGiver(inst, item, giver)
    if item == nil or not item:IsValid() then
        return
    end
    local owner = giver
    if owner == nil or not owner:IsValid() then
        local follower = inst.components and inst.components.follower
        owner = follower and (follower.GetLeader ~= nil and follower:GetLeader() or follower.leader) or nil
    end
    if inst.components ~= nil and inst.components.inventory ~= nil then
        inst.components.inventory:RemoveItem(item, true)
    end
    if not item:IsValid() then
        return
    end
    if owner ~= nil and owner:IsValid() and owner.components ~= nil and owner.components.inventory ~= nil then
        owner.components.inventory:GiveItem(item)
        return
    end
    local x, y, z = inst.Transform:GetWorldPosition()
    if item.Transform ~= nil then
        item.Transform:SetPosition(x, 0, z)
    end
end

local function PrefabExists(name)
    return name ~= nil and _G.Prefabs ~= nil and _G.Prefabs[name] ~= nil
end

local function PickWarriorPrefab(inst)
    if inst:HasTag("lunarminion") or inst.prefab == "merm_lunar" then
        if PrefabExists("mermguard_lunar") then
            return "mermguard_lunar"
        end
    elseif inst:HasTag("shadowminion") or inst.prefab == "merm_shadow" then
        if PrefabExists("mermguard_shadow") then
            return "mermguard_shadow"
        end
    elseif inst.prefab == "merm_loyal" and PrefabExists("mermguard_loyal") then
        return "mermguard_loyal"
    end
    return "mermguard"
end

-- Spawn a real vanilla guard prefab, transferring position, leader, loyalty, inventory, health, home.
local function TransformToWarrior(inst)
    if inst == nil or not inst:IsValid() then
        return nil
    end

    local prefab = PickWarriorPrefab(inst)
    local warrior = _G.SpawnPrefab(prefab)
    if warrior == nil or not warrior:IsValid() then
        print("[LOYALTY_GUARD] failed to spawn warrior prefab=" .. tostring(prefab))
        return nil
    end

    warrior.Transform:SetPosition(inst.Transform:GetWorldPosition())
    warrior.Transform:SetRotation(inst.Transform:GetRotation())

    if inst.components.health ~= nil and warrior.components.health ~= nil and inst.components.health.TransferComponent ~= nil then
        inst.components.health:TransferComponent(warrior)
    end
    if inst.components.inventory ~= nil and warrior.components.inventory ~= nil and inst.components.inventory.TransferComponent ~= nil then
        inst.components.inventory:TransferComponent(warrior)
    end

    local leader = inst.components.follower ~= nil and inst.components.follower:GetLeader() or nil
    if leader ~= nil and leader:IsValid() and leader.components.leader ~= nil then
        leader.components.leader:AddFollower(warrior)
    elseif warrior.components.follower ~= nil and leader ~= nil and leader:IsValid() then
        warrior.components.follower:SetLeader(leader)
    end

    local home = inst.components.homeseeker ~= nil and inst.components.homeseeker:GetHome() or nil
    inst:PushEvent("detachchild")
    if home ~= nil and home:IsValid() and home.components.childspawner ~= nil then
        home.components.childspawner:TakeOwnership(warrior)
    end

    if inst.components.combat ~= nil and warrior.components.combat ~= nil then
        warrior.components.combat:SetTarget(inst.components.combat.target)
    end

    SetFeedCount(warrior, 2)
    ApplyNeverExpire(warrior)

    warrior:PushEvent("mutated", { oldbuild = inst.AnimState ~= nil and inst.AnimState:GetBuild() or nil })

    print(string.format(
        "[LOYALTY_GUARD] transformed %s -> %s feeds=2 neverexpire=%s keepdeadleader=%s leader=%s",
        tostring(inst.prefab),
        tostring(warrior.prefab),
        tostring(warrior.components.follower ~= nil and warrior.components.follower.neverexpire),
        tostring(warrior.components.follower ~= nil and warrior.components.follower.keepdeadleader),
        tostring(leader and leader.prefab)
    ))

    if _G.TheWorld ~= nil then
        _G.TheWorld._wurt_last_moonglass_result = warrior
    end
    inst:Remove()
    return warrior
end

local function HookTraderSecondFeed(inst)
    local trader = inst.components and inst.components.trader
    if trader == nil or trader.test == nil or inst._wurt_moonglass_trader_hooked then
        return
    end
    inst._wurt_moonglass_trader_hooked = true

    local old_test = trader.test
    trader:SetAcceptTest(function(merm, item, giver, count)
        if item ~= nil and item:HasTag("moonglass_piece") then
            local feeds = GetFeedCount(merm)
            if feeds >= 1 and not IsGuardMerm(merm) then
                local follower = merm.components and merm.components.follower
                local leader = follower and (follower.GetLeader ~= nil and follower:GetLeader() or follower.leader) or nil
                if giver ~= nil and leader == giver then
                    local ok, reason = CanSecondFeed(merm)
                    if not ok then
                        HintSecondFeed(merm, giver, reason)
                        print(string.format(
                            "[LOYALTY_GUARD] second feed rejected: %s prefab=%s feeds=%s",
                            tostring(reason), tostring(merm.prefab), tostring(feeds)
                        ))
                        return false
                    end
                    print(string.format(
                        "[LOYALTY_GUARD] second feed accepted (conditions met) prefab=%s feeds=%s range=%s",
                        tostring(merm.prefab), tostring(feeds), tostring(SECOND_FEED_RANGE)
                    ))
                    return true
                end
            end
        end
        return old_test(merm, item, giver, count)
    end)

    local old_onaccept = trader.onaccept
    trader.onaccept = function(merm, giver, item, count)
        if item ~= nil and item:IsValid() and item:HasTag("moonglass_piece")
            and (GetFeedCount(merm) >= 1 or IsLunarMerm(merm))
            and not IsGuardMerm(merm)
        then
            local ok, reason = CanSecondFeed(merm)
            if ok then
                local warrior = TransformToWarrior(merm)
                if item:IsValid() then
                    item:Remove()
                end
                return warrior
            end
            HintSecondFeed(merm, giver, reason)
            ReturnItemToGiver(merm, item, giver)
            return
        end
        if old_onaccept ~= nil then
            old_onaccept(merm, giver, item, count)
        end
    end
end

local function HookMutation(inst)
    if inst._wurt_moonglass_mutation_hooked then
        return
    end
    inst._wurt_moonglass_mutation_hooked = true

    if inst.DoLunarMutation ~= nil then
        local old_Do = inst.DoLunarMutation
        inst.DoLunarMutation = function(merm)
            local count = merm.wurt_moonglass_feeds
            if count == nil then
                count = GetFeedCount(merm)
            end
            local pending = merm._wurt_pending_moonglass_feed
            merm._wurt_pending_moonglass_feed = nil
            local newmerm = old_Do(merm)
            if newmerm ~= nil and newmerm:IsValid() then
                if pending then
                    SetFeedCount(newmerm, math.max(count or 0, 0) + 1)
                else
                    -- Other mutation paths (e.g. terraformer): already lunar-upgraded.
                    SetFeedCount(newmerm, math.max(count or 0, 1))
                end
                ApplyNeverExpire(newmerm)
                if _G.TheWorld ~= nil then
                    _G.TheWorld._wurt_last_moonglass_result = newmerm
                end
                print(string.format(
                    "[LOYALTY_GUARD] first-feed/lunar mutate %s -> %s feeds=%s neverexpire=%s keepdeadleader=%s",
                    tostring(merm.prefab),
                    tostring(newmerm.prefab),
                    tostring(newmerm.wurt_moonglass_feeds),
                    tostring(newmerm.components.follower ~= nil and newmerm.components.follower.neverexpire),
                    tostring(newmerm.components.follower ~= nil and newmerm.components.follower.keepdeadleader)
                ))
            end
            return newmerm
        end
    end

    if inst.TestForLunarMutation ~= nil then
        local old_Test = inst.TestForLunarMutation
        inst.TestForLunarMutation = function(merm, item)
            if item ~= nil and item:IsValid() and item:HasTag("moonglass_piece") then
                local feeds = GetFeedCount(merm)
                -- Never run vanilla remutation on an already-lunar merm.
                if (feeds >= 1 or IsLunarMerm(merm)) and not IsGuardMerm(merm) then
                    local follower = merm.components and merm.components.follower
                    local leader = follower and (follower.GetLeader ~= nil and follower:GetLeader() or follower.leader) or nil
                    local ok, reason = CanSecondFeed(merm)
                    if not ok then
                        HintSecondFeed(merm, leader, reason)
                        print(string.format(
                            "[LOYALTY_GUARD] second feed rejected at eat: %s prefab=%s feeds=%s",
                            tostring(reason), tostring(merm.prefab), tostring(feeds)
                        ))
                        ReturnItemToGiver(merm, item, leader)
                        return
                    end
                    local warrior = TransformToWarrior(merm)
                    if item:IsValid() then
                        item:Remove()
                    end
                    if warrior == nil then
                        print("[LOYALTY_GUARD] second feed transform failed")
                    end
                    return warrior
                end

                if IsLunarMerm(merm) or IsGuardMerm(merm) then
                    print(string.format(
                        "[LOYALTY_GUARD] ignoring extra moonglass on %s feeds=%s guard=%s",
                        tostring(merm.prefab), tostring(feeds), tostring(IsGuardMerm(merm))
                    ))
                    ReturnItemToGiver(merm, item, nil)
                    return merm
                end

                -- Vanilla first-feed path (wurt_lunar_allegiance_1, merm -> merm_lunar).
                merm._wurt_pending_moonglass_feed = true
            end
            if old_Test ~= nil then
                old_Test(merm, item)
            end
            return _G.TheWorld and _G.TheWorld._wurt_last_moonglass_result or nil
        end
    end
end

local function WatchMerm(inst)
    if not _G.TheWorld or not _G.TheWorld.ismastersim then
        return
    end
    if inst.components == nil or inst.components.follower == nil then
        return
    end

    inst:ListenForEvent("startfollowing", function()
        ApplyNeverExpire(inst)
    end)
    inst:ListenForEvent("gainloyalty", function()
        ApplyNeverExpire(inst)
    end)
    inst:ListenForEvent("leaderchanged", function()
        ApplyNeverExpire(inst)
    end)
    inst:ListenForEvent("entitywake", function()
        ApplyNeverExpire(inst)
    end)

    HookPersistFeedCount(inst)
    HookTraderSecondFeed(inst)
    HookMutation(inst)

    inst:DoTaskInTime(0, function()
        ApplyNeverExpire(inst)
    end)
end

AddPrefabPostInit("merm", WatchMerm)
AddPrefabPostInit("merm_loyal", WatchMerm)

if INCLUDE_GUARDS then
    AddPrefabPostInit("mermguard", WatchMerm)
    AddPrefabPostInit("mermguard_loyal", WatchMerm)
end

for _, prefab in ipairs({
    "merm_shadow", "merm_lunar",
    "mermguard_shadow", "mermguard_lunar",
    "merm_mutated", "mermguard_mutated",
}) do
    AddPrefabPostInit(prefab, WatchMerm)
end

local function SetupPlayer(inst)
    if not _G.TheWorld or not _G.TheWorld.ismastersim then
        return
    end

    if ONLY_WURT and inst.prefab ~= "wurt" then
        return
    end

    if inst.components.wurt_merm_migrate == nil then
        inst:AddComponent("wurt_merm_migrate")
    end

    local function RefreshFollowers()
        if inst.components.leader == nil then
            return
        end
        for follower, _ in pairs(inst.components.leader.followers) do
            if follower ~= nil and follower:IsValid() then
                ApplyNeverExpire(follower)
            end
        end
    end

    inst:ListenForEvent("ms_respawnedfromghost", RefreshFollowers)
    inst:ListenForEvent("respawnfromghost", RefreshFollowers)
    inst:ListenForEvent("playeractivated", function()
        inst:DoTaskInTime(0.5, RefreshFollowers)
    end)

    if inst._wurt_merm_loyalty_despawn_hooked then
        return
    end
    inst._wurt_merm_loyalty_despawn_hooked = true

    local old_OnDespawn = inst.OnDespawn
    inst.OnDespawn = function(player, migrationdata)
        if migrationdata ~= nil and player.components.wurt_merm_migrate ~= nil then
            player.components.wurt_merm_migrate:CaptureFollowersForMigration()
        end
        if old_OnDespawn ~= nil then
            old_OnDespawn(player, migrationdata)
        end
        if migrationdata ~= nil and player.components.wurt_merm_migrate ~= nil then
            player.components.wurt_merm_migrate:RemoveCapturedFollowers()
        end
    end
end

AddPlayerPostInit(SetupPlayer)

AddComponentPostInit("follower", function(self)
    if not _G.TheWorld or not _G.TheWorld.ismastersim then
        return
    end
    local old_LongUpdate = self.LongUpdate
    self.LongUpdate = function(comp, dt)
        if old_LongUpdate ~= nil then
            old_LongUpdate(comp, dt)
        end
        if comp.inst ~= nil then
            ApplyNeverExpire(comp.inst)
        end
    end
end)

print("[wurt_merm_loyalty] v1.3.0 loaded (neverexpire + keepdeadleader + cave migrate + moonglass guard upgrade)")
