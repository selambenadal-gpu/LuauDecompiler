local Constants = {}

Constants.TAG = {
	NIL = 0,
	BOOLEAN = 1,
	NUMBER = 2,
	STRING = 3,
	IMPORT = 4,
	TABLE = 5,
	CLOSURE = 6,
	VECTOR = 7,
	TABLE_WITH_CONSTANTS = 8,
	INTEGER = 9,
	CLASS_SHAPE = 10,
	VECTORD = 11,
}

function Constants.isKnownTag(tag)
	return Constants.TAG[tag] ~= nil
end

function Constants.name(tag)
	for name, value in pairs(Constants.TAG) do
		if value == tag then
			return name
		end
	end

	return "UNKNOWN"
end

return Constants
