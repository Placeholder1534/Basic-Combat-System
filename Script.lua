--[[
	Combat System (Server-Side)
	
	Description:
	Handles player combat logic including:
	- Melee attacks with combo system
	- Dash ability using LinearVelocity
	- Stun mechanic on max combo
	- Ability cooldown validation
	- Server-side hit detection
	
	All combat logic is validated on the server to prevent client abuse
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local ATTACK_COOLDOWN = 1
local DASH_COOLDOWN = 1
local DASH_FORCE = 100

local COMBO_WINDOW = 1.5
local MAX_COMBO = 4

local STUN_TIME = 0.5

local COLLISION_GROUP = "Players"

local Cooldown = {}

local ActionEvent = ReplicatedStorage:FindFirstChild("Action")
if not ActionEvent then
	ActionEvent = Instance.new("RemoteEvent")
	ActionEvent.Name = "Action"
	ActionEvent.Parent = ReplicatedStorage
end

if not PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then
	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
end

-- Updates the player combo
-- Resets combo if the time between attacks is greater than COMBO_WINDOW
local function updateCombo(player: Player)
	local character = player.Character
	if not character then 
		return
	end
	
	local currentCombo = character:GetAttribute("CurrentCombo") or 0
	local lastCombo = character:GetAttribute("LastCombo") or 0
	
	if os.clock() - lastCombo > COMBO_WINDOW then
		currentCombo = 0
	end
	
	if currentCombo >= MAX_COMBO then
		currentCombo = 0
	end
	
	character:SetAttribute("CurrentCombo", currentCombo + 1)
	character:SetAttribute("LastCombo", os.clock())
end

-- Short forward dash using LinearVelocity
local function dash(player: Player)
	local character = player.Character
	if not character then 
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = humanoidRootPart

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = humanoidRootPart.CFrame.LookVector * DASH_FORCE
	linearVelocity.Parent = humanoidRootPart

	Debris:AddItem(linearVelocity, 0.25)
	Debris:AddItem(attachment, 0.25)
end

local function canDamagePlayer(humanoid: Humanoid)
	return humanoid.Health > 0
end

local function setCooldown(player: Player, abilityName: string)
	if not Cooldown[player] then
		Cooldown[player] = {}
	end
	
	Cooldown[player][abilityName] = os.clock()
end

local function canUseAbility(player: Player, abilityName: string, cooldown: number)
	if not Cooldown[player] then
		Cooldown[player] = {}
	end
	
	local lastTime = Cooldown[player][abilityName] or 0
	return os.clock() - lastTime > cooldown
end

local function createHitbox(character: Model)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then 
		return
	end
	
	local hitbox = Instance.new("Part")
	hitbox.Transparency = 0.5
	hitbox.CFrame = humanoidRootPart.CFrame * CFrame.new(0, 0, -3)
	hitbox.Anchored = true
	hitbox.BrickColor = BrickColor.Red()
	hitbox.Size = Vector3.new(5, 5, 5)
	hitbox.CanCollide = false
	hitbox.Parent = workspace
	
	Debris:AddItem(hitbox, 0.5)
	
	return hitbox
end

-- The target get stunned if the attacker has reached MAX_COMBO
-- also can not move or jump during the stun
local function canStun(player: Model, attacker: Model)
	local combo = player:GetAttribute("CurrentCombo") or 0

	if combo == MAX_COMBO then
		local humanoid = attacker:FindFirstChildOfClass("Humanoid")
		if not humanoid then 
			return
		end

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		
		attacker:SetAttribute("Stunned", true)

		task.delay(STUN_TIME, function()
			if humanoid and humanoid.Parent then
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
				
				attacker:SetAttribute("Stunned", false)
			end
		end)
	end
end

local function dealDamage(player: Player)
	local character = player.Character
	if not character then 
		return
	end
	
	local hitbox = createHitbox(character)
	if not hitbox then 
		return
	end
	
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {character}
	
	-- prevent the player from taking damage twice
	local hitHumanoids = {}
	
	local parts = workspace:GetPartsInPart(hitbox, overlapParams)
	
	for _, otherPart in ipairs(parts) do
		local target = otherPart:FindFirstAncestorOfClass("Model")
		if not target then 
			continue
		end
		
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		if not humanoid then 
			continue
		end
		
		if hitHumanoids[humanoid] then 
			continue
		end
		
		if canDamagePlayer(humanoid) then
			-- damage scales based on current combo
			local currentCombo = character:GetAttribute("CurrentCombo") or 1
			local damage = 10 + (currentCombo * 2)
			
			hitHumanoids[humanoid] = true
			humanoid:TakeDamage(damage)
			canStun(character, target)
			break
		end
	end
end

local function onActionEvent(player: Player, actionName: string)
	local character = player.Character
	if not character then 
		return
	end
	
	--the player sends the action name to the server
	--we check that here and then do the action
	
	if actionName == "Attack" then
		-- player cant attack if this guy is stunned
		if character:GetAttribute("Stunned") then
			return
		end
		
		if canUseAbility(player, "LastAttack", ATTACK_COOLDOWN) then
			setCooldown(player, "LastAttack")
			updateCombo(player)
			dealDamage(player)
		end
	elseif actionName == "Dash" then
		if canUseAbility(player, "LastDash", DASH_COOLDOWN) then
			setCooldown(player, "LastDash")
			dash(player)
		end
	end
end

local function onCharacterAdded(character: Model)
	character:SetAttribute("CurrentCombo", 0)
	character:SetAttribute("LastCombo", os.clock())
	character:SetAttribute("Stunned", false)
	
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = COLLISION_GROUP
		end
	end
end

local function onPlayerRemoving(player: Player)
	Cooldown[player] = nil
end

local function onPlayerAdded(player: Player)
	Cooldown[player] = {}
	
	if player.Character then
		onCharacterAdded(player.Character)
	end
	
	player.CharacterAdded:Connect(onCharacterAdded)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

ActionEvent.OnServerEvent:Connect(onActionEvent)

