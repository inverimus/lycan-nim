-- RogueAssassination.lua
-- November 2022

if UnitClassBase( "player" ) ~= "ROGUE" then return end

local addon, ns = ...
local Hekili = _G[ addon ]
local class, state = Hekili.Class, Hekili.State
local PTR = ns.PTR

local format, wipe = string.format, table.wipe
local UA_GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID

local orderedPairs = ns.orderedPairs

local spec = Hekili:NewSpecialization( 259 )

spec:RegisterResource( Enum.PowerType.ComboPoints )
spec:RegisterResource( Enum.PowerType.Energy, {
    garrote_vim = {
        aura = "garrote",
        debuff = true,

        last = function ()
            local app = state.debuff.garrote.last_tick
            local exp = state.debuff.garrote.expires
            local tick = state.debuff.garrote.tick_time
            local t = state.query_time

            return min( exp, app + ( floor( ( t - app ) / tick ) * tick ) )
        end,

        stop = function ()
            return state.debuff.poisoned.down
        end,

        interval = function ()
            return state.debuff.garrote.tick_time
        end,

        value = 8
    },
    rupture_vim = {
        aura = "rupture",
        debuff = true,

        last = function ()
            local app = state.debuff.rupture.last_tick
            local exp = state.debuff.rupture.expires
            local tick = state.debuff.rupture.tick_time
            local t = state.query_time

            return min( exp, app + ( floor( ( t - app ) / tick ) * tick ) )
        end,

        stop = function ()
            return state.debuff.wound_poison_dot.down and state.debuff.deadly_poison_dot.down
        end,

        interval = function ()
            return state.debuff.rupture.tick_time
        end,

        value = 8
    },
    nothing_personal = {
        aura = "nothing_personal_regen",

        last = function ()
            local app = state.buff.nothing_personal_regen.applied
            local exp = state.buff.nothing_personal_regen.expires
            local tick = state.buff.nothing_personal_regen.tick_time
            local t = state.query_time

            return min( exp, app + ( floor( ( t - app ) / tick ) * tick ) )
        end,

        stop = function ()
            return state.buff.nothing_personal_regen.down
        end,

        interval = function ()
            return state.buff.nothing_personal_regen.tick_time
        end,

        value = 4
    }
} )


-- Talents
spec:RegisterTalents( {
    -- Rogue Talents
    acrobatic_strikes      = { 90752, 196924, 1 }, -- Increases the range of your melee attacks by $s1 yds.
    airborne_irritant      = { 90741, 200733, 1 }, -- Blind has $s1% reduced cooldown, $s2% reduced duration, and applies to all nearby enemies.
    alacrity               = { 90751, 193539, 2 }, -- Your finishing moves have a $s2% chance per combo point to grant $193538s1% Haste for $193538d, stacking up to $193538u times.
    atrophic_poison        = { 90763, 381637, 1 }, -- Coats your weapons with a Non-Lethal Poison that lasts for $d. Each strike has a $h% chance of poisoning the enemy, reducing their damage by ${$392388s1*-1}.1% for $392388d.
    blackjack              = { 90686, 379005, 1 }, -- Enemies have $394119s1% reduced damage and healing for $394119d after Blind or Sap's effect on them ends.
    blind                  = { 90684, 2094  , 1 }, -- Blinds $?a200733[all enemies near ][]the target, causing $?a200733[them][it] to wander disoriented for $d. Damage will interrupt the effect. Limit 1.
    cheat_death            = { 90742, 31230 , 1 }, -- Fatal attacks instead reduce you to $s2% of your maximum health. For $45182d afterward, you take $45182s1% reduced damage. Cannot trigger more often than once per $45181d.
    cloak_of_shadows       = { 90697, 31224 , 1 }, -- Provides a moment of magic immunity, instantly removing all harmful spell effects. The cloak lingers, causing you to resist harmful spells for $d.
    cold_blood             = { 90748, 382245, 1 }, -- Increases the critical strike chance of your next damaging ability by $s1%.
    deadened_nerves        = { 90743, 231719, 1 }, -- Physical damage taken reduced by $s1%.;
    deadly_precision       = { 90760, 381542, 1 }, -- Increases the critical strike chance of your attacks that generate combo points by $s1%.
    deeper_stratagem       = { 90750, 193531, 1 }, -- Gain $s1 additional max combo point.; Your finishing moves that consume more than $s3 combo points have increased effects, and your finishing moves deal $s4% increased damage.
    echoing_reprimand      = { 90639, 385616, 1 }, -- Deal $s1 Arcane damage to an enemy, extracting their anima to Animacharge a combo point for $323558d.; Damaging finishing moves that consume the same number of combo points as your Animacharge function as if they consumed $s2 combo points.; Awards $s3 combo $lpoint:points;.;
    elusiveness            = { 90742, 79008 , 1 }, -- Evasion also reduces damage taken by $s2%, and Feint also reduces non-area-of-effect damage taken by $s1%.
    evasion                = { 90764, 5277  , 1 }, -- Increases your dodge chance by ${$s1/2}% for $d.$?a344363[ Dodging an attack while Evasion is active will trigger Mastery: Main Gauche.][]
    featherfoot            = { 94563, 423683, 1 }, -- Sprint increases movement speed by an additional $s1% and has ${$s2/1000} sec increased duration.
    fleet_footed           = { 90762, 378813, 1 }, -- Movement speed increased by $s1%.
    gouge                  = { 90741, 1776  , 1 }, -- Gouges the eyes of an enemy target, incapacitating for $d. Damage will interrupt the effect.; Must be in front of your target.; Awards $s2 combo $lpoint:points;.
    graceful_guile         = { 94562, 423647, 1 }, -- Feint has $m1 additional $Lcharge:charges;.;
    improved_ambush        = { 90692, 381620, 1 }, -- $?s185438[Shadowstrike][Ambush] generates $s1 additional combo point.
    improved_sprint        = { 90746, 231691, 1 }, -- Reduces the cooldown of Sprint by ${$m1/-1000} sec.
    improved_wound_poison  = { 90637, 319066, 1 }, -- Wound Poison can now stack $s1 additional times.
    iron_stomach           = { 90744, 193546, 1 }, -- Increases the healing you receive from Crimson Vial, healing potions, and healthstones by $s1%.
    leeching_poison        = { 90758, 280716, 1 }, -- Adds a Leeching effect to your Lethal poisons, granting you $108211s1% Leech.
    lethality              = { 90749, 382238, 2 }, -- Critical strike chance increased by $s1%. Critical strike damage bonus of your attacks that generate combo points increased by $s2%.
    marked_for_death       = { 90750, 137619, 1 }, -- Marks the target, instantly granting full combo points and increasing the damage of your finishing moves by $s1% for $d. Cooldown resets if the target dies during effect.
    master_poisoner        = { 90636, 378436, 1 }, -- Increases the non-damaging effects of your weapon poisons by $s1%.
    nightstalker           = { 90693, 14062 , 2 }, -- While Stealth$?c3[ or Shadow Dance][] is active, your abilities deal $s1% more damage.
    nimble_fingers         = { 90745, 378427, 1 }, -- Energy cost of Feint and Crimson Vial reduced by $s1.
    numbing_poison         = { 90763, 5761  , 1 }, -- Coats your weapons with a Non-Lethal Poison that lasts for $d.  Each strike has a $5761h% chance of poisoning the enemy, clouding their mind and slowing their attack and casting speed by $5760s1% for $5760d.
    recuperator            = { 90640, 378996, 1 }, -- Slice and Dice heals you for up to $s1% of your maximum health per 2 sec.
    resounding_clarity     = { 90638, 381622, 1 }, -- Echoing Reprimand Animacharges $m1 additional combo $Lpoint:points;.
    reverberation          = { 90638, 394332, 1 }, -- Echoing Reprimand's damage is increased by $s1%.
    rushed_setup           = { 90754, 378803, 1 }, -- The Energy costs of Kidney Shot, Cheap Shot, Sap, and Distract are reduced by $s1%.
    shadow_dance           = { 90689, 185313, 1 }, -- Description not found.
    shadowrunner           = { 90687, 378807, 1 }, -- While Stealth or Shadow Dance is active, you move $s1% faster.
    shadowstep             = { 90695, 36554 , 1 }, -- Description not found.
    shiv                   = { 90740, 5938  , 1 }, -- Attack with your $?s319032[poisoned blades][off-hand], dealing $sw1 Physical damage, dispelling all enrage effects and applying a concentrated form of your $?a3408[Crippling Poison, reducing movement speed by $115196s1% for $115196d.]?a5761[Numbing Poison, reducing casting speed by $359078s1% for $359078d.][]$?(!a3408&!a5761)[active Non-Lethal poison.][]$?(a319032&a400783)[; Your Nature and Bleed ]?a319032[; Your Nature ]?a400783[; Your Bleed ][]$?(a400783|a319032)[damage done to the target is increased by $319504s1% for $319504d.][]$?a354124[ The target's healing received is reduced by $354124S1% for $319504d.][]; Awards $s3 combo $lpoint:points;.
    soothing_darkness      = { 90691, 393970, 1 }, -- You are healed for ${$393971s1*($393971d/$393971t)}% of your maximum health over $393971d after gaining Vanish or Shadow Dance.
    stillshroud            = { 94561, 423662, 1 }, -- Shroud of Concealment has $s1% reduced cooldown.;
    subterfuge             = { 90688, 108208, 1 }, -- Your abilities requiring Stealth can still be used for ${$s2/1000} sec after Stealth breaks.
    superior_mixture       = { 94567, 423701, 1 }, -- Crippling Poison reduces movement speed by an additional $s1%.
    thistle_tea            = { 90756, 381623, 1 }, -- Restore $s1 Energy. Mastery increased by ${$s2*$mas}.1% for $d.
    tight_spender          = { 90692, 381621, 1 }, -- Energy cost of finishing moves reduced by $s1%.
    tricks_of_the_trade    = { 90686, 57934 , 1 }, -- $?s221622[Increases the target's damage by $221622m1%, and redirects][Redirects] all threat you cause to the targeted party or raid member, beginning with your next damaging attack within the next $d and lasting $59628d.
    unbreakable_stride     = { 90747, 400804, 1 }, -- Reduces the duration of movement slowing effects $s1%.
    vigor                  = { 90759, 14983 , 2 }, -- Increases your maximum Energy by $s1 and Energy regeneration by $s2%.
    virulent_poisons       = { 90760, 381543, 1 }, -- Increases the damage of your weapon poisons by $s1%.

    -- Assassination Talents
    amplifying_poison      = { 90621, 381664, 1 }, -- Coats your weapons with a Lethal Poison that lasts for $d. Each strike has a $h% chance to poison the enemy, dealing $383414s1 Nature damage and applying Amplifying Poison for $383414d. Envenom can consume $s2 stacks of Amplifying Poison to deal $s1% increased damage. Max $383414u stacks.
    arterial_precision     = { 90784, 400783, 1 }, -- Shiv strikes ${$s2-1} additional nearby enemies and increases your Bleed damage done to affected targets by $s1% for $319504d.
    blindside              = { 90786, 328085, 1 }, -- Ambush and Mutilate have a $s1% chance to make your next Ambush free and usable without Stealth. Chance increased to $s2% if the target is under $s3% health.
    bloody_mess            = { 90625, 381626, 1 }, -- Garrote and Rupture damage increased by $s1%.
    caustic_spatter        = { 94556, 421975, 1 }, -- Using Mutilate on a target afflicted by your Rupture and Deadly Poison applies Caustic Spatter for $421976d. Limit 1.; Caustic Spatter causes $421976s1% of your Poison damage dealt to splash onto other nearby enemies, reduced beyond $421976s2 targets.
    crimson_tempest        = { 90632, 121411, 1 }, -- Finishing move that slashes all enemies within $A1 yards, causing victims to bleed. Lasts longer per combo point.; Deals extra damage when multiple enemies are afflicted, increasing by $s4% per target, up to ${$s4*5}%.; Deals reduced damage beyond $s3 targets.;    1 point  : ${$o1*4} over ${$d+(2*1)} sec;    2 points: ${$o1*5} over ${$d+(2*2)} sec;    3 points: ${$o1*6} over ${$d+(2*3)} sec;    4 points: ${$o1*7} over ${$d+(2*4)} sec;    5 points: ${$o1*8} over ${$d+(2*5)} sec$?s193531[;    6 points: ${$o1*9} over ${$d+(2*6)} sec][]
    cut_to_the_chase       = { 94557, 51667 , 1 }, -- Envenom extends the duration of Slice and Dice by up to $s1 sec per combo point spent.
    dashing_scoundrel      = { 90766, 381797, 1 }, -- Envenom also increases the critical strike chance of your weapon poisons by $s1%, and their critical strikes generate $s2 Energy.
    deadly_poison          = { 90783, 2823  , 1 }, -- Coats your weapons with a Lethal Poison that lasts for $d. Each strike has a $h% chance to poison the enemy for ${$2818m1*$2818d/$2818t1} Nature damage over $2818d. Subsequent poison applications will instantly deal $113780s1 Nature damage.
    deathmark              = { 90769, 360194, 1 }, -- Carve a deathmark into an enemy, dealing $o1 Bleed damage over $d. While marked your Garrote, Rupture, and Lethal poisons applied to the target are duplicated, dealing $?a134735[${100+$394331s1+$394331s3}%][${100+$394331s1}%] of normal damage.
    doomblade              = { 90777, 381673, 1 }, -- Mutilate deals an additional $s1% Bleed damage over ${$381672d+2} sec.
    dragontempered_blades  = { 94553, 381801, 1 }, -- You may apply $s1 additional Lethal and Non-Lethal Poison to your weapons, but they have $s2% less application chance.
    fatal_concoction       = { 90626, 392384, 1 }, -- Increases the damage of your weapon poisons by $s1%.
    flying_daggers         = { 94554, 381631, 1 }, -- Fan of Knives has its radius increased to $s4 yds, deals $s5% more damage, and an additional $s1% when striking $s2 or more targets.
    improved_garrote       = { 90780, 381632, 1 }, -- Garrote deals $s1% increased damage and has no cooldown when used from Stealth and for $392401d after breaking Stealth.
    improved_poisons       = { 90634, 381624, 1 }, -- Increases the application chance of your weapon poisons by $s1%.
    improved_shiv          = { 90628, 319032, 1 }, -- Shiv now also increases your Nature damage done against the target by $319504s1% for $319504d.
    indiscriminate_carnage = { 90774, 381802, 1 }, -- Garrote and Rupture apply to ${$m1-1} additional nearby $Lenemy:enemies; when used from Stealth and for $385747d after breaking Stealth.
    intent_to_kill         = { 94555, 381630, 1 }, -- Shadowstep's cooldown is reduced by $s1% when used on a target afflicted by your Garrote.
    internal_bleeding      = { 94556, 381627, 1 }, -- Kidney Shot and Rupture also apply Internal Bleeding, dealing up to ${5*$154953o1} Bleed damage over $154953d, based on combo points spent.
    iron_wire              = { 94555, 196861, 1 }, -- Garrote silences the target for $s2 sec when used from Stealth.; Enemies silenced by Garrote deal $256148s1% reduced damage for $256148d.
    kingsbane              = { 94552, 385627, 1 }, -- Release a lethal poison from your weapons and inject it into your target, dealing $s2 Nature damage instantly and an additional $o4 Nature damage over $d. ; Each time you apply a Lethal Poison to a target affected by Kingsbane, Kingsbane damage increases by $394095s1%.; Awards $s6 combo $lpoint:points;.
    lethal_dose            = { 90624, 381640, 2 }, -- Your weapon poisons, Nature damage over time, and Bleed abilities deal $s1% increased damage to targets for each weapon poison, Nature damage over time, and Bleed effect on them.
    lightweight_shiv       = { 90633, 394983, 1 }, -- Shiv deals $s2% increased damage and has $m1 additional $Lcharge:charges;.
    master_assassin        = { 90623, 255989, 1 }, -- Critical strike chance increased by $256735s1% while Stealthed and for $s1 sec after breaking Stealth.
    path_of_blood          = { 94536, 423054, 1 }, -- Increases maximum Energy by $s1.
    poison_bomb            = { 90767, 255544, 2 }, -- Envenom has a $<chance>% chance per combo point spent to smash a vial of poison at the target's location, creating a pool of acidic death that deals ${$255546s1*$s2} Nature damage over $255545d to all enemies within it.
    sanguine_blades        = { 90779, 200806, 1 }, -- While above $s1% of maximum Energy your Garrote, Rupture, and Crimson Tempest consume $s2 Energy to duplicate $s3% of any damage dealt.
    scent_of_blood         = { 90775, 381799, 2 }, -- Each enemy afflicted by your Rupture increases your Agility by $S1%, up to a maximum of $394080u%.
    seal_fate              = { 90757, 14190 , 1 }, -- Critical strikes with attacks that generate combo points grant an additional combo point per critical strike.
    sepsis                 = { 90622, 385408, 1 }, -- Infect the target's blood, dealing $o1 Nature damage over $d and gaining $s6 use of any Stealth ability. If the target survives its full duration, they suffer an additional $394026s1 damage and you gain $s6 additional use of any Stealth ability for $375939d.; Cooldown reduced by $s3 sec if Sepsis does not last its full duration.; Awards $s7 combo $lpoint:points;.
    serrated_bone_spike    = { 90622, 385424, 1 }, -- Embed a bone spike in the target, dealing $s1 Physical damage and $394036s1 Bleed damage every $394036t1 sec until they die or leave combat. ; Refunds a charge when target dies.; Awards 1 combo point plus 1 additional per active bone spike.
    shrouded_suffocation   = { 90776, 385478, 1 }, -- Garrote damage increased by $s1%. Garrote generates $s2 additional combo points when used from Stealth.
    sudden_demise          = { 94551, 423136, 1 }, -- Bleed damage increased by $s1%.; Targets below $s3% health instantly bleed out and take fatal damage when the remaining Bleed damage you would deal to them exceeds $s2% of their remaining health.
    systemic_failure       = { 90771, 381652, 1 }, -- Garrote increases the damage of Ambush and Mutilate on the target by $s1%.
    thrown_precision       = { 90630, 381629, 1 }, -- Fan of Knives has $s2% increased critical strike chance and its critical strikes always apply your weapon poisons.
    tiny_toxic_blade       = { 90770, 381800, 1 }, -- Shiv deals $s1% increased damage and no longer costs Energy.
    twist_the_knife        = { 90768, 381669, 1 }, -- Envenom duration increased by ${$s1/1000} sec.
    venom_rush             = { 94554, 152152, 1 }, -- Ambush and Mutilate refund $256522s1 Energy when used against a poisoned target.
    venomous_wounds        = { 90635, 79134 , 1 }, -- You regain $s2 Energy each time your Garrote or Rupture deal Bleed damage to a poisoned target.; If an enemy dies while afflicted by your Rupture, you regain energy based on its remaining duration.
    vicious_venoms         = { 90772, 381634, 2 }, -- Ambush and Mutilate cost $s2 more Energy and deal $s1% additional damage as Nature.
    zoldyck_recipe         = { 90785, 381798, 2 }, -- Your Poisons and Bleeds deal $s1% increased damage to targets below $s2% health.
} )

-- PvP Talents
spec:RegisterPvpTalents( {
    control_is_king    = 5530, -- (354406) Cheap Shot grants Slice and Dice for $s1 sec and Kidney Shot restores $s2 Energy per combo point spent.
    creeping_venom     = 141 , -- (354895) Your Envenom applies Creeping Venom, reducing the target's movement speed by $354896s1% for $354896d.  Creeping Venom is reapplied when the target moves. Max $354896u stacks.
    dagger_in_the_dark = 5550, -- (198675) Each second while Stealth is active, nearby enemies within $198688A1 yards take an additional $198688s1% damage from you for $198688d. Stacks up to $198688u times.
    death_from_above   = 3479, -- (269513) Finishing move that empowers your weapons with energy to performs a deadly attack.; You leap into the air and $?s32645[Envenom]?s2098[Dispatch][Eviscerate] your target on the way back down, with such force that it has a $269512s2% stronger effect.
    dismantle          = 5405, -- (207777) Disarm the enemy, preventing the use of any weapons or shield for $d.
    hemotoxin          = 830 , -- (354124) Shiv also reduces the target's healing received by $S1% for $319504d.
    maneuverability    = 3448, -- (197000) Sprint has $s1% reduced cooldown and $s2% reduced duration.
    smoke_bomb         = 3480, -- (212182) Creates a cloud of thick smoke in an $m2 yard radius around the Rogue for $d. Enemies are unable to target into or out of the smoke cloud.
    system_shock       = 147 , -- (198145) Casting Envenom with at least 5 combo points on a target afflicted by your Garrote, Rupture, and lethal poison deals $198222s1 Nature damage, and reduces their movement speed by $198222m2% for $198222d.
    thick_as_thieves   = 5408, -- (221622) Tricks of the Trade now increases the friendly target's damage by $m1% for $59628d.
    veil_of_midnight   = 5517, -- (198952) Cloak of Shadows now also removes harmful physical effects and increases dodge chance by ${-$31224m1/2}%.
} )


spec:RegisterStateExpr( "cp_max_spend", function ()
    return combo_points.max
end )

spec:RegisterStateExpr( "effective_combo_points", function ()
    local c = combo_points.current or 0
    if not talent.echoing_reprimand.enabled and not covenant.kyrian then return c end
    if c < 2 or c > 5 then return c end
    if buff[ "echoing_reprimand_" .. c ].up then return 7 end
    return c
end )


local stealth = {
    normal = { "stealth" },
    vanish = { "vanish" },
    subterfuge = { "subterfuge" },
    shadow_dance = { "shadow_dance" },
    shadowmeld = { "shadowmeld" },
    sepsis = { "sepsis_buff" },

    improved_garrote = { "improved_garrote", "sepsis_buff" },

    basic = { "stealth", "vanish" },
    mantle = { "stealth", "vanish" },
    rogue = { "stealth", "vanish", "subterfuge", "shadow_dance" },
    ambush = { "stealth", "vanish", "subterfuge", "shadow_dance", "sepsis_buff" },

    -- SimC includes Improved Garrote in stealthed.all, but it feels misleading.
    all = { "stealth", "vanish", "shadowmeld", "subterfuge", "shadow_dance", "sepsis_buff", "improved_garrote" },
}


spec:RegisterStateTable( "stealthed", setmetatable( {}, {
    __index = function( t, k )
        local kRemains = k == "remains" and "all" or k:match( "^(.+)_remains$" )

        if kRemains then
            local category = stealth[ kRemains ]
            if not category then return 0 end

            local remains = 0
            for _, aura in ipairs( category ) do
                remains = max( remains, buff[ aura ].remains )
            end

            return remains
        end

        local category = stealth[ k ]
        if not category then return false end

        for _, aura in ipairs( category ) do
            if buff[ aura ].up then return true end
        end

        return false
    end,
} ) )


spec:RegisterStateExpr( "master_assassin_remains", function ()
    if not ( talent.master_assassin.enabled or legendary.mark_of_the_master_assassin.enabled ) then return 0 end
    if stealthed.mantle then return cooldown.global_cooldown.remains + ( legendary.mark_of_the_master_assassin.enabled and 4 or 3 )
    elseif buff.master_assassin_any.up then return buff.master_assassin_any.remains end
    return 0
end )

local stealth_dropped = 0

local function isStealthed()
    return ( UA_GetPlayerAuraBySpellID( 1784 ) or UA_GetPlayerAuraBySpellID( 115191 ) or UA_GetPlayerAuraBySpellID( 115192 ) or UA_GetPlayerAuraBySpellID( 11327 ) or GetTime() - stealth_dropped < 0.2 )
end

local calculate_multiplier = setfenv( function( spellID )
    local mult = 1

    if talent.nightstalker.enabled and isStealthed() then
        mult = mult * 1.08
    end

    if spellID == 703 and talent.improved_garrote.enabled and ( UA_GetPlayerAuraBySpellID( 375939 ) or UA_GetPlayerAuraBySpellID( 347037 ) or UA_GetPlayerAuraBySpellID( 392401 ) or UA_GetPlayerAuraBySpellID( 392403 ) ) then
        mult = mult * 1.5
    end

    return mult
end, state )


-- Bleed Modifiers
local tracked_bleeds = {}

local function NewBleed( key, spellID )
    tracked_bleeds[ key ] = {
        id = spellID,
        exsanguinate = {},
        rate = {},
        last_tick = {},
        haste = {}
    }

    tracked_bleeds[ spellID ] = tracked_bleeds[ key ]
end

local function ApplyBleed( key, target, exsanguinate )
    local bleed = tracked_bleeds[ key ]

    bleed.rate[ target ]         = 1 + ( exsanguinate and 1 or 0 )
    bleed.last_tick[ target ]    = GetTime()
    bleed.exsanguinate[ target ] = exsanguinate
    bleed.haste[ target ]        = 100 + GetHaste()
end

local function UpdateBleed( key, target, exsanguinate )
    local bleed = tracked_bleeds[ key ]

    if not bleed.rate[ target ] then
        return
    end

    if exsanguinate and not bleed.exsanguinate[ target ] then
        bleed.rate[ target ] = bleed.rate[ target ] + 1
        bleed.exsanguinate[ target ] = true
    end

    bleed.haste[ target ] = 100 + GetHaste()
end

local function UpdateBleedTick( key, target, time )
    local bleed = tracked_bleeds[ key ]

    if not bleed.rate[ target ] then return end

    bleed.last_tick[ target ] = time or GetTime()
end

local function RemoveBleed( key, target )
    local bleed = tracked_bleeds[ key ]

    bleed.rate[ target ]         = nil
    bleed.last_tick[ target ]    = nil
    bleed.exsanguinate[ target ] = nil
    bleed.haste[ target ]        = nil
end

local function GetExsanguinateRate( aura, target )
    return tracked_bleeds[ aura ] and tracked_bleeds[ aura ].rate[ target ] or 1
end

NewBleed( "garrote", 703 )
NewBleed( "garrote_deathmark", 360830 )
NewBleed( "rupture", 1943 )
NewBleed( "rupture_deathmark", 360826 )
NewBleed( "crimson_tempest", 121411 )
NewBleed( "internal_bleeding", 154904 )

NewBleed( "deadly_poison_dot", 2823 )
NewBleed( "deadly_poison_dot_deathmark", 394324 )
NewBleed( "sepsis", 328305 )
NewBleed( "serrated_bone_spike", 324073 )

local application_events = {
    SPELL_AURA_APPLIED      = true,
    SPELL_AURA_APPLIED_DOSE = true,
    SPELL_AURA_REFRESH      = true,
}

local removal_events = {
    SPELL_AURA_REMOVED      = true,
    SPELL_AURA_BROKEN       = true,
    SPELL_AURA_BROKEN_SPELL = true,
}

local stealth_spells = {
    [1784  ] = true,
    [115191] = true,
}

local tick_events = {
    SPELL_PERIODIC_DAMAGE   = true,
}

local death_events = {
    UNIT_DIED               = true,
    UNIT_DESTROYED          = true,
    UNIT_DISSIPATES         = true,
    PARTY_KILL              = true,
    SPELL_INSTAKILL         = true,
}

spec:RegisterCombatLogEvent( function( _, subtype, _,  sourceGUID, sourceName, _, _, destGUID, destName, destFlags, _, spellID, spellName )
    if sourceGUID == state.GUID then
        if removal_events[ subtype ] then
            if stealth_spells[ spellID ] then
                stealth_dropped = GetTime()
                return
            end
        end

        if tracked_bleeds[ spellID ] then
            if application_events[ subtype ] then
                -- TODO:  Modernize basic debuff tracking and snapshotting.
                ns.saveDebuffModifier( spellID, calculate_multiplier( spellID ) )
                ns.trackDebuff( spellID, destGUID, GetTime(), true )

                ApplyBleed( spellID, destGUID )
                return
            end

            if tick_events[ subtype ] then
                UpdateBleedTick( spellID, destGUID, GetTime() )
                return
            end

            if removal_events[ subtype ] then
                RemoveBleed( spellID, destGUID )
                return
            end
        end

        -- Exsanguinate was used.
        if subtype == "SPELL_CAST_SUCCESS" and spellID == 200806 then
            UpdateBleed( "garrote", destGUID, true )
            UpdateBleed( "rupture", destGUID, true )
            UpdateBleed( "crimson_tempest", destGUID, true )
            UpdateBleed( "internal_bleeding", destGUID, true )
            return
        end
    end

    if death_events[ subtype ] then
        --[[ TODO: Deal with annoying Training Dummy resets.

        RemoveBleed( "garrote", destGUID )
        RemoveBleed( "rupture", destGUID )
        RemoveBleed( "crimson_tempest", destGUID )
        RemoveBleed( "internal_bleeding", destGUID )

        RemoveBleed( "deadly_poison_dot", destGUID )
        RemoveBleed( "sepsis", destGUID )
        RemoveBleed( "serrated_bone_spike", destGUID ) ]]
    end
end, false )


local energySpent = 0

local ENERGY = Enum.PowerType.Energy
local lastEnergy = -1

spec:RegisterUnitEvent( "UNIT_POWER_FREQUENT", "player", nil, function( event, unit, powerType )
    if powerType == "ENERGY" then
        local current = UnitPower( "player", ENERGY )

        if current < lastEnergy then
            energySpent = ( energySpent + lastEnergy - current ) % 30
        end

        lastEnergy = current
        return
    elseif powerType == "COMBO_POINTS" then
        Hekili:ForceUpdate( powerType, true )
    end
end )

spec:RegisterCycle( function ()
    if this_action == "marked_for_death" then
        if cycle_enemies == 1 or active_dot.marked_for_death >= cycle_enemies then return end -- As far as we can tell, MfD is on everything we care about, so we don't cycle.
        if debuff.marked_for_death.up then return "cycle" end -- If current target already has MfD, cycle.
        if target.time_to_die > 3 + Hekili:GetLowestTTD() and active_dot.marked_for_death == 0 then return "cycle" end -- If our target isn't lowest TTD, and we don't have to worry that the lowest TTD target is already MfD'd, cycle.
    end
end )

spec:RegisterStateExpr( "energy_spent", function ()
    return energySpent
end )

spec:RegisterHook( "spend", function( amt, resource )
    if legendary.duskwalkers_patch.enabled and cooldown.vendetta.remains > 0 and resource == "energy" and amt > 0 then
        energy_spent = energy_spent + amt
        local reduction = floor( energy_spent / 30 )
        energy_spent = energy_spent % 30

        if reduction > 0 then
            reduceCooldown( "vendetta", reduction )
        end
    end

    if set_bonus.tier31_4pc > 0 and resource == "energy" and amt > 9 then
        addStack( "natureblight", 6, floor( amt / 10 ) )
    end

    if resource == "combo_points" then
        if buff.flagellation_buff.up then
            if legendary.obedience.enabled then
                reduceCooldown( "flagellation", amt )
            end

            if debuff.flagellation.up then
                stat.mod_haste_pct = stat.mod_haste_pct + amt
            end
        end

        if amt > 0 and talent.elaborate_planning.enabled then
            applyBuff( "elaborate_planning" )
        end

        if amt > 1 and amt < 6 and action.echoing_reprimand.known then
            local er = "echoing_reprimand_" .. amt
            if buff[ er ].up then removeBuff( er ) end
        end
    end
end )


spec:RegisterStateExpr( "persistent_multiplier", function ()
    if not this_action then return 1 end
    local mult = 1

    if buff.stealth.up or buff.subterfuge.up then
        if talent.nightstalker.enabled then
            mult = mult * 1.08
        end
    end

    if this_action == "garrote" and ( buff.improved_garrote.up or talent.improved_garrote.enabled and buff.sepsis_buff.up ) then mult = mult * 1.5 end

    return mult
end )




local exsanguinated_spells = {
    garrote = "garrote",
    garrote_deathmark = "garrote_deathmark",
    kidney_shot = "internal_bleeding",
    rupture = "rupture",
    rupture_deathmark = "rupture_deathmark",
    crimson_tempest = "crimson_tempest",

    deadly_poison = "deadly_poison_dot",
    sepsis = "sepsis",
    serrated_bone_spike = "serrated_bone_spike",
}

local true_exsanguinated = {
    "garrote",
    "garrote_deathmark",
    "internal_bleeding",
    "rupture",
    "rupture_deathmark",
    "crimson_tempest",
}

spec:RegisterStateExpr( "exsanguinated", function ()
    local aura = this_action and exsanguinated_spells[ this_action ]
    aura = aura and debuff[ aura ]

    if not aura or not aura.up then return false end
    return aura.exsanguinated_rate > 1
end )

spec:RegisterStateExpr( "will_lose_exsanguinate", function ()
    local aura = this_action and exsanguinated_spells[ this_action ]
    aura = aura and debuff[ aura ]

    if not aura or not aura.up then return false end
    return aura.exsanguinated_rate > 1
end )

spec:RegisterStateExpr( "exsanguinated_rate", function ()
    local aura = this_action and exsanguinated_spells[ this_action ]
    aura = aura and debuff[ aura ]

    if not aura or not aura.up then return 1 end
    return aura.exsanguinated_rate
end )


-- Enemies with either Deadly Poison or Wound Poison applied.
spec:RegisterStateExpr( "poisoned_enemies", function ()
    return ns.countUnitsWithDebuffs( "deadly_poison_dot", "wound_poison_dot", "crippling_poison_dot", "amplifying_poison_dot" )
end )

spec:RegisterStateExpr( "poison_remains", function ()
    return debuff.lethal_poison.remains
end )


local valid_bleeds = { "garrote", "internal_bleeding", "rupture", "crimson_tempest", "mutilated_flesh", "serrated_bone_spike" }

-- Count of bleeds on targets.
spec:RegisterStateExpr( "bleeds", function ()
    local n = 0

    for _, aura in pairs( valid_bleeds ) do
        if debuff[ aura ].up then
            n = n + 1
        end
    end

    return n
end )

-- Count of bleeds on all poisoned (Deadly/Wound) targets.
spec:RegisterStateExpr( "poisoned_bleeds", function ()
    return ns.conditionalDebuffCount( "deadly_poison_dot", "wound_poison_dot", "amplifying_poison_dot", "garrote", "internal_bleeding", "rupture" )
end )


spec:RegisterStateExpr( "ss_buffed", function ()
    return false
end )

spec:RegisterStateExpr( "non_ss_buffed_targets", function ()
    return active_enemies
    --[[ local count = ( debuff.garrote.down or not debuff.garrote.exsanguinated ) and 1 or 0

    for guid, counted in ns.iterateTargets() do
        if guid ~= target.unit and counted and ( not ns.actorHasDebuff( guid, 703 ) or not ssG[ guid ] ) then
            count = count + 1
        end
    end

    return count ]]
end )

spec:RegisterStateExpr( "ss_buffed_targets_above_pandemic", function ()
    --[[ if not debuff.garrote.refreshable and debuff.garrote.ss_buffed then
        return 1
    end ]]
    return 0
end )



spec:RegisterStateExpr( "pmultiplier", function ()
    if not this_action then return 0 end

    local a = class.abilities[ this_action ]
    if not a then return 0 end

    local aura = a.aura or this_action
    if not aura then return 0 end

    if debuff[ aura ] and debuff[ aura ].up then
        return debuff[ aura ].pmultiplier or 1
    end

    return 0
end )

spec:RegisterStateExpr( "improved_garrote_remains", function()
    if buff.improved_garrote_buff.up then
        if buff.shadow_dance.up then return buff.shadow_dance.remains end
        return buff.improved_garrote_buff.remains
    end
    return 0
end )

spec:RegisterStateExpr( "priority_rotation", function ()
    return settings.priority_rotation
end )


local ExpireSepsis = setfenv( function ()
    applyBuff( "sepsis_buff" )

    if legendary.toxic_onslaught.enabled then
        applyBuff( "adrenaline_rush", 10 )
        applyBuff( "shadow_blades", 10 )
    end
end, state )


-- Tier 31
spec:RegisterGear( "tier31", 207234, 207235, 207236, 207237, 207239 )
-- 422905: Rogue Assassination 10.2 Class Set 2pc
-- Each 10 energy you spend grants Natureblight, granting 1.0% attack speed and 1.0% Nature Damage for 6 sec. Multiple instances of Natureblight may overlap, up to 12.
-- TODO: Each application is actually individual, so I should track this differently.
spec:RegisterAura( "natureblight", {
    id = 426568,
    duration = 6,
    max_stack = 12
} )

-- Tier 30
spec:RegisterGear( "tier30", 202500, 202498, 202497, 202496, 202495 )
spec:RegisterAuras( {
    poisoned_edges = {
        id = 409587,
        duration = 30,
        max_stack = 1
    }
} )

local ExpireDeathmarkT30 = setfenv( function ()
    applyBuff( "poisoned_edges" )
end, state )


-- Tier Set
spec:RegisterGear( "tier29", 200372, 200374, 200369, 200371, 200373 )
spec:RegisterAura( "septic_wounds", {
    id = 394845,
    duration = 8,
    max_stack = 5
} )


local kingsbaneReady = false

spec:RegisterHook( "reset_precast", function ()
    local status = "Bleed Snapshots       Remains  Multip.  RateMod  Exsang.\n"
    for _, aura in orderedPairs( exsanguinated_spells ) do
        local d = debuff[ aura ]
        d.pmultiplier = nil
        d.exsanguinated_rate = nil
        d.exsanguinated = nil

        if Hekili.ActiveDebug then
            status = format( "%s%-20s  %7.2f  %7.2f  %7.2f  %7s\n", status, aura, d.remains, d.pmultiplier, d.exsanguinated_rate, d.exsanguinated and "true" or "false" )
        end
    end

    if Hekili.ActiveDebug then Hekili:Debug( status ) end

    if debuff.sepsis.up then
        state:QueueAuraExpiration( "sepsis", ExpireSepsis, debuff.sepsis.expires )
    end

    if set_bonus.tier30_4pc > 0 and debuff.deathmark.up then
        state:QueueAuraExpiration( "deathmark", ExpireDeathmarkT30, debuff.deathmark.expires )
    end

    class.abilities.apply_poison = class.abilities[ action.apply_poison_actual.next_poison ]

    if buff.cold_blood.up then setCooldown( "cold_blood", action.cold_blood.cooldown ) end

    if buff.vanish.up then applyBuff( "stealth" ) end
    -- Pad Improved Garrote's expiry in order to avoid ruining your snapshot.
    if buff.improved_garrote.up then buff.improved_garrote.expires = buff.improved_garrote.expires - 0.05 end

    if buff.indiscriminate_carnage.up then
        if action.garrote.lastCast < action.indiscriminate_carnage.lastCast then applyBuff( "indiscriminate_carnage_garrote" ) end
        if action.rupture.lastCast < action.indiscriminate_carnage.lastCast then applyBuff( "indiscriminate_carnage_rupture" ) end
    end

    if not kingsbaneReady then
        rawset( buff, "kingsbane", buff.kingsbane_buff )
        rawset( debuff, "kingsbane", debuff.kingsbane_dot )
        kingsbaneReady = true
    end

    if buff.master_assassin.up and buff.master_assassin.remains > 3 then
        removeBuff( "master_assassin" )
        applyBuff( "master_assassin_aura" )
    end
end )

-- We need to break stealth when we start combat from an ability.
spec:RegisterHook( "runHandler", function( ability )
    local a = class.abilities[ ability ]

    if stealthed.mantle and ( not a or a.startsCombat ) then
        if talent.master_assassin.enabled then
            removeBuff( "master_assassin_aura" )
            applyBuff( "master_assassin" )
        end

        if talent.subterfuge.enabled then
            applyBuff( "subterfuge" )
        end

        if talent.indiscriminate_carnage.enabled then
            applyBuff( "indiscriminate_carnage", 10 )
        end

        if legendary.mark_of_the_master_assassin.enabled and stealthed.mantle then
            applyBuff( "master_assassins_mark", 4 )
        end

        if buff.stealth.up then
            setCooldown( "stealth", 2 )
        end

        removeBuff( "stealth" )
        removeBuff( "shadowmeld" )
        removeBuff( "vanish" )

        if buff.improved_garrote.up and buff.improved_garrote.remains > 3 then
            buff.improved_garrote.expires = query_time + 2.95
        end
    end

    if buff.cold_blood.up and ( not a or a.startsCombat ) then
        removeBuff( "cold_blood" )
    end

    class.abilities.apply_poison = class.abilities[ action.apply_poison_actual.next_poison ]
end )


-- Auras
spec:RegisterAuras( {
    -- Talent: Each strike has a chance of inflicting Nature damage and applying Amplification. Envenom consumes Amplification to deal increased damage.
    -- https://wowhead.com/beta/spell=381664
    alacrity = {
        id = 193538,
        duration = 15,
        max_stack = 5,
    },
    amplifying_poison = {
        id = 381664,
        duration = 3600,
        max_stack = 1
    },
    -- Talent: Envenom consumes stacks to amplify its damage.
    -- https://wowhead.com/beta/spell=383414
    amplifying_poison_dot = {
        id = 383414,
        duration = 12,
        max_stack = 20
    },
    amplifying_poison_dot_deathmark = {
        id = 394328,
        duration = 12,
        max_stack = 20,
    },
    -- Talent: $w1% reduced damage and healing.
    -- https://wowhead.com/beta/spell=394119
    blackjack = {
        id = 394119,
        duration = 6,
        max_stack = 1
    },
    -- Attacks striking up to $s3 additional nearby enemies.
    -- https://wowhead.com/beta/spell=319606
    blade_flurry = {
        id = 319606,
        duration = 12,
        max_stack = 1,
        copy = 13877
    },
    -- Talent: Disoriented.
    -- https://wowhead.com/beta/spell=2094
    blind = {
        id = 2094,
        duration = function() return 60 * ( talent.airborne_irritant.enabled and 0.6 or 1 ) end,
        mechanic = "disorient",
        type = "Ranged",
        max_stack = 1
    },
    blindside = {
        id = 121153,
        duration = 10,
        max_stack = 1,
    },
    caustic_spatter = {
        id = 421976,
        duration = 10,
        max_stack = 1
    },
    -- Stunned.
    -- https://wowhead.com/beta/spell=1833
    cheap_shot = {
        id = 1833,
        duration = 4,
        mechanic = "stun",
        max_stack = 1
    },
    -- You have recently escaped certain death.  You will not be so lucky a second time.
    -- https://wowhead.com/beta/spell=45181
    cheated_death = {
        id = 45181,
        duration = 360,
        max_stack = 1
    },
    -- All damage taken reduced by $s1%.
    -- https://wowhead.com/beta/spell=45182
    cheating_death = {
        id = 45182,
        duration = 3,
        max_stack = 1
    },
    -- Talent: Resisting all harmful spells.
    -- https://wowhead.com/beta/spell=31224
    cloak_of_shadows = {
        id = 31224,
        duration = 5,
        max_stack = 1
    },
    -- Talent: Critical strike chance of your next damaging ability increased by $s1%.
    -- https://wowhead.com/beta/spell=382245
    cold_blood = {
        id = 382245,
        duration = 3600,
        max_stack = 1,
        onRemove = function()
            setCooldown( "cold_blood", action.cold_blood.cooldown )
        end,
    },
    crimson_tempest = {
        id = 121411,
        duration = function () return 2 * ( 1 + effective_combo_points ) end,
        max_stack = 1,
        meta = {
            exsanguinated = function( t ) return t.up and tracked_bleeds.crimson_tempest.exsanguinate[ target.unit ] or false end,
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.crimson_tempest.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.crimson_tempest.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t )
                if t.down then return haste * 2 end
                local hasteMod = tracked_bleeds.crimson_tempest.haste[ target.unit ]
                hasteMod = 2 * ( hasteMod and ( 100 / hasteMod ) or haste )
                return hasteMod / t.exsanguinated_rate
            end,
            haste_pct = function( t ) return ( 100 / haste ) end,
            haste_pct_next_tick = function( t ) return t.up and ( tracked_bleeds.crimson_tempest.haste[ target.unit ] or ( 100 / haste ) ) or 0 end,
        },
    },
    -- Healing for ${$W1}.2% of maximum health every $t1 sec.
    -- https://wowhead.com/beta/spell=354494
    crimson_vial = {
        id = 354494,
        duration = 4,
        type = "Magic",
        max_stack = 1,
        copy = { 212198, 185311 }
    },
    -- Each strike has a chance of poisoning the enemy, slowing movement speed by $3409s1% for $3409d.
    -- https://wowhead.com/beta/spell=3408
    crippling_poison = {
        id = 3408,
        duration = 3600,
        max_stack = 1
    },
    -- Movement slowed by $s1%.
    -- https://wowhead.com/beta/spell=3409
    crippling_poison_dot = {
        id = 3409,
        duration = 12,
        mechanic = "snare",
        type = "Magic",
        max_stack = 1
    },
    -- Movement speed slowed by $s1%.
    -- https://wowhead.com/beta/spell=115196
    crippling_poison_snare = {
        id = 115196,
        duration = 5,
        mechanic = "snare",
        max_stack = 1
    },
    -- Each strike has a chance of causing the target to suffer Nature damage every $2818t1 sec for $2818d. Subsequent poison applications deal instant Nature damage.
    -- https://wowhead.com/beta/spell=2823
    deadly_poison = {
        id = 2823,
        duration = 3600,
        max_stack = 1
    },
    -- Talent: Suffering $w1 Nature damage every $t1 seconds.
    -- https://wowhead.com/beta/spell=394324
    deadly_poison_dot = {
        id = 2818,
        duration = function () return 12 * haste end,
        max_stack = 1,
        exsanguinated = false,
        copy = 394324,
        meta = {
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.deadly_poison_dot.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.deadly_poison_dot.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t )
                if t.down then return haste * 2 end
                local hasteMod = tracked_bleeds.deadly_poison_dot.haste[ target.unit ]
                hasteMod = 2 * ( hasteMod and ( 100 / hasteMod ) or haste )
                return hasteMod / t.exsanguinated_rate
            end,
            haste_pct = function( t ) return ( 100 / haste ) end,
            haste_pct_next_tick = function( t ) return t.up and ( tracked_bleeds.deadly_poison_dot.haste[ target.unit ] or ( 100 / haste ) ) or 0 end,
        },
    },
    deadly_poison_dot_deathmark = {
        id = 394324,
        duration = function () return 12 * haste end,
        max_stack = 1,
        exsanguinated = false,
        meta = {
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.deadly_poison_dot_deathmark.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.deadly_poison_dot_deathmark.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t )
                if t.down then return haste * 2 end
                local hasteMod = tracked_bleeds.deadly_poison_dot_deathmark.haste[ target.unit ]
                hasteMod = 2 * ( hasteMod and ( 100 / hasteMod ) or haste )
                return hasteMod / t.exsanguinated_rate
            end,
            haste_pct = function( t ) return ( 100 / haste ) end,
            haste_pct_next_tick = function( t ) return t.up and ( tracked_bleeds.deadly_poison_dot_deathmark.haste[ target.unit ] or ( 100 / haste ) ) or 0 end,
        },
    },
    -- Talent: Bleeding for $w damage every $t sec. Duplicating $@auracaster's Garrote, Rupture, and Lethal poisons applied.
    -- https://wowhead.com/beta/spell=360194
    deathmark = {
        id = 360194,
        duration = 16,
        tick_time = 2,
        mechanic = "bleed",
        max_stack = 1
    },
    -- Detecting certain creatures.
    -- https://wowhead.com/beta/spell=56814
    detection = {
        id = 56814,
        duration = 30,
        max_stack = 1
    },
    -- Talent: Damage done increased by $w1%.
    -- https://wowhead.com/beta/spell=193641
    elaborate_planning = {
        id = 193641,
        duration = 4,
        max_stack = 1
    },
    -- Poison application chance increased by $s2%.$?s340081[  Poison critical strikes generate $340426s1 Energy.][]
    -- https://wowhead.com/beta/spell=32645
    envenom = {
        id = 32645,
        duration = function () return ( effective_combo_points ) + ( 2 * talent.twist_the_knife.rank ) end,
        type = "Poison",
        max_stack = 1
    },
    -- Talent: Dodge chance increased by ${$w1/2}%.$?a344363[ Dodging an attack while Evasion is active will trigger Mastery: Main Gauche.][]
    -- https://wowhead.com/beta/spell=5277
    evasion = {
        id = 5277,
        duration = 10,
        max_stack = 1
    },
    -- Movement speed increased by $w1%.
    -- https://wowhead.com/beta/spell=331868
    fancy_footwork = {
        id = 331868,
        duration = 6,
        max_stack = 1
    },
    -- Talent: Damage taken from area-of-effect attacks reduced by $s1%$?$w2!=0[ and all other damage taken reduced by $w2%.  ][.]
    -- https://wowhead.com/beta/spell=1966
    feint = {
        id = 1966,
        duration = 6,
        max_stack = 1
    },
    -- Talent: $w1% of armor is ignored by the attacking Rogue.
    -- https://wowhead.com/beta/spell=316220
    find_weakness = {
        id = 316220,
        duration = 10,
        max_stack = 1
    },
    garrote = {
        id = 703,
        duration = 18,
        max_stack = 1,
        ss_buffed = false,
        meta = {
            duration = function( t ) return t.up and ( 18 * haste / t.exsanguinated_rate ) or class.auras.garrote.duration end,
            exsanguinated = function( t ) return t.up and tracked_bleeds.garrote.exsanguinate[ target.unit ] or false end,
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.garrote.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.garrote.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t )
                if t.down then return haste * 2 end
                local hasteMod = tracked_bleeds.garrote.haste[ target.unit ]
                hasteMod = 2 * ( hasteMod and ( 100 / hasteMod ) or haste )
                return hasteMod / t.exsanguinated_rate
            end,
            haste_pct = function( t ) return ( 100 / haste ) end,
            haste_pct_next_tick = function( t ) return t.up and ( tracked_bleeds.garrote.haste[ target.unit ] or ( 100 / haste ) ) or 0 end,
        },
    },
    garrote_deathmark = {
        id = 360830,
        duration = 18,
        max_stack = 1,
        ss_buffed = false,
        meta = {
            duration = function( t ) return t.up and ( 18 * haste / t.exsanguinated_rate ) or class.auras.garrote_deathmark.duration end,
            exsanguinated = function( t ) return t.up and tracked_bleeds.garrote_deathmark.exsanguinate[ target.unit ] or false end,
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.garrote_deathmark.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.garrote_deathmark.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t )
                if t.down then return haste * 2 end
                local hasteMod = tracked_bleeds.garrote_deathmark.haste[ target.unit ]
                hasteMod = 2 * ( hasteMod and ( 100 / hasteMod ) or haste )
                return hasteMod / t.exsanguinated_rate
            end,
            haste_pct = function( t ) return ( 100 / haste ) end,
            haste_pct_next_tick = function( t ) return t.up and ( tracked_bleeds.garrote_deathmark.haste[ target.unit ] or ( 100 / haste ) ) or 0 end,
        },
    },
    -- Silenced.
    -- https://wowhead.com/beta/spell=1330
    garrote_silence = {
        id = 1330,
        duration = function () return talent.iron_wire.enabled and 6 or 3 end,
        mechanic = "silence",
        max_stack = 1
    },
    -- Talent: Incapacitated.
    -- https://wowhead.com/beta/spell=1776
    gouge = {
        id = 1776,
        duration = 4,
        mechanic = "incapacitate",
        max_stack = 1
    },
    improved_garrote = {
        id = 392401,
        duration = 3600,
        max_stack = 1,
        copy = { 392403, "improved_garrote_aura", "improved_garrote_buff" }
    },
    -- Talent: Your next Garrote and Rupture apply to $s1 nearby targets.
    -- https://wowhead.com/beta/spell=381802
    indiscriminate_carnage = {
        id = 381802,
        duration = 3600,
        max_stack = 1,
        copy = 385747
    },
    indiscriminate_carnage_garrote = {
        duration = 3600,
        max_stack = 1
    },
    indiscriminate_carnage_rupture = {
        duration = 3600,
        max_stack = 1
    },
    -- Each strike has a chance of poisoning the enemy, inflicting $315585s1 Nature damage.
    -- https://wowhead.com/beta/spell=315584
    instant_poison = {
        id = 315584,
        duration = 3600,
        max_stack = 1
    },
    internal_bleeding = {
        id = 154953,
        duration = 6,
        max_stack = 1,
        meta = {
            exsanguinated = function( t ) return t.up and tracked_bleeds.internal_bleeding.exsanguinate[ target.unit ] or false end,
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.internal_bleeding.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.internal_bleeding.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t )
                if t.down then return haste * 2 end
                local hasteMod = tracked_bleeds.internal_bleeding.haste[ target.unit ]
                hasteMod = 2 * ( hasteMod and ( 100 / hasteMod ) or haste )
                return hasteMod / t.exsanguinated_rate
            end,
            haste_pct = function( t ) return ( 100 / haste ) end,
            haste_pct_next_tick = function( t ) return t.up and ( tracked_bleeds.internal_bleeding.haste[ target.unit ] or ( 100 / haste ) ) or 0 end,
        },
    },
    -- Talent: Damage done reduced by $s1%.
    -- https://wowhead.com/beta/spell=256148
    iron_wire = {
        id = 256148,
        duration = 8,
        max_stack = 1
    },
    -- Stunned.
    -- https://wowhead.com/beta/spell=408
    kidney_shot = {
        id = 408,
        duration = function() return ( 1 + effective_combo_points ) end,
        mechanic = "stun",
        max_stack = 1
    },
    -- Talent: Suffering $w4 Nature damage every $t4 sec.
    -- https://wowhead.com/beta/spell=385627
    kingsbane_dot = {
        id = 385627,
        duration = 14,
        max_stack = 1,
        copy = "kingsbane"
    },
    -- Talent: Kingsbane damage increased by $s1%.
    -- https://wowhead.com/beta/spell=394095
    kingsbane_buff = {
        id = 394095,
        duration = 20,
        max_stack = 99
    },
    -- Movement-impairing effects suppressed.
    -- https://wowhead.com/beta/spell=197003
    maneuverability = {
        id = 197003,
        duration = 4,
        max_stack = 1
    },
    -- Talent: Marked for death, taking extra damage from @auracaster's finishing moves. Cooldown resets upon death.
    -- https://wowhead.com/beta/spell=137619
    marked_for_death = {
        id = 137619,
        duration = 15,
        max_stack = 1
    },
    -- Talent: Critical strike chance increased by $w1%.
    -- https://wowhead.com/beta/spell=256735
    master_assassin = {
        id = 256735,
        duration = 3,
        max_stack = 1,
    },
    master_assassin_aura = {
        duration = 3600,
        max_stack = 1
    },
    -- Damage dealt increased by $w1%.
    -- https://wowhead.com/beta/spell=31665
    master_of_subtlety = {
        id = 31665,
        duration = 3600,
        max_stack = 1
    },
    -- Bleeding for $w1 damage every $t sec.
    -- https://wowhead.com/beta/spell=381672
    mutilated_flesh = {
        id = 381672,
        duration = 6,
        tick_time = 3,
        mechanic = "bleed",
        max_stack = 1,
        copy = 340431
    },
    -- Suffering $w1 Nature damage every $t1 sec.
    -- https://wowhead.com/beta/spell=286581
    nothing_personal = {
        id = 286581,
        duration = 20,
        tick_time = 2,
        type = "Magic",
        max_stack = 1,
    },
    nothing_personal_regen = {
        id = 289467,
        duration = 20,
        tick_time = 2,
        max_stack = 1,
    },
    -- Coats your weapons with a Non-Lethal Poison that lasts for 1 |4hour:hrs;. Each strike has a 30% chance of poisoning the enemy, clouding their mind and slowing their attack and casting speed by 15% for 10 sec.
    numbing_poison = {
        id = 5761,
        duration = 3600,
        max_stack = 1,
    },
    -- Talent: Attack and casting speed slowed by $s1%.
    -- https://wowhead.com/beta/spell=5760
    numbing_poison_dot = {
        id = 5760,
        duration = 10,
        max_stack = 1
    },
    -- Bleeding for $w1 damage every $t1 sec.
    -- https://wowhead.com/beta/spell=360826
    rupture = {
        id = 1943,
        duration = function () return 4 * ( 1 + effective_combo_points ) end,
        tick_time = function () return ( debuff.rupture.exsanguinated and 2 or 1 ) * haste end,
        mechanic = "bleed",
        max_stack = 1,
        meta = {
            exsanguinated = function( t ) return t.up and tracked_bleeds.rupture.exsanguinate[ target.unit ] or false end,
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.rupture.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.rupture.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t )
                if t.down then return haste * 2 end
                local hasteMod = tracked_bleeds.rupture.haste[ target.unit ]
                hasteMod = 2 * ( hasteMod and ( 100 / hasteMod ) or haste )
                return hasteMod / t.exsanguinated_rate
            end,
            haste_pct = function( t ) return ( 100 / haste ) end,
            haste_pct_next_tick = function( t ) return t.up and ( tracked_bleeds.rupture.haste[ target.unit ] or ( 100 / haste ) ) or 0 end,
        },
    },
    rupture_deathmark = {
        id = 360826,
        duration = function () return 4 * ( 1 + effective_combo_points ) end,
        tick_time = function () return ( debuff.rupture_deathmark.exsanguinated and 2 or 1 ) * haste end,
        mechanic = "bleed",
        max_stack = 1,
        meta = {
            exsanguinated = function( t ) return t.up and tracked_bleeds.rupture_deathmark.exsanguinate[ target.unit ] or false end,
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.rupture_deathmark.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.rupture_deathmark.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t )
                if t.down then return haste * 2 end
                local hasteMod = tracked_bleeds.rupture_deathmark.haste[ target.unit ]
                hasteMod = 2 * ( hasteMod and ( 100 / hasteMod ) or haste )
                return hasteMod / t.exsanguinated_rate
            end,
            haste_pct = function( t ) return ( 100 / haste ) end,
            haste_pct_next_tick = function( t ) return t.up and ( tracked_bleeds.rupture_deathmark.haste[ target.unit ] or ( 100 / haste ) ) or 0 end,
        },
    },
    -- Talent: Incapacitated.$?$w2!=0[  Damage taken increased by $w2%.][]
    -- https://wowhead.com/beta/spell=6770
    sap = {
        id = 6770,
        duration = 60,
        mechanic = "sap",
        max_stack = 1
    },
    -- Talent: Your Ruptures are increasing your Agility by $w1%.
    -- https://wowhead.com/beta/spell=394080
    scent_of_blood = {
        id = 394080,
        duration = 24,
        max_stack = 24
    },
    -- Talent: Suffering $w1 Nature damage every $t1 sec, and $394026s1 when the poison ends.
    -- https://wowhead.com/beta/spell=385408
    sepsis = {
        id = 385408,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
        copy = { 328305, 375936 },
        exsanguinated = false,
        meta = {
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.sepsis.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.sepsis.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t ) return t.up and ( haste * 2 / t.exsanguinated_rate ) or ( haste * 2 ) end,
        },
    },
    sepsis_buff = {
        id = 375939,
        duration = 10,
        max_stack = 1,
        copy = 347037
    },
    -- Bleeding for $w1 every $t1 sec.
    -- https://wowhead.com/beta/spell=394036
    serrated_bone_spike = {
        id = 394036,
        duration = 3600,
        tick_time = 3,
        max_stack = 1,
        exsanguinated = false,
        meta = {
            exsanguinated_rate = function( t ) return t.up and tracked_bleeds.serrated_bone_spike.rate[ target.unit ] or 1 end,
            last_tick = function( t ) return t.up and ( tracked_bleeds.serrated_bone_spike.last_tick[ target.unit ] or t.applied ) or 0 end,
            tick_time = function( t ) return t.up and ( haste * 2 / t.exsanguinated_rate ) or ( haste * 2 ) end,
        },
        copy = { "serrated_bone_spike_dot", 324073 }
    },
    -- Attacks deal $w1% additional damage as Shadow and combo point generating attacks generate full combo points.
    -- https://wowhead.com/beta/spell=121471
    shadow_blades = {
        id = 121471,
        duration = 20,
        max_stack = 1
    },
    -- Talent: Access to Stealth abilities.$?$w3!=0[  Movement speed increased by $w3%.][]$?$w4!=0[  Damage increased by $w4%.][]
    -- https://wowhead.com/beta/spell=185422
    shadow_dance = {
        id = 185422,
        duration = 6,
        max_stack = 1,
        copy = 185313
    },
    -- Combo points stored.
    -- TODO: Is the # of points stored as a stack or value?
    shadow_techniques = {
        id = 196911,
        duration = 3600,
        max_stack = 1,

        -- Affected by:
        -- deeper_stratagem[193531] #5: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER_BY_LABEL, 'points': 2.0, 'target': TARGET_UNIT_CASTER, 'modifies': MAX_STACKS, }
        -- improved_shadow_techniques[394023] #0: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER, 'points': 3.0, 'target': TARGET_UNIT_CASTER, 'modifies': EFFECT_2_VALUE, }
        -- secret_stratagem[394320] #5: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER_BY_LABEL, 'points': 2.0, 'target': TARGET_UNIT_CASTER, 'modifies': MAX_STACKS, }
    },
    -- Talent: Movement speed increased by $s2%.
    -- https://wowhead.com/beta/spell=36554
    shadowstep = {
        id = 36554,
        duration = 2,
        max_stack = 1
    },
    -- Energy cost of abilities reduced by $w1%.
    -- https://wowhead.com/beta/spell=112942
    shadow_focus = {
        id = 112942,
        duration = 3600,
        max_stack = 1
    },
    -- Movement speed slowed by $w1%.
    -- https://wowhead.com/beta/spell=206760
    shadows_grasp = {
        id = 206760,
        duration = 8,
        max_stack = 1
    },
    -- Shadowstrike deals $s2% increased damage and has $s1 yds increased range.
    -- https://wowhead.com/beta/spell=245623
    shadowstrike = {
        id = 245623,
        duration = 3600,
        max_stack = 1
    },
    -- Talent: $w1% increased Nature damage taken from $@auracaster.$?${$W2<0}[ Healing received reduced by $w2%.][]
    -- https://wowhead.com/beta/spell=319504
    shiv = {
        id = 319504,
        duration = 8,
        max_stack = 1
    },
    -- Concealing allies within $115834A1 yards in shadows.
    -- https://wowhead.com/beta/spell=114018
    shroud_of_concealment = {
        id = 114018,
        duration = 15,
        tick_time = 0.5,
        max_stack = 1
    },
    -- Concealed in shadows.
    -- https://wowhead.com/beta/spell=115834
    shroud_of_concealment_buff = {
        id = 115834,
        duration = 2,
        max_stack = 1
    },
    -- Attack speed increased by $w1%.
    -- https://wowhead.com/beta/spell=315496
    slice_and_dice = {
        id = 315496,
        duration = function () return 6 * ( 1 + effective_combo_points ) end,
        max_stack = 1,
    },
    smoke_bomb = {
        id = 212182,
        duration = 5,
        max_stack = 1,
    },
    sprint = {
        id = 2983,
        duration = function() return ( 8 + ( talent.featherfoot.rank * 4 ) ) * ( pvptalent.maneuverability.enabled and 0.5 or 1 ) end,
        max_stack = 1,
    },
    -- Stealthed.
    -- https://wowhead.com/beta/spell=115191
    stealth = {
        id = 115191,
        duration = 3600,
        max_stack = 1,
        copy = 1784
    },
    -- Damage done increased by 10%.
    -- https://wowhead.com/beta/spell= = {
    symbols_of_death = {
        id = 212283,
        duration = 10,
        max_stack = 1,
    },
    -- Movement speed increased by $w1%.
    terrifying_pace = {
        id = 428389,
        duration = 3.0,
        max_stack = 1,
    },
    -- Talent: Mastery increased by ${$w2*$mas}.1%.
    -- https://wowhead.com/beta/spell=381623
    thistle_tea = {
        id = 381623,
        duration = 6,
        type = "Magic",
        max_stack = 1
    },
    -- $s1% increased damage taken from poisons from the casting Rogue.
    -- https://wowhead.com/beta/spell=245389
    toxic_blade = {
        id = 245389,
        duration = 9,
        max_stack = 1
    },
    -- Talent: Threat redirected from Rogue.
    -- https://wowhead.com/beta/spell=57934
    tricks_of_the_trade_target = {
        id = 57934,
        duration = 30,
        max_stack = 1
    },
    -- Talent: All threat transferred from the Rogue to the target.  $?s221622[Damage increased by $221622m1%.][]
    -- https://wowhead.com/beta/spell=59628
    tricks_of_the_trade = {
        id = 59628,
        duration = 6,
        max_stack = 1
    },
    -- Improved stealth.$?$w3!=0[  Movement speed increased by $w3%.][]$?$w4!=0[  Damage increased by $w4%.][]
    -- https://wowhead.com/beta/spell=11327
    vanish = {
        id = 11327,
        duration = 3,
        max_stack = 1
    },
    -- Each strike has a chance of inflicting additional Nature damage to the victim and reducing all healing received for $8680d.
    -- https://wowhead.com/beta/spell=8679
    wound_poison = {
        id = 8679,
        duration = 3600,
        max_stack = 1
    },
    -- Healing effects reduced by $w2%.
    -- https://wowhead.com/beta/spell=8680
    wound_poison_debuff = {
        id = 8680,
        duration = 12,
        max_stack = 3,
        copy = { 394327, "wound_poison_dot" }
    },

    poisoned = {
        alias = { "amplifying_poison_dot", "amplifying_poison_dot_deathmark", "deadly_poison_dot", "deadly_poison_dot_deathmark", "kingsbane_dot", "sepsis", "wound_poison_dot" },
        aliasMode = "longest",
        aliasType = "debuff",
        duration = 3600,
    },
    lethal_poison = {
        alias = { "amplifying_poison", "deadly_poison", "wound_poison", "instant_poison" },
        aliasMode = "shortest",
        aliasType = "buff",
        duration = 3600
    },
    nonlethal_poison = {
        alias = { "atrophic_poison", "numbing_poison", "crippling_poison" },
        aliasMode = "shortest",
        aliasType = "buff",
        duration = 3600
    },

    -- PvP Talents
    creeping_venom = {
        id = 198097,
        duration = 4,
        max_stack = 18,
    },

    system_shock = {
        id = 198222,
        duration = 2,
    },

    -- Legendaries
    bloodfang = {
        id = 23581,
        duration = 6,
        max_stack = 1
    },

    master_assassins_mark = {
        id = 340094,
        duration = 4,
        max_stack = 1
    },

    master_assassin_any = {
        alias = { "master_assassin", "master_assassins_mark" },
        aliasMode = "longest",
        aliasType = "buff",
        duration = function () return legendary.mark_of_the_master_assassin.enabled and 4 or 3 end,
    }
} )


-- Abilities
spec:RegisterAbilities( {
    -- Ambush the target, causing $s1 Physical damage.$?s383281[    Has a $193315s3% chance to hit an additional time, making your next Pistol Shot half cost and double damage.][]    |cFFFFFFFFAwards $s2 combo $lpoint:points;$?s383281[ each time it strikes][].|r
    ambush = {
        id = 8676,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            if buff.blindside.up then return 0 end
            return talent.tight_spender.enabled and 45 or 50
        end,
        spendType = "energy",

        startsCombat = true,
        usable = function () return stealthed.ambush or buff.audacity.up or buff.blindside.up, "requires stealth or audacity/blindside/sepsis_buff" end,

        cp_gain = function ()
            if buff.shadow_blades.up then return 6 end
            return 2 + ( buff.shadow_blades.up and 1 or 0 ) + ( buff.broadside.up and 1 or 0 ) + talent.improved_ambush.rank + ( talent.seal_fate.enabled and buff.cold_blood.up and 1 or 0 )
        end,

        handler = function ()
            gain( action.ambush.cp_gain, "combo_points" )
            if talent.venom_rush.enabled and debuff.poisoned.up then gain( 7, "energy" ) end

            if buff.blindside.up then removeBuff( "blindside" ) end
            if buff.sepsis_buff.up then removeBuff( "sepsis_buff" ) end
            if buff.audacity.up then removeBuff( "audacity" ) end
        end,
    },

    -- Talent: Coats your weapons with a Lethal Poison that lasts for 1 |4hour:hrs;. Each strike has a 40% chance to poison the enemy, dealing 75 Nature damage and applying Amplification for 12 sec. Envenom can consume 10 stacks of Amplification to deal 35% increased damage. Max 20 stacks.
    amplifying_poison = {
        id = 381664,
        cast = 1.5,
        cooldown = 0,
        gcd = "totem",
        school = "physical",

        talent = "amplifying_poison",
        startsCombat = false,
        essential = true,

        handler = function ()
            applyBuff( "amplifying_poison" )
        end,
    },

    -- Talent: Coats your weapons with a Non-Lethal Poison that lasts for $d. Each strike has a $h% chance of poisoning the enemy, reducing their damage by ${$392388s1*-1}.1% for $392388d.
    atrophic_poison = {
        id = 381637,
        cast = 1.5,
        cooldown = 0,
        gcd = "off",

        talent = "atrophic_poison",
        startsCombat = false,
        essential = true,

        readyTime = function() return buff.atrophic_poison.remains - 120 end,

        handler = function ()
            applyBuff( "atrophic_poison" )
        end,
    },

    -- Talent: Blinds the target, causing it to wander disoriented for $d. Damage will interrupt the effect. Limit 1.
    blind = {
        id = 2094,
        cast = 0,
        cooldown = function () return ( talent.blinding_powder.enabled and 90 or 120 ) * ( talent.airborne_irritant.enabled and 0.5 or 1 ) end,
        gcd = "spell",

        talent = "blind",
        startsCombat = true,

        toggle = "interrupts",

        handler = function ()
            applyDebuff( "target", "blind" )
        end,
    },

    -- Stuns the target for $d.    |cFFFFFFFFAwards $s2 combo $lpoint:points;.|r
    cheap_shot = {
        id = 1833,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function ()
            if talent.dirty_tricks.enabled then return 0 end
            return ( talent.tight_spender.enabled and 36 or 40 ) * ( 1 + conduit.rushed_setup.mod * 0.01 ) end,
        spendType = "energy",

        startsCombat = true,

        cycle = function ()
            if talent.prey_on_the_weak.enabled then return "prey_on_the_weak" end
        end,

        usable = function ()
            if target.is_boss then return false, "cheap_shot assumed unusable in boss fights" end
            return stealthed.all or buff.subterfuge.up, "not stealthed"
        end,

        nodebuff = "cheap_shot",

        cp_gain = function () return 1 + ( buff.shadow_blades.up and 1 or 0 ) + ( talent.seal_fate.enabled and buff.cold_blood.up and 1 or 0 ) end,

        handler = function ()
            applyDebuff( "target", "cheap_shot", 4 )

            if buff.sepsis_buff.up then removeBuff( "sepsis_buff" ) end

            if talent.prey_on_the_weak.enabled then
                applyDebuff( "target", "prey_on_the_weak" )
            end

            if pvptalent.control_is_king.enabled then
                applyBuff( "slice_and_dice" )
            end

            gain( action.cheap_shot.cp_gain, "combo_points" )
        end,
    },

    -- Talent: Provides a moment of magic immunity, instantly removing all harmful spell effects. The cloak lingers, causing you to resist harmful spells for $d.
    cloak_of_shadows = {
        id = 31224,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        talent = "cloak_of_shadows",
        startsCombat = false,

        toggle = "interrupts",
        buff = "dispellable_magic",

        handler = function ()
            removeBuff( "dispellable_magic" )
            applyBuff( "cloak_of_shadows" )
        end,
    },

    -- Talent: Increases the critical strike chance of your next damaging ability by $s1%.
    cold_blood = {
        id = 382245,
        cast = 0,
        cooldown = 45,
        gcd = "off",
        school = "physical",

        talent = "cold_blood",
        startsCombat = false,
        nobuff = "cold_blood",
        readyTime = function() return gcd.remains end,

        handler = function ()
            applyBuff( "cold_blood" )
        end,
    },

    -- Drink an alchemical concoction that heals you for $?a354425&a193546[${$O1}.1][$o1]% of your maximum health over $d.
    crimson_vial = {
        id = 185311,
        cast = 0,
        cooldown = 30,
        gcd = "totem",
        school = "nature",

        spend = function () return 20 - ( 10 * talent.nimble_fingers.rank ) + conduit.nimble_fingers.mod end,
        spendType = "energy",

        startsCombat = false,
        texture = 1373904,

        handler = function ()
            applyBuff( "crimson_vial" )
        end,
    },

    -- Talent: Finishing move that slashes all enemies within 13 yards, dealing instant damage and causing victims to bleed for additional damage. Deals reduced damage beyond 8 targets. Lasts longer per combo point. 1 point : 325 plus 307 over 4 sec 2 points: 487 plus 460 over 6 sec 3 points: 650 plus 613 over 8 sec 4 points: 812 plus 767 over 10 sec 5 points: 975 plus 920 over 12 sec
    crimson_tempest = {
        id = 121411,
        cast = 0,
        cooldown = 0,
        gcd = "totem",
        school = "physical",

        spend = 30,
        spendType = "energy",

        talent = "crimson_tempest",
        startsCombat = true,
        aura = "crimson_tempest",
        cycle = "crimson_tempest",

        usable = function () return combo_points.current > 0, "requires combo points" end,

        handler = function ()
            applyDebuff( "target", "crimson_tempest", 2 + ( effective_combo_points * 2 ) )
            debuff.crimson_tempest.pmultiplier = persistent_multiplier
            debuff.crimson_tempest.exsanguinated_rate = 1
            debuff.crimson_tempest.exsanguinated = false

            removeBuff( "echoing_reprimand_" .. combo_points.current )
            spend( combo_points.current, "combo_points" )

            if talent.elaborate_planning.enabled then applyBuff( "elaborate_planning" ) end
        end,
    },


    crippling_poison = {
        id = 3408,
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        essential = true,
        texture = 132274,

        readyTime = function () return buff.crippling_poison.remains - 120 end,

        handler = function ()
            applyBuff( "crippling_poison" )
        end,
    },


    deadly_poison = {
        id = 2823,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        essential = true,
        texture = 132290,


        readyTime = function () return buff.deadly_poison.remains - 120 end,

        handler = function ()
            applyBuff( "deadly_poison" )
        end,
    },

    -- Talent: Carve a deathmark into an enemy, dealing 3,209 Bleed damage over 16 sec. While marked your Garrote, Rupture, and Lethal poisons applied to the target are duplicated, dealing 100% of normal damage.
    deathmark = {
        id = 360194,
        cast = 0,
        cooldown = 120,
        gcd = "totem",
        school = "physical",

        talent = "deathmark",
        startsCombat = true,

        toggle = "cooldowns",

        handler = function ()
            applyDebuff( "target", "deathmark" )
        end,
    },

    -- Throws a distraction, attracting the attention of all nearby monsters for $s1 seconds. Usable while stealthed.
    distract = {
        id = 1725,
        cast = 0,
        cooldown = 30,
        gcd = "totem",
        school = "physical",

        spend = function () return 30 * ( talent.rushed_setup.enabled and 0.8 or 1 ) * ( 1 + conduit.rushed_setup.mod * 0.01 ) end,
        spendType = "energy",

        startsCombat = false,
        texture = 132289,

        handler = function ()
        end,
    },


    -- Talent: Deal $s1 Arcane damage to an enemy, extracting their anima to Animacharge a combo point for $323558d.    Damaging finishing moves that consume the same number of combo points as your Animacharge function as if they consumed $s2 combo points.    |cFFFFFFFFAwards $s3 combo $lpoint:points;.|r
    echoing_reprimand = {
        id = function() return talent.echoing_reprimand.enabled and 385616 or 323547 end,
        cast = 0,
        cooldown = 45,
        gcd = "totem",
        school = "arcane",

        spend = 10,
        spendType = "energy",

        startsCombat = true,
        toggle = "cooldowns",

        cp_gain = function () return 2 + ( buff.shadow_blades.up and 1 or 0 ) + ( buff.broadside.up and 1 or 0 ) + ( talent.seal_fate.enabled and buff.cold_blood.up and 1 or 0 ) end,

        handler = function ()
            -- Can't predict the Animacharge, unless you have the talent/legendary.
            if legendary.resounding_clarity.enabled or talent.resounding_clarity.enabled then
                applyBuff( "echoing_reprimand_2", nil, 2 )
                applyBuff( "echoing_reprimand_3", nil, 3 )
                applyBuff( "echoing_reprimand_4", nil, 4 )
                applyBuff( "echoing_reprimand_5", nil, 5 )
            end
            gain( action.echoing_reprimand.cp_gain, "combo_points" )
        end,

        copy = { 385616, 323547 },
    },

    -- Finishing move that drives your poisoned blades in deep, dealing instant Nature damage and increasing your poison application chance by 30%. Damage and duration increased per combo point. 1 point : 288 damage, 2 sec 2 points: 575 damage, 3 sec 3 points: 863 damage, 4 sec 4 points: 1,150 damage, 5 sec 5 points: 1,438 damage, 6 sec
    envenom = {
        id = 32645,
        cast = 0,
        cooldown = 0,
        gcd = "totem",
        school = "nature",

        spend = 35,
        spendType = "energy",

        startsCombat = true,

        usable = function () return combo_points.current > 0, "requires combo_points" end,

        handler = function ()
            if pvptalent.system_shock.enabled then
                if combo_points.current >= 5 and debuff.garrote.up and debuff.rupture.up and ( debuff.deadly_poison_dot.up or debuff.wound_poison_dot.up ) then
                    applyDebuff( "target", "system_shock", 2 )
                end
            end

            if pvptalent.creeping_venom.enabled then
                applyDebuff( "target", "creeping_venom" )
            end

            if talent.cut_to_the_chase.enabled and buff.slice_and_dice.up then
                buff.slice_and_dice.expires = buff.slice_and_dice.expires + combo_points.current * 3
            end

            applyBuff( "envenom" )
            spend( combo_points.current, "combo_points" )

            if talent.elaborate_planning.enabled then applyBuff( "elaborate_planning" ) end
        end,
    },

-- Talent: Increases your dodge chance by ${$s1/2}% for $d.$?a344363[ Dodging an attack while Evasion is active will trigger Mastery: Main Gauche.][]
    evasion = {
        id = 5277,
        cast = 0,
        cooldown = 120,
        gcd = "off",
        school = "physical",

        talent = "evasion",
        startsCombat = false,

        toggle = "defensives",

        handler = function ()
            applyBuff( "evasion" )
        end,
    },

    -- Talent: Twist your blades into the target's wounds, causing your Bleed effects on them to bleed out 100% faster.
    exsanguinate = {
        id = 200806,
        cast = 0,
        cooldown = 180,
        gcd = "totem",
        school = "physical",

        spend = 25,
        spendType = "energy",

        talent = "exsanguinate",
        startsCombat = true,

        handler = function ()
            local rate

            for i, aura in ipairs( true_exsanguinated ) do
                local deb = debuff[ aura ]

                if deb.up and not deb.exsanguinated then
                    deb.exsanguinated = true

                    rate = deb.exsanguinated_rate
                    deb.exsanguinated_rate = deb.exsanguinated_rate + 1

                    deb.expires = query_time + ( deb.remains * rate / deb.exsanguinated_rate )
                    deb.duration = deb.expires - deb.applied
                end
            end
        end,
    },

    -- Sprays knives at all enemies within 18 yards, dealing 544 Physical damage and applying your active poisons at their normal rate. Deals reduced damage beyond 8 targets. Awards 1 combo point.
    fan_of_knives = {
        id = 51723,
        cast = 0,
        cooldown = 0,
        gcd = "totem",
        school = "physical",

        spend = 35,
        spendType = "energy",

        startsCombat = true,
        cycle = function () return buff.deadly_poison.up and "deadly_poison_dot" or buff.amplifying_poison.up and "amplifying_poison_dot" or nil end,

        handler = function ()
            gain( 1, "combo_points" )
            removeBuff( "hidden_blades" )
            if buff.deadly_poison.up then
                applyDebuff( "target", "deadly_poison_dot" )
                active_dot.deadly_poison_dot = min( active_enemies, active_dot.deadly_poison_dot + 8 )
            elseif buff.amplifying_poison.up then
                applyDebuff( "target", "amplifying_poison_dot" )
                active_dot.amplifying_poison_dot = min( active_enemies, active_dot.amplifying_poison_dot + 8 )
            end
        end,
    },

    -- Talent: Performs an evasive maneuver, reducing damage taken from area-of-effect attacks by $s1% $?s79008[and all other damage taken by $s2% ][]for $d.
    feint = {
        id = 1966,
        cast = 0,
        cooldown = function() return 15 * ( pvptalent.thiefs_bargain.enabled and 0.667 or 1 ) end,
        charges = function() return talent.graceful_guile.enabled and 2 or nil end,
        recharge = function() return talent.graceful_guile.enabled and ( 15 * ( pvptalent.thiefs_bargain.enabled and 0.667 or 1 ) ) or nil end,
        gcd = "totem",
        school = "physical",

        spend = function () return talent.nimble_fingers.enabled and 25 or 35 + conduit.nimble_fingers.mod end,
        spendType = "energy",

        startsCombat = false,
        texture = 132294,

        handler = function ()
            applyBuff( "feint" )
        end,
    },

    -- Garrote the enemy, causing 2,407 Bleed damage over 18 sec. Awards 1 combo point.
    garrote = {
        id = 703,
        cast = 0,
        cooldown = function () return ( buff.sepsis_buff.up or buff.improved_garrote.up ) and 0 or 6 end,
        gcd = "totem",
        school = "physical",

        spend = 45,
        spendType = "energy",

        startsCombat = true,
        aura = "garrote",
        cycle = "garrote",

        cp_gain = function() return ( stealthed.rogue or stealthed.improved_garrote ) and talent.shrouded_suffocation.enabled and 3 or 1 end,

        handler = function ()
            applyDebuff( "target", "garrote" )
            debuff.garrote.pmultiplier = persistent_multiplier
            debuff.garrote.exsanguinated_rate = 1
            debuff.garrote.exsanguinated = false

            if debuff.deathmark.up then
                applyDebuff( "target", "garrote_deathmark" )
                debuff.garrote_deathmark.pmultiplier = persistent_multiplier * ( buff.improved_garrote.up and 1.5 or 1 )
                debuff.garrote_deathmark.exsanguinated_rate = 1
                debuff.garrote_deathmark.exsanguinated = false
            end

            if buff.indiscriminate_carnage_garrote.up then
                active_dot.garrote = min( true_active_enemies, active_dot.garrote + 8 )
                removeBuff( "indiscriminate_carnage_garrote" )
                if buff.indiscriminate_carnage_rupture.down then
                    removeBuff( "indiscriminate_carnage" )
                    setCooldown( "indiscriminate_carnage", action.indiscriminate_carnage.cooldown )
                end
            end

            gain( action.garrote.cp_gain, "combo_points" )

            if stealthed.rogue then
                if talent.iron_wire.enabled then
                    applyDebuff( "target", "garrote_silence" )
                    applyDebuff( "target", "iron_wire" )
                end
                if azerite.shrouded_suffocation.enabled then
                    debuff.garrote.ss_buffed = true
                end
            end
        end,
    },

    -- Talent: Gouges the eyes of an enemy target, incapacitating for $d. Damage will interrupt the effect.    Must be in front of your target.    |cFFFFFFFFAwards $s2 combo $lpoint:points;.|r
    gouge = {
        id = 1776,
        cast = 0,
        cooldown = 20,
        gcd = "totem",
        school = "physical",

        spend = function () return talent.dirty_tricks.enabled and 0 or 25 end,
        spendType = "energy",

        talent = "gouge",
        startsCombat = true,

        cp_gain = function ()
            if buff.shadow_blades.up then return combo_points.max end
            return 1 + ( buff.broadside.up and 1 or 0 ) + ( talent.seal_fate.enabled and buff.cold_blood.up and 1 or 0 )
        end,

        handler = function ()
            applyDebuff( "target", "gouge" )
            gain( action.gouge.cp_gain, "combo_points" )
        end,
    },

    -- Talent: Your next Garrote and your next Rupture apply to up to 8 enemies within 10 yards.
    indiscriminate_carnage = {
        id = 381802,
        cast = 0,
        cooldown = 60,
        gcd = "off",
        school = "physical",

        talent = "indiscriminate_carnage",
        startsCombat = false,
        nobuff = "indiscriminate_carnage",

        handler = function ()
            applyBuff( "indiscriminate_carnage" )
            applyBuff( "indiscriminate_carnage_garrote" )
            applyBuff( "indiscriminate_carnage_rupture" )
        end,
    },

    instant_poison = {
        id = 315584,
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        essential = true,
        texture = 132273,

        readyTime = function () return buff.instant_poison.remains - 120 end,

        handler = function ()
            applyBuff( "instant_poison" )
        end,
    },

    -- A quick kick that interrupts spellcasting and prevents any spell in that school from being cast for 5 sec.
    kick = {
        id = 1766,
        cast = 0,
        cooldown = 15,
        gcd = "off",
        school = "physical",

        startsCombat = true,

        toggle = "interrupts",

        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            interrupt()
        end
    },

    -- Finishing move that stuns the target$?a426588[ and creates shadow clones to stun all other nearby enemies][]. Lasts longer per combo point, up to 5:;    1 point  : 2 seconds;    2 points: 3 seconds;    3 points: 4 seconds;    4 points: 5 seconds;    5 points: 6 seconds
    kidney_shot = {
        id = 408,
        cast = 0,
        cooldown = function() return talent.stunning_secret.enabled and 40 or 20 end,
        gcd = "spell",

        spend = function ()
            if buff.goremaws_bite.up then return 0 end
            return ( talent.rushed_setup.enabled and 20 or 25 ) * ( talent.stunning_secret.enabled and 2 or 1 ) * ( 1 - 0.1 * talent.tight_spender.rank ) * ( 1 + conduit.rushed_setup.mod * 0.01 )
        end,
        spendType = "energy",

        startsCombat = true,
        aura = "internal_bleeding",
        cycle = "internal_bleeding",

        usable = function ()
            if target.is_boss then return false, "kidney_shot assumed unusable in boss fights" end
            return combo_points.current > 0, "requires combo points"
        end,

        handler = function ()
            applyDebuff( "target", "kidney_shot", 1 + combo_points.current )
            if talent.alacrity.enabled and combo_points.current > 4 then addStack( "alacrity" ) end
            if talent.elaborate_planning.enabled then applyBuff( "elaborate_planning" ) end
            if talent.internal_bleeding.enabled then
                applyDebuff( "target", "internal_bleeding" )
                debuff.internal_bleeding.pmultiplier = persistent_multiplier
                debuff.internal_bleeding.exsanguinated = false
                debuff.internal_bleeding.exsanguinated_rate = 1
            end

            if pvptalent.control_is_king.enabled then
                gain( 10 * combo_points.current, "energy" )
            end

            spend( combo_points.current, "combo_points" )
        end,
    },

    -- Talent: Release a lethal poison from your weapons and inject it into your target, dealing 1,770 Nature damage instantly and an additional 1,648 Nature damage over 14 sec. Each time you apply a Lethal Poison to a target affected by Kingsbane, Kingsbane damage increases by 20%. Awards 1 combo point.
    kingsbane = {
        id = 385627,
        cast = 0,
        cooldown = 60,
        gcd = "totem",
        school = "nature",

        spend = 35,
        spendType = "energy",

        talent = "kingsbane",
        startsCombat = false,

        cp_gain = 1,

        handler = function ()
            applyDebuff( "target", "kingsbane_dot" )
            gain( action.kingsbane.cp_gain, "combo_points" )
        end,
    },

    -- Talent: Marks the target, instantly generating 5 combo points. Cooldown reset if the target dies within 1 min.
    -- TODO:  MfD cooldown for Subtlety is different?
    marked_for_death = {
        id = 137619,
        cast = 0,
        cooldown = 40,
        gcd = "off",
        school = "physical",

        talent = "marked_for_death",
        startsCombat = false,
        texture = 236364,

        toggle = "cooldowns",

        usable = function ()
            return combo_points.current <= settings.mfd_points, "combo_point (" .. combo_points.current .. ") > user preference (" .. settings.mfd_points .. ")"
        end,

        cp_gain = function () return 7 end,

        handler = function ()
            gain( action.marked_for_death.cp_gain, "combo_points" )
        end,
    },

    -- Attack with both weapons, dealing a total of 649 Physical damage. Awards 2 combo points.
    mutilate = {
        id = 1329,
        cast = 0,
        cooldown = 0,
        gcd = "totem",
        school = "physical",

        spend = 50,
        spendType = "energy",

        startsCombat = true,

        handler = function ()
            gain( 2, "combo_points" )
            if talent.caustic_spatter.enabled and dot.rupture.ticking and dot.deadly_poison_dot.ticking then
                applyDebuff( "target", "caustic_spatter" )
                active_dot.caustic_spatter = 1
            end

            if talent.venom_rush.enabled and debuff.poisoned.up then gain( 7, "energy" ) end

            if talent.doomblade.enabled or legendary.doomblade.enabled then
                applyDebuff( "target", "mutilated_flesh" )
            end
        end,
    },

    -- Throws a poison-coated knife, dealing 171 damage and applying your active Lethal and Non-Lethal Poisons. Awards 1 combo point.
    poisoned_knife = {
        id = 185565,
        cast = 0,
        cooldown = 0,
        gcd = "totem",
        school = "physical",

        spend = 40,
        spendType = "energy",

        startsCombat = true,

        handler = function ()
        end,
    },

    -- Coats your weapons with a Non-Lethal Poison that lasts for 1 hour.  Each strike has a 30% chance of poisoning the enemy, clouding their mind and slowing their attack and casting speed by 15% for 10 sec.
    numbing_poison = {
        id = 5761,
        cast = 1,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        essential = true,
        texture = 136066,

        readyTime = function () return buff.numbing_poison.remains - 120 end,

        handler = function ()
            applyBuff( "numbing_poison" )
        end,
    },

    -- Pick the target's pocket.
    pick_pocket = {
        id = 921,
        cast = 0,
        cooldown = 0.5,
        gcd = "off",

        startsCombat = true,
        texture = 133644,

        handler = function ()
        end,
    },

    -- Finishing move that tears open the target, dealing Bleed damage over time. Lasts longer per combo point. 1 point : 1,250 over 8 sec 2 points: 1,876 over 12 sec 3 points: 2,501 over 16 sec 4 points: 3,126 over 20 sec 5 points: 3,752 over 24 sec
    rupture = {
        id = 1943,
        cast = 0,
        cooldown = 0,
        gcd = "totem",
        school = "physical",

        spend = function()
            if buff.goremaws_bite.up then return 0 end
            return 25
        end,
        spendType = "energy",

        startsCombat = true,
        aura = "rupture",
        cycle = "rupture",

        usable = function () return combo_points.current > 0, "requires combo_points" end,

        used_for_danse = function()
            if not state.spec.subtlety or not talent.danse_macabre.enabled or buff.shadow_dance.down then return false end
            return danse_macabre_tracker.rupture
        end,

        handler = function ()
            removeStack( "goremaws_bite" )
            removeBuff( "masterful_finish" )

            applyDebuff( "target", "rupture" )
            debuff.rupture.pmultiplier = persistent_multiplier
            debuff.rupture.exsanguinated = false
            debuff.rupture.exsanguinated_rate = 1

            if debuff.deathmark.up then
                applyDebuff( "target", "rupture_deathmark" )
                debuff.rupture_deathmark.pmultiplier = persistent_multiplier
                debuff.rupture_deathmark.exsanguinated = false
                debuff.rupture_deathmark.exsanguinated_rate = 1
            end

            if buff.indiscriminate_carnage_rupture.up then
                active_dot.rupture = min( true_active_enemies, active_dot.rupture + 8 )
                removeBuff( "indiscriminate_carnage_rupture" )
                if buff.indiscriminate_carnage_garrote.down then
                    removeBuff( "indiscriminate_carnage" )
                    setCooldown( "indiscriminate_carnage", action.indiscriminate_carnage.cooldown )
                end
            end

            if buff.finality_rupture.up then removeBuff( "finality_rupture" )
            elseif talent.finality.enabled then applyBuff( "finality_rupture" ) end

            if talent.scent_of_blood.enabled or azerite.scent_of_blood.enabled then
                applyBuff( "scent_of_blood", dot.rupture.remains, active_dot.rupture )
            end

            spend( combo_points.current, "combo_points" )
        end,
    },


    sap = {
        id = 6770,
        cast = 0,
        cooldown = 0,
        gcd = "totem",
        school = "physical",

        spend = function () return ( talent.dirty_tricks.enabled and 0 or 35 ) * ( 1 + conduit.rushed_setup.mod * 0.01 ) end,
        spendType = "energy",

        startsCombat = false,

        handler = function ()
            applyDebuff( "target", "sap" )
        end,
    },

    -- Talent: Infect the target's blood, dealing $o1 Nature damage over $d. If the target survives its full duration, they suffer an additional $328306s1 damage and you gain $s6 use of any Stealth ability for $347037d.    Cooldown reduced by $s3 sec if Sepsis does not last its full duration.    |cFFFFFFFFAwards $s7 combo $lpoint:points;.|r
    sepsis = {
        id = function() return talent.sepsis.enabled and 385408 or 328305 end,
        cast = 0,
        cooldown = 90,
        gcd = "totem",
        school = "nature",

        spend = 25,
        spendType = "energy",

        startsCombat = true,

        toggle = "cooldowns",

        cp_gain = function()
            if buff.shadow_blades.up then return 7 end
            return 1 + ( talent.seal_fate.enabled and buff.cold_blood.up and 1 or 0 ) + ( buff.broadside.up and 1 or 0 )
        end,

        handler = function ()
            applyBuff( "sepsis_buff" )
            applyDebuff( "target", "sepsis" )
            debuff.sepsis.exsanguinated_rate = 1
            gain( action.sepsis.cp_gain, "combo_points" )
        end,

        copy = { 385408, 328305 }
    },

    -- Talent: Embed a bone spike in the target, dealing 1,696 Physical damage and 141 Bleed damage every 2.8 sec until they die or leave combat. Refunds a charge when target dies. Awards 1 combo point plus 1 additional per active bone spike.
    serrated_bone_spike = {
        id = function() return talent.serrated_bone_spike.enabled and 385424 or 328547 end,
        cast = 0,
        charges = function () return legendary.deathspike.equipped and 5 or 3 end,
        cooldown = 30,
        recharge = 30,
        gcd = "totem",
        school = "physical",

        spend = 15,
        spendType = "energy",

        startsCombat = true,
        cycle = "serrated_bone_spike",

        cp_gain = function () return ( buff.broadside.up and 1 or 0 ) + active_dot.serrated_bone_spike end,

        handler = function ()
            applyDebuff( "target", "serrated_bone_spike" )
            debuff.serrated_bone_spike.exsanguinated_rate = 1
            gain( action.serrated_bone_spike.cp_gain, "combo_points" )
            if soulbind.kevins_oozeling.enabled then applyBuff( "kevins_oozeling" ) end
        end,

        copy = { 385424, 328547 }
    },

    -- Talent: Allows use of all Stealth abilities and grants all the combat benefits of Stealth for $d$?a245687[, and increases damage by $s2%][]. Effect not broken from taking damage or attacking.$?s137035[    If you already know $@spellname185313, instead gain $394930s1 additional $Lcharge:charges; of $@spellname185313.][]
    shadow_dance = {
        id = 185313,
        cast = 0,
        charges = function ()
            if state.spec.subtlety and talent.shadow_dance.enabled then return 2 end
            return talent.enveloping_shadows.enabled and 2 or nil end,
        cooldown = 60,
        recharge = function ()
            if state.spec.subtlety and talent.shadow_dance.enabled then return 60 end
            return talent.enveloping_shadows.enabled and 60 or nil
        end,
        gcd = "off",

        startsCombat = false,

        toggle = "cooldowns",
        nobuff = "shadow_dance",

        usable = function () return not stealthed.all, "not used in stealth" end,
        handler = function ()
            applyBuff( "shadow_dance" )

            if talent.danse_macabre.enabled then
                applyBuff( "danse_macabre" )
                wipe( danse_macabre_tracker )
            end
            if talent.master_of_shadows.enabled then applyBuff( "master_of_shadows" ) end
            if talent.premeditation.enabled then applyBuff( "premeditation" ) end
            if talent.shot_in_the_dark.enabled then applyBuff( "shot_in_the_dark" ) end
            if talent.silent_storm.enabled then applyBuff( "silent_storm" ) end
            if talent.soothing_darkness.enabled then applyBuff( "soothing_darkness" ) end

            if state.spec.subtlety and set_bonus.tier30_2pc > 0 then
                applyBuff( "symbols_of_death", 6 )
                if debuff.rupture.up then debuff.rupture.expires = debuff.rupture.expires + 4 end
            end

            if azerite.the_first_dance.enabled then
                gain( 2, "combo_points" )
                applyBuff( "the_first_dance" )
            end
        end,
    },

    -- Step through the shadows to appear behind your target and gain 70% increased movement speed for 2 sec. If you already know Shadowstep, instead gain 1 additional charge of Shadowstep.
    shadowstep = {
        id = 36554,
        cast = 0,
        charges = function()
            if talent.shadowstep.enabled and talent.shadowstep_2.enabled then return 2 end
        end,
        cooldown = function() return 30 * ( 1 - 0.333 * talent.intent_to_kill.rank ) end,
        recharge = function()
            if talent.shadowstep.enabled and talent.shadowstep_2.enabled then return 30 * ( 1 - 0.333 * talent.intent_to_kill.rank ) end
        end,
        gcd = "off",

        talent = "shadowstep",
        startsCombat = false,
        texture = 132303,

        handler = function ()
            applyBuff( "shadowstep" )
            setDistance( 5 )
        end,
    },

    -- Talent: Attack with your poisoned blades, dealing 319 Physical damage, dispelling all enrage effects and applying a concentrated form of your active Non-Lethal poison. Your Nature damage done against the target is increased by 20% for 8 sec. Awards 1 combo point.
    shiv = {
        id = 5938,
        cast = 0,
        charges = function()
            if talent.lightweight_shiv.enabled then return 2 end
        end,
        cooldown = 25,
        recharge = function()
            if talent.lightweight_shiv.enabled then return 25 end
        end,
        gcd = "totem",
        school = "physical",

        spend = function () return ( talent.tiny_toxic_blade.enabled or legendary.tiny_toxic_blade.enabled ) and 0 or 30 end,
        spendType = "energy",

        talent = "shiv",
        startsCombat = true,

        cp_gain = function () return 1 + ( buff.shadow_blades.up and 6 or 0 ) + ( buff.broadside.up and 1 or 0 ) end,

        handler = function ()
            gain( action.shiv.cp_gain, "combo_points" )
            removeDebuff( "target", "dispellable_enrage" )
            if talent.improved_shiv.enabled then applyDebuff( "target", "shiv" ) end
        end,
    },

    -- Extend a cloak that shrouds party and raid members within 30 yards in shadows, providing stealth for 15 sec.
    shroud_of_concealment = {
        id = 114018,
        cast = 0,
        cooldown = function() return talent.stillshroud.enabled and 180 or 360 end,
        gcd = "totem",
        school = "physical",

        startsCombat = false,

        toggle = "interrupts",

        usable = function() return stealthed.all, "requires stealth" end,
        handler = function ()
            applyBuff( "shroud_of_concealment" )
        end,
    },

    -- Finishing move that consumes combo points to increase attack speed by 50%. Lasts longer per combo point. 1 point : 12 seconds 2 points: 18 seconds 3 points: 24 seconds 4 points: 30 seconds 5 points: 36 seconds
    slice_and_dice = {
        id = 315496,
        cast = 0,
        cooldown = 0,
        gcd = "totem",
        school = "physical",

        spend = function()
            if buff.goremaws_bite.up then return 0 end
            return talent.tight_spender.enabled and 22.5 or 25
        end,
        spendType = "energy",

        startsCombat = false,
        texture = 132306,

        usable = function() return combo_points.current > 0, "requires combo points" end,

        handler = function ()
            removeStack( "goremaws_bite" )
            if talent.alacrity.enabled and combo_points.current > 4 then
                addStack( "alacrity" )
            end
            applyBuff( "slice_and_dice" )
            spend( combo_points.current, "combo_points" )
        end,
    },

    -- Increases your movement speed by 70% for 8 sec. Usable while stealthed.
    sprint = {
        id = 2983,
        cast = 0,
        cooldown = function () return 120 * ( talent.improved_sprint.enabled and 0.5 or 1 ) * ( pvptalent.maneuverability.enabled and 0.5 or 1 ) end,
        gcd = "off",

        startsCombat = false,
        texture = 132307,

        toggle = "interrupts",

        handler = function ()
            applyBuff( "sprint" )
        end,
    },

    -- Conceals you in the shadows until cancelled, allowing you to stalk enemies without being seen.
    stealth = {
        id = 1784,
        cast = 0,
        cooldown = 2,
        gcd = "off",
        school = "physical",

        startsCombat = false,
        texture = 132320,

        usable = function ()
            if time > 0 then return false, "cannot stealth in combat"
            elseif buff.stealth.up then return false, "already in stealth"
            elseif buff.vanish.up then return false, "already vanished" end
            return true
        end,

        handler = function ()
            applyBuff( "stealth" )

            if talent.improved_garrote.enabled then applyBuff( "improved_garrote" ) end
            if talent.premeditation.enabled then applyBuff( "premeditation" ) end
            if talent.silent_storm.enabled then applyBuff( "silent_storm" ) end
            if talent.take_em_by_surprise.enabled and buff.take_em_by_surprise.down then
                applyBuff( "take_em_by_surprise" )
                stat.haste = state.haste + 0.1
            end

            if conduit.cloaked_in_shadows.enabled then applyBuff( "cloaked_in_shadows" ) end
            if conduit.fade_to_nothing.enabled then applyBuff( "fade_to_nothing" ) end
        end,

        copy = 115191
    },

    -- Talent: Restore 100 Energy. Mastery increased by 13.6% for 6 sec.
    thistle_tea = {
        id = 381623,
        cast = 0,
        charges = 3,
        cooldown = 60,
        recharge = 60,
        icd = 1,
        gcd = "off",
        school = "physical",

        spend = -100,
        spendType = "energy",

        talent = "thistle_tea",
        startsCombat = false,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "thistle_tea" )
        end,
    },

    -- Talent: Redirects all threat you cause to the targeted party or raid member, beginning with your next damaging attack within the next 30 sec and lasting 6 sec.
    tricks_of_the_trade = {
        id = 57934,
        cast = 0,
        cooldown = 30,
        gcd = "off",

        talent = "tricks_of_the_trade",
        startsCombat = false,

        usable = function() return group, "requires an ally" end,

        handler = function ()
            applyBuff( "tricks_of_the_trade" )
        end,
    },

    -- Allows you to vanish from sight, entering stealth while in combat. For the first 3 sec after vanishing, damage and harmful effects received will not break stealth. Also breaks movement impairing effects.
    vanish = {
        id = 1856,
        cast = 0,
        charges = 1,
        cooldown = function() return 120 * ( pvptalent.thiefs_bargain.enabled and 0.667 or 1 ) end,
        recharge = function() return 120 * ( pvptalent.thiefs_bargain.enabled and 0.667 or 1 ) end,
        gcd = "off",

        startsCombat = false,
        texture = 132331,

        disabled = function ()
            if ( settings.solo_vanish and solo ) or group or boss then return false end
            return true
        end,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "vanish" )
            applyBuff( "stealth" )

            if talent.improved_garrote.enabled then applyBuff( "improved_garrote" ) end
            if talent.invigorating_shadowdust.enabled then
                for name, cd in pairs( cooldown ) do
                    if cd.remains > 0 then reduceCooldown( name, 15 * talent.invigorating_shadowdust.rank ) end
                end
            end
            if talent.premeditation.enabled then applyBuff( "premeditation" ) end
            if talent.silent_storm.enabled then applyBuff( "silent_storm" ) end
            if talent.soothing_darkness.enabled then applyBuff( "soothing_darkness" ) end
            if talent.take_em_by_surprise.enabled and buff.take_em_by_surprise.down then
                applyBuff( "take_em_by_surprise" )
                stat.haste = state.haste + 0.1
            end

            if conduit.cloaked_in_shadows.enabled then applyBuff( "cloaked_in_shadows" ) end
            if conduit.fade_to_nothing.enabled then applyBuff( "fade_to_nothing" ) end
        end,
    },


    wound_poison = {
        id = 8679,
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        essential = true,
        texture = 134197,

        readyTime = function () return buff.wound_poison.remains - 120 end,

        handler = function ()
            applyBuff( "wound_poison" )
        end,
    },

    -- TODO: Dragontempered Blades allows for 2 Lethal Poisons and 2 Non-Lethal Poisons.
    apply_poison_actual = {
        name = "|cff00ccff[" .. _G.MINIMAP_TRACKING_VENDOR_POISON .. "]|r",
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",

        startsCombat = false,
        essential = true,

        next_poison = function()
            if buff.lethal_poison.down or talent.dragontempered_blades.enabled and buff.lethal_poison.stack < 2 then
                if talent.amplifying_poison.enabled and buff.amplifying_poison.down then return "amplifying_poison"
                elseif action.deadly_poison.known and buff.deadly_poison.down then return "deadly_poison"
                elseif action.instant_poison.known and buff.instant_poison.down then return "instant_poison"
                elseif action.wound_poison.known and buff.wound_poison.down then return "wound_poison" end

            elseif buff.nonlethal_poison.down or talent.dragontempered_blades.enabled and buff.nonlethal_poison.stack < 2 then
                if talent.atrophic_poison.enabled and buff.atrophic_poison.down then return "atrophic_poison"
                elseif action.numbing_poison.known and buff.numbing_poison.down then return "numbing_poison"
                elseif action.crippling_poison.known and buff.crippling_poison.down then return "crippling_poison" end

            end

            return "apply_poison_actual"
        end,

        texture = function ()
            local np = action.apply_poison_actual.next_poison
            if np == "apply_poison_actual" then return 136242 end
            return action[ np ].texture
        end,

        bind = function ()
            return action.apply_poison_actual.next_poison
        end,

        readyTime = function ()
            if action.apply_poison_actual.next_poison ~= "apply_poison_actual" then return 0 end
            return 0.01 + min( buff.lethal_poison.remains, buff.nonlethal_poison.remains )
        end,

        handler = function ()
            applyBuff( action.apply_poison_actual.next_poison )
        end,

        copy = "apply_poison"
    },
} )


spec:RegisterRanges( "pick_pocket", "sinister_strike", "blind", "shadowstep" )

spec:RegisterOptions( {
    enabled = true,

    aoe = 3,
    cycle = false,

    nameplates = true,
    rangeChecker = "pick_pocket",
    rangeFilter = false,

    canFunnel = true,
    funnel = false,

    damage = true,
    damageExpiration = 6,

    potion = "phantom_fire",

    package = "Assassination",
} )


spec:RegisterSetting( "priority_rotation", false, {
    name = "Funnel AOE -> Target",
    desc = "If checked, the addon's default priority list will focus on funneling damage into your primary target when multiple enemies are present.",
    type = "toggle",
    width = 1.5
} )

spec:RegisterSetting( "envenom_pool_pct", 50, {
    name = "Energy % for |T132287:0|t Envenom",
    desc = "If set above 0, the addon will pool to this Energy threshold before recommending |T132287:0|t Envenom.",
    type = "range",
    min = 0,
    max = 100,
    step = 1,
    width = 1.5
} )

spec:RegisterStateExpr( "envenom_pool_deficit", function ()
    return energy.max * ( ( 100 - ( settings.envenom_pool_pct or 100 ) ) / 100 )
end )

spec:RegisterSetting( "mfd_points", 3, {
    name = "|T236340:0|t Marked for Death Combo Points",
    desc = "The addon will only recommend |T236364:0|t Marked for Death when you have the specified number of combo points or fewer.",
    type = "range",
    min = 0,
    max = 5,
    step = 1,
    width = "full"
} )

spec:RegisterSetting( "solo_vanish", true, {
    name = "Allow |T132331:0|t Vanish when Solo",
    desc = "If unchecked, the addon will not recommend |T132331:0|t Vanish when you are alone (to avoid resetting combat).",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "allow_shadowmeld", nil, {
    name = "Allow |T132089:0|t Shadowmeld",
    desc = "If checked, |T132089:0|t Shadowmeld can be recommended for Night Elves when its conditions are met.  Your stealth-based abilities can be used in Shadowmeld, even if your action bar does not change.  " ..
        "Shadowmeld can only be recommended in boss fights or when you are in a group (to avoid resetting combat).",
    type = "toggle",
    width = "full",
    get = function () return not Hekili.DB.profile.specs[ 259 ].abilities.shadowmeld.disabled end,
    set = function ( _, val )
        Hekili.DB.profile.specs[ 259 ].abilities.shadowmeld.disabled = not val
    end,
} )


spec:RegisterPack( "Assassination", 20231127, [[Hekili:D3ZAZTnos(BX1wLgPyBfj6htYCwERmjZExYEzUPgNBVVzzAkklEwIuhF4eVLl9B)6UXdcacasPiNjZw7oo2IGan63Va01JV(txF1SWY4R)1GrbNmECWpoC84XV(SZV(QYhxhF9vRdJUp8o4xsdxb)8nffHffjPHLjzP4tFCzw4mCwkYQYJGrSOSCDXp9YxExs5IQBhgLT6LfjRQwsVruE48s8VJE51xDBvYYY3NE9T2bHZU(QWQYfz5xF1vjRElmZjZMfZgECr01xHd)4XJpo4h)Pn3S5M)wYx2Cts6dX5fWkT5MYSn38PK48n3CY4n3Sm7UKOHB(WMpiFTZHx7JjPzWiWfyZnvRr4OqBuJp7NmE8MBoCZnVnpzvbUkFkE164Isy5(CC496V6i4vFpSNJxfNwgUuFE0g6Oxdd93JxgcBHFb2cPzR2CtE8)xvc7L1HPrVQE0nbe3VgIN(Bv5LlqKY4rddSVLhHB5FlSmAbBu1pC05hhCk8WpH7vas)sry6Dvi3q8MBctNbFu0ISK07qWBnaz0NfLLolbP(klZOZy4)RIxxKaO0IhtJ4ejyMa68mLXgCCacsVz5YSpRGFcH37T)g8URJtNHBPW7ctsruq4MBM9ibgLH53fdFYNxed4OFVADzvUawBI6(Cw1s4bzig6ZjfWatZGp(w4xQk0ajarHKma9mA4p2KKcpNbYZGPBvckXaadWb)WMBa6s(JdV(QLjfLfKKtzC4syjrXOFLKiJtdVDj83)81xnplFAA8xkXNCvyexSllB508yUih8SaJ3smWcyfzIl5jRzF0hdVh2ofeAafrwe(qSa0QwdiUQCcy)7WplUnmnMHObu6CGqdmXrlIJU)6RGzSmopjeuueUe2tdVx8cd5aYMB6T5M(WmMP(WYKO7Pf4PNqwJSLZY(CQYZryyG4vpaE74BRMpFiUtON1t)JagDKOV5MlaQH4nPhhZ4tGxcXqN4adjxyd0KY2pjfXpHZqMV3fMgbF0CuPrrA46IfzLL025xtUBrzbGlUpoxf7Wbv81NodF7Aq(YjBUjWfaFQdaMpkdWvkuGKuC6ldrWg4QytEnDvBNOcOXZNhdRXdXtbD23MnDniixYHYtz4D7est4VMKaV5j4E5SDBVia5pgcIiacxy8HrsqzQLXcr8TBNqW7kAANgYN1PHv5HcwSd4JrJWXF2dHWQaBLHmiykhaG955o2NrmnntlzkAGp4Xi5lwqI21qpOoB5sXZya9j06MhphK5xGZo93TVnzsqs4DwCy5IvH53pvQsMjgEBwrb9cZrM4PAeWGrSXCGI0QCIaAD4ShfIDmygymwb7TSPZsa48yeUf87BU5CdADtDW4FCYHIjRGXrle1meZau(p6aLFxyEEwzClOAHM3HjRwNN9q8SP83tG(uvVa)54aAhXynitxtPFxoSbmK1AWHNYK1lj3pqS4y2N3N)Uja6hXcRiBNtJcZtbNSemyHmQkkUjbNli7C1mgdNhMonB(07tHHYw4bcox7mODLefyqIEph1S5M)DgWG21wVEjq2rTG)oJRemEco8X2EkJT4iC7eLvLY0sskofg9zkMqyHBr(9AOfWcndVG05xzqN3gIOlQHMTJtLS5EqFU1BOoxNiOfQYLGqZ8KOKsM85yYlsGB6finHSFwSipRcC8zAbSizrK)YctPn5RbuYRDW6NZ8YXGmk99XI5m3IyMg)rNoY3sLToOasJ82v0IedUH(A1nKZbxJ6AV6HW0KIf2CzsBBFfJ7a4L4kVaq7FqVkGfiNojwYgm5c(53jwBdxXG)npCA4kKZ(6Ro9SDY5S6TSjuBXDJ0S0Jv8kPiUSADHkL4ajRKDxX4p0ukrBmsv8IhYvjXDJt8PUKOuhJM5kjX2kjvZvqvJlkYNbTpm0(YO2L963IQ0l)ReN7aBUn2DS9bDdHZhJHofZzcXRCX6HMUbOJZRrfN8vHY1WL9B6gUvXtvc2P1CemlL1omoqc38NOP80HaIhxI5Qc0fHec5KUT1OFkkY2cplLs3mX9SQs3gHSs7BHUj4aSBU)FzeopD)k05kCbDnRwubRQH2J74E5xiDTGlJHpqCic)ye2d2BCh)zI1WpLdDz0JN4TJTBgFxJKqyjFdDa5AxZSEyS6rRAzaQX56rJN2Bxpa(BBZf2UHGcxU82WO7DGQSZ39hQfhRkr(MBeH8rKs)Lfpe9KEmwIWejelzUaFHygqRwMcp5rykj)C4JfS0xEelEO15jzajj5FgZt)YYqmS2xHESHHDx05uNvtpxIEK)5yk4Cc5PomJChjjGwYBMcDtJRwHwR(5UZDNhPiAR6i3E6z(6u9e9X3Rg5kPERIZPRqZemjMVSk3cogl53iAbohfuKyVYM76DKA99kPQnsrD0yDcbPl74jXQoLTIclWztjtaV8n5egEjpXERJJO)ikjpQAfejk4)NnXMq(RnfCVlkPqjE59iM1PprTIQS4XAJTax3LDX(2ul8nz)3N()soiAQ47ZPZZzuBKyb6)hn81uAn6IOqTKmlnAOg0PQgtotYtAt7V4ZByOTB0g0rZgCYUC70cN8FtAvgTqKMPY0YyVdXmKTBXl2oz1lZZ(HM)9JczWo(kWf5PrZk8zlFDg7F1l2f8IGRRaUoRQqlhqBU534VqKEPAUDzw2SLvaScXmgv2scYbxng5mxv(s(dTmtNxL)ydh)ahiqGvYrbczW)wWcLfRfjkRGeawejcrtnnKoGg3PZW2ludSX5fX5c)yDRuZ7KmpjpM212K1QNJ(TRb0LhMMC(dKjDF3MUDZ3hfnlKHlii1LqCDlxY4LH95kVmYHflavRqawG3JtJxH4(SQLxFvvrm8PZNEx0mkdKSgYW1O1qOB)obDkWRxbbMLj4kb76BdXcN)jiaU7XkU4rga5FJZVfq5ftVnhqwlCTlTnYg7ql2c8c)ECEjCjOfd0dnDD1)8FcQ1Un7loja2gQIiHdvSTKrLGwaCtzqhwNIiAb5QvfRheaVPWMvrqD0XIsT58NZSkxSeRkaZnXE(ZtKJ6hwli2YkeOA(HnIHLbdLilE5gXj7a3cUTKxtoenqop(akqAg)fatXFOsByi)epopWhtW2HPdE2X0JTHPh)DfMoGPWCw88WQLLTwPNFpUquRh0PS1Gj7KBXmw0h9p7HQLPX5H0heNgVkb9WaJ2atzzyPQ7GSzXNIR7tWoGrVkPPaXff0zvWwGyygTdzDUurYQvKqycoy2KvimJd6qkn8xSUYMmRhnuxLbMxlWEFOovsm8l(BlRInAMaZm3DrZI9(wrJbGAYrqN62hEIqavWy9dlWTiv(3uoY8rALNYui2ORim1v1oudZz(DpcSs3fNsLvmjfTvFjv1lSqYf8NvUatmfGQBSneVZVqtfwM67WoalnoEg(XuvbcbTYyJhQa8SPv8eRUQWb)K5AfHg4LVnlTcdrjo)KXtpDDKjmvJj)m6e3cwZMXAUmITiRkNWNaaRctPzLtXuFJUF5cNnnEzrSplHchYDKHGwRbRwo7KI9LlskkrIDC4W5vlXSZZCFFkRQ(xOPvItwxhXRjWRgjP4FFd49TN6gTptxvSN9St93VEKTIwyLDRf9U1rRBKA02D8qdUm4G)14Vuw39gkQ4iu2TGVgZyA)ukRgQGNiwIE7e7Zd20tFmTEBWe(hkzSfksAMzG24)DSXLSzU382QGrKLEmjp7UQygj0xJNGp3SpruPqJW5mpjQuRVoXOeMY(JPy7HYAsub6q2MOEQLG3zaJG2tFJuSmjkEkqGMolPrhj8ByPrVk9DSMefiELGZ(OraY5Y3Ipf1Psz8(TlawHJKnSMWcNSV(qvGOxOKrXAkVMTpMSRgePgxMDxQn7)KaPJhICzuvIT9egRuecKAXbAwMdl9ZcI(gpQTK65Dv8SXS9ivzZZCcwsAOOJkr40vaME5raKl9YUC9X)ldH4hXEF3zAGRruVDOoJsCOv7(krLLhb6)buBEoGMPLH8TW45RRiDb1looWZuhiLzYIP)VvZUdBtEZXEU6yVn8ok8Aqy9(c9rcViMIoYbYwDp9x(smWxetw8bzMyHNN4FFxc2B838MOO41irfB1hWA0kWYeRBaj)erNUgQSBXmmI8bfWFzXzvVUzj0X2WpCn2564ca24PyOJddtFC6S1f2JtR5OqXpBHxiK6zKFBH6vpIb2DK6ZlsWtOa)Db1XyWdY(zNcZ9FGA9R1(pE38HoWkoX2U1wevTGtSUJVSnK2a)0qHt3MH0OZN7mF3g2bK84tLvWuRlAv0BAA0ip(4iQ8NxHZj36)7OFvngnEGEmThEsnM9(f)D07Hnl3QW7Gz(n3MSempHr4G)V6ZlcmMtbTm9p7qz39D1a2ziHLg)seKihTpcZDY61chAcxTEzYC2rkHjXrzsb0iCeFa0)LSkK5f5mCw5fegdYmml(6U3ZKh6WlnkI8E6r3ReCGMBV1qmxfXqcE52f5oH6eoaay90vHFzkD2AAg(Ur2(hS16F4EJzTBHKDLI7nPtyzRJ5IAT1LlXZSrTefMPp(N6jjHRQktwsXpACaBeN(I3gwvuIo9E16WYs9JfIWvb2qa8mnIg9PI7QZWPZMtGr0pMp2suk9uWL1BC6ZDJM7sTn)Z6ER2c7QBRkwytv5)6TxLmZwcbvAyioNYkcMPJyausU3K3NFUaU6NVsM4Rn1NKdzlwgk2xS2lN3YmpEe(RXZHvHqrY3JFw(kYGLf7i95L4)qHAqhYW8hfdwLY4bzWQOCJndDIlkRBylxD0Mv8WEBHBEIv8eVx7KK)ECmWknphTaIM0iuPSgRObQBRYtzwhjukPWpBop08IUSZCgP7fytb8kb3UVJz0zgjOXYgBiAqsc5hl3fATHaoxJggCg3OKZyDBfV9)qNy0p(gwcpjFdqu0ca0RdA9iXjxL5oXvuNcSFWxEm32Zm5wTewQvWGsEM7YAhmsXTl2H6fEo)m96n8sTKm3OYuPmER)opf0iknq90EHmKNu7F2NAFJi1KkuJmnpRK7NCV26DvM2ZdvtMdpdp19XYS8W7YsPoyih5ywgc7PAn8d8gVSb2W3Pr7azoqNjdStvZG)TQipPn6ZdXdAycYVnJwXBN0gTLmaWmiW2mfmpXssdjNofEol1Ed7oK8tFcarXZ0ndWyjeB9n3i27dySrN8jRjEWWyUH9k6dzaYpdUxoRizw8l1o9nCV4dfnYj7eqH(psbBGBywgrHa4Fxgxtrfw2vXKB5ev3tjhPd7ihoV7u4aP0bbMEaBNfrL(7Ub3TAJx6j76nQ7hlHVY1vhCguNsgVUl)vleCGNWC45sBNyRN0SGyFk82J)ihY1yPFhbHyBeXchK0Kj5wRZ5u3dCOUS9FSgv5JZGf2SJ(IQ9WVQtlQZEb3HsfttLHjLns8pLxyJdthAnLDLqWIlJgJsp(xhbMKJdIcT(0kVBHz6TDI0C6WrNWeyhYKJwha3(emDGfbupXnyRuuEQrVKXXoo11yST7mY7snXw0zAvujGKjtrURos5U3aDNQA9rCobkcHm2vscJkH0dXfgc8C8vka98fZtWCbBJqOH(90DAzQhPb9UuONrtp69eu40mBxEzxNuh1j17XL12r4gZzIJclYEIA)nq2kSfvRg19)gTVvWLrr(d1Ms84iTM8Itl5KX3gMwctd3ApQUmjIXVlabVfrG1GCwcd1IUql8aT4z7eDxBLtGT49SLkjcD8g5EsEZPuqhcSoTbf9BSZy68CUGfnz3)bGWzPddf9yhKzlhQBFNFklkdDOCPFln6dg(2iJu2zLYynKSi1(IYBr7BCHVCUqS4ReQ939G(4LgRCWVLiuRHJjgLsNhy6m6dzjOu0dX5ICpZki2rChkrui)C4FU84eXCbvU2C3vPXhkcrU2h0O6oGMDLiPMLBE80xBPsSQ9lrn(1AP8gnYDT8AQO1Ljzry(xQ1nf7uVSsyl96aBN3Fhzd2O1Y6Nl8d2B1aznF(l)DwRD)Y)lMMtSp33O2q3DsFIS74TfhQgPuRHYO9IZmrmH6rHoT(8ZVOTGVIu6yfpvToc2Wtf9gEjRi07KlT9BXbFLBBJi4N4JOLDyEy690Jz8A4PrgntO7VdV(sOa6gX1wIETMKLMuMnTvHFjzv1kq7Ce5BdkS(Z4skkGeZHOOkQM2l17KocgRlsdvqg6L2nhHzQw134kvfQoDtUxxdh)J5oOX3Cxj6BoH2fQJ24lbDjWW2Tls4xAwQOOM7CEB4Ly3VAjZZx5LReRxBnB(dBUG17FLVZLWSW9jbEruWmwX0bRQvywpJ59sjPt3MV2csI4sQrFDLbdwT((4ykcGLfzKTkCjlzLk9nz)cZ3f843OSOkmdouRm08g2HrnC7mTjnVd4YXb2CCUX((zcavzSm6uv65TMZUGTyFAToeUknul35q7rkENKa7okTd4I(IIY3VoLWHGVOP3nTavQnlpEzTFeVqC0fpuVq9nOxVq4)6aF1AsIyF2Wa9BHVQr92n0nVfAIE(XKBvXZArnf)MVsEo8Udzmdlr3RPOavoD)ylKiARl2LLf4ruSyGXZq3gyHmVGh4212BGgctUJ6mqcLMze0dwE)m3fLdNOKKbxZZle6q2QzRnwJbe3XPDWJ0sMdI8l5x5vgmyI7ZH5yhfdUO8jKUKSAnLMEIa8dshF)b59Jl6awg5cxvz2kgJe4hF6D0TH7)zcMM(GFcpZO4vkm94FWm6HFGP3QXNl4HHN3F8xgiNVxzF(SDZVzm1(UC4QxLnFWYEN5E(FSBChZNzIYmMwx5rZC2pzpdToMVNxO1GV3yYDKHEZ5(0V9ZT9lWitCJ3B5OUUs7h8)5pJ4ihZ9ZaoY1kTFWr)4ZioYXCVZsRouQUNWeoM9VsmHvf1y6n3o10J3ZOY9TAFhQ6AEbxymXUVbm6OQcwnomMv9RlJoot78E3X8Th37NTNHyhZ3ZpeVvulRIoIuGUDIpFJqG7W8zDtsfgB72Hnyc5NQaZJuVeYCDM7BL7ENNy3yp(RyEO0BmLwgGFYYopXUOm8JO(2rBETDUfZdpMbtJRZwM5MM(Yh55y6TIaKhrKTdf0WEJKYyEQzSqBSme)gZKSOTo5whsNMClNwhFSvkJ5zD6BDITCmK8j6UTW9Uo9U9KyFsmDn57f2q3q(UHsEMN(wN4DLfSJW9Uo9ovnthoSTtTKd3wnodgMAoTFcqm33oClCVm3o8)yVm3JDeRH1MJ2yj82a1TyzzRDQBFhdZZBYiEENDhbVUZ4cxov89WeAx6pBlf9DKwLgvPWKd3vvmm3Wos(XEy(38H3tBDCAXo(JvKJn3qFnJbpNQ9D01)AWzVgpsVzZtWod4VGFlUTxoy6B(a)VhkDgCI6ruFZhG1ABp62wM0dN8srLGocBwGj8zP(4pFe1UdtgFuY8jUnL3R)bUDI4PN8yp6YjEmYo4RbKdub5MqLci3C)udYwGQl9SDCaXIltlKS11ZXTJzs78KFuJJtoJsPweSpqR6x3f6LewMOUt2lxtxYPg2C4vbgc(hO3BveZ(UDxAPo76SnAhdmolJN6WDrahm2I7cl3lUrvx5lV1U87sx3sxQ6a629GLB4r5mHFu26j0vK0rYESzITlKlom33AF(90tw7SWNEY2nmfmyTgv9PNKIv(VzPUiy0GNEQVr)Q2Z2nj1ftcGHwF)rD5Kxn6PN06wOlM86rhvF)h9DWothCj693GBnkpImnVdPSXTuRu0SrHVu(i9RuQEUFLl0OrCMo3dxLa6yXu3FMTIjFFkpPfSRvkMovJtvYtp5(kR6PNCu49lh1(QdoPZSt8CFjrPckgMvqDW2VBL6z5G00tThlUCsWtpDGJmG1tXWKXBDQk4WLEjl4oMjhGNNR9PloZ3sANya72omi2DMIY40VCLWTHE3DF5KXNDO9M6U5SqxbtQFUXnUK6J0UGLit)KrlMGaJVApDaZQDpbyyBOQW(XJIl(k4oCuzpMkwZZeuhxoPMzNRQCekAJR1NxBVGqw)bCSS66oTX(ZqbLvjvtBLhy5GU1RLd5MTNBbTBUpyAHrzblNDSldgHoKBpI8Ew4hap0DmyjrT(mH1ZX5b7IjJh0RFZgQ6YXnCoy8ObedX()KCzINSRJHQxfkot(D)qg(9o9V8fq8jvEB2xZRss96ZAc9otJ5VcD6MzZ86SpdcHjPZRWQnkOpnp6ggGPCa4B4RdTbxJGGn6z4RvWiv)x9DqW6g(b9WIMXD(uD1GFvXxofdrso9gYs9944ZKZaokFyPbMlVCDW1UVt)ivpgxxC(GThOSsShyNOn(mcf)9YzRYeLP4tDThm6h2QE9ByiE0i7wIR1hPAXGTYxsHt03AOa9SE0PU48AVIQzH2cKpFLFX5m9qD6mp1nrhr9(72OzDazZO075WL3jJAmVzIdOeolnCjJjf39V5W(32TV5WQHkueIK3tEWQCUGS56RGhNgv5sR2mFz148wXp9kFUVa8NNoOMboY(36mkAK0YgctPG5lvZDAOvqWz(QUJs)JfJ63XVXE3HsEZD8BER2Wrn7)NDEZBX1UDN2X8ERxtvyhS)b8(91nV18QP6YrdF9HTXevZC3mVfxE2agxU(3fwomh6gTXug3XVbRCIJ3oSQbfzxrYFZvoqOQ2)sKQgljmmbyk2xiviUI2SgFVsz1G5jJKPFtveGGID)7fkRqx93)uK7Z2wuBVL8lcQT5TKFZpTnVK(3DsKhLwCgXsOG6mxOppD712gdzde28T)LEu9gIIbc2n4L2d(7mhsS)L20rkFbdXYF3wzDDYylMbccAdwA(vRKd4WMtFB9Qz5BlPMlNnzFpPBnWkCOPJRTVhKCd2fhrfNuuvog6qQMPrH8MmUx)UyeJvgapZtGw9jL7EQpeb3YTXb7jSjy5G17a3R3GoJbcAddeSNWaJ1k353cmal9z)P42KUMCXYK7HAjG2(jefcv5qRyiaH2RMsOuynP1ih3M0Gp7GflhRM6niTkMxZ08Gowsq510SLnUE2gRVE0KvEP5PP8YXk(kOTHDaNmhbcDDZoBbQexYBQfeqVvRC4JJZleyj1WXLbmwWWApiRXd9CUNAa0SljX)ubY)zap)xyzk8pYBgzlyol3bUAjgvDNXI7W7fxChxbTdOnZE)UVIaI9R9(nUJGTdW0rgKUy0Wx1RVT8rEMAIq9FhhFCZGiVycE3gZuAURxqXpFByh8)gEKBZ0L5fmSJv3Aqt80YVdxTWwGeTgOXfoO)bnU)D75PpCaRKhAuOlrIaS2zSdSVFiTgFlVoDBf9yru(aEKc2V8wTH5Sw6u2hAOZ2UsxVi(ty6E)E4w(1R1wRCz80guFd7k6yNMx2VqWFQn3bXJHjt1rUeB47mQoIp7QliJtChVcC9zRE75CoWPNOQv)TB8ftmdpuU787EHLLre0W3IRgmfOlRPFVUV0UeT9MhmYlejOR5TI2lcgC5FLRJDVEFF1LTt9TmdFtWeaSCfMDzn1XnMGfSXE56VYe6nYUOnoCn8pyuqRZI0lXFpNrWbc1Yn6wu5AiWgxH(nOxZUj4yryZNtOS91n3LjsJR13SMAkv6SxFZEFqfP5bWhh4AXSqz2PfVMoy0AST4lqBq9FrPPC2Z4BUbvVPiyNX49p9qrMwBCCfEXzdoSVl81loFWaxqQfI1oc59DsV0c63qTJxHJVYDSQG1Z6DnLhXoxn3OhPGNEsQxbnotn)BlEHbUI08DErq7VLBK)Glp1x57z9t0vcpIWJWcHbQrfsVLoelvtg2nZfG5lWvqaponn(lLtgZZ6d24sfK8ikTXpLkSU9zTvh)4utE)KW6frRlSZQnVfvbgCtRoBgYsQP8Ncu)4gTAdla6A4g1Qy0VretvrA46IfzCJ4)kf3maY3RM4l1TLe4Kv)sRlZfYpGUqBaKmfRi2ELmNBKial1icuUoSAfu6swrDu7hnytY)EIomkaLps8IaFgNzKxqDko4M5GzRHqcwm53dbTjuRg0efR6uCZKrz3fOtudwMouiCYExi5BV)pNOPE(7lhEEpVdnLAO)jzg8q5HFxVN1r0VYyXS4hgrU)sSgk9BHGbMhHaMjQ3RDTpHPwMU3NSJL94dJ7w7Vw5B)Xbh7keYbp9KPEEweOoUxQaomwEhMQe)(fE0OpyGZee5HEe4hr0Yg3LLRXN6mt)Ee1eVnyzYHTYddKrsz5c7t33olkB9i0zytHNFcR4MDZlV(2uIyTDeKf)wC68u6iI)b1QDIExL48BiljZaNyoR3gSo1ZJf5JGFMhonCfkDn50Z4D3uttw4jvvXYwrCz16cllKzlZ2Shdk3IM2UVAUSmz(uFMIQVboQxQNkEpoW3JV88rUyq9LdGl)RNoyNqqo7bE(NBilXsTFDZ0xBdqhbX2lNS1yhA73O7JBmjcC5P2AQQb9u(mPypVpCyC4KS6A0GIcJTWBaLZGHS0oTQOxIYv6xvxOqbk3QU5VhzzpDpYsUvkhe0lsRay1m8bIcjSvlugTpPo)rtC8HrdAIuA66AZqA8Hg8Jfu66k7TT0jUA9kxsS83Or)iPVZKj31(ESl01NjfA26CLNf9v0DL81))]] )