# Validação do exemplo do capítulo 7

16/10/2026. Windows PowerShell 5.1, Delphi 13 build 37.0.57242.3601, Win64. Comando: scripts/Test-Chapter07.ps1, com DelphiRoot apontando a instalação. Código de composição novo, regras de domínio e criptografia existentes preservadas.

Resultado: 114 testes existentes aprovados, zero falhas/erros/ignorados. São 76 testes offline anteriores e 38 casos da base didática, não 114 testes novos de transações. A suíte inclui blocos e mineração em memória. Separadamente, o console executou 14 verificações de transação/estado, sem construir blocos, iniciar rede ou minerar. Não são os 14 cenários de processos de nós da Parte 3.

Os resultados de experiment.txt cobrem validação sem aplicação, primeiro registro, formato inválido, adulteração, reenvio, sequência reutilizada, salto, documento duplicado, outra rede, preservação dos valores observados após recusas, mesmo documento em outra conta, próxima sequência, reconstrução das consultas e rejeição de A/2 antes de A/1. Os casos válidos aplicados são A/1, B/1 e A/2. Rejeições esperadas capturam somente EDidacticValidation; falhas inesperadas continuam erros. Uma assinatura válida não suprime regra de negócio.

Três falhas operacionais esperadas: falta de argumentos, arquivo inexistente e entradas com hashes iguais, todas com saída 1. Caminhos de entrada com espaços também repetiram as 14 condições com aprovação. acceptance.json, results.xml e summary.json comprovam execução; os textos de stderr registram os casos negativos. As chaves privadas de teste são publicamente conhecidas (inteiros 1 e 2), não segredos do leitor.

Apply é exercitado diretamente em memória com metadado sintético BlockHeight=1. Isso não cria bloco ou comprova inclusão, persistência, consenso, identidade ou tempo. Histórico é um array local. Reconstrução compara as consultas exercitadas e sequências, não declara autenticidade ou origem confiável do histórico. A interface de envio da cadeia completa tem tratamento próprio para duplicatas; o componente de estado rejeita reaplicação.

Referência: chapter07-examples-2026-10-16. Roteiro em chapters/chapter07/README.md. Sem novas dependências ou alterações nas primitivas; helper de compilação acrescenta switch do console, exercitado com seleção Didactic e o novo programa. Outros percursos, como Anvil e processos de nós, não foram repetidos nesta etapa.
