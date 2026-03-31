
require("scripts.processor")
require("scripts.models_lib")

if script.active_mods["factorio-test"] then
   require("__factorio-test__/init")({
      "tests/processor-lifecycle",
   }, {
      load_luassert = true,
   })
end
