import pathlib
import unittest
from lupa.luajit21 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parents[1]
MOD = ROOT / "mod/NightCityLottery"

MOCK_ENGINE = r'''
events, hotkeys = {}, {}
function registerForEvent(n,f) events[n]=f end
function registerHotkey(n,_,f) hotkeys[n]=f end
function print(...) end
io = {open=function() return nil end}
json = {encode=function() return '{}' end}
Codeware = {}
DynamicEntitySpec = {new=function() return {} end}
TweakDBID = {new=function(v) return v end}
Vector4 = {new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
function ToVector4(v) return v end
EAIAttitude={AIA_Friendly=1,AIA_Hostile=2}
CName={new=function(v) return v end}
gameGodModeType={Immortal=1}
AINoRole={new=function() return {OnRoleCleared=function() end} end}
TweakDBInterface={GetReactionPresetRecord=function(v) return v end}
M={ entities={}, next=0, creates=0, deleted=0, combat=false, workspot=false,
    tier=0, delay=false, failRole=false, noRecords=false, failDelete=false, teleports=0, triggers=0 }
local attitude={SetAttitudeGroup=function() end, SetAttitudeTowards=function() end,
                GetAttitudeGroup=function() return 'player' end}
local controller={GetAIRole=function() return M.role end,
  SetAIRole=function(_,r) if M.failRole then error('simulated incompatible AI') end; M.role=r end,
  OnAttach=function() M.attached=true end}
local function npc()
  return {IsNPC=function() return true end, IsAttached=function() return true end,
          IsDead=function() return M.npcDead or false end,
          IsInCombat=function() return M.triggers>0 end,
          reactionComponent={SetReactionPreset=function() end, TriggerCombat=function() M.triggers=M.triggers+1 end},
          GetAIControllerComponent=function() return controller end,
          GetEntityID=function() return 'npc-id' end,
          GetWorldPosition=function() return {x=2,y=2,z=3,w=1} end,
          GetAttitudeAgent=function() return attitude end,
          NPCManager={ScaleToPlayer=function() M.scaled=true end}}
end
player={IsDead=function() return false end, IsInCombat=function() return M.combat end,
 GetEntityID=function() return 'player-id' end, GetAttitudeAgent=function() return attitude end,
 GetWorldPosition=function() return {x=1,y=2,z=3,w=1} end,
 GetWorldForward=function() return {x=0,y=1,z=0,w=0} end,
 GetWorldOrientation=function() return {ToEulerAngles=function() return {} end} end}
system={IsReady=function() return true end, IsRestored=function() return true end,
 IsManaged=function(_,id) return M.entities[id] ~= nil end,
 IsTagged=function(_,id,tag) return M.entities[id] and M.entities[id].tag==tag end,
 GetTaggedIDs=function(_,tag) local t={} for id,e in pairs(M.entities) do if e.tag==tag then t[#t+1]=id end end return t end,
 DeleteEntity=function(_,id) if M.failDelete then return false end; M.entities[id]=nil; M.deleted=M.deleted+1; return true end,
 CreateEntity=function(_,spec) M.next=M.next+1; M.creates=M.creates+1; M.spec=spec; M.entities[M.next]={tag=spec.tags[1],npc=npc()}; return M.next end,
 GetEntity=function(_,id) return not M.delay and M.entities[id] and M.entities[id].npc or nil end}
Game={ GetPlayer=function() if M.unloaded then return nil end; return player end,
 GetDynamicEntitySystem=function() return system end,
 GetWorkspotSystem=function() return {IsActorInWorkspot=function() return M.workspot end} end,
 GetAllBlackboardDefs=function() return {PlayerStateMachine={SceneTier='tier'}} end,
 GetBlackboardSystem=function() return {GetLocalInstanced=function() return {GetInt=function() return M.tier end} end} end,
 CreateEntityReference=function(ref,_) return ref end,
 GetTeleportationFacility=function() return {Teleport=function() M.teleports=M.teleports+1 end} end }
Game.GetSpatialQueriesSystem=function() return {SyncRaycastByCollisionGroup=function(_,from,to)
 if M.noFloor then return false,nil end
 return true,{position={x=from.x,y=from.y,z=3,w=1},normal={x=0,y=0,z=1,w=0}} end} end
TweakDB={GetRecord=function(_,r) return not M.noRecords and r or nil end}
Game.GetStatPoolsSystem=function() return {GetStatPoolValue=function() return 100 end} end
Game.GetGodModeSystem=function() return {AddGodMode=function() end, ClearGodMode=function() end} end
gamedataStatPoolType={Health='health'}
AIFollowerRole={new=function() return {IsA=function(_,name) return name=='AIFollowerRole' end,OnRoleCleared=function() end} end}
ImGuiCond={FirstUseEver=1,Always=2}
ImGui=setmetatable({Begin=function() return true end,Button=function() return false end}, {__index=function() return function() end end})
function require(name) if name=='battlefield' then return Battle end; return Pool end
'''


class LuaBehavior(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK_ENGINE)
        self.lua.globals().Pool = self.lua.execute((MOD / 'pool.lua').read_text(encoding='utf-8'))
        self.lua.globals().Battle = self.lua.execute((MOD / 'battlefield.lua').read_text(encoding='utf-8'))
        self.api = self.lua.execute((MOD / 'init.lua').read_text(encoding='utf-8'))
        self.g = self.lua.globals()
        self.g.registerHotkey = None  # CET removes registration APIs before onInit.
        self.g.events.onInit()

    def spawn(self):
        self.assertTrue(self.api.draw())
        self.g.events.onUpdate(0.5)
        self.g.events.onUpdate(0.1)
        self.assertEqual(self.api.status()['phase'], 'active')

    def test_temporary_spawn_and_follow_role(self):
        self.spawn()
        self.assertFalse(self.g.M.spec.persistSpawn)
        self.assertFalse(self.g.M.spec.persistState)
        self.assertEqual(self.g.M.role.followerRef, '#player')
        self.assertTrue(self.g.M.attached)
        self.assertTrue(self.g.M.scaled)

    def test_reroll_respects_cooldown_and_never_repeats_immediately(self):
        self.spawn()
        original = self.g.M.spec.recordID
        self.assertFalse(self.api.draw())
        self.assertEqual(self.g.M.creates, 1)
        self.g.events.onUpdate(10)
        self.assertTrue(self.api.draw())
        self.g.events.onUpdate(0.5); self.g.events.onUpdate(0.1)
        self.assertNotEqual(original, self.g.M.spec.recordID)
        self.assertEqual(len(list(self.g.M.entities.items())), 1)

    def test_existing_world_npc_is_never_deleted(self):
        self.lua.execute("M.entities['world-npc']={tag='not-our-tag'}")
        self.spawn(); self.assertTrue(self.api.dismiss())
        self.assertIsNotNone(self.g.M.entities['world-npc'])
        self.assertEqual(len(list(self.g.M.entities.items())), 1)

    def test_combat_workspot_scene_guards(self):
        for field, value in [('combat', True), ('workspot', True), ('tier', 3)]:
            self.g.M[field] = value
            self.assertFalse(self.api.draw())
            self.assertEqual(self.g.M.creates, 0)
            self.g.M[field] = False if field != 'tier' else 0

    def test_pending_cancel_and_timeout(self):
        self.g.M.delay = True
        self.assertTrue(self.api.draw()); self.g.events.onUpdate(0.5)
        self.assertEqual(self.api.status()['phase'], 'spawning')
        self.assertTrue(self.api.dismiss())
        self.g.events.onUpdate(20)
        self.assertEqual(len(list(self.g.M.entities.items())), 0)
        self.assertTrue(self.api.draw()); self.g.events.onUpdate(0.5); self.g.events.onUpdate(16)
        self.assertEqual(self.api.status()['phase'], 'error')
        self.assertEqual(len(list(self.g.M.entities.items())), 0)

    def test_failed_follower_setup_removes_partial_spawn(self):
        self.g.M.failRole = True
        self.assertTrue(self.api.draw()); self.g.events.onUpdate(0.5); self.g.events.onUpdate(0.1)
        self.assertEqual(self.api.status()['phase'], 'error')
        self.assertEqual(len(list(self.g.M.entities.items())), 0)
        self.g.events.onUpdate(1)
        self.assertEqual(self.g.M.creates, 1)

    def test_recall_does_not_revive_dead_companion(self):
        self.spawn(); self.assertTrue(self.api.recall())
        self.g.M.npcDead = True
        self.assertFalse(self.api.recall())
        self.assertEqual(self.g.M.teleports, 1)

    def test_missing_dependency_and_records_are_safe(self):
        self.g.Codeware = None
        self.assertFalse(self.api.draw())
        self.g.Codeware = self.lua.table()
        self.g.M.noRecords = True
        self.assertFalse(self.api.draw())
        self.assertEqual(self.g.M.creates, 0)

    def test_overlay_and_hotkeys_register(self):
        self.assertEqual(len(list(self.g.hotkeys.items())), 3)
        self.g.events.onOverlayOpen(); self.g.events.onDraw(); self.g.events.onOverlayClose()

    def test_load_does_not_automatically_respawn_companion(self):
        self.spawn()
        self.g.M.unloaded = True; self.g.events.onUpdate(1)
        self.assertEqual(self.api.status()['phase'], 'idle')
        self.g.M.unloaded = False; self.g.events.onUpdate(1)
        self.assertEqual(self.g.M.creates, 1)
        self.assertEqual(len(list(self.g.M.entities.items())), 0)

    def test_no_floor_cancels_spawn(self):
        self.g.M.noFloor = True
        self.assertTrue(self.api.draw()); self.g.events.onUpdate(0.5)
        self.assertEqual(self.api.status()['phase'], 'error')
        self.assertEqual(self.g.M.creates, 0)

    def test_async_delete_never_spawns_second_companion(self):
        self.spawn(); self.g.events.onUpdate(10)
        self.g.M.failDelete = True
        self.assertTrue(self.api.draw()); self.g.events.onUpdate(0.5)
        self.assertEqual(self.g.M.creates, 1)
        self.assertEqual(self.api.status()['phase'], 'preparing')
        self.g.M.failDelete = False
        self.lua.execute('M.entities={}')
        self.g.events.onUpdate(0.1); self.g.events.onUpdate(0.1)
        self.assertEqual(self.g.M.creates, 2)

    def assemble(self):
        for _ in range(60): self.g.events.onUpdate(0.5)
        return self.api.status()['battle']

    def test_stage_works_in_combat_and_caps_both_teams(self):
        self.g.M.combat = True
        self.assertTrue(self.api.battle(1000))
        stage = self.assemble()
        self.assertEqual(stage['phase'], 'active')
        self.assertEqual((stage['allies'], stage['foes']), (8, 8))
        self.assertEqual(self.g.M.creates, 16)
        self.assertGreater(self.g.M.triggers, 0)
        self.assertFalse(self.g.M.spec.persistState)
        self.assertFalse(self.g.M.spec.persistSpawn)

    def test_stage_cancel_preserves_world_entities(self):
        self.lua.execute("M.entities['world-npc']={tag='not-our-tag'}")
        self.assertTrue(self.api.battle(4)); self.g.events.onUpdate(0.5)
        self.assertTrue(self.api.dismiss()); self.assemble()
        self.assertIsNotNone(self.g.M.entities['world-npc'])
        self.assertEqual(len(list(self.g.M.entities.items())), 1)
        self.assertEqual(self.api.status()['battle']['phase'], 'idle')

    def test_stage_async_delete_blocks_new_team_until_old_removed(self):
        self.assertTrue(self.api.battle(4)); self.assemble()
        self.g.M.failDelete = True
        self.assertTrue(self.api.battle(6)); self.assemble()
        self.assertEqual(self.g.M.creates, 8)
        self.g.M.failDelete = False; self.lua.execute('M.entities={}')
        stage = self.assemble()
        self.assertEqual((stage['allies'], stage['foes']), (6, 6))

    def test_stage_scene_guard_and_setup_failure(self):
        self.g.M.tier = 3
        self.assertFalse(self.api.battle(4)); self.assertEqual(self.g.M.creates, 0)
        self.g.M.tier = 0; self.g.M.failRole = True
        self.assertTrue(self.api.battle(4)); stage = self.assemble()
        self.assertEqual(stage['phase'], 'error')
        self.assertEqual(len(list(self.g.M.entities.items())), 0)

    def test_stage_allies_only_and_shutdown(self):
        self.assertTrue(self.api.squad(4)); stage = self.assemble()
        self.assertEqual((stage['allies'], stage['foes']), (4, 0))
        self.g.events.onShutdown()
        self.assertEqual(len(list(self.g.M.entities.items())), 0)



if __name__ == '__main__':
    unittest.main(verbosity=2)
