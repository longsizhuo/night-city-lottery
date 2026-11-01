-- Night City Lottery 0.2.0: random companions and bounded temporary combat teams.
-- Requires CET 1.38.1, Codeware 1.21.2, RED4ext 1.31.0, redscript 0.5.32.
-- Follower API reference: WolvenKit/cet-examples (MIT; see THIRD_PARTY.txt).
local pool = require("pool")
local VERSION = "0.2.0"
local TAG = "CodexRandomAlly_v1"
local state = {
  phase = "idle", message = "就绪。自由探索时抽取一位临时队友。",
  id = nil, pending = nil, selected = nil, previous = nil,
  elapsed = 0, ticker = 0, cooldown = 0, overlay = false,
  cleaned = false, health = nil, lastCommand = nil, suspended = false,
  debug = nil, debugTimer = 0, needsSize = true,
}
local api = {}
local battle

local function log(message)
  print("[NightCityLottery] " .. tostring(message))
end

local function writeStatus()
  local data = {
    version = VERSION, phase = state.phase, message = state.message,
    name = state.selected and state.selected.name or nil,
    record = state.selected and state.selected.record or nil,
    health_percent = state.health, command_id = state.lastCommand, debug = state.debug,
    checked_at = os.time(), persistent_spawn = false,
    battle = battle and battle:status() or nil,
  }
  pcall(function()
    local file = assert(io.open("status.json", "w"))
    file:write(json.encode(data)); file:close()
  end)
end

local function say(message, phase)
  state.message = message
  if phase then state.phase = phase end
  log(message)
  writeStatus()
end

local function backend()
  if not Codeware or not DynamicEntitySpec then
    return nil, nil, "缺少 Codeware。请先安装配套依赖，再重新启动游戏。"
  end
  local player = Game.GetPlayer()
  if not player then return nil, nil, "请先载入存档。" end
  local system = Game.GetDynamicEntitySystem()
  if not system or not system:IsReady() or not system:IsRestored() then
    return nil, nil, "场景正在加载，请稍后再试。"
  end
  return system, player
end

local function outsideScene(player)
  if player:IsDead() then return false, "角色已死亡，请先读档。" end
  if player:IsInCombat() then return false, "请在脱离战斗后抽取或召回队友。" end
  if Game.GetWorkspotSystem():IsActorInWorkspot(player) then
    return false, "请先离开座位、载具或剧情动作，再操作。"
  end
  local defs = Game.GetAllBlackboardDefs().PlayerStateMachine
  local board = Game.GetBlackboardSystem():GetLocalInstanced(player:GetEntityID(), defs)
  if not board then return false, "玩家状态尚未就绪。" end
  if board:GetInt(defs.SceneTier) > 1 then
    return false, "请在剧情对话或演出结束后操作。"
  end
  return true
end

local function owned(system, id)
  return id and system:IsManaged(id) and system:IsTagged(id, TAG)
end

local function deleteOwned(system)
  -- Delete only managed entities carrying our private tag, never world/quest NPCs.
  for _, id in ipairs(system:GetTaggedIDs(TAG)) do
    -- Codeware returns false for an entity whose deletion is already queued.
    if owned(system, id) then system:DeleteEntity(id) end
  end
  state.id, state.pending, state.health, state.debug = nil, nil, nil, nil
end

local function positionBeside(player)
  local p, f = player:GetWorldPosition(), player:GetWorldForward()
  local offsets = {{f.x * 1.5, f.y * 1.5}, {f.y * 1.5, -f.x * 1.5},
                   {-f.y * 1.5, f.x * 1.5}, {-f.x * 1.5, -f.y * 1.5}}
  local queries = Game.GetSpatialQueriesSystem()
  for _, offset in ipairs(offsets) do
    local from = Vector4.new(p.x + offset[1], p.y + offset[2], p.z + 0.8, 1)
    local to = Vector4.new(from.x, from.y, p.z - 1.5, 1)
    for _, group in ipairs({"Static", "Terrain"}) do
      local hit, result = queries:SyncRaycastByCollisionGroup(from, to, group, false, false)
      if hit and result then
        local position, normal = ToVector4(result.position), ToVector4(result.normal)
        if normal.z > 0.7 and math.abs(position.z - p.z) < 1.5 then
          return Vector4.new(position.x, position.y, position.z + 0.15, 1)
        end
      end
    end
  end
  error("附近没有检测到平坦地面，请换一处开阔位置再试。")
end

local function makeFollower(npc, player)
  if not npc:IsNPC() or not npc:IsAttached() then error("NPC 尚未完成加载。") end
  local controller, attitude = npc:GetAIControllerComponent(), npc:GetAttitudeAgent()
  if not controller or not attitude then error("此 NPC 没有可用的战斗 AI。") end
  -- Establish friendly attitude before activating follower behavior.
  attitude:SetAttitudeGroup(player:GetAttitudeAgent():GetAttitudeGroup())
  attitude:SetAttitudeTowards(player:GetAttitudeAgent(), EAIAttitude.AIA_Friendly)
  local old = controller:GetAIRole()
  if old then old:OnRoleCleared(npc) end
  local role = AIFollowerRole.new()
  role.followerRef = Game.CreateEntityReference("#player", {})
  controller:SetAIRole(role)
  controller:OnAttach()
  npc.isPlayerCompanionCached = true
  npc.isPlayerCompanionCachedTimeStamp = 0
  -- Codeware's manager is optional here; ordinary follower behavior stays available.
  local ok, err = pcall(function() npc.NPCManager:ScaleToPlayer() end)
  if not ok then log("等级同步未启用: " .. tostring(err)) end
end

battle = require("battlefield").new({backend = backend, makeFollower = makeFollower, pool = pool})

local function guarded(action)
  local ok, result = pcall(action)
  if not ok then
    state.suspended = true
    -- If setup failed, remove our partially spawned NPC instead of leaving a hostile.
    local cleanupOK, cleanupError = pcall(function()
      local system = Game.GetDynamicEntitySystem()
      if system and system:IsReady() then deleteOwned(system) end
    end)
    if not cleanupOK then log("清理失败: " .. tostring(cleanupError)) end
    say("操作未完成: " .. tostring(result), "error")
    return false
  end
  return result
end

function api.draw()
  state.suspended = false
  return guarded(function()
    if state.phase == "spawning" or state.phase == "preparing" then
      say("上一位队友正在加载，请稍候。")
      return false
    end
    if state.cooldown > 0 then
      say("重抽冷却中: " .. math.ceil(state.cooldown) .. " 秒。")
      return false
    end
    local system, player, err = backend()
    if not system then say(err); return false end
    local allowed, why = outsideScene(player)
    if not allowed then say(why); return false end
    local available = {}
    for _, entry in ipairs(pool) do
      if entry.record ~= state.previous and TweakDB:GetRecord(entry.record) then
        available[#available + 1] = entry
      end
    end
    if #available == 0 then say("当前版本中没有可用的候选 NPC。", "error"); return false end
    local selection = available[math.random(#available)]
    deleteOwned(system)
    state.selected, state.previous = selection, selection.record
    state.elapsed = 0
    state.cooldown = 10
    say("抽中: " .. selection.name .. "，正在生成……", "preparing")
    return true
  end)
end

function api.dismiss()
  state.suspended = false
  return guarded(function()
    local system, _, err = backend()
    if not system then say(err); return false end
    deleteOwned(system)
    battle:clear()
    state.selected = nil
    if #system:GetTaggedIDs(TAG) > 0 then
      say("正在解散队友……", "dismissing")
    else say("队友已解散。", "idle") end
    return true
  end)
end

function api.recall()
  state.suspended = false
  return guarded(function()
    local system, player, err = backend()
    if not system then say(err); return false end
    local allowed, why = outsideScene(player)
    if not allowed then say(why); return false end
    if not owned(system, state.id) then say("当前没有可召回的队友。"); return false end
    local npc = system:GetEntity(state.id)
    if not npc or not npc:IsAttached() or npc:IsDead() then
      say("队友不在场或已阵亡，可以重新抽取。")
      return false
    end
    Game.GetTeleportationFacility():Teleport(npc, positionBeside(player), player:GetWorldOrientation():ToEulerAngles())
    say("已将队友召回身边。", "active")
    return true
  end)
end

function api.status()
  return {phase = state.phase, message = state.message, record = state.selected and state.selected.record,
          battle = battle:status()}
end

function api.squad(count) return battle:start(count or 4, 0) end
function api.battle(count) return battle:start(count or 4, count or 4) end
function api.clearBattle() return battle:clear() end

local function pollCommand()
  local file = io.open("command.json", "r")
  if not file then return end
  local content = file:read("*a"); file:close()
  os.remove("command.json")
  local ok, request = pcall(json.decode, content)
  if not ok or type(request) ~= "table" or type(request.id) ~= "string" then
    say("忽略了无效的本地指令。")
    return
  end
  if request.id == state.lastCommand then return end
  state.lastCommand = request.id
  if request.action == "draw" then api.draw()
  elseif request.action == "dismiss" then api.dismiss()
  elseif request.action == "recall" then api.recall()
  elseif request.action == "status" then writeStatus()
  elseif request.action == "squad" then api.squad(request.count)
  elseif request.action == "battle" then api.battle(request.count)
  elseif request.action == "clear_battle" then api.clearBattle()
  else say("不支持的本地指令。") end
end

-- CET exposes registration only while the mod file is being evaluated.
registerHotkey("ncl_draw", "随机队友 / Draw companion", api.draw)
registerHotkey("ncl_dismiss", "解散队友 / Dismiss companion", api.dismiss)
registerHotkey("ncl_recall", "召回队友 / Recall companion", api.recall)

registerForEvent("onInit", function()
  math.randomseed(os.time())
  say("随机队友已加载。打开 CET 面板进行抽取。")
end)

registerForEvent("onOverlayOpen", function() state.overlay = true end)
registerForEvent("onOverlayClose", function() state.overlay = false end)

registerForEvent("onUpdate", function(delta)
  state.cooldown = math.max(0, state.cooldown - delta)
  battle:update(delta)
  -- A failed engine call disables this update path until an explicit user action.
  if state.suspended then return end
  guarded(function()
    local system, player = backend()
    if not system then
      state.id, state.pending, state.health = nil, nil, nil
      state.cleaned = false
      if state.phase == "active" or state.phase == "spawning" or state.phase == "preparing" then
        state.selected = nil
        say("场景已卸载；队友为临时生成，下次需重新抽取。", "idle")
      end
      return
    end
    if not state.cleaned then
      deleteOwned(system)
      state.cleaned = true
    end
    if state.phase == "dismissing" then
      if #system:GetTaggedIDs(TAG) == 0 then say("队友已解散。", "idle") end
    elseif state.phase == "preparing" then
      state.elapsed = state.elapsed + delta
      if state.elapsed >= 0.5 then
        if #system:GetTaggedIDs(TAG) > 0 then
          if state.elapsed > 10 then error("旧队友仍在解散，请稍后重试。") end
          return
        end
        local allowed, why = outsideScene(player)
        if not allowed then say(why, "idle"); return end
        local spec = DynamicEntitySpec.new()
        spec.recordID = TweakDBID.new(state.selected.record)
        spec.position, spec.orientation = positionBeside(player), player:GetWorldOrientation()
        spec.persistState, spec.persistSpawn = false, false
        spec.alwaysSpawned, spec.spawnInView, spec.active = true, true, true
        spec.tags = {TAG}
        state.pending = system:CreateEntity(spec)
        state.elapsed = 0
        say("正在等待 NPC 加载……", "spawning")
      end
    elseif state.phase == "spawning" then
      state.elapsed = state.elapsed + delta
      local npc = state.pending and system:GetEntity(state.pending)
      if npc and npc:IsAttached() then
        makeFollower(npc, player)
        state.id, state.pending = state.pending, nil
        say("队友就位: " .. state.selected.name, "active")
      elseif state.elapsed > 15 then
        deleteOwned(system)
        say("生成超时，已清理本次生成。可换一处开阔地再试。", "error")
      end
    end
    state.ticker = state.ticker + delta
    if state.ticker >= 0.5 then
      state.ticker = 0
      pollCommand()
    end
    state.debugTimer = state.debugTimer + delta
    if state.debugTimer >= 1 then
      state.debugTimer = 0
      if owned(system, state.id) then
        local npc = system:GetEntity(state.id)
        if npc and npc:IsAttached() then
          local p, n = player:GetWorldPosition(), npc:GetWorldPosition()
          local role = npc:GetAIControllerComponent():GetAIRole()
          state.health = Game.GetStatPoolsSystem():GetStatPoolValue(npc:GetEntityID(), gamedataStatPoolType.Health, true)
          state.debug = {distance_m = math.sqrt((p.x-n.x)^2 + (p.y-n.y)^2 + (p.z-n.z)^2),
            follower_role = role ~= nil and role:IsA("AIFollowerRole"), dead = npc:IsDead(),
            player_position = {x=p.x,y=p.y,z=p.z}, npc_position = {x=n.x,y=n.y,z=n.z},
            managed_companions = #system:GetTaggedIDs(TAG)}
        end
      end
      writeStatus()
    end
  end)
end)

registerForEvent("onDraw", function()
  if not state.overlay then return end
  if state.needsSize then
    ImGui.SetNextWindowSize(1100, 1000, ImGuiCond.Always)
    state.needsSize = false
  end
  if ImGui.Begin("随机队友 · Night City Lottery") then
    ImGui.TextWrapped("从 10 种普通战斗 NPC 中随机抽取一名临时队友。")
    ImGui.Separator()
    ImGui.TextWrapped(state.message)
    if state.selected then ImGui.TextWrapped("当前: " .. state.selected.name) end
    ImGui.Text("状态: " .. state.phase .. "  |  重抽冷却: " .. math.ceil(state.cooldown) .. " 秒")
    if state.debug then
      ImGui.Text(string.format("生命: %.0f%%   距离: %.1f 米", state.health or 0, state.debug.distance_m))
      ImGui.Text("跟随角色: " .. tostring(state.debug.follower_role) .. "  |  在场人数: " .. state.debug.managed_companions)
    end
    ImGui.Spacing()
    if ImGui.Button("抽取 / 重新抽取", 200, 38) then api.draw() end
    ImGui.SameLine()
    if ImGui.Button("解散队友", 160, 38) then api.dismiss() end
    if ImGui.Button("召回身边", 200, 32) then api.recall() end
    ImGui.Spacing()
    ImGui.TextWrapped("请在自由探索、脱离战斗后抽取。剧情演出前请解散。")
    ImGui.TextWrapped("队友会跟随并协助战斗；载具、复杂室内寻路需实测。读档后不会自动重生。")
    ImGui.TextWrapped("快捷键可在 CET 的 Bindings 中自行绑定。")
    battle:draw()
  end
  ImGui.End()
end)

registerForEvent("onShutdown", function()
  pcall(function()
    battle:clear()
    local system = Game.GetDynamicEntitySystem()
    if system and system:IsReady() then deleteOwned(system) end
  end)
end)

return api
