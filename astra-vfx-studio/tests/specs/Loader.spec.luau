--!strict
-- The Lune loader mirrors Rojo: *.vfx.json (syncRules "text") becomes a StringValue holding the raw file text.
return function(T: any, _use: (string) -> any, ctx: any)
	T.itIf(ctx.environment == "lune", "maps *.vfx.json presets to StringValues (Rojo syncRules)", function()
		local presets = ctx.loader:resolve("Presets")
		for _, child in presets:GetChildren() do
			if child:IsA("StringValue") then
				T.expect(string.sub(child.Name, -4)).never.toBe("json")
				T.expect(string.sub(child.Value, 1, 1)).toBe("{")
			end
		end
	end)
end
