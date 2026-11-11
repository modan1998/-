-- Saves Wurt's loyal merms into the player session during shard migration,
-- then respawns them on the destination shard next to the player.
-- Feed-count (wurt_moonglass_feeds) is persisted via each merm's OnSave in the save record.

local WurtMermMigrate = Class(function(self, inst)
    self.inst = inst
    self.pending_records = nil
    self._captured = nil
    self.test_phase = nil -- carried across shards for automated tests
end)

local function IsMermPrefab(prefab)
    if prefab == nil then
        return false
    end
    return prefab == "merm"
        or prefab == "merm_loyal"
        or prefab == "mermguard"
        or prefab == "mermguard_loyal"
        or prefab == "merm_shadow"
        or prefab == "merm_lunar"
        or prefab == "mermguard_shadow"
        or prefab == "mermguard_lunar"
        or prefab == "merm_mutated"
        or prefab == "mermguard_mutated"
        or string.find(prefab, "merm", 1, true) ~= nil
end

function WurtMermMigrate:DetachHome(merm)
    if merm == nil or not merm:IsValid() then
        return
    end
    merm:PushEvent("detachchild")
    if merm.components.homeseeker ~= nil then
        if merm.components.homeseeker.SetHome ~= nil then
            merm.components.homeseeker:SetHome(nil)
        end
        merm:RemoveComponent("homeseeker")
    end
end

function WurtMermMigrate:CaptureFollowersForMigration()
    self.pending_records = nil
    self._captured = nil

    local leader = self.inst.components.leader
    if leader == nil or leader.followers == nil then
        return
    end

    local records = {}
    local captured = {}

    for follower, _ in pairs(leader.followers) do
        if follower ~= nil and follower:IsValid() and IsMermPrefab(follower.prefab) then
            self:DetachHome(follower)
            follower.temp_save_platform_pos = true
            local saved = follower:GetSaveRecord()
            follower.temp_save_platform_pos = nil
            if saved ~= nil then
                table.insert(records, saved)
                table.insert(captured, follower)
            end
        end
    end

    if #records > 0 then
        self.pending_records = records
        self._captured = captured
        print(string.format("[wurt_merm_loyalty] captured %d merm(s) for shard migration", #records))
    end
end

function WurtMermMigrate:RemoveCapturedFollowers()
    if self._captured == nil then
        return
    end
    for _, merm in ipairs(self._captured) do
        if merm ~= nil and merm:IsValid() then
            merm:Remove()
        end
    end
    self._captured = nil
end

function WurtMermMigrate:OnSave()
    local data = {}
    if self.pending_records ~= nil and #self.pending_records > 0 then
        data.merms = self.pending_records
    end
    if self.test_phase ~= nil then
        data.test_phase = self.test_phase
    end
    if next(data) ~= nil then
        return data
    end
end

local function ApplyPermanent(follower)
    if follower == nil or follower.components == nil or follower.components.follower == nil then
        return
    end
    local f = follower.components.follower
    f.neverexpire = true
    f.keepdeadleader = true
    if f.KeepLeaderOnAttacked ~= nil then
        f:KeepLeaderOnAttacked()
    end
    if f.CancelLoyaltyTask ~= nil then
        f:CancelLoyaltyTask()
    end
end

function WurtMermMigrate:OnLoad(data)
    if data == nil then
        return
    end
    if data.test_phase ~= nil then
        self.test_phase = data.test_phase
    end
    if data.merms == nil or #data.merms == 0 then
        return
    end

    local spawned = 0
    for _, record in ipairs(data.merms) do
        local merm = SpawnSaveRecord(record)
        if merm ~= nil and merm:IsValid() then
            self:DetachHome(merm)
            ApplyPermanent(merm)
            if self.inst.components.leader ~= nil then
                self.inst.components.leader:AddFollower(merm)
            elseif merm.components.follower ~= nil then
                merm.components.follower:SetLeader(self.inst)
            end
            ApplyPermanent(merm)
            if self.inst.migrationpets ~= nil then
                table.insert(self.inst.migrationpets, merm)
            end
            spawned = spawned + 1
        end
    end

    self.pending_records = nil
    print(string.format("[wurt_merm_loyalty] restored %d merm(s) after shard migration", spawned))
end

return WurtMermMigrate
