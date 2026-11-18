local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local AssetService = game:GetService("AssetService")

local EVENT_NAME = "CatalogBulkPurchaseEvent"
local remote = ReplicatedStorage:FindFirstChild(EVENT_NAME)
if remote and not remote:IsA("RemoteEvent") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = EVENT_NAME
	remote.Parent = ReplicatedStorage
end

if remote:GetAttribute("BulkPurchaseHandlerV239") then return end
remote:SetAttribute("BulkPurchaseHandlerV239", true)

local ASSET_PRODUCT_TYPE = Enum.MarketplaceProductType.AvatarAsset
local BUNDLE_PRODUCT_TYPE = Enum.MarketplaceProductType.AvatarBundle
local ALLOWED_TYPES = {
	[ASSET_PRODUCT_TYPE] = true,
	[BUNDLE_PRODUCT_TYPE] = true,
}

local MAX_SAFE_ROBLOX_ID = 9007199254740991
local BOLD_ANIMATION_BUNDLE_ID = 331856
local BLOCKED_BUNDLE_IDS = { [331465] = true }
local MAX_ITEMS = 20
local MAX_CANDIDATES = 48
local WORKER_COUNT = 5
local DISCOVERY_TIMEOUT = 12
local SEARCH_CACHE_SECONDS = 600
local processing = {}
local bundleSearchCache = {}
local bundleDetailsCache = {}

local ANIMATION_TYPES = {
	ClimbAnimation = true,
	FallAnimation = true,
	IdleAnimation = true,
	JumpAnimation = true,
	RunAnimation = true,
	SwimAnimation = true,
	WalkAnimation = true,
	EmoteAnimation = true,
	MoodAnimation = true,
}

local BODY_TYPES = {
	Head = true,
	DynamicHead = true,
	Torso = true,
	LeftArm = true,
	RightArm = true,
	LeftLeg = true,
	RightLeg = true,
}

local SHOE_TYPES = {
	LeftShoeAccessory = true,
	RightShoeAccessory = true,
	LeftShoe = true,
	RightShoe = true,
}

local ASSET_TYPE_IDS = {
	[17] = "Head",
	[27] = "Torso",
	[28] = "RightArm",
	[29] = "LeftArm",
	[30] = "LeftLeg",
	[31] = "RightLeg",
	[48] = "ClimbAnimation",
	[50] = "FallAnimation",
	[51] = "IdleAnimation",
	[52] = "JumpAnimation",
	[53] = "RunAnimation",
	[54] = "SwimAnimation",
	[55] = "WalkAnimation",
	[61] = "EmoteAnimation",
	[70] = "LeftShoeAccessory",
	[71] = "RightShoeAccessory",
	[78] = "MoodAnimation",
	[79] = "DynamicHead",
}

local function normalizeName(value)
	local name = tostring(value or "")
	name = name:gsub("^Enum%.AvatarAssetType%.", "")
	name = name:gsub("^AvatarAssetType%.", "")
	name = name:gsub("^Enum%.BundleType%.", "")
	name = name:gsub("^BundleType%.", "")
	return name:match("([%w_]+)$") or name
end

local function normalizeBundleType(value)
	local name = tostring(value or "")
	name = name:gsub("^Enum%.BundleType%.", "")
	name = name:gsub("^BundleType%.", "")
	return name:match("([%w_]+)$") or name
end

local function getAssetCategory(typeName)
	typeName = normalizeName(typeName)
	if typeName == "" or typeName == "Item" or typeName == "Unknown" or typeName == "Asset" then return nil end
	if ANIMATION_TYPES[typeName] or typeName:find("Animation", 1, true) then return "Animation" end
	if BODY_TYPES[typeName] then return "Body" end
	if SHOE_TYPES[typeName] then return "Shoes" end
	return typeName
end

local function getBundleCategory(bundleType, bundleName, bundleId)
	local normalizedId = tonumber(bundleId)
	local normalizedName = tostring(bundleName or ""):lower()
	if normalizedId == BOLD_ANIMATION_BUNDLE_ID or normalizedName:find("bold animation", 1, true) then
		return "Animation"
	end
	local value = normalizeBundleType(bundleType):lower()
	if value:find("animation", 1, true) then return "Animation" end
	if value:find("dynamichead", 1, true) or value:find("bodypart", 1, true) then return "Body" end
	if value:find("shoe", 1, true) then return "Shoes" end
	return nil
end

local function validId(value)
	if type(value) ~= "string" or #value < 1 or #value > 16 then return false end
	if not value:match("^%d+$") then return false end
	local numeric = tonumber(value)
	return numeric ~= nil and numeric > 0 and numeric <= MAX_SAFE_ROBLOX_ID
end

local function send(player, success, result, phase)
	if player and player.Parent == Players then
		remote:FireClient(player, success, result, phase)
	end
end

local function callAvatarEditor(method, ...)
	local args = table.pack(...)
	local asyncMethod
	pcall(function()
		asyncMethod = AvatarEditorService[method .. "Async"]
	end)
	if type(asyncMethod) == "function" then
		local ok, result = pcall(asyncMethod, AvatarEditorService, table.unpack(args, 1, args.n))
		if ok then return true, result end
	end

	local legacyMethod
	pcall(function()
		legacyMethod = AvatarEditorService[method]
	end)
	if type(legacyMethod) == "function" then
		local ok, result = pcall(legacyMethod, AvatarEditorService, table.unpack(args, 1, args.n))
		if ok then return true, result end
		return false, result
	end
	return false, "AvatarEditorService method unavailable: " .. tostring(method)
end

local function runWorkers(items, workerCount, callback, deadline)
	if #items == 0 then return true end
	local nextIndex = 0
	local finishedWorkers = 0
	local count = math.min(workerCount, #items)

	for _ = 1, count do
		task.spawn(function()
			while os.clock() < deadline do
				nextIndex += 1
				local index = nextIndex
				if index > #items then break end
				pcall(callback, items[index], index)
			end
			finishedWorkers += 1
		end)
	end

	while finishedWorkers < count and os.clock() < deadline do
		task.wait(0.05)
	end
	return finishedWorkers == count
end

local function readCatalogPage(pages)
	local ok, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	return ok and type(page) == "table" and page or nil
end

local function getBundlesForAsset(assetId)
	local now = os.clock()
	local cached = bundleSearchCache[assetId]
	if cached and cached.expires > now then
		return cached.items
	end

	local ok, pages = callAvatarEditor("GetBundlesByAssetId", assetId, 100)
	if not ok or not pages then return nil end
	local page = readCatalogPage(pages)
	if not page then return nil end

	local items = {}
	for _, entry in ipairs(page) do
		if type(entry) == "table" then
			local id = tonumber(entry.Id or entry.id or entry.BundleId)
			if id and id > 0 and not BLOCKED_BUNDLE_IDS[id] then
				table.insert(items, {
					id = id,
					name = entry.Name or entry.name,
					bundleType = entry.BundleType or entry.bundleType,
					searchDetails = entry,
				})
			end
		end
	end

	bundleSearchCache[assetId] = {
		expires = now + SEARCH_CACHE_SECONDS,
		items = items,
	}
	return items
end

local function parseBundleContents(details)
	local contents = details and (details.BundledItems or details.Items)
	if type(contents) ~= "table" then return nil end

	local assets = {}
	local assetTypes = {}
	for _, entry in ipairs(contents) do
		if type(entry) == "table" then
			local nested = type(entry.Item) == "table" and entry.Item
				or (type(entry.Asset) == "table" and entry.Asset or entry)
			local itemType = tostring(entry.Type or entry.ItemType or nested.Type or "Asset"):lower()
			local id = tonumber(entry.Id or entry.AssetId or nested.Id or nested.AssetId)
			if id and id > 0 and not itemType:find("bundle", 1, true)
				and (itemType == "asset" or itemType:find("asset", 1, true)) then
				assets[id] = true
				local assetType = normalizeName(entry.AssetType or entry.AssetTypeName
					or nested.AssetType or nested.AssetTypeName)
				if assetType ~= "" then assetTypes[id] = assetType end
			end
		end
	end

	if next(assets) == nil then return nil end
	return assets, assetTypes
end

local function getBundleDetails(bundleId, searchDetails, fallbackBundleType)
	if BLOCKED_BUNDLE_IDS[tonumber(bundleId)] then return nil end
	local cached = bundleDetailsCache[bundleId]
	if cached then return cached end

	local details = {}
	if type(searchDetails) == "table" then
		for key, value in pairs(searchDetails) do
			if value ~= nil then details[key] = value end
		end
	end

	local contents = details.BundledItems or details.Items
	if type(contents) ~= "table" then
		local ok, result = callAvatarEditor("GetItemDetails", bundleId, Enum.AvatarItemType.Bundle)
		if ok and type(result) == "table" then
			for key, value in pairs(result) do
				if value ~= nil then details[key] = value end
			end
			contents = details.BundledItems or details.Items
		end
	end

	local assets, assetTypes = parseBundleContents(details)
	if not assets then
		local ok, result = pcall(function()
			return AssetService:GetBundleDetailsAsync(bundleId)
		end)
		if ok and type(result) == "table" then
			for key, value in pairs(result) do
				if value ~= nil then details[key] = value end
			end
			assets, assetTypes = parseBundleContents(details)
		end
	end
	if not assets then return nil end

	local result = {
		id = bundleId,
		name = tostring(details.Name or details.name or ("Bundle " .. tostring(bundleId))),
		bundleType = normalizeBundleType(details.BundleType or details.bundleType or fallbackBundleType),
		assets = assets,
		assetTypes = assetTypes,
	}
	bundleDetailsCache[bundleId] = result
	return result
end

local function discoverBundleCandidates(assetIds, deadline, requestedAssetTypes)
	local candidatesById = {}
	local jobs = table.clone(assetIds)
	local hasHeadAsset = false
	local boldAnimationSources = {}
	for _, assetId in ipairs(assetIds) do
		local assetType = normalizeName(requestedAssetTypes[assetId])
		if getAssetCategory(assetType) == "Animation" then
			boldAnimationSources[assetId] = true
		end
		if assetType == "Head" or assetType == "DynamicHead"
			or assetId == 14488197116 or assetId == 10647852134 then
			hasHeadAsset = true
		end
	end
	if next(boldAnimationSources) ~= nil then
		candidatesById[BOLD_ANIMATION_BUNDLE_ID] = {
			id = BOLD_ANIMATION_BUNDLE_ID,
			name = "Bold Animation Pack",
			bundleType = "Animations",
			sourceIds = boldAnimationSources,
			priority = true,
		}
	end
	if hasHeadAsset then
		local sourceIds = {}
		for _, assetId in ipairs(assetIds) do
			local assetType = normalizeName(requestedAssetTypes[assetId])
			if assetType == "Head" or assetType == "DynamicHead"
				or assetId == 14488197116 or assetId == 10647852134 then
				sourceIds[assetId] = true
			end
		end
		candidatesById[1952] = {
			id = 1952,
			name = "Faceless",
			bundleType = "DynamicHead",
			sourceIds = sourceIds,
			priority = true,
		}
	end

	local completed = runWorkers(jobs, WORKER_COUNT, function(assetId)
		local bundles = getBundlesForAsset(assetId)
		if type(bundles) ~= "table" then return end
		for _, bundle in ipairs(bundles) do
			if not BLOCKED_BUNDLE_IDS[tonumber(bundle.id)] then
				local existing = candidatesById[bundle.id]
				if not existing then
					existing = {
						id = bundle.id,
						name = bundle.name,
						bundleType = bundle.bundleType,
						searchDetails = bundle.searchDetails,
						sourceIds = {},
					}
					candidatesById[bundle.id] = existing
				elseif not existing.searchDetails or not (existing.searchDetails.BundledItems or existing.searchDetails.Items) then
					if type(bundle.searchDetails) == "table" then existing.searchDetails = bundle.searchDetails end
					if bundle.bundleType then existing.bundleType = bundle.bundleType end
				end
				existing.sourceIds[assetId] = true
			end
		end
	end, deadline)

	if not completed then return nil end

	local candidates = {}
	for _, candidate in pairs(candidatesById) do
		local sourceCount = 0
		for _ in pairs(candidate.sourceIds) do sourceCount += 1 end
		if sourceCount > 0 then
			candidate.sourceCount = sourceCount
			table.insert(candidates, candidate)
		end
	end

	table.sort(candidates, function(a, b)
		if a.priority ~= b.priority then return a.priority == true end
		if a.sourceCount ~= b.sourceCount then return a.sourceCount > b.sourceCount end
		return a.id < b.id
	end)
	while #candidates > MAX_CANDIDATES do table.remove(candidates) end
	return candidates
end

local function resolveCandidates(candidates, requestedAssets, requestedAssetTypes, deadline)
	local resolved = {}
	local completed = runWorkers(candidates, WORKER_COUNT, function(candidate)
		if BLOCKED_BUNDLE_IDS[tonumber(candidate.id)] then return end
		local bundle = getBundleDetails(candidate.id, candidate.searchDetails, candidate.bundleType)
		if not bundle then return end

		local covered = {}
		for assetId in pairs(bundle.assets) do
			if requestedAssets[assetId] then
				covered[assetId] = true
			end
		end

		local bundleCategory = getBundleCategory(bundle.bundleType, bundle.name, bundle.id)
		local count = 0
		local coreCount = 0
		local expectedCategory
		local typeAllowed = true
		for assetId in pairs(covered) do
			count += 1
			local assetType = normalizeName(bundle.assetTypes[assetId] or requestedAssetTypes[assetId])
			local category = getAssetCategory(assetType)
			local auxiliaryMood = bundleCategory == "Body" and assetType == "MoodAnimation"
			if not auxiliaryMood then
				category = category or bundleCategory
				if not category then
					typeAllowed = false
					break
				end
				if bundleCategory and category ~= bundleCategory then
					typeAllowed = false
					break
				end
				if expectedCategory and expectedCategory ~= category then
					typeAllowed = false
					break
				end
				expectedCategory = category
				coreCount += 1
			end
		end

		if not bundleCategory then bundleCategory = expectedCategory end
		local minimumCount = bundleCategory and 1 or 2
		if bundleCategory and coreCount < minimumCount then typeAllowed = false end
		if typeAllowed and count >= minimumCount then
			table.insert(resolved, {
				id = bundle.id,
				name = bundle.name,
				bundleType = bundle.bundleType,
				category = bundleCategory or expectedCategory,
				covered = covered,
				count = count,
			})
		end
	end, deadline)

	if not completed then return nil end
	table.sort(resolved, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.id < b.id
	end)
	return resolved
end

local function mergeBundles(requestedLines, requestedAssetTypes)
	local requestedAssets = {}
	local explicitBundles = {}
	local assetIds = {}

	for _, line in ipairs(requestedLines) do
		if line.Type == ASSET_PRODUCT_TYPE then
			local id = tonumber(line.Id)
			if id then
				requestedAssets[id] = true
				table.insert(assetIds, id)
			end
		elseif line.Type == BUNDLE_PRODUCT_TYPE then
			local id = tonumber(line.Id)
			if id then explicitBundles[id] = true end
		end
	end

	if #assetIds == 0 then
		local result = {}
		for _, line in ipairs(requestedLines) do
			table.insert(result, { Type = line.Type, Id = tostring(line.Id) })
		end
		return result, 0
	end

	local deadline = os.clock() + DISCOVERY_TIMEOUT
	local candidates = discoverBundleCandidates(assetIds, deadline, requestedAssetTypes)
	if not candidates or #candidates == 0 then
		local result = {}
		for _, line in ipairs(requestedLines) do
			table.insert(result, { Type = line.Type, Id = tostring(line.Id) })
		end
		return result, 0
	end

	local resolved = resolveCandidates(candidates, requestedAssets, requestedAssetTypes, deadline)
	if not resolved then
		local result = {}
		for _, line in ipairs(requestedLines) do
			table.insert(result, { Type = line.Type, Id = tostring(line.Id) })
		end
		return result, 0
	end

	local usedIds = {}
	local selectedBundles = {}
	local bundleSeen = {}
	for bundleId in pairs(explicitBundles) do
		if not BLOCKED_BUNDLE_IDS[tonumber(bundleId)] then
			bundleSeen[bundleId] = true
			local bundle = getBundleDetails(bundleId, nil)
			if bundle then
				for assetId in pairs(bundle.assets) do
					if requestedAssets[assetId] then usedIds[assetId] = true end
				end
			end
		end
	end

	local mergedCount = 0
	for _, bundle in ipairs(resolved) do
		if not BLOCKED_BUNDLE_IDS[tonumber(bundle.id)] then
			local available = {}
			for assetId in pairs(bundle.covered) do
				if requestedAssets[assetId] and not usedIds[assetId] then
					table.insert(available, assetId)
				end
			end
			local minimumCount = bundle.category and 1 or 2
			if #available >= minimumCount then
				local compatible = true
				if bundle.category ~= "Animation" then
					for assetId in pairs(bundle.covered) do
						if requestedAssets[assetId] and usedIds[assetId] then
							compatible = false
							break
						end
					end
				end
				if compatible and not bundleSeen[bundle.id] then
					bundleSeen[bundle.id] = true
					for _, assetId in ipairs(available) do usedIds[assetId] = true end
					table.insert(selectedBundles, {
						Type = BUNDLE_PRODUCT_TYPE,
						Id = tostring(bundle.id),
					})
					mergedCount += 1
				end
			end
		end
	end

	local result = {}
	local seen = {}
	for _, line in ipairs(requestedLines) do
		local id = tonumber(line.Id)
		local coveredAsset = line.Type == ASSET_PRODUCT_TYPE and id and usedIds[id]
		local blockedBundle = line.Type == BUNDLE_PRODUCT_TYPE and id and BLOCKED_BUNDLE_IDS[id]
		local key = tostring(line.Type) .. ":" .. tostring(line.Id)
		if not coveredAsset and not blockedBundle and not seen[key] then
			seen[key] = true
			table.insert(result, { Type = line.Type, Id = tostring(line.Id) })
		end
	end

	for _, line in ipairs(selectedBundles) do
		local key = tostring(line.Type) .. ":" .. tostring(line.Id)
		if not seen[key] then
			seen[key] = true
			table.insert(result, line)
		end
	end

	return result, mergedCount
end

remote.OnServerEvent:Connect(function(player, requestedItems)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then return end

	if processing[player] then
		send(player, false, "A bulk purchase request is already being prepared.", "busy")
		return
	end

	if typeof(requestedItems) ~= "table" then
		send(player, false, "The purchase list is invalid.", "error")
		return
	end

	local requestedCount = #requestedItems
	if requestedCount < 1 or requestedCount > MAX_ITEMS then
		send(player, false, "Select between 1 and 20 items.", "error")
		return
	end

	local lineItems = {}
	local seen = {}
	for index = 1, requestedCount do
		local entry = requestedItems[index]
		if typeof(entry) ~= "table" or not ALLOWED_TYPES[entry.Type] or not validId(entry.Id) then
			send(player, false, "The purchase list contained an invalid item.", "error")
			return
		end

		local numericId = tonumber(entry.Id)
		if numericId and BLOCKED_BUNDLE_IDS[numericId] then
			send(player, false, "ID 331465 is a duplicate Bold Animation bundle and is blocked. Use bundle 331856 instead.", "error")
			return
		end

		local id = tostring(entry.Id)
		local key = tostring(entry.Type) .. ":" .. id
		if not seen[key] then
			seen[key] = true
			table.insert(lineItems, {
				Type = entry.Type,
				Id = id,
				AssetType = entry.Type == ASSET_PRODUCT_TYPE and normalizeName(entry.AssetType) or nil,
			})
		end
	end

	if #lineItems < 1 or #lineItems > MAX_ITEMS then
		send(player, false, "The purchase list must contain between 1 and 20 unique items.", "error")
		return
	end

	processing[player] = true
	local requestAssetTypes = {}
	for _, line in ipairs(lineItems) do
		if line.Type == ASSET_PRODUCT_TYPE then
			requestAssetTypes[tonumber(line.Id)] = line.AssetType
		end
	end

	local mergeOk, mergedItems, mergedCount = pcall(mergeBundles, lineItems, requestAssetTypes)
	if not mergeOk or type(mergedItems) ~= "table" then
		warn("[CatalogBulkPurchase] Bundle discovery failed for " .. player.Name .. ": " .. tostring(mergedItems))
		mergedItems = {}
		for _, line in ipairs(lineItems) do
			table.insert(mergedItems, { Type = line.Type, Id = tostring(line.Id) })
		end
		mergedCount = 0
	end

	if #mergedItems < 1 or #mergedItems > MAX_ITEMS then
		processing[player] = nil
		send(player, false, "The merged purchase list is invalid. Try again.", "error")
		return
	end

	for _, line in ipairs(mergedItems) do
		if tonumber(line.Id) == 331465 then
			processing[player] = nil
			send(player, false, "ID 331465 is blocked. Only Bold Animation bundle 331856 is supported.", "error")
			return
		end
	end

	if player.Parent ~= Players then
		processing[player] = nil
		return
	end

	local promptOk, promptError = pcall(function()
		MarketplaceService:PromptBulkPurchase(player, mergedItems, {})
	end)
	processing[player] = nil

	if not promptOk then
		warn("[CatalogBulkPurchase] Purchase prompt failed for " .. player.Name .. ": " .. tostring(promptError))
		send(player, false, tostring(promptError), "error")
		return
	end

	send(player, true, #mergedItems, "opened")
end)

Players.PlayerRemoving:Connect(function(player)
	processing[player] = nil
end)
