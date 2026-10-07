# UTITypes: checks Uniform Type Identifiers (CoreServices' UTType functions and the
# UniformTypeIdentifiers framework) against the LaunchServices database. Needs no window.
add_devtest_app(UTITypes
	SOURCES
		main.m
	LIBRARIES
		CoreServices
		UniformTypeIdentifiers
		Foundation
		objc
)
