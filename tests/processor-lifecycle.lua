local commons = require("scripts.commons")
local editor = require("scripts.editor")

local processor_name = commons.processor_name
local processor_name_1x1 = commons.processor_name_1x1
local device_name = commons.device_name
local iopoint_name = commons.iopoint_name
local EDITOR_SIZE = commons.EDITOR_SIZE

local nauvis

before_all(function()
   nauvis = game.surfaces["nauvis"]
end)

local function place_processor(name, position)
   local entity = nauvis.create_entity {
      name = name or processor_name,
      position = position or { 4, 4 },
      force = "player",
      raise_built = true,
   }
   return entity, storage.procinfos[entity.unit_number]
end

local function destroy(entity)
   if entity and entity.valid then
      entity.destroy { raise_destroy = true }
   end
end

test("2x2 processor creation produces 16 iopoints and a co-located device", function()
   local processor, procinfo = place_processor()

   assert.are_equal(16, #procinfo.iopoints)
   assert.is.falsy(processor.rotatable)

   local devices = nauvis.find_entities_filtered {
      name = device_name,
      position = processor.position,
      radius = 0.2,
   }
   assert.are_equal(1, #devices)
   assert.is.falsy(devices[1].destructible)

   for _, iopoint in pairs(procinfo.iopoints) do
      assert.is.falsy(iopoint.destructible)
      assert.is.falsy(iopoint.minable)
   end

   destroy(processor)
end)

test("1x1 processor gets exactly 4 iopoints", function()
   local processor, procinfo = place_processor(processor_name_1x1, { 10, 10 })

   assert.are_equal(4, #procinfo.iopoints)

   destroy(processor)
end)

test("destroying a processor cleans up procinfo, surface_map, and sub-entities", function()
   local processor, procinfo = place_processor(nil, { 16, 16 })
   local unit_number = processor.unit_number
   local position = { x = processor.position.x, y = processor.position.y }

   editor.get_or_create_surface(procinfo)
   local surface_name = editor.get_surface_name(processor)

   processor.destroy { raise_destroy = true }

   assert.is_nil(storage.procinfos[unit_number])
   assert.is_nil(storage.surface_map[surface_name])

   local remaining_devices = nauvis.find_entities_filtered {
      name = device_name,
      position = position,
      radius = 0.2,
   }
   assert.are_equal(0, #remaining_devices)

   local remaining_iopoints = nauvis.find_entities_filtered {
      name = iopoint_name,
      position = position,
      radius = 1.5,
   }
   assert.are_equal(0, #remaining_iopoints)
end)

test("editor surface has correct tile layout and properties", function()
   local processor, procinfo = place_processor(nil, { 24, 24 })
   local surface = editor.get_or_create_surface(procinfo)

   assert.is.truthy(surface.always_day)
   assert.is.falsy(surface.show_clouds)
   assert.is.truthy(game.forces["player"].get_surface_hidden(surface))
   assert.are_equal(procinfo, storage.surface_map[surface.name])

   local expected_ground = "compaktcircuit-ground"
   if not prototypes.tile[expected_ground] then
      expected_ground = "refined-concrete"
   end
   assert.are_equal(expected_ground, surface.get_tile(0, 0).name)
   assert.are_equal("out-of-map", surface.get_tile(EDITOR_SIZE / 2 + 1, 0).name)

   destroy(processor)
end)

test("cloning an unpacked processor transfers surface ownership to destination", function()
   local src, src_procinfo = place_processor(nil, { 32, 32 })

   local surface = editor.get_or_create_surface(src_procinfo)
   local original_surface_name = surface.name
   assert.is.truthy(src_procinfo.surface)

   local dest = src.clone { position = { 40, 40 } }
   assert.is.truthy(dest)
   local dst_procinfo = storage.procinfos[dest.unit_number]
   assert.is.truthy(dst_procinfo)

   assert.is.truthy(src_procinfo.is_packed)
   assert.is_nil(src_procinfo.surface)

   assert.is.truthy(dst_procinfo.surface)
   assert.is.falsy(dst_procinfo.is_packed)

   local expected_surface_name = "proc_" .. dest.unit_number
   assert.are_equal(expected_surface_name, dst_procinfo.surface.name)
   assert.is_nil(storage.surface_map[original_surface_name])
   assert.are_equal(dst_procinfo, storage.surface_map[expected_surface_name])

   assert.are_equal(16, #dst_procinfo.iopoints)

   destroy(dest)
   destroy(src)
end)
