# Fechamento durante trabalho: inspeção visual executada

Em 17/10/2026 foi executado o último caso visual com o mesmo binário corrigido da tag chapter18-examples-2026-10-17-r1/d11cfd1, sem alteração em fonte, tempo de espera ou teste. O caso de acompanhamento era curto para o ciclo de observação/ação da ferramenta. Foi usado o cálculo local de SHA-256 de uma entrada fictícia de 3 GiB, que passa pelo mesmo trabalhador e pelo mesmo QueryClose da janela.

Com Calcular hash desabilitado e trabalho em andamento, Alt+F4 não encerrou a janela. A captura mostrou: “Aguarde esta operação terminar para fechar. O acompanhamento será preservado.” A janela continuou processando eventos: contadores 102 e 287 observados. Aos 32 segundos da observação inicial, a consulta de estado já encontrou hashed e controles liberados; esse instante não é medida exata do tempo de processamento. Outra captura mostrou hash local e nenhum registro enviado. Novo Alt+F4 após a conclusão encerrou normalmente a instância, cuja ausência foi confirmada por list_windows.

As capturas foram vistas diretamente no Computer Use; as árvores de acessibilidade de trabalho/conclusão são preservadas no repositório privado do livro. Como os rótulos estáticos não aparecem nessa árvore, a confirmação da mensagem vem da inspeção da captura, não da extração de texto. O manifesto distingue essa observação visual da cobertura automatizada de fechamento durante acompanhamento pendente. Não foi feita aferição da escala numérica nem avaliação em várias escalas. O caso não equivale à revisão humana final do livro.

## Repetição opcional do diagnóstico

Não é necessário repetir uma entrada grande em cada execução. Para reproduzir esse caso, tenha mais de 8 GiB livres e crie um arquivo fictício novo, em uma pasta de teste, usando Windows PowerShell:

```powershell
$inputPath = Join-Path (Get-Location) 'hash-lento-ficticio.bin'
$stream = [IO.File]::Open($inputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
try { $stream.SetLength(3GB) } finally { $stream.Dispose() }
```

Abra a versão corrigida da aplicação. Selecione somente esse arquivo, clique em Calcular hash e tente fechar enquanto os botões estiverem desabilitados. Confira a mensagem de espera e a permanência da janela. Após hashed, feche novamente. Remova apenas a entrada que acabou de criar. A velocidade depende da máquina; se o cálculo acabar antes da tentativa de fechamento, o caso não foi observado.

O executável realiza leitura e hash em Delphi nativo. PowerShell prepara somente a entrada; nenhum servidor lento ou dependência adicional foi necessário. A entrada desta execução foi removida após fechar a janela, com caminho e tamanho conferidos. Não foi distribuída nem adicionada ao Git. Fontes, tag e PDF foram preservados.
