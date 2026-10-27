--!strict
--[[
	New — declarative instance construction.

		local button = New("TextButton", {
			Size = UDim2.new(0, 80, 0, 24),
			Text = "Play",
			OnActivated = function() editor:play() end,       -- connects button.Activated
			OnChangeText = function(text) ... end,             -- GetPropertyChangedSignal("Text"), passes the new value
			Parent = frame,                                    -- always applied last
		}, {
			New("UICorner", { CornerRadius = UDim.new(0, 4) }),
		})

	Connections made through On* keys belong to the instance and are disconnected by Roblox when it is destroyed.
	Property names and values are validated by the engine (and by Lune's reflection database in tests).
]]

local function apply(inst: Instance, props: { [string]: any })
	local target = inst :: any
	local parent = nil
	for key, value in pairs(props) do
		if key == "Parent" then
			parent = value
		elseif string.sub(key, 1, 8) == "OnChange" and #key > 8 then
			local property = string.sub(key, 9)
			inst:GetPropertyChangedSignal(property):Connect(function()
				value(target[property])
			end)
		elseif string.sub(key, 1, 2) == "On" and #key > 2 then
			local eventName = string.sub(key, 3)
			target[eventName]:Connect(value)
		else
			target[key] = value
		end
	end
	return parent
end

local function New(className: string, props: { [string]: any }?, children: { Instance? }?): any
	local inst = Instance.new(className)
	local parent = if props then apply(inst, props) else nil
	if children then
		for _, child in pairs(children) do
			if child then
				child.Parent = inst
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

return New
