--!strict
return function(T: any, use: (string) -> any, ctx: any)
	local Quality = use("AstraVFX.Core.Quality")
	local Env = use("AstraVFX.Core.Env")
	local Constants = use("AstraVFX.Core.Constants")
	local isLune = ctx.environment == "lune"

	-- Builds a mixed-type array (the type checker infers homogeneous arrays from literals).
	local function L(...: any): { any }
		return { ... }
	end

	local LEVELS = { "Low", "Medium", "High" }

	-- Fake RunService answering the run-context flags.
	local function runService(flags: { [string]: boolean }): any
		local fake: any = {}
		for _, method in { "IsStudio", "IsRunning", "IsClient", "IsServer", "IsEdit" } do
			fake[method] = function(_self: any): boolean
				return flags[method] == true
			end
		end
		return fake
	end

	local LIVE_CLIENT = { IsClient = true, IsServer = false, IsStudio = false, IsRunning = true }

	-- Loads a private copy of Quality whose `UserSettings` global is `userSettings` (Lune loader internals).
	local canIsolate = isLune and ctx.loader ~= nil and ctx.loader._compile ~= nil
	local function isolatedQuality(userSettings: any): any
		local loader = ctx.loader
		return loader:_compile(loader:resolve("AstraVFX.Core.Quality"), { UserSettings = userSettings })()
	end
	local function settingsReturning(value: any): () -> any
		local gameSettings = { SavedQualityLevel = value }
		local settings = {
			GetService = function(_self: any, name: string): any
				assert(name == "UserGameSettings", "unexpected service " .. name)
				return gameSettings
			end,
		}
		return function(): any
			return settings
		end
	end

	T.describe("Quality", function()
		T.beforeEach(function()
			Env.reset()
		end)
		T.afterEach(function()
			Env.reset()
		end)

		T.describe("PROFILES", function()
			T.it("matches ARCHITECTURE §5.4", function()
				T.expect(Quality.PROFILES.Low).toEqual({
					level = "Low",
					countScale = 0.35,
					segmentScale = 0.5,
					sizeCompensation = 1.12,
					lightShadows = false,
					maxLights = 2,
				})
				T.expect(Quality.PROFILES.Medium).toEqual({
					level = "Medium",
					countScale = 0.65,
					segmentScale = 0.75,
					sizeCompensation = 1.05,
					lightShadows = false,
					maxLights = 4,
				})
				T.expect(Quality.PROFILES.High).toEqual({
					level = "High",
					countScale = 1,
					segmentScale = 1,
					sizeCompensation = 1,
					lightShadows = true,
					maxLights = math.huge,
				})
				T.expect(Quality.UNLIMITED).toBe(math.huge)
			end)

			T.it("covers exactly Constants.QUALITY_LEVELS, in order", function()
				T.expect(Quality.LEVELS).toEqual(Constants.QUALITY_LEVELS)
				local count = 0
				for level, profile in Quality.PROFILES do
					count += 1
					T.expect(profile.level).toBe(level)
				end
				T.expect(count).toBe(3)
			end)

			T.it("is frozen", function()
				T.expect(table.isfrozen(Quality.PROFILES)).toBe(true)
				for _, level in LEVELS do
					T.expect(table.isfrozen(Quality.PROFILES[level])).toBe(true)
				end
				T.expect(function()
					(Quality.PROFILES.Low :: any).countScale = 2
				end).toThrow()
				T.expect(Quality.PROFILES.Low.countScale).toBe(0.35)
			end)

			T.it("scales monotonically from Low to High", function()
				local low, medium, high = Quality.PROFILES.Low, Quality.PROFILES.Medium, Quality.PROFILES.High
				T.expect(low.countScale < medium.countScale and medium.countScale < high.countScale).toBe(true)
				T.expect(low.segmentScale < medium.segmentScale and medium.segmentScale < high.segmentScale).toBe(true)
				T.expect(low.sizeCompensation > medium.sizeCompensation).toBe(true)
				T.expect(medium.sizeCompensation > high.sizeCompensation).toBe(true)
				T.expect(low.maxLights < medium.maxLights and medium.maxLights < high.maxLights).toBe(true)
			end)
		end)

		T.describe("resolve", function()
			T.it("returns a copy of the named profile", function()
				for _, level in LEVELS do
					local profile = Quality.resolve(level)
					T.expect(profile).toEqual(Quality.PROFILES[level])
					T.expect(profile == Quality.PROFILES[level]).toBe(false)
					T.expect(table.isfrozen(profile)).toBe(false)
				end
			end)

			T.it("returns independent copies that callers may modify", function()
				local a = Quality.resolve("Low")
				a.countScale = 99
				T.expect(Quality.resolve("Low").countScale).toBe(0.35)
				T.expect(Quality.PROFILES.Low.countScale).toBe(0.35)
			end)

			T.it("uses detect() for nil and Auto", function()
				local expected = Quality.detect()
				T.expect(Quality.resolve(nil).level).toBe(expected)
				T.expect(Quality.resolve("Auto").level).toBe(expected)
				T.expect(Quality.resolve().level).toBe(expected)
			end)

			T.it("resolves Auto to Medium outside a live client", function()
				Env.override("RunService", runService({ IsServer = true }))
				T.expect(Quality.resolve("Auto")).toEqual(Quality.PROFILES.Medium)
			end)

			T.it("merges the override of the resolved level only", function()
				local overrides = {
					Low = { countScale = 0.2, maxLights = 1 },
					High = { lightShadows = false },
				}
				local low = Quality.resolve("Low", overrides)
				T.expect(low.countScale).toBe(0.2)
				T.expect(low.maxLights).toBe(1)
				T.expect(low.segmentScale).toBe(0.5)
				T.expect(low.sizeCompensation).toBe(1.12)
				T.expect(low.lightShadows).toBe(false)
				T.expect(Quality.resolve("Medium", overrides)).toEqual(Quality.PROFILES.Medium)
				local high = Quality.resolve("High", overrides)
				T.expect(high.lightShadows).toBe(false)
				T.expect(high.countScale).toBe(1)
				T.expect(high.maxLights).toBe(math.huge)
			end)

			T.it("accepts every field of an override", function()
				local medium = Quality.resolve("Medium", {
					Medium = {
						countScale = 1.5,
						segmentScale = 0,
						sizeCompensation = 2,
						lightShadows = true,
						maxLights = 0,
					},
				})
				T.expect(medium).toEqual({
					level = "Medium",
					countScale = 1.5,
					segmentScale = 0,
					sizeCompensation = 2,
					lightShadows = true,
					maxLights = 0,
				})
				local unlimited = Quality.resolve("Low", { Low = { maxLights = math.huge, countScale = 0 } })
				T.expect(unlimited.maxLights).toBe(math.huge)
				T.expect(unlimited.countScale).toBe(0)
			end)

			T.it("ignores invalid override values field by field", function()
				local bad: any = {
					Low = {
						countScale = -0.1,
						segmentScale = 0 / 0,
						sizeCompensation = 0,
						lightShadows = "yes",
						maxLights = 2.5,
					},
				}
				T.expect(Quality.resolve("Low", bad)).toEqual(Quality.PROFILES.Low)
				local mixed: any = { Low = { countScale = math.huge, segmentScale = 0.25, maxLights = -1 } }
				local low = Quality.resolve("Low", mixed)
				T.expect(low.countScale).toBe(0.35)
				T.expect(low.segmentScale).toBe(0.25)
				T.expect(low.maxLights).toBe(2)
				local strings: any = { High = { countScale = "0.5", sizeCompensation = -math.huge, maxLights = "3" } }
				T.expect(Quality.resolve("High", strings)).toEqual(Quality.PROFILES.High)
			end)

			T.it("ignores unknown fields, the level field and malformed override maps", function()
				local overrides: any = { Low = { level = "High", bogus = 5, countScale = 0.3 } }
				local low = Quality.resolve("Low", overrides)
				T.expect(low.level).toBe("Low")
				T.expect((low :: any).bogus).toBeNil()
				T.expect(low.countScale).toBe(0.3)
				for _, malformed in L(5, "Low", { Low = 3 }, { Low = "x" }, { low = { countScale = 0.1 } }) do
					T.expect(Quality.resolve("Low", malformed :: any)).toEqual(Quality.PROFILES.Low)
				end
				T.expect(Quality.resolve("Low", { Auto = { countScale = 0.1 } } :: any)).toEqual(Quality.PROFILES.Low)
			end)

			T.it("accepts a profile table as the base (invalid fields fall back to the level's profile)", function()
				local custom = Quality.resolve({
					level = "High",
					countScale = 0.8,
					segmentScale = 0.9,
					sizeCompensation = 1.01,
					lightShadows = false,
					maxLights = 6,
				})
				T.expect(custom).toEqual({
					level = "High",
					countScale = 0.8,
					segmentScale = 0.9,
					sizeCompensation = 1.01,
					lightShadows = false,
					maxLights = 6,
				})
				local partial = Quality.resolve({ level = "Medium", countScale = -5 } :: any)
				T.expect(partial).toEqual(Quality.PROFILES.Medium)
				local withOverride = Quality.resolve(custom, { High = { maxLights = 3 } })
				T.expect(withOverride.maxLights).toBe(3)
				T.expect(withOverride.countScale).toBe(0.8)
				T.expect(custom.maxLights).toBe(6)
			end)

			T.it("errors for unknown levels and wrong types", function()
				T.expect(function()
					Quality.resolve("Ultra" :: any)
				end).toThrow('unknown quality level "Ultra"')
				T.expect(function()
					Quality.resolve("high" :: any)
				end).toThrow("unknown quality level")
				T.expect(function()
					Quality.resolve(3 :: any)
				end).toThrow("expected a quality level or profile")
				T.expect(function()
					Quality.resolve({ level = "Ultra" } :: any)
				end).toThrow("unknown level")
			end)
		end)

		T.describe("fromSavedQualityLevel", function()
			T.it("maps every Enum.SavedQualitySetting item", function()
				local expected = {
					Automatic = "Medium",
					QualityLevel1 = "Low",
					QualityLevel2 = "Low",
					QualityLevel3 = "Low",
					QualityLevel4 = "Medium",
					QualityLevel5 = "Medium",
					QualityLevel6 = "Medium",
					QualityLevel7 = "Medium",
					QualityLevel8 = "High",
					QualityLevel9 = "High",
					QualityLevel10 = "High",
				}
				local items = Enum.SavedQualitySetting:GetEnumItems()
				T.expect(#items).toBe(11)
				for _, item in items do
					T.expect(Quality.fromSavedQualityLevel(item)).toBe(expected[item.Name])
					T.expect(Quality.fromSavedQualityLevel(item.Name)).toBe(expected[item.Name])
					T.expect(Quality.fromSavedQualityLevel(item.Value)).toBe(expected[item.Name])
				end
			end)

			T.it("returns nil for unrecognised values", function()
				for _, value in
					L(11, -1, 2.5, 0 / 0, math.huge, "QualityLevel11", "QualityLevel0", "High", "", {}, true)
				do
					T.expect(Quality.fromSavedQualityLevel(value)).toBeNil()
				end
				T.expect(Quality.fromSavedQualityLevel(nil)).toBeNil()
				T.expect(Quality.fromSavedQualityLevel(Enum.Material.Plastic)).toBeNil()
			end)
		end)

		T.describe("detect", function()
			T.it("never errors and returns Medium in the test environment", function()
				T.expect(Quality.detect()).toBe("Medium")
			end)

			T.it("returns Medium on servers and in Studio", function()
				Env.override("RunService", runService({ IsServer = true, IsRunning = true }))
				T.expect(Quality.detect()).toBe("Medium")
				Env.override("RunService", runService({ IsClient = true, IsServer = true, IsStudio = true }))
				T.expect(Quality.detect()).toBe("Medium")
				Env.override("RunService", runService({ IsClient = true, IsStudio = true, IsRunning = true }))
				T.expect(Quality.detect()).toBe("Medium")
			end)

			T.it("returns Medium when RunService is unusable", function()
				Env.override("RunService", {})
				T.expect(Quality.detect()).toBe("Medium")
				Env.override("RunService", 5)
				T.expect(Quality.detect()).toBe("Medium")
			end)

			T.itIf(isLune, "falls back to Medium on a client without UserSettings (Lune)", function()
				Env.override("RunService", runService(LIVE_CLIENT))
				T.expect(Quality.detect()).toBe("Medium")
			end)

			T.itIf(canIsolate, "reads SavedQualityLevel on a live client", function()
				Env.override("RunService", runService(LIVE_CLIENT))
				local S = Enum.SavedQualitySetting
				local cases: { { setting: EnumItem, level: string } } = {
					{ setting = S.QualityLevel1, level = "Low" },
					{ setting = S.QualityLevel3, level = "Low" },
					{ setting = S.QualityLevel4, level = "Medium" },
					{ setting = S.QualityLevel7, level = "Medium" },
					{ setting = S.QualityLevel8, level = "High" },
					{ setting = S.QualityLevel10, level = "High" },
					{ setting = S.Automatic, level = "Medium" },
				}
				for _, case in cases do
					local fresh = isolatedQuality(settingsReturning(case.setting))
					T.expect(fresh.detect()).toBe(case.level)
					T.expect(fresh.resolve("Auto").level).toBe(case.level)
				end
			end)

			T.itIf(canIsolate, "does not read the setting outside a live client", function()
				local reads = 0
				local fresh = isolatedQuality(function(): any
					reads += 1
					return settingsReturning(Enum.SavedQualitySetting.QualityLevel1)()
				end)
				Env.override("RunService", runService({ IsServer = true }))
				T.expect(fresh.detect()).toBe("Medium")
				Env.override("RunService", runService({ IsClient = true, IsStudio = true }))
				T.expect(fresh.detect()).toBe("Medium")
				T.expect(reads).toBe(0)
				Env.override("RunService", runService(LIVE_CLIENT))
				T.expect(fresh.detect()).toBe("Low")
				T.expect(reads).toBe(1)
			end)

			T.itIf(canIsolate, "falls back to Medium when reading the setting fails", function()
				Env.override("RunService", runService(LIVE_CLIENT))
				local throwing = isolatedQuality(function(): any
					error("The current thread cannot access 'UserGameSettings'")
				end)
				T.expect(throwing.detect()).toBe("Medium")
				local noService = isolatedQuality(function(): any
					return {
						GetService = function(): any
							error("not a service")
						end,
					}
				end)
				T.expect(noService.detect()).toBe("Medium")
				T.expect(isolatedQuality(settingsReturning(nil)).detect()).toBe("Medium")
				T.expect(isolatedQuality(settingsReturning("garbage")).detect()).toBe("Medium")
				T.expect(isolatedQuality(settingsReturning(42)).detect()).toBe("Medium")
			end)
		end)

		T.describe("rank / includes / isLevel", function()
			T.it("ranks Low 1, Medium 2, High 3", function()
				T.expect(Quality.rank("Low")).toBe(1)
				T.expect(Quality.rank("Medium")).toBe(2)
				T.expect(Quality.rank("High")).toBe(3)
			end)

			T.it("errors when ranking unknown levels", function()
				for _, bad in L("Auto", "low", "", 2, {}) do
					T.expect(function()
						Quality.rank(bad :: any)
					end).toThrow("unknown quality level")
				end
				T.expect(function()
					Quality.rank(nil :: any)
				end).toThrow("unknown quality level")
			end)

			T.it("includes components whose minQuality is at or below the level", function()
				local expected = {
					Low = { Low = true, Medium = false, High = false },
					Medium = { Low = true, Medium = true, High = false },
					High = { Low = true, Medium = true, High = true },
				}
				for _, level in LEVELS do
					T.expect(Quality.includes(level, nil)).toBe(true)
					T.expect(Quality.includes(level)).toBe(true)
					for _, minQuality in LEVELS do
						T.expect(Quality.includes(level, minQuality)).toBe(expected[level][minQuality])
					end
				end
			end)

			T.it("errors for unknown levels in includes", function()
				T.expect(function()
					Quality.includes("Ultra" :: any, "Low")
				end).toThrow("unknown quality level")
				T.expect(function()
					Quality.includes("High", "Ultra" :: any)
				end).toThrow("unknown minQuality")
				T.expect(function()
					Quality.includes(nil :: any)
				end).toThrow("unknown quality level")
			end)

			T.it("recognises valid level names only", function()
				for _, level in LEVELS do
					T.expect(Quality.isLevel(level)).toBe(true)
				end
				for _, bad in L("Auto", "low", "HIGH", "", 1, {}) do
					T.expect(Quality.isLevel(bad)).toBe(false)
				end
				T.expect(Quality.isLevel(nil)).toBe(false)
			end)

			T.it("validates single override values", function()
				T.expect(Quality.isValidOverride("countScale", 0)).toBe(true)
				T.expect(Quality.isValidOverride("countScale", -1)).toBe(false)
				T.expect(Quality.isValidOverride("sizeCompensation", 0)).toBe(false)
				T.expect(Quality.isValidOverride("sizeCompensation", 0.5)).toBe(true)
				T.expect(Quality.isValidOverride("lightShadows", false)).toBe(true)
				T.expect(Quality.isValidOverride("lightShadows", 0)).toBe(false)
				T.expect(Quality.isValidOverride("maxLights", 3)).toBe(true)
				T.expect(Quality.isValidOverride("maxLights", math.huge)).toBe(true)
				T.expect(Quality.isValidOverride("maxLights", 3.5)).toBe(false)
				T.expect(Quality.isValidOverride("level", "Low")).toBe(false)
				T.expect(Quality.isValidOverride("unknown", 1)).toBe(false)
				T.expect(Quality.OVERRIDE_FIELDS).toEqual({
					"countScale",
					"segmentScale",
					"sizeCompensation",
					"lightShadows",
					"maxLights",
				})
			end)
		end)
	end)
end
