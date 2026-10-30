-- Visual Carry (standalone) - by Honami
-- UI is built in this file (styled after Mugiwara UI); swap and preview logic ported from Mugiwara HUB's
-- Games/Evade/VisualSwap.lua, CarryPreview.lua (Carry) and VisualGridUI.lua.

-- Only runs in Evade (same place ids as Mugiwara HUB); in any other game nothing is loaded.
local EVADE_PLACE_IDS = { [9872472334] = true, [99214917572799] = true, [10668472534] = true }
if not EVADE_PLACE_IDS[game.PlaceId] then
    warn("[Visual Carry] This script only works in Evade.")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Visual Carry", Text = "This script only works in Evade.", Duration = 6 })
    end)
    return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local FOLDER = "VisualCarry"
if makefolder and isfolder and not isfolder(FOLDER) then makefolder(FOLDER) end

-- VisualSwap/CarryPreview below call getgenv().MugiwaraRegisterCleanup(...) and read
-- getgenv().MugiwaraFolder - satisfied here with a small local implementation (no hub loaded).
local cleanupFns = {}
local function RegisterCleanup(fn)
    table.insert(cleanupFns, fn)
end
getgenv().MugiwaraFolder = FOLDER
getgenv().MugiwaraRegisterCleanup = RegisterCleanup

-- Dijalankan saat script dimuat ulang: hasil swap dari sesi sebelumnya dikembalikan dulu.
local env = getgenv()
if env.VisualCarryCleanup then pcall(env.VisualCarryCleanup) end
env.VisualCarryCleanup = function()
    for _, fn in ipairs(cleanupFns) do pcall(fn) end
end

-- ==========================================================
-- Swap engine (ported from Games/Evade/VisualSwap.lua)
-- ==========================================================
local function NewSwap(config)
    local Swap = {}

    local CATEGORY = config.Category
    local PATHS = config.Paths or {}
    local WHITELIST = config.Whitelist or {}
    local NOUN = config.Noun or "item"

    local entries = {}
    local byInstance = {}
    local swapped = {}
    local originals = {}

    local function SpacedName(name)
        return (name:gsub("(%l)(%u)", "%1 %2"))
    end

    local function ResolvePath(path)
        local current = game
        for _, name in ipairs(string.split(path, ".")) do
            if name == "ReplicatedStorage" then
                current = ReplicatedStorage
            else
                current = current:FindFirstChild(name)
            end
            if not current then return nil end
        end
        return current
    end

    local loaded = false
    local source = "none"

    local function AddEntry(instance, id)
        if byInstance[instance] then return end

        local info
        local ok, result = pcall(require, instance)
        if ok and type(result) == "table" then info = result end
        local display = info and info.AppearanceInfo and info.AppearanceInfo.Name
        local header = info and info.UIInfo and info.UIInfo.Header

        local entry = {
            Name = instance.Name,
            Display = type(display) == "string" and display or SpacedName(instance.Name),
            Header = type(header) == "string" and header or "Other",
            Id = id,
            Instance = instance,
        }
        table.insert(entries, entry)
        byInstance[instance] = entry
    end

    local function LoadFromRegistry()
        local items = ReplicatedStorage:FindFirstChild("Items")
        local registryModule = items and items:FindFirstChild("Registry")
        if not registryModule then return false end

        local ok, Registry = pcall(require, registryModule)
        if not ok or type(Registry) ~= "table" or type(Registry.GetByCategory) ~= "function" then return false end

        local okList, list = pcall(Registry.GetByCategory, CATEGORY)
        if not okList or type(list) ~= "table" then return false end

        for id, record in pairs(list) do
            local module = type(record) == "table" and record.Module
            if typeof(module) == "Instance" then AddEntry(module, id) end
        end
        return #entries > 0
    end

    local function LoadFromPaths()
        for _, path in ipairs(PATHS) do
            local instance = ResolvePath(path)
            if instance then AddEntry(instance) end
        end
    end

    local function LoadFromScan()
        local items = ReplicatedStorage:FindFirstChild("Items")
        if not items then return end
        for _, descendant in ipairs(items:GetDescendants()) do
            if descendant:IsA("ModuleScript") then
                local inCategory = false
                local parent = descendant.Parent
                while parent and parent ~= items do
                    if parent:IsA("Folder") and parent.Name == CATEGORY then
                        inCategory = true
                        break
                    end
                    parent = parent.Parent
                end
                if inCategory then AddEntry(descendant) end
            end
        end
    end

    function Swap.Load()
        if loaded then return #entries end
        loaded = true

        if not ReplicatedStorage:FindFirstChild("Items") then
            pcall(function() ReplicatedStorage:WaitForChild("Items", 8) end)
        end

        if LoadFromRegistry() then
            source = "registry"
        else
            table.clear(entries)
            table.clear(byInstance)
            LoadFromPaths()
            source = "paths"
            if #entries == 0 then
                LoadFromScan()
                source = "scan"
            end
        end

        table.sort(entries, function(a, b)
            return string.lower(a.Display) < string.lower(b.Display)
        end)
        return #entries
    end

    function Swap.GetSource()
        return source
    end

    function Swap.GetEntries()
        return entries
    end

    function Swap.GetWhitelist(entry)
        return entry and WHITELIST[entry.Name] or nil
    end

    function Swap.GetPartner(entry)
        local partner = entry and swapped[entry.Instance]
        return partner and byInstance[partner] or nil
    end

    -- 1 = belum bisa, 2 = bisa ditukar, 3 = pasangan yang sudah tertukar (tombol jadi Revert)
    function Swap.GetState(base, target)
        if not base or not target or base == target then return 1 end
        if swapped[base.Instance] == target.Instance then return 3 end
        if swapped[base.Instance] ~= nil or swapped[target.Instance] ~= nil then return 1 end
        return 2
    end

    local function CacheOriginal(item)
        if not originals[item] then
            originals[item] = {}
            for _, child in ipairs(item:GetChildren()) do
                table.insert(originals[item], child:Clone())
            end
        end
    end

    local function InjectContents(targetItem, sourceItem)
        for _, child in ipairs(targetItem:GetChildren()) do
            child:Destroy()
        end
        for _, child in ipairs(originals[sourceItem]) do
            child:Clone().Parent = targetItem
        end
    end

    function Swap.Swap(base, target)
        if Swap.GetState(base, target) ~= 2 then
            return false, "Please make sure you picked a valid Base and Target " .. NOUN .. "."
        end

        local ok, err = pcall(function()
            CacheOriginal(base.Instance)
            CacheOriginal(target.Instance)
            InjectContents(base.Instance, target.Instance)
            InjectContents(target.Instance, base.Instance)
        end)
        if not ok then return false, "The swap failed: " .. tostring(err) end

        swapped[base.Instance] = target.Instance
        swapped[target.Instance] = base.Instance
        return true, base.Display .. " ⇌ " .. target.Display
    end

    function Swap.Revert(base, target)
        if Swap.GetState(base, target) ~= 3 then
            return false, "These two " .. NOUN .. "s are not swapped."
        end

        local ok, err = pcall(function()
            InjectContents(base.Instance, base.Instance)
            InjectContents(target.Instance, target.Instance)
        end)
        if not ok then return false, "The revert failed: " .. tostring(err) end

        swapped[base.Instance] = nil
        swapped[target.Instance] = nil
        return true, base.Display .. " and " .. target.Display .. " were restored."
    end

    function Swap.RevertAll()
        local restored, touched = 0, {}
        for instance, partner in pairs(table.clone(swapped)) do
            if swapped[instance] == partner then
                local entry, other = byInstance[instance], byInstance[partner]
                if entry and other and Swap.Revert(entry, other) then
                    restored = restored + 1
                    table.insert(touched, entry)
                    table.insert(touched, other)
                end
            end
        end
        return restored, touched
    end

    getgenv().MugiwaraRegisterCleanup(function()
        pcall(Swap.RevertAll)
    end)

    return Swap
end

-- ==========================================================
-- Preview: frozen-pose viewport models for the carry grid
-- (ported from Games/Evade/CarryPreview.lua, Carry kind only: two mannequins, the carrier and the
-- carried one, posed with their carry animations plus the carry's prop model)
-- ==========================================================
local Preview = {}
do
    local TRACK_TIMEOUT = 5
    local SETTLE_FRAMES = 2
    local MAX_HOSTS = 3
    local COLLECT_GAP = 0.12

    local POSE_FILE = FOLDER .. "/CarryPoses.json"
    local POSE_VERSION = 1

    local alive = true
    local hostGui = nil
    local hosts = {}
    local cache = {}
    local inflight = {}
    local inflightPose = {}
    local poses = nil
    local poseToken = 0

    local function HeartbeatWait(frames)
        for _ = 1, frames or 1 do RunService.Heartbeat:Wait() end
    end

    local function IsR15()
        local ok, rigType = pcall(function() return Players.LocalPlayer:GetAttribute("RigType") end)
        if ok and rigType ~= nil then return rigType == "R15" end
        return true
    end

    local function AssetItem(name)
        local assets = ReplicatedStorage:FindFirstChild("Assets")
        local items = assets and assets:FindFirstChild("Items")
        return items and items:FindFirstChild(name)
    end

    local function MannequinTemplate(r15)
        return AssetItem(r15 and "Mannequin" or "MannequinClassic")
    end

    function Preview.Available()
        return MannequinTemplate(IsR15()) ~= nil
    end

    local function LoadPoses()
        if poses then return poses end
        poses = {}
        if readfile and isfile and isfile(POSE_FILE) then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(POSE_FILE)) end)
            if ok and type(decoded) == "table" and decoded.Version == POSE_VERSION and type(decoded.Poses) == "table" then
                poses = decoded.Poses
            end
        end
        return poses
    end

    local function FlushPoses()
        poseToken = poseToken + 1
        if not (poses and writefile) then return end
        pcall(function()
            if makefolder and isfolder and not isfolder(FOLDER) then makefolder(FOLDER) end
            writefile(POSE_FILE, HttpService:JSONEncode({ Version = POSE_VERSION, Poses = poses }))
        end)
    end

    local function SavePosesSoon()
        poseToken = poseToken + 1
        local mine = poseToken
        task.delay(3, function()
            if mine == poseToken then FlushPoses() end
        end)
    end

    local function JointPath(rig, joint)
        local names = {}
        local node = joint
        while node and node ~= rig do
            table.insert(names, 1, node.Name)
            node = node.Parent
        end
        return table.concat(names, "/")
    end

    local IDENTITY = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }

    local function IsIdentity(components)
        for index, value in ipairs(IDENTITY) do
            if math.abs((components[index] or 0) - value) > 0.0001 then return false end
        end
        return true
    end

    local function CapturePose(rig)
        local pose = {}
        for _, descendant in ipairs(rig:GetDescendants()) do
            if descendant:IsA("Motor6D") then
                local components = { descendant.Transform:GetComponents() }
                if not IsIdentity(components) then pose[JointPath(rig, descendant)] = components end
            end
        end
        return pose
    end

    local function HasMotion(rig)
        for _, descendant in ipairs(rig:GetDescendants()) do
            if descendant:IsA("Motor6D") and not IsIdentity({ descendant.Transform:GetComponents() }) then return true end
        end
        return false
    end

    local function ApplyPose(rig, pose)
        for _, descendant in ipairs(rig:GetDescendants()) do
            if descendant:IsA("Motor6D") then
                local components = pose[JointPath(rig, descendant)]
                descendant.Transform = components and CFrame.new(table.unpack(components)) or CFrame.new()
            end
        end
    end

    local function EnsureGui()
        if hostGui and hostGui.Parent then return hostGui end

        local parent
        pcall(function() parent = (gethui and gethui()) or game:GetService("CoreGui") end)
        if not parent then parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

        hostGui = Instance.new("ScreenGui")
        hostGui.Name = "VisualCarryPreview"
        hostGui.ResetOnSpawn = false
        hostGui.DisplayOrder = -10
        hostGui.IgnoreGuiInset = true
        hostGui.Parent = parent
        table.clear(hosts)
        return hostGui
    end

    local function AcquireHost()
        while alive do
            local gui = EnsureGui()
            for _, entry in ipairs(hosts) do
                if not entry.InUse and entry.Frame.Parent then
                    entry.InUse = true
                    return entry
                end
            end
            if #hosts < MAX_HOSTS then
                local frame = Instance.new("ViewportFrame")
                frame.Name = "Host" .. (#hosts + 1)
                frame.Size = UDim2.fromOffset(8, 8)
                frame.Position = UDim2.fromOffset(0, 0)
                frame.BackgroundTransparency = 1
                frame.ImageTransparency = 0.98
                frame.Parent = gui
                local entry = { Frame = frame, InUse = true }
                table.insert(hosts, entry)
                return entry
            end
            task.wait(0.03)
        end
        return nil
    end

    -- R15 reads the carry module directly, classic (R6) reads its "Classic" folder.
    local function CarryVariant(item, r15)
        if r15 then return item end
        return item:FindFirstChild("Classic")
    end

    -- "Carry" is the carrier's animation, "Carried" the one being carried.
    local function FindCarryAnimation(item, r15, animationName)
        local variant = CarryVariant(item, r15)
        local animation = variant and variant:FindFirstChild(animationName)
        if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then return animation end
        return nil
    end

    local function PoseJobs(entry, r15)
        local jobs = {}
        local template = MannequinTemplate(r15)
        local prefix = r15 and "M15:" or "M6:"
        for name, animationName in pairs({ Carrier = "Carry", Carried = "Carried" }) do
            local animation = FindCarryAnimation(entry.Instance, r15, animationName)
            if animation then table.insert(jobs, { Name = name, Animation = animation, Prefix = prefix, Template = template, Classic = not r15 }) end
        end
        return jobs
    end

    local function PoseKey(job)
        return job.Prefix .. tostring(job.Animation.AnimationId)
    end

    local function GetAnimator(rig)
        local controller = rig:FindFirstChildWhichIsA("AnimationController", true) or rig:FindFirstChildWhichIsA("Humanoid", true)
        if not controller then return nil end
        return controller:FindFirstChildOfClass("Animator") or (function()
            local animator = Instance.new("Animator")
            animator.Parent = controller
            return animator
        end)()
    end

    -- Classic mannequin: joints whose C0 and C1 rotations match get their rotation zeroed (CarryPair.alignJoints).
    local function AlignJoints(model)
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("Motor6D") then
                local c0, c1 = descendant.C0, descendant.C1
                if c0.Rotation ~= CFrame.identity and c0.Rotation:FuzzyEq(c1.Rotation) then
                    descendant.C0 = CFrame.new(c0.Position)
                    descendant.C1 = CFrame.new(c1.Position)
                end
            end
        end
    end

    local function SolveJoints(container, solved)
        if not solved then
            local root = container:FindFirstChild("HumanoidRootPart", true) or container.PrimaryPart
            if not root then return false end
            solved = { [root] = true }
        end

        local joints = {}
        for _, descendant in ipairs(container:GetDescendants()) do
            if descendant:IsA("Motor6D") or descendant:IsA("Weld") then
                if descendant.Part0 and descendant.Part1 then table.insert(joints, descendant) end
            end
        end

        local progress = true
        while progress do
            progress = false
            for _, joint in ipairs(joints) do
                local part0, part1 = joint.Part0, joint.Part1
                local transform = joint:IsA("Motor6D") and joint.Transform or CFrame.new()
                if solved[part0] and not solved[part1] then
                    part1.CFrame = part0.CFrame * joint.C0 * transform * joint.C1:Inverse()
                    solved[part1] = true
                    progress = true
                elseif solved[part1] and not solved[part0] then
                    part0.CFrame = part1.CFrame * joint.C1 * transform:Inverse() * joint.C0:Inverse()
                    solved[part0] = true
                    progress = true
                end
            end
        end
        return true
    end

    local function Orient(model)
        local primary = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart", true)
        if not primary then return end

        local inverse = primary.CFrame:Inverse()
        local base = CFrame.new(primary.Position)
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then descendant.CFrame = base * (inverse * descendant.CFrame) end
        end
    end

    local STRIP_CLASSES = {
        "Motor6D", "Weld", "ManualWeld", "WeldConstraint", "Snap", "Constraint",
        "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke", "Sparkles", "Explosion", "Highlight", "ForceField",
        "PointLight", "SpotLight", "SurfaceLight", "WrapTarget", "WrapLayer",
        "AnimationController", "Humanoid", "Animator", "LuaSourceContainer", "Sound",
    }

    local function ShouldStrip(instance)
        for _, class in ipairs(STRIP_CLASSES) do
            if instance:IsA(class) then return true end
        end
        return instance:IsA("Attachment") and not instance:IsA("Bone")
    end

    local function Freeze(source, name)
        local copy = source:Clone()
        copy.Name = name
        for _, descendant in ipairs(copy:GetDescendants()) do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CastShadow = false
                descendant.CanCollide = false
                descendant.CanQuery = false
                descendant.CanTouch = false
            end
        end
        for _, descendant in ipairs(copy:GetDescendants()) do
            if ShouldStrip(descendant) then pcall(function() descendant:Destroy() end) end
        end
        Orient(copy)
        return copy
    end

    local function IsInside(part, container)
        local node = part
        while node do
            if node == container then return true end
            node = node.Parent
        end
        return false
    end

    -- Two mannequins (Carrier and Carried) are placed at the HumanoidRootPart of each holder in the carry's
    -- "Character" model, posed with their animations, then the prop model (CarryModel) is attached to them.
    local function BuildCarryModel(entry, r15, poseOf)
        local template = MannequinTemplate(r15)
        if not template then return nil, "the game's mannequin was not found" end

        local variant = CarryVariant(entry.Instance, r15)
        local characterTemplate = variant and variant:FindFirstChild("Character")
        if not characterTemplate then return nil, "this carry has no character model" end

        local okClone, character = pcall(function() return characterTemplate:Clone() end)
        if not okClone or not character then return nil, "this carry model cannot be copied" end

        local model = Instance.new("Model")
        model.Name = entry.Display

        local placed = {}
        for _, name in ipairs({ "Carrier", "Carried" }) do
            local holder = character:FindFirstChild(name)
            local anchor = holder and holder:FindFirstChild("HumanoidRootPart")
            if not (anchor and anchor:IsA("BasePart")) then
                character:Destroy()
                model:Destroy()
                return nil, "this carry model is incomplete"
            end

            local clone = template:Clone()
            clone.Name = name
            if not r15 then pcall(AlignJoints, clone) end
            if poseOf[name] then ApplyPose(clone, poseOf[name]) end
            SolveJoints(clone)

            local root = clone:FindFirstChild("HumanoidRootPart", true)
            local move = anchor.CFrame * root.CFrame:Inverse()
            for _, descendant in ipairs(clone:GetDescendants()) do
                if descendant:IsA("BasePart") then descendant.CFrame = move * descendant.CFrame end
            end

            clone.Parent = model
            placed[name] = clone
        end

        local propParts = {}
        for _, name in ipairs({ "Carrier", "Carried" }) do
            local holder = character:FindFirstChild(name)
            local carryModel = holder and holder:FindFirstChild("CarryModel")
            if carryModel then
                for _, descendant in ipairs(carryModel:GetDescendants()) do
                    if descendant:IsA("BasePart") then propParts[descendant] = true end
                    if descendant:IsA("Motor6D") or descendant:IsA("Weld") or descendant:IsA("ManualWeld") or descendant:IsA("WeldConstraint") then
                        for _, property in ipairs({ "Part0", "Part1" }) do
                            local part = descendant[property]
                            if typeof(part) == "Instance" and IsInside(part, character) and not IsInside(part, carryModel) then
                                local top = part
                                while top.Parent and top.Parent ~= character do top = top.Parent end
                                local mannequin = placed[top.Name]
                                if mannequin then
                                    local replacement = mannequin:FindFirstChild(part.Name)
                                    if not (replacement and replacement:IsA("BasePart")) then replacement = mannequin:FindFirstChild("HumanoidRootPart") end
                                    descendant[property] = replacement
                                end
                            end
                        end
                    end
                end
                carryModel.Parent = placed[name]
            end
        end

        model.PrimaryPart = placed.Carrier:FindFirstChild("HumanoidRootPart")
        character:Destroy()

        local solved = {}
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") and not propParts[descendant] then solved[descendant] = true end
        end
        SolveJoints(model, solved)

        local frozen = Freeze(model, entry.Display)
        pcall(function() model:Destroy() end)
        return frozen
    end

    local function EnsurePose(job)
        local key = PoseKey(job)
        local store = LoadPoses()
        if store[key] then return store[key] end

        while inflightPose[key] do
            task.wait(0.03)
            if not alive then return nil, "unloaded" end
        end
        if store[key] then return store[key] end
        inflightPose[key] = true

        local hostEntry = AcquireHost()
        if not hostEntry then
            inflightPose[key] = nil
            return nil, "unloaded"
        end

        local pose, failure
        local world
        local ok, err = pcall(function()
            world = Instance.new("WorldModel")
            world.Parent = hostEntry.Frame

            local rig = job.Template:Clone()
            if job.Classic then pcall(AlignJoints, rig) end
            rig.Parent = world

            local animator = GetAnimator(rig)
            if not animator then
                failure = "the preview rig has no animator"
                return
            end

            local track = animator:LoadAnimation(job.Animation)
            track.Priority = Enum.AnimationPriority.Action3
            track:Play(0)
            track:AdjustSpeed(0)

            -- single-keyframe hold poses keep Length 0 even when loaded, so joint motion counts too
            local limit = os.clock() + TRACK_TIMEOUT
            while alive and os.clock() < limit and track.Length <= 0 and not HasMotion(rig) do HeartbeatWait(1) end
            if track.Length <= 0 and not HasMotion(rig) then
                failure = "the animation did not load (" .. tostring(job.Animation.AnimationId) .. ")"
                return
            end

            HeartbeatWait(SETTLE_FRAMES)
            pose = CapturePose(rig)
        end)

        if world then pcall(function() world:Destroy() end) end
        hostEntry.InUse = false
        inflightPose[key] = nil

        if not ok then return nil, tostring(err) end
        if not pose then return nil, failure or "preview failed" end

        store[key] = pose
        SavePosesSoon()
        return pose
    end

    function Preview.Get(entry)
        return entry and cache[entry.Instance] or nil
    end

    function Preview.PoseKnown(entry)
        local store = LoadPoses()
        for _, job in ipairs(PoseJobs(entry, IsR15())) do
            if not store[PoseKey(job)] then return false end
        end
        return true
    end

    function Preview.Invalidate(entry)
        local model = entry and cache[entry.Instance]
        if model then
            cache[entry.Instance] = nil
            pcall(function() model:Destroy() end)
        end
    end

    function Preview.Preload(entries)
        local r15 = IsR15()
        local store = LoadPoses()
        local list = {}
        for _, entry in ipairs(entries) do
            for _, job in ipairs(PoseJobs(entry, r15)) do
                if not store[PoseKey(job)] then table.insert(list, job.Animation) end
            end
        end
        if #list == 0 then return end
        task.spawn(function()
            pcall(function() game:GetService("ContentProvider"):PreloadAsync(list) end)
        end)
    end

    function Preview.Bake(entry)
        if not alive then return nil, "unloaded" end
        local cached = cache[entry.Instance]
        if cached then return cached end

        local r15 = IsR15()

        while inflight[entry.Instance] do
            task.wait(0.03)
            if not alive then return nil, "unloaded" end
        end
        cached = cache[entry.Instance]
        if cached then return cached end
        inflight[entry.Instance] = true

        local model, failure
        local ok, err = pcall(function()
            local poseOf = {}
            for _, job in ipairs(PoseJobs(entry, r15)) do
                local pose, reason = EnsurePose(job)
                if not pose then
                    failure = reason
                    return
                end
                poseOf[job.Name] = pose
            end
            model, failure = BuildCarryModel(entry, r15, poseOf)
        end)
        inflight[entry.Instance] = nil

        if not ok then return nil, tostring(err) end
        if not model then return nil, failure or "preview failed" end
        if not alive then
            model:Destroy()
            return nil, "unloaded"
        end

        cache[entry.Instance] = model
        return model
    end

    function Preview.Collect(entries)
        local r15 = IsR15()
        local store = LoadPoses()
        local collected = 0
        for _, entry in ipairs(entries) do
            if not alive then break end
            for _, job in ipairs(PoseJobs(entry, r15)) do
                if not store[PoseKey(job)] then
                    if EnsurePose(job) then collected = collected + 1 end
                    task.wait(COLLECT_GAP)
                end
            end
        end
        return collected
    end

    RegisterCleanup(function()
        alive = false
        FlushPoses()
        for instance, model in pairs(cache) do pcall(function() model:Destroy() end) cache[instance] = nil end
        if hostGui then pcall(function() hostGui:Destroy() end) hostGui = nil end
        table.clear(hosts)
    end)
end

-- ==========================================================
-- UI: own implementation that copies the look of Mugiwara UI (Gear 5 theme): glass window,
-- spinning neon border, animated gradient title / badge / buttons, white translucent cards,
-- dark inset fields and picture cells with a check badge. Layout: Base left, Target right, each
-- with a category dropdown, a search box and an always-open grid of previews.
-- ==========================================================
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local VERSION = "v2.0"

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local THEME = {
    Background = rgb(12, 13, 21), BackgroundAlpha = 0.12,
    Card = rgb(255, 255, 255), CardAlpha = 0.91,
    Stroke = rgb(255, 255, 255), StrokeAlpha = 0.84,
    Field = rgb(0, 0, 0), FieldAlpha = 0.45,
    Popup = rgb(14, 14, 20), PopupAlpha = 0.08,
    Text = rgb(252, 252, 255), SubText = rgb(200, 204, 220), Muted = rgb(142, 146, 164),
    Accent = rgb(255, 255, 255), OnAccent = rgb(16, 18, 30),
    Success = rgb(80, 230, 150), Danger = rgb(255, 72, 92),
    Swapped = rgb(255, 200, 62),
}
local GRADIENT_STOPS = { rgb(255, 255, 255), rgb(224, 234, 255), rgb(255, 247, 226), rgb(255, 224, 160) }

local function Linear(stops)
    local points = {}
    for index, color in ipairs(stops) do
        points[index] = ColorSequenceKeypoint.new((index - 1) / (#stops - 1), color)
    end
    return ColorSequence.new(points)
end
local GRADIENT = Linear(GRADIENT_STOPS)
local CYCLE = (function()
    local mirrored = table.clone(GRADIENT_STOPS)
    for index = #GRADIENT_STOPS - 1, 1, -1 do table.insert(mirrored, GRADIENT_STOPS[index]) end
    return Linear(mirrored)
end)()

local FONT_TITLE, FONT_LABEL, FONT_BODY = Enum.Font.GothamBold, Enum.Font.GothamSemibold, Enum.Font.GothamMedium

local function New(class, props, parent)
    local instance = Instance.new(class)
    for key, value in pairs(props) do instance[key] = value end
    instance.Parent = parent
    return instance
end

local function Round(instance, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, radius) }, instance)
end

local function Stroke(instance, transparency, thickness, color)
    return New("UIStroke", {
        Color = color or THEME.Stroke,
        Transparency = transparency,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, instance)
end

local function Gradient(parent, rotation, sequence)
    return New("UIGradient", { Rotation = rotation or 0, Color = sequence or GRADIENT }, parent)
end

local function Label(parent, props)
    local merged = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = FONT_BODY,
        TextColor3 = THEME.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }
    for key, value in pairs(props) do merged[key] = value end
    return New("TextLabel", merged, parent)
end

local function Tween(instance, props, duration, style)
    TweenService:Create(instance, TweenInfo.new(duration or 0.2, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local spinTweens = {}
local function Spin(gradient, seconds)
    local tween = TweenService:Create(gradient, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = gradient.Rotation + 360 })
    tween:Play()
    table.insert(spinTweens, tween)
end
RegisterCleanup(function()
    for _, tween in ipairs(spinTweens) do pcall(function() tween:Cancel() end) end
end)

-- Icons drawn from rotated bars, like Mugiwara UI draws its own glyphs.
local function Glyph(parent, size)
    return New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
    }, parent)
end

local function Bar(root, length, thickness, rotation, x, y, color)
    local bar = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(x, y),
        Size = UDim2.fromOffset(length, thickness),
        Rotation = rotation,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, root)
    Round(bar, thickness)
    return bar
end

local function ChevronGlyph(parent, size, color)
    local root = Glyph(parent, size)
    local length = size * 0.56
    return root, { Bar(root, length, 2, 45, 0.31, 0.5, color), Bar(root, length, 2, -45, 0.69, 0.5, color) }
end

local function CheckGlyph(parent, size, color)
    local root = Glyph(parent, size)
    Bar(root, size * 0.34, 2, 42, 0.3, 0.63, color)
    Bar(root, size * 0.64, 2, -48, 0.63, 0.51, color)
    return root
end

local function CloseGlyph(parent, size, color)
    local root = Glyph(parent, size)
    return { Bar(root, size * 0.78, 2, 45, 0.5, 0.5, color), Bar(root, size * 0.78, 2, -45, 0.5, 0.5, color) }
end

local function MinusGlyph(parent, size, color)
    local root = Glyph(parent, size)
    return { Bar(root, size * 0.7, 2, 0, 0.5, 0.5, color) }
end

-- A pill button: gradient fill (primary) or a white translucent card (secondary).
local function MakeButton(parent, text, primary, width)
    local pill = New("Frame", {
        Size = UDim2.fromOffset(width, 32),
        BackgroundColor3 = primary and Color3.new(1, 1, 1) or THEME.Card,
        BackgroundTransparency = primary and 0 or THEME.CardAlpha,
        BorderSizePixel = 0,
    }, parent)
    Round(pill, 9)
    if primary then Gradient(pill, 0) else Stroke(pill, THEME.StrokeAlpha) end
    local label = Label(pill, {
        Text = text,
        Font = FONT_TITLE,
        TextColor3 = primary and THEME.OnAccent or THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })
    local hit = New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, pill)
    local button = { Frame = pill, Label = label, Hit = hit, Primary = primary, Width = width }
    hit.MouseButton1Down:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width - 6, 28) }, 0.08)
    end)
    hit.MouseButton1Up:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width, 32) }, 0.3, Enum.EasingStyle.Back)
    end)
    hit.MouseLeave:Connect(function()
        Tween(pill, { Size = UDim2.fromOffset(width, 32) }, 0.2)
    end)
    if not primary then
        hit.MouseEnter:Connect(function() Tween(pill, { BackgroundTransparency = 0.84 }, 0.15) end)
        hit.MouseLeave:Connect(function() Tween(pill, { BackgroundTransparency = THEME.CardAlpha }, 0.2) end)
    end
    return button
end

local function SetEnabled(button, enabled)
    button.Frame.BackgroundTransparency = enabled and (button.Primary and 0 or THEME.CardAlpha) or 0.6
    button.Label.TextTransparency = enabled and 0 or 0.45
end

local guiParent
pcall(function() guiParent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not guiParent then guiParent = Players.LocalPlayer:WaitForChild("PlayerGui") end

local Gui = New("ScreenGui", {
    Name = "VisualCarry",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 10000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)
RegisterCleanup(function() pcall(function() Gui:Destroy() end) end)

local camera = workspace.CurrentCamera
local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)
local WIDTH, HEIGHT = 680, 470
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 480, 340, 1000, 760
local TOPBAR, BAR_H = 54, 56
-- Small screens (phones) shrink the whole UI so it fits instead of being cut off.
local UI_SCALE = math.clamp(math.min(1, (screen.X - 24) / WIDTH, (screen.Y - 24) / HEIGHT), 0.45, 1)

local Main = New("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WIDTH, HEIGHT),
    BackgroundTransparency = 1,
}, Gui)
New("UIScale", { Scale = UI_SCALE }, Main)

local Pop = New("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
}, Main)
local PopScale = New("UIScale", { Scale = 0.9 }, Pop)

-- neon glow rings behind the window
local glowRings = {}
for _, layer in ipairs({ { 0, 3, 0.5 }, { 3, 7, 0.8 }, { 10, 14, 0.92 } }) do
    local pad, thickness, transparency = layer[1], layer[2], layer[3]
    local ring = New("Frame", {
        Name = "Glow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, pad * 2, 1, pad * 2),
        BackgroundTransparency = 1,
    }, Pop)
    Round(ring, 16 + pad)
    local stroke = Stroke(ring, 1, thickness)
    Spin(Gradient(stroke, 0, CYCLE), 9)
    table.insert(glowRings, { Stroke = stroke, Base = transparency })
end

local Win = New("CanvasGroup", {
    Name = "Window",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = THEME.Background,
    BackgroundTransparency = THEME.BackgroundAlpha,
    GroupTransparency = 1,
    BorderSizePixel = 0,
}, Pop)
Round(Win, 16)

-- glass wash + sheen
local wash = New("Frame", { Name = "Wash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, Win)
Gradient(wash, 35).Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.9),
})
local sheen = New("Frame", { Name = "Sheen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, Win)
New("UIGradient", {
    Rotation = 20,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.92), NumberSequenceKeypoint.new(0.35, 1), NumberSequenceKeypoint.new(1, 0.97),
    }),
}, sheen)

-- spinning neon border above the window
local border = New("Frame", { Name = "Border", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, Pop)
Round(border, 16)
local borderStroke = Stroke(border, 1, 1.5)
Spin(Gradient(borderStroke, 0, CYCLE), 9)
table.insert(glowRings, { Stroke = borderStroke, Base = 0.3 })

-- topbar
local TopBar = New("Frame", { Name = "Topbar", Size = UDim2.new(1, 0, 0, TOPBAR), BackgroundTransparency = 1 }, Win)

local brand = New("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 16, 0.5, 0),
    Size = UDim2.fromOffset(30, 30),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, TopBar)
Round(brand, 9)
Gradient(brand, 45)
Label(brand, {
    Text = "V",
    Font = Enum.Font.GothamBlack,
    TextSize = 17,
    TextColor3 = THEME.OnAccent,
    TextXAlignment = Enum.TextXAlignment.Center,
    Size = UDim2.fromScale(1, 1),
})

local titleRow = New("Frame", {
    Position = UDim2.fromOffset(56, 8),
    Size = UDim2.new(1, -200, 0, 22),
    BackgroundTransparency = 1,
}, TopBar)
New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 8),
}, titleRow)
local titleLabel = Label(titleRow, {
    Text = "Visual Carry",
    Font = FONT_TITLE,
    TextSize = 16,
    TextColor3 = Color3.new(1, 1, 1),
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 20),
    LayoutOrder = 1,
})
Gradient(titleLabel, 0)

local versionPill = New("Frame", {
    Size = UDim2.fromOffset(0, 16),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    LayoutOrder = 2,
}, titleRow)
Round(versionPill, 8)
New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, versionPill)
Gradient(versionPill, 0)
Label(versionPill, {
    Text = VERSION,
    Font = FONT_TITLE,
    TextSize = 11,
    TextColor3 = THEME.OnAccent,
    TextXAlignment = Enum.TextXAlignment.Center,
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 16),
})

Label(TopBar, {
    Text = "by Honami  ·  K to hide or show",
    TextSize = 12,
    TextColor3 = THEME.SubText,
    Position = UDim2.fromOffset(56, 30),
    Size = UDim2.new(1, -200, 0, 14),
})

local function ControlButton(offset, makeGlyph, hoverColor)
    local button = New("TextButton", {
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, offset, 0.5, 0),
        Size = UDim2.fromOffset(34, 34),
    }, TopBar)
    Round(button, 9)
    local bars = makeGlyph(button, 20, THEME.SubText)
    button.MouseEnter:Connect(function()
        Tween(button, { BackgroundTransparency = 0.88 }, 0.15)
        for _, bar in ipairs(bars) do Tween(bar, { BackgroundColor3 = hoverColor or THEME.Text }, 0.15) end
    end)
    button.MouseLeave:Connect(function()
        Tween(button, { BackgroundTransparency = 1 }, 0.2)
        for _, bar in ipairs(bars) do Tween(bar, { BackgroundColor3 = THEME.SubText }, 0.2) end
    end)
    return button
end

local CloseButton = ControlButton(-12, CloseGlyph, THEME.Danger)
local MinimizeButton = ControlButton(-50, MinusGlyph)

local topLine = New("Frame", {
    Position = UDim2.fromOffset(0, TOPBAR),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
}, Win)
Gradient(topLine, 0).Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 0.9),
})

local Body = New("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(0, TOPBAR + 1),
    Size = UDim2.new(1, 0, 1, -(TOPBAR + 1)),
    BackgroundTransparency = 1,
}, Win)

local PaneHolder = New("Frame", { Name = "Panes", Size = UDim2.new(1, 0, 1, -BAR_H), BackgroundTransparency = 1 }, Body)
New("UIPadding", {
    PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 8),
}, PaneHolder)
New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 10),
}, PaneHolder)

local BottomBar = New("Frame", {
    Name = "BottomBar",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.fromScale(0, 1),
    Size = UDim2.new(1, 0, 0, BAR_H),
    BackgroundTransparency = 1,
}, Body)
New("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = THEME.Stroke,
    BackgroundTransparency = THEME.StrokeAlpha,
    BorderSizePixel = 0,
}, BottomBar)

local StatusLabel = Label(BottomBar, {
    Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(1, -290, 1, 0),
    TextColor3 = THEME.SubText,
    TextTruncate = Enum.TextTruncate.AtEnd,
})
local RevertAllButton = MakeButton(BottomBar, "Revert All", false, 104)
RevertAllButton.Frame.AnchorPoint = Vector2.new(1, 0.5)
RevertAllButton.Frame.Position = UDim2.new(1, -12, 0.5, 0)
local SwapButton = MakeButton(BottomBar, "Swap", true, 140)
SwapButton.Frame.AnchorPoint = Vector2.new(1, 0.5)
SwapButton.Frame.Position = UDim2.new(1, -128, 0.5, 0)

-- Window behaviour: drag by the topbar, minimize, close.
do
    local dragging, dragStart, startPosition = false, nil, nil
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPosition = true, input.Position, Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    local moveConnection = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = (input.Position - dragStart) / UI_SCALE
            Main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    RegisterCleanup(function() moveConnection:Disconnect() end)

    -- resize grip in the bottom-right corner (the window grows from its top-left corner)
    local grip = New("TextButton", {
        Name = "ResizeGrip",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, -4),
        Size = UDim2.fromOffset(22, 22),
        ZIndex = 8,
    }, Pop)
    Bar(grip, 14, 2, -45, 0.58, 0.58, THEME.Muted)
    Bar(grip, 7, 2, -45, 0.78, 0.78, THEME.Muted)

    local resizing, resizeStart, startSize, resizeOrigin = false, nil, nil, nil
    grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing, resizeStart, startSize, resizeOrigin = true, input.Position, Main.Size, Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then resizing = false end
            end)
        end
    end)
    local resizeConnection = UserInputService.InputChanged:Connect(function(input)
        if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = (input.Position - resizeStart) / UI_SCALE
            local maxWidth = math.max(MIN_WIDTH, math.min(MAX_WIDTH, (screen.X - 24) / UI_SCALE))
            local maxHeight = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, (screen.Y - 24) / UI_SCALE))
            local width = math.clamp(startSize.X.Offset + delta.X, MIN_WIDTH, maxWidth)
            local height = math.clamp(startSize.Y.Offset + delta.Y, MIN_HEIGHT, maxHeight)
            Main.Size = UDim2.fromOffset(width, height)
            Main.Position = UDim2.new(
                resizeOrigin.X.Scale, resizeOrigin.X.Offset + (width - startSize.X.Offset) / 2,
                resizeOrigin.Y.Scale, resizeOrigin.Y.Offset + (height - startSize.Y.Offset) / 2
            )
        end
    end)
    RegisterCleanup(function() resizeConnection:Disconnect() end)

    -- floating round open button (like Mugiwara UI's), shown while the window is hidden
    local OpenButton = New("TextButton", {
        Name = "OpenButton",
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 36, 0.5, 0),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = THEME.Popup,
        BackgroundTransparency = THEME.PopupAlpha,
        Visible = false,
    }, Gui)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, OpenButton)
    New("UIScale", { Scale = UI_SCALE }, OpenButton)
    Spin(Gradient(Stroke(OpenButton, 0.15, 2), 0, CYCLE), 6)
    Spin(Gradient(Stroke(OpenButton, 0.7, 6), 0, CYCLE), 6)
    local openMark = Label(OpenButton, {
        Text = "V",
        Font = Enum.Font.GothamBlack,
        TextSize = 22,
        TextColor3 = Color3.new(1, 1, 1),
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })
    Gradient(openMark, 45)

    local opened = true
    local function SetOpen(state)
        if state == opened then return end
        opened = state
        if state then
            Main.Visible = true
            PopScale.Scale = 0.9
            Tween(PopScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Quint)
            Tween(Win, { GroupTransparency = 0 }, 0.3)
            for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = ring.Base }, 0.4) end
            Tween(OpenButton, { Size = UDim2.fromOffset(0, 0) }, 0.18)
            task.delay(0.18, function()
                if opened then OpenButton.Visible = false end
            end)
        else
            Tween(PopScale, { Scale = 0.92 }, 0.3, Enum.EasingStyle.Quint)
            Tween(Win, { GroupTransparency = 1 }, 0.24)
            for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = 1 }, 0.2) end
            task.delay(0.3, function()
                if not opened then Main.Visible = false end
            end)
            OpenButton.Visible = true
            Tween(OpenButton, { Size = UDim2.fromOffset(52, 52) }, 0.5, Enum.EasingStyle.Back)
        end
    end

    -- the open button can be dragged; a tap (no drag) opens the window again
    local pressed, moved, pressStart, pressPosition = false, false, nil, nil
    OpenButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            pressed, moved, pressStart, pressPosition = true, false, input.Position, OpenButton.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    pressed = false
                    if not moved then SetOpen(true) end
                end
            end)
        end
    end)
    local openMoveConnection = UserInputService.InputChanged:Connect(function(input)
        if pressed and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = (input.Position - pressStart) / UI_SCALE
            if delta.Magnitude * UI_SCALE > 6 then moved = true end
            if moved then
                OpenButton.Position = UDim2.new(pressPosition.X.Scale, pressPosition.X.Offset + delta.X, pressPosition.Y.Scale, pressPosition.Y.Offset + delta.Y)
            end
        end
    end)
    RegisterCleanup(function() openMoveConnection:Disconnect() end)

    MinimizeButton.MouseButton1Click:Connect(function() SetOpen(false) end)

    local keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.K then SetOpen(not opened) end
    end)
    RegisterCleanup(function() keyConnection:Disconnect() end)

    -- close asks first: every swapped carry is put back, and the script has to be run again to reopen
    local dialogOpen = false
    local function ConfirmClose()
        if dialogOpen then return end
        dialogOpen = true

        local overlay = New("TextButton", {
            Name = "Dialog",
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1,
            ZIndex = 50,
        }, Win)
        Tween(overlay, { BackgroundTransparency = 0.42 }, 0.25)

        local card = New("CanvasGroup", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(0, 330, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = THEME.Popup,
            BackgroundTransparency = THEME.PopupAlpha,
            GroupTransparency = 1,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 51,
        }, overlay)
        Round(card, 14)
        local outline = Stroke(card, 1, 1.4, Color3.new(1, 1, 1))
        Spin(Gradient(outline, 45, CYCLE), 8)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18),
            PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
        }, card)
        New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }, card)
        local cardScale = New("UIScale", { Scale = 0.9 }, card)
        Tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
        Tween(card, { GroupTransparency = 0 }, 0.25)
        Tween(outline, { Transparency = 0.3 }, 0.25)

        local title = Label(card, {
            Text = "Close Visual Carry?",
            Font = FONT_TITLE,
            TextSize = 16,
            TextColor3 = Color3.new(1, 1, 1),
            TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            LayoutOrder = 1,
        })
        Gradient(title, 0)
        Label(card, {
            Text = "The interface will be closed and every swapped carry will be put back to normal. Run the script again to reopen it.",
            TextSize = 14,
            TextColor3 = THEME.SubText,
            TextWrapped = true,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
            LayoutOrder = 2,
        })

        local row = New("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 3 }, card)
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
        }, row)

        local function CloseDialog()
            Tween(cardScale, { Scale = 0.93 }, 0.2)
            Tween(card, { GroupTransparency = 1 }, 0.2)
            Tween(outline, { Transparency = 1 }, 0.2)
            Tween(overlay, { BackgroundTransparency = 1 }, 0.2)
            task.delay(0.22, function()
                overlay:Destroy()
                dialogOpen = false
            end)
        end

        local function DialogButton(text, danger, order, callback)
            local button = New("TextButton", {
                Text = text,
                Font = FONT_TITLE,
                TextSize = 13,
                TextColor3 = danger and THEME.OnAccent or THEME.Text,
                AutoButtonColor = false,
                BorderSizePixel = 0,
                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.fromOffset(0, 36),
                BackgroundColor3 = danger and THEME.Danger or THEME.Card,
                BackgroundTransparency = danger and 0 or 0.84,
                LayoutOrder = order,
            }, row)
            Round(button, 9)
            New("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, button)
            button.MouseButton1Click:Connect(callback)
        end

        DialogButton("Cancel", false, 1, CloseDialog)
        DialogButton("Close", true, 2, function()
            local fns = cleanupFns
            cleanupFns = {}
            for _, fn in ipairs(fns) do pcall(fn) end
        end)
    end
    CloseButton.MouseButton1Click:Connect(ConfirmClose)

    -- open animation: pop in and fade the glow up
    Tween(PopScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Back)
    Tween(Win, { GroupTransparency = 0 }, 0.35)
    for _, ring in ipairs(glowRings) do Tween(ring.Stroke, { Transparency = ring.Base }, 0.45) end
end

-- ==========================================================
-- Carry grid logic (ported from Games/Evade/VisualGridUI.lua, rebuilt on the UI above)
-- ==========================================================
local HEADER_ORDER = { "Normal", "Gamepasses", "Halloween", "Winter Holidays", "Summer", "Spring", "Valentines", "Event", "Special" }

local function BuildGroups(entries)
    local byHeader = {}
    for _, entry in ipairs(entries) do
        byHeader[entry.Header] = byHeader[entry.Header] or {}
        table.insert(byHeader[entry.Header], entry)
    end

    local order, seen = {}, {}
    for _, header in ipairs(HEADER_ORDER) do
        if byHeader[header] then
            table.insert(order, header)
            seen[header] = true
        end
    end
    local rest = {}
    for header in pairs(byHeader) do
        if not seen[header] then table.insert(rest, header) end
    end
    table.sort(rest)
    for _, header in ipairs(rest) do table.insert(order, header) end

    local groups = {}
    for _, header in ipairs(order) do
        table.insert(groups, { Title = header, Entries = byHeader[header] })
    end
    return groups
end

-- Same camera as the game's carry menu: in front, a little to the right and above.
local LOOK_DIRECTION = Vector3.new(4.25, 1.7, -8.5).Unit
local CELL_HEIGHT, TITLE_HEIGHT, GAP = 108, 20, 6

local function BuildCarryUI(Swap)
    if Swap.Load() == 0 then
        Label(PaneHolder, {
            Text = "No carries were found in this game. The game may have changed its item folders.",
            TextWrapped = true,
            TextColor3 = THEME.SubText,
            TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1),
        })
        SwapButton.Frame.Visible = false
        RevertAllButton.Frame.Visible = false
        return
    end

    local groups = BuildGroups(Swap.GetEntries())
    local byName = {}
    for _, entry in ipairs(Swap.GetEntries()) do byName[entry.Name] = entry end
    local sides = {}
    local failedPreview = {}
    local previewState = nil
    local statusToken = 0
    local Refresh, RefreshVisible

    local function TitleOf(entry)
        local partner = Swap.GetPartner(entry)
        return partner and (entry.Display .. " (" .. partner.Display .. ")") or entry.Display
    end

    local function ShowHint()
        local base, target = sides.Base.Selected, sides.Target.Selected
        local state = Swap.GetState(base, target)
        if state == 3 then
            StatusLabel.Text = base.Display .. " looks like " .. target.Display .. " (swapped)"
        elseif state == 2 then
            StatusLabel.Text = "Ready: " .. base.Display .. " will look like " .. target.Display
        else
            StatusLabel.Text = "Pick a Base and a Target carry."
        end
        StatusLabel.TextColor3 = THEME.SubText
    end

    local function SetStatus(text, color)
        statusToken = statusToken + 1
        local mine = statusToken
        StatusLabel.Text = text
        StatusLabel.TextColor3 = color or THEME.SubText
        task.delay(3.5, function()
            if mine == statusToken then ShowHint() end
        end)
    end

    local function PreviewsOn()
        if previewState == nil then
            previewState = Preview.Available() and true or false
            if not previewState then SetStatus("Previews are not available in this game version.", THEME.Danger) end
        end
        return previewState
    end

    -- ---------- cells ----------
    local function AttachView(tile)
        if tile.View then return end
        local model = Preview.Get(tile.Entry)
        if not model then return end

        local view = New("ViewportFrame", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Ambient = Color3.fromRGB(190, 190, 190),
            LightColor = Color3.fromRGB(255, 255, 255),
        }, tile.Thumb)
        local clone = model:Clone()
        clone.Parent = view

        local cf, size = clone:GetBoundingBox()
        local radius = math.max(size.X, size.Y, size.Z) / 2
        local distance = radius / math.tan(math.rad(15)) * 1.1
        local viewCamera = New("Camera", { FieldOfView = 30 }, view)
        viewCamera.CFrame = CFrame.lookAt(cf.Position + LOOK_DIRECTION * distance, cf.Position)
        view.CurrentCamera = viewCamera

        tile.View = view
        tile.Placeholder.Visible = false
    end

    local function DetachView(tile)
        if tile.View then
            tile.View:Destroy()
            tile.View = nil
        end
        tile.Placeholder.Visible = true
    end

    local function PaintTile(side, tile, hovered)
        local on = side.Selected == tile.Entry
        -- already swapped: the whole cell is tinted gold so it stands out in the list
        local swapped = Swap.GetPartner(tile.Entry) ~= nil
        tile.Button.BackgroundColor3 = swapped and THEME.Swapped or Color3.new(1, 1, 1)
        tile.Button.BackgroundTransparency = swapped and (on and 0.68 or (hovered and 0.74 or 0.8)) or (on and 0.82 or (hovered and 0.9 or 0.95))
        tile.Badge.Visible = on
        tile.Stroke.Color = on and THEME.Accent or (swapped and THEME.Swapped or THEME.Stroke)
        tile.Stroke.Transparency = on and 0.2 or (swapped and 0.35 or (hovered and 0.7 or THEME.StrokeAlpha))
        tile.Stroke.Thickness = (on or swapped) and 1.5 or 1
    end

    local function Pick(side, entry)
        side.Selected = (side.Selected ~= entry) and entry or nil
        Refresh()
        if side.Selected and Swap.GetWhitelist(side.Selected) then
            SetStatus("Whitelist applied! This carry is restricted to a specific pair.", THEME.Swapped)
        end
    end

    local function MakeTile(side, entry)
        local button = New("TextButton", {
            Name = entry.Name,
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.95,
        }, side.Scroll)
        Round(button, 10)
        local stroke = Stroke(button, THEME.StrokeAlpha)

        local thumb = New("Frame", {
            Name = "Thumb",
            Position = UDim2.fromOffset(5, 5),
            Size = UDim2.new(1, -10, 0, CELL_HEIGHT - 10 - TITLE_HEIGHT),
            BackgroundColor3 = THEME.Field,
            BackgroundTransparency = THEME.FieldAlpha,
            ClipsDescendants = true,
            BorderSizePixel = 0,
        }, button)
        Round(thumb, 7)
        local placeholder = Label(thumb, {
            Text = "…",
            TextSize = 18,
            TextColor3 = THEME.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1),
        })
        local name = Label(button, {
            Text = TitleOf(entry),
            Font = FONT_LABEL,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.new(0, 6, 0, CELL_HEIGHT - TITLE_HEIGHT - 2),
            Size = UDim2.new(1, -12, 0, TITLE_HEIGHT),
        })

        local badge = New("Frame", {
            Name = "Badge",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -9, 0, 9),
            Size = UDim2.fromOffset(18, 18),
            BackgroundColor3 = THEME.Accent,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 3,
        }, button)
        Round(badge, 9)
        CheckGlyph(badge, 12, THEME.OnAccent)

        local tile = { Entry = entry, Button = button, Stroke = stroke, Thumb = thumb, Placeholder = placeholder, Name = name, Badge = badge }
        button.MouseEnter:Connect(function() PaintTile(side, tile, true) end)
        button.MouseLeave:Connect(function() PaintTile(side, tile, false) end)
        button.MouseButton1Click:Connect(function() Pick(side, entry) end)
        return tile
    end

    local function DestroyTile(tile)
        DetachView(tile)
        tile.Button:Destroy()
    end

    -- Only cells near the visible part of the list hold a viewport; each one is a separate render
    -- surface that is redrawn every frame.
    local function IsNear(side, tile)
        local scroll = side.Scroll
        local top = scroll.CanvasPosition.Y
        local bottom = top + scroll.AbsoluteWindowSize.Y
        local y = tile.Button.AbsolutePosition.Y - scroll.AbsolutePosition.Y + top
        local margin = 120
        return y + tile.Button.AbsoluteSize.Y >= top - margin and y <= bottom + margin
    end

    local function UpdateVisible(side)
        for _, tile in ipairs(side.TileList) do
            if IsNear(side, tile) then AttachView(tile) elseif tile.View then DetachView(tile) end
        end
    end

    local function OnBaked(entry)
        for _, side in pairs(sides) do
            local tile = side.TileByEntry[entry]
            if tile and IsNear(side, tile) then AttachView(tile) end
        end
    end

    local WORKERS = 3
    local function Bake(side)
        if not PreviewsOn() then return end
        side.BakeToken = side.BakeToken + 1
        local mine = side.BakeToken

        local pending = {}
        for _, tile in ipairs(side.TileList) do
            if IsNear(side, tile) and not Preview.Get(tile.Entry) and not failedPreview[tile.Entry] then
                table.insert(pending, tile.Entry)
            end
        end
        if #pending == 0 then return end
        Preview.Preload(pending)

        local nextIndex = 1
        local function Worker()
            while mine == side.BakeToken and nextIndex <= #pending do
                local entry = pending[nextIndex]
                nextIndex = nextIndex + 1

                local model, reason = Preview.Bake(entry)
                if model then
                    OnBaked(entry)
                else
                    failedPreview[entry] = true
                    if reason ~= "unloaded" then warn("[Visual Carry] Preview failed for " .. entry.Name .. ": " .. tostring(reason)) end
                end
            end
        end
        for _ = 1, math.min(WORKERS, #pending) do task.spawn(Worker) end
    end

    RefreshVisible = function(side)
        UpdateVisible(side)
        Bake(side)
    end

    -- ---------- one side (Base / Target) ----------
    local function RenderSide(side)
        local other = side == sides.Base and sides.Target or sides.Base
        local query = string.lower(side.Query)

        -- a carry with a required partner (whitelist) only lets that partner show on the other side
        local onlyName = other.Selected and Swap.GetWhitelist(other.Selected) or nil

        local entries = {}
        if onlyName then
            local partner = byName[onlyName]
            if partner then entries[1] = partner end
        else
            for _, entry in ipairs(groups[side.Group].Entries) do
                if entry ~= other.Selected and (query == "" or string.find(string.lower(entry.Display), query, 1, true)) then
                    table.insert(entries, entry)
                end
            end
        end

        local list, map = {}, {}
        for index, entry in ipairs(entries) do
            local tile = side.TileByEntry[entry] or MakeTile(side, entry)
            tile.Button.LayoutOrder = index
            tile.Name.Text = TitleOf(entry)
            list[index] = tile
            map[entry] = tile
        end
        for entry, tile in pairs(side.TileByEntry) do
            if not map[entry] then DestroyTile(tile) end
        end
        side.TileList, side.TileByEntry = list, map

        for _, tile in ipairs(list) do PaintTile(side, tile, false) end

        local selected = side.Selected
        side.SelectedLabel.Text = selected and TitleOf(selected) or "None selected"
        side.SelectedLabel.TextColor3 = selected and THEME.Text or THEME.Muted
    end

    local function UpdateButton()
        local state = Swap.GetState(sides.Base.Selected, sides.Target.Selected)
        SwapButton.Label.Text = state == 3 and "Revert" or "Swap"
        SetEnabled(SwapButton, state ~= 1)
    end

    Refresh = function()
        -- selections that no longer fit a whitelist pair (or are the same carry) are dropped
        local base, target = sides.Base.Selected, sides.Target.Selected
        local targetOnly = base and Swap.GetWhitelist(base) or nil
        local baseOnly = target and Swap.GetWhitelist(target) or nil
        if target and ((targetOnly and target.Name ~= targetOnly) or target == base) then sides.Target.Selected = nil end
        if base and ((baseOnly and base.Name ~= baseOnly) or base == target) then sides.Base.Selected = nil end

        RenderSide(sides.Base)
        RenderSide(sides.Target)
        UpdateButton()
        ShowHint()
        for _, side in pairs(sides) do
            task.defer(function() RefreshVisible(side) end)
        end
    end

    -- dark inset field (Base.Field in Mugiwara UI)
    local function Field(parent, position, size, class, props)
        local merged = {
            BorderSizePixel = 0,
            BackgroundColor3 = THEME.Field,
            BackgroundTransparency = THEME.FieldAlpha,
            Position = position,
            Size = size,
        }
        for key, value in pairs(props or {}) do merged[key] = value end
        local field = New(class, merged, parent)
        Round(field, 8)
        Stroke(field, 0.9)
        return field
    end

    local function NewSide(sideName, titleText)
        local side = {
            Name = sideName, Group = 1, Query = "", Selected = nil,
            TileList = {}, TileByEntry = {}, BakeToken = 0,
        }
        sides[sideName] = side

        local frame = New("Frame", {
            Name = sideName,
            LayoutOrder = sideName == "Base" and 1 or 2,
            Size = UDim2.new(0.5, -5, 1, 0),
            BackgroundColor3 = THEME.Card,
            BackgroundTransparency = THEME.CardAlpha,
            BorderSizePixel = 0,
        }, PaneHolder)
        Round(frame, 10)
        Stroke(frame, 0.9)

        local inner = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, frame)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        }, inner)

        Label(inner, { Text = titleText, Font = FONT_TITLE, TextSize = 15, Size = UDim2.new(0.5, 0, 0, 20) })
        side.SelectedLabel = Label(inner, {
            Text = "None selected",
            TextSize = 12,
            TextColor3 = THEME.Muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromScale(0.5, 0),
            Size = UDim2.new(0.5, 0, 0, 20),
        })

        -- category dropdown
        local categoryButton = Field(inner, UDim2.fromOffset(0, 26), UDim2.new(1, 0, 0, 32), "TextButton", { Text = "", AutoButtonColor = false })
        local categoryLabel = Label(categoryButton, {
            Text = groups[1].Title,
            Font = FONT_LABEL,
            Position = UDim2.fromOffset(10, 0),
            Size = UDim2.new(1, -36, 1, 0),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local chevronHolder = New("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -8, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
        }, categoryButton)
        ChevronGlyph(chevronHolder, 14, THEME.SubText)

        -- search
        local search = Field(inner, UDim2.fromOffset(0, 64), UDim2.new(1, 0, 0, 32), "TextBox", {
            Text = "",
            PlaceholderText = "Search carry...",
            PlaceholderColor3 = THEME.Muted,
            TextColor3 = THEME.Text,
            Font = FONT_BODY,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
        })
        New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, search)

        -- grid, open from the start
        side.Scroll = New("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 104),
            Size = UDim2.new(1, 0, 1, -104),
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = THEME.Muted,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ElasticBehavior = Enum.ElasticBehavior.Never,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(),
        }, inner)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3),
            PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 6),
        }, side.Scroll)
        New("UIGridLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            CellSize = UDim2.new(1 / 3, -math.ceil(GAP * 2 / 3), 0, CELL_HEIGHT),
            CellPadding = UDim2.fromOffset(GAP, GAP),
        }, side.Scroll)

        -- category drawer: opens under the field and pushes the search box and the grid down,
        -- like the Mugiwara UI dropdown (dark inset list, rows with gradient / check when chosen)
        local DRAWER_Y = 62
        local drawerHeight = math.min(#groups * 36 + 10, 150)
        local drawer = Field(inner, UDim2.fromOffset(0, DRAWER_Y), UDim2.new(1, 0, 0, drawerHeight), "Frame", { ClipsDescendants = true })
        drawer.Visible = false
        local list = New("ScrollingFrame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = THEME.Muted,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(),
        }, drawer)
        New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, list)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
            PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 8),
        }, list)

        local rows = {}
        local function PaintRow(index, hovered)
            local row = rows[index]
            local on = index == side.Group
            row.Button.BackgroundTransparency = on and 0.78 or (hovered and 0.92 or 1)
            row.Check.Visible = on
            row.Stroke.Color = on and THEME.Accent or THEME.Stroke
            row.Stroke.Transparency = on and 0.45 or (hovered and 0.78 or THEME.StrokeAlpha)
        end

        local drawerOpen = false
        local function Layout(open)
            drawerOpen = open
            drawer.Visible = open
            Tween(chevronHolder, { Rotation = open and 180 or 0 }, 0.2)
            local searchY = open and (DRAWER_Y + drawerHeight + 6) or 64
            local gridY = searchY + 40
            Tween(search, { Position = UDim2.fromOffset(0, searchY) }, 0.2)
            Tween(side.Scroll, { Position = UDim2.fromOffset(0, gridY), Size = UDim2.new(1, 0, 1, -gridY) }, 0.2)
            task.delay(0.25, function() RefreshVisible(side) end)
        end

        for index, group in ipairs(groups) do
            local button = New("TextButton", {
                Text = "",
                AutoButtonColor = false,
                BorderSizePixel = 0,
                BackgroundColor3 = Color3.new(1, 1, 1),
                BackgroundTransparency = 1,
                LayoutOrder = index,
                Size = UDim2.new(1, 0, 0, 32),
            }, list)
            Round(button, 8)
            Gradient(button, 0)
            local stroke = Stroke(button, THEME.StrokeAlpha)
            Label(button, {
                Text = group.Title,
                Font = FONT_LABEL,
                Position = UDim2.fromOffset(12, 0),
                Size = UDim2.new(1, -80, 1, 0),
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            Label(button, {
                Text = tostring(#group.Entries),
                TextSize = 12,
                TextColor3 = THEME.Muted,
                TextXAlignment = Enum.TextXAlignment.Right,
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -34, 0, 0),
                Size = UDim2.new(0, 36, 1, 0),
            })
            local checkSlot = New("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -10, 0.5, 0),
                Size = UDim2.fromOffset(14, 14),
                BackgroundTransparency = 1,
                Visible = false,
            }, button)
            CheckGlyph(checkSlot, 14, THEME.Accent)
            rows[index] = { Button = button, Stroke = stroke, Check = checkSlot }

            button.MouseEnter:Connect(function() PaintRow(index, true) end)
            button.MouseLeave:Connect(function() PaintRow(index, false) end)
            button.MouseButton1Click:Connect(function()
                side.Group = index
                categoryLabel.Text = group.Title
                for rowIndex in ipairs(rows) do PaintRow(rowIndex, false) end
                side.Scroll.CanvasPosition = Vector2.zero
                for entry in pairs(failedPreview) do failedPreview[entry] = nil end
                Layout(false)
                Refresh()
            end)
        end
        for rowIndex in ipairs(rows) do PaintRow(rowIndex, false) end

        categoryButton.MouseButton1Click:Connect(function() Layout(not drawerOpen) end)

        search:GetPropertyChangedSignal("Text"):Connect(function()
            side.Query = search.Text
            side.Scroll.CanvasPosition = Vector2.zero
            Refresh()
        end)

        local scrollToken = 0
        side.Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            scrollToken = scrollToken + 1
            local mine = scrollToken
            task.delay(0.08, function()
                if mine == scrollToken then RefreshVisible(side) end
            end)
        end)
    end

    NewSide("Base", "Base Carry")
    NewSide("Target", "Target Carry")

    -- Swaps drop the old preview models (the items changed) and rebuild them.
    local function Forget(entries)
        for _, entry in ipairs(entries) do
            Preview.Invalidate(entry)
            failedPreview[entry] = nil
            for _, side in pairs(sides) do
                local tile = side.TileByEntry[entry]
                if tile then DetachView(tile) end
            end
        end
    end

    SwapButton.Hit.MouseButton1Click:Connect(function()
        local base, target = sides.Base.Selected, sides.Target.Selected
        local state = Swap.GetState(base, target)
        if state == 1 then
            SetStatus("Pick a valid Base and Target carry first.", THEME.Danger)
            return
        end

        local pair = { base, target }
        local ok, message
        if state == 2 then
            ok, message = Swap.Swap(base, target)
            SetStatus(ok and (base.Display .. " now looks like " .. target.Display) or message, ok and THEME.Success or THEME.Danger)
        else
            ok, message = Swap.Revert(base, target)
            SetStatus(ok and "Restored to normal." or message, ok and THEME.Success or THEME.Danger)
        end

        if ok then Forget(pair) end
        sides.Base.Selected, sides.Target.Selected = nil, nil
        Refresh()
    end)

    RevertAllButton.Hit.MouseButton1Click:Connect(function()
        local restored, touched = Swap.RevertAll()
        Forget(touched)
        sides.Base.Selected, sides.Target.Selected = nil, nil
        Refresh()
        SetStatus(restored > 0 and ("Restored " .. restored .. " swapped pair(s).") or "Nothing is swapped.", restored > 0 and THEME.Success or THEME.SubText)
    end)

    Refresh()

    -- Poses of every carry are gathered quietly in the background (once; saved to a file), so
    -- opening any category later is instant.
    task.spawn(function()
        if not PreviewsOn() then return end
        local list, missing = {}, 0
        for _, group in ipairs(groups) do
            for _, entry in ipairs(group.Entries) do
                table.insert(list, entry)
                if not Preview.PoseKnown(entry) then missing = missing + 1 end
            end
        end
        if missing == 0 then return end
        if missing > 20 then SetStatus("Preparing " .. missing .. " carry previews in the background (one time only)...") end
        Preview.Collect(list)
    end)
end

local Swap = NewSwap({ Category = "CarryAnimations", Noun = "carry" })
BuildCarryUI(Swap)
