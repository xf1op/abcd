local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local PROXY_DOMAIN = "rotunnel.com"

local function proxyUrl(service, path)
	return "https://" .. service .. "." .. PROXY_DOMAIN .. path
end

local function responseError(response)
	local body = tostring(response and response.Body or "")
	body = body:gsub("[%c]+", " ")
	if #body > 240 then body = string.sub(body, 1, 240) .. "..." end
	return "HTTP " .. tostring(response and response.StatusCode or "unknown") .. (body ~= "" and (": " .. body) or "")
end

local remote = ReplicatedStorage:FindFirstChild("AvatarEvent")
if remote and not remote:IsA("RemoteEvent") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "AvatarEvent"
	remote.Parent = ReplicatedStorage
end

local SINGLE = {
	Shirt = "Shirt", Pants = "Pants", TShirt = "GraphicTShirt",
	Face = "Face", Head = "Head", DynamicHead = "Head", Torso = "Torso",
	RightArm = "RightArm", LeftArm = "LeftArm", LeftLeg = "LeftLeg", RightLeg = "RightLeg",
	ClimbAnimation = "ClimbAnimation", FallAnimation = "FallAnimation",
	IdleAnimation = "IdleAnimation", JumpAnimation = "JumpAnimation",
	RunAnimation = "RunAnimation", SwimAnimation = "SwimAnimation",
	WalkAnimation = "WalkAnimation", MoodAnimation = "MoodAnimation",
}

local MULTI = {
	Hat = "HatAccessory", HairAccessory = "HairAccessory",
	FaceAccessory = "FaceAccessory", NeckAccessory = "NeckAccessory",
	ShoulderAccessory = "ShouldersAccessory", FrontAccessory = "FrontAccessory",
	BackAccessory = "BackAccessory", WaistAccessory = "WaistAccessory",
}

local LAYERED = {
	TShirtAccessory = Enum.AccessoryType.TShirt,
	ShirtAccessory = Enum.AccessoryType.Shirt,
	PantsAccessory = Enum.AccessoryType.Pants,
	JacketAccessory = Enum.AccessoryType.Jacket,
	SweaterAccessory = Enum.AccessoryType.Sweater,
	ShortsAccessory = Enum.AccessoryType.Shorts,
	LeftShoeAccessory = Enum.AccessoryType.LeftShoe,
	RightShoeAccessory = Enum.AccessoryType.RightShoe,
	DressSkirtAccessory = Enum.AccessoryType.DressSkirt,
	EyebrowAccessory = Enum.AccessoryType.Eyebrow,
	EyelashAccessory = Enum.AccessoryType.Eyelash,
}

for assetTypeName, propertyName in pairs({
	EarAccessory = "EarAccessory",
	EyeAccessory = "EyeAccessory",
	EyebrowAccessory = "EyebrowAccessory",
	EyelashAccessory = "EyelashAccessory",
	FaceMakeup = "FaceMakeup",
	LipMakeup = "LipMakeup",
	EyeMakeup = "EyeMakeup",
	}) do
	local probe = Instance.new("HumanoidDescription")
	local propertyExists = pcall(function() local _ = probe[propertyName] end)
	probe:Destroy()
	if propertyExists then
		MULTI[assetTypeName] = propertyName
		LAYERED[assetTypeName] = nil
	end
end

for _, enumName in ipairs({ "FaceMakeup", "LipMakeup", "EyeMakeup" }) do
	local ok, accessoryType = pcall(function() return Enum.AccessoryType[enumName] end)
	if ok and accessoryType then
		local name = enumName
		if not MULTI[name] then LAYERED[name] = accessoryType end
	end
end

local ASSET_TYPE_NAMES = {
	[2] = "TShirt", [8] = "Hat", [11] = "Shirt", [12] = "Pants",
	[17] = "Head", [18] = "Face", [27] = "Torso", [28] = "RightArm",
	[29] = "LeftArm", [30] = "LeftLeg", [31] = "RightLeg",
	[41] = "HairAccessory", [42] = "FaceAccessory", [43] = "NeckAccessory",
	[44] = "ShoulderAccessory", [45] = "FrontAccessory", [46] = "BackAccessory",
	[47] = "WaistAccessory", [48] = "ClimbAnimation", [50] = "FallAnimation",
	[51] = "IdleAnimation", [52] = "JumpAnimation", [53] = "RunAnimation",
	[54] = "SwimAnimation", [55] = "WalkAnimation",
	[64] = "TShirtAccessory", [65] = "ShirtAccessory", [66] = "PantsAccessory",
	[67] = "JacketAccessory", [68] = "SweaterAccessory", [69] = "ShortsAccessory",
	[70] = "LeftShoeAccessory", [71] = "RightShoeAccessory", [72] = "DressSkirtAccessory",
	[57] = "EarAccessory", [58] = "EyeAccessory",
	[61] = "EmoteAnimation",
	[76] = "EyebrowAccessory", [77] = "EyelashAccessory",
	[78] = "MoodAnimation", [79] = "DynamicHead",
	[88] = "FaceMakeup", [89] = "LipMakeup", [90] = "EyeMakeup",
	[92] = "AvatarBackground",
}

local saved = {}
local busy = {}

local MAX_SAFE_ROBLOX_ID = 9007199254740991

local function isId(n)
	return typeof(n) == "number"
		and n > 0
		and n % 1 == 0
		and n <= MAX_SAFE_ROBLOX_ID
end

local function supported(name)
	return SINGLE[name] ~= nil or MULTI[name] ~= nil or LAYERED[name] ~= nil
end

local function getHumanoid(plr)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

local function getAppliedDescription(hum)
	local ok, desc = pcall(function()
		return hum:GetAppliedDescription()
	end)
	if not ok or not desc then
		return nil, "could not read the current avatar: " .. tostring(desc)
	end
	return desc
end

local function callHumanoidAppearanceMethod(hum, method, desc)
	local asyncOk, asyncMethod = pcall(function()
		return hum[method .. "Async"]
	end)
	if asyncOk and type(asyncMethod) == "function" then
		return asyncMethod(hum, desc)
	end

	local legacyOk, legacyMethod = pcall(function()
		return hum[method]
	end)
	if legacyOk and type(legacyMethod) == "function" then
		return legacyMethod(hum, desc)
	end
	error("Humanoid method is unavailable: " .. tostring(method))
end

local function callPlayersDescriptionMethod(method, id)
	local asyncOk, asyncMethod = pcall(function()
		return Players[method .. "Async"]
	end)
	if asyncOk and type(asyncMethod) == "function" then
		return asyncMethod(Players, id)
	end

	local legacyOk, legacyMethod = pcall(function()
		return Players[method]
	end)
	if legacyOk and type(legacyMethod) == "function" then
		return legacyMethod(Players, id)
	end
	error("Players method is unavailable: " .. tostring(method))
end

local function getUserDescription(userId)
	return callPlayersDescriptionMethod("GetHumanoidDescriptionFromUserId", userId)
end

local function getOutfitDescription(outfitId)
	return callPlayersDescriptionMethod("GetHumanoidDescriptionFromOutfitId", outfitId)
end

local function resolveType(id, hint, preferHint)
	if preferHint and supported(hint) then
		return hint
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
	end)
	if ok and type(info) == "table" and type(info.AssetTypeId) == "number" then
		local name = ASSET_TYPE_NAMES[info.AssetTypeId]
		if name and supported(name) then
			return name
		end
		if supported(hint) then
			return hint
		end
		return nil, "unsupported asset type id " .. tostring(info.AssetTypeId)
	end
	if supported(hint) then
		return hint
	end
	return nil, "could not resolve asset " .. tostring(id) .. ": " .. tostring(info)
end

local ACCESSORY_TYPE_NAMES = {}
for assetTypeName, accessoryType in pairs(LAYERED) do
	ACCESSORY_TYPE_NAMES[accessoryType] = assetTypeName
end
for enumName, assetTypeName in pairs({
	Hat = "Hat",
	Hair = "HairAccessory",
	Face = "FaceAccessory",
	Neck = "NeckAccessory",
	Shoulder = "ShoulderAccessory",
	Front = "FrontAccessory",
	Back = "BackAccessory",
	Waist = "WaistAccessory",
	}) do
	local ok, accessoryType = pcall(function() return Enum.AccessoryType[enumName] end)
	if ok and accessoryType then ACCESSORY_TYPE_NAMES[accessoryType] = assetTypeName end
end

local function collectEquippedItems(desc)
	local items, seen = {}, {}
	local function add(value, typeName)
		local id = tonumber(value)
		if id and id > 0 and id % 1 == 0 and not seen[id] then
			seen[id] = true
			table.insert(items, { id = id, typeName = typeName or "Item" })
		end
	end

	for assetTypeName, property in pairs(SINGLE) do
		local ok, value = pcall(function() return desc[property] end)
		if ok then add(value, assetTypeName) end
	end
	for assetTypeName, property in pairs(MULTI) do
		local ok, value = pcall(function() return desc[property] end)
		if ok and type(value) == "string" then
			for part in string.gmatch(value, "[^,]+") do add(part, assetTypeName) end
		end
	end
	local accessoriesOk, accessories = pcall(function()
		return desc:GetAccessories(true)
	end)
	if accessoriesOk and type(accessories) == "table" then
		for _, accessory in ipairs(accessories) do
			local typeName = ACCESSORY_TYPE_NAMES[accessory.AccessoryType] or "Accessory"
			add(accessory.AssetId, typeName)
		end
	else
		warn("[CatalogServer] GetAccessories(true) failed while building equipped list:", accessories)
	end

	local emotesOk, emotes = pcall(function() return desc:GetEquippedEmotes() end)
	if emotesOk and type(emotes) == "table" then
		for _, emote in pairs(emotes) do
			if type(emote) == "table" then
				add(emote.Id or emote.AssetId, "EmoteAnimation")
			elseif type(emote) == "number" then
				add(emote, "EmoteAnimation")
			end
		end
	end

	table.sort(items, function(a, b)
		if a.typeName == b.typeName then
			return a.id < b.id
		end
		return a.typeName < b.typeName
	end)
	return items
end

local function collectEquippedIds(desc)
	local ids = {}
	for _, item in ipairs(collectEquippedItems(desc)) do
		table.insert(ids, item.id)
	end
	return ids
end

local function toggleInList(str, id, forceAdd)
	local list, found, seen = {}, false, {}
	for part in string.gmatch(str or "", "[^,]+") do
		local n = tonumber(part)
		if n and n > 0 and n % 1 == 0 and not seen[n] then
			seen[n] = true
			if n == id then
				found = true
				if forceAdd then
					table.insert(list, tostring(n))
				end
			else
				table.insert(list, tostring(n))
			end
		end
	end
	if not found then
		table.insert(list, tostring(id))
	end
	return table.concat(list, ","), (not found) or (forceAdd == true)
end

local function modify(desc, id, typeName, forceAdd)
	local single = SINGLE[typeName]
	local multi = MULTI[typeName]
	local layeredType = LAYERED[typeName]

	if single then
		if desc[single] == id and not forceAdd then
			desc[single] = 0
			return false
		end
		desc[single] = id
		return true
	elseif multi then
		local value, added = toggleInList(desc[multi], id, forceAdd)
		desc[multi] = value
		return added
	elseif layeredType then
		local accessories = desc:GetAccessories(true)
		local updated, found = {}, false
		local nextOrder = 1

		for _, accessory in ipairs(accessories) do
			if accessory.IsLayered then
				nextOrder = math.max(nextOrder, (tonumber(accessory.Order) or 0) + 1)
			end
			if accessory.AssetId == id then
				found = true
				if forceAdd then
					table.insert(updated, accessory)
				end
			else
				table.insert(updated, accessory)
			end
		end

		if not found then
			table.insert(updated, {
				AssetId = id,
				AccessoryType = layeredType,
				IsLayered = true,
				Order = nextOrder,
			})
		end
		desc:SetAccessories(updated, true)
		return (not found) or (forceAdd == true)
	end

	return nil, "unsupported type: " .. tostring(typeName)
end

local function apply(plr, hum, desc)
	local ok, err = pcall(function()
		callHumanoidAppearanceMethod(hum, "ApplyDescription", desc)
	end)
	if not ok then
		warn("[CatalogServer] ApplyDescriptionAsync failed: " .. tostring(err) .. " (retrying with ApplyDescriptionResetAsync)")
		ok, err = pcall(function()
			callHumanoidAppearanceMethod(hum, "ApplyDescriptionReset", desc)
		end)
	end

	if not ok then
		if desc then desc:Destroy() end
		warn("[CatalogServer] ApplyDescriptionReset failed: " .. tostring(err))
		return false, "could not apply avatar: " .. tostring(err)
	end

	local snapshotOk, snapshot = pcall(function()
		return hum:GetAppliedDescription()
	end)
	if not snapshotOk or not snapshot then
		local cloneOk, cloneResult = pcall(function()
			return desc:Clone()
		end)
		snapshot = cloneOk and cloneResult or nil
	end

	local equippedItems = collectEquippedItems(snapshot or desc)
	local equippedIds = {}
	for _, item in ipairs(equippedItems) do
		table.insert(equippedIds, item.id)
	end
	if snapshot then
		local old = saved[plr]
		saved[plr] = snapshot
		if old then
			old:Destroy()
		end
	else
		warn("[CatalogServer] Avatar applied, but could not save its respawn description")
	end

	if desc then desc:Destroy() end
	return true, equippedIds, equippedItems
end

local function wearResolved(plr, id, typeName)
	local hum = getHumanoid(plr)
	if not hum then
		return "error", "character not ready"
	end

	local desc, descError = getAppliedDescription(hum)
	if not desc then
		return "error", descError
	end
	local changed, why = modify(desc, id, typeName, false)
	if changed == nil then
		desc:Destroy()
		return "error", why
	end

	local ok, currentIds, currentItems = apply(plr, hum, desc)
	if not ok then
		return "error", currentIds
	end
	return changed and "added" or "removed", {
		id = id,
		typeName = typeName,
		equippedIds = currentIds,
		equippedItems = currentItems,
	}
end

local function wear(plr, id, hint)
	local typeName, reason = resolveType(id, hint)
	if not typeName then
		return "error", reason
	end
	return wearResolved(plr, id, typeName)
end

local function wearMany(plr, items, preferHints)
	local hum = getHumanoid(plr)
	if not hum then
		return "error", "character not ready"
	end

	local desc, descError = getAppliedDescription(hum)
	if not desc then
		return "error", descError
	end

	local appliedIds, seenIds, firstReason = {}, {}, nil
	local skippedCount = 0
	for _, entry in ipairs(items) do
		local id, hint = entry[1], entry[2]
		if not seenIds[id] then
			seenIds[id] = true
			local typeName, reason = resolveType(id, hint, preferHints == true)
			if typeName then
				local changed, why = modify(desc, id, typeName, true)
				if changed ~= nil then
					table.insert(appliedIds, id)
				else
					firstReason = firstReason or why
				end
			else
				skippedCount += 1
				firstReason = firstReason or reason
			end
		end
	end

	if #appliedIds == 0 then
		desc:Destroy()
		return "error", firstReason or "no usable items in bundle"
	end

	local ok, currentIds, currentItems = apply(plr, hum, desc)
	if not ok then
		return "error", currentIds
	end
	return "many", { ids = appliedIds, skipped = skippedCount, equippedIds = currentIds, equippedItems = currentItems }
end

local function applyFetched(plr, getter, okCode)
	local hum = getHumanoid(plr)
	if not hum then
		return "error", "character not ready"
	end

	local ok, desc = pcall(getter)
	if not ok or not desc then
		return "error", "could not fetch avatar description: " .. tostring(desc)
	end
	if not desc:IsA("HumanoidDescription") then
		return "error", "avatar service returned an invalid description"
	end

	local applied, currentIds, currentItems = apply(plr, hum, desc)
	if not applied then
		return "error", currentIds
	end
	return okCode, { equippedIds = currentIds, equippedItems = currentItems }
end

local function wearOutfit(plr, outfitId)
	return applyFetched(plr, function()
		return getOutfitDescription(outfitId)
	end, "outfit")
end

local function normalizeBundleAssetType(value)
	local name = tostring(value or "")
	name = name:gsub("^Enum%.AvatarAssetType%.", "")
	name = name:gsub("^AvatarAssetType%.", "")
	name = name:match("([%w_]+)$") or name
	return name
end

local function wearBundle(plr, bundleId)
	local ok, bundle = pcall(function()
		return AssetService:GetBundleDetailsAsync(bundleId)
	end)
	if not ok then
		return "error", "could not load bundle " .. tostring(bundleId) .. ": " .. tostring(bundle)
	end
	if type(bundle) ~= "table" or type(bundle.Items) ~= "table" then
		return "error", "Roblox returned bundle details without an Items list"
	end

	local assets, seen = {}, {}
	local skipped, overLimit = 0, 0
	local bodyPartCount = 0
	for _, item in ipairs(bundle.Items) do
		local itemType = string.lower(tostring(item.Type or ""))
		local itemId = tonumber(item.Id)
		if itemType == "asset" and isId(itemId) and not seen[itemId] then
			if #assets < 40 then
				seen[itemId] = true
				local typeHint = normalizeBundleAssetType(item.AssetType)
				if typeHint == "DynamicHead" or typeHint == "Head" or typeHint == "Torso"
					or typeHint == "LeftArm" or typeHint == "RightArm"
					or typeHint == "LeftLeg" or typeHint == "RightLeg" then
					bodyPartCount += 1
				end
				table.insert(assets, { itemId, typeHint })
			else
				overLimit += 1
			end
		end
	end

	if #assets == 0 then
		return "error", "bundle contains no wearable asset entries"
	end

	local code, detail = wearMany(plr, assets, true)
	if code == "many" and type(detail) == "table" then
		detail.bundleName = tostring(bundle.Name or ("Bundle " .. tostring(bundleId)))
		detail.skipped = (tonumber(detail.skipped) or 0) + skipped
		detail.overLimit = overLimit
		detail.bodyPartAssets = bodyPartCount
	end
	return code, detail
end

local function wearAuto(plr, id)
	local typeName, assetReason = resolveType(id, nil)
	if typeName then
		return wearResolved(plr, id, typeName)
	end

	local bundleCode, bundleDetail = wearBundle(plr, id)
	if bundleCode ~= "error" then
		return bundleCode, bundleDetail
	end
	return "error", "not a supported avatar asset or bundle: " .. tostring(assetReason) .. "; " .. tostring(bundleDetail)
end

local function removeAssetById(plr, assetId)
	local humanoid = getHumanoid(plr)
	if not humanoid then
		return "error", "character not ready"
	end
	local desc, descError = getAppliedDescription(humanoid)
	if not desc then
		return "error", descError
	end

	local removed = false
	for _, property in pairs(SINGLE) do
		if tonumber(desc[property]) == assetId then
			desc[property] = 0
			removed = true
		end
	end
	for _, property in pairs(MULTI) do
		local updated = {}
		local changed = false
		for part in string.gmatch(desc[property] or "", "[^,]+") do
			local id = tonumber(part)
			if id == assetId then
				changed = true
				removed = true
			elseif id then
				table.insert(updated, tostring(id))
			end
		end
		if changed then
			desc[property] = table.concat(updated, ",")
		end
	end

	local accessories = desc:GetAccessories(true)
	local updatedAccessories = {}
	local accessoryChanged = false
	for _, accessory in ipairs(accessories) do
		if tonumber(accessory.AssetId) == assetId then
			accessoryChanged = true
			removed = true
		else
			table.insert(updatedAccessories, accessory)
		end
	end
	if accessoryChanged then
		desc:SetAccessories(updatedAccessories, true)
	end

	local emotesOk, emotes = pcall(function() return desc:GetEquippedEmotes() end)
	if emotesOk and type(emotes) == "table" then
		local remainingEmotes = {}
		local removedEmote = false
		for emoteName, emoteValue in pairs(emotes) do
			local emoteId
			if type(emoteValue) == "number" or type(emoteValue) == "string" then
				emoteId = tonumber(emoteValue)
			elseif type(emoteValue) == "table" then
				emoteId = tonumber(emoteValue.Id or emoteValue.AssetId or emoteValue.id)
			end
			if emoteId == assetId then
				removedEmote = true
				removed = true
			else
				remainingEmotes[emoteName] = emoteValue
			end
		end
		if removedEmote then
			local setOk, setError = pcall(function() desc:SetEquippedEmotes(remainingEmotes) end)
			if not setOk then
				desc:Destroy()
				return "error", "could not remove equipped emote: " .. tostring(setError)
			end
		end
	end

	if not removed then
		desc:Destroy()
		return "notEquipped", { id = assetId }
	end

	local applied, currentIds, currentItems = apply(plr, humanoid, desc)
	if not applied then
		return "error", currentIds
	end
	return "removed", { id = assetId, equippedIds = currentIds, equippedItems = currentItems }
end

local profileBackgroundCache = {}
local function getProfileBackgroundId(plr)
	local cached = profileBackgroundCache[plr]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end

	local ok, configuration = pcall(function()
		return Players:GetProfileConfigurationFromUserIdAsync(plr.UserId)
	end)
	local backgroundId = nil
	if ok and type(configuration) == "table" then
		local value = tonumber(configuration.BackgroundAssetId)
		if value and value > 0 then
			backgroundId = value
		end
	else
		warn("[CatalogServer] profile background lookup failed for", plr.Name, configuration)
	end
	profileBackgroundCache[plr] = backgroundId or false
	return backgroundId
end

local function getCurrentlyWearingFallback(userId)
	local requestOk, response = pcall(function()
		return HttpService:RequestAsync({
			Url = proxyUrl("avatar", "/v1/users/" .. tostring(userId) .. "/currently-wearing"),
			Method = "GET",
			Headers = { Accept = "application/json" },
		})
	end)
	if not requestOk or not response or not response.Success then
		warn("[CatalogServer] Currently-wearing fallback unavailable:", response)
		return {}
	end
	local decodeOk, payload = pcall(function() return HttpService:JSONDecode(response.Body) end)
	if not decodeOk or type(payload) ~= "table" then return {} end
	local ids = payload.assetIds or payload.AssetIds or payload.data or payload.Data or {}
	if type(ids) ~= "table" then return {} end
	local items, seen = {}, {}
	for _, value in ipairs(ids) do
		local id = tonumber(type(value) == "table" and (value.id or value.assetId or value.Id) or value)
		if id and id > 0 and id % 1 == 0 and not seen[id] then
			seen[id] = true
			local typeName = resolveType(id, nil, false) or "Item"
			table.insert(items, { id = id, typeName = typeName })
		end
	end
	table.sort(items, function(a, b)
		if a.typeName ~= b.typeName then return a.typeName < b.typeName end
		return a.id < b.id
	end)
	return items
end

local function getAvatarSnapshot(plr)
	local character = plr.Character
	if not character then
		local ok, addedCharacter = pcall(function() return plr.CharacterAdded:Wait() end)
		if ok then character = addedCharacter end
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid and character then
		humanoid = character:WaitForChild("Humanoid", 8)
	end
	if not humanoid or humanoid.Health <= 0 then
		return "error", "character is not ready yet"
	end
	local desc, descError = getAppliedDescription(humanoid)
	if not desc then return "error", descError end

	local equippedItems = collectEquippedItems(desc)
	local snapshotSource = "current HumanoidDescription"

	if #equippedItems == 0 then
		for attempt = 1, 3 do
			task.wait(0.35)
			local retryDesc = getAppliedDescription(humanoid)
			if retryDesc then
				local retryOk, retryItems = pcall(collectEquippedItems, retryDesc)
				if retryOk and type(retryItems) == "table" and #retryItems > 0 then
					desc:Destroy()
					desc = retryDesc
					equippedItems = retryItems
					snapshotSource = "replicated HumanoidDescription"
					break
				else
					retryDesc:Destroy()
				end
			end
		end
	end

	if #equippedItems == 0 and saved[plr] then
		local savedOk, savedItems = pcall(collectEquippedItems, saved[plr])
		if savedOk and type(savedItems) == "table" and #savedItems > 0 then
			equippedItems = savedItems
			snapshotSource = "last confirmed applied description"
		end
	end

	if #equippedItems == 0 then
		local fallbackItems = getCurrentlyWearingFallback(plr.UserId)
		if #fallbackItems > 0 then
			equippedItems = fallbackItems
			snapshotSource = "Roblox currently-wearing fallback"
			warn("[CatalogServer] snapshot used Roblox currently-wearing fallback for", plr.Name, #fallbackItems)
		end
	end

	if #equippedItems == 0 then
		local profileOk, profileDesc = pcall(function() return getUserDescription(plr.UserId) end)
		if profileOk and profileDesc then
			local listOk, profileItems = pcall(collectEquippedItems, profileDesc)
			if listOk and type(profileItems) == "table" and #profileItems > 0 then
				equippedItems = profileItems
				snapshotSource = "Roblox profile description fallback"
			end
			profileDesc:Destroy()
		end
	end
	local equippedIds = {}
	for _, item in ipairs(equippedItems) do table.insert(equippedIds, item.id) end
	local bodyScales = {}
	for _, property in ipairs({ "HeightScale", "WidthScale", "DepthScale", "HeadScale", "BodyTypeScale", "ProportionScale" }) do
		local ok, value = pcall(function() return desc[property] end)
		if ok and type(value) == "number" then bodyScales[property] = value end
	end
	desc:Destroy()
	return "snapshot", {
		equippedIds = equippedIds,
		equippedItems = equippedItems,
		bodyScales = bodyScales,
		backgroundId = getProfileBackgroundId(plr),
		snapshotSource = snapshotSource,
	}
end

local function reset(plr)
	return applyFetched(plr, function()
		return getUserDescription(plr.UserId)
	end, "reset")
end

local function copyUser(plr, name)
	local ok, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not ok or not userId then
		return "nouser"
	end
	return applyFetched(plr, function()
		return getUserDescription(userId)
	end, "user")
end

local PUBLIC_INVENTORY_TYPE_IDS = {
	2, 8, 11, 12, 17, 18, 27, 28, 29, 30, 31,
	41, 42, 43, 44, 45, 46, 47, 48, 50, 51, 52, 53, 54, 55,
	57, 58, 61, 64, 65, 66, 67, 68, 69, 70, 71, 72,
	76, 77, 78, 79, 88, 89, 90, 92,
}

local catalogPublicOutfitsRateLimitedUntil = 0
local catalogPublicInventoryRateLimitedUntil = 0

local function getRetryAfterSeconds(response)
	local headers = response and response.Headers

	if type(headers) == "table" then
		for name, value in pairs(headers) do
			if string.lower(tostring(name)) == "retry-after" then
				local seconds = tonumber(value)

				if seconds and seconds > 0 then
					return math.clamp(math.ceil(seconds), 1, 300)
				end
			end
		end
	end

	return 60
end

local function getRateLimitStatus(untilTime)
	local remaining = math.max(1, math.ceil(untilTime - os.clock()))

	return "Rate limited, waiting (" .. tostring(remaining) .. " seconds)."
end
local PUBLIC_LOOKUP_COOLDOWN = 2
local publicInventoryLastRequest = {}
local function getPublicInventory(userId, onPage)
	local remaining = catalogPublicInventoryRateLimitedUntil - os.clock()

	if remaining > 0 then
		return nil, "rate_limited",
			getRateLimitStatus(catalogPublicInventoryRateLimitedUntil)
	end

	local results, seen = {}, {}
	local partial = false
	local maximumItems = 10000
	local pageSize = 100
	local maxPagesPerType = 100
	local stopAll = false
	local statusMessage = nil

	for _, assetTypeId in ipairs(PUBLIC_INVENTORY_TYPE_IDS) do
		if #results >= maximumItems or stopAll then
			if #results >= maximumItems then
				partial = true
			end
			break
		end

		local cursor = nil

		for pageIndex = 1, maxPagesPerType do
			remaining = catalogPublicInventoryRateLimitedUntil - os.clock()

			if remaining > 0 then
				statusMessage = getRateLimitStatus(catalogPublicInventoryRateLimitedUntil)

				if #results > 0 then
					partial = true
					stopAll = true
					break
				end

				return nil, "rate_limited", statusMessage
			end

			local url = proxyUrl(
				"inventory",
				"/v2/users/" .. tostring(userId)
					.. "/inventory/" .. tostring(assetTypeId)
					.. "?limit=" .. tostring(pageSize)
					.. "&sortOrder=Desc"
			)

			if cursor and cursor ~= "" then
				url ..= "&cursor=" .. HttpService:UrlEncode(cursor)
			end

			local requestOk, response = pcall(function()
				return HttpService:RequestAsync({
					Url = url,
					Method = "GET",
					Headers = {
						Accept = "application/json",
					},
				})
			end)

			if requestOk and response.StatusCode == 429 then
				local seconds = getRetryAfterSeconds(response)

				catalogPublicInventoryRateLimitedUntil = os.clock() + seconds
				statusMessage = getRateLimitStatus(catalogPublicInventoryRateLimitedUntil)

				if #results > 0 then
					partial = true
					stopAll = true
					break
				end

				return nil, "rate_limited", statusMessage
			end

			if not requestOk or not response.Success then
				statusMessage = "Unavailable, user's inventory is private."

				if #results > 0 then
					partial = true
					stopAll = true
					break
				end

				return nil, "unavailable", statusMessage
			end

			local decodeOk, payload = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)

			if not decodeOk or type(payload) ~= "table" then
				statusMessage = "Unavailable, user's inventory is private."

				if #results > 0 then
					partial = true
					stopAll = true
					break
				end

				return nil, "unavailable", statusMessage
			end

			local pageItems = payload.data
				or payload.Data
				or payload.items
				or payload.Items
				or {}

			local pageResults = {}

			if type(pageItems) == "table" then
				for _, raw in ipairs(pageItems) do
					local assetId

					if type(raw) == "table" then
						assetId = tonumber(
							raw.assetId
								or raw.AssetId
								or raw.id
								or raw.Id
						)
					else
						assetId = tonumber(raw)
					end

					if assetId and assetId > 0
						and assetId % 1 == 0
						and not seen[assetId] then

						seen[assetId] = true

						local rawName = type(raw) == "table"
							and (
								raw.assetName
								or raw.AssetName
								or raw.name
								or raw.Name
							)
							or nil

						local normalizedItem = {
							id = assetId,
							name = type(rawName) == "string"
								and rawName ~= ""
								and rawName
								or nil,
							typeName = ASSET_TYPE_NAMES[assetTypeId] or "Item",
						}

						table.insert(results, normalizedItem)
						table.insert(pageResults, normalizedItem)

						if #results >= maximumItems then
							partial = true
							break
						end
					end
				end
			end

			if #pageResults > 0 and type(onPage) == "function" then
				local callbackOk, callbackError = pcall(onPage, pageResults)

				if not callbackOk then
					warn("[CatalogServer] Public inventory page delivery failed:", callbackError)
				end
			end

			if #results >= maximumItems then
				break
			end

			local nextCursor = payload.nextPageCursor or payload.NextPageCursor

			if type(nextCursor) ~= "string" or nextCursor == "" then
				break
			end

			if pageIndex >= maxPagesPerType then
				partial = true
				break
			end

			cursor = nextCursor
			task.wait(0.25)
		end

		task.wait(0.15)
	end

	table.sort(results, function(a, b)
		if a.typeName ~= b.typeName then
			return a.typeName < b.typeName
		end

		if a.name ~= b.name then
			return string.lower(a.name) < string.lower(b.name)
		end

		return a.id < b.id
	end)

	return results, partial and "partial" or "ok", statusMessage
end

local publicOutfitsLastRequest = {}
local function getPublicSavedOutfits(userId)
	local remaining = catalogPublicOutfitsRateLimitedUntil - os.clock()

	if remaining > 0 then
		return nil, "rate_limited",
			getRateLimitStatus(catalogPublicOutfitsRateLimitedUntil)
	end

	local function outfitTimestamp(outfit)
		local raw = outfit.createdAt or outfit.CreatedAt or outfit.created or outfit.Created

		if typeof(raw) == "DateTime" then
			return raw.UnixTimestamp
		end

		if type(raw) == "number" then
			return raw
		end

		if type(raw) == "string" and raw ~= "" then
			local ok, date = pcall(function()
				return DateTime.fromIsoDate(raw)
			end)

			if ok and date then
				return date.UnixTimestamp
			end

			local year, month, day, hour, minute, second =
				raw:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")

			if year then
				local dateOk, parsed = pcall(function()
					return DateTime.fromUniversalTime(
						tonumber(year),
						tonumber(month),
						tonumber(day),
						tonumber(hour),
						tonumber(minute),
						tonumber(second)
					)
				end)

				if dateOk and parsed then
					return parsed.UnixTimestamp
				end
			end
		end

		return 0
	end

	local results, seen, seenTokens = {}, {}, {}
	local paginationToken = nil
	local page = 1
	local maxPages = 8
	local partial = false
	local statusMessage = nil

	while page <= maxPages do
		remaining = catalogPublicOutfitsRateLimitedUntil - os.clock()

		if remaining > 0 then
			statusMessage = getRateLimitStatus(catalogPublicOutfitsRateLimitedUntil)

			if #results > 0 then
				partial = true
				break
			end

			return nil, "rate_limited", statusMessage
		end

		local url = proxyUrl(
			"avatar",
			"/v2/avatar/users/" .. tostring(userId)
				.. "/outfits?outfitType=Avatar&itemsPerPage=50&isEditable=true"
		)

		if paginationToken and paginationToken ~= "" then
			url ..= "&paginationToken=" .. HttpService:UrlEncode(paginationToken)
		end

		local requestOk, response = pcall(function()
			return HttpService:RequestAsync({
				Url = url,
				Method = "GET",
				Headers = {
					Accept = "application/json",
				},
			})
		end)

		if requestOk and response.StatusCode == 429 then
			local seconds = getRetryAfterSeconds(response)

			catalogPublicOutfitsRateLimitedUntil = os.clock() + seconds
			statusMessage = getRateLimitStatus(catalogPublicOutfitsRateLimitedUntil)

			if #results > 0 then
				partial = true
				break
			end

			return nil, "rate_limited", statusMessage
		end

		if not requestOk or not response.Success then
			statusMessage = "Unavailable, user's outfits are private."

			if #results > 0 then
				partial = true
				break
			end

			return nil, "unavailable", statusMessage
		end

		local decodeOk, payload = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)

		if not decodeOk or type(payload) ~= "table" then
			statusMessage = "Unavailable, user's outfits are private."

			if #results > 0 then
				partial = true
				break
			end

			return nil, "unavailable", statusMessage
		end

		local data = payload.data
			or payload.Data
			or payload.outfits
			or payload.Outfits
			or {}

		if type(data) ~= "table" then
			data = {}
		end

		for _, outfit in ipairs(data) do
			if type(outfit) ~= "table" then
				continue
			end

			local id = tonumber(
				outfit.id
					or outfit.Id
					or outfit.outfitId
					or outfit.OutfitId
			)

			local private = outfit.isPrivate == true
				or outfit.IsPrivate == true
				or outfit.isPublic == false
				or outfit.IsPublic == false

			local editable = outfit.isEditable

			if editable == nil then
				editable = outfit.IsEditable
			end

			local outfitType = outfit.outfitType or outfit.OutfitType
			local isAvatarOutfit = outfitType == nil or tostring(outfitType) == "Avatar"

			if id and id > 0 and id % 1 == 0
				and isAvatarOutfit
				and not private
				and editable ~= false
				and not seen[id] then

				seen[id] = true

				table.insert(results, {
					id = id,
					name = tostring(
						outfit.name
							or outfit.Name
							or ("Outfit " .. tostring(id))
					),
					createdAt = outfitTimestamp(outfit),
					isEditable = true,
					_sourceOrder = #results + 1,
				})
			end
		end

		local nextToken = payload.paginationToken or payload.PaginationToken

		if type(nextToken) ~= "string" or nextToken == "" then
			break
		end

		if seenTokens[nextToken] then
			partial = true
			break
		end

		seenTokens[nextToken] = true

		if page >= maxPages then
			partial = true
			break
		end

		paginationToken = nextToken
		page += 1

		-- Slightly space out paginated requests.
		task.wait(0.5)
	end

	local hasTimestamps = false

	for _, outfit in ipairs(results) do
		if outfit.createdAt > 0 then
			hasTimestamps = true
			break
		end
	end

	if hasTimestamps then
		table.sort(results, function(a, b)
			if a.createdAt ~= b.createdAt then
				return a.createdAt > b.createdAt
			end

			return a._sourceOrder < b._sourceOrder
		end)
	end

	for _, outfit in ipairs(results) do
		outfit._sourceOrder = nil
	end

	return results, partial and "partial" or "ok", statusMessage
end

local function inspectPublicOutfits(plr, name)
	local ok, userId = pcall(function() return Players:GetUserIdFromNameAsync(name) end)
	if not ok or not userId then return "nouser" end
	local lastRequest = publicOutfitsLastRequest[plr] or 0
	if os.clock() - lastRequest < PUBLIC_LOOKUP_COOLDOWN then return "error", "Please wait a moment before searching public outfits again." end
	publicOutfitsLastRequest[plr] = os.clock()
	local canonicalName = name
	pcall(function() canonicalName = Players:GetNameFromUserIdAsync(userId) end)
	local outfits, state, reason = getPublicSavedOutfits(userId)
	if type(outfits) ~= "table" then
		return "error", tostring(reason or state or "Public outfits could not be loaded. The inventory may be private.")
	end
	return "publicOutfits", {
		userId = userId,
		username = canonicalName,
		outfits = outfits,
		partial = state == "partial",
		statusMessage = reason,
	}
end

local function inspectPublicAvatar(plr, name, requestInventory, requestId)
	local ok, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not ok or not userId then
		return "nouser"
	end
	local canonicalName = name
	pcall(function() canonicalName = Players:GetNameFromUserIdAsync(userId) end)

	if requestInventory then
		local lastRequest = publicInventoryLastRequest[plr] or 0
		if os.clock() - lastRequest < PUBLIC_LOOKUP_COOLDOWN then
			return "error", "Please wait a moment before searching another public inventory."
		end
		publicInventoryLastRequest[plr] = os.clock()
		local inventory, inventoryState, inventoryError = getPublicInventory(userId, function(pageItems)
			if requestId and requestId > 0 and plr.Parent then
				remote:FireClient(plr, "Progress", requestId, "publicInventoryPage", {
					userId = userId,
					username = canonicalName,
					items = pageItems,
				})
			end
		end)

		if type(inventory) == "table" then
			return "publicInventory", {
				userId = userId,
				username = canonicalName,
				itemCount = #inventory,
				partial = inventoryState == "partial",
				statusMessage = inventoryError,
			}
		end

		if inventoryState == "rate_limited" then
			return "error", inventoryError
		end
		local descOk, desc = pcall(function() return getUserDescription(userId) end)
		local wornItems = {}
		if descOk and desc then
			local itemsOk, items = pcall(collectEquippedItems, desc)
			if itemsOk and type(items) == "table" then wornItems = items end
			desc:Destroy()
		end
		return "publicAvatar", {
			userId = userId,
			username = canonicalName,
			items = wornItems,
			inventoryPrivate = true,
			warning = "Unavailable, user's inventory is private.",
		}
	end

	local descOk, desc = pcall(function() return getUserDescription(userId) end)
	if not descOk or not desc then
		return "error", "could not read that player's public avatar: " .. tostring(desc)
	end
	local itemsOk, items = pcall(collectEquippedItems, desc)
	desc:Destroy()
	if not itemsOk then
		return "error", "could not read the avatar's worn items: " .. tostring(items)
	end
	return "publicAvatar", { userId = userId, username = canonicalName, items = items }
end

local function unequipAll(plr)
	local hum = getHumanoid(plr)
	if not hum then
		return "error", "character not ready"
	end
	local desc, descError = getAppliedDescription(hum)
	if not desc then
		return "error", descError
	end

	for _, property in pairs(SINGLE) do
		local ok, err = pcall(function() desc[property] = 0 end)
		if not ok then
			warn("[CatalogServer] couldn't clear avatar slot", property, err)
		end
	end
	for _, property in pairs(MULTI) do
		desc[property] = ""
	end
	local okAccessories, accessoryError = pcall(function() desc:SetAccessories({}, true) end)
	if not okAccessories then
		desc:Destroy()
		return "error", "could not clear layered accessories: " .. tostring(accessoryError)
	end
	pcall(function() desc:SetEquippedEmotes({}) end)

	local applied, currentIds, currentItems = apply(plr, hum, desc)
	if not applied then
		return "error", currentIds
	end
	local remaining = type(currentItems) == "table" and #currentItems or 0
	local detail = {
		equippedIds = currentIds or {},
		equippedItems = currentItems or {},
		remaining = remaining,
	}
	if remaining > 0 then
		warn("[CatalogServer] UnequipAll left", remaining, "supported assets on", plr.Name)
		return "unequipPartial", detail
	end
	return "unequippedAll", detail
end

local function clearAccessories(plr)
	local hum = getHumanoid(plr)
	if not hum then
		return "error", "character not ready"
	end

	local desc, descError = getAppliedDescription(hum)
	if not desc then
		return "error", descError
	end
	for _, property in pairs(MULTI) do
		desc[property] = ""
	end
	desc:SetAccessories({}, true)

	local ok, currentIds, currentItems = apply(plr, hum, desc)
	if not ok then
		return "error", currentIds
	end
	return "cleared", { equippedIds = currentIds, equippedItems = currentItems }
end

local function setSkin(plr, color)
	local hum = getHumanoid(plr)
	if not hum then
		return "error", "character not ready"
	end

	local desc, descError = getAppliedDescription(hum)
	if not desc then
		return "error", descError
	end
	desc.HeadColor = color
	desc.TorsoColor = color
	desc.LeftArmColor = color
	desc.RightArmColor = color
	desc.LeftLegColor = color
	desc.RightLegColor = color

	local ok, currentIds, currentItems = apply(plr, hum, desc)
	if not ok then
		return "error", currentIds
	end
	return "skin", { equippedIds = currentIds, equippedItems = currentItems }
end

local BODY_COLOR_PROPERTIES = {
	Head = "HeadColor",
	Torso = "TorsoColor",
	LeftArm = "LeftArmColor",
	RightArm = "RightArmColor",
	LeftLeg = "LeftLegColor",
	RightLeg = "RightLegColor",
}

local function setSkinPart(plr, partName, color)
	local property = BODY_COLOR_PROPERTIES[partName]
	if not property then
		return "error", "unsupported body color target"
	end
	if typeof(color) ~= "Color3"
		or color.R ~= color.R or color.G ~= color.G or color.B ~= color.B
		or color.R < 0 or color.R > 1
		or color.G < 0 or color.G > 1
		or color.B < 0 or color.B > 1 then
		return "error", "invalid color"
	end
	local hum = getHumanoid(plr)
	if not hum then
		return "error", "character not ready"
	end
	local desc, descError = getAppliedDescription(hum)
	if not desc then
		return "error", descError
	end
	desc[property] = color
	local ok, currentIds, currentItems = apply(plr, hum, desc)
	if not ok then
		return "error", currentIds
	end
	return "skinPart", { part = partName, equippedIds = currentIds, equippedItems = currentItems }
end

local AVATAR_SCALE_LIMITS = {
	HeightScale = { 0.90, 1.05 },
	WidthScale = { 0.70, 1.00 },
	HeadScale = { 0.95, 1.00 },
	BodyTypeScale = { 0.00, 1.00 },
	ProportionScale = { 0.00, 1.00 },
	DepthScale = { 0.50, 1.50 },
}

local function setAvatarScales(plr, values)
	if typeof(values) ~= "table" then return "error", "invalid scale values" end
	local hum = getHumanoid(plr)
	if not hum then return "error", "character not ready" end
	local desc, descError = getAppliedDescription(hum)
	if not desc then return "error", descError end
	local updated = {}
	for property, limits in pairs(AVATAR_SCALE_LIMITS) do
		local raw = values[property]
		if raw ~= nil then
			local value = tonumber(raw)
			if not value or value ~= value or math.abs(value) == math.huge then
				desc:Destroy()
				return "error", "invalid value for " .. property
			end
			value = math.clamp(value, limits[1], limits[2])
			local ok, err = pcall(function() desc[property] = value end)
			if not ok then
				desc:Destroy()
				return "error", "could not set " .. property .. ": " .. tostring(err)
			end
			updated[property] = value
		end
	end
	if next(updated) == nil then
		desc:Destroy()
		return "error", "no valid scale values were supplied"
	end
	local applied, currentIds, currentItems = apply(plr, hum, desc)
	if not applied then return "error", currentIds end
	return "scales", {
		equippedIds = currentIds,
		equippedItems = currentItems,
		bodyScales = updated,
	}
end

local function validList(list)
	if typeof(list) ~= "table" or #list == 0 or #list > 40 then
		return false
	end
	for index = 1, #list do
		local entry = list[index]
		if typeof(entry) ~= "table" or not isId(entry[1]) or typeof(entry[2]) ~= "string" or #entry[2] > 64 then
			return false
		end
	end
	return true
end

local function sendResult(plr, requestId, code, detail)
	if plr.Parent then
		remote:FireClient(plr, "Result", requestId, code or "error", detail)
	end
end

remote.OnServerEvent:Connect(function(plr, action, a, b, requestId)
	if typeof(action) ~= "string" then
		return
	end
	if typeof(requestId) ~= "number" or requestId % 1 ~= 0 or requestId < 1 then
		requestId = 0
	end

	if busy[plr] then
		sendResult(plr, requestId, "busy")
		return
	end
	busy[plr] = true

	local ok, code, detail = pcall(function()
		if action == "Snapshot" then
			return getAvatarSnapshot(plr)
		elseif action == "Unequip" and isId(a) then
			return removeAssetById(plr, a)
		elseif action == "Wear" and isId(a) and typeof(b) == "string" and #b <= 64 then
			return wear(plr, a, b)
		elseif action == "WearAuto" and isId(a) then
			return wearAuto(plr, a)
		elseif action == "Many" and validList(a) then
			return wearMany(plr, a)
		elseif action == "Outfit" and isId(a) then
			return wearOutfit(plr, a)
		elseif action == "Bundle" and isId(a) then
			return wearBundle(plr, a)
		elseif action == "Reset" then
			return reset(plr)
		elseif action == "Clear" then
			return clearAccessories(plr)
		elseif action == "UnequipAll" then
			return unequipAll(plr)
		elseif action == "Skin" and typeof(a) == "Color3" then
			return setSkin(plr, a)
		elseif action == "SkinPart" and typeof(a) == "string" and typeof(b) == "Color3" then
			return setSkinPart(plr, a, b)
		elseif action == "AvatarScale" and typeof(a) == "table" then
			return setAvatarScales(plr, a)
		elseif action == "User" and typeof(a) == "string" and #a >= 3 and #a <= 20 and string.match(a, "^[%w_]+$") then
			return copyUser(plr, a)
		elseif action == "InspectUser" and typeof(a) == "string" and #a >= 3 and #a <= 20 and string.match(a, "^[%w_]+$") then
			return inspectPublicAvatar(plr, a, false)
		elseif action == "PublicInventory" and typeof(a) == "string" and #a >= 3 and #a <= 20 and string.match(a, "^[%w_]+$") then
			return inspectPublicAvatar(plr, a, true, requestId)
		elseif action == "PublicOutfits" and typeof(a) == "string" and #a >= 3 and #a <= 20 and string.match(a, "^[%w_]+$") then
			return inspectPublicOutfits(plr, a)
		end
		return "error", "invalid request: " .. action
	end)

	if not ok then
		detail = tostring(code)
		code = "error"
	end
	if code == "error" then
		warn("[CatalogServer] " .. plr.Name .. " / " .. action .. " failed: " .. tostring(detail))
	end

	busy[plr] = nil
	sendResult(plr, requestId, code, detail)
end)

local function setupPlayer(plr)
	plr.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 10)
		local current = saved[plr]
		if not hum or not current or not plr.Parent then
			return
		end

		local desc
		local cloneOk, cloneResult = pcall(function()
			return current:Clone()
		end)
		if cloneOk then
			desc = cloneResult
		end
		if not desc then
			warn("[CatalogServer] couldn't clone saved avatar for", plr.Name)
			return
		end

		local ok, err = pcall(function()
			callHumanoidAppearanceMethod(hum, "ApplyDescriptionReset", desc)
		end)
		if not ok then
			ok, err = pcall(function()
				callHumanoidAppearanceMethod(hum, "ApplyDescription", desc)
			end)
		end
		desc:Destroy()
		if not ok then
			warn("[CatalogServer] respawn apply failed: " .. tostring(err))
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, plr in ipairs(Players:GetPlayers()) do
	setupPlayer(plr)
end

Players.PlayerRemoving:Connect(function(plr)
	if saved[plr] then
		saved[plr]:Destroy()
	end
	saved[plr] = nil
	busy[plr] = nil
	profileBackgroundCache[plr] = nil
	publicInventoryLastRequest[plr] = nil
	publicOutfitsLastRequest[plr] = nil
end)
