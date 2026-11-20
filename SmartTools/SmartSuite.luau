--!native
--!optimize 2
--!strict

--[[==========================================================================
    SMART SUITE (Conjunto de Ferramentas Inteligentes)
    -------------------------------------------------------------------------
    Exporta todos os módulos do SmartTools:
      * SmartVariableRenamer - Renomador inteligente de variáveis
      * SmartCodeGenerator   - Gerador de código inteligente
      * UnionGenerator       - Gerador de UNION (UnionOperation)

    Projeto: BetterSaveinstance (Roblox saveinstance)
============================================================================--]]

local SmartSuite = {}

SmartSuite.VariableRenamer = require(script.VariableRenamer)
SmartSuite.CodeGenerator = require(script.CodeGenerator)
SmartSuite.UnionGenerator = require(script.UnionGenerator)

-- Informações da suíte
SmartSuite.Info = {
	name = "SmartSuite",
	version = "1.0.0",
	description = "Ferramentas inteligentes para renomeação de variáveis, geração de código e serialização de UNION (UnionOperation) para BetterSaveinstance.",
	modules = {
		"VariableRenamer",
		"CodeGenerator",
		"UnionGenerator",
	},
}

-- Exemplo rápido de uso (descomente para testar em contexto Roblox):
--[[
local SmartSuite = require(path.to.SmartTools.SmartSuite)

-- 1. Renomear variáveis de um script
local result = SmartSuite.VariableRenamer.Rename(sourceCode, {
	preserve = {"game", "workspace", "script"},
	forceRename = true,
	minLength = 3,
})
print(result.stats.totalRenamed, "variáveis renomeadas")

-- 2. Gerar uma classe
local classCode = SmartSuite.CodeGenerator.GenerateClass({
	className = "PlayerData",
	props = {Health = 100, MaxHealth = 100},
	methods = {
		TakeDamage = {
			params = {"amount"},
			body = {"self.Health -= amount", "if self.Health < 0 then self.Health = 0 end"},
		},
	},
})
print(classCode)

-- 3. Coletar e serializar Uniões de um model
local unions = SmartSuite.UnionGenerator.CollectUnions(workspace)
print("Uniões encontradas:", unions.count)
local xml = SmartSuite.UnionGenerator.GenerateAllUnionsXml(unions.unions)
--]]

return SmartSuite
