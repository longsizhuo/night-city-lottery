-- Temporary, bounded teams for gameplay testing and recording real combat.
local Battle = {}
local TAG = "CodexRandomAlly_Stage_v1"
local ASSEMBLY_GOD = "NCL_Assembly"
local FILM_GOD = "NCL_Filming"

function Battle.new(ctx)
  local self = {actors = {}, queue = {}, pending = nil, phase = "idle", timer = 0,
                tick = 0, initialized = false, sustain = false, message = "演示小队待命。"}

  local function message(value)
    self.message = value
    print("[NightCityLottery/Stage] " .. value)
  end

  local function valid(system, id)
    return id and system:IsManaged(id) and system:IsTagged(id, TAG)
  end

  local function entity(system, actor)
    if not valid(system, actor.id) then return nil end
    local npc = system:GetEntity(actor.id)
    return npc and npc:IsAttached() and npc or nil
  end

  local function setGod(npc, key, enabled)
    local gods = Game.GetGodModeSystem()
    if enabled then gods:AddGodMode(npc:GetEntityID(), gameGodModeType.Immortal, CName.new(key))
    else gods:ClearGodMode(npc:GetEntityID(), CName.new(key)) end
  end

  local function sceneAllowed(player)
    if player:IsDead() then return false, "角色已死亡，请先读档。" end
    if Game.GetWorkspotSystem():IsActorInWorkspot(player) then return false, "请先离开载具或剧情动作。" end
    local defs = Game.GetAllBlackboardDefs().PlayerStateMachine
    local board = Game.GetBlackboardSystem():GetLocalInstanced(player:GetEntityID(), defs)
    if not board or board:GetInt(defs.SceneTier) > 1 then return false, "请在剧情演出结束后使用演示小队。" end
    return true
  end

  local function pointFor(player, team, index)
    local p, f = player:GetWorldPosition(), player:GetWorldForward()
    local row = math.floor((index - 1) / 4)
    local lateral = ((index - 1) % 4 - 1.5) * 1.8
    local forward = (team == "ally" and 2.5 or 10) + row * 2
    local queries = Game.GetSpatialQueriesSystem()
    for attempt = 0, 15 do
      local jitter = attempt > 0 and (math.floor((attempt + 1) / 2) * 0.65 * (attempt % 2 == 0 and -1 or 1)) or 0
      local distance = forward + math.floor(attempt / 6)
      local x = p.x + f.x * distance + f.y * (lateral + jitter)
      local y = p.y + f.y * distance - f.x * (lateral + jitter)
      local from = Vector4.new(x, y, p.z + 1.8, 1)
      local to = Vector4.new(x, y, p.z - 2, 1)
      for _, group in ipairs({"Static", "Terrain"}) do
        local hit, result = queries:SyncRaycastByCollisionGroup(from, to, group, false, false)
        if hit and result then
          local pos, normal = ToVector4(result.position), ToVector4(result.normal)
          if normal.z > 0.75 and math.abs(pos.z - p.z) < 1.8 then
            return Vector4.new(pos.x, pos.y, pos.z + 0.15, 1)
          end
        end
      end
    end
    return nil
  end

  function self:clear()
    local system = ctx.backend()
    self.queue, self.pending = {}, nil
    if system then
      for _, id in ipairs(system:GetTaggedIDs(TAG)) do
        if valid(system, id) then
          local npc = system:GetEntity(id)
          if npc and npc:IsAttached() then
            pcall(setGod, npc, ASSEMBLY_GOD, false)
            pcall(setGod, npc, FILM_GOD, false)
          end
          system:DeleteEntity(id)
        end
      end
    end
    self.actors, self.phase = {}, "idle"
    message("演示小队已清理。")
    return true
  end

  function self:start(count, foes)
    local system, player, err = ctx.backend()
    if not system then message(err or "场景未就绪。"); return false end
    local allowed, why = sceneAllowed(player)
    if not allowed then message(why); return false end
    count = math.max(1, math.min(8, math.floor(tonumber(count) or 4)))
    foes = math.max(0, math.min(8, math.floor(tonumber(foes) or 0)))
    local available = {}
    for _, entry in ipairs(ctx.pool) do
      if TweakDB:GetRecord(entry.record) then available[#available + 1] = entry end
    end
    if #available == 0 then message("候选 NPC 不可用。"); return false end
    self:clear()
    self.initialized = true
    self.timer, self.tick = 0, 0
    for _, team in ipairs({"ally", "foe"}) do
      for i = 1, team == "ally" and count or foes do
        self.queue[#self.queue + 1] = {team = team, index = i, selected = available[math.random(#available)]}
      end
    end
    self.phase = "assembling"
    message(string.format("正在分批集结：我方 %d 人 / 对方 %d 人。", count, foes))
    return true
  end

  local function setHostile(npc, player)
    local controller = npc:GetAIControllerComponent()
    local role = controller:GetAIRole()
    if role then role:OnRoleCleared(npc) end
    controller:SetAIRole(AINoRole.new())
    controller:OnAttach()
    npc:GetAttitudeAgent():SetAttitudeGroup("Hostile")
    npc:GetAttitudeAgent():SetAttitudeTowards(player:GetAttitudeAgent(), EAIAttitude.AIA_Hostile)
    npc.isPlayerCompanionCached = false
    npc.isPlayerCompanionCachedTimeStamp = 0
  end

  local function trigger(npc, target)
    if npc:IsDead() or target:IsDead() then return end
    local reaction = npc.reactionComponent
    if not reaction then return end
    local preset = TweakDBInterface.GetReactionPresetRecord(TweakDBID.new("ReactionPresets.Ganger_Aggressive"))
    reaction:SetReactionPreset(preset)
    reaction:TriggerCombat(target)
  end

  local function engage(system)
    local allies, foes = {}, {}
    for _, actor in ipairs(self.actors) do
      local npc = entity(system, actor)
      if npc and not npc:IsDead() then
        local list = actor.team == "ally" and allies or foes
        list[#list + 1] = npc
      end
    end
    for _, ally in ipairs(allies) do
      for _, foe in ipairs(foes) do
        ally:GetAttitudeAgent():SetAttitudeTowards(foe:GetAttitudeAgent(), EAIAttitude.AIA_Hostile)
        foe:GetAttitudeAgent():SetAttitudeTowards(ally:GetAttitudeAgent(), EAIAttitude.AIA_Hostile)
      end
    end
    for i, ally in ipairs(allies) do if #foes > 0 then trigger(ally, foes[(i - 1) % #foes + 1]) end end
    for i, foe in ipairs(foes) do if #allies > 0 then trigger(foe, allies[(i - 1) % #allies + 1]) end end
  end

  local function releaseTeams(system, player)
    for _, actor in ipairs(self.actors) do
      local npc = entity(system, actor)
      if npc then
        if actor.team == "foe" then setHostile(npc, player) end
        setGod(npc, FILM_GOD, self.sustain)
        setGod(npc, ASSEMBLY_GOD, false)
      end
    end
    -- Same-camp units stay friendly to each other, including mixed original factions.
    for _, actor in ipairs(self.actors) do
      local npc = entity(system, actor)
      if npc then
        for _, other in ipairs(self.actors) do
          local friend = actor.team == other.team and entity(system, other) or nil
          if friend then npc:GetAttitudeAgent():SetAttitudeTowards(friend:GetAttitudeAgent(), EAIAttitude.AIA_Friendly) end
        end
      end
    end
    self.phase, self.tick = "active", 0
    engage(system)
    message("小队已就位，正在交战。F8 可清理全部演示 NPC。")
  end

  function self:update(delta)
    local ok, err = pcall(function()
      local system, player = ctx.backend()
      if not system then self.actors, self.queue, self.pending, self.phase, self.initialized = {}, {}, nil, "idle", false; return end
      if not self.initialized then self:clear(); self.initialized = true end
      self.timer, self.tick = self.timer + delta, self.tick + delta
      if self.pending then
        self.pending.age = self.pending.age + delta
        local npc = system:GetEntity(self.pending.id)
        if npc and npc:IsAttached() then
          -- Everyone starts friendly and protected while the complete teams are assembled.
          ctx.makeFollower(npc, player)
          setGod(npc, ASSEMBLY_GOD, true)
          self.actors[#self.actors + 1] = self.pending
          self.pending = nil
        elseif self.pending.age > 15 then
          if valid(system, self.pending.id) then system:DeleteEntity(self.pending.id) end
          self.pending = nil
          message("一名 NPC 加载超时，已跳过。")
        end
      elseif self.phase == "assembling" and self.timer >= 0.4 then
        self.timer = 0
        if #system:GetTaggedIDs(TAG) > #self.actors then return end
        local job = table.remove(self.queue, 1)
        if job then
          local point = pointFor(player, job.team, job.index)
          if point then
            local spec = DynamicEntitySpec.new()
            spec.recordID, spec.position, spec.orientation = TweakDBID.new(job.selected.record), point, player:GetWorldOrientation()
            spec.tags = {TAG}
            spec.persistSpawn, spec.persistState, spec.alwaysSpawned, spec.spawnInView, spec.active = false, false, true, true, true
            job.id, job.age = system:CreateEntity(spec), 0
            self.pending = job
          else message("附近一处落点不合适，已跳过该演员。") end
        else releaseTeams(system, player) end
      end
      if self.phase == "active" and self.tick >= 4 then
        self.tick = 0
        engage(system)
      end
    end)
    if not ok then
      pcall(function() self:clear() end)
      self.phase = "error"
      message("演示暂停: " .. tostring(err))
    end
  end

  function self:status()
    local system = ctx.backend()
    local data = {phase = self.phase, allies = 0, foes = 0, alive_allies = 0, alive_foes = 0,
                  pending = #self.queue + (self.pending and 1 or 0), sustain = self.sustain,
                  message = self.message, actors = {}}
    for _, actor in ipairs(self.actors) do
      local npc = system and entity(system, actor)
      if npc then
        local p = npc:GetWorldPosition()
        local hp = Game.GetStatPoolsSystem():GetStatPoolValue(npc:GetEntityID(), gamedataStatPoolType.Health, true)
        local entry = {team = actor.team, name = actor.selected.name, dead = npc:IsDead(), health_percent = hp,
                       in_combat = npc:IsInCombat(), position = {x=p.x,y=p.y,z=p.z}}
        data.actors[#data.actors + 1] = entry
        if actor.team == "ally" then
          data.allies = data.allies + 1; if not entry.dead then data.alive_allies = data.alive_allies + 1 end
        else data.foes = data.foes + 1; if not entry.dead then data.alive_foes = data.alive_foes + 1 end end
      end
    end
    return data
  end

  function self:draw()
    ImGui.Separator()
    ImGui.Text("多人演示小队（临时生成，上限 8 对 8）")
    ImGui.TextWrapped(self.message)
    if ImGui.Button("战斗增援：我方 4 人", 280, 34) then self:start(4, 0) end
    if ImGui.Button("4 对 4 演示交战", 260, 34) then self:start(4, 4) end
    ImGui.SameLine()
    if ImGui.Button("6 对 6 演示交战", 260, 34) then self:start(6, 6) end
    local selected, changed = ImGui.Checkbox("拍摄续航：演示 NPC 不死（仅本次生成）", self.sustain)
    if changed then
      self.sustain = selected
      local system = ctx.backend()
      if system then for _, actor in ipairs(self.actors) do local npc = entity(system, actor); if npc then pcall(setGod, npc, FILM_GOD, selected) end end end
    end
    if ImGui.Button("清理演示小队（F8 也可）", 360, 32) then self:clear() end
    local snapshot = self:status()
    ImGui.Text(string.format("我方 %d/%d 存活  |  对方 %d/%d 存活  |  待生成 %d", snapshot.alive_allies, snapshot.allies, snapshot.alive_foes, snapshot.foes, snapshot.pending))
  end

  return self
end

return Battle
