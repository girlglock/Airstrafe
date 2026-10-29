Input = {}

function Input:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj.moveLeft = false
    obj.moveRight = false
    obj.moveForward = false
    obj.moveBackward = false
    --controlla
    obj.axisX = 0.0
    obj.axisY = 0.0

    return obj
end

function Input:ParseAction(action)
    local actionName = Game.NameToString(action:GetName())

    if actionName == "MoveX" or actionName == "MoveY" then
        local ok, value = pcall(function() return action:GetValue() end)
        if not ok or type(value) ~= "number" then
            return
        end
        if actionName == "MoveX" then
            self.axisX = value
        else
            self.axisY = value
        end
        return
    end

    local ok, actionType = pcall(function() return action:GetType(action).value end)
    if not ok then
        ok, actionType = pcall(function() return action:GetType().value end)
        if not ok then
            return
        end
    end
    local pressed = actionType == "BUTTON_PRESSED"
    local released = actionType == "BUTTON_RELEASED"

    if actionName == "Left" then
        if pressed then
            self.moveLeft = true
        elseif released then
            self.moveLeft = false
        end
    elseif actionName == "Right" then
        if pressed then
            self.moveRight = true
        elseif released then
            self.moveRight = false
        end
    elseif actionName == "Forward" then
        if pressed then
            self.moveForward = true
        elseif released then
            self.moveForward = false
        end
    elseif actionName == "Back" then
        if pressed then
            self.moveBackward = true
        elseif released then
            self.moveBackward = false
        end
    end
end

function Input:GetInputVector()
    local x = 0.0
    local y = 0.0

    if self.moveBackward then
        y = y - 1.0
    end

    if self.moveForward then
        y = y + 1.0
    end

    if self.moveLeft then
        x = x - 1.0
    end

    if self.moveRight then
        x = x + 1.0
    end

    if x == 0.0 and y == 0.0 then
        x = self.axisX
        y = self.axisY
    end

    return Vector4.new(x, y, 0.0, 0.0)
end