# Blockchain na Prática com Delphi

Exemplos e laboratório local do livro de Régys Borges da Silveira, subtítulo *Entenda os conceitos, descubra onde usar e implemente passo a passo*.

O projeto editorial é separado e privado. Este repositório público contém o protótipo de integração concluído: contrato de documentos, cliente Delphi nativo, acompanhamento persistido e testes locais. A versão técnica de referência é `prototype-accepted-2026-10-16`.

## Blockchain própria em Delphi

A Parte 3 também possui implementação e validação próprias: blocos, assinaturas, prova de trabalho, persistência e nós Delphi. Referência `didactic-chain-accepted-2026-10-16`; não usa Anvil nem solc.

```powershell
.\scripts\Test-Didactic.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

São 114 testes (incluindo os 76 offline anteriores), 14 cenários com processos reais e verificação de encerramento dos filhos do supervisor. Consulte o [percurso dos capítulos 8–13](chapters/part03/README.md), com comandos manuais e limites, e os [resultados](validation/2026-10-16-didactic/RESULTADOS.md). O roteiro de integração abaixo permanece separado.

## Assinaturas do capítulo 6

O [exemplo de arquivos assinados](chapters/chapter06/README.md) usa as funções Delphi já validadas para observar assinatura correta, mensagem alterada, chave diferente, assinatura trocada e nova assinatura. Versão `chapter06-examples-r1-2026-10-16`.

```powershell
.\scripts\Test-Chapter06.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

São 76 testes offline existentes e cinco experimentos nativos, sem iniciar nó. As chaves são conhecidas e exclusivas do laboratório. Consulte os [resultados executados](validation/2026-10-16-chapter06/RESULTADOS.md).

## Transações e estado do capítulo 7

O [console de transações](chapters/chapter07/README.md) exercita as regras existentes de formato, assinatura, sequência e duplicidade, sem construir blocos ou iniciar nós. Referência `chapter07-examples-2026-10-16`.

```powershell
.\scripts\Test-Chapter07.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

Executa 114 testes existentes da base didática e 14 verificações no console, com três erros operacionais esperados. Consulte os [resultados e limites](validation/2026-10-16-chapter07/RESULTADOS.md).

## Requisitos

- Windows x86-64 e Delphi 13 com compilador Win64, bibliotecas padrão e DUnit. Referência observada: build 37.0.57242.3601. O leitor deve ter uma licença Delphi adequada à sua utilização.
- PowerShell e Git para obter as revisões de fontes.
- Internet para obter os fontes. A preparação e os testes desta etapa não usam conta GitHub, provedor blockchain, carteira ou dinheiro real.

Não são necessários componentes visuais instalados na IDE, OpenSSL externo, Docker, Node.js ou Python. Assinatura e interação são Delphi nativo. Anvil 1.8.5 e solc 0.8.37 são as ferramentas externas para nó e compilação do contrato, obtidas pelo roteiro com checksum. As suítes offline de bytes/protocolo podem ser executadas sem essas ferramentas.

## Repetir localmente

Clone em uma pasta de sua escolha:

```powershell
git clone https://github.com/regyssilveira/blockchain-na-pratica-com-delphi-exemplos.git
cd blockchain-na-pratica-com-delphi-exemplos
```

Para reproduzir o protótipo completo:

```powershell
git checkout prototype-accepted-2026-10-16
.\scripts\Test-Prototype.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

A suíte própria tem **108 testes aprovados**, sem ignorados, falhas ou erros. O roteiro também executa o console, retoma acompanhamento/consulta em processos novos e verifica a falha depois de encerrar o nó real. Aceita `-DocumentPath` e `-Port`. Consulte o [roteiro completo e a matriz V01–V12](validation/2026-10-16-prototype/RESULTADOS.md), incluindo os comandos Delphi separados para explorar cada conceito localmente.

## Suítes de terceiros e histórico

Execute em PowerShell. Se a política local bloquear scripts, revise os arquivos e use uma sessão com autorização adequada às regras de sua máquina; o roteiro não altera a política global.

```powershell
.\scripts\Prepare-Dependencies.ps1
.\scripts\Build-UpstreamSuites.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
.\scripts\Run-UpstreamSuites.ps1
```

Adapte somente a raiz Delphi. O script rejeita compiladores de outra geração; não confia em dcc64 encontrado no PATH. Todas as dependências são obtidas nos commits completos de `dependencies.lock.json`; o preparo interrompe se encontrar alterações inesperadas. Ele não sobrescreve checkouts existentes de outra revisão.

Para uma única suíte, acrescente `-Suite SimpleBaseLib4Pascal`, `-Suite HashLib4Pascal`, `-Suite CryptoLib4Pascal` ou `-Suite DUnitX` ao build e à execução. O prazo padrão da execução é de 30 minutos por suíte, ajustável por `-TimeoutMinutes`. Uma expiração é resultado incompleto, nunca aprovação.

Os scripts mantêm fontes em `dependencies/` e compilados/logs em `build/`, ambos ignorados pelo Git. Arquivos da instalação Delphi não são copiados ou publicados. O compilador recebe `--no-config`, caminhos explícitos, `CONSOLE_TESTRUNNER` e `CI`, e produz executáveis Win64. Os logs incluem os argumentos efetivos. As suítes DUnit são executadas a partir da raiz da respectiva biblioteca, pois seus carregadores descobrem os vetores pelo diretório corrente. A suíte DUnitX gera XML e não aguarda Enter.

## Dependências e correção de compatibilidade

CryptoLib4Pascal usa HashLib4Pascal e SimpleBaseLib4Pascal. As suítes dessas bibliotecas usam DUnit incluído no Delphi. A suíte do DUnitX também requer Delphi-Mocks 0.2.2, fixado por commit e utilizado somente nos testes do próprio executor. O submódulo DUnitXML do Delphi-Mocks não é necessário para esse uso e não é obtido.

O preparo aplica uma única correção documentada a `Delphi-Mocks/Source/Delphi.Mocks.pas`: remove `Generics.Defaults` da lista uses da implementação, pois a interface já importa `System.Generics.Defaults`. Essa duplicidade impede a compilação no Delphi 13. O script compara o conteúdo com a revisão original e aceita apenas a transformação especificada; nenhuma regra de teste é alterada.

O preparo também aplica `patches/DUnitX-nunit-duration-locale.patch` ao teste de duração XML do DUnitX. O logger original já usa ponto decimal; a expectativa do teste foi corrigida para o mesmo contrato e ampliada para quatro cenários, com separadores regionais ponto/vírgula e durações 0/1.234 segundos. A configuração é restaurada ao sair do teste. Nenhum teste foi desabilitado e o logger de produção não foi alterado. Detalhes e comprovação de detecção de uma mutação estão em [validação da correção regional](validation/2026-10-16-locale-fix/RESULTADOS.md).

Não habilitar integrações opcionais do DUnitX com ferramentas comerciais de diagnóstico. Os fontes e testes criptográficos permanecem na revisão original. A suíte DUnitX agora passa com 367 testes aprovados e os mesmos 9 ignorados existentes na base. Consultar os resultados observados em `validation/`; não confundir aprovação das suítes com validação da integração blockchain.

Para repetir a verificação de regressão, incluindo uma mutação temporária que deve ser rejeitada:

```powershell
.\scripts\Test-DUnitXLocaleRegression.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O script restaura o logger em `finally`, recompila e repete a suíte correta. A falha durante a mutação é esperada; o comando só aprova se os quatro casos a detectarem e a execução restaurada passar. Não muda as configurações regionais do Windows nem precisa de conexão com uma rede blockchain.

## Hashes, bytes e precisão numérica

A etapa P02 contém os primeiros componentes do protótipo em `src/Blockchain.Primitives.pas` e 44 casos de teste nativos em `tests/`. Eles verificam os bytes dos arquivos, SHA-256 contra referências independentes e representação exata de valores até 2^256−1, sem ponto flutuante monetário. As entradas e suas referências estão em `fixtures/p02/`.

```powershell
.\scripts\Test-Primitives.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O leitor pode executar somente esse comando após clonar o repositório e preparar o Delphi; as dependências são obtidas ou conferidas pelo script. Todos os cálculos e asserções ocorrem no executável Delphi local. Não são necessários Anvil, solc ou conta de blockchain nesta etapa. Consulte [resultados e limites de P02](validation/2026-10-16-p02/RESULTADOS.md). A aprovação numérica não significa que assinatura e transações já estejam validadas.

## Keccak, ABI, RLP e assinatura de transações

A etapa P03 acrescenta `src/Blockchain.Ethereum.pas`: palavras ABI estáticas, RLP, assinatura secp256k1, recuperação de remetente e montagem de transações tipo 2 com lista de acesso vazia. A execução combinada tem 76 testes aprovados, incluindo a regressão de P02. São testes offline contra vetores fixos independentes; ainda não demonstram aceitação por um nó.

```powershell
.\scripts\Test-Protocol.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O comando prepara as mesmas dependências e compila um executável Delphi nativo. Não requer carteira, rede Ethereum, Node.js ou Python. Consulte [resultados e limites P03](validation/2026-10-16-p03/RESULTADOS.md) e a [procedência dos vetores](fixtures/p03/PROVENIENCIA.md). Os dados de chave do exemplo são deliberadamente públicos e exclusivos do teste.

## Histórico P04: contrato de documentos e console Delphi

Na tag `prototype-p04-complete-2026-10-16`, o roteiro compila o contrato com solc 0.8.37 fixado, prepara Anvil 1.8.5 local, executa **78 testes**, compila o console Delphi e registra um arquivo. Delphi calcula SHA-256, assina a implantação e o registro, envia as transações, confere o código implantado e consulta o resultado. Somente nó e compilador Solidity são externos.

```powershell
.\scripts\Test-Anvil.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

A entrada padrão é document-a.txt. Para um arquivo próprio, acrescente `-DocumentPath 'C:\Documentos\meu documento.pdf'`; se necessário, use `-Port 18546`. Somente o hash é enviado ao contrato. O roteiro cria uma rede nova e encerra o nó ao terminar, preservando recibos e consultas em build/Anvil.

Use a tag `prototype-p04-complete-2026-10-16` e siga o [roteiro completo, critérios e limites](validation/2026-10-16-p04-contract/RESULTADOS.md). O [recorte anterior de transferência](validation/2026-10-16-p04/RESULTADOS.md) permanece como histórico. Requisitos: Windows x86-64, Git, PowerShell 5.1 ou 7 e Delphi 13 instalado/licenciado. O primeiro preparo precisa de internet; a execução usa uma rede exclusivamente local. As chaves são publicamente conhecidas e exclusivas do teste.

## Licença do material

O código original e os scripts deste repositório usam Apache License 2.0, em `LICENSE`. As dependências mantêm suas próprias licenças e avisos, descritos em `THIRD_PARTY_NOTICES.md`. Elas são baixadas de suas origens e não são incorporadas ao histórico deste repositório.

## Ambiente do capítulo 14

A inspeção Delphi de rede, bloco e saldo está em [chapters/chapter14](chapters/chapter14/README.md), tag `chapter14-examples-2026-10-16`. O roteiro `scripts/Test-Chapter14.ps1` inicia um Anvil novo, faz consultas e encerra sua própria instância; não exige contrato ou solc.
