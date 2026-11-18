local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local REMOTE_NAME = "AvatarRigSwitch"
local REQUEST_COOLDOWN = 2
local RESPAWN_APPEARANCE_TIMEOUT = 10

local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if remote and not remote:IsA("RemoteFunction") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
end

local preferredRig = {}
local switching = {}
local lastRequest = {}
local generation = {}

local function getRigType(name)
	if name == "R6" then
		return Enum.HumanoidRigType.R6
	elseif name == "R15" then
		return Enum.HumanoidRigType.R15
	end
	return nil
end

local function copyCharacterScripts(oldCharacter, newCharacter)
	local copied = {}

	local function copyScriptsFrom(container)
		if not container then return end
		for _, child in ipairs(container:GetChildren()) do
			if (child:IsA("LocalScript") or child:IsA("Script")) and not copied[child.Name] then
				if not newCharacter:FindFirstChild(child.Name) then
					local ok, clone = pcall(function() return child:Clone() end)
					if ok and clone then
						clone.Parent = newCharacter
						copied[child.Name] = true
					end
				end
			end
		end
	end

	copyScriptsFrom(oldCharacter)
	copyScriptsFrom(StarterPlayer:FindFirstChild("StarterCharacterScripts"))
end

local function buildCharacterForRig(player, targetRig, expectedCharacter)
	if not player.Parent then
		return false, "Player is no longer in this server."
	end

	local oldCharacter = player.Character
	if not oldCharacter or (expectedCharacter and oldCharacter ~= expectedCharacter) then
		return false, "Your character changed before the rig switch could finish."
	end

	local oldHumanoid = oldCharacter:FindFirstChildOfClass("Humanoid")
	local oldRoot = oldCharacter:FindFirstChild("HumanoidRootPart")
	if not oldHumanoid or not oldRoot or oldHumanoid.Health <= 0 then
		return false, "Your character is not ready to change rigs."
	end
	if oldHumanoid.RigType == targetRig then
		return true, targetRig.Name .. " is already your current character rig."
	end

	local descriptionOk, description = pcall(function()
		return oldHumanoid:GetAppliedDescription()
	end)
	if not descriptionOk or not description then
		return false, "Could not read your current avatar appearance: " .. tostring(description)
	end

	local createOk, newCharacter = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(
			description,
			targetRig,
			Enum.AssetTypeVerification.Default
		)
	end)
	pcall(function() description:Destroy() end)
	if not createOk or not newCharacter then
		return false, "Roblox could not build the requested rig: " .. tostring(newCharacter)
	end

	local newHumanoid = newCharacter:FindFirstChildOfClass("Humanoid")
	local newRoot = newCharacter:FindFirstChild("HumanoidRootPart")
	if not newHumanoid or not newRoot then
		newCharacter:Destroy()
		return false, "The new character model was missing its Humanoid or HumanoidRootPart."
	end

	newHumanoid.WalkSpeed = oldHumanoid.WalkSpeed
	newHumanoid.UseJumpPower = oldHumanoid.UseJumpPower
	newHumanoid.JumpPower = oldHumanoid.JumpPower
	newHumanoid.JumpHeight = oldHumanoid.JumpHeight
	newHumanoid.AutoRotate = oldHumanoid.AutoRotate
	newHumanoid.MaxHealth = math.max(1, oldHumanoid.MaxHealth)
	newHumanoid.Health = math.clamp(oldHumanoid.Health, 1, newHumanoid.MaxHealth)
	newHumanoid.DisplayDistanceType = oldHumanoid.DisplayDistanceType
	newHumanoid.HealthDisplayDistance = oldHumanoid.HealthDisplayDistance
	newHumanoid.NameDisplayDistance = oldHumanoid.NameDisplayDistance

	newCharacter.Name = player.Name
	newCharacter:SetAttribute("CatalogRigType", targetRig.Name)
	newCharacter.PrimaryPart = newRoot
	copyCharacterScripts(oldCharacter, newCharacter)

	local oldPivot = oldCharacter:GetPivot()
	local oldVelocity = oldRoot.AssemblyLinearVelocity
	local oldAngularVelocity = oldRoot.AssemblyAngularVelocity

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(oldCharacter:GetChildren()) do
			if child:IsA("Tool") then
				child.Parent = backpack
			end
		end
	end

	newCharacter.Parent = workspace
	newCharacter:PivotTo(oldPivot)
	player.Character = newCharacter
	pcall(function() newRoot:SetNetworkOwner(player) end)
	newRoot.AssemblyLinearVelocity = oldVelocity
	newRoot.AssemblyAngularVelocity = oldAngularVelocity

	task.defer(function()
		if oldCharacter and oldCharacter.Parent and player.Character == newCharacter then
			oldCharacter:Destroy()
		end
	end)

	if targetRig == Enum.HumanoidRigType.R6 then
		return true, "Your actual character is now R6. Some R15-only layered items or dynamic heads may not appear on R6."
	end
	return true, "Your actual character is now R15."
end

local function schedulePreferredRig(player, character)
	local targetRig = preferredRig[player]
	if not targetRig or switching[player] then return end

	generation[player] = (generation[player] or 0) + 1
	local token = generation[player]
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", RESPAWN_APPEARANCE_TIMEOUT)
		if not humanoid or player.Character ~= character then return end
		if humanoid.RigType == targetRig then return end

		local appearanceLoaded = false
		local connection = player.CharacterAppearanceLoaded:Connect(function(loadedCharacter)
			if loadedCharacter == character then
				appearanceLoaded = true
			end
		end)
		local started = os.clock()
		while player.Parent and player.Character == character and not appearanceLoaded
			and os.clock() - started < RESPAWN_APPEARANCE_TIMEOUT do
			task.wait(0.1)
		end
		connection:Disconnect()
		task.wait(1.0)

		if generation[player] ~= token or player.Character ~= character or switching[player] then
			return
		end
		local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
		if not currentHumanoid or currentHumanoid.RigType == targetRig then return end

		switching[player] = true
		local ok, message = buildCharacterForRig(player, targetRig, character)
		switching[player] = nil
		if not ok then
			warn("[CatalogRigSwitch] Could not restore " .. targetRig.Name .. " for " .. player.Name .. ": " .. tostring(message))
		end
	end)
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		schedulePreferredRig(player, character)
	end)
	if player.Character then
		schedulePreferredRig(player, player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

remote.OnServerInvoke = function(player, requestedRigName)
	local targetRig = getRigType(requestedRigName)
	if not targetRig then
		return false, nil, "Choose either R6 or R15."
	end
	if switching[player] then
		return false, nil, "A character rig change is already running."
	end

	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return false, nil, "Please wait a moment before switching rigs again."
	end
	lastRequest[player] = now

	local oldPreference = preferredRig[player]
	preferredRig[player] = targetRig
	switching[player] = true
	local ok, message = buildCharacterForRig(player, targetRig, player.Character)
	switching[player] = nil

	if not ok then
		preferredRig[player] = oldPreference
		local currentHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local currentName = currentHumanoid and currentHumanoid.RigType.Name or nil
		return false, currentName, message
	end

	player:SetAttribute("CatalogPreferredRig", targetRig.Name)
	return true, targetRig.Name, message
end

Players.PlayerRemoving:Connect(function(player)
	preferredRig[player] = nil
	switching[player] = nil
	lastRequest[player] = nil
	generation[player] = nil
end)
