# Validação do capítulo 14

16/10/2026. Windows PowerShell 5.1, Delphi 13 Win64 37.0.57242.3601. Inspeção nativa aprovada na configuração fixada: chainId 31337, altura zero, nenhuma conta administrada pelo nó e 100 ether em wei no endereço financiado. Apenas consultas; sem contrato, solc ou envio de transação.

Dois erros operacionais esperados: argumentos ausentes e falha de transporte com a instância real encerrada. Script exige saída 1 e diagnóstico correspondente. Hash do bloco pode variar entre instâncias. Não é validação de consenso, segurança de produção ou repetição dos 108 testes da integração completa.

76 testes de regressão offline reexecutados e aprovados, zero erros, falhas ou ignorados, para conferir também a seleção Protocol do helper compartilhado. Não são novos testes de ambiente. Nenhum algoritmo ou cliente foi modificado.

A primeira execução do novo script encontrou incompatibilidade do Start-Process do PowerShell 5.1 com ArgumentList vazio. Corrigida a orquestração para omitir o parâmetro quando não há argumentos; programa e expectativa de erro preservados. A versão final foi reexecutada, incluindo diagnóstico de transporte, com aprovação.
