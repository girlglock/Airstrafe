Airstrafe = {
    description = "Airstrafing!",
    player = nil,
    input = nil,
    isPlayerInAir = false,
    delta = 0.0
}

Config = {
    wishSpeed = 1.0,
    airAccel = 150.0
}

require("input")

function Airstrafe:new()
    registerForEvent("onInit", function()
        Airstrafe.player = Game.GetPlayer()
        Airstrafe.input = Input:new()

        Observe('QuestTrackerGameController', 'OnInitialize', function()
            Airstrafe.player = Game.GetPlayer()
        end)

        Observe("PlayerPuppet", "OnAction", function(_, action)
            Airstrafe.input:ParseAction(action)
        end)
        
        Observe("PlayerPuppet", "OnLocomotionStateChanged", function()
            local locomotionState = Game.GetBlackboardSystem():GetLocalInstanced(Airstrafe.player:GetEntityID(), Game.GetAllBlackboardDefs().PlayerStateMachine):GetInt(Game.GetAllBlackboardDefs().PlayerStateMachine.LocomotionDetailed)
            Airstrafe.isPlayerInAir = locomotionState == EnumInt(gamePSMDetailedLocomotionStates.Jump) or locomotionState == EnumInt(gamePSMDetailedLocomotionStates.DoubleJump) or locomotionState == EnumInt(gamePSMDetailedLocomotionStates.ChargeJump) or locomotionState == EnumInt(gamePSMDetailedLocomotionStates.Fall)
        end)
    end)

    registerForEvent("onShutdown", function()
        Airstrafe.player = nil
        Airstrafe.input = nil
    end)

    registerForEvent("onUpdate", function(delta)
        Airstrafe.delta = delta
        if Airstrafe.isPlayerInAir then
            Airstrafe:AirMove()
        end
    end)
end

function Airstrafe:AirMove()
    local inputVec = Vector4.Normalize(Airstrafe.input:GetInputVector())
    local yaw = Airstrafe.player:GetWorldYaw()
    local wishDir = Vector4.RotateAxis(inputVec, Airstrafe.player:GetWorldUp(), yaw * math.pi / 180.0)
    local prevMove = Airstrafe.player:GetVelocity()
    prevMove = Vector4.new(prevMove.x, prevMove.y, 0.0, 0.0);
    local nextMove = Airstrafe:AirAccelerate(wishDir, prevMove, Config.wishSpeed, Config.airAccel)
    Airstrafe:AddImpulse(nextMove)
end

function Airstrafe:AirAccelerate(wishDir, prevVelocity, wishSpeed, accel)
    local currSpeed = Vector4.Dot(prevVelocity, wishDir)
    local addSpeed = wishSpeed - currSpeed

    if addSpeed <= 0 then
        return Vector4.Zero()
    end

    local accelSpeed = accel * wishSpeed * Airstrafe.delta
    accelSpeed = math.min(accelSpeed, addSpeed)
    return MultiplyVector(wishDir, accelSpeed)
end

function Airstrafe:AddImpulse(vec)
    local impulseEvent = PSMImpulse.new()
    impulseEvent.id = "impulse"
    impulseEvent.impulse = vec
    Airstrafe.player:QueueEvent(impulseEvent)
end

function MultiplyVector(vec, mult)
    return Vector4.new(vec.x * mult, vec.y * mult, vec.z * mult, vec.w * mult)
end

return Airstrafe:new()