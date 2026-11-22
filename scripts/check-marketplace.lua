-- Marketplace discovery/update metadata must load before plugin initialization.
local path, expected_name, version_file = assert(arg[1]), assert(arg[2]), assert(arg[3])
package.preload.gettext = function() return function(text) return text end end
local meta = assert(dofile(path))
local f = assert(io.open(version_file, "r"))
local expected_version = f:read("*a"):gsub("%s+$", "")
f:close()
assert(meta.name == expected_name, "Changing the plugin identifier can duplicate installations")
assert(type(meta.fullname) == "string" and meta.fullname ~= "", "Missing display name")
assert(meta.version == expected_version, "Metadata/release version mismatch")
assert(meta.version:match("^%d+%.%d+%.%d+$"), "Use a numeric release version")
assert(type(meta.description) == "string" and meta.description ~= "", "Missing description")
print("Marketplace metadata verified: " .. meta.name .. " " .. meta.version)
