# Ambiente local da integração

Referência: `chapter14-examples-2026-10-16`. Windows x64, Delphi 13 Win64 licenciado, Git e PowerShell. A preparação obtém as revisões fixadas e Anvil 1.8.5 com checksum. Não requer solc, Node.js, Python, Docker, carteira ou fundos reais para esta inspeção.

Na raiz dos exemplos:

```powershell
git checkout chapter14-examples-2026-10-16
.\scripts\Test-Chapter14.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

Aceita `-Port 18946` para outra porta livre. Cria e encerra sua própria instância Anvil em loopback; não encerra outro processo em caso de conflito. Compila `Chapter14.Environment` e faz apenas consultas pelo cliente Delphi existente. Não implanta contrato nem envia transações.

Resultados em `build/Chapter14.Environment/acceptance.json` e `environment.json`. Esperado: cliente Anvil, chainId `0x7a69` (31337), altura `0x0`, zero contas administradas pelo nó e saldo `100000000000000000000` wei no endereço `0x7e5f4552091a69125d5dfcb7b8c2659029395bdf`. O endereço é derivado em Delphi do valor privado 1, publicado para teste. Ter saldo não significa que o nó possui a chave. O programa só a usa para derivar o endereço, sem enviá-la ao nó.

`latestBlockHash` é conferido quanto à forma e ao número do bloco; não há validação independente de consenso. O hash inicial pode variar entre instâncias. O roteiro também exige saída 1 e diagnóstico de argumentos ausentes e transporte depois de encerrar o nó. Expiração de prazo é falha do roteiro.

Configuração: chainId 31337, hardfork Cancun, `--accounts 0`, dois endereços de teste financiados, base fee inicial 1000000000 e produção automática desligada (`--no-mining`). Nenhuma conta ou segredo real deve ser usado. O script não carrega nem salva estado da rede entre suas execuções.

O helper de build ganhou somente a seleção `-BuildEnvironmentDemo`; nenhum cliente RPC ou algoritmo criptográfico foi alterado. [Resultados executados](../../validation/2026-10-16-chapter14/RESULTADOS.md).
