local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local AvatarEditorService = game:GetService("AvatarEditorService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("AvatarEvent")
local rigSwitchRemote = ReplicatedStorage:WaitForChild("AvatarRigSwitch")
local H = {}

function H.enumItem(enum, name)
	local ok, value = pcall(function() return enum[name] end)
	return ok and value or nil
end

function H.enumList(enum, names)
	local result = {}
	for _, name in ipairs(names) do
		local value = H.enumItem(enum, name)
		if value then table.insert(result, value) end
	end
	return result
end
H.apiState = {
	active = 0,
	maxConcurrent = 6,
	lastPrune = 0,
	productCache = {},
	productPending = {},
	detailsCache = {},
	detailsPending = {},
}

function H.withApiSlot(callback)
	local state = H.apiState
	while state.active >= state.maxConcurrent do task.wait(0.03) end
	state.active += 1
	local ok, result = pcall(callback)
	state.active -= 1
	if not ok then error(result, 0) end
	return result
end

function H.cachedApiCall(cache, pending, key, ttl, callback)
	local state = H.apiState
	local now = os.clock()
	if now >= state.lastPrune then
		state.lastPrune = now + 60
		for cacheKey, entry in pairs(state.productCache) do
			if entry.expires <= now then state.productCache[cacheKey] = nil end
		end
		for cacheKey, entry in pairs(state.detailsCache) do
			if entry.expires <= now then state.detailsCache[cacheKey] = nil end
		end
	end
	local cached = cache[key]
	if cached and cached.expires > now then
		if not cached.ok then error(cached.value, 0) end
		return type(cached.value) == "table" and table.clone(cached.value) or cached.value
	end
	local waiting = pending[key]
	if waiting then
		while not waiting.done do task.wait() end
		if not waiting.ok then error(waiting.value, 0) end
		return type(waiting.value) == "table" and table.clone(waiting.value) or waiting.value
	end
	local request = { done = false }
	pending[key] = request
	local ok, result = pcall(callback)
	request.ok = ok
	request.value = result
	request.done = true
	pending[key] = nil
	cache[key] = { ok = ok, value = result, expires = os.clock() + (ok and ttl or 2) }
	if not ok then error(result, 0) end
	return type(result) == "table" and table.clone(result) or result
end

function H.callAES(method, ...)
	local args = table.pack(...)
	local function fetch()
		return H.withApiSlot(function()
			local ok, asyncMethod = pcall(function() return AvatarEditorService[method .. "Async"] end)
			if ok and type(asyncMethod) == "function" then
				local worked, result = pcall(asyncMethod, AvatarEditorService, table.unpack(args, 1, args.n))
				if worked then return result end
			end
			local directOk, directMethod = pcall(function() return AvatarEditorService[method] end)
			if directOk and type(directMethod) == "function" then
				return directMethod(AvatarEditorService, table.unpack(args, 1, args.n))
			end
			error("AvatarEditorService method is unavailable: " .. tostring(method))
		end)
	end
	if method == "GetItemDetails" and args.n >= 2 then
		local itemId = tostring(args[1])
		local itemKind = tostring(args[2])
		local ttl = args[2] == Enum.AvatarItemType.Bundle and 120 or 35
		return H.cachedApiCall(H.apiState.detailsCache, H.apiState.detailsPending,
			itemKind .. ":" .. itemId, ttl, fetch)
	end
	return fetch()
end

function H.getProductInfo(assetId, infoType)
	local key = tostring(infoType) .. ":" .. tostring(assetId)
	return H.cachedApiCall(H.apiState.productCache, H.apiState.productPending, key, 18, function()
		return H.withApiSlot(function()
			local memberOk, asyncMethod = pcall(function() return MarketplaceService.GetProductInfoAsync end)
			if memberOk and type(asyncMethod) == "function" then
				local ok, result = pcall(asyncMethod, MarketplaceService, assetId, infoType)
				if ok then return result end
			end
			return MarketplaceService:GetProductInfo(assetId, infoType)
		end)
	end)
end

H.assetTypeNameByValue = (function()
	local map = {}
	for _, item in ipairs(Enum.AvatarAssetType:GetEnumItems()) do
		map[item.Value] = item.Name
	end
	return map
end)()

function H.assetTypeName(value)
	if typeof(value) == "EnumItem" then return value.Name end
	if type(value) == "number" then
		if value == 92 then return "AvatarBackground" end
		return H.assetTypeNameByValue[value]
	elseif type(value) == "string" then
		local normalized = value:gsub("^Enum%.AvatarAssetType%.", ""):gsub("^AvatarAssetType%.", "")
		if normalized == "92" then return "AvatarBackground" end
		return normalized
	end
	return nil
end
function H.isBundle(item)
	local itemType = item and item.ItemType
	return itemType == Enum.AvatarItemType.Bundle or tostring(itemType):find("Bundle", 1, true) ~= nil
end

function H.comma(number)
	local value = tostring(math.floor(number))
	return (value:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function H.prettyType(name)
	return name and name:gsub("(%l)(%u)", "%1 %2") or ""
end
function H.trim(value)
	return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function H.bindLongPressDetails(button, callback)
	local touchState = { input = nil, startPosition = nil, fired = false, token = 0 }
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		touchState.token += 1
		local token = touchState.token
		touchState.input = input
		touchState.startPosition = input.Position
		touchState.fired = false
		task.delay(0.58, function()
			if touchState.token ~= token or touchState.input ~= input or not button.Parent then return end
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if (input.Position - touchState.startPosition).Magnitude > 18 then return end
			touchState.fired = true
			callback()
		end)
	end)
	button.InputEnded:Connect(function(input)
		if input ~= touchState.input then return end
		touchState.input = nil
		touchState.token += 1
		if touchState.fired then

			task.delay(0.22, function() touchState.fired = false end)
		end
	end)
	return function()
		if touchState.fired then
			touchState.fired = false
			return true
		end
		return false
	end
end

local TABS = {}
local INVENTORY_LAYERED_TYPES = {
	TShirtAccessory = true, ShirtAccessory = true, PantsAccessory = true,
	JacketAccessory = true, SweaterAccessory = true, ShortsAccessory = true,
	LeftShoeAccessory = true, RightShoeAccessory = true, DressSkirtAccessory = true,
}

local function assetChip(labelText, names)
	return { label = labelText, assets = H.enumList(Enum.AvatarAssetType, names) }
end
local function bundleChip(labelText, names)
	return { label = labelText, assets = {}, bundles = H.enumList(Enum.BundleType, names) }
end

local function combinedChip(labelText, assetNames, bundleNames)
	local chip = assetChip(labelText, assetNames)
	chip.bundles = H.enumList(Enum.BundleType, bundleNames or {})
	return chip
end

local allTypes, seenAssetValues = {}, {}
for _, assetType in ipairs(Enum.AvatarAssetType:GetEnumItems()) do
	if assetType.Name ~= "Unknown" and assetType.Name ~= "EarAccessory" and assetType.Name ~= "EyeAccessory"
		and assetType.Name ~= "MoodAnimation"
		and not seenAssetValues[assetType.Value] then
		seenAssetValues[assetType.Value] = true
		table.insert(allTypes, assetType)
	end
end
table.sort(allTypes, function(a, b)
	return string.lower(H.prettyType(a.Name)) < string.lower(H.prettyType(b.Name))
end)
local accessoryNames = {
	"Hat", "HairAccessory", "FaceAccessory", "NeckAccessory",
	"ShoulderAccessory", "FrontAccessory", "BackAccessory", "WaistAccessory",
}

local bodyPartNames = { "DynamicHead", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local makeupNames = { "EyebrowAccessory", "EyelashAccessory", "FaceMakeup", "LipMakeup", "EyeMakeup" }
local clothingNames = {
	"TShirt", "Shirt", "Pants", "TShirtAccessory", "ShirtAccessory", "PantsAccessory",
	"JacketAccessory", "SweaterAccessory", "ShortsAccessory", "DressSkirtAccessory",
	"LeftShoeAccessory", "RightShoeAccessory",
}
local animationNames = {
	"ClimbAnimation", "FallAnimation", "IdleAnimation", "JumpAnimation",
	"RunAnimation", "SwimAnimation", "WalkAnimation", "EmoteAnimation",
}

local accessoriesTab = {
	name = "Accessories", kind = "catalog",
	chips = {
		assetChip("All", accessoryNames),
		assetChip("Hats", { "Hat" }),
		assetChip("Hair", { "HairAccessory" }),
		assetChip("Face", { "FaceAccessory" }),
		assetChip("Neck", { "NeckAccessory" }),
		assetChip("Shoulders", { "ShoulderAccessory" }),
		assetChip("Front", { "FrontAccessory" }),
		assetChip("Back", { "BackAccessory" }),
		assetChip("Waist", { "WaistAccessory" }),
		assetChip("Backgrounds", { "AvatarBackground" }),
	},
}

local bodyAssetNames = {}
for _, name in ipairs(bodyPartNames) do table.insert(bodyAssetNames, name) end
for _, name in ipairs(makeupNames) do table.insert(bodyAssetNames, name) end
local bodyTab = {
	name = "Body", kind = "catalog",
	chips = {
		combinedChip("All", bodyAssetNames, { "BodyParts", "DynamicHeadAvatar" }),
		bundleChip("Body Bundles", { "BodyParts", "DynamicHeadAvatar" }),
		combinedChip("Dynamic Head", { "DynamicHead" }, { "DynamicHeadAvatar", "DynamicHead" }),
		assetChip("Torso", { "Torso" }),
		assetChip("Left Arm", { "LeftArm" }),
		assetChip("Right Arm", { "RightArm" }),
		assetChip("Left Leg", { "LeftLeg" }),
		assetChip("Right Leg", { "RightLeg" }),
		assetChip("Eyebrows", { "EyebrowAccessory" }),
		assetChip("Eyelashes", { "EyelashAccessory" }),
		assetChip("Face Makeup", { "FaceMakeup" }),
		assetChip("Lip Makeup", { "LipMakeup" }),
		assetChip("Eye Makeup", { "EyeMakeup" }),
		{ label = "Body Colors", assets = {}, special = "bodycolors" },
		{ label = "Body Scale", assets = {}, special = "bodyscaling" },
	},
}
local clothingTab = {
	name = "Clothing", kind = "catalog",
	chips = {
		combinedChip("All", clothingNames, { "Shoes" }),
		assetChip("Classic T-Shirt", { "TShirt" }),
		assetChip("Classic Shirt", { "Shirt" }),
		assetChip("Classic Pants", { "Pants" }),
		assetChip("Layered T-Shirt", { "TShirtAccessory" }),
		assetChip("Layered Shirt", { "ShirtAccessory" }),
		assetChip("Layered Pants", { "PantsAccessory" }),
		assetChip("Jacket", { "JacketAccessory" }),
		assetChip("Sweater", { "SweaterAccessory" }),
		assetChip("Shorts", { "ShortsAccessory" }),
		assetChip("Dress / Skirt", { "DressSkirtAccessory" }),
		assetChip("Left Shoe", { "LeftShoeAccessory" }),
		assetChip("Right Shoe", { "RightShoeAccessory" }),
		bundleChip("Shoe Bundles", { "Shoes" }),
	},
}

local animationsTab = {
	name = "Animations", kind = "catalog",
	chips = {
		combinedChip("All", animationNames, { "Animations" }),
		bundleChip("Animation Packs", { "Animations" }),
		assetChip("Climb", { "ClimbAnimation" }),
		assetChip("Fall", { "FallAnimation" }),
		assetChip("Idle", { "IdleAnimation" }),
		assetChip("Jump", { "JumpAnimation" }),
		assetChip("Run", { "RunAnimation" }),
		assetChip("Swim", { "SwimAnimation" }),
		assetChip("Walk", { "WalkAnimation" }),
		assetChip("Emotes", { "EmoteAnimation" }),
	},
}

local function sortedAssetNames(names)
	local copy = table.clone(names)
	table.sort(copy, function(a, b)
		return string.lower(H.prettyType(a)) < string.lower(H.prettyType(b))
	end)
	return copy
end
local inventoryAccessoryNames = sortedAssetNames(accessoryNames)
local inventoryClassicNames = sortedAssetNames({ "Pants", "Shirt", "TShirt" })
local inventoryLayeredNames = sortedAssetNames({
	"DressSkirtAccessory", "JacketAccessory", "LeftShoeAccessory", "PantsAccessory",
	"RightShoeAccessory", "ShirtAccessory", "ShortsAccessory", "SweaterAccessory", "TShirtAccessory",
})
local inventoryAnimationNames = sortedAssetNames({
	"ClimbAnimation", "FallAnimation", "IdleAnimation", "JumpAnimation", "RunAnimation", "SwimAnimation", "WalkAnimation",
})
local inventoryEmoteNames = { "EmoteAnimation" }
local inventoryGearNames = { "Gear" }
local inventoryBackgroundNames = { "AvatarBackground" }

local inventoryGrouped = {}
for _, group in ipairs({
	inventoryAccessoryNames, inventoryClassicNames, inventoryLayeredNames,
	inventoryAnimationNames, inventoryEmoteNames, inventoryGearNames, inventoryBackgroundNames,
	}) do
	for _, name in ipairs(group) do inventoryGrouped[name] = true end
end
local inventoryOtherNames = {}
for _, assetType in ipairs(allTypes) do
	if not inventoryGrouped[assetType.Name] then
		table.insert(inventoryOtherNames, assetType.Name)
	end
end
inventoryOtherNames = sortedAssetNames(inventoryOtherNames)

local inventoryChips = {
	{ label = "All Items", assets = allTypes, allInventory = true },
	assetChip("Accessory Items", inventoryAccessoryNames),
	assetChip("2D Clothes", inventoryClassicNames),
	assetChip("Layered", inventoryLayeredNames),
	assetChip("Animations", inventoryAnimationNames),
	assetChip("Emotes", inventoryEmoteNames),
	assetChip("Gears", inventoryGearNames),
	assetChip("Backgrounds", inventoryBackgroundNames),
	assetChip("Body & Other", inventoryOtherNames),
	{ label = "Bundles", assets = {}, special = "inventorybundles" },
}

TABS = {
	accessoriesTab,
	animationsTab,
	bodyTab,
	clothingTab,
	{ name = "Limited", kind = "catalog", limitedOnly = true, chips = nil },
	{ name = "Outfits", kind = "outfits", chips = nil },
	{ name = "Inventory", kind = "inventory", chips = inventoryChips },
}

local SORTS = {}
for _, entry in ipairs({
	{ "Relevance", "Relevance" }, { "Bestselling", "Bestselling" },
	{ "Newest", "RecentlyCreated" }, { "Lowest Price", "PriceLowToHigh" },
	{ "Highest Price", "PriceHighToLow" },
	}) do
	local value = H.enumItem(Enum.CatalogSortType, entry[2])
	if value then table.insert(SORTS, { label = entry[1], value = value }) end
end

local SALES = {}
for _, entry in ipairs({ { "All sales", "All" }, { "Limiteds", "Collectibles" }, { "Premium", "Premium" } }) do
	local value = H.enumItem(Enum.SalesTypeFilter, entry[2])
	if value then table.insert(SALES, { label = entry[1], value = value }) end
end
local state = { keyword = "", sort = 1, sale = 1, offsale = true, min = nil, max = nil, creator = "" }
local curTab = 1
local chipIdx = {}
for index = 1, #TABS do chipIdx[index] = 1 end

local C = {
	bg = Color3.fromRGB(14, 15, 18), panel = Color3.fromRGB(27, 29, 34),
	field = Color3.fromRGB(37, 40, 47), card = Color3.fromRGB(42, 45, 53),
	line = Color3.fromRGB(58, 62, 71), text = Color3.fromRGB(235, 237, 240),
	sub = Color3.fromRGB(148, 154, 166), accent = Color3.fromRGB(0, 162, 255),
	success = Color3.fromRGB(42, 150, 82), danger = Color3.fromRGB(180, 52, 52),
}
local F, FM, FB = Enum.Font.BuilderSansBold, Enum.Font.BuilderSansBold, Enum.Font.BuilderSansBold
local textObjects = {}
local currentTextScale = 1
local designSizes = setmetatable({}, { __mode = "k" })
local REFERENCE_CANVAS_SIZE = Vector2.new(1920, 1080)

function H.updateTextConstraint(instance, baseSize, scale)
	if not instance then return end
	local maximum = math.clamp(math.floor(baseSize * scale + 0.5), 6, 100)

	local constraint = instance:FindFirstChildOfClass("UITextSizeConstraint")
	if not constraint then
		constraint = Instance.new("UITextSizeConstraint")
		constraint.Parent = instance
	end
	constraint.MinTextSize = math.max(6, math.floor(maximum * 0.58))
	constraint.MaxTextSize = maximum
	instance.TextScaled = true
	instance.TextSize = maximum
end
function H.registerTextObject(instance)
	if not (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then return end
	local baseSize = instance.TextSize + 8
	instance:SetAttribute("CatalogBaseTextSize", baseSize)
	instance.Font = FB
	instance.TextStrokeColor3 = Color3.new(0, 0, 0)
	instance.TextStrokeTransparency = 0.52
	if not instance:FindFirstChildOfClass("UIPadding") then
		local padding = Instance.new("UIPadding")
		padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
		padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 3), UDim.new(0, 3)
		padding.Parent = instance
	end
	H.updateTextConstraint(instance, baseSize, currentTextScale)
	table.insert(textObjects, instance)
end

function H.setTextSize(instance, baseSize)
	if not instance then return end
	instance:SetAttribute("CatalogBaseTextSize", baseSize + 8)
	instance.Font = FB
	H.updateTextConstraint(instance, baseSize + 8, currentTextScale)
end

function H.isAutoAxis(object, axis)
	if not object or not object:IsA("GuiObject") then return false end
	local automatic = object.AutomaticSize
	if axis == "X" then return automatic == Enum.AutomaticSize.X or automatic == Enum.AutomaticSize.XY end
	return automatic == Enum.AutomaticSize.Y or automatic == Enum.AutomaticSize.XY
end
function H.getDesignSize(reference)
	if reference and reference:IsA("GuiObject") then
		local known = designSizes[reference]
		if known then return known end
		return reference.AbsoluteSize
	end
	return Vector2.zero
end

function H.toScaleUDim2(reference, value)
	if typeof(value) ~= "UDim2" or not reference or not reference:IsA("GuiObject") then return value end
	local referenceSize = H.getDesignSize(reference)
	local xScale, xOffset = value.X.Scale, 0
	local yScale, yOffset = value.Y.Scale, 0
	if H.isAutoAxis(reference, "X") then xOffset = value.X.Offset
	elseif referenceSize.X > 0 then xScale += value.X.Offset / referenceSize.X
	else xOffset = value.X.Offset end
	if H.isAutoAxis(reference, "Y") then yOffset = value.Y.Offset
	elseif referenceSize.Y > 0 then yScale += value.Y.Offset / referenceSize.Y
	else yOffset = value.Y.Offset end
	return UDim2.new(xScale, xOffset, yScale, yOffset)
end

function H.toScaleUDim(reference, value, axis)
	if typeof(value) ~= "UDim" or not reference or not reference:IsA("GuiObject") or H.isAutoAxis(reference, axis) then return value end
	local size = H.getDesignSize(reference)
	local span = axis == "X" and size.X or size.Y
	if span <= 0 then return value end
	return UDim.new(value.Scale + value.Offset / span, 0)
end
function H.estimateDesignSize(object, parent, normalizedSize)
	local parentSize = H.getDesignSize(parent)
	local actual = object.AbsoluteSize
	local x, y = actual.X, actual.Y
	if not H.isAutoAxis(object, "X") then
		x = parentSize.X > 0 and normalizedSize.X.Scale * parentSize.X + normalizedSize.X.Offset or actual.X
	end
	if not H.isAutoAxis(object, "Y") then
		y = parentSize.Y > 0 and normalizedSize.Y.Scale * parentSize.Y + normalizedSize.Y.Offset or actual.Y
	end
	return Vector2.new(math.max(0, x), math.max(0, y))
end

function H.setLayout(object, property, value)
	local reference = property == "CanvasSize" and object or object.Parent
	local converted = value
	if property == "Position" or property == "Size" or property == "CanvasSize" or property == "CellSize" or property == "CellPadding" then
		converted = H.toScaleUDim2(reference, value)
	end
	object[property] = converted
	if property == "Size" and object:IsA("GuiObject") then
		designSizes[object] = H.estimateDesignSize(object, object.Parent, converted)
	end
end

function H.new(className, properties, parent)
	local object = Instance.new(className)
	local deferredCanvas

	for property, original in pairs(properties) do
		local value = original

		if typeof(value) == "UDim2" then
			if property == "CanvasSize" then
				deferredCanvas = value
			elseif property == "Position" or property == "Size"
				or property == "CellSize" or property == "CellPadding" then
				value = H.toScaleUDim2(parent, value)
			end
		elseif typeof(value) == "UDim" and parent and parent:IsA("GuiObject") then
			if property == "Padding" then
				value = H.toScaleUDim(parent, value, properties.FillDirection == Enum.FillDirection.Vertical and "Y" or "X")
			elseif property == "PaddingLeft" or property == "PaddingRight" then
				value = H.toScaleUDim(parent, value, "X")
			elseif property == "PaddingTop" or property == "PaddingBottom" then
				value = H.toScaleUDim(parent, value, "Y")
			end
		end

		object[property] = value
	end

	if object:IsA("GuiButton") then
		object.AutoButtonColor = true
	end

	object.Parent = parent

	if object:IsA("GuiObject") and typeof(object.Size) == "UDim2" then
		designSizes[object] = H.estimateDesignSize(object, parent, object.Size)
	end

	H.registerTextObject(object)

	if deferredCanvas then
		object.CanvasSize = H.toScaleUDim2(object, deferredCanvas)
	end

	return object
end
function H.round(object, radius)
	H.new("UICorner", { CornerRadius = UDim.new(0, radius) }, object)
end

function H.stroke(object)
	H.new("UIStroke", { Color = C.line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, object)
end

function H.padX(object)
	local padding = object:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 3), UDim.new(0, 3)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
	padding.Parent = object
end
function H.label(parent, text, x, y, width, height, size, color, font)
	return H.new("TextLabel", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
		Text = text, TextColor3 = color or C.text, Font = font or FM, TextSize = size or 16,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

function H.applyTouchScale(button, factor)
	if UserInputService.TouchEnabled and button and button:IsA("GuiObject")
		and not button:FindFirstChildOfClass("UIScale") then
		H.new("UIScale", { Scale = factor or 1.06 }, button)
	end
end

function H.mkButton(parent, text, width, height, color)
	local baseColor = color or C.card

	local button = H.new("TextButton", {
		Text = text,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = baseColor,
		TextColor3 = C.text,
		Font = FM,
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AutoButtonColor = true,
	}, parent)

	H.applyTouchScale(button, 1.06)
	H.round(button, 10)

	local outline = H.new("UIStroke", {
		Color = color and C.accent or C.line,
		Transparency = 0.45,
		Thickness = 1,
	}, button)

	button.MouseEnter:Connect(function()
		TweenService:Create(outline, TweenInfo.new(0.12), {
			Transparency = 0.12,
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(outline, TweenInfo.new(0.16), {
			Transparency = 0.45,
		}):Play()
	end)

	return button
end
function H.mkBox(parent, placeholder, width, height)
	local box = H.new("TextBox", {
		PlaceholderText = placeholder, Text = "", ClearTextOnFocus = false,
		Size = UDim2.fromOffset(width, height), BackgroundColor3 = C.field,
		TextColor3 = C.text, PlaceholderColor3 = C.sub, Font = F, TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	H.round(box, 8)
	H.padX(box)
	return box
end

function H.mkPanel(parent, x, y, width, height)
	local panel = H.new("Frame", {
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.panel, BackgroundTransparency = 0.08, BorderSizePixel = 0, Active = true,
	}, parent)
	H.round(panel, 12)
	H.stroke(panel)
	return panel
end

local gui = H.new("ScreenGui", {
	Name = "CatalogCreator", ResetOnSpawn = false,

	IgnoreGuiInset = false,
	DisplayOrder = 1,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))
local root = H.new("Frame", {
	Name = "ResponsiveRoot", AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
}, gui)
designSizes[root] = REFERENCE_CANVAS_SIZE
H.new("UIAspectRatioConstraint", {
	AspectRatio = 16 / 9, AspectType = Enum.AspectType.FitWithinMaxSize,
	DominantAxis = Enum.DominantAxis.Width,
}, root)

local toggleBtn = H.new("TextButton", {
	Name = "CatalogToggleButton", AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.985), Size = UDim2.fromScale(0.12, 0.045),
	BackgroundColor3 = C.accent, Text = "Open Catalog", TextColor3 = C.text,
	Font = FB, TextSize = 20, ZIndex = 5,
}, root)
H.applyTouchScale(toggleBtn, 1.06)
H.round(toggleBtn, 24)

RunService.Heartbeat:Wait()
local function updateTextScale()
	local size = root.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	currentTextScale = math.max(0.30, math.min(size.X / 1920, size.Y / 1080))
	for index = #textObjects, 1, -1 do
		local object = textObjects[index]
		if not object.Parent then table.remove(textObjects, index)
		else
			local base = object:GetAttribute("CatalogBaseTextSize")
			if type(base) == "number" then H.updateTextConstraint(object, base, currentTextScale) end
		end
	end
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTextScale)
task.defer(updateTextScale)
local main = H.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, root)
RunService.Heartbeat:Wait()

local mainCloseBtn = H.mkButton(main, "×", 48, 44, C.card)
H.setLayout(mainCloseBtn, "Position", UDim2.new(1, -78, 0, 26))
H.setTextSize(mainCloseBtn, 30)
mainCloseBtn.ZIndex = 10
mainCloseBtn.Name = "CloseCatalogButton"
mainCloseBtn.AutoButtonColor = true

local viewCard = H.mkPanel(main, 20, 48, 390, 1008)
RunService.Heartbeat:Wait()
local viewportPosition = UDim2.fromOffset(12, 12)
local viewportSize = UDim2.fromOffset(366, 520)
local avatarBackgroundImage = H.new("ImageLabel", {
	Name = "AvatarBackgroundPreview", Position = viewportPosition, Size = viewportSize,
	BackgroundColor3 = Color3.fromRGB(18, 20, 25), BackgroundTransparency = 0,
	BorderSizePixel = 0, Image = "", ScaleType = Enum.ScaleType.Crop, Visible = false, ZIndex = 1,
}, viewCard)
H.round(avatarBackgroundImage, 10)

local viewport = H.new("ViewportFrame", {
	Position = viewportPosition, Size = viewportSize, BackgroundTransparency = 1,
	BorderSizePixel = 0, Ambient = Color3.fromRGB(150, 150, 160),
	LightColor = Color3.fromRGB(255, 255, 255), LightDirection = Vector3.new(-0.25, -0.5, 1), ZIndex = 2,
}, viewCard)
H.round(viewport, 10)
local cam = H.new("Camera", { FieldOfView = 40 }, viewport)
viewport.CurrentCamera = cam
local world = H.new("WorldModel", {}, viewport)
local dragZone = H.new("TextButton", {
	Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
	Position = viewportPosition, Size = viewportSize, ZIndex = 3,
}, viewCard)

local spinBtn = H.mkButton(viewCard, "Auto-rotate: Off", 112, 32)
H.setLayout(spinBtn, "Position", UDim2.fromOffset(12, 544))
local resetViewBtn = H.mkButton(viewCard, "Reset view", 112, 32)
H.setLayout(resetViewBtn, "Position", UDim2.fromOffset(130, 544))
H.rigToggleBtn = H.mkButton(viewCard, "Rig: ...", 112, 32)
H.setLayout(H.rigToggleBtn, "Position", UDim2.fromOffset(248, 544))
H.rigToggleBtn.Name = "CharacterRigToggleButton"
local wearingTitle = H.label(viewCard, "CURRENTLY WEARING", 14, 590, 362, 24, 16, C.text, FB)
wearingTitle.Name = "CurrentlyWearingTitle"

local controlsScroll = H.new("ScrollingFrame", {
	Name = "CurrentlyWearingScroll", Position = UDim2.fromOffset(12, 620),
	Size = UDim2.fromOffset(366, 126), BackgroundColor3 = C.field,
	BackgroundTransparency = 0.12, BorderSizePixel = 0,
	ScrollBarImageColor3 = C.sub, ScrollBarThickness = UserInputService.TouchEnabled and 6 or 4,
	CanvasSize = UDim2.new(1, 0, 1, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.None, ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollingEnabled = true, ClipsDescendants = true,
}, viewCard)
H.round(controlsScroll, 10)
local wearingContent = H.new("Frame", {
	Name = "WearingContent", Size = UDim2.fromOffset(354, 118), BackgroundTransparency = 1,
}, controlsScroll)
local wearingGridHolder = H.new("Frame", {
	Name = "EquippedItemsRow", Position = UDim2.fromOffset(6, 4),
	Size = UDim2.fromOffset(342, 110), BackgroundTransparency = 1, ClipsDescendants = false,
}, wearingContent)

local currentEquippedItems = {}
local refreshLocalWearingSnapshot
local hasWearingSnapshot = false
state.wornLayout = { gap = 8, cellSize = 86, contentHeight = 126 }

local unequipAllBtn = H.mkButton(viewCard, "Unequip all", 178, 40, C.danger)
H.setLayout(unequipAllBtn, "Position", UDim2.fromOffset(12, 760))
local resetBtn = H.mkButton(viewCard, "Reset avatar", 178, 40, C.card)
H.setLayout(resetBtn, "Position", UDim2.fromOffset(200, 760))
do
	H.purchaseAllBtn = H.mkButton(viewCard, "Purchase All (up to 20)", 354, 40, C.success)
	H.setLayout(H.purchaseAllBtn, "Position", UDim2.fromOffset(12, 808))
	H.saveToRobloxBtn = H.mkButton(viewCard, "Save to Roblox", 354, 40, C.accent)
	H.setLayout(H.saveToRobloxBtn, "Position", UDim2.fromOffset(12, 856))
end

local function updateWearingCanvas()
	if not controlsScroll.Parent then return end

	local scale = math.max(0.12, math.min(root.AbsoluteSize.X / 1920, root.AbsoluteSize.Y / 1080))
	local viewportWidth = math.max(1, controlsScroll.AbsoluteSize.X)
	local viewportHeight = math.max(1, controlsScroll.AbsoluteSize.Y)
	local touchFactor = UserInputService.TouchEnabled and 1.15 or 1
	local cellSize = math.max(10, math.min(86 * scale * touchFactor, viewportHeight - 12 * scale))
	local gap = 8 * scale
	local sidePadding = 8 * scale
	local verticalPadding = math.max(2 * scale, (viewportHeight - cellSize) / 2)
	local count = #currentEquippedItems
	local contentWidth = math.max(viewportWidth, sidePadding * 2 + math.max(1, count) * cellSize + math.max(0, count - 1) * gap)
	state.wornLayout.pixelCellSize = cellSize
	state.wornLayout.pixelGap = gap
	state.wornLayout.pixelSidePadding = sidePadding
	state.wornLayout.pixelVerticalPadding = verticalPadding
	state.wornLayout.contentWidth = contentWidth

	wearingContent.Size = UDim2.new(0, contentWidth, 1, 0)
	wearingGridHolder.Position = UDim2.fromOffset(sidePadding, 0)
	wearingGridHolder.Size = UDim2.new(0, math.max(1, contentWidth - sidePadding * 2), 1, 0)
	controlsScroll.CanvasSize = UDim2.new(0, contentWidth, 1, 0)
	controlsScroll.ScrollingDirection = Enum.ScrollingDirection.X
	controlsScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	controlsScroll.ScrollingEnabled = contentWidth > viewportWidth + 1
	local maxX = math.max(0, contentWidth - viewportWidth)
	controlsScroll.CanvasPosition = Vector2.new(math.clamp(controlsScroll.CanvasPosition.X, 0, maxX), 0)
	if count == 0 then controlsScroll.CanvasPosition = Vector2.zero end
end

local function setViewportBackground(assetId)
	local id = tonumber(assetId)
	if not id or id <= 0 or id % 1 ~= 0 then
		avatarBackgroundImage.Image = ""
		avatarBackgroundImage.Visible = false
		avatarBackgroundImage:SetAttribute("AssetId", nil)
		if H.refreshBackgroundPreviewBadges then H.refreshBackgroundPreviewBadges() end
		return
	end
	avatarBackgroundImage.Image = "rbxthumb://type=Asset&id=" .. string.format("%d", id) .. "&w=420&h=420"
	avatarBackgroundImage:SetAttribute("AssetId", id)
	avatarBackgroundImage.Visible = true
	if H.refreshBackgroundPreviewBadges then H.refreshBackgroundPreviewBadges() end
end

local previewModel
local yaw, pitch, zoom = 0, 0, 1
local baseDist = 10
local focus = Vector3.zero
local autoRotate = false
local dragging = false
local activeTouch
local lastMousePosition

local animationAssetTypeCache = {}
local animationAssetTypeIds = {}
for _, typeName in ipairs({
	"Animation", "ClimbAnimation", "DeathAnimation", "FallAnimation", "IdleAnimation",
	"JumpAnimation", "RunAnimation", "SwimAnimation", "WalkAnimation", "PoseAnimation",
	}) do
	local ok, assetType = pcall(function() return Enum.AssetType[typeName] end)
	if ok and assetType then animationAssetTypeIds[assetType.Value] = true end
end
local function isAnimationAsset(assetId)
	assetId = tonumber(assetId)
	if not assetId or assetId <= 0 then return false end
	local cached = animationAssetTypeCache[assetId]
	if cached ~= nil then return cached end
	local ok, info = pcall(function()
		return H.getProductInfo(assetId, Enum.InfoType.Asset)
	end)
	if ok and type(info) == "table" and type(info.AssetTypeId) == "number" then
		local valid = animationAssetTypeIds[info.AssetTypeId] == true
		animationAssetTypeCache[assetId] = valid
		return valid
	end

	return nil
end

local function copyEmoteDictionary(source)
	local result = {}
	if type(source) == "table" then
		for name, ids in pairs(source) do
			if type(ids) == "table" then
				local copiedIds = {}
				for _, id in ipairs(ids) do table.insert(copiedIds, id) end
				result[name] = copiedIds
			end
		end
	end
	return result
end

local function copyEquippedEmotes(source)
	local result = {}
	if type(source) == "table" then
		for _, entry in ipairs(source) do
			if type(entry) == "table" then
				table.insert(result, { Slot = tonumber(entry.Slot) or (#result + 1), Name = tostring(entry.Name or "") })
			elseif type(entry) == "string" then
				table.insert(result, entry)
			end
		end
	end
	return result
end

local function restoreCatalogEmoteState(restore)
	if not restore then return end
	local description = restore.description
	if description and description.Parent then
		pcall(function() description:SetEmotes(restore.originalEmotes) end)
		pcall(function() description:SetEquippedEmotes(restore.originalEquipped) end)
	end
	if restore.createdDescription and description then
		pcall(function() description:Destroy() end)
	end
end

local function startCatalogEmotePreview(humanoid, emoteAssetId)
	if not humanoid or not humanoid.Parent then
		return nil, nil, nil, "your character is not ready for emote playback"
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil, nil, nil, "marketplace emote previews require an R15 character"
	end

	local description = humanoid:FindFirstChildOfClass("HumanoidDescription")
	local createdDescription = false
	if not description then
		local descOk, applied = pcall(function() return humanoid:GetAppliedDescription() end)
		if not descOk or not applied then
			return nil, nil, nil, "could not read your current avatar description: " .. tostring(applied)
		end
		description = applied
		description.Name = "CatalogEmotePreviewDescription"
		description.Parent = humanoid
		createdDescription = true
	end

	local emotesOk, currentEmotes = pcall(function() return description:GetEmotes() end)
	if not emotesOk then
		if createdDescription then description:Destroy() end
		return nil, nil, nil, "could not read the avatar's emote list: " .. tostring(currentEmotes)
	end
	local equippedOk, currentEquipped = pcall(function() return description:GetEquippedEmotes() end)
	if not equippedOk then
		if createdDescription then description:Destroy() end
		return nil, nil, nil, "could not read equipped emotes: " .. tostring(currentEquipped)
	end

	local originalEmotes = copyEmoteDictionary(currentEmotes)
	local originalEquipped = copyEquippedEmotes(currentEquipped)
	local emoteName = "CatalogPreview_" .. tostring(emoteAssetId)
	local updatedEmotes = copyEmoteDictionary(currentEmotes)
	updatedEmotes[emoteName] = { tonumber(emoteAssetId) }

	local equippedNames = {}
	local sortedEquipped = copyEquippedEmotes(currentEquipped)
	table.sort(sortedEquipped, function(a, b)
		local slotA = type(a) == "table" and (tonumber(a.Slot) or 999) or 999
		local slotB = type(b) == "table" and (tonumber(b.Slot) or 999) or 999
		return slotA < slotB
	end)
	for _, entry in ipairs(sortedEquipped) do
		local name = type(entry) == "table" and entry.Name or entry
		if type(name) == "string" and name ~= "" and #equippedNames < 7 then
			table.insert(equippedNames, name)
		end
	end
	table.insert(equippedNames, emoteName)

	local setOk, setError = pcall(function()
		description:SetEmotes(updatedEmotes)
		description:SetEquippedEmotes(equippedNames)
	end)
	if not setOk then
		restoreCatalogEmoteState({ description = description, originalEmotes = originalEmotes,
			originalEquipped = originalEquipped, createdDescription = createdDescription })
		return nil, nil, nil, "Roblox could not register this emote: " .. tostring(setError)
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local tracksBefore = {}
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do tracksBefore[track] = true end

	local playOk, played
	local playAsyncOk, playAsync = pcall(function() return humanoid.PlayEmoteAsync end)
	if playAsyncOk and type(playAsync) == "function" then
		playOk, played = pcall(playAsync, humanoid, emoteName)
	else
		local legacyOk, legacy = pcall(function() return humanoid.PlayEmote end)
		if legacyOk and type(legacy) == "function" then
			playOk, played = pcall(legacy, humanoid, emoteName)
		else
			playOk, played = false, "PlayEmoteAsync is unavailable on this client"
		end
	end

	if not playOk or played ~= true then
		restoreCatalogEmoteState({ description = description, originalEmotes = originalEmotes,
			originalEquipped = originalEquipped, createdDescription = createdDescription })
		return nil, nil, nil, "Roblox could not play this emote: " .. tostring(played)
	end

	local playerTracks = {}
	local discoveredAnimationId
	for attempt = 1, 8 do
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if not tracksBefore[track] then
				local alreadyAdded = false
				for _, existing in ipairs(playerTracks) do
					if existing == track then alreadyAdded = true; break end
				end
				if not alreadyAdded then table.insert(playerTracks, track) end
				if not discoveredAnimationId and track.Animation then
					local numericId = tonumber(tostring(track.Animation.AnimationId):match("%d+"))
					if numericId and numericId ~= tonumber(emoteAssetId) then discoveredAnimationId = numericId end
				end
			end
		end
		if #playerTracks > 0 then break end
		task.wait(0.05)
	end

	local restoreState = {
		humanoid = humanoid,
		description = description,
		originalEmotes = originalEmotes,
		originalEquipped = originalEquipped,
		createdDescription = createdDescription,
		playerTracks = playerTracks,
	}
	return restoreState, discoveredAnimationId, nil, nil
end

local function playAnimationOnHumanoid(humanoid, assetId)
	if not humanoid or not humanoid.Parent then return nil, nil end
	local validAnimation = isAnimationAsset(assetId)
	if validAnimation == false then
		return nil, nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(assetId)
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if (not ok or not track) and humanoid.LoadAnimation then
		ok, track = pcall(function() return humanoid:LoadAnimation(animation) end)
	end
	if not ok or not track then
		animation:Destroy()
		return nil, nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	local played, playError = pcall(function() track:Play(0.15) end)
	if not played then
		pcall(function() track:Destroy() end)
		animation:Destroy()
		return nil, nil
	end
	return track, animation
end
local function stopEmotePreview()
	local active = H.activeEmote
	if not active then return end
	for _, track in ipairs(active.playerTracks or {}) do
		pcall(function() track:Stop(0.15) end)
	end
	for _, key in ipairs({ "playerTrack", "viewportTrack" }) do
		local track = active[key]
		if track then pcall(function() track:Stop(0.15); track:Destroy() end) end
	end
	for _, key in ipairs({ "playerAnimation", "viewportAnimation" }) do
		local animation = active[key]
		if animation then pcall(function() animation:Destroy() end) end
	end
	H.activeEmote = nil

	if active.emoteRestore then
		restoreCatalogEmoteState(active.emoteRestore)
	end
	if H.previewIdleTrack then pcall(function() H.previewIdleTrack:Play(0.2) end) end
end

local function stopViewportEmotePreview()
	local active = H.activeEmote
	if not active then return end

	if active.viewportTrack then
		pcall(function()
			active.viewportTrack:Stop(0.15)
			active.viewportTrack:Destroy()
		end)
		active.viewportTrack = nil
	end
	if active.viewportAnimation then
		pcall(function() active.viewportAnimation:Destroy() end)
		active.viewportAnimation = nil
	end

	if H.previewIdleTrack then
		pcall(function() H.previewIdleTrack:Play(0.2) end)
	end
end

local function isEmotePreviewItem(data)
	if not data then return false end
	local typeName = tostring(data.typeName or ""):gsub("^Enum%.AvatarAssetType%.", "")
	if data.emote == true or typeName == "EmoteAnimation" then return true end
	local lowered = tostring(data.name or ""):lower()
	return lowered:find("dance", 1, true) ~= nil or lowered:find("emote", 1, true) ~= nil
end

local function toggleEmotePreview(data)
	if not data or not tonumber(data.id) then return end
	if H.activeEmote and H.activeEmote.id == data.id then
		stopEmotePreview()
		if H.status then H.status.Text = "Animation stopped" end
		return
	end
	stopEmotePreview()

	local typeName = tostring(data.typeName or ""):gsub("^Enum%.AvatarAssetType%.", "")
	local isMarketplaceEmote = typeName == "EmoteAnimation" or data.emote == true
	if isMarketplaceEmote then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			if H.status then H.status.Text = "Character is not ready for emote playback" end
			return
		end
		local restoreState, animationClipId, _, previewError = startCatalogEmotePreview(humanoid, tonumber(data.id))
		if not restoreState then
			if H.status then H.status.Text = tostring(previewError or "Roblox could not load this emote") end
			return
		end

		local active = { id = data.id, emoteRestore = restoreState, playerTracks = restoreState.playerTracks }

		local previewHumanoid = previewModel and previewModel:FindFirstChildOfClass("Humanoid")
		if previewHumanoid and animationClipId then
			active.viewportTrack, active.viewportAnimation = playAnimationOnHumanoid(previewHumanoid, animationClipId)
		end
		H.activeEmote = active
		if H.status then
			H.status.Text = "Playing " .. tostring(data.name) .. " on your avatar · click again to stop"
		end
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		if H.status then H.status.Text = "Character is not ready for an animation preview" end
		return
	end
	local previewState = { id = data.id }
	H.activeEmote = previewState
	previewState.playerTrack, previewState.playerAnimation = playAnimationOnHumanoid(humanoid, data.id)
	local previewHumanoid = previewModel and previewModel:FindFirstChildOfClass("Humanoid")
	if previewHumanoid then
		if H.previewIdleTrack then pcall(function() H.previewIdleTrack:Stop(0.1) end) end
		previewState.viewportTrack, previewState.viewportAnimation = playAnimationOnHumanoid(previewHumanoid, data.id)
	end
	if not previewState.playerTrack and not previewState.viewportTrack then
		H.activeEmote = nil
		if H.previewIdleTrack then pcall(function() H.previewIdleTrack:Play(0.2) end) end
		if H.status then H.status.Text = "Roblox could not load this animation asset" end
		return
	end
	if H.status then H.status.Text = "Playing " .. tostring(data.name) .. " · click again to stop" end
end

local function applyOrbitDelta(delta)
	if not dragging or not delta then return end
	local fullTurn = math.pi * 2
	yaw = (yaw - math.rad(delta.X * 0.6)) % fullTurn
	pitch = (pitch + math.rad(delta.Y * 0.6)) % fullTurn
	H.updateCamera()
end

H.wearingAccessoryTypes = {
	Accessory = true, Hat = true, HairAccessory = true, FaceAccessory = true,
	NeckAccessory = true, ShoulderAccessory = true, FrontAccessory = true,
	BackAccessory = true, WaistAccessory = true, EarAccessory = true, EyeAccessory = true,
}
H.wearingBodyTypes = {
	DynamicHead = true, Head = true, Face = true, Torso = true,
	LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true,
	TShirt = true, Shirt = true, Pants = true,
	TShirtAccessory = true, ShirtAccessory = true, PantsAccessory = true,
	JacketAccessory = true, SweaterAccessory = true, ShortsAccessory = true,
	LeftShoeAccessory = true, RightShoeAccessory = true, DressSkirtAccessory = true,
	EyebrowAccessory = true, EyelashAccessory = true,
	FaceMakeup = true, LipMakeup = true, EyeMakeup = true,
}
function H.wearingGroup(typeName)
	local name = tostring(typeName or "Item"):gsub("^Enum%.AvatarAssetType%.", "")
	if H.wearingAccessoryTypes[name] then return 1 end
	if H.wearingBodyTypes[name] then return 2 end
	if name:find("Animation", 1, true) or name == "Emote" then return 3 end
	return 4
end

local function refreshWearingList()
	wearingContent:SetAttribute("SelectedWearingItemId", nil)
	local emptyOld = wearingContent:FindFirstChild("NothingEquippedLabel")
	if emptyOld then emptyOld:Destroy() end
	for _, child in ipairs(wearingGridHolder:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	table.sort(currentEquippedItems, function(a, b)
		local typeA = tostring(a.typeName or "Item")
		local typeB = tostring(b.typeName or "Item")
		local groupA, groupB = H.wearingGroup(typeA), H.wearingGroup(typeB)
		if groupA ~= groupB then return groupA < groupB end
		local sortA = string.lower(H.prettyType(typeA))
		local sortB = string.lower(H.prettyType(typeB))
		if sortA ~= sortB then return sortA < sortB end
		return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
	end)
	updateWearingCanvas()

	if #currentEquippedItems == 0 then
		local message = hasWearingSnapshot and "No equipped items detected · press ↻ to retry" or "Loading equipped items..."
		local empty = H.new("TextLabel", {
			Name = "NothingEquippedLabel", BackgroundTransparency = 1,
			Text = message, TextColor3 = C.sub, Font = FB, TextSize = 12,
			TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, wearingGridHolder)
		empty.Position = UDim2.fromOffset(8, 0)
		empty.Size = UDim2.new(1, -16, 1, 0)
		return
	end
	local layout = state.wornLayout
	local cellSize = layout.pixelCellSize or 44
	local gap = layout.pixelGap or 4
	local verticalPadding = layout.pixelVerticalPadding or 2
	for index, item in ipairs(currentEquippedItems) do
		local x = (index - 1) * (cellSize + gap)
		local card = H.new("Frame", {
			Name = "EquippedItem_" .. tostring(item.id),
			BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = index,
		}, wearingGridHolder)
		card.Position = UDim2.fromOffset(x, verticalPadding)
		card.Size = UDim2.fromOffset(cellSize, cellSize)
		card.ZIndex = 2
		H.round(card, 5)
		H.new("UIStroke", { Color = C.line, Thickness = 0.65, Transparency = 0.48 }, card)
		local image = H.new("ImageButton", {
			Name = "ItemImage", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
			Image = "rbxthumb://type=Asset&id=" .. string.format("%d", item.id) .. "&w=420&h=420",
			ZIndex = 3, AutoButtonColor = false,
		}, card)
		H.round(image, 5)

		local actionOverlay = H.new("Frame", {
			Name = "WornItemActions", Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(12, 14, 18), BackgroundTransparency = 0.08,
			Visible = false, ZIndex = 6, Active = true,
		}, card)
		H.round(actionOverlay, 7)
		local buyButton = H.mkButton(actionOverlay, "Buy", 80, 18, C.success)
		buyButton.Position = UDim2.new(0.05, 0, 0.08, 0)
		buyButton.Size = UDim2.new(0.9, 0, 0.38, 0)
		buyButton.ZIndex = 7
		local unequipButton = H.mkButton(actionOverlay, "Remove", 80, 18, C.danger)
		unequipButton.Position = UDim2.new(0.05, 0, 0.54, 0)
		unequipButton.Size = UDim2.new(0.9, 0, 0.38, 0)
		unequipButton.ZIndex = 7
		H.setTextSize(buyButton, 11)
		H.setTextSize(unequipButton, 10)
		H.applyTouchScale(buyButton, 1.04)
		H.applyTouchScale(unequipButton, 1.04)

		local consumeWearingLongPress = H.bindLongPressDetails(image, function()
			if H.openItemDetails then
				H.openItemDetails({ id = item.id, name = H.prettyType(item.typeName), typeName = item.typeName, emote = tostring(item.typeName) == "EmoteAnimation" })
			end
		end)
		image.Activated:Connect(function()
			if consumeWearingLongPress() then return end
			local show = wearingContent:GetAttribute("SelectedWearingItemId") ~= item.id
			wearingContent:SetAttribute("SelectedWearingItemId", show and item.id or nil)
			for _, sibling in ipairs(wearingGridHolder:GetChildren()) do
				local actions = sibling:FindFirstChild("WornItemActions")
				if actions then actions.Visible = sibling == card and show end
			end
		end)
		image.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and H.openItemDetails then
				H.openItemDetails({ id = item.id, name = H.prettyType(item.typeName), typeName = item.typeName, emote = tostring(item.typeName) == "EmoteAnimation" })
			end
		end)
		buyButton.Activated:Connect(function()
			wearingContent:SetAttribute("SelectedWearingItemId", nil)
			actionOverlay.Visible = false
			local ok, err = pcall(function() MarketplaceService:PromptPurchase(player, item.id) end)
			if not ok then warn("[CatalogUI] Purchase prompt failed:", err) end
		end)
		unequipButton.Activated:Connect(function()
			wearingContent:SetAttribute("SelectedWearingItemId", nil)
			actionOverlay.Visible = false
			if H.onUnequipRequested then H.onUnequipRequested(item.id, item.typeName) end
		end)
	end
end
refreshWearingList()
controlsScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	updateWearingCanvas()
	refreshWearingList()
end)
task.defer(function()
	if controlsScroll.Parent then
		updateWearingCanvas()
		refreshWearingList()
	end
end)
H.updateCamera = function()
	local orbit = CFrame.fromOrientation(pitch, yaw, 0)
	local offset = orbit:VectorToWorldSpace(Vector3.new(0, 0, -baseDist * zoom))
	local cameraUp = orbit:VectorToWorldSpace(Vector3.new(0, 1, 0))
	cam.CFrame = CFrame.lookAt(focus + offset, focus, cameraUp)
	viewport.LightDirection = (cam.CFrame.LookVector + Vector3.new(-0.25, -0.5, 0)).Unit
end

local function rebuildViewport()
	if H.activeEmote then stopEmotePreview() end
	local character = player.Character
	local realHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not realHumanoid or not character:FindFirstChild("HumanoidRootPart") then return end

	local targetRig = realHumanoid.RigType
	H.previewRigType = targetRig
	H.rigToggleBtn.Text = targetRig == Enum.HumanoidRigType.R6 and "Rig: R6" or "Rig: R15"

	local descOk, description = pcall(function() return realHumanoid:GetAppliedDescription() end)
	if not descOk or not description then
		warn("[CatalogUI] Could not read avatar description for viewport:", description)
		if H.status then H.status.Text = "Could not read avatar appearance for preview" end
		return
	end

	local idleId = targetRig == Enum.HumanoidRigType.R6 and 180435571 or 507766666
	if targetRig == Enum.HumanoidRigType.R15 then
		local describedIdle = tonumber(description.IdleAnimation)
		if describedIdle and describedIdle > 0 then idleId = describedIdle end
	end

	H.viewportBuildToken = (H.viewportBuildToken or 0) + 1
	local buildToken = H.viewportBuildToken
	local created, clone = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, targetRig)
	end)
	pcall(function() description:Destroy() end)
	if buildToken ~= H.viewportBuildToken then
		if created and clone then clone:Destroy() end
		return
	end
	if not created or not clone then
		warn("[CatalogUI] Could not create " .. tostring(targetRig) .. " viewport rig:", clone)
		if H.status then H.status.Text = "Roblox could not build the " .. (targetRig == Enum.HumanoidRigType.R6 and "R6" or "R15") .. " preview" end
		return
	end

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Tool") then
			descendant:Destroy()
		end
	end
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		clone:Destroy()
		warn("[CatalogUI] Generated viewport rig has no HumanoidRootPart")
		return
	end
	clone.PrimaryPart = rootPart
	rootPart.Anchored = true
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function() humanoid.EvaluateStateMachine = false end)
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local oldPreview = previewModel
	previewModel = clone
	clone:PivotTo(CFrame.new())
	clone.Parent = world
	if oldPreview then oldPreview:Destroy() end
	local frame, bounds = clone:GetBoundingBox()
	focus = frame.Position
	local largest = math.max(bounds.X, bounds.Y, bounds.Z, 5.5)
	baseDist = (largest * 0.72) / math.tan(math.rad(cam.FieldOfView / 2))
	H.updateCamera()
	if H.previewIdleTrack then pcall(function() H.previewIdleTrack:Stop(0) end) end
	if H.previewIdleAnimation then pcall(function() H.previewIdleAnimation:Destroy() end) end
	H.previewIdleTrack, H.previewIdleAnimation = nil, nil
	if humanoid then
		H.previewIdleTrack, H.previewIdleAnimation = playAnimationOnHumanoid(humanoid, idleId)
	end
end

local rebuildToken = 0
local function scheduleRebuild(delaySeconds)
	rebuildToken += 1
	local token = rebuildToken
	task.delay(delaySeconds, function() if token == rebuildToken then rebuildViewport() end end)
end
local characterConnections = {}
local wearingRefreshToken = 0
local function watchCharacter(character)
	stopEmotePreview()
	for _, connection in ipairs(characterConnections) do connection:Disconnect() end
	table.clear(characterConnections)
	local function scheduleWearing(delaySeconds)
		wearingRefreshToken += 1
		local token = wearingRefreshToken
		task.delay(delaySeconds or 0.8, function()
			if token == wearingRefreshToken and player.Character == character and refreshLocalWearingSnapshot then
				refreshLocalWearingSnapshot()
			end
		end)
	end
	table.insert(characterConnections, character.DescendantAdded:Connect(function()
		scheduleRebuild(0.55)
		scheduleWearing(1)
	end))
	table.insert(characterConnections, character.DescendantRemoving:Connect(function()
		scheduleRebuild(0.55)
		scheduleWearing(0.8)
	end))
	scheduleRebuild(1)
	scheduleWearing(1.3)
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character) end

local function pointIsOverViewport(point)
	local position, size = viewport.AbsolutePosition, viewport.AbsoluteSize
	return point.X >= position.X and point.X <= position.X + size.X
		and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

dragZone.Active = true
dragZone.InputBegan:Connect(function(input)
	if not main.Visible then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		activeTouch = nil
		lastMousePosition = UserInputService:GetMouseLocation()
	elseif input.UserInputType == Enum.UserInputType.Touch and not activeTouch then
		dragging = true
		activeTouch = input
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false; lastMousePosition = nil
	elseif input.UserInputType == Enum.UserInputType.Touch and input == activeTouch then dragging = false; activeTouch = nil end
end)
UserInputService.InputChanged:Connect(function(input)
	if not main.Visible then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if pointIsOverViewport(UserInputService:GetMouseLocation()) then
			zoom = math.clamp(zoom * math.exp(-input.Position.Z * 0.12), 0.4, 1.8)
			H.updateCamera()
		end
	elseif dragging and activeTouch and input.UserInputType == Enum.UserInputType.Touch and input == activeTouch then
		applyOrbitDelta(Vector2.new(input.Delta.X, input.Delta.Y))
	end
end)
RunService.RenderStepped:Connect(function(deltaTime)
	if dragging and not activeTouch and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		local position = UserInputService:GetMouseLocation()
		if lastMousePosition then applyOrbitDelta(position - lastMousePosition) end
		lastMousePosition = position
	end
	if H.activeEmote then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			stopEmotePreview()
			if H.status then H.status.Text = "Animation stopped because the character is no longer available" end
		end
	end
	if autoRotate and not dragging and main.Visible and previewModel then
		yaw = (yaw + deltaTime * 0.6) % (math.pi * 2)
		H.updateCamera()
	end
end)
spinBtn.Activated:Connect(function()
	autoRotate = not autoRotate
	spinBtn.Text = autoRotate and "Auto-rotate: On" or "Auto-rotate: Off"
end)
resetViewBtn.Activated:Connect(function() yaw, pitch, zoom = 0, 0, 1; H.updateCamera() end)
local rigSwitchBusy = false
local function updateRigToggleLabel()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		H.previewRigType = humanoid.RigType
		H.rigToggleBtn.Text = humanoid.RigType == Enum.HumanoidRigType.R6 and "Rig: R6" or "Rig: R15"
	else
		H.rigToggleBtn.Text = "Rig: ..."
	end
end

H.rigToggleBtn.Activated:Connect(function()
	if rigSwitchBusy then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		if H.status then H.status.Text = "Your character is not ready yet." end
		return
	end

	local targetRig = humanoid.RigType == Enum.HumanoidRigType.R15 and "R6" or "R15"
	rigSwitchBusy = true
	H.rigToggleBtn.Active = false
	H.rigToggleBtn.Text = "Switching..."
	if H.status then
		H.status.Text = "Changing your actual character to " .. targetRig .. "..."
	end

	task.spawn(function()
		local invokeOk, success, rigName, message = pcall(function()
			return rigSwitchRemote:InvokeServer(targetRig)
		end)
		rigSwitchBusy = false
		H.rigToggleBtn.Active = true

		if not invokeOk then
			warn("[CatalogUI] Character rig switch request failed:", success)
			updateRigToggleLabel()
			if H.status then H.status.Text = "Rig switch failed. Check that CatalogRigSwitch is installed in ServerScriptService." end
			return
		end
		if not success then
			updateRigToggleLabel()
			if H.status then H.status.Text = tostring(message or "Roblox could not change your character rig.") end
			return
		end

		local newCharacter = player.Character
		local newHumanoid = newCharacter and newCharacter:FindFirstChildOfClass("Humanoid")
		if not newHumanoid or (rigName and newHumanoid.RigType.Name ~= rigName) then
			newCharacter = player.CharacterAdded:Wait()
			newHumanoid = newCharacter:WaitForChild("Humanoid", 10)
		end
		if newHumanoid then
			H.previewRigType = newHumanoid.RigType
			H.rigToggleBtn.Text = newHumanoid.RigType == Enum.HumanoidRigType.R6 and "Rig: R6" or "Rig: R15"
			local camera = workspace.CurrentCamera
			if camera then camera.CameraSubject = newHumanoid end
		else
			updateRigToggleLabel()
		end
		yaw, pitch, zoom = 0, 0, 1
		if H.status then H.status.Text = tostring(message or ("Your character is now " .. tostring(rigName) .. ".")) end
		scheduleRebuild(0.15)
	end)
end)

player.CharacterAdded:Connect(function()
	task.defer(updateRigToggleLabel)
end)
task.defer(updateRigToggleLabel)

local center = H.mkPanel(main, 420, 48, 1480, 1008)
RunService.Heartbeat:Wait()
mainCloseBtn.Parent = center
H.setLayout(mainCloseBtn, "Size", UDim2.fromOffset(48, 44))
H.setLayout(mainCloseBtn, "Position", UDim2.new(1, -58, 0, 8))
mainCloseBtn.ZIndex = 8

local tabBar = H.new("ScrollingFrame", {
	Name = "CatalogTabBar", Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -84, 0, 54),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.X, ScrollingEnabled = true,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
}, center)
H.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, tabBar)
H.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local tabButtons = {}
for index, tab in ipairs(TABS) do
	local button = H.new("TextButton", {
		Text = tab.name, BackgroundTransparency = 1, Size = UDim2.fromOffset(126, 54),
		Font = FM, TextSize = 16, TextColor3 = C.sub, AutoButtonColor = false, LayoutOrder = index,
	}, tabBar)
	H.applyTouchScale(button, 1.06)
	local underline = H.new("Frame", {
		BackgroundColor3 = C.accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(1, -26, 0, 3), Visible = false,
	}, button)
	tabButtons[index] = { btn = button, ul = underline }
end
H.new("Frame", {
	BackgroundColor3 = C.line, BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 1),
}, center)
local filterRow = H.new("Frame", {
	BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 76), Size = UDim2.new(1, -28, 0, 40),
}, center)
H.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
}, filterRow)
local searchBox = H.mkBox(filterRow, "Search catalog", 365, 40)
local sortBtn = H.mkButton(filterRow, "", 136, 40)
local saleBtn = H.mkButton(filterRow, "", 118, 40)
local offBtn = H.mkButton(filterRow, "", 125, 40)
local minBox = H.mkBox(filterRow, "Min R$", 90, 40)
local maxBox = H.mkBox(filterRow, "Max R$", 90, 40)
local creatorBox = H.mkBox(filterRow, "Creator", 180, 40)
H.setTextSize(minBox, 14)
H.setTextSize(maxBox, 14)
for index, object in ipairs({ searchBox, sortBtn, saleBtn, offBtn, minBox, maxBox, creatorBox }) do object.LayoutOrder = index end

local sortMenu = H.new("Frame", {
	Name = "SortOptionsMenu", Position = UDim2.fromOffset(387, 120),
	Size = UDim2.fromOffset(150, #SORTS * 34 + 8), BackgroundColor3 = C.panel,
	BorderSizePixel = 0, Visible = false, ZIndex = 40,
}, center)
H.round(sortMenu, 8)
H.stroke(sortMenu)
H.new("UIPadding", {
	PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
}, sortMenu)
H.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
}, sortMenu)
local sortOptionButtons = {}
for index, sort in ipairs(SORTS) do
	local option = H.mkButton(sortMenu, sort.label, 140, 30)
	option.LayoutOrder = index
	option.ZIndex = 41
	option.Activated:Connect(function()
		state.sort = index
		sortMenu.Visible = false
		H.refreshFilterLabels()
		if TABS[curTab].kind == "catalog" then H.load() end
	end)
	table.insert(sortOptionButtons, option)
end

local linkRow = H.new("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 124),
	Size = UDim2.new(1, -28, 0, 38),
}, center)

local linkLabel = H.label(linkRow, "Item ID/Link", 0, 0, 105, 38, 11, C.sub, FB)
linkLabel.TextYAlignment = Enum.TextYAlignment.Center

local urlBox = H.mkBox(linkRow, "Item ID or URL", 850, 38)
H.setLayout(urlBox, "Position", UDim2.fromOffset(112, 0))

local publicAvatarRow = H.new("Frame", {
	Name = "PublicAvatarSearchRow",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 124),
	Size = UDim2.new(1, -28, 0, 38),
	Visible = false,
}, center)

local publicAvatarUserBox = H.mkBox(publicAvatarRow, "Username", 300, 38)

local inspectPublicAvatarBtn = H.mkButton(
	publicAvatarRow, "Public inventory", 150, 38
)
H.setLayout(inspectPublicAvatarBtn, "Position", UDim2.fromOffset(310, 0))

local publicOutfitsBtn = H.mkButton(
	publicAvatarRow, "Search outfits", 150, 38
)
H.setLayout(publicOutfitsBtn, "Position", UDim2.fromOffset(478, 0))

local myOutfitsBtn = H.mkButton(
	publicAvatarRow, "My outfits", 150, 38
)
H.setLayout(myOutfitsBtn, "Position", UDim2.fromOffset(646, 0))

H.publicSearchLocked = false

-- Only these two buttons are locked during public searches.
H.publicSearchButtons = {
	inspectPublicAvatarBtn,
	publicOutfitsBtn,
}

H.setPublicSearchLocked = function(locked)
	H.publicSearchLocked = locked == true

	publicAvatarUserBox.TextEditable = not H.publicSearchLocked

	for _, button in ipairs(H.publicSearchButtons) do
		button.Active = not H.publicSearchLocked
		button.Selectable = not H.publicSearchLocked
		button.AutoButtonColor = not H.publicSearchLocked
		button.TextColor3 = H.publicSearchLocked and C.sub or C.text
	end

	-- My outfits is always available.
	myOutfitsBtn.Active = true
	myOutfitsBtn.Selectable = true
	myOutfitsBtn.AutoButtonColor = true
	myOutfitsBtn.TextColor3 = C.text
end

-- Client-side rate-limit countdown.
H.publicRateLimitToken = 0

H.startPublicSearchCooldown = function(seconds)
	H.publicRateLimitToken += 1

	local token = H.publicRateLimitToken

	H.publicRateLimitRemaining = math.clamp(
		math.ceil(tonumber(seconds) or 60),
		1,
		300
	)

	H.setPublicSearchLocked(true)

	task.spawn(function()
		while H.publicRateLimitRemaining > 0
			and token == H.publicRateLimitToken do

			if H.status then
				H.status.Text = "Rate limited, waiting ("
					.. tostring(H.publicRateLimitRemaining)
					.. " seconds)."
			end

			task.wait(1)

			if token ~= H.publicRateLimitToken then
				return
			end

			H.publicRateLimitRemaining -= 1
		end

		if token == H.publicRateLimitToken then
			H.setPublicSearchLocked(false)

			if H.status then
				H.status.Text = "You can search again."
			end
		end
	end)
end

local chipHolder = H.new("ScrollingFrame", {
	Name = "CategoryChips", BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 170), Size = UDim2.new(1, -28, 0, 40),
	ClipsDescendants = true, BorderSizePixel = 0, ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.line, ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollingEnabled = true, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
}, center)
H.new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2) }, chipHolder)
H.new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder,
}, chipHolder)

local results = H.new("ScrollingFrame", {
	Position = UDim2.fromOffset(14, 218), Size = UDim2.new(1, -28, 1, -262),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = UserInputService.TouchEnabled and 16 or 12,
	ScrollBarImageColor3 = C.line, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.None, ScrollingDirection = Enum.ScrollingDirection.Y,
	ClipsDescendants = true,
}, center)

local resultsPadding = H.new("UIPadding", {
	PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
}, results)
state.catalogLayout = { columns = 8, gap = 5, cellHeight = 220, cellWidth = 1 }
H.resultsGrid = H.new("UIGridLayout", {
	CellSize = UDim2.fromOffset(1, 1),
	CellPadding = UDim2.fromOffset(5, 5),
	FillDirectionMaxCells = state.catalogLayout.columns, SortOrder = Enum.SortOrder.LayoutOrder,
}, results)

H.inventoryCanvasItemCount = nil

local publicInventoryViewActive = false
local publicInventoryAllItems = {}
local publicInventoryItems = {}
local publicInventoryRequestId = nil
local publicInventoryStreamRequestId = nil
local publicInventoryReceivedCount = 0
local publicInventoryUsername = ""

function H.getCatalogUiScale()
	return math.max(0.30, math.min(root.AbsoluteSize.X / 1920, root.AbsoluteSize.Y / 1080))
end
function H.updateResultsCanvas()
	if not results.Parent then return end
	local itemCount = 0
	if (publicInventoryViewActive or (TABS[curTab] and TABS[curTab].kind == "inventory"))
		and H.inventoryCanvasItemCount ~= nil then
		itemCount = math.max(0, H.inventoryCanvasItemCount)
	else
		for _, child in ipairs(results:GetChildren()) do
			if child:IsA("GuiButton") and child.Visible then itemCount += 1 end
		end
	end
	local rows = math.ceil(itemCount / state.catalogLayout.columns)
	local cellHeight = H.resultsGrid.CellSize.Y.Offset
	local rowGap = H.resultsGrid.CellPadding.Y.Offset
	local topPadding = resultsPadding.PaddingTop.Offset
	local bottomPadding = resultsPadding.PaddingBottom.Offset
	local contentHeight = topPadding + bottomPadding
	if rows > 0 then contentHeight += rows * cellHeight + (rows - 1) * rowGap end
	local targetHeight = math.max(results.AbsoluteSize.Y, contentHeight)
	local oldY = results.CanvasPosition.Y
	if math.abs(results.CanvasSize.Y.Offset - targetHeight) > 1 then
		results.CanvasSize = UDim2.fromOffset(0, targetHeight)
	end
	local maximumY = math.max(0, targetHeight - results.AbsoluteSize.Y)
	local clampedY = math.clamp(oldY, 0, maximumY)
	if math.abs(clampedY - oldY) > 1 then results.CanvasPosition = Vector2.new(0, clampedY) end
end
function H.updateResultsGridSizing()
	if not results.Parent then return end
	local scale = H.getCatalogUiScale()

	resultsPadding.PaddingLeft = UDim.new(0, 8 * scale)
	resultsPadding.PaddingTop = UDim.new(0, 4 * scale)
	resultsPadding.PaddingRight = UDim.new(0, 8 * scale)
	resultsPadding.PaddingBottom = UDim.new(0, 8 * scale)
	local columns, gap = state.catalogLayout.columns, state.catalogLayout.gap
	local horizontalPadding = 16 * scale
	local gaps = math.max(0, columns - 1) * gap * scale
	local available = math.max(columns, results.AbsoluteSize.X - horizontalPadding - results.ScrollBarThickness - gaps)
	local cellWidthPixels = available / columns
	state.catalogLayout.cellWidth = cellWidthPixels / scale
	H.resultsGrid.CellSize = UDim2.fromOffset(cellWidthPixels, state.catalogLayout.cellHeight * scale)
	H.resultsGrid.CellPadding = UDim2.fromOffset(gap * scale, gap * scale)
	task.defer(H.updateResultsCanvas)
end
H.resultsCullQueued = false
H.updateResultsTileVisibility = function()
	if not results.Parent then return end
	local viewportTop = results.AbsolutePosition.Y + resultsPadding.PaddingTop.Offset
	local viewportBottom = results.AbsolutePosition.Y + results.AbsoluteSize.Y - resultsPadding.PaddingBottom.Offset
	local overscan = math.max(H.resultsGrid.CellSize.Y.Offset * 1.4, results.AbsoluteSize.Y * 0.12)
	local resultsActive = results.Visible
	for _, tile in ipairs(results:GetChildren()) do
		if tile:IsA("GuiButton") then
			local content = tile:FindFirstChild("TileContent")
			if content then
				local tileTop = tile.AbsolutePosition.Y
				local tileBottom = tileTop + tile.AbsoluteSize.Y
				local inRange = resultsActive and tile.Visible
					and tileBottom >= viewportTop - overscan and tileTop <= viewportBottom + overscan
				content.Visible = inRange
				tile.BackgroundTransparency = inRange and 0 or 1
				tile.Active = inRange
				local stroke = tile:FindFirstChildOfClass("UIStroke")
				if stroke then
					local hovered = tile:GetAttribute("CatalogHovered") == true
					stroke.Transparency = inRange and (hovered and 0.05 or 0.45) or 1
					stroke.Color = hovered and C.accent or C.line
				end
			end
		end
	end
end
H.scheduleResultsTileVisibility = function()
	if H.resultsCullQueued then return end
	H.resultsCullQueued = true
	task.delay(0.045, function()
		H.resultsCullQueued = false
		H.updateResultsTileVisibility()
	end)
end
results.AutomaticCanvasSize = Enum.AutomaticSize.None
H.resultsGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(H.updateResultsCanvas)
results:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	H.updateResultsGridSizing()
	H.scheduleResultsTileVisibility()
end)
results:GetPropertyChangedSignal("CanvasPosition"):Connect(H.scheduleResultsTileVisibility)
results:GetPropertyChangedSignal("Visible"):Connect(H.scheduleResultsTileVisibility)
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(H.updateResultsGridSizing)
H.updateResultsGridSizing()
local bodyColorPane = H.new("ScrollingFrame", {
	Name = "BodyColorCatalogPane", Position = results.Position, Size = results.Size,
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8,
	ScrollBarImageColor3 = C.line, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	Visible = false, ClipsDescendants = true,
}, center)
local bodyScalePane = H.new("ScrollingFrame", {
	Name = "BodyScalingCatalogPane", Position = results.Position, Size = results.Size,
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8,
	ScrollBarImageColor3 = C.line, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	Visible = false, ClipsDescendants = true,
}, center)
H.status = { Text = "" }

local detailOverlay = H.new("Frame", {
	Name = "CatalogItemDetailsOverlay", Position = center.Position, Size = center.Size,
	BackgroundColor3 = C.panel, BackgroundTransparency = 0.015,
	BorderSizePixel = 0, Visible = false, ZIndex = 30,

	Active = true,
}, main)
H.round(detailOverlay, 14)
H.new("UIStroke", { Color = C.line, Thickness = 1.5 }, detailOverlay)

local detailInputShield = H.new("TextButton", {
	Name = "DetailOverlayInputShield",
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	Active = true,
	Selectable = false,
	ZIndex = 30,
}, detailOverlay)
local detailTitle = H.label(detailOverlay, "Item details", 24, 18, 1180, 46, 31, C.text, FB)
detailTitle.ZIndex = 31
local detailCloseBtn = H.mkButton(detailOverlay, "×", 52, 48, C.card)
H.setLayout(detailCloseBtn, "Position", UDim2.new(1, -72, 0, 12))
H.setTextSize(detailCloseBtn, 30)
detailCloseBtn.ZIndex = 32
detailCloseBtn.Name = "CloseItemDetailsButton"
detailCloseBtn.AutoButtonColor = true
local detailImage = H.new("ImageLabel", {
	Name = "DetailItemImage", Position = UDim2.fromOffset(28, 84), Size = UDim2.fromOffset(410, 410),
	BackgroundColor3 = C.field, BorderSizePixel = 0, ScaleType = Enum.ScaleType.Fit, Image = "", ZIndex = 31,
}, detailOverlay)
H.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, detailImage)
H.round(detailImage, 12)
local detailType = H.label(detailOverlay, "", 474, 92, 880, 30, 19, C.text, FB)
detailType.ZIndex = 31
local detailInfo = H.label(detailOverlay, "Loading item information...", 474, 132, 880, 116, 20, C.text, FM)
detailInfo.TextWrapped = true
detailInfo.TextYAlignment = Enum.TextYAlignment.Top
detailInfo.TextTruncate = Enum.TextTruncate.None
detailInfo.ZIndex = 31
local detailDescription = H.label(detailOverlay, "", 474, 262, 880, 418, 19, C.sub, F)
detailDescription.TextWrapped = true
detailDescription.TextYAlignment = Enum.TextYAlignment.Top
detailDescription.TextTruncate = Enum.TextTruncate.None
detailDescription.ZIndex = 31
local bundleItemsTitle = H.label(detailOverlay, "ITEMS INCLUDED IN THIS BUNDLE", 474, 262, 880, 30, 18, C.text, FB)
bundleItemsTitle.ZIndex = 31
bundleItemsTitle.Visible = false
local bundleItemsScroll = H.new("ScrollingFrame", {
	Name = "BundleContents", Position = UDim2.fromOffset(474, 300), Size = UDim2.fromOffset(880, 422),
	BackgroundColor3 = C.field, BackgroundTransparency = 0.15, BorderSizePixel = 0,
	ScrollBarThickness = 8, ScrollBarImageColor3 = C.sub,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.None,
	ScrollingDirection = Enum.ScrollingDirection.Y, ScrollingEnabled = true,
	Visible = false, ZIndex = 31, ClipsDescendants = true,
}, detailOverlay)
H.round(bundleItemsScroll, 10)
local bundleItemsGrid = H.new("UIGridLayout", {
	CellSize = UDim2.fromOffset(280, 112), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder,
}, bundleItemsScroll)
local bundleItemsPadding = H.new("UIPadding", {
	PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
}, bundleItemsScroll)

local function updateBundleGridSizing()
	local scale = math.max(0.30, math.min(root.AbsoluteSize.X / 1920, root.AbsoluteSize.Y / 1080))
	if scale <= 0 then scale = 1 end
	bundleItemsGrid.CellSize = UDim2.fromOffset(280 * scale, 112 * scale)
	bundleItemsGrid.CellPadding = UDim2.fromOffset(8 * scale, 8 * scale)
	local padding = math.floor(8 * scale + 0.5)
	bundleItemsPadding.PaddingLeft = UDim.new(0, padding)
	bundleItemsPadding.PaddingRight = UDim.new(0, padding)
	bundleItemsPadding.PaddingTop = UDim.new(0, padding)
	bundleItemsPadding.PaddingBottom = UDim.new(0, padding)
end
updateBundleGridSizing()
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateBundleGridSizing)
local detailBuyBtn = H.mkButton(detailOverlay, "Buy", 200, 56, C.success)
H.setLayout(detailBuyBtn, "Position", UDim2.fromOffset(474, 748))
detailBuyBtn.ZIndex = 32
local detailWearBtn = H.mkButton(detailOverlay, "Wear / Preview", 250, 56)
H.setLayout(detailWearBtn, "Position", UDim2.fromOffset(690, 748))
detailWearBtn.ZIndex = 32
local detailFootnote = H.label(detailOverlay, "Close to return to the catalog.", 474, 816, 880, 30, 17, C.sub, F)
detailFootnote.ZIndex = 31

do
	H.saveOverlay = H.new("Frame", {
		Name = "SaveToRobloxReviewOverlay", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.32,
		BorderSizePixel = 0, Visible = false, Active = true, ZIndex = 60,
	}, main)
	local shield = H.new("TextButton", {
		Name = "SaveOverlayInputShield", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", Active = true,
		AutoButtonColor = false, Selectable = false, ZIndex = 60,
	}, H.saveOverlay)
	H.savePanel = H.new("Frame", {
		Name = "SaveToRobloxPanel", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(900, 760),
		BackgroundColor3 = C.panel, BorderSizePixel = 0, Active = true, ZIndex = 61,
	}, H.saveOverlay)
	H.round(H.savePanel, 14)
	H.stroke(H.savePanel)
	H.saveTitle = H.label(H.savePanel, "SAVE TO ROBLOX", 24, 16, 760, 38, 24, C.text, FB)
	H.saveTitle.ZIndex = 62
	H.saveHint = H.label(H.savePanel, "Choose the owned item cards to include in the saved avatar or outfit.", 24, 56, 820, 34, 14, C.sub, F)
	H.saveHint.TextWrapped = true
	H.saveHint.ZIndex = 62
	H.saveCloseBtn = H.mkButton(H.savePanel, "×", 44, 40, C.card)
	H.setLayout(H.saveCloseBtn, "Position", UDim2.new(1, -58, 0, 12))
	H.saveCloseBtn.ZIndex = 64
	H.saveSelectAllBtn = H.mkButton(H.savePanel, "Select all owned", 170, 34, C.card)
	H.setLayout(H.saveSelectAllBtn, "Position", UDim2.fromOffset(24, 98))
	H.saveSelectAllBtn.ZIndex = 64
	H.saveSelectNoneBtn = H.mkButton(H.savePanel, "Select none", 140, 34, C.card)
	H.setLayout(H.saveSelectNoneBtn, "Position", UDim2.fromOffset(204, 98))
	H.saveSelectNoneBtn.ZIndex = 64
	H.saveCount = H.label(H.savePanel, "0 selected", 370, 98, 500, 34, 14, C.sub, FB)
	H.saveCount.ZIndex = 62
	H.saveList = H.new("ScrollingFrame", {
		Name = "OwnedAvatarItemsList", Position = UDim2.fromOffset(24, 142), Size = UDim2.fromOffset(852, 500),
		BackgroundColor3 = C.field, BackgroundTransparency = 0.1, BorderSizePixel = 0,
		ScrollBarThickness = UserInputService.TouchEnabled and 8 or 6, ScrollBarImageColor3 = C.sub,
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, ZIndex = 62,
	}, H.savePanel)
	H.round(H.saveList, 10)
	H.new("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	}, H.saveList)

	H.saveListLayout = H.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(400, 116),
		CellPadding = UDim2.fromOffset(8, 8),
		FillDirectionMaxCells = 2,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, H.saveList)
	H.saveAvatarBtn = H.mkButton(H.savePanel, "Save as Avatar", 210, 46, C.success)
	H.setLayout(H.saveAvatarBtn, "Position", UDim2.fromOffset(24, 670))
	H.saveAvatarBtn.ZIndex = 64
	H.saveOutfitBtn = H.mkButton(H.savePanel, "Save as Outfit", 210, 46, C.accent)
	H.setLayout(H.saveOutfitBtn, "Position", UDim2.fromOffset(250, 670))
	H.saveOutfitBtn.ZIndex = 64
	H.saveCancelBtn = H.mkButton(H.savePanel, "Cancel", 150, 46, C.card)
	H.setLayout(H.saveCancelBtn, "Position", UDim2.fromOffset(726, 670))
	H.saveCancelBtn.ZIndex = 64
end

local busy = false
local busyToken = 0
local activeRequestId
local lastName = ""
local updateBodyScaleInputs
local function setStatus(message)
	if H.status then H.status.Text = message end
end

local function beginBusy(message)
	if busy then return nil end
	busy = true
	busyToken += 1
	local requestId = busyToken
	activeRequestId = requestId
	setStatus(message)
	task.delay(35, function()
		if activeRequestId == requestId and busy then
			busy = false
			activeRequestId = nil

			H.setPublicSearchLocked(false)

			setStatus("Timed out. You can try again.")
		end
	end)
	return requestId
end
local function failBusy(requestId, message)
	warn("[CatalogUI] " .. tostring(message))

	if activeRequestId == requestId and busy then
		busy = false
		activeRequestId = nil

		H.setPublicSearchLocked(false)

		setStatus(message)
	end
end

local function buildBodyColorControls()
	local bodyColorTitle = H.label(bodyColorPane, "Custom body colors", 12, 12, 700, 32, 22, C.text, FB)
	local bodyColorHelp = H.label(bodyColorPane, "Choose a body part, pick a color with the wheel, then press Apply.", 12, 46, 1100, 24, 13, C.sub, F)
	local BODY_COLOR_TARGETS = {
		{ label = "All parts", key = "All" }, { label = "Head", key = "Head" },
		{ label = "Torso", key = "Torso" }, { label = "Left arm", key = "LeftArm" },
		{ label = "Right arm", key = "RightArm" }, { label = "Left leg", key = "LeftLeg" },
		{ label = "Right leg", key = "RightLeg" },
	}
	local selectedBodyColorTarget = "All"
	local bodyColorTargetButtons = {}

	local function sendBodyColor(color)
		local requestId = beginBusy("Applying body color...")
		if not requestId then return end
		if selectedBodyColorTarget == "All" then remote:FireServer("Skin", color, nil, requestId)
		else remote:FireServer("SkinPart", selectedBodyColorTarget, color, requestId) end
	end

	for index, target in ipairs(BODY_COLOR_TARGETS) do
		local button = H.mkButton(bodyColorPane, target.label, 142, 34, target.key == selectedBodyColorTarget and C.accent or C.card)
		H.setLayout(button, "Position", UDim2.fromOffset(18 + (index - 1) * 151, 82))
		button.Activated:Connect(function()
			selectedBodyColorTarget = target.key
			for _, entry in ipairs(bodyColorTargetButtons) do
				entry.button.BackgroundColor3 = entry.key == selectedBodyColorTarget and C.accent or C.card
			end
		end)
		table.insert(bodyColorTargetButtons, { button = button, key = target.key })
	end

	local selectedColor = Color3.new(1, 1, 1)
	local selectedHue, selectedSaturation, selectedValue = 0, 0, 1
	local customColorButton = H.new("TextButton", {
		Name = "CustomColorWheelButton", Text = "", 
		Position = UDim2.fromOffset(18, 130), Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = selectedColor, TextColor3 = C.text, Font = FB, TextSize = 12,
		AutoButtonColor = false, BorderSizePixel = 0,
	}, bodyColorPane)
	H.applyTouchScale(customColorButton, 1.04)
	H.round(customColorButton, 6)
	H.stroke(customColorButton)
	H.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, customColorButton)
	local rgbFields = {}
	for index, channel in ipairs({"R", "G", "B"}) do
		local x = 70 + (index - 1) * 78
		local channelLabel = H.label(bodyColorPane, channel, x, 132, 16, 36, 14, C.text, FB)
		channelLabel.TextXAlignment = Enum.TextXAlignment.Center
		local field = H.new("TextBox", {
			Name = "CustomColor" .. channel, Text = "255", PlaceholderText = "0-255",
			Position = UDim2.fromOffset(x + 19, 132), Size = UDim2.fromOffset(54, 36),
			BackgroundColor3 = C.field, TextColor3 = C.text, PlaceholderColor3 = C.sub,
			Font = FB, TextSize = 15, ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Center, BorderSizePixel = 0,
		}, bodyColorPane)
		H.round(field, 7)
		H.stroke(field)
		table.insert(rgbFields, field)
	end
	local applyCustomColorBtn = H.mkButton(bodyColorPane, "Apply color", 126, 42, C.accent)
	H.setLayout(applyCustomColorBtn, "Position", UDim2.fromOffset(314, 130))

	local pickerPanel = H.new("Frame", {
		Name = "BodyColorWheelPopup", Position = UDim2.fromOffset(18, 176),
		Size = UDim2.fromOffset(430, 238), BackgroundColor3 = C.panel,
		BorderSizePixel = 0, Visible = false, ZIndex = 20, Active = true,
	}, bodyColorPane)
	H.round(pickerPanel, 12)
	H.new("UIStroke", { Color = C.line, Thickness = 1.5 }, pickerPanel)
	local pickerTitle = H.label(pickerPanel, "COLOR PICKER", 14, 7, 250, 22, 13, C.text, FB)
	pickerTitle.ZIndex = 22
	local pickerClose = H.mkButton(pickerPanel, "×", 32, 28, C.card)
	H.setLayout(pickerClose, "Position", UDim2.fromOffset(386, 5))
	pickerClose.ZIndex = 24
	pickerClose.Activated:Connect(function() pickerPanel.Visible = false end)

	local wheelArea = H.new("Frame", {
		Name = "HueWheelInput", Position = UDim2.fromOffset(8, 30),
		Size = UDim2.fromOffset(184, 184), BackgroundTransparency = 1,
		BorderSizePixel = 0, Active = true, ZIndex = 21,
	}, pickerPanel)
	local wheelCenter = Vector2.new(92, 92)
	local wheelRadius = 77
	local HUE_SEGMENTS = 720
	for index = 0, HUE_SEGMENTS - 1 do
		local hue = index / HUE_SEGMENTS
		local angle = hue * math.pi * 2
		local segment = H.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(
				wheelCenter.X + math.cos(angle) * wheelRadius,
				wheelCenter.Y + math.sin(angle) * wheelRadius
			),
			Size = UDim2.fromOffset(2.2, 16),
			Rotation = math.deg(angle) + 90,
			BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
			BorderSizePixel = 0, ZIndex = 22,
		}, wheelArea)
		H.round(segment, 1)
	end
	local hueMarker = H.new("Frame", {
		Name = "HueWheelMarker", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(wheelCenter.X + wheelRadius, wheelCenter.Y),
		Size = UDim2.fromOffset(15, 15), BackgroundColor3 = selectedColor, BackgroundTransparency = 0,
		BorderSizePixel = 0, ZIndex = 25,
	}, wheelArea)
	H.round(hueMarker, 8)
	H.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, hueMarker)
	local wheelInput = H.new("TextButton", {
		Name = "HueWheelHitTarget", Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, Active = true, ZIndex = 24,
	}, wheelArea)

	local saturationValue = H.new("Frame", {
		Name = "SaturationValueField", Position = UDim2.fromOffset(220, 40),
		Size = UDim2.fromOffset(188, 166), BackgroundColor3 = Color3.fromHSV(0, 1, 1),
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 21,
	}, pickerPanel)
	H.round(saturationValue, 8)
	local whiteLayer = H.new("Frame", {
		Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 22,
	}, saturationValue)
	H.new("UIGradient", {
		Rotation = 0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, whiteLayer)
	local blackLayer = H.new("Frame", {
		Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 23,
	}, saturationValue)
	H.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, blackLayer)
	local svMarker = H.new("Frame", {
		Name = "SaturationValueMarker", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0), Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 26,
	}, saturationValue)
	H.round(svMarker, 8)
	H.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, svMarker)
	local svInput = H.new("TextButton", {
		Name = "SaturationValueHitTarget", Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = "", AutoButtonColor = false, Active = true, ZIndex = 25,
	}, saturationValue)

	local function updateColorDisplay()
		selectedColor = Color3.fromHSV(selectedHue, selectedSaturation, selectedValue)
		local red = math.floor(selectedColor.R * 255 + 0.5)
		local green = math.floor(selectedColor.G * 255 + 0.5)
		local blue = math.floor(selectedColor.B * 255 + 0.5)
		customColorButton.BackgroundColor3 = selectedColor
		if not rgbFields[1]:IsFocused() then rgbFields[1].Text = tostring(red) end
		if not rgbFields[2]:IsFocused() then rgbFields[2].Text = tostring(green) end
		if not rgbFields[3]:IsFocused() then rgbFields[3].Text = tostring(blue) end
		saturationValue.BackgroundColor3 = Color3.fromHSV(selectedHue, 1, 1)
		hueMarker.BackgroundColor3 = selectedColor
		hueMarker.Position = UDim2.fromScale(
			0.5 + math.cos(selectedHue * math.pi * 2) * (wheelRadius / 184),
			0.5 + math.sin(selectedHue * math.pi * 2) * (wheelRadius / 184)
		)
		svMarker.Position = UDim2.fromScale(selectedSaturation, 1 - selectedValue)
	end

	local function setHueFromPosition(position)
		local center = wheelArea.AbsolutePosition + wheelArea.AbsoluteSize / 2
		local delta = Vector2.new(position.X, position.Y) - center
		selectedHue = (math.atan2(delta.Y, delta.X) / (math.pi * 2)) % 1
		updateColorDisplay()
	end
	local function setSaturationValueFromPosition(position)
		local absolutePosition = saturationValue.AbsolutePosition
		local size = saturationValue.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		selectedSaturation = math.clamp((position.X - absolutePosition.X) / size.X, 0, 1)
		selectedValue = 1 - math.clamp((position.Y - absolutePosition.Y) / size.Y, 0, 1)
		updateColorDisplay()
	end

	local function applyRGBFieldValues()
		local values = {}
		for index, field in ipairs(rgbFields) do
			local number = tonumber(field.Text)
			if not number then
				updateColorDisplay()
				return
			end
			values[index] = math.clamp(math.floor(number + 0.5), 0, 255)
		end
		selectedColor = Color3.fromRGB(values[1], values[2], values[3])
		selectedHue, selectedSaturation, selectedValue = selectedColor:ToHSV()
		updateColorDisplay()
	end
	for _, field in ipairs(rgbFields) do
		field.FocusLost:Connect(applyRGBFieldValues)
	end

	local activePickerControl = nil
	local activePickerTouch = nil
	H.closeBodyColorPicker = function()
		pickerPanel.Visible = false
		activePickerControl = nil
		activePickerTouch = nil
	end
	local function beginPickerDrag(control, input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if control == "Hue" then
			local wheelSize = wheelArea.AbsoluteSize
			local scaleFactor = wheelSize.X / 184
			if scaleFactor <= 0 then return end
			local center = wheelArea.AbsolutePosition + wheelSize / 2
			local delta = Vector2.new(input.Position.X, input.Position.Y) - center
			local radius = delta.Magnitude
			local actualRadius = wheelRadius * scaleFactor
			local tolerance = 18 * scaleFactor
			if radius < actualRadius - tolerance or radius > actualRadius + tolerance then return end
		end
		activePickerControl = control
		activePickerTouch = input.UserInputType == Enum.UserInputType.Touch and input or nil
		if control == "Hue" then setHueFromPosition(input.Position)
		else setSaturationValueFromPosition(input.Position) end
	end
	wheelInput.InputBegan:Connect(function(input) beginPickerDrag("Hue", input) end)
	svInput.InputBegan:Connect(function(input) beginPickerDrag("SV", input) end)
	UserInputService.InputChanged:Connect(function(input)
		if not activePickerControl then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or (activePickerTouch and input.UserInputType == Enum.UserInputType.Touch) then
			if activePickerControl == "Hue" then setHueFromPosition(input.Position)
			else setSaturationValueFromPosition(input.Position) end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or (activePickerTouch and input == activePickerTouch) then
			activePickerControl = nil
			activePickerTouch = nil
		end
	end)

	customColorButton.Activated:Connect(function()
		pickerPanel.Visible = not pickerPanel.Visible
		if pickerPanel.Visible then updateColorDisplay() end
	end)
	applyCustomColorBtn.Activated:Connect(function()
		pickerPanel.Visible = false
		sendBodyColor(selectedColor)
	end)

	local brickColorsByNumber = {}
	local function addBrickColor(brickColor)
		if typeof(brickColor) == "BrickColor" and brickColor.Number > 0 then
			brickColorsByNumber[brickColor.Number] = brickColor
		end
	end
	for number = 1, 1200 do
		local ok, brickColor = pcall(function() return BrickColor.new(number) end)
		if ok and brickColor and brickColor.Number == number then addBrickColor(brickColor) end
	end
	for index = 0, 127 do
		local ok, brickColor = pcall(function() return BrickColor.palette(index) end)
		if ok then addBrickColor(brickColor) end
	end
	local allBrickColors = {}
	for _, brickColor in pairs(brickColorsByNumber) do table.insert(allBrickColors, brickColor) end
	table.sort(allBrickColors, function(a, b) return a.Number < b.Number end)
	local COLOR_CELL, COLOR_GAP, COLOR_COLUMNS = 46, 8, 22
	local colorRows = math.max(1, math.ceil(#allBrickColors / COLOR_COLUMNS))
	local colorGridHeight = colorRows * COLOR_CELL + (colorRows - 1) * COLOR_GAP
	local colorGridHolder = H.new("Frame", {
		Name = "RobloxBrickColorGrid", Position = UDim2.fromOffset(18, 190),
		Size = UDim2.new(1, -36, 0, colorGridHeight), BackgroundTransparency = 1,
	}, bodyColorPane)
	H.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(COLOR_CELL, COLOR_CELL),
		CellPadding = UDim2.fromOffset(COLOR_GAP, COLOR_GAP),
		FillDirectionMaxCells = COLOR_COLUMNS, SortOrder = Enum.SortOrder.LayoutOrder,
	}, colorGridHolder)
	for index, brickColor in ipairs(allBrickColors) do
		local swatch = H.new("TextButton", {
			Name = "CatalogBrickColor_" .. tostring(brickColor.Number), Text = "",
			BackgroundColor3 = brickColor.Color, AutoButtonColor = false, LayoutOrder = index,
		}, colorGridHolder)
		H.round(swatch, 8)
		H.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, swatch)
		H.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.15 }, swatch)
		swatch:SetAttribute("BrickColorName", brickColor.Name)
		swatch:SetAttribute("BrickColorNumber", brickColor.Number)
		swatch.Activated:Connect(function()
			local hue, saturation, value = brickColor.Color:ToHSV()
			selectedHue, selectedSaturation, selectedValue = hue, saturation, value
			updateColorDisplay()
			sendBodyColor(brickColor.Color)
			bodyColorHelp.Text = "Applied palette color: " .. brickColor.Name
		end)
	end
	updateColorDisplay()
end
buildBodyColorControls()


local function buildAvatarScalingControls()

	H.label(bodyScalePane, "Avatar scaling", 12, 12, 700, 32, 22, C.text, FB)
	H.label(bodyScalePane, "Changes apply automatically shortly after you stop moving a slider.", 12, 46, 1100, 24, 13, C.sub, F)
	local scaleFields = {
		{ key = "HeadScale", label = "Head size", default = 100, min = 95, max = 100 },
		{ key = "HeightScale", label = "Height", default = 100, min = 90, max = 105 },
		{ key = "WidthScale", label = "Width", default = 100, min = 70, max = 100 },
		{ key = "ProportionScale", label = "Proportions", default = 0, min = 0, max = 100 },
		{ key = "BodyTypeScale", label = "Body type", default = 0, min = 0, max = 100 },
	}
	local scaleSliders = {}
	local activeScaleSlider = nil
	local activeScaleTouch = nil
	local scaleApplyToken = 0

	local function readScaleValues()
		local values = {}
		for _, entry in ipairs(scaleSliders) do
			values[entry.field.key] = entry.value / 100
		end
		return values
	end

	local function tryApplyScaleValues(token, attempt)
		if token ~= scaleApplyToken then return end
		if busy then
			if attempt < 160 then
				task.delay(0.25, function()
					tryApplyScaleValues(token, attempt + 1)
				end)
			end
			return
		end
		local requestId = beginBusy("Applying avatar scaling...")
		if not requestId then
			if attempt < 160 then
				task.delay(0.25, function()
					tryApplyScaleValues(token, attempt + 1)
				end)
			end
			return
		end
		remote:FireServer("AvatarScale", readScaleValues(), nil, requestId)
	end

	local function scheduleScaleApply()
		scaleApplyToken += 1
		local token = scaleApplyToken
		task.delay(0.28, function()
			tryApplyScaleValues(token, 0)
		end)
	end

	local function setSliderValue(entry, rawValue, shouldApply)
		local field = entry.field
		local numeric = tonumber(rawValue) or field.default
		local value = math.clamp(math.floor(numeric + 0.5), field.min, field.max)
		local changed = entry.value ~= value
		entry.value = value
		entry.valueLabel.Text = tostring(value) .. "%"
		local range = math.max(1, field.max - field.min)
		local alpha = math.clamp((value - field.min) / range, 0, 1)
		entry.fill.Size = UDim2.new(alpha, 0, 1, 0)
		entry.knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		if shouldApply and changed then scheduleScaleApply() end
	end

	local function updateSliderFromX(entry, screenX)
		local track = entry.track
		local width = track.AbsoluteSize.X
		if width <= 0 then return end
		local alpha = math.clamp((screenX - track.AbsolutePosition.X) / width, 0, 1)
		local value = entry.field.min + alpha * (entry.field.max - entry.field.min)
		setSliderValue(entry, value, true)
	end
	for index, field in ipairs(scaleFields) do
		local column = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local x, y = 20 + column * 680, 88 + row * 128
		local card = H.new("Frame", {
			Name = "ScaleSlider_" .. field.key,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(650, 108),
			BackgroundColor3 = C.field,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
		}, bodyScalePane)
		H.round(card, 10)
		H.stroke(card)

		local nameLabel = H.label(card, field.label, 16, 10, 420, 26, 17, C.text, FB)
		nameLabel.ZIndex = 2
		local valueLabel = H.label(card, tostring(field.default) .. "%", 500, 10, 125, 26, 18, C.accent, FB)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.ZIndex = 2

		local hitArea = H.new("TextButton", {
			Name = "SliderHitTarget",
			Position = UDim2.fromOffset(18, 48),
			Size = UDim2.fromOffset(610, 46),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Active = true,
			ZIndex = 3,
		}, card)
		local track = H.new("Frame", {
			Name = "SliderTrack",
			Position = UDim2.fromOffset(8, 17),
			Size = UDim2.new(1, -16, 0, 12),
			BackgroundColor3 = C.line,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 4,
		}, hitArea)
		H.round(track, 8)
		local fill = H.new("Frame", {
			Name = "SliderFill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.accent,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 5,
		}, track)
		H.round(fill, 8)
		local knob = H.new("Frame", {
			Name = "SliderKnob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = C.text,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, track)
		H.round(knob, 12)
		H.new("UIStroke", { Color = C.accent, Thickness = 2 }, knob)
		local entry = {
			field = field,
			value = field.default,
			valueLabel = valueLabel,
			track = track,
			fill = fill,
			knob = knob,
			hitArea = hitArea,
		}
		table.insert(scaleSliders, entry)
		setSliderValue(entry, field.default)

		hitArea.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				activeScaleSlider = entry
				activeScaleTouch = nil
				updateSliderFromX(entry, input.Position.X)
			elseif input.UserInputType == Enum.UserInputType.Touch and not activeScaleTouch then
				activeScaleSlider = entry
				activeScaleTouch = input
				updateSliderFromX(entry, input.Position.X)
			end
		end)
	end

	UserInputService.InputChanged:Connect(function(input)
		local entry = activeScaleSlider
		if not entry then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement and not activeScaleTouch then
			updateSliderFromX(entry, input.Position.X)
		elseif input.UserInputType == Enum.UserInputType.Touch and activeScaleTouch then
			updateSliderFromX(entry, input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not activeScaleTouch then
			activeScaleSlider = nil
		elseif input.UserInputType == Enum.UserInputType.Touch and input == activeScaleTouch then
			activeScaleSlider = nil
			activeScaleTouch = nil
		end
	end)

	local resetScalesBtn = H.mkButton(bodyScalePane, "Reset scaling", 190, 44, C.card)
	H.setLayout(resetScalesBtn, "Position", UDim2.fromOffset(20, 500))
	resetScalesBtn.Activated:Connect(function()
		scaleApplyToken += 1
		for _, entry in ipairs(scaleSliders) do
			setSliderValue(entry, entry.field.default, false)
		end
		scheduleScaleApply()
	end)
	updateBodyScaleInputs = function(values)
		if type(values) ~= "table" then return end
		for _, entry in ipairs(scaleSliders) do
			local value = values[entry.field.key]
			if type(value) == "number" then
				setSliderValue(entry, value * 100, false)
			end
		end
	end
end
buildAvatarScalingControls()

local function resolveAssetType(id)
	local ok, details = pcall(H.callAES, "GetItemDetails", id, Enum.AvatarItemType.Asset)
	if ok and type(details) == "table" then
		local name = H.assetTypeName(details.AssetType)
		if name then return name end
	else
	end
	local infoOk, info = pcall(function() return H.getProductInfo(id, Enum.InfoType.Asset) end)
	if infoOk and type(info) == "table" and info.AssetTypeId then return H.assetTypeName(info.AssetTypeId) end
	return nil
end
local function sendBundle(id, requestId)
	if activeRequestId == requestId then remote:FireServer("Bundle", id, nil, requestId) end
end

local function wearItem(data)
	if type(data) ~= "table" or not tonumber(data.id) then return end

	if not data.background and not data.typeName and data.auto then
		data.typeName = resolveAssetType(data.id)
	end

	if data.background == true or data.typeName == "AvatarBackground" then
		setViewportBackground(data.id)
		setStatus("Previewing background: " .. tostring(data.name or data.id))
		return
	end
	local requestId = beginBusy("Applying " .. tostring(data.name or data.id) .. "...")
	if not requestId then return end
	lastName = data.name
	task.spawn(function()
		local ok, err = pcall(function()
			if data.outfit then remote:FireServer("Outfit", data.id, nil, requestId); return end
			if data.bundle then sendBundle(data.id, requestId); return end
			if data.auto and not data.typeName then remote:FireServer("WearAuto", data.id, nil, requestId); return end
			local typeName = data.typeName or resolveAssetType(data.id)

			if typeName == "AvatarBackground" then
				failBusy(requestId, "Avatar backgrounds can only be previewed")
				setViewportBackground(data.id)
				setStatus("Previewing background: " .. tostring(data.name or data.id))
				return
			end

			if typeName == "DynamicHead" then typeName = "Head" end
			if activeRequestId ~= requestId then return end
			if typeName and typeName ~= "" then
				remote:FireServer("Wear", data.id, typeName, requestId)
			else

				remote:FireServer("WearAuto", data.id, nil, requestId)
			end
		end)
		if not ok then failBusy(requestId, "Couldn't prepare item: " .. tostring(err)) end
	end)
end

local pages
local sourceId = 0
local loadingMore = false
local order = 0
local scrollCheckToken = 0
local equippedIds = {}
local inventoryLoadedById = {}
local sortedInventoryCache = nil
local inventorySortDirty = true
local inventoryCacheReady = false
local inventoryCacheLoading = false
local inventoryCacheError = nil
local inventoryTypesReady = {}
local catalogLoadedById = {}
local resultScrollPositions = {}
local activeInventoryItems = nil
local inventoryRenderedCount = 0
H.inventoryRenderWorkerToken = nil
H.pendingInventoryRenderCount = 0
local INVENTORY_INITIAL_RENDER_COUNT = 32
local INVENTORY_BATCH_SIZE = 100
local INVENTORY_PAGE_DELAY_SECONDS = 0
local renderMoreInventoryTiles
local beginInventoryTileView
local refreshActiveInventoryView
local inventoryViewBuildToken = 0
local inventoryViewRebuilding = false
local bundleProductInfoCache = {}
H.animationPackByAsset = H.animationPackByAsset or {}
H.bundleAssetsByBundle = H.bundleAssetsByBundle or H.animationPackAssetsByBundle or {}
H.animationPackAssetsByBundle = H.bundleAssetsByBundle
H.bundleContentsChecked = H.bundleContentsChecked or H.animationPackChecked or {}
H.animationPackChecked = H.bundleContentsChecked
function H.registerAnimationPack(data)
	if not data or not data.bundle then return end
	local bundleId = tonumber(data.id)
	if not bundleId or bundleId <= 0 or H.bundleContentsChecked[bundleId] then return end
	H.bundleContentsChecked[bundleId] = true
	task.spawn(function()
		local ok, info = pcall(H.callAES, "GetItemDetails", bundleId, Enum.AvatarItemType.Bundle)
		if not ok or type(info) ~= "table" then return end
		local entries = info.BundledItems or info.Items
		if type(entries) ~= "table" then return end
		local bundleAssets = {}
		for _, entry in ipairs(entries) do
			local nested = type(entry.Item) == "table" and entry.Item or (type(entry.Asset) == "table" and entry.Asset or entry)
			local id = tonumber(entry.Id or entry.AssetId or nested.Id or nested.AssetId)
			local itemType = tostring(entry.Type or entry.ItemType or nested.Type or "Asset"):lower()
			if id and id > 0 and itemType:find("asset", 1, true) then
				bundleAssets[id] = true
				H.animationPackByAsset[id] = bundleId
			end
		end
		if next(bundleAssets) then
			H.bundleAssetsByBundle[bundleId] = bundleAssets
			if H.refreshEquippedBadges then H.refreshEquippedBadges() end
		end
	end)
end
local function getResultScrollKey(tabIndex, chipIndex)
	return tostring(tabIndex) .. ":" .. tostring(chipIndex or 1)
end

local function restoreResultsScroll(tabIndex, chipIndex, yPosition, requestSource)
	task.delay(0.08, function()
		if requestSource ~= sourceId or not results.Parent then return end
		local key = getResultScrollKey(tabIndex, chipIndex)
		local maximum = math.max(0, results.AbsoluteCanvasSize.Y - results.AbsoluteSize.Y)
		results.CanvasPosition = Vector2.new(0, math.clamp(tonumber(yPosition) or resultScrollPositions[key] or 0, 0, maximum))
	end)
end

local function bundleFullyEquipped(bundleId)
	local bundleAssets = H.bundleAssetsByBundle and H.bundleAssetsByBundle[tonumber(bundleId)]
	if not bundleAssets then return false end
	local assetCount = 0
	for assetId in pairs(bundleAssets) do
		assetCount += 1
		if equippedIds[assetId] ~= true then return false end
	end
	return assetCount > 0
end
H.isBundleFullyEquipped = bundleFullyEquipped

local function refreshEquippedBadges()
	for _, child in ipairs(results:GetChildren()) do
		if child:IsA("GuiButton") then
			local badge = child:FindFirstChild("EquippedBadge")
			local id = child:GetAttribute("AssetId")
			local isBundle = child:GetAttribute("IsBundle") == true
			local isEquipped = false
			if id ~= nil then
				isEquipped = isBundle and bundleFullyEquipped(id) or (not isBundle and equippedIds[id] == true)
			end
			if badge then badge.Visible = isEquipped end
		end
	end
	if H.refreshBundleContentBadges then H.refreshBundleContentBadges() end
end
H.refreshEquippedBadges = refreshEquippedBadges
H.refreshBackgroundPreviewBadges = function()
	local activeId = tonumber(avatarBackgroundImage:GetAttribute("AssetId"))
	for _, child in ipairs(results:GetChildren()) do
		if child:IsA("GuiButton") then
			local badge = child:FindFirstChild("PreviewBadge")
			if badge then badge.Visible = activeId ~= nil and child:GetAttribute("AssetId") == activeId end
		end
	end
end

local function setEquipped(id, isEquipped)
	if type(id) ~= "number" then return end
	if isEquipped then equippedIds[id] = true else equippedIds[id] = nil end
	refreshEquippedBadges()
end

local function replaceEquippedState(ids, items)
	hasWearingSnapshot = true
	if type(ids) == "table" then
		table.clear(equippedIds)
		for _, id in ipairs(ids) do if type(id) == "number" and id > 0 then equippedIds[id] = true end end
	end
	table.clear(currentEquippedItems)
	local seen = {}
	if type(items) == "table" then
		for _, item in ipairs(items) do
			if type(item) == "table" and type(item.id) == "number" and not seen[item.id] then
				seen[item.id] = true
				table.insert(currentEquippedItems, { id = item.id, typeName = tostring(item.typeName or "Item") })
			end
		end
	end
	if type(ids) == "table" then
		for _, id in ipairs(ids) do
			if type(id) == "number" and id > 0 and not seen[id] then
				seen[id] = true
				table.insert(currentEquippedItems, { id = id, typeName = "Item" })
			end
		end
	end
	refreshEquippedBadges()
	refreshWearingList()
	updateWearingCanvas()
end
refreshLocalWearingSnapshot = function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	local ok, description = pcall(function() return humanoid:GetAppliedDescription() end)
	if not ok or not description then
		warn("[CatalogUI] Local equipped-item snapshot failed:", description)
		return false
	end
	local items, seen = {}, {}
	local function add(idValue, typeName)
		local id = tonumber(idValue)
		if id and id > 0 and id % 1 == 0 and not seen[id] then
			seen[id] = true
			table.insert(items, { id = id, typeName = typeName or "Item" })
		end
	end
	local properties = {
		{ "GraphicTShirt", "TShirt" }, { "Shirt", "Shirt" }, { "Pants", "Pants" },
		{ "Face", "Face" }, { "Head", "Head" }, { "Torso", "Torso" },
		{ "RightArm", "RightArm" }, { "LeftArm", "LeftArm" }, { "RightLeg", "RightLeg" }, { "LeftLeg", "LeftLeg" },
		{ "ClimbAnimation", "ClimbAnimation" }, { "FallAnimation", "FallAnimation" },
		{ "IdleAnimation", "IdleAnimation" }, { "JumpAnimation", "JumpAnimation" },
		{ "RunAnimation", "RunAnimation" }, { "SwimAnimation", "SwimAnimation" },
		{ "WalkAnimation", "WalkAnimation" }, { "MoodAnimation", "MoodAnimation" },
		{ "EyebrowAccessory", "EyebrowAccessory" }, { "EyelashAccessory", "EyelashAccessory" },
		{ "FaceMakeup", "FaceMakeup" }, { "LipMakeup", "LipMakeup" }, { "EyeMakeup", "EyeMakeup" },
	}
	for _, entry in ipairs(properties) do
		local propertyOk, value = pcall(function() return description[entry[1]] end)
		if propertyOk then add(value, entry[2]) end
	end
	local accessoriesOk, accessories = pcall(function() return description:GetAccessories(true) end)
	if accessoriesOk and type(accessories) == "table" then
		local names = {
			Hat = "Hat", Hair = "HairAccessory", Face = "FaceAccessory",
			Neck = "NeckAccessory", Shoulder = "ShoulderAccessory", Front = "FrontAccessory", Back = "BackAccessory",
			Waist = "WaistAccessory", Eyebrow = "EyebrowAccessory", Eyelash = "EyelashAccessory",
			FaceMakeup = "FaceMakeup", LipMakeup = "LipMakeup", EyeMakeup = "EyeMakeup",
			TShirt = "TShirtAccessory", Shirt = "ShirtAccessory", Pants = "PantsAccessory",
			Jacket = "JacketAccessory", Sweater = "SweaterAccessory", Shorts = "ShortsAccessory",
			LeftShoe = "LeftShoeAccessory", RightShoe = "RightShoeAccessory", DressSkirt = "DressSkirtAccessory",
		}
		for _, accessory in ipairs(accessories) do
			local accessoryName = tostring(accessory.AccessoryType or ""):gsub("^Enum%.AccessoryType%.", "")
			add(accessory.AssetId, names[accessoryName] or "Accessory")
		end
	end
	local emotesOk, emotes = pcall(function() return description:GetEquippedEmotes() end)
	if emotesOk and type(emotes) == "table" then
		for _, emote in pairs(emotes) do
			if type(emote) == "table" then add(emote.Id or emote.AssetId, "EmoteAnimation")
			elseif type(emote) == "number" then add(emote, "EmoteAnimation") end
		end
	end
	pcall(function() description:Destroy() end)
	if #items == 0 then
		if #currentEquippedItems > 0 then
			return true
		end
		hasWearingSnapshot = false
		refreshWearingList()
		return true
	end
	table.sort(items, function(a, b)
		if a.typeName == b.typeName then return a.id < b.id end
		return a.typeName < b.typeName
	end)
	local ids = {}
	for _, item in ipairs(items) do table.insert(ids, item.id) end
	replaceEquippedState(ids, items)
	return true
end

local function clearEquippedState()
	hasWearingSnapshot = true
	table.clear(equippedIds)
	table.clear(currentEquippedItems)
	refreshEquippedBadges()
	refreshWearingList()
	updateWearingCanvas()
end

local function clearTiles()
	for _, child in ipairs(results:GetChildren()) do
		if child:IsA("GuiButton") then child:Destroy() end
	end
	H.inventoryCanvasItemCount = nil
	results.CanvasPosition = Vector2.zero
	results.CanvasSize = UDim2.fromOffset(0, results.AbsoluteSize.Y)
	order = 0
	task.defer(H.updateResultsCanvas)
	H.scheduleResultsTileVisibility()
end
local function publicInventoryMatchesFilter(data, keyword)
	local searchText = string.lower(
		tostring(data.name) .. " "
			.. tostring(data.typeName or "") .. " "
			.. tostring(data.id)
	)

	return keyword == "" or string.find(searchText, keyword, 1, true) ~= nil
end

local function rebuildPublicInventoryView(restoreY)
	local keyword = string.lower(H.trim(searchBox.Text))

	table.clear(publicInventoryItems)

	for _, data in ipairs(publicInventoryAllItems) do
		if publicInventoryMatchesFilter(data, keyword) then
			table.insert(publicInventoryItems, data)
		end
	end

	beginInventoryTileView(
		publicInventoryItems,
		curTab,
		chipIdx[curTab],
		restoreY or 0,
		sourceId
	)
end
local function applyFilter()
	local keyword = string.lower(H.trim(searchBox.Text))
	if publicInventoryViewActive then
		local restoreY = tonumber(results.CanvasPosition.Y) or 0

		rebuildPublicInventoryView(restoreY)
		local prefix = publicInventoryRequestId
			and "Loading public inventory"
			or "Public inventory"

		setStatus(prefix .. " for " .. publicInventoryUsername
			.. " · " .. tostring(#publicInventoryItems)
			.. " matching items · "
			.. tostring(publicInventoryReceivedCount) .. " received")

		return
	end
	local localItems = TABS[curTab].kind ~= "catalog"
	local visibleOrder, hiddenOrder = 0, 0
	for _, child in ipairs(results:GetChildren()) do
		if child:IsA("GuiButton") then
			local matches = not localItems or keyword == ""
				or string.find(child:GetAttribute("n") or "", keyword, 1, true) ~= nil
			if matches then
				visibleOrder += 1
				child.LayoutOrder = visibleOrder
				child.Visible = true
			else
				hiddenOrder += 1
				child.LayoutOrder = 1000000 + hiddenOrder
				child.Visible = false
			end
		end
	end
	if not (TABS[curTab].kind == "inventory" and H.inventoryCanvasItemCount ~= nil) then
		H.inventoryCanvasItemCount = nil
	end
	task.defer(H.updateResultsCanvas)
	H.scheduleResultsTileVisibility()
end

local function getBundleProductInfo(bundleId)
	local cached = bundleProductInfoCache[bundleId]
	if cached then return true, cached end
	local bundleInfoType = H.enumItem(Enum.InfoType, "Bundle")
	if not bundleInfoType then
		return false, "This Roblox client does not expose Enum.InfoType.Bundle"
	end
	local ok, productInfo = pcall(H.getProductInfo, bundleId, bundleInfoType)
	if ok and type(productInfo) == "table" then
		bundleProductInfoCache[bundleId] = productInfo
		return true, productInfo
	end
	return false, productInfo
end

local function addTile(data, kind)
	if kind == "catalog" and data.bundle then H.registerAnimationPack(data) end
	order += 1
	local thumbType = data.outfit and "Outfit" or (data.bundle and "BundleThumbnail" or "Asset")
	local subtitle, subtitleColor
	subtitleColor = C.sub
	if kind == "catalog" then
		if data.background then subtitle = "Avatar background · Preview"
		else
			local price = data.price
			if data.bundle and (type(price) ~= "number" or price <= 0 or data.isForSale == false) then
				subtitle = "Bundle · Checking price..."
			elseif data.hasResellers and data.resalePrice and data.resalePrice > 0 then
				subtitle = "R$ " .. H.comma(data.resalePrice) .. " · Resale"
				subtitleColor = C.success
			elseif data.limited and data.hasResellers == true then
				subtitle = "Limited · resale price unavailable"
			elseif data.limited and (data.priceStatus == "No Resellers" or data.hasResellers == false) then
				subtitle = "Limited · No resellers"
			elseif type(price) == "number" and price > 0 then
				subtitle = "R$ " .. H.comma(price)
				subtitleColor = C.success
			elseif data.priceStatus == "Free" or (price == 0 and data.isForSale == true) then
				subtitle = "Free"
			elseif data.bundle then
				subtitle = "Bundle · Price unavailable"
			elseif data.typeName == "DynamicHead" then
				subtitle = "Head asset · checking availability"
			else
				subtitle = data.limited and "Limited · Off sale" or "Off sale"
			end
			if data.bundle and not subtitle:find("^Bundle") then subtitle = "Bundle · " .. subtitle end
		end
	elseif kind == "inventory" then subtitle = H.prettyType(data.typeName)
	else subtitle = "Outfit" end

	local tile = H.new("TextButton", { Text = "", BackgroundColor3 = C.card, LayoutOrder = order, Active = true }, results)
	designSizes[tile] = Vector2.new(state.catalogLayout.cellWidth, state.catalogLayout.cellHeight)
	H.round(tile, 10)
	local tileStroke = H.new("UIStroke", { Color = C.line, Transparency = 0.45, Thickness = 1 }, tile)
	local tileContent = H.new("Frame", {
		Name = "TileContent", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
	}, tile)
	tile.MouseEnter:Connect(function()
		tile:SetAttribute("CatalogHovered", true)
		if tileContent.Visible then
			TweenService:Create(tileStroke, TweenInfo.new(0.12), { Transparency = 0.05, Color = C.accent }):Play()
		end
	end)
	tile.MouseLeave:Connect(function()
		tile:SetAttribute("CatalogHovered", false)
		if tileContent.Visible then
			TweenService:Create(tileStroke, TweenInfo.new(0.16), { Transparency = 0.45, Color = C.line }):Play()
		end
	end)
	tile:SetAttribute("n", string.lower(tostring(data.name) .. " " .. tostring(data.typeName or "") .. " " .. tostring(data.id)))
	tile:SetAttribute("AssetId", data.id)
	tile:SetAttribute("IsBundle", data.bundle == true)

	local imageSize = math.min(state.catalogLayout.cellWidth - 28, 118)
	local imageX = (state.catalogLayout.cellWidth - imageSize) / 2
	local textTop = 8 + imageSize + 8
	local image = H.new("ImageLabel", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(imageX, 8),
		Size = UDim2.fromOffset(imageSize, imageSize), ScaleType = Enum.ScaleType.Fit,
		Image = "rbxthumb://type=" .. thumbType .. "&id=" .. string.format("%d", data.id)
			.. "&w=" .. (thumbType == "Asset" and "420" or "150")
			.. "&h=" .. (thumbType == "Asset" and "420" or "150"),
	}, tileContent)
	H.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, image)
	local equippedBadge = H.new("TextLabel", {
		Name = "EquippedBadge", Position = UDim2.fromOffset(state.catalogLayout.cellWidth - 60, 8),
		Size = UDim2.fromOffset(52, 21), BackgroundColor3 = C.accent, Text = "EQUIPPED",
		TextColor3 = C.text, Font = FB, TextSize = 10,
		Visible = data.bundle and bundleFullyEquipped(data.id) or (not data.bundle and equippedIds[data.id] == true), ZIndex = 3,
	}, tileContent)
	H.round(equippedBadge, 8)

	local nameLabel = H.label(tileContent, data.name, 8, textTop, state.catalogLayout.cellWidth - 16, 52, 18, C.text, FM)
	nameLabel.Name = "CatalogItemName"
	nameLabel.TextScaled = true
	nameLabel.TextWrapped = true
	nameLabel.TextTruncate = Enum.TextTruncate.None
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	local namePadding = nameLabel:FindFirstChildOfClass("UIPadding")
	if namePadding then
		namePadding.PaddingTop, namePadding.PaddingBottom = UDim.new(0, 0), UDim.new(0, 0)
		namePadding.PaddingLeft, namePadding.PaddingRight = UDim.new(0, 0), UDim.new(0, 0)
	end
	local subtitleLabel = H.label(tileContent, subtitle, 8, textTop + 54, state.catalogLayout.cellWidth - 16, 24, 17, subtitleColor, FB)
	subtitleLabel.Name = "CatalogItemPriceOrType"
	subtitleLabel.TextScaled = true
	local subtitlePadding = subtitleLabel:FindFirstChildOfClass("UIPadding")
	if subtitlePadding then
		subtitlePadding.PaddingTop, subtitlePadding.PaddingBottom = UDim.new(0, 0), UDim.new(0, 0)
		subtitlePadding.PaddingLeft, subtitlePadding.PaddingRight = UDim.new(0, 0), UDim.new(0, 0)
	end

	if kind == "catalog" and data.bundle
		and (type(data.price) ~= "number" or data.price <= 0 or data.isForSale == false) then
		task.spawn(function()
			local infoOk, productInfo = getBundleProductInfo(data.id)
			if not tile.Parent or not subtitleLabel.Parent then return end
			if not infoOk or type(productInfo) ~= "table" then
				if data.priceStatus == "Free" or (tonumber(data.price) == 0 and data.isForSale ~= false) then
					data.price = 0
					subtitleLabel.Text = "Bundle · Free"
				else
					subtitleLabel.Text = "Bundle · Price unavailable"
				end
				return
			end
			local currentPrice = tonumber(productInfo.PriceInRobux or productInfo.Price) or tonumber(data.price)
			local currentSaleStatus = tostring(productInfo.PriceStatus or ""):lower()
			if productInfo.IsForSale == false or currentSaleStatus == "off sale" then
				data.isForSale = false
				subtitleLabel.Text = "Bundle · Off sale"
			elseif currentPrice and currentPrice > 0 then
				data.price = currentPrice
				data.isForSale = true
				subtitleLabel.Text = "Bundle · R$ " .. H.comma(currentPrice)
				subtitleLabel.TextColor3 = C.success
			elseif productInfo.IsForSale == true or currentSaleStatus == "free"
				or productInfo.IsFree == true
				or (currentPrice == 0 and productInfo.IsForSale ~= false and data.isForSale ~= false and currentSaleStatus ~= "off sale") then
				data.price = 0
				data.isForSale = true
				subtitleLabel.Text = "Bundle · Free"
			elseif data.isForSale == false then
				subtitleLabel.Text = "Bundle · Off sale"
			else
				subtitleLabel.Text = "Bundle · Price unavailable"
			end
		end)
	end

	if kind == "catalog" and not data.bundle and data.typeName == "DynamicHead"
		and (type(data.price) ~= "number" or data.price <= 0 or data.isForSale == false) then
		task.spawn(function()
			local marketOk, marketInfo, catalogOk, catalogInfo
			local completed = 0
			task.spawn(function()
				marketOk, marketInfo = pcall(H.getProductInfo, data.id, Enum.InfoType.Asset)
				completed += 1
			end)
			task.spawn(function()
				catalogOk, catalogInfo = pcall(H.callAES, "GetItemDetails", data.id, Enum.AvatarItemType.Asset)
				completed += 1
			end)
			while completed < 2 do task.wait() end
			if not tile.Parent or not subtitleLabel.Parent then return end
			local livePrice = marketOk and type(marketInfo) == "table"
				and tonumber(marketInfo.PriceInRobux or marketInfo.Price) or nil
			local liveForSale = marketOk and type(marketInfo) == "table" and marketInfo.IsForSale == true
			if (not livePrice or livePrice <= 0 or not liveForSale) and catalogOk and type(catalogInfo) == "table" then
				local catalogPrice = tonumber(catalogInfo.PriceInRobux or catalogInfo.Price)
				if catalogInfo.IsForSale == true and catalogPrice and catalogPrice > 0 then
					livePrice, liveForSale = catalogPrice, true
				elseif catalogInfo.PriceStatus == "Free" and catalogInfo.IsForSale == true then
					livePrice, liveForSale = 0, true
				end
			end
			if liveForSale and livePrice and livePrice > 0 then
				data.price, data.isForSale = livePrice, true
				subtitleLabel.Text = "R$ " .. H.comma(livePrice)
				subtitleLabel.TextColor3 = C.success
			elseif liveForSale and livePrice == 0 then
				data.price, data.isForSale = 0, true
				subtitleLabel.Text = "Free"
			else
				data.isForSale = false
				subtitleLabel.Text = "Head asset · check Dynamic Head bundles"
			end
		end)
	end

	if data.background then
		local previewBadge = H.new("TextLabel", {
			Name = "PreviewBadge", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(56, 20),
			BackgroundColor3 = C.accent, Text = "PREVIEW", TextColor3 = C.text,
			Font = FB, TextSize = 10, Visible = data.id == tonumber(avatarBackgroundImage:GetAttribute("AssetId")), ZIndex = 3,
		}, tileContent)
		H.round(previewBadge, 7)
	end
	local consumeTileLongPress = H.bindLongPressDetails(tile, function()
		if H.openItemDetails then H.openItemDetails(data) end
	end)
	tile.Activated:Connect(function()
		if consumeTileLongPress() then return end
		if data.background then
			setViewportBackground(data.id)
			setStatus("Previewing background: " .. data.name)
		elseif isEmotePreviewItem(data) then toggleEmotePreview(data)
		else wearItem(data) end
	end)
	tile.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and H.openItemDetails then H.openItemDetails(data) end
	end)
	H.scheduleResultsTileVisibility()
end
local function inventoryAcquiredTimestamp(item)

	local createdTime = item.CreatedTime or item.createdTime
	if createdTime ~= nil then
		local ok, timestamp = pcall(function() return createdTime.UnixTimestamp end)
		if ok and type(timestamp) == "number" then return timestamp end
	end
	local rawCreated = item.Created or item.created or item.CreatedAt or item.createdAt
	if typeof(rawCreated) == "DateTime" then return rawCreated.UnixTimestamp end
	if type(rawCreated) == "number" then return rawCreated end
	local created = tostring(rawCreated or "")
	local year, month, day, hour, minute, second = created:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
	if year then
		local ok, date = pcall(function()
			return DateTime.fromUniversalTime(tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(minute), tonumber(second))
		end)
		if ok and date then return date.UnixTimestamp end
	end
	return 0
end

local function normalize(kind, item)
	if kind == "catalog" then
		if type(item.Id) ~= "number" then return nil end
		local typeName = H.assetTypeName(item.AssetType or item.AssetTypeId)
		local resalePrice = tonumber(item.LowestResalePrice)
		if not resalePrice or resalePrice <= 0 then resalePrice = tonumber(item.LowestPrice) end
		local hasResellers = item.HasResellers
		if hasResellers == nil and resalePrice ~= nil and resalePrice > 0 then hasResellers = true end
		local priceStatus = tostring(item.PriceStatus or "")
		local limited = hasResellers == true or item.IsLimited == true or item.IsLimitedUnique == true or priceStatus == "No Resellers"
		if type(item.ItemRestrictions) == "table" then
			for _, restriction in ipairs(item.ItemRestrictions) do
				if restriction == "Collectible" or restriction == "Limited" or restriction == "LimitedUnique" then
					limited = true
					break
				end
			end
		end
		local isBundle = H.isBundle(item)
		local bundleType = tostring(item.BundleType or "")
		local isBackground = typeName == "AvatarBackground"
			or tonumber(item.AssetTypeId) == 92
		return {
			id = item.Id, name = tostring(item.Name or ("Item " .. item.Id)), price = tonumber(item.PriceInRobux or item.Price),
			resalePrice = resalePrice, hasResellers = hasResellers, limited = limited,
			priceStatus = priceStatus, isForSale = item.IsForSale,
			typeName = typeName, emote = typeName == "EmoteAnimation", background = isBackground, bundle = isBundle,
			bundleType = bundleType,
			bodyBundle = isBundle and TABS[curTab] and TABS[curTab].name == "Body",
		}
	elseif kind == "inventory" then
		local id = tonumber(item.AssetId or item.assetId)
		if not id then return nil end
		local typeName = H.assetTypeName(item.AssetType or item.assetType or item.Type or item.AssetTypeId)
		local isBackground = typeName == "AvatarBackground"
			or tonumber(item.AssetTypeId or item.assetTypeId) == 92
		return {
			id = id,
			name = tostring(item.AssetName or item.Name or item.name or ("Item " .. id)),
			typeName = typeName,
			background = isBackground,
			acquiredAt = inventoryAcquiredTimestamp(item),
		}
	end
	local outfitId = tonumber(item.Id or item.id)
	if not outfitId then return nil end
	return {
		id = outfitId,
		name = tostring(item.Name or item.name or "Outfit"),
		outfit = true,

		createdAt = inventoryAcquiredTimestamp(item),
	}
end

local function collectInventoryPage(page)
	local added = 0
	for _, item in ipairs(page) do
		local data = normalize("inventory", item)
		if data and not inventoryLoadedById[data.id] then
			inventoryLoadedById[data.id] = data
			added += 1
		end
	end
	if added > 0 then inventorySortDirty = true end
	return added
end
local function sortedInventoryItems()
	if sortedInventoryCache and not inventorySortDirty then return sortedInventoryCache end
	local sorted = {}
	for _, data in pairs(inventoryLoadedById) do table.insert(sorted, data) end
	table.sort(sorted, function(a, b)
		local timeA, timeB = tonumber(a.acquiredAt) or 0, tonumber(b.acquiredAt) or 0
		if timeA ~= timeB then return timeA > timeB end
		local nameA, nameB = string.lower(a.name), string.lower(b.name)
		if nameA ~= nameB then return nameA < nameB end
		return a.id < b.id
	end)
	sortedInventoryCache = sorted
	inventorySortDirty = false
	return sortedInventoryCache
end

local function getInventoryItemsForChip(chipData)
	local sorted = sortedInventoryItems()
	local allItems = not chipData or chipData.allInventory == true
	local allowed = {}
	for _, assetType in ipairs(chipData and chipData.assets or {}) do
		if typeof(assetType) == "EnumItem" then allowed[assetType.Name] = true end
	end
	local showOther = chipData and chipData.label == "Body & Other"
	local keyword = string.lower(H.trim(searchBox.Text))
	local filtered = {}
	for _, data in ipairs(sorted) do
		local typeName = data.typeName
		local inCategory = allItems or allowed[typeName] or (showOther and (not typeName or not inventoryGrouped[typeName]))
		local searchText = string.lower(tostring(data.name) .. " " .. tostring(typeName or "") .. " " .. tostring(data.id))
		if inCategory and (keyword == "" or searchText:find(keyword, 1, true)) then
			table.insert(filtered, data)
		end
	end
	return filtered
end

local function addCurrentPage(kind)
	local ok, page = pcall(function() return pages:GetCurrentPage() end)
	if not ok then warn(page); return 0 end
	local count = 0
	if kind == "catalog" then
		for _, item in ipairs(page) do
			local data = normalize(kind, item)
			if data and not catalogLoadedById[data.id] then
				catalogLoadedById[data.id] = true
				addTile(data, kind)
				count += 1
			end
		end
		applyFilter()
	else

		local outfits = {}
		for pageIndex, item in ipairs(page) do
			local editable = item.IsEditable == true or item.isEditable == true
			if editable then
				local data = normalize(kind, item)
				if data then
					data.pageOrder = pageIndex
					table.insert(outfits, data)
				end
			end
		end
		local hasTimestamps = false
		for _, data in ipairs(outfits) do
			if (tonumber(data.createdAt) or 0) > 0 then
				hasTimestamps = true
				break
			end
		end
		if hasTimestamps then
			table.sort(outfits, function(a, b)
				local timeA, timeB = tonumber(a.createdAt) or 0, tonumber(b.createdAt) or 0
				if timeA ~= timeB then return timeA > timeB end
				return a.pageOrder < b.pageOrder
			end)
		end
		for _, data in ipairs(outfits) do addTile(data, kind); count += 1 end
		applyFilter()
	end
	task.defer(H.updateResultsCanvas)
	H.scheduleResultsTileVisibility()
	return count
end

local function nearBottom()
	local canvasHeight = results.CanvasSize.Y.Offset
	local threshold = math.max(120 * H.getCatalogUiScale(), results.AbsoluteSize.Y * 0.20)
	return results.CanvasPosition.Y + results.AbsoluteSize.Y >= canvasHeight - threshold
end
local loadMore
local function checkFill()
	scrollCheckToken += 1
	local token = scrollCheckToken
	task.delay(0.20, function()
		if token ~= scrollCheckToken then return end
		if publicInventoryViewActive or (TABS[curTab] and TABS[curTab].kind == "inventory") then return end
		if nearBottom() then loadMore() end
	end)
end

H.requestInventoryTilesForScroll = function()
	if not (publicInventoryViewActive or (TABS[curTab] and TABS[curTab].kind == "inventory")) then return end
	if type(activeInventoryItems) ~= "table" then return end
	local totalItems = #activeInventoryItems
	if inventoryRenderedCount >= totalItems then return end
	local rowHeight = math.max(1, H.resultsGrid.CellSize.Y.Offset + H.resultsGrid.CellPadding.Y.Offset)
	local bottomInCanvas = results.CanvasPosition.Y + results.AbsoluteSize.Y + rowHeight * 1.5
	local rowsNeeded = math.max(1, math.ceil((bottomInCanvas - 4 * H.getCatalogUiScale()) / rowHeight) + 1)
	local targetCount = math.min(totalItems, math.max(INVENTORY_BATCH_SIZE, rowsNeeded * state.catalogLayout.columns))
	if targetCount <= inventoryRenderedCount then return end

	local viewToken = inventoryViewBuildToken
	H.pendingInventoryRenderCount = math.max(H.pendingInventoryRenderCount, targetCount)
	if H.inventoryRenderWorkerToken == viewToken then return end
	H.inventoryRenderWorkerToken = viewToken
	task.spawn(function()
		while viewToken == inventoryViewBuildToken
			and type(activeInventoryItems) == "table"
			and inventoryRenderedCount < H.pendingInventoryRenderCount do
			local added = renderMoreInventoryTiles()
			if added <= 0 then break end

			task.wait()
		end
		if H.inventoryRenderWorkerToken == viewToken then
			H.inventoryRenderWorkerToken = nil
			H.pendingInventoryRenderCount = inventoryRenderedCount
		end
	end)
end

loadMore = function()
	if loadingMore then return end
	if TABS[curTab] and TABS[curTab].kind == "inventory" then
		H.requestInventoryTilesForScroll()
		return
	end
	local current = pages
	if not current or current.IsFinished then return end
	loadingMore = true
	local myId = sourceId
	local ok, err = pcall(function() current:AdvanceToNextPageAsync() end)
	if myId ~= sourceId or current ~= pages then loadingMore = false; return end
	loadingMore = false
	if not ok then warn(err); return end
	addCurrentPage(TABS[curTab].kind)
	task.defer(H.updateResultsCanvas)
	checkFill()
end
results:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	H.scheduleResultsTileVisibility()
	if not inventoryViewRebuilding then
		resultScrollPositions[getResultScrollKey(curTab, chipIdx[curTab])] = results.CanvasPosition.Y
		if publicInventoryViewActive or (TABS[curTab] and TABS[curTab].kind == "inventory") then
			H.requestInventoryTilesForScroll()
		elseif nearBottom() then
			loadMore()
		end
	end
end)

renderMoreInventoryTiles = function()
	if type(activeInventoryItems) ~= "table" then return 0 end
	local firstIndex = inventoryRenderedCount + 1
	local lastIndex = math.min(#activeInventoryItems, inventoryRenderedCount + INVENTORY_BATCH_SIZE)
	if firstIndex > lastIndex then return 0 end
	for index = firstIndex, lastIndex do
		addTile(activeInventoryItems[index], "inventory")
	end
	inventoryRenderedCount = lastIndex
	return lastIndex - firstIndex + 1
end

beginInventoryTileView = function(items, tabIndex, chipIndex, restoreY, requestSource)
	inventoryViewBuildToken += 1
	local buildToken = inventoryViewBuildToken
	inventoryViewRebuilding = true
	activeInventoryItems = items or {}
	inventoryRenderedCount = 0
	H.pendingInventoryRenderCount = 0
	clearTiles()
	H.inventoryCanvasItemCount = #activeInventoryItems
	H.updateResultsCanvas()

	local targetCount = math.min(#activeInventoryItems, INVENTORY_INITIAL_RENDER_COUNT)
	while inventoryRenderedCount < targetCount do
		if renderMoreInventoryTiles() <= 0 then break end
	end
	task.defer(function()
		if buildToken ~= inventoryViewBuildToken then return end
		if requestSource == sourceId and results.Parent then
			restoreResultsScroll(tabIndex, chipIndex, restoreY, requestSource)
		end
		inventoryViewRebuilding = false

		H.scheduleResultsTileVisibility()
		if requestSource == sourceId and results.Parent
			and not (TABS[curTab] and TABS[curTab].kind == "inventory") then
			checkFill()
		end
	end)
end

refreshActiveInventoryView = function()
	if not inventoryCacheLoading then return end
	local activeTab = TABS[curTab]
	if not activeTab or activeTab.kind ~= "inventory" then return end
	local tabIndex = curTab
	local chipIndex = chipIdx[curTab]
	local chipData = activeTab.chips and activeTab.chips[chipIndex] or nil
	if chipData and chipData.special then return end

	local filtered = getInventoryItemsForChip(chipData)
	local oldCount = type(activeInventoryItems) == "table" and #activeInventoryItems or -1
	if oldCount == #filtered then return end

	local key = getResultScrollKey(tabIndex, chipIndex)
	local currentY = tonumber(results.CanvasPosition.Y) or 0
	local restoreY = math.max(tonumber(resultScrollPositions[key]) or 0, currentY)
	resultScrollPositions[key] = restoreY
	local activeSource = sourceId
	beginInventoryTileView(filtered, tabIndex, chipIndex, restoreY, activeSource)
	setStatus("Inventory loading in background · " .. tostring(#inventoryLoadedById)
		.. " items cached · " .. tostring(#filtered) .. " match this category")
end

local inventoryOk = false
local promptingInventory = false
local function ensureInventory()
	if inventoryOk then return true end
	if promptingInventory then return false end
	promptingInventory = true
	local promptOk = pcall(function() AvatarEditorService:PromptAllowInventoryReadAccess() end)
	if not promptOk then promptingInventory = false; return false end
	local result = AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Wait()
	promptingInventory = false
	inventoryOk = result == Enum.AvatarPromptResult.Success
	return inventoryOk
end
local function getOutfits()

	local createdSource = H.enumItem(Enum.OutfitSource, "Created") or Enum.OutfitSource.All
	return H.callAES("GetOutfits", createdSource, Enum.OutfitType.All)
end

do
	local bulkPurchaseEvent = ReplicatedStorage:WaitForChild("CatalogBulkPurchaseEvent")
	local ownedAssetIdsCache
	local ownedAssetIdsCacheKey
	local saveRows = {}
	local saveBaseDescription
	local saveSelected = {}
	local saveOwned = {}
	local pendingSaveDescription
	local saveLoadToken = 0

	local function countSelected()
		local count = 0
		for id, selected in pairs(saveSelected) do
			if selected and saveOwned[id] then count += 1 end
		end
		return count
	end

	local function updateSaveCount()
		H.saveCount.Text = tostring(countSelected()) .. " selected"
	end

	local function clearSaveRows()
		for _, child in ipairs(H.saveList:GetChildren()) do
			if child:IsA("GuiObject") and child ~= H.saveListLayout then child:Destroy() end
		end
		table.clear(saveRows)
	end

	local function closeSaveReview()
		saveLoadToken += 1
		H.saveOverlay.Visible = false
		if saveBaseDescription then
			pcall(function() saveBaseDescription:Destroy() end)
			saveBaseDescription = nil
		end
		clearSaveRows()
	end

	local function loadOwnedAssetIds()
		if not ensureInventory() then return nil, "Inventory permission was not granted." end
		local wornItems = table.clone(currentEquippedItems)
		if #wornItems == 0 then return nil, "There are no currently worn items to check." end
		local wornIds, wornTypes = {}, {}
		local signatureParts = {}
		for _, worn in ipairs(wornItems) do
			local id = tonumber(worn.id)
			if id and id > 0 then
				wornIds[id] = true
				wornTypes[id] = tostring(worn.typeName or "")
				table.insert(signatureParts, tostring(id) .. ":" .. wornTypes[id])
			end
		end
		table.sort(signatureParts)
		local cacheKey = table.concat(signatureParts, "|")
		if ownedAssetIdsCache and ownedAssetIdsCacheKey == cacheKey then return ownedAssetIdsCache end
		local owned, remainingIds = {}, {}
		for id in pairs(wornIds) do
			if inventoryLoadedById[id] then owned[id] = true else remainingIds[id] = true end
		end
		if inventoryCacheReady then
			ownedAssetIdsCache = owned
			ownedAssetIdsCacheKey = cacheKey
			return owned
		end
		local remainingCount = 0
		for _ in pairs(remainingIds) do remainingCount += 1 end
		if remainingCount == 0 then
			ownedAssetIdsCache = owned
			ownedAssetIdsCacheKey = cacheKey
			return owned
		end
		local requestedTypes, seenTypes, unresolved = {}, {}, {}
		local function addType(typeName)
			local enumValue = H.enumItem(Enum.AvatarAssetType, typeName)
			if not enumValue then return false end
			if not seenTypes[enumValue.Value] then
				seenTypes[enumValue.Value] = true
				table.insert(requestedTypes, enumValue)
			end
			return true
		end
		for id in pairs(remainingIds) do
			local typeName = wornTypes[id]
			if not H.enumItem(Enum.AvatarAssetType, typeName) then
				typeName = resolveAssetType(id) or ""
			end
			if typeName == "" or not addType(typeName) then
				table.insert(unresolved, tostring(id))
			elseif typeName == "Head" then
				addType("DynamicHead")
			end
		end
		if #unresolved > 0 then
			return nil, "Could not identify the inventory type for worn item ID(s): " .. table.concat(unresolved, ", ") .. ". No full-inventory scan was started."
		end
		if #requestedTypes == 0 then return nil, "No supported inventory types were found among currently worn items." end
		local ok, inventoryPages = pcall(H.callAES, "GetInventory", requestedTypes)
		if not ok or not inventoryPages then
			return nil, "Roblox could not read the inventory types used by your currently worn items: " .. tostring(inventoryPages)
		end
		local foundCount, pageCount = 0, 0
		while true do
			local pageOk, page = pcall(function() return inventoryPages:GetCurrentPage() end)
			if not pageOk or type(page) ~= "table" then
				return nil, "Could not read an inventory page: " .. tostring(page)
			end
			for _, raw in ipairs(page) do
				local id = tonumber(raw.AssetId or raw.assetId or raw.Id or raw.id)
				if id and remainingIds[id] and not owned[id] then
					owned[id] = true
					foundCount += 1
				end
			end
			pageCount += 1
			if foundCount >= remainingCount or inventoryPages.IsFinished then break end
			if pageCount >= 200 then
				return nil, "Ownership check reached the 200-page safety limit for the remaining currently worn item types."
			end
			local advanceOk, advanceError = pcall(function() inventoryPages:AdvanceToNextPageAsync() end)
			if not advanceOk then return nil, "Inventory ownership check stopped: " .. tostring(advanceError) end
		end
		ownedAssetIdsCache = owned
		ownedAssetIdsCacheKey = cacheKey
		return owned
	end

	local saveBundleTools = (function()
		local saveBundleOfferCache = {}
		local saveBundleOfferLoading = {}
		local saveBundleDetailsCache = {}
		local saveBundleDiscoveryActive = 0
		local SAVE_MAX_CONCURRENT_DISCOVERY = 2
		local saveAssetService = game:GetService("AssetService")
		local saveBlockedBundleIds = { [331465] = true }
		local saveAnimationTypes = {
			ClimbAnimation = true, FallAnimation = true, IdleAnimation = true,
			JumpAnimation = true, RunAnimation = true, SwimAnimation = true,
			WalkAnimation = true, EmoteAnimation = true, MoodAnimation = true,
		}
		local saveBodyTypes = {
			Head = true, DynamicHead = true, Torso = true, LeftArm = true,
			RightArm = true, LeftLeg = true, RightLeg = true,
		}
		local saveShoeTypes = {
			LeftShoeAccessory = true, RightShoeAccessory = true, LeftShoe = true, RightShoe = true,
		}

		local function normalizeSaveType(value)
			local name = tostring(value or "")
			name = name:gsub("^Enum%.AvatarAssetType%.", ""):gsub("^AvatarAssetType%.", "")
			name = name:gsub("^Enum%.BundleType%.", ""):gsub("^BundleType%.", "")
			return name:match("([%w_]+)$") or name
		end

		local function getSaveCategory(typeName)
			local name = normalizeSaveType(typeName)
			if saveAnimationTypes[name] or name:find("Animation", 1, true) then return "Animation" end
			if saveBodyTypes[name] then return "Body" end
			if saveShoeTypes[name] then return "Shoes" end
			return nil
		end

		local function getSaveBundleCategory(bundleType, bundleName, bundleId, contentTypes)
			local id = tonumber(bundleId)
			local name = tostring(bundleName or ""):lower()
			local normalizedType = normalizeSaveType(bundleType):lower()
			if id == 331856 or name:find("bold animation", 1, true) then return "Animation" end
			if normalizedType:find("animation", 1, true) or name:find("animation", 1, true) then return "Animation" end
			local hasAnimation, hasBody, hasShoes = false, false, false
			for _, typeName in pairs(contentTypes or {}) do
				local normalized = normalizeSaveType(typeName)
				if saveAnimationTypes[normalized] or normalized:find("Animation", 1, true) then hasAnimation = true end
				if saveBodyTypes[normalized] then hasBody = true end
				if saveShoeTypes[normalized] then hasShoes = true end
			end
			if hasAnimation and not hasBody then return "Animation" end
			if hasShoes then return "Shoes" end
			if normalizedType:find("shoe", 1, true) or name:find("shoe", 1, true) then return "Shoes" end
			if hasBody or normalizedType:find("body", 1, true) or normalizedType:find("dynamichead", 1, true)
				or name:find("faceless", 1, true) or name:find("body", 1, true) then return "Body" end
			if hasAnimation then return "Animation" end
			return nil
		end

		local function readSaveBundleContents(details)
			local contents = details and (details.BundledItems or details.Items)
			if type(contents) ~= "table" then return nil, nil end
			local assets, assetTypes = {}, {}
			for _, entry in ipairs(contents) do
				if type(entry) == "table" then
					local nested = type(entry.Item) == "table" and entry.Item
						or (type(entry.Asset) == "table" and entry.Asset or entry)
					local itemType = tostring(entry.Type or entry.ItemType or nested.Type or "Asset"):lower()
					local assetId = tonumber(entry.Id or entry.AssetId or nested.Id or nested.AssetId)
					if assetId and assetId > 0 and not itemType:find("bundle", 1, true)
						and (itemType == "asset" or itemType:find("asset", 1, true)) then
						assets[assetId] = true
						local assetType = normalizeSaveType(entry.AssetType or entry.AssetTypeName or nested.AssetType or nested.AssetTypeName)
						if assetType ~= "" then assetTypes[assetId] = assetType end
					end
				end
			end
			if next(assets) == nil then return nil, nil end
			return assets, assetTypes
		end

		local function getSaveBundleDetails(candidate)
			local bundleId = tonumber(candidate.id)
			if not bundleId or saveBlockedBundleIds[bundleId] then return nil end
			local cached = saveBundleDetailsCache[bundleId]
			if cached then
				if candidate.sourceMatched and candidate.sourceAssetId then cached.assets[candidate.sourceAssetId] = true end
				return cached
			end
			local details = {}
			if type(candidate.searchDetails) == "table" then
				for key, value in pairs(candidate.searchDetails) do details[key] = value end
			end
			local assets, assetTypes = readSaveBundleContents(details)
			if not assets then
				local ok, result = pcall(H.callAES, "GetItemDetails", bundleId, Enum.AvatarItemType.Bundle)
				if ok and type(result) == "table" then
					for key, value in pairs(result) do if value ~= nil then details[key] = value end end
					assets, assetTypes = readSaveBundleContents(details)
				end
			end
			if not assets then
				local ok, result = pcall(function() return saveAssetService:GetBundleDetailsAsync(bundleId) end)
				if ok and type(result) == "table" then
					for key, value in pairs(result) do if value ~= nil then details[key] = value end end
					assets, assetTypes = readSaveBundleContents(details)
				end
			end
			if candidate.sourceMatched and candidate.sourceAssetId then
				if not assets then assets, assetTypes = {}, {} end
				assets[candidate.sourceAssetId] = true
				assetTypes = assetTypes or {}
			end
			if not assets then return nil end
			local result = {
				id = bundleId,
				name = tostring(details.Name or details.name or candidate.name or ("Bundle " .. tostring(bundleId))),
				bundleType = details.BundleType or details.bundleType or candidate.bundleType,
				assets = assets,
				assetTypes = assetTypes or {},
				isForSale = details.IsForSale,
				isPurchasable = details.IsPurchasable,
			}
			saveBundleDetailsCache[bundleId] = result
			return result
		end

		local function discoverSaveBuyOffer(item)
			local itemId = tonumber(item.id)
			if not itemId then return { kind = "asset", id = item.id, name = tostring(item.name or "item") } end
			local cached = saveBundleOfferCache[itemId]
			if cached then return cached end
			local expectedCategory = getSaveCategory(item.typeName)
			local candidatesById = {}
			local function addCandidate(bundleId, name, bundleType, searchDetails, forced, sourceAssetId)
				bundleId = tonumber(bundleId)
				if not bundleId or bundleId <= 0 or saveBlockedBundleIds[bundleId] then return end
				local existing = candidatesById[bundleId]
				if not existing then
					existing = { id = bundleId, name = name, bundleType = bundleType, searchDetails = searchDetails, forced = forced == true }
					candidatesById[bundleId] = existing
				elseif searchDetails and (not existing.searchDetails or not (existing.searchDetails.BundledItems or existing.searchDetails.Items)) then
					existing.searchDetails = searchDetails
				end
				if sourceAssetId then
					existing.sourceMatched = true
					existing.sourceAssetId = tonumber(sourceAssetId)
				end
			end
			if expectedCategory == "Animation" then
				addCandidate(331856, "Bold Animation Pack", "Animations", nil, true)
			elseif expectedCategory == "Body" and (normalizeSaveType(item.typeName) == "Head" or normalizeSaveType(item.typeName) == "DynamicHead") then
				addCandidate(1952, "Faceless", "DynamicHead", nil, true)
			end
			local pagesOk, pages = pcall(H.callAES, "GetBundlesByAssetId", itemId, 100)
			if pagesOk and pages then
				for pageIndex = 1, 3 do
					local pageOk, page = pcall(function() return pages:GetCurrentPage() end)
					if not pageOk or type(page) ~= "table" then break end
					for _, entry in ipairs(page) do
						if type(entry) == "table" then
							addCandidate(entry.Id or entry.id or entry.BundleId, entry.Name or entry.name,
								entry.BundleType or entry.bundleType, entry, false, itemId)
						end
					end
					if pages.IsFinished or pageIndex == 3 then break end
					local advanceOk = pcall(function() pages:AdvanceToNextPageAsync() end)
					if not advanceOk then break end
				end
			end
			local candidates = {}
			for _, candidate in pairs(candidatesById) do
				local typeName = normalizeSaveType(candidate.bundleType):lower()
				local name = tostring(candidate.name or ""):lower()
				local hintedCategory = getSaveBundleCategory(candidate.bundleType, candidate.name, candidate.id)
				candidate.hintMatches = candidate.forced or (expectedCategory and hintedCategory == expectedCategory)
					or (expectedCategory == nil and (typeName ~= "" or name ~= ""))
				table.insert(candidates, candidate)
			end
			table.sort(candidates, function(a, b)
				if a.hintMatches ~= b.hintMatches then return a.hintMatches == true end
				if a.forced ~= b.forced then return a.forced == true end
				return a.id < b.id
			end)
			while #candidates > 32 do table.remove(candidates) end
			local relatedIds = {}
			for _, worn in ipairs(currentEquippedItems) do
				local wornId = tonumber(worn.id)
				if wornId and getSaveCategory(worn.typeName) == expectedCategory then relatedIds[wornId] = true end
			end
			local resolved = {}
			local nextIndex, finished = 0, 0
			local workerCount = math.min(4, #candidates)
			local deadline = os.clock() + 9
			for _ = 1, workerCount do
				task.spawn(function()
					while os.clock() < deadline do
						nextIndex += 1
						local index = nextIndex
						if index > #candidates then break end
						local candidate = candidates[index]
						local bundle = getSaveBundleDetails(candidate)
						if bundle and bundle.assets[itemId] then
							local contentTypes = {}
							for assetId, typeName in pairs(bundle.assetTypes) do contentTypes[assetId] = typeName end
							if not contentTypes[itemId] then contentTypes[itemId] = item.typeName end
							local category = getSaveBundleCategory(bundle.bundleType, bundle.name, bundle.id, contentTypes)
							local categoryMatches = expectedCategory == nil or category == nil or category == expectedCategory
							if categoryMatches and bundle.isPurchasable ~= false and bundle.isForSale ~= false and os.clock() < deadline then
								local coverage = 0
								for relatedId in pairs(relatedIds) do
									if bundle.assets[relatedId] then coverage += 1 end
								end
								table.insert(resolved, {
									kind = "bundle", id = bundle.id, name = bundle.name,
									category = category or expectedCategory, coverage = coverage,
									priority = candidate.forced == true,
								})
							end
						end
					end
					finished += 1
				end)
			end
			while finished < workerCount and os.clock() < deadline do task.wait(0.05) end
			table.sort(resolved, function(a, b)
				if a.priority ~= b.priority then return a.priority == true end
				if a.coverage ~= b.coverage then return a.coverage > b.coverage end
				return a.id < b.id
			end)
			local offer = resolved[1] or { kind = "asset", id = itemId, name = tostring(item.name or H.prettyType(item.typeName)) }
			saveBundleOfferCache[itemId] = offer
			return offer
		end

		local function requestSaveBuyOffer(item, row, buyButton, idLabel, requestToken)
			local cached = saveBundleOfferCache[tonumber(item.id)]
			if cached then
				if cached.kind == "bundle" then
					idLabel.Text = "Bundle: " .. cached.name
					buyButton.Text = "Buy bundle"
				else
					buyButton.Text = "Buy item"
				end
				buyButton.Active = true
				return
			end
			if saveBundleOfferLoading[item.id] then return end
			saveBundleOfferLoading[item.id] = true
			buyButton.Text = "Finding bundle..."
			buyButton.Active = false
			task.spawn(function()
				while saveBundleDiscoveryActive >= SAVE_MAX_CONCURRENT_DISCOVERY and requestToken == saveLoadToken and row.Parent do
					task.wait(0.05)
				end
				if requestToken ~= saveLoadToken or not row.Parent or not H.saveOverlay.Visible then
					saveBundleOfferLoading[item.id] = nil
					return
				end
				saveBundleDiscoveryActive += 1
				local ok, offer = pcall(discoverSaveBuyOffer, item)
				saveBundleDiscoveryActive = math.max(0, saveBundleDiscoveryActive - 1)
				saveBundleOfferLoading[item.id] = nil
				if not row.Parent or requestToken ~= saveLoadToken or not H.saveOverlay.Visible then return end
				if not ok or type(offer) ~= "table" then
					offer = { kind = "asset", id = item.id, name = tostring(item.name or H.prettyType(item.typeName)) }
					saveBundleOfferCache[tonumber(item.id)] = offer
				end
				if offer.kind == "bundle" then
					idLabel.Text = "Bundle: " .. offer.name
					buyButton.Text = "Buy bundle"
				else
					buyButton.Text = "Buy item"
				end
				buyButton.Active = true
			end)
		end

		return {
			request = requestSaveBuyOffer,
			getOffer = function(itemId) return saveBundleOfferCache[tonumber(itemId)] end,
		}
	end)()

	local function createSaveRow(item, index)
		local owned = saveOwned[item.id] == true
		local selected = owned and saveSelected[item.id] == true
		local row = H.new("TextButton", {
			Name = "SaveItem_" .. tostring(item.id), Text = "", AutoButtonColor = false,
			Size = UDim2.fromOffset(400, 116), BackgroundColor3 = selected and C.card or C.panel,
			BorderSizePixel = 0, LayoutOrder = index, ZIndex = 63,
			Active = true, Selectable = owned, ClipsDescendants = true,
		}, H.saveList)
		H.round(row, 10)
		row:SetAttribute("ItemTypeName", item.typeName)
		local outline = H.new("UIStroke", {
			Color = selected and C.accent or C.line, Transparency = owned and 0.25 or 0.65, Thickness = 1.2,
		}, row)
		local thumbnailFrame = H.new("Frame", {
			Name = "SaveItemThumbnailFrame", Position = UDim2.fromOffset(9, 9),
			Size = UDim2.fromOffset(98, 98), BackgroundColor3 = C.field,
			BorderSizePixel = 0, ZIndex = 64,
		}, row)
		H.round(thumbnailFrame, 8)
		local thumbnail = H.new("ImageLabel", {
			Name = "SaveItemThumbnail", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScaleType = Enum.ScaleType.Fit,
			Image = "rbxthumb://type=Asset&id=" .. tostring(item.id) .. "&w=150&h=150",
			ImageTransparency = owned and 0 or 0.45, ZIndex = 65,
		}, thumbnailFrame)
		H.round(thumbnail, 8)
		local title = H.label(row, H.prettyType(item.typeName), 118, 13, 245, 40, 16, C.text, FB)
		title.Name = "SaveItemTitle"
		title.TextWrapped = true
		title.TextTruncate = Enum.TextTruncate.None
		title.ZIndex = 65
		local idLabel = H.label(row, "ID: " .. tostring(item.id), 118, 56, 240, 18, 11, C.sub, F)
		idLabel.Name = "SaveItemId"
		idLabel.ZIndex = 65
		local ownership = H.label(row, owned and "OWNED · READY TO SAVE" or "NOT OWNED · EXCLUDED", 118, 82, 137, 20, 10, owned and C.success or C.sub, FB)
		ownership.Name = "SaveItemOwnership"
		ownership.ZIndex = 65
		local mark
		if owned then
			mark = H.new("TextLabel", {
				Name = "SaveSelectionMark", AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(28, 28),
				BackgroundColor3 = selected and C.accent or C.field,
				Text = selected and "✓" or "", TextColor3 = C.text, Font = FB, TextSize = 17,
				TextScaled = false, BorderSizePixel = 0, ZIndex = 66,
			}, row)
			H.round(mark, 14)
			H.new("UIStroke", { Color = selected and C.accent or C.line, Transparency = 0.2, Thickness = 1 }, mark)
		end
		local buyButton
		if not owned then
			buyButton = H.mkButton(row, "Buy", 128, 29, C.success)
			buyButton.Name = "SaveItemBuyButton"
			buyButton.AnchorPoint = Vector2.new(1, 1)
			buyButton.Position = UDim2.new(1, -9, 1, -8)
			buyButton.Visible = false
			buyButton.Active = false
			buyButton.ZIndex = 68
			local hoverActive = false
			local function showBuy()
				hoverActive = true
				buyButton.Visible = true
				saveBundleTools.request(item, row, buyButton, idLabel, saveLoadToken)
			end
			local function hideBuy()
				hoverActive = false
				task.delay(0.12, function()
					if not hoverActive and buyButton.Parent then buyButton.Visible = false end
				end)
			end
			row.MouseEnter:Connect(showBuy)
			row.MouseLeave:Connect(hideBuy)
			buyButton.MouseEnter:Connect(function() hoverActive = true end)
			row.Activated:Connect(function()
				if UserInputService.TouchEnabled then
					if buyButton.Visible then buyButton.Visible = false else showBuy() end
				end
			end)
			buyButton.Activated:Connect(function()
				local offer = saveBundleTools.getOffer(item.id)
				if not offer then
					saveBundleTools.request(item, row, buyButton, idLabel, saveLoadToken)
					return
				end
				buyButton.Active = false
				buyButton.Text = "Opening..."
				local promptOk, promptError = pcall(function()
					if offer.kind == "bundle" then
						MarketplaceService:PromptBundlePurchase(player, offer.id)
					else
						MarketplaceService:PromptPurchase(player, item.id)
					end
				end)
				if not promptOk then
					buyButton.Text = "Try again"
					buyButton.Active = true
					warn("[CatalogUI] Save review purchase prompt failed:", promptError)
				else
					task.delay(1.5, function()
						if buyButton.Parent then
							buyButton.Text = offer.kind == "bundle" and "Buy bundle" or "Buy item"
							buyButton.Active = true
						end
					end)
				end
			end)
		end
		if owned then
			row.Activated:Connect(function()
				saveSelected[item.id] = not saveSelected[item.id]
				local nowSelected = saveSelected[item.id] == true
				row.BackgroundColor3 = nowSelected and C.card or C.panel
				outline.Color = nowSelected and C.accent or C.line
				mark.BackgroundColor3 = nowSelected and C.accent or C.field
				mark.Text = nowSelected and "✓" or ""
				mark:FindFirstChildOfClass("UIStroke").Color = nowSelected and C.accent or C.line
				updateSaveCount()
			end)
		end
		table.insert(saveRows, row)

		task.spawn(function()
			local ok, info = pcall(H.getProductInfo, item.id, Enum.InfoType.Asset)
			if ok and type(info) == "table" and row.Parent then
				title.Text = tostring(info.Name or H.prettyType(item.typeName))
			end
		end)
	end

	local function openSaveReview()
		if #currentEquippedItems == 0 then
			setStatus("There are no currently worn items to review.")
			return
		end
		closeSaveReview()
		H.saveOverlay.Visible = true
		H.saveHint.Text = "Checking your inventory. Only owned items can be selected for the saved avatar/outfit."
		H.saveAvatarBtn.Active = false
		H.saveOutfitBtn.Active = false
		H.saveAvatarBtn.BackgroundTransparency = 0.35
		H.saveOutfitBtn.BackgroundTransparency = 0.35
		local token = saveLoadToken
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			H.saveHint.Text = "Your character is not ready yet."
			return
		end
		local descOk, description = pcall(function() return humanoid:GetAppliedDescription() end)
		if not descOk or not description then
			H.saveHint.Text = "Could not read your current avatar description."
			return
		end
		saveBaseDescription = description
		task.spawn(function()
			local owned, reason = loadOwnedAssetIds()
			if token ~= saveLoadToken or not H.saveOverlay.Visible then return end
			if not owned then
				H.saveHint.Text = tostring(reason or "Could not verify item ownership.")
				return
			end
			table.clear(saveOwned)
			table.clear(saveSelected)
			for id in pairs(owned) do saveOwned[id] = true end
			clearSaveRows()
			local itemCopy = table.clone(currentEquippedItems)
			table.sort(itemCopy, function(a, b)
				if tostring(a.typeName) == tostring(b.typeName) then return a.id < b.id end
				return tostring(a.typeName) < tostring(b.typeName)
			end)
			local ownedCount = 0
			for _, item in ipairs(itemCopy) do
				if saveOwned[item.id] then
					saveSelected[item.id] = true
					ownedCount += 1
				end
				createSaveRow(item, #saveRows + 1)
			end
			H.saveHint.Text = tostring(ownedCount) .. " of " .. tostring(#itemCopy) .. " currently worn items are owned. Select the items to include, then choose how to save."
			H.saveAvatarBtn.Active = ownedCount > 0
			H.saveOutfitBtn.Active = ownedCount > 0
			H.saveAvatarBtn.BackgroundTransparency = ownedCount > 0 and 0 or 0.45
			H.saveOutfitBtn.BackgroundTransparency = ownedCount > 0 and 0 or 0.45
			updateSaveCount()
		end)
	end

	local function filterDescriptionToSelection(description, selectedIds)
		local singleProperties = {
			"GraphicTShirt", "Shirt", "Pants", "Face", "Head", "Torso", "RightArm", "LeftArm",
			"RightLeg", "LeftLeg", "ClimbAnimation", "FallAnimation", "IdleAnimation", "JumpAnimation",
			"RunAnimation", "SwimAnimation", "WalkAnimation", "MoodAnimation",
		}
		for _, property in ipairs(singleProperties) do
			local ok, id = pcall(function() return tonumber(description[property]) end)
			if ok and id and id > 0 and not selectedIds[id] then
				pcall(function() description[property] = 0 end)
			end
		end
		local multiProperties = {
			"HatAccessory", "HairAccessory", "FaceAccessory", "NeckAccessory", "ShouldersAccessory",
			"FrontAccessory", "BackAccessory", "WaistAccessory", "EarAccessory", "EyeAccessory",
			"EyebrowAccessory", "EyelashAccessory", "FaceMakeup", "LipMakeup", "EyeMakeup",
		}
		for _, property in ipairs(multiProperties) do
			local ok, value = pcall(function() return description[property] end)
			if ok and type(value) == "string" then
				local kept = {}
				for token in value:gmatch("[^,]+") do
					local id = tonumber(token)
					if id and selectedIds[id] then table.insert(kept, tostring(id)) end
				end
				pcall(function() description[property] = table.concat(kept, ",") end)
			end
		end
		local accessoryOk, accessories = pcall(function() return description:GetAccessories(true) end)
		if accessoryOk and type(accessories) == "table" then
			local kept = {}
			for _, accessory in ipairs(accessories) do
				if selectedIds[tonumber(accessory.AssetId)] then table.insert(kept, accessory) end
			end
			pcall(function() description:SetAccessories(kept, true) end)
		end
		local emoteOk, emotes = pcall(function() return description:GetEquippedEmotes() end)
		if emoteOk and type(emotes) == "table" then
			local kept = {}
			for name, value in pairs(emotes) do
				local id
				if type(value) == "number" or type(value) == "string" then id = tonumber(value)
				elseif type(value) == "table" then id = tonumber(value.Id or value.AssetId or value.id) end
				if id and selectedIds[id] then kept[name] = value end
			end
			pcall(function() description:SetEquippedEmotes(kept) end)
		end
	end

	H.submitSave = function(kind)
		local selected = {}
		for id, enabled in pairs(saveSelected) do
			if enabled and saveOwned[id] then selected[id] = true end
		end
		local selectedCount = 0
		for _ in pairs(selected) do selectedCount += 1 end
		if selectedCount == 0 then
			H.saveHint.Text = "Select at least one owned item first."
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or not saveBaseDescription then
			H.saveHint.Text = "Your avatar description is no longer available. Reopen Save to Roblox."
			return
		end
		local cloneOk, description = pcall(function() return saveBaseDescription:Clone() end)
		if not cloneOk or not description then
			H.saveHint.Text = "Could not prepare the selected avatar items."
			return
		end
		filterDescriptionToSelection(description, selected)
		closeSaveReview()
		pendingSaveDescription = description
		local promptOk, promptError = pcall(function()
			if kind == "avatar" then
				AvatarEditorService:PromptSaveAvatar(description, humanoid.RigType)
			else

				AvatarEditorService:PromptCreateOutfit(description, humanoid.RigType)
			end
		end)
		if not promptOk then
			if pendingSaveDescription then pcall(function() pendingSaveDescription:Destroy() end) end
			pendingSaveDescription = nil
			setStatus("Roblox could not open the save prompt: " .. tostring(promptError))
		else
			setStatus(kind == "avatar" and "Confirm the Roblox prompt to save your avatar." or "Confirm the Roblox prompt to create your outfit.")
		end
	end

	H.refreshSaveRowStates = function()
		for _, row in ipairs(saveRows) do
			local id = tonumber(row.Name:match("SaveItem_(%d+)"))
			if id and saveOwned[id] then
				local selected = saveSelected[id] == true
				row.BackgroundColor3 = selected and C.card or C.panel
				local outline = row:FindFirstChildOfClass("UIStroke")
				if outline then outline.Color = selected and C.accent or C.line end
				local mark = row:FindFirstChild("SaveSelectionMark")
				if mark then
					mark.BackgroundColor3 = selected and C.accent or C.field
					mark.Text = selected and "✓" or ""
					local markStroke = mark:FindFirstChildOfClass("UIStroke")
					if markStroke then markStroke.Color = selected and C.accent or C.line end
				end
			end
		end
		updateSaveCount()
	end
	H.saveCloseBtn.Activated:Connect(closeSaveReview)
	H.saveCancelBtn.Activated:Connect(closeSaveReview)
	H.saveSelectAllBtn.Activated:Connect(function()
		for id in pairs(saveOwned) do saveSelected[id] = true end
		H.refreshSaveRowStates()
	end)
	H.saveSelectNoneBtn.Activated:Connect(function()
		table.clear(saveSelected)
		H.refreshSaveRowStates()
	end)
	H.saveAvatarBtn.Activated:Connect(function() H.submitSave("avatar") end)
	H.saveOutfitBtn.Activated:Connect(function() H.submitSave("outfit") end)
	H.saveToRobloxBtn.Activated:Connect(openSaveReview)

	AvatarEditorService.PromptSaveAvatarCompleted:Connect(function(result)
		if pendingSaveDescription then pcall(function() pendingSaveDescription:Destroy() end) end
		pendingSaveDescription = nil
		setStatus(result == Enum.AvatarPromptResult.Success and "Avatar saved to Roblox successfully." or "Avatar save was cancelled or failed.")
	end)
	AvatarEditorService.PromptCreateOutfitCompleted:Connect(function(result, failureType)
		if pendingSaveDescription then pcall(function() pendingSaveDescription:Destroy() end) end
		pendingSaveDescription = nil
		if result == Enum.AvatarPromptResult.Success then
			setStatus("Outfit saved to Roblox successfully.")
		elseif result == Enum.AvatarPromptResult.PermissionDenied then
			setStatus("Outfit save was cancelled. Confirm the Roblox outfit prompt to continue.")
		elseif failureType == Enum.CreateOutfitFailure.OutfitLimitReached then
			setStatus("Roblox could not save this outfit: your saved-outfit limit has been reached.")
		elseif failureType == Enum.CreateOutfitFailure.InvalidName then
			setStatus("Roblox rejected the outfit name. Try a different name in the Roblox prompt.")
		else
			warn("[CatalogUI] PromptCreateOutfit failed:", result, failureType)
			setStatus("Roblox could not create the outfit: " .. tostring(failureType or result) .. ". Try again in the published experience.")
		end
	end)

	local bulkPurchaseCooldown = false
	H.bulkPurchaseCooldownToken = 0
	local purchaseButtonText = "Purchase All (up to 20)"

	H.beginBulkPurchaseCooldown = function()
		bulkPurchaseCooldown = true
		H.bulkPurchaseCooldownToken += 1
		local token = H.bulkPurchaseCooldownToken
		H.purchaseAllBtn.Text = "Please wait..."
		task.delay(2, function()
			if H.bulkPurchaseCooldownToken ~= token then return end
			bulkPurchaseCooldown = false
			if H.purchaseAllBtn and H.purchaseAllBtn.Parent then
				H.purchaseAllBtn.Text = purchaseButtonText
			end
		end)
	end

	H.getBulkPurchaseLines = function()
		local lines, seen, truncated = {}, {}, false
		local assetType = H.enumItem(Enum.MarketplaceProductType, "AvatarAsset")
		if not assetType then
			return nil, "Roblox bulk avatar purchase types are unavailable on this client."
		end

		local items = table.clone(currentEquippedItems)
		local function purchasePriority(item)
			local name = tostring(item.typeName or ""):gsub("^Enum%.AvatarAssetType%.", ""):gsub("^AvatarAssetType%.", "")
			if name:find("Animation", 1, true) then return 1 end
			if name == "Head" or name == "DynamicHead" or name == "Torso"
				or name == "LeftArm" or name == "RightArm" or name == "LeftLeg" or name == "RightLeg" then
				return 2
			end
			if name == "LeftShoeAccessory" or name == "RightShoeAccessory" or name == "LeftShoe" or name == "RightShoe" then
				return 3
			end
			return 4
		end
		table.sort(items, function(a, b)
			local priorityA, priorityB = purchasePriority(a), purchasePriority(b)
			if priorityA ~= priorityB then return priorityA < priorityB end
			if tostring(a.typeName) == tostring(b.typeName) then
				return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
			end
			return tostring(a.typeName) < tostring(b.typeName)
		end)

		for _, item in ipairs(items) do
			local id = tonumber(item.id)
			if id and id > 0 and id % 1 == 0 and id <= 9007199254740991 then
				local key = tostring(assetType) .. ":" .. tostring(id)
				if not seen[key] then
					seen[key] = true
					if #lines < 20 then
						table.insert(lines, {
							Type = assetType,
							Id = tostring(id),
							AssetType = tostring(item.typeName or ""):gsub("^Enum%.AvatarAssetType%.", ""):gsub("^AvatarAssetType%.", ""),
						})
					else
						truncated = true
					end
				end
			end
		end
		return lines, nil, truncated
	end

	H.purchaseAllBtn.Activated:Connect(function()
		if bulkPurchaseCooldown then return end
		if #currentEquippedItems == 0 then
			setStatus("There are no currently worn items to purchase.")
			return
		end

		local lines, errorText, truncated = H.getBulkPurchaseLines()
		if not lines then
			setStatus(errorText)
			return
		end
		if #lines == 0 then
			setStatus("No valid currently worn items were found.")
			return
		end

		H.beginBulkPurchaseCooldown()
		if truncated then
			setStatus("Opening purchase for the first 20 items.")
		else
			setStatus("Opening purchase for " .. tostring(#lines) .. " items.")
		end
		bulkPurchaseEvent:FireServer(lines)
	end)
end

local function buildParams(chipData, tab)
	local params = CatalogSearchParams.new()
	params.SearchKeyword = state.keyword
	params.IncludeOffSale = state.offsale
	params.SortType = SORTS[state.sort].value
	local limitedFilter = tab and tab.limitedOnly and H.enumItem(Enum.SalesTypeFilter, "Collectibles")
	params.SalesTypeFilter = limitedFilter or SALES[state.sale].value
	if state.min then params.MinPrice = state.min end
	if state.max then params.MaxPrice = state.max end
	if state.creator ~= "" then params.CreatorName = state.creator end
	if chipData then
		if #chipData.assets > 0 then params.AssetTypes = chipData.assets end
		if chipData.bundles and #chipData.bundles > 0 then params.BundleTypes = chipData.bundles end
	end
	return params
end

H.load = function()
	sourceId += 1
	local myId = sourceId
	local tabIndex = curTab
	local chipIndex = chipIdx[curTab]
	local tab = TABS[curTab]
	local chipData = tab.chips and tab.chips[chipIdx[curTab]] or nil
	publicInventoryViewActive = false
	publicInventoryRequestId = nil
	publicInventoryStreamRequestId = nil
	publicInventoryReceivedCount = 0
	publicInventoryUsername = ""

	table.clear(publicInventoryAllItems)
	table.clear(publicInventoryItems)
	activeInventoryItems = nil
	inventoryRenderedCount = 0
	H.inventoryCanvasItemCount = nil
	H.pendingInventoryRenderCount = 0
	local scrollKey = getResultScrollKey(tabIndex, chipIndex)
	local restoreY = resultScrollPositions[scrollKey] or 0
	pages = nil
	loadingMore = false
	clearTiles()
	setStatus("Loading...")
	if tab.kind == "catalog" then table.clear(catalogLoadedById) end
	if chipData and chipData.special == "inventorybundles" then
		results.Visible = true
		bodyColorPane.Visible, bodyScalePane.Visible = false, false
		setStatus("Roblox's supported inventory API lists owned assets by AvatarAssetType, not owned bundle records. Check Outfits for saved looks or catalog bundle categories for bundles.")
		return
	end
	if chipData and (chipData.special == "bodycolors" or chipData.special == "bodyscaling") then
		results.Visible = false
		bodyColorPane.Visible = chipData.special == "bodycolors"
		bodyScalePane.Visible = chipData.special == "bodyscaling"
		setStatus(chipData.special == "bodycolors" and "Choose a body color above." or "Adjust the avatar scale values, then apply them.")
		return
	end
	bodyColorPane.Visible, bodyScalePane.Visible = false, false
	results.Visible = true

	if tab.kind == "inventory" then
		local granted = ensureInventory()
		if myId ~= sourceId then return end
		if not granted then
			setStatus("Inventory access wasn't allowed. Open this tab again to retry.")
			return
		end
		if inventoryCacheReady then
			local filtered = getInventoryItemsForChip(chipData)
			beginInventoryTileView(filtered, tabIndex, chipIndex, restoreY, myId)
			setStatus("Showing first " .. tostring(math.min(#filtered, INVENTORY_INITIAL_RENDER_COUNT)) .. " of " .. tostring(#filtered)
				.. " cached items · scroll to load more · newest acquired first")
			return
		end
		if inventoryCacheLoading then

			local filtered = getInventoryItemsForChip(chipData)
			beginInventoryTileView(filtered, tabIndex, chipIndex, restoreY, myId)
			setStatus("Inventory loading in background · " .. tostring(#inventoryLoadedById)
				.. " cached items · " .. tostring(#filtered) .. " in this category so far")
			return
		end
		if not chipData or #chipData.assets == 0 then
			setStatus("Nothing to show here")
			return
		end

		inventoryCacheLoading = true
		inventoryCacheError = nil
		local alreadyCached = getInventoryItemsForChip(chipData)
		beginInventoryTileView(alreadyCached, tabIndex, chipIndex, restoreY, myId)
		setStatus("Caching your inventory in the background · " .. tostring(#inventoryLoadedById) .. " items already cached...")
		task.spawn(function()

			local failedTypes = {}
			local fetchedTypes = 0
			local totalTypes = #allTypes
			local pendingTypes = {}
			for typeIndex, assetType in ipairs(allTypes) do
				if inventoryTypesReady[assetType.Value] then
					fetchedTypes += 1
				else
					table.insert(pendingTypes, { assetType = assetType, index = typeIndex })
				end
			end
			local nextTypeIndex = 0
			local viewRefreshQueued = false
			local lastInventoryStatus = 0

			local function queueInventoryViewRefresh()
				if viewRefreshQueued then return end
				viewRefreshQueued = true
				task.delay(0.25, function()
					viewRefreshQueued = false
					if inventoryCacheLoading then refreshActiveInventoryView() end
				end)
			end

			local function fetchOneInventoryType(assetType)
				local lastError = "unknown inventory error"

				for attempt = 1, 3 do
					local requestOk, inventoryPages = pcall(H.callAES, "GetInventory", { assetType })
					if requestOk and inventoryPages then
						local pageCount = 0
						local seenPageSignatures = {}
						local pageError = nil
						while pageCount < 500 do
							local pageOk, page = pcall(function() return inventoryPages:GetCurrentPage() end)
							if not pageOk or type(page) ~= "table" then
								pageError = "could not read page: " .. tostring(page)
								break
							end

							local pageIds = {}
							for _, entry in ipairs(page) do
								local itemId = tonumber(entry.AssetId or entry.assetId or entry.Id or entry.id)
								if itemId then table.insert(pageIds, itemId) end
							end
							table.sort(pageIds)
							local signature = table.concat(pageIds, ",")
							if seenPageSignatures[signature] then
								pageError = "Roblox repeated a page for " .. assetType.Name
								break
							end
							seenPageSignatures[signature] = true
							local addedThisPage = collectInventoryPage(page)
							pageCount += 1
							if addedThisPage > 0 then queueInventoryViewRefresh() end
							if TABS[curTab] and TABS[curTab].kind == "inventory" and os.clock() - lastInventoryStatus >= 0.45 then
								lastInventoryStatus = os.clock()
								setStatus("Caching " .. H.prettyType(assetType.Name) .. " · page " .. tostring(pageCount)
									.. " · " .. tostring(#inventoryLoadedById) .. " unique items cached")
							end

							local finishedOk, isFinished = pcall(function() return inventoryPages.IsFinished end)
							if finishedOk and isFinished == true then
								return true, pageCount
							elseif not finishedOk then
								pageError = "could not read page completion state: " .. tostring(isFinished)
								break
							end

							task.wait(INVENTORY_PAGE_DELAY_SECONDS)
							local advanceOk, advanceError = false, nil
							for advanceAttempt = 1, 3 do
								advanceOk, advanceError = pcall(function()
									inventoryPages:AdvanceToNextPageAsync()
								end)
								if advanceOk then break end
								task.wait(0.25 * advanceAttempt)
							end
							if not advanceOk then
								pageError = "page advance failed: " .. tostring(advanceError)
								break
							end
						end
						if not pageError then pageError = "exceeded 500 pages for " .. assetType.Name end
						lastError = pageError
					else
						lastError = "request failed: " .. tostring(inventoryPages)
					end
					if attempt < 3 then task.wait(0.4 * attempt) end
				end
				return false, lastError
			end

			local workerCount = math.min(3, #pendingTypes)
			local finishedWorkers = 0
			local function inventoryTypeWorker()
				while inventoryCacheLoading do
					nextTypeIndex += 1
					local job = pendingTypes[nextTypeIndex]
					if not job then break end
					local assetType = job.assetType
					if TABS[curTab] and TABS[curTab].kind == "inventory" then
						setStatus("Caching inventory · type " .. tostring(job.index) .. "/" .. tostring(totalTypes)
							.. " · " .. H.prettyType(assetType.Name) .. " · " .. tostring(#inventoryLoadedById) .. " items found")
					end
					local typeOk, typeResult = fetchOneInventoryType(assetType)
					if typeOk then
						inventoryTypesReady[assetType.Value] = true
					else
						table.insert(failedTypes, assetType.Name .. " (" .. tostring(typeResult) .. ")")
					end
					fetchedTypes += 1
				end
				finishedWorkers += 1
			end
			for _ = 1, workerCount do task.spawn(inventoryTypeWorker) end
			while finishedWorkers < workerCount do task.wait(0.05) end
			refreshActiveInventoryView()

			local loadError
			if #failedTypes > 0 then
				loadError = tostring(#failedTypes) .. " asset type(s) could not be fully read: " .. table.concat(failedTypes, "; ")
			end
			inventoryCacheLoading = false
			inventoryCacheError = loadError and tostring(loadError) or nil
			inventoryCacheReady = loadError == nil

			if TABS[curTab] and TABS[curTab].kind == "inventory" then
				local activeTabIndex = curTab
				local activeChipIndex = chipIdx[curTab]
				local activeSource = sourceId
				local activeKey = getResultScrollKey(activeTabIndex, activeChipIndex)
				local activeY = resultScrollPositions[activeKey] or 0
				local activeChip = TABS[curTab].chips and TABS[curTab].chips[activeChipIndex]

				if not (activeChip and activeChip.special == "inventorybundles") then
					local filtered = getInventoryItemsForChip(activeChip)
					beginInventoryTileView(filtered, activeTabIndex, activeChipIndex, activeY, activeSource)
					if inventoryCacheReady then
						setStatus("Cached " .. tostring(#inventoryLoadedById) .. " items across " .. tostring(fetchedTypes) .. "/" .. tostring(totalTypes) .. " types · first " .. tostring(math.min(#filtered, INVENTORY_INITIAL_RENDER_COUNT)) .. " shown · scroll to load more")
					else
						warn("[CatalogUI] Inventory cache is partial:", inventoryCacheError)
						setStatus("Loaded " .. tostring(#inventoryLoadedById) .. " items · some asset types failed · scroll to load more")
					end
				end
			end
		end)
		return
	end

	local ok, response
	if tab.kind == "catalog" then
		ok, response = pcall(H.callAES, "SearchCatalog", buildParams(chipData, tab))
	else
		local granted = ensureInventory()
		if myId ~= sourceId then return end
		if not granted then
			setStatus("Inventory access wasn't allowed. Open this tab again to retry.")
			return
		end
		ok, response = pcall(getOutfits)
	end
	if myId ~= sourceId then return end
	if not ok or not response then
		warn("[CatalogUI] Load failed:", response)
		setStatus("Couldn't load (see Output)")
		return
	end

	pages = response
	local count = addCurrentPage(tab.kind)
	if count == 0 then setStatus("No results")
	elseif chipData and chipData.label == "Backgrounds" then setStatus("Tap a background to preview it behind your avatar")
	else setStatus(tab.kind == "outfits" and "Your saved outfits · newest Roblox results first · tap to wear, right-click for details" or "Tap an item to wear it") end
	restoreResultsScroll(tabIndex, chipIndex, restoreY, myId)
	checkFill()
end

local chipScrollPositions = {}
chipHolder:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	chipScrollPositions[curTab] = chipHolder.CanvasPosition.X
end)
local function rebuildChips()
	local savedChipScroll = chipScrollPositions[curTab] or 0
	for _, child in ipairs(chipHolder:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	local tab = TABS[curTab]
	if not tab.chips then return end
	for index, chipData in ipairs(tab.chips) do
		local active = index == chipIdx[curTab]
		local button = H.new("TextButton", {
			LayoutOrder = index, Text = chipData.label, AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 32), BackgroundColor3 = active and C.accent or C.card,
			TextColor3 = C.text, Font = FM, TextSize = 16,
		}, chipHolder)
		H.applyTouchScale(button, 1.06)
		H.round(button, 16)
		H.padX(button)
		button.Activated:Connect(function()
			if chipIdx[curTab] == index then return end
			chipIdx[curTab] = index
			rebuildChips()
			local selected = TABS[curTab].chips[index]
			if selected and selected.special == "bodycolors" then
				pages = nil
				sourceId += 1
				clearTiles()
				results.Visible = false
				bodyColorPane.Visible = true
				bodyScalePane.Visible = false
				setStatus("Choose a body color above.")
			elseif selected and selected.special == "bodyscaling" then
				pages = nil
				sourceId += 1
				clearTiles()
				results.Visible = false
				bodyColorPane.Visible = false
				bodyScalePane.Visible = true
				setStatus("Adjust the avatar scale values, then apply them.")
			else
				bodyColorPane.Visible, bodyScalePane.Visible = false, false
				results.Visible = true
				H.load()
			end
		end)
	end
	task.defer(function()
		if not chipHolder.Parent then return end
		local maximum = math.max(0, chipHolder.AbsoluteCanvasSize.X - chipHolder.AbsoluteSize.X)
		chipHolder.CanvasPosition = Vector2.new(math.clamp(savedChipScroll, 0, maximum), 0)
	end)
end

H.refreshFilterLabels = function()
	sortBtn.Text = "Sort: ".. SORTS[state.sort].label
	for index, option in ipairs(sortOptionButtons) do option.BackgroundColor3 = index == state.sort and C.accent or C.card end
	saleBtn.Text = SALES[state.sale].label
	offBtn.Text = state.offsale and "Offsale: On" or "Offsale: Off"
	offBtn.BackgroundColor3 = state.offsale and C.accent or C.card
end

local function setTab(index)
	sortMenu.Visible = false
	if searchBox.Text ~= state.keyword then state.keyword = searchBox.Text end
	curTab = index
	searchBox.Text = state.keyword
	for tabIndex, entry in ipairs(tabButtons) do
		entry.btn.TextColor3 = tabIndex == index and C.text or C.sub
		entry.ul.Visible = tabIndex == index
	end
	local selectedButton = tabButtons[index] and tabButtons[index].btn
	if selectedButton then
		task.defer(function()
			local left = selectedButton.AbsolutePosition.X - tabBar.AbsolutePosition.X + tabBar.CanvasPosition.X
			local right = left + selectedButton.AbsoluteSize.X
			local visibleWidth = tabBar.AbsoluteSize.X
			local target = tabBar.CanvasPosition.X
			if left < target then target = left elseif right > target + visibleWidth then target = right - visibleWidth end
			local maxCanvas = math.max(0, tabBar.AbsoluteCanvasSize.X - visibleWidth)
			tabBar.CanvasPosition = Vector2.new(math.clamp(target, 0, maxCanvas), 0)
		end)
	end
	local tab = TABS[index]
	local isCatalog = tab.kind == "catalog"
	local isLimited = tab.limitedOnly == true
	sortBtn.Visible = isCatalog
	saleBtn.Visible = isCatalog and not isLimited
	offBtn.Visible = isCatalog
	publicAvatarRow.Visible = tab.kind == "outfits"
	minBox.Visible, maxBox.Visible, creatorBox.Visible = isCatalog, isCatalog, isCatalog
	linkRow.Visible = isCatalog
	urlBox.Visible, linkLabel.Visible = isCatalog, isCatalog
	if isCatalog then
		searchBox.PlaceholderText = tab.name == "Body" and "Search body items" or (isLimited and "Search limited items" or "Search the catalog")
	elseif tab.kind == "inventory" then searchBox.PlaceholderText = "Filter your items"
	else searchBox.PlaceholderText = "Filter outfits or inventory" end
	chipHolder.Visible = tab.chips ~= nil
	local selected = tab.chips and tab.chips[chipIdx[index]] or nil
	local showColors = selected and selected.special == "bodycolors"
	local showScaling = selected and selected.special == "bodyscaling"
	bodyColorPane.Visible = showColors == true
	bodyScalePane.Visible = showScaling == true
	results.Visible = not showColors and not showScaling
	rebuildChips()
	H.load()
end

for index, entry in ipairs(tabButtons) do
	entry.btn.Activated:Connect(function()
		if index ~= curTab then setTab(index) end
	end)
end

searchBox.FocusLost:Connect(function()
	local keyword = searchBox.Text
	if keyword ~= state.keyword then
		state.keyword = keyword
		if TABS[curTab].kind == "catalog" then
			H.load()
		elseif TABS[curTab].kind == "inventory" and (inventoryCacheReady or inventoryCacheLoading) then
			local key = getResultScrollKey(curTab, chipIdx[curTab])
			resultScrollPositions[key] = 0
			H.load()
		else
			applyFilter()
		end
	end
end)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local tab = TABS[curTab]
	if not tab then return end

	-- Keep public inventory filtering on its existing path.
	if publicInventoryViewActive then
		applyFilter()
		return
	end

	-- Rebuild private inventory immediately when the search changes.
	if tab.kind == "inventory" then
		local chipIndex = chipIdx[curTab]
		local chipData = tab.chips and tab.chips[chipIndex]

		if chipData and chipData.special then
			return
		end

		state.keyword = searchBox.Text

		local key = getResultScrollKey(curTab, chipIndex)

		-- Always start filtered results at the top.
		resultScrollPositions[key] = 0

		-- Filter the cached inventory, not the Roblox API.
		local filtered = getInventoryItemsForChip(chipData)

		beginInventoryTileView(
			filtered,
			curTab,
			chipIndex,
			0,
			sourceId
		)

		local status = "Showing first "
			.. tostring(math.min(#filtered, INVENTORY_INITIAL_RENDER_COUNT))
			.. " of "
			.. tostring(#filtered)
			.. " matching items"

		if inventoryCacheLoading then
			status ..= " · inventory still loading"
		else
			status ..= " · newest acquired first"
		end

		setStatus(status)
		return
	end

	if tab.kind ~= "catalog" then
		applyFilter()
	end
end)

sortBtn.Activated:Connect(function() sortMenu.Visible = not sortMenu.Visible end)
saleBtn.Activated:Connect(function()
	state.sale = state.sale % #SALES + 1
	H.refreshFilterLabels()
	H.load()
end)
offBtn.Activated:Connect(function()
	state.offsale = not state.offsale
	H.refreshFilterLabels()
	H.load()
end)

local function parsePrice(box)
	local value = tonumber(box.Text)
	return value and value >= 0 and math.floor(value) or nil
end
local function updatePriceFilter()
	local nextMin, nextMax = parsePrice(minBox), parsePrice(maxBox)
	if nextMin and nextMax and nextMin > nextMax then
		setStatus("Minimum price cannot exceed maximum price")
		minBox.Text = state.min and tostring(state.min) or ""
		maxBox.Text = state.max and tostring(state.max) or ""
		return
	end
	if nextMin ~= state.min or nextMax ~= state.max then
		state.min, state.max = nextMin, nextMax
		H.load()
	end
end
minBox.FocusLost:Connect(updatePriceFilter)
maxBox.FocusLost:Connect(updatePriceFilter)
creatorBox.FocusLost:Connect(function()
	local value = H.trim(creatorBox.Text)
	if value ~= state.creator then
		state.creator = value
		if TABS[curTab].kind == "catalog" then H.load() end
	end
end)

H.inspectPublicAvatar = function()
	if H.publicSearchLocked then return end

	local username = H.trim(publicAvatarUserBox.Text)

	if #username < 3 or #username > 20
		or not username:match("^[%w_]+$") then
		setStatus("Invalid username")
		return
	end

	local requestId = beginBusy("Loading public inventory...")

	if not requestId then return end

	publicInventoryRequestId = requestId
	publicInventoryStreamRequestId = nil
	publicInventoryViewActive = false
	publicInventoryReceivedCount = 0
	publicInventoryUsername = username

	table.clear(publicInventoryAllItems)
	table.clear(publicInventoryItems)

	H.setPublicSearchLocked(true)

	-- Only request inventory here.
	-- Outfits are loaded separately by the Search outfits button.
	remote:FireServer("PublicInventory", username, nil, requestId)
end

H.inspectPublicOutfits = function()
	if H.publicSearchLocked then return end

	local username = H.trim(publicAvatarUserBox.Text)

	if #username < 3 or #username > 20
		or not username:match("^[%w_]+$") then
		setStatus("Invalid username")
		return
	end

	local requestId = beginBusy("Loading public outfits...")

	if not requestId then return end

	-- Clear previous public inventory state.
	publicInventoryRequestId = nil
	publicInventoryStreamRequestId = nil
	publicInventoryViewActive = false

	table.clear(publicInventoryAllItems)
	table.clear(publicInventoryItems)

	H.setPublicSearchLocked(true)

	remote:FireServer("PublicOutfits", username, nil, requestId)
end

inspectPublicAvatarBtn.Activated:Connect(H.inspectPublicAvatar)
publicOutfitsBtn.Activated:Connect(H.inspectPublicOutfits)

myOutfitsBtn.Activated:Connect(function()
	publicAvatarUserBox.Text = ""
	state.keyword = searchBox.Text

	if TABS[curTab].kind == "outfits" then
		H.load()
	end
end)

publicAvatarUserBox.FocusLost:Connect(function(enterPressed)
	if enterPressed and not H.publicSearchLocked then
		H.inspectPublicOutfits()
	end
end)

local currentDetailData
local detailLoadToken = 0
local bundleContentEntries = {}
local bundleContentRendered = 0
local bundleContentRendering = false
local bundleContentGeneration = 0
local bundleContentRows = {}
local bundleContentIsOutfit = false
local bundleContentOutfitId = nil
local bundleContentDetailToken = nil
local subItemMetadataCache = {}
local outfitBundleMergeCache = {}
local BUNDLE_CONTENT_BATCH_SIZE = 24
local function updateBundleContentsCanvas()

	if not bundleItemsScroll.Parent then return end
	local gridHeight = bundleItemsGrid.AbsoluteContentSize.Y
	local paddingHeight = bundleItemsPadding.PaddingTop.Offset + bundleItemsPadding.PaddingBottom.Offset
	local contentHeight = math.ceil(gridHeight + paddingHeight + 4)
	local viewportHeight = bundleItemsScroll.AbsoluteWindowSize.Y
	if viewportHeight <= 0 then viewportHeight = bundleItemsScroll.AbsoluteSize.Y end
	bundleItemsScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	bundleItemsScroll.CanvasSize = UDim2.fromOffset(0, math.max(viewportHeight, contentHeight))
end
bundleItemsGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateBundleContentsCanvas)
bundleItemsScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	updateBundleGridSizing()
	task.defer(updateBundleContentsCanvas)
end)
local function clearBundleContents()
	bundleContentGeneration += 1
	bundleContentRendering = false
	for _, child in ipairs(bundleItemsScroll:GetChildren()) do
		if child:IsA("GuiObject") and child ~= bundleItemsGrid then child:Destroy() end
	end
	table.clear(bundleContentEntries)
	table.clear(bundleContentRows)
	bundleContentIsOutfit = false
	bundleContentOutfitId = nil
	bundleContentDetailToken = nil
	bundleContentRendered = 0
	bundleItemsScroll.CanvasPosition = Vector2.zero
	bundleItemsScroll.CanvasSize = UDim2.new(0, 0, 0, bundleItemsScroll.AbsoluteSize.Y)
end
local BODY_BUNDLE_CONTENT_TYPES = {
	DynamicHead = true, Torso = true, LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true,
}

local function getSubItemMetadata(item)
	local id = tonumber(item.id)
	if not id then return { name = item.name or "Unknown item", priceText = "Price unavailable", countInTotal = false } end
	local fallbackName = item.name
	if fallbackName == "Loading item details..." or fallbackName == "" then fallbackName = nil end
	local cacheKey = (item.bundle and "B:" or "A:") .. tostring(id)
	local cached = subItemMetadataCache[cacheKey]
	if cached then return cached end

	local info = {}
	if item.bundle then
		local productOk, productInfo, detailsOk, details
		local completed = 0
		task.spawn(function()
			local callOk, lookupOk, lookupValue = pcall(getBundleProductInfo, id)
			productOk = callOk and lookupOk == true
			productInfo = callOk and lookupValue or nil
			completed += 1
		end)
		task.spawn(function()
			detailsOk, details = pcall(H.callAES, "GetItemDetails", id, Enum.AvatarItemType.Bundle)
			completed += 1
		end)
		while completed < 2 do task.wait() end
		if detailsOk and type(details) == "table" then
			for key, value in pairs(details) do info[key] = value end
		end
		if productOk and type(productInfo) == "table" then
			for key, value in pairs(productInfo) do
				if value ~= nil then info[key] = value end
			end
		end
		local detailPrice = detailsOk and type(details) == "table" and tonumber(details.PriceInRobux or details.Price) or nil
		local productPrice = productOk and type(productInfo) == "table" and tonumber(productInfo.PriceInRobux or productInfo.Price) or nil
		local savedPrice = tonumber(item.bundlePrice)
		local price = (detailPrice and detailPrice > 0 and detailPrice)
			or (productPrice and productPrice > 0 and productPrice)
			or (savedPrice and savedPrice > 0 and savedPrice)
			or detailPrice or productPrice or savedPrice
		local detailStatus = tostring(detailsOk and type(details) == "table" and details.PriceStatus or ""):lower()
		local productStatus = tostring(productOk and type(productInfo) == "table" and productInfo.PriceStatus or ""):lower()
		local status = tostring(item.bundlePriceStatus or detailStatus or productStatus or info.PriceStatus or ""):lower()
		local explicitlyFree = info.IsFree == true or item.bundleIsFree == true or detailStatus == "free" or productStatus == "free" or status == "free"
		local explicitlyOffSale = not explicitlyFree and (detailStatus == "off sale" or detailStatus == "offsale" or productStatus == "off sale" or productStatus == "offsale" or status == "off sale" or status == "offsale")
		local isPurchasable = info.IsPurchasable
		if isPurchasable == nil then isPurchasable = item.bundleIsPurchasable end
		local isForSale = info.IsForSale
		if isForSale == nil then isForSale = item.bundleIsForSale end
		if price == 0 and (isForSale == true or isPurchasable == true) then explicitlyFree = true end
		local priceText, countInTotal, totalPrice
		if explicitlyOffSale and not explicitlyFree then
			priceText, countInTotal = "Off sale", false
		elseif explicitlyFree then
			priceText, countInTotal, totalPrice = "Free", true, 0
		elseif price and price > 0 then
			priceText, countInTotal, totalPrice = "R$ " .. H.comma(price), true, price
		elseif isForSale == false or isPurchasable == false then
			priceText, countInTotal = "Off sale", false
		else
			priceText, countInTotal = "Price unavailable", false
		end
		cached = {
			name = tostring(info.Name or fallbackName or ((item.assetType or "Bundle") .. " #" .. tostring(id))),
			priceText = priceText, countInTotal = countInTotal, totalPrice = totalPrice,
		}
	else
		local aesOk, aesInfo, marketOk, marketInfo
		local completed = 0
		task.spawn(function()
			aesOk, aesInfo = pcall(H.callAES, "GetItemDetails", id, Enum.AvatarItemType.Asset)
			completed += 1
		end)
		task.spawn(function()
			marketOk, marketInfo = pcall(H.getProductInfo, id, Enum.InfoType.Asset)
			completed += 1
		end)
		while completed < 2 do task.wait() end
		if aesOk and type(aesInfo) == "table" then
			for key, value in pairs(aesInfo) do info[key] = value end
		end
		if marketOk and type(marketInfo) == "table" then

			for key, value in pairs(marketInfo) do
				if value ~= nil then info[key] = value end
			end
		end
		local collectibles = type(info.CollectiblesItemDetails) == "table" and info.CollectiblesItemDetails or {}
		local resale = tonumber(info.LowestResalePrice) or tonumber(collectibles.CollectibleLowestResalePrice)
		if (not resale or resale <= 0) and info.HasResellers == true then resale = tonumber(info.LowestPrice) end
		local limited = info.IsLimited == true or info.IsLimitedUnique == true or info.HasResellers == true
		local price = tonumber(info.PriceInRobux or info.Price)
		local priceText, countInTotal, totalPrice
		if resale and resale > 0 then
			priceText, countInTotal, totalPrice = "R$ " .. H.comma(resale) .. " resale", true, resale
		elseif info.IsForSale ~= false and (info.PriceStatus == "Free" or info.IsFree == true
			or price == 0) then
			priceText, countInTotal, totalPrice = "Free", true, 0
		elseif info.IsForSale == true and price and price > 0 then
			priceText, countInTotal, totalPrice = "R$ " .. H.comma(price), true, price
		elseif limited and info.HasResellers == false then
			priceText, countInTotal = "Limited · no resellers", false
		elseif limited and info.HasResellers == true then
			priceText, countInTotal = "Limited · resale price unavailable", false
		elseif info.IsForSale == false then
			priceText, countInTotal = "Off sale", false
		elseif price and price > 0 and info.IsForSale == nil then

			priceText, countInTotal, totalPrice = "R$ " .. H.comma(price), true, price
		else
			priceText, countInTotal = "Price unavailable", false
		end
		cached = {
			name = tostring(info.Name or fallbackName or ("Unknown item #" .. tostring(id))),
			priceText = priceText, countInTotal = countInTotal, totalPrice = totalPrice,
		}
	end
	subItemMetadataCache[cacheKey] = cached
	return cached
end

H.updateBundleContentRow = function(item)
	local rowData = bundleContentRows[item]
	if not rowData then return end
	rowData.nameLabel.Text = item.name or "Loading item details..."
	if rowData.detailData then rowData.detailData.name = item.name end
	local typeText = item.includedAnimationCount and ("Animation Pack · " .. tostring(item.includedAnimationCount) .. (item.includedAnimationCount == 1 and " clip" or " clips"))
		or (item.animationRole and H.prettyType(item.animationRole) or H.prettyType(item.assetType or "Item"))
	if item.priceText then typeText = typeText .. " · " .. item.priceText end
	rowData.typeLabel.Text = typeText
	rowData.typeLabel.TextColor3 = item.countInTotal and C.success or C.sub
	if item.bundle then
		rowData.thumb.Image = "rbxthumb://type=BundleThumbnail&id=" .. tostring(item.id) .. "&w=150&h=150"
	end
	if rowData.equippedBadge then
		rowData.equippedBadge.Visible = item.bundle
			and H.isBundleFullyEquipped(item.id) or (not item.bundle and equippedIds[item.id] == true)
	end
end

H.refreshBundleContentBadges = function()
	for item, rowData in pairs(bundleContentRows) do
		if rowData.equippedBadge then
			rowData.equippedBadge.Visible = item.bundle
				and H.isBundleFullyEquipped(item.id) or (not item.bundle and equippedIds[item.id] == true)
		end
	end
end

H.discoverOutfitBundles = function(entries, detailToken)
	local assets, wantedIds, sortedIds, assetTypes = {}, {}, {}, {}
	for _, item in ipairs(entries) do
		local id = tonumber(item.Id or item.id)
		if id and id > 0 and not wantedIds[id] then
			wantedIds[id] = true
			assetTypes[id] = tostring(item.AssetType or ""):gsub("^Enum%.AvatarAssetType%.", ""):gsub("^AvatarAssetType%.", "")
			table.insert(assets, item)
			table.insert(sortedIds, id)
		end
	end
	table.sort(sortedIds)
	if #assets < 1 then return entries end
	local keyParts = {}
	for _, id in ipairs(sortedIds) do table.insert(keyParts, tostring(id)) end
	local cacheKey = table.concat(keyParts, ",")
	local cached = outfitBundleMergeCache[cacheKey]
	if cached then
		local result = {}
		for _, item in ipairs(cached) do table.insert(result, table.clone(item)) end
		return result
	end

	local function isCurrent()
		return detailToken == detailLoadToken and detailOverlay.Visible
	end
	local candidatesById = {}
	local nextAssetIndex, searchFinished = 0, 0
	local searchWorkerCount = math.min(4, #assets)
	local function searchWorker()
		while isCurrent() do
			nextAssetIndex += 1
			local index = nextAssetIndex
			if index > #assets then break end
			local assetId = tonumber(assets[index].Id or assets[index].id)
			local pagesOk, pages = pcall(H.callAES, "GetBundlesByAssetId", assetId, 100)
			if pagesOk and pages then
				local pageOk, page = pcall(function() return pages:GetCurrentPage() end)
				if pageOk and type(page) == "table" then
					for _, bundle in ipairs(page) do
						local bundleId = tonumber(bundle.Id or bundle.id)
						if bundleId and bundleId > 0 then
							local candidate = candidatesById[bundleId]
							if not candidate then
								candidate = {
									id = bundleId,
									name = bundle.Name or bundle.name,
									bundleType = bundle.BundleType or bundle.bundleType,
									searchDetails = bundle,
									sourceIds = {},
								}
								candidatesById[bundleId] = candidate
							elseif not candidate.searchDetails or not candidate.searchDetails.BundledItems then
								candidate.searchDetails = bundle
							end
							candidate.sourceIds[assetId] = true
						end
					end
				end
			end
		end
		searchFinished += 1
	end
	for _ = 1, searchWorkerCount do task.spawn(searchWorker) end
	while searchFinished < searchWorkerCount and isCurrent() do task.wait() end
	if not isCurrent() then return entries end

	local candidates = {}
	for _, candidate in pairs(candidatesById) do
		local sourceCount = 0
		for _ in pairs(candidate.sourceIds) do sourceCount += 1 end
		if sourceCount >= 1 then
			candidate.sourceCount = sourceCount
			table.insert(candidates, candidate)
		end
	end
	table.sort(candidates, function(a, b)
		if a.sourceCount ~= b.sourceCount then return a.sourceCount > b.sourceCount end
		return a.id < b.id
	end)
	while #candidates > 64 do table.remove(candidates) end
	if #candidates == 0 then
		return entries
	end

	local resolved, nextCandidateIndex, resolveFinished = {}, 0, 0
	local resolveWorkerCount = math.min(4, #candidates)
	local function normalizeType(value)
		local name = tostring(value or "")
		local enumName = name:match("^Enum%.BundleType%.([%w_]+)$") or name:match("^BundleType%.([%w_]+)$")
		return enumName or name
	end
	local function resolveWorker()
		while isCurrent() do
			nextCandidateIndex += 1
			local index = nextCandidateIndex
			if index > #candidates then break end
			local candidate = candidates[index]
			local searchDetails = type(candidate.searchDetails) == "table" and candidate.searchDetails or {}
			local detailsOk, fetchedDetails, productOk, productInfo
			local completed = 0
			task.spawn(function()
				detailsOk, fetchedDetails = pcall(H.callAES, "GetItemDetails", candidate.id, Enum.AvatarItemType.Bundle)
				completed += 1
			end)
			task.spawn(function()
				local callOk, lookupOk, lookupValue = pcall(getBundleProductInfo, candidate.id)
				productOk = callOk and lookupOk == true
				productInfo = callOk and lookupValue or nil
				completed += 1
			end)
			while completed < 2 do task.wait() end
			local details = {}
			for key, value in pairs(searchDetails) do details[key] = value end
			if detailsOk and type(fetchedDetails) == "table" then
				for key, value in pairs(fetchedDetails) do
					if value ~= nil then details[key] = value end
				end
			end
			if next(details) ~= nil then
				local contents = details.BundledItems or details.Items
				local covered = {}
				if type(contents) == "table" then
					for _, entry in ipairs(contents) do
						local nested = type(entry.Item) == "table" and entry.Item or (type(entry.Asset) == "table" and entry.Asset or entry)
						local itemType = tostring(entry.Type or entry.ItemType or nested.Type or "Asset"):lower()
						local itemId = tonumber(entry.Id or entry.AssetId or nested.Id or nested.AssetId)
						if itemId and wantedIds[itemId] and not itemType:find("bundle", 1, true) then covered[itemId] = true end
					end
				end
				for assetId in pairs(candidate.sourceIds) do
					if wantedIds[assetId] then covered[assetId] = true end
				end
				local count = 0
				for _ in pairs(covered) do count += 1 end
				if count >= 1 then
					local bundleType = normalizeType(details.BundleType or candidate.bundleType or details.Name or candidate.name)
					local lowerType = bundleType:lower()
					local displayType = lowerType:find("animation", 1, true) and "Animation Pack"
						or (lowerType:find("body", 1, true) and "Body Bundle")
						or (lowerType:find("shoe", 1, true) and "Shoe Bundle")
						or (lowerType:find("dynamic", 1, true) and "Dynamic Head Bundle") or "Bundle"
					local bodyTypes = { Head = true, DynamicHead = true, Torso = true, LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true }
					local expectedCategory, typeAllowed = nil, true
					for assetId in pairs(covered) do
						local assetType = assetTypes[assetId] or ""
						local category
						if assetType:find("Animation", 1, true) then category = "Animation"
						elseif bodyTypes[assetType] then category = "Body"
						elseif assetType == "LeftShoeAccessory" or assetType == "RightShoeAccessory" then category = "Shoes"
						else category = assetType end
						if not expectedCategory then expectedCategory = category
						elseif expectedCategory ~= category then typeAllowed = false break end
						if displayType == "Animation Pack" and category ~= "Animation" then typeAllowed = false break end
						if (displayType == "Body Bundle" or displayType == "Dynamic Head Bundle") and category ~= "Body" then typeAllowed = false break end
						if displayType == "Shoe Bundle" and category ~= "Shoes" then typeAllowed = false break end
					end
					if displayType == "Bundle" then
						if expectedCategory == "Animation" then displayType = "Animation Pack"
						elseif expectedCategory == "Body" then displayType = "Body Bundle"
						elseif expectedCategory == "Shoes" then displayType = "Shoe Bundle" end
					end
					local minimumGroupCount = displayType == "Bundle" and 2 or 1
					productInfo = productOk and type(productInfo) == "table" and productInfo or {}
					local detailPrice = tonumber(details.PriceInRobux or details.Price)
					local productPrice = tonumber(productInfo.PriceInRobux or productInfo.Price)
					local bundlePrice = (detailPrice and detailPrice > 0 and detailPrice)
						or (productPrice and productPrice > 0 and productPrice)
						or detailPrice or productPrice
					local detailStatus = tostring(details.PriceStatus or ""):lower()
					local productStatus = tostring(productInfo.PriceStatus or ""):lower()
					local priceStatus = detailStatus ~= "" and detailStatus or productStatus
					local explicitlyFree = details.IsFree == true or productInfo.IsFree == true or detailStatus == "free" or productStatus == "free"
					local isForSale = productInfo.IsForSale
					if isForSale == nil then isForSale = details.IsForSale end
					local isPurchasable = details.IsPurchasable
					if isPurchasable == nil then isPurchasable = productInfo.IsPurchasable end
					if bundlePrice == 0 and (isForSale == true or isPurchasable == true) then explicitlyFree = true end
					local hasPositivePrice = bundlePrice ~= nil and bundlePrice > 0
					local explicitlyOffSale = not explicitlyFree and (detailStatus == "off sale" or detailStatus == "offsale" or productStatus == "off sale" or productStatus == "offsale")
					local unavailable = explicitlyOffSale or (not hasPositivePrice and not explicitlyFree and (isForSale == false or isPurchasable == false))
					local verifiedPrice = hasPositivePrice or explicitlyFree
					if typeAllowed and count >= minimumGroupCount and verifiedPrice and not unavailable then
						table.insert(resolved, {
							id = candidate.id,
							name = tostring(details.Name or candidate.name or (displayType .. " #" .. tostring(candidate.id))),
							displayType = displayType,
							covered = covered,
							count = count,
							price = bundlePrice,
							priceStatus = priceStatus,
							isFree = explicitlyFree,
							isForSale = isForSale,
							isPurchasable = isPurchasable,
						})
					end
				end
			end
		end
		resolveFinished += 1
	end
	for _ = 1, resolveWorkerCount do task.spawn(resolveWorker) end
	while resolveFinished < resolveWorkerCount and isCurrent() do task.wait() end
	if not isCurrent() then return entries end

	table.sort(resolved, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.id < b.id
	end)
	local merged, usedIds = {}, {}
	for _, bundle in ipairs(resolved) do
		local available = {}
		for assetId in pairs(bundle.covered) do
			if not usedIds[assetId] then table.insert(available, assetId) end
		end
		if #available >= (bundle.displayType == "Bundle" and 2 or 1) then
			for _, assetId in ipairs(available) do usedIds[assetId] = true end
			table.insert(merged, {
				Id = bundle.id,
				Type = "Bundle",
				Bundle = true,
				Name = bundle.name,
				AssetType = bundle.displayType,
				IncludedAnimationCount = bundle.displayType == "Animation Pack" and #available or nil,
				bundlePrice = bundle.price,
				bundlePriceStatus = bundle.priceStatus,
				bundleIsFree = bundle.isFree,
				bundleIsForSale = bundle.isForSale,
				bundleIsPurchasable = bundle.isPurchasable,
			})
		end
	end
	for _, item in ipairs(entries) do
		local id = tonumber(item.Id or item.id)
		if not id or not usedIds[id] then table.insert(merged, item) end
	end
	if #merged > 0 then
		table.sort(merged, function(a, b)
			local typeA = tostring(a.AssetType or "")
			local typeB = tostring(b.AssetType or "")
			if typeA ~= typeB then return typeA < typeB end
			return (tonumber(a.Id or a.id) or 0) < (tonumber(b.Id or b.id) or 0)
		end)
		local cacheCopy = {}
		for _, item in ipairs(merged) do table.insert(cacheCopy, table.clone(item)) end
		outfitBundleMergeCache[cacheKey] = cacheCopy
		return merged
	end
	return entries
end

H.enrichBundleContents = function(generation)
	task.spawn(function()
		local total, unavailableCount = 0, 0
		local itemCount = #bundleContentEntries
		local nextIndex = 0
		local workerCount = math.min(4, itemCount)
		local finishedWorkers = 0

		local function finishIfReady()
			if finishedWorkers ~= workerCount or not bundleContentIsOutfit
				or generation ~= bundleContentGeneration
				or bundleContentDetailToken ~= detailLoadToken or not detailOverlay.Visible then
				return
			end
			local outfitId = bundleContentOutfitId or 0
			detailInfo.RichText = true
			local totalText = "R$ " .. H.comma(total)
			local note = unavailableCount > 0
				and ("\n" .. tostring(unavailableCount) .. " entries excluded: price unavailable or off sale.") or ""
			detailInfo.Text = "Outfit ID: " .. tostring(outfitId)
				.. "\nItems: " .. tostring(itemCount)
				.. "\n<font color=\"rgb(72,190,105)\">Estimated total: " .. totalText .. "</font>" .. note
		end

		local function worker()
			while generation == bundleContentGeneration and detailOverlay.Visible do
				nextIndex += 1
				local index = nextIndex
				if index > itemCount then break end
				local item = bundleContentEntries[index]
				local metadata = getSubItemMetadata(item)
				if generation ~= bundleContentGeneration or not detailOverlay.Visible then return end
				item.name = metadata.name
				item.priceText = metadata.priceText
				item.countInTotal = metadata.countInTotal
				item.totalPrice = metadata.totalPrice
				if metadata.countInTotal then
					total += tonumber(metadata.totalPrice) or 0
				else
					unavailableCount += 1
				end
				updateBundleContentRow(item)
			end
			finishedWorkers += 1
			finishIfReady()
		end

		for _ = 1, workerCount do task.spawn(worker) end
		if workerCount == 0 then
			finishedWorkers = 0
			finishIfReady()
		end
	end)
end

H.renderMoreBundleContents = function()
	if bundleContentRendering then return 0 end
	local firstIndex = bundleContentRendered + 1
	local lastIndex = math.min(#bundleContentEntries, bundleContentRendered + BUNDLE_CONTENT_BATCH_SIZE)
	if firstIndex > lastIndex then return 0 end
	bundleContentRendering = true
	local generation = bundleContentGeneration
	for itemOrder = firstIndex, lastIndex do
		local item = bundleContentEntries[itemOrder]
		local row = H.new("TextButton", {
			Name = "BundleAsset_" .. tostring(item.id), Text = "", BackgroundColor3 = C.card,
			BorderSizePixel = 0, LayoutOrder = itemOrder, ZIndex = 32,
		}, bundleItemsScroll)
		designSizes[row] = Vector2.new(280, 112)
		H.round(row, 8)
		local thumbType = item.bundle and "BundleThumbnail" or "Asset"
		local thumbSize = item.bundle and "150" or "420"
		local thumb = H.new("ImageLabel", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(5, 5),
			Size = UDim2.fromOffset(92, 92), ScaleType = Enum.ScaleType.Fit,
			Image = "rbxthumb://type=" .. thumbType .. "&id=" .. string.format("%d", item.id) .. "&w=" .. thumbSize .. "&h=" .. thumbSize, ZIndex = 33,
		}, row)
		H.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, thumb)
		local nameLabel = H.label(row, item.name or "Loading item details...", 106, 8, 166, 52, 16, C.text, FB)
		nameLabel.ZIndex = 33
		nameLabel.TextWrapped = true
		nameLabel.TextTruncate = Enum.TextTruncate.None
		local typeText = item.includedAnimationCount and ("Animation Pack · " .. tostring(item.includedAnimationCount) .. (item.includedAnimationCount == 1 and " clip" or " clips"))
			or H.prettyType(item.animationRole or item.assetType or "Item")
		if item.priceText then typeText = typeText .. " · " .. item.priceText end
		local typeLabel = H.label(row, typeText, 106, 66, 166, 38, 14, item.countInTotal and C.success or C.sub, FB)
		typeLabel.ZIndex = 33
		typeLabel.TextScaled = true
		local equippedBadge = H.new("TextLabel", {
			Name = "EquippedBadge", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(68, 18),
			BackgroundColor3 = C.accent, Text = "EQUIPPED", TextColor3 = C.text,
			Font = FB, TextSize = 12, Visible = false, ZIndex = 35,
		}, row)
		H.round(equippedBadge, 6)
		local detailData = {
			id = item.id, name = item.name, typeName = item.animationRole or item.assetType,
			emote = item.animationRole == "EmoteAnimation", auto = true, bundle = item.bundle == true,
		}
		bundleContentRows[item] = {
			row = row, thumb = thumb, nameLabel = nameLabel, typeLabel = typeLabel,
			equippedBadge = equippedBadge, detailData = detailData,
		}
		local consumeBundleRowLongPress = H.bindLongPressDetails(row, function()
			H.openItemDetails(detailData)
		end)
		row.Activated:Connect(function()
			if consumeBundleRowLongPress() then return end
			if item.animationRole == "EmoteAnimation" then
				toggleEmotePreview({ id = item.id, name = item.name, typeName = item.animationRole, emote = true })
			elseif item.animationRole then
				detailOverlay.Visible = false
				wearItem(detailData)
			else
				H.openItemDetails(detailData)
			end
		end)
		row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then H.openItemDetails(detailData) end
		end)
		H.updateBundleContentRow(item)
	end
	bundleContentRendered = lastIndex
	updateBundleContentsCanvas()
	task.defer(function()
		if generation ~= bundleContentGeneration then return end
		updateBundleContentsCanvas()
		bundleContentRendering = false
	end)
	return lastIndex - firstIndex + 1
end

H.showBundleContents = function(items, animationBundle, bodyBundle, dynamicHeadOnly, isOutfitContents, detailToken)
	clearBundleContents()
	bundleContentIsOutfit = isOutfitContents == true
	bundleContentOutfitId = bundleContentIsOutfit and currentDetailData and currentDetailData.id or nil
	bundleContentDetailToken = detailToken
	for _, entry in ipairs(type(items) == "table" and items or {}) do
		local nested = type(entry.Item) == "table" and entry.Item or (type(entry.Asset) == "table" and entry.Asset or entry)
		local id = tonumber(entry.Id or entry.AssetId or nested.Id or nested.AssetId)
		local entryType = tostring(entry.Type or entry.ItemType or (entry.AssetId and "Asset") or nested.Type or "Asset")
		local isBundleEntry = entry.Bundle == true or entry.IsBundle == true or entryType:lower():find("bundle", 1, true) ~= nil
		local assetType = tostring(entry.AssetType or entry.AssetTypeName or nested.AssetType or nested.AssetTypeName or (isBundleEntry and "Animation Pack" or "Item"))
		local normalizedAssetType = assetType:match("^Enum%.AvatarAssetType%.([%w_]+)$") or assetType:match("^AvatarAssetType%.([%w_]+)$")
		if normalizedAssetType then assetType = normalizedAssetType end
		local bodyTypeAllowed = not bodyBundle or BODY_BUNDLE_CONTENT_TYPES[assetType] == true
		local dynamicHeadTypeAllowed = not dynamicHeadOnly or assetType == "DynamicHead"
		if id and id > 0 and (isBundleEntry or entryType:lower():find("asset", 1, true))
			and bodyTypeAllowed and dynamicHeadTypeAllowed and assetType ~= "MoodAnimation" then
			local itemName = entry.Name or nested.Name
			if type(itemName) ~= "string" or itemName == "" then itemName = "Loading item details..." end
			local animationRole
			local source = (assetType .. " " .. entryType .. " " .. itemName):lower()
			if not isBundleEntry and (animationBundle or source:find("animation", 1, true)) then
				if source:find("idle", 1, true) then animationRole = "IdleAnimation"
				elseif source:find("walk", 1, true) then animationRole = "WalkAnimation"
				elseif source:find("run", 1, true) then animationRole = "RunAnimation"
				elseif source:find("jump", 1, true) then animationRole = "JumpAnimation"
				elseif source:find("fall", 1, true) then animationRole = "FallAnimation"
				elseif source:find("climb", 1, true) then animationRole = "ClimbAnimation"
				elseif source:find("swim", 1, true) then animationRole = "SwimAnimation"
				else animationRole = "EmoteAnimation" end
			end
			table.insert(bundleContentEntries, {
				id = id, name = itemName, assetType = assetType, animationRole = animationRole,
				bundle = isBundleEntry, includedAnimationCount = tonumber(entry.IncludedAnimationCount),
				bundlePrice = tonumber(entry.bundlePrice),
				bundlePriceStatus = entry.bundlePriceStatus,
				bundleIsFree = entry.bundleIsFree,
				bundleIsForSale = entry.bundleIsForSale,
				bundleIsPurchasable = entry.bundleIsPurchasable,
			})
			if isBundleEntry then
				H.registerAnimationPack({ id = id, name = itemName, bundleType = assetType, bundle = true })
			end
		end
	end
	if #bundleContentEntries == 0 then
		local empty = H.label(bundleItemsScroll, "Roblox did not return individual assets for this bundle.", 10, 10, 850, 32, 16, C.sub, FB)
		empty.ZIndex = 33
		bundleItemsScroll.CanvasSize = UDim2.new(0, 0, 0, bundleItemsScroll.AbsoluteSize.Y)
		return
	end

	H.renderMoreBundleContents()
	bundleItemsScroll.CanvasPosition = Vector2.zero
	updateBundleContentsCanvas()
	H.enrichBundleContents(bundleContentGeneration)
end

bundleItemsScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()

	if not detailOverlay.Visible or not bundleItemsScroll.Visible or bundleContentRendering then
		return
	end
	if bundleContentRendered >= #bundleContentEntries then return end
	local viewportHeight = bundleItemsScroll.AbsoluteSize.Y
	local canvasHeight = bundleItemsScroll.CanvasSize.Y.Offset
	local maxScroll = canvasHeight - viewportHeight
	if maxScroll <= 8 then return end
	local threshold = math.min(math.max(50, viewportHeight * 0.18), maxScroll * 0.65)
	local visibleBottom = bundleItemsScroll.CanvasPosition.Y + viewportHeight
	if visibleBottom >= canvasHeight - threshold then
		H.renderMoreBundleContents()
	end
end)

H.parseCatalogLink = function(raw)
	local value = H.trim(raw)
	local bundleId = value:match("/bundles/(%d+)")
	local assetId = value:match("/catalog/(%d+)") or value:match("/library/(%d+)")
		or value:match("/asset/(%d+)") or value:match("[?&]id=(%d+)")
	local numericId = tonumber(value:match("^(%d+)$"))
	if bundleId then return tonumber(bundleId), true end
	if assetId then return tonumber(assetId), false end
	if numericId then return numericId, nil end
	return nil, nil
end

H.openItemDetails = function(data)
	if type(data) ~= "table" or not tonumber(data.id) then return end
	detailLoadToken += 1
	local token = detailLoadToken
	currentDetailData = data
	local id = tonumber(data.id)
	local thumbType = data.bundle and "BundleThumbnail" or (data.outfit and "Outfit" or "Asset")
	detailImage.Image = "rbxthumb://type=" .. thumbType .. "&id=" .. string.format("%d", id) .. "&w=420&h=420"
	detailTitle.Text = tostring(data.name or ("Item " .. tostring(id)))
	detailType.Text = data.background and "AVATAR BACKGROUND" or (data.bundle and "BUNDLE" or (data.outfit and "OUTFIT" or H.prettyType(data.typeName or "Catalog item")):upper())
	detailInfo.Text = data.outfit and ("Loading saved outfit contents...\nOutfit ID: " .. tostring(id)) or ("Loading creator, price and item information...\nAsset ID: " .. tostring(id))
	detailDescription.Text = ""
	detailDescription.Visible = true
	bundleItemsTitle.Visible = false
	bundleItemsScroll.Visible = false
	clearBundleContents()
	detailWearBtn.Text = data.background and "Preview background" or (isEmotePreviewItem(data) and "Play / Stop") or (data.bundle and "Wear bundle" or "Wear item")
	detailBuyBtn.Visible = not data.outfit
	detailOverlay.Visible = true

	task.spawn(function()
		if data.outfit then
			local outfitOk, description = pcall(function() return Players:GetHumanoidDescriptionFromOutfitIdAsync(id) end)
			if not outfitOk or not description then
				outfitOk, description = pcall(function() return Players:GetHumanoidDescriptionFromOutfitId(id) end)
			end
			if token ~= detailLoadToken or not detailOverlay.Visible then
				if description then pcall(function() description:Destroy() end) end
				return
			end
			if not outfitOk or not description then
				detailInfo.Text = "Roblox could not load this saved outfit's description.\nOutfit ID: " .. tostring(id)
				detailDescription.Text = "The outfit may no longer be available."
				return
			end
			local entries, seen = {}, {}
			local function addOutfitAsset(assetId, assetType)
				local numericId = tonumber(assetId)
				if numericId and numericId > 0 and numericId % 1 == 0 and not seen[numericId] then
					seen[numericId] = true

					table.insert(entries, { Id = numericId, Type = "Asset", AssetType = assetType })
				end
			end
			local properties = {
				{ "GraphicTShirt", "TShirt" }, { "Shirt", "Shirt" }, { "Pants", "Pants" },
				{ "Face", "Face" }, { "Head", "Head" }, { "Torso", "Torso" },
				{ "RightArm", "RightArm" }, { "LeftArm", "LeftArm" }, { "RightLeg", "RightLeg" }, { "LeftLeg", "LeftLeg" },
				{ "ClimbAnimation", "ClimbAnimation" }, { "FallAnimation", "FallAnimation" },
				{ "IdleAnimation", "IdleAnimation" }, { "JumpAnimation", "JumpAnimation" },
				{ "RunAnimation", "RunAnimation" }, { "SwimAnimation", "SwimAnimation" },
				{ "WalkAnimation", "WalkAnimation" }, { "MoodAnimation", "MoodAnimation" },
			}
			for _, property in ipairs(properties) do
				local propertyOk, value = pcall(function() return description[property[1]] end)
				if propertyOk then addOutfitAsset(value, property[2]) end
			end
			local accessoriesOk, accessories = pcall(function() return description:GetAccessories(true) end)
			if accessoriesOk and type(accessories) == "table" then
				local names = {
					Hat = "Hat", Hair = "HairAccessory", Face = "FaceAccessory", Neck = "NeckAccessory",
					Shoulder = "ShoulderAccessory",
					Front = "FrontAccessory", Back = "BackAccessory", Waist = "WaistAccessory",
					Eyebrow = "EyebrowAccessory", Eyelash = "EyelashAccessory",
					FaceMakeup = "FaceMakeup", LipMakeup = "LipMakeup", EyeMakeup = "EyeMakeup",
					TShirt = "TShirtAccessory", Shirt = "ShirtAccessory", Pants = "PantsAccessory",
					Jacket = "JacketAccessory", Sweater = "SweaterAccessory", Shorts = "ShortsAccessory",
					LeftShoe = "LeftShoeAccessory", RightShoe = "RightShoeAccessory", DressSkirt = "DressSkirtAccessory",
				}
				for _, accessory in ipairs(accessories) do
					local name = tostring(accessory.AccessoryType or ""):gsub("^Enum%.AccessoryType%.", "")
					addOutfitAsset(accessory.AssetId, names[name] or "Accessory")
				end
			end
			local emotesOk, emotes = pcall(function() return description:GetEquippedEmotes() end)
			if emotesOk and type(emotes) == "table" then
				for _, emote in pairs(emotes) do
					if type(emote) == "table" then addOutfitAsset(emote.Id or emote.AssetId, "EmoteAnimation")
					elseif type(emote) == "number" then addOutfitAsset(emote, "EmoteAnimation") end
				end
			end
			pcall(function() description:Destroy() end)
			table.sort(entries, function(a, b)
				if a.AssetType == b.AssetType then return a.Id < b.Id end
				return tostring(a.AssetType) < tostring(b.AssetType)
			end)
			detailTitle.Text = tostring(data.name or "Saved outfit")
			detailInfo.RichText = false
			detailInfo.Text = "Outfit ID: " .. tostring(id)
				.. "\nItems: " .. tostring(#entries) .. "\nCalculating estimated total..."
			detailDescription.Visible = false
			bundleItemsTitle.Text = "OUTFIT CONTENTS"
			bundleItemsTitle.Visible = true
			bundleItemsScroll.Visible = true
			local mergedEntries = H.discoverOutfitBundles(entries, token)
			if token ~= detailLoadToken or not detailOverlay.Visible then return end
			H.showBundleContents(mergedEntries, false, false, false, true, token)
			return
		end
		local ok, info
		local bundleProductInfo
		local bundleProductInfoAvailable = false
		if data.bundle then
			local detailsOk, bundleDetails = pcall(H.callAES, "GetItemDetails", id, Enum.AvatarItemType.Bundle)
			local productOk, fetchedBundleProductInfo = getBundleProductInfo(id)
			bundleProductInfo = fetchedBundleProductInfo
			bundleProductInfoAvailable = productOk and type(fetchedBundleProductInfo) == "table"
			if detailsOk and type(bundleDetails) == "table" then
				info = bundleDetails
				ok = true
			elseif bundleProductInfoAvailable then
				info = bundleProductInfo
				ok = true
			else
				ok = false
				info = bundleDetails or bundleProductInfo
			end
			if bundleProductInfoAvailable then

				local productPrice = tonumber(bundleProductInfo.PriceInRobux or bundleProductInfo.Price)
				if productPrice ~= nil then
					info.PriceInRobux = productPrice
					info.Price = productPrice
				end
				if productPrice and productPrice > 0 then

					info.IsForSale = true
					info.PriceStatus = nil
				elseif bundleProductInfo.IsForSale ~= nil then
					info.IsForSale = bundleProductInfo.IsForSale
				end
				if bundleProductInfo.PriceStatus ~= nil then info.PriceStatus = bundleProductInfo.PriceStatus end
				if info.Name == nil then info.Name = bundleProductInfo.Name end
				if info.Creator == nil then info.Creator = bundleProductInfo.Creator end
				if info.CreatorName == nil then info.CreatorName = bundleProductInfo.CreatorName end
			end
		else

			local catalogOk, catalogInfo = pcall(H.callAES, "GetItemDetails", id, Enum.AvatarItemType.Asset)
			local marketOk, marketInfo = pcall(H.getProductInfo, id, Enum.InfoType.Asset)
			if catalogOk and type(catalogInfo) == "table" then
				info = catalogInfo
				if marketOk and type(marketInfo) == "table" then
					for key, value in pairs(marketInfo) do
						if info[key] == nil then info[key] = value end
					end
					local liveAssetPrice = tonumber(marketInfo.PriceInRobux or marketInfo.Price)
					if marketInfo.IsForSale == true and liveAssetPrice and liveAssetPrice > 0 then
						info.PriceInRobux = liveAssetPrice
						info.Price = liveAssetPrice
						info.IsForSale = true
						info.PriceStatus = nil
					elseif marketInfo.IsForSale == true and (liveAssetPrice == 0 or marketInfo.IsFree == true) then
						info.PriceInRobux = 0
						info.Price = 0
						info.IsForSale = true
						info.PriceStatus = "Free"
					end
				end
				ok = true
			else
				ok, info = marketOk, marketInfo
			end
		end
		if token ~= detailLoadToken or not detailOverlay.Visible then return end
		if not ok or type(info) ~= "table" then
			detailInfo.Text = "Roblox could not return full item details.\nAsset ID: " .. tostring(id)
			detailDescription.Text = "You can still close this panel and continue browsing."
			return
		end
		if not data.bundle and (tonumber(info.AssetTypeId) == 92 or H.assetTypeName(info.AssetType) == "AvatarBackground") then
			data.background = true
			data.typeName = "AvatarBackground"
			detailType.Text = "AVATAR BACKGROUND"
			detailWearBtn.Text = "Preview background"
		end
		local creator = "Unknown creator"
		if type(info.Creator) == "table" then creator = tostring(info.Creator.Name or info.Creator.CreatorName or creator)
		elseif info.CreatorName then creator = tostring(info.CreatorName) end
		local collectibles = type(info.CollectiblesItemDetails) == "table" and info.CollectiblesItemDetails or {}
		local resalePrice = tonumber(info.LowestResalePrice) or tonumber(info.LowestPrice)
		if not resalePrice or resalePrice <= 0 then
			resalePrice = tonumber(collectibles.CollectibleLowestResalePrice)
		end
		local hasResellers = info.HasResellers
		if hasResellers == nil and resalePrice ~= nil and resalePrice > 0 then hasResellers = true end
		local restrictions = type(info.ItemRestrictions) == "table" and info.ItemRestrictions or {}
		local priceStatus = tostring(info.PriceStatus or "")
		local limited = not data.bundle and (info.IsLimited == true or info.IsLimitedUnique == true or hasResellers or priceStatus == "No Resellers")
		for _, restriction in ipairs(restrictions) do
			if restriction == "Collectible" or restriction == "Limited" or restriction == "LimitedUnique" then
				limited = true
				break
			end
		end
		local price = tonumber(info.PriceInRobux or info.Price)
		local priceText
		if data.bundle then
			local liveBundlePrice = bundleProductInfoAvailable
				and tonumber(bundleProductInfo.PriceInRobux or bundleProductInfo.Price) or price
			local liveBundleStatus = bundleProductInfoAvailable
				and tostring(bundleProductInfo.PriceStatus or ""):lower() or ""
			if bundleProductInfoAvailable then
				if bundleProductInfo.IsForSale == false or liveBundleStatus == "off sale" or info.IsForSale == false then
					priceText = "Off sale"
				elseif liveBundlePrice and liveBundlePrice > 0 then
					priceText = "R$ " .. H.comma(liveBundlePrice)
				elseif liveBundleStatus == "free" or bundleProductInfo.IsFree == true
					or (liveBundlePrice == 0 and bundleProductInfo.IsForSale ~= false) then
					priceText = "Free"
				else
					priceText = "Price unavailable"
				end
			elseif info.IsForSale == false or info.IsPurchasable == false or tostring(info.PriceStatus or ""):lower() == "off sale" then
				priceText = "Off sale"
			elseif price and price > 0 then
				priceText = "R$ " .. H.comma(price)
			elseif info.IsForSale ~= false and (info.PriceStatus == "Free" or info.IsFree == true or price == 0) then
				priceText = "Free"
			else
				priceText = "Price unavailable"
			end
		elseif hasResellers and resalePrice and resalePrice > 0 then
			priceText = "R$ " .. H.comma(resalePrice) .. " (lowest resale)"
		elseif limited and (info.HasResellers == false or priceStatus == "No Resellers") then
			priceText = "Limited · no current resellers"
		elseif price and price > 0 then
			priceText = "R$ " .. H.comma(price) .. (limited and " (original price)" or "")
		elseif info.PriceStatus == "Free" or (price == 0 and info.IsForSale == true) then
			priceText = "Free"
		else
			priceText = limited and "Limited · off sale" or "Off sale"
		end
		detailTitle.Text = tostring(info.Name or data.name or ("Item " .. tostring(id)))
		local safeCreator = creator:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		local safePrice = priceText:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		detailInfo.RichText = true
		detailInfo.Text = "Creator: " .. safeCreator .. "\n<font color=\"rgb(72,190,105)\">Price: " .. safePrice .. "</font>\nID: " .. tostring(id)
		detailInfo.TextColor3 = C.text
		if info.AssetType then detailInfo.Text ..= "\nType: " .. tostring(info.AssetType)
		elseif info.AssetTypeId then detailInfo.Text ..= "\nAsset type ID: " .. tostring(info.AssetTypeId)
		elseif info.BundleType then detailInfo.Text ..= "\nBundle type: " .. tostring(info.BundleType) end
		if data.bundle then
			local bundleTypeName = tostring(info.BundleType or data.bundleType or "")
			bundleTypeName = bundleTypeName:gsub("^Enum%.BundleType%.", "")
			bundleTypeName = bundleTypeName:match("([%w_]+)$") or bundleTypeName
			local animationBundle = bundleTypeName:lower():find("animation", 1, true) ~= nil or tostring(data.name or ""):lower():find("animation", 1, true) ~= nil
			local dynamicHeadBundle = bundleTypeName == "DynamicHeadAvatar" or bundleTypeName == "DynamicHead" or bundleTypeName == "DynamicHeadBundle"
			local bodyBundle = data.bodyBundle == true or bundleTypeName == "BodyParts" or dynamicHeadBundle
			detailDescription.Visible = false
			bundleItemsTitle.Text = animationBundle and "ANIMATION PACK CONTENTS"
				or (dynamicHeadBundle and "DYNAMIC HEAD ONLY · FACE ITEMS EXCLUDED"
					or (bodyBundle and "CHARACTER BODY PARTS · FACE ITEMS EXCLUDED" or "ITEMS INCLUDED IN THIS BUNDLE"))
			bundleItemsTitle.Visible = true
			bundleItemsScroll.Visible = true
			H.showBundleContents(info.BundledItems or info.Items, animationBundle, bodyBundle, dynamicHeadBundle, false, token)
		else
			detailDescription.Visible = true
			detailDescription.Text = tostring(info.Description or info.DescriptionText or "No description was provided.")
		end
	end)
end
H.previewCatalogLink = function()
	local id, bundleFlag = H.parseCatalogLink(urlBox.Text)
	if not id or id <= 0 or id >= 1e13 then
		setStatus("Enter a valid Roblox catalog/bundle URL or numeric item ID.")
		return
	end
	H.openItemDetails({ id = id, name = "Catalog item " .. tostring(id), bundle = bundleFlag == true, auto = bundleFlag == nil, typeName = nil })
end
urlBox.FocusLost:Connect(function()
	if H.trim(urlBox.Text) ~= "" then H.previewCatalogLink() end
end)

H.onUnequipRequested = function(assetId, typeName)
	local numericId = tonumber(assetId)
	if not numericId or numericId <= 0 or numericId % 1 ~= 0 or numericId > 9007199254740991 then
		setStatus("Cannot remove this item: invalid asset ID.")
		return
	end
	local requestId = beginBusy("Removing " .. H.prettyType(typeName) .. "...")
	if requestId then remote:FireServer("Unequip", numericId, nil, requestId) end
end
H.requestUnequipAll = function()
	local requestId = beginBusy("Unequipping all avatar items...")
	if requestId then remote:FireServer("UnequipAll", nil, nil, requestId) end
end
unequipAllBtn.Activated:Connect(H.requestUnequipAll)
detailCloseBtn.Activated:Connect(function()
	detailLoadToken += 1
	detailOverlay.Visible = false
end)
detailWearBtn.Activated:Connect(function()
	local data = currentDetailData
	if not data then return end
	if data.background then
		setViewportBackground(data.id)
		setStatus("Previewing background: " .. tostring(data.name))
		detailOverlay.Visible = false
	elseif isEmotePreviewItem(data) then
		detailOverlay.Visible = false
		toggleEmotePreview(data)
	else
		detailOverlay.Visible = false
		wearItem(data)
	end
end)
detailBuyBtn.Activated:Connect(function()
	local data = currentDetailData
	if not data then return end
	local ok, err = pcall(function()
		if data.bundle then MarketplaceService:PromptBundlePurchase(player, data.id)
		else MarketplaceService:PromptPurchase(player, data.id) end
	end)
	if not ok then
		warn("[CatalogUI] Purchase prompt failed:", err)
		setStatus("Roblox could not open the purchase prompt for this item.")
	end
end)
resetBtn.Activated:Connect(function()
	local requestId = beginBusy("Resetting...")
	if requestId then remote:FireServer("Reset", nil, nil, requestId) end
end)

local snapshotState = { requested = false, requestId = nil, emptyAttempts = 0 }
snapshotState.request = function(attempt)
	attempt = attempt or 0
	if refreshLocalWearingSnapshot then refreshLocalWearingSnapshot() end
	if snapshotState.requested then return end
	if busy then
		if attempt < 12 then task.delay(0.9, function() snapshotState.request(attempt + 1) end) end
		return
	end
	local requestId = beginBusy("Loading your equipped items...")
	if not requestId then
		if attempt < 12 then task.delay(0.9, function() snapshotState.request(attempt + 1) end) end
		return
	end
	snapshotState.requested = true
	snapshotState.requestId = requestId
	remote:FireServer("Snapshot", nil, nil, requestId)
	task.delay(37, function()
		if snapshotState.requestId == requestId then
			snapshotState.requested = false
			snapshotState.requestId = nil
			if attempt < 12 then task.delay(0.9, function() snapshotState.request(attempt + 1) end) end
		end
	end)
end
local function beginPublicInventoryStream(requestId, username)
	publicInventoryStreamRequestId = requestId
	H.publicInventoryTileViewStarted = false

	publicInventoryViewActive = true
	publicInventoryUsername = tostring(username or "player")
	publicInventoryReceivedCount = 0

	table.clear(publicInventoryAllItems)
	table.clear(publicInventoryItems)
	table.clear(catalogLoadedById)

	sourceId += 1
	pages = nil
	loadingMore = false
end

local function appendPublicInventoryPage(requestId, detail)
	if publicInventoryRequestId ~= requestId or type(detail) ~= "table" then
		return
	end

	local firstPage = publicInventoryStreamRequestId ~= requestId

	if firstPage then
		beginPublicInventoryStream(requestId, detail.username)
	end

	local keyword = string.lower(H.trim(searchBox.Text))

	for _, item in ipairs(type(detail.items) == "table" and detail.items or {}) do
		local itemId = tonumber(item.id or item.assetId)

		if itemId and itemId > 0 and not catalogLoadedById[itemId] then
			catalogLoadedById[itemId] = true

			local typeName = tostring(item.typeName or "Item")

			local data = {
				id = itemId,
				name = tostring(item.name or (H.prettyType(typeName) .. " · " .. tostring(itemId))),
				typeName = typeName,
				background = typeName == "AvatarBackground",
				auto = true,
			}

			table.insert(publicInventoryAllItems, data)
			publicInventoryReceivedCount += 1

			if publicInventoryMatchesFilter(data, keyword) then
				table.insert(publicInventoryItems, data)
			end
		end
	end

	-- Wait until 32 matching items are available before creating the view.
	if not H.publicInventoryTileViewStarted
		and #publicInventoryItems >= INVENTORY_INITIAL_RENDER_COUNT then

		H.publicInventoryTileViewStarted = true

		beginInventoryTileView(
			publicInventoryItems,
			curTab,
			chipIdx[curTab],
			0,
			sourceId
		)

	elseif H.publicInventoryTileViewStarted then
		H.inventoryCanvasItemCount = #publicInventoryItems
		H.updateResultsCanvas()
		H.scheduleResultsTileVisibility()
	end

	setStatus("Loading public inventory for " .. publicInventoryUsername
		.. " · " .. tostring(publicInventoryReceivedCount)
		.. " items received · scroll to load more")
end
remote.OnClientEvent:Connect(function(kind, requestId, code, detail)
	if kind == "Progress" then
		if requestId ~= activeRequestId
			or publicInventoryRequestId ~= requestId
			or code ~= "publicInventoryPage" then
			return
		end

		appendPublicInventoryPage(requestId, detail)
		return
	end

	if kind ~= "Result" or requestId ~= activeRequestId then return end

	busy = false
	activeRequestId = nil

	local rateLimitResponse =
		(type(detail) == "string"
			and detail:match("^Rate limited, waiting"))
		or (type(detail) == "table"
			and type(detail.statusMessage) == "string"
			and detail.statusMessage:match("^Rate limited, waiting"))

	if not rateLimitResponse then
		H.setPublicSearchLocked(false)
	end
	if code == "publicOutfits" and type(detail) == "table" then
		publicInventoryViewActive = false
		publicInventoryRequestId = nil
		publicInventoryStreamRequestId = nil

		table.clear(publicInventoryAllItems)
		table.clear(publicInventoryItems)
		sourceId += 1
		pages = nil
		loadingMore = false
		table.clear(catalogLoadedById)
		clearTiles()
		local seenOutfits, outfitCount = {}, 0
		for _, outfit in ipairs(type(detail.outfits) == "table" and detail.outfits or {}) do
			local outfitId = tonumber(outfit.id or outfit.Id)
			local editable = outfit.isEditable
			if editable == nil then editable = outfit.IsEditable end
			if editable ~= false and outfitId and outfitId > 0 and not seenOutfits[outfitId] then
				seenOutfits[outfitId] = true
				addTile({ id = outfitId, name = tostring(outfit.name or outfit.Name or ("Outfit " .. tostring(outfitId))), outfit = true }, "outfits")
				outfitCount += 1
			end
		end
		local suffix = detail.partial and " · partial result" or ""
		setStatus(outfitCount > 0 and ("Public saved outfits for " .. tostring(detail.username or "player") .. " · " .. tostring(outfitCount) .. " outfits" .. suffix)
			or ("No public saved outfits were returned for " .. tostring(detail.username or "player")))
	elseif code == "publicInventory" and type(detail) == "table" then
		if publicInventoryRequestId == requestId then

			if publicInventoryStreamRequestId ~= requestId then
				beginPublicInventoryStream(requestId, detail.username)
			end

			if not H.publicInventoryTileViewStarted then
				H.publicInventoryTileViewStarted = true

				beginInventoryTileView(
					publicInventoryItems,
					curTab,
					chipIdx[curTab],
					0,
					sourceId
				)
			else
				H.inventoryCanvasItemCount = #publicInventoryItems
				H.updateResultsCanvas()
				H.scheduleResultsTileVisibility()
			end

			publicInventoryReceivedCount =
				tonumber(detail.itemCount) or publicInventoryReceivedCount

			publicInventoryUsername =
				tostring(detail.username or publicInventoryUsername)

			publicInventoryRequestId = nil
			publicInventoryStreamRequestId = nil
		end

	elseif code == "publicAvatar" and type(detail) == "table" then
		publicInventoryViewActive = false
		publicInventoryRequestId = nil
		publicInventoryStreamRequestId = nil

		table.clear(publicInventoryAllItems)
		table.clear(publicInventoryItems)

		sourceId += 1
		pages = nil
		loadingMore = false
		table.clear(catalogLoadedById)
		clearTiles()

		local itemCount = 0

		for _, item in ipairs(type(detail.items) == "table" and detail.items or {}) do
			local itemId = tonumber(item.id or item.assetId)

			if itemId and itemId > 0 and not catalogLoadedById[itemId] then
				catalogLoadedById[itemId] = true

				local typeName = tostring(item.typeName or "Item")

				addTile({
					id = itemId,
					name = tostring(item.name or (H.prettyType(typeName) .. " · " .. tostring(itemId))),
					typeName = typeName,
					background = typeName == "AvatarBackground",
					auto = true,
				}, "inventory")

				itemCount += 1
			end
		end

		applyFilter()

		local prefix = detail.inventoryPrivate
			and "Inventory is private; "
			or "Public inventory unavailable; "

		setStatus(prefix .. "showing currently worn avatar items for "
			.. tostring(detail.username or "player")
			.. " · " .. tostring(itemCount) .. " items")
	elseif type(detail) == "table" and type(detail.equippedIds) == "table" then
		local serverCount = #detail.equippedIds
		if type(detail.equippedItems) == "table" then serverCount = math.max(serverCount, #detail.equippedItems) end
		local keepLocal = code == "snapshot" and serverCount == 0 and #currentEquippedItems > 0
		if not keepLocal then replaceEquippedState(detail.equippedIds, detail.equippedItems) end
		if type(detail.bodyScales) == "table" and updateBodyScaleInputs then updateBodyScaleInputs(detail.bodyScales) end
	elseif code == "added" and type(detail) == "table" then
		setEquipped(detail.id, true)
	elseif code == "removed" and type(detail) == "table" then
		setEquipped(detail.id, false)
	elseif code == "outfit" or code == "reset" or code == "user" then
		clearEquippedState()
		snapshotState.requested = false
		task.delay(0.4, function() snapshotState.request() end)
	end
	if requestId == snapshotState.requestId then
		snapshotState.requestId = nil
		if code == "snapshot" then
			local snapshotCount = type(detail) == "table" and type(detail.equippedItems) == "table" and #detail.equippedItems or 0
			if snapshotCount == 0 and #currentEquippedItems == 0 and snapshotState.emptyAttempts < 14 then
				snapshotState.requested = false
				snapshotState.emptyAttempts += 1
				task.delay(1.25, function() snapshotState.request(snapshotState.emptyAttempts) end)
			else
				snapshotState.requested = true
				snapshotState.emptyAttempts = 0
			end
		else
			snapshotState.requested = false
			task.delay(2, function() snapshotState.request() end)
		end
	end
	if code == "snapshot" and type(detail) == "table" then
		setViewportBackground(detail.backgroundId)
		if type(detail.equippedItems) == "table" then
		end
	end
	local messages = {
		added = "Wearing " .. lastName, removed = "Item removed", many = "Applied " .. lastName,
		outfit = "Outfit applied", reset = "Avatar reset", cleared = "Accessories cleared",
		unequippedAll = "All equipped avatar items removed",
		unequipPartial = "Some items could not be removed. Check the Wearing now list.",
		skin = "Body color changed", skinPart = "Selected body part recolored",
		scales = "Avatar scaling updated", user = "Avatar copied", snapshot = "Current avatar loaded",
		publicAvatar = "Public avatar loaded",
		publicInventory = "Public inventory loaded",
		publicOutfits = "Public outfits loaded",
		background = "Avatar background loaded", notEquipped = "That item is not currently equipped",
		nouser = "User not found", busy = "Please wait...",
	}
	local message = messages[code]
	if code == "many" and type(detail) == "table" then
		local applied = type(detail.ids) == "table" and #detail.ids or 0
		local skipped = tonumber(detail.skipped) or 0
		local overLimit = tonumber(detail.overLimit) or 0
		local bodyParts = tonumber(detail.bodyPartAssets) or 0
		message = "Applied " .. tostring(detail.bundleName or lastName) .. " (" .. tostring(applied) .. " items)"
		if bodyParts > 0 then message ..= " · " .. tostring(bodyParts) .. " body parts included" end
		if skipped + overLimit > 0 then message ..= " · " .. tostring(skipped + overLimit) .. " skipped" end
	end
	if code == "publicOutfits" and type(detail) == "table" then
		local outfitCount = type(detail.outfits) == "table"
			and #detail.outfits
			or 0

		local suffix = ""

		if detail.statusMessage then
			suffix = " · " .. tostring(detail.statusMessage)
		elseif detail.partial then
			suffix = " · partial result"
		end

		message = "Public saved outfits for "
			.. tostring(detail.username or "player")
			.. " · " .. tostring(outfitCount)
			.. " outfits"
			.. suffix
	end

	if code == "publicAvatar" and type(detail) == "table"
		and detail.inventoryPrivate then

		message = "Unavailable, user's inventory is private."
	end
	if code == "publicInventory" and type(detail) == "table" then
		local itemCount = tonumber(detail.itemCount) or publicInventoryReceivedCount

		local suffix = ""

		if detail.statusMessage then
			suffix = " · " .. tostring(detail.statusMessage)
		elseif detail.partial then
			suffix = " · partial result"
		end

		message = "Public inventory for "
			.. tostring(detail.username or publicInventoryUsername)
			.. " · " .. tostring(itemCount)
			.. " items"
			.. suffix
			.. " · scroll to load more"
	end
	if not message then
		local detailMessage = tostring(detail or code)

		if detailMessage:match("^Rate limited, waiting")
			or detailMessage:match("^Unavailable, user's") then

			message = detailMessage
		else
			message = "Couldn't apply: " .. string.sub(detailMessage, 1, 90)
		end
	end
	setStatus(message)
	if type(detail) == "string"
		and detail:match("^Rate limited, waiting") then

		H.startPublicSearchCooldown(
			tonumber(detail:match("%((%d+) seconds?%)")) or 60
		)

	elseif type(detail) == "table"
		and type(detail.statusMessage) == "string"
		and detail.statusMessage:match("^Rate limited, waiting") then

		H.startPublicSearchCooldown(
			tonumber(detail.statusMessage:match("%((%d+) seconds?%)")) or 60
		)
	end
	if code ~= "error" and code ~= "busy" and code ~= "nouser" then
		scheduleRebuild(0.6)
		task.delay(0.75, function()
			if refreshLocalWearingSnapshot then refreshLocalWearingSnapshot() end
			if code == "unequippedAll" or code == "reset" or code == "outfit" or code == "user" then
				snapshotState.requested = false
				snapshotState.request()
			end
		end)
	end
end)

H.refreshFilterLabels()
H.opened = false
H.setCatalogVisible = function(visible)
	player.CameraMinZoomDistance = visible and 5 or 0.5
	main.Visible = visible
	toggleBtn.Visible = not visible
	if not visible then
		stopViewportEmotePreview()
		if H.closeBodyColorPicker then H.closeBodyColorPicker() end
		detailOverlay.Visible = false
		if H.saveOverlay then H.saveOverlay.Visible = false end
	end
end
mainCloseBtn.Activated:Connect(function() H.setCatalogVisible(false) end)
toggleBtn.Activated:Connect(function()
	if main.Visible then return end
	H.setCatalogVisible(true)
	if refreshLocalWearingSnapshot then refreshLocalWearingSnapshot() end
	task.delay(0.65, function()
		if main.Visible and refreshLocalWearingSnapshot then refreshLocalWearingSnapshot() end
	end)
	if not H.opened then
		H.opened = true
		setTab(1)
	end
	snapshotState.request()
end)
player.CharacterAdded:Connect(function()
	snapshotState.requested = false
	snapshotState.requestId = nil
	task.delay(1.5, function()
		if refreshLocalWearingSnapshot then refreshLocalWearingSnapshot() end
		snapshotState.request()
	end)
end)
player.CharacterAppearanceLoaded:Connect(function(character)
	if character ~= player.Character then return end
	task.delay(0.25, function()
		if character ~= player.Character then return end
		if refreshLocalWearingSnapshot then refreshLocalWearingSnapshot() end
		snapshotState.requested = false
		snapshotState.request()
	end)
end)
