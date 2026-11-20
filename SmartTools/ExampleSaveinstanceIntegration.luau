--!native
--!optimize 2
--!strict

--[[==========================================================================
    EXEMPLO DE INTEGRAÇÃO COM BETTERSAVEINSTANCE
    -------------------------------------------------------------------------
    Mostra como integrar o SmartSuite (especialmente o UnionGenerator)
    no fluxo de salvamento do saveinstance.luau.
============================================================================--]]

local SmartSuite = require(script.Parent.SmartSuite)

local function integrateWithSaveinstance(saveOptions: table, rootInstance: Instance)
	-- 1. Antes de salvar, coleta todas as UnionOperations
	local unionCollection = SmartSuite.UnionGenerator.CollectUnions(rootInstance)

	if unionCollection.count > 0 then
		warn(string.format("SmartSuite: %d UnionOperation(s) detectada(s).", unionCollection.count))

		-- 2. Gera XML rbxlx para as uniões (para inserir no arquivo .rbxlx)
		local unionXml = SmartSuite.UnionGenerator.GenerateAllUnionsXml(unionCollection.unions)
		print("XML de uniões gerado com sucesso.")
		print(unionXml:sub(1, 500) .. "...")

		-- 3. Gera módulo de reconstrução (fallback client-side)
		local reconstructor = SmartSuite.UnionGenerator.GenerateReconstructionModule(unionCollection.unions)
		print("Módulo de reconstrução gerado.")
	end

	-- 4. Exemplo: renomear variáveis de um script antes de salvar
	local scriptSource = "local x = 10 local y = 20 print(x + y)"
	local renameResult = SmartSuite.VariableRenamer.Rename(scriptSource, {
		preserve = {"print"},
		forceRename = true,
	})
	print("Código renomeado:", renameResult.renamedCode)

	-- 5. Exemplo: gerar código de uma instância dinamicamente
	local partCode = SmartSuite.CodeGenerator.GenerateInstance({
		className = "Part",
		varName = "SavedPart",
		name = "PartSalva",
		properties = {Anchored = true, Size = Vector3.new(4, 4, 4)},
		parent = "workspace",
	})
	print("Código da instância:\n" .. partCode)

	return {
		unionCount = unionCollection.count,
		unionXml = unionXml,
		reconstructor = reconstructor,
	}
end

return integrateWithSaveinstance
