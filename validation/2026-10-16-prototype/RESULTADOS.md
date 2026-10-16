# Protótipo de integração concluído

**108 testes próprios aprovados**, sem ignorados, falhas ou erros: 78 regressões e 30 cenários novos. Também passaram o console e 13 comandos em processos independentes, executados em Windows PowerShell 5.1.26100.9711.

P05 a P08 completam o percurso de arquivo, assinatura, registro e consulta no Anvil local. O cliente, o acompanhamento persistido e os testes são Delphi 13 Win64. Anvil fornece o nó e solc compila o contrato Solidity. O objetivo é fornecer uma base executada para a redação técnica do livro; não é uma aplicação de custódia ou uma rede de produção.

## Reprodução automática

Requisitos: Windows x86-64, Delphi 13 com compilador Win64 instalado/licenciado, Git e Windows PowerShell 5.1 ou PowerShell 7. O primeiro preparo obtém dependências e ferramentas das origens fixadas; depois disso os testes usam somente a máquina local. Não exige Node.js, Python, Rust, Docker, carteira, Forge, Cast ou serviço público de rede.

```powershell
git clone https://github.com/regyssilveira/blockchain-na-pratica-com-delphi-exemplos.git
Set-Location blockchain-na-pratica-com-delphi-exemplos
git checkout prototype-accepted-2026-10-16
.\scripts\Test-Prototype.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

Informe o diretório real do Delphi 13. Para outra porta livre, acrescente `-Port 18546`. Para outro arquivo, acrescente `-DocumentPath 'C:\Documentos\meu documento.pdf'`. Os casos fixos da suíte continuam usando fixtures/p02; o console e o fluxo entre processos usam o arquivo escolhido. Os experimentos adicionais de cópia e alteração do console são executados quando a entrada corresponde ao documento A padrão.

Se a política local impedir scripts, execute em processo separado: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Prototype.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'`. Não é necessária mudança permanente na política ou no PATH.

O roteiro verifica versões e checksums, compila o contrato, inicia uma rede nova em loopback, executa a suíte, o console e os comandos de clientes independentes. Encerra a instância criada e executa uma consulta adicional para verificar a falha com esse nó real parado. Os resultados ficam em build/Anvil. Uma nova execução usa uma nova rede e outra pasta de checkpoints, sem depender do estado anterior nem apagar suas evidências.

## Registro e acompanhamento

O hash SHA-256 identifica o conteúdo do arquivo. O identificador da transação é outro hash, Keccak-256 do envelope assinado. O cliente preserva o envelope e esse identificador antes de tentar enviá-lo. Uma resposta perdida não comprova rejeição: o nó pode ter recebido a transação. Nesse caso, a retomada consulta o identificador original, sem criar outra assinatura ou reenviar automaticamente.

O checkpoint é um arquivo JSON que preserva porta local, rede, contrato esperado, conta, hash do documento, envelope assinado, identificador e estado observado. Não contém chave privada. A gravação substitui o arquivo por movimento atômico no Windows, a partir de um temporário próprio. Uma falha ao gravar o checkpoint inicial impede o envio. Um checkpoint existente não pode ser sobrescrito para iniciar outra transação; deve-se retomar a consulta ou escolher outro arquivo para uma nova operação.

O carregamento verifica estrutura, versão, porta, valores e correspondência entre hash e envelope. Isso detecta as corrupções exercitadas; não torna o arquivo autenticado contra alguém que possa substituir todo o conteúdo. A configuração retomada também precisa coincidir com a rede e o artefato compilado locais. Assinatura, nonce e regras do contrato não são substituídos por confiança nesse arquivo.

| Estado | Significado |
|---|---|
| prepared | Envelope assinado preservado, antes da tentativa de envio |
| unknown | Envio pode ter ocorrido, ou uma consulta falhou; preservar o hash e investigar |
| submitted | Nó aceitou os bytes; inclusão ainda não confirmada |
| pending | Recibo ausente durante a consulta; pode-se retomar pelo mesmo hash |
| rejected | Resposta de erro do nó ao envio; diferente de recibo revertido |
| succeeded | Recibo incluído com status 0x1; no registro, evento também conferido |
| reverted | Recibo incluído com status 0x0; execução desfeita e gás consumido |

Um prazo de acompanhamento esgotado não significa rejeição. O padrão é 30 segundos, consultando a cada segundo. O relógio monotônico controla o prazo total e o tempo restante é aplicado à chamada HTTP em andamento, com cancelamento por uma thread Delphi. Conexão, envio e resposta também possuem limites próprios. O teste de 30 segundos admite até dois segundos de tolerância de agendamento; o experimento HTTP curto usa 300 ms e tolerância maior para variação do sistema. Os tempos reais estão nos arquivos p07-*.json.

A retomada verifica versão e identificador JSON-RPC, exclusividade de result/error, estrutura do erro e estrutura do recibo. Para registros com checkpoint, confere remetente, destinatário, contrato do evento, tópicos de conta/hash e bloco do evento contra o recibo. Um objeto incompleto com status 0x1 não basta para declarar sucesso. Respostas de transporte, HTTP e protocolo não são classificadas como rejeição de negócio.

## Comandos Delphi para explorar o fluxo

DocumentRegistry.Cli.exe possui operações separadas para permitir encerrar e reiniciar o cliente. Primeiro prepare ferramentas e compile:

```powershell
.\scripts\Prepare-Anvil.ps1
.\scripts\Build-Contract.ps1
.\scripts\Test-Primitives.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0' -BuildCli
```

Em outro terminal, mantenha o nó local aberto:

```powershell
.\build\tools\anvil\anvil.exe --host 127.0.0.1 --port 18545 --chain-id 31337 --hardfork cancun --accounts 0 --fund-accounts 0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f:100 0x7e5f4552091a69125d5dfcb7b8c2659029395bdf:100 --block-base-fee-per-gas 1000000000 --no-mining
```

Na raiz do checkout, execute os comandos abaixo. Cada chamada abre e encerra um processo Delphi; o nó continua vivo no outro terminal:

```powershell
$client = '.\build\DocumentRegistry.Cli\DocumentRegistry.Cli.exe'
$session = 'build\manual-' + [guid]::NewGuid().ToString('N')
$deployment = $session + '\deployment.json'
$registration = $session + '\registration.json'
& $client deploy $deployment 18545
& $client wait $deployment 1000
& $client mine 18545
& $client wait $deployment 2000
& $client register $deployment 'fixtures\p02\document-a.txt' $registration
& $client wait $registration 1000
& $client mine 18545
& $client wait $registration 2000
& $client query $registration
& $client verify $registration 'fixtures\p02\document-a-copy.txt'
& $client verify $registration 'fixtures\p02\document-b.txt'
```

`wait` antes de minerar termina com código 2: resultado ainda não confirmado. `verify` do documento alterado termina com código 4: não encontrado para aquela conta e hash, e não uma afirmação de ausência global. Código 0 significa operação concluída, código 1 erro explícito e código 3 recibo revertido. Um script que use esses comandos deve tratar os códigos esperados, como faz Run-PrototypeStages.ps1. O comando `hash <arquivo>` permite calcular somente SHA-256, sem nó.

Os recibos são preservados ao lado do checkpoint com sufixo .receipt.json; a consulta usa .query.json. O console de demonstração anterior também permanece disponível. Depois de encerrar o nó com Ctrl+C, uma consulta deve falhar explicitamente. Uma rede nova não contém o contrato antigo: repita a implantação com checkpoints novos, sem reaproveitar silenciosamente o endereço anterior.

## Reprodução independente concluída

Um checkout Git independente do commit e301cb9cd77f4927bb771c11f4885e8d729f1286, sem cache prévio de ferramentas ou dependências e em pasta com espaços, repetiu 108 testes e os 13 comandos, em rede nova na porta 18546. Os hashes de todas as fontes testadas coincidem com o manifesto da versão de referência. O hash do registro também coincidiu entre as duas redes limpas. clean-reproduction.json e clean-results.xml preservam a comprovação. A versão aceita acrescenta a consolidação documental sobre essas mesmas fontes.

## Evidências e alcance

summary.json e results.xml registram os testes Delphi. acceptance-matrix.json relaciona V01 a V12 às entradas, expectativas, resultados e evidências. prototype-processes.json registra cada processo de implantação, acompanhamento e consulta; as duas consultas após reiniciar o cliente conservam o nonce, sem envio adicional. stopped-node.json registra a falha depois de encerrar a instância real.

P05/P06 usam Anvil real: registro e consulta, cópia, alteração, evento, contas independentes, duplicidade com novo nonce e chamada truncada. P07 produz pendência real com mineração pausada. Também usa um servidor HTTP escrito em Delphi para respostas malformadas, erro HTTP e resposta demorada: são simulações de comunicação, identificadas como tais. O caso de perda de resposta descarta deliberadamente uma resposta já recebida após aceitação real pelo Anvil; não é uma falha espontânea de rede.

Os binários do nó e do compilador não são redistribuídos. As revisões Pascal, seus avisos e patches explícitos não mudaram desde P04. As suítes de terceiros continuam com as evidências anteriores: SimpleBase 240 aprovados, HashLib 1967, CryptoLib 1607; DUnitX 367 aprovados e nove ignorados, que não integram a cobertura alegada. A suíte própria atual não usa testes ignorados. A lista de módulos do console distingue bibliotecas normais do Windows das bibliotecas Pascal compiladas no executável.

O protótipo de integração está encerrado no limite definido em P00–P08. Blockchain didática própria, interface gráfica, rede pública, reorganizações, concorrência e custódia de produção continuam fora deste experimento. Sua exclusão não retira os assuntos planejados do livro nem os declara implementados.

Fontes operacionais: [JSON-RPC 2.0](https://www.jsonrpc.org/specification), [API JSON-RPC Ethereum](https://ethereum.org/developers/docs/apis/json-rpc/), [ABI Solidity 0.8.37](https://docs.soliditylang.org/en/v0.8.37/abi-spec.html), código RTL da instalação Delphi identificada nos manifestos e versões/checksums previamente registrados. A matriz e os testes sustentam os resultados observados; a documentação de protocolo sustenta o formato esperado.
