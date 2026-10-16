# Validação do exemplo do capítulo 6

Executado em 16/10/2026, Windows PowerShell 5.1, Delphi 13 build 37.0.57242.3601, Win64. Comando: scripts/Test-Chapter06.ps1 com DelphiRoot apontando a instalação. Fontes das bibliotecas e implementação criptográfica preservadas; novo console somente compõe chamadas existentes.

Resultado: 76 testes offline aprovados, zero erros/falhas/ignorados; cinco resultados de assinatura conferidos, mais duas falhas operacionais esperadas com saída 1. Os 76 incluem os 44 testes básicos e 32 de protocolo; não somar como 76 novos testes de assinatura. Referências independentes permanecem em fixtures/p03 e fixtures/didactic.

| Caso | Entrada | Expectativa observada |
|---|---|---|
| Original | SHA-256 do arquivo A, assinatura de A e pública correspondente | True |
| Mensagem alterada | SHA-256 de B, assinatura de A e mesma pública | False |
| Outra chave | Resumo de A, assinatura de A e pública da chave de teste 1 | False |
| Assinatura de outra mensagem | Resumo de A e assinatura de B com mesma pública | False |
| Alterada assinada novamente | Resumo de B, assinatura de B e mesma pública | True |
| Argumentos ausentes | Console sem caminhos | Erro e saída 1 |
| Arquivo ausente | Caminho confirmado inexistente | Erro e saída 1 |

A e B são fixtures/p02/document-a.txt e document-b.txt; chave principal pública de laboratório, 46 repetido 32 vezes. Todos os cálculos ocorrem no executável Delphi. Não há nó, rede blockchain ou ponte criptográfica externa. True/False não significam certificado autêntico/falso: os casos verificam a combinação dos parâmetros. O programa não persiste assinaturas nem gerencia chaves reais. Avaliação de segurança de produção não faz parte desta comprovação.

Evidências: results.xml/summary.json (suíte), acceptance.json/experiment.txt (console), stderr dos casos negativos e hashes das fontes normalizados para LF. O roteiro do leitor está em chapters/chapter06/README.md. A adição de um switch ao helper de compilação foi exercitada na seleção Protocol e no novo console; os demais percursos não foram reexecutados nesta etapa de redação.

Conferências adicionais: execução do console com caminhos de entrada contendo espaços preservou os cinco resultados; duas entradas idênticas produziram True nos casos que dependiam de alteração e False para a chave diferente. Saídas em paths-with-spaces.txt e identical-inputs.txt.
