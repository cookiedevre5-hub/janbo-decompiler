--!native
--!optimize 2
--!strict

--[[==========================================================================
    SMART CODE GENERATOR (Gerador de Código Inteligente)
    -------------------------------------------------------------------------
    Gera código Lua/Luau a partir de descrições estruturadas (templates
    paramétricos). Suporta:
      * Funções (com parâmetros, retorno, corpo)
      * Tabelas/classes (métodos, propriedades, metatables)
      * Eventos / conexões RBXScriptSignal
      * Criação de instâncias Roblox (Instance.new + propriedades)
      * Blocos de controle (if, for, while, repeat, try/catch com pcall)
      * Injeção de dependências e imports
============================================================================--]]

local SmartCodeGenerator = {}

local function indent(level: number): string
	return string.rep("\t", level)
end

-- Escapa uma string para uso em código Lua (aspas duplas)
local function escapeLuaString(value: string): string
	local s = string.gsub(value, "\\", "\\\\")
	s = string.gsub(s, "\"", "\\\"")
	s = string.gsub(s, "\n", "\\n")
	s = string.gsub(s, "\r", "\\r")
	s = string.gsub(s, "\t", "\\t")
	return '"' .. s .. '"'
end

-- Converte um valor Lua em representação de código-fonte
local function valueToCode(value, depth: number): string
	depth = depth or 0
	local t = type(value)

	if t == "nil" then
		return "nil"
	elseif t == "boolean" then
		return value and "true" or "false"
	elseif t == "number" then
		return tostring(value)
	elseif t == "string" then
		return escapeLuaString(value)
	elseif t == "table" then
		if depth > 20 then
			return "{}" -- evita recursão infinita
		end
		local parts = {}
		local isArray = true
		local maxIndex = 0
		for k, v in pairs(value) do
			if type(k) == "number" then
				maxIndex = math.max(maxIndex, k)
			else
				isArray = false
			end
		end
		if isArray and maxIndex == #value then
			for _, v in ipairs(value) do
				table.insert(parts, valueToCode(v, depth + 1))
			end
			return "{" .. table.concat(parts, ", ") .. "}"
		else
			for k, v in pairs(value) do
				if type(k) == "string" and string.match(k, "^[%a_][%a%d_]*$") then
					table.insert(parts, k .. " = " .. valueToCode(v, depth + 1))
				else
					table.insert(parts, "[" .. valueToCode(k, depth + 1) .. "] = " .. valueToCode(v, depth + 1))
				end
			end
			return "{" .. table.concat(parts, ", ") .. "}"
		end
	elseif t == "function" then
		return "function() end" -- placeholder
	else
		return "nil" -- tipos não serializáveis viram nil
	end
end

--[[
    Gera uma função Lua.

    Params:
      name        : string (nome da função, pode ser nil para anônima)
      params      : string[] (lista de parâmetros)
      body        : string[] ou string (linhas do corpo)
      isLocal     : boolean (se é local)
      returnVals  : string[] (variáveis de retorno)
      async       : boolean (gera task.spawn / coroutine.wrapper)
]]
function SmartCodeGenerator.GenerateFunction(params: table): string
	params = params or {}
	local name = params.name or ""
	local paramList = params.params or {}
	local body = params.body or ""
	local isLocal = params.isLocal or false
	local isAsync = params.async or false

	local lines = {}
	if type(body) == "string" then
		body = {body}
	end

	local header
	if isLocal then
		header = "local function " .. name .. "(" .. table.concat(paramList, ", ") .. ")"
	else
		header = "function " .. name .. "(" .. table.concat(paramList, ", ") .. ")"
	end

	table.insert(lines, header)
	for _, line in ipairs(body) do
		table.insert(lines, "\t" .. line)
	end
	table.insert(lines, "end")

	local code = table.concat(lines, "\n")

	if isAsync then
		return "task.spawn(function()\n" .. code:gsub("\n", "\n\t") .. "\nend)"
	end

	return code
end

--[[
    Gera uma classe/tabela Lua com construtor, métodos e propriedades.

    Params:
      className   : string
      props       : {[string]: any} (propriedades padrão)
      methods     : {[string]: {params = string[], body = string[]}}
      static      : {[string]: {params = string[], body = string[]}} (estáticos)
      inherits    : string? (classe pai)
]]
function SmartCodeGenerator.GenerateClass(params: table): string
	params = params or {}
	local className = params.className or "MyClass"
	local props = params.props or {}
	local methods = params.methods or {}
	local statics = params.statics or {}
	local inherits = params.inherits

	local lines = {}
	table.insert(lines, "local " .. className .. " = {}")
	table.insert(lines, className .. "__index = " .. className)

	-- Herança
	if inherits then
		table.insert(lines, "setmetatable(" .. className .. ", {__index = " .. inherits .. "})")
	end

	table.insert(lines, "")

	-- Construtor
	table.insert(lines, "function " .. className .. ".new(...)")
	table.insert(lines, "\tlocal self = setmetatable({}, " .. className .. ")")
	for propName, defaultValue in pairs(props) do
		table.insert(lines, "\tself." .. propName .. " = " .. valueToCode(defaultValue))
	end
	table.insert(lines, "\treturn self")
	table.insert(lines, "end")
	table.insert(lines, "")

	-- Métodos de instância
	for methodName, methodDef in pairs(methods) do
		local paramsList = methodDef.params or {}
		local body = methodDef.body or {}
		if type(body) == "string" then
			body = {body}
		end
		table.insert(lines, "function " .. className .. ":" .. methodName .. "(" .. table.concat(paramsList, ", ") .. ")")
		for _, line in ipairs(body) do
			table.insert(lines, "\t" .. line)
		end
		table.insert(lines, "end")
		table.insert(lines, "")
	end

	-- Métodos estáticos
	for staticName, staticDef in pairs(statics) do
		local paramsList = staticDef.params or {}
		local body = staticDef.body or {}
		if type(body) == "string" then
			body = {body}
		end
		table.insert(lines, "function " .. className .. "." .. staticName .. "(" .. table.concat(paramsList, ", ") .. ")")
		for _, line in ipairs(body) do
			table.insert(lines, "\t" .. line)
		end
		table.insert(lines, "end")
		table.insert(lines, "")
	end

	table.insert(lines, "return " .. className)

	return table.concat(lines, "\n")
end

--[[
    Gera criação de instância Roblox.

    Params:
      className   : string (ex: "Part", "ScreenGui")
      name        : string
      parent      : string? (variável do pai)
      properties  : {[string]: any}
      attributes  : {[string]: any}
]]
function SmartCodeGenerator.GenerateInstance(params: table): string
	params = params or {}
	local className = params.className or "Part"
	local varName = params.varName or sanitizeVarName(className)
	local name = params.name or className
	local parent = params.parent
	local properties = params.properties or {}
	local attributes = params.attributes or {}

	local lines = {}
	table.insert(lines, "local " .. varName .. " = Instance.new(\"" .. className .. "\")")
	table.insert(lines, varName .. ".Name = " .. escapeLuaString(name))

	for propName, propValue in pairs(properties) do
		table.insert(lines, varName .. "." .. propName .. " = " .. valueToCode(propValue))
	end

	if parent then
		table.insert(lines, varName .. ".Parent = " .. parent)
	end

	for attrName, attrValue in pairs(attributes) do
		table.insert(lines, varName .. ":SetAttribute(" .. escapeLuaString(attrName) .. ", " .. valueToCode(attrValue) .. ")")
	end

	return table.concat(lines, "\n")
end

-- Sanitiza nome de variável a partir de um nome qualquer
local function sanitizeVarName(name: string): string
	local s = string.gsub(name, "[^%a_%d]", "_")
	local first = string.sub(s, 1, 1)
	if not string.match(first, "[%a_]") then
		s = "_" .. s
	end
	return s
end

--[[
    Gera um evento / conexão RBXScriptSignal.

    Params:
      signal      : string (ex: "button.MouseButton1Click")
      handlerName : string
      params      : string[] (parâmetros do handler)
      body        : string[]
      disconnectAfter : boolean (desconecta após primeira execução)
]]
function SmartCodeGenerator.GenerateConnection(params: table): string
	params = params or {}
	local signal = params.signal or "someSignal"
	local handler = params.handlerName or "OnEvent"
	local pList = params.params or {}
	local body = params.body or {}
	local once = params.disconnectAfter or false

	if type(body) == "string" then
		body = {body}
	end

	local lines = {}
	table.insert(lines, "local function " .. handler .. "(" .. table.concat(pList, ", ") .. ")")
	for _, line in ipairs(body) do
		table.insert(lines, "\t" .. line)
	end
	table.insert(lines, "end")

	if once then
		table.insert(lines, "local connection")
		table.insert(lines, "connection = " .. signal .. ":Connect(function(" .. table.concat(pList, ", ") .. ")")
		table.insert(lines, "\t" .. handler .. "(" .. table.concat(pList, ", ") .. ")")
		table.insert(lines, "\tconnection:Disconnect()")
		table.insert(lines, "end)")
	else
		table.insert(lines, signal .. ":Connect(" .. handler .. ")")
	end

	return table.concat(lines, "\n")
end

--[[
    Gera um bloco de controle condicional.

    Params:
      condition : string
      thenBody  : string[]
      elseBody  : string[]?
      elseif    : {{condition = string, body = string[]}}?
]]
function SmartCodeGenerator.GenerateIf(params: table): string
	params = params or {}
	local condition = params.condition or "true"
	local thenBody = params.thenBody or {}
	local elseBody = params.elseBody or {}
	local elseifList = params.elseif or {}

	if type(thenBody) == "string" then
		thenBody = {thenBody}
	end
	if type(elseBody) == "string" then
		elseBody = {elseBody}
	end

	local lines = {}
	table.insert(lines, "if " .. condition .. " then")
	for _, line in ipairs(thenBody) do
		table.insert(lines, "\t" .. line)
	end

	for _, elseifBlock in ipairs(elseifList) do
		table.insert(lines, "elseif " .. elseifBlock.condition .. " then")
		local eBody = elseifBlock.body or {}
		if type(eBody) == "string" then
			eBody = {eBody}
		end
		for _, line in ipairs(eBody) do
			table.insert(lines, "\t" .. line)
		end
	end

	if #elseBody > 0 then
		table.insert(lines, "else")
		for _, line in ipairs(elseBody) do
			table.insert(lines, "\t" .. line)
		end
	end

	table.insert(lines, "end")

	return table.concat(lines, "\n")
end

--[[
    Gera um loop for numérico.

    Params:
      var     : string (variável de controle)
      from    : string/number
      to      : string/number
      step    : string/number?
      body    : string[]
]]
function SmartCodeGenerator.GenerateFor(params: table): string
	params = params or {}
	local var = params.var or "i"
	local from = params.from or "1"
	local to = params.to or "10"
	local step = params.step
	local body = params.body or {}

	if type(body) == "string" then
		body = {body}
	end

	local lines = {}
	local stepStr = step and (", " .. tostring(step)) or ""
	table.insert(lines, "for " .. var .. " = " .. tostring(from) .. ", " .. tostring(to) .. stepStr .. " do")
	for _, line in ipairs(body) do
		table.insert(lines, "\t" .. line)
	end
	table.insert(lines, "end")

	return table.concat(lines, "\n")
end

--[[
    Gera um loop genérico (for in / pairs / ipairs).

    Params:
      vars    : string[] (variáveis, ex: {"k", "v"})
      iter    : string (iterador, ex: "pairs(table)")
      body    : string[]
]]
function SmartCodeGenerator.GenerateForIn(params: table): string
	params = params or {}
	local vars = params.vars or {"k", "v"}
	local iter = params.iter or "pairs({})"
	local body = params.body or {}

	if type(body) == "string" then
		body = {body}
	end

	local lines = {}
	table.insert(lines, "for " .. table.concat(vars, ", ") .. " in " .. iter .. " do")
	for _, line in ipairs(body) do
		table.insert(lines, "\t" .. line)
	end
	table.insert(lines, "end")

	return table.concat(lines, "\n")
end

--[[
    Gera um bloco pcall (try/catch estilo Lua).

    Params:
      tryBody   : string[]
      catchBody : string[]? (recebe "err" como parâmetro)
      finally   : string[]?
]]
function SmartCodeGenerator.GeneratePcall(params: table): string
	params = params or {}
	local tryBody = params.tryBody or {}
	local catchBody = params.catchBody or {}
	local finally = params.finally or {}

	if type(tryBody) == "string" then
		tryBody = {tryBody}
	end
	if type(catchBody) == "string" then
		catchBody = {catchBody}
	end
	if type(finally) == "string" then
		finally = {finally}
	end

	local lines = {}
	table.insert(lines, "local ok, err = pcall(function()")
	for _, line in ipairs(tryBody) do
		table.insert(lines, "\t" .. line)
	end
	table.insert(lines, "end)")

	table.insert(lines, "if not ok then")
	for _, line in ipairs(catchBody) do
		table.insert(lines, "\t" .. line:gsub("err", "err"))
	end
	table.insert(lines, "end")

	if #finally > 0 then
		table.insert(lines, "-- finally")
		for _, line in ipairs(finally) do
			table.insert(lines, "\t" .. line)
		end
	end

	return table.concat(lines, "\n")
end

--[[
    Gera um require / import de módulo.

    Params:
      modulePath : string
      varName    : string?
]]
function SmartCodeGenerator.GenerateRequire(params: table): string
	params = params or {}
	local path = params.modulePath or "Module"
	local var = params.varName or sanitizeVarName(path)
	return "local " .. var .. " = require(" .. escapeLuaString(path) .. ")"
end

--[[
    Gera um arquivo completo com header, imports, código principal e retorno.
]]
function SmartCodeGenerator.GenerateFile(params: table): string
	params = params or {}
	local header = params.header or "-- Auto-generado por SmartCodeGenerator\n"
	local imports = params.imports or {}
	local body = params.body or {}
	local returnValue = params.returnValue

	local lines = {}
	table.insert(lines, header)
	table.insert(lines, "")

	for _, imp in ipairs(imports) do
		table.insert(lines, SmartCodeGenerator.GenerateRequire(imp))
	end

	if #imports > 0 then
		table.insert(lines, "")
	end

	if type(body) == "string" then
		body = {body}
	end

	for _, line in ipairs(body) do
		table.insert(lines, line)
	end

	if returnValue ~= nil then
		table.insert(lines, "")
		table.insert(lines, "return " .. valueToCode(returnValue))
	end

	return table.concat(lines, "\n")
end

return SmartCodeGenerator
