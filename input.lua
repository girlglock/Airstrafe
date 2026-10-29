Input = {}

function Input:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    obj.moveLeft = false
    obj.moveRight = false
    obj.moveForward = false
    obj.moveBackward = false

    return obj
end

function Input:ParseAction(action)
    local actionName = Game.NameToString(action:GetName())
    local actionType = action:GetType(action).value
    local pressed = actionType == "BUTTON_PRESSED"
    local released = actionType == "BUTTON_RELEASED"

    self.horizontalAxis = 0.0
    self.verticalAxis = 0.0

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

    return Vector4.new(x, y, 0.0, 0.0)
end