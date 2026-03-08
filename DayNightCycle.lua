local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CYCLE_DURATION = 240
local TIME_START = 6
local STAR_COUNT = 60
local STAR_FADE_SPEED = 0.04

local SKY_COLORS = {
	dawn  = { ambient = Color3.fromRGB(255, 180, 120), outdoor = Color3.fromRGB(255, 160, 100), fog = Color3.fromRGB(255, 200, 160) },
	day   = { ambient = Color3.fromRGB(180, 210, 255), outdoor = Color3.fromRGB(140, 180, 255), fog = Color3.fromRGB(200, 220, 255) },
	dusk  = { ambient = Color3.fromRGB(255, 140, 80),  outdoor = Color3.fromRGB(230, 100, 50),  fog = Color3.fromRGB(255, 160, 100) },
	night = { ambient = Color3.fromRGB(30, 40, 80),    outdoor = Color3.fromRGB(15, 20, 50),    fog = Color3.fromRGB(20, 25, 60) },
}

local FOG_RANGES = {
	dawn  = { min = 200, max = 800 },
	day   = { min = 800, max = 2000 },
	dusk  = { min = 150, max = 600 },
	night = { min = 80,  max = 300 },
}

local BRIGHTNESS_VALUES = {
	dawn  = 1.2,
	day   = 2.0,
	dusk  = 0.9,
	night = 0.1,
}

local PHASE_START_HOURS = { dawn = 5, day = 8, dusk = 18, night = 21 }
local PHASE_END_HOURS   = { dawn = 8, day = 18, dusk = 21, night = 29 }
local PHASE_ORDER = { "dawn", "day", "dusk", "night" }

local remoteFolder = ReplicatedStorage:FindFirstChild("DayNightRemotes")
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "DayNightRemotes"
	remoteFolder.Parent = ReplicatedStorage
end

local timeOfDayEvent = Instance.new("RemoteEvent")
timeOfDayEvent.Name = "TimeOfDayChanged"
timeOfDayEvent.Parent = remoteFolder

local requestTimeEvent = Instance.new("RemoteFunction")
requestTimeEvent.Name = "RequestCurrentTime"
requestTimeEvent.Parent = remoteFolder

local phaseChangedEvent = Instance.new("BindableEvent")
phaseChangedEvent.Name = "PhaseChanged"
phaseChangedEvent.Parent = remoteFolder

local currentTime = TIME_START
local currentPhase = "day"
local lastPhase = ""
local tweenInProgress = false
local starParts = {}

-- Works out which phase of the day we're currently in based on the hour
local function getPhaseFromHour(hour)
	if hour >= 5 and hour < 8 then
		return "dawn"
	elseif hour >= 8 and hour < 18 then
		return "day"
	elseif hour >= 18 and hour < 21 then
		return "dusk"
	else
		return "night"
	end
end

-- Cycles to the next phase in order, wrapping from night back to dawn
local function getNextPhase(phase)
	for i, p in ipairs(PHASE_ORDER) do
		if p == phase then
			return PHASE_ORDER[(i % #PHASE_ORDER) + 1]
		end
	end
	return "day"
end

local function lerpColor(a, b, t)
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

local function lerpNumber(a, b, t)
	return a + (b - a) * t
end

-- Makes transitions feel smoother by easing in and out instead of moving at a constant rate
local function smoothstep(t)
	return t * t * (3 - 2 * t)
end

-- Returns how far through the current phase we are as a 0-1 value with smoothstep applied
-- Night needs special handling since it crosses midnight (e.g. hour 2 AM needs to become 26)
local function getPhaseBlendFactor(hour)
	local phase = getPhaseFromHour(hour)
	local phaseStart = PHASE_START_HOURS[phase]
	local phaseEnd = PHASE_END_HOURS[phase]
	local adjusted = (phase == "night" and hour < 5) and hour + 24 or hour
	local t = math.clamp((adjusted - phaseStart) / (phaseEnd - phaseStart), 0, 1)
	return phase, smoothstep(t)
end

-- Blends all lighting values between the current and next phase so nothing changes abruptly
local function getBlendedPhaseValues(hour)
	local phase, t = getPhaseBlendFactor(hour)
	local nextPhase = getNextPhase(phase)
	local ca = SKY_COLORS[phase]
	local cb = SKY_COLORS[nextPhase]
	local fa = FOG_RANGES[phase]
	local fb = FOG_RANGES[nextPhase]
	return {
		ambient    = lerpColor(ca.ambient, cb.ambient, t),
		outdoor    = lerpColor(ca.outdoor, cb.outdoor, t),
		fogColor   = lerpColor(ca.fog, cb.fog, t),
		fogMin     = lerpNumber(fa.min, fb.min, t),
		fogMax     = lerpNumber(fa.max, fb.max, t),
		brightness = lerpNumber(BRIGHTNESS_VALUES[phase], BRIGHTNESS_VALUES[nextPhase], t),
	}
end

local function applyLightingValues(values)
	Lighting.Ambient = values.ambient
	Lighting.OutdoorAmbient = values.outdoor
	Lighting.FogColor = values.fogColor
	Lighting.FogStart = values.fogMin
	Lighting.FogEnd = values.fogMax
	Lighting.Brightness = values.brightness
	Lighting.ClockTime = currentTime
end

-- Spawns stars as glowing neon balls scattered randomly across the sky dome
-- Uses spherical coordinates so they're evenly distributed rather than clumped
local function createStars()
	local folder = workspace:FindFirstChild("StarFolder") or Instance.new("Folder")
	folder.Name = "StarFolder"
	folder.Parent = workspace

	for i = 1, STAR_COUNT do
		local star = Instance.new("Part")
		star.Name = "Star_" .. i
		star.Size = Vector3.new(0.3, 0.3, 0.3)
		star.Shape = Enum.PartType.Ball
		star.Material = Enum.Material.Neon
		star.BrickColor = BrickColor.new("White")
		star.Anchored = true
		star.CanCollide = false
		star.CastShadow = false

		local theta = math.random() * math.pi * 2
		local phi = math.acos(2 * math.random() - 1)
		local radius = 900 + math.random() * 100

		star.CFrame = CFrame.new(
			radius * math.sin(phi) * math.cos(theta),
			math.abs(radius * math.cos(phi)) + 200,
			radius * math.sin(phi) * math.sin(theta)
		)

		star.Transparency = 1
		star.Parent = folder
		table.insert(starParts, star)
	end
end

-- Fades stars in at night and back out during the day, runs every frame so the transition is gradual
local function updateStarVisibility(phase)
	local target = (phase == "night") and 0 or 1
	for _, star in ipairs(starParts) do
		local current = star.Transparency
		if math.abs(current - target) < STAR_FADE_SPEED then
			star.Transparency = target
		else
			star.Transparency = current + (target - current) * STAR_FADE_SPEED
		end
	end
end

local function notifyAllClients(phase)
	for _, player in ipairs(Players:GetPlayers()) do
		timeOfDayEvent:FireClient(player, phase, currentTime)
	end
end

-- Handles everything that needs to happen when the phase switches:
-- fires events, tells all clients, and tweens the lighting to the new phase colors
-- The tween guard stops multiple tweens from running on top of each other
local function onPhaseChanged(newPhase)
	phaseChangedEvent:Fire(newPhase)
	notifyAllClients(newPhase)

	if tweenInProgress then return end
	tweenInProgress = true

	local info = TweenInfo.new(6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local goal = {
		OutdoorAmbient = SKY_COLORS[newPhase].outdoor,
		Ambient        = SKY_COLORS[newPhase].ambient,
	}
	local tween = TweenService:Create(Lighting, info, goal)
	tween:Play()
	tween.Completed:Connect(function()
		tweenInProgress = false
	end)
end

phaseChangedEvent.Event:Connect(function(newPhase)
	print(string.format("[DayNight] Phase: %s | Hour: %.1f", newPhase, currentTime))
end)

requestTimeEvent.OnServerInvoke = function(player)
	return currentPhase, currentTime
end

Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	timeOfDayEvent:FireClient(player, currentPhase, currentTime)
end)

-- The main loop - runs every frame, moves the clock forward and keeps everything in sync
local function updateStarVisibility(phase)
RunService.Heartbeat:Connect(function(dt)
	local hoursPerSecond = 24 / CYCLE_DURATION
	currentTime = currentTime + hoursPerSecond * dt

	if currentTime >= 24 then
		currentTime -= 24
	end

	local newPhase = getPhaseFromHour(currentTime)
	if newPhase ~= lastPhase then
		currentPhase = newPhase
		lastPhase = newPhase
		onPhaseChanged(newPhase)
	end

	applyLightingValues(getBlendedPhaseValues(currentTime))
	updateStarVisibility(currentPhase)
end)

createStars()
Lighting.ClockTime = TIME_START
Lighting.GeographicLatitude = 41.7
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.5
applyLightingValues(getBlendedPhaseValues(TIME_START))
