--[[
MODULE LOADER BY VYRON

An Advanced Module Loader designed to give you easy control over your modules!

[FEATURES]
You can put a "Ignore" attribute on module scripts that you want to ignore
You can put a "Delay" attribute on module scripts that will run after a set amount of time
You can put a "Dependency" attribute on module scripts with the name of the module script that it waits for to load before loading itself.


[SETTINGS]
DEBUG_MODE - Enables prints and warns, helping you identify errors with info (the amount of time taken to load a module, etc.)
WAIT_FOR_SERVER - If the client should wait for the server to finish loading modules before loading client modules
LOADING_PRIORITIES - Enables loading priorities (the order in which modules load), just give the module script an attribute called "Priority"

[HOW TO USE]
- Place this module loader in ReplicatedStorage
- Place the "Start" server script in ServerScriptService
- Place the "Start" local script in StarterPlayerScripts

]]

--!strict
local RunService = game:GetService("RunService")

export type LoaderSettings = {
	DEBUG_MODE: boolean,
	WAIT_FOR_SERVER: boolean,
	LOADING_PRIORITIES: boolean,
}

export type ModScript = { [string]: any }
export type PredicateFunction = (module: ModuleScript) -> boolean

-----[[ SETTINGS ]]-----

local SETTINGS: LoaderSettings = {
	DEBUG_MODE = true,
	WAIT_FOR_SERVER = true,
	LOADING_PRIORITIES = true,
}

local runContext = if RunService:IsClient() then "Client" else "Server"
local prefix = if runContext == "Client" then "[CLIENT]" else "[SERVER]"
local serverLoaded = false
local clientLoaded = false
local requiredModules: { [string]: ModScript } = {}

-----[[ PRIVATE ]]-----

local function modPrint(msg: string, notDebug: boolean?)
	if not notDebug and SETTINGS.DEBUG_MODE then
		print(`{prefix} {msg}`)
	else
		print(`{prefix} {msg}`)
	end
end

local function modWarn(msg: string, notDebug: boolean?)
	if not notDebug and SETTINGS.DEBUG_MODE then
		warn(`{prefix} {msg}`)
	else
		warn(`{prefix} {msg}`)
	end
end

local function modAssert(value: any, msg: string)
	if not value then
		error(msg)
	end
end

local function getSortedModules(modules: { ModuleScript }): { ModuleScript }
	local sortedModules = {}

	for _, module: ModuleScript in modules do
		table.insert(sortedModules, module)
	end

	table.sort(sortedModules, function(a: ModuleScript, b: ModuleScript)
		local aPriority = a:GetAttribute("Priority") or 1
		local bPriority = b:GetAttribute("Priority") or 1
		return aPriority > bPriority
	end)

	return sortedModules
end 

local function loadModule(module: ModuleScript, callback: (number) -> ()?)
	if module:GetAttribute("Dependency") then
		while not requiredModules[module:GetAttribute("Dependency")] do
			task.wait()
		end
	end
	
	if module:GetAttribute("Delay") then
		modPrint(`{module.Name} delayed for {module:GetAttribute("Delay")}s because of delay attribute`)
		
		task.wait(module:GetAttribute("Delay"))
	end

	local startTime = os.clock()
	local finished = false
	local recordingThread = task.spawn(function()
		while not finished do
			if os.clock() - startTime >= 5 then
				modWarn(`{module.Name} has been loading for: {os.clock() - startTime}s. Consider optimizing it.`, true)
				return
			end
			task.wait()
		end
	end)

	local success, result: ModScript = pcall(require, module)
	finished = true
	task.cancel(recordingThread)
	modAssert(success and result, `Module Loader failed loading: {module.Name}`)

	local timeTaken = os.clock() - startTime

	if SETTINGS.DEBUG_MODE then
		modPrint(`Loaded: {module.Name} for {timeTaken}s`)
	end

	if callback then
		callback(timeTaken)
	end

	requiredModules[module.Name] = result
end

local function filterModules(modules: { Instance }, predicate: PredicateFunction?): { ModuleScript }
	local filtered = {}
	for _, module in modules do
		if not module:IsA("ModuleScript") or module:GetAttribute("Ignore") then
			continue
		end

		if predicate and not predicate(module) then
			continue
		end
		
		table.insert(filtered, module)
	end

	return filtered
end

-----[[ PUBLIC ]]-----

-- Loads the given modules
local function load(modules: { any }, predicate: PredicateFunction?): { [string]: ModScript }
	modAssert(modules, "You must pass in a table of modules")

	if SETTINGS.DEBUG_MODE then
		modPrint(`Module Loader started at: {time()}s`)
	end

	-- Wait for server
	if SETTINGS.WAIT_FOR_SERVER and runContext ~= "Server" then
		while not workspace:GetAttribute("SERVER_LOADED") do
			task.wait()
		end
	end

	local filteredModules = filterModules(modules, predicate)
	local totalTime = 0

	modAssert(#filteredModules >= 1, "No modules to load inside the given table")

	if SETTINGS.LOADING_PRIORITIES then
		filteredModules = getSortedModules(filteredModules)
	end

	-- Load
	for _, module: ModuleScript in filteredModules do
		if SETTINGS.DEBUG_MODE then
			task.spawn(loadModule, module, function(timeTaken: number)
				totalTime += timeTaken
			end)

			continue
		end

		task.spawn(loadModule, module)
	end

	if SETTINGS.DEBUG_MODE then
		for _, module in filteredModules do
			while not requiredModules[module.Name] do
				task.wait()
			end
		end
		modPrint(`Loading Completed. Total Time Taken: {totalTime}s`)
	end

	if runContext == "Server" then
		workspace:SetAttribute("SERVER_LOADED", true)
		serverLoaded = true
	else
		clientLoaded = true
	end

	return requiredModules
end

local function loadDescendants(parent: Instance, predicate: PredicateFunction?): { [string]: ModScript }
	return load(parent:GetDescendants(), predicate)
end

local function loadChildren(parent: Instance, predicate: PredicateFunction?): { [string]: ModScript }
	return load(parent:GetChildren(), predicate)
end

local function runModules(modules: { [string]: any }, methodName: string)
	for moduleName, module in modules do
		task.spawn(function()
			local startTime = os.clock()
			local method: () -> () = module[methodName]

			modAssert(method, "Method not found or nil")
			modAssert(typeof(method) == "function", "Method found is not a function")

			if method and typeof(method) == "function" then
				method()
			end

			if SETTINGS.DEBUG_MODE then
				modPrint(`{moduleName} took {os.clock() - startTime} to run {methodName}`)
			end
		end)
	end
end

-- Returns the specified module
local function getModule(moduleName: string): ModScript
	return requiredModules[moduleName]
end

local function isServerLoaded(): boolean
	modAssert(runContext == "Server", "Cannot check Server Modules on the Client")
	return serverLoaded
end

local function isClientLoaded(): boolean
	modAssert(runContext == "Client", "Cannot check Client Modules on the Server")
	return clientLoaded
end

local function changeSettings(newSettings: LoaderSettings)
	SETTINGS = newSettings
end

return table.freeze({
	Load = load,
	LoadDescendants = loadDescendants,
	LoadChildren = loadChildren,
	RunModules = runModules,
	GetModule = getModule,
	IsServerLoaded = isServerLoaded,
	IsClientLoaded = isClientLoaded,
	ChangeSettings = changeSettings,
})
