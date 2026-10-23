# Capítulo 17 — rastreamento dos bytes

Referência: tag `reading-revision-2026-10-23`. Código original Apache License 2.0; dependências mantêm seus avisos. Windows x64, Delphi 13 Win64 instalado e licenciado, Windows PowerShell 5.1 e Git. O preparo inicial usa internet; o rastreamento funciona offline depois das dependências.

Se já executou o capítulo anterior, continue na mesma cópia e preserve alterações próprias. A revisão `chapter14-examples-2026-10-16`, usada nos capítulos 14 e 16, ainda não contém este novo exercício: selecione a revisão abaixo antes de tentar executá-lo.

Somente se ainda não possui a cópia, obtenha-a e entre na pasta:

```powershell
git clone https://github.com/regyssilveira/blockchain-na-pratica-com-delphi-exemplos.git
cd blockchain-na-pratica-com-delphi-exemplos
```

Na raiz da cópia existente ou recém-obtida:

```powershell
git fetch origin --tags
git checkout reading-revision-2026-10-23
.\scripts\Test-ReadingRevision.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
.\build\Chapter17.Trace\Chapter17.Trace.exe 'fixtures\p02\document-a.txt'
```

O script confere 114 testes existentes, os mapas de bytes, duas causas isoladas de rejeição de vínculo, a busca limitada e o rastreamento. Consulta o mesmo arquivo com SHA-256 do Windows como comparação independente e confere assinatura e recuperação da conta. Repete com outro documento e exige erro para caminho inexistente. Resultados novos em `build/ReadingRevision/latest.json`; referências em `validation/2026-10-23-reading`.

`documentBytes` são os bytes lidos. `documentHash` é o SHA-256 desses bytes. `callData` reúne seletor `e1fa8e84` e 32 bytes do hash: 36 bytes ao todo. `unsignedEnvelope` é a representação sem assinatura; `signingHash` é o Keccak-256 dessa representação. `signedEnvelope` incorpora a assinatura; `transactionHash` é o Keccak-256 do envelope final. `signatureVerified` deve ser verdadeiro e `sent` falso.

O destino terminado em `0001` é ilustrativo. Nenhuma transação é enviada, não existe recibo produzido por este console e ele não afirma existir contrato no destino. A chave privada 1 é publicada para testes. Não usar valores reais. O fluxo real de implantação, registro, consulta e recibo permanece em `DocumentRegistry.Cli` e nos capítulos 16–18.

## Montagem do bloco e causas isoladas

O capítulo 8 mostra o record e `CanonicalBytes` de `src/Didactic.Block.pas`. Os campos do cabeçalho começam nas posições 0 (formato), 20 (rede), 45 (altura), 53 (hash anterior), 85 (instante), 93 (dificuldade), 94 (nonce) e 102 (quantidade). Esses offsets valem para os textos da política padrão.

`link-demo` prepara B1 e B2 sem alterar a gênese e exige um controle positivo. Primeiro muda o instante de B1 de 1 para 2, conservando B2 em 20: exige `Broken block link.` com tempo crescente. Depois restaura B1, iguala o instante de B2 e recalcula o hash próprio: exige `Block timestamp must increase.` com referência e hash coerentes. Os candidatos demonstram validação parcial, sem alegar aprovação integral da cadeia.

Conferência da sequência em `validation/2026-10-23-sequence/RESULTADOS.md`. Execute os roteiros um de cada vez: o preparo compartilha a pasta de ferramentas em `build/tools`.
