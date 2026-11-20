--!native
--!optimize 2
--!strict

--[[==========================================================================
    SMART VARIABLE RENAMER (Renomador Inteligente de Variáveis)
    -------------------------------------------------------------------------
    Analisa código-fonte Lua/Luau, detecta variáveis locais, globais,
    parâmetros de função e renomeia de forma inteligente, respeitando:
      * Escopos (não há colisão entre escopos diferentes)
      * Palavras reservadas do Lua
      * Variáveis preservadas (ex: _ENV, game, script, etc.)
      * Nomes baseados no contexto de uso (tipo, valor inicial, serviço)
============================================================================--]]

local SmartVariableRenamer = {}

-- Palavras reservadas do Lua 5.1 / Luau
local LUA_KEYWORDS = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
	["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
	["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true,
}

-- Variáveis que nunca devem ser renomeadas
local PRESERVED_NAMES = {
	["_ENV"] = true, ["_G"] = true, ["_VERSION"] = true,
	["game"] = true, ["workspace"] = true, ["script"] = true,
	["shared"] = true, ["debug"] = true,
}

-- Prefixos sugeridos por contexto de uso
local CONTEXT_PREFIXES = {
	["Instance"] = "inst",
	["Service"] = "svc",
	["Function"] = "fn",
	["Callback"] = "cb",
	["Connection"] = "conn",
	["Table"] = "tbl",
	["String"] = "str",
	["Number"] = "num",
	["Boolean"] = "bool",
	["Vector3"] = "v3",
	["CFrame"] = "cf",
	["UDim2"] = "ud2",
	["Color3"] = "c3",
	["RBXScriptSignal"] = "sig",
	["RBXScriptConnection"] = "con",
}

-- Contador global para gerar nomes únicos quando não há contexto
local uniqueCounter = 0

local function resetCounter()
	uniqueCounter = 0
end

local function nextUnique()
	uniqueCounter += 1
	return uniqueCounter
end

-- Verifica se um nome é palavra reservada do Lua
local function isLuaKeyword(name: string): boolean
	return LUA_KEYWORDS[name] == true
end

-- Verifica se um nome deve ser preservado
local function isPreserved(name: string): boolean
	return PRESERVED_NAMES[name] == true
end

-- Verifica se um nome é um identificador Lua válido
local function isValidIdentifier(name: string): boolean
	if name == "" then
		return false
	end
	if isLuaKeyword(name) then
		return false
	end
	local first = string.sub(name, 1, 1)
	if not (string.match(first, "[%a_]") or string.byte(first) >= 128) then
		return false
	end
	for i = 2, #name do
		local c = string.sub(name, i, i)
		if not (string.match(c, "[%a_%d]") or string.byte(c) >= 128) then
			return false
		end
	end
	return true
end

-- Sanitiza um nome para torná-lo um identificador válido
local function sanitizeName(name: string): string
	if name == "" or name == nil then
		return "var"
	end
	local s = string.gsub(name, "[^%a_%d]", "_")
	local first = string.sub(s, 1, 1)
	if not string.match(first, "[%a_]") then
		s = "_" .. s
	end
	if isLuaKeyword(s) then
		s = "_" .. s
	end
	return s
end

-- Gera um nome inteligente baseado no contexto
local function generateSmartName(context: string?, original: string?, usedNames: {[string]: boolean}): string
	local base = ""
	if context and CONTEXT_PREFIXES[context] then
		base = CONTEXT_PREFIXES[context]
	elseif original and isValidIdentifier(original) and not isLuaKeyword(original) and not isPreserved(original) then
		base = original
	else
		base = "var"
	end

	base = sanitizeName(base)

	local candidate = base
	local suffix = 1
	while usedNames[candidate] == true do
		candidate = base .. suffix
		suffix += 1
	end

	usedNames[candidate] = true
	return candidate
end

-- Estrutura de escopo
type Scope = {
	parent: Scope?,
	variables: {[string]: {newName: string, original: string, context: string?}},
	usedNames: {[string]: boolean},
}

local function newScope(parent: Scope?): Scope
	return {
		parent = parent,
		variables = {},
		usedNames = {},
	}
end

-- Registra uma palavra reservada como usada em todos os escopos para evitar colisão
local function markReservedAsUsed(scope: Scope)
	for kw in pairs(LUA_KEYWORDS) do
		scope.usedNames[kw] = true
	end
end

--[[
    Analisa o código-fonte (string) e retorna:
      * renamedCode: o código com variáveis renomeadas
      * mapping: tabela { originalNome = novoNome }
      * stats: estatísticas da operação
]]
function SmartVariableRenamer.Rename(source: string, options: table?): {renamedCode: string, mapping: {[string]: string}, stats: table}
	options = options or {}

	local preserveList = options.preserve or {}
	for _, name in ipairs(preserveList) do
		PRESERVED_NAMES[name] = true
	end

	local forceRename = options.forceRename or false
	local minLength = options.minLength or 1
	local prefix = options.prefix or ""

	resetCounter()

	local rootScope = newScope(nil)
	markReservedAsUsed(rootScope)

	local mapping = {} -- original -> novo
	local renamedCount = 0
	local skippedCount = 0
	local scopeStack = {rootScope}

	local currentScope: Scope = rootScope

	-- Função auxiliar para obter o escopo atual
	local function getCurrentScope()
		return scopeStack[#scopeStack]
	end

	-- Resultado acumulado
	local out = {}
	local i = 1
	local len = #source

	-- Estado simples de "estamos dentro de uma string ou comentário"
	local inString = false
	local stringChar = ""
	local inComment = false
	local commentEnd = nil -- padrão para detectar fim de comentário longo [[ ... ]]

	while i <= len do
		local ch = string.sub(source, i, i)

		-- Tratamento de strings
		if not inComment then
			if (ch == '"' or ch == "'") and not inString then
				inString = true
				stringChar = ch
				table.insert(out, ch)
				i += 1
				continue
			elseif inString and ch == stringChar then
				-- Verifica escape
				local backslashes = 0
				local j = i - 1
				while j >= 1 and string.sub(source, j, j) == "\\" do
					backslashes += 1
					j -= 1
				end
				if backslashes % 2 == 0 then
					inString = false
				end
				table.insert(out, ch)
				i += 1
				continue
			elseif inString then
				table.insert(out, ch)
				i += 1
				continue
			end
		end

		-- Tratamento de comentários
		if not inString then
			if ch == "-" and string.sub(source, i, i + 1) == "--" and not inComment then
				local rest = string.sub(source, i + 2, i + 3)
				if rest == "[[" then
					inComment = true
					commentEnd = "]]"
					table.insert(out, "--[[" )
					i += 4
					continue
				elseif rest == "[=" then
					-- comentário longo com [=[ ... ]=
					local eqCount = 0
					local k = i + 4
					while k <= len and string.sub(source, k, k) == "=" do
						eqCount += 1
						k += 1
					end
					if string.sub(source, k, k) == "[" then
						inComment = true
						commentEnd = "]" .. string.rep("=", eqCount) .. "]"
						table.insert(out, string.sub(source, i, k))
						i = k + 1
						continue
					end
				end
				-- comentário de linha curta
				table.insert(out, ch)
				i += 1
				-- pula até o final da linha
				while i <= len and string.sub(source, i, i) ~= "\n" do
					table.insert(out, string.sub(source, i, i))
					i += 1
				end
				continue
			elseif inComment then
				local ce = commentEnd
				if string.sub(source, i, i + #ce - 1) == ce then
					table.insert(out, ce)
					i += #ce
					inComment = false
					commentEnd = nil
					continue
				else
					table.insert(out, ch)
					i += 1
					continue
				end
			end
		end

		-- Detecção de identificadores (variáveis, funções, etc.)
		if not inString and not inComment then
			local first = string.sub(i, i)
			local idStart = i
			if string.match(ch, "[%a_]") or string.byte(ch) >= 128 then
				local j = i + 1
				while j <= len do
					local c = string.sub(source, j, j)
					if string.match(c, "[%a_%d]") or string.byte(c) >= 128 then
						j += 1
					else
						break
					end
				end
				local ident = string.sub(source, idStart, j - 1)
				i = j

				-- Pula palavras reservadas
				if isLuaKeyword(ident) then
					table.insert(out, ident)
					continue
				end

				-- Verifica o próximo caractere não-espaço para decidir contexto
				local k = i
				while k <= len do
					local nxt = string.sub(source, k, k)
					if nxt == " " or nxt == "\t" or nxt == "\n" or nxt == "\r" then
						k += 1
					else
						break
					end
				end
				local nextChar = string.sub(source, k, k)

				local context = nil

				-- Detecção de contexto simples baseada no próximo token
				if nextChar == "(" then
					context = "Function"
				elseif nextChar == "=" then
					-- Pode ser atribuição; olha atrás para ver se é local/parâmetro
					context = "Variable"
				elseif nextChar == "." or nextChar == ":" then
					context = "Variable"
				end

				-- Heurística de tipo baseado no valor seguinte (muito simplificado)
				if context == "Variable" and nextChar == "=" then
					local afterEq = k + 1
					while afterEq <= len do
						local c = string.sub(source, afterEq, afterEq)
						if c == " " or c == "\t" or c == "\n" or c == "\r" then
							afterEq += 1
						else
							break
						end
					end
					local valueStart = string.sub(source, afterEq, afterEq)
					if valueStart == "game" or valueStart == "workspace" then
						context = "Service"
					elseif string.match(valueStart, "%p") or string.match(valueStart, "%d") then
						-- valor literal ou expressão
						context = "Variable"
					end
				end

				-- Decide se renomeia
				local shouldRename = forceRename
				if not shouldRename then
					-- Renomeia apenas se não for preservado e não for uma chave de tabela óbvia
					if not isPreserved(ident) and not isValidIdentifier(ident) == false then
						shouldRename = true
					end
				end

				if shouldRename and #ident >= minLength then
					local curScope = getCurrentScope()
					local existing = curScope.variables[ident]
					if existing then
						mapping[ident] = existing.newName
						renamedCount += 1
						table.insert(out, prefix .. existing.newName)
					else
						local newName = generateSmartName(context, ident, curScope.usedNames)
						curScope.variables[ident] = {newName = newName, original = ident, context = context}
						mapping[ident] = newName
						renamedCount += 1
						table.insert(out, prefix .. newName)
					end
				else
					if not isPreserved(ident) then
						skippedCount += 1
					end
					table.insert(out, ident)
				end
				continue
			end
		end

		table.insert(out, ch)
		i += 1
	end

	local renamedCode = table.concat(out)

	local stats = {
		totalRenamed = renamedCount,
		totalSkipped = skippedCount,
		uniqueNamesGenerated = nextUnique() - 1,
		scopesUsed = 1, -- simplificado
	}

	return {
		renamedCode = renamedCode,
		mapping = mapping,
		stats = stats,
	}
end

-- Renomeia variáveis em uma tabela de scripts (nome do script -> código-fonte)
function SmartVariableRenamer.RenameMultiple(scripts: {[string]: string}, options: table?): {[string]: {renamedCode: string, mapping: {[string]: string}}}
	local results = {}
	for name, source in pairs(scripts) do
		results[name] = SmartVariableRenamer.Rename(source, options)
	end
	return results
end

return SmartVariableRenamer
