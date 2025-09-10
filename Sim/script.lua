-- Freeciv - Copyright (C) 2007 - The Freeciv Project
--   This program is free software; you can redistribute it and/or modify
--   it under the terms of the GNU General Public License as published by
--   the Free Software Foundation; either version 2, or (at your option)
--   any later version.
--
--   This program is distributed in the hope that it will be useful,
--   but WITHOUT ANY WARRANTY; without even the implied warranty of
--   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--   GNU General Public License for more details.

-- This file is for lua-functionality that is specific to a given
-- ruleset. When freeciv loads a ruleset, it also loads script
-- file called 'default.lua'. The one loaded if your ruleset
-- does not provide an override is default/default.lua.


-- Place Ruins at the location of the destroyed city.
function city_destroyed_callback(city, loser, destroyer)
  city.tile:create_extra("Ruins", NIL)
  -- continue processing
  return false
end

signal.connect("city_destroyed", "city_destroyed_callback")

-------------------
-- Unit resupply --
-------------------

-- Settings --

-- When modifying this, also see `actionenabler_resupply` in `game.ruleset`.
function is_supplier(unit)
  return unit.utype:has_flag("Supplier")
end

function is_mergeable(unit)
  return unit.utype:has_flag("Mergeable")
end

-- When modifying this, also see `actionenabler_resupply` in `game.ruleset`.
function can_resupply(unit)
  return not unit.utype:has_flag("NonMil")
end

-- How many hitpoints a unit can heal when it uses the Resupply action
resupply_action_max_heal = 30

-- End of settings --

-- How many hitpoints the unit needs.
function unit_supplies_needed(unit)
  return unit.utype.hp - unit.hp
end

-- Find the supplier with the fewest supplies remaining on the given tile.
function best_supplier(tile)
  local best = nil
  for unit in tile:units_iterate() do
    if is_supplier(unit) and not is_mergeable(unit) then
      if best == nil or best.hp > unit.hp then
        best = unit
      end
    end
  end
  return best
end

-- Check if the tile contains only supply units
function tile_has_only_suppliers(tile)
  for unit in tile:units_iterate() do
    if not is_supplier(unit) then
      return false
    end
  end
  return true
end

-- How many hitpoints all suppliable units on the tile need.
function tile_supplies_needed(tile)
  local total = 0
  for unit in tile:units_iterate() do
    if can_resupply(unit) and not is_supplier(unit) then
      total = total + unit_supplies_needed(unit)
    end
  end
  return total
end

-- Transfer supplies from the supplier to the unit up to the given amount.
function resupply_by_amount(unit, supplier, amount)
  local heal = math.min(amount, supplier.hp, unit_supplies_needed(unit))
  if heal <= 0 then return end -- No resupply needed
  edit.unit_recover_hp(unit, heal)
  edit.unit_damage_hp(supplier, heal, "used", unit.owner)
end

-- Transfer all supplies possible from the supplier to all suppliable units on
-- the tile, in round-robin order.
function resupply_tile(supplier)
  while tile_supplies_needed(supplier.tile) > 0 do
    for unit in supplier.tile:units_iterate() do
      if can_resupply(unit) and not is_supplier(unit) then
        resupply_by_amount(unit, supplier, 1)
        if not supplier:exists() then 
          return -- Supply unit is exhausted
        end 
      end
    end
  end
end

-- Unit action to resupply at the targetted supply unit.
function resupply_action_handler(action, actor, target)
  if action:rule_name() ~= "User Action 1" then return end -- Resupply
  resupply_by_amount(actor, target, resupply_action_max_heal)
end
signal.connect("action_started_unit_unit", "resupply_action_handler")

-- Automatic resupply at turn start
function auto_resupply_tile(tile)
  if tile:num_units() <= 0 then return end -- Skip empty tiles
  local supplier = best_supplier(tile)
  while supplier and supplier:exists() do
    resupply_tile(supplier)
    if supplier:exists() then
      return -- All units must have been fully supplied if this still exists
    else
      supplier = best_supplier(tile) -- If exhausted, get the next best supplier
    end
  end
end

function auto_resupply_phase()
  for tile in whole_map_iterate() do
    auto_resupply_tile(tile)
  end
end
signal.connect("turn_begin", "auto_resupply_phase")

-- Attacking supply units in cities
function citizens_mount_defence(city, attacker)
  -- TODO: Calculate chance of citizen defence
  return false
end

function attackers_steal_supplies(attacker, city)
  -- TODO: On fail, calculate stolen supplies
end

function supply_attacked_in_city_handler(action, actor, target)
  if action ~= "Attack" then return end
  local city = target:city()
  if not city then return end
  if not tile_has_only_suppliers(target) then return end
  if citizens_mount_defence(city, actor) then return end
  attackers_steal_supplies(actor, city)
end
signal.connect("action_started_unit_units", "supply_attacked_in_city_handler")

--------------------------
-- End of Unit Resupply --
--------------------------

