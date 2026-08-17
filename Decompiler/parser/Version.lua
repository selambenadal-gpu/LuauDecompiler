local Version = {}

Version.MIN = 3
Version.MAX = 12
Version.TARGET = 9

Version.TYPE_MIN = 1
Version.TYPE_MAX = 3
Version.TYPE_TARGET = 3

function Version.isSupported(version)
	return type(version) == "number"
		and version >= Version.MIN
		and version <= Version.MAX
end

function Version.requiresProtoSize(version)
	return version >= 12
end

function Version.hasFeedback(version)
	return version >= 11
end

function Version.hasClassShape(version)
	return version >= 10
end

function Version.hasIntegerConstants(version)
	return version >= 8
end

function Version.hasTableWithConstants(version)
	return version >= 7
end

function Version.hasVectorConstants(version)
	return version >= 5
end

function Version.hasTypeInfo(version)
	return version >= 4
end

return Version
