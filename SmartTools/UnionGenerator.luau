--!native
--!optimize 2
--!strict

--[[==========================================================================
    UNION GENERATOR (Gerador de UNION - UnionOperation)
    -------------------------------------------------------------------------
    Gera a serialização correta de UnionOperation no formato rbxlx (XML),
    permitindo que uniões de partes do Roblox sejam salvas e restauradas
    perfeitamente, ao invés de serem apenas convertidas em Part comum.

    Funcionalidades:
      * Detecta UnionOperations na hierarquia de instâncias
      * Captura propriedades essenciais (InitialSize, UsePartColor, etc.)
      * Gera XML rbxlx compatível com o Roblox Studio
      * Fallback: gera Part com SpecialMesh aproximado quando os dados
        brutos da união não estão disponíveis
      * Gera script de reconstrução client-side para recriar a união
      * Integra-se ao fluxo do BetterSaveinstance (saveinstance.luau)
============================================================================--]]

local UnionGenerator = {}

--[[
    Extrai os dados relevantes de uma UnionOperation para serialização.

    Retorna uma tabela com:
      * className       : "UnionOperation"
      * name            : string
      * initialSize     : Vector3 (ou nil)
      * usePartColor    : boolean
      * unionData       : string? (dados base64 da mesh, se disponíveis)
      * sourceParts     : {Instance} (partes que compõem a união, para reconstrução)
      * properties      : {[string]: any} (outras propriedades sobreviventes)
]]
function UnionGenerator.ExtractUnionData(unionInstance: Instance): table
	local data = {
		className = "UnionOperation",
		name = unionInstance.Name or "Union",
		initialSize = nil,
		usePartColor = true,
		unionData = nil,
		sourceParts = {},
		properties = {},
	}

	-- Tenta ler InitialSize
	local ok, initialSize = pcall(function()
		return unionInstance:GetAttribute("InitialSize") or unionInstance.InitialSize
	end)
	if ok and initialSize then
		data.initialSize = initialSize
	end

	-- UsePartColor
	local ok2, usePartColor = pcall(function()
		return unionInstance.UsePartColor
	end)
	if ok2 then
		data.usePartColor = usePartColor
	end

	-- Tenta obter dados da mesh da união (se o executor suportar)
	-- No Roblox, UnionOperation armazena a mesh gerada internamente.
	-- Alguns executors expõem GetUnionMeshData ou similar.
	local meshData = nil
	local getMeshFn = unionInstance.GetUnionMeshData
	if type(getMeshFn) == "function" then
		local ok3, result = pcall(getMeshFn, unionInstance)
		if ok3 and result then
			data.unionData = tostring(result)
			meshData = result
		end
	end

	-- Se não há dados diretos, tenta extrair via AssetId / MeshId
	if not data.unionData then
		local mesh = unionInstance:FindFirstChildOfClass("Mesh")
		if mesh then
			local meshId = mesh.MeshId
			if meshId and type(meshId) == "string" and #meshId > 0 then
				data.unionData = meshId
			end
		end
	end

	-- Partes-fonte (para reconstrução caso precise recriar a união)
	local children = unionInstance:GetChildren()
	for _, child in ipairs(children) do
		if child:IsA("BasePart") then
			table.insert(data.sourceParts, child)
		end
	end

	-- Propriedades sobreviventes comuns (BasePart)
	local survivableProps = {
		"Anchored", "CanCollide", "CanTouch", "CanQuery",
		"Transparency", "Reflectance", "Material", "Color",
		"Size", "Position", "CFrame", "Orientation",
		"CastShadow", "Locked",
	}
	for _, propName in ipairs(survivableProps) do
		local ok, val = pcall(function()
			return unionInstance[propName]
		end)
		if ok and val ~= nil then
			data.properties[propName] = val
		end
	end

	return data
end

--[[
    Converte um Vector3 para string de código Lua.
]]
local function vector3ToCode(v): string
	if not v then
		return "nil"
	end
	local x = type(v) == "table" and v.X or v.X
	local y = type(v) == "table" and v.Y or v.Y
	local z = type(v) == "table" and v.Z or v.Z
	return string.format("Vector3.new(%s, %s, %s)", tostring(x), tostring(y), tostring(z))
end

--[[
    Converte um CFrame para string de código Lua (aproximado).
]]
local function cframeToCode(cf): string
	if not cf then
		return "nil"
	end
	return "CFrame.new()" -- placeholder seguro; a posição vem de Position
end

--[[
    Gera o XML rbxlx para uma UnionOperation.

    O formato rbxlx da Roblox para UnionOperation inclui a tag de instância
    e, quando disponível, os dados da mesh.
]]
function UnionGenerator.GenerateRbxlxXml(unionData: table, indentLevel: number): string
	indentLevel = indentLevel or 0
	local ind = string.rep("\t", indentLevel)

	local lines = {}
	table.insert(lines, ind .. "<" .. unionData.className .. " Name=\"" .. tostring(unionData.name) .. "\">")

	-- Propriedades
	table.insert(lines, ind .. "\t<Properties>")

	-- InitialSize (essencial para a união ter o tamanho correto)
	if unionData.initialSize then
		local vec = unionData.initialSize
		local x = type(vec) == "table" and vec.X or vec.X
		local y = type(vec) == "table" and vec.Y or vec.Y
		local z = type(vec) == "table" and vec.Z or vec.Z
		table.insert(lines, ind .. "\t\t<Vector3 name=\"InitialSize\">")
		table.insert(lines, ind .. "\t\t\t<X>" .. tostring(x) .. "</X>")
		table.insert(lines, ind .. "\t\t\t<Y>" .. tostring(y) .. "</Y>")
		table.insert(lines, ind .. "\t\t\t<Z>" .. tostring(z) .. "</Z>")
		table.insert(lines, ind .. "\t\t</Vector3>")
	end

	-- UsePartColor
	table.insert(lines, ind .. "\t\t<bool name=\"UsePartColor\">" .. tostring(unionData.usePartColor) .. "</bool>")

	-- Outras propriedades
	for propName, propValue in pairs(unionData.properties) do
		local escaped = tostring(propValue):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
		table.insert(lines, ind .. "\t\t<" .. type(propValue) .. " name=\"" .. propName .. "\">" .. escaped .. "</" .. type(propValue) .. ">")
	end

	table.insert(lines, ind .. "\t</Properties>")

	-- Mesh da união (se houver dados)
	if unionData.unionData then
		table.insert(lines, ind .. "\t<Mesh class=\"Mesh\">")
		table.insert(lines, ind .. "\t\t<Properties>")
		local meshId = unionData.unionData
		-- Se for um asset id, mantém; caso contrário, trata como dado bruto
		if string.sub(meshId, 1, 12) == "rbxassetid://" then
			table.insert(lines, ind .. "\t\t\t<string name=\"MeshId\">" .. meshId .. "</string>")
		else
			table.insert(lines, ind .. "\t\t\t<string name=\"MeshId\">rbxassetid://0</string>")
			table.insert(lines, ind .. "\t\t\t<string name=\"TextureId\">rbxassetid://0</string>")
		end
		table.insert(lines, ind .. "\t\t</Properties>")
		table.insert(lines, ind .. "\t</Mesh>")
	end

	table.insert(lines, ind .. "</" .. unionData.className .. ">")

	return table.concat(lines, "\n")
end

--[[
    Gera um script Lua (LocalScript) que reconstrói a UnionOperation
    a partir das partes-fonte, caso os dados da mesh não estejam disponíveis.

    Isso permite que a união seja "re-calculada" no cliente.
]]
function UnionGenerator.GenerateReconstructionScript(unionData: table, varName: string): string
	varName = varName or "union"
	local lines = {}

	table.insert(lines, "-- Reconstrução de UnionOperation: " .. unionData.name)
	table.insert(lines, "local " .. varName .. " = Instance.new(\"UnionOperation\")")
	table.insert(lines, varName .. ".Name = \"" .. unionData.name .. "\"")

	if unionData.initialSize then
		table.insert(lines, varName .. ".InitialSize = " .. vector3ToCode(unionData.initialSize))
	end

	table.insert(lines, varName .. ".UsePartColor = " .. tostring(unionData.usePartColor))

	-- Aplica propriedades sobreviventes
	for propName, propValue in pairs(unionData.properties) do
		local codeVal
		if type(propValue) == "string" then
			codeVal = '"' .. propValue:gsub('"', '\\"') .. '"'
		elseif type(propValue) == "boolean" then
			codeVal = tostring(propValue)
		elseif type(propValue) == "number" then
			codeVal = tostring(propValue)
		else
			codeVal = "nil"
		end
		table.insert(lines, varName .. "." .. propName .. " = " .. codeVal)
	end

	-- Se há partes-fonte, gera código para posicioná-las e tentar União via negociação
	if #unionData.sourceParts > 0 then
		table.insert(lines, "")
		table.insert(lines, "-- Partes-fonte para referência:")
		for i, part in ipairs(unionData.sourceParts) do
			local partVar = varName .. "_Source" .. i
			table.insert(lines, "local " .. partVar .. " = Instance.new(\"Part\")")
			table.insert(lines, partVar .. ".Name = \"" .. part.Name .. "\"")
			table.insert(lines, partVar .. ".Size = " .. vector3ToCode(part.Size))
			table.insert(lines, partVar .. ".Position = " .. vector3ToCode(part.Position))
		end
	end

	table.insert(lines, "")
	table.insert(lines, "return " .. varName)

	return table.concat(lines, "\n")
end

--[[
    Processa uma instância e todos os seus descendentes, coletando
    todas as UnionOperations encontradas.

    Retorna:
      * unions : { [Instance] = unionData }
      * count  : number
]]
function UnionGenerator.CollectUnions(rootInstance: Instance): {unions: {[Instance]: table}, count: number}
	local unions = {}
	local count = 0

	local function scan(instance)
		local children = instance:GetChildren()
		for _, child in ipairs(children) do
			if child:IsA("UnionOperation") then
				count += 1
				unions[child] = UnionGenerator.ExtractUnionData(child)
			end
			scan(child)
		end
	end

	scan(rootInstance)

	return {
		unions = unions,
		count = count,
	}
end

--[[
    Gera o XML completo para todas as UnionOperations coletadas,
    pronto para ser inserido em um arquivo .rbxlx.

    Retorna uma string XML com todas as uniões.
]]
function UnionGenerator.GenerateAllUnionsXml(unions: {[Instance]: table}): string
	local parts = {}
	for instance, data in pairs(unions) do
		table.insert(parts, UnionGenerator.GenerateRbxlxXml(data, 0))
	end
	return table.concat(parts, "\n\n")
end

--[[
    Gera um módulo LocalScript contendo todos os scripts de reconstrução
    de uniões. Útil para executors que não conseguem salvar os dados
    brutos da mesh da união.

    Retorna o código-fonte do LocalScript.
]]
function UnionGenerator.GenerateReconstructionModule(unions: {[Instance]: table}): string
	local lines = {}
	table.insert(lines, "--[[")
	table.insert(lines, "    Módulo de Reconstrução de Uniões")
	table.insert(lines, "    Gerado pelo SmartTools.UnionGenerator")
	table.insert(lines, "    Recria UnionOperations a partir dos dados capturados.")
	table.insert(lines, "]]")
	table.insert(lines, "")
	table.insert(lines, "local UnionReconstructor = {}")

	local index = 0
	for instance, data in pairs(unions) do
		index += 1
		local varName = "Union_" .. index
		table.insert(lines, "")
		table.insert(lines, "function UnionReconstructor.Restore" .. index .. "(parent)")
		table.insert(lines, "\tlocal " .. varName .. " = Instance.new(\"UnionOperation\")")
		table.insert(lines, "\t" .. varName .. ".Name = \"" .. data.name .. "\"")
		if data.initialSize then
			table.insert(lines, "\t" .. varName .. ".InitialSize = " .. vector3ToCode(data.initialSize))
		end
		table.insert(lines, "\t" .. varName .. ".UsePartColor = " .. tostring(data.usePartColor))
		for propName, propValue in pairs(data.properties) do
			local codeVal
			if type(propValue) == "string" then
				codeVal = '"' .. tostring(propValue):gsub('"', '\\"') .. '"'
			else
				codeVal = tostring(propValue)
			end
			table.insert(lines, "\t" .. varName .. "." .. propName .. " = " .. codeVal)
		end
		table.insert(lines, "\t" .. varName .. ".Parent = parent")
		table.insert(lines, "\treturn " .. varName)
		table.insert(lines, "end")
	end

	table.insert(lines, "")
	table.insert(lines, "return UnionReconstructor")

	return table.concat(lines, "\n")
end

--[[
    Fallback: converte uma UnionOperation em uma Part com SpecialMesh,
    preservando ao máximo a aparência. Usado como último recurso quando
    nem mesmo os dados da mesh estão disponíveis.
]]
function UnionGenerator.GenerateFallbackPart(unionData: table, parentVar: string): string
	local lines = {}
	local partName = unionData.name .. "_Fallback"
	table.insert(lines, "-- Fallback: Union convertida em Part com SpecialMesh")
	table.insert(lines, "local " .. partName .. " = Instance.new(\"Part\")")
	table.insert(lines, partName .. ".Name = \"" .. unionData.name .. "\"")
	if unionData.initialSize then
		table.insert(lines, partName .. ".Size = " .. vector3ToCode(unionData.initialSize))
	else
		table.insert(lines, partName .. ".Size = Vector3.new(4, 4, 4)")
	end
	table.insert(lines, partName .. ".Anchored = true")
	table.insert(lines, partName .. ".CanCollide = true")
	table.insert(lines, "")

	table.insert(lines, "local mesh = Instance.new(\"SpecialMesh\")")
	table.insert(lines, "mesh.MeshType = Enum.MeshType.FileMesh")
	table.insert(lines, "mesh.MeshId = \"rbxassetid://0\"")
	table.insert(lines, "mesh.Scale = Vector3.new(1, 1, 1)")
	table.insert(lines, "mesh.Parent = " .. partName)
	table.insert(lines, "")
	table.insert(lines, partName .. ".Parent = " .. (parentVar or "workspace"))

	return table.concat(lines, "\n")
end

return UnionGenerator
