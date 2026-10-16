# Validação da blockchain didática

Execução em 16/10/2026, Delphi 13 build 37.0.57242.3601, Win64, Windows PowerShell 5.1. Comando: `scripts/Test-Didactic.ps1 -DelphiRoot` seguido da raiz instalada do Delphi. O [roteiro do leitor](../../chapters/part03/README.md) explica execução completa e manual.

Resultado: **114 testes aprovados**, zero erros, falhas e ignorados; **14 cenários nativos aprovados**. Os 114 incluem os 76 testes offline P02/P03 e 38 novos casos, não 114 novos casos exclusivos. Não são somados aos 108 testes da integração, que compartilham fixtures anteriores. `results.xml` e `summary.json` registram a suíte; `scenario.json` registra entradas e observações dos processos. `acceptance.json` identifica a execução de origem.

| Critério | Entrada e expectativa | Evidência executada |
|---|---|---|
| B08 | Mesmo conteúdo produz mesmos bytes/hash; alteração muda hash; bloco inicial fixo | Vetores independentes, testes de bloco e lesson-08.txt |
| B09 | Hash/referência incorretos são rejeitados; recalcular só o bloco antigo não basta | Testes completos e lesson-09.txt; demonstração parcial explicitada |
| B10 | Pendente não é registro incluído; salvar/carregar preserva estado; corrupção não reinicia cadeia | N02, N04, N07, N08, N13, N14; três snapshots finais |
| B11 | Prova limitada, dificuldade fixa, empate mantém história, mais trabalho exige validade integral | lesson-11.txt, N06, N09, N10, N11 e testes de cadeia inválida com prova recalculada |
| B12 | Nós reais propagam transações/blocos e sincronizam história ausente | N01–N04, N08, N12; reinício em topologia A–B–C |
| B13 | Assinatura inválida, repetição, interrupção, falha de gravação e bifurcação têm efeitos observáveis | N03, N05–N14 e lifecycle.json |

A partição de rede é uma injeção controlada via endpoint; a parada e o reinício de B são processos reais. A falha de gravação usa arquivo somente leitura. A corrupção é feita numa cópia com checksum externo recalculado, exigindo rejeição por validação interna. N13 exige saída 1 e preservação dos bytes. Nenhum teste altera a regra para aceitar o caso inválido.

Os três arquivos finais foram carregados e validados por processos CLI separados: altura 7, trabalho 1792 e hash `00300f1dbbb18703ca3d4428ccda1dbd7a22f0ab5da38433b967e83aaa34350a`. O cenário registra nove inicializações de processos e zero encerramentos forçados no percurso normal. A prova adicional lifecycle encerra deliberadamente o supervisor e confirma a saída do filho por Windows Job Object.

A regressão da integração Anvil executou novamente 108 testes e o percurso de clientes independentes com sucesso depois da alteração no helper de compilação. Não houve alteração nas versões/licenças das dependências. Código original Apache-2.0; fontes reutilizados mantêm os avisos de THIRD_PARTY_NOTICES.md.

Limites: modelo restrito a loopback e entradas pequenas, chaves públicas de laboratório, prova de trabalho fraca, nenhuma finalidade ou segurança de produção. Hash não comprova identidade civil ou autoria. Capítulos do livro continuam planejamento; esta entrega valida seus exemplos técnicos.
