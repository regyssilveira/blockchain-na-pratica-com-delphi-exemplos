# Capítulo 15 — cliente mínimo completo

Tag `reading-revision-2026-10-23`, fontes originais Apache License 2.0. Pré-requisitos e preparação: capítulo 4 e README da raiz. Use Windows x64, Delphi 13 Win64 instalado/licenciado, Git e Windows PowerShell 5.1. Dependências e Anvil são obtidos da internet no primeiro preparo; não requer provedor público, carteira ou fundos reais.

Na raiz dos exemplos:

```powershell
git fetch origin --tags
git checkout reading-revision-2026-10-23
.\scripts\Test-Chapter15.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0' -Port 20045
```

O roteiro compila `demos/Chapter15.Read.dpr`, inicia seu próprio Anvil, exige a resposta `{"chainId":"31337"}`, confere a ausência de argumento e encerra o nó. Depois exige falha de transporte ao consultar o nó parado. A porta deve estar livre; um serviço desconhecido não é encerrado. Resultados em `build/Chapter15.Read/acceptance.json`.

O programa entrega o array de parâmetros a `TLocalRpc.Call`, exige resultado textual, interpreta a quantidade com inteiro exato e libera o resultado em `finally`. A criação do cliente e sua liberação cercam esse percurso. Para examinar o envelope de requisição, correlação e erros, siga `src/Blockchain.LocalRpc.pas`; para executar os casos simulados de protocolo e o contrato real, use `scripts/Test-Prototype.ps1` como no livro. Este pequeno cliente não substitui as validações do transporte.
