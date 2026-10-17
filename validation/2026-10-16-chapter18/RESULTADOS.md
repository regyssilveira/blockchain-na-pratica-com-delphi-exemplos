# Validação funcional da aplicação do capítulo 18

16/10/2026. Windows PowerShell 5.1, Delphi 13 Win64 37.0.57242.3601, Anvil 1.8.5 e solc 0.8.37 fixados. Executado Test-Chapter18 sem SkipPrototype, portas 19345 e 19346. Fontes identificados no manifesto.

Aprovados 108 testes próprios anteriores, 13 operações do protótipo e erro posterior com nó real encerrado. Adicionalmente: 28 condições do fluxo da aplicação, três condições de retomada em outro processo e quatro condições com o nó da aplicação encerrado. Não são 143 novos testes DUnitX. Autoteste VCL: processamento de timer durante espera, fechamento adiado, controles desabilitados, apresentação na thread principal, trabalhador liberado e hash original preservado. As consultas posteriores não aumentaram a contagem de envios da conta.

Arquivo idêntico/cópia com espaços encontrados; arquivo alterado ausente; consulta não modifica acompanhamento; tentativa duplicada é outra transação e reverte, mantendo o primeiro registro. Arquivo ausente, tipo de acompanhamento incorreto, configuração divergente e JSON corrompido recusados sem converter erro em sucesso.

O orçamento do teste de nó parado é de oito segundos para observar a falha de transporte local antes do prazo global. Na investigação inicial, 300 ms esgotavam antes da recusa TCP; essa condição produz unknown por prazo, não rejeição de negócio. A exigência final de erro explícito do cliente, estado desconhecido e hash preservado foi mantida.

Não há avaliação humana de usabilidade, conferência visual aprovada, teste de diálogos por leitor ou validação de rede pública. Capturas investigativas não produziram imagem válida e não são apresentadas como prova de interface. O autoteste atual cria a janela oculta e verifica seu ciclo de eventos e trabalho. A conferência visual/manual permanece pendente. Reproduza pelo roteiro em chapters/chapter18/README.md; nenhum binário ou segredo real é publicado.
