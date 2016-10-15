util.AddNetworkString("Prone.RequestedProne")
util.AddNetworkString("Prone.GetUpWarning")
util.AddNetworkString("Prone.Entered")
util.AddNetworkString("Prone.EndAnimation")
util.AddNetworkString("Prone.Exit")
util.AddNetworkString("Prone.PlayerFullyLoaded")

net.Receive("Prone.RequestedProne", function(_, ply)
	if ply.prone.lastrequest <= CurTime() then
		prone.Handle(ply)
		ply.prone.lastrequest = CurTime() + 1.25
	end
end)

local PLAYER = FindMetaTable("Player")
function PLAYER:CanExitProne()
	local tr = util.TraceHull({
		start = self:GetPos(),
		endpos = self:GetPos(),
		filter = self,
		mins = Vector(-16, -16, 0), -- make this use obbs as reference
		maxs = Vector(16, 16, 78)
	})

	if tr.Hit then
		net.Start("Prone.GetUpWarning")
		net.Send(self)
	end

	return not tr.Hit
end

function prone.Handle(ply)
	if not IsValid(ply) or not ply:Alive() then
		return
	end

	if ply:IsProne() then
		if ply:CanExitProne() then
			local hookresult = hook.Call("Prone.CanExit", nil, ply) == nil and false or true
			if hookresult then
				prone.End(ply)
			end
		end
	else
		if ply:GetMoveType() ~= MOVETYPE_NOCLIP and ply:IsFlagSet(FL_ONGROUND) and ply:WaterLevel() < 1 then
			local hookresult = hook.Call("Prone.CanEnter", nil, ply) == nil and false or true
			if hookresult then
				prone.Enter(ply)
			end
		end
	end
end

function prone.Enter(ply)
	if not IsValid(ply) then
		return
	end

	net.Start("Prone.Entered")
		net.WriteEntity(ply)
	net.Broadcast()

	ply.prone.starttime = CurTime()

	local length = ply:SequenceDuration(ply:LookupSequence("proneup_stand"))
	ply.prone.getdowntime = length + ply.prone.starttime
	ply:SetProneAnimationLength(ply.prone.getdowntime)

	ply.prone.oldviewoffset = ply:GetViewOffset()
	ply.prone.oldviewoffset_ducked = ply:GetViewOffsetDucked()

	local weapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon() or false
	if weapon then
		weapon:SetNextPrimaryFire(ply.prone.getdowntime)
		weapon:SetNextSecondaryFire(ply.prone.getdowntime)
	end

	ply:SetHull(Vector(-16, -16, 0), Vector(16, 16, prone.config.HullHeight))
	ply:SetHullDuck(Vector(-16, -16, 0), Vector(16, 16, prone.config.HullHeight))

	ply:AnimRestartMainSequence()
	ply:SetProneAnimationState(PRONE_GETTINGDOWN)

	hook.Call("Prone.OnPlayerEntered", nil, ply, length)
end

-- Gets up and exits prone, unless forced is true. Then it wont play the get up animation.
function prone.End(ply, forced)
	if not IsValid(ply) then
		return
	end

	ply.prone.endtime = CurTime()
	local length = 0

	if forced ~= true then
		net.Start("Prone.EndAnimation")
			net.WriteEntity(ply)
		net.Broadcast()

		length = ply:SequenceDuration(ply:LookupSequence("proneup_stand"))
		ply.prone.getuptime = length + ply.prone.endtime - .1
		ply:SetProneAnimationLength(ply.prone.getuptime)

		local weapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon() or false
		if weapon then
			weapon:SetNextPrimaryFire(ply.prone.getuptime)
			weapon:SetNextSecondaryFire(ply.prone.getuptime)
		end

		ply:AnimRestartMainSequence()
		ply:SetProneAnimationState(PRONE_GETTINGUP)
	else
		prone.Exit(ply)
	end
end

-- Actually leaving prone, call Prone.End with the second arguement as true rather than calling this directly.
function prone.Exit(ply)
	if not IsValid(ply) then
		return
	end

	ply:SetViewOffset(ply.prone.oldviewoffset)
	ply:SetViewOffsetDucked(ply.prone.oldviewoffset_ducked)

	ply:ResetHull()

	net.Start("prone.Exit")
		net.WriteEntity(ply)
	net.Broadcast()

	ply:SetProneAnimationState(PRONE_NOTINPRONE)
	hook.Call("Prone.OnPlayerExitted", nil, ply)
end

net.Receive("Prone.PlayerFullyLoaded", function(_, ply)
	local proneplayers = {}
	for i, v in ipairs(player.GetAll()) do
		if v:IsProne() then
			table.insert(proneplayers, v)
		end
	end

	if #proneplayers > 0 then
		net.Start("Prone.SendPronePlayers")
			net.WriteUInt(#proneplayers, 7)
			for i, v in ipairs(proneplayers) do
				net.WriteEntity(v)
			end
		net.Send(ply)
	end
end)

hook.Add("DoPlayerDeath", "Prone.ExitOnDeath", function(ply)
	if ply:IsProne() then
		prone.End(ply, true)
	end
end)

hook.Add("VehicleMove", "Prone.ExitOnVehicleEnter", function(ply)
	if ply:IsProne() then
		prone.Prone(ply, true)
	end
end)

timer.Create("Prone.Manage", 1, 0, function()
	for i, v in ipairs(player.GetAll()) do
		if v:IsProne() then
			if v:GetMoveType() == MOVETYPE_NOCLIP then 
				prone.End(v, true)
			elseif v:WaterLevel() > 1 and not v:ProneIsGettingUp() then
				prone.End(v)
			end
		end
	end
end)