-- V2: event = patrol/farm/hop; outside event = collect/store Fruit and wait.
-- Requires executor loadstring + queue_on_teleport (or equivalent) for continuation.
-- Existing EvenMagnetFarm.lua is unchanged. Both versions share the singleton.
local env = (type(getgenv) == "function" and getgenv()) or _G
if not game:IsLoaded() then game.Loaded:Wait() end
local ok, now = pcall(function() return workspace:GetServerTimeNow() end)
if not ok then now = os.time() end
env.__EventMagnetV2Deadline = math.floor(now / 3600) * 3600 + 600
local source = [====[
-- Event Magnet Farm: standalone client script; uses the game's __ServerBrowser
-- plus HTTP server-list/Worker coordination from the supplied Multi-Account hop.
-- Worker heartbeat sends username, JobId and PlaceId. Continuation queues this embedded source; no downloaded code.
-- Run only one movement/farm script at a time. Stop the other auto scripts first.
-- Detect replicated events; farm living NPCs whose Name/DisplayName contains
-- "magnetized" (case insensitive). Generic Magnet tags are diagnostic only.
-- Optional overrides BEFORE running: getgenv().EventMagnetConfig = { Enabled = false }
local env = (type(getgenv) == "function" and getgenv()) or _G
local continuationSource = env.__EventMagnetV2Source
local eventDeadline = env.__EventMagnetV2Deadline
local function eventStillOpen()
    local ok, now = pcall(function() return workspace:GetServerTimeNow() end)
    if not ok then now = os.time() end
    eventDeadline = math.floor(now / 3600) * 3600 + 600
    return now % 3600 < 600
end
local continuationQueued = false
-- Same readiness gate as giayeuem.lua, before replacing the active session.
repeat task.wait() until game:IsLoaded() and game:GetService("Players").LocalPlayer
local previous = env.EventMagnetFarm
if type(previous) == "table" and type(previous.Destroy) == "function" then
    previous.Destroy()
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Tags = game:GetService("CollectionService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
if not game:IsLoaded() then game.Loaded:Wait() end
local player = Players.LocalPlayer
while not player do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = Players.LocalPlayer
end
assert(player, "EventMagnetFarm must run on the client")
local config = {
    Enabled = true, Team = "Marines", AutoSelectTeam = true,
    TeamRetryInterval = 2, TeamRequestTimeout = 5,
    EventScheduleEnabled = true, EventDurationSeconds = 600,
    Speed = 190, Weapon = "Melee", ScanInterval = 0.5,
    AttackInterval = 0.25, AttackRange = 60, HoverHeight = 30,
    AttackNoAnimation = true,
    AutoBuso = true, BusoCheckDelay = 1, BusoRetryDelay = 3,
    BusoConfirmTimeout = 1.5, UseBusoKeyFallback = true,
    TargetTimeout = 120, NoDamageTimeout = 12, NoProgressTimeout = 12,
    RetryDelay = 20, LogLimit = 80,
    Patrol = true, PatrolHeight = 12, PatrolWait = 1, SpawnTimeout = 1,
    WaterWalkEnabled = true, WaterWalkSurfaceY = -4.5,
    PatrolArrival = 6, SpawnRadius = 180,
    SpawnSettleTime = 1,
    CampSettleTime = 1,
    CampMergeRadius = 500, CampNearbyRadius = 220, CampHeightTolerance = 120,
    Sea1IslandMode = false, IslandWait = 1, IslandSpawnTimeout = 1,
    UsePortalFruit = true, PortalLongDistance = 750, PortalMinSaving = 250,
    PortalTargetRadius = 3000, PortalCooldown = 8, GatewayOpenTimeout = 3,
    GatewayArrivalTimeout = 5, GatewayArrivalRadius = 500,
    GatewayMoveThreshold = 250,
    FruitEnabled = true, FruitESPEnabled = true, FruitESPUpdateInterval = 0.1,
    FruitScanInterval = 1, FruitPickupDistance = 6, FruitPickupConfirm = 2,
    FruitPickupAttempts = 3, FruitRetryDelay = 60,
    StoreFruit = true, StoreRetryDelay = 15, StoreAttempts = 3,
    AutoRandomToken = true,
    RandomCheckIdle = 30,
    RandomCheckCooldown = 5,
    RandomFallbackCooldown = 60,
    WebhookURL = "",
    WebhookEnabled = true, WebhookOnPickup = true, WebhookOnRandom = true, WebhookOnStore = true,
    WebhookMinRarity = "Legendary", WebhookUsername = "Noti Fruit", WebhookTitle = "Noti Fruit",
    WebhookFooterText = "Hoàng Trọng DEV", WebhookColor = 16776960,
    WebhookPing = "", WebhookAvatarURL = "", WebhookBannerURL = "",
    AutoCloseSpinner = true, AutoHideItemNotice = true,
    BringMobs = true, BringMobCount = 2, BringMobRadius = 200,
    BringActivationRange = 50, BringPlayerSafeRange = 300, BringMobInterval = 0.1,
    StartupHop = true, StartupDelay = 5, CurrentPlayerLimit = 4,
    TargetExistingPlayers = 3, HopMaxPages = 30, HopCandidates = 3,
    HopRequestRetries = 3, HopRetryDelay = 60, HopTeleportTimeout = 10,
    HopBrowserTimeout = 8,
    HopMaxPlayers = 3, HopEmptyPageLimit = 4, HopPageDelay = 0.1,
    HopMaxAttempts = 8, HopAttemptDelay = 1.5, HopRandomizeTies = true,
    HopApiUrl = "https://hop.giacode.workers.dev", HopHeartbeatInterval = 30,
}
local overrides = env.EventMagnetV2Config
-- Seed coordinates copied from auto_farm_level.lua QuestDatabase (not executed).
-- Historical fallback only; live EnemySpawns adds points for the current map.
local seedRoutes = {
    [1] = {
        { "Bandit", Vector3.new(1185.03, 16.48, 1618.34) },
        { "Monkey", Vector3.new(-1610.96, 21.70, 142.13) },
        { "Gorilla", Vector3.new(-1237.52, 6.27, -485.45) },
        { "Pirate", Vector3.new(-1215.17, 4.75, 3915.22) },
        { "Brute", Vector3.new(-1379.88, 14.85, 4132.89) },
        { "Desert Bandit", Vector3.new(990.22, 6.43, 4440.89) },
        { "Desert Officer", Vector3.new(1573.49, 13.91, 4426.68) },
        { "Snow Bandit", Vector3.new(1288.75, 105.77, -1451.98) },
        { "Snowman", Vector3.new(1288.75, 105.77, -1451.98) },
        { "Chief Petty Officer", Vector3.new(-4892.47, 21.05, 4280.97) },
        { "Sky Bandit", Vector3.new(-4981.49, 717.67, -2614.93) },
        { "Dark Master", Vector3.new(-5251.27, 388.58, -2270.82) },
        { "Prisoner", Vector3.new(5412.35, 1.65, 502.82) },
        { "Dangerous Prisoner", Vector3.new(5544.75, 1.65, 689.47) },
        { "Toga Warrior", Vector3.new(-1805.88, 7.35, -2758.62) },
        { "Gladiator", Vector3.new(-1432.88, 7.35, -3130.98) },
        { "Mil. Soldier", Vector3.new(-5414.28, 12.23, 8466.82) },
        { "Mil. Spy", Vector3.new(-5822.48, 86.85, 8828.21) },
        { "Fishman Warrior", Vector3.new(60846.54, 43.19, 1378.89) },
        { "Fishman Commando", Vector3.new(61794.75, 43.19, 1464.38) },
        { "God's Guard", Vector3.new(-4714.29, 845.27, -1885.64) },
        { "Shanda", Vector3.new(-7678.43, 5566.94, -499.78) },
        { "Royal Squad", Vector3.new(-7725.29, 5610.45, -1445.69) },
        { "Royal Soldier", Vector3.new(-7861.64, 5610.45, -1774.22) },
        { "Galley Pirate", Vector3.new(5591.95, 38.50, 3971.95) },
        { "Galley Captain", Vector3.new(5654.49, 38.50, 4945.89) },
    },
    [2] = {
        { "Raider", Vector3.new(-738.74, 82.98, 2378.96) },
        { "Mercenary", Vector3.new(-962.77, 72.98, 1438.45) },
        { "Swan Pirate", Vector3.new(878.89, 121.72, 1221.75) },
        { "Factory Staff", Vector3.new(295.34, 73.10, -56.32) },
        { "Marine Lieutenant", Vector3.new(-2824.52, 73.01, -3038.98) },
        { "Marine Captain", Vector3.new(-1867.75, 73.01, -3320.12) },
        { "Zombie", Vector3.new(-5642.45, 48.51, -720.89) },
        { "Vampire", Vector3.new(-6018.98, 6.45, -1312.45) },
        { "Snow Trooper", Vector3.new(508.89, 401.55, -5578.45) },
        { "Winter Warrior", Vector3.new(1185.74, 429.85, -5189.65) },
        { "Lab Subordinate", Vector3.new(-5778.45, 15.95, -4468.89) },
        { "Horned Warrior", Vector3.new(-6402.12, 15.95, -5812.45) },
        { "Magma Ninja", Vector3.new(-5212.89, 15.95, -4822.45) },
        { "Lava Pirate", Vector3.new(-5245.78, 15.95, -4720.12) },
        { "Ship Deckhand", Vector3.new(1185.45, 125.06, 32989.12) },
        { "Ship Engineer", Vector3.new(912.45, 125.06, 33022.45) },
        { "Ship Steward", Vector3.new(912.45, 125.06, 33455.78) },
        { "Ship Officer", Vector3.new(1055.89, 125.06, 33312.45) },
        { "Arctic Warrior", Vector3.new(6022.45, 28.19, -6245.89) },
        { "Snow Lurker", Vector3.new(5522.78, 28.19, -6812.45) },
        { "Sea Soldier", Vector3.new(-3245.89, 237.28, -9812.45) },
        { "Water Fighter", Vector3.new(-3389.12, 237.28, -10512.78) },
    },
    [3] = {
        { "Pirate Millionaire", Vector3.new(-375.45, 43.76, 5322.89) },
        { "Pistol Billionaire", Vector3.new(-180.12, 43.76, 5912.45) },
        { "Dragon Crew Warrior", Vector3.new(6412.89, 51.68, -985.45) },
        { "Dragon Crew Archer", Vector3.new(6612.45, 51.68, -1250.78) },
        { "Female Islander", Vector3.new(5212.89, 601.62, 1022.45) },
        { "Giant Islander", Vector3.new(4822.45, 601.62, 589.12) },
        { "Marine Commodore", Vector3.new(2455.89, 27.81, -6512.45) },
        { "Marine Rear Admiral", Vector3.new(1912.45, 27.81, -7022.78) },
        { "Fishman Raider", Vector3.new(-10312.45, 331.66, -8412.89) },
        { "Fishman Captain", Vector3.new(-10822.89, 331.66, -9012.45) },
        { "Forest Pirate", Vector3.new(-13455.89, 331.78, -7312.45) },
        { "Mythological Pirate", Vector3.new(-13688.12, 331.78, -7912.89) },
        { "Jungle Pirate", Vector3.new(-9122.45, 142.13, 5788.89) },
        { "Musketeer Pirate", Vector3.new(-8822.89, 142.13, 6012.45) },
        { "Reborn Skeleton", Vector3.new(-8755.12, 142.13, 6212.89) },
        { "Living Zombie", Vector3.new(-10122.45, 142.13, 5912.89) },
        { "Demonic Soul", Vector3.new(-9512.89, 175.13, 6112.45) },
        { "Posessed Mummy", Vector3.new(-9612.45, 6.13, 6212.89) },
        { "Peanut Scout", Vector3.new(-2312.45, 38.10, -10412.89) },
        { "Peanut President", Vector3.new(-1912.89, 38.10, -10512.45) },
        { "Ice Cream Chef", Vector3.new(-612.45, 65.82, -11122.89) },
        { "Ice Cream Commander", Vector3.new(-1022.89, 65.82, -11212.45) },
        { "Cookie Crafter", Vector3.new(-2312.45, 37.80, -12212.89) },
        { "Cake Guard", Vector3.new(-1712.89, 37.80, -12312.45) },
        { "Baking Staff", Vector3.new(-1612.45, 37.79, -12912.89) },
        { "Head Baker", Vector3.new(-2112.89, 37.79, -13012.45) },
        { "Cocoa Warrior", Vector3.new(412.45, 25.33, -12412.89) },
        { "Chocolate Bar Battler", Vector3.new(52.89, 25.33, -12612.45) },
        { "Sweet Thief", Vector3.new(-912.45, 15.93, -14612.89) },
        { "Candy Rebel", Vector3.new(-1388.89, 15.93, -14712.45) },
        { "Candy Pirate", Vector3.new(-1122.45, 15.94, -15212.89) },
        { "Snow Demon", Vector3.new(-1512.89, 15.94, -15312.45) },
        { "Isle Outlaw", Vector3.new(-16212.45, 54.87, -312.89) },
        { "Island Boy", Vector3.new(-16812.89, 54.87, -412.45) },
        { "Sun-kissed Warrior", Vector3.new(-16312.45, 54.87, -689.12) },
        { "Isle Champion", Vector3.new(-16788.89, 54.87, -789.45) },
        { "Serpent Hunter", Vector3.new(-16212.45, 54.87, -1212.89) },
        { "Submerged Stalker", Vector3.new(-16812.89, 54.87, -1312.45) },
    },
}

-- Known Portal arrival anchors. Camp/mob coordinates are matched to the nearest
-- anchor, then translated to the actual World Warp label through aliases below.
local portalDestinations = {
    [2] = {
        ["Cafe"] = Vector3.new(-382, 74, 356),
        ["Colosseum"] = Vector3.new(-1836, 46, 1642),
        ["Dark Arena"] = Vector3.new(3948, 13, -3479),
        ["Docks 1"] = Vector3.new(-923, 8, 1810),
        ["Docks 2"] = Vector3.new(-13, 39, 2708),
        ["Docks 3"] = Vector3.new(-1944, 9, -2594),
        ["Docks 4"] = Vector3.new(-5798, 1, -5021),
        ["Doghouse"] = Vector3.new(-1984, 125, -82),
        ["Graveyard"] = Vector3.new(-5710, 126, -775),
        ["Haunted Ship"] = Vector3.new(937, 125, 32879),
        ["Lab"] = Vector3.new(-5542, 335, -5924),
        ["Lava"] = Vector3.new(-5280, 7, -5618),
        ["Mansion"] = Vector3.new(-494, 339, 593),
        ["Raid"] = Vector3.new(-6503, 251, -4495),
        ["Remote"] = Vector3.new(4766, 8, 2911),
        ["Skull"] = Vector3.new(-2956.24341, 123.399323, -9981.06934),
        ["Snow"] = Vector3.new(1210, 429, -4663),
        ["Winter Castle"] = Vector3.new(5544.71777, 60.1393852, -6359.08887),
    },
    [3] = {
        ["Cake Land"] = Vector3.new(-2098.97046, 76.39494, -12128.3594),
        ["Chocolate Land"] = Vector3.new(379.13962, 130.20599, -12720.8398),
        ["Great Tree"] = Vector3.new(4345.09375, 575.05243, -6159.00439),
        ["Haunted Castle"] = Vector3.new(-9515.00098, 149.18877, 5534.05029),
        ["Hydra Arena"] = Vector3.new(5020.9458, 174.08646, -2011.18506),
        ["Hydra Town"] = Vector3.new(5229.995, 604.345, 345.154),
        ["Ice Cream Land"] = Vector3.new(-917.54852, 63.36414, -10858.6963),
        ["Peanut Land"] = Vector3.new(-2037.80017, 13.65112, -9948.20215),
        ["Port"] = Vector3.new(-342.43436, 23.83155, 5547.3457),
        ["Sea Castle"] = Vector3.new(-5502.17871, 323.6709, -2863.46167),
        ["Tiki Outpost"] = Vector3.new(-16456.4629, 530.25195, 436.23181),
        ["Turtle Center"] = Vector3.new(-12007.9795, 339.15549, -9178.58008),
        ["Turtle Entrance"] = Vector3.new(-10163.9648, 340.29028, -8320.76758),
        ["Turtle Mansion"] = Vector3.new(-12538.4219, 339.39359, -7817.0708),
        ["Turtle Mountain"] = Vector3.new(-12856.6133, 852.7536, -10715.2305),
    },
}

-- Several farm camps belong to one large World Warp region. The first alias is
-- the canonical route key and the remaining values tolerate older UI labels.
local portalRouteAliases = {
    [2] = {
        ["Cafe"] = {"Kingdom of Rose", "Cafe"},
        ["Colosseum"] = {"Kingdom of Rose", "Colosseum"},
        ["Docks 1"] = {"Kingdom of Rose", "Docks 1"},
        ["Docks 2"] = {"Kingdom of Rose", "Docks 2"},
        ["Doghouse"] = {"Kingdom of Rose", "Doghouse"},
        ["Mansion"] = {"Kingdom of Rose", "Mansion"},
        ["Dark Arena"] = {"Dark Arena"},
        ["Remote"] = {"Green Zone", "Remote"},
        ["Graveyard"] = {"Graveyard"}, ["Docks 3"] = {"Graveyard", "Docks 3"},
        ["Docks 4"] = {"Hot and Cold", "Docks 4"},
        ["Lab"] = {"Hot and Cold", "Lab"}, ["Lava"] = {"Hot and Cold", "Lava"},
        ["Raid"] = {"Hot and Cold", "Raid"},
        ["Haunted Ship"] = {"Cursed Ship", "Haunted Ship"},
        ["Snow"] = {"Snow Mountain", "Snow"},
        ["Winter Castle"] = {"Ice Castle", "Winter Castle"},
        ["Skull"] = {"Forgotten Island", "Skull"},
    },
    [3] = {
        ["Port"] = {"Port Town", "Port"},
        ["Hydra Arena"] = {"Hydra Island", "Hydra Arena"},
        ["Hydra Town"] = {"Hydra Island", "Hydra Town"},
        ["Great Tree"] = {"Great Tree"},
        ["Sea Castle"] = {"Castle on the Sea", "Castle On The Sea", "Sea Castle"},
        ["Haunted Castle"] = {"Haunted Castle"},
        ["Turtle Center"] = {"Floating Turtle", "Turtle Center"},
        ["Turtle Entrance"] = {"Floating Turtle", "Turtle Entrance"},
        ["Turtle Mansion"] = {"Floating Turtle", "Turtle Mansion"},
        ["Turtle Mountain"] = {"Floating Turtle", "Turtle Mountain"},
        ["Cake Land"] = {"Sea of Treats", "Cake Land"},
        ["Chocolate Land"] = {"Sea of Treats", "Chocolate Land"},
        ["Ice Cream Land"] = {"Sea of Treats", "Ice Cream Land"},
        ["Peanut Land"] = {"Sea of Treats", "Peanut Land"},
        ["Tiki Outpost"] = {"Tiki Outpost"},
    },
}

-- Mesh fallback shared by Fruit pickup and ESP. Direct Tool/Model names remain
-- the primary signal and Portal-Portal is never classified as an item Fruit.
local fruitNamesByMeshId = {
    ["15100283484"] = "Light Fruit", ["15116730102"] = "Love Fruit",
    ["15100273645"] = "Dough Fruit", ["15116967784"] = "Spider Fruit",
    ["15112263502"] = "Shadow Fruit", ["15104782377"] = "Blade Fruit",
    ["15060012861"] = "Rocket Fruit", ["15106768588"] = "Leopard Fruit",
    ["15112469964"] = "Falcon Fruit", ["15708895165"] = "T-Rex Fruit",
    ["19001642259"] = "Dragon East Fruit", ["86024571204851"] = "Gas Fruit",
    ["15100246632"] = "Phoenix Fruit", ["14661873358"] = "Sound Fruit",
    ["15111584216"] = "Flame Fruit", ["15105281957"] = "Spring Fruit",
    ["15116740364"] = "Bomb Fruit", ["15104817760"] = "Rubber Fruit",
    ["15057683975"] = "Spin Fruit", ["15105350415"] = "Magma Fruit",
    ["15482881956"] = "Kitsune Fruit", ["15100485671"] = "Barrier Fruit",
    ["18955022385"] = "Dragon West Fruit", ["101378450824208"] = "Yeti Fruit",
    ["15116721173"] = "Pain Fruit", ["10395893751"] = "Venom Fruit",
    ["11908375285"] = "Spirit Fruit", ["15100433167"] = "Ice Fruit",
    ["15100299740"] = "Gravity Fruit", ["15107005807"] = "Spike Fruit",
    ["15116696973"] = "Smoke Fruit", ["15112600534"] = "Diamond Fruit",
    ["15112333093"] = "Ghost Fruit", ["15057718441"] = "Quake Fruit",
    ["15111517529"] = "Sand Fruit", ["15100313696"] = "Buddha Fruit",
    ["15116747420"] = "Rumble Fruit", ["15100384816"] = "Blizzard Fruit",
    ["15111553409"] = "Dark Fruit", ["14661837634"] = "Mammoth Fruit",
    ["15100184583"] = "Control Fruit",
}
local fruitColors = {
    ["Leopard Fruit"] = Color3.fromRGB(255, 170, 0),
    ["Dragon East Fruit"] = Color3.fromRGB(255, 0, 0),
    ["Dragon West Fruit"] = Color3.fromRGB(255, 80, 80),
    ["Kitsune Fruit"] = Color3.fromRGB(200, 100, 255),
    ["Spirit Fruit"] = Color3.fromRGB(120, 200, 255),
    ["Venom Fruit"] = Color3.fromRGB(180, 60, 200),
    ["Dough Fruit"] = Color3.fromRGB(255, 220, 180),
    ["Light Fruit"] = Color3.fromRGB(255, 255, 150),
}
if type(overrides) == "table" then
    for key, value in pairs(config) do
        if type(overrides[key]) == type(value) then config[key] = overrides[key] end
    end
end
for key, value in pairs(config) do
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("Invalid EventMagnetConfig." .. key)
        end
        -- World coordinates may be negative; only durations/distances need a floor.
        config[key] = key == "WaterWalkSurfaceY" and value or math.max(value, 0.05)
    end
end
-- Haki is mandatory, including each respawn; do not allow a disabled retry loop.
config.AutoBuso = true
config.LogLimit = math.clamp(math.floor(config.LogLimit), 10, 300)
config.ScanInterval = math.max(config.ScanInterval, 0.2)
config.AttackInterval = math.max(config.AttackInterval, 0.1)
config.Speed = math.clamp(config.Speed, 1, 500)
config.HoverHeight = math.clamp(config.HoverHeight, 1, 60)
config.AttackRange = math.clamp(math.max(config.AttackRange,
    math.sqrt(config.HoverHeight * config.HoverHeight + 4) + 5), 7, 100)
config.PatrolWait = math.max(config.PatrolWait, config.ScanInterval * 2)
config.SpawnTimeout = math.max(config.SpawnTimeout, config.PatrolWait)
config.IslandWait = math.max(config.IslandWait, config.ScanInterval * 2)
config.IslandSpawnTimeout = math.max(config.IslandSpawnTimeout, config.IslandWait)
config.CampSettleTime = math.max(config.CampSettleTime, config.ScanInterval * 2)
config.FruitPickupAttempts = math.clamp(math.floor(config.FruitPickupAttempts), 1, 10)
config.StoreAttempts = math.clamp(math.floor(config.StoreAttempts), 1, 10)
config.CurrentPlayerLimit = math.max(1, math.floor(config.CurrentPlayerLimit))
config.TargetExistingPlayers = math.clamp(math.floor(config.TargetExistingPlayers),
    0, math.max(0, config.CurrentPlayerLimit - 1))
config.HopMaxPages = math.clamp(math.floor(config.HopMaxPages), 1, 30)
config.HopMaxPlayers = math.clamp(math.floor(config.HopMaxPlayers), 1, 11)
config.HopMaxAttempts = math.clamp(math.floor(config.HopMaxAttempts), 1, 8)
config.HopEmptyPageLimit = math.max(1, math.floor(config.HopEmptyPageLimit))
config.HopHeartbeatInterval = math.max(30, config.HopHeartbeatInterval)
config.HopCandidates = math.clamp(math.floor(config.HopCandidates), 1, 10)
config.HopRequestRetries = math.clamp(math.floor(config.HopRequestRetries), 1, 5)
config.EventDurationSeconds = math.clamp(config.EventDurationSeconds, 1, 3600)
config.RandomCheckIdle = math.max(5, math.floor(config.RandomCheckIdle))
config.RandomCheckCooldown = math.max(1, math.floor(config.RandomCheckCooldown))
config.RandomFallbackCooldown = math.max(5, math.floor(config.RandomFallbackCooldown))
do
    local wanted = string.lower(tostring(config.Team or "Marines"))
    config.Team = (wanted == "pirate" or wanted == "pirates") and "Pirates" or "Marines"
end

local alive, enabled = true, config.Enabled
local connections, remotes, mobs = {}, {}, {}
local targets, logs = {}, {}
local skipped = setmetatable({}, { __mode = "k" })
local target, targetSince, lastDamage, lastHP, attackSince
local bestDistance, lastProgress = math.huge, 0
local moveRoot, moveHumanoid, floatForce, oldPlatform
local collisionState = {}
local eventCount, deliveryCount = 0, 0
local status = "Dang quet..."
local scanClock, attackClock, uiClock, fruitScanClock, fruitESPClock = 0, 0, 0, 0, 0
local lastError = -math.huge
local api = {}
env.EventMagnetFarm = api
local patrol = { points = {}, pass = 1, current = nil, refresh = 0,
    arrived = nil, started = nil, best = math.huge, progress = 0 }
local action = { kind = nil, token = 0 }
local portal = { retryAt = 0, lastResult = "Chua dung", destination = nil, forCombat = false }
local closePortalMenu
local fruitRecords = setmetatable({}, { __mode = "k" })
local storeRecords = setmetatable({}, { __mode = "k" })
local fruitTask = { target = nil, started = nil, best = math.huge, progress = 0 }
local hop = { busy = false, retryAt = 0, status = "Cho kiem tra dau phien" }
-- [FIX 1] Random token: tự dò cooldown qua Check, không phụ thuộc event window
local randomToken = { busy = false, locked = false, retryAt = 0, serial = 0,
    status = "Cho kiem tra cooldown",
    nextCheck = 0,
    tokenNow = 0,
    tokenNeed = 500,
    cooldownLeft = 0,
    requirementMet = false }
if type(env.WebhookURL) == "string" then config.WebhookURL = env.WebhookURL end
config.EventScheduleEnabled, config.EventDurationSeconds, config.StartupHop = true, 600, true
config.HopMaxPlayers = math.min(config.HopMaxPlayers, config.TargetExistingPlayers)
local eventWindow = { active = false, cycle = nil, remaining = 0 }
local function readEventWindow(timestamp)
    local elapsed = timestamp % 3600
    local active = config.EventScheduleEnabled and elapsed < config.EventDurationSeconds
    return active, active and (config.EventDurationSeconds - elapsed) or (3600 - elapsed),
        math.floor(timestamp / 3600)
end
local function updateEventWindow()
    local ok, timestamp = pcall(function() return workspace:GetServerTimeNow() end)
    if not ok then timestamp = os.time() end
    local active, remaining, cycle = readEventWindow(timestamp)
    if active and eventWindow.cycle ~= cycle and eventWindow.cycle ~= nil then
        patrol.pass = patrol.pass + 1
        patrol.current, patrol.arrived, patrol.started, patrol.seenAt = nil, nil, nil, nil
        patrol.best = math.huge
        for _, point in ipairs(patrol.points) do point.retryAt = 0 end
    end
    eventWindow.active, eventWindow.remaining, eventWindow.cycle = active, remaining, cycle
end
local teamSelect = { desired = config.Team, ready = false, pending = false,
    pendingSince = 0, nextAttempt = 0, request = 0, lastResult = "Chua chon team" }
local sessionSerial = (tonumber(env.__EventMagnetSessionSerial) or 0) + 1
env.__EventMagnetSessionSerial = sessionSerial
local serverChoiceMemory = env.__EventMagnetServerChoice
if type(serverChoiceMemory) ~= "table" then
    serverChoiceMemory = {}
    env.__EventMagnetServerChoice = serverChoiceMemory
end

local function contains(text, word)
    return string.find(string.lower(tostring(text or "")), word, 1, true) ~= nil
end
local function short(text, length)
    return string.sub(tostring(text):gsub("[%c]", " "), 1, length or 150)
end
local function path(instance)
    local ok, result = pcall(function() return instance:GetFullName() end)
    return ok and short(result, 220) or "<removed>"
end
local function log(kind, message)
    table.insert(logs, { time = os.clock(), kind = kind, text = short(message, 260) })
    if #logs > config.LogLimit then table.remove(logs, 1) end
end
local function connect(signal, callback)
    local connection = signal:Connect(function(...)
        if alive then callback(...) end
    end)
    table.insert(connections, connection)
    return connection
end
local function currentTeamName()
    local current = player.Team
    local name = current and current.Name
    return (name == "Pirates" or name == "Marines") and name or nil
end
local function teamSelectionStep(now)
    -- Do not wait for Map/Character here: those can depend on choosing a team.
    if not game:IsLoaded() or not player:FindFirstChildOfClass("PlayerGui") then
        teamSelect.loadReadyAt = nil
        teamSelect.lastResult = "Cho game load / PlayerGui"
        return false
    end
    teamSelect.loadReadyAt = teamSelect.loadReadyAt or (now + 5)
    if now < teamSelect.loadReadyAt then
        teamSelect.lastResult = "Cho on dinh game " .. math.ceil(teamSelect.loadReadyAt - now) .. "s truoc chon team"
        return false
    end
    local selected = currentTeamName()
    if selected then
        if not teamSelect.ready or teamSelect.lastResult ~= "Da vao " .. selected then
            teamSelect.lastResult = "Da vao " .. selected
            log("TEAM", teamSelect.lastResult)
        end
        teamSelect.ready, teamSelect.pending = true, false
        return true
    end

    teamSelect.ready = false
    if not config.AutoSelectTeam then
        teamSelect.lastResult = "Auto team tat; hay chon team thu cong"
        return false
    end

    if teamSelect.pending and now - teamSelect.pendingSince >= config.TeamRequestTimeout then
        teamSelect.request = teamSelect.request + 1 -- invalidate a stuck InvokeServer callback
        teamSelect.pending = false
        teamSelect.nextAttempt = now + config.TeamRetryInterval
        teamSelect.lastResult = "SetTeam timeout; se thu lai"
        log("TEAM", teamSelect.lastResult)
    end
    if teamSelect.pending or now < teamSelect.nextAttempt then return false end

    local remotesFolder = RS:FindFirstChild("Remotes")
    local remote = remotesFolder and remotesFolder:FindFirstChild("CommF_")
    if not remote or not remote:IsA("RemoteFunction") then
        teamSelect.nextAttempt = now + config.TeamRetryInterval
        teamSelect.lastResult = "Chua tim thay Remotes.CommF_"
        return false
    end

    teamSelect.request = teamSelect.request + 1
    local requestId = teamSelect.request
    teamSelect.pending, teamSelect.pendingSince = true, now
    teamSelect.nextAttempt = now + config.TeamRetryInterval
    teamSelect.lastResult = "Dang chon " .. teamSelect.desired
    task.spawn(function()
        local ok, response = pcall(function()
            return remote:InvokeServer("SetTeam", teamSelect.desired)
        end)
        if not alive or requestId ~= teamSelect.request then return end
        teamSelect.pending = false
        teamSelect.nextAttempt = os.clock() + config.TeamRetryInterval
        if ok then
            teamSelect.lastResult = "Da gui SetTeam " .. teamSelect.desired
        else
            teamSelect.lastResult = "SetTeam loi: " .. short(response, 80)
        end
        log("TEAM", teamSelect.lastResult)
    end)
    return false
end
local function rootOf(model)
    local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    return root and root:IsA("BasePart") and root or nil
end
local function livingNPC(model)
    if not model or not model:IsDescendantOf(workspace) then return nil end
    if Players:GetPlayerFromCharacter(model) then return nil end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = rootOf(model)
    if humanoid and humanoid.Health > 0 and root then return humanoid, root end
end
local function isMagnetized(model, humanoid)
    return contains(model.Name, "magnetized") or contains(humanoid.DisplayName, "magnetized")
end
local function releaseMovement()
    if floatForce then floatForce:Destroy(); floatForce = nil end
    if moveHumanoid and moveHumanoid.Parent then moveHumanoid.PlatformStand = oldPlatform end
    if moveRoot and moveRoot.Parent then
        moveRoot.AssemblyLinearVelocity = Vector3.zero
        moveRoot.AssemblyAngularVelocity = Vector3.zero
    end
    for part, original in pairs(collisionState) do
        if part.Parent then part.CanCollide = original end
    end
    collisionState = {}
    moveRoot, moveHumanoid, oldPlatform = nil, nil, nil
end
local function actionIsCurrent(kind, token)
    return alive and enabled and sessionSerial == env.__EventMagnetSessionSerial
        and action.kind == kind and action.token == token
end
local function beginAction(kind)
    if action.kind then return nil end
    action.token = action.token + 1
    action.kind = kind
    return action.token
end
local function endAction(kind, token)
    if action.kind == kind and action.token == token then action.kind = nil end
end
local function cancelAction(reason)
    local oldKind = action.kind
    if oldKind == "portal" and closePortalMenu then pcall(closePortalMenu) end
    if oldKind and reason then log("ACTION", oldKind .. ": " .. reason) end
    action.token = action.token + 1
    action.kind = nil
    portal.destination, portal.forCombat = nil, false
    if oldKind == "hop" then
        hop.busy = false
        if hop.dispatched then
            hop.blocked, hop.dispatched = true, false
            hop.status = "Da gui teleport; dung hop phien nay vi ket qua chua ro"
        else
            hop.status = "Hop tam dung de uu tien farm"
        end
    end
    releaseMovement()
end
local function hasLiveMagnetized()
    if not eventStillOpen() then return false end
    for _, model in ipairs(targets) do
        local humanoid = livingNPC(model)
        if humanoid and isMagnetized(model, humanoid)
            and (skipped[model] or 0) <= os.clock() then return true end
    end
    return false
end
local function resetTarget(reason, skip)
    if target and skip then skipped[target] = os.clock() + config.RetryDelay end
    if target and reason then log("FARM", short(target.Name, 80) .. ": " .. reason) end
    target, attackSince = nil, nil
    patrol.combatCamp, patrol.combatHumanoid = nil, nil
    bestDistance = math.huge
    patrol.arrived, patrol.started, patrol.best = nil, nil, math.huge
    patrol.seenAt = nil
    releaseMovement()
end
function api.SetEnabled(value)
    if not alive then return end
    enabled = value == true
    cancelAction(enabled and "bat lai" or "da dung")
    if enabled and not hop.checked then hop.readyAt = nil end
    resetTarget()
    status = enabled and "Dang tim Magnetized..." or "Da dung farm; van theo doi event"
end
function api.GetTargets()
    local result = {}
    for model in pairs(mobs) do
        local humanoid, root = livingNPC(model)
        if humanoid and isMagnetized(model, humanoid) then
            table.insert(result, { model = model, name = model.Name,
                displayName = humanoid.DisplayName, health = humanoid.Health,
                position = root.Position, evidence = "Name/DisplayName contains magnetized" })
        end
    end
    return result
end
function api.GetLogs()
    local copy = {}
    for i, entry in ipairs(logs) do
        copy[i] = { time = entry.time, kind = entry.kind, text = entry.text }
    end
    return copy
end
function api.GetEvents()
    local result = {}
    for instance, record in pairs(remotes) do
        table.insert(result, { path = path(instance), class = instance.ClassName,
            received = record.received, magnetName = contains(instance.Name, "magnet") })
    end
    return result
end

-- Keep metadata only: never serialize arbitrary remote payloads or invoke a
-- discovered remote. RemoteFunctions are catalogued without replacing callbacks.
local function observeEvent(instance, initial)
    if remotes[instance] then return end
    local isRemote = instance:IsA("RemoteEvent") or instance:IsA("UnreliableRemoteEvent")
    local isBindable = instance:IsA("BindableEvent")
    if not isRemote and not isBindable and not instance:IsA("RemoteFunction") then return end
    local record = { received = 0, lastLog = -math.huge }
    remotes[instance] = record
    eventCount = eventCount + 1
    if not initial or contains(instance.Name, "magnet") then
        log(initial and "EVENT EXISTING" or "EVENT NEW", instance.ClassName .. " " .. path(instance))
    end
    if isRemote or isBindable then
        local signal = isRemote and instance.OnClientEvent or instance.Event
        record.connection = signal:Connect(function(...)
            if not alive then return end
            record.received = record.received + 1
            deliveryCount = deliveryCount + 1
            local now = os.clock()
            if now - record.lastLog >= 2 then
                record.lastLog = now
                log("EVENT RECEIVED", path(instance) .. " | args=" .. select("#", ...)
                    .. " | total=" .. record.received)
            end
        end)
    end
    record.rename = instance:GetPropertyChangedSignal("Name"):Connect(function()
        if alive then log("EVENT RENAMED", path(instance)) end
    end)
    record.destroy = instance.Destroying:Connect(function()
        if record.connection then record.connection:Disconnect() end
        record.rename:Disconnect()
        record.destroy:Disconnect()
        remotes[instance] = nil
        eventCount = eventCount - 1
    end)
end
local function observeMob(instance)
    if instance:IsA("Humanoid") then
        local model = instance.Parent
        if model and model:IsA("Model") then mobs[model] = mobs[model] or {} end
    end
end
-- Subscribe before initial scan so spawns during startup are not missed.
connect(game.DescendantAdded, function(instance) observeEvent(instance, false) end)
connect(workspace.DescendantAdded, observeMob)
for _, instance in ipairs(game:GetDescendants()) do observeEvent(instance, true) end
for _, instance in ipairs(workspace:GetDescendants()) do observeMob(instance) end

local function magnetMarkers(model, humanoid, root)
    local found = {}
    for _, instance in ipairs({ model, humanoid, root }) do
        for key, value in pairs(instance:GetAttributes()) do
            if contains(key, "magnet") and value ~= false then
                table.insert(found, "attribute:" .. short(key, 50))
            end
        end
        for _, tag in ipairs(Tags:GetTags(instance)) do
            if contains(tag, "magnet") then table.insert(found, "tag:" .. short(tag, 50)) end
        end
    end
    table.sort(found)
    return table.concat(found, ", ")
end
local function scanMobs()
    targets = {}
    for model, record in pairs(mobs) do
        if not model:IsDescendantOf(workspace) then
            mobs[model] = nil
        else
            local humanoid, root = livingNPC(model)
            local confirmed = humanoid and isMagnetized(model, humanoid) or false
            local markers = humanoid and magnetMarkers(model, humanoid, root) or ""
            if confirmed then
                table.insert(targets, model)
                if not record.confirmed then log("MAGNETIZED", path(model)) end
            end
            if markers ~= "" and markers ~= record.markers then
                log("MAGNET CANDIDATE", path(model) .. " | " .. markers)
            end
            record.confirmed, record.markers = confirmed, markers
        end
    end
end

local function normalizeAssetId(value)
    return value ~= nil and string.match(tostring(value), "%d+") or nil
end
local function fruitAnchor(instance)
    if not instance or not instance.Parent then return nil end
    if instance:IsA("BasePart") then return instance end
    local handle = instance:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then return handle end
    if instance:IsA("Model") and instance.PrimaryPart then return instance.PrimaryPart end
    return instance:FindFirstChildWhichIsA("BasePart", true)
end
local function identifyWorldFruit(instance)
    if not instance or instance.Parent ~= workspace then return nil end
    local name, anchor
    if instance:IsA("Tool") and contains(instance.Name, "fruit") then
        name, anchor = instance.Name, fruitAnchor(instance)
    elseif instance:IsA("Model") then
        for _, descendant in ipairs(instance:GetDescendants()) do
            local meshId
            if descendant:IsA("MeshPart") then
                meshId, anchor = descendant.MeshId, descendant
            elseif descendant:IsA("SpecialMesh") then
                meshId, anchor = descendant.MeshId, descendant.Parent
            end
            name = fruitNamesByMeshId[normalizeAssetId(meshId)]
            if name then break end
        end
        if not name and contains(instance.Name, "fruit") then name = instance.Name end
        anchor = anchor or fruitAnchor(instance)
    end
    if not name or not anchor or not anchor:IsA("BasePart") then return nil end
    if instance:FindFirstChild("Ignored") or anchor:FindFirstChild("Ignored") then return nil end
    return name, anchor
end
local function removeFruitRecord(instance)
    local record = fruitRecords[instance]
    if not record then return end
    if record.billboard then record.billboard:Destroy() end
    if record.highlight then record.highlight:Destroy() end
    fruitRecords[instance] = nil
    if fruitTask.target == instance then
        fruitTask.target, fruitTask.started = nil, nil
        releaseMovement()
    end
end
local function createFruitVisual(record)
    if not config.FruitESPEnabled or record.billboard then return end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EventMagnetFruitESP"
    billboard.Adornee, billboard.AlwaysOnTop = record.part, true
    billboard.LightInfluence = 0
    billboard.Size, billboard.StudsOffsetWorldSpace = UDim2.fromOffset(250, 38), Vector3.new(0, 3, 0)
    local text = Instance.new("TextLabel")
    text.BackgroundColor3, text.BackgroundTransparency = Color3.new(0, 0, 0), 0.35
    text.Size, text.Font, text.TextSize = UDim2.fromScale(1, 1), Enum.Font.SourceSansBold, 18
    text.TextStrokeTransparency = 0
    text.TextColor3 = fruitColors[record.name] or Color3.new(1, 1, 1)
    text.Parent, billboard.Parent = billboard, record.part
    local highlight = Instance.new("Highlight")
    highlight.Name = "EventMagnetFruitHighlight"
    highlight.Adornee = record.instance:IsA("Model") and record.instance or record.part
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor, highlight.OutlineColor = text.TextColor3, text.TextColor3
    highlight.FillTransparency, highlight.OutlineTransparency = 0.82, 0
    highlight.Parent = record.part
    record.billboard, record.label, record.highlight = billboard, text, highlight
end
local function addFruitRecord(instance)
    if fruitRecords[instance] then return false end
    local name, part = identifyWorldFruit(instance)
    if not name then return false end
    local record = { instance = instance, name = name, part = part, distance = math.huge,
        retryAt = 0, attempts = 0 }
    fruitRecords[instance] = record
    createFruitVisual(record)
    log("FRUIT", "Phat hien " .. short(name, 80))
    return true
end
local function refreshFruits()
    for _, child in ipairs(workspace:GetChildren()) do addFruitRecord(child) end
    for instance, record in pairs(fruitRecords) do
        if not instance:IsDescendantOf(workspace) then
            removeFruitRecord(instance)
        else
            local name, part = identifyWorldFruit(instance)
            if not name then removeFruitRecord(instance)
            else record.name, record.part = name, part end
        end
    end
end
local function updateFruitESP(root)
    for instance, record in pairs(fruitRecords) do
        if not instance:IsDescendantOf(workspace) or not record.part or not record.part.Parent then
            removeFruitRecord(instance)
        else
            record.distance = root and (record.part.Position - root.Position).Magnitude or math.huge
            createFruitVisual(record)
            if record.billboard then
                record.billboard.Adornee = record.part
                record.billboard.Enabled = config.FruitESPEnabled and root ~= nil
                record.highlight.Enabled = config.FruitESPEnabled and root ~= nil
                record.label.Text = record.name .. " [" .. math.floor(record.distance + 0.5) .. " studs]"
            end
        end
    end
end
local function isOwnedFruitTool(item)
    return item and item:IsA("Tool") and contains(item.Name, "fruit")
        and item:FindFirstChild("Handle") ~= nil
end
local function getFruitOriginalName(item)
    if not item then return nil end
    local ok, value = pcall(function() return item:GetAttribute("OriginalName") end)
    if ok and type(value) == "string" and value ~= "" then return value end
    local child = item:FindFirstChild("OriginalName")
    if child and child:IsA("StringValue") and child.Value ~= "" then return child.Value end
end
local function fruitIdentity(value)
    local name = string.lower(tostring(value or "")):gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub("%s+fruit$", "")
    name = name:gsub("[%(%)]", ""):gsub("%s+", " ")
    for separator = 1, #name do
        if string.sub(name, separator, separator) == "-" then
            local left, right = string.sub(name, 1, separator - 1), string.sub(name, separator + 1)
            if left ~= "" and left == right then return left end
        end
    end
    return name
end
local function ownedFruitMatches(record, item)
    if item == record.instance then return true end
    local wanted = fruitIdentity(record.name)
    return fruitIdentity(item.Name) == wanted
        or fruitIdentity(getFruitOriginalName(item)) == wanted
end
local function ownedFruitTools()
    local result = {}
    for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if isOwnedFruitTool(item) then table.insert(result, item) end
            end
        end
    end
    return result
end
-- Same FruitInfo source as auto_factory; resolve off the farm loop.
local fruitInfoList
task.spawn(function()
    local module = RS:WaitForChild("FruitInfo", 5)
    if not module then return end
    local ok, data = pcall(require, module)
    if ok and type(data) == "table" and type(data.List) == "table" then
        fruitInfoList = data.List
    end
end)
local mythicalFallback = {
    kitsune = true, dragon = true, leopard = true, ["t-rex"] = true, trex = true,
    mammoth = true, dough = true, shadow = true, venom = true, control = true,
    spirit = true, gravity = true,
}
local function hasMythicalFruit()
    for _, item in ipairs(ownedFruitTools()) do
        local identity = fruitIdentity(getFruitOriginalName(item) or item.Name)
        local rarity = item:GetAttribute("Rarity")
        local rarityValue = item:FindFirstChild("Rarity")
        if rarityValue and rarityValue:IsA("StringValue") then rarity = rarityValue.Value end
        if fruitInfoList then
            for key, entry in pairs(fruitInfoList) do
                if type(key) == "string" and type(entry) == "table"
                    and fruitIdentity(key) == identity then
                    rarity = entry.Rarity or rarity
                    break
                end
            end
        end
        if type(rarity) == "table" then rarity = rarity.Name end
        if type(rarity) == "string" then
            if rarity:lower() == "mythical" then return true, item.Name end
        elseif mythicalFallback[identity] then
            return true, item.Name
        end
    end
    return false
end
local function inventoryFruitCount(commF, storageName)
    local ok, rows = pcall(function() return commF:InvokeServer("getInventoryFruits") end)
    if not ok or type(rows) ~= "table" then return nil end
    local count = 0
    for _, row in pairs(rows) do
        if type(row) == "table" and row.Name == storageName then count = count + 1 end
    end
    return count
end
local function responseConfirmsStore(response)
    if response == true then return true end
    if type(response) == "table" and (response.Success == true or response.Stored == true) then return true end
    if type(response) == "string" then
        local lowered = string.lower(response)
        return lowered == "success" or lowered == "stored" or lowered == "stored."
            or contains(lowered, "stored successfully") or contains(lowered, "successfully stored")
    end
    return false
end
local function responseRejectsStore(response)
    if response == false then return true end
    local lowered = string.lower(tostring(response or ""))
    return contains(lowered, "full") or contains(lowered, "maximum")
        or contains(lowered, "cannot store") or contains(lowered, "already have")
end
local function getStoreSummary()
    local owned, blocked, waiting = ownedFruitTools(), 0, 0
    for _, item in ipairs(owned) do
        local record = storeRecords[item]
        if record and record.blocked then blocked = blocked + 1
        elseif record and record.retryAt > os.clock() then waiting = waiting + 1 end
    end
    return owned, blocked, waiting
end
-- Webhook format/events/rarity filter adapted from auto_factory.lua.
-- Only this queue sends HTTP; no Worker, hop API or downloaded code.
local sendFruitWebhook
do
    local fruitInfo, queue = nil, {}
    local seen = setmetatable({}, {__mode = "k"})
    local tiers = {common = 1, uncommon = 2, rare = 3, legendary = 4, mythical = 5}
    local fallback = {
        kitsune = 5, dragon = 5, leopard = 5, ["t-rex"] = 5, trex = 5,
        mammoth = 5, dough = 5, shadow = 5, venom = 5, control = 5, spirit = 5, gravity = 5,
        portal = 4, blizzard = 4, rumble = 4, buddha = 4, sound = 4, phoenix = 4,
        spider = 4, string = 4, love = 4, pain = 4, paw = 4, quake = 4,
    }
    task.spawn(function()
        local module = RS:WaitForChild("FruitInfo", 5)
        local ok, data = pcall(function() return module and require(module) end)
        if alive and env.EventMagnetFarm == api and ok and type(data) == "table" then
            fruitInfo = data.List
        end
    end)
    local function tierOf(name, storageName)
        local wanted = fruitIdentity(storageName or name)
        if type(fruitInfo) == "table" then
            for key, row in pairs(fruitInfo) do
                if type(key) == "string" and fruitIdentity(key) == wanted and type(row) == "table" then
                    local rarity = type(row.Rarity) == "table" and row.Rarity.Name or row.Rarity
                    if type(rarity) == "string" and tiers[rarity:lower()] then return tiers[rarity:lower()] end
                end
            end
        end
        return fallback[wanted] or 0
    end
    sendFruitWebhook = function(eventType, fruitName, tool, storageName)
        if not alive or env.EventMagnetFarm ~= api or not config.WebhookEnabled then return end
        if eventType == "Picked" and not config.WebhookOnPickup
            or eventType == "Random" and not config.WebhookOnRandom
            or eventType == "Stored" and not config.WebhookOnStore then return end
        local url = tostring(env.WebhookURL or ""):match("^%s*(.-)%s*$")
        if url == "" then url = tostring(config.WebhookURL or ""):match("^%s*(.-)%s*$") end
        if url == "" then return end
        if not url:match("^https://") then log("WEBHOOK", "URL phai bat dau bang https://"); return end
        local minimum = tostring(env.WebhookMinRarity or config.WebhookMinRarity):lower()
        local threshold = minimum == "all" and 0 or (minimum == "mythical" and 5 or 4)
        if tierOf(fruitName, storageName) < threshold then return end
        if tool then
            seen[tool] = seen[tool] or {}
            if seen[tool][eventType] then return end
            seen[tool][eventType] = true
        end
        if #queue >= 50 then log("WEBHOOK", "Hang doi day; bo qua thong bao moi"); return end
        local titles = {Picked = "Picked Fruit", Random = "Random Fruit", Stored = "Stored Fruit"}
        local embed = {
            title = config.WebhookTitle, description = "**Main Status**\nUsername : ||" .. player.Name .. "||",
            color = config.WebhookColor, footer = {text = config.WebhookFooterText},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            fields = {
                {name = titles[eventType] or "Fruit", value = "```\n" .. short(fruitName, 150) .. "\n```", inline = false},
                {name = "Username", value = "||" .. player.Name .. "||", inline = true},
                {name = "Time", value = os.date("%Y-%m-%d %H:%M:%S"), inline = true},
                {name = "PlaceId", value = tostring(game.PlaceId), inline = true},
            },
        }
        if config.WebhookBannerURL:match("^https://") then embed.thumbnail = {url = config.WebhookBannerURL} end
        local payload = {content = config.WebhookPing, username = config.WebhookUsername, embeds = {embed},
            allowed_mentions = {parse = {}}}
        -- Pings are opt-in; never infer @everyone from a fruit notification.
        if config.WebhookPing == "@everyone" or config.WebhookPing == "@here" then
            payload.allowed_mentions = {parse = {"everyone"}}
        end
        if config.WebhookAvatarURL:match("^https://") then payload.avatar_url = config.WebhookAvatarURL end
        queue[#queue + 1] = {url = url, payload = payload}
    end
    task.spawn(function()
        while alive and env.EventMagnetFarm == api do
            task.wait(0.5)
            if not alive or env.EventMagnetFarm ~= api then break end
            local entry = table.remove(queue, 1)
            if entry then
                local requestFn = (type(request) == "function" and request)
                    or (type(http_request) == "function" and http_request)
                    or (type(syn) == "table" and syn.request) or (type(http) == "table" and http.request)
                    or (type(fluxus) == "table" and fluxus.request)
                if type(requestFn) ~= "function" then log("WEBHOOK", "Executor khong ho tro HTTP")
                else
                    local ok, response = pcall(function()
                        return requestFn({Url = entry.url, Method = "POST",
                            Headers = {["Content-Type"] = "application/json"},
                            Body = HttpService:JSONEncode(entry.payload)})
                    end)
                    if alive then
                        local code = type(response) == "table" and tonumber(response.StatusCode or response.Status or response.status_code)
                        log("WEBHOOK", ok and code and code >= 200 and code < 300
                            and "Da gui" or "Gui loi/chua xac nhan; khong tu gui lai")
                    end
                end
            end
        end
    end)
end
local function startStore(item, force)
    if not config.StoreFruit or action.kind or randomToken.busy then return false end
    local record = storeRecords[item] or { attempts = 0, retryAt = 0, blocked = false }
    storeRecords[item] = record
    if not force and (record.blocked or record.retryAt > os.clock()) then return false end
    local storageName = getFruitOriginalName(item)
    if not storageName then
        record.retryAt = os.clock() + config.StoreRetryDelay
        record.last = "Cho OriginalName"
        return false
    end
    local remotesFolder = RS:FindFirstChild("Remotes")
    local commF = remotesFolder and remotesFolder:FindFirstChild("CommF_")
    if not commF then
        record.retryAt = os.clock() + config.StoreRetryDelay
        record.last = "Khong tim thay CommF_"
        return false
    end
    local token = beginAction("store")
    if not token then return false end
    releaseMovement()
    task.spawn(function()
        local before = inventoryFruitCount(commF, storageName)
        if not actionIsCurrent("store", token) or hasLiveMagnetized() then
            endAction("store", token); return
        end
        record.attempts = record.attempts + 1
        local ok, response = pcall(function()
            return commF:InvokeServer("StoreFruit", storageName, item)
        end)
        if not actionIsCurrent("store", token) then return end
        -- auto_factory: wait briefly for the Tool to leave the inventory.
        local deadline = os.clock() + 0.5
        while actionIsCurrent("store", token) and os.clock() < deadline do task.wait(0.1) end
        if not actionIsCurrent("store", token) then return end
        local after = inventoryFruitCount(commF, storageName)
        if not actionIsCurrent("store", token) then return end
        local backpack = player:FindFirstChild("Backpack")
        local stillOwned = item.Parent and ((backpack and item:IsDescendantOf(backpack))
            or (player.Character and item:IsDescendantOf(player.Character)))
        local confirmed = ok and not stillOwned and (responseConfirmsStore(response)
            or (before ~= nil and after ~= nil and after > before))
        if confirmed then
            record.blocked, record.last = false, "Da luu xac nhan"
            record.retryAt, record.attempts = os.clock() + config.StoreRetryDelay, 0
            log("STORE", short(item.Name, 80) .. ": da luu")
            sendFruitWebhook("Stored", item.Name, item, storageName)
        else
            -- Ported from auto_factory: a completed call with a remaining Tool
            -- is skipped for this instance; transport failures remain retryable.
            local permanent = ok and (stillOwned or responseRejectsStore(response))
            record.blocked = permanent or false
            record.retryAt = os.clock() + config.StoreRetryDelay
            record.last = permanent and "Bo qua trai khong luu duoc (Tool nay)"
                or (ok and "Chua xac nhan luu" or short(response, 100))
            log("STORE", short(item.Name, 80) .. ": " .. record.last
                .. (record.blocked and "; chan hop" or "; se thu lai"))
        end
        endAction("store", token)
    end)
    return true
end
function api.GetFruits()
    local result = {}
    for _, record in pairs(fruitRecords) do
        table.insert(result, { instance = record.instance, name = record.name,
            distance = record.distance, attempts = record.attempts, retryAt = record.retryAt })
    end
    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result
end
function api.RetryStore()
    for _, item in ipairs(ownedFruitTools()) do
        local record = storeRecords[item]
        if record then record.blocked, record.retryAt, record.attempts = false, 0, 0 end
    end
    return true
end
connect(workspace.ChildAdded, function(child)
    task.defer(function() if alive then addFruitRecord(child) end end)
end)
connect(workspace.ChildRemoved, removeFruitRecord)
refreshFruits()

-- Same lifecycle as auto_factory: watch while enabled, not just a short roll timer.
do
    local spinnerController, lastClose = nil, 0
    task.spawn(function()
        local ok, controller = pcall(function()
            local controllers = RS:WaitForChild("Controllers", 10)
            local ui = controllers and controllers:WaitForChild("UI", 10)
            local module = ui and ui:WaitForChild("Spinner", 10)
            return module and require(module)
        end)
        if alive and env.EventMagnetFarm == api and ok and type(controller) == "table" then
            spinnerController = controller
        end
    end)
    local function showing(item)
        return item and ((item:IsA("ScreenGui") and item.Enabled) or (item:IsA("GuiObject") and item.Visible))
    end
    local function hide(item)
        if item:IsA("ScreenGui") then item.Enabled = false
        elseif item:IsA("GuiObject") then item.Visible = false end
    end
    task.spawn(function()
        while alive and env.EventMagnetFarm == api do
            task.wait(0.2)
            if not alive or env.EventMagnetFarm ~= api then break end
            if enabled then
                pcall(function()
                    local pg = player:FindFirstChildOfClass("PlayerGui")
                    if not pg then return end
                    local window = pg:FindFirstChild("SpinnerWindow")
                    if config.AutoCloseSpinner and showing(window) then
                        local above = window:FindFirstChild("AboveSpinner")
                        local navigation = above and above:FindFirstChild("Navigation")
                        local close = navigation and navigation:FindFirstChild("CloseButton")
                        if close and close:IsA("GuiObject") and close.Visible and os.clock() - lastClose >= 0.5 then
                            lastClose = os.clock()
                            local closed = false
                            if spinnerController and type(spinnerController.Close) == "function" then
                                closed = pcall(function() spinnerController:Close() end)
                            end
                            if not closed then hide(window) end
                        end
                    end
                    if config.AutoHideItemNotice then
                        for _, name in ipairs({"Item", "ItemUI"}) do
                            local notice = pg:FindFirstChild(name)
                            if showing(notice) then hide(notice) end
                        end
                    end
                end)
            end
        end
    end)
end
-- Auto Buso adapted from auto_factory.lua: remote, HasBuso confirmation,
-- then J fallback. One session-bound coroutine; never blocks combat Heartbeat.
do
    task.spawn(function()
        local function current(character)
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            return alive and enabled and config.AutoBuso and env.EventMagnetFarm == api
                and character ~= nil and character == player.Character and character.Parent ~= nil
                and humanoid and humanoid.Health > 0
        end
        local function confirmed(character, timeout)
            local deadline = os.clock() + timeout
            repeat
                if not current(character) then return false end
                if character:FindFirstChild("HasBuso") then return true end
                task.wait(0.1)
            until os.clock() >= deadline
            return current(character) and character:FindFirstChild("HasBuso") ~= nil
        end
        while alive and env.EventMagnetFarm == api do
            local character = player.Character
            local hasBuso = character and character:FindFirstChild("HasBuso") ~= nil
            if current(character) and not hasBuso then
                local ok = pcall(function()
                    local folder = RS:FindFirstChild("Remotes")
                    local remote = folder and folder:FindFirstChild("CommF_")
                    if remote and remote:IsA("RemoteFunction") then remote:InvokeServer("Buso") end
                    hasBuso = confirmed(character, config.BusoConfirmTimeout)
                    if not hasBuso and config.UseBusoKeyFallback and current(character)
                        and not character:FindFirstChild("HasBuso") then
                        local pressed = pcall(function()
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.J, false, game)
                            task.wait(0.05)
                        end)
                        -- Always release J, even if Stop/respawn happened during the press.
                        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.J, false, game) end)
                        if pressed then hasBuso = confirmed(character, 0.75) end
                    end
                end)
                if alive and env.EventMagnetFarm == api and (not ok or not hasBuso) then
                    log("BUSO", "Chua xac nhan HasBuso; cho thu lai")
                end
            end
            task.wait(hasBuso and config.BusoCheckDelay or config.BusoRetryDelay)
        end
    end)
end
-- A single movement owner serves both patrol and combat.
local function flyTo(root, humanoid, destination, dt, facing)
    if moveRoot ~= root then
        releaseMovement()
        moveRoot, moveHumanoid, oldPlatform = root, humanoid, humanoid.PlatformStand
        floatForce = Instance.new("BodyVelocity")
        floatForce.Name = "EventMagnetFloat"
        floatForce.MaxForce = Vector3.new(1e5, 1e5, 1e5)
        floatForce.Velocity = Vector3.zero
        floatForce.Parent = root
    end
    humanoid.PlatformStand = true
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    local delta = destination - root.Position
    local position = root.Position
    if delta.Magnitude > 0.01 then
        position = position + delta.Unit * math.min(config.Speed * math.clamp(dt, 0, 0.1), delta.Magnitude)
    end
    local flatFacing = facing and Vector3.new(facing.X, position.Y, facing.Z)
    if flatFacing and (flatFacing - position).Magnitude > 0.01 then
        root.CFrame = CFrame.lookAt(position, flatFacing)
    else
        root.CFrame = CFrame.new(position) * root.CFrame.Rotation
    end
end
local sea = ({
    [2753915549] = 1, [85211729168715] = 1,
    [4442272183] = 2, [79091703265657] = 2,
    [7449423635] = 3, [100117331123089] = 3,
})[game.PlaceId]
hop.readyAt = nil
hop.checked = serverChoiceMemory[game.JobId] == true
do
    local ok, chosen = pcall(function() return TeleportService:GetTeleportSetting("EventMagnetChosenServer") end)
    if ok and type(chosen) == "table" and chosen.id == game.JobId
        and type(chosen.expires) == "number" and chosen.expires > os.time() then
        hop.checked = true
        serverChoiceMemory[game.JobId] = true
        hop.status = "Da vao server duoc bo hop lua chon"
    end
end

local function portalTool()
    local character, backpack = player.Character, player:FindFirstChildOfClass("Backpack")
    return (character and character:FindFirstChild("Portal-Portal"))
        or (backpack and backpack:FindFirstChild("Portal-Portal"))
end
local function portalSkillReady(tool)
    if not tool then return false, "Khong co Portal-Portal" end
    local data = player:FindFirstChild("Data")
    local devilFruit = data and data:FindFirstChild("DevilFruit")
    if devilFruit and devilFruit.Value ~= "Portal-Portal" then return false, "Chua dung trai Portal" end
    local level = tool:FindFirstChild("Level")
    local mastery = level and tonumber(level.Value)
    if mastery and mastery < 200 then return false, "Portal C chua du mastery" end
    return true, mastery and ("Mastery " .. math.floor(mastery)) or "Portal san sang"
end
local function openGateway()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    local gateway = pg and pg:FindFirstChild("Gateway", true)
    if gateway and gateway:IsA("GuiObject") and gateway.Visible then return gateway end
end
local function normalizePortalText(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end
local function portalAliases(name)
    local aliases = portalRouteAliases[sea] or {}
    return aliases[name] or { name }
end
local function portalRouteKey(name)
    local aliases = portalAliases(name)
    return normalizePortalText(aliases[1] or name)
end
local function nearestPortalAnchor(position)
    local nearestName, nearestDistance
    for name, anchor in pairs(portalDestinations[sea] or {}) do
        local distance = (position - anchor).Magnitude
        if not nearestDistance or distance < nearestDistance then
            nearestName, nearestDistance = name, distance
        end
    end
    if nearestDistance and nearestDistance <= config.PortalTargetRadius then
        return nearestName, nearestDistance
    end
end
local function bestPortalFor(targetPosition, rootPosition)
    local bestName, bestPosition, bestSaving
    local direct = (targetPosition - rootPosition).Magnitude
    for name, position in pairs(portalDestinations[sea] or {}) do
        local remaining = (targetPosition - position).Magnitude
        local saving = direct - remaining
        if remaining <= config.PortalTargetRadius and saving >= config.PortalMinSaving
            and (not bestSaving or saving > bestSaving) then
            bestName, bestPosition, bestSaving = name, position, saving
        end
    end
    return bestName, bestPosition
end
local function findGatewayButton(scrolling, destinationName)
    local buttons = {}
    for _, descendant in ipairs(scrolling:GetDescendants()) do
        if descendant:IsA("GuiButton") then table.insert(buttons, descendant) end
    end
    local function buttonLabels(button)
        local labels = { button.Name }
        if button:IsA("TextButton") then table.insert(labels, button.Text) end
        for _, descendant in ipairs(button:GetDescendants()) do
            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                table.insert(labels, descendant.Text)
            end
        end
        return labels
    end
    local aliases = { destinationName }
    for _, alias in ipairs(portalAliases(destinationName)) do table.insert(aliases, alias) end
    for _, alias in ipairs(aliases) do
        local wanted = normalizePortalText(alias)
        for _, button in ipairs(buttons) do
            for _, label in ipairs(buttonLabels(button)) do
                if normalizePortalText(label) == wanted then return button, alias end
            end
        end
    end
    -- Some game versions append the Sea/status to the visible button label.
    for _, alias in ipairs(aliases) do
        local wanted = normalizePortalText(alias)
        if #wanted >= 5 then
            for _, button in ipairs(buttons) do
                for _, label in ipairs(buttonLabels(button)) do
                    if string.find(normalizePortalText(label), wanted, 1, true) then
                        return button, alias
                    end
                end
            end
        end
    end
end
local function activateExactButton(button, legacy)
    local signal = legacy and button.MouseButton1Click or button.Activated
    local getConnections = rawget(env, "getconnections")
    if type(getConnections) ~= "function" and type(getconnections) == "function" then
        getConnections = getconnections
    end
    if type(getConnections) == "function" then
        local ok, list = pcall(getConnections, signal)
        if ok and type(list) == "table" then
            local fired = false
            for _, connection in pairs(list) do
                local gotFunction, callback = pcall(function() return connection.Function end)
                if gotFunction and type(callback) == "function"
                    and pcall(callback) then fired = true end
            end
            if fired then return true end
        end
    end
    if type(firesignal) == "function" then
        return pcall(function() firesignal(signal) end)
    end
    return false
end
closePortalMenu = function()
    local gateway = openGateway()
    if not gateway then return end
    for _, item in ipairs(gateway:GetDescendants()) do
        if item:IsA("GuiButton") and (string.lower(item.Name):find("close", 1, true)
            or (item:IsA("TextButton") and item.Text == "X")) then
            activateExactButton(item, true)
            break
        end
    end
    -- Local UI cleanup only; this is not a claim that a server warp was cancelled.
    if gateway.Parent then gateway.Visible = false end
end
local function tryStartPortal(targetPosition, root, humanoid, forCombat)
    local distance = (targetPosition - root.Position).Magnitude
    if action.kind then return false end
    if not config.UsePortalFruit or not (sea == 2 or sea == 3)
        or distance < config.PortalLongDistance or os.clock() < portal.retryAt
        then
        if openGateway() then pcall(closePortalMenu) end
        return false
    end
    local name = bestPortalFor(targetPosition, root.Position)
    if not name then
        portal.lastResult = "Khong co diem Portal gan dich; bay 190"
        if openGateway() then pcall(closePortalMenu) end
        return false
    end
    local tool = portalTool()
    local usable, reason = portalSkillReady(tool)
    if not usable and not openGateway() then
        portal.retryAt, portal.lastResult = os.clock() + config.PortalCooldown, reason
        return false
    end
    local currentName = nearestPortalAnchor(root.Position)
    if currentName and portalRouteKey(currentName) == portalRouteKey(name) then
        if openGateway() then pcall(closePortalMenu) end
        portal.lastResult = "Cung vung " .. tostring(portalAliases(name)[1]) .. "; bay 190"
        return false
    end
    local token = beginAction("portal")
    if not token then return false end
    portal.destination, portal.forCombat = name, forCombat == true
    portal.retryAt = os.clock() + config.PortalCooldown
    local oldPosition = root.Position
    local oldDistance = distance
    releaseMovement()
    task.spawn(function()
        local success, detail = false, "Gateway khong mo"
        local ok, runtimeError = xpcall(function()
            if not actionIsCurrent("portal", token)
                or (hasLiveMagnetized() and not forCombat) then return end
            local gateway = openGateway()
            if not gateway and tool and tool.Parent ~= player.Character then humanoid:EquipTool(tool); task.wait(0.15) end
            if not actionIsCurrent("portal", token)
                or (hasLiveMagnetized() and not forCombat) then return end
            if not gateway then pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.C, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.C, false, game)
            end) end
            local deadline = os.clock() + config.GatewayOpenTimeout
            while actionIsCurrent("portal", token) and os.clock() < deadline do
                gateway = openGateway()
                if gateway and gateway.Visible then break end
                task.wait(0.1)
            end
            if not actionIsCurrent("portal", token)
                or (hasLiveMagnetized() and not forCombat) then return end
            if not gateway or not gateway.Visible then return end
            local button, matched = findGatewayButton(gateway, name)
            local routeLabel = matched or portalAliases(name)[1] or name
            if not button then detail = "Khong co nut " .. tostring(routeLabel); return end
            local activated = activateExactButton(button)
            local fallbackUsed = not activated
            if fallbackUsed then activated = activateExactButton(button, true) end
            if not activated then detail = "Khong bam duoc nut " .. tostring(routeLabel); return end
            detail = "Da bam " .. tostring(routeLabel) .. "; cho xac nhan"
            local arrivalDeadline = os.clock() + config.GatewayArrivalTimeout
            local clickFallbackAt = os.clock() + 1
            while actionIsCurrent("portal", token) and os.clock() < arrivalDeadline do
                local character = player.Character
                local newRoot = rootOf(character)
                if newRoot then
                    local newDistance = (targetPosition - newRoot.Position).Magnitude
                    local moved = (newRoot.Position - oldPosition).Magnitude
                    if newDistance <= config.GatewayArrivalRadius
                        or (moved >= config.GatewayMoveThreshold
                            and newDistance <= oldDistance - config.GatewayMoveThreshold) then
                        success, detail = true, "Da xac nhan World Warp " .. tostring(routeLabel)
                        break
                    end
                end
                if not fallbackUsed and os.clock() >= clickFallbackAt and openGateway()
                    and newRoot and (newRoot.Position - oldPosition).Magnitude < config.GatewayMoveThreshold then
                    fallbackUsed = true
                    activateExactButton(button, true)
                end
                task.wait(0.2)
            end
            if not success then
                detail = "Da bam " .. tostring(routeLabel) .. " nhung chua xac nhan dich chuyen"
            end
        end, function(err) return tostring(err) end)
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.C, false, game) end)
        if actionIsCurrent("portal", token) then
            pcall(closePortalMenu)
            portal.lastResult = ok and detail or short(runtimeError, 100)
            log("PORTAL", portal.lastResult)
            portal.destination, portal.forCombat = nil, false
            endAction("portal", token)
            if not success then releaseMovement() end
        end
    end)
    return true
end

-- Adapted from the user's Standalone Low Player Server Hop (Multi-Account).
-- All waits belong to this farm session; no second movement/controller loop.
local hopRandom = Random.new()
local hopVisited = {}
do
    local ok, saved = pcall(function() return TeleportService:GetTeleportSetting("EventMagnetHopTTL") end)
    if ok and type(saved) == "table" then hopVisited = saved end
end
local function loadVisitedServers()
    local seen = { [game.JobId] = true }
    for id, expires in pairs(hopVisited) do
        if type(expires) == "number" and expires > os.time() then seen[id] = true
        else hopVisited[id] = nil end
    end
    return seen
end
local function saveVisitedServer(id)
    hopVisited[id] = eventDeadline
    pcall(function() TeleportService:SetTeleportSetting("EventMagnetHopTTL", hopVisited) end)
end
local function hopAllowed(token)
    local character = player.Character
    if not character or not character:FindFirstChild("HasBuso") then return false end
    return actionIsCurrent("hop", token) and (hop.startup or eventStillOpen())
        and (hop.startup or not hasLiveMagnetized()) and not hasMythicalFruit() and not randomToken.busy
end
local function hopRequest(options)
    local requestFn = (type(http_request) == "function" and http_request)
        or (type(request) == "function" and request)
        or (type(syn) == "table" and syn.request)
        or (type(http) == "table" and http.request)
        or (type(fluxus) == "table" and fluxus.request)
    if type(requestFn) ~= "function" then return nil end
    options.url, options.method = options.Url, options.Method or "GET"
    options.headers, options.body = options.Headers, options.Body
    return requestFn(options)
end
local function hopCall(token, callback)
    local done, ok, value = false, false, nil
    task.spawn(function()
        if hopAllowed(token) then ok, value = pcall(callback) end
        done = true
    end)
    local deadline = os.clock() + config.HopBrowserTimeout
    while not done and hopAllowed(token) and os.clock() < deadline do task.wait(0.1) end
    if not done then
        -- A yielded request cannot be revoked; don't accumulate more requests.
        hop.blocked = true
        return false, "Request timeout/da huy; dung hop phien nay"
    end
    return ok, value
end
local function workerRequest(path, payload)
    if config.HopApiUrl == "" then return nil end
    return hopRequest({
        Url = config.HopApiUrl:gsub("/+$", "") .. path,
        Method = payload and "POST" or "GET",
        Headers = { ["Content-Type"] = "application/json" },
        Body = payload and HttpService:JSONEncode(payload) or nil,
    })
end
local function fetchOccupiedServers(token)
    local occupied = loadVisitedServers()
    if config.HopApiUrl == "" then return occupied end
    local ok, response = hopCall(token, function() return workerRequest("/api/occupied") end)
    if ok and type(response) == "table" and tonumber(response.StatusCode) == 200 then
        local decoded, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if decoded and type(data) == "table" and type(data.occupied) == "table" then
            for _, id in ipairs(data.occupied) do occupied[tostring(id)] = true end
        end
    end
    return occupied
end
local function chooseHopCandidate(candidates)
    if #candidates == 0 then return nil end
    local best, ties = math.huge, {}
    for _, candidate in ipairs(candidates) do
        if candidate.playing < best then best, ties = candidate.playing, { candidate }
        elseif candidate.playing == best then table.insert(ties, candidate) end
    end
    return ties[config.HopRandomizeTies and hopRandom:NextInteger(1, #ties) or 1]
end
local function findHopCandidates(token, occupied)
    local browser = RS:FindFirstChild("__ServerBrowser")
    if browser and not browser:IsA("RemoteFunction") then browser = nil end
    local candidates, added, empty = {}, {}, 0
    local function add(id, count, maximum)
        if type(id) == "string" and id ~= "" and count and count >= 0
            and count <= config.HopMaxPlayers and count < maximum
            and not occupied[id] and not added[id] then
            added[id] = true
            table.insert(candidates, { id = id, playing = count, browser = browser })
        end
    end
    if browser then
        for page = 1, config.HopMaxPages do
            if not hopAllowed(token) or hop.blocked then return nil end
            hop.status = "Quet ServerBrowser trang " .. page
            local ok, servers = hopCall(token, function() return browser:InvokeServer(page) end)
            if hop.blocked then return nil end
            if not ok or type(servers) ~= "table" or next(servers) == nil then empty = empty + 1
            else
                empty = 0
                for id, info in pairs(servers) do
                    if type(info) == "table" then add(id, tonumber(info.Count), 12) end
                end
            end
            local best = chooseHopCandidate(candidates)
            if (best and best.playing <= config.TargetExistingPlayers) or empty >= config.HopEmptyPageLimit then break end
            task.wait(config.HopPageDelay)
        end
    end
    local best = chooseHopCandidate(candidates)
    if best then return best end
    -- User script's Roblox public-server API fallback, always the current PlaceId.
    local cursor = ""
    for page = 1, 4 do
        if not hopAllowed(token) or hop.blocked then return nil end
        hop.status = "Quet Roblox API trang " .. page
        local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100", tostring(game.PlaceId))
        if cursor ~= "" then url = url .. "&cursor=" .. HttpService:UrlEncode(cursor) end
        local ok, response = hopCall(token, function() return hopRequest({ Url = url, Method = "GET" }) end)
        if not ok or type(response) ~= "table" or tonumber(response.StatusCode) ~= 200 then break end
        local decoded, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then break end
        for _, info in ipairs(data.data) do
            if type(info) == "table" then add(info.id, tonumber(info.playing), tonumber(info.maxPlayers) or 12) end
        end
        best = chooseHopCandidate(candidates)
        if best and best.playing <= config.TargetExistingPlayers then break end
        cursor = type(data.nextPageCursor) == "string" and data.nextPageCursor or ""
        if cursor == "" then break end
        task.wait(0.2)
    end
    return chooseHopCandidate(candidates)
end
local function queueContinuation()
    if continuationQueued then return true end
    local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    if type(queue) ~= "function" or type(continuationSource) ~= "string" then
        hop.blocked, hop.status = true, "Executor khong ho tro tu chay tiep sau hop"
        return false
    end
    local configJSON = HttpService:JSONEncode(config)
    local payload = string.format(
        "local e=getgenv(); e.__EventMagnetV2Source=%q; e.__EventMagnetV2Deadline=%s; e.EventMagnetV2Config=game:GetService('HttpService'):JSONDecode(%q); if not game:IsLoaded() then game.Loaded:Wait() end; local f,err=loadstring(e.__EventMagnetV2Source); assert(f,err); f()",
        continuationSource, tostring(eventDeadline), configJSON)
    local ok, err = pcall(queue, payload)
    if not ok then
        hop.blocked, hop.status = true, "Khong queue duoc script: " .. tostring(err)
        return false
    end
    continuationQueued = true
    return true
end
local function requestHopTeleport(token, candidate)
    if config.HopApiUrl ~= "" then
        hopCall(token, function() return workerRequest("/api/reserve", { jobId = candidate.id }) end)
    end
    if not hopAllowed(token) or hop.blocked then return "cancelled" end
    if not queueContinuation() then return "cancelled" end
    if not hopAllowed(token) then return "cancelled" end
    saveVisitedServer(candidate.id)
    -- Accept our chosen fallback server after re-execute, avoiding a hop chain.
    pcall(function()
        TeleportService:SetTeleportSetting("EventMagnetChosenServer", {
            id = candidate.id, expires = os.time() + 120,
        })
    end)
    hop.status = "Dang vao server " .. candidate.playing .. " nguoi"
    local failed, started, done, failureMessage = false, false, false, nil
    local failedConnection = TeleportService.TeleportInitFailed:Connect(function(who, result, message)
        if who == player then failed, failureMessage = true, tostring(result) .. ": " .. tostring(message) end
    end)
    local stateConnection = player.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then started = true end
        if state == Enum.TeleportState.Failed then failed, failureMessage = true, failureMessage or "Teleport failed" end
    end)
    hop.dispatched = true
    task.spawn(function()
        if not hopAllowed(token) then done, failed = true, true; return end
        local ok, err = false, nil
        if candidate.browser then
            ok, err = pcall(function() candidate.browser:InvokeServer("teleport", candidate.id) end)
        end
        -- Match supplied fallback only on a thrown call error or missing browser;
        -- never send a second route after Started or an explicit restriction.
        if not ok and not started and not failed and hopAllowed(token) then
            ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, candidate.id, player) end)
        end
        if not ok then failed, failureMessage = true, tostring(err) end
        done = true
    end)
    local deadline = os.clock() + config.HopTeleportTimeout
    while actionIsCurrent("hop", token) and not failed and os.clock() < deadline do task.wait(0.2) end
    if failed and actionIsCurrent("hop", token) then task.wait(0.3) end
    failedConnection:Disconnect(); stateConnection:Disconnect()
    hop.dispatched = false
    if not actionIsCurrent("hop", token) then return "cancelled" end
    if started and not failed or not done then
        hop.blocked = true
        hop.status = "Teleport chua ro ket qua; dung hop phien nay"
        return "pending"
    end
    -- A completed request with no departure can retry as in the supplied script.
    hop.status = failureMessage or "Van o server cu sau timeout; thu server khac"
    log("HOP", hop.status)
    return "retry"
end
local function startHop(startup)
    if hop.busy or hop.blocked or action.kind or randomToken.busy
        or (not startup and not eventStillOpen()) then return false end
    hop.startup = startup == true
    local token = beginAction("hop")
    if not token then return false end
    hop.busy, hop.status = true, "Dang tim server it nguoi"
    releaseMovement()
    task.spawn(function()
        local ok, err = pcall(function()
            for attempt = 1, config.HopMaxAttempts do
                if not hopAllowed(token) or hop.blocked then break end
                hop.status = "Quet server lan " .. attempt .. "/" .. config.HopMaxAttempts
                local occupied = fetchOccupiedServers(token)
                if not hopAllowed(token) or hop.blocked then break end
                local candidate = findHopCandidates(token, occupied)
                if candidate and hopAllowed(token) and not hop.blocked then
                    local outcome = requestHopTeleport(token, candidate)
                    if outcome ~= "retry" then break end
                end
                local deadline = os.clock() + config.HopAttemptDelay
                while hopAllowed(token) and os.clock() < deadline do task.wait(0.1) end
            end
        end)
        if actionIsCurrent("hop", token) then
            hop.busy, hop.retryAt = false, os.clock() + config.HopRetryDelay
            if not ok then hop.status = "Hop loi: " .. short(err, 100)
            elseif not hop.blocked then hop.status = "Het luot quet; cho thu lai" end
            log("HOP", hop.status)
            endAction("hop", token)
        end
    end)
    return true
end

local islandMode = sea == 1 and config.Sea1IslandMode and config.Patrol
-- Explicit groups: a completed island cannot be re-added by a new spawn marker.
-- Sky regions at different elevations are separate stops to allow streaming.
local sea1Islands = {
    ["Bandit"] = "Starter Pirate",
    ["Monkey"] = "Jungle", ["Gorilla"] = "Jungle",
    ["Pirate"] = "Pirate Village", ["Brute"] = "Pirate Village",
    ["Desert Bandit"] = "Desert", ["Desert Officer"] = "Desert",
    ["Snow Bandit"] = "Frozen Village", ["Snowman"] = "Frozen Village",
    ["Chief Petty Officer"] = "Marine Fortress",
    ["Sky Bandit"] = "Skylands Lower", ["Dark Master"] = "Skylands Lower",
    ["God's Guard"] = "Skylands Lower",
    ["Prisoner"] = "Prison", ["Dangerous Prisoner"] = "Prison",
    ["Toga Warrior"] = "Colosseum", ["Gladiator"] = "Colosseum",
    ["Mil. Soldier"] = "Magma Village", ["Mil. Spy"] = "Magma Village",
    ["Fishman Warrior"] = "Underwater City", ["Fishman Commando"] = "Underwater City",
    ["Shanda"] = "Skylands Upper", ["Royal Squad"] = "Skylands Upper",
    ["Royal Soldier"] = "Skylands Upper",
    ["Galley Pirate"] = "Fountain City", ["Galley Captain"] = "Fountain City",
}
local function islandAt(position)
    local name, distance = nil, 1500
    for _, row in ipairs(seedRoutes[1]) do
        local delta = (row[2] - position).Magnitude
        if delta < distance then name, distance = sea1Islands[row[1]], delta end
    end
    -- Extra regions discovered from live markers use their own anchor.
    for _, point in ipairs(patrol.points) do
        local delta = (point.position - position).Magnitude
        if delta < distance then name, distance = point.name, delta end
    end
    return name
end
-- Exact normalized names also cover spawn markers without a [Boss] suffix.
local patrolBossNames = {}
for _, name in ipairs({
    "Gorilla King", "Bobby", "The Saw", "Yeti", "Mob Leader", "Vice Admiral",
    "Warden", "Chief Warden", "Swan", "Magma Admiral", "Fishman Lord",
    "Wysper", "Thunder God", "Cyborg", "Saber Expert", "Greybeard",
    "Diamond", "Jeremy", "Fajita", "Don Swan", "Darkbeard", "Order",
    "Smoke Admiral", "Cursed Captain", "Awakened Ice Admiral", "Tide Keeper",
    "Stone", "Island Empress", "Kilo Admiral", "Captain Elephant",
    "Beautiful Pirate", "Longma", "Soul Reaper", "Cake Queen",
    "Cake Prince", "Dough King", "rip_indra", "rip_indra True Form",
}) do
    patrolBossNames[name:lower():gsub("[^%w]", "")] = true
end
-- User-excluded Sea 2 camps. Filter both seed routes and live spawn markers
-- before merging, so marker refresh cannot reintroduce Kingdom of Rose stops.
local kingdomOfRoseCamps = {
    raider = true, mercenary = true, swanpirate = true, factorystaff = true,
    kingdomofrose = true,
}
local function addPatrolPoint(name, position, source)
    -- Boss respawn timers are not farm camps. Filter before stripping [Boss]
    -- or merging nearby markers, so they never add a stop to the patrol route.
    local spawnName = string.lower(tostring(name or ""))
    local bareName = spawnName:gsub("%b[]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    local bossKey = bareName:gsub("magnetized", ""):gsub("[^%w]", "")
    -- Factory Core markers may have no [Boss] suffix. Never add/merge this stop.
    if bossKey == "core" or bossKey == "factorycore" then return false end
    if sea == 2 and kingdomOfRoseCamps[bossKey] then return false end
    if spawnName:find("%f[%a]boss%f[%A]") or patrolBossNames[bossKey]
        or bossKey:match("^ripindra") then
        return false
    end
    if typeof(position) ~= "Vector3" then return false end
    for _, coordinate in ipairs({position.X, position.Y, position.Z}) do
        if coordinate ~= coordinate or math.abs(coordinate) == math.huge then return false end
    end    -- Strip level/event suffixes so every Mercenary spawn belongs to its camp.
    local mobKey = string.lower(tostring(name)):gsub("%b[]", "")
        :gsub("magnetized", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if islandMode then
        name = sea1Islands[name] or islandAt(position) or ("Khu spawn " .. short(name, 30)
            .. " @" .. math.floor(position.X) .. "," .. math.floor(position.Z))
    end
    local nearest, nearestDistance
    for _, point in ipairs(patrol.points) do
        if islandMode and point.name == name then return false end
        local distance = (point.position - position).Magnitude
        if islandMode and distance < 35 then return false end
        if not islandMode then
            local radius = point.mobKeys[mobKey] and config.CampMergeRadius or config.CampNearbyRadius
            if distance <= radius and math.abs(point.position.Y - position.Y) <= config.CampHeightTolerance
                and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = point, distance
            end
        end
    end
    local memberKey = string.format("%.0f:%.0f:%.0f", position.X, position.Y, position.Z)
    if nearest then
        if not nearest.members[memberKey] then
            nearest.members[memberKey] = true
            nearest.spawnCount = nearest.spawnCount + 1
            nearest.radius = math.max(nearest.radius, nearestDistance + config.SpawnRadius)
        end
        nearest.mobKeys[mobKey] = true
        -- Keep the visit anchor and visited flag stable during marker refresh.
        return false
    end
    table.insert(patrol.points, { name = short(name, 80), position = position,
        source = source, visited = 0, retryAt = 0, radius = config.SpawnRadius,
        mobKeys = { [mobKey] = true }, members = { [memberKey] = true }, spawnCount = 1 })
    return true
end
function api.AddPatrolPoint(name, position)
    if not alive then return false end
    return addPatrolPoint(name, position, "manual")
end
function api.GetPatrol()
    local points, visited = {}, 0
    for _, point in ipairs(patrol.points) do
        if point.visited == patrol.pass then visited = visited + 1 end
        table.insert(points, { name = point.name, position = point.position,
            spawnCount = point.spawnCount, radius = point.radius,
            source = point.source, visited = point.visited == patrol.pass, retryAt = point.retryAt })
    end
    return { pass = patrol.pass, visited = visited, total = #points, points = points,
        current = patrol.current and patrol.current.name or nil,
        mode = islandMode and "island" or "camp" }
end
function api.GetState()
    local owned, blocked, waiting = getStoreSummary()
    return {
        alive = alive, enabled = enabled, sea = sea, action = action.kind,
        eventActive = eventWindow.active, eventRemaining = eventWindow.remaining,
        hopBlocked = hop.blocked == true,
        status = status, magnetized = #targets, worldFruits = #api.GetFruits(),
        ownedFruits = #owned, blockedFruits = blocked, waitingStore = waiting,
        portal = portal.lastResult, portalDestination = portal.destination,
        hopChecked = hop.checked, hopBusy = hop.busy, hopStatus = hop.status,
        playerCount = #Players:GetPlayers(), session = sessionSerial,
        randomStatus = randomToken.status,
        randomToken = randomToken.tokenNow,
        randomCooldown = randomToken.cooldownLeft,
    }
end
for _, row in ipairs(seedRoutes[sea] or {}) do addPatrolPoint(row[1], row[2], "local database") end
local function refreshSpawnPoints()
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local folder = origin and origin:FindFirstChild("EnemySpawns")
    if not folder then return end
    for _, instance in ipairs(folder:GetDescendants()) do
        -- A Model marker contributes its pivot once, not every decorative part.
        local ancestor, nested = instance.Parent, false
        while ancestor and ancestor ~= folder do
            if ancestor:IsA("Model") then nested = true; break end
            ancestor = ancestor.Parent
        end
        if not nested and instance:IsA("BasePart") then
            addPatrolPoint(instance.Name, instance.Position, "EnemySpawns")
        elseif not nested and instance:IsA("Model") and instance:FindFirstChildWhichIsA("BasePart", true) then
            addPatrolPoint(instance.Name, instance:GetPivot().Position, "EnemySpawns")
        end
    end
end
refreshSpawnPoints()
local function finishPatrolPoint(reason, failed)
    local point = patrol.current
    if point then
        point.visited = patrol.pass
        if failed then point.retryAt = os.clock() + config.RetryDelay end
        log("PATROL", point.name .. ": " .. reason)
    end
    patrol.current, patrol.arrived, patrol.started = nil, nil, nil
    patrol.seenAt = nil
    patrol.best = math.huge
    releaseMovement()
end
local function patrolStep(root, humanoid, dt, now)
    if not config.Patrol then
        releaseMovement(); status = "Cho quai Magnetized; tuan tra dang tat"; return
    end
    if not patrol.current then
        local nearest, remaining = math.huge, false
        for _, point in ipairs(patrol.points) do
            if point.visited ~= patrol.pass then
                remaining = true
                local distance = (point.position - root.Position).Magnitude
                if point.retryAt <= now and distance < nearest then
                    patrol.current, nearest = point, distance
                end
            end
        end
        if not patrol.current then
            releaseMovement()
            if #patrol.points == 0 then
                status = "Chua co diem spawn; cho EnemySpawns hoac AddPatrolPoint"
            elseif not remaining then
                local mythical, fruitName = hasMythicalFruit()
                if mythical then
                    status = "Xong vong; chan hop: Mythical " .. tostring(fruitName)
                elseif hop.blocked then
                    status = hop.status
                elseif now >= hop.retryAt then
                    startHop()
                    status = hop.status
                else
                    status = "Xong vong; cho thu hop " .. math.ceil(hop.retryAt - now) .. "s"
                end
            else
                status = "Cho cooldown cac bai bi ket..."
            end
            return
        end
        log("PATROL", "Den " .. patrol.current.name .. " | vong " .. patrol.pass)
    end
    local point = patrol.current
    local destination = point.position + Vector3.new(0, config.PatrolHeight, 0)
    local distance = (destination - root.Position).Magnitude
    if not patrol.started then
        patrol.started, patrol.progress, patrol.best = now, now, distance
        patrol.deadline = now + math.max(45, distance / config.Speed * 3 + 30)
    end
    if distance <= config.PatrolArrival then
        if not patrol.arrived then patrol.arrived = now end
        local elapsed = now - patrol.arrived
        local seenNPC = false
        for model in pairs(mobs) do
            local h, r = livingNPC(model)
            if h and (r.Position - point.position).Magnitude <= (point.radius or config.SpawnRadius)
                and math.abs(r.Position.Y - point.position.Y) <= config.CampHeightTolerance then
                seenNPC = true; break
            end
        end
        status = "Quan sat bai " .. point.name .. " (" .. point.spawnCount .. " diem spawn) | " .. math.floor(elapsed)
            .. "s | " .. (seenNPC and "co quai" or "cho spawn")
        if seenNPC then patrol.seenAt = patrol.seenAt or now else patrol.seenAt = nil end
        local settleTime = islandMode and config.SpawnSettleTime or config.CampSettleTime
        local settled = patrol.seenAt and now - patrol.seenAt >= settleTime
        local waitTime = islandMode and config.IslandWait or config.CampSettleTime
        local timeout = islandMode and config.IslandSpawnTimeout or config.SpawnTimeout
        if elapsed >= timeout or (settled and elapsed >= waitTime) then
            local reason = islandMode and "khong con Magnetized hop le; bo qua dao trong vong nay"
                or (seenNPC and "da quan sat; sang bai tiep" or "het cho spawn; thu lai vong sau")
            finishPatrolPoint(reason)
            return
        end
        patrol.progress, patrol.best = now, distance
    else
        patrol.arrived = nil -- Server correction does not count as waiting at camp.
        patrol.seenAt = nil
        if distance < patrol.best - 2 then patrol.best, patrol.progress = distance, now end
        if now - patrol.progress > config.NoProgressTimeout or now > patrol.deadline then
            finishPatrolPoint("khong den duoc; tam bo qua", true); return
        end
        status = "Tuan tra " .. point.name .. " | " .. math.ceil(distance) .. " studs"
    end
    if distance > config.PatrolArrival and tryStartPortal(point.position, root, humanoid) then
        status = "Portal den gan " .. point.name
        return
    end
    flyTo(root, humanoid, destination, dt)
end

-- Same Melee/Fighting Style recognition as auto_factory; never substitute a Sword/Fruit.
local equipState = { character = nil, tool = nil, readyAt = 0, retryAt = 0 }
local function equip(character, humanoid)
    local now = os.clock()
    if equipState.character ~= character then
        equipState.character, equipState.tool = character, nil
        equipState.readyAt, equipState.retryAt = 0, 0
    end
    if character ~= player.Character or not humanoid or humanoid.Parent ~= character
        or humanoid.Health <= 0 then return nil, "Character chua san sang" end
    local function normalize(value)
        return tostring(value or ""):lower():match("^%s*(.-)%s*$")
    end
    local wanted = normalize(config.Weapon)
    local function matches(tool)
        if not tool:IsA("Tool") then return false end
        local tooltip = normalize(tool.ToolTip)
        if wanted == "melee" or wanted == "fighting style" then
            return tooltip == "melee" or tooltip == "fighting style"
        end
        return tooltip == wanted or normalize(tool.Name) == wanted
    end
    for _, tool in ipairs(character:GetChildren()) do
        if matches(tool) then
            if equipState.tool ~= tool then
                equipState.tool, equipState.readyAt = tool, now + 0.25
            end
            if now < equipState.readyAt then return nil, "Cho equip: " .. tool.Name end
            return tool
        end
    end
    -- Losing the equipped tool (Portal, pickup, respawn) requires a new settle window.
    equipState.tool = nil
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if matches(tool) then
                if now < equipState.retryAt then return nil, "Dang equip: " .. tool.Name end
                equipState.retryAt = now + 0.75
                local ok = pcall(function() humanoid:EquipTool(tool) end)
                if not ok then return nil, "Equip that bai: " .. tool.Name end
                if tool.Parent == character then
                    equipState.tool, equipState.readyAt = tool, now + 0.25
                end
                -- Do not send an attack in the same tick as EquipTool.
                return nil, "Cho equip: " .. tool.Name
            end
        end
    end
    return nil, "Khong tim thay vu khi: " .. tostring(config.Weapon)
end
-- Resolver adapted from auto_factory.lua ResolveCombatRemotes/TrySourceMeleeAttack.
-- Module require may yield: resolve in one background task, never the Heartbeat.
local combatRemote = { register = nil, hit = nil, resolving = false, retryAt = 0,
    status = "Cho combat remotes" }
local function resolveCombatRemotes()
    if combatRemote.register and combatRemote.register.Parent
        and combatRemote.hit and combatRemote.hit.Parent then return true end
    if combatRemote.resolving or os.clock() < combatRemote.retryAt then return false end
    local modules = RS:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    local register = net and net:FindFirstChild("RE/RegisterAttack")
    local hit = net and net:FindFirstChild("RE/RegisterHit")
    combatRemote.retryAt = os.clock() + 2
    if register and register:IsA("RemoteEvent") and hit and hit:IsA("RemoteEvent") then
        combatRemote.register, combatRemote.hit = register, hit
        return true
    end
    if not register or not net or not net:IsA("ModuleScript") then
        combatRemote.status = "Thieu Modules.Net/RegisterAttack"
        return false
    end
    combatRemote.resolving, combatRemote.status = true, "Dang lay RegisterHit qua Modules.Net"
    task.spawn(function()
        local ok, result = pcall(function()
            local netApi = require(net)
            return netApi:RemoteEvent("RegisterHit", true)
        end)
        if not alive or sessionSerial ~= env.__EventMagnetSessionSerial then return end
        combatRemote.resolving = false
        if ok and typeof(result) == "Instance" and result:IsA("RemoteEvent") then
            combatRemote.register, combatRemote.hit = register, result
            combatRemote.status = "Attack No Animation"
        else
            combatRemote.status = "Khong lay duoc RegisterHit"
            log("COMBAT", combatRemote.status .. ": " .. short(result, 80))
        end
    end)
    return false
end
local function attack(mobRoot, tool)
    local character = player.Character
    if not character or not tool or tool.Parent ~= character then
        return false, "Vu khi chua duoc equip"
    end
    if not mobRoot or not mobRoot.Parent then return false, "Muc tieu da bien mat" end
    if not config.AttackNoAnimation then
        local ok, err = pcall(function() tool:Activate() end)
        return ok, ok and "Tool attack" or short(err, 80)
    end
    if not resolveCombatRemotes() then return false, combatRemote.status end
    local ok, err = pcall(function()
        combatRemote.register:FireServer(0)
        combatRemote.hit:FireServer(mobRoot, {})
    end)
    if not ok then
        combatRemote.register, combatRemote.hit = nil, nil
        combatRemote.status = "Combat remote loi: " .. short(err, 80)
    end
    return ok, ok and "Attack No Animation" or combatRemote.status
end

local function nearestFruit(root, now)
    local best, distance
    for instance, record in pairs(fruitRecords) do
        if instance:IsDescendantOf(workspace) and record.part and record.part.Parent
            and record.retryAt <= now then
            local candidateDistance = (record.part.Position - root.Position).Magnitude
            if not distance or candidateDistance < distance then
                best, distance = record, candidateDistance
            end
        end
    end
    return best, distance
end
local function failFruit(record, reason)
    record.attempts = record.attempts + 1
    if record.attempts >= config.FruitPickupAttempts then
        record.retryAt, record.attempts = os.clock() + config.FruitRetryDelay, 0
    end
    log("FRUIT", record.name .. ": " .. reason)
    fruitTask.target, fruitTask.started = nil, nil
    releaseMovement()
end
local function startFruitPickup(record, root, humanoid)
    local token = beginAction("pickup")
    if not token then return false end
    releaseMovement()
    task.spawn(function()
        local snapshot = {}
        for _, item in ipairs(ownedFruitTools()) do snapshot[item] = true end
        local oldCanTouch = {}
        local found, touched, aborted = nil, false, false
        local ok, runtimeError = xpcall(function()
            if not actionIsCurrent("pickup", token) or hasLiveMagnetized() then
                aborted = true; return
            end
            local character = player.Character
            if not character or not humanoid.Parent or not root.Parent then error("Character da thay doi") end
            pcall(function()
                humanoid:UnequipTools()
                humanoid.Sit, humanoid.PlatformStand = false, false
            end)
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    oldCanTouch[part] = part.CanTouch
                    pcall(function() part.CanTouch = true end)
                end
            end
            local handle = record.part
            touched = pcall(function()
                root.CFrame = handle.CFrame
                root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
                if type(firetouchinterest) == "function" then
                    firetouchinterest(root, handle, 0); task.wait(0.03); firetouchinterest(root, handle, 1)
                    local right = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")
                    local left = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")
                    for _, foot in pairs({ right, left }) do
                        if foot then firetouchinterest(foot, handle, 0); task.wait(0.02); firetouchinterest(foot, handle, 1) end
                    end
                end
                humanoid.Jump = true
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.04)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
            if not touched then return end
            local deadline = os.clock() + config.FruitPickupConfirm
            while actionIsCurrent("pickup", token) and os.clock() < deadline do
                for _, item in ipairs(ownedFruitTools()) do
                    if not snapshot[item] and ownedFruitMatches(record, item) then found = item; break end
                end
                if found then break end
                task.wait(0.1)
            end
        end, function(err) return tostring(err) end)
        pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        for part, oldValue in pairs(oldCanTouch) do
            if part.Parent then pcall(function() part.CanTouch = oldValue end) end
        end
        if not actionIsCurrent("pickup", token) then return end
        endAction("pickup", token)
        if aborted then return end
        if not ok then
            failFruit(record, "Loi pickup: " .. short(runtimeError, 80))
        elseif not touched then
            failFruit(record, "Khong kich hoat duoc touch")
        elseif found then
            log("FRUIT", "Da xac nhan nhat: " .. short(found.Name, 80))
            sendFruitWebhook("Picked", found.Name, found, getFruitOriginalName(found))
            fruitTask.target, fruitTask.started = nil, nil
        else
            failFruit(record, "Da cham nhung chua vao inventory")
        end
    end)
    return true
end
local function fruitStep(root, humanoid, dt, now)
    if not config.FruitEnabled then return false end
    local record = fruitTask.target and fruitRecords[fruitTask.target]
    if not record or not record.instance:IsDescendantOf(workspace)
        or not record.part or not record.part.Parent then
        record = nearestFruit(root, now)
        fruitTask.target = record and record.instance or nil
        fruitTask.started, fruitTask.progress, fruitTask.best = now, now, math.huge
    end
    if not record then return false end
    local distance = (record.part.Position - root.Position).Magnitude
    if distance < fruitTask.best - 2 then
        fruitTask.best, fruitTask.progress = distance, now
    elseif now - fruitTask.progress > config.NoProgressTimeout then
        failFruit(record, "Di chuyen khong tien trien")
        return true
    end
    if distance <= config.FruitPickupDistance then
        status = "Dang nhat " .. short(record.name, 60)
        startFruitPickup(record, root, humanoid)
        return true
    end
    if tryStartPortal(record.part.Position, root, humanoid) then
        status = "Portal den Fruit " .. short(record.name, 50)
        return true
    end
    status = "Den Fruit " .. short(record.name, 55) .. " | " .. math.ceil(distance) .. " studs"
    flyTo(root, humanoid, record.part.Position + Vector3.new(0, 2, 0), dt)
    return true
end

-- [FIX 3] Random Token: tự dò cooldown + token qua Check, không phụ thuộc event window.
-- State: idle -> check -> (chờ token / chờ cooldown / đủ điều kiện) -> Purchase -> check lại
local function randomTokenStep()
    if not alive or not enabled or not config.AutoRandomToken then return end
    if randomToken.locked or randomToken.busy or action.kind then return end

    local now = os.clock()
    if now < randomToken.nextCheck then return end

    local character = player.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or not currentTeamName()
        or not character:FindFirstChild("HasBuso") then return end

    -- Nhường việc ưu tiên cao hơn (store đang chờ)
    local owned, blocked = getStoreSummary()
    if #owned > blocked then return end

    local modules = RS:FindFirstChild("Modules")
    local net = modules and modules:FindFirstChild("Net")
    local rf = net and net:FindFirstChild("RF/GachaNetworkRF")
    if not rf or not rf:IsA("RemoteFunction") then
        randomToken.nextCheck = now + 5
        randomToken.status = "Chua tim thay GachaNetworkRF"
        return
    end

    randomToken.busy = true
    randomToken.serial = randomToken.serial + 1
    local serial = randomToken.serial
    local function current()
        return alive and env.EventMagnetFarm == api and randomToken.serial == serial
    end
    -- Timeout an toàn: nếu request treo quá 20s thì mở khoá
    task.delay(20, function()
        if current() and randomToken.busy then
            randomToken.locked, randomToken.status = true, "Timeout: khoa random, cho ket qua"
        end
    end)

    task.spawn(function()
        local dispatched = false
        local ok, err = pcall(function()
            -- ===== BƯỚC 1: CHECK =====
            local a, b = rf:InvokeServer({Context = "Check", BoxName = "MagnetEventGacha26"})
            if not current() then return end
            local req = type(b) == "table" and b or (type(a) == "table" and a)
            local price = req and req.Price
            if not req or type(req.RequirementsMet) ~= "boolean" or type(price) ~= "table"
                or tonumber(price.ItemId) ~= 1574 or tonumber(price.Value) ~= 500
                or type(price.Current) ~= "number" then
                randomToken.locked, randomToken.status = true, "Du lieu/gia thay doi: dung random"
                return
            end

            randomToken.tokenNow = tonumber(price.Current) or 0
            randomToken.tokenNeed = tonumber(price.Value) or 500
            randomToken.requirementMet = req.RequirementsMet == true

            -- ===== BƯỚC 2: ĐỌC COOLDOWN =====
            local cooldown = req.Cooldown
            local cdLeft = 0
            local cooldownBlocked = false
            if type(cooldown) == "table" then
                cdLeft = tonumber(cooldown.TimeLeft) or tonumber(cooldown.Remaining)
                    or tonumber(cooldown.Duration) or 0
                if type(cooldown.RequirementMet) == "boolean"
                    and cooldown.RequirementMet == false and cdLeft <= 0 then
                    cdLeft = config.RandomFallbackCooldown
                    cooldownBlocked = true
                end
            end
            randomToken.cooldownLeft = math.max(cdLeft, 0)

            -- ===== BƯỚC 3: QUYẾT ĐỊNH =====
            local tokenReady = randomToken.tokenNow >= randomToken.tokenNeed
            local cooldownReady = randomToken.cooldownLeft <= 0 and not cooldownBlocked

            if not tokenReady then
                randomToken.nextCheck = os.clock() + config.RandomCheckIdle
                randomToken.status = string.format("Token %d/%d (cho %ds)",
                    randomToken.tokenNow, randomToken.tokenNeed, config.RandomCheckIdle)
                return
            end
            if not randomToken.requirementMet then
                randomToken.nextCheck = os.clock() + 10
                randomToken.status = "Chua du dieu kien event"
                return
            end
            if not cooldownReady then
                local wait = math.max(randomToken.cooldownLeft, 1) + config.RandomCheckCooldown
                randomToken.nextCheck = os.clock() + wait
                randomToken.status = string.format("Cooldown %ds (token %d/%d)",
                    math.ceil(randomToken.cooldownLeft),
                    randomToken.tokenNow, randomToken.tokenNeed)
                return
            end

            -- ===== BƯỚC 4: PURCHASE =====
            if not current() or not enabled or randomToken.locked then return end
            if player.Character ~= character or hum.Health <= 0 then return end
            if not character:FindFirstChild("HasBuso") then return end

            local before = {}
            for _, item in ipairs(ownedFruitTools()) do before[item] = true end

            dispatched = true
            randomToken.status = "Quay 500 Magnet Token"
            local accepted = rf:InvokeServer({Context = "Purchase", BoxName = "MagnetEventGacha26"})
            if not current() then return end

            if accepted == false then
                randomToken.nextCheck = os.clock() + 5
                randomToken.status = "Server tu choi; Check lai sau 5s"
                return
            elseif accepted ~= true then
                randomToken.locked, randomToken.status = true, "Purchase chua ro; dung random"
                return
            end

            -- Chờ Tool mới xuất hiện
            local rewards = {}
            local rewardDeadline = os.clock() + 8
            repeat
                task.wait(0.1)
                if not current() then return end
                rewards = {}
                for _, item in ipairs(ownedFruitTools()) do
                    if not before[item] then rewards[#rewards + 1] = item.Name end
                end
            until #rewards > 0 or os.clock() >= rewardDeadline

            randomToken.status = #rewards > 0 and ("Nhan " .. table.concat(rewards, ", "))
                or "Server chap nhan; chua thay Fruit"
            log("RANDOM", randomToken.status)
            for _, item in ipairs(ownedFruitTools()) do
                if not before[item] then
                    sendFruitWebhook("Random", item.Name, item, getFruitOriginalName(item))
                end
            end

            -- ===== BƯỚC 5: ĐỌC LẠI COOLDOWN MỚI =====
            task.wait(1)
            if not current() then return end
            local ok2, a2, b2 = pcall(function()
                return rf:InvokeServer({Context = "Check", BoxName = "MagnetEventGacha26"})
            end)
            if ok2 and current() then
                local req2 = type(b2) == "table" and b2 or (type(a2) == "table" and a2)
                if req2 and type(req2.Cooldown) == "table" then
                    local cd2 = tonumber(req2.Cooldown.TimeLeft)
                        or tonumber(req2.Cooldown.Remaining)
                        or tonumber(req2.Cooldown.Duration) or 0
                    randomToken.cooldownLeft = math.max(cd2, 0)
                else
                    randomToken.cooldownLeft = config.RandomFallbackCooldown
                end
                randomToken.tokenNow = req2 and req2.Price
                    and tonumber(req2.Price.Current) or 0
                randomToken.nextCheck = os.clock()
                    + math.max(randomToken.cooldownLeft, 1) + config.RandomCheckCooldown
                randomToken.status = string.format("Cooldown moi %ds; token %d/%d",
                    math.ceil(randomToken.cooldownLeft),
                    randomToken.tokenNow, randomToken.tokenNeed)
            else
                randomToken.nextCheck = os.clock() + 30
                randomToken.status = "Da quay; cho check lai cooldown"
            end
        end)

        if not current() then return end
        if not ok then
            log("RANDOM", "Loi: " .. short(err, 120))
            randomToken.nextCheck = os.clock() + 15
            randomToken.status = "Loi Check; thu lai sau 15s"
        end
        randomToken.busy = false
    end)
end
-- Adapted from giayeuem.lua SourceBringMob: same radius/count/throttle and
-- other-player guard, but only living Magnetized NPCs are eligible.
local bringState = { at = 0, parts = setmetatable({}, { __mode = "k" }) }
local function restoreBring()
    for part, original in pairs(bringState.parts) do
        if part.Parent then pcall(function() part.CanCollide = original end) end
    end
    bringState.parts = setmetatable({}, { __mode = "k" })
end
local function bringEventMobs(root, mobRoot, now)
    if not config.BringMobs or now - bringState.at < config.BringMobInterval then return end
    bringState.at = now
    restoreBring()
    if (root.Position - mobRoot.Position).Magnitude > config.BringActivationRange then return end
    local function otherPlayerNear(position)
        for _, other in ipairs(Players:GetPlayers()) do
            local otherRoot = other ~= player and rootOf(other.Character)
            if otherRoot and (otherRoot.Position - position).Magnitude <= config.BringPlayerSafeRange then
                return true
            end
        end
        return false
    end
    if otherPlayerNear(mobRoot.Position) then return end
    local count = 0
    for _, model in ipairs(targets) do
        if count >= math.max(math.floor(config.BringMobCount) - 1, 0) then break end
        local h, r = livingNPC(model)
        if model ~= target and h and isMagnetized(model, h) and not model:FindFirstChild("Ignored")
            and (skipped[model] or 0) <= now
            and (r.Position - mobRoot.Position).Magnitude <= config.BringMobRadius
            and not otherPlayerNear(r.Position) then
            local owned = true
            if type(isnetworkowner) == "function" then
                local ok, result = pcall(isnetworkowner, r)
                owned = ok and result == true
            end
            if owned then
                pcall(function()
                    for _, part in ipairs(model:GetDescendants()) do
                        if part:IsA("BasePart") then
                            bringState.parts[part] = part.CanCollide
                            part.CanCollide = false
                        end
                    end
                    r.AssemblyLinearVelocity, r.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
                    r.CFrame = mobRoot.CFrame * CFrame.new(0, math.random(0, 2), math.random(0, 2))
                end)
                count = count + 1
            end
        end
    end
end
local seatGuard = { humanoid = nil, original = nil }
local function restoreSeatGuard()
    if seatGuard.humanoid and seatGuard.humanoid.Parent then
        pcall(function()
            seatGuard.humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, seatGuard.original)
        end)
    end
    seatGuard.humanoid, seatGuard.original = nil, nil
end
local function needsMovement()
    if not alive or not enabled then return false end
    local character = player.Character
    local root = rootOf(character)
    if not root or not character:FindFirstChild("HasBuso") or not teamSelect.ready then return false end
    if action.kind == "hop" then return false end
    if action.kind == "portal" or action.kind == "pickup" then return true end
    if hasLiveMagnetized() then return true end
    if action.kind == "store" then return false end
    if config.Patrol and (not config.EventScheduleEnabled or eventWindow.active) and #patrol.points > 0 then return true end
    if config.FruitEnabled and not eventWindow.active then
        local owned, blocked = getStoreSummary()
        return #owned == blocked and nearestFruit(root, os.clock()) ~= nil
    end
    return false
end
local function updateSeatGuard()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local moving = needsMovement()
    if seatGuard.humanoid ~= humanoid or not moving then restoreSeatGuard() end
    if not moving or not humanoid or humanoid.Health <= 0 then return end
    if not seatGuard.humanoid then
        seatGuard.original = humanoid:GetStateEnabled(Enum.HumanoidStateType.Seated)
        seatGuard.humanoid = humanoid
    end
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
end
local seatRecovery = { root = nil, nextAttempt = 0, pending = false }
local function recoverFromSeat(root, humanoid, now)
    if seatRecovery.root ~= root then
        seatRecovery.root, seatRecovery.nextAttempt, seatRecovery.pending = root, 0, false
        seatRecovery.started, seatRecovery.clearSince = nil, nil
    end
    if not needsMovement() then
        restoreSeatGuard()
        seatRecovery.pending, seatRecovery.started, seatRecovery.clearSince = false, nil, nil
        return false
    end
    if humanoid.Sit or humanoid.SeatPart then
        releaseMovement()
        seatRecovery.pending = true
        seatRecovery.started = seatRecovery.started or now
        seatRecovery.clearSince = nil
        status = "Dang tu roi ghe de tiep tuc farm"
        if now - seatRecovery.started >= 6 then
            api.SetEnabled(false)
            restoreSeatGuard()
            status = "Ghe chua nha sau 6s; hay nhay roi ghe va bat lai farm"
            log("SEAT", status)
            seatRecovery.started = nil
            return true
        end
        if now >= seatRecovery.nextAttempt then
            seatRecovery.nextAttempt = now + 0.5
            humanoid.PlatformStand = false
            humanoid.Sit = false
            humanoid.Jump = true
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        return true
    end
    if seatRecovery.pending then
        seatRecovery.clearSince = seatRecovery.clearSince or now
        if now - seatRecovery.clearSince < 0.2 then return true end
        -- Chỉ nâng nhân vật sau khi SeatPart đã nhả để không kéo theo ghế/thuyền.
        seatRecovery.pending = false
        seatRecovery.started, seatRecovery.clearSince = nil, nil
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.CFrame = root.CFrame + Vector3.new(0, 12, 0)
        patrol.started, patrol.arrived, patrol.seenAt = nil, nil, nil
        patrol.progress, patrol.best = now, math.huge
        lastProgress, lastDamage, bestDistance = now, now, math.huge
        fruitTask.progress, fruitTask.best = now, math.huge
        status = "Da roi ghe; tiep tuc farm"
        log("FARM", status)
    end
    return false
end
-- Match the fought mob to its actual camp, not the interrupted patrol stop.
local function combatCampAt(position)
    local best, distance
    for _, point in ipairs(patrol.points) do
        local delta = (point.position - position).Magnitude
        if delta <= point.radius and math.abs(point.position.Y - position.Y) <= config.CampHeightTolerance
            and (not distance or delta < distance) then best, distance = point, delta end
    end
    return best
end
local function finishClearedCombatCamp()
    local point, humanoid = patrol.combatCamp, patrol.combatHumanoid
    -- Disappearance/timeout is not proof of a kill.
    if not point or not humanoid or humanoid.Health > 0 then return end
    for model in pairs(mobs) do
        local h, r = livingNPC(model)
        if h and isMagnetized(model, h)
            and (r.Position - point.position).Magnitude <= point.radius
            and math.abs(r.Position.Y - point.position.Y) <= config.CampHeightTolerance then return end
    end
    point.visited, point.retryAt = patrol.pass, 0
    if patrol.current == point then
        patrol.current, patrol.arrived, patrol.started, patrol.seenAt = nil, nil, nil, nil
    end
    log("PATROL", "Da danh het Magnetized dang hien dien: bo qua bai " .. point.name .. " trong vong nay")
end
local function farmStep(dt)
    if not enabled then return end
    -- [FIX 4] Nhường random token nếu đang trong lúc Purchase
    if randomToken.busy and randomToken.status == "Quay 500 Magnet Token" then return end
    if not eventStillOpen() then
        if target then resetTarget("het event; chuyen sang Fruit") end
        restoreBring()
        if action.kind == "hop" and not hop.startup and not hop.dispatched then cancelAction("het event; dung tim server") end
        if action.kind == "portal" and (portal.forCombat or not fruitTask.target) then
            cancelAction("het event; chuyen sang Fruit")
        end
    end
    local now = os.clock()
    if not teamSelectionStep(now) then
        releaseMovement()
        status = teamSelect.lastResult
        return
    end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = rootOf(character)
    if not humanoid or humanoid.Health <= 0 or not root then
        resetTarget(); status = "Cho respawn..."; return
    end
    if not character:FindFirstChild("HasBuso") then
        releaseMovement()
        if action.kind and not hop.dispatched then cancelAction("cho Haki bat buoc") end
        status = "Cho bat Haki Buso bat buoc; chua xac nhan HasBuso"
        return
    end
    hop.readyAt = hop.readyAt or (now + config.StartupDelay)
    if recoverFromSeat(root, humanoid, now) then return end
    if not hop.checked and not hop.blocked and not action.kind then
        if now < hop.readyAt then
            releaseMovement()
            status = "Cho kiem tra server dau phien " .. math.ceil(hop.readyAt - now) .. "s"
            return
        elseif #Players:GetPlayers() <= config.CurrentPlayerLimit then
            hop.checked, hop.status = true, "Server trong gioi han " .. config.CurrentPlayerLimit .. " nguoi"
        elseif hasMythicalFruit() then
            hop.status = "Chan hop dau phien: con Mythical chua luu"
            -- Continue into storage/farming while retaining the startup check.
        elseif now >= hop.retryAt then
            startHop(true)
            status = hop.status
            return
        end
    end

    if config.EventScheduleEnabled and not eventWindow.active and action.kind == "portal"
        and not portal.forCombat and not fruitTask.target then
        cancelAction("het gio event; dung Portal tuan tra")
    end
    if hasLiveMagnetized() and action.kind and not hop.dispatched
        and not (action.kind == "hop" and hop.startup)
        and not (action.kind == "portal" and portal.forCombat) then
        cancelAction("nhuong Magnetized")
    end
    if action.kind then
        status = action.kind == "portal" and ("Dang mo Portal: " .. tostring(portal.destination))
            or action.kind == "hop" and hop.status
            or action.kind == "store" and "Dang xac nhan luu Fruit"
            or "Dang xac nhan nhat Fruit"
        return
    end
    local mobHumanoid, mobRoot = livingNPC(target)
    if target and (not mobHumanoid or not isMagnetized(target, mobHumanoid)) then
        finishClearedCombatCamp()
        resetTarget("chet / mat muc tieu / het Magnetized (khong xac nhan reward)")
        mobHumanoid, mobRoot = nil, nil
    end
    if not target then
        -- Sea 1 remains island-scoped. Sea 2/3 may acquire any replicated
        -- Magnetized target and always preempt every lower-priority task.
        local nearest = math.huge
        if eventWindow.active and (not islandMode or patrol.current) then
            for _, model in ipairs(targets) do
                local h, r = livingNPC(model)
                local onCurrentIsland = not islandMode or (r and patrol.current
                    and islandAt(r.Position) == patrol.current.name)
                if h and onCurrentIsland and isMagnetized(model, h) and (skipped[model] or 0) <= now then
                    local distance = (r.Position - root.Position).Magnitude
                    if distance < nearest then target, nearest = model, distance end
                end
            end
        end
        if not target then
            local owned, blocked, waiting = getStoreSummary()
            if #owned > 0 and config.StoreFruit then
                for _, item in ipairs(owned) do
                    if startStore(item, false) then
                        status = "Dang luu " .. short(item.Name, 60)
                        return
                    end
                end
            end


            -- Rejected Tools stay in the bag but must not block the next pickup.
            -- A new/unresolved Tool still waits for its store attempt. Holding a
            -- rejected Tool also prevents hop, so allow pickup before hop.checked.
            local pendingStore = #owned - blocked
            if pendingStore == 0 and (hop.checked or hop.blocked or blocked > 0)
                and not eventWindow.active and fruitStep(root, humanoid, dt, now) then return end
            if config.EventScheduleEnabled and not eventWindow.active then
                releaseMovement()
                status = "Ngoai event: cho Fruit | event sau " .. math.ceil(eventWindow.remaining) .. "s"
                return
            end
            patrolStep(root, humanoid, dt, now)
            return
        end
        patrol.arrived, patrol.started, patrol.best = nil, nil, math.huge
        patrol.seenAt = nil
        mobHumanoid, mobRoot = livingNPC(target)
        patrol.combatCamp, patrol.combatHumanoid = combatCampAt(mobRoot.Position), mobHumanoid
        targetSince, lastDamage, lastProgress = now, now, now
        lastHP, bestDistance, attackSince = mobHumanoid.Health, math.huge, nil
        log("FARM", "Chon " .. target.Name)
    end
    if now - targetSince > config.TargetTimeout then
        resetTarget("timeout; tam bo qua", true); return
    end
    local distance = (mobRoot.Position - root.Position).Magnitude
    if mobHumanoid.Health < lastHP then lastDamage = now end
    lastHP = mobHumanoid.Health
    if distance < bestDistance - 2 then bestDistance, lastProgress = distance, now end
    if distance > config.AttackRange then
        attackSince = nil
        if now - lastProgress > config.NoProgressTimeout then
            resetTarget("di chuyen khong tien trien; tam bo qua", true); return
        end
    else
        lastProgress, bestDistance = now, distance
        if not attackSince then attackSince, lastDamage = now, now end
        if now - lastDamage > config.NoDamageTimeout then
            resetTarget("HP khong giam; kiem tra vu khi/combat/server", true); return
        end
    end
    local destination = mobRoot.Position + Vector3.new(0, config.HoverHeight, 2)
    if distance > config.AttackRange
        and tryStartPortal(mobRoot.Position, root, humanoid, true) then
        status = "Portal den Magnetized " .. short(target.Name, 45)
        return
    end
    flyTo(root, humanoid, destination, dt, mobRoot.Position)
    bringEventMobs(root, mobRoot, now)
    status = "Farm " .. short(target.Name, 65) .. " | HP " .. math.ceil(mobHumanoid.Health)
    attackClock = attackClock + dt
    if distance <= config.AttackRange and attackClock >= config.AttackInterval then
        attackClock = 0
        local tool, equipDetail = equip(character, humanoid)
        if tool then
            local sent, detail = attack(mobRoot, tool)
            if not sent then status = detail end
        else status = equipDetail or "Cho vu khi san sang" end
    end
end

-- Mặt đứng trên nước lấy từ cơ chế đã test; luôn hoạt động trong suốt phiên,
-- kể cả lúc bay, mở Portal hoặc tạm dừng farm. Chỉ Destroy mới dọn platform.
local waterPlatform
local staleWaterPlatform = workspace:FindFirstChild("EventMagnetWaterPlatform")
if staleWaterPlatform and staleWaterPlatform:IsA("BasePart") then
    pcall(function() staleWaterPlatform:Destroy() end)
end
local function updateWaterWalk()
    if waterPlatform then waterPlatform.CanCollide = false end
    if not alive or not config.WaterWalkEnabled then return end
    local character = player.Character
    local root = rootOf(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 or humanoid.Sit then return end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = waterPlatform and { character, waterPlatform } or { character }
    params.IgnoreWater = false
    local hit = workspace:Raycast(
        root.Position + Vector3.new(0, 5, 0),
        Vector3.new(0, -140, 0),
        params
    )
    local surface = config.WaterWalkSurfaceY
    local hitName = hit and string.lower(hit.Instance.Name) or ""
    local nearWaterLevel = root.Position.Y >= surface - 15 and root.Position.Y <= surface + 12.5
    if nearWaterLevel then
        -- Fixed-level support from Auto Factory, even if a mob/prop blocks the ray.
        surface = config.WaterWalkSurfaceY
    elseif hit and (hit.Material == Enum.Material.Water or hitName == "sea"
        or hitName:find("water", 1, true) or hitName:find("ocean", 1, true)) then
        surface = hit.Position.Y
    elseif hit and hit.Position.Y > surface - 8 then
        return
    end
    if root.Position.Y > surface + 70 or root.Position.Y < surface - 15 then return end

    if not waterPlatform then
        waterPlatform = Instance.new("Part")
        waterPlatform.Name = "EventMagnetWaterPlatform"
        waterPlatform.Size = Vector3.new(32, 1, 32)
        waterPlatform.Anchored = true
        waterPlatform.Transparency = 1
        waterPlatform.CanTouch = false
        waterPlatform.CanQuery = false
        waterPlatform.CastShadow = false
        waterPlatform.Parent = workspace
    end
    waterPlatform.CFrame = CFrame.new(root.Position.X, surface - 0.5, root.Position.Z)
    waterPlatform.CanCollide = true
end
connect(RunService.Stepped, function()
    local ok, err = pcall(updateWaterWalk)
    if not ok then
        if waterPlatform then waterPlatform.CanCollide = false end
        if os.clock() - lastError > 5 then
            lastError = os.clock()
            log("WATER", short(err, 100))
        end
    end
end)

-- A separate function avoids combining farm and dashboard locals in Luau.
local function mountDashboard()
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "EventMagnetFarmUI", false, 1000
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local function tryMountGui(parent)
    if not parent then return false end
    local ok = pcall(function()
        local stale = parent:FindFirstChild(gui.Name)
        if stale and stale ~= gui then stale:Destroy() end
        gui.Parent = parent
    end)
    return ok and gui.Parent == parent
end
local mounted = false
if type(gethui) == "function" then
    local ok, hiddenUi = pcall(gethui)
    if ok then mounted = tryMountGui(hiddenUi) end
end
if not mounted then
    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if ok then mounted = tryMountGui(coreGui) end
end
if not mounted then
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
        or player:WaitForChild("PlayerGui", 15)
    mounted = tryMountGui(playerGui)
end
if not mounted then
    gui:Destroy()
    error("Khong the hien EventMagnetFarmUI qua gethui/CoreGui/PlayerGui")
end
local UIS = game:GetService("UserInputService")
local C = {
    bg = Color3.fromRGB(3, 20, 35), card = Color3.fromRGB(4, 28, 47),
    cyan = Color3.fromRGB(0, 218, 255), line = Color3.fromRGB(12, 89, 125),
    text = Color3.fromRGB(228, 243, 255), muted = Color3.fromRGB(142, 188, 224),
    green = Color3.fromRGB(0, 241, 130), yellow = Color3.fromRGB(255, 207, 0),
    red = Color3.fromRGB(225, 15, 62), button = Color3.fromRGB(5, 43, 81),
}
local panel = Instance.new("Frame")
panel.Name, panel.Size = "MagnetDashboard", UDim2.fromOffset(560, 680)
panel.AnchorPoint, panel.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3, panel.BorderSizePixel = C.bg, 0
panel.Active, panel.ClipsDescendants, panel.Parent = true, true, gui
local scale = Instance.new("UIScale")
scale.Parent = panel
local function rounded(parent, radius, color, thickness)
    local corner = Instance.new("UICorner")
    corner.CornerRadius, corner.Parent = UDim.new(0, radius), parent
    if color then
        local outline = Instance.new("UIStroke")
        outline.Color, outline.Thickness, outline.Parent = color, thickness or 1, parent
    end
end
rounded(panel, 16, C.cyan, 2)
local function text(parent, value, x, y, w, h, size, color, bold)
    local label = Instance.new("TextLabel")
    label.Position, label.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
    label.Text, label.TextSize = value, size or 16
    label.TextColor3, label.BackgroundTransparency = color or C.text, 1
    label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    label.TextWrapped, label.TextXAlignment = true, Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end
local function card(parent, x, y, w, h)
    local frame = Instance.new("Frame")
    frame.Position, frame.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
    frame.BackgroundColor3, frame.BorderSizePixel, frame.Parent = C.card, 0, parent
    rounded(frame, 10, C.line, 1)
    return frame
end
local function button(parent, label, x, y, w, h, color)
    local item = Instance.new("TextButton")
    item.Position, item.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
    item.Text, item.Font, item.TextSize = label, Enum.Font.GothamBold, 18
    item.BackgroundColor3, item.TextColor3 = color or C.button, C.text
    item.BorderSizePixel, item.Parent = 0, parent
    rounded(item, 9, C.cyan, 1)
    return item
end
local header = Instance.new("Frame")
header.Name, header.Size, header.BackgroundTransparency = "DragHandle", UDim2.new(1, 0, 0, 54), 1
header.Active, header.Parent = true, panel
local titleLabel = text(header, "MAGNETIZED FARM V2", 20, 9, 370, 34, 24, C.text, true)
local onLabel = text(header, "● ON", 405, 10, 68, 32, 20, C.green, true)
local minimize = button(header, "−", 476, 10, 32, 32)
local topClose = button(header, "×", 516, 10, 32, 32)
local body = Instance.new("Frame")
body.Name, body.Size, body.BackgroundTransparency = "DashboardBody", UDim2.fromScale(1, 1), 1
body.Parent = panel
-- Keep header above the transparent body so drag/minimize/close remain clickable.
header.ZIndex = 3
for _, child in ipairs(header:GetChildren()) do if child:IsA("GuiObject") then child.ZIndex = 4 end end
local refs = {}
text(body, "●  USER", 22, 64, 102, 25, 15, C.muted, true)
text(body, "@" .. player.Name, 128, 62, 406, 29, 19, C.text, true)
local teamCard = card(body, 18, 108, 169, 76)
text(teamCard, "♟ TEAM", 12, 8, 145, 20, 13, C.muted, true)
refs.team = text(teamCard, "-", 12, 31, 145, 34, 20, C.text, true)
local eventCard = card(body, 195, 108, 169, 76)
text(eventCard, "◷ EVENT", 12, 8, 145, 20, 13, C.muted, true)
refs.event = text(eventCard, "-", 12, 31, 145, 34, 16, C.yellow, true)
local campCard = card(body, 372, 108, 170, 76)
text(campCard, "⌖ VÒNG / BÃI", 12, 8, 146, 20, 13, C.muted, true)
refs.camp = text(campCard, "-", 12, 31, 146, 34, 21, C.text, true)
local counts = card(body, 18, 196, 524, 112)
local function counter(label, x, y)
    text(counts, label, x, y, 136, 25, 16, C.muted, false)
    local value = text(counts, "0", x + 138, y, 90, 25, 17, C.text, true)
    value.TextXAlignment = Enum.TextXAlignment.Right
    return value
end
refs.magnet = counter("Magnetized", 14, 10)
refs.owned = counter("Giữ", 14, 43)
refs.auto = counter("Auto token", 14, 76)
refs.events = counter("Event", 280, 10)
refs.fruits = counter("Fruit map", 280, 43)
refs.blocked = counter("Chờ/chặn", 280, 76)
local system = card(body, 18, 320, 524, 112)
text(system, "⚙  HỆ THỐNG", 14, 8, 490, 26, 17, C.muted, true)
text(system, "Portal", 14, 36, 110, 22, 15, C.muted)
refs.portal = text(system, "-", 130, 36, 380, 22, 14)
text(system, "Hop", 14, 60, 110, 22, 15, C.muted)
refs.hop = text(system, "-", 130, 60, 380, 22, 14)
text(system, "Webhook", 14, 84, 110, 22, 15, C.muted)
refs.webhook = text(system, "-", 130, 84, 380, 22, 14)
local stateCard = card(body, 18, 444, 524, 112)
text(stateCard, "⌁  TRẠNG THÁI", 14, 6, 490, 25, 17, C.cyan, true)
local targetLabel = text(stateCard, "Đang khởi động...", 14, 34, 496, 40, 17, C.cyan, true)
refs.random = text(stateCard, "-", 14, 77, 496, 25, 12, C.muted)
local toggle = button(body, "■  DỪNG FARM", 18, 568, 256, 52, C.red)
local close = button(body, "⇥  THOÁT", 286, 568, 256, 52, C.button)
local footer = text(body, "Hoàng Trọng DEV", 18, 637, 524, 27, 20, C.cyan)
footer.TextXAlignment = Enum.TextXAlignment.Center
local collapsed, dragging, dragInput, dragStart, startPosition = false, false, nil, nil, nil
local cameraConnection
local function viewport()
    return workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
end
local function fitPanel()
    local size = viewport()
    if size.X < 40 or size.Y < 40 then return end
    -- Same scale in expanded/collapsed states prevents position jumps on reopening.
    scale.Scale = math.min(1, (size.X - 24) / 560, (size.Y - 24) / 680)
    local half = Vector2.new(560, collapsed and 54 or 680) * scale.Scale / 2
    local x = panel.Position.X.Scale * size.X + panel.Position.X.Offset
    local y = panel.Position.Y.Scale * size.Y + panel.Position.Y.Offset
    panel.Position = UDim2.fromOffset(
        math.clamp(x, half.X + 8, size.X - half.X - 8),
        math.clamp(y, half.Y + 8, size.Y - half.Y - 8))
end
connect(minimize.Activated, function()
    collapsed = not collapsed
    body.Visible = not collapsed
    panel.Size = UDim2.fromOffset(560, collapsed and 54 or 680)
    minimize.Text = collapsed and "+" or "−"
    titleLabel.Text = collapsed and ("MAGNETIZED FARM V2 | @" .. player.Name) or "MAGNETIZED FARM V2"
    titleLabel.TextSize = collapsed and 15 or 24
    fitPanel()
end)
local function bindCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then cameraConnection = connect(camera:GetPropertyChangedSignal("ViewportSize"), fitPanel) end
    fitPanel()
end
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)
bindCamera()
connect(header.InputBegan, function(input)
    local kind = input.UserInputType
    if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
    if input.Position.X >= minimize.AbsolutePosition.X then return end
    dragging, dragInput, dragStart, startPosition = true, input, input.Position, panel.Position
end)
connect(UIS.InputChanged, function(input)
    if not dragging or not dragStart then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragInput then return end
    local delta = input.Position - dragStart
    panel.Position = UDim2.fromOffset(startPosition.X.Offset + delta.X, startPosition.Y.Offset + delta.Y)
    fitPanel()
end)
connect(UIS.InputEnded, function(input)
    if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, dragInput, dragStart, startPosition = false, nil, nil, nil
    end
end)
local function renderDashboard()
    toggle.Text = enabled and "■  DỪNG FARM" or "▶  BẬT FARM"
    toggle.BackgroundColor3 = enabled and C.red or C.button
    onLabel.Text, onLabel.TextColor3 = enabled and "● ON" or "● OFF", enabled and C.green or C.muted
    local visited = 0
    for _, point in ipairs(patrol.points) do if point.visited == patrol.pass then visited = visited + 1 end end
    local owned, blocked, waiting = getStoreSummary()
    local fruitCount = 0
    for _ in pairs(fruitRecords) do fruitCount = fruitCount + 1 end
    refs.team.Text = tostring(currentTeamName() or "Chờ chọn team")
    refs.event.Text = config.EventScheduleEnabled and ((eventWindow.active and "ĐANG MỞ " or "TIẾP THEO ")
        .. string.format("%02d:%02d", math.floor(eventWindow.remaining / 60), math.floor(eventWindow.remaining % 60))) or "LỊCH TẮT"
    refs.camp.Text = patrol.pass .. " • " .. visited .. "/" .. #patrol.points
    refs.magnet.Text, refs.owned.Text = tostring(#targets), tostring(#owned)
    refs.events.Text, refs.fruits.Text = tostring(eventCount), tostring(fruitCount)
    refs.blocked.Text = waiting .. "/" .. blocked
    refs.auto.Text = randomToken.locked and "LỖI" or (config.AutoRandomToken and "ON" or "OFF")
    refs.auto.TextColor3 = randomToken.locked and C.red or (config.AutoRandomToken and C.green or C.muted)
    refs.portal.Text = short(portal.lastResult, 65)
    refs.hop.Text = short(hop.status, 65)
    local url = tostring(env.WebhookURL or config.WebhookURL or "")
    refs.webhook.Text = config.WebhookEnabled and url:match("^https://")
        and ("ON • " .. tostring(env.WebhookMinRarity or config.WebhookMinRarity)) or "OFF"
    targetLabel.Text = short(status, 150)
    refs.random.Text = "Token: " .. short(randomToken.status, 95)
end
renderDashboard()
function api.Destroy()
    if not alive then return end
    if waterPlatform then waterPlatform:Destroy(); waterPlatform = nil end
    cancelAction("Destroy")
    alive, enabled = false, false
    restoreBring()
    restoreSeatGuard()
    resetTarget()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, record in pairs(remotes) do
        if record.connection then record.connection:Disconnect() end
        record.rename:Disconnect(); record.destroy:Disconnect()
    end
    remotes, mobs, targets = {}, {}, {}
    local fruitInstances = {}
    for instance in pairs(fruitRecords) do table.insert(fruitInstances, instance) end
    for _, instance in ipairs(fruitInstances) do removeFruitRecord(instance) end
    gui:Destroy()
    if env.EventMagnetFarm == api then env.EventMagnetFarm = nil end
end
connect(toggle.Activated, function() api.SetEnabled(not enabled) end)
connect(close.Activated, api.Destroy)
connect(topClose.Activated, api.Destroy)
connect(player.CharacterRemoving, function()
    cancelAction("CharacterRemoving"); resetTarget(); hop.readyAt = nil; status = "Cho respawn..."
end)
connect(player.CharacterAdded, function()
    cancelAction("CharacterAdded"); resetTarget(); scanClock = config.ScanInterval
end)
connect(RunService.Stepped, function()
    if not enabled or not target or action.kind then restoreBring() end
    local ok, err = pcall(updateSeatGuard)
    if not ok and os.clock() - lastError > 5 then
        lastError = os.clock(); log("SEAT", short(err, 100))
    end
    if not moveRoot or not enabled then return end
    local character = player.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if collisionState[part] == nil then collisionState[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end)
connect(RunService.Heartbeat, function(dt)
    local ok, err = pcall(function()
        scanClock, uiClock = scanClock + dt, uiClock + dt
        fruitScanClock, fruitESPClock = fruitScanClock + dt, fruitESPClock + dt
        patrol.refresh = patrol.refresh + dt
        if patrol.refresh >= 5 then patrol.refresh = 0; refreshSpawnPoints() end
        if scanClock >= config.ScanInterval then scanClock = 0; scanMobs() end
        if fruitScanClock >= config.FruitScanInterval then fruitScanClock = 0; refreshFruits() end
        if fruitESPClock >= config.FruitESPUpdateInterval then
            fruitESPClock = 0
            updateFruitESP(rootOf(player.Character))
        end
        updateEventWindow()
        farmStep(dt)
        randomTokenStep()
        if uiClock >= 0.3 then
            uiClock = 0
            renderDashboard()
        end
    end)
    if not ok then
        api.SetEnabled(false)
        status = "Loi: da dung farm. Xem GetLogs()."
        targetLabel.Text = status
        if os.clock() - lastError > 5 then lastError = os.clock(); log("ERROR", err) end
    end
end)
-- Same 30-second interval as the supplied code (its 90-second comment was stale).
task.spawn(function()
    task.wait(2)
    while alive and sessionSerial == env.__EventMagnetSessionSerial do
        if enabled and config.HopApiUrl ~= "" and game.JobId ~= "" then
            -- Only this coroutine sends heartbeats: a hanging HTTP request cannot
            -- spawn another one, and a stopped/rerun session exits afterwards.
            pcall(function()
                workerRequest("/api/heartbeat", {
                    username = player.Name, jobId = game.JobId, placeId = tostring(game.PlaceId),
                })
            end)
        end
        task.wait(config.HopHeartbeatInterval)
    end
end)
end -- dashboard function
mountDashboard()
log("INFO", "Chi quan sat event client; khong xac nhan reward hoac event rieng server")
return api


]====]
env.__EventMagnetV2Source = source
local run, err = loadstring(source)
assert(run, err)
return run()
