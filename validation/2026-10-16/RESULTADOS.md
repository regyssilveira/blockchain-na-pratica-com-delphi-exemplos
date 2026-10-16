# Validação local das suítes em 16 de outubro de 2026

Registro histórico da primeira execução. A falha regional descrita abaixo foi posteriormente investigada e resolvida; consultar [a validação da correção](../2026-10-16-locale-fix/RESULTADOS.md). Os números originais foram preservados.

Ambiente: Windows 11 Pro x86-64, Delphi 13, dcc64 build 37.0.57242.3601. As revisões de dependências estão em `dependencies.lock.json`. Todos os executáveis foram compilados em Win64, sem pacotes de execução de terceiros, com fontes locais e definições CONSOLE_TESTRUNNER e CI.

| Suíte original | Compilação | Execução observada |
|---|---|---|
| SimpleBaseLib4Pascal | Aprovada | 240 testes aprovados |
| HashLib4Pascal | Aprovada | 1.967 testes aprovados, 5,847 segundos no relógio da suíte |
| CryptoLib4Pascal | Aprovada | 1.607 testes aprovados, 123,905 segundos no relógio da suíte |
| DUnitX | Aprovada com Delphi-Mocks e correção de importação | 373 encontrados; 363 aprovados, 9 ignorados, 1 falha, zero erros e zero vazamentos reportados |

As três primeiras suítes exibiram `OK: N tests`. A execução DUnitX retornou código 1 e resultado XML Failure. As contagens do XML não são idênticas ao total encontrado no console: `total=364` representa os executados, com `ignored=9`. Não somar o total do console com o total XML.

## Ressalva que impede aprovação integral

Falhou `DUnitX.Tests.Loggers.XML.NUnit.TDUnitX_LoggerXMLNUnitTests.OnTestingEnds_Writes_The_Assembly_Time_As_A_Duration`:

```text
Expected [0,000] but got [0.000]
```

O teste original compara o atributo XML com `Format('%.3f', ...)`, sujeito à configuração regional. O logger produziu ponto decimal e a expectativa do teste usou vírgula. Essa diferença foi observada nesta máquina; não foi alterado o teste, a configuração regional global ou o logger para obter aprovação. O roteiro mantém o sinal de falha. Diagnóstico completo e eventual correção do teste por formato invariável são pendentes, antes de declarar a combinação inteiramente aprovada.

Não foram executados testes de ABI Ethereum, transação tipo 2, assinatura aceita por nó, contrato ou rede blockchain. As aprovações acima validam somente as suítes exercitadas neste ambiente.

## Ajustes reproduzíveis do ambiente

- Os carregadores de HashLib4Pascal e CryptoLib4Pascal procuram vetores a partir do diretório corrente. Executar a partir da raiz do checkout correspondente. A tentativa inicial de HashLib fora dessa raiz encerrou com runtime error 217 antes dos testes; a execução correta passou integralmente.
- A suíte DUnitX exige Delphi-Mocks 0.2.2, além das quatro dependências selecionadas inicialmente. A licença principal Apache 2.0 foi conferida no checkout. Essa dependência pertence somente à suíte do executor.
- Delphi-Mocks repete a importação de Generics.Defaults na implementação depois de importar System.Generics.Defaults na interface. O preparo remove apenas a segunda declaração, sem alterar funções, asserções ou testes. A revisão base continua fixada, e a modificação é explicitamente conferida pelo script.
- Os caminhos de includes do DUnitX devem conter Source e Tests; a primeira tentativa sem eles não encontrou DUnitX.MemoryLeaks.inc.
- O script de execução foi exercitado com SimpleBaseLib4Pascal e confirmou código zero e 240 testes aprovados. As outras três execuções registradas nesta data usaram diretamente os executáveis, com os mesmos diretórios de trabalho e parâmetros documentados.

Os logs brutos ficam em `build/` e não são enviados ao Git. O processo de reprodução gera compile.log, compiler-arguments.txt, tests.log e, no DUnitX, results.xml. O executor não considera código zero do DUnit suficiente: também exige o resumo `OK`. Não há certificação de segurança ou medição de requisitos mínimos de hardware.
