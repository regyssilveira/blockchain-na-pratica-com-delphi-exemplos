# P04 — Aceitação local de transações assinadas em Delphi

Validação executada em 16/10/2026, Windows x86-64, Delphi 13, dcc64 37.0.57242.3601. Resultado: **77 testes aprovados**, sem ignorados, falhas ou erros: 76 regressões P02/P03 e um cenário de integração com múltiplas asserções e três rejeições esperadas.

## O que o leitor executa

O Delphi constrói a transação tipo 2, calcula Keccak-256, assina com secp256k1, codifica o envelope e envia os bytes por JSON-RPC (chamadas remotas codificadas em JSON), usando exclusivamente bibliotecas Delphi e a biblioteca padrão. Anvil é o nó externo de desenvolvimento; PowerShell prepara dependências e controla os processos. Não há assinatura por conta desbloqueada do nó, nem uso de cast, forge, Node.js, Python, Docker ou Rust no fluxo do leitor.

Requisitos: Windows x86-64, Git, PowerShell com Expand-Archive e Invoke-WebRequest, Delphi 13 com compilador Win64 e acesso à internet para obter inicialmente os repositórios e o pacote oficial. O Delphi é proprietário e requer instalação/licença do leitor; não é distribuído aqui. Após preparar e manter os downloads/dependências locais, o teste usa apenas 127.0.0.1 e não depende de serviço público.

```powershell
git clone https://github.com/regyssilveira/blockchain-na-pratica-com-delphi-exemplos.git
Set-Location blockchain-na-pratica-com-delphi-exemplos
git checkout prototype-p04-2026-10-16
.\scripts\Test-Anvil.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

Informe o caminho real do Delphi 13, sem depender do compilador encontrado no PATH. Se a política local bloquear scripts, pode-se executar o arquivo em um processo separado com `powershell -ExecutionPolicy Bypass -File .\scripts\Test-Anvil.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'`, sem alterar a política permanente. Outra porta livre pode ser indicada por `-Port 18546`.

## Versão fixada e isolamento

Prepare-Anvil.ps1 baixa foundry_v1.8.5_win32_amd64.zip da release oficial v1.8.5, commit 51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f. SHA-256 do ZIP: `21f86b563d87404a68481f513bf3e419780ee536307b89c658215ae6f8f5aa45`. O pacote tem 119.196.334 bytes. A cada preparo, o script verifica o arquivo e reextrai o executável a partir dele, confere o commit informado e registra o hash do executável em build/tools/anvil/manifest.json. Um arquivo incompleto ou divergente causa interrupção; remova somente esse ZIP e repita o preparo para baixá-lo novamente.

Somente anvil.exe é executado. Os demais executáveis contidos no pacote ficam ignorados em build/tools/anvil. O código principal do Foundry tem licença MIT OU Apache-2.0; o pacote oficial não é redistribuído neste repositório. O inventário anterior de dependências transitivas não equivale a revisão completa de redistribuição do binário.

Configuração efetiva: host 127.0.0.1, porta 18545, chain ID 31337, hardfork Cancun, zero contas geradas, saldo inicial de 100 ETH para o endereço derivado da chave de teste do EIP-155, taxa base inicial de 1.000.000.000 wei e mineração automática desativada. A chave privada é deliberadamente conhecida, formada por 32 bytes 0x46; não usar para fundos reais.

O roteiro verifica a disponibilidade da porta e aborta se ocupada. Inicia uma instância nova, aguarda a porta e encerra somente o processo que criou em finally, inclusive se a compilação ou teste falhar. Não se conecta a uma rede já existente. Logs, compilação, resultados e evidências ficam em build/Anvil. Não instala serviços nem altera PATH.

## Critérios conferidos

1. Rede 31337, bloco inicial zero, nonce zero, remetente derivado da chave igual a 0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f e saldo inicial exato.
2. Transferência de 1 ETH para 0x3535353535353535353535353535353535353535, gás limite 21.000, prioridade 1 gwei, teto 3 gwei e access list vazia. Gwei equivale a um bilhão de wei; os cálculos usam inteiros, sem ponto flutuante.
3. Hash calculado no Delphi igual ao retornado por eth_sendRawTransaction: `0xb43b69af2a0bbf14177224c3ca72e266f5cb8a3c1b0d2db4d8b9138bd6424459`.
4. Antes de evm_mine, recibo nulo, nonce latest zero e pending um: aceitação não é inclusão em bloco.
5. Após mineração explícita, recibo com status 0x1, bloco um, remetente/destinatário corretos e consumo de 21.000 unidades de gás. Consulta da transação confirma tipo 2, chain ID e nonce.
6. Saldo do destinatário igual ao valor transferido; saldo final do remetente igual ao inicial menos valor e gasUsed × effectiveGasPrice, usando inteiros exatos.
7. Rede incorreta, saldo insuficiente e nonce consumido geram erros JSON-RPC reais com motivos específicos. Falha HTTP, erro de transporte ou JSON malformado não contam como rejeição válida. As consultas de nonce/bloco verificam que as rejeições não avançaram o estado esperado.

## Evidências e limites

summary.json preserva a contagem DUnitX; acceptance.json preserva envelope, hash, erros, consulta e recibo reais; anvil-manifest.json registra a ferramenta. Resultados completos são gerados em build/Anvil/results.xml, compile.log e tests.log. Timestamps e hash do bloco podem variar entre execuções; o hash da transação é determinístico para estes campos.

A execução valida transferência simples com assinatura Delphi e aceitação por este nó local. Não valida contrato de registro, implantação Solidity, transações revertidas de contrato, reorganização, finalidade de rede pública, concorrência ou segurança de custódia. A implantação contratual prevista no roteiro amplo P04 permanece pendente; este recorte atende à aceitação solicitada pelo autor. A auditoria editorial de fontes é uma verificação estática adicional e não substitui esses testes executados.

## Fontes operacionais

- [Release fixada do Foundry](https://github.com/foundry-rs/foundry/releases/tag/v1.8.5) e ajuda local de `anvil --help` dessa versão.
- [API JSON-RPC do Ethereum](https://ethereum.org/developers/docs/apis/json-rpc/), especialmente eth_sendRawTransaction, eth_getTransactionReceipt e eth_getTransactionCount.
- [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559), envelope tipo 2 e cobrança do gás.
