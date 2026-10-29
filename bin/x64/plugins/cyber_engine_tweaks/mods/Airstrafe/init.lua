-- original mod was made by teetoxd on nexusmods https://www.nexusmods.com/cyberpunk2077/mods/5816
-- updated for game ver 2.5 by girlglock with many tweaks in attempt to make the air movement closer to quake/hl1

Airstrafe = {
    description = "Airstrafing!",
    player = nil,
    input = nil,
    isPlayerInAir = false,
    delta = 0.0,
    accumulator = 0.0,  -- unsimmed time at 72t
    angles = { pitch = 0.0, yaw = 0.0, roll = 0.0 }, -- sv_player->v.angles
    speedText = nil,
    shownSpeed = -1,
    showUI = false
}

Defaults = {
    airAccel = 10.0,    --sv_accelerate
    airCap = 30.0,      --wishspd in SV_AirAccelerate
    maxSpeed = 320.0,   --sv_maxspeed
    autohop = true      --holding jump jumps again on landing
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
    unitsPerMeter = 32.0    --1u = 1/32m (56u player = 1,75m)
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

ResetConfig()

function Airstrafe:new()
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
            if not Config.autohop or scriptInterface:GetActionValue("Jump") <= 0.0 then
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

        ObserveAfter("gameuiCrosshairContainerController", "OnPlayerAttach", function(self)
            Airstrafe:CreateSpeedText(self:GetRootCompoundWidget())
        end)
    end)

    registerForEvent("onShutdown", function()
        if Airstrafe.speedText and IsDefined(Airstrafe.speedText) then
            Airstrafe.speedText:SetVisible(false)
        end
        Airstrafe.player = nil
        Airstrafe.input = nil
    end)

    registerForEvent("onUpdate", function(delta)
        Airstrafe.delta = delta
        Airstrafe.player = Game.GetPlayer()
        if not Airstrafe.player or not Airstrafe.input then
            Airstrafe.isPlayerInAir = false
            return
        end

        Airstrafe:UpdateSpeedText()

        local bb = Game.GetBlackboardSystem():GetLocalInstanced(Airstrafe.player:GetEntityID(), Game.GetAllBlackboardDefs().PlayerStateMachine)
        Airstrafe.isPlayerInAir = bb ~= nil and AirStates[bb:GetInt(Game.GetAllBlackboardDefs().PlayerStateMachine.LocomotionDetailed)] == true

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

        ImGui.Begin("Airstrafe")

        local accel, accelChanged = ImGui.SliderFloat("sv_accelerate", Config.airAccel, 1.0, 30.0)
        if accelChanged then Config.airAccel = accel end

        local cap, capChanged = ImGui.SliderFloat("Air Speed cap", Config.airCap, 10.0, 100.0)
        if capChanged then Config.airCap = cap end

        local max, maxChanged = ImGui.SliderFloat("sv_maxspeed", Config.maxSpeed, 100.0, 640.0)
        if maxChanged then Config.maxSpeed = max end

        local hop, hopChanged = ImGui.Checkbox("Autohop", Config.autohop)
        if hopChanged then Config.autohop = hop end

        if ImGui.Button("Reset to Defaults") then
            ResetConfig()
        end

        ImGui.End()
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

function Airstrafe:UpdateSpeedText()
    if not Airstrafe.speedText or not IsDefined(Airstrafe.speedText) then return end

    local vel = Airstrafe.player:GetVelocity()
    local speed = math.floor(math.sqrt(vel.x * vel.x + vel.y * vel.y) * QUAKE.unitsPerMeter + 0.5)
    if speed ~= Airstrafe.shownSpeed then
        Airstrafe.shownSpeed = speed
        Airstrafe.speedText:SetText(tostring(speed))
    end
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