local Skada = Skada
--local L = LibStub("AceLocale-3.0"):GetLocale("Skada", false)

local mod = Skada:NewModule("Stagger")
local modDetails = Skada:NewModule("Stagger details")

local function printdebug(...)
      --print(...)
end

local function getSetDuration(set)
      if set.time > 0 then
            return set.time
      else
            local endtime = set.endtime
            if not endtime then
                  endtime = time()
            end
            return endtime - set.starttime
      end
end

local function nextDataset(win, context)
      context.index = context.index or 1

      local dataset = win.dataset[context.index] or {}
      dataset.id = context.index
      win.dataset[context.index] = dataset

      context.index = context.index + 1
      return dataset
end

local function getPurifyPercent(unitGUID)
      local talentGroup = GetActiveSpecGroup()
      _, _, _, elusiveDanceSelected, _ = GetTalentInfo(7, 1, talentGroup, true, unitGUID)

      local purifyPercent = 0.5
      if elusiveDanceSelected then
            purifyPercent = purifyPercent + 0.15
      end
      --printdebug("Purify percent for "..unitGUID..": "..purifyPercent)
      return purifyPercent
end

local tick = {}
local function logStaggerTick(set, tick, isCurrent)
      local player = Skada:get_player(set, tick.dstGUID, tick.dstName)
      if player then
            player.stagger.taken = player.stagger.taken + tick.samount
            player.stagger.tickCount = player.stagger.tickCount + 1
            if player.stagger.tickMax < tick.samount then
                  player.stagger.tickMax = tick.samount
            end
            if isCurrent then
                  if player.stagger.lastTickTime then
                        local timeSinceLastTick = tick.timestamp - player.stagger.lastTickTime
                        player.stagger.duration = player.stagger.duration + timeSinceLastTick
                        if timeSinceLastTick > 60 then
                              printdebug(tick.dstName.."'s time since last tick: "..timeSinceLastTick.." (ignored)")
                        elseif timeSinceLastTick > 2 then
                              printdebug(tick.dstName.."'s time since last tick: "..timeSinceLastTick)
                              player.stagger.freezeDuration = player.stagger.freezeDuration + (timeSinceLastTick - 0.5)
                        end
                  end
                  if tick.remainingStagger > 0 then
                        player.stagger.lastTickTime = tick.timestamp
                        --printdebug(tick.dstName.."'s stagger tick for "..tick.samount.." ("..tick.remainingStagger.." remains)")
                  else
                        player.stagger.lastTickTime = nil
                        printdebug(tick.dstName.."'s stagger ended")
                  end
            end
      end
end

local purify = {}
local function logStaggerPurify(set, purify)
      local player = Skada:get_player(set, purify.srcGUID, purify.srcName)
      if player then
            player.stagger.purified = player.stagger.purified + purify.samount
            player.stagger.purifyCount = player.stagger.purifyCount + 1
            if player.stagger.purifyMax < purify.samount then
                  player.stagger.purifyMax = purify.samount
            end
      end
end

local function log_stabsorb(set,samount, dstGUID, dstName)
	-- Stagger absorbs
	local player = Skada:get_player(set, dstGUID, dstName)
	player.stagger.absorbed = player.stagger.absorbed + samount

	if set == Skada.current then
	    local stvar = player.stagger
	    stvar.stpool = stvar.stpool + samount
	    print('--',dstName,player.stagger.absorbed,stvar.stpool,UnitStagger(dstName))
	end

	--print(player.stagger.stpool,UnitStagger(dstName))
end

local function SpellAbsorbed(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
    local chk = ...
    local spellId, spellName, spellSchool, aGUID, aName, aFlags, aRaidFlags, aspellId, aspellName, aspellSchool, aAmount

    if type(chk) == "number" then
	-- Spell event
	spellId, spellName, spellSchool, aGUID, aName, aFlags, aRaidFlags, aspellId, aspellName, aspellSchool, aAmount = ...

	if aspellId ~= 115069 then
	    return
	end
	if aAmount then
	    log_stabsorb(Skada.current, aAmount,  dstGUID, dstName)
	    log_stabsorb(Skada.total, aAmount, dstGUID, dstName)
	end
    else
	-- Swing event
	aGUID, aName, aFlags, aRaidFlags, aspellId, aspellName, aspellSchool, aAmount = ...


	if aspellId ~= 115069 then
	    return
	end
	if aAmount then
	    log_stabsorb(Skada.current, aAmount, dstGUID, dstName)
	    log_stabsorb(Skada.total, aAmount, dstGUID, dstName)
	end
    end
end

last = 0
sttaken = 0
local function SpellDamage(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
    local spellId, spellName, spellSchool, samount, soverkill, sschool, sresisted, sblocked, sabsorbed, scritical, sglancing, scrushing = ...
    if spellId == 124255 then -- Stagger damage
	local player = Skada:get_player(Skada.current, dstGUID, dstName)
	stvar = player.stagger
	print(stvar.stpool)
	tick.timestamp = timestamp
	tick.dstGUID = dstGUID
	tick.dstName = dstName
	tick.samount = samount
	tick.remainingStagger = UnitStagger(dstName)
	logStaggerTick(Skada.current, tick, true)
	logStaggerTick(Skada.total, tick, false)

	stvar.stpool = stvar.stpool - samount

	local st = UnitStagger(srcName) 
	sttaken = sttaken + samount
	--prt = string.format('%f, %f, %f',tmp,samount, last-tmp)
	--prt = string.format('%d,%d,%d,%d',st,sttaken,stpury,stin)
	--print(prt)
	--print('--test',stin-st-sttaken-stpury)
	last = st
    end
end

stpury = 0
local function SpellCast(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
    local spellId, spellName, spellSchool = ...
    local player = Skada:get_player(Skada.current, srcGUID, srcName)
    local stvar = player.stagger
    if spellId == 119582 then -- Purifying brew
	local purifiedAmount = UnitStagger(srcName) * getPurifyPercent(srcGUID)
	printdebug(srcName.." purified "..purifiedAmount.." stagger")

	stvar.stpool = stvar.stpool * 0.56

	purify.srcGUID = srcGUID
	purify.srcName = srcName
	purify.samount = purifiedAmount
	logStaggerPurify(Skada.current, purify)
	logStaggerPurify(Skada.total, purify)
    elseif spellId == 115308 then
	  print('ironskin')
    end
end

function mod:OnEnable()
      mod.metadata = {showspots = false, click1 = modDetails}
      modDetails.metadata = {showspots = false, ordersort = true}
      
      Skada:RegisterForCL(SpellDamage, 'SPELL_PERIODIC_DAMAGE', {src_is_interesting = true, dst_is_interesting_nopets = false})
      Skada:RegisterForCL(SpellCast, 'SPELL_CAST_SUCCESS', {src_is_interesting = true, dst_is_interesting_nopets = false})
      Skada:RegisterForCL(SpellAbsorbed, 'SPELL_ABSORBED', {dst_is_interesting = true})

      Skada:AddMode(self, "Stagger")
end

function mod:OnDisable()
      Skada:RemoveMode(self)
end

function modDetails:Enter(win, id, label)
      modDetails.playerid = id
      modDetails.title = label.."'s Stagger"
end

function modDetails:Update(win, set)
      local player = Skada:find_player(set, self.playerid)
      if player then
            local playerStagger = player.stagger

	    local damageStaggered = playerStagger.taken + playerStagger.purified
            local staggerabsorbed = playerStagger.absorbed
            if damageStaggered == 0 then
                  return
            end
            local setDuration = getSetDuration(set)

            local datasetContext = {}

            local staggerabsorb = nextDataset(win, datasetContext)
            staggerabsorb.label = "Staggered absorbed"
            staggerabsorb.valuetext = Skada:FormatNumber(staggerabsorbed)
            staggerabsorb.value = 1

            local staggered = nextDataset(win, datasetContext)
            staggered.label = "Damage Staggered"
            staggered.valuetext = Skada:FormatNumber(damageStaggered)
            staggered.value = 1

            local staggerTaken = nextDataset(win, datasetContext)
            staggerTaken.label = "Taken"
            staggerTaken.valuetext = Skada:FormatNumber(playerStagger.taken)..(" (%02.1f%%)"):format(playerStagger.taken / damageStaggered * 100)
            staggerTaken.value = playerStagger.taken / damageStaggered

            if playerStagger.purifyCount > 0 then
                  local staggerPurified = nextDataset(win, datasetContext)
                  staggerPurified.label = "Purified"
                  staggerPurified.valuetext = Skada:FormatNumber(playerStagger.purified)..(" (%02.1f%%)"):format(playerStagger.purified / damageStaggered * 100)
                  staggerPurified.value = playerStagger.purified / damageStaggered

                  local staggerPurifiedAvg = nextDataset(win, datasetContext)
                  staggerPurifiedAvg.label = "Purified (average)"
                  staggerPurifiedAvg.valuetext = Skada:FormatNumber(playerStagger.purified / playerStagger.purifyCount).." ("..playerStagger.purifyCount.."x)"
                  staggerPurifiedAvg.value = (playerStagger.purified / playerStagger.purifyCount) / damageStaggered
            end

            if setDuration > 0 and playerStagger.duration > 0 then
                  local staggerDuration = nextDataset(win, datasetContext)
                  staggerDuration.label = "Stagger Duration"
                  staggerDuration.valuetext = ("%02.1fs"):format(playerStagger.duration)
                  staggerDuration.value = playerStagger.duration / setDuration
                  
                  if playerStagger.freezeDuration > 2 then
                        local freezeDuration = nextDataset(win, datasetContext)
                        freezeDuration.label = "Freeze Duration"
                        freezeDuration.valuetext = ("%02.1fs"):format(playerStagger.freezeDuration)..(" (%02.1f%%)"):format(playerStagger.freezeDuration / playerStagger.duration * 100)
                        freezeDuration.value = playerStagger.freezeDuration / setDuration
                  end
            end

            local tickMax = nextDataset(win, datasetContext)
            tickMax.label = "Tick (max)"
            tickMax.valuetext = Skada:FormatNumber(playerStagger.tickMax)
            tickMax.value = playerStagger.tickMax / damageStaggered

            win.metadata.maxvalue = 1
      end
end

function mod:AddPlayerAttributes(player, set)
      if not player.stagger then
            player.stagger = 
            {
		  purified_quicksip = 0,

		  absorbed = 0,
		  stpool = 0,

                  taken = 0,
                  purified = 0,
                  purifyCount = 0,
                  purifyMax = 0,

                  lastTickTime = nil,
                  tickMax = 0,
                  tickCount = 0,

                  duration = 0,
                  freezeDuration = 0,
            }
      end          
end

function mod:GetSetSummary(set)
      local totalPurified = 0
      for i, player in ipairs(set.players) do
            if player.stagger then
                  totalPurified = totalPurified + player.stagger.purified
            end
      end
      return "(purified) "..Skada:FormatNumber(totalPurified)
end

function mod:Update(win, set)
      local nr = 1
      local max = 0

      for i, player in ipairs(set.players) do
            if player.stagger then

                  local value = player.stagger.taken + player.stagger.purified
                  if value > 0 then
                        local d = win.dataset[nr] or {}
                        win.dataset[nr] = d

                        d.id = player.id
                        d.label = player.name
                        d.value = value
                        d.valuetext = Skada:FormatNumber(value)
                        d.class = player.class
                        d.role = player.role

                        if max < value then
                              max = value
                        end
                  end

                  nr = nr + 1
            end
      end
      win.metadata.maxvalue = max
end
