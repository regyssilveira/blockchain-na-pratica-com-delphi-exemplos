# P04 concluído — implantação e registro de documentos

Validação executada em 16/10/2026, Windows x86-64 e Delphi 13, compilador dcc64 37.0.57242.3601. **78 testes aprovados**, zero ignorados, falhas ou erros: 76 regressões P02/P03, o cenário de transferência P04 e um novo cenário integrado de contrato com múltiplas asserções. O console de demonstração também foi compilado e executado com sucesso, separadamente da contagem DUnitX.

## O que este exemplo faz

Um contrato é um programa executado pelo nó. O DocumentRegistry guarda, para cada par conta e hash do documento, o número do bloco do primeiro registro. O contrato obtém a conta de `msg.sender`, o remetente reconhecido pela assinatura. Outra conta pode registrar o mesmo hash; uma repetição pela mesma conta reverte, isto é, desfaz as alterações dessa execução. Uma transação revertida ainda consome nonce, o contador de transações da conta, e paga gás pela execução.

O arquivo fica na máquina do leitor. Delphi calcula seu SHA-256 e envia somente os 32 bytes do hash. O contrato não recebe nome, caminho ou conteúdo do arquivo. O registro não comprova identidade civil, autoria ou veracidade do documento; o bloco não é um carimbo de tempo confiável.

A interface binária da aplicação (ABI) especifica a representação das chamadas, retornos e eventos. O cliente Delphi implementa apenas os tipos estáticos usados neste contrato. Delphi também monta e assina as transações tipo 2, envia os bytes por JSON-RPC, o protocolo de chamadas remotas em JSON, confere o código implantado e consulta o registro. A compilação Solidity usa solc; o nó local usa Anvil. São as duas exceções externas. PowerShell prepara e orquestra; não assina, implanta ou chama o contrato.

## Reproduzir do início

Requisitos: Windows x86-64, Git, Delphi 13 com compilador Win64 instalado/licenciado e Windows PowerShell 5.1 ou PowerShell 7. O primeiro preparo precisa de internet para downloads oficiais e dependências fixadas. Node.js, Python, Docker, Rust, Forge, Cast, carteira e provedor público não são necessários.

```powershell
git clone https://github.com/regyssilveira/blockchain-na-pratica-com-delphi-exemplos.git
Set-Location blockchain-na-pratica-com-delphi-exemplos
git checkout prototype-p04-complete-2026-10-16
.\scripts\Test-Anvil.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O roteiro usa document-a.txt como entrada padrão. Para testar um arquivo próprio:

```powershell
.\scripts\Test-Anvil.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0' -DocumentPath 'C:\Documentos\meu documento.pdf' -Port 18546
```

O caminho deve existir na máquina do leitor. Informe o diretório real do Delphi 13; o roteiro não usa o compilador do PATH. Se a política local impedir scripts, execute em processo separado: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Anvil.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'`. Isso não altera a política permanente.

O roteiro verifica o arquivo de entrada, prepara ferramentas, compila o contrato, inicia rede nova em 127.0.0.1, executa os 78 testes, compila o console e o executa com o arquivo escolhido. Encerra somente o nó criado, em `finally`, inclusive se houver falha. Cada execução começa com uma rede nova e registros vazios; o console implanta sua própria instância. O teste integrado usa snapshot e restaura o estado ao terminar, para não depender da ordem das suítes. A rede não é preservada quando o processo encerra; os recibos são preservados em arquivos.

Depois do primeiro preparo, mantendo dependências e downloads locais, não é necessário acesso a serviço externo para executar. Os testes não enviam documentos ou transações para rede pública. O console não substitui uma carteira de produção: usa chave de teste publicamente conhecida, taxas e limites fixos para este laboratório, mineração explícita e uma rede de uso exclusivo.

## Compilação fixada e artefatos

Build-Contract.ps1 baixa e verifica `solc-windows-amd64-v0.8.37+commit.f401782d.exe`. SHA-256: `967743b2d12155f59a0ddf9410afe25c7deaa73f4fe3d33c4dc0739f627d9ec9`. O compilador é executado por `--standard-json`, com EVM Cancun, otimizador habilitado, 200 execuções estimadas, `metadata.bytecodeHash=none` e `metadata.appendCBOR=false`. A versão EVM é a versão-alvo da Máquina Virtual Ethereum; fixá-la evita emitir instruções de uma versão mais recente que o nó configurado.

A fonte e os campos de `contracts/build.lock.json` são fixados no Git. O script verifica tanto o código de saída quanto erros com severidade `error` no JSON do compilador. A compilação precisa coincidir com o manifesto em versão, checksum do compilador, opções e hashes. Os campos creationHexSha256 e runtimeHexSha256 são SHA-256 do **texto hexadecimal ASCII, sem 0x e sem quebra de linha**, e não dos bytes decodificados. A fonte Solidity é mantida em LF por `.gitattributes` para preservar seu checksum entre checkouts Windows.

Saídas em `build/contract`: entrada e saída completas do compilador e DocumentRegistry.json com manifesto, ABI, bytecode de criação e bytecode de execução. O primeiro cria o contrato; o segundo é o programa que fica no nó. O Delphi compara integralmente o bytecode de execução esperado com `eth_getCode`, após a implantação e antes das interações. Não há bibliotecas Solidity vinculadas, proxies ou campos imutáveis que exijam substituição de bytes.

Anvil permanece em 1.8.5, commit 51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f, com o checksum documentado na etapa anterior. Configuração: rede 31337, Cancun, loopback, nenhuma conta gerada, duas contas de teste financiadas com 100 ETH cada, mineração automática desativada e taxa base inicial de 1 gwei. Um gwei equivale a um bilhão de wei. A chave A contém 32 bytes 0x46; a chave B é o inteiro um em 32 bytes. Ambas são publicamente conhecidas e exclusivas do laboratório.

## Critérios executados

| Verificação | Resultado observado |
|---|---|
| Implantação Delphi | Transação tipo 2 assinada localmente; hash local igual ao retornado; recibo status 0x1, destino nulo e endereço do contrato presente |
| Código esperado | `eth_getCode` coincide byte a byte com o runtime produzido pelo compilador fixado |
| Registro do arquivo A | SHA-256 calculado pelo Delphi, registro status 0x1, evento e consulta com conta, hash e bloco coerentes |
| Cópia e alteração | Cópia de A tem hash igual; B tem hash diferente e consulta explícita de ausência |
| Duplicidade | `eth_call` retorna erro customizado AlreadyRegistered com conta/hash; nova transação assinada com novo nonce é incluída com status 0x0, sem eventos e sem substituir o registro original |
| Separação por conta | B não encontra registro próprio antes; registra o mesmo hash com sucesso; registro de A conserva o bloco original |
| Chamada malformada | Somente o seletor, sem bytes32, é enviado diretamente; recibo status 0x0, sem eventos e sem criar registro |
| Validação local | Rede divergente, endereço sem código esperado, runtime diferente, hash curto e arquivo inexistente falham; nonce permanece inalterado |
| Antes de assinar | Rede divergente é rejeitada mesmo com chave inválida: a falha identifica a rede antes de tentar assinar |
| Estados | Antes da mineração, recibo nulo; após mineração manual, status do recibo decide sucesso ou reversão |

Os 77 testes anteriores continuam aprovados, inclusive saldos com custo efetivo do gás e rejeições por rede incorreta, saldo insuficiente e nonce consumido. Os testes novos não removem a verificação de duplicidade para obter aprovação.

## Resultado do console e evidências

Com document-a.txt, o SHA-256 observado foi `adf835a3a021fc814fbb13f2cb4e544a18dabd8e608a0013f6eb450318713bf2`. Na execução registrada, o contrato foi `0x20bb3edd03cdb25b85f5e7e5f107c801869cc3ae`, com registro confirmado no bloco 3. Não copie esse endereço para uma rede em execução diferente: o console deriva o endereço do recibo de sua própria implantação. Um arquivo diferente produz outro hash e outra transação de registro. Timestamps e hashes de blocos podem variar.

O diretório desta validação preserva summary.json, contract-acceptance.json, demo.json e o artefato compilado. Arquivos gerados localmente: `build/Anvil/results.xml`, tests.log, acceptance.json da transferência, contract-acceptance.json, demo.log e demo.json; compilação do console em `build/DocumentRegistry.Demo/compile.log`. O snapshot de módulos carregados em demo.json contém o executável Delphi e bibliotecas do Windows, incluindo transporte HTTP. A presença de DLLs do sistema não é delegação da assinatura; o cliente não inicia processos de assinatura, e as bibliotecas Pascal são compiladas no executável.

Reprodução completa conferida também em Windows PowerShell 5.1.26100.9711. Processos rápidos exigiram preservar o handle antes de aguardar e ler ExitCode; a correção mantém a validação de saída em vez de ignorá-la. Os downloads usam parsing básico, sem depender do Internet Explorer.

P04 está concluído como preparação da rede, compilação, implantação assinada e conferência do contrato. O exemplo também executa o registro e as regras essenciais. Não certifica custódia de produção, concorrência, reorganizações, finalidade de rede pública nem todas as falhas de comunicação previstas para etapas posteriores. Não há identidade civil associada às contas de teste.

## Licenças e fontes

Fontes originais Delphi, Solidity e scripts: Apache-2.0. Anvil e solc são obtidos separadamente, não há executáveis dessas ferramentas distribuídos no Git. O solc possui licença GPL versão 3 no repositório oficial; o código principal Foundry declara MIT OU Apache-2.0. Mantêm-se os avisos das bibliotecas Pascal em THIRD_PARTY_NOTICES.md. Isso não declara auditoria exaustiva dos componentes dos binários externos.

- [Solidity: interface do compilador e alvo EVM](https://docs.soliditylang.org/en/v0.8.37/using-the-compiler.html).
- [Solidity: ABI, eventos e erros](https://docs.soliditylang.org/en/v0.8.37/abi-spec.html).
- [Licença do Solidity na versão fixada](https://github.com/argotorg/solidity/blob/v0.8.37/LICENSE.txt).
- [Binários oficiais solc](https://binaries.soliditylang.org/windows-amd64/list.json).
- [API JSON-RPC Ethereum](https://ethereum.org/developers/docs/apis/json-rpc/).
