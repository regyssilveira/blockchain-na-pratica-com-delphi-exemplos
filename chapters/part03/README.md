# Laboratório dos capítulos 8 a 13

Este percurso constrói uma blockchain didática própria: blocos, transações assinadas, persistência, mineração e três nós são executáveis Delphi nativos. É separado da integração Ethereum do livro. Não requer Anvil, Solidity, Docker, Node.js ou Python. Requer Windows x64, Delphi 13 Win64 instalado/licenciado, PowerShell e Git; o primeiro preparo usa internet para obter os fontes fixados em `dependencies.lock.json`.

## Repetir a validação completa

Na raiz do repositório público, execute:

```powershell
git checkout didactic-chain-accepted-2026-10-16
.\scripts\Test-Didactic.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O roteiro prepara as dependências, compila os testes e três programas Delphi, executa 114 testes e 14 cenários de rede, valida os três arquivos finais e encerra os processos que criou. A verificação adicional de ciclo de vida encerra deliberadamente o processo supervisor e exige que seu filho também termine. Não encerra processos pelo nome. Se as portas 18571–18574 estiverem ocupadas, use `-BasePort 18581`, reservando quatro portas consecutivas. Os resultados ficam em `build/Didactic/acceptance.json`, `build/Didactic/results.xml` e uma pasta nova em `build/Didactic/runs/`.

Esperado: zero falhas, erros e ignorados; altura final 7, trabalho 1792, três cadeias válidas com o mesmo hash. Os 114 testes incluem os 76 testes offline anteriores; não devem ser somados a eles como casos exclusivos. Tempos de mineração dependem da máquina.

## Explorar um conceito por vez

Execute os comandos a partir da raiz, depois da compilação acima. A interface de linha de comando (CLI) é o programa `build/Didactic.Cli/Didactic.Cli.exe`.

| Capítulo | Comando ou cenário | Resultado a observar |
|---|---|---|
| 8 | `build/Didactic.Cli/Didactic.Cli.exe block-demo fixtures/p02/document-a.txt` | Bytes canônicos e hashes diferentes após alteração |
| 9 | `build/Didactic.Cli/Didactic.Cli.exe link-demo fixtures/p02/document-a.txt` | Recalcular o bloco antigo não corrige a referência do seguinte |
| 10 | `make`, `send`, `mine`, `document`, `stop`, reinício e `validate` abaixo | Pendente é diferente de incluída; dados persistem e são revalidados |
| 11 | `build/Didactic.Cli/Didactic.Cli.exe pow-demo` e N09–N10 | Dificuldades 2/3/4, empate e adoção de mais trabalho válido |
| 12 | N01–N04 e N12 do cenário automático | Propagação entre processos reais, inclusive A → B → C sem ligação A–C |
| 13 | N05–N14 e teste de ciclo de vida | Rejeição, falha de gravação, parada real, recuperação, bifurcações e corrupção |

`block-demo` e `link-demo` isolam hash e encadeamento. São verificações parciais para a progressão didática; não substituem a validação completa de assinatura, prova de trabalho e estado usada nos nós.

## Operar três nós manualmente

Abra três terminais na raiz e use uma pasta nova para não reaproveitar a cadeia do cenário automático:

```powershell
# Terminal A
.\build\Didactic.Node\Didactic.Node.exe A 18671 build/manual/A.json 18672 2
# Terminal B
.\build\Didactic.Node\Didactic.Node.exe B 18672 build/manual/B.json 18671,18673 2
# Terminal C
.\build\Didactic.Node\Didactic.Node.exe C 18673 build/manual/C.json 18672 2
```

Em um quarto terminal, crie a transação, envie e inclua em bloco:

```powershell
$cli = '.\build\Didactic.Cli\Didactic.Cli.exe'
& $cli make 1 fixtures/p02/document-a.txt 1 build/manual/transaction.json
& $cli send 18671 build/manual/transaction.json
& $cli status 18673
& $cli mine 18671 1
& $cli document 18673 50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0 adf835a3a021fc814fbb13f2cb4e544a18dabd8e608a0013f6eb450318713bf2
```

`make` recebe índice da chave pública de laboratório, arquivo, sequência e caminho de saída. A assinatura é calculada em Delphi antes do envio. Use o arquivo de saída como entrada de `send`; a saída de diagnóstico no terminal também contém campos derivados e não é o formato de transmissão. Chaves 1–9 são deliberadamente conhecidas e nunca servem para valores reais. A sequência começa em 1 por conta; o documento é identificado pelo SHA-256 de seus bytes. Para uma segunda operação da mesma conta, use outro documento e sequência 2.

O envio entra no conjunto pendente; a consulta só encontra o registro após inclusão. A propagação é assíncrona: repita `status` ou use `wait-tip <porta> <hash>` e `wait-tx <porta> <id> confirmed`, ambos com prazo limitado. `mine` recebe um instante lógico inteiro estritamente maior que o bloco anterior, não um relógio de confiança. Enviar novamente a mesma transação retorna `accepted:false`, sem nova inclusão.

```powershell
& $cli network 18673 0
& $cli network 18673 1
& $cli sync 18673 18672
& $cli stop 18671
& $cli stop 18672
& $cli stop 18673
& $cli validate build/manual/A.json
```

`network 0` simula uma partição controlada; não encerra o processo. `stop` encerra realmente o nó. Reinicie com o mesmo comando e arquivo para recuperar o estado. Um arquivo existente corrompido provoca erro de inicialização e é preservado; não vira uma cadeia vazia silenciosamente. Use arquivos novos para repetir o primeiro registro desde a sequência 1.

## Limites

O transporte é HTTP/JSON restrito a loopback, sem autenticação, TLS ou defesa contra participantes hostis. A dificuldade é pequena e fixa por rede. O empate preserva a história atual; mais trabalho só vence após validação integral. Não há finalidade de rede pública, proteção de custódia ou comprovação de identidade/autoria. O checksum do arquivo detecta alterações acidentais, não autentica o produtor. Consulte o [formato e regras](PROTOCOL.md), a [procedência dos vetores](../../fixtures/didactic/PROVENIENCIA.md) e os [resultados executados](../../validation/2026-10-16-didactic/RESULTADOS.md).
