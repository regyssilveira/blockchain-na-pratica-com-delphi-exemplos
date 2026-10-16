# Correção da expectativa regional de duração no DUnitX

Validação de 16/10/2026 em Delphi 13 Win64, build 37.0.57242.3601. A revisão upstream permanece `fbad5c969cc0b89ae433a014d551a36684f370e1`, acrescida do patch explícito `patches/DUnitX-nunit-duration-locale.patch`. O resultado anterior, incluindo sua falha, foi preservado em `validation/2026-10-16/`.

## Causa e contrato verificado

O construtor de `TDUnitXXMLNUnitLogger` configura `FFormatSettings.DecimalSeparator := '.'`. O atributo `time` do elemento Assembly usa esse formato local ao logger, com três casas decimais. A expectativa antiga do teste usava `SysUtils.Format` sem informar formato, herdando a vírgula decimal do ambiente. A comparação confrontava duas convenções diferentes.

O ponto decimal coincide com o [escritor oficial NUnit2XmlOutputWriter na revisão consultada](https://github.com/nunit/nunit/blob/6a23694a8ce4ae8705014b2f82a525084342365f/src/NUnitFramework/nunitlite/OutputWriters/NUnit2XmlOutputWriter.cs), que usa `NumberFormatInfo.InvariantInfo` ao escrever a duração, e com o [exemplo oficial NUnit 2](https://nunit.org/files/testresult_25.txt). Essas referências corroboram o contrato já explícito no logger Delphi. Não se concluiu apenas da sintaxe XML que todo atributo time exige ponto: o schema NUnit 2 consultado o declara como string.

A falha era uma expectativa regional indevida do teste, não um defeito demonstrado no logger. Alterar o logger para produzir vírgula ou substituir texto no XML esconderia o problema e violaria o comportamento de interoperabilidade pretendido.

## Correção e ampliação

O teste continua comparando o atributo emitido pelo logger com a duração esperada em segundos, com três casas. Agora fornece configurações explícitas de formatação e verifica os valores literais `0.000` e `1.234`, evitando que o resultado esperado seja apenas uma reprodução cega da implementação.

A duração recebida pelo logger é controlada por um duplo de IRunResults. Assim, 1.234 milissegundos de entrada são conferidos como 1,234 segundo de duração, representado no XML por `1.234`; não se usa espera real para obter uma fração de segundo. Os resultados de fixtures do cenário original continuam sendo usados.

| Cenário | Separador regional durante o teste | Entrada em milissegundos | Atributo esperado |
|---|---|---:|---|
| CommaZero | vírgula | 0 | `0.000` |
| CommaFraction | vírgula | 1234 | `1.234` |
| PointZero | ponto | 0 | `0.000` |
| PointFraction | ponto | 1234 | `1.234` |

O teste preserva TFormatSettings antes de cada cenário, verifica que o logger não troca o separador regional e restaura o estado em `finally`. Isso exercita os separadores no processo Delphi; não equivale a testar todas as configurações de localidades completas. A execução usada é sequencial, conforme o executor upstream desta preparação. Não altera o Windows.

## Verificações executadas

1. O patch foi removido da cópia de trabalho e reaplicado pelo preparo sobre a revisão upstream intacta. O preparo conferiu que o diff final corresponde exatamente ao patch versionado.
2. A suíte completa compilou e executou com a correção: **376 encontrados, 367 aprovados, 9 ignorados, zero falhas e zero erros**, código de saída zero. O aumento de três no total vem da substituição de um teste por quatro cenários; os nove ignorados já existiam.
3. Foi compilada uma mutação temporária do logger, trocando seu separador explícito de ponto para vírgula. Os quatro cenários falharam com expectativas `0.000`/`1.234` e saídas `0,000`/`1,234`. Não houve erro de preparação ou compilação contado como detecção de defeito.
4. O logger foi restaurado byte a byte, sua integridade conferida e a suíte recompilada. O resultado voltou a 367 aprovados, 9 ignorados, zero falhas/erros e código zero.

O comando reproduzível é `scripts/Test-DUnitXLocaleRegression.ps1 -DelphiRoot <raiz-do-Delphi-13>`. Ele exige que os quatro casos falhem na mutação e que a suíte restaurada passe. A mutação não é parte do patch permanente. O script de preparo também foi repetido sobre o estado já corrigido para conferir idempotência.

Logs e XML de execução e de mutação ficam em `build/DUnitX/`. Os resumos e os quatro casos extraídos foram preservados ao lado deste relatório. As três bibliotecas criptográficas não mudaram: permanecem válidos os resultados anteriores de 240, 1.967 e 1.607 testes aprovados, sem alegação de nova execução delas nesta correção.

A ressalva regional de P01 está resolvida para esta combinação e este ambiente. Os nove casos ignorados continuam não executados. A integração blockchain ainda depende de implementação e de seus próprios testes.
