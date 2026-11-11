--[[
  全人物天赋点亮
  - client_only：改 TheSkillTree / TheGenericKV（账号侧）
  - 动态扫描 SKILLTREE_DEFS，新角色上线后无需改名单
  注意：DST 模组环境无 GLOBAL.pcall，不要直接用裸 pcall
]]

local _G = GLOBAL

local function GetConfig(name, default)
    local val = GetModConfigData(name)
    if val == nil then
        return default
    end
    return val
end

local function SafeRequire(path)
    local ok, mod = _G.pcall(_G.require, path)
    if ok then
        return mod
    end
    return nil
end

local function CollectCharacterPrefabs()
    local chars = {}
    local seen = {}

    local defs = SafeRequire("prefabs/skilltree_defs")
    if defs and defs.SKILLTREE_DEFS then
        for prefab, treedef in pairs(defs.SKILLTREE_DEFS) do
            if type(prefab) == "string" and treedef ~= nil and not seen[prefab] then
                seen[prefab] = true
                table.insert(chars, prefab)
            end
        end
    end

    if #chars == 0 then
        local fallback = {
            "wilson", "willow", "wolfgang", "wendy", "wx78", "woodie",
            "wathgrithr", "winona", "wortox", "wormwood", "wurt", "walter",
        }
        for _, prefab in ipairs(fallback) do
            table.insert(chars, prefab)
        end
    end

    table.sort(chars)
    return chars, defs
end

local function UnlockAffinityAndQuests()
    local TheGenericKV = _G.TheGenericKV
    if TheGenericKV == nil or TheGenericKV.SetKV == nil then
        return
    end

    local bool_keys = {
        "fuelweaver_killed",
        "celestialchampion_killed",
        "wathgrithr_container_unlocked",
        "wathgrithr_horn_played",
    }

    for _, key in ipairs(bool_keys) do
        _G.pcall(function()
            TheGenericKV:SetKV(key, "1")
        end)
    end

    local song_uses = 10
    if _G.TUNING and _G.TUNING.SKILLS and _G.TUNING.SKILLS.WATHGRITHR
        and _G.TUNING.SKILLS.WATHGRITHR.INSTANTSONG_CD_UNLOCK_COUNT then
        song_uses = _G.TUNING.SKILLS.WATHGRITHR.INSTANTSONG_CD_UNLOCK_COUNT
    end
    _G.pcall(function()
        TheGenericKV:SetKV("wathgrithr_instantsong_uses", tostring(song_uses))
    end)
end

local function MaxInsightFor(prefab, maxxp)
    local TheSkillTree = _G.TheSkillTree
    if TheSkillTree == nil or TheSkillTree.AddSkillXP == nil then
        return false
    end

    local ok = _G.pcall(function()
        TheSkillTree:AddSkillXP(maxxp, prefab)
        if TheSkillTree.UpdateSaveState ~= nil then
            TheSkillTree:UpdateSaveState(prefab)
        end
    end)
    return ok
end

local function TryActivateAllNodes(prefab, defs)
    local TheSkillTree = _G.TheSkillTree
    if TheSkillTree == nil or defs == nil or defs.SKILLTREE_DEFS == nil then
        return 0
    end
    local tree = defs.SKILLTREE_DEFS[prefab]
    if type(tree) ~= "table" then
        return 0
    end

    local old_skip = TheSkillTree.skip_validation
    TheSkillTree.skip_validation = true

    local count = 0
    for skillname, skilldef in pairs(tree) do
        if type(skillname) == "string" and type(skilldef) == "table" and skilldef.lock_open == nil then
            local ok = _G.pcall(function()
                if TheSkillTree.ActivateSkill ~= nil then
                    TheSkillTree:ActivateSkill(skillname, prefab)
                end
            end)
            if ok then
                count = count + 1
            end
        end
    end

    TheSkillTree.skip_validation = old_skip
    if TheSkillTree.UpdateSaveState ~= nil then
        _G.pcall(function()
            TheSkillTree:UpdateSaveState(prefab)
        end)
    end
    return count
end

local function UnlockAllSkills()
    local TheSkillTree = _G.TheSkillTree
    if TheSkillTree == nil then
        print("[全人物天赋点亮] TheSkillTree 尚未就绪，稍后重试")
        return false
    end

    local maxxp = 160
    if TheSkillTree.GetMaximumExperiencePoints ~= nil then
        local ok, val = _G.pcall(function()
            return TheSkillTree:GetMaximumExperiencePoints()
        end)
        if ok and type(val) == "number" and val > 0 then
            maxxp = val
        end
    end

    local chars, defs = CollectCharacterPrefabs()
    local done = 0
    for _, prefab in ipairs(chars) do
        if MaxInsightFor(prefab, maxxp) then
            done = done + 1
            if GetConfig("activate_all_nodes", false) then
                TryActivateAllNodes(prefab, defs)
            end
        end
    end

    UnlockAffinityAndQuests()

    if GetConfig("announce", true) then
        print(string.format("[全人物天赋点亮] 已处理 %d 个角色的洞察进度（maxxp=%s）", done, tostring(maxxp)))
    end
    return true
end

_G.UnlockAllSkills = UnlockAllSkills

local function ScheduleUnlock(delay)
    if not GetConfig("auto_unlock", true) then
        return
    end
    if _G.scheduler == nil or _G.scheduler.ExecuteInTime == nil then
        UnlockAllSkills()
        return
    end
    _G.scheduler:ExecuteInTime(delay or 1, function()
        if not UnlockAllSkills() then
            _G.scheduler:ExecuteInTime(2, UnlockAllSkills)
        end
    end)
end

AddGamePostInit(function()
    ScheduleUnlock(1)
end)
