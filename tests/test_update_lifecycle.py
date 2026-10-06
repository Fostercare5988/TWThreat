"""Native frame visibility and cancellable query cadence regressions."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

SOURCE = (Path(__file__).resolve().parents[1] / 'TWThreat.lua').read_text(encoding='utf-8-sig')

def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        __pairs=pairs; __min=math.min; __max=math.max; __abs=math.abs
        function table_wipe(t) for k in pairs(t) do t[k]=nil end end
        function fire(f,event,dt)
            local oldThis,oldArg=this,arg1; this,arg1=f,dt
            if f.scripts[event] then f.scripts[event]() end
            this,arg1=oldThis,oldArg
        end
        function CreateFrame(kind,name)
            local f={shown=true,scripts={},width=2}
            function f:SetScript(event,cb) self.scripts[event]=cb end
            function f:GetScript(event) return self.scripts[event] end
            function f:IsVisible() return self.shown end
            function f:Show() if not self.shown then self.shown=true;fire(self,'OnShow') end end
            function f:Hide() if self.shown then self.shown=false;fire(self,'OnHide') end end
            function f:SetWidth(w) self.width=w end
            function f:GetWidth() return self.width end
            if name then _G[name]=f end
            return f
        end
        timers={}; C_Timer={}
        function C_Timer.NewTicker(interval,cb)
            local t={interval=interval,callback=cb,cancelled=false}
            function t:Cancel() self.cancelled=true end
            timers[#timers+1]=t; return t
        end
        raid=0; party=4; combat=true; queries=0; targetChanges=0
        function GetNumRaidMembers() return raid end
        function GetNumPartyMembers() return party end
        function UnitAffectingCombat() return combat end
        TWT={windowWidth=102,updateSpeed=.5,targetName='Boss',healerMasterTarget=''}
        TWT_CONFIG={visible=true,visibleBars=5}
        TWT.round=function(n) return math.floor(n+.5) end
        TWT.targetChanged=function() targetChanges=targetChanges+1 end
        TWT.UnitDetailedThreatSituation=function(n) assert(n==4);queries=queries+1 end
        TWT.threatQuery=CreateFrame('Frame'); TWT.threatQuery:Hide()
        TWThreat1BG=CreateFrame('Frame','TWThreat1BG')
        TWThreat2BG=CreateFrame('Frame','TWThreat2BG')
    """)
    begin=SOURCE.index("TWT.barAnimator = CreateFrame('Frame'")
    end=SOURCE.index('function TWT.calcTPS(',begin)
    lua.execute(SOURCE[begin:end])
    return lua

class UpdateLifecycleTests(unittest.TestCase):
    def test_query_uses_one_cancellable_timer_and_rejects_stale_callbacks(self):
        lua=runtime()
        lua.execute("""
            local f=TWT.threatQuery
            assert(not f:GetScript('OnUpdate'),'Queries do not need render-frame polling')
            f:Show(); assert(#timers==1 and timers[1].interval==.5)
            f:Show(); assert(#timers==1 and queries==0)
            timers[1].callback(); assert(queries==1)
            f:Hide(); assert(timers[1].cancelled)
            timers[1].callback(); assert(queries==1)
            TWT.updateSpeed=.7; f:Show()
            assert(#timers==2 and timers[2].interval==.7)
            timers[1].callback(); assert(queries==1)
            timers[2].callback(); assert(queries==2)
            f:Hide(); timers[2].callback(); assert(queries==2)
        """)

    def test_query_retains_group_combat_target_and_feature_gates(self):
        lua=runtime()
        lua.execute("""
            TWT.threatQuery:Show(); local tick=timers[1].callback
            party=0; tick(); assert(queries==0)
            raid=40; combat=false; tick(); assert(queries==0)
            combat=true; TWT.targetName=''; tick(); assert(targetChanges==1 and queries==0)
            TWT.targetName='Boss'; TWT.healerMasterTarget='Tank'; tick(); assert(queries==0)
            TWT.healerMasterTarget=''; TWT_CONFIG.visible=false; tick(); assert(queries==0)
            TWT_CONFIG.glow=true; tick(); assert(queries==1)
        """)

    def test_animation_wakes_for_pending_widths_and_sleeps_after_completion(self):
        lua=runtime()
        lua.execute("""
            local f=TWT.barAnimator
            assert(not f:IsVisible())
            f:animateTo(1,100,false)
            assert(f:IsVisible() and f.frames.TWThreat1BG==100,'OnShow must retain the first target')
            for i=1,100 do if f:IsVisible() then fire(f,'OnUpdate',.016) end end
            assert(TWThreat1BG:GetWidth()==100 and not next(f.frames) and not f:IsVisible())
            f:animateTo(1,50,false); f:animateTo(2,75,false)
            assert(f:IsVisible() and f.frames.TWThreat2BG==75)
            f:Hide(); assert(not next(f.frames),'Combat cleanup discards unfinished animation')
            f:animateTo(2,25,false)
            assert(f:IsVisible() and f.frames.TWThreat2BG==25)
            f:animateTo(2,25,true)
            assert(TWThreat2BG:GetWidth()==25 and not f:IsVisible())
            f:animateTo(1,10,false); f:animateTo(1,nil,false)
            assert(not f:IsVisible() and not next(f.frames))
        """)

    def test_startup_checks_declared_superwow_floor_and_native_timer(self):
        prefix=SOURCE[:SOURCE.index('local _G =')]
        for version,timer,expected in (('2.2',True,0),('2.1',True,1),('2.2',False,1)):
            lua=LuaRuntime(unpack_returned_tuples=True)
            lua.execute("""
                CLASSIC_API_VERSION=11515;warnings=0
                DEFAULT_CHAT_FRAME={AddMessage=function() warnings=warnings+1 end}
            """)
            lua.globals().SUPERWOW_VERSION=version
            if timer:lua.execute('C_Timer={NewTicker=function() end}')
            lua.execute(prefix)
            self.assertEqual(lua.globals().warnings,expected)

if __name__=='__main__': unittest.main()
