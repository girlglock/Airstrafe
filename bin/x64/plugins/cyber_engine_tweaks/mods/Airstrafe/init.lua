-- original mod was made by teetoxd on nexusmods https://www.nexusmods.com/cyberpunk2077/mods/5816
-- updated for game ver 2.5 by girlglock with many tweaks in attempt to make the air movement closer to quake/hl1

Airstrafe = {
    description = "Adds quake/hl1 like Airstrafing",
    player = nil,
    input = nil,
    isPlayerInAir = false,
    delta = 0.0,
    accumulator = 0.0,  -- unsimmed time at 72t
    angles = { pitch = 0.0, yaw = 0.0, roll = 0.0 }, -- sv_player->v.angles
    speedText = nil,
    shownSpeed = -1,
    lastState = 0,
    airVelocity = nil,
    timeOnGround = 0.0,
    capRaised = false,
    knockdownCooldown = 0,
    vanillaAirXY = nil,
    vanillaExtendedAirXY = nil,
    showUI = false
}

Defaults = {
    enabled = true,     --toggle mod
    airAccel = 10.0,    --sv_accelerate
    airCap = 30.0,      --wishspd in SV_AirAccelerate
    maxSpeed = 320.0,   --sv_maxspeed
    autohop = true,     --holding jump jumps again on landing
    slopeJump = true,
    uncapAir = true,    --remove the velo cap vanilla movement has
    shotgunJump = true, --rocketjumping but scuffed
    noStumble = true
}

Config = {}

--quake vars, only needed for air move
local QUAKE = {
    forwardSpeed = 400.0,   --cl_forwardspeed on always run
    backSpeed = 400.0,      --cl_backspeed
    sideSpeed = 350.0,      --cl_sidespeed
    rollAngle = 2.0,        --sv_rollangle
    rollSpeed = 200.0,      --sv_rollspeed
    frameTime = 1.0 / 72.0, --host_maxfps 72
    frameTimeMax = 0.1,     --host_frametime clamp
    unitsPerMeter = 32.0,   --1u = 1/32m (56u player = 1,75m)
    standable = 0.7,        --sv_standable_normal
    uncappedAirXY = 100000.0,
    friction = 4.0,         --sv_friction
    stopSpeed = 100.0,      --sv_stopspeed
    hopWindow = 0.3,        --max time on the ground that still counts as a hop
    rocketDamage = 120.0,   --T_RadiusDamage
    rocketKnockback = 8.0   --T_Damage velocity += dir * damage * 8
}

--gamePSMDetailedLocomotionStates, 14 fall, 18 jump, 19 double jump, 20 charge yump, 21 hover yump
local AirStates = {
    [14] = true,
    [18] = true,
    [19] = true,
    [20] = true,
    [21] = true
}

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

require("input")

function ResetConfig()
    for k, v in pairs(Defaults) do
        Config[k] = v
    end
end

local SettingsFile = "settings.txt"

function LoadConfig()
    local file = io.open(SettingsFile, "r")
    if not file then
        return
    end
    for line in file:lines() do
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        local default = key and Defaults[key]
        if default ~= nil then
            if type(default) == "boolean" and (value == "true" or value == "false") then
                Config[key] = value == "true"
            elseif type(default) == "number" and tonumber(value) then
                Config[key] = tonumber(value)
            end
        end
    end
    file:close()
end

function SaveConfig()
    local file = io.open(SettingsFile, "w")
    if not file then
        return
    end
    local keys = {}
    for k in pairs(Defaults) do
        table.insert(keys, k)
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        file:write(k .. "=" .. tostring(Config[k]) .. "\n")
    end
    file:close()
end

ResetConfig()
LoadConfig()

function Airstrafe:new()
    registerForEvent("onTweak", function()
        Airstrafe.vanillaAirXY = TweakDB:GetFlat("player.locomotion.maxAirXYSpeed")
        Airstrafe.vanillaExtendedAirXY = TweakDB:GetFlat("player.locomotion.extendedMaxAirXYSpeed")
        Airstrafe:SetAirSpeedCap(Config.enabled and Config.uncapAir)
    end)

    registerForEvent("onInit", function()
        Airstrafe.input = Input:new()

        Observe("PlayerPuppet", "OnAction", function(_, action)
            if Airstrafe.input then
                Airstrafe.input:ParseAction(action)
            end
        end)

        --autohop
        Override("JumpDecisions", "EnterCondition", function(self, stateContext, scriptInterface, wrappedMethod)
            if wrappedMethod(stateContext, scriptInterface) then
                return true
            end
            if not Config.enabled or not Config.autohop or scriptInterface:GetActionValue("Jump") <= 0.0 then
                return false
            end
            if scriptInterface.localBlackboard:GetBool(Game.GetAllBlackboardDefs().PlayerStateMachine.IsPlayerInsideElevator) then
                return false
            end
            if not scriptInterface:HasStatFlag(gamedataStatType.CanJump) then
                return false
            end
            return self:IsTouchingGround(scriptInterface)
        end)

        --remove the stupid non fatal stumbles when landing from elevations
        Override("LocomotionAirDecisions", "ToRegularLand", function(self, stateContext, scriptInterface, wrappedMethod)
            if wrappedMethod(stateContext, scriptInterface) then
                return true
            end
            if not Config.enabled or not Config.noStumble then
                return false
            end
            if not self:IsTouchingGround(scriptInterface) or self:GetVerticalSpeed(scriptInterface) > 0.0 then
                return false
            end
            local landingType = self:GetLandingType(stateContext)
            return landingType == 2 or landingType == 3
        end)

        Override("LocomotionAirDecisions", "ToHardLand", function(self, stateContext, scriptInterface, wrappedMethod)
            if Config.enabled and Config.noStumble then
                return false
            end
            return wrappedMethod(stateContext, scriptInterface)
        end)

        Override("LocomotionAirDecisions", "ToVeryHardLand", function(self, stateContext, scriptInterface, wrappedMethod)
            if Config.enabled and Config.noStumble then
                return false
            end
            return wrappedMethod(stateContext, scriptInterface)
        end)

        --shotgun jumping
        ObserveAfter("ShootEvents", "OnEnter", function(_, _, scriptInterface)
            if not Config.enabled or not Config.shotgunJump then
                return
            end
            Airstrafe:ShotgunJump(scriptInterface)
        end)

        ObserveAfter("gameuiCrosshairContainerController", "OnPlayerAttach", function(self)
            Airstrafe:CreateSpeedText(self:GetRootCompoundWidget())
        end)
    end)

    registerForEvent("onShutdown", function()
        Airstrafe:SetAirSpeedCap(false)
        if Airstrafe.speedText and IsDefined(Airstrafe.speedText) then
            Airstrafe.speedText:SetVisible(false)
        end
        Airstrafe.player = nil
        Airstrafe.input = nil
    end)

    registerForEvent("onUpdate", function(delta)
        if not Config.enabled then
            Airstrafe:SetAirSpeedCap(false)
            Airstrafe:SetSpeedTextVisible(false)
            Airstrafe.accumulator = 0.0
            Airstrafe.isPlayerInAir = false
            return
        end

        Airstrafe.delta = delta
        Airstrafe.player = Game.GetPlayer()
        if not Airstrafe.player or not Airstrafe.input then
            Airstrafe.isPlayerInAir = false
            return
        end

        Airstrafe:SetSpeedTextVisible(true)
        Airstrafe:UpdateSpeedText()

        local bb = Game.GetBlackboardSystem():GetLocalInstanced(Airstrafe.player:GetEntityID(), Game.GetAllBlackboardDefs().PlayerStateMachine)
        local state = bb ~= nil and bb:GetInt(Game.GetAllBlackboardDefs().PlayerStateMachine.LocomotionDetailed) or 0
        Airstrafe.isPlayerInAir = AirStates[state] == true

        Airstrafe:SetAirSpeedCap(Config.uncapAir)

        --29 is knockdown
        if state == 29 and Airstrafe.capRaised then
            Airstrafe:ClampKnockdown()
        end

        if state == 18 and not AirStates[Airstrafe.lastState] then
            local vel = Airstrafe.player:GetVelocity()
            local takeoff = { x = vel.x, y = vel.y }
            if Config.uncapAir then
                takeoff = Airstrafe:KeepHopSpeed(takeoff)
            end
            if Config.slopeJump then
                Airstrafe:SlopeJump(takeoff)
            end
        end
        Airstrafe.lastState = state

        if Airstrafe.isPlayerInAir then
            local vel = Airstrafe.player:GetVelocity()
            Airstrafe.airVelocity = { x = vel.x, y = vel.y }
            Airstrafe.timeOnGround = 0.0
        else
            Airstrafe.timeOnGround = Airstrafe.timeOnGround + delta
        end

        if Airstrafe.isPlayerInAir then
            Airstrafe:AirMove()
        else
            Airstrafe.accumulator = 0.0
        end
    end)

    registerForEvent("onOverlayOpen", function() Airstrafe.showUI = true end)
    registerForEvent("onOverlayClose", function() Airstrafe.showUI = false end)

    registerForEvent("onDraw", function()
        if not Airstrafe.showUI then return end

        local before = {}
        for k, v in pairs(Config) do
            before[k] = v
        end

        ImGui.Begin("CyberpunkAirstrafe")

        local enabled, enabledChanged = ImGui.Checkbox("Mod enabled", Config.enabled)
        if enabledChanged then Config.enabled = enabled end

        local accel, accelChanged = ImGui.SliderFloat("sv_accelerate", Config.airAccel, 1.0, 30.0)
        if accelChanged then Config.airAccel = accel end

        local cap, capChanged = ImGui.SliderFloat("Air Speed cap", Config.airCap, 10.0, 100.0)
        if capChanged then Config.airCap = cap end

        local max, maxChanged = ImGui.SliderFloat("sv_maxspeed", Config.maxSpeed, 100.0, 640.0)
        if maxChanged then Config.maxSpeed = max end

        local hop, hopChanged = ImGui.Checkbox("Autohop", Config.autohop)
        if hopChanged then Config.autohop = hop end

        local slope, slopeChanged = ImGui.Checkbox("Slope jumping", Config.slopeJump)
        if slopeChanged then Config.slopeJump = slope end

        local uncap, uncapChanged = ImGui.Checkbox("Uncap air speed", Config.uncapAir)
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Only applies after restarting the game")
        end
        if uncapChanged then Config.uncapAir = uncap end

        local shotgun, shotgunChanged = ImGui.Checkbox("Shotgun jumping", Config.shotgunJump)
        if shotgunChanged then Config.shotgunJump = shotgun end

        local stumble, stumbleChanged = ImGui.Checkbox("No landing stumble", Config.noStumble)
        if stumbleChanged then Config.noStumble = stumble end

        if ImGui.Button("Reset to Defaults") then
            ResetConfig()
        end

        ImGui.End()

        for k, v in pairs(Config) do
            if before[k] ~= v then
                SaveConfig()
                break
            end
        end
    end)
end

--velo speedometer
function Airstrafe:CreateSpeedText(root)
    if not root then return end

    local text = inkText.new()
    text:SetName("AirstrafeSpeed")
    text:SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", "Medium")
    text:SetFontSize(58)
    text:SetTintColor(HDRColor.new({ Red = 1.0, Green = 1.0, Blue = 1.0, Alpha = 1.0 }))
    text:SetHorizontalAlignment(textHorizontalAlignment.Center)
    text:SetVerticalAlignment(textVerticalAlignment.Center)
    text:SetAnchor(inkEAnchor.Centered)
    text:SetAnchorPoint(Vector2.new({ X = 0.5, Y = 0.5 }))
    text:SetFitToContent(true)
    text:SetTranslation(Vector2.new({ X = 0.0, Y = 540.0 }))
    text:SetText("0")
    text:Reparent(root, -1)

    Airstrafe.speedText = text
    Airstrafe.shownSpeed = -1
end

function Airstrafe:SetSpeedTextVisible(visible)
    if Airstrafe.speedText and IsDefined(Airstrafe.speedText) then
        Airstrafe.speedText:SetVisible(visible)
    end
end

function Airstrafe:UpdateSpeedText()
    if not Airstrafe.speedText or not IsDefined(Airstrafe.speedText) then return end

    local vel = Airstrafe.player:GetVelocity()
    local speed = math.floor(math.sqrt(vel.x * vel.x + vel.y * vel.y) * QUAKE.unitsPerMeter + 0.5)
    if speed ~= Airstrafe.shownSpeed then
        Airstrafe.shownSpeed = speed
        Airstrafe.speedText:SetText(tostring(speed))
    end
end

--this will only apply after restart
function Airstrafe:SetAirSpeedCap(raised)
    if raised == Airstrafe.capRaised or not Airstrafe.vanillaAirXY then
        return
    end
    if raised then
        TweakDB:SetFlat("player.locomotion.maxAirXYSpeed", QUAKE.uncappedAirXY)
        TweakDB:SetFlat("player.locomotion.extendedMaxAirXYSpeed", QUAKE.uncappedAirXY)
    else
        TweakDB:SetFlat("player.locomotion.maxAirXYSpeed", Airstrafe.vanillaAirXY)
        TweakDB:SetFlat("player.locomotion.extendedMaxAirXYSpeed", Airstrafe.vanillaExtendedAirXY)
    end
    Airstrafe.capRaised = raised
end

--uncapped all session, so pull knockdowns back to the vanilla air cap otherwise if you get hit by a car you get sent to israel
function Airstrafe:ClampKnockdown()
    if Airstrafe.knockdownCooldown > 0 then
        Airstrafe.knockdownCooldown = Airstrafe.knockdownCooldown - 1
        return
    end

    local vel = Airstrafe.player:GetVelocity()
    local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
    local limit = Airstrafe.vanillaAirXY
    if speed <= limit then
        return
    end
    local scale = limit / speed
    Airstrafe:AddImpulse(Vector4.new(vel.x * scale - vel.x, vel.y * scale - vel.y, 0.0, 0.0))
    Airstrafe.knockdownCooldown = 2
end

--halftick of sv_user.c SV_UserFriction
function Airstrafe:KeepHopSpeed(current)
    local air = Airstrafe.airVelocity
    if not air or Airstrafe.timeOnGround > QUAKE.hopWindow then
        return current
    end

    local u = QUAKE.unitsPerMeter
    local speed = math.sqrt(air.x * air.x + air.y * air.y) * u
    if speed < 1.0 then
        return current
    end
    local control = math.max(speed, QUAKE.stopSpeed)
    local newspeed = math.max(speed - QUAKE.frameTime * 0.5 * control * QUAKE.friction, 0.0)
    local scale = newspeed / speed
    local target = { x = air.x * scale, y = air.y * scale }

    local currentSpeed = math.sqrt(current.x * current.x + current.y * current.y) * u
    if newspeed <= currentSpeed then
        return current
    end
    Airstrafe:AddImpulse(Vector4.new(target.x - current.x, target.y - current.y, 0.0, 0.0))
    return target
end

--slope jumping, very scuffed sv_phys.c
function Airstrafe:SlopeJump(vel)
    local pos = Airstrafe.player:GetWorldPosition()
    local from = Vector4.new(pos.x, pos.y, pos.z + 0.5, 1.0)
    local to = Vector4.new(pos.x, pos.y, pos.z - 0.5, 1.0)
    local sqs = Game.GetSpatialQueriesSystem()
    local hit, result = sqs:SyncRaycastByCollisionGroup(from, to, "Static", false, false)
    if not hit then
        hit, result = sqs:SyncRaycastByCollisionPreset(from, to, "World Dynamic", false, false)
    end
    if not hit or not result then
        return
    end

    local n = result.normal
    if n.z <= QUAKE.standable or n.z >= 0.999 then
        return
    end

    local backoff = vel.x * n.x + vel.y * n.y
    if backoff >= 0 then
        return
    end
    Airstrafe:AddImpulse(Vector4.new(-n.x * backoff, -n.y * backoff, -n.z * backoff, 0.0))
end

function Airstrafe:ShotgunJump(scriptInterface)
    local player = Game.GetPlayer()
    if not player or not scriptInterface.executionOwner or not scriptInterface.executionOwner:IsPlayer() then
        return
    end

    local ok, isShotgun = pcall(function()
        local weapon = Game.GetTransactionSystem():GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight"))
        return weapon ~= nil and weapon:IsShotgun()
    end)
    if not ok or not isShotgun then
        return
    end

    local camera = scriptInterface:GetCameraWorldTransform()
    local from = Transform.GetPosition(camera)
    local aim = Transform.GetForward(camera)
    local range = 240.0 / QUAKE.unitsPerMeter
    local to = Vector4.new(from.x + aim.x * range, from.y + aim.y * range, from.z + aim.z * range, 1.0)
    local sqs = Game.GetSpatialQueriesSystem()
    local hit, result = sqs:SyncRaycastByCollisionGroup(from, to, "Static", false, false)
    if not hit then
        hit, result = sqs:SyncRaycastByCollisionPreset(from, to, "World Dynamic", false, false)
    end
    if not hit or not result then
        return
    end

    local p = result.position
    local dx, dy, dz = p.x - from.x, p.y - from.y, p.z - from.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz) * QUAKE.unitsPerMeter
    local points = (QUAKE.rocketDamage - 0.5 * dist) * 0.5
    if points <= 0 then
        return
    end

    local push = points * QUAKE.rocketKnockback / QUAKE.unitsPerMeter
    Airstrafe.player = player
    Airstrafe:AddImpulse(Vector4.new(-aim.x * push, -aim.y * push, -aim.z * push, 0.0))
end

--mathlib.c AngleVectors
function AngleVectors(angles)
    local sy, cy = math.sin(math.rad(angles.yaw)), math.cos(math.rad(angles.yaw))
    local sp, cp = math.sin(math.rad(angles.pitch)), math.cos(math.rad(angles.pitch))
    local sr, cr = math.sin(math.rad(angles.roll)), math.cos(math.rad(angles.roll))

    local forward = { x = cp * cy, y = cp * sy, z = -sp }
    local right = {
        x = -1 * sr * sp * cy + -1 * cr * -sy,
        y = -1 * sr * sp * sy + -1 * cr * cy,
        z = -1 * sr * cp
    }
    return forward, right
end

--view.c V_CalcRoll
function CalcRoll(angles, velocity)
    local _, right = AngleVectors(angles)
    local side = velocity.x * right.x + velocity.y * right.y + velocity.z * right.z
    local sign = side < 0 and -1 or 1
    side = math.abs(side)
    if side < QUAKE.rollSpeed then
        side = side * QUAKE.rollAngle / QUAKE.rollSpeed
    else
        side = QUAKE.rollAngle
    end
    return side * sign
end

function Airstrafe:AirMove()
    Airstrafe.accumulator = math.min(Airstrafe.accumulator + Airstrafe.delta, QUAKE.frameTimeMax)
    if Airstrafe.accumulator < QUAKE.frameTime then
        return
    end

    local inputVec = Airstrafe.input:GetInputVector()
    local fmove = inputVec.y * (inputVec.y >= 0 and QUAKE.forwardSpeed or QUAKE.backSpeed)
    local smove = inputVec.x * QUAKE.sideSpeed

    -- v_angle from the cam
    local camForward = Game.GetCameraSystem():GetActiveCameraForward()
    if math.abs(camForward.x) < 0.001 and math.abs(camForward.y) < 0.001 then
        camForward = Airstrafe.player:GetWorldForward()
    end
    local viewYaw = math.deg(atan2(camForward.y, camForward.x))
    local viewPitch = math.deg(math.asin(math.max(-1.0, math.min(1.0, -camForward.z))))

    local u = QUAKE.unitsPerMeter
    local prevMove = Airstrafe.player:GetVelocity()
    local start = { x = prevMove.x * u, y = prevMove.y * u, z = prevMove.z * u }
    local velocity = { x = start.x, y = start.y, z = start.z }

    while Airstrafe.accumulator >= QUAKE.frameTime do
        Airstrafe.accumulator = Airstrafe.accumulator - QUAKE.frameTime

        --SV_ClientThinks angles[ROLL] = V_CalcRoll*4, angles[PITCH] = -v_angle[PITCH]/3
        local angles = Airstrafe.angles
        angles.roll = CalcRoll(angles, velocity) * 4.0
        angles.pitch = -viewPitch / 3.0
        angles.yaw = viewYaw

        --SV_AirMove
        local forward, right = AngleVectors(angles)
        local wishVel = {
            x = forward.x * fmove + right.x * smove,
            y = forward.y * fmove + right.y * smove
        }
        local wishSpeed = math.sqrt(wishVel.x * wishVel.x + wishVel.y * wishVel.y)
        if wishSpeed > Config.maxSpeed then
            wishVel.x = wishVel.x * Config.maxSpeed / wishSpeed
            wishVel.y = wishVel.y * Config.maxSpeed / wishSpeed
            wishSpeed = Config.maxSpeed
        end

        if wishSpeed > 0 then
            local wishDir = { x = wishVel.x / wishSpeed, y = wishVel.y / wishSpeed }
            Airstrafe:AirAccelerate(wishDir, velocity, wishSpeed, Config.airAccel)
        end
    end

    --apply the velo delta in m/s as impulse
    local nextMove = Vector4.new((velocity.x - start.x) / u, (velocity.y - start.y) / u, 0.0, 0.0)
    if nextMove.x ~= 0.0 or nextMove.y ~= 0.0 then
        Airstrafe:AddImpulse(nextMove)
    end
end

--SV_AirAccel
function Airstrafe:AirAccelerate(wishDir, velocity, wishSpeed, accel)
    local wishSpd = math.min(wishSpeed, Config.airCap)
    local currSpeed = velocity.x * wishDir.x + velocity.y * wishDir.y
    local addSpeed = wishSpd - currSpeed

    if addSpeed <= 0 then
        return
    end

    local accelSpeed = math.min(accel * wishSpeed * QUAKE.frameTime, addSpeed)
    velocity.x = velocity.x + accelSpeed * wishDir.x
    velocity.y = velocity.y + accelSpeed * wishDir.y
end

function Airstrafe:AddImpulse(vec)
    local impulseEvent = PSMImpulse.new()
    impulseEvent.id = "impulse"
    impulseEvent.impulse = vec
    Airstrafe.player:QueueEvent(impulseEvent)
end

return Airstrafe:new()