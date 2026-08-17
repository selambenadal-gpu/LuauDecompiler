local ProtoReader = {}

function ProtoReader.new(reader, version, Definitions)
	assert(reader, "reader is required")
	assert(type(version) == "number", "version is required")
	assert(Definitions, "Definitions is required")

	return {
		reader = reader,
		version = version,
		Definitions = Definitions,
	}
end

function ProtoReader:read()
	error("ProtoReader.read() is not implemented yet")
end

return ProtoReader
