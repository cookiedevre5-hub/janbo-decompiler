# 🛠️ SmartTools — Ferramentas Inteligentes para BetterSaveinstance

Este módulo adiciona três ferramentas ao ecossistema **BetterSaveinstance**:

1. **Renomador Inteligente de Variáveis** (`VariableRenamer.luau`)
2. **Gerador de Código Inteligente** (`CodeGenerator.luau`)
3. **Gerador de UNION** (`UnionGenerator.luau`)

---

## 1. Renomador Inteligente de Variáveis

Analisa código-fonte Lua/Luau e renomeia variáveis locais, globais e parâmetros
respeitando escopos, palavras reservadas e nomes preservados.

### Uso rápido

```lua
local SmartSuite = require(path.to.SmartTools.SmartSuite)

local result = SmartSuite.VariableRenamer.Rename(sourceCode, {
	preserve = {"game", "workspace", "script", "plr"},
	forceRename = true,
	minLength = 3,
})

print(result.renamedCode)      -- código com variáveis renomeadas
print(result.mapping)          -- { antigoNome = novoNome }
print(result.stats.totalRenamed) -- quantidade renomeada
```

### Opções

| Opção | Tipo | Padrão | Descrição |
|-------|------|--------|-----------|
| `preserve` | `table` | `{}` | Nomes que nunca serão renomeados |
| `forceRename` | `boolean` | `false` | Renomeia mesmo identificadores válidos |
| `minLength` | `number` | `1` | Tamanho mínimo para renomear |
| `prefix` | `string` | `""` | Prefixo adicionado aos novos nomes |

---

## 2. Gerador de Código Inteligente

Gera código Lua/Luau a partir de descrições estruturadas.

### Exemplos

**Função:**
```lua
local fn = SmartSuite.CodeGenerator.GenerateFunction({
	name = "CalcularDano",
	params = {"atk", "def"},
	body = {"return math.floor(atk * 0.8 - def * 0.2)"},
	isLocal = true,
})
```

**Classe:**
```lua
local classCode = SmartSuite.CodeGenerator.GenerateClass({
	className = "PlayerData",
	props = {Health = 100, MaxHealth = 100},
	methods = {
		TakeDamage = {
			params = {"amount"},
			body = {"self.Health = math.max(0, self.Health - amount)"},
		},
	},
})
```

**Instância Roblox:**
```lua
local partCode = SmartSuite.CodeGenerator.GenerateInstance({
	className = "Part",
	varName = "myPart",
	name = "Bloco",
	properties = {Size = Vector3.new(4,4,4), Anchored = true},
	attributes = {Tier = 1},
	parent = "workspace",
})
```

Outros geradores disponíveis: `GenerateConnection`, `GenerateIf`, `GenerateFor`,
`GenerateForIn`, `GeneratePcall`, `GenerateRequire`, `GenerateFile`.

---

## 3. Gerador de UNION (UnionOperation) ⭐

Salva `UnionOperation` corretamente no formato `.rbxlx` (XML), permitindo que
uniões de partes sejam restauradas no Roblox Studio — ao invés de serem apenas
convertidas em `Part` comum (como faz a opção `TreatUnionsAsParts`).

### Uso no contexto do saveinstance

```lua
local SmartSuite = require(path.to.SmartTools.SmartSuite)

-- 1. Coleta todas as uniões de um model/workspace
local collected = SmartSuite.UnionGenerator.CollectUnions(workspace)
print("Uniões encontradas:", collected.count)

-- 2. Gera XML rbxlx para todas as uniões
local unionXml = SmartSuite.UnionGenerator.GenerateAllUnionsXml(collected.unions)

-- 3. Gera módulo de reconstrução (fallback para executors sem dados de mesh)
local reconstructor = SmartSuite.UnionGenerator.GenerateReconstructionModule(collected.unions)
```

### Fluxo de integração com `saveinstance.luau`

No seu arquivo `saveinstance.luau`, antes de gravar o arquivo `.rbxlx`, faça:

```lua
local SmartSuite = require(path.to.SmartTools.SmartTools.SmartSuite)

-- Depois de montar a hierarquia de instâncias a ser salva:
local unions = SmartSuite.UnionGenerator.CollectUnions(game)

-- Insira o XML das uniões na árvore do arquivo rbxlx
local unionXml = SmartSuite.UnionGenerator.GenerateAllUnionsXml(unions.unions)
-- ... insira unionXml dentro do <roblox> ... </roblox> do seu XML

-- Ou salve o módulo de reconstrução como um LocalScript dentro do arquivo:
local reconstructorCode = SmartSuite.UnionGenerator.GenerateReconstructionModule(unions.unions)
```

### Por que isso é necessário?

No Roblox, uma `UnionOperation` não é uma malha simples — ela é gerada
procedimentalmente pelo engine. A maioria dos executors **não consegue ler**
os dados brutos da mesh da união, então o saveinstance original simplesmente
as converte em `Part` (opção `TreatUnionsAsParts`).

Este gerador:
- Captura `InitialSize`, `UsePartColor` e propriedades sobreviventes.
- Gera XML compatível com o formato rbxlx da Roblox.
- Fornece um **módulo de reconstrução client-side** que recria a união a
  partir das partes-fonte, caso os dados brutos não estejam disponíveis.

---

## Estrutura da pasta

```
SmartTools/
├── VariableRenamer.luau   # Renomador de variáveis
├── CodeGenerator.luau     # Gerador de código
├── UnionGenerator.luau    # Gerador de UNION
├── SmartSuite.luau        # Módulo principal (exporta tudo)
└── SMARTTOOLS_README.md   # Este arquivo
```

---

## Requisitos

- Lua 5.1 / Luau (compatível com executors Roblox)
- Nenhuma dependência externa

---

## Créditos

Feito como extensão do projeto **BetterSaveinstance** (Universal Syn Save Instance).
Mantém os créditos originais: `UniversalSynSaveInstance https://discord.gg/wx4ThpAsmw`
