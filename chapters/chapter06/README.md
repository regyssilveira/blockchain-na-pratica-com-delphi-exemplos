# Assinar e verificar arquivos em Delphi

Exemplo do capítulo 6. `demos/Chapter06.Signatures.dpr` reutiliza as funções já validadas de `Blockchain.Ethereum` e `Blockchain.Primitives`; não implementa matemática criptográfica nova. Calcula SHA-256 dos bytes de dois arquivos e usa ECDSA secp256k1 para assinar e verificar o resumo de 32 bytes. O formato da assinatura é o registro TEthereumSignature do laboratório. Não é uma transação nem o formato de assinatura de mensagens de uma carteira Ethereum.

## Repetir

Requisitos: Windows x64, Delphi 13 Win64 instalado/licenciado, PowerShell 5.1 ou 7 e Git. O preparo inicial obtém as fontes fixadas de dependencies.lock.json. Não requer nó, Anvil, solc, carteira, Node.js ou Python. Código original Apache-2.0; dependências mantêm suas licenças em THIRD_PARTY_NOTICES.md.

```powershell
git checkout chapter06-examples-r1-2026-10-16
.\scripts\Test-Chapter06.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O roteiro executa 76 testes offline (44 básicos + 32 de protocolo, não exclusivos de assinatura), compila o console e exige os cinco resultados abaixo. Também verifica saída 1 quando faltam argumentos ou um arquivo não existe. Uma expiração de prazo é falha/incompleto, nunca aprovação. Relatórios locais em build/Protocol e build/Chapter06.Signatures.

```text
original=True
mensagem_alterada=False
outra_chave=False
assinatura_de_outra_mensagem=False
alterada_assinada_novamente=True
```

Para executar apenas o programa já compilado, a partir da raiz:

```powershell
.\build\Chapter06.Signatures\Chapter06.Signatures.exe '.\fixtures\p02\document-a.txt' '.\fixtures\p02\document-b.txt'
```

São as frases fictícias Certificado de exemplo 001 e 002, sem quebra final. Aceita dois caminhos próprios. Se os arquivos tiverem os mesmos bytes, os casos que dependem de conteúdo alterado também poderão retornar True. O processo do experimento termina com zero ao concluir as comparações; False é esperado em três casos, não uma falha de execução.

## Chaves e limites

A chave principal é `46` repetido 32 vezes, já publicada no vetor EIP-155 dos testes P03; a chave alternativa é o inteiro 1 em 32 bytes. Ambas são conhecidas e não protegem nada real. O programa não aceita chave secreta do leitor, não gera chaves para uso real e não publica documentos numa rede. O segredo nunca deve ser substituído por uma chave real no fonte.

Uma assinatura válida relaciona conteúdo e chave pública, não comprova por si só identidade civil, veracidade, autorização da aplicação ou custódia segura. Nova assinatura pode ser produzida para o arquivo alterado por quem conhece a privada. A verificação trabalha com o resumo calculado dos arquivos, sem normalizar texto ou assinar a apresentação hexadecimal.

As bibliotecas e vetores independentes permanecem nas revisões anteriores; consulte fixtures/p03/PROVENIENCIA.md e fixtures/didactic/PROVENIENCIA.md. [Resultados desta composição](../../validation/2026-10-16-chapter06/RESULTADOS.md).
