--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name = "Nanospray GL4",
		version = 3,
		desc = "Draws Dense Nano Spray",
		author = "Beherith",
		date = "2023.01.04",
		license = "Lua code is GPL V2, GLSL is (c) Beherith (mysterme@gmail.com)",
		layer = 9999,
		enabled = false
	}
end

-------------------------------- Notes, TODO ----------------------------------
-- Spawn 1000 geoshader billboards from a buffer of points filled with random
-- use startframe to start anim, and endframe to end anim

-- PROBLEMS:
-- GetUnitNanoPieces returns nil if unit is not building
	-- use 'hardcoded' nanopiecenames by scrounging through the cobs

-- When a piece is hidden, its matrix is zero'd out, so gotta workaround sustainy type effects
	--  use a different emit piece, one thats not hidden

-- Hard to query who what where when is building
	-- UnitCmdDone signifies completion (sometimes?)

-- Needs some unitform buffer shit to convey buildpower
-- Needs stop and start times added to it
-- If builder is not visible, then no nano spray produced (this is bad for LOS)
-- query lostex in geoshader


-- If target is mobile, and unit has to chase it, the script_buildstartstop doenst get called multiple times

-- See \luarules\gadgets\gfx_unit_script_buildstartstop.lua !!!!!!

-- Change all nano-lights to hide only after some time, to allow for the last particles to get there

--X Fall back to drawpos if matrix not present

-- Handle Team Changes

-- 'Detach' sprays?
--X direction
-- timing
-- strength
-- velocity adjust
--X a mobile target can only ever be a unitID!

-- Allow a texture to be defined

-- Build types
	-- construction
	-- repair
		-- mobile
		-- immobile
	-- reclaim
		-- feature
		-- unit
		-- mobile
		-- immobile
	-- resurrect
		-- feature
		-- unit
	-- capture
		-- mobile
		-- immobile
	-- restore
-- Area Commands?

----------------------------- Localize for optmization ------------------------------------

local glBlending = gl.Blending
local glTexture = gl.Texture


-- Strong:
local spGetGroundHeight = Spring.GetGroundHeight
local spIsSphereInView  = Spring.IsSphereInView
local spGetUnitPosition  = Spring.GetUnitPosition

local fadeout = 60

local shaderConfig = {
	POINTCOUNT = 64,
	FADEOUT = fadeout,
}
local nanoParticleTexture = 'LuaUI/images/nanoparticle_gl4.tga'

local intensityMultiplier = 1.0
------------------------------ Debug switches ------------------------------
local autoupdate = true
------------------------------ Data structures and management variables ------------

local nanoSprayVBO  -- for immobile targets
local nanoSprayMobileVBO  -- for mobile targets (pretty much repair + reclaim only)

local mobileSprays = {} -- table of instanceID to mobileUnitID

local nanoSprayShader

local sprayRemoveQueue = {} -- stores sprays that have expired life {gameframe = {lightIDs ... }}

local unitDefCanNanoSpray = {} -- maps unitDefID to wether a unit can ever spray nanos
local unitDefPeiceMapCache = {} -- maps unitDefID to piecemap

local nanoSprayCacheTable = {} -- this is a reusable table cache for saving memory later on
local unitAttachedNanoSprays = {}
local numSprays = 0
local numScriptEvents = 0

local autoSprayInstanceID = 128000 -- as MAX_PROJECTILES = 128000, so they get unique ones

local gameFrame = 0

local luaShaderDir = "LuaUI/Include/"
local LuaShader = VFS.Include(luaShaderDir.."LuaShader.lua")
VFS.Include(luaShaderDir.."instancevbotable.lua")

local shaderSourceCache = {
	shaderName = 'Nanospray GL4',
	vssrcpath = "LuaUI/Shaders/nanospray_gl4.vert.glsl",
	gssrcpath = "LuaUI/Shaders/nanospray_gl4.geom.glsl",
	fssrcpath = "LuaUI/Shaders/nanospray_gl4.frag.glsl",
	shaderConfig = shaderConfig,
	uniformInt = {
		nanoParticleTexture = 0,
		},
	uniformFloat = {
		nightFactor = 1.0,
		intensityMultiplier = 1.0,
	  },
}

local spec = Spring.GetSpectatingState()

---------------------- INITIALIZATION FUNCTIONS ----------------------------------

local function goodbye(reason)
	Spring.Echo('Nanospray GL4 exiting:', reason)
	widgetHandler:RemoveWidget()
end

local function initGL4()
	nanoSprayShader = LuaShader.CheckShaderUpdates(shaderSourceCache, 0)
	if not nanoSprayShader then
		goodbye("Failed to compile nanoSprayShader GL4 shader")
		return false
	end
	-- init the VBO
	local vboLayout = {
			{id = 1, name = 'endworldposrad', size = 4}, -- target world pos and radius
			{id = 2, name = 'otherparams', size = 4}, -- startframe, endframe, count, direction
			{id = 3, name = 'pieceIndex', size = 1, type = GL.UNSIGNED_INT},
			{id = 4, name = 'instData', size = 4, type = GL.UNSIGNED_INT},
	}

	local vertexVBO, numVertices  = makePointVBO(shaderConfig.POINTCOUNT, 1, true)
	nanoSprayVBO = makeInstanceVBOTable( vboLayout, 16, "nanoSprayShader GL4", 4)
	if vertexVBO == nil or nanoSprayVBO == nil then goodbye("Failed to make nanoSprayVBO") end
	nanoSprayVBO.vertexVBO = vertexVBO
	nanoSprayVBO.numVertices = numVertices
	nanoSprayVBO.VAO = makeVAOandAttach(nanoSprayVBO.vertexVBO, nanoSprayVBO.instanceVBO)
end

local function GetUnitNanoPieces(unitID, unitDefID)
	unitDefID = unitDefID or Spring.GetUnitDefID(unitID)
	if unitDefID == nil then return nil end
	if unitDefPeiceMapCache[unitDefID] then return unitDefPeiceMapCache[unitDefID] end
	local nanolist = Spring.GetUnitNanoPieces(unitID)
	--Spring.Echo("GetUnitNanoPieces", unitID, unitDefID, nanolist)
	if nanolist == nil then
		return nil
	else
		unitDefPeiceMapCache[unitDefID] = nanolist
		return nanolist
	end
end

---AddSpray(instanceID, unitID, pieceIndex, nanoparams, noUpload)
local function AddSpray(instanceID, unitID, pieceIndex, noUpload, x,y,z,r,m, sprayType )
	--if autoupdate then Spring.Echo("AddSpray", unitID, pieceIndex, 'xyzrm', x,y,z,r,m ) end
	if instanceID == nil then
		autoSprayInstanceID = autoSprayInstanceID + 1
		instanceID = autoSprayInstanceID
	end
	local gameFrame = Spring.GetGameFrame()
	if noUpload then gameFrame = -500 end -- shitty hax
	--Spring.Echo(x,y,z,r)
	instanceID = pushElementInstance(nanoSprayVBO, {x,y,z,r,gameFrame,0,1023,sprayType, pieceIndex, 0,0,0,0}, instanceID, true, noUpload, unitID)
	-- calcLightExpiry
	return instanceID
end

-- multiple lights per unitdef/piece are possible, as the lights are keyed by lightname
local function AddSprayForUnit(unitID, unitDefID, noUpload, reason, x,y,z,r,m, sprayType)
	-- canbuild
	local nanos = GetUnitNanoPieces(unitID)
	--Spring.Debug.TraceEcho()
	--Spring.Echo("AddSprayForUnit",unitID, unitDefID, noUpload,nanos)
	if nanos then
		if unitAttachedNanoSprays[unitID] == nil then
			unitAttachedNanoSprays[unitID] = {}
		end
		for i,pieceIndex in ipairs(nanos) do
			local instanceID = AddSpray(nil, unitID, pieceIndex, noUpload, x,y,z,r,m, sprayType)
			if m then 
				mobileSprays[instanceID] = m
			end
			unitAttachedNanoSprays[unitID][instanceID] = true
		end
	end
end

local function RemoveSprayForUnit(unitID, instanceID, noUpload)
	local numremoved = 0
	if unitAttachedNanoSprays[unitID] then
		if instanceID and unitAttachedNanoSprays[unitID][instanceID] then
			popElementInstance(nanoSprayVBO,instanceID)
			numremoved = numremoved + 1
			unitAttachedNanoSprays[unitID][instanceID] = nil
		else
			for instanceID, _ in pairs(unitAttachedNanoSprays[unitID]) do
				if nanoSprayVBO.instanceIDtoIndex[instanceID] then
					numremoved = numremoved + 1
					popElementInstance(nanoSprayVBO,instanceID)
					mobileSprays[instanceID] = nil
				else
					--Spring.Echo("Light attached to unit no longer is in targetVBO", unitID, instanceID, targetVBO.myName)
				end
			end
			--Spring.Echo("Removed lights from unitID", unitID, numremoved, successes)
			unitAttachedNanoSprays[unitID] = nil
		end
	else
		--Spring.Echo("RemoveunitAttachedNanoSprays: No lights attached to", unitID)
	end
	return numremoved
end
function widget:PlayerChanged(playerID)
	spec = Spring.GetSpectatingState()
	local _, _, isSpec, teamID = Spring.GetPlayerInfo(playerID, false)
end

--[[
Stuff needed in the cob script:

lua_UnitScriptBuildStartStop(onoff, param1, param2, param3) 
{
	return 0;
}

call-script lua_UnitScriptBuildStartStop(onoff, 1,2,3);
]]--
-- only add them to a table for further processing!
local unitScriptBuildEventQueue = {}

local function UnitScriptBuildStartStop(unitID, unitDefID, onoff, param1, param2, param3)
	--Spring.Echo("Widgetside UnitScriptBuildStartStop", unitID, unitDefID, whichDecal, posx,posz, heading)
	if unitDefCanNanoSpray[unitDefID] and Spring.ValidUnitID(unitID) and Spring.GetUnitIsDead(unitID) == false then
		--Spring.Echo("Queued spray for", unitID, unitDefID, onoff)
		if Spring.IsUnitAllied(unitID) then 
			unitScriptBuildEventQueue[unitID] = onoff
		end
	end
end

function widget:Initialize()
	if initGL4() == false then return end
	
	-- find all builders
	for unitDefID, unitDef in pairs(UnitDefs) do 
		if unitDef.canAssist or unitDef.canRepair or unitDef.canReclaim or #unitDef.buildOptions > 0 then 
			unitDefCanNanoSpray[unitDefID] = true
		end
	end
	
	widgetHandler:RegisterGlobal('UnitScriptBuildStartStop', UnitScriptBuildStartStop)
	if WG['unittrackerapi'] and WG['unittrackerapi'].visibleUnits then
		widget:VisibleUnitsChanged(WG['unittrackerapi'].visibleUnits, nil)
	end
end

function widget:VisibleUnitAdded(unitID, unitDefID, unitTeam)
	--AddSprayForUnit(unitID, unitDefID, false, "VisibleUnitAdded")
end

function widget:VisibleUnitsChanged(extVisibleUnits, extNumVisibleUnits)
	clearInstanceTable(nanoSprayVBO) -- clear all instances
	for unitID, unitDefID in pairs(extVisibleUnits) do
		--AddSprayForUnit(unitID, unitDefID, true, "VisibleUnitsChanged") -- add them with noUpload = true
	end
	uploadAllElements(nanoSprayVBO) -- upload them all
end

function widget:VisibleUnitRemoved(unitID) -- remove all the lights for this unit
	--if debugmode then Spring.Debug.TraceEcho("remove",unitID,reason) end
	RemoveSprayForUnit(unitID)
end


function widget:Shutdown()
	widgetHandler:DeregisterGlobal('UnitScriptBuildStartStop')
end

local function isMobile(unitID) 
	local buildprogress = select(5,Spring.GetUnitHealth(unitID))
	if not buildprogress then return nil end
	if buildprogress < 1 then 
		return nil
	else
		local unitDefID = Spring.GetUnitDefID(unitID)
		if UnitDefs[unitDefID].canMove then 
			return unitID
		else
			return nil
		end
	end
end


-- This is the true hell!
-- returns the x,y,z,radius,mobileUnitID or nil
-- spraytype is 1=forward, -1=reverse, 0=bidirectional
local function GetNanoSprayTargetType(unitID, unitDefID)
	--local index, name, cmdtype, cmdstr = Spring.GetActiveCommand(unitID)
	local x,y,z,r,mobile
	local spraytype = 1
	local buildTargetID = Spring.GetUnitIsBuilding(unitID)
	if buildTargetID then -- Easiest case, the unit is building something
		_,_,_, x, y, z = spGetUnitPosition(buildTargetID, true)
		r = Spring.GetUnitRadius(buildTargetID)
		mobile = isMobile(buildTargetID)
		return x, y, z, r, mobile, spraytype
	end
	
	local nanopieces =  Spring.GetUnitNanoPieces (  unitID ) --return: nil | { [1] = number piece1, etc ... }
	local cmdID, cmdOpts, cmdTag, cmdParam1, cmdParam2, cmdParam3, cmdParam4 =  Spring.GetUnitCurrentCommand(unitID, 1)
	
	if cmdID == CMD.RECLAIM or cmdID == CMD.REPAIR or cmdID == CMD.CAPTURE then  
		--Spring.Echo("Cmdtarget", cmdID, cmdOpts, cmdTag, cmdParam1, cmdParam2, cmdParam3)
		buildTargetID = cmdParam1
		if buildTargetID < 32000 then  
			_,_,_, x, y, z = spGetUnitPosition(buildTargetID, true)
			r = Spring.GetUnitRadius(buildTargetID)
			mobile = isMobile(buildTargetID)
		else -- if buildTargetID > maxunits then its a feature
			for i, featureID in ipairs(Spring.GetAllFeatures()) do 
				--Spring.Echo(featureID, FeatureDefs[Spring.GetFeatureDefID(featureID)].name)
			end
			buildTargetID = buildTargetID - 32000
			_,_,_, x, y, z = Spring.GetFeaturePosition(buildTargetID, true)
			r = Spring.GetFeatureRadius(buildTargetID)
		end
			
		if cmdID == CMD.RECLAIM then spraytype = -1	end
		if cmdID == CMD.CAPTURE then spraytype = 0	end
	end
	
	if cmdID == CMD.RESTORE then -- Resp
		--Spring.Echo("CMD.RESTORE", cmdID, cmdOpts, cmdTag, cmdParam1, cmdParam2, cmdParam3, cmdParam4)
		x,y,z,r = cmdParam1, cmdParam2, cmdParam3, cmdParam4
		spraytype = 0
	end
	
	if cmdID == CMD.RESURRECT then 
		--Spring.Echo("CMD.RESURRECT", cmdID, cmdOpts, cmdTag, cmdParam1, cmdParam2, cmdParam3, cmdParam4)
		buildTargetID = cmdParam1 - 32000
		_,_,_, x, y, z = Spring.GetFeaturePosition(buildTargetID, true)
		r = Spring.GetFeatureRadius(buildTargetID)
		spraytype = 0
	end
	
	--Spring.Echo("Target?", unitID, 'cmdID=', cmdID, 'cmdTag=',cmdTag, 'isbuilding=', isbuilding, 'nanopieces = ' , nanopieces, "xyzr", x,y,z,r, "buildTargetID=",buildTargetID)

	return x, y, z, r, mobile, spraytype
end

local updateSprayTable = {}
local function UpdateSprayPosition(instanceID, mobileID)
	local _,_,_,x,y,z = spGetUnitPosition(mobileID, true)
	if x then 
		local instanceIndex = nanoSprayVBO.instanceIDtoIndex[instanceID]
		if instanceIndex == nil then return nil end
		getElementInstanceData(nanoSprayVBO, instanceID, updateSprayTable)
		updateSprayTable[1] = x
		updateSprayTable[2] = y
		updateSprayTable[3] = z
		local unitID = nanoSprayVBO.indextoUnitID[instanceIndex]
		pushElementInstance(nanoSprayVBO, updateSprayTable, instanceID, true, nil, unitID)
	end
end

local function UpdateSprayDieTime(instanceID, gameFrame)
	local instanceIndex = nanoSprayVBO.instanceIDtoIndex[instanceID]
	if instanceIndex == nil then return nil end
	getElementInstanceData(nanoSprayVBO, instanceID, updateSprayTable)
	updateSprayTable[6] = gameFrame
	updateSprayTable[9] = 0 -- try setting piece index to 0 
	local unitID = nanoSprayVBO.indextoUnitID[instanceIndex]
	pushElementInstance(nanoSprayVBO, updateSprayTable, instanceID, true, nil, unitID)
end

local function StopSprayForUnit(unitID, gameFrame, diequeue)
	if unitAttachedNanoSprays[unitID] then
		for instanceID, _ in pairs(unitAttachedNanoSprays[unitID]) do
			UpdateSprayDieTime(instanceID, gameFrame)
			diequeue[instanceID] = unitID
		end
	end
end

local lastGameFrame = Spring.GetGameFrame() -1 
function widget:Update()
	local gameFrame = Spring.GetGameFrame()
	
	if gameFrame > lastGameFrame then 
		lastGameFrame = gameFrame
		
		for unitID, buildstatus in pairs(unitScriptBuildEventQueue) do
			local index, name, cmdtype, cmdstr = Spring.GetActiveCommand(unitID)
			
			local isbuilding = Spring.GetUnitIsBuilding ( unitID )
			local nanopieces =  Spring.GetUnitNanoPieces (  unitID ) --return: nil | { [1] = number piece1, etc ... }
			--Spring.Echo("TRY", unitID, isbuilding,nanopieces )
			if buildstatus == 1 then 
				local  x,y,z, r, mobileID, sprayType = GetNanoSprayTargetType(unitID)
				if x then 
					AddSprayForUnit(unitID, unitDefID, nil, "fuck", x,y,z,r, mobileID, sprayType )
				end
			else
				local dietime = gameFrame + fadeout
				if sprayRemoveQueue[dietime] == nil then
					sprayRemoveQueue[dietime] = {}
				end
				StopSprayForUnit(unitID, gameFrame, sprayRemoveQueue[dietime])
				--RemoveSprayForUnit(unitID)
			end
			unitScriptBuildEventQueue[unitID] = nil
		end
			
		for instanceID, mobileUnitID in pairs(mobileSprays) do 
			UpdateSprayPosition(instanceID, mobileUnitID)
		end
		
		
		if sprayRemoveQueue[gameFrame] then
			for instanceID, unitID in pairs(sprayRemoveQueue[gameFrame]) do
				if nanoSprayVBO.instanceIDtoIndex[instanceID] then
					--Spring.Echo("removing dead light", targetVBO.usedElements, 'id:', instanceID)
					popElementInstance(nanoSprayVBO, instanceID)
					unitAttachedNanoSprays[unitID][instanceID] = nil
					if next(unitAttachedNanoSprays[unitID]) == nil then 
						unitAttachedNanoSprays[unitID] = nil
					end
				end
				

			end
			sprayRemoveQueue[gameFrame] = nil
		end
	end
end

function widget:DrawWorld() -- We are drawing in world space, probably a bad idea but hey
	if autoupdate then
		nanoSprayShader = LuaShader.CheckShaderUpdates(shaderSourceCache, 0) or nanoSprayShader
	end

	if nanoSprayVBO.usedElements > 0 then
		--if Spring.GetDrawFrame() % 100 == 0 then Spring.Echo(nanoSprayVBO.usedElements) end 
		gl.DepthTest(true)
		gl.Texture(0, nanoParticleTexture)
		nanoSprayShader:Activate()
		--nanoSprayShader:SetUniformFloat("nightFactor", nightFactor)
		glBlending(GL.SRC_ALPHA, GL.ONE)
		nanoSprayVBO:draw(GL.POINTS)
		nanoSprayShader:Deactivate()
		gl.Texture(0, false)
		gl.Culling(GL.BACK)
		gl.DepthTest(true)
		--gl.DepthMask(true) --"BK OpenGL state resets", was true but now commented out (redundant set of false states)
		glBlending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)
	end
end

-- Register /luaui dlgl4stats to dump light statistics
function widget:TextCommand(command)
	if string.find(command, "asdfasdfasfasdfsadfsdafsd", nil, true) then
		return true
	end
	return false
end
