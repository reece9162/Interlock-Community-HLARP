local config = {
    smokeColor = Color(234, 177, 33),
    smokeAlpha = 110,
    smokeSpawnerDistance = 100 -- distance between the smoke emitters on the box line
}

local PLUGIN = PLUGIN

PLUGIN.name = "Toxic Gas"
PLUGIN.author = "liquid"
PLUGIN.description = "Adds configurable toxic gas and gas-mask item."

PLUGIN.positions = PLUGIN.positions or {}
PLUGIN.smokeStacks = PLUGIN.smokeStacks or {}

ix.util.Include("sh_config.lua")

function PLUGIN:LoadData()
    PLUGIN.positions = self:GetData()
    self:UpdateWorldData()
end

function PLUGIN:SaveData()
    self:SetData(PLUGIN.positions)
    self:UpdateWorldData()
end

function PLUGIN:UpdateWorldData()
    SetNetVar("toxicGasPositions", PLUGIN.positions)
    -- global netvar doesn't seem to sync without this
    for _, ply in pairs(player.GetAll()) do
        ply:SyncVars()
    end
end

function PLUGIN:IsGasImmune(ply)
    local char = ply:GetCharacter()

    if(!char) then 
        return false 
    end

    for _, item in pairs(char:GetInventory():GetItems()) do
        if(item.gasImmunity and item:GetData("equip") == true) then
            return true
        end
    end

    if ( char:IsCombine() or char:IsDispatch() or char:GetFaction() == FACTION_EVENT ) then 
        return true
    end

    if ( ply:GetMoveType() == MOVETYPE_NOCLIP and ply:IsAdmin() ) or ply:InVehicle() then 
        return true
    end

    return false
end

local function GetBoxLine(min, max)
    local deltaX = math.abs(min.x - max.x)
    local deltaY = math.abs(min.y - max.y)

    local lineStart, lineEnd

    if deltaX < deltaY then
        lineStart = Vector(min.x + (max.x - min.x) / 2, min.y, min.z)
        lineEnd = Vector(min.x + (max.x - min.x) / 2, min.y + (max.y - min.y), min.z)
    else
        lineStart = Vector(min.x, min.y + (max.y - min.y) / 2, min.z)
        lineEnd = Vector(min.x + (max.x - min.x), min.y + (max.y - min.y) / 2, min.z)
    end

    return lineStart, lineEnd
end

if SERVER then
    timer.Create("GasTick", 0.15, 0, function()
        for idx, gasBox in pairs(PLUGIN.positions) do
            if PLUGIN.smokeStacks[idx] == nil then
                local min, max = gasBox.min, gasBox.max

                local startSmoke, endSmoke = GetBoxLine(min, max)

                PLUGIN.smokeStacks[idx] = {
                    count = math.floor(startSmoke:Distance(endSmoke) / config.smokeSpawnerDistance),
                    stacks = {}
                }

                for i = 1, PLUGIN.smokeStacks[idx].count do
                    local smoke = ents.Create("env_smokestack")
                    smoke:SetPos(startSmoke + (endSmoke - startSmoke):GetNormalized() * (i) * config.smokeSpawnerDistance)
                    smoke:SetKeyValue("InitialState", "1")
                    smoke:SetKeyValue("WindAngle", "0 0 0")
                    smoke:SetKeyValue("WindSpeed", "0")
                    smoke:SetKeyValue("rendercolor", tostring(config.smokeColor))
                    smoke:SetKeyValue("renderamt", tostring(config.smokeAlpha))
                    smoke:SetKeyValue("SmokeMaterial", "particle/particle_smokegrenade.vmt")
                    smoke:SetKeyValue("BaseSpread", tostring(config.smokeSpawnerDistance))
                    smoke:SetKeyValue("SpreadSpeed", "10")
                    smoke:SetKeyValue("Speed", "32")
                    smoke:SetKeyValue("StartSize", "32")
                    smoke:SetKeyValue("EndSize", "32")
                    smoke:SetKeyValue("roll", "8")
                    smoke:SetKeyValue("Rate", "64")
                    smoke:SetKeyValue("JetLength", tostring(max.z - min.z))
                    smoke:SetKeyValue("twist", "6")
                    smoke:Spawn()
                    smoke:Activate()
                    smoke.Think = function()
                        if PLUGIN.positions[idx] == nil then
                            smoke:Remove()
                        end
                    end
                    PLUGIN.smokeStacks[idx].stacks[i] = smoke
                end
            end
        end

        for _, ply in pairs(player.GetAll()) do
            local char = ply:GetCharacter()

            if(!ply:Alive() or !char) then 
                continue 
            end
            
            local pos = ply:EyePos()
            local canBreathe = false
            
            if(!canBreathe) then
                canBreathe = PLUGIN:IsGasImmune(ply)
            end

            if(!canBreathe) then
                for _, gasBox in pairs(PLUGIN.positions) do
                    local curTime = CurTime() -- Micro optimization

                    if pos:WithinAABox(gasBox.min, gasBox.max) then
                        ply.nextGasDamage = ply.nextGasDamage or curTime
                        ply.nextGasNotify = ply.nextGasNotify or curTime

                        if(curTime >= ply.nextGasDamage) then
                            ply.nextGasDamage = curTime + ix.config.Get("gasDmgTick", 0)
                            ply:TakeDamage(ix.config.Get("gasDmg", 0))
                            ply:SetRunSpeed(ix.config.Get("runSpeed") * ix.config.Get("gasRunSlow", 0.7))
                            ply:SetWalkSpeed(ix.config.Get("walkSpeed") * ix.config.Get("gasWalkSlow", 0.7))
                            ply:ScreenFade(1, Color(234, 177, 33, 100), 2, 0)

                            if(curTime >= ply.nextGasNotify) then
                                ply.nextGasNotify = curTime + ix.config.Get("gasNotifyTime", 45)

                                ix.util.Notify("You feel a burning sensation in the back of your throat.", ply)
                            end    
                        end
                    end
                end
            end
        end
    end)
end

if CLIENT then
    -- toggles showing toxic gas boxes when in noclip/observer
    CreateConVar("ix_toxicgas_observer", "0", FCVAR_ARCHIVE)

    local function IsInRange(min, max, scale)
        local localPos = LocalPlayer():GetPos()

        local distance = min:Distance(max)

        if localPos:Distance(min + ((max - min) / 2)) <= distance * scale then
            return true
        end

        return false
    end

    function PLUGIN:PostDrawTranslucentRenderables()
        local toxicGasPositions = GetNetVar("toxicGasPositions")

        if toxicGasPositions == nil then return end

        for _, gasBox in pairs(toxicGasPositions) do
            local min, max = gasBox.min, gasBox.max

            if not IsInRange(min, max, 3) then continue end

            local observerCvar = GetConVar("ix_toxicgas_observer")

            if LocalPlayer():IsAdmin()
            and LocalPlayer():GetMoveType() == MOVETYPE_NOCLIP
            and observerCvar and observerCvar:GetBool() then
                render.DrawWireframeBox(min, Angle(), Vector(0, 0, 0), max - min, Color(142, 222, 131, 255), false)
                local startSmoke, endSmoke = GetBoxLine(min, max)
                render.DrawLine(startSmoke, endSmoke, Color(0, 255, 0), false)
            end
        end
    end
end

ix.command.Add("AddToxicGas", {
    description = "Adds a toxic gas box from where you're standing and where you're looking at.",
    adminOnly = true,
    OnRun = function(self, ply)
        local pos = ply:GetPos()
        
        local tr = ply:GetEyeTrace()
        if not tr then return end
        
        local hitPos = tr.HitPos

        table.insert(PLUGIN.positions, {
            min = pos, max = hitPos
        })

        PLUGIN:SaveData()

        return "Added toxic gas."
    end
})

ix.command.Add("RemoveToxicGas", {
    description = "Removes the closest toxic gas point relative to you.",
    adminOnly = true,
    OnRun = function(self, ply)
        local closestDistance = -1
        local closestIndex = -1
        
        for idx, gasBox in pairs(PLUGIN.positions) do
            local min, max = gasBox.min, gasBox.max

            local center = min + ((max - min) / 2)

            local distance = ply:GetPos():Distance(center) 
            if closestDistance == -1 or distance < closestDistance then
                closestDistance = distance
                closestIndex = idx
            end
        end

        if closestIndex ~= -1 then
            table.remove(PLUGIN.positions, closestIndex)

            if PLUGIN.smokeStacks[closestIndex] then
                for k, v in pairs(PLUGIN.smokeStacks[closestIndex].stacks) do
                    v:Remove()
                end
                table.remove(PLUGIN.smokeStacks, closestIndex)
            end
            
            PLUGIN:SaveData()

            return "Removed 1 toxic gas box."
        else
            return "Could not find any toxic gas to remove!"
        end
    end
})
