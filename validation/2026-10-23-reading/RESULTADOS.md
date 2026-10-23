# Validação da revisão de leitura — 23/10/2026

Execuções locais em Windows x64, Delphi 13 Win64 37.0.57242.3601. Dependências, Anvil 1.8.5 e solc 0.8.37 preservados nas revisões fixadas. As rotinas de assinatura, codificação, comunicação e aplicação continuam Delphi nativas.

| Roteiro | Resultado observado |
|---|---|
| Test-ReadingRevision.ps1 | 114 testes, mapa de bytes, vínculo e tempo isolados, três buscas, rastreamento e arquivo alterado/ausente aprovados |
| Test-Didactic.ps1, base 19811 | 114 testes, N01–N14 e ciclo de vida aprovados; altura 7, trabalho 1792, três arquivos válidos |
| Test-Chapter15.ps1, porta 20045 | Cliente mínimo retorna cadeia 31337; argumentos ausentes e nó encerrado são erros esperados |
| Test-Chapter19.ps1, porta 19945 | 94 testes offline; 108 regressões do protótipo; fluxo da janela, retomada, nó parado e perda de recibo aprovados |

Os grupos se sobrepõem. Os cenários não são novos testes DUnitX e não devem ser somados como cobertura uniforme de segurança. A repetição final de Test-ReadingRevision foi feita com Windows PowerShell 5.1. Os JSONs conservam observações e diretórios da execução; os arquivos DPAPI, checkpoints e executáveis não são publicados. O rastreamento conserva apenas uma transação offline com chave publicada e destino ilustrativo, identificada como não enviada.

Reprodução: selecione `reading-revision-2026-10-23`, leia os READMEs de chapters/part03, chapter15 e chapter17 e execute os mesmos scripts com sua raiz Delphi. O primeiro preparo usa internet; as operações da rede ficam em loopback. Não é necessário Python, Node.js, Docker, carteira ou provedor público para os exemplos. `source-sha256.json` registra os fontes que foram exercitados. As tags antigas continuam disponíveis.

Esta validação não afirma custódia de produção, independência física entre organizações, finalidade pública ou segurança contra todos os participantes hostis. A inspeção manual histórica dos diálogos permanece distinta do autoteste de janela reexecutado aqui; esta revisão não alterou o formulário.

## Reprodução em outra cópia

Uma clonagem Git independente em `build/reproducao leitura 2026-10-23`, com caminho contendo espaços, repetiu o preparo inicial do capítulo 4 e selecionou a tag do capítulo 5 na mesma cópia. Os 44 testes passaram; original e cópia produziram o mesmo hash, arquivo alterado produziu outro e arquivo inexistente foi recusado com saída 1. As dependências Git foram obtidas novamente, sem copiar a pasta de dependências do checkout principal.

Depois de selecionar o commit de código `b4b02de`, os 114 testes e os experimentos revisados passaram em Windows PowerShell 5.1. O cliente mínimo consultou a cadeia 31337 e recusou argumentos ausentes e nó parado. A primeira tentativa de preparo RPC foi interrompida durante o preparo demorado; a repetição usou o arquivo de distribuição Anvil do cache conferido por SHA-256 e terminou aprovada. Portanto, essa repetição comprova compilação e execução em outra cópia, mas não é apresentada como nova validação integral do download do Anvil do zero. O manifesto e a reextração do arquivo fixado continuam sendo conferidos pelo script.

`source-sha256.json` conserva bytes do checkout original; diferenças de BOM e fim de linha podem alterar esses hashes. `source-normalized-sha256.json` remove BOM e normaliza fins de linha para comparar o conteúdo textual, que coincidiu entre os dois checkouts. A evidência posterior de reprodução acrescenta somente documentos e resumos ao commit exercitado; os fontes executáveis são os mesmos.
